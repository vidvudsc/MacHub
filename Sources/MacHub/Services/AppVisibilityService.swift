import AppKit
import Carbon

enum AppVisibilityService {
  private static let preferredDashboardContentSize = NSSize(width: 980, height: 680)
  private static var isHidingToMenuBar = false

  static func configureDashboardWindow(_ window: NSWindow?) {
    guard let window, isDashboardWindow(window) else { return }
    window.isReleasedWhenClosed = false
    window.delegate = DashboardWindowDelegate.shared
    _ = window.setFrameAutosaveName("")
    closeDuplicateDashboardWindows(keeping: window)
  }

  static func showDashboard() {
    showDashboard(attempt: 0)
  }

  private static func showDashboard(attempt: Int) {
    isHidingToMenuBar = false
    transformProcess(to: ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
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
    applyDefaultDashboardSizeIfNeeded(primary)
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
      window.close()
    }
  }

  static func hideToMenuBar() {
    guard beginHidingToMenuBar() else { return }

    let windows = dashboardWindows()
    if windows.isEmpty {
      finishHidingToMenuBar()
      return
    }

    for window in windows {
      window.close()
    }

    DispatchQueue.main.async {
      finishHidingToMenuBar()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      finishHidingToMenuBar()
    }
  }

  fileprivate static func closeButtonWillCloseDashboard() {
    guard beginHidingToMenuBar() else { return }
    DispatchQueue.main.async {
      finishHidingToMenuBar()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      finishHidingToMenuBar()
    }
  }

  private static func beginHidingToMenuBar() -> Bool {
    guard !isHidingToMenuBar else { return false }
    isHidingToMenuBar = true
    return true
  }

  private static func finishHidingToMenuBar() {
    activateFallbackApplication()
    NSApp.setActivationPolicy(.accessory)
    isHidingToMenuBar = false
  }

  private static func applyDefaultDashboardSizeIfNeeded(_ window: NSWindow) {
    guard window.frame.width < 900 || window.frame.height < 620 else { return }
    let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let width = min(preferredDashboardContentSize.width, visibleFrame.width)
    let height = min(preferredDashboardContentSize.height, visibleFrame.height)
    let frame = CGRect(
      x: visibleFrame.midX - width / 2,
      y: visibleFrame.midY - height / 2,
      width: width,
      height: height
    )
    window.setFrame(frame.integral, display: true, animate: false)
  }

  private static func activateFallbackApplication() {
    if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
      finder.activate()
    } else {
      NSWorkspace.shared.runningApplications
        .first { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }?
        .activate()
    }
  }

  private static func transformProcess(to transformState: ProcessApplicationTransformState) {
    var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
    TransformProcessType(&process, transformState)
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
    AppVisibilityService.closeButtonWillCloseDashboard()
    return true
  }

  func windowWillMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    AppVisibilityService.hideToMenuBar()
    DispatchQueue.main.async {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.close()
    }
  }
}
