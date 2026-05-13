import SwiftUI

struct StorageView: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      UtilityPanel {
        HStack {
          PanelHeader(
            title: "Storage scan",
            detail: !store.hasFullDiskAccess
              ? "Full Disk Access is needed before MacHub scans Downloads and other protected folders."
              : store.isScanningFolders || store.isScanningCurrentFolder
              ? (store.isScanningFolders ? "Scanning starting points..." : "Scanning current folder...")
              : "Drill into folders and clean only what you recognize."
          )
          if store.isScanningFolders || store.isScanningCurrentFolder {
            ProgressView()
              .controlSize(.small)
          }
          Spacer()
          Button {
            Task { await store.refreshFolders() }
          } label: {
            Label("Scan Roots", systemImage: "arrow.clockwise")
          }
          .disabled(store.isScanningFolders || !store.hasFullDiskAccess)
        }
      }

      HStack(alignment: .top, spacing: 12) {
        startingPointsPanel
          .frame(width: 280)
        FolderExplorer(store: store)
          .frame(minWidth: 0, maxWidth: .infinity)
      }
    }
  }

  private var startingPointsPanel: some View {
    UtilityPanel {
      PanelHeader(title: "Starting points")
      Divider()
      ForEach(store.folders) { folder in
        RootFolderRow(
          folder: folder,
          isSelected: store.currentFolder?.id == folder.id || store.folderPath.first?.id == folder.id,
          action: { store.openRoot(folder) }
        )
      }
    }
  }
}

private struct FolderExplorer: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    UtilityPanel {
      if let folder = store.currentFolder {
        explorerHeader(folder)
        Divider()
        folderSummary(folder)
        Divider()
        childrenList(folder)
      } else {
        ContentUnavailableView(
          "No folder selected",
          systemImage: "folder.badge.questionmark",
          description: Text("Scan roots or select a folder to inspect storage.")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
      }
    }
  }

  private func explorerHeader(_ folder: FolderUsage) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ViewThatFits(in: .horizontal) {
        HStack {
          PanelHeader(title: folder.name, detail: folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
          Spacer(minLength: 12)
          explorerActions(folder)
        }

        VStack(alignment: .leading, spacing: 10) {
          PanelHeader(title: folder.name, detail: folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
          explorerActions(folder)
        }
      }

      ViewThatFits(in: .horizontal) {
        breadcrumbRow

        Menu {
          ForEach(store.folderPath) { crumb in
            Button(crumb.name) {
              Task { await store.jumpToPathItem(crumb) }
            }
          }
        } label: {
          Label(folder.name, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
      }
    }
  }

  private var breadcrumbRow: some View {
    HStack(spacing: 6) {
      ForEach(store.folderPath) { crumb in
        Button {
          Task { await store.jumpToPathItem(crumb) }
        } label: {
          Text(crumb.name)
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func explorerActions(_ folder: FolderUsage) -> some View {
    HStack(spacing: 8) {
      Button {
        Task { await store.goUp() }
      } label: {
        Label("Up", systemImage: "chevron.up")
      }
      .disabled(store.folderPath.count <= 1 || store.isScanningCurrentFolder)

      Button {
        Task { await store.scanCurrentFolder() }
      } label: {
        Label("Rescan", systemImage: "arrow.clockwise")
      }
      .disabled(store.isScanningCurrentFolder)

      Button {
        store.open(folder)
      } label: {
        Label("Open", systemImage: "folder")
      }

      Button {
        store.reveal(folder)
      } label: {
        Label("Reveal", systemImage: "magnifyingglass")
      }
    }
  }

  private func folderSummary(_ folder: FolderUsage) -> some View {
    HStack(spacing: 16) {
      CompactMetricRow(
        title: folder.isDirectory ? "Current folder" : "Selected item",
        value: Formatters.bytes(folder.bytes),
        systemImage: folder.isDirectory ? "folder" : "doc"
      )
      Text("\(folder.children.count) direct items loaded")
        .foregroundStyle(.secondary)
      Spacer()
      Button(role: .destructive) {
        store.moveToTrash(folder)
      } label: {
        Label("Move Current to Trash", systemImage: "trash")
      }
    }
  }

  private func childrenList(_ folder: FolderUsage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Largest items")
          .font(.headline)
        Spacer()
        Text("\(folder.children.count) shown")
          .foregroundStyle(.secondary)
      }

      ForEach(folder.sortedChildren) { child in
        UtilityListRow(
          systemImage: child.isDirectory ? "folder" : "doc",
          title: child.name,
          detail: child.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
          value: Formatters.bytes(child.bytes)
        ) {
          Button {
            Task { await store.drillInto(child) }
          } label: {
            Label(child.isDirectory ? "Dive In" : "Open", systemImage: child.isDirectory ? "chevron.right" : "arrow.up.right.square")
          }
          .disabled(store.isScanningCurrentFolder)

          Button {
            store.reveal(child)
          } label: {
            Label("Reveal", systemImage: "magnifyingglass")
          }

          Button(role: .destructive) {
            store.moveToTrash(child)
          } label: {
            Label("Trash", systemImage: "trash")
          }
        }
      }
    }
  }
}

private struct RootFolderRow: View {
  let folder: FolderUsage
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "folder")
          .foregroundStyle(.secondary)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 3) {
          Text(folder.name)
            .lineLimit(1)
          Text(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Text(Formatters.bytes(folder.bytes))
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(10)
      .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 8)
            .stroke(MacHubTheme.blue.opacity(0.65), lineWidth: 1)
        }
      }
    }
    .buttonStyle(.plain)
  }
}
