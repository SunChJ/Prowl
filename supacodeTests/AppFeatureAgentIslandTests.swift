import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

/// Island-originated actions surface the main window before reusing the sidebar's own paths.
@MainActor
struct AppFeatureAgentIslandTests {
  @Test(.dependencies) func agentIslandEntrySurfacesProwlBeforeReusingAgentFocusPath() async {
    let entryID = UUID()
    let worktreeID = "/tmp/repo/worktree"
    let entry = ActiveAgentEntry(
      id: entryID,
      worktreeID: worktreeID,
      worktreeName: "worktree",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: "Agent",
      surfaceID: entryID,
      paneIndex: 0,
      iconLookupToken: DetectedAgent.codex.iconLookupToken,
      agent: .codex,
      rawState: .working,
      displayState: .working,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )
    var state = AppFeature.State()
    state.repositories.selection = .canvas
    state.repositories.activeAgents.entries = [entry]
    state.repositories.activeAgents.isIslandRosterExpanded = true
    let events = LockIsolated<[String]>([])
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.appLifecycleClient.surfaceMainWindow = {
        events.withValue { $0.append("surface") }
        return true
      }
      $0.terminalClient.focusSurface = { _, _ in
        events.withValue { $0.append("focus") }
        return true
      }
    }

    await store.send(.repositories(.activeAgents(.island(.entryTapped(entry.id))))) {
      $0.repositories.activeAgents.isIslandRosterExpanded = false
    }
    await store.receive(\.repositories.activeAgents.entryTapped) {
      $0.repositories.activeAgents.focusedSurfaceID = entry.surfaceID
      $0.repositories.nextCanvasFocusRequestID = 1
      $0.repositories.pendingCanvasFocusRequest = CanvasFocusRequest(
        id: 1,
        target: .tab(entry.tabID)
      )
      $0.repositories.openedWorktreeIDs = [worktreeID]
    }
    await store.finish()

    #expect(events.value == ["surface", "focus"])
  }

  @Test(.dependencies) func agentIslandOpenProwlOnlySurfacesCurrentWindow() async {
    var state = AppFeature.State()
    state.repositories.activeAgents.isIslandRosterExpanded = true
    let surfaced = LockIsolated(0)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.appLifecycleClient.surfaceMainWindow = {
        surfaced.withValue { $0 += 1 }
        return true
      }
    }

    await store.send(.repositories(.activeAgents(.islandOpenProwlTapped))) {
      $0.repositories.activeAgents.isIslandRosterExpanded = false
    }

    #expect(surfaced.value == 1)
  }

  @Test(.dependencies) func agentIslandHandOffSurfacesProwlBeforeForwardingSharedAction() async {
    let entryID = UUID()
    var state = AppFeature.State()
    state.repositories.activeAgents.isIslandRosterExpanded = true
    let surfaced = LockIsolated(0)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.appLifecycleClient.surfaceMainWindow = {
        surfaced.withValue { $0 += 1 }
        return true
      }
    }

    await store.send(.repositories(.activeAgents(.island(.handOffTapped(entryID))))) {
      $0.repositories.activeAgents.isIslandRosterExpanded = false
    }
    await store.receive(\.repositories.activeAgents.handOffTapped, entryID)

    #expect(surfaced.value == 1)
  }

  @Test(.dependencies) func agentIslandWorkflowSurfacesProwlBeforeForwardingSharedAction() async {
    let entryID = UUID()
    var state = AppFeature.State()
    state.repositories.activeAgents.isIslandRosterExpanded = true
    let surfaced = LockIsolated(0)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.appLifecycleClient.surfaceMainWindow = {
        surfaced.withValue { $0 += 1 }
        return true
      }
    }

    await store.send(
      .repositories(
        .activeAgents(.island(.runWorkflowTapped(entryID, workflowKey: "review")))
      )
    ) {
      $0.repositories.activeAgents.isIslandRosterExpanded = false
    }
    await store.receive(\.repositories.activeAgents.runWorkflowTapped)

    #expect(surfaced.value == 1)
  }
}
