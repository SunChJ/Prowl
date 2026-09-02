import CoreGraphics

struct AgentIslandScreenDescriptor: Equatable, Identifiable {
  let id: String
  let name: String
  let frame: CGRect
  let visibleFrame: CGRect
  let isBuiltIn: Bool
  let notchFrame: CGRect?

  var hasNotch: Bool { notchFrame != nil }
}

struct AgentIslandNotchLayout: Equatable {
  private static let minimumCompactWidth: CGFloat = 360
  /// The compact bar matches the cutout height so it ends flush with the menu bar. The floor
  /// only guards the 27pt icon cluster against an unusually short safe-area inset.
  private static let minimumCompactHeight: CGFloat = 28
  private static let minimumWingWidth: CGFloat = 120

  let cutoutSize: CGSize
  let compactWidth: CGFloat
  let compactHeight: CGFloat
  let wingWidth: CGFloat

  init(cutoutSize: CGSize) {
    let cutoutSize = CGSize(
      width: max(0, cutoutSize.width),
      height: max(0, cutoutSize.height)
    )
    let compactWidth = max(
      Self.minimumCompactWidth,
      cutoutSize.width + (Self.minimumWingWidth * 2)
    )
    self.cutoutSize = cutoutSize
    self.compactWidth = compactWidth
    compactHeight = max(Self.minimumCompactHeight, cutoutSize.height)
    wingWidth = (compactWidth - cutoutSize.width) / 2
  }
}

enum AgentIslandScreenLayout {
  static let floatingTopOffset: CGFloat = 8

  static func notchFrame(
    screenFrame: CGRect,
    safeAreaTopInset: CGFloat,
    auxiliaryTopLeftArea: CGRect?,
    auxiliaryTopRightArea: CGRect?
  ) -> CGRect? {
    guard safeAreaTopInset > 0 else { return nil }
    let topBandMinY = screenFrame.maxY - safeAreaTopInset
    if let auxiliaryTopLeftArea,
      let auxiliaryTopRightArea,
      auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
    {
      return CGRect(
        x: auxiliaryTopLeftArea.maxX,
        y: topBandMinY,
        width: auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX,
        height: safeAreaTopInset
      )
    }

    let fallbackWidth = min(220, max(180, screenFrame.width * 0.125))
    return CGRect(
      x: screenFrame.midX - (fallbackWidth / 2),
      y: topBandMinY,
      width: fallbackWidth,
      height: safeAreaTopInset
    )
  }

  static func resolve(
    preference: AgentIslandDisplayPreference,
    screens: [AgentIslandScreenDescriptor],
    mainWindowScreenID: String?,
    mainScreenID: String?
  ) -> AgentIslandScreenDescriptor? {
    if case .display(let id, _) = preference,
      let selected = screens.first(where: { $0.id == id })
    {
      return selected
    }
    if let mainWindowScreenID,
      let mainWindowScreen = screens.first(where: { $0.id == mainWindowScreenID })
    {
      return mainWindowScreen
    }
    return screens.first(where: { $0.isBuiltIn && $0.hasNotch })
      ?? mainScreenID.flatMap { id in screens.first(where: { $0.id == id }) }
      ?? screens.first
  }

  static func panelFrame(
    contentSize: CGSize,
    screen: AgentIslandScreenDescriptor
  ) -> CGRect {
    let top = screen.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - floatingTopOffset
    let anchorX = screen.notchFrame?.midX ?? screen.frame.midX
    return CGRect(
      x: anchorX - (contentSize.width / 2),
      y: top - contentSize.height,
      width: contentSize.width,
      height: contentSize.height
    )
  }
}
