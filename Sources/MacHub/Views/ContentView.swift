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
  final class Coordinator {
    weak var configuredWindow: NSWindow?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      configureIfNeeded(view.window, context: context)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard context.coordinator.configuredWindow !== nsView.window else { return }
    DispatchQueue.main.async {
      configureIfNeeded(nsView.window, context: context)
    }
  }

  private func configureIfNeeded(_ window: NSWindow?, context: Context) {
    guard let window, context.coordinator.configuredWindow !== window else { return }
    AppVisibilityService.configureDashboardWindow(window)
    context.coordinator.configuredWindow = window
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

      HStack(spacing: 0) {
        ForEach(DashboardSection.allCases) { section in
          Button {
            self.section = section
          } label: {
            Text(section.rawValue)
              .font(.callout.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .foregroundStyle(self.section == section ? .white : .secondary)
              .background(
                self.section == section ? MacHubTheme.blue : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
              )
              .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
          .frame(maxWidth: .infinity)
          .buttonStyle(.plain)
        }
      }
      .padding(2)
      .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .frame(minWidth: 520, maxWidth: 620)
      .layoutPriority(1)

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
