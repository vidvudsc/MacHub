import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DashboardStore
  @SceneStorage("selectedSection") private var selectedSection = DashboardSection.overview.rawValue

  private var section: DashboardSection {
    get { DashboardSection(rawValue: selectedSection) ?? .overview }
    nonmutating set { selectedSection = newValue.rawValue }
  }

  var body: some View {
    VStack(spacing: 0) {
      TopBar(section: Binding(get: { section }, set: { section = $0 }), store: store)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HeaderView(section: section, store: store)

          switch section {
          case .overview:
            OverviewView(store: store)
          case .clean:
            CleanerView(store: store)
          case .storage:
            StorageView(store: store)
          case .battery:
            BatteryView(store: store)
          case .windows:
            WindowToolsView()
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(.background)
    }
  }
}

private struct TopBar: View {
  @Binding var section: DashboardSection
  @ObservedObject var store: DashboardStore

  var body: some View {
    HStack(spacing: 16) {
      HStack(spacing: 9) {
        Image(systemName: "sparkles.rectangle.stack")
          .font(.title3)
          .foregroundStyle(.blue)
        Text("MacHub")
          .font(.headline)
      }

      Picker("Section", selection: $section) {
        ForEach(DashboardSection.allCases) { section in
          Label(section.rawValue, systemImage: section.systemImage)
            .tag(section)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 560)

      Spacer()

      if store.isRefreshing || store.isScanningFolders || store.isScanningCurrentFolder {
        ProgressView()
          .controlSize(.small)
      }

      Button {
        AppVisibilityService.hideToMenuBar()
      } label: {
        Label("Hide to Menu Bar", systemImage: "menubar.rectangle")
      }

      Button {
        Task { await store.refreshAll() }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(store.isRefreshing)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }
}

private struct HeaderView: View {
  let section: DashboardSection
  @ObservedObject var store: DashboardStore

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text(section.rawValue)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
        Text(subtitle)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(store.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Starting up")
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  private var subtitle: String {
    switch section {
    case .overview:
      "Live CPU, memory, network, disk, and quick system health."
    case .clean:
      "Find junk, review it, and move only what you choose to Trash."
    case .storage:
      "Drill into folders to see what is actually taking space."
    case .battery:
      "Charge, health, signed watts, voltage, current, and time estimates."
    case .windows:
      "Resize the frontmost window with one click."
    }
  }
}
