import Darwin
import Foundation
import IOKit.ps

actor SystemMetricsService {
  private var previousCPU = host_cpu_load_info()
  private var previousNetworkTotals: (received: UInt64, sent: UInt64, date: Date)?
  private var previousDiskTotal: (bytes: UInt64, date: Date)?
  private var previousPowerSamples: [Int: ProcessPowerSample] = [:]
  private var previousPowerSampleDate: Date?
  private var cachedTopPowerApp: (date: Date, app: PowerAppInfo?)?
  private var cachedBatteryDetails: (date: Date, details: BatteryDetails)?
  private var cachedGPU: GPUInfo?

  func batterySnapshot() async -> BatteryInfo {
    await batteryInfo()
  }

  func snapshot() async -> SystemSnapshot {
    async let battery = batteryInfo()
    async let gpu = gpuInfo()

    let cpu = cpuUsage()
    let memory = memoryUsage()
    let disk = diskUsage()
    let networkRates = await networkRates()
    let diskRate = await diskRate()
    let processCount = await countProcesses()
    let batteryInfo = await battery
    let gpuInfo = await gpu
    let topPowerApp = await topPowerHungryApp(
      systemWatts: batteryInfo.watts.map(abs),
      systemCPUUsage: cpu
    )

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
      gpu: gpuInfo,
      topPowerApp: topPowerApp,
      uptime: ProcessInfo.processInfo.systemUptime,
      processCount: processCount
    )
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

    return BatteryInfo(
      percent: percent,
      isPresent: true,
      isCharging: isCharging,
      isPluggedIn: pluggedIn,
      timeRemainingMinutes: minutes,
      watts: batteryDetails.watts,
      voltage: batteryDetails.voltage,
      amperage: batteryDetails.amperage,
      temperature: batteryDetails.temperature,
      cycleCount: batteryDetails.cycleCount,
      health: batteryDetails.health
    )
  }

  private func smartBatteryDetails() async -> BatteryDetails {
    if let cachedBatteryDetails, Date().timeIntervalSince(cachedBatteryDetails.date) < 0.5 {
      return cachedBatteryDetails.details
    }

    guard let output = try? await ProcessRunner.run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"], timeout: 2) else {
      return cachedBatteryDetails?.details ?? BatteryDetails()
    }

    let details = BatteryTelemetryParser.details(from: output)
    cachedBatteryDetails = (Date(), details)
    return details
  }

  private func gpuInfo() async -> GPUInfo {
    if let cachedGPU {
      return cachedGPU
    }

    guard let output = try? await ProcessRunner.run("/usr/sbin/system_profiler", ["SPDisplaysDataType"], timeout: 4) else {
      return .empty
    }

    let name = firstValue(after: "Chipset Model:", in: output) ?? firstValue(after: "Graphics:", in: output) ?? "Unknown GPU"
    let vram = firstValue(after: "VRAM", in: output) ?? firstValue(after: "Total Number of Cores:", in: output) ?? "Integrated"
    let metal = firstValue(after: "Metal Support:", in: output) ?? "Unknown Metal support"
    let gpu = GPUInfo(name: name, vram: vram, metal: metal)
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
    guard let output = try? await ProcessRunner.run("/usr/sbin/netstat", ["-ibn"], timeout: 2) else {
      return (0, 0)
    }

    var received: UInt64 = 0
    var sent: UInt64 = 0
    var countedInterfaces = Set<String>()

    for line in output.split(separator: "\n").dropFirst() {
      let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard parts.count >= 10 else { continue }
      let name = parts[0]
      guard
        parts[2].hasPrefix("<Link"),
        !name.hasPrefix("lo"),
        !name.hasPrefix("gif"),
        !name.hasPrefix("stf"),
        !name.hasPrefix("bridge"),
        !countedInterfaces.contains(name)
      else {
        continue
      }

      received += UInt64(parts[6]) ?? 0
      sent += UInt64(parts[9]) ?? 0
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
    guard let output = try? await ProcessRunner.run("/usr/sbin/iostat", ["-Id", "disk0"], timeout: 2) else {
      return 0
    }

    let rows = output.split(separator: "\n")
    guard let last = rows.last else { return 0 }
    let parts = last.split(whereSeparator: \.isWhitespace)
    guard let megabytes = Double(parts.last ?? "0") else { return 0 }
    return UInt64(megabytes * 1_048_576)
  }

  private func countProcesses() async -> Int {
    guard let output = try? await ProcessRunner.run("/bin/ps", ["-axo", "pid="], timeout: 2) else { return 0 }
    return output.split(separator: "\n").count
  }

  private func topPowerHungryApp(systemWatts: Double?, systemCPUUsage: Double) async -> PowerAppInfo? {
    if let cachedTopPowerApp, Date().timeIntervalSince(cachedTopPowerApp.date) < 9 {
      return cachedTopPowerApp.app
    }

    guard let output = try? await ProcessRunner.run("/bin/ps", ["-axo", "pid=,cputime=,rss=,command=", "-r"], timeout: 2) else {
      return cachedTopPowerApp?.app
    }

    let now = Date()
    let samples = output.split(separator: "\n").compactMap { processPowerSample(from: String($0)) }
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

  private func processPowerSample(from line: String) -> ProcessPowerSample? {
    let pattern = #"^\s*(\d+)\s+([0-9:\.-]+)\s+(\d+)\s+(.+)$"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
      let pidRange = Range(match.range(at: 1), in: line),
      let cpuTimeRange = Range(match.range(at: 2), in: line),
      let rssRange = Range(match.range(at: 3), in: line),
      let commandRange = Range(match.range(at: 4), in: line),
      let pid = Int(line[pidRange]),
      let cpuSeconds = cpuSeconds(from: String(line[cpuTimeRange])),
      let rssKB = UInt64(line[rssRange])
    else {
      return nil
    }

    let command = String(line[commandRange])
    let name = appName(from: command)
    guard !name.isEmpty, name != "MacHub" else { return nil }
    return ProcessPowerSample(
      pid: pid,
      name: name,
      cpuSeconds: cpuSeconds,
      memoryBytes: rssKB * 1024
    )
  }

  private func cpuSeconds(from value: String) -> Double? {
    let parts = value.split(separator: ":").map(String.init)
    guard let secondsPart = parts.last, let seconds = Double(secondsPart) else {
      return nil
    }

    var total = seconds
    if parts.count >= 2, let minutes = Double(parts[parts.count - 2]) {
      total += minutes * 60
    }
    if parts.count >= 3 {
      let hoursPart = parts[parts.count - 3]
      if let dayRange = hoursPart.range(of: "-") {
        let days = Double(hoursPart[..<dayRange.lowerBound]) ?? 0
        let hours = Double(hoursPart[dayRange.upperBound...]) ?? 0
        total += days * 86_400 + hours * 3600
      } else if let hours = Double(hoursPart) {
        total += hours * 3600
      }
    }
    return total
  }

  private func appName(from command: String) -> String {
    if let range = command.range(of: #"/([^/]+)\.app/Contents/"#, options: .regularExpression) {
      let component = String(command[range])
      return component
        .split(separator: "/")
        .first(where: { $0.hasSuffix(".app") })?
        .replacingOccurrences(of: ".app", with: "") ?? "Unknown"
    }

    let firstToken = command.split(separator: " ").first.map(String.init) ?? command
    return URL(fileURLWithPath: firstToken).lastPathComponent
  }

  private func number(_ value: Any?) -> NSNumber {
    if let number = value as? NSNumber { return number }
    if let int = value as? Int { return NSNumber(value: int) }
    if let double = value as? Double { return NSNumber(value: double) }
    return 0
  }

  private func firstValue(after label: String, in text: String) -> String? {
    text.split(separator: "\n").compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix(label) else { return nil }
      return trimmed.replacingOccurrences(of: label, with: "").trimmingCharacters(in: .whitespaces)
    }.first
  }

  private func regexInt(_ pattern: String, in text: String) -> Int? {
    regexString(pattern, in: text).flatMap(Int.init)
  }

  private func regexSignedInt(_ pattern: String, in text: String) -> Int? {
    guard let raw = regexString(pattern, in: text), let unsigned = UInt64(raw) else {
      return regexString(pattern, in: text).flatMap(Int.init)
    }
    if unsigned > UInt64(Int64.max) {
      return Int(Int64(bitPattern: unsigned))
    }
    return Int(unsigned)
  }

  private func regexString(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard
      let match = regex.firstMatch(in: text, range: range),
      match.numberOfRanges > 1,
      let matchRange = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[matchRange])
  }
}

private struct ProcessPowerSample {
  var pid: Int
  var name: String
  var cpuSeconds: Double
  var memoryBytes: UInt64
}
