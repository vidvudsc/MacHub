import SwiftUI

struct CleanerView: View {
  @ObservedObject var store: DashboardStore

  private var totalCleanable: UInt64 {
    store.cleanupTargets.filter(\.isSafeToTrash).reduce(0) { $0 + $1.bytes }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      UtilityPanel {
        HStack(spacing: 22) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Likely safe cleanup")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(Formatters.bytes(totalCleanable))
              .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            Text("Selected")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button {
            Task { await store.refreshCleanupTargets() }
          } label: {
            Label("Rescan Junk", systemImage: "arrow.clockwise")
          }
          .disabled(!store.hasFullDiskAccess)

          if !store.hasFullDiskAccess {
            Divider()
              .frame(height: 52)

            VStack(alignment: .leading, spacing: 5) {
              Text("Full Disk Access")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text("Needed")
                .font(.headline)
                .foregroundStyle(MacHubTheme.yellow)
              Text("Required before protected scans")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
              PrivacySettingsService.openFullDiskAccess()
            } label: {
              Label("Open Settings", systemImage: "checkmark.circle")
            }
          }
        }
      }

      UtilityPanel {
        HStack {
          Text("Item")
            .frame(maxWidth: .infinity, alignment: .leading)
          Text("Details")
            .frame(maxWidth: .infinity, alignment: .leading)
          Text("Size")
            .frame(width: 110, alignment: .trailing)
          Text("Safety")
            .frame(width: 80)
          Text("Action")
            .frame(width: 140)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)

        ForEach(store.cleanupTargets) { target in
          CleanupRow(target: target, store: store)
        }

        if store.cleanupTargets.isEmpty {
          ContentUnavailableView(
            store.hasFullDiskAccess ? "Nothing scanned yet" : "Full Disk Access needed",
            systemImage: store.hasFullDiskAccess ? "sparkles" : "lock",
            description: Text(store.hasFullDiskAccess ? "Run a junk scan to estimate cleanable files." : "Enable MacHub in Full Disk Access before scanning protected folders.")
          )
          .frame(maxWidth: .infinity, minHeight: 180)
        }
      }
    }
  }
}

private struct CleanupRow: View {
  let target: CleanupTarget
  @ObservedObject var store: DashboardStore

  var body: some View {
    UtilityListRow(
      systemImage: target.systemImage,
      title: target.title,
      detail: target.detail,
      value: Formatters.bytes(target.bytes),
      tint: target.isSafeToTrash ? .blue : .orange
    ) {
      StatusPill(text: target.isSafeToTrash ? "Safe" : "Review", tint: target.isSafeToTrash ? MacHubTheme.green : MacHubTheme.yellow)

      Button {
        NSWorkspace.shared.open(target.url)
      } label: {
        Label("Open", systemImage: "folder")
      }

      Button(role: target.isSafeToTrash ? .destructive : nil) {
        if target.isSafeToTrash {
          store.moveCleanupTargetToTrash(target)
        } else {
          NSWorkspace.shared.activateFileViewerSelecting([target.url])
        }
      } label: {
        Label(target.isSafeToTrash ? "Trash" : "Review", systemImage: target.isSafeToTrash ? "trash" : "magnifyingglass")
      }
    }
  }
}
