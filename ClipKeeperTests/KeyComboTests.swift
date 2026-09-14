import AppKit
import Testing
@testable import ClipKeeper

@Suite @MainActor struct KeyComboTests {
    private func event(keyCode: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode))
    }

    private func freshStore() throws -> KeyBindingStore {
        KeyBindingStore(defaults: try #require(UserDefaults(suiteName: "KeyComboTests-\(UUID().uuidString)")))
    }

    @Test func arrowKeys() throws {
        #expect(KeyCombo(event: try event(keyCode: 126, chars: "")) == KeyCombo("up"))
        #expect(KeyCombo(event: try event(keyCode: 125, chars: "")) == KeyCombo("down"))
    }

    @Test func controlLetter() throws {
        let combo = KeyCombo(event: try event(keyCode: 45, chars: "n", flags: [.control]))
        #expect(combo == KeyCombo("n", [.control]))
        #expect(combo?.description == "⌃N")
    }

    @Test func commandNumber() throws {
        #expect(KeyCombo(event: try event(keyCode: 18, chars: "1", flags: [.command])) == KeyCombo("1", [.command]))
    }

    @Test func description() {
        #expect(KeyCombo("return", [.command, .shift]).description == "⇧⌘⏎")
        #expect(KeyCombo("escape").description == "esc")
    }

    @Test func storeResolvesDefaults() throws {
        let store = try freshStore()
        #expect(store.resolve(event: try event(keyCode: 126, chars: ""), searchHasText: false) == .moveUp)
        #expect(store.resolve(event: try event(keyCode: 45, chars: "p", flags: [.control]), searchHasText: true) == .moveUp)
        // Left yields to the search field when it has text; Tab does not.
        #expect(store.resolve(event: try event(keyCode: 123, chars: ""), searchHasText: false) == .previousSet)
        #expect(store.resolve(event: try event(keyCode: 123, chars: ""), searchHasText: true) == nil)
        #expect(store.resolve(event: try event(keyCode: 48, chars: "\t"), searchHasText: true) == .nextSet)
        // Plain Delete yields to the search field; ⌘Delete does not.
        #expect(store.resolve(event: try event(keyCode: 51, chars: ""), searchHasText: true) == nil)
        #expect(store.resolve(event: try event(keyCode: 51, chars: "", flags: [.command]), searchHasText: true) == .delete)
    }

    @Test func rebindMovesComboBetweenActions() throws {
        let defaults = try #require(UserDefaults(suiteName: "KeyComboTests-\(UUID().uuidString)"))
        let store = KeyBindingStore(defaults: defaults)
        let combo = KeyCombo("j", [.control])
        store.add(combo, to: .moveDown)
        #expect(store.action(for: combo) == .moveDown)
        store.add(combo, to: .moveUp)
        #expect(store.action(for: combo) == .moveUp)
        #expect(!store.combos(for: .moveDown).contains(combo))
        let reloaded = KeyBindingStore(defaults: defaults)
        #expect(reloaded.action(for: combo) == .moveUp)
    }
}
