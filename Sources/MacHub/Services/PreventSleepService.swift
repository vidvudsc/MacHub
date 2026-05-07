import Foundation
import IOKit.pwr_mgt

final class PreventSleepService {
  static let shared = PreventSleepService()

  private var assertionID = IOPMAssertionID(0)

  private init() {}

  var isEnabled: Bool {
    assertionID != 0
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
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "MacHub prevent sleeping" as CFString,
      &assertionID
    )
    if result != kIOReturnSuccess {
      assertionID = 0
    }
    return isEnabled
  }

  private func disable() {
    guard isEnabled else { return }
    IOPMAssertionRelease(assertionID)
    assertionID = 0
  }

  deinit {
    disable()
  }
}
