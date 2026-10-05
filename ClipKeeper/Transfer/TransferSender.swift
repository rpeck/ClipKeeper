import CryptoKit
import Foundation
import Security

/// One thing to send: what LocalSend calls a file.
struct OutgoingItem {
    var fileName: String
    var fileType: String
    var data: Data
    /// For text: the text itself, so the phone can show it as a message.
    var preview: String?
}

enum SendOutcome: Equatable {
    case sent
    /// The phone asks for its own receive PIN.
    case needsPIN
}

enum SendError: Error, Equatable {
    case fingerprintMismatch
    case refused
    case busy
    case tooManyRequests
    case wrongPIN
    case tooLarge
    case replyTooLarge
    case http(Int)
    case network
    case cancelled

    var message: String {
        switch self {
        case .fingerprintMismatch: return "The device did not present the certificate it announced. Nothing was sent."
        case .refused: return "The phone refused the transfer."
        case .busy: return "The phone is busy with another transfer."
        case .tooManyRequests: return "The phone blocks new requests for now."
        case .wrongPIN: return "The PIN was wrong."
        case .tooLarge: return "The clip is too large to send."
        case .replyTooLarge: return "The device sent a reply larger than the protocol allows. Nothing more was read."
        case .http(let code): return "The phone answered with an error (\(code))."
        case .network: return "The phone did not answer."
        case .cancelled: return "Cancelled."
        }
    }
}

/// The URLSession delegate that decides trust. The only accepted server is
/// the one whose leaf certificate hashes to the expected fingerprint. The
/// default system evaluation is never the decision, and redirects are refused.
final class PinnedTrustDelegate: NSObject, URLSessionTaskDelegate {
    let expectedFingerprint: String
    private(set) var mismatch = false

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }
        let der = SecCertificateCopyData(leaf) as Data
        let actual = LocalSend.fingerprint(ofCertificateDER: [UInt8](der))
        if LocalSend.constantTimeEquals(actual, expectedFingerprint) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            mismatch = true
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Sends to one device. A new instance per transfer: the session, its
/// delegate, and the pinned fingerprint live only as long as the transfer.
final class TransferSender {
    let address: String
    let port: Int
    let fingerprint: String
    private let delegate: PinnedTrustDelegate
    private let session: URLSession
    private var sessionID: String?

    init(address: String, port: Int, fingerprint: String) {
        self.address = address
        self.port = port
        self.fingerprint = fingerprint
        delegate = PinnedTrustDelegate(expectedFingerprint: fingerprint)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = LocalSend.Limits.sendDeadline
        config.timeoutIntervalForResource = LocalSend.Limits.sendDeadline
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// Builds a URL from parts the Mac controls. Only https, only an IPv4 literal.
    private func url(_ route: LocalSend.Route, query: [String: String] = [:]) -> URL? {
        guard NetworkInterfaces.ipv4(from: address) != nil else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = address
        c.port = port
        c.path = route.path
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        // URLComponents leaves "+" alone in a query; a PIN never holds one, but encode it anyway.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    /// The largest reply each route may send. Every status code counts.
    private static func replyLimit(for request: URLRequest) -> Int {
        request.url?.path == LocalSend.Route.prepareUpload.path ? LocalSend.Limits.prepareBodyBytes : LocalSend.Limits.registerBodyBytes
    }

    /// Reads the reply as it arrives and stops at the route's limit, so a
    /// device cannot make the Mac hold a large reply in memory.
    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        var request = request
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let limit = Self.replyLimit(for: request)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw SendError.network }
            if http.expectedContentLength > Int64(limit) {
                bytes.task.cancel()
                throw SendError.replyTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit {
                    bytes.task.cancel()
                    throw SendError.replyTooLarge
                }
            }
            return (data, http.statusCode)
        } catch let error as SendError {
            throw error
        } catch {
            if delegate.mismatch { throw SendError.fingerprintMismatch }
            if (error as? URLError)?.code == .cancelled { throw SendError.cancelled }
            throw SendError.network
        }
    }

    /// `GET info` over the pinned connection. Proves the device at this
    /// address holds the certificate it announced.
    func probe() async throws -> LocalSend.DeviceInfo {
        guard let url = url(.info) else { throw SendError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, status) = try await perform(request)
        guard status == 200 else { throw SendError.http(status) }
        guard let info = try? LocalSend.decode(LocalSend.DeviceInfo.self, from: data, maxBytes: LocalSend.Limits.registerBodyBytes, maxDepth: LocalSend.Limits.announcementDepth) else {
            throw SendError.network
        }
        return info
    }

    /// `prepare-upload`, then one `upload` per file. Returns `.needsPIN` when
    /// the phone asks for its receive PIN.
    func send(_ items: [OutgoingItem], from info: LocalSend.DeviceInfo, pin: String?) async throws -> SendOutcome {
        let total = items.reduce(0) { $0 + $1.data.count }
        guard !items.isEmpty, total <= LocalSend.Limits.bytesPerTransfer else { throw SendError.tooLarge }
        var files: [String: LocalSend.FileMeta] = [:]
        var byID: [String: OutgoingItem] = [:]
        for item in items {
            let id = ReceiveCoordinator.randomToken()
            let sha = SHA256.hash(data: item.data).map { String(format: "%02x", $0) }.joined()
            files[id] = LocalSend.FileMeta(id: id, fileName: item.fileName, size: Int64(item.data.count), fileType: item.fileType, sha256: sha, preview: item.preview)
            byID[id] = item
        }
        let body = LocalSend.PrepareUploadRequest(info: info, files: files)
        guard let prepareURL = url(.prepareUpload, query: pin.map { ["pin": $0] } ?? [:]) else { throw SendError.network }
        var request = URLRequest(url: prepareURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, status) = try await perform(request)
        switch status {
        case 200: break
        case 204: return .sent
        case 401: if pin == nil { return .needsPIN } else { throw SendError.wrongPIN }
        case 403: throw SendError.refused
        case 409: throw SendError.busy
        case 429: throw SendError.tooManyRequests
        default: throw SendError.http(status)
        }
        guard let reply = try? LocalSend.decode(LocalSend.PrepareUploadResponse.self, from: data, maxBytes: LocalSend.Limits.prepareBodyBytes, maxDepth: 4) else {
            throw SendError.network
        }
        sessionID = reply.sessionId
        for (fileID, token) in reply.files {
            guard let item = byID[fileID] else { continue }
            try Task.checkCancellation()
            guard let uploadURL = url(.upload, query: ["sessionId": reply.sessionId, "fileId": fileID, "token": token]) else { throw SendError.network }
            var upload = URLRequest(url: uploadURL)
            upload.httpMethod = "POST"
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            upload.httpBody = item.data
            let (_, uploadStatus) = try await perform(upload)
            guard uploadStatus == 200 else { throw SendError.http(uploadStatus) }
        }
        sessionID = nil
        return .sent
    }

    /// Tells the phone to drop the session. Best effort.
    func cancel() async {
        guard let id = sessionID, let url = url(.cancel, query: ["sessionId": id]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        _ = try? await perform(request)
        sessionID = nil
    }

    /// The items for a set of clips. Text kinds go as text with a preview,
    /// so LocalSend shows them as a message with a Copy button. Images go in
    /// their original format. Files clips are not sent in this phase.
    @MainActor
    static func items(for clips: [Clip], store: ClipStore) -> [OutgoingItem] {
        var out: [OutgoingItem] = []
        for clip in clips {
            switch clip.kind {
            case .text, .markdown, .code, .richText, .link, .color:
                let text = clip.text
                guard !text.isEmpty else { continue }
                let data = Data(text.utf8)
                guard Int64(data.count) <= LocalSend.Limits.bytesPerText else { continue }
                out.append(OutgoingItem(fileName: "\(ReceiveCoordinator.randomToken().prefix(8)).txt", fileType: "text/plain", data: data, preview: text))
            case .image:
                guard let snapshot = store.snapshot(for: clip) else { continue }
                if let png = snapshot.data(for: PBType.png) {
                    out.append(OutgoingItem(fileName: "Image.png", fileType: "image/png", data: png, preview: nil))
                } else if let jpeg = snapshot.data(for: PBType.jpeg) {
                    out.append(OutgoingItem(fileName: "Image.jpg", fileType: "image/jpeg", data: jpeg, preview: nil))
                } else if let gif = snapshot.data(for: PBType.gif) {
                    out.append(OutgoingItem(fileName: "Image.gif", fileType: "image/gif", data: gif, preview: nil))
                } else if let tiff = snapshot.data(for: PBType.tiff), let png = ImageConversion.convert(tiff, to: .png) {
                    out.append(OutgoingItem(fileName: "Image.png", fileType: "image/png", data: png, preview: nil))
                }
            case .files:
                continue
            }
        }
        return out
    }

    /// The text LocalSend shows on its Verify page in text mode: both
    /// fingerprints, sorted, joined.
    static func combinedFingerprint(_ a: String, _ b: String) -> String {
        [a.uppercased(), b.uppercased()].sorted().joined()
    }
}
