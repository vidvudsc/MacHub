import Foundation

struct SystemSnapshot: Equatable {
  var cpuUsage: Double = 0
  var memoryUsed: UInt64 = 0
  var memoryTotal: UInt64 = 0
  var memoryWired: UInt64 = 0
  var memoryCompressed: UInt64 = 0
  var memoryCached: UInt64 = 0
  var diskUsed: UInt64 = 0
  var diskTotal: UInt64 = 0
  var networkInPerSecond: UInt64 = 0
  var networkOutPerSecond: UInt64 = 0
  var diskBytesPerSecond: UInt64 = 0
  var battery: BatteryInfo = .empty
  var gpu: GPUInfo = .empty
  var topPowerApp: PowerAppInfo?
  var uptime: TimeInterval = 0
  var processCount: Int = 0

  var memoryPressure: Double {
    guard memoryTotal > 0 else { return 0 }
    return Double(memoryUsed) / Double(memoryTotal)
  }

  var diskPressure: Double {
    guard diskTotal > 0 else { return 0 }
    return Double(diskUsed) / Double(diskTotal)
  }
}

struct ActivitySample: Identifiable, Equatable {
  let id = UUID()
  var date = Date()
  var cpuUsage: Double
  var memoryPressure: Double
  var networkInPerSecond: UInt64
  var networkOutPerSecond: UInt64
  var diskBytesPerSecond: UInt64
}

struct BatterySample: Identifiable, Equatable {
  let id = UUID()
  var date = Date()
  var percent: Double
  var watts: Double?
}

struct PowerAppInfo: Equatable {
  var name: String
  var cpuPercent: Double
  var memoryBytes: UInt64
  var estimatedWatts: Double?
}

struct BatteryInfo: Equatable {
  var percent: Double = 0
  var isPresent = false
  var isCharging = false
  var isPluggedIn = false
  var timeRemainingMinutes: Int?
  var watts: Double?
  var externalWatts: Double?
  var systemWatts: Double?
  var voltage: Double?
  var amperage: Double?
  var temperature: Double?
  var cycleCount: Int?
  var health: String?

  static let empty = BatteryInfo()

  var stateLabel: String {
    if !isPresent { return "No battery" }
    if isCharging { return "Charging" }
    if isPluggedIn { return "Plugged in" }
    return "On battery"
  }
}

struct GPUInfo: Equatable {
  var name = "Unknown GPU"
  var vram = "Unknown VRAM"
  var metal = "Unknown Metal support"

  static let empty = GPUInfo()
}

struct FolderUsage: Identifiable, Equatable {
  var id: String { url.path }
  var name: String
  var url: URL
  var bytes: UInt64
  var isDirectory = false
  var itemCount: Int = 0
  var skippedCount: Int = 0
  var children: [FolderUsage] = []

  var sortedChildren: [FolderUsage] {
    children.sorted { $0.bytes > $1.bytes }
  }
}

enum ActivityMetric: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case network = "Network"
  case disk = "Disk"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .cpu: "cpu"
    case .memory: "memorychip"
    case .network: "network"
    case .disk: "internaldrive"
    }
  }
}

enum DashboardSection: String, CaseIterable, Identifiable {
  case overview = "Monitor"
  case clean = "Clean"
  case storage = "Storage"
  case battery = "Battery"
  case windows = "Windows"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .overview: "gauge.with.dots.needle.67percent"
    case .clean: "sparkles"
    case .storage: "internaldrive"
    case .battery: "battery.75percent"
    case .windows: "rectangle.3.group"
    }
  }
}

struct CleanupTarget: Identifiable, Equatable {
  var id: String { url.path }
  var title: String
  var detail: String
  var url: URL
  var bytes: UInt64
  var isSafeToTrash: Bool
  var systemImage: String
}
