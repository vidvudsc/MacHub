import AppKit

enum AppVisibilityService {
  private static var isHidingToMenuBar = false

  static func configureDashboardWindow(_ window: NSWindow?) {
    guard let window, isDashboardWindow(window) else { return }
    window.isReleasedWhenClosed = false
    window.delegate = DashboardWindowDelegate.shared
  }

  static func showDashboard() {
    isHidingToMenuBar = false
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    for window in dashboardWindows() {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  static func hideToMenuBar() {
    guard !isHidingToMenuBar else { return }
    isHidingToMenuBar = true

    NSApp.setActivationPolicy(.accessory)
    for window in NSApp.windows {
      window.orderOut(nil)
    }
    NSApp.hide(nil)

    DispatchQueue.main.async {
      isHidingToMenuBar = false
    }
  }

  private static func dashboardWindows() -> [NSWindow] {
    NSApp.windows.filter(isDashboardWindow)
  }

  private static func isDashboardWindow(_ window: NSWindow) -> Bool {
    window.title == "MacHub" && window.level == .normal
  }
}

private final class DashboardWindowDelegate: NSObject, NSWindowDelegate {
  static let shared = DashboardWindowDelegate()

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    AppVisibilityService.hideToMenuBar()
    return false
  }

  func windowWillMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    AppVisibilityService.hideToMenuBar()
    DispatchQueue.main.async {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.orderOut(nil)
    }
  }
}
