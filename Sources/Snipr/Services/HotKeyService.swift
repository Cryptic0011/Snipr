import Carbon
import Foundation

enum SniprHotKey {
    case commandPalette
    case captureArea
}

@MainActor
final class HotKeyService {
    private let handler: (SniprHotKey) -> Void
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    init(handler: @escaping (SniprHotKey) -> Void) {
        self.handler = handler
    }

    func invalidate() {
        for ref in refs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }

        refs.removeAll()
        eventHandler = nil
    }

    func registerDefaults() {
        installEventHandlerIfNeeded()
        register(keyCode: UInt32(kVK_Space), modifiers: cmdKey | shiftKey, id: 1)
        register(keyCode: UInt32(kVK_ANSI_4), modifiers: cmdKey | shiftKey, id: 2)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                Task { @MainActor in
                    service.handleHotKey(id: hotKeyID.id)
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func register(keyCode: UInt32, modifiers: Int, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let signature = OSType(UInt32(bigEndian: "SNPR".fourCharCode))
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            refs.append(hotKeyRef)
        }
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            handler(.commandPalette)
        case 2:
            handler(.captureArea)
        default:
            break
        }
    }
}

private extension String {
    var fourCharCode: UInt32 {
        unicodeScalars.reduce(UInt32(0)) { result, scalar in
            (result << 8) + scalar.value
        }
    }
}
