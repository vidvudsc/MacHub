import AppKit
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
  @Published var snapshot = SystemSnapshot()
  @Published var folders: [FolderUsage] = []
  @Published var selectedFolder: FolderUsage?
  @Published var currentFolder: FolderUsage?
  @Published var folderPath: [FolderUsage] = []
  @Published var cleanupTargets: [CleanupTarget] = []
  @Published var history: [ActivitySample] = []
  @Published var batteryHistory: [BatterySample] = []
  @Published var isRefreshing = false
  @Published var isScanningFolders = false
  @Published var isScanningCurrentFolder = false
  @Published var hasFullDiskAccess = FullDiskAccessService.hasFullDiskAccess()
  @Published var lastUpdated: Date?

  private let metricsService = SystemMetricsService()
  private let scanner = FolderScanner()
  private var metricsRefreshTask: Task<Void, Never>?
  private var batteryRefreshTask: Task<Void, Never>?
  private var metricsRefreshActivity: NSObjectProtocol?
  private static let metricsRefreshIntervalNanoseconds: UInt64 = 1_500_000_000
  private static let batteryRefreshIntervalNanoseconds: UInt64 = 500_000_000
  private var isRefreshingMetrics = false
  private var isRefreshingBattery = false
  private var didStart = false
  private var didStartDashboardScans = false

  init() {
    startAutoRefresh()
  }

  var menuBarSystemImage: String {
    "gauge.with.dots.needle.67percent"
  }

  var menuBarTitle: String {
    let battery = snapshot.battery.isPresent ? Formatters.percent(snapshot.battery.percent) : "--"
    let cpu = Formatters.percent(snapshot.cpuUsage)
    let ram = Formatters.memory(snapshot.memoryUsed)
    let net = Formatters.bytes(snapshot.networkInPerSecond + snapshot.networkOutPerSecond)
    return "\(battery)  CPU \(cpu)  RAM \(ram)  NET \(net)/s"
  }

  func startAutoRefresh() {
    guard metricsRefreshTask == nil else { return }
    metricsRefreshActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "Keep MacHub menu bar metrics current"
    )
    metricsRefreshTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        if let self {
          await self.refreshMetrics()
        } else {
          return
        }
        do {
          try await Task.sleep(nanoseconds: Self.metricsRefreshIntervalNanoseconds)
        } catch {
          return
        }
      }
    }
    batteryRefreshTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        if let self {
          await self.refreshBatteryOnly()
        } else {
          return
        }
        do {
          try await Task.sleep(nanoseconds: Self.batteryRefreshIntervalNanoseconds)
        } catch {
          return
        }
      }
    }
  }

  func start() async {
    startAutoRefresh()
    guard !didStart else {
      return
    }
    didStart = true
    await refreshMetrics()
  }

  func startDashboard() async {
    await start()
    await startDashboardScansIfNeeded()
  }

  private func startDashboardScansIfNeeded() async {
    guard !didStartDashboardScans else { return }
    didStartDashboardScans = true
    refreshPrivacyStatus()
    guard hasFullDiskAccess else { return }
    async let folders: Void = refreshFolders()
    async let cleanup: Void = refreshCleanupTargets()
    _ = await (folders, cleanup)
  }

  func refreshAll() async {
    isRefreshing = true
    await refreshMetrics()
    refreshPrivacyStatus()
    if hasFullDiskAccess {
      async let folders: Void = refreshFolders()
      async let cleanup: Void = refreshCleanupTargets()
      _ = await (folders, cleanup)
    }
    isRefreshing = false
  }

  func refreshMetrics() async {
    guard !isRefreshingMetrics else { return }
    isRefreshingMetrics = true
    defer { isRefreshingMetrics = false }

    snapshot = await metricsService.snapshot()
    appendHistory(from: snapshot)
    lastUpdated = Date()
  }

  func refreshBatteryOnly() async {
    guard !isRefreshingBattery else { return }
    isRefreshingBattery = true
    defer { isRefreshingBattery = false }

    let battery = await metricsService.batterySnapshot()
    snapshot.battery = battery
    appendBatteryHistory(from: battery)
    lastUpdated = Date()
  }

  func stopAutoRefresh() {
    metricsRefreshTask?.cancel()
    metricsRefreshTask = nil
    batteryRefreshTask?.cancel()
    batteryRefreshTask = nil
    if let metricsRefreshActivity {
      ProcessInfo.processInfo.endActivity(metricsRefreshActivity)
      self.metricsRefreshActivity = nil
    }
  }

  deinit {
    metricsRefreshTask?.cancel()
    batteryRefreshTask?.cancel()
    if let metricsRefreshActivity {
      ProcessInfo.processInfo.endActivity(metricsRefreshActivity)
    }
  }

  func refreshFolders() async {
    refreshPrivacyStatus()
    guard hasFullDiskAccess else {
      folders = []
      selectedFolder = nil
      currentFolder = nil
      folderPath = []
      isScanningFolders = false
      return
    }

    isScanningFolders = true
    folders = []
    selectedFolder = nil
    folders = await scanner.scanHomeFolders { [weak self] usage in
      await MainActor.run {
        guard let self else { return }
        self.folders.append(usage)
        self.folders.sort { $0.bytes > $1.bytes }
        if self.selectedFolder == nil {
          self.selectedFolder = self.folders.first
        }
      }
    }
    if selectedFolder == nil {
      selectedFolder = folders.first
    }
    currentFolder = folders.first
    folderPath = folders.first.map { [$0] } ?? []
    lastUpdated = Date()
    isScanningFolders = false
  }

  func refreshCleanupTargets() async {
    refreshPrivacyStatus()
    guard hasFullDiskAccess else {
      cleanupTargets = []
      return
    }

    cleanupTargets = await scanner.scanCleanupTargets()
    lastUpdated = Date()
  }

  func refreshPrivacyStatus() {
    hasFullDiskAccess = FullDiskAccessService.hasFullDiskAccess()
  }

  func openRoot(_ folder: FolderUsage) {
    currentFolder = folder
    selectedFolder = folder
    folderPath = [folder]
  }

  func scanCurrentFolder() async {
    guard let currentFolder else { return }
    await scanFolder(currentFolder.url, preservingPath: true)
  }

  func drillInto(_ folder: FolderUsage) async {
    guard folder.isDirectory else {
      open(folder)
      return
    }
    folderPath.append(folder)
    await scanFolder(folder.url, preservingPath: true)
  }

  func goUp() async {
    guard folderPath.count > 1 else { return }
    folderPath.removeLast()
    guard let parent = folderPath.last else { return }
    await scanFolder(parent.url, preservingPath: false)
  }

  func jumpToPathItem(_ folder: FolderUsage) async {
    guard let index = folderPath.firstIndex(where: { $0.id == folder.id }) else { return }
    folderPath = Array(folderPath.prefix(index + 1))
    await scanFolder(folder.url, preservingPath: false)
  }

  private func scanFolder(_ url: URL, preservingPath: Bool) async {
    isScanningCurrentFolder = true
    let folder = await scanner.scanFolder(url)
    currentFolder = folder
    selectedFolder = folder
    if preservingPath, !folderPath.isEmpty {
      folderPath[folderPath.count - 1] = folder
    }
    lastUpdated = Date()
    isScanningCurrentFolder = false
  }

  private func appendHistory(from snapshot: SystemSnapshot) {
    history.append(ActivitySample(
      cpuUsage: snapshot.cpuUsage,
      memoryPressure: snapshot.memoryPressure,
      networkInPerSecond: snapshot.networkInPerSecond,
      networkOutPerSecond: snapshot.networkOutPerSecond,
      diskBytesPerSecond: snapshot.diskBytesPerSecond
    ))

    if history.count > 72 {
      history.removeFirst(history.count - 72)
    }

    appendBatteryHistory(from: snapshot.battery)
  }

  private func appendBatteryHistory(from battery: BatteryInfo) {
    guard battery.isPresent else { return }
    let now = Date()
    if let last = batteryHistory.last, now.timeIntervalSince(last.date) < 1 {
      batteryHistory[batteryHistory.count - 1] = BatterySample(
        date: now,
        percent: battery.percent,
        watts: battery.watts
      )
    } else {
      batteryHistory.append(BatterySample(
        date: now,
        percent: battery.percent,
        watts: battery.watts
      ))
    }

    if batteryHistory.count > 360 {
      batteryHistory.removeFirst(batteryHistory.count - 360)
    }
  }

  func reveal(_ usage: FolderUsage) {
    NSWorkspace.shared.activateFileViewerSelecting([usage.url])
  }

  func open(_ usage: FolderUsage) {
    NSWorkspace.shared.open(usage.url)
  }

  func openTrash() {
    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
  }

  func moveToTrash(_ usage: FolderUsage) {
    do {
      _ = try FileManager.default.trashItem(at: usage.url, resultingItemURL: nil)
      if currentFolder?.id == usage.id {
        currentFolder = nil
      }
      currentFolder?.children.removeAll { $0.id == usage.id }
      folders.removeAll { $0.id == usage.id }
    } catch {
      reveal(usage)
    }
  }

  func moveCleanupTargetToTrash(_ target: CleanupTarget) {
    do {
      if target.title == "Trash" {
        openTrash()
        return
      }
      _ = try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
      cleanupTargets.removeAll { $0.id == target.id }
    } catch {
      NSWorkspace.shared.activateFileViewerSelecting([target.url])
    }
  }
}
