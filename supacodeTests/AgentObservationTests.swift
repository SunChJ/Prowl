import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct AgentObservationTests {
  @Test func liveShellStartsWithAtomicEmptySnapshotAndReplaysLatestSignal() async throws {
    let fixture = makeFixture()
    let firstStream = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID)
    var firstIterator = firstStream.makeAsyncIterator()

    let first = try await firstIterator.next()
    guard case .snapshot(let initial) = first else {
      Issue.record("Expected snapshot first")
      return
    }
    #expect(initial.agent == nil)
    #expect(initial.latestSignal == nil)
    #expect(initial.revision == 0)

    let signal = makeSignal()
    #expect(fixture.manager.recordAgentSignal(signal, surfaceID: fixture.surfaceID))
    #expect(try await firstIterator.next() == .signal(signal))

    let secondStream = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID)
    var secondIterator = secondStream.makeAsyncIterator()
    guard case .snapshot(let replay) = try await secondIterator.next() else {
      Issue.record("Expected replay snapshot first")
      return
    }
    #expect(replay.agent == nil)
    #expect(replay.latestSignal == signal)
    #expect(replay.revision == 1)
  }

  @Test func signalIsMulticastToIndependentSubscribers() async throws {
    let fixture = makeFixture()
    var first = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    var second = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    _ = try await first.next()
    _ = try await second.next()

    let signal = makeSignal(detail: "Review complete")
    #expect(fixture.manager.recordAgentSignal(signal, surfaceID: fixture.surfaceID))

    #expect(try await first.next() == .signal(signal))
    #expect(try await second.next() == .signal(signal))
  }

  @Test func publishedAgentRemovalPrecedesSurfaceClosureAndFinishesStream() async throws {
    let fixture = makeFixture()
    var iterator = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    _ = try await iterator.next()

    fixture.state.emitAgentEntry(
      surfaceID: fixture.surfaceID,
      tabId: fixture.tabID,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )
    guard case .changed(let entry) = try await iterator.next() else {
      Issue.record("Expected changed event")
      return
    }
    #expect(entry.surfaceID == fixture.surfaceID)

    #expect(fixture.state.closeSurface(id: fixture.surfaceID, confirmation: .skip))
    #expect(try await iterator.next() == .removed)
    #expect(try await iterator.next() == .surfaceClosed)
    #expect(try await iterator.next() == nil)
  }

  @Test func shellWithoutPublishedAgentClosesWithoutFalseRemoval() async throws {
    let fixture = makeFixture()
    fixture.state.wakeAgentDetection(forSurfaceID: fixture.surfaceID)
    var iterator = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    _ = try await iterator.next()

    #expect(fixture.state.closeSurface(id: fixture.surfaceID, confirmation: .skip))
    #expect(try await iterator.next() == .surfaceClosed)
    #expect(try await iterator.next() == nil)
  }

  @Test func agentRemovalDoesNotCloseObserverAndLaterSignalStillArrives() async throws {
    let fixture = makeFixture()
    var iterator = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    _ = try await iterator.next()
    fixture.state.emitAgentEntry(
      surfaceID: fixture.surfaceID,
      tabId: fixture.tabID,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )
    _ = try await iterator.next()

    fixture.state.emitAgentEntry(
      surfaceID: fixture.surfaceID,
      tabId: fixture.tabID,
      state: PaneAgentState()
    )
    #expect(try await iterator.next() == .removed)

    let signal = makeSignal()
    #expect(fixture.manager.recordAgentSignal(signal, surfaceID: fixture.surfaceID))
    #expect(try await iterator.next() == .signal(signal))
  }

  @Test func closeAllAndPruneFinishEverySurfaceObserver() async throws {
    let closeAllFixture = makeFixture()
    var closeAllIterator = closeAllFixture.manager
      .observeAgentState(surfaceID: closeAllFixture.surfaceID)
      .makeAsyncIterator()
    _ = try await closeAllIterator.next()
    closeAllFixture.state.emitAgentEntry(
      surfaceID: closeAllFixture.surfaceID,
      tabId: closeAllFixture.tabID,
      state: PaneAgentState(detectedAgent: .claude, state: .working)
    )
    guard case .changed = try await closeAllIterator.next() else {
      Issue.record("Expected published agent before close-all")
      return
    }

    closeAllFixture.state.closeAllSurfaces()
    #expect(try await closeAllIterator.next() == .removed)
    #expect(try await closeAllIterator.next() == .surfaceClosed)
    #expect(try await closeAllIterator.next() == nil)

    let pruneFixture = makeFixture()
    var pruneIterator = pruneFixture.manager
      .observeAgentState(surfaceID: pruneFixture.surfaceID)
      .makeAsyncIterator()
    _ = try await pruneIterator.next()
    pruneFixture.state.emitAgentEntry(
      surfaceID: pruneFixture.surfaceID,
      tabId: pruneFixture.tabID,
      state: PaneAgentState(detectedAgent: .codex, state: .working)
    )
    guard case .changed = try await pruneIterator.next() else {
      Issue.record("Expected published agent before prune")
      return
    }

    pruneFixture.manager.prune(keeping: [])
    #expect(try await pruneIterator.next() == .removed)
    #expect(try await pruneIterator.next() == .surfaceClosed)
    #expect(try await pruneIterator.next() == nil)
  }

  @Test func cancellationRemovesOnlyTheCancelledSubscriber() async throws {
    let fixture = makeFixture()
    let firstStream = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID)
    let secondStream = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID)
    #expect(fixture.manager.agentObservationSubscriberCount(surfaceID: fixture.surfaceID) == 2)

    let task = Task {
      for try await _ in firstStream {}
    }
    await Task.yield()
    task.cancel()
    _ = await task.result
    for _ in 0..<10 where fixture.manager.agentObservationSubscriberCount(surfaceID: fixture.surfaceID) == 2 {
      await Task.yield()
    }

    #expect(fixture.manager.agentObservationSubscriberCount(surfaceID: fixture.surfaceID) == 1)
    var secondIterator = secondStream.makeAsyncIterator()
    _ = try await secondIterator.next()
    let signal = makeSignal()
    #expect(fixture.manager.recordAgentSignal(signal, surfaceID: fixture.surfaceID))
    #expect(try await secondIterator.next() == .signal(signal))
  }

  @Test func closedSurfaceProducesSnapshotThenSurfaceClosed() async throws {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    var iterator = manager.observeAgentState(surfaceID: UUID()).makeAsyncIterator()

    guard case .snapshot(let snapshot) = try await iterator.next() else {
      Issue.record("Expected snapshot first")
      return
    }
    #expect(snapshot.agent == nil)
    #expect(snapshot.latestSignal == nil)
    #expect(try await iterator.next() == .surfaceClosed)
    #expect(try await iterator.next() == nil)
  }

  @Test func boundedOverflowIsExplicitAndRecoverableByResubscription() async throws {
    let fixture = makeFixture(bufferCapacity: 1)
    let stream = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID)
    let signal = makeSignal()

    // Leave the initial snapshot buffered so the next critical event overflows.
    #expect(fixture.manager.recordAgentSignal(signal, surfaceID: fixture.surfaceID))

    var iterator = stream.makeAsyncIterator()
    guard case .snapshot = try await iterator.next() else {
      Issue.record("Expected the protected initial snapshot")
      return
    }
    do {
      _ = try await iterator.next()
      Issue.record("Expected explicit buffer overflow")
    } catch let error as AgentObservationError {
      #expect(error == .bufferOverflow)
    }

    var replacement = fixture.manager.observeAgentState(surfaceID: fixture.surfaceID).makeAsyncIterator()
    guard case .snapshot(let snapshot) = try await replacement.next() else {
      Issue.record("Expected resubscription snapshot")
      return
    }
    #expect(snapshot.latestSignal == signal)
  }

  private struct Fixture {
    let manager: WorktreeTerminalManager
    let state: WorktreeTerminalState
    let tabID: TerminalTabID
    let surfaceID: UUID
  }

  private func makeFixture(bufferCapacity: Int = 64) -> Fixture {
    let manager = WorktreeTerminalManager(
      runtime: GhosttyRuntime(),
      agentObservationBufferCapacity: bufferCapacity
    )
    let worktree = Worktree(
      id: "/tmp/agent-observation",
      name: "agent-observation",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/agent-observation"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/agent-observation")
    )
    let state = manager.state(for: worktree)
    let tabID = state.createTab()!
    let surfaceID = state.focusedSurfaceId(in: tabID)!
    return Fixture(manager: manager, state: state, tabID: tabID, surfaceID: surfaceID)
  }

  private func makeSignal(detail: String? = nil) -> AgentSignal {
    AgentSignal(
      kind: .turnEnded,
      source: .cooperativeCLI,
      confidence: .exact,
      timestamp: Date(timeIntervalSince1970: 1_000),
      sessionID: "session-1",
      detail: detail,
      claimedOrigin: nil
    )
  }
}
