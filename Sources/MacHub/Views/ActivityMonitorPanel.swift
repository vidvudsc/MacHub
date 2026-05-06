import SwiftUI

struct ActivityMonitorPanel: View {
  @ObservedObject var store: DashboardStore
  @State private var metric: ActivityMetric = .cpu

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Metric", selection: $metric) {
        ForEach(ActivityMetric.allCases) { metric in
          Text(metric.rawValue).tag(metric)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 520)

      HStack(alignment: .top, spacing: 16) {
        ActivityBars(values: values)
          .frame(height: 210)

        VStack(alignment: .leading, spacing: 12) {
          Text(primaryValue)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(secondaryValue)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          Divider()

          ForEach(detailRows, id: \.0) { row in
            LabeledContent(row.0, value: row.1)
              .font(.callout)
          }
        }
        .frame(width: 230, alignment: .topLeading)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}

private struct ActivityBars: View {
  let values: [Double]

  var body: some View {
    GeometryReader { proxy in
      let barCount = max(values.count, 1)
      let spacing: CGFloat = 3
      let width = max((proxy.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount), 3)

      HStack(alignment: .bottom, spacing: spacing) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          RoundedRectangle(cornerRadius: 2)
            .fill(.blue.gradient)
            .frame(width: width, height: max(proxy.size.height * value, 3))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .overlay {
        VStack {
          Divider().opacity(0.35)
          Spacer()
          Divider().opacity(0.2)
          Spacer()
          Divider().opacity(0.2)
        }
      }
    }
  }
}
