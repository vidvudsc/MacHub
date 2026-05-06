import AppKit
import SwiftUI

struct MenuBarPanel: View {
  @ObservedObject var store: DashboardStore
  let openMainWindow: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("MacHub")
          .font(.headline)
        Spacer()
        Button {
          Task { await store.refreshAll() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .help("Refresh")
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
        MiniMetric(
          title: "Battery",
          value: store.snapshot.battery.isPresent ? Formatters.percent(store.snapshot.battery.percent) : "--",
          systemImage: store.snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent"
        )
        MiniMetric(title: "CPU", value: Formatters.percent(store.snapshot.cpuUsage), systemImage: "cpu")
        MiniMetric(title: "RAM", value: Formatters.memory(store.snapshot.memoryUsed), systemImage: "memorychip")
        MiniMetric(title: "Disk", value: Formatters.percent(store.snapshot.diskPressure), systemImage: "internaldrive")
        MiniMetric(
          title: "Network",
          value: "\(Formatters.bytes(store.snapshot.networkInPerSecond + store.snapshot.networkOutPerSecond))/s",
          systemImage: "network"
        )
      }
      .frame(maxWidth: .infinity)

      Divider()

      MetricLine(systemImage: "bolt.circle", title: "Battery power", value: Formatters.watts(store.snapshot.battery.watts))
      MetricLine(systemImage: "arrow.down.arrow.up", title: "Network", value: "\(Formatters.bytes(store.snapshot.networkInPerSecond))/s in, \(Formatters.bytes(store.snapshot.networkOutPerSecond))/s out")

      if let topFolder = store.folders.first {
        Divider()
        HStack {
          Image(systemName: "folder")
            .foregroundStyle(.secondary)
          Text(topFolder.name)
            .lineLimit(1)
          Spacer()
          Text(Formatters.bytes(topFolder.bytes))
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack {
        Button("Open Dashboard", action: openMainWindow)
        Button("Hide Dock") {
          AppVisibilityService.hideToMenuBar()
        }
        Spacer()
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(14)
    .frame(width: 380)
  }
}

private struct MetricLine: View {
  let systemImage: String
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }
}

private struct MiniMetric: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline.monospacedDigit())
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}
