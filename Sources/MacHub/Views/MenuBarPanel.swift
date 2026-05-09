import AppKit
import SwiftUI

struct MenuBarPanel: View {
  @ObservedObject var store: DashboardStore
  let openMainWindow: () -> Void
  @Environment(\.dismiss) private var dismiss

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
          values: store.history.suffix(28).map(\.cpuUsage),
          fixedRange: 0...1
        )
        MiniMetric(
          title: "RAM",
          value: Formatters.percent(store.snapshot.memoryPressure),
          tint: MacHubTheme.blue,
          values: store.history.suffix(28).map(\.memoryPressure),
          fixedRange: 0...1
        )
        MiniMetric(
          title: "Battery",
          value: store.snapshot.battery.isPresent ? Formatters.percent(store.snapshot.battery.percent) : "--",
          tint: MacHubTheme.green,
          values: store.batteryHistory.suffix(360).map(\.percent),
          fixedRange: 0...1
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
        MenuToggleAction(
          systemImage: store.isPreventingSleep ? "moon.zzz.fill" : "moon.zzz",
          title: "Prevent Sleeping",
          isOn: store.isPreventingSleep
        ) { isOn in
          store.setPreventSleep(isOn)
        }
        MenuToggleAction(
          systemImage: "laptopcomputer",
          title: "Lid Sleep Override",
          isOn: store.isLidSleepOverrideEnabled,
          isDisabled: store.isChangingLidSleepOverride
        ) { isOn in
          guard !store.isChangingLidSleepOverride else { return }
          Task { await store.setLidSleepOverride(isOn) }
        }
        MenuToggleAction(
          systemImage: "keyboard",
          title: "Keyboard Cleaning",
          isOn: store.isKeyboardCleaningEnabled
        ) { isOn in
          store.setKeyboardCleaning(isOn)
        }
      }

      VStack(spacing: 4) {
        MenuAction(systemImage: "macwindow", title: "Open Dashboard") {
          dismiss()
          AppVisibilityService.closeMenuBarPanels()
          DispatchQueue.main.async {
            openMainWindow()
          }
        }
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
      Task {
        await store.refreshMetrics()
        await store.refreshPowerStatus()
      }
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
  var fixedRange: ClosedRange<Double>?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Sparkline(values: values, tint: tint, fixedRange: fixedRange)
        .frame(height: 24)
    }
    .padding(11)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .hubPanel()
  }
}

private struct MenuToggleAction: View {
  let systemImage: String
  let title: String
  let isOn: Bool
  var isDisabled = false
  let action: (Bool) -> Void
  @State private var isHovering = false

  var body: some View {
    Button {
      guard !isDisabled else { return }
      action(!isOn)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .frame(width: 18)
        Text(title)
        Spacer()
        SwitchIndicator(isOn: isOn)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.white.opacity(isHovering ? 0.075 : 0.035),
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.6 : 1)
    .scaleEffect(isHovering ? 1.018 : 1)
    .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isHovering)
    .onHover { isHovering = $0 }
  }
}

private struct SwitchIndicator: View {
  let isOn: Bool

  var body: some View {
    Capsule(style: .continuous)
      .fill(isOn ? MacHubTheme.blue : Color.white.opacity(0.18))
      .frame(width: 28, height: 16)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Circle()
          .fill(Color.white.opacity(0.95))
          .frame(width: 12, height: 12)
          .padding(2)
      }
      .accessibilityHidden(true)
  }
}

private struct MenuAction: View {
  let systemImage: String
  let title: String
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .frame(width: 18)
        Text(title)
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.white.opacity(isHovering ? 0.075 : 0.035),
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .scaleEffect(isHovering ? 1.018 : 1)
    .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isHovering)
    .onHover { isHovering = $0 }
  }
}
