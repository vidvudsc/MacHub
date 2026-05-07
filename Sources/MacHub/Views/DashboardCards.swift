import SwiftUI

enum MacHubTheme {
  static let windowBackground = LinearGradient(
    colors: [
      Color(red: 0.10, green: 0.12, blue: 0.13),
      Color(red: 0.07, green: 0.08, blue: 0.09)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  static let surface = Color.white.opacity(0.055)
  static let surfaceElevated = Color.white.opacity(0.08)
  static let stroke = Color.white.opacity(0.11)
  static let hairline = Color.white.opacity(0.07)
  static let green = Color(red: 0.32, green: 0.82, blue: 0.42)
  static let blue = Color(red: 0.27, green: 0.58, blue: 1.0)
  static let yellow = Color(red: 0.96, green: 0.68, blue: 0.10)
  static let purple = Color(red: 0.66, green: 0.35, blue: 0.93)
}

struct HubPanelBackground: ViewModifier {
  var cornerRadius: CGFloat = 8

  func body(content: Content) -> some View {
    content
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .background(MacHubTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(MacHubTheme.stroke, lineWidth: 1)
      }
  }
}

extension View {
  func hubPanel(cornerRadius: CGFloat = 8) -> some View {
    modifier(HubPanelBackground(cornerRadius: cornerRadius))
  }
}

struct HubButtonStyle: ButtonStyle {
  var isProminent = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.medium))
      .labelStyle(.titleAndIcon)
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .padding(.horizontal, 11)
      .padding(.vertical, 7)
      .foregroundStyle(isProminent ? .white : .primary)
      .background(
        (isProminent ? MacHubTheme.blue.opacity(0.62) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.075)),
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color.white.opacity(isProminent ? 0.18 : 0.08), lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.82 : 1)
  }
}

struct MetricCard: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String
  var progress: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: systemImage)
          .font(.title3)
          .foregroundStyle(tint(for: progress ?? 0.4))
          .frame(width: 24)
        Text(title)
          .font(.headline)
        Spacer()
      }

      Text(value)
        .font(.system(size: 30, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      if let progress {
        ProgressView(value: progress)
          .tint(tint(for: progress))
      }

      Text(detail)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .hubPanel()
  }

  private func tint(for progress: Double) -> Color {
    switch progress {
    case 0..<0.7: .green
    case 0.7..<0.88: .orange
    default: .red
    }
  }
}

struct CardGrid<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
      content
    }
  }
}

struct UtilityPanel<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .hubPanel()
  }
}

struct PanelHeader: View {
  let title: String
  var detail: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.headline)
      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct CompactMetricRow: View {
  let title: String
  let value: String
  let systemImage: String
  var progress: Double?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(tint(for: progress ?? 0.35))
        .frame(width: 20)
      Text(title)
        .lineLimit(1)
      Spacer()
      Text(value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      if let progress {
        ProgressView(value: progress)
          .frame(width: 86)
          .tint(tint(for: progress))
      }
    }
    .font(.callout)
    .padding(.vertical, 5)
  }

  private func tint(for progress: Double) -> Color {
    switch progress {
    case 0..<0.7: .green
    case 0.7..<0.88: .orange
    default: .red
    }
  }
}

struct UtilityListRow<Actions: View>: View {
  let systemImage: String
  let title: String
  let detail: String
  let value: String
  var tint: Color = .secondary
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(tint.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .lineLimit(1)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Text(value)
        .font(.headline.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 96, alignment: .trailing)

      actions
    }
    .padding(10)
    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MacHubTheme.hairline)
        .frame(height: 1)
        .padding(.leading, 50)
    }
  }
}

struct StatusPill: View {
  let text: String
  var tint: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .foregroundStyle(tint)
  }
}

struct PowerFlowPills: View {
  let battery: BatteryInfo
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 8 : 14) {
      PowerFlowPill(systemImage: leftIcon, value: wattValue, compact: compact)
      Image(systemName: "arrow.right")
        .font(compact ? .callout : .title3)
        .foregroundStyle(.secondary)
        .frame(width: compact ? 18 : 24)
      PowerFlowPill(systemImage: rightIcon, value: wattValue, compact: compact)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var wattValue: String {
    guard battery.isPresent else { return "--" }
    return compact ? Formatters.shortWatts(battery.watts) : Formatters.absoluteWatts(battery.watts)
  }

  private var leftIcon: String {
    if !battery.isPresent { return "battery.0percent" }
    if let watts = battery.watts, watts > 0.1 {
      return "powerplug"
    }
    if battery.isPluggedIn, let watts = battery.watts, watts < -0.1 {
      return "powerplug"
    }
    return "battery.75percent"
  }

  private var rightIcon: String {
    if !battery.isPresent { return "laptopcomputer" }
    if let watts = battery.watts, watts > 0.1 {
      return "battery.75percent"
    }
    return "laptopcomputer"
  }
}

private struct PowerFlowPill: View {
  let systemImage: String
  let value: String
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 6 : 10) {
      Image(systemName: systemImage)
        .font(.system(size: compact ? 14 : 17, weight: .semibold))
      Text(value)
        .font(.system(size: compact ? 14 : 18, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, compact ? 10 : 18)
    .padding(.vertical, compact ? 8 : 10)
    .frame(width: compact ? 104 : nil)
    .frame(minWidth: compact ? nil : 118)
    .background(Color.white.opacity(0.07), in: Capsule())
  }
}

struct Sparkline: View {
  let values: [Double]
  var tint: Color = MacHubTheme.green
  var showsFill = false

  var body: some View {
    GeometryReader { proxy in
      let points = normalizedPoints(in: proxy.size)
      ZStack(alignment: .bottomLeading) {
        if showsFill {
          fillPath(points: points, size: proxy.size)
            .fill(
              LinearGradient(
                colors: [tint.opacity(0.22), tint.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        }

        linePath(points: points)
          .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
      }
    }
  }

  private func normalizedPoints(in size: CGSize) -> [CGPoint] {
    let samples = values.isEmpty ? [0.18, 0.22, 0.2, 0.26, 0.24, 0.3, 0.28] : values
    let minValue = samples.min() ?? 0
    let maxValue = samples.max() ?? 1
    let range = max(maxValue - minValue, 0.01)
    let step = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : size.width

    return samples.enumerated().map { index, value in
      let normalized = (value - minValue) / range
      return CGPoint(
        x: CGFloat(index) * step,
        y: size.height - (size.height * CGFloat(min(max(normalized, 0), 1)))
      )
    }
  }

  private func linePath(points: [CGPoint]) -> Path {
    Path { path in
      guard let first = points.first else { return }
      path.move(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
    }
  }

  private func fillPath(points: [CGPoint], size: CGSize) -> Path {
    Path { path in
      guard let first = points.first, let last = points.last else { return }
      path.move(to: CGPoint(x: first.x, y: size.height))
      path.addLine(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
      path.addLine(to: CGPoint(x: last.x, y: size.height))
      path.closeSubpath()
    }
  }
}
