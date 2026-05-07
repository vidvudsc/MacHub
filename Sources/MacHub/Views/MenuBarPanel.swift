import AppKit
import SwiftUI

struct MenuBarPanel: View {
  @ObservedObject var store: DashboardStore
  let openMainWindow: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("MacHub")
          .font(.title3.weight(.semibold))
        Spacer()
        Button {
          Task { await store.refreshAll() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .help("Refresh")
      }

      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        MiniMetric(
          title: "CPU",
          value: Formatters.percent(store.snapshot.cpuUsage),
          tint: MacHubTheme.green,
          values: store.history.suffix(28).map(\.cpuUsage)
        )
        MiniMetric(
          title: "RAM",
          value: Formatters.percent(store.snapshot.memoryPressure),
          tint: MacHubTheme.blue,
          values: store.history.suffix(28).map(\.memoryPressure)
        )
        MiniMetric(
          title: "Battery",
          value: store.snapshot.battery.isPresent ? Formatters.percent(store.snapshot.battery.percent) : "--",
          tint: MacHubTheme.green,
          values: store.batteryHistory.suffix(28).map(\.percent)
        )
        MiniMetric(
          title: "Disk",
          value: Formatters.percent(store.snapshot.diskPressure),
          tint: MacHubTheme.yellow,
          values: store.history.suffix(28).map { Double($0.diskBytesPerSecond) }
        )
      }

      MenuSection {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "network")
              .foregroundStyle(MacHubTheme.purple)
              .frame(width: 16)
            Text("Network")
          }
          .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Sparkline(
            values: store.history.suffix(28).map { Double($0.networkInPerSecond + $0.networkOutPerSecond) },
            tint: MacHubTheme.purple
          )
          .frame(width: 108, height: 26)
        }
        MetricLine(systemImage: "arrow.down", title: "Download", value: "\(Formatters.bytes(store.snapshot.networkInPerSecond))/s")
        MetricLine(systemImage: "arrow.up", title: "Upload", value: "\(Formatters.bytes(store.snapshot.networkOutPerSecond))/s")
      }

      MenuSection {
        MetricLine(systemImage: "timer", title: "Time Left", value: Formatters.batteryTime(store.snapshot.battery))
        PowerFlowPills(battery: store.snapshot.battery, compact: true)
        if let topPowerApp = store.snapshot.topPowerApp {
          MetricLine(
            systemImage: "bolt.fill",
            title: topPowerApp.name,
            value: topPowerApp.estimatedWatts.map(Formatters.estimatedWatts) ?? String(format: "%.0f%% CPU", topPowerApp.cpuPercent)
          )
        }
      }

      VStack(spacing: 4) {
        MenuAction(systemImage: "macwindow", title: "Open Dashboard", action: openMainWindow)
        MenuAction(systemImage: "menubar.rectangle", title: "Hide to Menu Bar") {
          AppVisibilityService.hideToMenuBar()
        }
        MenuAction(systemImage: "power", title: "Quit MacHub") {
          NSApplication.shared.terminate(nil)
        }
      }

      Text("Version 1.0.0")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(HubButtonStyle())
    .padding(14)
    .frame(width: 300)
    .background(MacHubTheme.windowBackground)
    .preferredColorScheme(.dark)
    .onAppear {
      Task { await store.refreshMetrics() }
    }
    .task {
      await store.refreshBatteryOnly()
    }
  }
}

private struct MenuSection<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      content
    }
    .padding(11)
    .hubPanel()
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
        .lineLimit(1)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
    .font(.callout)
  }
}

private struct MiniMetric: View {
  let title: String
  let value: String
  let tint: Color
  let values: [Double]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Sparkline(values: values, tint: tint)
        .frame(height: 24)
    }
    .padding(11)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .hubPanel()
  }
}

private struct MenuAction: View {
  let systemImage: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .frame(width: 18)
        Text(title)
        Spacer()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
  }
}
