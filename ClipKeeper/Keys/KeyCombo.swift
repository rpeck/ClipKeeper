import AppKit
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
            if first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol {
                key = String(first).lowercased()
            } else {
                return nil
            }
        } else {
            return nil
        }
        modifiers = mods
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
