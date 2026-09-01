import Foundation
import IdentifiedCollections

struct ActiveAgentWorktreeMetadata: Equatable {
  let repositoryNamesByWorktreeID: [Worktree.ID: String]
  let branchNamesByWorktreeID: [Worktree.ID: String]
  let repositoryColorsByWorktreeID: [Worktree.ID: RepositoryColorChoice]
}

struct ActiveAgentRowDisplay: Equatable {
  let repositoryName: String
  let branchName: String
  let color: RepositoryColorChoice?
  /// The directory the agent runs in (or its owning worktree's directory as a
  /// fallback); drives the context menu's Copy Path / Reveal in Finder.
  let directory: URL?
}

enum ActiveAgentRowDisplayResolver {
  static func worktreeMetadata(
    repositories: IdentifiedArrayOf<Repository>,
    customTitles: [Repository.ID: String],
    repositoryAppearances: [Repository.ID: RepositoryAppearance] = [:]
  ) -> ActiveAgentWorktreeMetadata {
    var repositoryNamesByWorktreeID: [Worktree.ID: String] = [:]
    var branchNamesByWorktreeID: [Worktree.ID: String] = [:]
    var repositoryColorsByWorktreeID: [Worktree.ID: RepositoryColorChoice] = [:]

    for repository in repositories {
      let repositoryName = customTitles[repository.id] ?? repository.name
      let repositoryColor = repositoryAppearances[repository.id]?.color
      if repository.capabilities.supportsRunnableFolderActions
        && !repository.capabilities.supportsWorktrees
      {
        repositoryNamesByWorktreeID[repository.id] = repositoryName
        branchNamesByWorktreeID[repository.id] = repository.name
        if let repositoryColor {
          repositoryColorsByWorktreeID[repository.id] = repositoryColor
        }
      }
      for worktree in repository.worktrees {
        repositoryNamesByWorktreeID[worktree.id] = repositoryName
        branchNamesByWorktreeID[worktree.id] = worktree.name
        if let repositoryColor {
          repositoryColorsByWorktreeID[worktree.id] = repositoryColor
        }
      }
    }

    return ActiveAgentWorktreeMetadata(
      repositoryNamesByWorktreeID: repositoryNamesByWorktreeID,
      branchNamesByWorktreeID: branchNamesByWorktreeID,
      repositoryColorsByWorktreeID: repositoryColorsByWorktreeID
    )
  }

  static func rowDisplays(
    entries: IdentifiedArrayOf<ActiveAgentEntry>,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata
  ) -> [ActiveAgentEntry.ID: ActiveAgentRowDisplay] {
    let resolvedWorktreeIDs = WorktreeDirectoryIndexCache.worktreeIDs(
      forWorkingDirectories: entries.compactMap(\.workingDirectory),
      in: repositories
    )
    var displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] = [:]
    for entry in entries {
      let resolvedWorktreeID = entry.workingDirectory.flatMap { resolvedWorktreeIDs[$0] }
      displays[entry.id] = rowDisplay(
        for: entry,
        repositories: repositories,
        metadata: metadata,
        resolvedWorktreeID: resolvedWorktreeID
      )
    }
    return displays
  }

  static func rowDisplay(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata,
    directoryIndex: WorktreeDirectoryIndex? = nil
  ) -> ActiveAgentRowDisplay {
    let resolvedWorktreeID = entry.workingDirectory.flatMap { workingDirectory in
      (directoryIndex ?? WorktreeDirectoryIndex(repositories: repositories))
        .worktreeID(forWorkingDirectory: workingDirectory)
    }
    return rowDisplay(
      for: entry,
      repositories: repositories,
      metadata: metadata,
      resolvedWorktreeID: resolvedWorktreeID
    )
  }

  static func rowDisplay(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata,
    resolvedWorktreeID: Worktree.ID?
  ) -> ActiveAgentRowDisplay {
    if let workingDirectory = entry.workingDirectory {
      if let key = resolvedWorktreeID {
        let fallbackName = workingDirectory.lastPathComponent
        return ActiveAgentRowDisplay(
          repositoryName: metadata.repositoryNamesByWorktreeID[key] ?? fallbackName,
          branchName: metadata.branchNamesByWorktreeID[key] ?? fallbackName,
          color: metadata.repositoryColorsByWorktreeID[key],
          directory: workingDirectory
        )
      }
      let name = Repository.name(for: workingDirectory)
      return ActiveAgentRowDisplay(
        repositoryName: name,
        branchName: name,
        color: nil,
        directory: workingDirectory
      )
    }
    return ActiveAgentRowDisplay(
      repositoryName: metadata.repositoryNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName,
      branchName: metadata.branchNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName,
      color: metadata.repositoryColorsByWorktreeID[entry.worktreeID],
      directory: directory(forWorktreeID: entry.worktreeID, in: repositories)
    )
  }

  static func resolveWorktreeID(
    forWorkingDirectory workingDirectory: URL,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Worktree.ID? {
    WorktreeDirectoryIndex(repositories: repositories)
      .worktreeID(forWorkingDirectory: workingDirectory)
  }

  static func directory(
    forWorktreeID worktreeID: Worktree.ID,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> URL? {
    for repository in repositories {
      if let worktree = repository.worktrees[id: worktreeID] {
        return worktree.workingDirectory
      }
    }
    guard let repository = repositories[id: worktreeID],
      repository.capabilities.supportsRunnableFolderActions
    else { return nil }
    return repository.rootURL
  }
}
