import AppKit

enum AppVisibilityService {
  private static var isHidingToMenuBar = false

  static func configureDashboardWindow(_ window: NSWindow?) {
    guard let window, isDashboardWindow(window) else { return }
    window.isReleasedWhenClosed = false
    window.delegate = DashboardWindowDelegate.shared
    closeDuplicateDashboardWindows(keeping: window)
  }

  static func showDashboard() {
    showDashboard(attempt: 0)
  }

  private static func showDashboard(attempt: Int) {
    isHidingToMenuBar = false
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    var windows = dashboardWindows()
    if windows.isEmpty {
      NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
      windows = dashboardWindows()
    }

    guard let primary = windows.first else {
      NSApp.activate(ignoringOtherApps: true)
      if attempt < 5 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
          showDashboard(attempt: attempt + 1)
        }
      }
      return
    }

    closeDuplicateDashboardWindows(keeping: primary)
    if primary.isMiniaturized {
      primary.deminiaturize(nil)
    }
    primary.makeKeyAndOrderFront(nil)
    primary.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  static func closeMenuBarPanels() {
    for window in NSApp.windows where !isDashboardWindow(window) {
      window.orderOut(nil)
    }
  }

  static func closeDuplicateDashboardWindows(keeping primary: NSWindow? = nil) {
    let windows = dashboardWindows()
    guard windows.count > 1 else { return }
    let keeper = primary ?? windows.first
    for window in windows where window !== keeper {
      window.orderOut(nil)
    }
  }

  static func hideToMenuBar() {
    guard !isHidingToMenuBar else { return }
    isHidingToMenuBar = true

    for window in NSApp.windows {
      window.orderOut(nil)
    }
    NSApp.hide(nil)
    NSApp.setActivationPolicy(.accessory)

    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.accessory)
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
