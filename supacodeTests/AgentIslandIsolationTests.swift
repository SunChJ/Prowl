import AppKit
import Testing

@testable import supacode

@MainActor
struct AgentIslandIsolationTests {
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
