import ApplicationServices
import AppKit
import Carbon
import Foundation

enum WindowLayout: String, CaseIterable, Identifiable {
  case leftHalf = "Left Half"
  case rightHalf = "Right Half"
  case maximize = "Full View"
  case center = "Center"
  case topLeft = "Top Left"
  case topRight = "Top Right"
  case bottomLeft = "Bottom Left"
  case bottomRight = "Bottom Right"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .leftHalf: "rectangle.leadinghalf.inset.filled"
    case .rightHalf: "rectangle.trailinghalf.inset.filled"
    case .maximize: "arrow.up.left.and.arrow.down.right"
    case .center: "scope"
    case .topLeft: "arrow.up.left"
    case .topRight: "arrow.up.right"
    case .bottomLeft: "arrow.down.left"
    case .bottomRight: "arrow.down.right"
    }
  }

  var defaultShortcut: WindowShortcut {
    switch self {
    case .leftHalf: WindowShortcut(keyCode: 123, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧←")
    case .rightHalf: WindowShortcut(keyCode: 124, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧→")
    case .maximize: WindowShortcut(keyCode: 126, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧↑")
    case .center: WindowShortcut(keyCode: 125, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧↓")
    case .topLeft: WindowShortcut(keyCode: 12, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧Q")
    case .topRight: WindowShortcut(keyCode: 13, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧W")
    case .bottomLeft: WindowShortcut(keyCode: 14, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧E")
    case .bottomRight: WindowShortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey), displayLabel: "⌘⇧R")
    }
  }

  var shortcutLabel: String {
    WindowShortcutStore.shared.shortcut(for: self).displayLabel
  }

  fileprivate var horizontalAnchor: WindowHorizontalAnchor {
    switch self {
    case .leftHalf, .topLeft, .bottomLeft:
      return .leading
    case .center, .maximize:
      return .center
    case .rightHalf, .topRight, .bottomRight:
      return .trailing
    }
  }

  fileprivate var verticalAnchor: WindowVerticalAnchor {
    switch self {
    case .topLeft, .topRight:
      return .top
    case .center, .leftHalf, .rightHalf, .maximize:
      return .center
    case .bottomLeft, .bottomRight:
      return .bottom
    }
  }
}

private enum WindowHorizontalAnchor {
  case leading
  case center
  case trailing
}

private enum WindowVerticalAnchor {
  case top
  case center
  case bottom
}

private struct WindowTargetScreen {
  let screen: NSScreen
  let axFrame: CGRect
  let axVisibleFrame: CGRect
}

struct WindowShortcut: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayLabel: String
}

final class WindowShortcutStore {
  static let shared = WindowShortcutStore()

  private let defaults = UserDefaults.standard
  private let prefix = "windowShortcut."

  private init() { }

  func shortcut(for layout: WindowLayout) -> WindowShortcut {
    let key = prefix + layout.id
    guard
      let data = defaults.data(forKey: key),
      let shortcut = try? JSONDecoder().decode(WindowShortcut.self, from: data)
    else {
      return layout.defaultShortcut
    }
    return shortcut
  }

  func setShortcut(_ shortcut: WindowShortcut, for layout: WindowLayout) {
    let key = prefix + layout.id
    guard let data = try? JSONEncoder().encode(shortcut) else { return }
    defaults.set(data, forKey: key)
  }

  func resetShortcut(for layout: WindowLayout) {
    defaults.removeObject(forKey: prefix + layout.id)
  }
}

enum WindowManagerService {
  enum WindowError: Error {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noFocusedWindow
    case cannotMoveWindow(position: AXError, size: AXError)
  }

  static var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  private static let operationLock = WindowOperationLock()
  private static var lastTargetApp: NSRunningApplication?

  static func noteActivatedApplication(_ app: NSRunningApplication) {
    guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
    lastTargetApp = app
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
    await operationLock.acquire()
    do {
      try await applyLocked(layout)
      await operationLock.release()
    } catch {
      await operationLock.release()
      throw error
    }
  }

  private static func applyLocked(_ layout: WindowLayout) async throws {
    guard AXIsProcessTrusted() else {
      throw WindowError.accessibilityPermissionMissing
    }

    guard let window = focusedTargetWindow() ?? fallbackTargetWindow() else {
      throw WindowError.noFocusedWindow
    }
    guard let targetScreen = targetScreen(containing: window) ?? activeTargetScreen() else {
      throw WindowError.noFocusedWindow
    }
    let targetFrame = frame(for: layout, visibleFrame: targetScreen.axVisibleFrame)

    guard isAttributeSettable(kAXSizeAttribute as CFString, on: window),
          isAttributeSettable(kAXPositionAttribute as CFString, on: window) else {
      throw WindowError.cannotMoveWindow(position: .attributeUnsupported, size: .attributeUnsupported)
    }

    AXUIElementSetMessagingTimeout(window, 1.0)

    try await setAnchoredFrame(targetFrame, layout: layout, on: targetScreen, window: window)
    try await Task.sleep(nanoseconds: 90_000_000)
    if !isFrame(window, closeTo: expectedAccessibilityFrame(for: layout, targetFrame: targetFrame, targetScreen: targetScreen, window: window)) {
      try await setAnchoredFrame(targetFrame, layout: layout, on: targetScreen, window: window)
      try await Task.sleep(nanoseconds: 90_000_000)
    }
    if !isFrame(window, closeTo: expectedAccessibilityFrame(for: layout, targetFrame: targetFrame, targetScreen: targetScreen, window: window)) {
      try await setAnchoredFrame(targetFrame, layout: layout, on: targetScreen, window: window)
    }
  }

  private static func expectedAccessibilityFrame(
    for layout: WindowLayout,
    targetFrame: CGRect,
    targetScreen: WindowTargetScreen,
    window: AXUIElement
  ) -> CGRect {
    let actualSize = currentFrame(of: window)?.size ?? targetFrame.size
    return constrainedFrame(
      anchoredFrame(for: layout, targetFrame: targetFrame, actualSize: actualSize),
      to: targetScreen.axVisibleFrame
    )
  }

  private static func setAnchoredFrame(_ targetFrame: CGRect, layout: WindowLayout, on targetScreen: WindowTargetScreen, window: AXUIElement) async throws {
    if shouldPrepositionForGrowth(window: window, targetSize: targetFrame.size) {
      try setPosition(targetFrame.origin, on: window)
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    let actualSize = try await driveSize(targetFrame.size, on: window)
    let firstAnchoredFrame = constrainedFrame(
      anchoredFrame(for: layout, targetFrame: targetFrame, actualSize: actualSize),
      to: targetScreen.axVisibleFrame
    )
    try setPosition(firstAnchoredFrame.origin, on: window)
    try await Task.sleep(nanoseconds: 35_000_000)

    let finalSize = currentFrame(of: window)?.size ?? actualSize
    let finalAnchoredFrame = constrainedFrame(
      anchoredFrame(for: layout, targetFrame: targetFrame, actualSize: finalSize),
      to: targetScreen.axVisibleFrame
    )
    try setPosition(finalAnchoredFrame.origin, on: window)
  }

  private static func shouldPrepositionForGrowth(window: AXUIElement, targetSize: CGSize) -> Bool {
    guard let currentSize = currentFrame(of: window)?.size else { return true }
    return targetSize.width > currentSize.width + 6 ||
      targetSize.height > currentSize.height + 6
  }

  private static func driveSize(_ target: CGSize, on window: AXUIElement) async throws -> CGSize {
    var latestSize = currentFrame(of: window)?.size ?? target
    var bestSize = latestSize
    var bestError = sizeError(latestSize, target: target)
    var previousSize = latestSize
    var previousError = bestError
    var stagnantAttempts = 0

    for _ in 0..<8 {
      try setSize(target, on: window)
      try? await Task.sleep(nanoseconds: 55_000_000)
      guard let size = currentFrame(of: window)?.size else { continue }
      latestSize = size
      let error = sizeError(size, target: target)

      if error < bestError {
        bestSize = size
        bestError = error
      }

      if isSize(size, closeTo: target) {
        return size
      }

      let sizeDelta = abs(size.width - previousSize.width) + abs(size.height - previousSize.height)
      if sizeDelta <= 2 && error >= previousError - 2 {
        stagnantAttempts += 1
      } else {
        stagnantAttempts = 0
      }

      previousSize = size
      previousError = error

      if stagnantAttempts >= 2 {
        return bestError <= error ? bestSize : size
      }
    }

    return bestError < sizeError(latestSize, target: target) ? bestSize : latestSize
  }

  private static func sizeError(_ size: CGSize, target: CGSize) -> CGFloat {
    abs(size.width - target.width) + abs(size.height - target.height)
  }

  private static func isSize(_ size: CGSize, closeTo expected: CGSize) -> Bool {
    abs(size.width - expected.width) <= 6 &&
      abs(size.height - expected.height) <= 6
  }

  private static func setSize(_ size: CGSize, on window: AXUIElement) throws {
    var size = size
    guard let sizeValue = AXValueCreate(.cgSize, &size) else {
      throw WindowError.cannotMoveWindow(position: .failure, size: .failure)
    }

    let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    guard status == .success else {
      throw WindowError.cannotMoveWindow(position: .success, size: status)
    }
  }

  private static func setPosition(_ origin: CGPoint, on window: AXUIElement) throws {
    var origin = origin
    guard let originValue = AXValueCreate(.cgPoint, &origin) else {
      throw WindowError.cannotMoveWindow(position: .failure, size: .failure)
    }

    let status = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
    guard status == .success else {
      throw WindowError.cannotMoveWindow(position: status, size: .success)
    }
  }

  private static func isFrame(_ window: AXUIElement, closeTo expected: CGRect) -> Bool {
    guard let current = currentFrame(of: window) else { return false }
    return abs(current.minX - expected.minX) <= 3 &&
      abs(current.minY - expected.minY) <= 3 &&
      abs(current.width - expected.width) <= 6 &&
      abs(current.height - expected.height) <= 6
  }

  private static func currentFrame(of window: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
      let positionValue,
      let sizeValue
    else {
      return nil
    }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard
      AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    return CGRect(origin: origin, size: size)
  }

  private static func focusedTargetWindow() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedAppValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      systemWide,
      kAXFocusedApplicationAttribute as CFString,
      &focusedAppValue
    )
    guard status == .success, let focusedAppValue else { return nil }

    let appElement = focusedAppValue as! AXUIElement
    var pid: pid_t = 0
    AXUIElementGetPid(appElement, &pid)
    guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

    return focusedWindow(in: appElement) ?? firstWindow(in: appElement)
  }

  private static func fallbackTargetWindow() -> AXUIElement? {
    guard let app = targetApplication() else { return nil }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    return focusedWindow(in: appElement) ?? firstWindow(in: appElement)
  }

  private static func targetApplication() -> NSRunningApplication? {
    let frontmost = NSWorkspace.shared.frontmostApplication
    if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
      return frontmost
    }

    if let lastTargetApp, !lastTargetApp.isTerminated {
      return lastTargetApp
    }

    return NSWorkspace.shared.runningApplications.first { app in
      app.activationPolicy == .regular &&
        app.bundleIdentifier != Bundle.main.bundleIdentifier &&
        !app.isTerminated
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

  private static func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
    return status == .success && settable.boolValue
  }

  private static func activeTargetScreen() -> WindowTargetScreen? {
    guard let mouseLocation = CGEvent(source: nil)?.location else {
      return (NSScreen.main ?? NSScreen.screens.first).flatMap(targetScreen(for:))
    }

    return NSScreen.screens
      .compactMap(targetScreen(for:))
      .first { $0.axFrame.contains(mouseLocation) }
      ?? (NSScreen.main ?? NSScreen.screens.first).flatMap(targetScreen(for:))
  }

  private static func targetScreen(containing window: AXUIElement) -> WindowTargetScreen? {
    guard let frame = currentFrame(of: window) else { return nil }

    let rankedScreens = NSScreen.screens.compactMap { screen -> (targetScreen: WindowTargetScreen, area: CGFloat)? in
      guard let targetScreen = targetScreen(for: screen) else { return nil }
      let intersection = frame.intersection(targetScreen.axFrame)
      guard !intersection.isNull else { return nil }
      return (targetScreen, intersection.width * intersection.height)
    }

    if let best = rankedScreens.max(by: { $0.area < $1.area }), best.area > 0 {
      return best.targetScreen
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    return NSScreen.screens
      .compactMap(targetScreen(for:))
      .first { $0.axFrame.contains(center) }
  }

  private static func targetScreen(for screen: NSScreen) -> WindowTargetScreen? {
    guard
      let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
      return nil
    }

    let displayID = CGDirectDisplayID(screenNumber.uint32Value)
    let axFrame = CGDisplayBounds(displayID)
    guard !axFrame.isNull, axFrame.width > 0, axFrame.height > 0 else { return nil }

    let appKitFrame = screen.frame
    let visibleFrame = screen.visibleFrame
    let leftInset = max(visibleFrame.minX - appKitFrame.minX, 0)
    let rightInset = max(appKitFrame.maxX - visibleFrame.maxX, 0)
    let topInset = max(appKitFrame.maxY - visibleFrame.maxY, 0)
    let bottomInset = max(visibleFrame.minY - appKitFrame.minY, 0)
    let axVisibleFrame = CGRect(
      x: axFrame.minX + leftInset,
      y: axFrame.minY + topInset,
      width: max(axFrame.width - leftInset - rightInset, 1),
      height: max(axFrame.height - topInset - bottomInset, 1)
    )
    return WindowTargetScreen(screen: screen, axFrame: axFrame, axVisibleFrame: axVisibleFrame)
  }

  private static func anchoredFrame(for layout: WindowLayout, targetFrame: CGRect, actualSize: CGSize) -> CGRect {
    let x: CGFloat
    switch layout.horizontalAnchor {
    case .leading:
      x = targetFrame.minX
    case .center:
      x = targetFrame.midX - actualSize.width / 2
    case .trailing:
      x = targetFrame.maxX - actualSize.width
    }

    let y: CGFloat
    switch layout.verticalAnchor {
    case .bottom:
      y = targetFrame.minY
    case .center:
      y = targetFrame.midY - actualSize.height / 2
    case .top:
      y = targetFrame.maxY - actualSize.height
    }

    return CGRect(origin: CGPoint(x: x, y: y), size: actualSize)
  }

  private static func constrainedFrame(_ frame: CGRect, to bounds: CGRect) -> CGRect {
    let x: CGFloat
    if frame.width >= bounds.width {
      x = bounds.minX
    } else {
      x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
    }

    let y: CGFloat
    if frame.height >= bounds.height {
      y = bounds.minY
    } else {
      y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
    }

    return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
  }

  private static func frame(for layout: WindowLayout, visibleFrame: CGRect) -> CGRect {
    switch layout {
    case .leftHalf:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
    case .rightHalf:
      return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
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
    case .topLeft:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width / 2, height: visibleFrame.height / 2)
    case .topRight:
      return CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: visibleFrame.width / 2, height: visibleFrame.height / 2)
    case .bottomLeft:
      return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height / 2)
    case .bottomRight:
      return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height / 2)
    }
  }
}

private actor WindowOperationLock {
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if !isLocked {
      isLocked = true
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    guard !waiters.isEmpty else {
      isLocked = false
      return
    }

    waiters.removeFirst().resume()
  }
}
