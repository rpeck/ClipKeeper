import Foundation
import Testing
@testable import ClipKeeper

@Suite struct PersonalDataDetectorTests {
    @Test func findsEmail() {
        #expect(PersonalDataDetector.detect("Write to jane.doe@example.com today").contains(.email))
    }

    @Test func ignoresCodeThatLooksLikeEmail() {
        #expect(!PersonalDataDetector.detect("@MainActor final class A {}").contains(.email))
        #expect(!PersonalDataDetector.detect("ssh user@localhost").contains(.email))
    }

    @Test func findsValidCardNumbers() {
        #expect(PersonalDataDetector.detect("Visa 4111 1111 1111 1111").contains(.card))
        #expect(PersonalDataDetector.detect("amex 378282246310005").contains(.card))
        #expect(PersonalDataDetector.detect("5555-5555-5555-4444").contains(.card))
    }

    @Test func ignoresNumbersThatAreNotCards() {
        // The check digit is wrong.
        #expect(!PersonalDataDetector.detect("4111 1111 1111 1112").contains(.card))
        // A timestamp in microseconds: no card network starts with 17.
        #expect(!PersonalDataDetector.detect("ts=1760380000000000").contains(.card))
        // All one digit passes Luhn, but is not a card.
        #expect(!PersonalDataDetector.detect("0000000000000000").contains(.card))
    }

    @Test func luhn() {
        #expect(PersonalDataDetector.luhn("4111111111111111"))
        #expect(!PersonalDataDetector.luhn("4111111111111112"))
    }

    @Test func socialSecurityNumbers() {
        #expect(PersonalDataDetector.detect("SSN 123-45-6789").contains(.ssn))
        #expect(!PersonalDataDetector.detect("000-12-3456").contains(.ssn))
        #expect(!PersonalDataDetector.detect("666-12-3456").contains(.ssn))
        #expect(!PersonalDataDetector.detect("912-12-3456").contains(.ssn))
        #expect(!PersonalDataDetector.detect("123-00-4567").contains(.ssn))
        #expect(!PersonalDataDetector.detect("released 2026-10-13").contains(.ssn))
        #expect(!PersonalDataDetector.detect("id 1123-45-6789").contains(.ssn))
    }

    @Test func iban() {
        #expect(PersonalDataDetector.detect("IBAN GB82 WEST 1234 5698 7654 32").contains(.iban))
        #expect(PersonalDataDetector.detect("DE89370400440532013000").contains(.iban))
        #expect(!PersonalDataDetector.detect("GB82WEST12345698765433").contains(.iban))
        #expect(PersonalDataDetector.ibanValid("GB82WEST12345698765432"))
        #expect(!PersonalDataDetector.ibanValid("GB82WEST1234"))
    }

    @Test func secrets() {
        #expect(PersonalDataDetector.detect("aws_access_key_id = AKIAIOSFODNN7EXAMPLE").contains(.secret))
        #expect(PersonalDataDetector.detect("token ghp_" + String(repeating: "a1B2", count: 9)).contains(.secret))
        #expect(PersonalDataDetector.detect("-----BEGIN RSA PRIVATE KEY-----\nMIIE").contains(.secret))
        #expect(PersonalDataDetector.detect("-----BEGIN OPENSSH PRIVATE KEY-----").contains(.secret))
        #expect(PersonalDataDetector.detect("sk-ant-api03-Abc123def456GHI789jkl012MNO").contains(.secret))
        #expect(PersonalDataDetector.detect("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U").contains(.secret))
    }

    @Test func ignoresTextThatOnlyLooksLikeSecrets() {
        #expect(!PersonalDataDetector.detect("-----BEGIN PUBLIC KEY-----").contains(.secret))
        #expect(!PersonalDataDetector.detect("see risk-assessment-for-the-whole-team-2026").contains(.secret))
        #expect(!PersonalDataDetector.detect("disk-utility-and-backup-settings-page").contains(.secret))
    }

    @Test func phoneNeedsTenDigits() {
        #expect(PersonalDataDetector.detect("Call +1 (415) 555-0132 tomorrow").contains(.phone))
        #expect(!PersonalDataDetector.detect("extension 555-0132").contains(.phone))
    }

    @Test func plainCodeHasNoFlags() {
        let code = """
        func add(_ a: Int, _ b: Int) -> Int {
            return a + b // version 1.2.3, build 20261013
        }
        """
        #expect(PersonalDataDetector.detect(code).isEmpty)
    }

    @Test func emptyText() {
        #expect(PersonalDataDetector.detect("").isEmpty)
    }

    @Test func hostileInputStaysFast() {
        let inputs = [
            String(repeating: "1", count: 300_000),
            String(repeating: "1-", count: 150_000),
            String(repeating: "AB12", count: 75_000),
            String(repeating: "a@", count: 150_000),
            "sk-" + String(repeating: "a-", count: 150_000),
            String(repeating: "eyJaaaaaaaaa.", count: 20_000),
        ]
        for input in inputs {
            let start = Date()
            _ = PersonalDataDetector.detect(input)
            #expect(Date().timeIntervalSince(start) < 2, "slow input starts with \(input.prefix(8))")
        }
    }

    @Test func names() {
        let flags: PersonalDataFlags = [.email, .secret]
        #expect(flags.names == "email address, password, key, or token")
    }
}

@Suite struct SearchTokenTests {
    @Test func fromAndHas() {
        let parsed = SearchTokens.parse("from:Pixel hello has:personal world")
        #expect(parsed.text == "hello world")
        #expect(parsed.filter.source == .deviceNamed("pixel"))
        #expect(parsed.filter.personalOnly)
    }

    @Test func fromKeywords() {
        #expect(SearchTokens.parse("from:other").filter.source == .otherDevices)
        #expect(SearchTokens.parse("from:this").filter.source == .thisMac)
        #expect(SearchTokens.parse("has:pii").filter.personalOnly)
    }

    @Test func plainSearchIsUntouched() {
        let parsed = SearchTokens.parse("from the phone")
        #expect(parsed.text == "from the phone")
        #expect(!parsed.filter.isActive)
    }

    @Test func emptyFromIsDropped() {
        let parsed = SearchTokens.parse("from: hello")
        #expect(parsed.text == "hello")
        #expect(!parsed.filter.isActive)
    }

    @Test func wordsOverrideTheMenuSource() {
        let menu = ClipFilter(source: .thisMac, personalOnly: true)
        let merged = menu.adding(SearchTokens.parse("from:other").filter)
        #expect(merged.source == .otherDevices)
        #expect(merged.personalOnly)
    }
}

@Suite @MainActor struct SourceFilterTests {
    let database: Database
    let store: ClipStore

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "SourceFilterTests-\(UUID().uuidString)"))
        let prefs = Preferences(defaults: defaults)
        prefs.fetchLinkTitles = false
        database = try Database.inMemory()
        store = ClipStore(database: database, blobs: .temporary(), prefs: prefs)
        store.ingest(.plainText("copied here"), sourceBundleID: nil, sourceAppName: "Notes")
        store.ingestNetworkText("from the phone", deviceName: "Pixel", deviceID: "d1")
        store.ingestNetworkText("from the work mac", deviceName: "Work Mac", deviceID: "d2")
        store.ingest(.plainText("handoff copy"), sourceBundleID: nil, sourceAppName: nil, origin: Clip.handoffOrigin, sourceDevice: Clip.handoffDeviceName)
    }

    private func texts(_ filter: ClipFilter, query: String = "") -> Set<String> {
        Set(store.clips(in: .history, query: query, filter: filter).map(\.text))
    }

    @Test func bySource() {
        #expect(texts(ClipFilter()).count == 4)
        #expect(texts(ClipFilter(source: .thisMac)) == ["copied here"])
        #expect(texts(ClipFilter(source: .otherDevices)) == ["from the phone", "from the work mac", "handoff copy"])
    }

    @Test func byOneDevice() {
        let pixel = SourceKey(origin: Clip.networkOrigin, deviceID: "d1", deviceName: nil)
        #expect(texts(ClipFilter(source: .device(pixel))) == ["from the phone"])
        let handoff = SourceKey(origin: Clip.handoffOrigin, deviceID: nil, deviceName: Clip.handoffDeviceName)
        #expect(texts(ClipFilter(source: .device(handoff))) == ["handoff copy"])
    }

    @Test func byName() {
        #expect(texts(ClipFilter(source: .deviceNamed("work"))) == ["from the work mac"])
        #expect(texts(ClipFilter(source: .deviceNamed("apple"))) == ["handoff copy"])
        // LIKE wildcards in a name match only themselves.
        #expect(texts(ClipFilter(source: .deviceNamed("%"))).isEmpty)
        #expect(texts(ClipFilter(source: .deviceNamed("_"))).isEmpty)
    }

    @Test func withSearchText() {
        #expect(texts(ClipFilter(source: .otherDevices), query: "phone") == ["from the phone"])
        #expect(texts(ClipFilter(source: .thisMac), query: "phone").isEmpty)
    }

    @Test func personalOnly() {
        store.ingest(.plainText("mail jane.doe@example.com"), sourceBundleID: nil, sourceAppName: nil)
        _ = ClipStore.scanPending(in: database.queue)
        #expect(texts(ClipFilter(source: .all, personalOnly: true)) == ["mail jane.doe@example.com"])
        let clip = try? #require(store.clips(in: .history, query: "jane").first)
        #expect(clip?.personalData == .email)
        #expect(store.personalDataCount() == 1)
    }

    @Test func scanMarksEveryClipOnce() throws {
        _ = ClipStore.scanPending(in: database.queue)
        let unscanned = try database.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE piiFlags IS NULL") }
        #expect(unscanned == 0)
        #expect(ClipStore.scanPending(in: database.queue) == false)
    }

    @Test func summaries() throws {
        let rows = store.sourceSummaries()
        #expect(rows.count == 3)
        let pixel = try #require(rows.first { $0.name == "Pixel" })
        #expect(pixel.count == 1)
        #expect(pixel.key.deviceID == "d1")
        #expect(pixel.kinds == [.text])
        #expect(rows.contains { $0.isHandoff && $0.name == Clip.handoffDeviceName })
        #expect(store.thisMacCount() == 1)
    }

    @Test func deleteOneSource() throws {
        let pixel = try #require(store.sourceSummaries().first { $0.name == "Pixel" })
        store.delete(store.clips(from: pixel.key))
        #expect(texts(ClipFilter()) == ["copied here", "from the work mac", "handoff copy"])
    }

    @Test func renamedDeviceStaysOneSource() throws {
        store.ingestNetworkText("second from the phone", deviceName: "Pixel 10", deviceID: "d1")
        let rows = store.sourceSummaries().filter { $0.key.deviceID == "d1" }
        #expect(rows.count == 1)
        #expect(rows.first?.count == 2)
    }
}
