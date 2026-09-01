import AppKit
import CoreGraphics
import Observation

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
  private static let minimumCompactHeight: CGFloat = 40
  private static let minimumWingWidth: CGFloat = 120
  private static let bottomExtension: CGFloat = 8

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
    compactHeight = max(Self.minimumCompactHeight, cutoutSize.height + Self.bottomExtension)
    wingWidth = (compactWidth - cutoutSize.width) / 2
  }

  var rootWidth: CGFloat {
    max(420, compactWidth)
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

@MainActor
@Observable
final class AgentIslandDisplayCatalog {
  static let shared = AgentIslandDisplayCatalog()

  private(set) var screens: [AgentIslandScreenDescriptor] = []
  private var observers: [NSObjectProtocol] = []

  init(notificationCenter: NotificationCenter = .default) {
    refresh()
    let observer = notificationCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
    observers.append(observer)
  }

  func refresh() {
    screens = NSScreen.screens.compactMap(Self.descriptor(for:))
  }

  func descriptor(for screen: NSScreen?) -> AgentIslandScreenDescriptor? {
    guard let screen else { return nil }
    return Self.descriptor(for: screen)
  }

  private static func descriptor(for screen: NSScreen) -> AgentIslandScreenDescriptor? {
    guard
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else { return nil }
    let displayID = CGDirectDisplayID(number.uint32Value)
    guard let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
      return nil
    }
    let id = CFUUIDCreateString(nil, displayUUID) as String
    let notchFrame = AgentIslandScreenLayout.notchFrame(
      screenFrame: screen.frame,
      safeAreaTopInset: screen.safeAreaInsets.top,
      auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: screen.auxiliaryTopRightArea
    )
    return AgentIslandScreenDescriptor(
      id: id,
      name: screen.localizedName,
      frame: screen.frame,
      visibleFrame: screen.visibleFrame,
      isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
      notchFrame: notchFrame
    )
  }
}
