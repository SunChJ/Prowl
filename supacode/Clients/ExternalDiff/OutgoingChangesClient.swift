import ComposableArchitecture
import Foundation

/// Re-resolves the outgoing comparison from scratch: pull request base →
/// configured worktree base → automatic default branch. The diff window runs
/// this on every outgoing refresh and on mode switches, so a pull request
/// created, retargeted, or closed while the window is open moves the base
/// visibly instead of pinning the value captured at open time.
typealias OutgoingComparisonResolver = @Sendable () async throws -> GitOutgoingChangesComparison

nonisolated struct OutgoingChangesClient: Sendable {
  var open:
    @MainActor @Sendable (
      _ worktree: Worktree,
      _ resolvedKeybindings: ResolvedKeybindingMap,
      _ onError: @escaping @MainActor @Sendable (OpenActionError) -> Void
    ) async -> Void
  var makeResolver: @MainActor @Sendable (_ worktree: Worktree) -> OutgoingComparisonResolver
}

extension OutgoingChangesClient {
  /// `pullRequestInfo` reads the currently cached pull request for a worktree;
  /// the app wires it to live store state so resolvers observe pull request
  /// changes that happen after the diff window was opened.
  static func live(
    pullRequestInfo: @escaping @MainActor @Sendable (Worktree.ID) -> GithubPullRequest?
  ) -> Self {
    let makeResolver: @MainActor @Sendable (Worktree) -> OutgoingComparisonResolver = { worktree in
      {
        let pullRequest = await pullRequestInfo(worktree.id)
        let pullRequestBase = pullRequest.map {
          GitPullRequestBase(url: $0.url, baseRefName: $0.baseRefName ?? "")
        }
        @Shared(.repositorySettings(worktree.repositoryRootURL)) var repositorySettings
        let gitClient = GitClient()
        let base = try await gitClient.outgoingBaseResolution(
          pullRequest: pullRequestBase,
          configuredBaseRef: repositorySettings.worktreeBaseRef,
          in: worktree.workingDirectory
        )
        return try await gitClient.outgoingChangesComparison(base: base, at: worktree.workingDirectory)
      }
    }
    return OutgoingChangesClient(
      open: { worktree, resolvedKeybindings, onError in
        let resolver = makeResolver(worktree)
        do {
          let comparison = try await resolver()
          @Shared(.settingsFile) var settingsFile
          DiffWindowManager.shared.show(
            worktreeURL: worktree.workingDirectory,
            branchName: worktree.name,
            comparison: .outgoing(comparison),
            outgoingResolver: resolver,
            resolvedKeybindings: resolvedKeybindings,
            colorScheme: settingsFile.global.appearanceMode.colorScheme
          )
        } catch {
          onError(
            OpenActionError(
              title: "Unable to show outgoing changes",
              message: error.localizedDescription
            )
          )
        }
      },
      makeResolver: makeResolver
    )
  }
}

extension OutgoingChangesClient: DependencyKey {
  static let liveValue = OutgoingChangesClient.live(pullRequestInfo: { _ in nil })

  static let testValue = OutgoingChangesClient(
    open: { _, _, _ in },
    makeResolver: { _ in { throw OutgoingBaseResolutionError.noResolvableBase } }
  )
}

extension DependencyValues {
  var outgoingChangesClient: OutgoingChangesClient {
    get { self[OutgoingChangesClient.self] }
    set { self[OutgoingChangesClient.self] = newValue }
  }
}
