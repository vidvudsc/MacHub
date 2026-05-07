import SwiftUI

struct BatteryView: View {
  @ObservedObject var store: DashboardStore

  private var battery: BatteryInfo {
    store.snapshot.battery
  }

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      UtilityPanel {
        BatteryFactsCard(battery: battery)
      }
      .frame(width: 300)

      UtilityPanel {
        BatteryTrendCard(store: store)
      }
      .frame(maxWidth: 520)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct BatteryFactsCard: View {
  let battery: BatteryInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text("Battery")
          .font(.headline)
        Spacer()
        Text(battery.isPresent ? Formatters.percent(battery.percent) : "No battery")
          .font(.headline.monospacedDigit())
      }

      Divider()

      VStack(spacing: 12) {
        InfoRow("Time Left", Formatters.batteryTime(battery), systemImage: "timer")
        InfoRow("Mode", battery.isPluggedIn ? "Plugged In" : "On Battery", systemImage: "powerplug")
        InfoRow("Power Source", battery.isPluggedIn ? "Adapter" : "Battery", systemImage: "battery.75percent")
        InfoRow("Battery Power", Formatters.watts(battery.watts), systemImage: "bolt")
        InfoRow("Voltage", Formatters.volts(battery.voltage), systemImage: "waveform.path.ecg")
        InfoRow("Current", Formatters.amps(battery.amperage), systemImage: "plusminus")
        InfoRow("Temperature", Formatters.celsius(battery.temperature), systemImage: "thermometer.medium")
        InfoRow("Health", battery.health ?? "Unknown", systemImage: "heart")
        InfoRow("Cycles", battery.cycleCount.map(String.init) ?? "Unavailable", systemImage: "clock.arrow.circlepath")
      }
    }
  }
}

private struct BatteryTrendCard: View {
  @ObservedObject var store: DashboardStore

  private var battery: BatteryInfo {
    store.snapshot.battery
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Recent charge")
          .font(.headline)
        BatteryLineChart(samples: store.batteryHistory)
          .frame(height: 160)
      }

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        Text("Power flow")
          .font(.headline)

        PowerFlowPills(battery: battery)

        Text(powerFlowDetail)
          .font(.callout)
          .foregroundStyle(.secondary)

        if let topPowerApp = store.snapshot.topPowerApp {
          PowerAppRow(app: topPowerApp)
        }
      }
    }
  }

  private var powerFlowDetail: String {
    guard battery.isPresent else { return "No battery power data is available." }
    guard let watts = battery.watts else {
      return battery.isPluggedIn ? "Connected to charger; battery flow is still measuring." : "Running on battery; watt draw is still measuring."
    }
    if watts > 0.1 {
      return battery.isCharging ? "Watts are flowing into the battery from the charger." : "Adapter power is connected and battery flow is positive."
    }
    if watts < -0.1 {
      return battery.isPluggedIn ? "The Mac is using charger power and supplementing from the battery." : "Watts are flowing out of the battery."
    }
    return battery.isPluggedIn ? "Connected to charger with the battery mostly idle." : "Battery flow is near idle."
  }
}

private struct PowerAppRow: View {
  let app: PowerAppInfo

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "bolt.fill")
        .foregroundStyle(MacHubTheme.yellow)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text("Top power app")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(app.name)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(Formatters.estimatedWatts(app.estimatedWatts))
          .font(.headline.monospacedDigit())
        Text("\(String(format: "%.0f%% CPU", app.cpuPercent)) · \(Formatters.memory(app.memoryBytes))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(MacHubTheme.stroke, lineWidth: 1)
    }
  }
}

private struct InfoRow: View {
  let title: String
  let value: String
  let systemImage: String

  init(_ title: String, _ value: String, systemImage: String) {
    self.title = title
    self.value = value
    self.systemImage = systemImage
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(title)
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.callout.weight(.semibold))
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
    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(MacHubTheme.stroke, lineWidth: 1)
    }
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
