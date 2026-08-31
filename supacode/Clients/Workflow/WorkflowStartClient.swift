// supacode/Clients/Workflow/WorkflowStartClient.swift
// GUI-side access to workflow starts (docs-ai 063 C2). The live value is assembled in
// WorkflowRuntimeComposition from the same catalog, resolver, settings, and coordinator the
// CLI path uses — the GUI never grows its own run-creation logic (011 decision 1).

import ComposableArchitecture
import Foundation

struct WorkflowStartClient: Sendable {
  /// Workflows visible to a worktree, for the entry points. Includes validation-failing files
  /// (the capsule popover dims them); excludes definitions disabled in Settings entirely.
  var catalog: @MainActor @Sendable (_ worktreeID: String) -> [WorkflowStartCatalogItem]
  /// The sheet's raw material for one workflow, or nil when the workflow or worktree is gone.
  var context:
    @MainActor @Sendable (_ workflowKey: String, _ worktreeID: String, _ preferredSourceSurfaceID: UUID?)
      -> WorkflowStartContext?
  /// Submits through the coordinator — the same entry `prowl workflow run` uses.
  var run: @MainActor @Sendable (_ request: WorkflowStartRequest) async -> WorkflowStartOutcome
}

extension WorkflowStartClient: DependencyKey {
  static let liveValue = WorkflowStartClient(
    catalog: { _ in [] },
    context: { _, _, _ in nil },
    run: { _ in .failed(code: CLIErrorCode.transportFailed, message: "Workflow runtime is not available.") }
  )

  static let testValue = WorkflowStartClient(
    catalog: { _ in [] },
    context: { _, _, _ in nil },
    run: { _ in .failed(code: CLIErrorCode.transportFailed, message: "No test workflow runtime configured.") }
  )
}

extension DependencyValues {
  var workflowStartClient: WorkflowStartClient {
    get { self[WorkflowStartClient.self] }
    set { self[WorkflowStartClient.self] = newValue }
  }
}
