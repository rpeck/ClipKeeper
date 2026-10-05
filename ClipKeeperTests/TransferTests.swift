import CryptoKit
import Foundation
import Testing
@testable import ClipKeeper

/// The protocol rules, one by one. Each test is an input a stranger on the
/// network could send.
@Suite struct TransferProtocolTests {
    @Test func depthCountsOnlyOutsideStrings() {
        #expect(StrictJSON.depth(of: Data(#"{"a":{"b":[1,2]}}"#.utf8)) == 3)
        #expect(StrictJSON.depth(of: Data(#"{"a":"{{{{[[[["}"#.utf8)) == 1)
        #expect(StrictJSON.depth(of: Data(#"{"a":"\"{"}"#.utf8)) == 1)
        #expect(StrictJSON.depth(of: Data("{{".utf8)) == Int.max)
        #expect(StrictJSON.depth(of: Data("}{".utf8)) == Int.max)
    }

    @Test func deepJSONIsRefusedBeforeDecoding() {
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(throws: LocalSend.ValidationError.tooDeep) {
            try LocalSend.decode([String].self, from: Data(deep.utf8), maxBytes: 100_000, maxDepth: 32)
        }
    }

    @Test func largeJSONIsRefused() {
        let big = Data(repeating: 0x20, count: 5_000)
        #expect(throws: LocalSend.ValidationError.tooLarge) {
            try LocalSend.decode(LocalSend.DeviceInfo.self, from: big, maxBytes: 4_096, maxDepth: 4)
        }
    }

    @Test func aliasLosesControlAndBidiCharacters() {
        #expect(LocalSend.cleanAlias("Pix\u{202E}el\u{0007}") == "Pixel")
        #expect(LocalSend.cleanAlias("\u{200B}\u{200F}") == nil)
        #expect(LocalSend.cleanAlias(String(repeating: "x", count: 100))?.count == 32)
        #expect(LocalSend.cleanAlias("ｆｕｌｌ") == "full")
    }

    @Test func fingerprintMustBe64Hex() {
        let good = String(repeating: "ab", count: 32)
        #expect(LocalSend.cleanFingerprint(good) == good.uppercased())
        #expect(LocalSend.cleanFingerprint(String(repeating: "g", count: 64)) == nil)
        #expect(LocalSend.cleanFingerprint("abcd") == nil)
        #expect(LocalSend.cleanFingerprint(String(repeating: "a", count: 65)) == nil)
    }

    @Test func portRange() {
        #expect(LocalSend.cleanPort(53317) == 53317)
        #expect(LocalSend.cleanPort(80) == nil)
        #expect(LocalSend.cleanPort(70_000) == nil)
        #expect(LocalSend.cleanPort(nil) == nil)
    }

    @Test func fileIDs() {
        #expect(LocalSend.isValidFileID("abc-DEF_123"))
        #expect(!LocalSend.isValidFileID(""))
        #expect(!LocalSend.isValidFileID("../etc"))
        #expect(!LocalSend.isValidFileID("a b"))
        #expect(!LocalSend.isValidFileID(String(repeating: "a", count: 129)))
    }

    private func request(_ files: [LocalSend.FileMeta]) -> LocalSend.PrepareUploadRequest {
        let info = LocalSend.DeviceInfo(alias: "Phone", version: "2.0", deviceModel: nil, deviceType: "mobile", fingerprint: String(repeating: "a", count: 64), port: 53317, scheme: "https", download: nil, announce: nil)
        return LocalSend.PrepareUploadRequest(info: info, files: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }))
    }

    private func file(_ id: String, _ size: Int64, _ type: String = "text/plain") -> LocalSend.FileMeta {
        LocalSend.FileMeta(id: id, fileName: "x.txt", size: size, fileType: type, sha256: nil, preview: nil)
    }

    @Test func validationAcceptsText() throws {
        let files = try LocalSend.validate(request([file("a", 10), file("b", 20, "text/markdown; charset=utf-8")]))
        #expect(files.count == 2)
        #expect(files[1].fileType == "text/markdown")
    }

    @Test func validationRefusesImagesAndDocumentsInPhaseA() {
        for type in ["image/png", "image/tiff", "application/rtf", "application/octet-stream", "text/html"] {
            #expect(throws: LocalSend.ValidationError.badType(type)) { try LocalSend.validate(request([file("a", 10, type)])) }
        }
    }

    @Test func validationRefusesBadSizesAndCounts() {
        #expect(throws: LocalSend.ValidationError.badSize) { try LocalSend.validate(request([file("a", -1)])) }
        #expect(throws: LocalSend.ValidationError.badSize) { try LocalSend.validate(request([file("a", 2_000_000)])) }
        #expect(throws: LocalSend.ValidationError.badSize) { try LocalSend.validate(request([file("a", Int64.max)])) }
        let many = (0..<51).map { file("f\($0)", 1) }
        #expect(throws: LocalSend.ValidationError.tooManyFiles) { try LocalSend.validate(request(many)) }
        #expect(throws: LocalSend.ValidationError.tooManyFiles) { try LocalSend.validate(request([])) }
    }

    @Test func validationRefusesMismatchedKeys() {
        var r = request([file("a", 1)])
        r.files = ["b": file("a", 1)]
        #expect(throws: LocalSend.ValidationError.badFileID) { try LocalSend.validate(r) }
    }

    @Test func routesMatchExactly() {
        #expect(LocalSend.Route.match("/api/localsend/v2/prepare-upload") == .prepareUpload)
        #expect(LocalSend.Route.match("/api/localsend/v2/prepare-upload/") == nil)
        #expect(LocalSend.Route.match("/API/localsend/v2/info") == nil)
        #expect(LocalSend.Route.match("/api/localsend/v2/../v2/info") == nil)
        #expect(LocalSend.Route.match("/api/localsend/v1/info") == nil)
    }

    @Test func queryParsingIsStrict() {
        #expect(TransferHTTPHandler.parseQuery("pin=abc%20d&x=1") == ["pin": "abc d", "x": "1"])
        #expect(TransferHTTPHandler.parseQuery("pin=1&pin=2") == nil)
        #expect(TransferHTTPHandler.parseQuery("pin=%zz") == nil)
        #expect(TransferHTTPHandler.parseQuery("=1") == nil)
        #expect(TransferHTTPHandler.parseQuery("novalue") == nil)
        #expect(TransferHTTPHandler.parseQuery(nil) == [:])
        #expect(TransferHTTPHandler.splitURI("/a?b=1#frag") == nil)
        #expect(TransferHTTPHandler.splitURI("http://evil/a") == nil)
        #expect(TransferHTTPHandler.splitURI("/a b") == nil)
    }

    @Test func constantTimeEquality() {
        #expect(LocalSend.constantTimeEquals("abc", "abc"))
        #expect(!LocalSend.constantTimeEquals("abc", "abd"))
        #expect(!LocalSend.constantTimeEquals("abc", "abcd"))
        #expect(!LocalSend.constantTimeEquals("", "a"))
    }

    @Test func combinedFingerprintMatchesLocalSend() {
        // LocalSend sorts both fingerprints and joins them.
        let a = String(repeating: "B", count: 64), b = String(repeating: "a", count: 64)
        #expect(TransferSender.combinedFingerprint(a, b) == String(repeating: "A", count: 64) + a)
        #expect(TransferSender.combinedFingerprint(b, a) == TransferSender.combinedFingerprint(a, b))
    }

    @Test func identityFingerprintIsSHA256OfDER() throws {
        let id = try TransferIdentity.ephemeral()
        #expect(id.fingerprint.count == 64)
        #expect(id.fingerprint == id.fingerprint.uppercased())
        #expect(id.fingerprint == LocalSend.fingerprint(ofCertificateDER: id.certificateDER))
    }

    @Test func aMaskChangeIsAnInterfaceChange() {
        let a = NetworkInterface(name: "en0", displayName: "Wi-Fi", ipv4: [(0xC0A8_0114, 0xFFFF_FF00)])
        let b = NetworkInterface(name: "en0", displayName: "Wi-Fi", ipv4: [(0xC0A8_0114, 0xFFFF_0000)])
        #expect(a != b)
        #expect(a == a)
    }

    @Test func linkCheck() {
        let lan = NetworkInterface(name: "en0", displayName: "Wi-Fi", ipv4: [(NetworkInterfaces.ipv4(from: "192.168.1.20") ?? 0, 0xFFFF_FF00)])
        #expect(NetworkInterfaces.isOnAllowedLink("192.168.1.77", interfaces: [lan]))
        #expect(!NetworkInterfaces.isOnAllowedLink("192.168.2.77", interfaces: [lan]))
        #expect(!NetworkInterfaces.isOnAllowedLink("10.0.0.1", interfaces: [lan]))
        #expect(!NetworkInterfaces.isOnAllowedLink("fe80::1", interfaces: [lan]))
        #expect(!NetworkInterfaces.isOnAllowedLink("not an address", interfaces: [lan]))
    }
}

@Suite struct TextSanitizerTests {
    @Test func refusesNULAndInvalidUTF8() {
        #expect(TextSanitizer.sanitize(Data([0x61, 0x00, 0x62])) == nil)
        #expect(TextSanitizer.sanitize(Data([0xC3, 0x28])) == nil)
        #expect(TextSanitizer.sanitize(Data("   \n".utf8)) == nil)
    }

    @Test func removesControlsAndBidi() {
        let raw = "a\u{0007}b\u{0085}c\u{202E}d\u{2066}e\r\nf\tg"
        #expect(TextSanitizer.sanitize(Data(raw.utf8)) == "abcde\nf\tg")
    }

    @Test func removesInvisibleCharacters() {
        let raw = "a\u{200B}b\u{FEFF}c\u{FFF9}d\u{2028}e\u{2029}f"
        #expect(TextSanitizer.sanitize(Data(raw.utf8)) == "abcd\ne\nf")
    }

    @Test func keepsOrdinaryText() {
        let raw = "https://example.com/path?q=1\nCafé — ✓ 日本"
        #expect(TextSanitizer.sanitize(Data(raw.utf8)) == raw)
    }
}

@Suite struct PINTests {
    @Test func generatedPINsUseTheAlphabet() {
        var seen = Set<String>()
        for _ in 0..<500 {
            let pin = TransferPIN.generate()
            #expect(pin.count == TransferPIN.length)
            #expect(pin.allSatisfy { TransferPIN.alphabet.contains($0) })
            seen.insert(pin)
        }
        #expect(seen.count == 500)
    }

    @Test func normalizeAcceptsSpacesDashesAndCase() {
        #expect(TransferPIN.normalize("ABCD efgh") == "abcdefgh")
        #expect(TransferPIN.normalize("abcd-efgh") == "abcdefgh")
    }

    @Test func budgetLocksAnAddressAfterThree() {
        let budget = PINBudget()
        for _ in 0..<3 {
            #expect(budget.check("1.1.1.1") == .allowed)
            _ = budget.recordFailure("1.1.1.1")
        }
        #expect(budget.check("1.1.1.1") == .locked)
        #expect(budget.check("1.1.1.2") == .allowed)
    }

    @Test func budgetLocksEveryoneAfterTenAMinute() {
        var clock = Date()
        let budget = PINBudget { clock }
        for i in 0..<10 { _ = budget.recordFailure("10.0.0.\(i)") }
        #expect(budget.check("10.0.0.99") == .locked)
        clock = clock.addingTimeInterval(61)
        #expect(budget.check("10.0.0.99") == .allowed)
    }

    @Test func budgetStopsForGoodAfterThirty() {
        var clock = Date()
        let budget = PINBudget { clock }
        var stopped = false
        for i in 0..<30 {
            clock = clock.addingTimeInterval(10)
            stopped = budget.recordFailure("10.0.\(i).1")
        }
        #expect(stopped)
        clock = clock.addingTimeInterval(3_600)
        #expect(budget.check("10.9.9.9") == .stopped)
        budget.reset()
        #expect(budget.check("10.9.9.9") == .allowed)
    }
}

@Suite @MainActor struct DeviceRegistryTests {
    @Test func pinsIdentifyPhonesAndReissueRevokes() throws {
        let registry = DeviceRegistry(database: try Database.inMemory(), vault: nil)
        let (pixel, pixelPIN) = try registry.addPhone(named: "Pixel")
        let (iphone, iphonePIN) = try registry.addPhone(named: "iPhone")
        #expect(pixelPIN != iphonePIN)
        #expect(registry.deviceMatching(pin: pixelPIN)?.uuid == pixel.uuid)
        #expect(registry.deviceMatching(pin: TransferPIN.display(iphonePIN).uppercased())?.uuid == iphone.uuid)
        #expect(registry.deviceMatching(pin: "wrongpin") == nil)
        let fresh = try registry.reissuePIN(for: pixel.uuid)
        #expect(registry.deviceMatching(pin: pixelPIN) == nil)
        #expect(registry.deviceMatching(pin: fresh)?.uuid == pixel.uuid)
        registry.remove(iphone.uuid)
        #expect(registry.deviceMatching(pin: iphonePIN) == nil)
        #expect(registry.all().map(\.name) == ["Pixel"])
    }

    @Test func sendOnlyDevicesHaveNoPIN() throws {
        let registry = DeviceRegistry(database: try Database.inMemory(), vault: nil)
        let device = try registry.addSendOnlyPhone(named: "Pixel")
        #expect(registry.pin(for: device.uuid) == nil)
        #expect(registry.isEmpty)
    }

    @Test func logKeepsNoContent() throws {
        let registry = DeviceRegistry(database: try Database.inMemory(), vault: nil)
        registry.log(TransferLogEntry(direction: "in", device: "Pixel", address: "192.168.1.5", count: 1, bytes: 12, outcome: "received"))
        let entry = try #require(registry.recentLog().first)
        #expect(entry.device == "Pixel")
        #expect(entry.bytes == 12)
    }
}

@Suite @MainActor struct NetworkIngestTests {
    let store: ClipStore
    let prefs: Preferences

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "NetworkIngestTests-\(UUID().uuidString)"))
        prefs = Preferences(defaults: defaults)
        store = ClipStore(database: try Database.inMemory(), blobs: .temporary(), prefs: prefs)
    }

    @Test func receivedTextIsMarked() throws {
        let clip = try #require(store.ingestNetworkText("hello from the phone", deviceName: "Pixel"))
        #expect(clip.isFromNetwork)
        #expect(clip.sourceAppName == "Pixel")
        #expect(clip.sourceBundleID == nil)
        #expect(store.snapshot(for: clip)?.allTypes == [PBType.string])
    }

    @Test func receivedCopyNeverReplacesALocalClip() throws {
        let local = try #require(store.ingest(.plainText("same text"), sourceBundleID: "com.example", sourceAppName: "Example"))
        let received = try #require(store.ingestNetworkText("same text", deviceName: "Pixel"))
        #expect(received.uuid != local.uuid)
        #expect(store.clip(uuid: local.uuid)?.sourceAppName == "Example")
        #expect(store.clip(uuid: local.uuid)?.isFromNetwork == false)
    }

    @Test func customSchemesStayText() throws {
        let clip = try #require(store.ingestNetworkText("vscode://open?file=/etc/passwd", deviceName: "Pixel"))
        #expect(clip.kind != .link)
        let web = try #require(store.ingestNetworkText("https://example.com/a", deviceName: "Pixel"))
        #expect(web.kind == .link)
        #expect(web.linkTitle == nil)
    }

    @Test func aFloodDoesNotEvictLocalHistory() throws {
        prefs.historyLimitEnabled = true
        prefs.historyLimit = 5
        for i in 0..<5 { store.ingest(.plainText("local \(i)"), sourceBundleID: nil, sourceAppName: nil) }
        for i in 0..<40 { store.ingestNetworkText("flood \(i)", deviceName: "Pixel") }
        let all = store.clips(in: .history, query: "")
        #expect(all.filter { !$0.isFromNetwork }.count == 5)
    }
}

/// The vault on this Mac's Secure Enclave. Skipped where there is none,
/// such as a virtual machine in CI.
@Suite(.enabled(if: SecureEnclave.isAvailable)) struct TransferVaultTests {
    private func vault() -> (TransferVault, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        return (TransferVault(directory: dir), dir)
    }

    @Test func theFingerprintIsStableAcrossLaunches() throws {
        let (first, dir) = vault()
        let a = try TransferIdentity.load(vault: first)
        let b = try TransferIdentity.load(vault: TransferVault(directory: dir))
        #expect(a.fingerprint == b.fingerprint)
        let mode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func secretsAreSealedOnDisk() throws {
        let (first, dir) = vault()
        try first.setSecret("k7mqx2ra", for: "pin.test")
        let raw = try Data(contentsOf: dir.appendingPathComponent("secrets.sealed"))
        #expect(raw.range(of: Data("k7mqx2ra".utf8)) == nil)
        #expect(try TransferVault(directory: dir).secret("pin.test") == "k7mqx2ra")
        try first.setSecret(nil, for: "pin.test")
        #expect(try TransferVault(directory: dir).secret("pin.test") == nil)
    }

    @Test func aTamperedFileStopsTheVault() throws {
        let (first, dir) = vault()
        try first.setSecret("k7mqx2ra", for: "pin.test")
        let url = dir.appendingPathComponent("secrets.sealed")
        var raw = try Data(contentsOf: url)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: url)
        #expect(throws: TransferVault.VaultError.self) { try TransferVault(directory: dir).secret("pin.test") }
    }
}

/// The whole path, over real TLS on the loopback address: the sender pins
/// the server's fingerprint, the server checks the PIN, asks, and stores.
@Suite(.serialized) @MainActor struct TransferEndToEndTests {
    static let loopback = NetworkInterface(name: "lo0", displayName: "Loopback for tests", ipv4: [(0x7F00_0001, 0xFF00_0000)])

    final class Harness {
        let identity: TransferIdentity
        let registry: DeviceRegistry
        let coordinator: ReceiveCoordinator
        let server: TransferServer
        let port: Int
        var received: [String] = []
        var asked = 0
        var accept = true

        @MainActor
        init() throws {
            identity = try TransferIdentity.ephemeral()
            registry = DeviceRegistry(database: try Database.inMemory(), vault: nil)
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("staging-\(UUID().uuidString)")
            try ReceiveCoordinator.prepareStaging(at: staging)
            let fp = identity.fingerprint
            coordinator = ReceiveCoordinator(registry: registry, budget: PINBudget(), stagingDir: staging,
                                             identityInfo: { TransferService.info(alias: "Test Mac", fingerprint: fp, port: 1_024) },
                                             interfaces: { [TransferEndToEndTests.loopback] },
                                             noteDevice: { _, _ in })
            server = TransferServer(handler: coordinator)
            var bound: Int?
            for _ in 0..<20 {
                let candidate = Int.random(in: 40_000...60_000)
                if (try? server.start(identity: identity, port: candidate, interfaces: [TransferEndToEndTests.loopback])) != nil {
                    bound = candidate
                    break
                }
            }
            port = try #require(bound)
            coordinator.askUser = { [unowned self] _, answer in
                self.asked += 1
                answer(self.accept)
            }
            coordinator.deliverText = { [unowned self] text, _ in
                self.received.append(text)
                return true
            }
        }

        func sender(fingerprint: String? = nil) -> TransferSender {
            TransferSender(address: "127.0.0.1", port: port, fingerprint: fingerprint ?? identity.fingerprint)
        }

        var phoneInfo: LocalSend.DeviceInfo {
            LocalSend.DeviceInfo(alias: "Phone", version: "2.0", deviceModel: "Pixel", deviceType: "mobile", fingerprint: String(repeating: "C", count: 64), port: 53317, scheme: "https", download: nil, announce: nil)
        }

        func text(_ s: String) -> OutgoingItem {
            OutgoingItem(fileName: "a.txt", fileType: "text/plain", data: Data(s.utf8), preview: s)
        }
    }

    @Test func pinnedProbeSucceedsAndWrongFingerprintFails() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let info = try await h.sender().probe()
        #expect(info.fingerprint == h.identity.fingerprint)
        await #expect(throws: SendError.fingerprintMismatch) {
            _ = try await h.sender(fingerprint: String(repeating: "0", count: 64)).probe()
        }
    }

    @Test func textArrivesWithTheRightPIN() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        let first = try await h.sender().send([h.text("x")], from: h.phoneInfo, pin: nil)
        #expect(first == .needsPIN)
        #expect(h.asked == 0)
        let outcome = try await h.sender().send([h.text("copied on the phone\u{202E}")], from: h.phoneInfo, pin: pin)
        #expect(outcome == .sent)
        #expect(h.asked == 1)
        #expect(h.received == ["copied on the phone"])
    }

    @Test func wrongPINNeverReachesTheDialog() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        _ = try h.registry.addPhone(named: "Pixel")
        await #expect(throws: SendError.wrongPIN) {
            _ = try await h.sender().send([h.text("x")], from: h.phoneInfo, pin: "aaaaaaaa")
        }
        #expect(h.asked == 0)
        #expect(h.received.isEmpty)
    }

    @Test func refusalStoresNothing() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        h.accept = false
        await #expect(throws: SendError.refused) {
            _ = try await h.sender().send([h.text("x")], from: h.phoneInfo, pin: pin)
        }
        #expect(h.received.isEmpty)
    }

    @Test func imagesAreRefusedInPhaseA() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        let png = OutgoingItem(fileName: "a.png", fileType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]), preview: nil)
        await #expect(throws: SendError.refused) {
            _ = try await h.sender().send([png], from: h.phoneInfo, pin: pin)
        }
        #expect(h.asked == 0)
    }

    @Test func tokensAreSingleUse() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        // Drive the protocol by hand to replay an upload.
        let delegate = PinnedTrustDelegate(expectedFingerprint: h.identity.fingerprint)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let body = Data("first".utf8)
        let meta = LocalSend.FileMeta(id: "f1", fileName: "a.txt", size: Int64(body.count), fileType: "text/plain", sha256: nil, preview: nil)
        var prepare = URLRequest(url: try #require(URL(string: "https://127.0.0.1:\(h.port)/api/localsend/v2/prepare-upload?pin=\(pin)")))
        prepare.httpMethod = "POST"
        prepare.httpBody = try JSONEncoder().encode(LocalSend.PrepareUploadRequest(info: h.phoneInfo, files: ["f1": meta]))
        let (data, response) = try await session.data(for: prepare)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let reply = try JSONDecoder().decode(LocalSend.PrepareUploadResponse.self, from: data)
        let token = try #require(reply.files["f1"])
        // A second prepare while a session is open: 409.
        let (_, busy) = try await session.data(for: prepare)
        #expect((busy as? HTTPURLResponse)?.statusCode == 409)
        // A wrong size is refused, and it spends the token.
        let url = try #require(URL(string: "https://127.0.0.1:\(h.port)/api/localsend/v2/upload?sessionId=\(reply.sessionId)&fileId=f1&token=\(token)"))
        var upload = URLRequest(url: url)
        upload.httpMethod = "POST"
        upload.httpBody = Data("first!".utf8)
        let (_, wrongSize) = try await session.data(for: upload)
        #expect((wrongSize as? HTTPURLResponse)?.statusCode == 400)
        upload.httpBody = body
        let (_, replay) = try await session.data(for: upload)
        #expect((replay as? HTTPURLResponse)?.statusCode == 403)
        #expect(h.received.isEmpty)
    }

    /// Opens a session by hand and returns what an upload needs.
    private func openSession(_ h: Harness, pin: String, text: String) async throws -> (URLSession, URLRequest) {
        let delegate = PinnedTrustDelegate(expectedFingerprint: h.identity.fingerprint)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let body = Data(text.utf8)
        let meta = LocalSend.FileMeta(id: "f1", fileName: "a.txt", size: Int64(body.count), fileType: "text/plain", sha256: nil, preview: nil)
        var prepare = URLRequest(url: try #require(URL(string: "https://127.0.0.1:\(h.port)/api/localsend/v2/prepare-upload?pin=\(pin)")))
        prepare.httpMethod = "POST"
        prepare.httpBody = try JSONEncoder().encode(LocalSend.PrepareUploadRequest(info: h.phoneInfo, files: ["f1": meta]))
        let (data, response) = try await session.data(for: prepare)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let reply = try JSONDecoder().decode(LocalSend.PrepareUploadResponse.self, from: data)
        let token = try #require(reply.files["f1"])
        var upload = URLRequest(url: try #require(URL(string: "https://127.0.0.1:\(h.port)/api/localsend/v2/upload?sessionId=\(reply.sessionId)&fileId=f1&token=\(token)")))
        upload.httpMethod = "POST"
        upload.httpBody = body
        return (session, upload)
    }

    @Test func aNewPINRevokesAnOpenSession() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (phone, pin) = try h.registry.addPhone(named: "Pixel")
        let (session, upload) = try await openSession(h, pin: pin, text: "after revocation")
        defer { session.invalidateAndCancel() }
        // Only the registry changes: the stale generation alone must stop the upload.
        _ = try h.registry.reissuePIN(for: phone.uuid)
        let (_, response) = try await session.data(for: upload)
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
        #expect(h.received.isEmpty)
    }

    @Test func removalRevokesAnOpenSession() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (phone, pin) = try h.registry.addPhone(named: "Pixel")
        let (session, upload) = try await openSession(h, pin: pin, text: "after removal")
        defer { session.invalidateAndCancel() }
        h.registry.remove(phone.uuid)
        h.coordinator.revoke(deviceID: phone.uuid)
        let (_, response) = try await session.data(for: upload)
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
        #expect(h.received.isEmpty)
    }

    @Test func shutdownStoresNothingMore() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        let (session, upload) = try await openSession(h, pin: pin, text: "after shutdown")
        defer { session.invalidateAndCancel() }
        h.coordinator.shutdown()
        let result = try? await session.data(for: upload)
        #expect((result?.1 as? HTTPURLResponse)?.statusCode != 200)
        #expect(h.received.isEmpty)
    }

    @Test func aPausedServerRefusesBeforeTheDialog() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let (_, pin) = try h.registry.addPhone(named: "Pixel")
        h.coordinator.setPaused(true)
        await #expect(throws: SendError.http(503)) {
            _ = try await h.sender().send([h.text("x")], from: h.phoneInfo, pin: pin)
        }
        #expect(h.asked == 0)
    }

    @Test func unknownPathsAndMethodsAreRefused() async throws {
        let h = try Harness()
        defer { h.server.stop() }
        let delegate = PinnedTrustDelegate(expectedFingerprint: h.identity.fingerprint)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let base = "https://127.0.0.1:\(h.port)/api/localsend/v2/"
        let (_, notFound) = try await session.data(from: try #require(URL(string: base + "download")))
        #expect((notFound as? HTTPURLResponse)?.statusCode == 404)
        let (_, wrongMethod) = try await session.data(from: try #require(URL(string: base + "upload")))
        #expect((wrongMethod as? HTTPURLResponse)?.statusCode == 405)
        var big = URLRequest(url: try #require(URL(string: base + "register")))
        big.httpMethod = "POST"
        big.httpBody = Data(repeating: 0x20, count: 10_000)
        let (_, tooLarge) = try await session.data(for: big)
        #expect((tooLarge as? HTTPURLResponse)?.statusCode == 413)
    }
}
