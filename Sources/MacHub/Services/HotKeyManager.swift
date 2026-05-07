import Carbon
import Foundation

final class HotKeyManager {
  static let shared = HotKeyManager()

  private var hotKeyRefs: [EventHotKeyRef?] = []
  private var handlerRef: EventHandlerRef?
  private(set) var registrationFailures: [(layout: WindowLayout, shortcut: WindowShortcut, status: OSStatus)] = []

  private init() { }

  func registerWindowHotKeys() {
    installHandlerIfNeeded()
    reloadWindowHotKeys()
  }

  func reloadWindowHotKeys() {
    unregisterWindowHotKeys()
    registrationFailures = []

    for layout in WindowLayout.allCases {
      var hotKeyRef: EventHotKeyRef?
      let shortcut = WindowShortcutStore.shared.shortcut(for: layout)
      let hotKeyID = EventHotKeyID(signature: fourCharCode("MHub"), id: layout.hotKeyIdentifier)
      let status = RegisterEventHotKey(
        shortcut.keyCode,
        shortcut.modifiers,
        hotKeyID,
        GetEventDispatcherTarget(),
        0,
        &hotKeyRef
      )
      if status == noErr {
        hotKeyRefs.append(hotKeyRef)
      } else {
        registrationFailures.append((layout, shortcut, status))
      }
    }
  }

  var registeredHotKeyCount: Int {
    hotKeyRefs.count
  }

  private func unregisterWindowHotKeys() {
    for hotKeyRef in hotKeyRefs {
      if let hotKeyRef {
        UnregisterEventHotKey(hotKeyRef)
      }
    }
    hotKeyRefs = []
  }

  private func installHandlerIfNeeded() {
    guard handlerRef == nil else { return }
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        guard status == noErr, let layout = WindowLayout(hotKeyIdentifier: hotKeyID.id) else {
          return noErr
        }

        Task {
          try? await WindowManagerService.apply(layout)
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &handlerRef
    )
  }

  private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
  }
}

extension WindowLayout {
  fileprivate init?(hotKeyIdentifier: UInt32) {
    switch hotKeyIdentifier {
    case 1: self = .leftHalf
    case 2: self = .rightHalf
    case 3: self = .maximize
    case 4: self = .center
    case 5: self = .topLeft
    case 6: self = .topRight
    case 7: self = .bottomLeft
    case 8: self = .bottomRight
    default: return nil
    }
  }

  fileprivate var hotKeyIdentifier: UInt32 {
    switch self {
    case .leftHalf: 1
    case .rightHalf: 2
    case .maximize: 3
    case .center: 4
    case .topLeft: 5
    case .topRight: 6
    case .bottomLeft: 7
    case .bottomRight: 8
    }
  }

}
