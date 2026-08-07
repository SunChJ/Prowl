import Testing

@testable import supacode

struct CanvasInteractionPolicyTests {
  @Test func hoveredLinkTakesPriorityOverCommandSelection() {
    let linkActivationRequested = CanvasInteractionPolicy.linkActivationRequested(
      hasHoveredLink: true,
      isCommandModifierActive: true
    )
    let showsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: true,
      selectionModeActive: true,
      broadcastFollower: true,
      linkActivationRequested: linkActivationRequested
    )

    #expect(linkActivationRequested)
    #expect(showsShield == false)
  }

  @Test func commandSelectionStillShieldsNonLinkContent() {
    let showsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: true,
      selectionModeActive: false,
      broadcastFollower: false,
      linkActivationRequested: false
    )

    #expect(showsShield)
  }

  @Test func selectionModeStillShieldsNonLinkContent() {
    let showsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: false,
      selectionModeActive: true,
      broadcastFollower: false,
      linkActivationRequested: false
    )

    #expect(showsShield)
  }

  @Test func broadcastingOnlyShieldsFollowerCards() {
    let primaryShowsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: false,
      selectionModeActive: false,
      broadcastFollower: false,
      linkActivationRequested: false
    )
    let followerShowsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: false,
      selectionModeActive: false,
      broadcastFollower: true,
      linkActivationRequested: false
    )

    #expect(primaryShowsShield == false)
    #expect(followerShowsShield)
  }

  @Test func hoveredLinkWithoutCommandStillUsesSelectionPolicy() {
    let linkActivationRequested = CanvasInteractionPolicy.linkActivationRequested(
      hasHoveredLink: true,
      isCommandModifierActive: false
    )
    let showsShield = CanvasInteractionPolicy.showsSelectionShield(
      commandSelectionActive: false,
      selectionModeActive: true,
      broadcastFollower: false,
      linkActivationRequested: linkActivationRequested
    )

    #expect(linkActivationRequested == false)
    #expect(showsShield)
  }
}
