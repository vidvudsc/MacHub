import AppKit

enum AppVisibilityService {
  static func showDashboard() {
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func hideToMenuBar() {
    for window in NSApp.windows {
      window.orderOut(nil)
    }
    NSApp.setActivationPolicy(.accessory)
  }
}
