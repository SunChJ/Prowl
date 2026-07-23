import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import supacode

/// `detectAgentState` re-emits on any `PaneAgentState` change, including
/// internal bookkeeping churn (raw-state oscillation, session miss streaks).
/// `emitAgentEntry` must forward only consumer-visible `ActiveAgentEntry`
/// changes so that churn never floods the terminal event stream.
@MainActor
struct AgentEntryEmissionDedupTests {
  @Test func rawStateAndBookkeepingChangesDoNotReEmit() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    // Same visible entry; only rawState (fallbackState) and internal bookkeeping
    // differ across the three emits.
    var paneState = PaneAgentState(detectedAgent: .claude, fallbackState: .working, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)
    paneState.sessionMissStreak = 1
    paneState.fallbackState = .idle
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)
    paneState.sessionMissStreak = 2
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: paneState)

    // rawState never renders in the sidebar, so a raw-only flicker must not
    // re-emit; only the first (visible) entry is forwarded.
    #expect(received.count == 1)
    #expect(received.map(\.rawState) == [.working])
  }

  @Test func visibleChangeStillEmits() {
    let fixture = makeFixture()
    var received: [ActiveAgentEntry] = []
    fixture.state.onAgentEntryChanged = { received.append($0) }

    let working = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)
    let idle = PaneAgentState(detectedAgent: .claude, state: .idle)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: idle)

    #expect(received.map(\.displayState) == [.working, .idle])
  }

  @Test func removalClearsTheCacheSoReattachEmits() {
    let fixture = makeFixture()
    var changed: [ActiveAgentEntry] = []
    var removed: [UUID] = []
    fixture.state.onAgentEntryChanged = { changed.append($0) }
    fixture.state.onAgentEntryRemoved = { removed.append($0) }

    let working = PaneAgentState(detectedAgent: .claude, state: .working)
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)
    // Agent went away (no detected agent -> no entry).
    fixture.state.emitAgentEntry(
      surfaceID: fixture.pane.id,
      tabId: fixture.tabId,
      state: PaneAgentState()
    )
    // Same agent comes back with the same visible entry: must emit again.
    fixture.state.emitAgentEntry(surfaceID: fixture.pane.id, tabId: fixture.tabId, state: working)

    #expect(changed.count == 2)
    #expect(removed == [fixture.pane.id])
  }

  private struct Fixture {
    let state: WorktreeTerminalState
    let tabId: TerminalTabID
    let pane: GhosttySurfaceView
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
