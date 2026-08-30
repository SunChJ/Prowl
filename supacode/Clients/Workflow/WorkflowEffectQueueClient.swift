// supacode/Clients/Workflow/WorkflowEffectQueueClient.swift
// One FIFO per run for the machine's ordered effects (docs-ai 063 B3). The reducer enqueues
// every batch synchronously as it reduces; a single long-lived effect per run performs them one
// after another, so an instruction file exists before the line that names it is typed and
// `run.json` writes never overtake each other. Long-running observers (idle waits, watchdogs)
// stay separate cancellable effects.

import ComposableArchitecture
import Foundation

/// A batch of effects together with the run state they were emitted from (`persist` writes it).
struct WorkflowEffectBatch: Equatable, Sendable {
  let session: WorkflowRunSession
  let effects: [WorkflowRunEffect]
}

struct WorkflowEffectQueueClient: Sendable {
  /// Opens the run's queue; the stream ends after `finish`.
  var start: @MainActor @Sendable (UUID) -> AsyncStream<WorkflowEffectBatch>
  var enqueue: @MainActor @Sendable (UUID, WorkflowEffectBatch) -> Void
  var finish: @MainActor @Sendable (UUID) -> Void
}

@MainActor
final class WorkflowEffectQueue {
  private var continuations: [UUID: AsyncStream<WorkflowEffectBatch>.Continuation] = [:]

  func start(_ runID: UUID) -> AsyncStream<WorkflowEffectBatch> {
    continuations[runID]?.finish()
    let (stream, continuation) = AsyncStream.makeStream(of: WorkflowEffectBatch.self)
    continuations[runID] = continuation
    return stream
  }

  func enqueue(_ runID: UUID, _ batch: WorkflowEffectBatch) {
    continuations[runID]?.yield(batch)
  }

  func finish(_ runID: UUID) {
    continuations.removeValue(forKey: runID)?.finish()
  }

  var client: WorkflowEffectQueueClient {
    WorkflowEffectQueueClient(
      start: { [self] runID in start(runID) },
      enqueue: { [self] runID, batch in enqueue(runID, batch) },
      finish: { [self] runID in finish(runID) }
    )
  }
}

extension WorkflowEffectQueueClient: DependencyKey {
  /// The app installs `WorkflowEffectQueue().client` at its composition root; tests inject a
  /// queue explicitly. The default performs nothing.
  static let liveValue = WorkflowEffectQueueClient(
    start: { _ in AsyncStream { $0.finish() } },
    enqueue: { _, _ in },
    finish: { _ in }
  )

  static let testValue = liveValue
}

extension DependencyValues {
  var workflowEffectQueue: WorkflowEffectQueueClient {
    get { self[WorkflowEffectQueueClient.self] }
    set { self[WorkflowEffectQueueClient.self] = newValue }
  }
}
