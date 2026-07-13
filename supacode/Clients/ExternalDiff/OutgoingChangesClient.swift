import ComposableArchitecture
import Foundation

nonisolated struct OutgoingChangesClient: Sendable {
  var open:
    @MainActor @Sendable (
      _ worktree: Worktree,
      _ pullRequestURL: String,
      _ baseRefName: String,
      _ resolvedKeybindings: ResolvedKeybindingMap,
      _ onError: @escaping @MainActor @Sendable (OpenActionError) -> Void
    ) async -> Void
}

extension OutgoingChangesClient: DependencyKey {
  static let liveValue = OutgoingChangesClient { worktree, pullRequestURL, baseRefName, resolvedKeybindings, onError in
    let gitClient = GitClient()
    guard
      let baseRef = await gitClient.outgoingChangesBaseRef(
        pullRequestURL: pullRequestURL,
        baseRefName: baseRefName,
        in: worktree.workingDirectory
      )
    else {
      onError(
        OpenActionError(
          title: "Unable to show outgoing changes",
          message:
            "Prowl could not resolve the pull request base in a local remote. Fetch the target remote and try again."
        )
      )
      return
    }

    do {
      let revisions = try await gitClient.outgoingChangesComparison(from: baseRef, at: worktree.workingDirectory)
      @Shared(.settingsFile) var settingsFile
      DiffWindowManager.shared.show(
        worktreeURL: worktree.workingDirectory,
        branchName: worktree.name,
        comparison: .outgoing(revisions),
        resolvedKeybindings: resolvedKeybindings,
        colorScheme: settingsFile.global.appearanceMode.colorScheme
      )
    } catch {
      onError(
        OpenActionError(
          title: "Unable to show outgoing changes",
          message: [
            "Prowl could not compare this branch with \(baseRef).",
            "Fetch the base branch and try again.",
            error.localizedDescription,
          ].joined(separator: "\n\n")
        )
      )
    }
  }

  static let testValue = OutgoingChangesClient { _, _, _, _, _ in }
}

extension DependencyValues {
  var outgoingChangesClient: OutgoingChangesClient {
    get { self[OutgoingChangesClient.self] }
    set { self[OutgoingChangesClient.self] = newValue }
  }
}
