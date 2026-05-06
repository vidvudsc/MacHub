import Darwin
import Foundation
import IOKit.ps

final class SystemMetricsService {
  private var previousCPU = host_cpu_load_info()
  private var previousNetworkTotals: (received: UInt64, sent: UInt64, date: Date)?
  private var previousDiskTotal: (bytes: UInt64, date: Date)?
  private var cachedGPU: GPUInfo?

  func snapshot() async -> SystemSnapshot {
    async let battery = batteryInfo()
    async let gpu = gpuInfo()

    let cpu = cpuUsage()
    let memory = memoryUsage()
    let disk = diskUsage()
    let networkRates = await networkRates()
    let diskRate = await diskRate()
    let processCount = await countProcesses()

    return await SystemSnapshot(
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
      battery: battery,
      gpu: gpu,
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

  private func smartBatteryDetails() async -> (watts: Double?, voltage: Double?, amperage: Double?, temperature: Double?, cycleCount: Int?, health: String?) {
    guard let output = try? await ProcessRunner.run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"], timeout: 2) else {
      return (nil, nil, nil, nil, nil, nil)
    }

    let voltageMillivolts = regexInt("^\\s+\"(?:AppleRawBatteryVoltage|Voltage)\"\\s*=\\s*(\\d+)", in: output)
    let amperageMilliamps = regexSignedInt("^\\s+\"InstantAmperage\"\\s*=\\s*(\\d+)", in: output)
      ?? regexSignedInt("^\\s+\"Amperage\"\\s*=\\s*(\\d+)", in: output)
    let batteryPowerMilliwatts = regexSignedInt("\"BatteryPower\"\\s*=\\s*(\\d+)", in: output)
    let cycleCount = regexInt("^\\s+\"CycleCount\"\\s*=\\s*(\\d+)", in: output)
    let temperature = regexInt("^\\s+\"Temperature\"\\s*=\\s*(\\d+)", in: output).map { Double($0) / 100 }
    let condition = regexString("^\\s+\"BatteryHealth\"\\s*=\\s*\"([^\"]+)\"", in: output)
      ?? regexString("^\\s+\"PermanentFailureStatus\"\\s*=\\s*(\\d+)", in: output).map { $0 == "0" ? "Normal" : "Service recommended" }

    let voltage = voltageMillivolts.map { Double($0) / 1000 }
    let amperage = amperageMilliamps.map { Double($0) / 1000 }
    let watts: Double?
    if let batteryPowerMilliwatts {
      watts = Double(batteryPowerMilliwatts) / 1000
    } else if let voltage, let amperage {
      watts = voltage * amperage
    } else {
      watts = nil
    }
    return (watts, voltage, amperage, temperature, cycleCount, condition)
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
