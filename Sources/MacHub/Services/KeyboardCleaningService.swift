import CoreGraphics
import Foundation

final class KeyboardCleaningService {
  static let shared = KeyboardCleaningService()

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private init() {}

  var isEnabled: Bool {
    eventTap != nil
  }

  @discardableResult
  func setEnabled(_ isEnabled: Bool) -> Bool {
    if isEnabled {
      return enable()
    }
    disable()
    return false
  }

  @discardableResult
  func toggle() -> Bool {
    setEnabled(!isEnabled)
  }

  @discardableResult
  private func enable() -> Bool {
    guard !isEnabled else { return true }
    let mask =
      (1 << CGEventType.keyDown.rawValue) |
      (1 << CGEventType.keyUp.rawValue) |
      (1 << CGEventType.flagsChanged.rawValue) |
      (1 << 14)

    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(mask),
      callback: Self.handleEvent,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      return false
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    return true
  }

  private func disable() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
  }

  private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
      return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<KeyboardCleaningService>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap = service.eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    return nil
  }

  deinit {
    disable()
  }
}
