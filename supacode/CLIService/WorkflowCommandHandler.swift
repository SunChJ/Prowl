// supacode/CLIService/WorkflowCommandHandler.swift
// Handles `prowl workflow list`: resolves the worktree whose repo source is searched, runs
// three-source discovery, and applies the (hidden until D1) enabled set.

import Foundation

struct WorkflowRuntimeSnapshot {
  let resolution: TargetResolutionSnapshot
  let paneByShellPID: [pid_t: CallerPane]
  let bundleWorkflowsURL: URL?
  let userWorkflowsURL: URL
  /// `<scope>/<id>` keys of definitions the user switched off.
  let disabledWorkflowIDs: Set<String>
  let bundledSkillIDs: Set<String>?
  let knownAgents: Set<String>
  let installedAgents: Set<String>?
  /// Preset fields of the enabled Agent Profiles, for the `suggest` match warning.
  let enabledProfiles: [WorkflowProfileSuggestion]
}

@MainActor
final class WorkflowCommandHandler: CommandHandler {
  typealias SnapshotProvider = @MainActor () -> WorkflowRuntimeSnapshot

  private let snapshotProvider: SnapshotProvider

  init(snapshotProvider: @escaping SnapshotProvider) {
    self.snapshotProvider = snapshotProvider
  }

  static func disabledKey(scope: WorkflowScope, id: String) -> String {
    "\(scope.rawValue)/\(id)"
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    await handle(envelope: envelope, context: CLICommandContext())
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope, context: CLICommandContext) async -> CommandResponse {
    guard case .workflow(let input) = envelope.command else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Expected a workflow command.")
    }
    let snapshot = snapshotProvider()
    switch resolveWorktree(input.target, snapshot: snapshot, context: context) {
    case .failure(.notFound(let message)):
      return failure(code: CLIErrorCode.targetNotFound, message: message)
    case .failure(.notUnique(let message)):
      return failure(code: CLIErrorCode.targetNotUnique, message: message)
    case .success(let worktree):
      do {
        let payload = try listPayload(worktree: worktree, snapshot: snapshot)
        return try CommandResponse(
          ok: true,
          command: WorkflowCommandPayload.commandName,
          schemaVersion: WorkflowCommandPayload.schemaVersion,
          data: RawJSON(encoding: WorkflowCommandPayload.list(payload))
        )
      } catch {
        return failure(code: CLIErrorCode.workflowFailed, message: "Failed to list workflows: \(error)")
      }
    }
  }

  // MARK: - Worktree resolution

  /// `.none` prefers the caller's own pane, then the focused worktree; nil means no worktree
  /// could be resolved and only the bundle and user sources are searched.
  private func resolveWorktree(
    _ selector: TargetSelector,
    snapshot: WorkflowRuntimeSnapshot,
    context: CLICommandContext
  ) -> Result<TargetResolutionSnapshot.Worktree?, TargetResolverError> {
    let resolver = TargetResolver { snapshot.resolution }
    if case .none = selector {
      if let callerPane = callerPane(context: context, paneByShellPID: snapshot.paneByShellPID),
        let worktree = snapshot.resolution.worktrees.first(where: { $0.id == callerPane.worktreeID })
      {
        return .success(worktree)
      }
      guard case .success(let focused) = resolver.resolve(.none) else {
        return .success(nil)
      }
      return .success(snapshot.resolution.worktrees.first { $0.id == focused.worktreeID })
    }
    return resolver.resolve(selector).map { resolved in
      snapshot.resolution.worktrees.first { $0.id == resolved.worktreeID }
    }
  }

  private func callerPane(context: CLICommandContext, paneByShellPID: [pid_t: CallerPane]) -> CallerPane? {
    if !context.callerProcessAncestry.isEmpty {
      return CallerPaneResolver.pane(
        forCallerProcessAncestry: context.callerProcessAncestry, paneByShellPID: paneByShellPID)
    }
    guard let callerProcessID = context.callerProcessID else { return nil }
    return CallerPaneResolver.pane(forCallerProcess: callerProcessID, paneByShellPID: paneByShellPID)
  }

  // MARK: - Listing

  private func listPayload(
    worktree: TargetResolutionSnapshot.Worktree?, snapshot: WorkflowRuntimeSnapshot
  ) throws -> WorkflowListPayload {
    let repoURL = worktree.map {
      WorkflowSources.repoDirectory(root: URL(filePath: $0.rootPath, directoryHint: .isDirectory))
    }
    let sources = WorkflowSources(bundle: snapshot.bundleWorkflowsURL, user: snapshot.userWorkflowsURL, repo: repoURL)
    let catalog = try WorkflowDiscovery.catalog(sources: sources) { scope in
      WorkflowValidationContext(
        scope: scope,
        bundledSkillIDs: snapshot.bundledSkillIDs,
        knownAgents: snapshot.knownAgents,
        installedAgents: snapshot.installedAgents,
        enabledProfiles: snapshot.enabledProfiles
      )
    }
    let workflows = catalog.map { entry in
      let enabled =
        entry.file.id.map {
          !snapshot.disabledWorkflowIDs.contains(Self.disabledKey(scope: entry.file.scope, id: $0))
        } ?? false
      return WorkflowListEntry(entry: entry, enabled: enabled)
    }
    return WorkflowListPayload(
      worktree: worktree.map {
        WorkflowListWorktree(id: $0.id, name: $0.name, path: $0.path, rootPath: $0.rootPath)
      },
      sources: WorkflowListSources(
        bundle: sources.bundle?.path(percentEncoded: false),
        user: sources.user.path(percentEncoded: false),
        repo: sources.repo?.path(percentEncoded: false)
      ),
      workflows: workflows
    )
  }

  private func failure(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: WorkflowCommandPayload.commandName,
      schemaVersion: WorkflowCommandPayload.schemaVersion,
      error: CommandError(code: code, message: message)
    )
  }
}
