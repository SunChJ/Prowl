import AppKit
import ComposableArchitecture
import SwiftUI

final class AgentIslandPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

enum AgentIslandInteractionPolicy {
  static func shouldInstallEventMonitors(
    isVisible: Bool,
    isRosterExpanded: Bool
  ) -> Bool {
    isVisible && isRosterExpanded
  }
}

struct AgentIslandEscapeKeyTracker {
  private var wasPressed: Bool

  init(isPressed: Bool = false) {
    wasPressed = isPressed
  }

  mutating func observe(isPressed: Bool) -> Bool {
    defer { wasPressed = isPressed }
    return isPressed && !wasPressed
  }
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
  private var escapePollTimer: Timer?
  private var escapeKeyTracker = AgentIslandEscapeKeyTracker()
  private var isVisible = false
  private var isRosterExpanded = false
  private var displayPreference: AgentIslandDisplayPreference = .automatic
  private var contentSize = CGSize(width: 420, height: 40)

  init(
    store: StoreOf<AppFeature>,
    displayCatalog: AgentIslandDisplayCatalog = .shared
  ) {
    appStore = store
    self.displayCatalog = displayCatalog
  }

  /// Runs the panel only while the setting is on, re-evaluating whenever it changes.
  func activate() {
    refreshLifecycle()
    observeEnabledSetting()
  }

  var isRunning: Bool { panel != nil }

  /// The synchronous half of `activate()`, shared by the observer and by tests.
  func refreshLifecycle() {
    if appStore.settings.agentIslandEnabled {
      start()
    } else {
      stop()
    }
  }

  private func observeEnabledSetting() {
    withObservationTracking {
      _ = appStore.settings.agentIslandEnabled
    } onChange: { [weak self] in
      // `onChange` fires before the new value lands; hop once so the read below sees it.
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshLifecycle()
        self.observeEnabledSetting()
      }
    }
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
    panel.becomesKeyOnlyIfNeeded = false
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
      ) { [weak self] isVisible, isRosterExpanded, preference, size in
        self?.updatePresentation(
          isVisible: isVisible,
          isRosterExpanded: isRosterExpanded,
          preference: preference,
          size: size
        )
      }
    )
    self.panel = panel
    installObservers()
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
    isRosterExpanded: Bool,
    preference: AgentIslandDisplayPreference,
    size: CGSize
  ) {
    self.isVisible = isVisible
    self.isRosterExpanded = isRosterExpanded
    displayPreference = preference
    if size.width > 0, size.height > 0 {
      contentSize = size
    }
    updateEventMonitors()
    refreshPlacement()
  }

  private func refreshPlacement() {
    guard let panel else { return }
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
      guard let self else { return }
      self.displayCatalog.refresh()
      self.refreshPlacement()
    }
    observe(NSWindow.didMoveNotification, object: nil) { [weak self] windowIdentifier in
      guard let self, windowIdentifier == self.mainProwlWindow.map(ObjectIdentifier.init) else {
        return
      }
      self.refreshPlacement()
    }
    observe(NSWindow.didChangeScreenNotification, object: nil) { [weak self] windowIdentifier in
      guard let self, windowIdentifier == self.mainProwlWindow.map(ObjectIdentifier.init) else {
        return
      }
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
    guard localEventMonitor == nil, globalEventMonitor == nil else { return }
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
    startEscapePolling()
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
    escapePollTimer?.invalidate()
    escapePollTimer = nil
  }

  private func startEscapePolling() {
    guard escapePollTimer == nil else { return }
    escapeKeyTracker = AgentIslandEscapeKeyTracker(isPressed: Self.isEscapePressed)
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.pollEscapeKey()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    escapePollTimer = timer
  }

  private func pollEscapeKey() {
    guard isRosterExpanded else { return }
    if escapeKeyTracker.observe(isPressed: Self.isEscapePressed) {
      appStore.send(.repositories(.activeAgents(.islandCollapseRoster)))
    }
  }

  private static var isEscapePressed: Bool {
    CGEventSource.keyState(.combinedSessionState, key: 53)
  }

  private func updateEventMonitors() {
    if AgentIslandInteractionPolicy.shouldInstallEventMonitors(
      isVisible: isVisible,
      isRosterExpanded: isRosterExpanded
    ) {
      installEventMonitors()
    } else {
      removeEventMonitors()
    }
  }
}
