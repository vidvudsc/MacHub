import SwiftUI

struct BatteryView: View {
  @ObservedObject var store: DashboardStore

  private var battery: BatteryInfo {
    store.snapshot.battery
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      BatteryInspectorCard(store: store)
        .frame(width: 500)
    }
  }
}

private struct BatteryInspectorCard: View {
  @ObservedObject var store: DashboardStore

  private var battery: BatteryInfo {
    store.snapshot.battery
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline) {
        Text("Battery")
          .font(.title2.weight(.semibold))
        Spacer()
        Text(battery.isPresent ? Formatters.percent(battery.percent) : "No battery")
          .font(.title2.weight(.semibold))
          .monospacedDigit()
      }

      VStack(spacing: 10) {
        InfoRow("Time Left", Formatters.minutes(battery.timeRemainingMinutes))
        InfoRow("Mode", battery.isPluggedIn ? "Charger connected" : "Charger not connected")
      }

      Divider()

      VStack(spacing: 10) {
        InfoRow("Power Source", battery.isPluggedIn ? "Power Adapter" : "Battery Power")
        InfoRow("Battery Power", Formatters.watts(battery.watts))
        InfoRow("Voltage", Formatters.volts(battery.voltage))
        InfoRow("Current", Formatters.amps(battery.amperage))
        InfoRow("Temperature", Formatters.celsius(battery.temperature))
        InfoRow("Health", battery.health ?? "Unknown")
        InfoRow("Cycles", battery.cycleCount.map(String.init) ?? "Unavailable")
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text("Recent charge")
          .font(.headline)
          .foregroundStyle(.secondary)
        BatteryLineChart(samples: store.batteryHistory)
          .frame(height: 160)
      }

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        Text("Power distribution")
          .font(.headline)
          .foregroundStyle(.secondary)

        HStack(spacing: 14) {
          PowerPill(systemImage: "battery.75percent", value: Formatters.watts(battery.watts))
          Image(systemName: "arrow.right")
            .font(.title3)
            .foregroundStyle(.secondary)
          PowerPill(systemImage: "laptopcomputer", value: Formatters.watts(battery.watts.map(abs)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct InfoRow: View {
  let title: String
  let value: String

  init(_ title: String, _ value: String) {
    self.title = title
    self.value = value
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.headline)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
    }
  }
}

private struct PowerPill: View {
  let systemImage: String
  let value: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
      Text(value)
        .monospacedDigit()
    }
    .font(.headline)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(.quaternary, in: Capsule())
  }
}

private struct BatteryLineChart: View {
  let samples: [BatterySample]
  private let hoursToShow = 12

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            grid(width: proxy.size.width)

            Path { path in
              let points = chartPoints(in: proxy.size)
              guard !points.isEmpty else { return }
              for index in points.indices {
                let point = points[index]
                if index == points.startIndex {
                  path.move(to: point)
                } else {
                  path.addLine(to: point)
                }
              }
            }
            .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          }
          .clipped()
        }
        .frame(height: 120)

        VStack(alignment: .trailing) {
          Text("100%")
          Spacer()
          Text("50%")
          Spacer()
          Text("0%")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 34, height: 120)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          ForEach(hourTicks(), id: \.timeIntervalSince1970) { tick in
            Text(hourLabel(tick))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .position(x: xPosition(for: tick, width: proxy.size.width - 42), y: 10)
          }
        }
      }
      .frame(height: 20)
    }
  }

  private var startDate: Date {
    Calendar.current.date(byAdding: .hour, value: -hoursToShow, to: endDate) ?? endDate.addingTimeInterval(-43_200)
  }

  private var endDate: Date {
    Date()
  }

  private func chartPoints(in size: CGSize) -> [CGPoint] {
    samples
      .filter { $0.date >= startDate && $0.date <= endDate }
      .map { sample in
        let x = xPosition(for: sample.date, width: size.width)
        let y = size.height * CGFloat(1 - min(max(sample.percent, 0), 1))
        return CGPoint(x: x, y: y)
      }
  }

  private func grid(width: CGFloat) -> some View {
    ZStack {
      VStack {
        Divider().opacity(0.45)
        Spacer()
        Divider().opacity(0.3)
        Spacer()
        Divider().opacity(0.3)
      }

      ForEach(hourTicks(), id: \.timeIntervalSince1970) { tick in
        DashedVerticalLine()
          .opacity(0.25)
          .position(x: xPosition(for: tick, width: width), y: 60)
          .frame(width: 1, height: 120)
      }
    }
    .frame(width: width, height: 120)
    .clipped()
  }

  private var timeLabels: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        ForEach(hourTicks(), id: \.timeIntervalSince1970) { tick in
          Text(hourLabel(tick))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .position(x: xPosition(for: tick, width: max(proxy.size.width - 42, 0)), y: 10)
        }
      }
    }
  }

  private func hourTicks() -> [Date] {
    let calendar = Calendar.current
    let currentHour = calendar.dateInterval(of: .hour, for: endDate)?.start ?? endDate
    return stride(from: hoursToShow, through: 0, by: -3).compactMap {
      calendar.date(byAdding: .hour, value: -$0, to: currentHour)
    }
  }

  private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
    let total = endDate.timeIntervalSince(startDate)
    guard total > 0 else { return 0 }
    let elapsed = date.timeIntervalSince(startDate)
    return min(max(CGFloat(elapsed / total) * width, 0), width)
  }

  private func hourLabel(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
  }
}

private struct DashedVerticalLine: View {
  var body: some View {
    GeometryReader { proxy in
      Path { path in
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
      }
      .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }
    .frame(width: 1)
  }
}
