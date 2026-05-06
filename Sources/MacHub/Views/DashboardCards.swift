import SwiftUI

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
          .foregroundStyle(.secondary)
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
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
