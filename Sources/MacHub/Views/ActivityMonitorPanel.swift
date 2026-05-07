import SwiftUI

struct ActivityMonitorPanel: View {
  @ObservedObject var store: DashboardStore
  @Binding var metric: ActivityMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ViewThatFits(in: .horizontal) {
        HStack {
          activityHeader
          Spacer()
          metricPicker
            .frame(width: 340)
        }

        VStack(alignment: .leading, spacing: 10) {
          activityHeader
          metricPicker
            .frame(maxWidth: 340)
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 14) {
          trendChart
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 220)
          detailBlock
            .frame(width: 190, alignment: .topLeading)
        }

        VStack(alignment: .leading, spacing: 12) {
          trendChart
            .frame(maxWidth: .infinity, minHeight: 200)
          detailBlock
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }
    .padding(14)
    .hubPanel()
  }

  private var values: [Double] {
    let samples = store.history.suffix(48)
    let raw: [Double]
    switch metric {
    case .cpu:
      raw = samples.map(\.cpuUsage)
    case .memory:
      raw = samples.map(\.memoryPressure)
    case .network:
      raw = samples.map { Double($0.networkInPerSecond + $0.networkOutPerSecond) }
    case .disk:
      raw = samples.map { Double($0.diskBytesPerSecond) }
    }

    if metric == .network || metric == .disk {
      let maxValue = max(raw.max() ?? 1, 1)
      return raw.map { min(max($0 / maxValue, 0.02), 1) }
    }
    return raw.map { min(max($0, 0.02), 1) }
  }

  private var activityHeader: some View {
    PanelHeader(title: "Live Activity", detail: store.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Updated just now")
  }

  private var metricPicker: some View {
    Picker("Metric", selection: $metric) {
      ForEach(ActivityMetric.allCases) { metric in
        Text(metric.rawValue).tag(metric)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  private var trendChart: some View {
    ActivityTrendChart(values: values, metric: metric)
  }

  private var detailBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      ActivityValueBlock(
        title: metric.rawValue,
        value: primaryValue,
        detail: secondaryValue,
        systemImage: metric.systemImage,
        tint: tint
      )

      ForEach(detailRows, id: \.0) { row in
        LabeledContent(row.0, value: row.1)
          .font(.callout)
      }
    }
    .padding(12)
    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var primaryValue: String {
    switch metric {
    case .cpu:
      Formatters.percent(store.snapshot.cpuUsage)
    case .memory:
      Formatters.memory(store.snapshot.memoryUsed)
    case .network:
      "\(Formatters.bytes(store.snapshot.networkInPerSecond))/s in"
    case .disk:
      "\(Formatters.bytes(store.snapshot.diskBytesPerSecond))/s"
    }
  }

  private var secondaryValue: String {
    switch metric {
    case .cpu:
      "\(store.snapshot.processCount) processes"
    case .memory:
      "\(Formatters.memory(store.snapshot.memoryTotal)) installed"
    case .network:
      "\(Formatters.bytes(store.snapshot.networkOutPerSecond))/s out"
    case .disk:
      "Recent disk transfer rate"
    }
  }

  private var detailRows: [(String, String)] {
    switch metric {
    case .cpu:
      [
        ("Load", Formatters.percent(store.snapshot.cpuUsage)),
        ("Uptime", Formatters.duration(store.snapshot.uptime))
      ]
    case .memory:
      [
        ("Wired", Formatters.memory(store.snapshot.memoryWired)),
        ("Compressed", Formatters.memory(store.snapshot.memoryCompressed)),
        ("Cached", Formatters.memory(store.snapshot.memoryCached))
      ]
    case .network:
      [
        ("Received", "\(Formatters.bytes(store.snapshot.networkInPerSecond))/s"),
        ("Sent", "\(Formatters.bytes(store.snapshot.networkOutPerSecond))/s")
      ]
    case .disk:
      [
        ("Used", Formatters.bytes(store.snapshot.diskUsed)),
        ("Free", Formatters.bytes(store.snapshot.diskTotal - store.snapshot.diskUsed))
      ]
    }
  }

  private var tint: Color {
    switch metric {
    case .cpu: MacHubTheme.green
    case .memory: MacHubTheme.blue
    case .network: MacHubTheme.purple
    case .disk: MacHubTheme.yellow
    }
  }
}

private struct ActivityValueBlock: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .frame(width: 16)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      Text(value)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.68)

      Text(detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct ActivityTrendChart: View {
  let values: [Double]
  let metric: ActivityMetric

  var body: some View {
    VStack(spacing: 7) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .trailing) {
          Text(topLabel)
          Spacer()
          Text(midLabel)
          Spacer()
          Text("0%")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 34)

        GeometryReader { proxy in
          ZStack {
            chartGrid
            Sparkline(values: values, tint: tint, showsFill: true)
              .padding(.vertical, 8)
              .padding(.trailing, 2)
          }
        }
      }

      HStack {
        Text(metric == .network || metric == .disk ? "Recent transfer rate" : "Last samples")
        Spacer()
        Text(metric.rawValue)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var chartGrid: some View {
    VStack {
      Rectangle().fill(MacHubTheme.hairline).frame(height: 1)
      Spacer()
      Rectangle().fill(MacHubTheme.hairline).frame(height: 1)
      Spacer()
      Rectangle().fill(MacHubTheme.hairline).frame(height: 1)
    }
    .overlay {
      HStack {
        ForEach(0..<6, id: \.self) { _ in
          Rectangle()
            .fill(MacHubTheme.hairline)
            .frame(width: 1)
          Spacer()
        }
      }
    }
  }

  private var topLabel: String {
    switch metric {
    case .network, .disk: "Max"
    default: "100%"
    }
  }

  private var midLabel: String {
    switch metric {
    case .network, .disk: "50%"
    default: "50%"
    }
  }

  private var tint: Color {
    switch metric {
    case .cpu: MacHubTheme.green
    case .memory: MacHubTheme.blue
    case .network: MacHubTheme.purple
    case .disk: MacHubTheme.yellow
    }
  }
}
