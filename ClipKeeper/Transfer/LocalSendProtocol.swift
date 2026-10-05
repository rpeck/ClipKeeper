import CryptoKit
import Foundation

/// The LocalSend protocol, version 2: constants, message shapes, and the
/// strict decoding rules from docs/SYNC-DESIGN.md. Every value that comes
/// from the network passes through here before any other code sees it.
enum LocalSend {
    static let version = "2.0"
    static let defaultPort = 53317
    static let multicastGroup = "224.0.0.167"
    static let multicastPort = 53317
    static let apiPrefix = "/api/localsend/v2/"

    enum Route: String, CaseIterable {
        case register, info
        case prepareUpload = "prepare-upload"
        case upload, cancel

        var path: String { LocalSend.apiPrefix + rawValue }

        /// Exact match on the path. No prefixes, no trailing slash, no case folding.
        static func match(_ path: String) -> Route? {
            allCases.first { $0.path == path }
        }
    }

    // MARK: Limits

    enum Limits {
        static let announcementBytes = 1_024
        static let announcementDepth = 4
        static let aliasGraphemes = 32
        static let fingerprintLength = 64
        static let discoveredDevices = 64
        static let discoveredTTL: TimeInterval = 60
        static let registerBodyBytes = 4_096
        static let prepareBodyBytes = 256 * 1_024
        static let prepareDepth = 32
        static let filesPerTransfer = 50
        static let bytesPerTransfer: Int64 = 100 * 1_000_000
        static let bytesPerFile: Int64 = 20 * 1_000_000
        static let bytesPerText: Int64 = 1_000_000
        static let fileIDLength = 128
        static let headerBlockBytes = 16 * 1_024
        static let headerCount = 64
        static let headerDeadline: TimeInterval = 10
        static let minimumThroughputBytesPerSecond = 8 * 1_024
        static let connections = 8
        static let connectionsPerAddress = 2
        static let stagingQuota: Int64 = 200 * 1_000_000
        static let freeSpaceFloor: Int64 = 2_000_000_000
        static let tokenIdleSeconds: TimeInterval = 300
        static let pinFailuresPerAddress = 3
        static let pinFailuresPerMinute = 10
        static let pinFailuresTotal = 30
        static let registerRepliesPerSourceSeconds: TimeInterval = 10
        static let registerRepliesPerMinute = 20
        static let sendDeadline: TimeInterval = 60
        static let receivedClips = 500
        static let receivedBytes: Int64 = 500 * 1_000_000
        static let receivedAlias = "phone"
    }

    /// MIME types accepted from the network in this phase. Images come in Phase B.
    static let acceptedTypes: Set<String> = ["text/plain", "text/markdown"]

    // MARK: Messages

    /// A device description: the multicast announcement, the `register` body,
    /// and the `info` reply all use this shape, with some fields optional.
    struct DeviceInfo: Codable, Equatable {
        var alias: String
        var version: String
        var deviceModel: String?
        var deviceType: String?
        var fingerprint: String
        var port: Int?
        /// "https" or "http". Named `scheme` because `protocol` is a Swift keyword.
        var scheme: String?
        var download: Bool?
        var announce: Bool?

        enum CodingKeys: String, CodingKey {
            case alias, version, deviceModel, deviceType, fingerprint, port, download, announce
            case scheme = "protocol"
        }
    }

    struct FileMeta: Codable, Equatable {
        var id: String
        var fileName: String
        var size: Int64
        var fileType: String
        var sha256: String?
        var preview: String?
    }

    struct PrepareUploadRequest: Codable, Equatable {
        var info: DeviceInfo
        var files: [String: FileMeta]
    }

    struct PrepareUploadResponse: Codable, Equatable {
        var sessionId: String
        var files: [String: String]
    }

    // MARK: Validation

    enum ValidationError: Error, Equatable {
        case tooLarge
        case tooDeep
        case malformed
        case badAlias
        case badFingerprint
        case badPort
        case tooManyFiles
        case badFileID
        case badSize
        case badType(String)
        case badChecksum
    }

    /// Decodes JSON after a byte and bracket-depth check, so the decoder never
    /// sees a document larger or deeper than the route allows.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, maxBytes: Int, maxDepth: Int) throws -> T {
        guard data.count <= maxBytes else { throw ValidationError.tooLarge }
        guard StrictJSON.depth(of: data) <= maxDepth else { throw ValidationError.tooDeep }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ValidationError.malformed
        }
    }

    /// An alias for display: NFKC, no control or format characters, at most 32
    /// graphemes, never empty.
    static func cleanAlias(_ raw: String) -> String? {
        let folded = raw.precomposedStringWithCompatibilityMapping
        var out = ""
        for scalar in folded.unicodeScalars {
            let cat = scalar.properties.generalCategory
            switch cat {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                continue
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Limits.aliasGraphemes))
    }

    /// A fingerprint is 64 hex characters. Returned in uppercase, which is the
    /// form LocalSend shows on the phone.
    static func cleanFingerprint(_ raw: String) -> String? {
        guard raw.utf8.count == Limits.fingerprintLength else { return nil }
        let upper = raw.uppercased()
        guard upper.allSatisfy({ $0.isHexDigit }) else { return nil }
        return upper
    }

    static func cleanPort(_ port: Int?) -> Int? {
        guard let port, port >= 1_024, port <= 65_535 else { return nil }
        return port
    }

    /// A file id: 1 to 128 characters from `[A-Za-z0-9_-]`.
    static func isValidFileID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= Limits.fileIDLength else { return false }
        return id.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F || byte == 0x2D
        }
    }

    /// Checks a `prepare-upload` body against every limit. Returns the files
    /// in a stable order. Throws on the first rule that fails.
    static func validate(_ request: PrepareUploadRequest) throws -> [FileMeta] {
        guard !request.files.isEmpty, request.files.count <= Limits.filesPerTransfer else { throw ValidationError.tooManyFiles }
        var total: Int64 = 0
        var files: [FileMeta] = []
        for (key, meta) in request.files.sorted(by: { $0.key < $1.key }) {
            guard key == meta.id, isValidFileID(meta.id) else { throw ValidationError.badFileID }
            guard meta.size >= 0, meta.size <= Limits.bytesPerFile else { throw ValidationError.badSize }
            let (sum, overflow) = total.addingReportingOverflow(meta.size)
            guard !overflow, sum <= Limits.bytesPerTransfer else { throw ValidationError.badSize }
            total = sum
            let type = meta.fileType.lowercased().split(separator: ";").first.map(String.init) ?? ""
            guard acceptedTypes.contains(type) else { throw ValidationError.badType(meta.fileType) }
            guard meta.size <= Limits.bytesPerText else { throw ValidationError.badSize }
            if let sha = meta.sha256 {
                guard sha.utf8.count == 64, sha.allSatisfy({ $0.isHexDigit }) else { throw ValidationError.badChecksum }
            }
            var clean = meta
            clean.fileType = type
            files.append(clean)
        }
        return files
    }

    /// The SHA-256 fingerprint of a certificate, uppercase hex of the DER bytes.
    static func fingerprint(ofCertificateDER der: [UInt8]) -> String {
        SHA256.hash(data: Data(der)).map { String(format: "%02X", $0) }.joined()
    }

    /// Groups of four for the comparison screen: "4BAD DE53 A7F7 …".
    static func formatFingerprint(_ fingerprint: String) -> String {
        var out = ""
        for (i, ch) in fingerprint.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(i % 32 == 0 ? "\n" : " ") }
            out.append(ch)
        }
        return out
    }

    /// Constant-time equality of two strings as UTF-8 bytes.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            diff |= Int(p ^ q)
        }
        return diff == 0
    }
}

/// Byte-level checks on JSON before decoding.
enum StrictJSON {
    /// The maximum nesting of `{` and `[`, counted outside of strings. A
    /// malformed document returns a large depth, so it is refused too.
    static func depth(of data: Data) -> Int {
        var depth = 0, maxDepth = 0
        var inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B, 0x5B:
                depth += 1
                maxDepth = max(maxDepth, depth)
            case 0x7D, 0x5D:
                depth -= 1
                if depth < 0 { return Int.max }
            default: break
            }
        }
        return inString || depth != 0 ? Int.max : maxDepth
    }
}
