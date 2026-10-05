import Foundation
import SwiftUI

/// UserDefaults keys and typed accessors for every user setting.
enum PrefKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let pasteIntoApp = "pasteIntoApp"
    static let skipConcealed = "skipConcealed"
    static let fetchLinkTitles = "fetchLinkTitles"
    static let excludedBundleIDs = "excludedBundleIDs"
    static let historyLimitEnabled = "historyLimitEnabled"
    static let historyLimit = "historyLimit"
    static let ageLimitEnabled = "ageLimitEnabled"
    static let ageLimitDays = "ageLimitDays"
    static let imageLimitEnabled = "imageLimitEnabled"
    static let imageLimitMB = "imageLimitMB"
    static let shelfWidth = "shelfWidth"
    static let isPaused = "isPaused"
    static let keyBindings = "keyBindings"
    static let moveToTopOnPaste = "moveToTopOnPaste"
    static let confirmDelete = "confirmDelete"
    static let edgeTriggerEnabled = "edgeTriggerEnabled"
    static let edgeDwell = "edgeDwell"
    static let edgeAutoHide = "edgeAutoHide"
    static let searchNewestFirst = "searchNewestFirst"
    static let shelfPinned = "shelfPinned"
    static let transferEnabled = "transferEnabled"
    static let transferAlias = "transferAlias"
    static let transferInterfaces = "transferInterfaces"
    static let transferPort = "transferPort"
}

/// Typed access to preferences. Every value has a default.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            PrefKey.hasCompletedOnboarding: false,
            PrefKey.pasteIntoApp: true,
            PrefKey.skipConcealed: true,
            PrefKey.fetchLinkTitles: true,
            PrefKey.excludedBundleIDs: [String](),
            PrefKey.historyLimitEnabled: true,
            PrefKey.historyLimit: 1000,
            PrefKey.ageLimitEnabled: false,
            PrefKey.ageLimitDays: 90,
            PrefKey.imageLimitEnabled: true,
            PrefKey.imageLimitMB: 50,
            PrefKey.shelfWidth: 440.0,
            PrefKey.isPaused: false,
            PrefKey.moveToTopOnPaste: false,
            PrefKey.confirmDelete: true,
            PrefKey.edgeTriggerEnabled: true,
            PrefKey.edgeDwell: 0.3,
            PrefKey.edgeAutoHide: true,
            PrefKey.searchNewestFirst: false,
            PrefKey.shelfPinned: false,
            PrefKey.transferEnabled: false,
            PrefKey.transferAlias: "ClipKeeper Mac",
            PrefKey.transferInterfaces: [String](),
            PrefKey.transferPort: 53_317,
        ])
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: PrefKey.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: PrefKey.hasCompletedOnboarding); objectWillChange.send() }
    }
    var pasteIntoApp: Bool {
        get { defaults.bool(forKey: PrefKey.pasteIntoApp) }
        set { defaults.set(newValue, forKey: PrefKey.pasteIntoApp); objectWillChange.send() }
    }
    var skipConcealed: Bool {
        get { defaults.bool(forKey: PrefKey.skipConcealed) }
        set { defaults.set(newValue, forKey: PrefKey.skipConcealed); objectWillChange.send() }
    }
    var fetchLinkTitles: Bool {
        get { defaults.bool(forKey: PrefKey.fetchLinkTitles) }
        set { defaults.set(newValue, forKey: PrefKey.fetchLinkTitles); objectWillChange.send() }
    }
    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: PrefKey.excludedBundleIDs) ?? [] }
        set { defaults.set(newValue, forKey: PrefKey.excludedBundleIDs); objectWillChange.send() }
    }
    var historyLimitEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.historyLimitEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.historyLimitEnabled); objectWillChange.send() }
    }
    var historyLimit: Int {
        get { max(1, defaults.integer(forKey: PrefKey.historyLimit)) }
        set { defaults.set(max(1, newValue), forKey: PrefKey.historyLimit); objectWillChange.send() }
    }
    var ageLimitEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.ageLimitEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.ageLimitEnabled); objectWillChange.send() }
    }
    var ageLimitDays: Int {
        get { max(1, defaults.integer(forKey: PrefKey.ageLimitDays)) }
        set { defaults.set(max(1, newValue), forKey: PrefKey.ageLimitDays); objectWillChange.send() }
    }
    var imageLimitEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.imageLimitEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.imageLimitEnabled); objectWillChange.send() }
    }
    var imageLimitMB: Int {
        get { max(1, defaults.integer(forKey: PrefKey.imageLimitMB)) }
        set { defaults.set(max(1, newValue), forKey: PrefKey.imageLimitMB); objectWillChange.send() }
    }
    var shelfWidth: Double {
        get { max(200, min(800, defaults.double(forKey: PrefKey.shelfWidth))) }
        set { defaults.set(newValue, forKey: PrefKey.shelfWidth); objectWillChange.send() }
    }
    var edgeTriggerEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.edgeTriggerEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.edgeTriggerEnabled); objectWillChange.send() }
    }
    /// Seconds the mouse must rest at the edge before the shelf opens.
    var edgeDwell: Double {
        get { max(0, min(2, defaults.double(forKey: PrefKey.edgeDwell))) }
        set { defaults.set(newValue, forKey: PrefKey.edgeDwell); objectWillChange.send() }
    }
    var edgeAutoHide: Bool {
        get { defaults.bool(forKey: PrefKey.edgeAutoHide) }
        set { defaults.set(newValue, forKey: PrefKey.edgeAutoHide); objectWillChange.send() }
    }
    /// Search results: newest first instead of best match first.
    var searchNewestFirst: Bool {
        get { defaults.bool(forKey: PrefKey.searchNewestFirst) }
        set { defaults.set(newValue, forKey: PrefKey.searchNewestFirst); objectWillChange.send() }
    }
    /// A pinned shelf stays open after a paste and when it loses focus, for drag and drop.
    var shelfPinned: Bool {
        get { defaults.bool(forKey: PrefKey.shelfPinned) }
        set { defaults.set(newValue, forKey: PrefKey.shelfPinned); objectWillChange.send() }
    }
    var isPaused: Bool {
        get { defaults.bool(forKey: PrefKey.isPaused) }
        set { defaults.set(newValue, forKey: PrefKey.isPaused); objectWillChange.send() }
    }
    var moveToTopOnPaste: Bool {
        get { defaults.bool(forKey: PrefKey.moveToTopOnPaste) }
        set { defaults.set(newValue, forKey: PrefKey.moveToTopOnPaste); objectWillChange.send() }
    }
    var confirmDelete: Bool {
        get { defaults.bool(forKey: PrefKey.confirmDelete) }
        set { defaults.set(newValue, forKey: PrefKey.confirmDelete); objectWillChange.send() }
    }

    // MARK: Phone transfer

    /// The LocalSend listener and discovery. Off by default.
    var transferEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.transferEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.transferEnabled); objectWillChange.send() }
    }
    /// The name phones see. Generic by default, so it says nothing about the user.
    var transferAlias: String {
        get { LocalSend.cleanAlias(defaults.string(forKey: PrefKey.transferAlias) ?? "") ?? "ClipKeeper Mac" }
        set { defaults.set(LocalSend.cleanAlias(newValue) ?? "ClipKeeper Mac", forKey: PrefKey.transferAlias); objectWillChange.send() }
    }
    /// BSD names of the allowed interfaces. Empty means every eligible Wi-Fi or Ethernet interface.
    var transferInterfaces: [String] {
        get { defaults.stringArray(forKey: PrefKey.transferInterfaces) ?? [] }
        set { defaults.set(newValue, forKey: PrefKey.transferInterfaces); objectWillChange.send() }
    }
    var transferPort: Int {
        get { LocalSend.cleanPort(defaults.integer(forKey: PrefKey.transferPort)) ?? LocalSend.defaultPort }
        set { defaults.set(LocalSend.cleanPort(newValue) ?? LocalSend.defaultPort, forKey: PrefKey.transferPort); objectWillChange.send() }
    }

    /// The image size limit in bytes, or nil when unlimited.
    var imageByteLimit: Int? {
        imageLimitEnabled ? imageLimitMB * 1_000_000 : nil
    }
}
