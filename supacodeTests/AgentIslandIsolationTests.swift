import AppKit
import ComposableArchitecture
import DependenciesTestSupport
import Testing

@testable import supacode

@MainActor
struct AgentIslandIsolationTests {
  @Test(.dependencies) func panelRunsOnlyWhileTheSettingIsEnabled() {
    let store: StoreOf<AppFeature> = Store(initialState: AppFeature.State()) {
      Scope(state: \.settings, action: \.settings) {
        BindingReducer()
      }
    }
    let controller = AgentIslandWindowController(store: store)

    controller.activate()
    #expect(!controller.isRunning)

    store.send(.settings(.binding(.set(\.agentIslandEnabled, true))))
    controller.refreshLifecycle()
    #expect(controller.isRunning)

    store.send(.settings(.binding(.set(\.agentIslandEnabled, false))))
    controller.refreshLifecycle()
    #expect(!controller.isRunning)
  }

  @Test func panelCannotTakeKeyWindowStatusFromGhostty() {
    let panel = AgentIslandPanel(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 40),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
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

  @Test func escapeTrackerReportsOnlyNewKeyDownEdges() {
    var tracker = AgentIslandEscapeKeyTracker(isPressed: false)
    let initialRelease = tracker.observe(isPressed: false)
    let firstPress = tracker.observe(isPressed: true)
    let heldPress = tracker.observe(isPressed: true)
    let release = tracker.observe(isPressed: false)
    let secondPress = tracker.observe(isPressed: true)

    #expect(!initialRelease)
    #expect(firstPress)
    #expect(!heldPress)
    #expect(!release)
    #expect(secondPress)
  }

  @Test func escapeTrackerDoesNotTreatAnAlreadyHeldKeyAsANewPress() {
    var tracker = AgentIslandEscapeKeyTracker(isPressed: true)
    let heldPress = tracker.observe(isPressed: true)
    let release = tracker.observe(isPressed: false)
    let nextPress = tracker.observe(isPressed: true)

    #expect(!heldPress)
    #expect(!release)
    #expect(nextPress)
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
