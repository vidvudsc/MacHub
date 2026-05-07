import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DashboardStore
  @SceneStorage("selectedSection") private var selectedSection = DashboardSection.overview.rawValue
  @State private var selectedActivityMetric: ActivityMetric = .cpu

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
            OverviewView(
              store: store,
              selectedMetric: $selectedActivityMetric,
              selectedSection: Binding(get: { section }, set: { section = $0 })
            )
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
    .background(DashboardWindowConfigurator())
    .preferredColorScheme(.dark)
  }
}

private struct DashboardWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      AppVisibilityService.configureDashboardWindow(view.window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      AppVisibilityService.configureDashboardWindow(nsView.window)
    }
  }
}

private struct TopBar: View {
  @Binding var section: DashboardSection
  @ObservedObject var store: DashboardStore

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        Text("MacHub")
          .font(.headline)
          .lineLimit(1)
      }
      .padding(.leading, 42)

      Picker("Section", selection: $section) {
        ForEach(DashboardSection.allCases) { section in
          Text(section.rawValue)
            .tag(section)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(minWidth: 300, maxWidth: 420)

      Spacer()

      if store.isRefreshing || store.isScanningFolders || store.isScanningCurrentFolder {
        ProgressView()
          .controlSize(.small)
      }

      Button {
        AppVisibilityService.hideToMenuBar()
      } label: {
        Image(systemName: "menubar.rectangle")
      }
      .help("Hide to Menu Bar")

      Button {
        Task { await store.refreshAll() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .disabled(store.isRefreshing)
      .help("Refresh")
    }
    .padding(.trailing, 12)
    .padding(.vertical, 10)
    .background(Color.white.opacity(0.035))
  }
}
