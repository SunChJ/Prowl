import Clocks
import Foundation
import Testing

@testable import supacode

@MainActor
struct AgentWaitCommandHandlerTests {
  @Test func succeededDispatchReturnsReceiptAndFailedReceiptIsStructuredError() async throws {
    let succeeded = snapshot(
      .completed(
        id: "d1", outcome: .succeeded, summary: "Done", createdAt: Self.start, completedAt: Self.start))
    let successHandler = handler(dispatchSnapshot: succeeded)
    let success = await successHandler.handle(envelope: waitDispatch("d1"))
    #expect(success.ok)
    let payload = try #require(success.data).decode(as: AgentWaitCommandPayload.self)
    guard case .dispatch(let dispatch) = payload else {
      Issue.record("Expected dispatch payload")
      return
    }
    #expect(dispatch.receipt.summary == "Done")
    #expect(dispatch.target == succeeded.binding?.target)

    let failed = snapshot(
      .completed(
        id: "d2", outcome: .failed, summary: "Tests failed", createdAt: Self.start, completedAt: Self.start))
    let failure = await handler(dispatchSnapshot: failed).handle(envelope: waitDispatch("d2"))
    #expect(failure.error?.code == CLIErrorCode.dispatchFailed)
    let details = try #require(failure.error?.details).decode(as: AgentWaitErrorDetails.self)
    guard case .dispatch(let dispatchDetails) = details else {
      Issue.record("Expected dispatch error details")
      return
    }
    #expect(dispatchDetails.record.state == .completed)
  }

  @Test func dispatchNeedsInputAndIncompleteNeverBecomeSuccess() async {
    let pending = snapshot(.pending(id: "d1", createdAt: Self.start))
    for (event, code) in [
      (AgentDispatchObservation.needsInput(pending), CLIErrorCode.dispatchNeedsInput),
      (.incomplete(pending), CLIErrorCode.dispatchIncomplete),
    ] {
      let handler = AgentWaitCommandHandler(
        observeDispatch: { _ in
          .success(
            AgentDispatchObservationStream { continuation in
              continuation.yield(event)
            })
        }
      )
      let response = await handler.handle(envelope: waitDispatch("d1"))
      #expect(!response.ok)
      #expect(response.error?.code == code)
    }
  }

  @Test func exactConditionSignalCanResolveInitialSnapshotButChangedCannot() async throws {
    let target = resolvedTarget()
    let entry = agentEntry(surfaceID: UUID(uuidString: target.paneID)!, status: .idle)
    let signal = AgentSignal(
      kind: .turnEnded,
      source: .cooperativeCLI,
      confidence: .exact,
      timestamp: Self.start,
      sessionID: nil,
      detail: nil,
      claimedOrigin: nil
    )
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in .failure(.notFound) },
      resolveConditionTarget: { _ in .success(target) },
      conditionSnapshot: { _ in
        .init(agent: entry, signal: signal, revision: 2, isLive: true, signals: .empty)
      }
    )
    let response = await handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .agentsWait(
          AgentWaitInput(mode: .condition, pane: target.paneID, condition: .idle, timeoutSeconds: 1)
        )
      )
    )
    #expect(response.ok)
    let payload = try #require(response.data).decode(as: AgentWaitCommandPayload.self)
    guard case .condition(let condition) = payload else {
      Issue.record("Expected condition payload")
      return
    }
    #expect(condition.observation.confidence == "exact")
    #expect(condition.observation.source == "cooperative_cli")
  }

  @Test func changedExactRejectsHeuristicRevisionWithoutANewSignal() async {
    let clock = TestClock()
    let target = resolvedTarget()
    let surfaceID = UUID(uuidString: target.paneID)!
    let idle = agentEntry(surfaceID: surfaceID, status: .idle)
    let working = agentEntry(surfaceID: surfaceID, status: .working)
    let staleSignal = AgentSignal(
      kind: .turnEnded,
      source: .cooperativeCLI,
      confidence: .exact,
      timestamp: Self.start,
      sessionID: nil,
      detail: nil,
      claimedOrigin: nil
    )
    var snapshotReads = 0
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in .failure(.notFound) },
      resolveConditionTarget: { _ in .success(target) },
      conditionSnapshot: { _ in
        snapshotReads += 1
        let didChangeHeuristically = snapshotReads > 2
        return .init(
          agent: didChangeHeuristically ? working : idle,
          signal: staleSignal,
          revision: didChangeHeuristically ? 2 : 1,
          isLive: true,
          signals: .empty
        )
      },
      clock: clock,
      now: { Self.start }
    )
    let task = Task {
      await handler.handle(
        envelope: CommandEnvelope(
          output: .json,
          command: .agentsWait(
            .init(
              mode: .condition,
              pane: target.paneID,
              condition: .changed,
              timeoutSeconds: 1,
              minimumConfidence: .exact
            )
          )
        ))
    }

    for _ in 0..<5 {
      await Task.yield()
      await clock.advance(by: .milliseconds(200))
    }
    let response = await task.value
    #expect(response.error?.code == CLIErrorCode.waitTimeout)
  }

  @Test func heuristicIdleRequiresTwoSecondsOfUnchangedState() async throws {
    let clock = TestClock()
    let target = resolvedTarget()
    let entry = agentEntry(surfaceID: UUID(uuidString: target.paneID)!, status: .idle)
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in .failure(.notFound) },
      resolveConditionTarget: { _ in .success(target) },
      conditionSnapshot: { _ in
        .init(agent: entry, signal: nil, revision: 1, isLive: true, signals: .empty)
      },
      clock: clock,
      now: { Self.start }
    )
    let task = Task {
      await handler.handle(
        envelope: CommandEnvelope(
          output: .json,
          command: .agentsWait(
            .init(mode: .condition, pane: target.paneID, condition: .idle, timeoutSeconds: 3)
          )
        ))
    }
    for _ in 0..<9 {
      await Task.yield()
      await clock.advance(by: .milliseconds(200))
    }
    #expect(!task.isCancelled)
    await Task.yield()
    await clock.advance(by: .milliseconds(200))
    let response = await task.value
    let payload = try #require(response.data).decode(as: AgentWaitCommandPayload.self)
    guard case .condition(let condition) = payload else {
      Issue.record("Expected condition payload")
      return
    }
    #expect(condition.waitedMilliseconds == 2_000)
    #expect(condition.observation.confidence == "heuristic")
  }

  @Test func requestedScreenWaitsForEightHundredMillisecondsOfStability() async throws {
    let clock = TestClock()
    let completed = snapshot(
      .completed(
        id: "d1", outcome: .succeeded, summary: "Done", createdAt: Self.start, completedAt: Self.start))
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in
        .success(
          AgentDispatchObservationStream { continuation in
            continuation.yield(.snapshot(completed))
            continuation.finish()
          })
      },
      screenProvider: { _ in "one\ntwo\nthree" },
      clock: clock,
      now: { Self.start }
    )
    let task = Task {
      await handler.handle(
        envelope: CommandEnvelope(
          output: .json,
          command: .agentsWait(
            .init(mode: .dispatch, dispatchID: "d1", timeoutSeconds: 1, includeScreenLines: 2)
          )
        ))
    }
    for _ in 0..<4 {
      await Task.yield()
      await clock.advance(by: .milliseconds(200))
    }
    let response = await task.value
    let payload = try #require(response.data).decode(as: AgentWaitCommandPayload.self)
    guard case .dispatch(let dispatch) = payload else {
      Issue.record("Expected dispatch payload")
      return
    }
    let screenPayload = try #require(dispatch.screen)
    guard case .captured(let screen) = screenPayload else {
      Issue.record("Expected captured screen")
      return
    }
    #expect(screen.waitedMilliseconds == 800)
    #expect(screen.text == "two\nthree")
    #expect(screen.stabilized)
  }

  @Test func cancellingGenericWaitRemovesObservationSubscriber() async {
    let clock = TestClock()
    let target = resolvedTarget()
    let surfaceID = UUID(uuidString: target.paneID)!
    let store = AgentObservationStore(bufferCapacity: 8)
    let entry = agentEntry(surfaceID: surfaceID, status: .working)
    store.publishAgentChanged(entry)
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in .failure(.notFound) },
      observeCondition: { store.observe(surfaceID: $0, isLive: true) },
      resolveConditionTarget: { _ in .success(target) },
      conditionSnapshot: { _ in
        .init(
          agent: entry,
          signal: nil,
          revision: store.snapshot(surfaceID: surfaceID)?.revision ?? 0,
          isLive: true,
          signals: .empty
        )
      },
      clock: clock,
      now: { Self.start }
    )
    let task = Task {
      await handler.handle(
        envelope: CommandEnvelope(
          output: .json,
          command: .agentsWait(
            .init(mode: .condition, pane: target.paneID, condition: .blocked, timeoutSeconds: 600)
          )
        ))
    }

    for _ in 0..<10 where store.subscriberCount(surfaceID: surfaceID) == 0 {
      await Task.yield()
    }
    #expect(store.subscriberCount(surfaceID: surfaceID) == 1)
    task.cancel()
    _ = await task.value
    for _ in 0..<10 where store.subscriberCount(surfaceID: surfaceID) != 0 {
      await Task.yield()
    }
    #expect(store.subscriberCount(surfaceID: surfaceID) == 0)
  }

  @Test func genericWaitResubscribesAfterObservationOverflow() async {
    let clock = TestClock()
    let target = resolvedTarget()
    let entry = agentEntry(surfaceID: UUID(uuidString: target.paneID)!, status: .working)
    var subscriptionCount = 0
    let handler = AgentWaitCommandHandler(
      observeDispatch: { _ in .failure(.notFound) },
      observeCondition: { _ in
        subscriptionCount += 1
        if subscriptionCount == 1 {
          return AgentObservationStream { continuation in
            continuation.finish(throwing: AgentObservationError.bufferOverflow)
          }
        }
        return AgentObservationStream { _ in }
      },
      resolveConditionTarget: { _ in .success(target) },
      conditionSnapshot: { _ in
        .init(agent: entry, signal: nil, revision: 1, isLive: true, signals: .empty)
      },
      clock: clock,
      now: { Self.start }
    )
    let task = Task {
      await handler.handle(
        envelope: CommandEnvelope(
          output: .json,
          command: .agentsWait(
            .init(mode: .condition, pane: target.paneID, condition: .blocked, timeoutSeconds: 600)
          )
        ))
    }

    for _ in 0..<10 where subscriptionCount < 2 {
      await Task.yield()
    }
    #expect(subscriptionCount == 2)
    task.cancel()
    _ = await task.value
  }

  private static let start = Date(timeIntervalSince1970: 1_000)

  private func handler(dispatchSnapshot: AgentDispatchSnapshot) -> AgentWaitCommandHandler {
    AgentWaitCommandHandler(
      observeDispatch: { _ in
        .success(
          AgentDispatchObservationStream { continuation in
            continuation.yield(.snapshot(dispatchSnapshot))
            continuation.finish()
          })
      },
      clock: TestClock(),
      now: { Self.start }
    )
  }

  private func waitDispatch(_ id: String) -> CommandEnvelope {
    CommandEnvelope(
      output: .json,
      command: .agentsWait(AgentWaitInput(mode: .dispatch, dispatchID: id, timeoutSeconds: 1))
    )
  }

  private func snapshot(_ record: AgentDispatchRecord) -> AgentDispatchSnapshot {
    AgentDispatchSnapshot(
      record: record,
      binding: AgentDispatchBinding(
        surfaceID: UUID(),
        target: target(),
        evidenceEpoch: UUID()
      )
    )
  }

  private func target() -> TabTarget {
    TabTarget(
      worktree: .init(id: "w1", name: "App", path: "/App", rootPath: "/App", kind: "worktree"),
      tab: .init(id: "t1", title: "Agent", selected: true),
      pane: .init(id: UUID().uuidString, title: "Agent", cwd: "/App", focused: true)
    )
  }

  private func resolvedTarget() -> TabResolvedTarget {
    let value = target()
    return TabResolvedTarget(
      worktreeID: value.worktree.id,
      worktreeName: value.worktree.name,
      worktreePath: value.worktree.path,
      worktreeRootPath: value.worktree.rootPath,
      worktreeKind: value.worktree.kind,
      tabID: value.tab.id,
      tabTitle: value.tab.title,
      tabSelected: value.tab.selected,
      paneID: value.pane.id,
      paneTitle: value.pane.title,
      paneCWD: value.pane.cwd,
      paneFocused: value.pane.focused
    )
  }

  private func agentEntry(surfaceID: UUID, status: AgentDisplayState) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: surfaceID,
      worktreeID: "w1",
      worktreeName: "App",
      workingDirectory: URL(fileURLWithPath: "/App"),
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: "Agent",
      surfaceID: surfaceID,
      paneIndex: 0,
      iconLookupToken: "codex",
      agent: .codex,
      rawState: status == .idle ? .idle : .working,
      displayState: status,
      lastChangedAt: Self.start
    )
  }
}
