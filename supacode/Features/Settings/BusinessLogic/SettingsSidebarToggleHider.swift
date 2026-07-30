import AppKit
import SwiftUI

/// Falls back to removing the system sidebar item when SwiftUI leaves it in a
/// standalone Settings window despite `.toolbar(removing: .sidebarToggle)`.
struct SettingsSidebarToggleHider: NSViewRepresentable {
  func makeNSView(context: Context) -> SettingsSidebarToggleHiderView {
    SettingsSidebarToggleHiderView()
  }

  func updateNSView(_ nsView: SettingsSidebarToggleHiderView, context: Context) {
    nsView.removeSidebarToggleIfNeeded()
  }
}

final class SettingsSidebarToggleHiderView: NSView {
  private static let sidebarToggleIdentifier = NSToolbarItem.Identifier(
    "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
  )

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    DispatchQueue.main.async { [weak self] in
      self?.removeSidebarToggleIfNeeded()
    }
  }

  func removeSidebarToggleIfNeeded() {
    guard let toolbar = window?.toolbar,
      let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.sidebarToggleIdentifier })
    else {
      return
    }
    toolbar.removeItem(at: index)
  }
}
