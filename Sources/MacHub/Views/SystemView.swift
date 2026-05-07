import SwiftUI

struct SystemView: View {
  @ObservedObject var store: DashboardStore
  @State private var selectedMetric: ActivityMetric = .cpu

  private var snapshot: SystemSnapshot {
    store.snapshot
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      ActivityMonitorPanel(store: store, metric: $selectedMetric)

      CardGrid {
        MetricCard(
          title: "CPU load",
          value: Formatters.percent(snapshot.cpuUsage),
          detail: "\(snapshot.processCount) processes",
          systemImage: "cpu",
          progress: snapshot.cpuUsage
        )
        MetricCard(
          title: "RAM",
          value: Formatters.memory(snapshot.memoryUsed),
          detail: "\(Formatters.memory(snapshot.memoryTotal)) total",
          systemImage: "memorychip",
          progress: snapshot.memoryPressure
        )
        MetricCard(
          title: "Uptime",
          value: Formatters.duration(snapshot.uptime),
          detail: "Since last restart",
          systemImage: "timer",
          progress: nil
        )
        MetricCard(
          title: "Disk used",
          value: Formatters.percent(snapshot.diskPressure),
          detail: "\(Formatters.bytes(snapshot.diskUsed)) of \(Formatters.bytes(snapshot.diskTotal))",
          systemImage: "internaldrive",
          progress: snapshot.diskPressure
        )
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Graphics")
          .font(.title3.weight(.semibold))
        LabeledContent("GPU", value: snapshot.gpu.name)
        LabeledContent("Memory / cores", value: snapshot.gpu.vram)
        LabeledContent("Metal", value: snapshot.gpu.metal)
      }
      .padding(16)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
  }
}
