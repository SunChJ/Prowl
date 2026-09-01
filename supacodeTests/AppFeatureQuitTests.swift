import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureQuitTests {
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

    await store.send(.repositories(.activeAgents(.islandEntryTapped(entry.id)))) {
      $0.repositories.activeAgents.isIslandRosterExpanded = false
      $0.repositories.activeAgents.focusedSurfaceID = entry.surfaceID
    }
    await store.receive(\.repositories.activeAgents.entryTapped) {
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

  @Test(.dependencies) func requestQuitWithConfirmationSurfacesMainWindowAndShowsAlert() async {
    var settings = SettingsFeature.State()
    settings.confirmBeforeQuit = true
    let surfaced = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: settings)
    ) {
      AppFeature()
    } withDependencies: {
      $0.appLifecycleClient.surfaceMainWindow = {
        surfaced.setValue(true)
        return true
      }
    }

    await store.send(.requestQuit) {
      $0.alert = AlertState {
        TextState("Quit Prowl?")
      } actions: {
        ButtonState(action: .confirmQuit) {
          TextState("Quit")
        }
        ButtonState(role: .cancel, action: .dismiss) {
          TextState("Cancel")
        }
      } message: {
        TextState("This will close all terminal sessions.")
      }
    }

    #expect(surfaced.value)
  }

  @Test(.dependencies) func requestQuitWithoutConfirmationTerminatesThroughLifecycleClient() async {
    var settings = SettingsFeature.State()
    settings.confirmBeforeQuit = false
    let terminated = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: settings)
    ) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.appLifecycleClient.terminate = {
        terminated.setValue(true)
      }
    }

    await store.send(.requestQuit)
    await store.finish()

    #expect(terminated.value)
    #expect(store.state.alert == nil)
  }
}
