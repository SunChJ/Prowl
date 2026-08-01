import Foundation
import Synchronization

nonisolated struct UntrackedLineFileFingerprint: Equatable, Sendable {
  let byteCount: Int
  let modificationDate: Date
  let resourceIdentifier: String?
}

nonisolated struct UntrackedLineCacheFile: Sendable {
  let relativePath: String
  let fingerprint: UntrackedLineFileFingerprint
}

nonisolated enum CachedUntrackedLineCount: Equatable, Sendable {
  case text(Int)
  case binary
}

nonisolated struct UntrackedLineCacheUpdate: Sendable {
  let relativePath: String
  let fingerprint: UntrackedLineFileFingerprint
  let value: CachedUntrackedLineCount
}

nonisolated final class UntrackedLineCountCache: Sendable {
  static let shared = UntrackedLineCountCache()

  private struct Entry {
    let fingerprint: UntrackedLineFileFingerprint
    let value: CachedUntrackedLineCount
  }

  private struct State {
    let maximumWorktreeCount: Int
    var entriesByWorktree: [String: [String: Entry]] = [:]
    var lastAccessByWorktree: [String: UInt64] = [:]
    var accessSequence: UInt64 = 0
  }

  private let state: Mutex<State>

  init(maximumWorktreeCount: Int = 128) {
    precondition(maximumWorktreeCount > 0)
    state = Mutex(State(maximumWorktreeCount: maximumWorktreeCount))
  }

  func cachedValues(
    for files: [UntrackedLineCacheFile],
    worktreeKey: String
  ) -> [String: CachedUntrackedLineCount] {
    state.withLock { state in
      guard !files.isEmpty else {
        state.entriesByWorktree.removeValue(forKey: worktreeKey)
        state.lastAccessByWorktree.removeValue(forKey: worktreeKey)
        return [:]
      }
      let currentPaths = Set(files.map(\.relativePath))
      var entries = state.entriesByWorktree[worktreeKey, default: [:]]
      entries = entries.filter { currentPaths.contains($0.key) }
      state.entriesByWorktree[worktreeKey] = entries
      touch(worktreeKey, state: &state)
      trimIfNeeded(state: &state)

      var result: [String: CachedUntrackedLineCount] = [:]
      for file in files {
        guard let entry = entries[file.relativePath], entry.fingerprint == file.fingerprint else {
          continue
        }
        result[file.relativePath] = entry.value
      }
      return result
    }
  }

  func store(
    _ updates: [UntrackedLineCacheUpdate],
    worktreeKey: String
  ) {
    guard !updates.isEmpty else { return }
    state.withLock { state in
      var entries = state.entriesByWorktree[worktreeKey, default: [:]]
      for update in updates {
        entries[update.relativePath] = Entry(
          fingerprint: update.fingerprint,
          value: update.value
        )
      }
      state.entriesByWorktree[worktreeKey] = entries
      touch(worktreeKey, state: &state)
      trimIfNeeded(state: &state)
    }
  }

  private func touch(_ worktreeKey: String, state: inout State) {
    state.accessSequence &+= 1
    state.lastAccessByWorktree[worktreeKey] = state.accessSequence
  }

  private func trimIfNeeded(state: inout State) {
    while state.entriesByWorktree.count > state.maximumWorktreeCount,
      let leastRecentlyUsed = state.lastAccessByWorktree.min(by: { $0.value < $1.value })?.key
    {
      state.entriesByWorktree.removeValue(forKey: leastRecentlyUsed)
      state.lastAccessByWorktree.removeValue(forKey: leastRecentlyUsed)
    }
  }
}
