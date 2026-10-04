import Foundation

/// Every keyboard action inside the shelf. Each action has one or more
/// default combos. The user can change them in Settings.
enum KeyAction: String, Codable, CaseIterable, Identifiable {
    case moveUp, moveDown
    case previousSet, nextSet
    case paste, pastePlain, copyOnly, pasteAs
    case edit, saveAs, pin, moveToCollection, duplicate
    case delete
    case toggleSelectMode, selectAll, extendSelectionUp, extendSelectionDown
    case togglePreview
    case close
    case openSettings
    case openLink
    case importFiles, importContents
    case keepShelfOpen
    case newCollection, renameCollection, deleteCollection
    case slot1, slot2, slot3, slot4, slot5, slot6, slot7, slot8, slot9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveUp: return "Move selection up"
        case .moveDown: return "Move selection down"
        case .previousSet: return "Previous set"
        case .nextSet: return "Next set"
        case .paste: return "Paste"
        case .pastePlain: return "Paste as plain text"
        case .copyOnly: return "Copy to clipboard only"
        case .pasteAs: return "Paste as…"
        case .edit: return "Edit or crop"
        case .saveAs: return "Save as…"
        case .pin: return "Pin or unpin"
        case .moveToCollection: return "Move to collection…"
        case .duplicate: return "Duplicate"
        case .delete: return "Delete"
        case .toggleSelectMode: return "Check or uncheck the selected clip"
        case .selectAll: return "Check all, or uncheck all"
        case .extendSelectionUp: return "Check and move up"
        case .extendSelectionDown: return "Check and move down"
        case .togglePreview: return "Toggle full preview"
        case .close: return "Close shelf"
        case .openSettings: return "Open Settings"
        case .openLink: return "Open link or reveal file"
        case .importFiles: return "Import files…"
        case .importContents: return "Import the contents of the files in this clip"
        case .keepShelfOpen: return "Keep the shelf open (pin)"
        case .newCollection: return "New collection…"
        case .renameCollection: return "Rename collection…"
        case .deleteCollection: return "Delete collection…"
        case .slot1: return "Paste slot 1"
        case .slot2: return "Paste slot 2"
        case .slot3: return "Paste slot 3"
        case .slot4: return "Paste slot 4"
        case .slot5: return "Paste slot 5"
        case .slot6: return "Paste slot 6"
        case .slot7: return "Paste slot 7"
        case .slot8: return "Paste slot 8"
        case .slot9: return "Paste slot 9"
        }
    }

    var group: String {
        switch self {
        case .moveUp, .moveDown, .previousSet, .nextSet, .togglePreview, .close, .openSettings, .keepShelfOpen: return "Navigation"
        case .paste, .pastePlain, .copyOnly, .pasteAs: return "Paste"
        case .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9: return "Slots"
        case .edit, .saveAs, .pin, .moveToCollection, .duplicate, .delete, .openLink, .importFiles, .importContents: return "Clip"
        case .toggleSelectMode, .selectAll, .extendSelectionUp, .extendSelectionDown: return "Selection"
        case .newCollection, .renameCollection, .deleteCollection: return "Collections"
        }
    }

    var slotNumber: Int? {
        switch self {
        case .slot1: return 1
        case .slot2: return 2
        case .slot3: return 3
        case .slot4: return 4
        case .slot5: return 5
        case .slot6: return 6
        case .slot7: return 7
        case .slot8: return 8
        case .slot9: return 9
        default: return nil
        }
    }

    static func slot(_ n: Int) -> KeyAction? {
        allCases.first { $0.slotNumber == n }
    }

    var defaultCombos: [KeyCombo] {
        switch self {
        case .moveUp: return [KeyCombo("up"), KeyCombo("p", [.control]), KeyCombo("k", [.control])]
        case .moveDown: return [KeyCombo("down"), KeyCombo("n", [.control]), KeyCombo("j", [.control])]
        case .previousSet: return [KeyCombo("left"), KeyCombo("b", [.control]), KeyCombo("tab", [.shift])]
        case .nextSet: return [KeyCombo("right"), KeyCombo("f", [.control]), KeyCombo("tab")]
        case .paste: return [KeyCombo("return")]
        case .pastePlain: return [KeyCombo("return", [.shift])]
        case .copyOnly: return [KeyCombo("return", [.option])]
        case .pasteAs: return [KeyCombo("return", [.command, .shift])]
        case .edit: return [KeyCombo("e", [.command])]
        case .saveAs: return [KeyCombo("s", [.command])]
        case .pin: return [KeyCombo("p", [.command])]
        case .moveToCollection: return [KeyCombo("m", [.command])]
        case .duplicate: return [KeyCombo("d", [.command])]
        case .delete: return [KeyCombo("delete", [.command]), KeyCombo("delete")]
        case .toggleSelectMode: return [KeyCombo("a", [.command, .shift])]
        case .selectAll: return [KeyCombo("a", [.command])]
        case .extendSelectionUp: return [KeyCombo("up", [.shift])]
        case .extendSelectionDown: return [KeyCombo("down", [.shift])]
        case .togglePreview: return [KeyCombo("space"), KeyCombo("y", [.command])]
        case .close: return [KeyCombo("escape")]
        case .openSettings: return [KeyCombo(",", [.command])]
        case .openLink: return [KeyCombo("o", [.command])]
        case .importFiles: return [KeyCombo("i", [.command])]
        case .importContents: return [KeyCombo("i", [.command, .shift])]
        case .keepShelfOpen: return [KeyCombo("p", [.command, .shift])]
        case .newCollection: return [KeyCombo("n", [.command])]
        case .renameCollection: return [KeyCombo("r", [.command])]
        case .deleteCollection: return []
        case .slot1: return [KeyCombo("1", [.command])]
        case .slot2: return [KeyCombo("2", [.command])]
        case .slot3: return [KeyCombo("3", [.command])]
        case .slot4: return [KeyCombo("4", [.command])]
        case .slot5: return [KeyCombo("5", [.command])]
        case .slot6: return [KeyCombo("6", [.command])]
        case .slot7: return [KeyCombo("7", [.command])]
        case .slot8: return [KeyCombo("8", [.command])]
        case .slot9: return [KeyCombo("9", [.command])]
        }
    }

    /// Actions whose unmodified combos must yield to the search field when it
    /// holds text. Left and Right move the caret; Delete edits the query;
    /// Space types a space.
    var yieldsToSearchText: Bool {
        switch self {
        case .previousSet, .nextSet, .delete, .togglePreview: return true
        default: return false
        }
    }
}
