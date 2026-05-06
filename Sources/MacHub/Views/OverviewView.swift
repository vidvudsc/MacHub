import SwiftUI

struct OverviewView: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      ActivityMonitorPanel(store: store)

      CardGrid {
        MetricCard(
          title: "CPU",
          value: Formatters.percent(store.snapshot.cpuUsage),
          detail: "\(store.snapshot.processCount) running processes",
          systemImage: "cpu",
          progress: store.snapshot.cpuUsage
        )
        MetricCard(
          title: "Memory",
          value: Formatters.memory(store.snapshot.memoryUsed),
          detail: "\(Formatters.memory(store.snapshot.memoryTotal)) installed",
          systemImage: "memorychip",
          progress: store.snapshot.memoryPressure
        )
        MetricCard(
          title: "Disk",
          value: Formatters.bytes(store.snapshot.diskUsed),
          detail: "\(Formatters.bytes(store.snapshot.diskTotal)) total",
          systemImage: "internaldrive",
          progress: store.snapshot.diskPressure
        )
        MetricCard(
          title: "Battery",
          value: Formatters.percent(store.snapshot.battery.percent),
          detail: "\(store.snapshot.battery.stateLabel), \(Formatters.watts(store.snapshot.battery.watts))",
          systemImage: store.snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
          progress: store.snapshot.battery.isPresent ? store.snapshot.battery.percent : nil
        )
      }

      CleanerSummary(store: store)
      StorageSummary(store: store)
    }
  }
}

private struct CleanerSummary: View {
  @ObservedObject var store: DashboardStore

  private var cleanableBytes: UInt64 {
    store.cleanupTargets.filter(\.isSafeToTrash).reduce(0) { $0 + $1.bytes }
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "sparkles")
        .font(.title2)
        .foregroundStyle(.blue)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text("Cleaner")
          .font(.headline)
        Text("\(Formatters.bytes(cleanableBytes)) likely safe to review")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        Task { await store.refreshCleanupTargets() }
      } label: {
        Label("Scan Junk", systemImage: "arrow.clockwise")
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct StorageSummary: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Largest folders")
        .font(.title3.weight(.semibold))

      ForEach(store.folders.prefix(5)) { folder in
        HStack(spacing: 12) {
          Image(systemName: "folder")
            .foregroundStyle(.secondary)
            .frame(width: 24)
          Text(folder.name)
            .lineLimit(1)
          Spacer()
          Text(Formatters.bytes(folder.bytes))
            .foregroundStyle(.secondary)
            .monospacedDigit()
          Button {
            store.reveal(folder)
          } label: {
            Label("Reveal", systemImage: "magnifyingglass")
          }
          .labelStyle(.iconOnly)
          .help("Reveal in Finder")
        }
        .padding(.vertical, 6)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
