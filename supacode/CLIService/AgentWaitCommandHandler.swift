import Foundation

@MainActor
final class AgentWaitCommandHandler: CommandHandler {
  typealias ObserveDispatch =
    @MainActor (
      String
    ) -> Result<AgentDispatchObservationStream, AgentDispatchStoreError>
  typealias ObserveCondition = @MainActor (UUID) -> AgentObservationStream
  struct ConditionSnapshot: Sendable {
    let agent: ActiveAgentEntry?
    /// Active terminal evidence for idle, blocked, and exit conditions.
    let signal: AgentSignal?
    /// Latest current-epoch signal used only to detect a post-baseline change.
    let changedSignal: AgentSignal?
    let revision: UInt64
    let isLive: Bool
    let signals: AgentSignalsPayload

    init(
      agent: ActiveAgentEntry?,
      signal: AgentSignal?,
      changedSignal: AgentSignal? = nil,
      revision: UInt64,
      isLive: Bool,
      signals: AgentSignalsPayload
    ) {
      self.agent = agent
      self.signal = signal
      self.changedSignal = changedSignal ?? signal
      self.revision = revision
      self.isLive = isLive
      self.signals = signals
    }
  }

  nonisolated private enum DispatchOutcome: Sendable {
    case terminal(AgentDispatchSnapshot)
    case needsInput(AgentDispatchSnapshot)
    case incomplete(AgentDispatchSnapshot)
    case timeout
    case cancelled
  }

  private let observeDispatch: ObserveDispatch
  private let observeCondition: ObserveCondition
  private let resolveConditionTarget: @MainActor (String) -> Result<TabResolvedTarget, TargetResolverError>
  private let conditionSnapshot: @MainActor (TabResolvedTarget) -> ConditionSnapshot
  private let signalsProvider: @MainActor (TabTarget) -> AgentSignalsPayload
  private let screenProvider: @MainActor (TabTarget) -> String?
  private let clock: any Clock<Duration>
  private let now: @MainActor () -> Date
  private let formatter: ISO8601DateFormatter

  init(
    observeDispatch: @escaping ObserveDispatch,
    observeCondition: @escaping ObserveCondition = { _ in
      AgentObservationStream { _ in }
    },
    resolveConditionTarget: @escaping @MainActor (String) -> Result<TabResolvedTarget, TargetResolverError> = {
      _ in .failure(.notFound("The pane was not found."))
    },
    conditionSnapshot: @escaping @MainActor (TabResolvedTarget) -> ConditionSnapshot = { _ in
      ConditionSnapshot(agent: nil, signal: nil, revision: 0, isLive: false, signals: .empty)
    },
    signalsProvider: @escaping @MainActor (TabTarget) -> AgentSignalsPayload = { _ in .empty },
    screenProvider: @escaping @MainActor (TabTarget) -> String? = { _ in nil },
    clock: any Clock<Duration> = ContinuousClock(),
    now: @escaping @MainActor () -> Date = Date.init
  ) {
    self.observeDispatch = observeDispatch
    self.observeCondition = observeCondition
    self.resolveConditionTarget = resolveConditionTarget
    self.conditionSnapshot = conditionSnapshot
    self.signalsProvider = signalsProvider
    self.screenProvider = screenProvider
    self.clock = clock
    self.now = now
    self.formatter = AgentDispatchCompleteCommandHandler.makeFormatter()
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .agentsWait(let input) = envelope.command else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Expected an agents.wait command.")
    }
    guard (1...AgentWaitInput.maximumTimeoutSeconds).contains(input.timeoutSeconds),
      input.includeScreenLines.map({ (1...AgentWaitInput.maximumScreenLines).contains($0) }) ?? true
    else {
      return failure(code: CLIErrorCode.invalidArgument, message: "The wait bounds are invalid.")
    }
    switch input.mode {
    case .dispatch:
      guard let dispatchID = input.dispatchID,
        input.pane == nil,
        input.condition == nil,
        input.minimumConfidence == nil
      else {
        return failure(code: CLIErrorCode.invalidArgument, message: "Dispatch wait accepts only a dispatch id.")
      }
      return await waitForDispatch(
        dispatchID,
        timeoutSeconds: input.timeoutSeconds,
        includeScreenLines: input.includeScreenLines
      )
    case .condition:
      return await waitForCondition(input)
    }
  }

  // Outcome ordering is kept explicit because each dispatch state has a distinct exit contract.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private func waitForDispatch(
    _ dispatchID: String,
    timeoutSeconds: Int,
    includeScreenLines: Int?
  ) async -> CommandResponse {
    let stream: AgentDispatchObservationStream
    switch observeDispatch(dispatchID) {
    case .failure:
      return failure(code: CLIErrorCode.dispatchNotFound, message: "The dispatch receipt was not found.")
    case .success(let value):
      stream = value
    }

    let startedAt = now()
    let waitClock = clock
    let latestSnapshot = LatestDispatchSnapshot()
    let cursor = AgentDispatchObservationCursor(stream: stream)
    guard let initialEvent = await cursor.next() else {
      return failure(code: CLIErrorCode.timeout, message: "The wait was cancelled.")
    }
    switch initialEvent {
    case .snapshot(let snapshot), .changed(let snapshot):
      latestSnapshot.set(snapshot)
      if snapshot.record.isTerminal {
        return await response(
          for: snapshot,
          waitedMilliseconds: max(0, Int(now().timeIntervalSince(startedAt) * 1_000)),
          includeScreenLines: includeScreenLines
        )
      }
    case .needsInput(let snapshot):
      return dispatchFailure(
        code: CLIErrorCode.dispatchNeedsInput,
        message: "The dispatched agent needs input.",
        snapshot: snapshot,
        waitedMilliseconds: max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
      )
    case .incomplete(let snapshot):
      return dispatchFailure(
        code: CLIErrorCode.dispatchIncomplete,
        message: "The agent turn ended without completing its dispatch receipt.",
        snapshot: snapshot,
        waitedMilliseconds: max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
      )
    }
    let outcome = await withTaskGroup(of: DispatchOutcome.self) { group in
      group.addTask {
        while !Task.isCancelled, let event = await cursor.next() {
          switch event {
          case .snapshot(let snapshot), .changed(let snapshot):
            latestSnapshot.set(snapshot)
            if snapshot.record.isTerminal { return .terminal(snapshot) }
          case .needsInput(let snapshot):
            return .needsInput(snapshot)
          case .incomplete(let snapshot):
            return .incomplete(snapshot)
          }
        }
        return .cancelled
      }
      group.addTask {
        do {
          try await waitClock.sleep(for: .seconds(timeoutSeconds))
          return .timeout
        } catch {
          return .cancelled
        }
      }
      let first = await group.next() ?? .cancelled
      group.cancelAll()
      return first
    }
    let waited = max(0, Int(now().timeIntervalSince(startedAt) * 1_000))

    switch outcome {
    case .cancelled:
      return failure(code: CLIErrorCode.timeout, message: "The wait was cancelled.")
    case .timeout:
      if let snapshot = latestSnapshot.value {
        return dispatchFailure(
          code: CLIErrorCode.waitTimeout,
          message: "Timed out waiting for dispatch completion.",
          snapshot: snapshot,
          waitedMilliseconds: waited
        )
      }
      return failure(code: CLIErrorCode.waitTimeout, message: "Timed out waiting for dispatch completion.")
    case .needsInput(let snapshot):
      return dispatchFailure(
        code: CLIErrorCode.dispatchNeedsInput,
        message: "The dispatched agent needs input.",
        snapshot: snapshot,
        waitedMilliseconds: waited
      )
    case .incomplete(let snapshot):
      return dispatchFailure(
        code: CLIErrorCode.dispatchIncomplete,
        message: "The agent turn ended without completing its dispatch receipt.",
        snapshot: snapshot,
        waitedMilliseconds: waited
      )
    case .terminal(let snapshot):
      return await response(
        for: snapshot,
        waitedMilliseconds: waited,
        includeScreenLines: includeScreenLines
      )
    }
  }

  private func response(
    for snapshot: AgentDispatchSnapshot,
    waitedMilliseconds: Int,
    includeScreenLines: Int?
  ) async -> CommandResponse {
    guard let binding = snapshot.binding else {
      return failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch has no bound pane.")
    }
    switch snapshot.payload(using: formatter) {
    case .completed(let receipt) where receipt.outcome == .succeeded:
      do {
        return try CommandResponse(
          ok: true,
          command: "agents.wait",
          schemaVersion: "prowl.cli.agents.wait.v1",
          data: RawJSON(
            encoding: AgentWaitCommandPayload.dispatch(
              AgentDispatchWaitPayload(
                waitedMilliseconds: waitedMilliseconds,
                target: binding.target,
                receipt: receipt,
                signals: signalsProvider(binding.target),
                screen: await stableScreen(requestedLines: includeScreenLines, target: binding.target)
              )))
        )
      } catch {
        return failure(code: CLIErrorCode.dispatchFailed, message: "Failed to encode the dispatch result.")
      }
    case .completed:
      return dispatchFailure(
        code: CLIErrorCode.dispatchFailed,
        message: "The dispatched task failed.",
        snapshot: snapshot,
        waitedMilliseconds: waitedMilliseconds
      )
    case .abandoned:
      return dispatchFailure(
        code: CLIErrorCode.dispatchAbandoned,
        message: "The dispatch was abandoned.",
        snapshot: snapshot,
        waitedMilliseconds: waitedMilliseconds
      )
    case .gone:
      return dispatchFailure(
        code: CLIErrorCode.agentGone,
        message: "The dispatched agent is gone.",
        snapshot: snapshot,
        waitedMilliseconds: waitedMilliseconds
      )
    case .pending:
      return dispatchFailure(
        code: CLIErrorCode.dispatchIncomplete,
        message: "The dispatch is still pending.",
        snapshot: snapshot,
        waitedMilliseconds: waitedMilliseconds
      )
    }
  }

  private func dispatchFailure(
    code: String,
    message: String,
    snapshot: AgentDispatchSnapshot,
    waitedMilliseconds: Int
  ) -> CommandResponse {
    guard let binding = snapshot.binding else { return failure(code: code, message: message) }
    do {
      return CommandResponse(
        ok: false,
        command: "agents.wait",
        schemaVersion: "prowl.cli.agents.wait.v1",
        error: CommandError(
          code: code,
          message: message,
          details: try RawJSON(
            encoding: AgentWaitErrorDetails.dispatch(
              AgentDispatchWaitErrorDetails(
                waitedMilliseconds: waitedMilliseconds,
                target: binding.target,
                record: snapshot.payload(using: formatter),
                signals: signalsProvider(binding.target)
              )))
        )
      )
    } catch {
      return failure(code: code, message: message)
    }
  }

  // This is the single cancellation-scoped state machine for freshness and stabilization.
  // swiftlint:disable:next function_body_length
  private func waitForCondition(_ input: AgentWaitInput) async -> CommandResponse {
    guard let pane = input.pane, let condition = input.condition, input.dispatchID == nil else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Condition wait requires a pane and condition.")
    }
    let target: TabResolvedTarget
    switch resolveConditionTarget(pane) {
    case .failure(.notFound(let message)):
      return failure(code: CLIErrorCode.targetNotFound, message: message)
    case .failure(.notUnique(let message)):
      return failure(code: CLIErrorCode.targetNotUnique, message: message)
    case .success(let resolved):
      target = resolved
    }
    guard let surfaceID = UUID(uuidString: target.paneID) else {
      return failure(code: CLIErrorCode.targetNotFound, message: "The pane identifier is invalid.")
    }

    let initial = conditionSnapshot(target)
    guard initial.agent != nil || condition == .exit else {
      return failure(code: CLIErrorCode.agentNotFound, message: "No detected agent is active in the selected pane.")
    }
    let baselineRevision = initial.revision
    let baselineSignal = initial.changedSignal
    let baselineState = normalizedState(initial)
    var stableState: String?
    var stableSinceMilliseconds = 0
    var elapsedMilliseconds = 0
    let timeoutMilliseconds = input.timeoutSeconds * 1_000
    let observationPump = AgentWaitObservationPump()
    observationPump.start(surfaceID: surfaceID, observe: observeCondition)
    defer { observationPump.cancel() }

    return await withTaskCancellationHandler {
      while elapsedMilliseconds <= timeoutMilliseconds {
        if Task.isCancelled {
          return failure(code: CLIErrorCode.timeout, message: "The wait was cancelled.")
        }
        let snapshot = conditionSnapshot(target)
        if let observation = exactMatch(
          condition: condition,
          snapshot: snapshot,
          baselineRevision: baselineRevision,
          baselineSignal: baselineSignal,
          minimumConfidence: input.minimumConfidence ?? .auto
        ) {
          return await conditionSuccess(
            condition: condition,
            waitedMilliseconds: elapsedMilliseconds,
            target: target,
            observation: observation,
            signals: snapshot.signals,
            includeScreenLines: input.includeScreenLines
          )
        }

        let state = normalizedState(snapshot)
        let heuristicEligible = allowsHeuristic(
          input.minimumConfidence ?? .auto,
          condition: condition,
          signals: snapshot.signals
        )
        let heuristicCandidate =
          heuristicEligible
          && heuristicMatches(
            condition: condition,
            snapshot: snapshot,
            normalizedState: state,
            baselineState: baselineState,
            baselineRevision: baselineRevision
          )
        if heuristicCandidate {
          if stableState != state {
            stableState = state
            stableSinceMilliseconds = elapsedMilliseconds
          } else if elapsedMilliseconds - stableSinceMilliseconds >= 2_000,
            let observation = heuristicObservation(snapshot, state: state)
          {
            return await conditionSuccess(
              condition: condition,
              waitedMilliseconds: elapsedMilliseconds,
              target: target,
              observation: observation,
              signals: snapshot.signals,
              includeScreenLines: input.includeScreenLines
            )
          }
        } else {
          stableState = nil
        }

        guard elapsedMilliseconds < timeoutMilliseconds else { break }
        do {
          try await clock.sleep(for: .milliseconds(200))
        } catch {
          return failure(code: CLIErrorCode.timeout, message: "The wait was cancelled.")
        }
        elapsedMilliseconds += 200
      }
      let last = conditionSnapshot(target)
      let details = AgentWaitErrorDetails.condition(
        AgentConditionWaitErrorDetails(
          condition: condition,
          waitedMilliseconds: min(elapsedMilliseconds, timeoutMilliseconds),
          target: TabTarget(from: target),
          observation: heuristicObservation(last, state: normalizedState(last)),
          signals: last.signals
        ))
      return failure(
        code: CLIErrorCode.waitTimeout,
        message: "Timed out waiting for the agent condition.",
        details: details
      )
    } onCancel: {
      observationPump.cancel()
    }
  }

  private func exactMatch(
    condition: AgentWaitCondition,
    snapshot: ConditionSnapshot,
    baselineRevision: UInt64,
    baselineSignal: AgentSignal?,
    minimumConfidence: AgentWaitMinimumConfidence
  ) -> AgentWaitObservation? {
    let signal = condition == .changed ? snapshot.changedSignal : snapshot.signal
    guard let signal,
      accepts(signal.confidence, minimum: minimumConfidence)
    else {
      if condition == .exit, !snapshot.isLive {
        return AgentWaitObservation(
          status: .done,
          rawState: "gone",
          source: "surface",
          confidence: "exact",
          timestamp: formatter.string(from: now()),
          revision: Int(clamping: snapshot.revision)
        )
      }
      return nil
    }
    let matches =
      switch condition {
      case .idle: signal.event == .turnEnded
      case .blocked: signal.event == .needsInput
      case .changed: snapshot.revision > baselineRevision && signal != baselineSignal
      case .exit: signal.event == .sessionEnd
      }
    guard matches else { return nil }
    return AgentWaitObservation(
      status: status(for: snapshot.agent, fallback: condition == .blocked ? .blocked : .done),
      rawState: snapshot.agent?.rawState.rawValue ?? "gone",
      source: signal.source.payloadName,
      confidence: signal.confidence.rawValue,
      timestamp: formatter.string(from: signal.timestamp),
      revision: Int(clamping: snapshot.revision)
    )
  }

  private func accepts(
    _ confidence: AgentSignal.Confidence,
    minimum: AgentWaitMinimumConfidence
  ) -> Bool {
    switch minimum {
    case .auto, .high: confidence == .exact || confidence == .high
    case .exact: confidence == .exact
    case .heuristic: true
    }
  }

  private func allowsHeuristic(
    _ minimum: AgentWaitMinimumConfidence,
    condition: AgentWaitCondition,
    signals: AgentSignalsPayload
  ) -> Bool {
    switch minimum {
    case .exact, .high:
      return false
    case .heuristic:
      return true
    case .auto:
      let coveredEvent: AgentSignalEvent =
        switch condition {
        case .idle: .turnEnded
        case .blocked: .needsInput
        case .exit: .sessionEnd
        case .changed: .progress
        }
      return !signals.channels.contains {
        $0.state == .verifiedLive && (condition == .changed || $0.events.contains(coveredEvent))
      }
    }
  }

  private func heuristicMatches(
    condition: AgentWaitCondition,
    snapshot: ConditionSnapshot,
    normalizedState: String,
    baselineState: String,
    baselineRevision: UInt64
  ) -> Bool {
    switch condition {
    case .idle:
      normalizedState == AgentsCommandStatus.idle.rawValue || normalizedState == AgentsCommandStatus.done.rawValue
    case .blocked: normalizedState == AgentsCommandStatus.blocked.rawValue
    case .changed: snapshot.revision > baselineRevision && normalizedState != baselineState
    case .exit: !snapshot.isLive || snapshot.agent == nil
    }
  }

  private func normalizedState(_ snapshot: ConditionSnapshot) -> String {
    guard snapshot.isLive else { return "gone" }
    return snapshot.agent.map { status(for: $0, fallback: .idle).rawValue } ?? "absent"
  }

  private func status(for agent: ActiveAgentEntry?, fallback: AgentsCommandStatus) -> AgentsCommandStatus {
    agent.flatMap { AgentsCommandStatus(rawValue: $0.displayState.rawValue) } ?? fallback
  }

  private func heuristicObservation(_ snapshot: ConditionSnapshot, state: String) -> AgentWaitObservation? {
    AgentWaitObservation(
      status: status(for: snapshot.agent, fallback: snapshot.isLive ? .idle : .done),
      rawState: snapshot.agent?.rawState.rawValue ?? state,
      source: "detection",
      confidence: "heuristic",
      timestamp: formatter.string(from: snapshot.agent?.lastChangedAt ?? now()),
      revision: Int(clamping: snapshot.revision)
    )
  }

  // Keeping the evidence fields explicit prevents a partial success payload.
  // swiftlint:disable:next function_parameter_count
  private func conditionSuccess(
    condition: AgentWaitCondition,
    waitedMilliseconds: Int,
    target: TabResolvedTarget,
    observation: AgentWaitObservation,
    signals: AgentSignalsPayload,
    includeScreenLines: Int?
  ) async -> CommandResponse {
    let payloadTarget = TabTarget(from: target)
    do {
      return try CommandResponse(
        ok: true,
        command: "agents.wait",
        schemaVersion: "prowl.cli.agents.wait.v1",
        data: RawJSON(
          encoding: AgentWaitCommandPayload.condition(
            AgentConditionWaitPayload(
              condition: condition,
              waitedMilliseconds: waitedMilliseconds,
              target: payloadTarget,
              observation: observation,
              signals: signals,
              screen: await stableScreen(requestedLines: includeScreenLines, target: payloadTarget)
            )))
      )
    } catch {
      return failure(code: CLIErrorCode.agentsFailed, message: "Failed to encode the wait result.")
    }
  }

  private func stableScreen(
    requestedLines: Int?,
    target: TabTarget
  ) async -> AgentWaitScreenPayload? {
    guard let requestedLines else { return nil }
    guard var lastText = screenProvider(target) else {
      return .unavailable(.init(requestedLines: requestedLines, waitedMilliseconds: 0))
    }
    var elapsedMilliseconds = 0
    var stableMilliseconds = 0
    while elapsedMilliseconds < 2_000, stableMilliseconds < 800 {
      do {
        try await clock.sleep(for: .milliseconds(200))
      } catch {
        break
      }
      elapsedMilliseconds += 200
      guard let nextText = screenProvider(target) else {
        return .unavailable(
          .init(requestedLines: requestedLines, waitedMilliseconds: elapsedMilliseconds))
      }
      if nextText == lastText {
        stableMilliseconds += 200
      } else {
        lastText = nextText
        stableMilliseconds = 0
      }
    }
    let lines = lastText.split(separator: "\n", omittingEmptySubsequences: false).suffix(requestedLines)
    return .captured(
      .init(
        requestedLines: requestedLines,
        waitedMilliseconds: elapsedMilliseconds,
        text: lines.joined(separator: "\n"),
        lineCount: lines.count,
        stabilized: stableMilliseconds >= 800
      ))
  }

  private func failure(
    code: String,
    message: String,
    details: AgentWaitErrorDetails? = nil
  ) -> CommandResponse {
    let encodedDetails: RawJSON?
    if let details {
      encodedDetails = try? RawJSON(encoding: details)
    } else {
      encodedDetails = nil
    }
    return CommandResponse(
      ok: false,
      command: "agents.wait",
      schemaVersion: "prowl.cli.agents.wait.v1",
      error: CommandError(code: code, message: message, details: encodedDetails ?? nil)
    )
  }
}

extension AgentSignalsPayload {
  static var empty: Self { AgentSignalsPayload(channels: [], last: nil, lastBinding: nil) }
}

private nonisolated final class LatestDispatchSnapshot: @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: AgentDispatchSnapshot?

  var value: AgentDispatchSnapshot? { lock.withLock { snapshot } }

  func set(_ snapshot: AgentDispatchSnapshot) {
    lock.withLock { self.snapshot = snapshot }
  }
}

/// Single-consumer cursor. `waitForDispatch` awaits the initial read before transferring
/// the cursor to exactly one task-group child, so reads never overlap.
private nonisolated final class AgentDispatchObservationCursor: @unchecked Sendable {
  private var iterator: AgentDispatchObservationStream.Iterator

  init(stream: AgentDispatchObservationStream) {
    self.iterator = stream.makeAsyncIterator()
  }

  func next() async -> AgentDispatchObservation? {
    var iterator = self.iterator
    let event = await iterator.next()
    self.iterator = iterator
    return event
  }
}

private nonisolated final class AgentWaitObservationPump: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Void, Never>?

  @MainActor
  func start(
    surfaceID: UUID,
    observe: @escaping AgentWaitCommandHandler.ObserveCondition
  ) {
    let task = Task { @MainActor in
      while !Task.isCancelled {
        do {
          for try await event in observe(surfaceID) {
            if Task.isCancelled { return }
            if case .surfaceClosed = event { return }
          }
          return
        } catch AgentObservationError.bufferOverflow {
          continue
        } catch {
          return
        }
      }
    }
    lock.withLock { self.task = task }
  }

  func cancel() {
    let task = lock.withLock { () -> Task<Void, Never>? in
      defer { self.task = nil }
      return self.task
    }
    task?.cancel()
  }
}
