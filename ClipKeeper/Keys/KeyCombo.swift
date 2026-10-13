import AppKit
import Carbon
import Foundation

/// A key plus modifiers, independent of keyboard layout for the special keys.
struct KeyCombo: Codable, Hashable, CustomStringConvertible {
    enum Modifier: String, Codable, Hashable, CaseIterable {
        case control, option, shift, command

        var symbol: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    /// Either a special key name ("up", "return") or a single lowercase character.
    var key: String
    var modifiers: Set<Modifier>

    init(_ key: String, _ modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    static let specialKeyNames: [UInt16: String] = [
        126: "up", 125: "down", 123: "left", 124: "right",
        36: "return", 76: "enter", 53: "escape", 48: "tab",
        51: "delete", 117: "forwarddelete", 49: "space",
        115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    static let keySymbols: [String: String] = [
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "return": "⏎", "enter": "⌤", "escape": "esc", "tab": "⇥",
        "delete": "⌫", "forwarddelete": "⌦", "space": "␣",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    /// Builds a combo from a key event. Returns nil for modifier-only events.
    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        var mods: Set<Modifier> = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        if let special = KeyCombo.specialKeyNames[event.keyCode] {
            key = special
        } else if let chars = event.charactersIgnoringModifiers, let first = chars.first {
            guard first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else { return nil }
            if first.isASCII {
                key = String(first).lowercased()
            } else if let ascii = KeyCombo.asciiCharacter(forKeyCode: event.keyCode, shift: flags.contains(.shift)) {
                // A non-Latin layout, such as Russian, gives "в" for the D key.
                // AppKit matches its own shortcuts through the ASCII-capable
                // layout; so does ClipKeeper.
                key = ascii
            } else {
                key = String(first).lowercased()
            }
        } else {
            return nil
        }
        modifiers = mods
    }

    /// The character that a key code gives in the current ASCII-capable
    /// layout, such as U.S. or the Latin layout that the user chose.
    static func asciiCharacter(forKeyCode keyCode: UInt16, shift: Bool) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let modifiers: UInt32 = shift ? UInt32(shiftKey >> 8) : 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length).lowercased()
            return text.count == 1 && text.first?.isASCII == true ? text : nil
        }
    }

    var description: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        let mods = order.filter { modifiers.contains($0) }.map(\.symbol).joined()
        let k = KeyCombo.keySymbols[key] ?? key.uppercased()
        return mods + k
    }

    var isEnter: Bool { key == "return" || key == "enter" }

    /// Keys that edit or move the caret in a text field: unmodified arrows,
    /// Delete, Space, Home, End, and the Emacs control keys.
    var isTextEditingKey: Bool {
        if modifiers.isEmpty {
            return ["left", "right", "delete", "forwarddelete", "space", "home", "end"].contains(key)
        }
        if modifiers == [.control] {
            return ["b", "f", "d", "h", "a", "e", "k", "t"].contains(key)
        }
        if modifiers == [.option] || modifiers == [.command] {
            return ["left", "right"].contains(key)
        }
        return false
    }
}
