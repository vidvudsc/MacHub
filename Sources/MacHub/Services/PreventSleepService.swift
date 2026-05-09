import Foundation
import IOKit
import IOKit.pwr_mgt

final class PreventSleepService {
  static let shared = PreventSleepService()

  private var idleAssertionID = IOPMAssertionID(0)
  private var lidIdleAssertionID = IOPMAssertionID(0)
  private var lidSystemAssertionID = IOPMAssertionID(0)
  private var clamshellConnection: io_connect_t = 0
  private var clamshellDisplaySleepTask: Task<Void, Never>?
  private var isLidSleepOverrideActive = false

  private init() {}

  var isEnabled: Bool {
    idleAssertionID != 0
  }

  @discardableResult
  func setEnabled(_ isEnabled: Bool) -> Bool {
    if isEnabled {
      return enableIdleSleepPrevention()
    }
    disableIdleSleepPrevention()
    return false
  }

  @discardableResult
  func toggle() -> Bool {
    setEnabled(!isEnabled)
  }

  @discardableResult
  func setLidSleepOverride(_ isEnabled: Bool) async -> Bool {
    if isEnabled {
      guard enableClamshellSleepOverride() else {
        return await isLidSleepOverrideEnabled()
      }
      activateLidAwakeState()
    } else {
      deactivateLidAwakeState()
      disableClamshellSleepOverride()
    }
    return await isLidSleepOverrideEnabled()
  }

  @discardableResult
  func toggleLidSleepOverride() async -> Bool {
    await setLidSleepOverride(!(await isLidSleepOverrideEnabled()))
  }

  func isLidSleepOverrideEnabled() async -> Bool {
    isLidSleepOverrideActive
  }

  func refreshLidSleepOverrideState() -> Bool {
    if !isLidSleepOverrideActive {
      setClamshellDisplaySleepMonitoring(false)
      disableLidAwakeMode()
      disableClamshellSleepOverride()
    }
    return isLidSleepOverrideActive
  }

  func resetLidSleepOverrideForFreshLaunch() {
    deactivateLidAwakeState()
    disableClamshellSleepOverride()
  }

  func setClamshellDisplaySleepMonitoring(_ isEnabled: Bool) {
    if isEnabled {
      startClamshellDisplaySleepMonitoring()
    } else {
      stopClamshellDisplaySleepMonitoring()
    }
  }

  @discardableResult
  private func enableIdleSleepPrevention() -> Bool {
    guard !isEnabled else { return true }
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "MacHub prevent sleeping" as CFString,
      &idleAssertionID
    )
    if result != kIOReturnSuccess {
      idleAssertionID = 0
    }
    return isEnabled
  }

  private func disableIdleSleepPrevention() {
    guard isEnabled else { return }
    IOPMAssertionRelease(idleAssertionID)
    idleAssertionID = 0
  }

  private func activateLidAwakeState() {
    guard clamshellConnection != 0 || isClamshellSleepDisabled() else { return }
    enableLidAwakeMode()
    setClamshellDisplaySleepMonitoring(true)
    isLidSleepOverrideActive = true
  }

  private func deactivateLidAwakeState() {
    setClamshellDisplaySleepMonitoring(false)
    disableLidAwakeMode()
    isLidSleepOverrideActive = false
  }

  private func enableLidAwakeMode() {
    if lidIdleAssertionID == 0 {
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "MacHub lid awake mode" as CFString,
        &lidIdleAssertionID
      )
      if result != kIOReturnSuccess {
        lidIdleAssertionID = 0
      }
    }

    if lidSystemAssertionID == 0 {
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "MacHub lid awake mode" as CFString,
        &lidSystemAssertionID
      )
      if result != kIOReturnSuccess {
        lidSystemAssertionID = 0
      }
    }
  }

  private func disableLidAwakeMode() {
    if lidIdleAssertionID != 0 {
      IOPMAssertionRelease(lidIdleAssertionID)
      lidIdleAssertionID = 0
    }
    if lidSystemAssertionID != 0 {
      IOPMAssertionRelease(lidSystemAssertionID)
      lidSystemAssertionID = 0
    }
  }

  private func renewLidAwakeAssertionsIfNeeded() {
    guard lidIdleAssertionID != 0 || lidSystemAssertionID != 0 else { return }
    disableLidAwakeMode()
    enableLidAwakeMode()
  }

  private func enableClamshellSleepOverride() -> Bool {
    if clamshellConnection != 0 {
      return setClamshellSleepDisabled(true, on: clamshellConnection)
    }

    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }

    var connection: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard openResult == KERN_SUCCESS else { return false }

    guard setClamshellSleepDisabled(true, on: connection) else {
      IOServiceClose(connection)
      return false
    }
    clamshellConnection = connection
    return true
  }

  private func disableClamshellSleepOverride() {
    if clamshellConnection != 0 {
      _ = setClamshellSleepDisabled(false, on: clamshellConnection)
      IOServiceClose(clamshellConnection)
      clamshellConnection = 0
    } else if isClamshellSleepDisabled() {
      resetStaleClamshellSleepOverride()
    }
  }

  private func resetStaleClamshellSleepOverride() {
    guard enableClamshellSleepOverride() else { return }
    _ = setClamshellSleepDisabled(false, on: clamshellConnection)
    IOServiceClose(clamshellConnection)
    clamshellConnection = 0
  }

  private func setClamshellSleepDisabled(_ isDisabled: Bool, on connection: io_connect_t) -> Bool {
    var value: UInt64 = isDisabled ? 1 : 0
    let result = withUnsafePointer(to: &value) { pointer in
      IOConnectCallScalarMethod(
        connection,
        UInt32(kPMSetClamshellSleepState),
        pointer,
        1,
        nil,
        nil
      )
    }
    return result == KERN_SUCCESS
  }

  private func sleepDisplaysForLidMode() async {
    _ = try? await ProcessRunner.run(
      "/usr/bin/pmset",
      ["displaysleepnow"],
      timeout: 2
    )
  }

  private func startClamshellDisplaySleepMonitoring() {
    guard clamshellDisplaySleepTask == nil else { return }
    clamshellDisplaySleepTask = Task { [weak self] in
      var wasClosed = false
      var lastDisplaySleep = Date.distantPast
      while !Task.isCancelled {
        guard let self else { return }
        let isClosed = self.isClamshellClosed()
        if isClosed, !wasClosed, Date().timeIntervalSince(lastDisplaySleep) > 5 {
          self.renewLidAwakeAssertionsIfNeeded()
          await self.sleepDisplaysForLidMode()
          lastDisplaySleep = Date()
        }
        wasClosed = isClosed
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
      }
    }
  }

  private func stopClamshellDisplaySleepMonitoring() {
    clamshellDisplaySleepTask?.cancel()
    clamshellDisplaySleepTask = nil
  }

  private func isClamshellClosed() -> Bool {
    rootDomainBoolProperty("AppleClamshellState") ?? false
  }

  private func isClamshellSleepDisabled() -> Bool {
    guard let causesSleep = rootDomainBoolProperty("AppleClamshellCausesSleep") else {
      return false
    }
    return !causesSleep
  }

  private func rootDomainBoolProperty(_ key: String) -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    return IORegistryEntryCreateCFProperty(
      service,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Bool
  }

  deinit {
    disableIdleSleepPrevention()
    deactivateLidAwakeState()
    disableClamshellSleepOverride()
  }
}
