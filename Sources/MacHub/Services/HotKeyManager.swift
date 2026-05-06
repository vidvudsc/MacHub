import Carbon
import Foundation

final class HotKeyManager {
  static let shared = HotKeyManager()

  private var hotKeyRefs: [EventHotKeyRef?] = []
  private var handlerRef: EventHandlerRef?

  private init() { }

  func registerWindowHotKeys() {
    guard hotKeyRefs.isEmpty else { return }

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

    for layout in WindowLayout.allCases {
      var hotKeyRef: EventHotKeyRef?
      let hotKeyID = EventHotKeyID(signature: fourCharCode("MHub"), id: layout.hotKeyIdentifier)
      RegisterEventHotKey(
        layout.keyCode,
        UInt32(cmdKey | shiftKey),
        hotKeyID,
        GetEventDispatcherTarget(),
        0,
        &hotKeyRef
      )
      hotKeyRefs.append(hotKeyRef)

      var fallbackRef: EventHotKeyRef?
      RegisterEventHotKey(
        layout.keyCode,
        UInt32(controlKey | optionKey),
        hotKeyID,
        GetEventDispatcherTarget(),
        0,
        &fallbackRef
      )
      hotKeyRefs.append(fallbackRef)
    }
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
    case 3: self = .topHalf
    case 4: self = .bottomHalf
    case 5: self = .maximize
    case 6: self = .center
    default: return nil
    }
  }

  fileprivate var hotKeyIdentifier: UInt32 {
    switch self {
    case .leftHalf: 1
    case .rightHalf: 2
    case .topHalf: 3
    case .bottomHalf: 4
    case .maximize: 5
    case .center: 6
    }
  }

  fileprivate var keyCode: UInt32 {
    switch self {
    case .leftHalf: 123
    case .rightHalf: 124
    case .topHalf: 126
    case .bottomHalf: 125
    case .maximize: 46
    case .center: 8
    }
  }
}
