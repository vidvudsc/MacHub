import AppKit
import Foundation

enum PrivacySettingsService {
  static func openFullDiskAccess() {
    let urls = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    ]

    for rawURL in urls {
      guard let url = URL(string: rawURL) else { continue }
      if NSWorkspace.shared.open(url) {
        return
      }
    }

    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
