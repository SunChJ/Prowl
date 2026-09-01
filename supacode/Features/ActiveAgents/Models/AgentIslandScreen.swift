import AppKit
import CoreGraphics
import Observation

struct AgentIslandScreenDescriptor: Equatable, Identifiable {
  let id: String
  let name: String
  let frame: CGRect
  let visibleFrame: CGRect
  let isBuiltIn: Bool
  let hasNotch: Bool
}

enum AgentIslandScreenLayout {
  static let floatingTopOffset = 8.0

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
    return CGRect(
      x: screen.frame.midX - (contentSize.width / 2),
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
    return AgentIslandScreenDescriptor(
      id: id,
      name: screen.localizedName,
      frame: screen.frame,
      visibleFrame: screen.visibleFrame,
      isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
      hasNotch: screen.safeAreaInsets.top > 0
    )
  }
}
