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
    let firstRunningGeneration = controller.observationGeneration

    store.send(.settings(.binding(.set(\.agentIslandEnabled, false))))
    await settle { !controller.isRunning }
    #expect(!controller.isRunning)
    let stoppedGeneration = controller.observationGeneration
    #expect(stoppedGeneration != firstRunningGeneration)

    store.send(.settings(.binding(.set(\.agentIslandEnabled, true))))
    await settle { controller.isRunning }
    #expect(controller.isRunning)
    #expect(controller.observationGeneration != stoppedGeneration)

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

  @Test func dedicatedGlobalHotKeyOnlyTogglesTheIsland() {
    #expect(
      AgentIslandHotKeyAction.resolve(
        isRosterExpanded: false,
        hasEntries: true
      ) == .toggleIslandRoster)
    #expect(
      AgentIslandHotKeyAction.resolve(
        isRosterExpanded: true,
        hasEntries: true
      ) == .collapseIsland)
    #expect(
      AgentIslandHotKeyAction.resolve(
        isRosterExpanded: false,
        hasEntries: false
      ) == nil)
  }

  @Test func strongAttentionHotKeysUseCommandOptionForAtMostNineCollapsedSlots() {
    #expect(AgentIslandAttentionShortcut.binding(at: 0)?.display == "⌘⌥1")
    #expect(AgentIslandAttentionShortcut.binding(at: 8)?.display == "⌘⌥9")
    #expect(AgentIslandAttentionShortcut.binding(at: 9) == nil)
    #expect(
      AgentIslandAttentionShortcut.slotCount(
        isRosterExpanded: false,
        attentionEntryCount: 12
      ) == 9)
    #expect(
      AgentIslandAttentionShortcut.slotCount(
        isRosterExpanded: true,
        attentionEntryCount: 4
      ) == 0)
  }

  @Test func globalHotKeyConfigurationOnlyRefreshesChangedRegistrationGroups() {
    let binding = Keybinding(
      key: "p",
      modifiers: KeybindingModifiers(command: true, shift: true)
    )
    let initial = AgentIslandGlobalHotKeyConfiguration(
      toggleBinding: binding,
      isRosterExpanded: false,
      attentionEntryCount: 2
    )

    #expect(initial.changes(from: nil) == [.toggle, .attentionSlots])
    #expect(initial.changes(from: initial).isEmpty)

    let differentCount = AgentIslandGlobalHotKeyConfiguration(
      toggleBinding: binding,
      isRosterExpanded: false,
      attentionEntryCount: 3
    )
    #expect(differentCount.changes(from: initial) == [.attentionSlots])

    let differentBinding = AgentIslandGlobalHotKeyConfiguration(
      toggleBinding: nil,
      isRosterExpanded: false,
      attentionEntryCount: 2
    )
    #expect(differentBinding.changes(from: initial) == [.toggle, .attentionSlots])
    #expect(initial.changes(from: initial, force: true) == [.toggle, .attentionSlots])
  }

  @Test func toggleShortcutRejectsContextualNumberBindings() {
    for digit in 1...AgentIslandAttentionShortcut.slotLimit {
      #expect(
        AgentIslandToggleShortcutPolicy.isReserved(
          Keybinding(key: String(digit), modifiers: KeybindingModifiers(command: true))
        )
      )
      #expect(
        AgentIslandToggleShortcutPolicy.isReserved(
          Keybinding(
            key: "digit_\(digit)",
            modifiers: KeybindingModifiers(command: true, option: true)
          )
        )
      )
    }

    #expect(
      !AgentIslandToggleShortcutPolicy.isReserved(
        Keybinding(key: "p", modifiers: KeybindingModifiers(command: true, shift: true))
      )
    )
    #expect(
      !AgentIslandToggleShortcutPolicy.isReserved(
        Keybinding(key: "1", modifiers: KeybindingModifiers(command: true, shift: true))
      )
    )

    let reservedConfiguration = AgentIslandGlobalHotKeyConfiguration(
      toggleBinding: Keybinding(
        key: "1",
        modifiers: KeybindingModifiers(command: true, option: true)
      ),
      isRosterExpanded: false,
      attentionEntryCount: 2
    )
    #expect(reservedConfiguration.toggleBinding == nil)
  }

  @Test func expandedRosterKeyMapSupportsArrowsVimiumActivationAndCommandNumbers() {
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 126, characters: nil, modifiers: [])
        == .move(.previous))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 125, characters: nil, modifiers: [])
        == .move(.next))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "k", modifiers: [])
        == .move(.previous))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "j", modifiers: []) == .move(.next)
    )
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 123, characters: nil, modifiers: [])
        == .page(.previous))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 124, characters: nil, modifiers: [])
        == .page(.next))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "h", modifiers: [])
        == .page(.previous))
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "l", modifiers: []) == .page(.next)
    )
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "u", modifiers: []) == nil)
    #expect(AgentIslandKeyboardCommand.resolve(keyCode: 0, characters: "d", modifiers: []) == nil)
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 36, characters: nil, modifiers: [])
        == .activateSelection)
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 49, characters: nil, modifiers: [])
        == .activateSelection)
    #expect(
      AgentIslandKeyboardCommand.resolve(keyCode: 53, characters: nil, modifiers: []) == .collapse)
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
      ) == 340)
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

  @Test func floatingCompactBarUsesTheDisplayMenuBarHeight() {
    #expect(
      AgentIslandRootLayout.compactHeight(
        notchCompactHeight: nil,
        floatingMenuBarHeight: 32
      ) == 32)
    #expect(
      AgentIslandRootLayout.compactHeight(
        notchCompactHeight: 36,
        floatingMenuBarHeight: 32
      ) == 36)
  }

  @Test func rosterDisplayControlRequiresMultipleConnectedDisplays() {
    #expect(!AgentIslandRootLayout.showsDisplayControl(connectedDisplayCount: 0))
    #expect(!AgentIslandRootLayout.showsDisplayControl(connectedDisplayCount: 1))
    #expect(AgentIslandRootLayout.showsDisplayControl(connectedDisplayCount: 2))
  }

  @Test func floatingBarKeepsAStableWidthAndCompactsTheAllStateSummary() {
    #expect(!AgentIslandRootLayout.usesCompactFloatingSummary(stateCount: 3))
    #expect(AgentIslandRootLayout.usesCompactFloatingSummary(stateCount: 4))
    #expect(AgentIslandRootLayout.floatingCompactWidth == 340)
    #expect(
      AgentIslandRootLayout.width(
        notchCompactWidth: nil,
        isRosterExpanded: false,
        attentionEntryCount: 0
      ) == 340)
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

  @Test func compactBarRingUsesOnlyTheStaticStateOutline() {
    let ring = AgentIslandStateRingView(frame: CGRect(x: 0, y: 0, width: 21, height: 21))

    ring.update(state: .working, reduceMotion: false, allowsAnimation: false)

    #expect(!ring.isRotationActive)
    #expect(!ring.isAnimatedRingVisible)
  }
}
