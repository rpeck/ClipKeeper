import CryptoKit
import Foundation
import NIOHTTP1

/// What the accept dialog shows. Everything here is either from the registry
/// (the device name) or counted by the Mac (count, bytes, types).
struct IncomingTransfer {
    var deviceName: String
    var address: String
    var count: Int
    var bytes: Int64
    var types: [String]
}

/// The receive side of the protocol: PIN checks, the single pending dialog,
/// sessions, single-use tokens, staging, and the hand-off to the clip store.
/// Called from SwiftNIO threads; all state sits behind one lock.
final class ReceiveCoordinator: TransferRequestHandling {
    /// Asks the user. Called on the main thread. The answer must come once.
    var askUser: (IncomingTransfer, @escaping (Bool) -> Void) -> Void = { _, answer in answer(false) }
    /// Stores one received text. Called on the main thread. Returns true when a clip was made.
    var deliverText: (String, String) -> Bool = { _, _ in false }
    /// The PIN budget is spent: the feature stops until the user restarts it.
    var onHardStop: () -> Void = {}
    /// A transfer finished, for the status line.
    var onReceived: (String, Int) -> Void = { _, _ in }

    private let registry: DeviceRegistry
    private let budget: PINBudget
    private let stagingDir: URL
    private let identityInfo: () -> LocalSend.DeviceInfo
    private let interfaces: () -> [NetworkInterface]
    private let noteDevice: (LocalSend.DeviceInfo, String) -> Void
    private let lock = NSLock()
    private var session: Session?
    private var dialogOpen = false
    private var paused = false
    /// Set once by `shutdown()`. Nothing is asked, accepted, or stored after it.
    private var closed = false
    private var stagedBytes: Int64 = 0

    private struct FileSlot {
        var meta: LocalSend.FileMeta
        var token: String
        var consumed = false
        var delivered = false
    }

    private struct Session {
        var id: String
        var credential: TransferCredential
        var deviceName: String
        var address: String
        var files: [String: FileSlot]
        var lastActivity: UInt64
        var bytes: Int64 = 0
        var delivered = 0
    }

    init(registry: DeviceRegistry, budget: PINBudget, stagingDir: URL,
         paused: Bool = false,
         identityInfo: @escaping () -> LocalSend.DeviceInfo,
         interfaces: @escaping () -> [NetworkInterface],
         noteDevice: @escaping (LocalSend.DeviceInfo, String) -> Void) {
        self.paused = paused
        self.registry = registry
        self.budget = budget
        self.stagingDir = stagingDir
        self.identityInfo = identityInfo
        self.interfaces = interfaces
        self.noteDevice = noteDevice
    }

    // MARK: Staging

    /// Creates the private staging folder and wipes anything left from a previous run.
    static func prepareStaging(at dir: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // MARK: State

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return paused || closed
    }

    /// Ends this coordinator for good, before its sockets close: the open
    /// session ends, a pending dialog answers "refuse", and queued work that
    /// arrives later finds `closed` and stores nothing.
    func shutdown() {
        lock.lock()
        closed = true
        let ended = session
        session = nil
        lock.unlock()
        if let ended { log(ended, outcome: "ended: transfer turned off") }
    }

    /// Ends the open session of a device whose PIN changed or that was removed.
    func revoke(deviceID: String) {
        lock.lock()
        var ended: Session?
        if let s = session, s.credential.deviceID == deviceID {
            ended = s
            session = nil
        }
        lock.unlock()
        if let ended { log(ended, outcome: "ended: PIN revoked") }
    }

    /// True while a session may continue: open, not paused, not expired, and
    /// its PIN still current. Call with the lock held.
    private func sessionValidLocked(_ id: String) -> Bool {
        expireLocked()
        guard !closed, !paused, let s = session, s.id == id else { return false }
        return registry.isCurrent(s.credential)
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        let ended = value ? session : nil
        if value { session = nil }
        lock.unlock()
        if let ended { log(ended, outcome: "ended: screen locked") }
    }

    func allowedInterfaces() -> [NetworkInterface] { interfaces() }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// Drops a session that has been idle for five minutes.
    private func expireLocked() {
        guard let s = session else { return }
        let idle = Double(Self.now() &- s.lastActivity) / 1e9
        if idle > LocalSend.Limits.tokenIdleSeconds { session = nil }
    }

    // MARK: register and info

    func deviceInfo(for registration: LocalSend.DeviceInfo?, from address: String) -> TransferResponse {
        if let registration { noteDevice(registration, address) }
        var info = identityInfo()
        info.port = nil
        info.scheme = nil
        info.announce = nil
        return .json(info)
    }

    // MARK: prepare-upload

    func checkPIN(query: [String: String], from address: String) -> RouteResult<TransferCredential> {
        switch budget.check(address) {
        case .stopped: return .failure(.tooManyRequests)
        case .locked: return .failure(.tooManyRequests)
        case .allowed: break
        }
        // No PIN yet: the phone asks its user for one. This is not a failure.
        guard let pin = query["pin"], !pin.isEmpty else { return .failure(.unauthorized) }
        guard pin.utf8.count <= 64, let match = registry.deviceMatching(pin: pin) else {
            if budget.recordFailure(address) {
                DispatchQueue.main.async { [weak self] in self?.onHardStop() }
            }
            return .failure(.unauthorized)
        }
        return .success(match.credential)
    }

    func prepareUpload(body: Data, credential: TransferCredential, from address: String, completion: @escaping (TransferResponse) -> Void) {
        let files: [LocalSend.FileMeta]
        do {
            let request = try LocalSend.decode(LocalSend.PrepareUploadRequest.self, from: body, maxBytes: LocalSend.Limits.prepareBodyBytes, maxDepth: LocalSend.Limits.prepareDepth)
            // The sender had a valid PIN, so its address is worth listing. The
            // list grants nothing: a send still needs the fingerprint comparison.
            noteDevice(request.info, address)
            files = try LocalSend.validate(request)
        } catch LocalSend.ValidationError.badType {
            return completion(.status(.forbidden))
        } catch {
            return completion(.status(.badRequest))
        }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        guard Self.freeSpace(at: stagingDir) >= LocalSend.Limits.freeSpaceFloor + total else {
            return completion(.status(.insufficientStorage))
        }
        guard registry.isCurrent(credential), let name = registry.name(of: credential.deviceID) else { return completion(.status(.unauthorized)) }

        lock.lock()
        expireLocked()
        if closed || paused || dialogOpen || session != nil {
            lock.unlock()
            return completion(.status(.conflict))
        }
        dialogOpen = true
        lock.unlock()

        let incoming = IncomingTransfer(deviceName: name, address: address, count: files.count, bytes: total, types: Array(Set(files.map(\.fileType))).sorted())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return completion(.status(.internalServerError)) }
            // Shut down, locked, or revoked while this waited for the main thread: no dialog.
            self.lock.lock()
            let stillAllowed = !self.closed && !self.paused && self.registry.isCurrent(credential)
            if !stillAllowed { self.dialogOpen = false }
            self.lock.unlock()
            guard stillAllowed else { return completion(.status(.forbidden)) }
            var answered = false
            self.askUser(incoming) { accepted in
                guard !answered else { return }
                answered = true
                completion(self.finishPrepare(accepted: accepted, files: files, credential: credential, deviceName: name, address: address))
            }
        }
    }

    private func finishPrepare(accepted: Bool, files: [LocalSend.FileMeta], credential: TransferCredential, deviceName: String, address: String) -> TransferResponse {
        lock.lock()
        dialogOpen = false
        guard accepted, !paused, !closed, registry.isCurrent(credential) else {
            lock.unlock()
            registry.log(TransferLogEntry(direction: "in", device: deviceName, address: address, count: files.count, bytes: 0, outcome: "refused"))
            return .status(.forbidden)
        }
        var slots: [String: FileSlot] = [:]
        var tokens: [String: String] = [:]
        for f in files {
            let token = Self.randomToken()
            slots[f.id] = FileSlot(meta: f, token: token)
            tokens[f.id] = token
        }
        let s = Session(id: Self.randomToken(), credential: credential, deviceName: deviceName, address: address, files: slots, lastActivity: Self.now())
        session = s
        lock.unlock()
        registry.touch(credential.deviceID)
        return .json(LocalSend.PrepareUploadResponse(sessionId: s.id, files: tokens))
    }

    // MARK: upload

    func openUpload(query: [String: String], from address: String, contentLength: Int64?) -> RouteResult<StagedUpload> {
        guard let sessionID = query["sessionId"], let fileID = query["fileId"], let token = query["token"] else { return .failure(.badRequest) }
        lock.lock()
        defer { lock.unlock() }
        guard let current = session, LocalSend.constantTimeEquals(current.id, sessionID), sessionValidLocked(current.id),
              var s = session, s.address == address else { return .failure(.forbidden) }
        guard var slot = s.files[fileID], LocalSend.constantTimeEquals(slot.token, token), !slot.consumed else { return .failure(.forbidden) }
        // The token is spent now, whatever happens next.
        slot.consumed = true
        s.files[fileID] = slot
        s.lastActivity = Self.now()
        session = s
        // The size from prepare-upload rules. A Content-Length must equal it; a
        // chunked body must end at exactly that size, checked as bytes arrive.
        if let contentLength, contentLength != slot.meta.size { return .failure(.badRequest) }
        let expected = slot.meta.size
        guard stagedBytes + expected <= LocalSend.Limits.stagingQuota else { return .failure(.insufficientStorage) }
        guard let (url, handle) = Self.createStagingFile(in: stagingDir) else { return .failure(.internalServerError) }
        stagedBytes += expected
        return .success(StagedUpload(sessionID: s.id, fileID: fileID, url: url, expectedBytes: expected, handle: handle))
    }

    func finishUpload(_ upload: StagedUpload, completion: @escaping (HTTPResponseStatus) -> Void) {
        try? upload.handle.close()
        let data = try? Data(contentsOf: upload.url)
        discard(upload)
        guard upload.written == upload.expectedBytes else { return completion(.badRequest) }
        lock.lock()
        guard let s = session, s.id == upload.sessionID, let slot = s.files[upload.fileID] else {
            lock.unlock()
            return completion(.forbidden)
        }
        lock.unlock()
        let digest = upload.hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let declared = slot.meta.sha256, !LocalSend.constantTimeEquals(declared.lowercased(), digest) {
            return completion(.unprocessableEntity)
        }
        guard let data, Int64(data.count) == upload.expectedBytes else { return completion(.internalServerError) }
        guard let text = TextSanitizer.sanitize(data) else { return completion(.badRequest) }

        // The clip store lives on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return completion(.internalServerError) }
            // The final check and the store happen under one lock, so a cancel,
            // a revocation, a screen lock, an expiry, or a shutdown on another
            // thread either comes first and stops the store, or comes after it.
            self.lock.lock()
            guard self.sessionValidLocked(upload.sessionID) else {
                self.lock.unlock()
                return completion(.forbidden)
            }
            let stored = self.deliverText(text, s.deviceName)
            guard stored else {
                self.lock.unlock()
                return completion(.internalServerError)
            }
            var finished: Session?
            if var cur = self.session, cur.id == upload.sessionID {
                cur.files[upload.fileID]?.delivered = true
                cur.delivered += 1
                cur.bytes += upload.expectedBytes
                cur.lastActivity = Self.now()
                if cur.files.values.allSatisfy(\.consumed) {
                    finished = cur
                    self.session = nil
                } else {
                    self.session = cur
                }
            }
            self.lock.unlock()
            if let finished {
                self.log(finished, outcome: "received")
                self.onReceived(finished.deviceName, finished.delivered)
            }
            completion(.ok)
        }
    }

    func abortUpload(_ upload: StagedUpload) {
        try? upload.handle.close()
        discard(upload)
    }

    private func discard(_ upload: StagedUpload) {
        try? FileManager.default.removeItem(at: upload.url)
        lock.lock()
        stagedBytes = max(0, stagedBytes - upload.expectedBytes)
        lock.unlock()
    }

    // MARK: cancel

    func cancel(query: [String: String], from address: String) -> HTTPResponseStatus {
        guard let sessionID = query["sessionId"] else { return .badRequest }
        lock.lock()
        guard let s = session, LocalSend.constantTimeEquals(s.id, sessionID), s.address == address else {
            lock.unlock()
            return .forbidden
        }
        session = nil
        lock.unlock()
        log(s, outcome: "cancelled by sender")
        return .ok
    }

    private func log(_ s: Session, outcome: String) {
        registry.log(TransferLogEntry(direction: "in", device: s.deviceName, address: s.address, count: s.delivered, bytes: s.bytes, outcome: outcome))
    }

    // MARK: Helpers

    /// 128 random bits as 32 hex characters.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "the system random generator failed")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A new file under a random name: O_CREAT|O_EXCL|O_NOFOLLOW, mode 600.
    static func createStagingFile(in dir: URL) -> (URL, FileHandle)? {
        let url = dir.appendingPathComponent(randomToken())
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        return (url, FileHandle(fileDescriptor: fd, closeOnDealloc: true))
    }

    static func freeSpace(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

/// Text from the network: valid UTF-8, no NUL, and no control characters
/// except tab and newline. Bidirectional controls are removed, so received
/// text cannot reorder what the user sees.
enum TextSanitizer {
    static func sanitize(_ data: Data) -> String? {
        guard !data.contains(0), let raw = String(data: data, encoding: .utf8) else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            let v = scalar.value
            if v == 0x09 || v == 0x0A { out.append(scalar); continue }
            if v < 0x20 || (v >= 0x7F && v <= 0x9F) { continue }
            if isBidiControl(v) { continue }
            // Line and paragraph separators become newlines.
            if v == 0x2028 || v == 0x2029 { out.append("\n"); continue }
            // Zero-width space, byte order mark, and interlinear annotation marks.
            if v == 0x200B || v == 0xFEFF || (0xFFF9...0xFFFB).contains(v) { continue }
            out.append(scalar)
        }
        let text = String(out)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func isBidiControl(_ v: UInt32) -> Bool {
        (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) || v == 0x200E || v == 0x200F || v == 0x061C
    }
}
