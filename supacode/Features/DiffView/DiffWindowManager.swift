import AppKit
import SwiftUI

@MainActor
final class DiffWindowManager {
  static let shared = DiffWindowManager()

  let state = DiffWindowState()
  private var window: NSWindow?
  private var skipNextFocusRefresh = false
  private var localEventMonitor: Any?

  private init() {}

  func show(
    worktreeURL: URL,
    branchName: String,
    comparison: DiffComparison = .workingTree,
    resolvedKeybindings: ResolvedKeybindingMap = .appDefaults,
    colorScheme: ColorScheme? = nil
  ) {
    state.load(worktreeURL: worktreeURL, branchName: branchName, comparison: comparison)
    skipNextFocusRefresh = true
    let rootView = AnyView(
      DiffWindowContentView(state: state)
        .environment(\.resolvedKeybindings, resolvedKeybindings)
    )

    let appearance = NSAppearance.from(colorScheme)

    if let existingWindow = window {
      if let hostingController = existingWindow.contentViewController as? NSHostingController<AnyView> {
        hostingController.rootView = rootView
      }
      existingWindow.title = windowTitle(branchName: branchName, comparison: comparison)
      existingWindow.appearance = appearance
      if existingWindow.isMiniaturized {
        existingWindow.deminiaturize(nil)
      }
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }

    let hostingController = NSHostingController(rootView: rootView)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = windowTitle(branchName: branchName, comparison: comparison)
    newWindow.identifier = NSUserInterfaceItemIdentifier("diff")
    newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    newWindow.tabbingMode = .disallowed
    newWindow.collectionBehavior = [.moveToActiveSpace]
    newWindow.toolbarStyle = .unified
    newWindow.toolbar = NSToolbar(identifier: "DiffToolbar")
    newWindow.isReleasedWhenClosed = false
    newWindow.appearance = appearance
    newWindow.minSize = NSSize(width: 600, height: 400)
    let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame DiffWindow") != nil
    newWindow.setFrameAutosaveName("DiffWindow")
    if !hasSavedFrame {
      newWindow.setContentSize(NSSize(width: 1000, height: 700))
      newWindow.center()
    }
    newWindow.makeKeyAndOrderFront(nil)

    window = newWindow

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey),
      name: NSWindow.didBecomeKeyNotification,
      object: newWindow,
    )

    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, window == event.window else { return event }
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
        event.charactersIgnoringModifiers == "w"
      {
        window.performClose(nil)
        return nil
      }
      return event
    }
  }

  var hasChanges: Bool {
    !state.changedFiles.isEmpty || state.isLoadingFiles
  }

  private func windowTitle(branchName: String, comparison: DiffComparison) -> String {
    switch comparison {
    case .workingTree:
      "Changes — \(branchName)"
    case .outgoing:
      "Outgoing Changes — \(branchName)"
    }
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    if skipNextFocusRefresh {
      skipNextFocusRefresh = false
      return
    }
    state.refresh()
  }
}

extension NSAppearance {
  fileprivate static func from(_ colorScheme: ColorScheme?) -> NSAppearance? {
    switch colorScheme {
    case .none: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    @unknown default: nil
    }
  }
}
