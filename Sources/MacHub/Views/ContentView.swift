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

      Rectangle()
        .fill(MacHubTheme.stroke)
        .frame(height: 1)

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(HubButtonStyle())
    .foregroundStyle(.primary)
    .background(MacHubTheme.windowBackground)
    .preferredColorScheme(.dark)
  }
}

private struct TopBar: View {
  @Binding var section: DashboardSection
  @ObservedObject var store: DashboardStore

  var body: some View {
    HStack(spacing: 14) {
      HStack(spacing: 8) {
        Text("MacHub")
          .font(.headline)
          .lineLimit(1)
      }
      .padding(.leading, 60)

      Picker("Section", selection: $section) {
        ForEach(DashboardSection.allCases) { section in
          Text(section.rawValue)
            .tag(section)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 420)

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
    .padding(.trailing, 12)
    .padding(.vertical, 10)
    .background(Color.white.opacity(0.035))
  }
}
