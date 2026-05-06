import SwiftUI

struct ToolsView: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ToolRow(
        title: "Open Downloads",
        detail: "Jump to a common cleanup folder.",
        systemImage: "folder"
      ) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(url)
      }

      ToolRow(
        title: "Show Caches",
        detail: "Inspect user caches before removing anything.",
        systemImage: "externaldrive.badge.magnifyingglass"
      ) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        NSWorkspace.shared.open(url)
      }

      ToolRow(
        title: "Open Trash",
        detail: "Review trashed files before deleting anything permanently.",
        systemImage: "trash"
      ) {
        store.openTrash()
      }

      ToolRow(
        title: "Refresh Everything",
        detail: "Update folders, battery, CPU, RAM, disk, and GPU info.",
        systemImage: "arrow.clockwise"
      ) {
        Task { await store.refreshAll() }
      }
    }
    .frame(maxWidth: 720, alignment: .leading)
  }
}

private struct ToolRow: View {
  let title: String
  let detail: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Run", action: action)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}
