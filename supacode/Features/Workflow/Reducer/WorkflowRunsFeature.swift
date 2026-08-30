// supacode/Features/Workflow/Reducer/WorkflowRunsFeature.swift
// The reducer that owns every live workflow run (docs-ai 063 B3, decision H2/W1). The pure
// `WorkflowRunMachine` is reconstructed per transition; this reducer performs its effects against
// the terminal, dispatch, launch, store, native-action, and watchdog boundaries, answers the CLI
// `done` rendezvous when an activation leaves `persisting`, and cleans up what arrives late.

import ComposableArchitecture
import Foundation

/// The in-memory part of a run that `run.json` deliberately excludes: the worktree object, the
/// frozen profile launch plans (their surface environment carries override values), the binding
/// memory keys, and the bundled skill locations.
nonisolated struct WorkflowRunSession: Equatable, Sendable {
  var run: WorkflowRun
  let worktree: Worktree
  let launchPlans: [String: AgentProfileLaunchPlan]
  /// Per `launch` role, the binding-memory key its profile is remembered under once launched.
  let bindingMemoryKeys: [String: WorkflowBindingMemoryKey]
  let skills: [String: BundledSkill]
  let limits: WorkflowDeliveryLimits

  init(
    run: WorkflowRun,
    worktree: Worktree,
    launchPlans: [String: AgentProfileLaunchPlan],
    bindingMemoryKeys: [String: WorkflowBindingMemoryKey] = [:],
    skills: [String: BundledSkill] = [:],
    limits: WorkflowDeliveryLimits = WorkflowDeliveryLimits()
  ) {
    self.run = run
    self.worktree = worktree
    self.launchPlans = launchPlans
    self.bindingMemoryKeys = bindingMemoryKeys
    self.skills = skills
    self.limits = limits
  }

  var store: WorkflowRunStore { WorkflowRunStore(rootURL: run.context.worktree.rootURL) }

  /// Every pane the run currently occupies (dsl-spec §10: one run per pane).
  var boundSurfaceIDs: Set<UUID> {
    Set(run.bindings.values.compactMap { $0.pane?.surfaceID })
  }

  func machine(now: @escaping @Sendable () -> Date, makeToken: @escaping @Sendable () -> String)
    -> WorkflowRunMachine
  {
    WorkflowRunMachine(run: run, limits: limits, now: now, makeToken: makeToken)
  }
}

/// A CLI `done` accepted by the machine and waiting for its output to reach the run directory.
nonisolated struct WorkflowPendingDelivery: Equatable, Sendable {
  let runID: UUID
  let ordinal: Int
  let receipt: WorkflowDeliveryReceipt
}

/// `prowl workflow done` after the handler attributed it (decision W3).
nonisolated struct WorkflowDeliveryRequest: Equatable, Sendable {
  let requestID: UUID
  let runID: UUID
  /// The activation the caller pane's pending dispatch resolved to; nil for a manual delivery.
  let ordinal: Int?
  let selector: WorkflowDeliverySelector
  let body: String
  let verdict: String?
  /// `pane` or `manual` (`manual --force` when the caller pane disagreed), for the run log.
  let source: String
}

@Reducer
struct WorkflowRunsFeature {
  @ObservableState
  struct State: Equatable {
    /// Every run started in this app instance, terminal ones included (`status` reads them).
    var sessions: [UUID: WorkflowRunSession] = [:]
    var pendingDeliveries: [UUID: WorkflowPendingDelivery] = [:]
    /// Worktree roots whose leftover runs were marked `interrupted` at load (dsl-spec §10 Restart).
    var scannedWorktreeRoots: Set<String> = []

    var activeSessions: [WorkflowRunSession] {
      sessions.values.filter { !$0.run.status.isTerminal }
    }

    /// The active run a pane belongs to, if any.
    func activeSession(boundTo surfaceID: UUID) -> WorkflowRunSession? {
      activeSessions.first { $0.boundSurfaceIDs.contains(surfaceID) }
    }
  }

  enum Action: Equatable {
    /// Admission succeeded (preflight, layout, initial record): own the run and perform its effects.
    case started(WorkflowRunSession, effects: [WorkflowRunEffect])
    case event(runID: UUID, WorkflowRunEvent)
    case deliver(WorkflowDeliveryRequest)
    case userAction(runID: UUID, WorkflowUserAction)
    case markInterruptedRuns(worktreeRoots: [String])
  }

  @Dependency(WorkflowRuntimeClient.self) var runtime
  @Dependency(WorkflowActivationClient.self) var activation
  @Dependency(WorkflowWatchdogClient.self) var watchdog
  @Dependency(WorkflowEffectQueueClient.self) var queue
  @Dependency(WorkflowCLIResponderClient.self) var responder
  @Dependency(\.date.now) var now
  @Dependency(\.uuid) var uuid

  nonisolated private static let logger = SupaLogger("WorkflowRuns")

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .started(let session, let effects):
        let runID = session.run.id
        state.sessions[runID] = session
        // The queue exists before the first batch is enqueued below; the executor drains it.
        let batches = queue.start(runID)
        return .merge(
          executor(runID: runID, batches: batches),
          perform(effects, runID: runID, session: session)
        )

      case .event(let runID, let event):
        guard var session = state.sessions[runID], !session.run.status.isTerminal else {
          return lateLaunchCleanup(event, session: state.sessions[runID])
        }
        let timestamp = now
        let generator = uuid
        var machine = session.machine(now: { timestamp }, makeToken: { generator().uuidString })
        let effects = machine.apply(event)
        let previous = session.run
        session.run = machine.run
        state.sessions[runID] = session
        if case .launched = event {
          rememberLaunchedBindings(previous: previous, current: session)
        }
        return .merge(
          resolvePendingDeliveries(&state, runID: runID, session: session),
          perform(effects, runID: runID, session: session),
          staleLaunchCleanup(event, session: session)
        )

      case .deliver(let request):
        guard var session = state.sessions[request.runID], !session.run.status.isTerminal else {
          return respond(
            request.requestID,
            .failed(code: CLIErrorCode.runNotFound, message: "The workflow run is not active."))
        }
        let timestamp = now
        let generator = uuid
        var machine = session.machine(now: { timestamp }, makeToken: { generator().uuidString })
        let (result, effects) = machine.deliver(
          ordinal: request.ordinal, selector: request.selector, body: request.body,
          verdict: request.verdict)
        switch result {
        case .failure(let error):
          return respond(request.requestID, .failed(code: error.code, message: error.message))
        case .success(let receipt):
          session.run = machine.run
          state.sessions[request.runID] = session
          state.pendingDeliveries[request.requestID] = WorkflowPendingDelivery(
            runID: request.runID, ordinal: receipt.ordinal, receipt: receipt)
          var ordered = effects
          if request.source != "pane" {
            ordered.insert(
              .log("Step '\(receipt.stepID)': delivery received (source=\(request.source))."), at: 0
            )
          }
          return perform(ordered, runID: request.runID, session: session)
        }

      case .userAction(let runID, let userAction):
        guard var session = state.sessions[runID], !session.run.status.isTerminal else {
          return .none
        }
        let timestamp = now
        let generator = uuid
        var machine = session.machine(now: { timestamp }, makeToken: { generator().uuidString })
        let effects = machine.apply(.user(userAction))
        session.run = machine.run
        state.sessions[runID] = session
        return .merge(
          resolvePendingDeliveries(&state, runID: runID, session: session),
          perform(effects, runID: runID, session: session)
        )

      case .markInterruptedRuns(let roots):
        let pending = roots.filter { !state.scannedWorktreeRoots.contains($0) }
        guard !pending.isEmpty else { return .none }
        state.scannedWorktreeRoots.formUnion(pending)
        let timestamp = now
        return .run { _ in
          for root in pending {
            let store = WorkflowRunStore(rootURL: URL(filePath: root, directoryHint: .isDirectory))
            do {
              let result = try store.markInterruptedRuns(now: timestamp)
              if !result.interrupted.isEmpty || !result.unreadable.isEmpty {
                Self.logger.info(
                  "[Workflow] \(root): \(result.interrupted.count) run(s) marked interrupted, "
                    + "\(result.unreadable.count) unreadable.")
              }
            } catch {
              Self.logger.warning(
                "[Workflow] Could not scan \(root) for interrupted runs: \(error)")
            }
          }
        }
      }
    }
  }

  // MARK: - Rendezvous

  private func respond(_ requestID: UUID, _ resolution: WorkflowDeliveryResolution) -> Effect<
    Action
  > {
    .run { _ in await responder.respond(requestID, resolution) }
  }

  /// Answers every `done` whose activation left `persisting` (decision W1): delivered and
  /// provisional succeed; a revoked, skipped, or unpersistable activation and a run that ended fail.
  private func resolvePendingDeliveries(
    _ state: inout State, runID: UUID, session: WorkflowRunSession
  ) -> Effect<Action> {
    var effects: [Effect<Action>] = []
    for (requestID, pending) in state.pendingDeliveries where pending.runID == runID {
      let activation = session.run.invocations.first { $0.ordinal == pending.ordinal }?.activation
      let resolution: WorkflowDeliveryResolution?
      switch activation?.state {
      case .delivered:
        resolution = .delivered(run: session.run, receipt: pending.receipt)
      case .provisional:
        resolution = .provisional(run: session.run, receipt: pending.receipt)
      case .persisting:
        if case .persistFailed(let reason) = session.run.status.attention?.reason,
          session.run.status.attention?.ordinal == pending.ordinal
        {
          resolution = .failed(
            code: CLIErrorCode.workflowFailed,
            message:
              "The output was accepted but could not be saved to the run directory: \(reason)")
        } else if session.run.status.isTerminal {
          resolution = .failed(
            code: CLIErrorCode.stepNotExpecting,
            message:
              "The run ended (\(WorkflowRunMachine.describe(session.run.status))) before the output was saved."
          )
        } else {
          resolution = nil
        }
      case .waiting, .skipped, .revoked, .none:
        resolution = .failed(
          code: CLIErrorCode.stepNotExpecting,
          message: "The step stopped waiting for this delivery before the output was saved.")
      }
      guard let resolution else { continue }
      state.pendingDeliveries.removeValue(forKey: requestID)
      effects.append(respond(requestID, resolution))
    }
    return .merge(effects)
  }

  // MARK: - Late launches

  /// A `.launched` that arrives after the run ended (or for an unknown run) owns a pane and maybe
  /// a dispatch record nobody will use: abandon the record and close the pane (B2: the machine
  /// ignores events on terminal runs, so the wiring must clean up).
  private func lateLaunchCleanup(_ event: WorkflowRunEvent, session: WorkflowRunSession?) -> Effect<
    Action
  > {
    guard case .launched(let ordinal, let pane, let dispatchID) = event else { return .none }
    let reason =
      "Workflow run \(session?.run.id.uuidString ?? "?") ended before role launch \(ordinal) completed."
    return closeUnboundLaunch(
      pane: pane, dispatchID: dispatchID, reason: reason, worktree: session?.worktree)
  }

  /// A `.launched` the running machine did not bind (its step was retried, relaunched, skipped,
  /// or cancelled while the launch was in flight) is cleaned up the same way.
  private func staleLaunchCleanup(_ event: WorkflowRunEvent, session: WorkflowRunSession) -> Effect<
    Action
  > {
    guard case .launched(let ordinal, let pane, let dispatchID) = event,
      !session.boundSurfaceIDs.contains(pane.surfaceID)
    else { return .none }
    let reason =
      "Workflow run \(session.run.id.uuidString) moved on before role launch \(ordinal) completed."
    return closeUnboundLaunch(
      pane: pane, dispatchID: dispatchID, reason: reason, worktree: session.worktree)
  }

  private func closeUnboundLaunch(
    pane: WorkflowPaneIdentity, dispatchID: String?, reason: String, worktree: Worktree?
  ) -> Effect<Action> {
    .run { _ in
      if let dispatchID {
        await activation.abandon(dispatchID, reason)
      }
      if let worktree {
        await runtime.close(worktree, pane.surfaceID)
      }
      Self.logger.info("[Workflow] Closed unbound launch \(pane.handle): \(reason)")
    }
  }

  // MARK: - Binding memory

  /// A successful launch remembers its profile under B2's requirements digest (dsl-spec §3).
  private func rememberLaunchedBindings(previous: WorkflowRun, current: WorkflowRunSession) {
    for (role, binding) in current.run.bindings {
      guard case .launch(let profile, let pane) = binding, pane != nil,
        previous.bindings[role]?.pane == nil,
        let key = current.bindingMemoryKeys[role]
      else { continue }
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.remember(workflowBinding: key, profileID: profile.id) }
    }
  }

  // MARK: - Effects

  nonisolated private enum CancelID: Hashable, Sendable {
    case executor(UUID)
    case roleWait(UUID, Int)
    case watchdog(UUID, Int)
    case observers(UUID)
  }

  /// The run's ordered effect executor (one per run). It ends when `.finished` closes the queue.
  private func executor(runID: UUID, batches: AsyncStream<WorkflowEffectBatch>) -> Effect<Action> {
    .run { send in
      for await batch in batches {
        for effect in batch.effects {
          let outcome = await perform(effect, runID: runID, session: batch.session, send: send)
          if outcome == .stop { break }
        }
      }
    }
    .cancellable(id: CancelID.executor(runID), cancelInFlight: true)
  }

  /// Splits a batch: ordered effects go to the run's queue; observers become cancellable effects.
  private func perform(_ effects: [WorkflowRunEffect], runID: UUID, session: WorkflowRunSession)
    -> Effect<Action>
  {
    var ordered: [WorkflowRunEffect] = []
    var observers: [Effect<Action>] = []
    let armedOrdinals = Set(
      effects.compactMap { effect -> Int? in
        if case .armWatchdog(let request) = effect { return request.ordinal }
        return nil
      })
    for effect in effects {
      switch effect {
      case .awaitRoleIdle(_, let surfaceID, let ordinal):
        observers.append(roleWait(runID: runID, surfaceID: surfaceID, ordinal: ordinal))
      case .cancelRoleWait(let ordinal):
        observers.append(.cancel(id: CancelID.roleWait(runID, ordinal)))
      case .armWatchdog(let request):
        observers.append(watchdogObserver(runID: runID, request: request))
      case .disarmWatchdog(let ordinal):
        // A re-arm in the same batch replaces the driver through `cancelInFlight`; a lone
        // disarm cancels the consuming effect, which tears the driver down.
        if !armedOrdinals.contains(ordinal) {
          observers.append(.cancel(id: CancelID.watchdog(runID, ordinal)))
        }
      case .finished:
        ordered.append(effect)
        observers.append(.cancel(id: CancelID.observers(runID)))
      default:
        ordered.append(effect)
      }
    }
    if !ordered.isEmpty {
      // Enqueued synchronously while reducing so batches keep the machine's order.
      queue.enqueue(runID, WorkflowEffectBatch(session: session, effects: ordered))
    }
    return .merge(observers)
  }

  /// The idle wait of a `message` step (dsl-spec §10): ends as `.roleIdle`, or as the failed
  /// injection the machine maps to attention.
  private func roleWait(runID: UUID, surfaceID: UUID, ordinal: Int) -> Effect<Action> {
    .run { send in
      switch await runtime.waitForRole(surfaceID) {
      case .idle:
        await send(.event(runID: runID, .roleIdle(ordinal: ordinal)))
      case .blocked:
        await send(.event(runID: runID, .roleUnavailable(ordinal: ordinal, .roleBlocked)))
      case .gone:
        await send(.event(runID: runID, .roleUnavailable(ordinal: ordinal, .surfaceMissing)))
      case .noAgent:
        await send(
          .event(
            runID: runID,
            .roleUnavailable(ordinal: ordinal, .activationUnavailable("the pane hosts no detected agent"))))
      case .dispatchPending(let dispatchID):
        await send(
          .event(
            runID: runID,
            .roleUnavailable(
              ordinal: ordinal,
              .activationUnavailable(
                "the pane already holds pending dispatch \(dispatchID); complete or abandon it first"))))
      case .cancelled:
        break
      }
    }
    .cancellable(id: CancelID.roleWait(runID, ordinal), cancelInFlight: true)
    .cancellable(id: CancelID.observers(runID))
  }

  /// One watchdog driver per waiting activation; cancelling the effect tears the driver down.
  private func watchdogObserver(runID: UUID, request: WorkflowWatchdogRequest) -> Effect<Action> {
    .run { send in
      let handle = await watchdog.arm(runID, request)
      for await verdict in handle.verdicts {
        await send(.event(runID: runID, .watchdog(ordinal: request.ordinal, verdict)))
      }
      await handle.cancel()
    }
    .cancellable(id: CancelID.watchdog(runID, request.ordinal), cancelInFlight: true)
    .cancellable(id: CancelID.observers(runID))
  }

  nonisolated private enum StepOutcome: Equatable {
    case `continue`
    /// The rest of the batch depends on what just failed (an instruction the line points at).
    case stop
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private func perform(
    _ effect: WorkflowRunEffect, runID: UUID, session: WorkflowRunSession, send: Send<Action>
  ) async -> StepOutcome {
    let store = session.store
    let timestamp = now
    switch effect {
    case .awaitRoleIdle, .cancelRoleWait, .armWatchdog, .disarmWatchdog:
      // Observers never enter the ordered queue.
      return .continue

    case .openActivation(_, let surfaceID, let ordinal):
      switch await activation.openMessage(surfaceID) {
      case .success(let dispatchID):
        await send(
          .event(runID: runID, .injectionSucceeded(ordinal: ordinal, dispatchID: dispatchID)))
      case .failure(let failure):
        await send(
          .event(runID: runID, .injectionFailed(ordinal: ordinal, failure.injectionFailure)))
      }

    case .materializeInstruction(let ordinal, let stepID, let text):
      do {
        try store.ensureLayout(runID: runID)
        _ = try store.writeInstruction(runID: runID, stepID: stepID, ordinal: ordinal, text: text)
      } catch {
        await send(
          .event(
            runID: runID,
            .injectionFailed(
              ordinal: ordinal,
              .activationUnavailable("the instruction file could not be written: \(error)"))))
        return .stop
      }

    case .materializeSkill(let id):
      do {
        guard let skill = session.skills[id] else { throw WorkflowRunStoreError.skillMissing(id) }
        try store.ensureLayout(runID: runID)
        _ = try store.materializeSkill(runID: runID, skill: skill)
      } catch {
        guard let ordinal = session.run.currentInvocation?.ordinal else { return .stop }
        await send(
          .event(
            runID: runID,
            .launchFailed(
              ordinal: ordinal, reason: "skill '\(id)' could not be materialized: \(error)")))
        return .stop
      }

    case .inject(_, let surfaceID, let ordinal, let line, let opensActivation):
      var dispatchID: String?
      if opensActivation {
        switch await activation.openMessage(surfaceID) {
        case .success(let value):
          dispatchID = value
        case .failure(let failure):
          await send(
            .event(runID: runID, .injectionFailed(ordinal: ordinal, failure.injectionFailure)))
          return .stop
        }
      }
      switch await runtime.deliverLine(session.worktree, surfaceID, line) {
      case .delivered:
        await send(
          .event(runID: runID, .injectionSucceeded(ordinal: ordinal, dispatchID: dispatchID)))
      case .insertFailed:
        if let dispatchID { activation.cancel(dispatchID) }
        await send(.event(runID: runID, .injectionFailed(ordinal: ordinal, .insertFailed)))
        return .stop
      case .submitFailed:
        if let dispatchID { activation.cancel(dispatchID) }
        await send(.event(runID: runID, .injectionFailed(ordinal: ordinal, .submitFailed)))
        return .stop
      }

    case .typeLine(let role, let surfaceID, let line):
      if runtime.deliverLine(session.worktree, surfaceID, line) != .delivered {
        Self.logger.warning("[Workflow] Could not type into role '\(role)' of run \(runID).")
      }

    case .launch(let request):
      guard let plan = session.launchPlans[request.role] else {
        await send(
          .event(
            runID: runID,
            .launchFailed(
              ordinal: request.ordinal, reason: "role '\(request.role)' has no frozen launch plan"))
        )
        return .stop
      }
      switch await runtime.launch(session.worktree, plan, request) {
      case .success(let result):
        await send(
          .event(
            runID: runID,
            .launched(ordinal: request.ordinal, pane: result.pane, dispatchID: result.dispatchID)))
      case .failure(.failed(let reason)):
        await send(.event(runID: runID, .launchFailed(ordinal: request.ordinal, reason: reason)))
        return .stop
      }

    case .runAction(let stepID, let actionID, let inputs):
      let context = WorkflowActionContext(
        runID: runID,
        rootURL: session.run.context.worktree.rootURL,
        roleAgents: session.run.bindings.mapValues {
          $0.templateRole.agent.isEmpty ? nil : $0.templateRole.agent
        },
        outgoingAgent: session.run.bindings.values.first { $0.source == .current }?.pane?.agent,
        now: timestamp)
      do {
        let outputs = try await WorkflowNativeActionRunner().execute(
          actionID: actionID, inputs: inputs, context: context)
        await send(.event(runID: runID, .actionCompleted(stepID: stepID, outputs: outputs)))
      } catch {
        await send(.event(runID: runID, .actionFailed(stepID: stepID, reason: "\(error)")))
      }

    case .notify(let text):
      runtime.notify(session.worktree, text)

    case .close(_, let surfaceID):
      runtime.close(session.worktree, surfaceID)

    case .abandonActivation(let dispatchID, let reason):
      activation.abandon(dispatchID, reason)

    case .completeActivation(let dispatchID, let summary):
      activation.complete(dispatchID, summary)

    case .persistOutput(let name, let ordinal, let body):
      do {
        _ = try store.writeOutput(runID: runID, name: name, ordinal: ordinal, body: body)
        await send(.event(runID: runID, .outputPersisted(ordinal: ordinal)))
      } catch {
        await send(.event(runID: runID, .outputPersistFailed(ordinal: ordinal, reason: "\(error)")))
      }

    case .persist:
      do {
        try store.ensureLayout(runID: runID)
        try store.writeRecord(WorkflowRunRecord(run: session.run))
      } catch {
        Self.logger.warning("[Workflow] Could not persist run \(runID): \(error)")
      }

    case .log(let line):
      do {
        try store.ensureLayout(runID: runID)
        try store.appendLog(runID: runID, line: line, now: timestamp)
      } catch {
        Self.logger.warning("[Workflow] Could not append to the log of run \(runID): \(error)")
      }

    case .finished:
      queue.finish(runID)
    }
    return .continue
  }
}
