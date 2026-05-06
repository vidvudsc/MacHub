import SwiftUI

struct WindowToolsView: View {
  @State private var status = "Ready"

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        MetricCard(
          title: "Front window",
          value: "Snap"
          ,
          detail: "Uses macOS Accessibility scripting. Grant permission when macOS asks.",
          systemImage: "rectangle.3.group",
          progress: nil
        )
        .frame(maxWidth: 340)

        VStack(alignment: .leading, spacing: 10) {
          Text("Status")
            .font(.headline)
          Text(status)
            .foregroundStyle(.secondary)
          Text("These actions resize the frontmost app window, not MacHub itself. Some apps may block scripting.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button {
            WindowManagerService.requestAccessibilityPermission()
            WindowManagerService.openAccessibilitySettings()
          } label: {
            Label("Accessibility Permission", systemImage: "hand.raised")
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
        ForEach(WindowLayout.allCases) { layout in
          Button {
            Task { await apply(layout) }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: layout.systemImage)
                .font(.title3)
                .frame(width: 28)
              Text(layout.rawValue)
                .font(.headline)
              Spacer()
              Text(layout.shortcutLabel)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .keyboardShortcut(shortcut(for: layout).key, modifiers: shortcut(for: layout).modifiers)
        }
      }
    }
  }

  private func apply(_ layout: WindowLayout) async {
    do {
      try await WindowManagerService.apply(layout)
      status = "Applied \(layout.rawValue)."
    } catch WindowManagerService.WindowError.accessibilityPermissionMissing {
      status = "Enable MacHub in System Settings > Privacy & Security > Accessibility."
    } catch {
      status = "Could not resize the front window. Some apps block window control."
    }
  }

  private func shortcut(for layout: WindowLayout) -> (key: KeyEquivalent, modifiers: EventModifiers) {
    switch layout {
    case .leftHalf: (.leftArrow, [.command, .shift])
    case .rightHalf: (.rightArrow, [.command, .shift])
    case .topHalf: (.upArrow, [.command, .shift])
    case .bottomHalf: (.downArrow, [.command, .shift])
    case .maximize: ("m", [.command, .shift])
    case .center: ("c", [.command, .shift])
    }
  }
}
