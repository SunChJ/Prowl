import Foundation
import IdentifiedCollections

/// Maps a directory an agent runs in to the deepest repository or worktree that contains it.
///
/// Normalizing a path to its canonical form touches the filesystem (a `stat` plus a symlink walk
/// per path component), so every candidate directory is normalized once when the index is built and
/// never again per lookup. A lookup then costs one normalization of the queried directory plus a
/// handful of dictionary probes, instead of re-scanning and re-normalizing every worktree.
nonisolated struct WorktreeDirectoryIndex: Equatable {
  /// Keyed by normalized path components joined back together, so a probe compares whole components
  /// rather than raw string prefixes — `/tmp/repo` must not match a sibling `/tmp/repo2`.
  private var idsByNormalizedPath: [String: Worktree.ID] = [:]
  private var deepestComponentCount = 0

  init() {}

  init(repositories: some Sequence<Repository>) {
    for repository in repositories {
      if repository.capabilities.supportsRunnableFolderActions,
        !repository.capabilities.supportsWorktrees
      {
        insert(id: repository.id, directory: repository.rootURL)
      }
      for worktree in repository.worktrees {
        insert(id: worktree.id, directory: worktree.workingDirectory)
      }
    }
  }

  private mutating func insert(id: Worktree.ID, directory: URL) {
    let components = PathPolicy.normalizeURL(directory).pathComponents
    let key = Self.key(for: components)
    // The first entry registered for a directory wins. This preserves the previous behavior when a
    // plain-folder repository root and its main worktree resolve to the same path.
    guard idsByNormalizedPath[key] == nil else { return }
    idsByNormalizedPath[key] = id
    deepestComponentCount = max(deepestComponentCount, components.count)
  }

  /// Finds the most specific indexed directory containing `workingDirectory`. The walk starts at the
  /// full path and shortens one component at a time, so the deepest match is the first hit.
  func worktreeID(forWorkingDirectory workingDirectory: URL) -> Worktree.ID? {
    guard !idsByNormalizedPath.isEmpty else { return nil }
    var components = PathPolicy.normalizeURL(workingDirectory).pathComponents
    // No indexed directory is deeper than this, so longer prefixes cannot match.
    if components.count > deepestComponentCount {
      components.removeLast(components.count - deepestComponentCount)
    }
    while !components.isEmpty {
      if let id = idsByNormalizedPath[Self.key(for: components)] {
        return id
      }
      components.removeLast()
    }
    return nil
  }

  private static func key(for components: [String]) -> String {
    components.joined(separator: "/")
  }
}

/// Memoizes the index across SwiftUI render passes.
///
/// `SidebarListView.body` re-runs on every agent output tick, and rebuilding the index each time
/// would put one filesystem round-trip per worktree back on the main thread. The index is a pure
/// function of the repository set, so a cached copy stays valid until that set changes.
@MainActor
enum WorktreeDirectoryIndexCache {
  private static var cachedSignature: [Entry] = []
  private static var cachedIndex = WorktreeDirectoryIndex()

  private struct Entry: Equatable {
    let id: Worktree.ID
    let directory: URL
  }

  static func index(for repositories: IdentifiedArrayOf<Repository>) -> WorktreeDirectoryIndex {
    let signature = signature(for: repositories)
    guard signature == cachedSignature else {
      cachedSignature = signature
      cachedIndex = WorktreeDirectoryIndex(repositories: repositories)
      return cachedIndex
    }
    return cachedIndex
  }

  /// The id/directory pairs the index is built from, in build order. Comparing these avoids
  /// rebuilding when an unrelated part of a repository changes (a branch rename, a color, an icon).
  private static func signature(for repositories: IdentifiedArrayOf<Repository>) -> [Entry] {
    var entries: [Entry] = []
    for repository in repositories {
      if repository.capabilities.supportsRunnableFolderActions,
        !repository.capabilities.supportsWorktrees
      {
        entries.append(Entry(id: repository.id, directory: repository.rootURL))
      }
      for worktree in repository.worktrees {
        entries.append(Entry(id: worktree.id, directory: worktree.workingDirectory))
      }
    }
    return entries
  }

  /// Drops the memo so a test starts from a known state.
  static func reset() {
    cachedSignature = []
    cachedIndex = WorktreeDirectoryIndex()
  }
}
