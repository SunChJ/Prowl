import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct ActiveAgentsFeatureTests {
  @Test func entriesKeepInsertionOrder() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    let old = Date(timeIntervalSince1970: 10)
    let new = Date(timeIntervalSince1970: 20)
    let idle = entry(id: UUID(0), state: .idle, changedAt: new)
    let blocked = entry(id: UUID(1), state: .blocked, changedAt: old)
    let working = entry(id: UUID(2), state: .working, changedAt: new)
    let done = entry(id: UUID(3), state: .done, changedAt: new)
    let updatedIdle = entry(id: UUID(0), state: .blocked, changedAt: Date(timeIntervalSince1970: 30))

    await store.send(.agentEntryChanged(idle, autoShowPanel: false)) {
      $0.entries = [idle]
    }
    await store.send(.agentEntryChanged(blocked, autoShowPanel: false)) {
      $0.entries = [idle, blocked]
    }
    await store.send(.agentEntryChanged(working, autoShowPanel: false)) {
      $0.entries = [idle, blocked, working]
    }
    await store.send(.agentEntryChanged(done, autoShowPanel: false)) {
      $0.entries = [idle, blocked, working, done]
    }
    await store.send(.agentEntryChanged(updatedIdle, autoShowPanel: false)) {
      $0.entries = [updatedIdle, blocked, working, done]
    }
  }

  @Test func autoShowRevealsHiddenPanelOnAgentEntry() async {
    let state = ActiveAgentsFeature.State()
    state.$isPanelHidden.withLock { $0 = true }
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }
    let agent = entry(id: UUID(0), state: .working, changedAt: Date(timeIntervalSince1970: 10))

    await store.send(.agentEntryChanged(agent, autoShowPanel: true)) {
      $0.entries = [agent]
      $0.$isPanelHidden.withLock { $0 = false }
    }
  }

  @Test func panelHeightIsClamped() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.panelHeightChanged(20)) {
      $0.$panelHeight.withLock { $0 = 120 }
    }
    await store.send(.panelHeightChanged(900)) {
      $0.$panelHeight.withLock { $0 = 560 }
    }
  }

  @Test func maximumPanelHeightKeepsRepositoryListVisible() {
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 900) == 560)
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 500) == 300)
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 250) == 120)
  }

  @Test func rowDisplayUsesDetectedCommandTokenBeforeAgentFallback() {
    let ompEntry = entry(
      id: UUID(0),
      state: .idle,
      changedAt: Date(timeIntervalSince1970: 10),
      agent: .pi,
      iconLookupToken: "omp"
    )
    #expect(ompEntry.iconSource?.assetName == "OMP")
    #expect(ompEntry.displayName == "omp")

    let fallbackEntry = entry(
      id: UUID(1),
      state: .idle,
      changedAt: Date(timeIntervalSince1970: 10),
      agent: .pi,
      iconLookupToken: "unknown-wrapper"
    )
    #expect(fallbackEntry.iconSource?.assetName == "Pi")
    #expect(fallbackEntry.displayName == "pi")

    let cursorEntry = entry(
      id: UUID(2),
      state: .idle,
      changedAt: Date(timeIntervalSince1970: 10),
      agent: .cursor,
      iconLookupToken: "agent"
    )
    #expect(cursorEntry.displayName == "cursor")
  }

  @Test func sharedDisplayNamePolicyDrivesCapsuleNaming() {
    // The toolbar Agents capsule feeds `paneState.iconLookupToken ?? agent.iconLookupToken`
    // through this policy, so it must agree with the panel rows for every alias.
    // Launch aliases with their own icon token keep their name…
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "omp", agent: .pi) == "omp")
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "oh-my-pi", agent: .pi) == "oh-my-pi")
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "cursor-agent", agent: .cursor) == "cursor-agent")
    // …tokens without an icon entry and the generic `agent` entrypoint fall
    // back to the semantic agent name.
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "omx", agent: .codex) == "codex")
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "agent", agent: .cursor) == "cursor")
    #expect(ActiveAgentEntry.displayName(iconLookupToken: "", agent: .claude) == "claude")
    // No pane token at all: the agent names itself.
    #expect(
      ActiveAgentEntry.displayName(iconLookupToken: DetectedAgent.pi.iconLookupToken, agent: .pi) == "pi"
    )
  }

  @Test func navigationReturnsNilForEmptyList() {
    let entries: IdentifiedArrayOf<ActiveAgentEntry> = []
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .next, in: entries) == nil)
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .previous, in: entries) == nil)
  }

  @Test func navigationWithoutAnchorStartsFromEdges() {
    let entries = sampleEntries()
    // No focus, or focus on a surface that is not in the list, anchors on an edge.
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .previous, in: entries) == UUID(2))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(99), direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(99), direction: .previous, in: entries) == UUID(2))
  }

  @Test func navigationStepsAndWrapsAroundAnchor() {
    let entries = sampleEntries()
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(0), direction: .next, in: entries) == UUID(1))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(2), direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(1), direction: .previous, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(0), direction: .previous, in: entries) == UUID(2))
  }

  @Test func selectNextEntryAdvancesAnchorAndTapsNeighbour() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    state.focusedSurfaceID = UUID(0)
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    await store.send(.selectNextEntry) {
      $0.focusedSurfaceID = UUID(1)
    }
    await store.receive(.entryTapped(UUID(1)))
  }

  @Test func selectPreviousEntryWrapsToLastWhenAtFirst() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    state.focusedSurfaceID = UUID(0)
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    await store.send(.selectPreviousEntry) {
      $0.focusedSurfaceID = UUID(2)
    }
    await store.receive(.entryTapped(UUID(2)))
  }

  @Test func navigationWithoutEntriesIsNoOp() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.selectNextEntry)
    await store.send(.selectPreviousEntry)
  }

  @Test func entryTappedUpdatesFocusAnchor() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    // Tapping mirrors the entry's surface into the focus anchor so keyboard
    // navigation continues from the just-selected agent, without relying on the
    // (per-worktree deduplicated) async `focusChanged` event.
    await store.send(.entryTapped(UUID(2))) {
      $0.focusedSurfaceID = UUID(2)
    }
  }

  @Test func handOffTappedUpdatesFocusAnchorLikeEntryTapped() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    // The context-menu hand off selects the entry's pane (parents focus it),
    // so the keyboard-nav anchor must move with it exactly like a tap.
    await store.send(.handOffTapped(UUID(2))) {
      $0.focusedSurfaceID = UUID(2)
    }
  }

  @Test func markAsReadTappedIsLocalNoOp() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    // Handled by RepositoriesFeature; the panel reducer itself must not move
    // the anchor or mutate entries.
    await store.send(.markAsReadTapped(UUID(1)))
  }

  @Test func focusedSurfaceChangedUpdatesAnchor() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.focusedSurfaceChanged(UUID(7))) {
      $0.focusedSurfaceID = UUID(7)
    }
    await store.send(.focusedSurfaceChanged(nil)) {
      $0.focusedSurfaceID = nil
    }
  }

  @Test func panelSubtitleAndHelpSwapPaneTitleAndBranchWhenEnabled() {
    let entry = entry(id: UUID(0), paneTitle: "Review issue 385", state: .idle, changedAt: Date())

    #expect(
      ActiveAgentsPanel.subtitle(for: entry, branchName: "main", showTabTitles: false)
        == "main"
    )
    #expect(
      ActiveAgentsPanel.helpText(for: entry, branchName: "main", showTabTitles: false)
        == "Review issue 385"
    )
    #expect(
      ActiveAgentsPanel.subtitle(for: entry, branchName: "main", showTabTitles: true)
        == "Review issue 385"
    )
    #expect(
      ActiveAgentsPanel.helpText(for: entry, branchName: "main", showTabTitles: true)
        == "main"
    )
  }

  @Test func panelPaneTitleFallsBackForEmptyTitles() {
    let entry = entry(id: UUID(0), paneTitle: "   ", state: .idle, changedAt: Date())

    #expect(ActiveAgentsPanel.paneTitle(for: entry) == "Untitled tab")
  }

  private func sampleEntries() -> IdentifiedArrayOf<ActiveAgentEntry> {
    let now = Date(timeIntervalSince1970: 10)
    return [
      entry(id: UUID(0), state: .working, changedAt: now),
      entry(id: UUID(1), state: .idle, changedAt: now),
      entry(id: UUID(2), state: .blocked, changedAt: now),
    ]
  }

  private func entry(
    id: UUID,
    paneTitle: String = "1",
    state: AgentDisplayState,
    changedAt: Date,
    agent: DetectedAgent = .codex,
    iconLookupToken: String? = nil
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: paneTitle,
      surfaceID: id,
      paneIndex: 1,
      iconLookupToken: iconLookupToken ?? agent.iconLookupToken,
      agent: agent,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: changedAt
    )
  }
}

extension UUID {
  fileprivate init(_ value: UInt8) {
    self.init(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }
}
