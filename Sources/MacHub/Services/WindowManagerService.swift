import ApplicationServices
import AppKit
import Foundation

enum WindowLayout: String, CaseIterable, Identifiable {
  case leftHalf = "Left Half"
  case rightHalf = "Right Half"
  case topHalf = "Top Half"
  case bottomHalf = "Bottom Half"
  case maximize = "Maximize"
  case center = "Center"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .leftHalf: "rectangle.leadinghalf.inset.filled"
    case .rightHalf: "rectangle.trailinghalf.inset.filled"
    case .topHalf: "rectangle.tophalf.inset.filled"
    case .bottomHalf: "rectangle.bottomhalf.inset.filled"
    case .maximize: "arrow.up.left.and.arrow.down.right"
    case .center: "scope"
    }
  }

  var shortcutLabel: String {
    switch self {
    case .leftHalf: "⌘⇧←"
    case .rightHalf: "⌘⇧→"
    case .topHalf: "⌘⇧↑"
    case .bottomHalf: "⌘⇧↓"
    case .maximize: "⌘⇧M"
    case .center: "⌘⇧C"
    }
  }
}

enum WindowManagerService {
  enum WindowError: Error {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noFocusedWindow
    case cannotMoveWindow
  }

  static var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  static func requestAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
  }

  static func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  static func apply(_ layout: WindowLayout) async throws {
    guard AXIsProcessTrusted() else {
      requestAccessibilityPermission()
      throw WindowError.accessibilityPermissionMissing
    }

    guard let app = NSWorkspace.shared.frontmostApplication else {
      throw WindowError.noFrontmostApplication
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = focusedWindow(in: appElement) ?? firstWindow(in: appElement) else {
      throw WindowError.noFocusedWindow
    }
    let frame = frame(for: layout, visibleFrame: activeScreenVisibleFrame())

    var origin = frame.origin
    var size = frame.size
    guard
      let originValue = AXValueCreate(.cgPoint, &origin),
      let sizeValue = AXValueCreate(.cgSize, &size)
    else {
      throw WindowError.cannotMoveWindow
    }

    let positionStatus = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
    let sizeStatus = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    guard positionStatus == .success, sizeStatus == .success else {
      throw WindowError.cannotMoveWindow
    }
  }

  private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
    var focusedWindowValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    )
    guard status == .success, let focusedWindowValue else {
      return nil
    }
    return (focusedWindowValue as! AXUIElement)
  }

  private static func firstWindow(in appElement: AXUIElement) -> AXUIElement? {
    var windowsValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      appElement,
      kAXWindowsAttribute as CFString,
      &windowsValue
    )
    guard
      status == .success,
      let windows = windowsValue as? [AXUIElement],
      let first = windows.first
    else {
      return nil
    }
    return first
  }

  private static func activeScreenVisibleFrame() -> CGRect {
    guard let mouseLocation = CGEvent(source: nil)?.location else {
      return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
    }

    return NSScreen.screens.first { screen in
      screen.frame.contains(mouseLocation)
    }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
  }

  private static func frame(for layout: WindowLayout, visibleFrame: CGRect) -> CGRect {
    switch layout {
    case .leftHalf:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
    case .rightHalf:
      return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
    case .topHalf:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: visibleFrame.height / 2)
    case .bottomHalf:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: visibleFrame.height / 2)
    case .maximize:
      return visibleFrame
    case .center:
      let width = visibleFrame.width * 0.72
      let height = visibleFrame.height * 0.78
      return CGRect(
        x: visibleFrame.midX - width / 2,
        y: visibleFrame.midY - height / 2,
        width: width,
        height: height
      )
    }
  }
}
