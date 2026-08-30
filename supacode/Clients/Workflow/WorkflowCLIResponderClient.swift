// supacode/Clients/Workflow/WorkflowCLIResponderClient.swift
// The reducer's side of the CLI rendezvous (docs-ai 063 B3, decision W1): a `done` request is
// answered when its activation leaves `persisting`, never on the `.outputPersisted` event alone.
// The composition root turns the resolution into a wire response and resumes the socket handler.

import ComposableArchitecture
import Foundation

/// How a CLI `done` request ended.
nonisolated enum WorkflowDeliveryResolution: Equatable, Sendable {
  /// The output is the step's output and the run advanced.
  case delivered(run: WorkflowRun, receipt: WorkflowDeliveryReceipt)
  /// The output is on disk with issues; the run waits for the user (decision H14).
  case provisional(run: WorkflowRun, receipt: WorkflowDeliveryReceipt)
  case failed(code: String, message: String)
}

struct WorkflowCLIResponderClient: Sendable {
  var respond: @MainActor @Sendable (UUID, WorkflowDeliveryResolution) -> Void
}

extension WorkflowCLIResponderClient: DependencyKey {
  static let liveValue = WorkflowCLIResponderClient(respond: { _, _ in })
  static let testValue = liveValue
}

extension DependencyValues {
  var workflowCLIResponder: WorkflowCLIResponderClient {
    get { self[WorkflowCLIResponderClient.self] }
    set { self[WorkflowCLIResponderClient.self] = newValue }
  }
}
