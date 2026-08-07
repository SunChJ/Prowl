enum CanvasInteractionPolicy {
  static func linkActivationRequested(
    hasHoveredLink: Bool,
    isCommandModifierActive: Bool
  ) -> Bool {
    hasHoveredLink && isCommandModifierActive
  }

  static func showsSelectionShield(
    commandSelectionActive: Bool,
    selectionModeActive: Bool,
    broadcastFollower: Bool,
    linkActivationRequested: Bool
  ) -> Bool {
    if linkActivationRequested {
      return false
    }
    if commandSelectionActive || selectionModeActive {
      return true
    }
    return broadcastFollower
  }
}
