import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    if let frontmost = NSWorkspace.shared.frontmostApplication {
      WindowManagerService.noteActivatedApplication(frontmost)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(applicationActivated(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
    HotKeyManager.shared.registerWindowHotKeys()
    DispatchQueue.main.async {
      AppVisibilityService.closeDuplicateDashboardWindows()
      AppVisibilityService.showDashboard()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillHide(_ notification: Notification) {
    AppVisibilityService.hideToMenuBar()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    AppVisibilityService.showDashboard()
    return true
  }

  @objc private func applicationActivated(_ notification: Notification) {
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
      return
    }
    WindowManagerService.noteActivatedApplication(app)
  }
}

@main
struct MacHubApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store = DashboardStore()

  var body: some Scene {
    WindowGroup("MacHub", id: "main") {
      ContentView(store: store)
        .frame(minWidth: 680, minHeight: 380)
        .task {
          await store.startDashboard()
        }
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) { }
      CommandMenu("MacHub") {
        Button("Refresh") {
          Task { await store.refreshAll() }
        }
        .keyboardShortcut("r", modifiers: [.command])

        Button("Open Full Disk Access") {
          PrivacySettingsService.openFullDiskAccess()
        }
        .keyboardShortcut(",", modifiers: [.command, .shift])
      }
      CommandMenu("Window Tools") {
        Button("Left Half") {
          Task { try? await WindowManagerService.apply(.leftHalf) }
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

        Button("Right Half") {
          Task { try? await WindowManagerService.apply(.rightHalf) }
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

        Button("Full View") {
          Task { try? await WindowManagerService.apply(.maximize) }
        }
        .keyboardShortcut(.upArrow, modifiers: [.command, .shift])

        Button("Center") {
          Task { try? await WindowManagerService.apply(.center) }
        }
        .keyboardShortcut(.downArrow, modifiers: [.command, .shift])

        Divider()

        Button("Top Left") {
          Task { try? await WindowManagerService.apply(.topLeft) }
        }
        .keyboardShortcut("q", modifiers: [.command, .shift])

        Button("Top Right") {
          Task { try? await WindowManagerService.apply(.topRight) }
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])

        Button("Bottom Left") {
          Task { try? await WindowManagerService.apply(.bottomLeft) }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Bottom Right") {
          Task { try? await WindowManagerService.apply(.bottomRight) }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
      }
    }

    MenuBarExtra {
      MenuBarPanel(store: store) {
        AppVisibilityService.showDashboard()
      }
      .task {
        await store.start()
      }
    } label: {
      Image(systemName: "gauge.with.dots.needle.67percent")
        .task {
          await store.start()
        }
    }
    .menuBarExtraStyle(.window)
  }
}
