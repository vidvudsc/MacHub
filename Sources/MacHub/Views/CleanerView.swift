import SwiftUI

struct CleanerView: View {
  @ObservedObject var store: DashboardStore

  private var totalCleanable: UInt64 {
    store.cleanupTargets.filter(\.isSafeToTrash).reduce(0) { $0 + $1.bytes }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        MetricCard(
          title: "Likely safe cleanup",
          value: Formatters.bytes(totalCleanable),
          detail: "Caches, logs, build artifacts, and Trash. Still review before removing.",
          systemImage: "sparkles",
          progress: nil
        )
        .frame(maxWidth: 360)

        VStack(alignment: .leading, spacing: 10) {
          Text("Cleaner rules")
            .font(.headline)
          Text("MacHub does not silently delete. Safe items go to Trash; review-heavy folders open in Finder so you stay in control.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button {
            Task { await store.refreshCleanupTargets() }
          } label: {
            Label("Rescan Junk", systemImage: "arrow.clockwise")
          }

          Button {
            PrivacySettingsService.openFullDiskAccess()
          } label: {
            Label("Full Disk Access", systemImage: "lock.open")
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Cleanup targets")
          .font(.title3.weight(.semibold))

        ForEach(store.cleanupTargets) { target in
          CleanupRow(target: target, store: store)
        }

        if store.cleanupTargets.isEmpty {
          ContentUnavailableView("Nothing scanned yet", systemImage: "sparkles", description: Text("Run a junk scan to estimate cleanable files."))
        }
      }
    }
  }
}

private struct CleanupRow: View {
  let target: CleanupTarget
  @ObservedObject var store: DashboardStore

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: target.systemImage)
        .font(.title3)
        .foregroundStyle(target.isSafeToTrash ? .blue : .orange)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(target.title)
            .font(.headline)
          Text(target.isSafeToTrash ? "Safe-ish" : "Review")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(target.isSafeToTrash ? .blue.opacity(0.16) : .orange.opacity(0.18), in: Capsule())
        }
        Text(target.detail)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Text(Formatters.bytes(target.bytes))
        .font(.headline.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 110, alignment: .trailing)

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
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}
