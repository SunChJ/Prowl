import AppKit
import ComposableArchitecture
import DependenciesTestSupport
import Testing

@testable import supacode

@MainActor
struct AgentIslandIsolationTests {
  @Test(.dependencies) func panelFollowsTheSettingThroughObservation() async {
    let store: StoreOf<AppFeature> = Store(initialState: AppFeature.State()) {
      Scope(state: \.settings, action: \.settings) {
        BindingReducer()
      }
    }
    let controller = AgentIslandWindowController(
      store: store,
      terminalManager: WorktreeTerminalManager(runtime: GhosttyRuntime())
    )

    controller.activate()
    #expect(!controller.isRunning)

    // Each change must be observed without any manual refresh, including after the
    // observation has fired once and re-registered.
    store.send(.settings(.binding(.set(\.agentIslandEnabled, true))))
    await settle { controller.isRunning }
    #expect(controller.isRunning)

    store.send(.settings(.binding(.set(\.agentIslandEnabled, false))))
    await settle { !controller.isRunning }
    #expect(!controller.isRunning)

    store.send(.settings(.binding(.set(\.agentIslandEnabled, true))))
    await settle { controller.isRunning }
    #expect(controller.isRunning)

    controller.stop()
  }

  /// The observer hops to the main actor once before re-reading the setting; yielding lets
  /// that hop run without sleeping.
  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<50 where !condition() {
      await Task.yield()
    }
  }

  @Test func panelOnlyAcceptsKeyboardInputForTheExpandedRoster() {
    let panel = AgentIslandPanel(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 40),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    #expect(!panel.canBecomeKey)
    panel.acceptsKeyboardInput = true
    #expect(panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
  }

  @Test func globalHotKeyPreservesTheInAppActionAndTogglesTheIslandElsewhere() {
    #expect(
      AgentIslandHotKeyAction.resolve(
        appIsActive: true,
        isRosterExpanded: false,
        hasEntries: true
      ) == .toggleSidebarPanel)
    #expect(
      AgentIslandHotKeyAction.resolve(
        appIsActive: false,
        isRosterExpanded: false,
        hasEntries: true
      ) == .toggleIslandRoster)
    #expect(
      AgentIslandHotKeyAction.resolve(
        appIsActive: true,
        isRosterExpanded: true,
        hasEntries: true
      ) == .collapseIsland)
    #expect(
      AgentIslandHotKeyAction.resolve(
        appIsActive: false,
        isRosterExpanded: false,
        hasEntries: false
      ) == nil)
  }

  @Test func expandedRosterKeyMapSupportsArrowsVimiumActivationAndCommandNumbers() {
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 126, characters: nil, modifiers: []) == .move(.previous))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 125, characters: nil, modifiers: []) == .move(.next))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "k", modifiers: []) == .move(.previous))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "j", modifiers: []) == .move(.next))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "u", modifiers: []) == .page(.previous))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "d", modifiers: []) == .page(.next))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 36, characters: nil, modifiers: []) == .activateSelection)
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 49, characters: nil, modifiers: []) == .activateSelection)
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 53, characters: nil, modifiers: []) == .collapse)
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 18, characters: "1", modifiers: .command)
        == .activateVisibleEntry(0))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 25, characters: "9", modifiers: .command)
        == .activateVisibleEntry(8))
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 18, characters: "1", modifiers: []) == nil)
  }

  @Test func eventMonitorsExistOnlyForAVisibleExpandedRoster() {
    #expect(
      !AgentIslandInteractionPolicy.shouldInstallEventMonitors(
        isVisible: false,
        isRosterExpanded: false
      ))
    #expect(
      !AgentIslandInteractionPolicy.shouldInstallEventMonitors(
        isVisible: false,
        isRosterExpanded: true
      ))
    #expect(
      !AgentIslandInteractionPolicy.shouldInstallEventMonitors(
        isVisible: true,
        isRosterExpanded: false
      ))
    #expect(
      AgentIslandInteractionPolicy.shouldInstallEventMonitors(
        isVisible: true,
        isRosterExpanded: true
      ))
  }

  @Test func compactPanelDoesNotRetainExpandedRosterWidth() {
    #expect(
      AgentIslandRootLayout.width(
        notchCompactWidth: nil,
        isRosterExpanded: false,
        attentionEntryCount: 0
      ) == 300)
    #expect(
      AgentIslandRootLayout.width(
        notchCompactWidth: nil,
        isRosterExpanded: false,
        attentionEntryCount: 2
      ) == 380)
    #expect(
      AgentIslandRootLayout.width(
        notchCompactWidth: nil,
        isRosterExpanded: true,
        attentionEntryCount: 0
      ) == 420)
    #expect(
      AgentIslandRootLayout.width(
        notchCompactWidth: 425,
        isRosterExpanded: false,
        attentionEntryCount: 0
      ) == 425)
  }

  @Test func coreAnimationRingStopsForReduceMotionAndIdle() {
    let ring = AgentIslandStateRingView(frame: CGRect(x: 0, y: 0, width: 21, height: 21))

    ring.update(state: .working, reduceMotion: false)
    #expect(ring.isRotationActive)

    ring.update(state: .working, reduceMotion: true)
    #expect(!ring.isRotationActive)

    ring.update(state: .idle, reduceMotion: false)
    #expect(!ring.isRotationActive)
  }
}
