import AppKit
import Carbon
import Foundation

enum SniprHotKeyAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case openApp
    case captureArea
    case screenRecord
    case commandPalette
    case hideStack
    case showStack
    case clearStack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openApp:
            "Open Snipr"
        case .captureArea:
            "Screenshot"
        case .screenRecord:
            "Screen Record"
        case .commandPalette:
            "Palette"
        case .hideStack:
            "Hide Stack"
        case .showStack:
            "Show Stack"
        case .clearStack:
            "Clear Stack"
        }
    }

    var subtitle: String {
        switch self {
        case .openApp:
            "Bring the Snipr window forward"
        case .captureArea:
            "Capture a selected screen region"
        case .screenRecord:
            "Reserved for the recording workflow"
        case .commandPalette:
            "Open commands and capture actions"
        case .hideStack:
            "Dismiss the floating capture stack"
        case .showStack:
            "Show recent captures as a floating stack"
        case .clearStack:
            "Remove local capture history"
        }
    }

    var systemImage: String {
        switch self {
        case .openApp:
            "macwindow"
        case .captureArea:
            "selection.pin.in.out"
        case .screenRecord:
            "record.circle"
        case .commandPalette:
            "command"
        case .hideStack:
            "eye.slash"
        case .showStack:
            "photo.stack"
        case .clearStack:
            "trash"
        }
    }

    var isAvailable: Bool {
        self != .screenRecord
    }
}

struct HotKeyBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var isEnabled: Bool

    var displayText: String {
        guard isEnabled else {
            return "Off"
        }

        let modifierText = HotKeyFormatter.modifierText(modifiers)
        let keyText = HotKeyFormatter.keyText(keyCode: keyCode)
        return modifierText.isEmpty ? keyText : modifierText + keyText
    }
}

enum HotKeyDefaults {
    static let bindings: [SniprHotKeyAction: HotKeyBinding] = [
        .openApp: .init(keyCode: UInt32(kVK_ANSI_S), modifiers: hotKeyModifiers(command: true, option: true), isEnabled: true),
        .captureArea: .init(keyCode: UInt32(kVK_ANSI_4), modifiers: hotKeyModifiers(command: true, shift: true), isEnabled: true),
        .screenRecord: .init(keyCode: UInt32(kVK_ANSI_5), modifiers: hotKeyModifiers(command: true, shift: true), isEnabled: false),
        .commandPalette: .init(keyCode: UInt32(kVK_Space), modifiers: hotKeyModifiers(command: true, shift: true), isEnabled: true),
        .hideStack: .init(keyCode: UInt32(kVK_Escape), modifiers: hotKeyModifiers(command: true, option: true), isEnabled: true),
        .showStack: .init(keyCode: UInt32(kVK_ANSI_S), modifiers: hotKeyModifiers(command: true, shift: true), isEnabled: true),
        .clearStack: .init(keyCode: UInt32(kVK_Delete), modifiers: hotKeyModifiers(command: true), isEnabled: true)
    ]
}

func hotKeyModifiers(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) -> UInt32 {
    var modifiers: UInt32 = 0
    if command { modifiers |= UInt32(cmdKey) }
    if shift { modifiers |= UInt32(shiftKey) }
    if option { modifiers |= UInt32(optionKey) }
    if control { modifiers |= UInt32(controlKey) }
    return modifiers
}

enum HotKeyFormatter {
    static func modifierText(_ modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    static func keyText(keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Fn Delete",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z"
    ]
}
