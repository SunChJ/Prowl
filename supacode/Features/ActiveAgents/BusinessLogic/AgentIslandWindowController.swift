import AppKit
import ComposableArchitecture
import SwiftUI

private final class AgentIslandPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class AgentIslandWindowController {
  private let appStore: StoreOf<AppFeature>
  private let displayCatalog: AgentIslandDisplayCatalog
  private let presentation = AgentIslandPresentationModel()
  private var panel: AgentIslandPanel?
  private var observers: [NSObjectProtocol] = []
  private var localEventMonitor: Any?
  private var globalEventMonitor: Any?
  private var isVisible = false
  private var displayPreference: AgentIslandDisplayPreference = .automatic
  private var contentSize = CGSize(width: 420, height: 40)

  init(
    store: StoreOf<AppFeature>,
    displayCatalog: AgentIslandDisplayCatalog = .shared
  ) {
    appStore = store
    self.displayCatalog = displayCatalog
  }

  func start() {
    guard panel == nil else { return }
    let panel = AgentIslandPanel(
      contentRect: CGRect(origin: .zero, size: contentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.identifier = NSUserInterfaceItemIdentifier("agent-island")
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isExcludedFromWindowsMenu = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.tabbingMode = .disallowed
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
      .canJoinAllApplications,
    ]

    panel.contentView = NSHostingView(
      rootView: AgentIslandView(
        store: appStore,
        presentation: presentation
      ) { [weak self] isVisible, preference, size in
        self?.updatePresentation(isVisible: isVisible, preference: preference, size: size)
      }
    )
    self.panel = panel
    installObservers()
    installEventMonitors()
    refreshPlacement()
  }

  func stop() {
    removeObservers()
    removeEventMonitors()
    panel?.orderOut(nil)
    panel = nil
  }

  private func updatePresentation(
    isVisible: Bool,
    preference: AgentIslandDisplayPreference,
    size: CGSize
  ) {
    self.isVisible = isVisible
    displayPreference = preference
    if size.width > 0, size.height > 0 {
      contentSize = size
    }
    refreshPlacement()
  }

  private func refreshPlacement() {
    guard let panel else { return }
    displayCatalog.refresh()
    let mainWindowScreenID = displayCatalog.descriptor(for: mainProwlWindow?.screen)?.id
    let mainScreenID = displayCatalog.descriptor(for: NSScreen.main)?.id
    guard
      let screen = AgentIslandScreenLayout.resolve(
        preference: displayPreference,
        screens: displayCatalog.screens,
        mainWindowScreenID: mainWindowScreenID,
        mainScreenID: mainScreenID
      )
    else {
      panel.orderOut(nil)
      return
    }

    let notchSize = screen.notchFrame?.size
    if presentation.notchSize != notchSize {
      presentation.notchSize = notchSize
    }
    let frame = AgentIslandScreenLayout.panelFrame(contentSize: contentSize, screen: screen)
    panel.setFrame(frame, display: panel.isVisible)
    if isVisible {
      panel.orderFrontRegardless()
    } else {
      panel.orderOut(nil)
    }
  }

  private var mainProwlWindow: NSWindow? {
    NSApplication.shared.windows.first { $0.identifier?.rawValue == WindowID.main }
  }

  private func installObservers() {
    observe(NSApplication.didChangeScreenParametersNotification, object: nil) { [weak self] _ in
      self?.refreshPlacement()
    }
    observe(NSWindow.didMoveNotification, object: nil) { [weak self] windowIdentifier in
      guard let self, windowIdentifier == self.mainProwlWindow.map(ObjectIdentifier.init) else { return }
      self.refreshPlacement()
    }
    observe(NSWindow.didChangeScreenNotification, object: nil) { [weak self] windowIdentifier in
      guard let self, windowIdentifier == self.mainProwlWindow.map(ObjectIdentifier.init) else { return }
      self.refreshPlacement()
    }
  }

  private func observe(
    _ name: Notification.Name,
    object: AnyObject?,
    handler: @escaping @MainActor (ObjectIdentifier?) -> Void
  ) {
    let observer = NotificationCenter.default.addObserver(
      forName: name,
      object: object,
      queue: .main
    ) { notification in
      let windowIdentifier = (notification.object as? NSWindow).map(ObjectIdentifier.init)
      MainActor.assumeIsolated {
        handler(windowIdentifier)
      }
    }
    observers.append(observer)
  }

  private func removeObservers() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func installEventMonitors() {
    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .keyDown,
    ]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown, event.keyCode == 53, isRosterExpanded {
        appStore.send(.repositories(.activeAgents(.islandCollapseRoster)))
        return nil
      }
      if event.window !== panel, isRosterExpanded {
        appStore.send(.repositories(.activeAgents(.islandCollapseRoster)))
      }
      return event
    }
    globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown,
    ]) {
      [weak self] _ in
      Task { @MainActor in
        guard let self, self.isRosterExpanded else { return }
        self.appStore.send(.repositories(.activeAgents(.islandCollapseRoster)))
      }
    }
  }

  private func removeEventMonitors() {
    if let localEventMonitor {
      NSEvent.removeMonitor(localEventMonitor)
      self.localEventMonitor = nil
    }
    if let globalEventMonitor {
      NSEvent.removeMonitor(globalEventMonitor)
      self.globalEventMonitor = nil
    }
  }

  private var isRosterExpanded: Bool {
    appStore.repositories.activeAgents.isIslandRosterExpanded
  }
}
