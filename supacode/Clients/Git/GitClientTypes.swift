import Foundation

enum GitOperation: String {
  case repoRoot = "repo_root"
  case worktreeList = "worktree_list"
  case worktreeCreate = "worktree_create"
  case worktreeRemove = "worktree_remove"
  case worktreePrune = "worktree_prune"
  case repoIsBare = "repo_is_bare"
  case branchNames = "branch_names"
  case branchNameValidation = "branch_name_validation"
  case branchRefs = "branch_refs"
  case defaultRemoteBranchRef = "default_remote_branch_ref"
  case localHeadRef = "local_head_ref"
  case ignoredFileCount = "ignored_file_count"
  case untrackedFileCount = "untracked_file_count"
  case branchRename = "branch_rename"
  case branchDelete = "branch_delete"
  case lineChanges = "line_changes"
  case diffNameStatus = "diff_name_status"
  case outgoingChangesComparison = "outgoing_changes_comparison"
  case outgoingDiffNameStatus = "outgoing_diff_name_status"
  case untrackedFilePaths = "untracked_file_paths"
  case showFile = "show_file"
  case remoteInfo = "remote_info"
  case remoteList = "remote_list"
  case fetchRemote = "fetch_remote"
  case remoteBranchRefs = "remote_branch_refs"
}

enum GitClientError: LocalizedError {
  case commandFailed(command: String, message: String)
  case worktreeNotRegistered(path: String)
  case worktreeRecoveryFailed(path: String, removalError: String, recoveryError: String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let command, let message):
      if message.isEmpty {
        return "Git command failed: \(command)"
      }
      return "Git command failed: \(command)\n\(message)"
    case .worktreeNotRegistered(let path):
      return "Git no longer recognizes this worktree: \(path)"
    case .worktreeRecoveryFailed(let path, let removalError, let recoveryError):
      return "\(removalError)\nUnable to restore the worktree directory at \(path): \(recoveryError)"
    }
  }
}

nonisolated struct GitWorktreeCreateRequest: Equatable, Sendable {
  struct CopyFiles: Equatable, Sendable {
    var ignored: Bool
    var untracked: Bool
  }

  var name: String
  var repoRoot: URL
  var baseDirectory: URL
  var copyFiles: CopyFiles
  var baseRef: String
  var directoryOverride: URL?

  init(
    name: String,
    repoRoot: URL,
    baseDirectory: URL,
    copyFiles: CopyFiles,
    baseRef: String,
    directoryOverride: URL? = nil
  ) {
    self.name = name
    self.repoRoot = repoRoot
    self.baseDirectory = baseDirectory
    self.copyFiles = copyFiles
    self.baseRef = baseRef
    self.directoryOverride = directoryOverride
  }
}

enum GitWorktreeCreateEvent: Equatable, Sendable {
  case outputLine(ShellStreamLine)
  case finished(Worktree)
}

enum LocalBranchDeletionOutcome: Equatable, Sendable {
  case deleted
  case notFound
  case protected
  case notRequested
}

nonisolated enum GitRemoteMatcher {
  static func matchingRemote(for ref: String, from remotes: [String]) -> String? {
    remotes
      .sorted { $0.count > $1.count }
      .first { ref.hasPrefix("\($0)/") }
  }
}

nonisolated enum GitBranchRefKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  case local
  case remoteTracking = "remote_tracking"
  case fetchedRemote = "fetched_remote"

  var title: String {
    switch self {
    case .local:
      return "Local Branches"
    case .remoteTracking:
      return "Remote Branches"
    case .fetchedRemote:
      return "Fetched Remote Branches"
    }
  }
}

nonisolated struct GitBranchRefOption: Codable, Equatable, Hashable, Sendable, Identifiable {
  var ref: String
  var kind: GitBranchRefKind

  var id: String {
    "\(kind.rawValue):\(ref)"
  }

  init(ref: String, kind: GitBranchRefKind) {
    self.ref = ref
    self.kind = kind
  }
}

nonisolated struct GitOutgoingChangesComparison: Equatable, Sendable {
  let baseRef: String
  let mergeBase: String
  let head: String
}

nonisolated struct GitRemoteBranchRefs: Equatable, Sendable {
  var options: [GitBranchRefOption]
  var defaultBaseRef: String?
}

nonisolated enum GitRemoteNaming {
  static func repositoryName(fromRemoteURL remoteURL: String) -> String {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmed.isEmpty else {
      return ""
    }
    let separatorIndex = trimmed.lastIndex { $0 == "/" || $0 == ":" }
    let component =
      separatorIndex.map { String(trimmed[trimmed.index(after: $0)...]) }
      ?? trimmed
    return component.hasSuffix(".git") ? String(component.dropLast(4)) : component
  }
}

struct GitWtWorktreeEntry: Decodable, Equatable {
  let branch: String
  let path: String
  let head: String
  let isBare: Bool

  enum CodingKeys: String, CodingKey {
    case branch
    case path
    case head
    case isBare = "is_bare"
  }
}
