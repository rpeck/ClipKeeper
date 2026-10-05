import Foundation
import GRDB
import Security

/// A device the user paired. The PIN is not part of the record: it lives in
/// the sealed vault under the device's uuid.
struct PairedDevice: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "device"

    enum Kind: String, Codable {
        case phone
    }

    var id: Int64?
    var uuid: String
    var name: String
    var kind: Kind
    /// The phone's fingerprint, recorded only after the user compared it on both screens.
    var verifiedFingerprint: String?
    var createdAt: Date
    var lastUsedAt: Date?

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// One line of the transfer log. Never content, never a PIN, never a token.
struct TransferLogEntry: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transferLog"
    var id: Int64?
    var time: Date
    var direction: String
    var device: String
    var address: String
    var count: Int
    var bytes: Int64
    var outcome: String

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(direction: String, device: String, address: String, count: Int, bytes: Int64, outcome: String) {
        self.id = nil
        self.time = Date()
        self.direction = direction
        self.device = device
        self.address = address
        self.count = count
        self.bytes = bytes
        self.outcome = outcome
    }
}

/// PINs: random, from an alphabet without look-alike characters, so a user
/// can type one on a phone keyboard. LocalSend asks for the PIN on every
/// transfer and does not store it, so the length is a balance: eight
/// characters from 32 symbols is 40 bits, and the server stops for good after
/// 30 wrong PINs, so a guess succeeds with a chance below 1 in 30 billion.
enum TransferPIN {
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
    static let length = 8

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: length * 2)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "the system random generator failed")
        var out = ""
        var i = 0
        // Rejection sampling: no modulo bias.
        let limit = UInt8(256 - (256 % alphabet.count))
        while out.count < length {
            if i >= bytes.count {
                _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                i = 0
            }
            let b = bytes[i]
            i += 1
            if b < limit { out.append(alphabet[Int(b) % alphabet.count]) }
        }
        return out
    }

    /// What the user typed, in the canonical form: lowercase, no spaces or dashes.
    static func normalize(_ raw: String) -> String {
        String(raw.lowercased().filter { $0 != " " && $0 != "-" })
    }

    /// "abcd efgh", for display.
    static func display(_ pin: String) -> String {
        guard pin.count == length else { return pin }
        return String(pin.prefix(4)) + " " + String(pin.suffix(4))
    }
}

/// The PIN budget. Three failures per address, ten per minute in total, and
/// 30 in total until the user restarts the feature.
final class PINBudget {
    enum Verdict: Equatable { case allowed, locked, stopped }

    private let lock = NSLock()
    private var perAddress: [String: Int] = [:]
    private var recent: [Date] = []
    private(set) var total = 0
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func check(_ address: String) -> Verdict {
        lock.lock(); defer { lock.unlock() }
        if total >= LocalSend.Limits.pinFailuresTotal { return .stopped }
        let t = now()
        recent = recent.filter { t.timeIntervalSince($0) < 60 }
        if recent.count >= LocalSend.Limits.pinFailuresPerMinute { return .locked }
        if (perAddress[address] ?? 0) >= LocalSend.Limits.pinFailuresPerAddress { return .locked }
        return .allowed
    }

    /// Records one wrong PIN. Returns true when the hard stop is reached.
    func recordFailure(_ address: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        total += 1
        recent.append(now())
        perAddress[address, default: 0] += 1
        if perAddress.count > 1_024 { perAddress.removeAll() }
        return total >= LocalSend.Limits.pinFailuresTotal
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        perAddress = [:]
        recent = []
        total = 0
    }
}

/// Proof that a request carried a device's PIN: the device, and the PIN
/// generation that matched. A new PIN or a removal makes the generation stale,
/// which revokes every authority that the old PIN gave.
struct TransferCredential: Equatable {
    var deviceID: String
    var generation: Int
}

/// The paired devices, with their PINs held in memory for constant-time
/// comparison on the server threads. The sealed vault is the only storage of a PIN.
final class DeviceRegistry {
    private let database: Database
    private let vault: TransferVault?
    private let lock = NSLock()
    private var pins: [String: String] = [:]
    private var names: [String: String] = [:]
    private var generations: [String: Int] = [:]
    private var nextGeneration = 1

    /// `vault` nil keeps PINs in memory only, for tests.
    init(database: Database, vault: TransferVault?) {
        self.database = database
        self.vault = vault
    }

    private static func pinAccount(_ uuid: String) -> String { "pin.\(uuid)" }

    /// Loads every device and its PIN. A device whose PIN is missing from the
    /// vault stays listed but cannot send until the user issues a new PIN.
    func load() throws {
        let devices = all()
        var loaded: [String: String] = [:]
        var loadedNames: [String: String] = [:]
        for d in devices {
            loadedNames[d.uuid] = d.name
            if let vault, let pin = try vault.secret(Self.pinAccount(d.uuid)) {
                loaded[d.uuid] = pin
            }
        }
        lock.lock()
        pins = vault == nil ? pins : loaded
        names = loadedNames
        for uuid in pins.keys where generations[uuid] == nil {
            generations[uuid] = nextGeneration
            nextGeneration += 1
        }
        lock.unlock()
    }

    func all() -> [PairedDevice] {
        (try? database.queue.read { db in try PairedDevice.order(Column("createdAt")).fetchAll(db) }) ?? []
    }

    func device(uuid: String) -> PairedDevice? {
        try? database.queue.read { db in try PairedDevice.filter(Column("uuid") == uuid).fetchOne(db) }
    }

    /// Adds a phone and issues its PIN. Returns the device and the PIN to show once.
    func addPhone(named name: String) throws -> (PairedDevice, String) {
        let clean = LocalSend.cleanAlias(name) ?? "Phone"
        var device = PairedDevice(id: nil, uuid: UUID().uuidString, name: clean, kind: .phone, verifiedFingerprint: nil, createdAt: Date(), lastUsedAt: nil)
        let pin = uniquePIN()
        try vault?.setSecret(pin, for: Self.pinAccount(device.uuid))
        try database.queue.write { db in try device.insert(db) }
        lock.lock()
        pins[device.uuid] = pin
        names[device.uuid] = clean
        generations[device.uuid] = nextGeneration
        nextGeneration += 1
        lock.unlock()
        return (device, pin)
    }

    /// Adds a device for sending only. It has no PIN, so it adds nothing
    /// that a stranger could guess. New PIN in Settings gives it one.
    func addSendOnlyPhone(named name: String) throws -> PairedDevice {
        let clean = LocalSend.cleanAlias(name) ?? "Phone"
        var device = PairedDevice(id: nil, uuid: UUID().uuidString, name: clean, kind: .phone, verifiedFingerprint: nil, createdAt: Date(), lastUsedAt: nil)
        try database.queue.write { db in try device.insert(db) }
        lock.lock()
        names[device.uuid] = clean
        lock.unlock()
        return device
    }

    /// Replaces a device's PIN. The old one stops working at once.
    func reissuePIN(for uuid: String) throws -> String {
        let pin = uniquePIN()
        try vault?.setSecret(pin, for: Self.pinAccount(uuid))
        lock.lock()
        pins[uuid] = pin
        generations[uuid] = nextGeneration
        nextGeneration += 1
        lock.unlock()
        return pin
    }

    func pin(for uuid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return pins[uuid]
    }

    func rename(_ uuid: String, to name: String) {
        guard let clean = LocalSend.cleanAlias(name) else { return }
        try? database.queue.write { db in
            try db.execute(sql: "UPDATE device SET name = ? WHERE uuid = ?", arguments: [clean, uuid])
        }
        lock.lock()
        names[uuid] = clean
        lock.unlock()
    }

    /// Removes a device and its PIN.
    func remove(_ uuid: String) {
        try? vault?.setSecret(nil, for: Self.pinAccount(uuid))
        try? database.queue.write { db in
            try db.execute(sql: "DELETE FROM device WHERE uuid = ?", arguments: [uuid])
        }
        lock.lock()
        pins[uuid] = nil
        names[uuid] = nil
        generations[uuid] = nil
        lock.unlock()
    }

    /// True while the PIN that made this credential is still the device's PIN.
    func isCurrent(_ credential: TransferCredential) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pins[credential.deviceID] != nil && generations[credential.deviceID] == credential.generation
    }

    func name(of uuid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return names[uuid]
    }

    /// Records the fingerprint after the user compared it on both screens.
    func setVerifiedFingerprint(_ fingerprint: String?, for uuid: String) {
        try? database.queue.write { db in
            try db.execute(sql: "UPDATE device SET verifiedFingerprint = ? WHERE uuid = ?", arguments: [fingerprint, uuid])
        }
    }

    func touch(_ uuid: String) {
        try? database.queue.write { db in
            try db.execute(sql: "UPDATE device SET lastUsedAt = ? WHERE uuid = ?", arguments: [Date(), uuid])
        }
    }

    /// The device whose PIN matches, compared in constant time against every
    /// PIN so the time taken says nothing about which one is close.
    func deviceMatching(pin raw: String) -> (uuid: String, name: String, credential: TransferCredential)? {
        let candidate = TransferPIN.normalize(raw)
        lock.lock()
        let snapshot = pins
        let nameMap = names
        let generationMap = generations
        lock.unlock()
        var match: String?
        for (uuid, pin) in snapshot where LocalSend.constantTimeEquals(candidate, pin) {
            match = uuid
        }
        guard let match, let generation = generationMap[match] else { return nil }
        return (match, nameMap[match] ?? "Phone", TransferCredential(deviceID: match, generation: generation))
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return pins.isEmpty
    }

    private func uniquePIN() -> String {
        lock.lock()
        let existing = Set(pins.values)
        lock.unlock()
        var pin = TransferPIN.generate()
        while existing.contains(pin) { pin = TransferPIN.generate() }
        return pin
    }

    // MARK: Log

    /// Adds an entry and keeps the last 500.
    func log(_ entry: TransferLogEntry) {
        var entry = entry
        try? database.queue.write { db in
            try entry.insert(db)
            try db.execute(sql: "DELETE FROM transferLog WHERE id NOT IN (SELECT id FROM transferLog ORDER BY id DESC LIMIT 500)")
        }
    }

    func recentLog(limit: Int = 50) -> [TransferLogEntry] {
        (try? database.queue.read { db in
            try TransferLogEntry.order(Column("id").desc).limit(limit).fetchAll(db)
        }) ?? []
    }
}
