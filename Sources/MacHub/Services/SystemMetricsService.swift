import Darwin
import Foundation
import IOKit
import IOKit.ps
import MacHubSMC
import Metal

actor SystemMetricsService {
  private var previousCPU = host_cpu_load_info()
  private var previousNetworkTotals: (received: UInt64, sent: UInt64, date: Date)?
  private var previousDiskTotal: (bytes: UInt64, date: Date)?
  private let smcPowerReader = AppleSMCPowerReader()
  private var previousPowerSamples: [Int: ProcessPowerSample] = [:]
  private var previousPowerSampleDate: Date?
  private var cachedTopPowerApp: (date: Date, app: PowerAppInfo?)?
  private var cachedBatteryDetails: (date: Date, details: BatteryDetails)?
  private var cachedGPU: GPUInfo?
  private var cachedProcessCount = 0
  private var isRefreshingSlowMetrics = false
  private var lastSlowMetricsRefresh: Date?
  private let slowMetricsInterval: TimeInterval = 10
  private let batteryDetailsCacheInterval: TimeInterval = 10

  func batterySnapshot() async -> BatteryInfo {
    await batteryInfo()
  }

  func snapshot() async -> SystemSnapshot {
    async let battery = batteryInfo()

    let cpu = cpuUsage()
    let memory = memoryUsage()
    let disk = diskUsage()
    let networkRates = await networkRates()
    let diskRate = await diskRate()
    let batteryInfo = await battery
    scheduleSlowMetricsRefresh(systemWatts: batteryInfo.systemWatts ?? batteryInfo.watts.map(abs), systemCPUUsage: cpu)

    return SystemSnapshot(
      cpuUsage: cpu,
      memoryUsed: memory.used,
      memoryTotal: memory.total,
      memoryWired: memory.wired,
      memoryCompressed: memory.compressed,
      memoryCached: memory.cached,
      diskUsed: disk.used,
      diskTotal: disk.total,
      networkInPerSecond: networkRates.received,
      networkOutPerSecond: networkRates.sent,
      diskBytesPerSecond: diskRate,
      battery: batteryInfo,
      gpu: cachedGPU ?? .empty,
      topPowerApp: cachedTopPowerApp?.app,
      uptime: ProcessInfo.processInfo.systemUptime,
      processCount: cachedProcessCount
    )
  }

  private func scheduleSlowMetricsRefresh(systemWatts: Double?, systemCPUUsage: Double) {
    guard !isRefreshingSlowMetrics else { return }
    if let lastSlowMetricsRefresh, Date().timeIntervalSince(lastSlowMetricsRefresh) < slowMetricsInterval {
      return
    }

    isRefreshingSlowMetrics = true
    Task {
      await refreshSlowMetrics(systemWatts: systemWatts, systemCPUUsage: systemCPUUsage)
    }
  }

  private func refreshSlowMetrics(systemWatts: Double?, systemCPUUsage: Double) async {
    async let gpu = gpuInfo()
    async let processCount = countProcesses()
    async let topPowerApp = topPowerHungryApp(systemWatts: systemWatts, systemCPUUsage: systemCPUUsage)

    cachedGPU = await gpu
    cachedProcessCount = await processCount
    cachedTopPowerApp = (Date(), await topPowerApp)
    lastSlowMetricsRefresh = Date()
    isRefreshingSlowMetrics = false
  }

  private func cpuUsage() -> Double {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }

    let user = Double(info.cpu_ticks.0 - previousCPU.cpu_ticks.0)
    let system = Double(info.cpu_ticks.1 - previousCPU.cpu_ticks.1)
    let idle = Double(info.cpu_ticks.2 - previousCPU.cpu_ticks.2)
    let nice = Double(info.cpu_ticks.3 - previousCPU.cpu_ticks.3)
    previousCPU = info

    let total = user + system + idle + nice
    guard total > 0 else { return 0 }
    return max(0, min(1, (total - idle) / total))
  }

  private func memoryUsage() -> (used: UInt64, total: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64) {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return (0, ProcessInfo.processInfo.physicalMemory, 0, 0, 0)
    }

    let pageSize = UInt64(vm_kernel_page_size)
    let active = UInt64(stats.active_count) * pageSize
    let inactive = UInt64(stats.inactive_count) * pageSize
    let wired = UInt64(stats.wire_count) * pageSize
    let compressed = UInt64(stats.compressor_page_count) * pageSize
    let speculative = UInt64(stats.speculative_count) * pageSize
    let purgeable = UInt64(stats.purgeable_count) * pageSize
    let external = UInt64(stats.external_page_count) * pageSize
    let total = ProcessInfo.processInfo.physicalMemory
    let cached = inactive + speculative + purgeable + external
    let used = active + wired + compressed
    return (min(used, total), total, wired, compressed, min(cached, total))
  }

  private func diskUsage() -> (used: UInt64, total: UInt64) {
    guard
      let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
      let total = attributes[.systemSize] as? NSNumber,
      let free = attributes[.systemFreeSize] as? NSNumber
    else {
      return (0, 0)
    }
    let totalBytes = total.uint64Value
    return (totalBytes - free.uint64Value, totalBytes)
  }

  private func batteryInfo() async -> BatteryInfo {
    guard
      let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
      let source = list.first,
      let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
    else {
      return .empty
    }

    let current = number(description[kIOPSCurrentCapacityKey]).doubleValue
    let max = number(description[kIOPSMaxCapacityKey]).doubleValue
    let percent = max > 0 ? current / max : 0
    let state = description[kIOPSPowerSourceStateKey] as? String
    let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
    let pluggedIn = state == kIOPSACPowerValue
    let minutes = (description[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
      ?? (description[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
    let batteryDetails = await smartBatteryDetails()
    let livePower = try? smcPowerReader.powerDistribution()

    return BatteryInfo(
      percent: percent,
      isPresent: true,
      isCharging: isCharging,
      isPluggedIn: pluggedIn,
      timeRemainingMinutes: minutes,
      watts: livePower?.batteryPower ?? batteryDetails.watts,
      externalWatts: livePower?.externalPower,
      systemWatts: livePower?.systemPower,
      voltage: batteryDetails.voltage,
      amperage: batteryDetails.amperage,
      temperature: batteryDetails.temperature,
      cycleCount: batteryDetails.cycleCount,
      health: batteryDetails.health
    )
  }

  private func smartBatteryDetails() async -> BatteryDetails {
    if let cachedBatteryDetails, Date().timeIntervalSince(cachedBatteryDetails.date) < batteryDetailsCacheInterval {
      return cachedBatteryDetails.details
    }

    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else {
      return cachedBatteryDetails?.details ?? BatteryDetails()
    }
    defer { IOObjectRelease(service) }

    let properties: [String: Any] = [
      "AppleRawBatteryVoltage": registryValue("AppleRawBatteryVoltage", from: service) as Any,
      "Voltage": registryValue("Voltage", from: service) as Any,
      "InstantAmperage": registryValue("InstantAmperage", from: service) as Any,
      "Amperage": registryValue("Amperage", from: service) as Any,
      "PowerTelemetryData": registryValue("PowerTelemetryData", from: service) as Any,
      "CycleCount": registryValue("CycleCount", from: service) as Any,
      "Temperature": registryValue("Temperature", from: service) as Any,
      "VirtualTemperature": registryValue("VirtualTemperature", from: service) as Any,
      "BatteryHealth": registryValue("BatteryHealth", from: service) as Any,
      "PermanentFailureStatus": registryValue("PermanentFailureStatus", from: service) as Any
    ].compactMapValues { value in
      if case Optional<Any>.none = value {
        return nil
      }
      return value
    }

    let details = BatteryTelemetryParser.details(from: properties)
    cachedBatteryDetails = (Date(), details)
    return details
  }

  private func registryValue(_ key: String, from service: io_service_t) -> Any? {
    guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
      return nil
    }
    return value.takeRetainedValue()
  }

  private func gpuInfo() async -> GPUInfo {
    if let cachedGPU {
      return cachedGPU
    }

    guard let device = MTLCreateSystemDefaultDevice() else {
      return .empty
    }

    let memory = device.recommendedMaxWorkingSetSize > 0
      ? Formatters.memory(device.recommendedMaxWorkingSetSize)
      : "Unified memory"
    let gpu = GPUInfo(
      name: device.name,
      vram: memory,
      metal: device.hasUnifiedMemory ? "Metal, unified memory" : "Metal, dedicated memory"
    )
    cachedGPU = gpu
    return gpu
  }

  private func networkRates() async -> (received: UInt64, sent: UInt64) {
    let totals = await networkTotals()
    let now = Date()
    defer { previousNetworkTotals = (totals.received, totals.sent, now) }

    guard let previousNetworkTotals else { return (0, 0) }
    let elapsed = max(now.timeIntervalSince(previousNetworkTotals.date), 0.1)
    let received = totals.received > previousNetworkTotals.received ? totals.received - previousNetworkTotals.received : 0
    let sent = totals.sent > previousNetworkTotals.sent ? totals.sent - previousNetworkTotals.sent : 0
    return (UInt64(Double(received) / elapsed), UInt64(Double(sent) / elapsed))
  }

  private func networkTotals() async -> (received: UInt64, sent: UInt64) {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0, let firstAddress else {
      return (0, 0)
    }
    defer { freeifaddrs(firstAddress) }

    var received: UInt64 = 0
    var sent: UInt64 = 0
    var countedInterfaces = Set<String>()
    var address = Optional(firstAddress)
    while let current = address {
      let interface = current.pointee
      defer { address = interface.ifa_next }
      guard
        let socketAddress = interface.ifa_addr,
        Int32(socketAddress.pointee.sa_family) == AF_LINK,
        let data = interface.ifa_data
      else {
        continue
      }

      let name = String(cString: interface.ifa_name)
      guard
        !name.hasPrefix("lo"),
        !name.hasPrefix("gif"),
        !name.hasPrefix("stf"),
        !name.hasPrefix("bridge"),
        !countedInterfaces.contains(name)
      else {
        continue
      }

      let stats = data.assumingMemoryBound(to: if_data.self).pointee
      received += UInt64(stats.ifi_ibytes)
      sent += UInt64(stats.ifi_obytes)
      countedInterfaces.insert(name)
    }

    return (received, sent)
  }

  private func diskRate() async -> UInt64 {
    let total = await diskTransferTotal()
    let now = Date()
    defer { previousDiskTotal = (total, now) }

    guard let previousDiskTotal else { return 0 }
    let elapsed = max(now.timeIntervalSince(previousDiskTotal.date), 0.1)
    let delta = total > previousDiskTotal.bytes ? total - previousDiskTotal.bytes : 0
    return UInt64(Double(delta) / elapsed)
  }

  private func diskTransferTotal() async -> UInt64 {
    guard let matching = IOServiceMatching("IOMedia") else {
      return 0
    }
    CFDictionarySetValue(
      matching,
      Unmanaged.passUnretained("Whole" as CFString).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )

    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
      return 0
    }
    defer { IOObjectRelease(iterator) }

    var total: UInt64 = 0
    while true {
      let media = IOIteratorNext(iterator)
      if media == IO_OBJECT_NULL {
        break
      }
      defer { IOObjectRelease(media) }

      var parent: io_registry_entry_t = 0
      guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS else {
        continue
      }
      defer { IOObjectRelease(parent) }

      guard IOObjectConformsTo(parent, "IOBlockStorageDriver") != 0 else {
        continue
      }
      total += blockStorageTransferTotal(parent)
    }

    return total
  }

  private func blockStorageTransferTotal(_ driver: io_registry_entry_t) -> UInt64 {
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(driver, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let dictionary = properties?.takeRetainedValue() as? [String: Any],
      let statistics = dictionary["Statistics"] as? [String: Any]
    else {
      return 0
    }

    return unsignedNumber(statistics["Bytes (Read)"]) + unsignedNumber(statistics["Bytes (Write)"])
  }

  private func countProcesses() async -> Int {
    max(Int(proc_listallpids(nil, 0)), 0)
  }

  private func topPowerHungryApp(systemWatts: Double?, systemCPUUsage: Double) async -> PowerAppInfo? {
    if let cachedTopPowerApp, Date().timeIntervalSince(cachedTopPowerApp.date) < 9 {
      return cachedTopPowerApp.app
    }

    let samples = processPowerSamples()
    guard !samples.isEmpty else {
      return cachedTopPowerApp?.app
    }

    let now = Date()
    defer {
      previousPowerSamples = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
      previousPowerSampleDate = now
    }

    guard let previousPowerSampleDate else {
      return nil
    }

    let elapsed = max(now.timeIntervalSince(previousPowerSampleDate), 0.25)
    var apps: [String: (cpuPercent: Double, memoryBytes: UInt64)] = [:]
    for sample in samples {
      guard let previous = previousPowerSamples[sample.pid] else { continue }
      let cpuSeconds = sample.cpuSeconds - previous.cpuSeconds
      guard cpuSeconds > 0 else {
        apps[sample.name, default: (0, 0)].memoryBytes += sample.memoryBytes
        continue
      }
      let cpuPercent = min(max(cpuSeconds / elapsed * 100, 0), 1600)
      apps[sample.name, default: (0, 0)].cpuPercent += cpuPercent
      apps[sample.name, default: (0, 0)].memoryBytes += sample.memoryBytes
    }

    guard let top = apps.max(by: { $0.value.cpuPercent < $1.value.cpuPercent }), top.value.cpuPercent > 0.1 else {
      cachedTopPowerApp = (now, nil)
      return nil
    }

    let totalActiveCPU = max(apps.values.reduce(0) { $0 + $1.cpuPercent }, top.value.cpuPercent)
    let appShare = min(max(top.value.cpuPercent / totalActiveCPU, 0), 1)
    let estimatedWatts: Double?
    if let systemWatts, systemWatts > 0.1, systemCPUUsage > 0.01 {
      let variablePower = max(systemWatts - 4, systemWatts * min(systemCPUUsage, 0.65))
      estimatedWatts = min(systemWatts, max(0, variablePower * appShare))
    } else {
      estimatedWatts = nil
    }

    let app = PowerAppInfo(
      name: top.key,
      cpuPercent: top.value.cpuPercent,
      memoryBytes: top.value.memoryBytes,
      estimatedWatts: estimatedWatts
    )
    cachedTopPowerApp = (now, app)
    return app
  }

  private func processPowerSamples() -> [ProcessPowerSample] {
    let capacity = max(Int(proc_listallpids(nil, 0)), 0) + 64
    guard capacity > 0 else { return [] }

    var pids = Array(repeating: pid_t(), count: capacity)
    let count = pids.withUnsafeMutableBufferPointer {
      proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride))
    }

    return pids
      .prefix(max(Int(count), 0))
      .compactMap { pid in
        guard pid > 0, pid != getpid() else { return nil }
        return processPowerSample(pid: pid)
      }
  }

  private func processPowerSample(pid: pid_t) -> ProcessPowerSample? {
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    guard status == 0 else { return nil }

    var nameBuffer = Array(repeating: CChar(0), count: 1024)
    let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
    guard nameLength > 0 else { return nil }

    let name = String(cString: nameBuffer)
    guard !name.isEmpty, name != "MacHub" else { return nil }
    return ProcessPowerSample(
      pid: Int(pid),
      name: name,
      cpuSeconds: Double(info.ri_user_time + info.ri_system_time) / 1_000_000_000,
      memoryBytes: info.ri_resident_size
    )
  }

  private func number(_ value: Any?) -> NSNumber {
    if let number = value as? NSNumber { return number }
    if let int = value as? Int { return NSNumber(value: int) }
    if let double = value as? Double { return NSNumber(value: double) }
    return 0
  }

  private func unsignedNumber(_ value: Any?) -> UInt64 {
    if let number = value as? NSNumber {
      return number.uint64Value
    }
    if let uint64 = value as? UInt64 {
      return uint64
    }
    if let int = value as? Int {
      return UInt64(max(int, 0))
    }
    return 0
  }
}

private struct ProcessPowerSample {
  var pid: Int
  var name: String
  var cpuSeconds: Double
  var memoryBytes: UInt64
}
