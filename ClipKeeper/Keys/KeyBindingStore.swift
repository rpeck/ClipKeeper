import AppKit
import Foundation

/// Holds the user's key bindings for shelf actions and resolves key events.
@MainActor
final class KeyBindingStore: ObservableObject {
    static let shared = KeyBindingStore()

    @Published private(set) var bindings: [KeyAction: [KeyCombo]]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [KeyAction: [KeyCombo]] = [:]
        if let data = defaults.data(forKey: PrefKey.keyBindings),
           let decoded = try? JSONDecoder().decode([String: [KeyCombo]].self, from: data) {
            for (raw, combos) in decoded {
                if let action = KeyAction(rawValue: raw) { loaded[action] = combos }
            }
        }
        for action in KeyAction.allCases where loaded[action] == nil {
            loaded[action] = action.defaultCombos
        }
        // Builds before 2026-10-05 saved Cmd-Shift-K for "send to a device";
        // Evernote claims it globally. Move an unchanged old default to the new one.
        if loaded[.sendToDevice] == [KeyCombo("k", [.command, .shift])] {
            loaded[.sendToDevice] = KeyAction.sendToDevice.defaultCombos
        }
        bindings = loaded
    }

    func combos(for action: KeyAction) -> [KeyCombo] {
        bindings[action] ?? []
    }

    /// The first combo, for display in hint bars and menus.
    func primaryCombo(for action: KeyAction) -> KeyCombo? {
        combos(for: action).first
    }

    func set(_ combos: [KeyCombo], for action: KeyAction) {
        bindings[action] = combos
        save()
    }

    func add(_ combo: KeyCombo, to action: KeyAction) {
        var list = combos(for: action)
        // A combo belongs to one action. Remove it from any other action.
        for other in KeyAction.allCases where other != action {
            if let idx = bindings[other]?.firstIndex(of: combo) {
                bindings[other]?.remove(at: idx)
            }
        }
        if !list.contains(combo) { list.append(combo) }
        bindings[action] = list
        save()
    }

    func remove(_ combo: KeyCombo, from action: KeyAction) {
        bindings[action]?.removeAll { $0 == combo }
        save()
    }

    func resetToDefaults(_ action: KeyAction) {
        bindings[action] = action.defaultCombos
        save()
    }

    func resetAll() {
        for action in KeyAction.allCases { bindings[action] = action.defaultCombos }
        save()
    }

    /// Which action, if any, a combo triggers.
    func action(for combo: KeyCombo) -> KeyAction? {
        for (action, combos) in bindings where combos.contains(combo) {
            return action
        }
        return nil
    }

    /// Returns the action for a key event, with the search-field policy applied.
    /// When the search field holds text, unmodified combos for caret-moving
    /// actions are given to the field instead.
    func resolve(event: NSEvent, searchHasText: Bool) -> KeyAction? {
        guard let combo = KeyCombo(event: event), let action = action(for: combo) else { return nil }
        if searchHasText, action.yieldsToSearchText, combo.isTextEditingKey {
            return nil
        }
        return action
    }

    private func save() {
        var dict: [String: [KeyCombo]] = [:]
        for (action, combos) in bindings { dict[action.rawValue] = combos }
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: PrefKey.keyBindings)
        }
    }
}
