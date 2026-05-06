import SwiftUI

struct OverviewView: View {
  @ObservedObject var store: DashboardStore

  private var cleanableBytes: UInt64 {
    store.cleanupTargets.filter(\.isSafeToTrash).reduce(0) { $0 + $1.bytes }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        ActivityMonitorPanel(store: store)
          .frame(minWidth: 520, maxWidth: .infinity)

        VStack(spacing: 10) {
          MetricSummaryCard(
            title: "CPU",
            subtitle: "\(store.snapshot.processCount) processes",
            value: Formatters.percent(store.snapshot.cpuUsage),
            systemImage: "cpu",
            tint: MacHubTheme.green,
            values: store.history.suffix(40).map(\.cpuUsage)
          )
          MetricSummaryCard(
            title: "RAM",
            subtitle: "\(Formatters.memory(store.snapshot.memoryUsed)) / \(Formatters.memory(store.snapshot.memoryTotal))",
            value: Formatters.percent(store.snapshot.memoryPressure),
            systemImage: "memorychip",
            tint: MacHubTheme.blue,
            values: store.history.suffix(40).map(\.memoryPressure)
          )
          MetricSummaryCard(
            title: "Disk",
            subtitle: "\(Formatters.bytes(store.snapshot.diskUsed)) / \(Formatters.bytes(store.snapshot.diskTotal))",
            value: Formatters.percent(store.snapshot.diskPressure),
            systemImage: "internaldrive",
            tint: MacHubTheme.yellow,
            values: store.history.suffix(40).map { Double($0.diskBytesPerSecond) }
          )
          MetricSummaryCard(
            title: "Network",
            subtitle: "In \(Formatters.bytes(store.snapshot.networkInPerSecond))/s  Out \(Formatters.bytes(store.snapshot.networkOutPerSecond))/s",
            value: "\(Formatters.bytes(store.snapshot.networkInPerSecond + store.snapshot.networkOutPerSecond))/s",
            systemImage: "arrow.down.arrow.up",
            tint: MacHubTheme.purple,
            values: store.history.suffix(40).map { Double($0.networkInPerSecond + $0.networkOutPerSecond) }
          )
          MetricSummaryCard(
            title: "Battery",
            subtitle: store.snapshot.battery.stateLabel,
            value: store.snapshot.battery.isPresent ? Formatters.percent(store.snapshot.battery.percent) : "--",
            systemImage: store.snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
            tint: MacHubTheme.green,
            values: store.batteryHistory.suffix(40).map(\.percent)
          )
        }
        .frame(width: 350)
      }

      HStack(alignment: .top, spacing: 14) {
        UtilityPanel {
          HStack {
            PanelHeader(title: "Cleaner", detail: "\(Formatters.bytes(cleanableBytes)) likely safe to review")
            Spacer()
            Button {
              Task { await store.refreshCleanupTargets() }
            } label: {
              Label("Scan Junk", systemImage: "arrow.clockwise")
            }
          }
        }

        UtilityPanel {
          HStack {
            PanelHeader(title: "Largest folder", detail: store.folders.first?.name ?? "Waiting for scan")
            Spacer()
            if let folder = store.folders.first {
              Text(Formatters.bytes(folder.bytes))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
              Button {
                store.reveal(folder)
              } label: {
                Label("Reveal", systemImage: "magnifyingglass")
              }
            }
          }
        }
      }
    }
  }
}

private struct MetricSummaryCard: View {
  let title: String
  let subtitle: String
  let value: String
  let systemImage: String
  let tint: Color
  let values: [Double]

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(tint.opacity(0.35), lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline) {
          Text(title)
            .font(.headline)
          Spacer()
          Text(value)
            .font(.headline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.66)
        }

        HStack(spacing: 10) {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
          Spacer(minLength: 4)
          Sparkline(values: values, tint: tint)
            .frame(width: 92, height: 26)
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
    .hubPanel()
  }
}
