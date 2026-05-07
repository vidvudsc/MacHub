import AppKit
import Carbon
import SwiftUI

struct WindowToolsView: View {
  @State private var status = "Ready"
  @State private var recordingLayout: WindowLayout?
  @State private var shortcutVersion = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        UtilityPanel {
          PanelHeader(
            title: "Front window",
            detail: "Resize the frontmost app window with global shortcuts or one click."
          )
          Divider()
          CompactMetricRow(title: "Accessibility", value: WindowManagerService.isAccessibilityTrusted ? "Enabled" : "Needed", systemImage: "hand.raised")
          CompactMetricRow(title: "Hotkeys", value: "\(HotKeyManager.shared.registeredHotKeyCount)/\(WindowLayout.allCases.count)", systemImage: "keyboard")
          Button {
            WindowManagerService.requestAccessibilityPermission()
            WindowManagerService.openAccessibilitySettings()
          } label: {
            Label("Accessibility Permission", systemImage: "hand.raised")
          }
        }
        .frame(width: 360)

        UtilityPanel {
          PanelHeader(title: "Status")
          Text(status)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if !HotKeyManager.shared.registrationFailures.isEmpty {
            Text(hotKeyFailureSummary)
              .font(.callout)
              .foregroundStyle(MacHubTheme.yellow)
              .fixedSize(horizontal: false, vertical: true)
          }
          Text("Some apps block resizing, but most standard app windows should respond once Accessibility is enabled.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      UtilityPanel {
        PanelHeader(title: "Window layouts", detail: "Double-click a layout to change its global shortcut.")
        Divider()

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
          ForEach(WindowLayout.allCases) { layout in
            WindowLayoutTile(layout: layout)
              .id("\(layout.id)-\(shortcutVersion)")
              .gesture(
                TapGesture(count: 2)
                  .onEnded {
                    recordingLayout = layout
                  }
                  .exclusively(before: TapGesture(count: 1).onEnded {
                    Task { await apply(layout) }
                  })
              )
              .help("Click to apply. Double-click to edit shortcut.")
          }
        }
      }
    }
    .sheet(item: $recordingLayout) { layout in
      ShortcutRecorderSheet(
        layout: layout,
        onCancel: { recordingLayout = nil },
        onReset: {
          WindowShortcutStore.shared.resetShortcut(for: layout)
          HotKeyManager.shared.reloadWindowHotKeys()
          shortcutVersion += 1
          status = "Reset \(layout.rawValue) to \(layout.shortcutLabel)."
          recordingLayout = nil
        },
        onRecord: { shortcut in
          WindowShortcutStore.shared.setShortcut(shortcut, for: layout)
          HotKeyManager.shared.reloadWindowHotKeys()
          shortcutVersion += 1
          status = "Updated \(layout.rawValue) to \(shortcut.displayLabel)."
          recordingLayout = nil
        }
      )
    }
  }

  private func apply(_ layout: WindowLayout) async {
    do {
      try await WindowManagerService.apply(layout)
      status = "Applied \(layout.rawValue)."
    } catch WindowManagerService.WindowError.accessibilityPermissionMissing {
      status = "Enable MacHub in System Settings > Privacy & Security > Accessibility."
    } catch WindowManagerService.WindowError.noFrontmostApplication {
      status = "No target app found. Click the app window you want to resize, then try again."
    } catch WindowManagerService.WindowError.noFocusedWindow {
      status = "The target app did not report a focused window."
    } catch WindowManagerService.WindowError.cannotMoveWindow(let position, let size) {
      status = "macOS refused the resize. AX position \(position.rawValue), size \(size.rawValue). Try a normal non-full-screen window."
    } catch {
      status = "Could not resize the front window. Some apps block window control."
    }
  }

  private var hotKeyFailureSummary: String {
    let failed = HotKeyManager.shared.registrationFailures
      .map { "\($0.layout.rawValue) \($0.shortcut.displayLabel): \($0.status)" }
      .joined(separator: ", ")
    return "Some global shortcuts did not register: \(failed)"
  }
}

private struct WindowLayoutTile: View {
  let layout: WindowLayout

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: layout.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 24)
      Text(layout.rawValue)
        .font(.headline)
      Spacer()
      Text(layout.shortcutLabel)
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(MacHubTheme.stroke, lineWidth: 1)
    }
  }
}

private struct ShortcutRecorderSheet: View {
  let layout: WindowLayout
  let onCancel: () -> Void
  let onReset: () -> Void
  let onRecord: (WindowShortcut) -> Void
  @State private var message = "Press the new shortcut now."

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Image(systemName: layout.systemImage)
          .font(.title2)
          .foregroundStyle(MacHubTheme.blue)
          .frame(width: 34)

        VStack(alignment: .leading, spacing: 4) {
          Text(layout.rawValue)
            .font(.headline)
          Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Text(layout.shortcutLabel)
        .font(.system(size: 34, weight: .semibold, design: .rounded).monospaced())
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(MacHubTheme.stroke, lineWidth: 1)
        }

      ShortcutCaptureView { event in
        if event.keyCode == 53 {
          onCancel()
          return
        }

        guard let shortcut = WindowShortcut(event: event) else {
          message = "Use Command, Control, or Option with a key."
          return
        }
        onRecord(shortcut)
      }
      .frame(width: 1, height: 1)

      HStack {
        Button("Reset", action: onReset)
        Spacer()
        Button("Cancel", action: onCancel)
      }
    }
    .padding(20)
    .frame(width: 360)
    .buttonStyle(HubButtonStyle())
    .background(MacHubTheme.windowBackground)
    .preferredColorScheme(.dark)
  }
}

private struct ShortcutCaptureView: NSViewRepresentable {
  let onKeyDown: (NSEvent) -> Void

  func makeNSView(context: Context) -> KeyCaptureView {
    let view = KeyCaptureView()
    view.onKeyDown = onKeyDown
    DispatchQueue.main.async {
      view.window?.makeFirstResponder(view)
    }
    return view
  }

  func updateNSView(_ nsView: KeyCaptureView, context: Context) {
    nsView.onKeyDown = onKeyDown
    DispatchQueue.main.async {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

private final class KeyCaptureView: NSView {
  var onKeyDown: ((NSEvent) -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    DispatchQueue.main.async {
      self.window?.makeFirstResponder(self)
    }
  }

  override func keyDown(with event: NSEvent) {
    onKeyDown?(event)
  }
}

extension WindowShortcut {
  init?(event: NSEvent) {
    let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
    guard carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
      return nil
    }

    let label = Self.displayLabel(for: event, modifiers: event.modifierFlags)
    self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, displayLabel: label)
  }

  private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    return modifiers
  }

  private static func displayLabel(for event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
    var parts = ""
    if modifiers.contains(.control) { parts += "⌃" }
    if modifiers.contains(.option) { parts += "⌥" }
    if modifiers.contains(.shift) { parts += "⇧" }
    if modifiers.contains(.command) { parts += "⌘" }
    return parts + keyLabel(for: event)
  }

  private static func keyLabel(for event: NSEvent) -> String {
    switch event.keyCode {
    case 36: return "↩"
    case 48: return "⇥"
    case 49: return "Space"
    case 51: return "⌫"
    case 53: return "Esc"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default:
      if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
        return characters.uppercased()
      }
      return "Key \(event.keyCode)"
    }
  }
}
