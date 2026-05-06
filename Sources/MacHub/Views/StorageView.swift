import SwiftUI

struct StorageView: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      HStack(alignment: .top, spacing: 16) {
        rootsList
          .frame(minWidth: 300, maxWidth: 360)

        FolderExplorer(store: store)
      }
    }
  }

  private var header: some View {
    HStack {
      Text("Storage scan")
        .font(.title3.weight(.semibold))
      if store.isScanningFolders || store.isScanningCurrentFolder {
        ProgressView()
          .controlSize(.small)
        Text(store.isScanningFolders ? "Scanning roots..." : "Scanning folder...")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        PrivacySettingsService.openFullDiskAccess()
      } label: {
        Label("Disk Access", systemImage: "lock.open")
      }
      Button {
        Task { await store.refreshFolders() }
      } label: {
        Label("Scan Roots", systemImage: "arrow.clockwise")
      }
      .disabled(store.isScanningFolders)
    }
  }

  private var rootsList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Starting points")
        .font(.headline)
      ForEach(store.folders) { folder in
        FolderRow(
          folder: folder,
          isSelected: store.currentFolder?.id == folder.id || store.folderPath.first?.id == folder.id,
          subtitle: folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        ) {
          store.openRoot(folder)
        }
      }
    }
  }
}

private struct FolderExplorer: View {
  @ObservedObject var store: DashboardStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let folder = store.currentFolder {
        explorerHeader(folder)

        HStack(alignment: .top, spacing: 14) {
          MetricCard(
            title: folder.isDirectory ? "Current folder" : "Selected item",
            value: Formatters.bytes(folder.bytes),
            detail: "\(folder.children.count) direct items loaded",
            systemImage: folder.isDirectory ? "folder" : "doc",
            progress: nil
          )
          .frame(maxWidth: 340)

          cleanupHints(folder)
        }

        childrenList(folder)
      } else {
        ContentUnavailableView(
          "No folder selected",
          systemImage: "folder.badge.questionmark",
          description: Text("Scan roots or select a folder to inspect storage.")
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func explorerHeader(_ folder: FolderUsage) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
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

        Spacer()

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

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(store.folderPath) { crumb in
            Button {
              Task { await store.jumpToPathItem(crumb) }
            } label: {
              Label(crumb.name, systemImage: "folder")
            }
            .buttonStyle(.bordered)
          }
        }
      }

      Text(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private func cleanupHints(_ folder: FolderUsage) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Clean safely")
        .font(.headline)
      Text("Use Trash for files you recognize. For app, cache, and developer folders, reveal first and verify before removing.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(role: .destructive) {
        store.moveToTrash(folder)
      } label: {
        Label("Move Current to Trash", systemImage: "trash")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        HStack(spacing: 10) {
          Image(systemName: child.isDirectory ? "folder" : "doc")
            .foregroundStyle(.secondary)
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 2) {
            Text(child.name)
              .lineLimit(1)
            Text(child.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer()
          Text(Formatters.bytes(child.bytes))
            .foregroundStyle(.secondary)
            .monospacedDigit()
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
          .labelStyle(.iconOnly)
          .help("Reveal in Finder")
          Button(role: .destructive) {
            store.moveToTrash(child)
          } label: {
            Label("Trash", systemImage: "trash")
          }
          .labelStyle(.iconOnly)
          .help("Move to Trash")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }
}

private struct FolderRow: View {
  let folder: FolderUsage
  let isSelected: Bool
  let subtitle: String
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
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Text(Formatters.bytes(folder.bytes))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 8)
            .fill(.selection.opacity(0.22))
        }
      }
    }
    .buttonStyle(.plain)
  }
}
