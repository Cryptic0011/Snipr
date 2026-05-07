import Carbon
import Foundation

@MainActor
final class HotKeyService {
    private let handler: (SniprHotKeyAction) -> Void
    private(set) var registrationFailures: [SniprHotKeyAction: OSStatus] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var actionByHotKeyID: [UInt32: SniprHotKeyAction] = [:]

    init(handler: @escaping (SniprHotKeyAction) -> Void) {
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
        actionByHotKeyID.removeAll()
        registrationFailures.removeAll()
    }

    func register(_ bindings: [SniprHotKeyAction: HotKeyBinding]) {
        invalidate()
        installEventHandlerIfNeeded()

        for action in SniprHotKeyAction.allCases where action.isAvailable {
            let binding = bindings[action] ?? HotKeyDefaults.bindings[action]
            guard let binding, binding.isEnabled else {
                continue
            }

            register(keyCode: binding.keyCode, modifiers: binding.modifiers, id: UInt32(action.registrationID), action: action)
        }
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

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: SniprHotKeyAction) {
        var hotKeyRef: EventHotKeyRef?
        // "SNPR" is already a big-endian-ordered FourCharCode after
        // `fourCharCode` packs it MSB→LSB. The previous `UInt32(bigEndian:)`
        // wrapper byte-swapped it a second time, producing 0x52504E53. The
        // Carbon HotKey signature is conventionally the literal four-char
        // value (0x534E5052 for "SNPR"), so drop the swap.
        let hotKeyID = EventHotKeyID(signature: OSType("SNPR".fourCharCode), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            refs.append(hotKeyRef)
            actionByHotKeyID[id] = action
        } else {
            registrationFailures[action] = status
        }
    }

    private func handleHotKey(id: UInt32) {
        if let action = actionByHotKeyID[id] {
            handler(action)
        }
    }
}

private extension SniprHotKeyAction {
    var registrationID: Int {
        switch self {
        case .openApp:
            1
        case .captureArea:
            2
        case .captureToolbar:
            3
        case .screenRecord:
            4
        case .commandPalette:
            5
        case .hideStack:
            6
        case .showStack:
            7
        case .clearStack:
            8
        case .captureWindow:
            9
        case .captureLastRegion:
            10
        case .ocr:
            11
        case .colorPick:
            12
        case .scrollingCapture:
            13
        }
    }
}

extension String {
    /// Packs the first four ASCII characters MSB→LSB into a `UInt32`.
    /// `"SNPR"` becomes `0x534E5052`. Internal so tests can assert the
    /// signature value pinned by the Phase 0 acceptance criteria.
    var fourCharCode: UInt32 {
        unicodeScalars.reduce(UInt32(0)) { result, scalar in
            (result << 8) + scalar.value
        }
    }
}
