// supacode/CLIService/WorkflowRuntimeCoordinator.swift
// The socket side of `prowl workflow run / status / done / cancel` (docs-ai 063 B3). It reads the
// reducer's sessions, attributes a `done` to an activation (decision W3), enters the reducer
// through actions, and awaits the `done` rendezvous (decision W1). It owns no run state.

import Foundation

/// A wire response carried as a failure through `Result`.
nonisolated struct WorkflowCommandRefusal: Error {
  let response: CommandResponse
}

@MainActor
final class WorkflowRuntimeCoordinator {
  struct Dependencies {
    let admissionEnvironment: @MainActor () -> WorkflowAdmissionEnvironment
    /// Every session the reducer holds, terminal ones included.
    let sessions: @MainActor () -> [WorkflowRunSession]
    let send: @MainActor (WorkflowRunsFeature.Action) -> Void
    /// The pending dispatch record of a pane, if any (the activation address of decision W3).
    let pendingDispatchID: @MainActor (UUID) -> String?
    /// Working directories of every known worktree, for `status` of a run that is not live (W5).
    let worktreeRoots: @MainActor () -> [URL]
    let rendezvous: WorkflowCLIRendezvous
    let makeRequestID: @Sendable () -> UUID

    init(
      admissionEnvironment: @escaping @MainActor () -> WorkflowAdmissionEnvironment,
      sessions: @escaping @MainActor () -> [WorkflowRunSession],
      send: @escaping @MainActor (WorkflowRunsFeature.Action) -> Void,
      pendingDispatchID: @escaping @MainActor (UUID) -> String?,
      worktreeRoots: @escaping @MainActor () -> [URL],
      rendezvous: WorkflowCLIRendezvous = WorkflowCLIRendezvous(),
      makeRequestID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
      self.admissionEnvironment = admissionEnvironment
      self.sessions = sessions
      self.send = send
      self.pendingDispatchID = pendingDispatchID
      self.worktreeRoots = worktreeRoots
      self.rendezvous = rendezvous
      self.makeRequestID = makeRequestID
    }
  }

  private let dependencies: Dependencies

  init(dependencies: Dependencies) {
    self.dependencies = dependencies
  }

  // MARK: - run

  func run(
    _ input: WorkflowInput, source: WorkflowRunSource, snapshot: WorkflowRuntimeSnapshot
  ) -> CommandResponse {
    var environment = dependencies.admissionEnvironment()
    environment = environment.busy(dependencies.sessions().filter { !$0.run.status.isTerminal })
    let admission = WorkflowRunAdmission.admit(input, source: source, snapshot: snapshot, environment: environment)
    switch admission {
    case .failure(let failure):
      return Self.failure(failure)
    case .success(let admitted):
      dependencies.send(.started(admitted.session, effects: admitted.effects))
      // The reducer may already have advanced (a self-initiated first step opens its activation
      // synchronously); answer with what it holds now.
      let run =
        dependencies.sessions().first { $0.run.id == admitted.session.run.id }?.run
        ?? admitted.session.run
      return Self.success(
        .run(
          WorkflowRunPayload(run: run, callerRole: admitted.callerRole, includeSelfInitiated: true))
      )
    }
  }

  // MARK: - status

  func status(_ input: WorkflowInput, callerPane: CallerPane?) -> CommandResponse {
    if let reference = input.runID {
      guard let runID = UUID(uuidString: reference) else {
        return Self.failure(
          code: CLIErrorCode.invalidArgument, message: "'\(reference)' is not a run UUID.")
      }
      if let session = dependencies.sessions().first(where: { $0.run.id == runID }) {
        let role = callerPane.flatMap { Self.role(of: $0.surfaceID, in: session) }
        return Self.success(
          .status(
            WorkflowRunPayload(run: session.run, callerRole: role, includeSelfInitiated: false)))
      }
      guard let record = readRecord(runID: runID) else {
        return Self.failure(
          code: CLIErrorCode.runNotFound,
          message: "No workflow run \(runID.uuidString) is live or recorded in a known worktree.")
      }
      return Self.success(.status(WorkflowRunPayload(record: record)))
    }
    guard let callerPane else {
      return Self.failure(
        code: CLIErrorCode.sourceRequired,
        message: "Run `prowl workflow status` inside a Prowl pane, or pass a run UUID.")
    }
    guard
      let session = dependencies.sessions().first(where: {
        !$0.run.status.isTerminal && $0.boundSurfaceIDs.contains(callerPane.surfaceID)
      })
    else {
      return Self.failure(
        code: CLIErrorCode.runNotFound, message: "This pane is not part of an active workflow run.")
    }
    let role = Self.role(of: callerPane.surfaceID, in: session)
    return Self.success(
      .status(WorkflowRunPayload(run: session.run, callerRole: role, includeSelfInitiated: false)))
  }

  // MARK: - done

  func done(_ input: WorkflowInput, callerPane: CallerPane?) async -> CommandResponse {
    guard let body = input.body else {
      return Self.failure(
        code: CLIErrorCode.invalidArgument, message: "The delivery has no output body.")
    }
    let explicit: (runID: UUID, stepID: String)?
    switch input.runID {
    case .none:
      guard input.stepID == nil else {
        return Self.failure(
          code: CLIErrorCode.invalidArgument, message: "--run and --step must be passed together.")
      }
      explicit = nil
    case .some(let reference):
      guard let stepID = input.stepID else {
        return Self.failure(
          code: CLIErrorCode.invalidArgument, message: "--run and --step must be passed together.")
      }
      guard let runID = UUID(uuidString: reference) else {
        return Self.failure(
          code: CLIErrorCode.invalidArgument, message: "'\(reference)' is not a run UUID.")
      }
      explicit = (runID, stepID)
    }

    let request: WorkflowDeliveryRequest
    let attribution = attribute(explicit: explicit, callerPane: callerPane, token: input.token, force: input.force)
    switch attribution {
    case .failure(let refusal):
      return refusal.response
    case .success(let attribution):
      request = WorkflowDeliveryRequest(
        requestID: dependencies.makeRequestID(),
        runID: attribution.runID,
        ordinal: attribution.ordinal,
        selector: attribution.selector,
        body: body,
        verdict: input.verdict,
        source: attribution.source)
    }
    dependencies.rendezvous.register(request.requestID)
    dependencies.send(.deliver(request))
    return await dependencies.rendezvous.wait(for: request.requestID)
  }

  private struct Attribution {
    let runID: UUID
    let ordinal: Int?
    let selector: WorkflowDeliverySelector
    let source: String
  }

  /// Decision W3: the caller pane's pending dispatch identifies the activation first; explicit
  /// `--run --step` is the manual path; both present and disagreeing needs `--force`.
  private func attribute(
    explicit: (runID: UUID, stepID: String)?, callerPane: CallerPane?, token: String?, force: Bool
  ) -> Result<Attribution, WorkflowCommandRefusal> {
    let active = dependencies.sessions().filter { !$0.run.status.isTerminal }
    var callerActivation: (session: WorkflowRunSession, activation: WorkflowActivation)?
    if let callerPane, let dispatchID = dependencies.pendingDispatchID(callerPane.surfaceID) {
      for session in active {
        if let activation = session.run.activation(forDispatchID: dispatchID) {
          callerActivation = (session, activation)
          break
        }
      }
    }
    if let (session, activation) = callerActivation {
      if let explicit, explicit.runID != session.run.id || explicit.stepID != activation.stepID {
        guard force else {
          return .failure(
            Self.refusal(
              code: CLIErrorCode.roleMismatch,
              message:
                "This pane is waiting for step '\(activation.stepID)' of run \(session.run.id.uuidString), "
                + "not step '\(explicit.stepID)' of run \(explicit.runID.uuidString); "
                + "pass --force to deliver there anyway."
            ))
        }
        return manual(explicit, source: "manual --force", active: active)
      }
      return .success(
        Attribution(
          runID: session.run.id, ordinal: activation.ordinal, selector: .token(token),
          source: "pane"))
    }
    guard let explicit else {
      if callerPane == nil {
        return .failure(
          Self.refusal(
            code: CLIErrorCode.sourceRequired,
            message: "Run `prowl workflow done` inside the pane that received the step, "
              + "or pass --run <run UUID> --step <step id> for a manual delivery."))
      }
      return .failure(
        Self.refusal(
          code: CLIErrorCode.stepNotExpecting,
          message:
            "This pane holds no waiting workflow activation; the step may have moved on or been skipped."
        ))
    }
    return manual(explicit, source: "manual", active: active)
  }

  private func manual(
    _ explicit: (runID: UUID, stepID: String), source: String, active: [WorkflowRunSession]
  ) -> Result<Attribution, WorkflowCommandRefusal> {
    guard let session = active.first(where: { $0.run.id == explicit.runID }) else {
      return .failure(
        Self.refusal(
          code: CLIErrorCode.runNotFound,
          message: "No active workflow run \(explicit.runID.uuidString)."))
    }
    return .success(
      Attribution(
        runID: session.run.id, ordinal: nil, selector: .manual(stepID: explicit.stepID),
        source: source))
  }

  /// The reducer's answer to a `done` (through `WorkflowCLIResponderClient`).
  func resolve(_ requestID: UUID, _ resolution: WorkflowDeliveryResolution) {
    let response: CommandResponse
    switch resolution {
    case .delivered(let run, let receipt):
      response = Self.success(
        .done(Self.donePayload(run: run, receipt: receipt, state: .delivered)))
    case .provisional(let run, let receipt):
      response = Self.success(
        .done(Self.donePayload(run: run, receipt: receipt, state: .provisional)))
    case .failed(let code, let message):
      response = Self.failure(code: code, message: message)
    }
    dependencies.rendezvous.resolve(requestID, with: response)
  }

  private static func donePayload(
    run: WorkflowRun, receipt: WorkflowDeliveryReceipt, state: WorkflowDeliveryState
  ) -> WorkflowDonePayload {
    let role = run.invocations.first { $0.ordinal == receipt.ordinal }?.role ?? "-"
    return WorkflowDonePayload(
      run: WorkflowRunPayload(run: run, callerRole: role, includeSelfInitiated: false),
      delivery: WorkflowDeliveryPayload(state: state, receipt: receipt, role: role))
  }

  // MARK: - cancel

  func cancel(_ input: WorkflowInput, callerPane: CallerPane?) -> CommandResponse {
    guard let reference = input.runID, let runID = UUID(uuidString: reference) else {
      return Self.failure(code: CLIErrorCode.invalidArgument, message: "cancel needs a run UUID.")
    }
    guard let session = dependencies.sessions().first(where: { $0.run.id == runID }) else {
      return Self.failure(
        code: CLIErrorCode.runNotFound, message: "No live workflow run \(runID.uuidString).")
    }
    guard !session.run.status.isTerminal else {
      return Self.failure(
        code: CLIErrorCode.runNotFound,
        message:
          "Workflow run \(runID.uuidString) already ended (\(WorkflowRunMachine.describe(session.run.status)))."
      )
    }
    dependencies.send(.userAction(runID: runID, .cancel))
    let cancelled = dependencies.sessions().first { $0.run.id == runID }?.run ?? session.run
    let role = callerPane.flatMap { Self.role(of: $0.surfaceID, in: session) }
    return Self.success(
      .cancel(WorkflowRunPayload(run: cancelled, callerRole: role, includeSelfInitiated: false)))
  }

  // MARK: - Helpers

  private static func role(of surfaceID: UUID, in session: WorkflowRunSession) -> String? {
    session.run.bindings.first { $0.value.pane?.surfaceID == surfaceID }?.key
  }

  /// A v1 record from any known worktree root; nothing is reconstructed from it (decision W5).
  private func readRecord(runID: UUID) -> WorkflowRunRecord? {
    for root in dependencies.worktreeRoots() {
      let store = WorkflowRunStore(rootURL: root)
      let recordURL = store.directory(for: runID).appending(
        path: WorkflowRunRecord.fileName, directoryHint: .notDirectory)
      guard FileManager.default.fileExists(atPath: recordURL.path(percentEncoded: false)) else {
        continue
      }
      if let record = try? store.readRecord(runID: runID) {
        return record
      }
    }
    return nil
  }

  static func success(_ payload: WorkflowCommandPayload) -> CommandResponse {
    do {
      return try CommandResponse(
        ok: true,
        command: WorkflowCommandPayload.commandName,
        schemaVersion: WorkflowCommandPayload.schemaVersion,
        data: RawJSON(encoding: payload))
    } catch {
      return failure(
        code: CLIErrorCode.workflowFailed,
        message: "Failed to encode the workflow response: \(error)")
    }
  }

  static func failure(_ failure: WorkflowAdmissionFailure) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: WorkflowCommandPayload.commandName,
      schemaVersion: WorkflowCommandPayload.schemaVersion,
      error: CommandError(
        code: failure.code,
        message: failure.message,
        details: failure.details.flatMap {
          try? RawJSON(encoding: WorkflowCommandPayload.validate($0))
        }))
  }

  static func failure(code: String, message: String) -> CommandResponse {
    WorkflowCLIRendezvous.failure(code: code, message: message)
  }

  static func refusal(code: String, message: String) -> WorkflowCommandRefusal {
    WorkflowCommandRefusal(response: failure(code: code, message: message))
  }
}

extension WorkflowAdmissionEnvironment {
  /// The same environment with the panes of `sessions` marked busy.
  func busy(_ sessions: [WorkflowRunSession]) -> WorkflowAdmissionEnvironment {
    WorkflowAdmissionEnvironment(
      profiles: profiles,
      recommendation: recommendation,
      rememberedBinding: rememberedBinding,
      detectedAgent: detectedAgent,
      pendingDispatchID: pendingDispatchID,
      busySurfaceIDs: busySurfaceIDs.union(sessions.flatMap(\.boundSurfaceIDs)),
      worktree: worktree,
      branchName: branchName,
      makeLaunchPlan: makeLaunchPlan,
      bundledSkill: bundledSkill,
      now: now,
      makeRunID: makeRunID,
      makeToken: makeToken,
      limits: limits)
  }
}
