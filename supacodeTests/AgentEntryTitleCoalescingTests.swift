import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import supacode

/// Agent TUIs animate a spinner glyph inside the terminal title (`⠦ spx-h` →
/// `⠧ spx-h`) at roughly 10 Hz. Each frame reaches `emitAgentEntry` as a new
/// `ActiveAgentEntry`, and forwarding all of them mutates the Active Agents
/// state — and dirties the SwiftUI graph — for a change no one perceives.
/// `emitAgentEntry` must space title-only emissions out while still forwarding
/// real state changes immediately.
@MainActor
struct AgentEntryTitleCoalescingTests {
  private let start = Date(timeIntervalSince1970: 1_000)

  @Test func spinnerFramesWithinTheIntervalAreCoalesced() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }
    let working = PaneAgentState(detectedAgent: .claude, state: .working)

    fixture.emit(working, at: start)
    // Four spinner frames over 400 ms, as a real agent would produce.
    for frame in ["⠦ spx-h", "⠧ spx-h", "⠇ spx-h", "⠏ spx-h"].enumerated() {
      fixture.setTitle(frame.element)
      fixture.emit(working, at: start.addingTimeInterval(0.1 * Double(frame.offset + 1)))
    }

    #expect(received.count == 1, "Only the initial emission should reach the consumer")
  }

  @Test func aTitleChangeEmitsOnceTheIntervalElapses() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }
    let working = PaneAgentState(detectedAgent: .claude, state: .working)

    fixture.emit(working, at: start)
    fixture.setTitle("⠦ spx-h")
    fixture.emit(working, at: start.addingTimeInterval(0.5))
    // Past the interval, so the newest title is forwarded.
    fixture.setTitle("⠧ spx-h")
    fixture.emit(working, at: start.addingTimeInterval(1.5))

    #expect(received.count == 2)
    // The suppressed frame is never recorded, so the emission that follows
    // carries the title as of that moment rather than the stale frame.
    #expect(received.last?.paneTitle == "⠧ spx-h")
  }

  @Test func aVisibleStateChangeEmitsImmediatelyDespiteTheInterval() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    fixture.emit(PaneAgentState(detectedAgent: .claude, state: .working), at: start)
    // Well inside the coalescing window, but `displayState` is user-visible and
    // must never be delayed.
    fixture.setTitle("⠧ spx-h")
    fixture.emit(PaneAgentState(detectedAgent: .claude, state: .blocked), at: start.addingTimeInterval(0.05))

    #expect(received.map(\.displayState) == [.working, .blocked])
    #expect(received.last?.paneTitle == "⠧ spx-h", "The pending title rides along on the real change")
  }

  @Test func identicalTitlesNeverEmitEvenAfterTheInterval() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }
    let working = PaneAgentState(detectedAgent: .claude, state: .working)

    fixture.emit(working, at: start)
    fixture.emit(working, at: start.addingTimeInterval(5))
    fixture.emit(working, at: start.addingTimeInterval(10))

    #expect(received.count == 1, "Coalescing must not turn into a periodic re-emit")
  }

  @Test func aSettledTitleIsFlushedByTheNextPoll() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }
    let working = PaneAgentState(detectedAgent: .claude, state: .working)

    fixture.emit(working, at: start)
    // The spinner's final frame is suppressed, then the agent stops animating,
    // so no further title change will ever arrive to carry it.
    fixture.setTitle("spx-h")
    fixture.emit(working, at: start.addingTimeInterval(0.2))
    #expect(received.count == 1)

    // A poll inside the window must not release it early.
    fixture.flush(at: start.addingTimeInterval(0.5))
    #expect(received.count == 1)

    fixture.flush(at: start.addingTimeInterval(1.2))
    #expect(received.count == 2)
    #expect(received.last?.paneTitle == "spx-h")

    // Nothing is left pending, so later polls stay quiet.
    fixture.flush(at: start.addingTimeInterval(5))
    #expect(received.count == 2)
  }

  @Test func comparisonIgnoresOnlyRawStateAndPaneTitle() {
    let base = makeEntry(paneTitle: "⠦ spx-h", rawState: .working, displayState: .working)
    let spinnerMoved = makeEntry(paneTitle: "⠧ spx-h", rawState: .idle, displayState: .working)
    let stateMoved = makeEntry(paneTitle: "⠦ spx-h", rawState: .working, displayState: .blocked)

    #expect(base.equalsIgnoringRawStateAndPaneTitle(spinnerMoved))
    #expect(!base.equalsIgnoringRawStateAndPaneTitle(stateMoved))
    // The narrower comparison still treats a title move as a difference.
    #expect(!base.equalsIgnoringRawState(spinnerMoved))
  }

  private func makeEntry(
    paneTitle: String,
    rawState: AgentRawState,
    displayState: AgentDisplayState
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: Self.entryID,
      worktreeID: "/tmp/repo/worktree",
      worktreeName: "worktree",
      workingDirectory: nil,
      tabID: Self.entryTabID,
      paneTitle: paneTitle,
      surfaceID: Self.entryID,
      paneIndex: 1,
      iconLookupToken: "claude",
      agent: .claude,
      session: nil,
      rawState: rawState,
      displayState: displayState,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private static let entryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
  /// Shared so two entries under comparison differ only in the field under test.
  private static let entryTabID = TerminalTabID()

  private struct Fixture {
    let state: WorktreeTerminalState
    let tabId: TerminalTabID
    let pane: GhosttySurfaceView

    func setTitle(_ title: String) {
      state.tabManager.updateTitle(tabId, title: title)
    }

    func emit(_ paneState: PaneAgentState, at now: Date) {
      state.emitAgentEntry(surfaceID: pane.id, tabId: tabId, state: paneState, now: now)
    }

    /// Stands in for one turn of the detection poll, which drives the flush.
    func flush(at now: Date) {
      state.flushPendingAgentEntry(surfaceID: pane.id, now: now)
    }
  }

  private func makeFixture() -> Fixture {
    let state = WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/worktree",
        name: "worktree",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/worktree"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    let pane = GhosttySurfaceView(
      runtime: state.runtime,
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/worktree", isDirectory: true),
      fontSize: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    let tabId = state.tabManager.createTab(title: "worktree 1", icon: "terminal")
    state.surfaces[pane.id] = pane
    state.trees[tabId] = SplitTree<GhosttySurfaceView>(view: pane)
    state.focusedSurfaceIdByTab[tabId] = pane.id
    return Fixture(state: state, tabId: tabId, pane: pane)
  }
}
