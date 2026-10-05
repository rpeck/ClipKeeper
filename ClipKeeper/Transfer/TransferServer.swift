import CryptoKit
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL

/// A response from the application layer. Nothing from the request is ever
/// copied into a response header.
struct TransferResponse {
    var status: HTTPResponseStatus
    var body: Data?
    var contentType: String?

    static func status(_ code: HTTPResponseStatus) -> TransferResponse { TransferResponse(status: code, body: nil, contentType: nil) }

    static func json<T: Encodable>(_ value: T) -> TransferResponse {
        guard let data = try? JSONEncoder().encode(value) else { return .status(.internalServerError) }
        return TransferResponse(status: .ok, body: data, contentType: "application/json")
    }
}

/// The outcome of an application check: a value, or the status to answer with.
enum RouteResult<T> {
    case success(T)
    case failure(HTTPResponseStatus)
}

/// An upload in progress: the staging descriptor and the bytes expected.
final class StagedUpload {
    let sessionID: String
    let fileID: String
    let url: URL
    let expectedBytes: Int64
    let handle: FileHandle
    var written: Int64 = 0
    var hasher = SHA256()

    init(sessionID: String, fileID: String, url: URL, expectedBytes: Int64, handle: FileHandle) {
        self.sessionID = sessionID
        self.fileID = fileID
        self.url = url
        self.expectedBytes = expectedBytes
        self.handle = handle
    }
}

/// What the HTTP layer needs from the application layer. All calls arrive on
/// NIO event-loop threads; the coordinator is thread-safe.
protocol TransferRequestHandling: AnyObject {
    var isPaused: Bool { get }
    func allowedInterfaces() -> [NetworkInterface]
    /// `register` and `info`.
    func deviceInfo(for registration: LocalSend.DeviceInfo?, from address: String) -> TransferResponse
    /// The PIN check for `prepare-upload`, done before the body is read.
    func checkPIN(query: [String: String], from address: String) -> RouteResult<TransferCredential>
    /// The `prepare-upload` body, after the PIN named the device. Asynchronous: it asks the user.
    func prepareUpload(body: Data, credential: TransferCredential, from address: String, completion: @escaping (TransferResponse) -> Void)
    func openUpload(query: [String: String], from address: String, contentLength: Int64) -> RouteResult<StagedUpload>
    func finishUpload(_ upload: StagedUpload, completion: @escaping (HTTPResponseStatus) -> Void)
    func abortUpload(_ upload: StagedUpload)
    func cancel(query: [String: String], from address: String) -> HTTPResponseStatus
}

/// The HTTPS listener. SwiftNIO parses HTTP/1.1; this file applies the
/// application rules from the design: exact paths, strict query, header
/// limits, body limits per route, deadlines, connection caps, one request
/// per connection.
final class TransferServer {
    private let group: MultiThreadedEventLoopGroup
    private var channels: [Channel] = []
    private let gate = ConnectionGate()
    private let children = ChildChannels()
    private weak var handler: TransferRequestHandling?

    init(handler: TransferRequestHandling) {
        self.handler = handler
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        stop()
        try? group.syncShutdownGracefully()
    }

    var isRunning: Bool { !channels.isEmpty }

    /// One listener per IPv4 address of each allowed interface. Nothing
    /// listens on the wildcard address, so a VPN or virtual interface never
    /// reaches the server. Each connection is still checked against the
    /// allowed links, because routes can change while a listener is open.
    func start(identity: TransferIdentity, port: Int, interfaces: [NetworkInterface]) throws {
        stop()
        let tls = try identity.tlsConfiguration()
        let sslContext = try NIOSSLContext(configuration: tls)
        guard let handler else { return }
        let gate = self.gate
        let children = self.children
        do {
            for iface in interfaces {
                // IP_BOUND_IF ties the listener to this interface: a packet that
                // arrives on any other interface, such as a VPN, never reaches it.
                let index = if_nametoindex(iface.name)
                guard index != 0 else { throw TransferServerError.noInterface(iface.name) }
                let bootstrap = ServerBootstrap(group: group)
                    .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
                    .serverChannelOption(ChannelOptions.socket(IPPROTO_IP, IP_BOUND_IF), value: SocketOptionValue(index))
                    .serverChannelOption(ChannelOptions.backlog, value: 16)
                    .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 4)
                    .childChannelInitializer { [weak handler] channel in
                        guard let handler else { return channel.close() }
                        // The peer must be IPv4, on the link of this listener's interface,
                        // that interface must still be allowed, and the caps must hold.
                        guard let address = channel.remoteAddress?.ipAddress,
                              let value = NetworkInterfaces.ipv4(from: address), iface.isOnLink(value),
                              handler.allowedInterfaces().contains(where: { $0.name == iface.name && $0.isOnLink(value) }),
                              gate.admit(address) else {
                            return channel.close()
                        }
                        let id = children.add(channel)
                        channel.closeFuture.whenComplete { _ in
                            gate.release(address)
                            children.remove(id)
                        }
                        do {
                            let ops = channel.pipeline.syncOperations
                            try ops.addHandler(NIOSSLServerHandler(context: sslContext))
                            try ops.configureHTTPServerPipeline(withPipeliningAssistance: false, withErrorHandling: true)
                            try ops.addHandler(TransferHTTPHandler(handler: handler, remoteAddress: address))
                            return channel.eventLoop.makeSucceededVoidFuture()
                        } catch {
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    }
                for address in iface.addressStrings {
                    channels.append(try bootstrap.bind(host: address, port: port).wait())
                }
            }
        } catch {
            stop()
            throw error
        }
    }

    /// Closes the listeners and every accepted connection, so no request
    /// continues with the old settings.
    func stop() {
        for channel in channels { try? channel.close().wait() }
        channels = []
        for child in children.all() { child.close(promise: nil) }
    }
}

enum TransferServerError: Error {
    case noInterface(String)
}

/// The accepted connections, so `stop()` can close them.
final class ChildChannels: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [Int: Channel] = [:]
    private var next = 0

    func add(_ channel: Channel) -> Int {
        lock.lock(); defer { lock.unlock() }
        next += 1
        channels[next] = channel
        return next
    }

    func remove(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        channels[id] = nil
    }

    func all() -> [Channel] {
        lock.lock(); defer { lock.unlock() }
        return Array(channels.values)
    }
}

/// Counts open connections in total and per address.
final class ConnectionGate {
    private let lock = NSLock()
    private var perAddress: [String: Int] = [:]
    private var total = 0

    func admit(_ address: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let mine = perAddress[address] ?? 0
        guard total < LocalSend.Limits.connections, mine < LocalSend.Limits.connectionsPerAddress else { return false }
        total += 1
        perAddress[address] = mine + 1
        return true
    }

    func release(_ address: String) {
        lock.lock(); defer { lock.unlock() }
        total = max(0, total - 1)
        let mine = (perAddress[address] ?? 1) - 1
        if mine <= 0 { perAddress[address] = nil } else { perAddress[address] = mine }
    }
}

/// One connection, one request. Every check that the design puts on the
/// transport is here.
final class TransferHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case waitingForHead
        case collecting(route: LocalSend.Route, query: [String: String], body: Data, limit: Int, credential: TransferCredential?)
        case uploading(StagedUpload)
        case done
    }

    private let handler: TransferRequestHandling
    private let remoteAddress: String
    private var state: State = .waitingForHead
    private var headerDeadline: Scheduled<Void>?
    private var throughputCheck: RepeatedTask?
    private var bodyDeadline: Scheduled<Void>?
    private var bytesSinceCheck: Int64 = 0

    init(handler: TransferRequestHandling, remoteAddress: String) {
        self.handler = handler
        self.remoteAddress = remoteAddress
    }

    func channelActive(context: ChannelHandlerContext) {
        headerDeadline = context.eventLoop.scheduleTask(in: .seconds(Int64(LocalSend.Limits.headerDeadline))) { [weak self] in
            guard let self, case .waitingForHead = self.state else { return }
            self.state = .done
            context.close(promise: nil)
        }
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        headerDeadline?.cancel()
        throughputCheck?.cancel()
        bodyDeadline?.cancel()
        if case .uploading(let upload) = state { handler.abortUpload(upload) }
        state = .done
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if case .uploading(let upload) = state { handler.abortUpload(upload) }
        state = .done
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            headerDeadline?.cancel()
            guard case .waitingForHead = state else { return }
            receive(head: head, context: context)
        case .body(var buffer):
            switch state {
            case .collecting(let route, let query, var body, let limit, let credential):
                guard body.count + buffer.readableBytes <= limit else {
                    return respond(.status(.payloadTooLarge), context: context)
                }
                if let bytes = buffer.readBytes(length: buffer.readableBytes) { body.append(contentsOf: bytes) }
                state = .collecting(route: route, query: query, body: body, limit: limit, credential: credential)
            case .uploading(let upload):
                let count = Int64(buffer.readableBytes)
                guard upload.written + count <= upload.expectedBytes else {
                    handler.abortUpload(upload)
                    state = .done
                    return respond(.status(.badRequest), context: context)
                }
                guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
                do {
                    try upload.handle.write(contentsOf: bytes)
                } catch {
                    handler.abortUpload(upload)
                    state = .done
                    return respond(.status(.internalServerError), context: context)
                }
                upload.hasher.update(data: bytes)
                upload.written += count
                bytesSinceCheck += count
            default:
                break
            }
        case .end:
            throughputCheck?.cancel()
            bodyDeadline?.cancel()
            switch state {
            case .collecting(let route, let query, let body, _, let credential):
                state = .done
                dispatch(route: route, query: query, body: body, credential: credential, context: context)
            case .uploading(let upload):
                state = .done
                let loop = context.eventLoop
                handler.finishUpload(upload) { [weak self] status in
                    loop.execute { self?.respond(.status(status), context: context) }
                }
            default:
                break
            }
        }
    }

    // MARK: Head

    private func receive(head: HTTPRequestHead, context: ChannelHandlerContext) {
        // Transport rules first. Any failure closes the connection with a status and no detail.
        guard head.version == .http1_1 || head.version == .http1_0 else { return respond(.status(.httpVersionNotSupported), context: context) }
        guard head.headers.count <= LocalSend.Limits.headerCount else { return respond(.status(.requestHeaderFieldsTooLarge), context: context) }
        let headerBytes = head.headers.reduce(head.uri.utf8.count) { $0 + $1.name.utf8.count + $1.value.utf8.count + 4 }
        guard headerBytes <= LocalSend.Limits.headerBlockBytes else { return respond(.status(.requestHeaderFieldsTooLarge), context: context) }
        guard !head.headers.contains(name: "transfer-encoding"), !head.headers.contains(name: "expect"), !head.headers.contains(name: "upgrade") else {
            return respond(.status(.badRequest), context: context)
        }
        let lengths = head.headers[canonicalForm: "content-length"]
        guard lengths.count <= 1 else { return respond(.status(.badRequest), context: context) }
        var contentLength: Int64 = 0
        if let raw = lengths.first {
            guard raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), raw.utf8.count <= 12, let value = Int64(String(raw)) else {
                return respond(.status(.badRequest), context: context)
            }
            contentLength = value
        }
        for header in head.headers where header.value.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D || $0 == 0x00 }) {
            return respond(.status(.badRequest), context: context)
        }

        // Path and query.
        guard let parsed = Self.splitURI(head.uri), let route = LocalSend.Route.match(parsed.path) else {
            return respond(.status(.notFound), context: context)
        }
        guard let query = Self.parseQuery(parsed.query) else { return respond(.status(.badRequest), context: context) }
        if handler.isPaused { return respond(.status(.serviceUnavailable), context: context) }

        switch (route, head.method) {
        case (.info, .GET):
            respond(handler.deviceInfo(for: nil, from: remoteAddress), context: context)
        case (.register, .POST):
            guard contentLength <= LocalSend.Limits.registerBodyBytes else { return respond(.status(.payloadTooLarge), context: context) }
            state = .collecting(route: route, query: query, body: Data(), limit: LocalSend.Limits.registerBodyBytes, credential: nil)
            startBodyDeadline(contentLength: contentLength, context: context)
        case (.prepareUpload, .POST):
            guard contentLength <= LocalSend.Limits.prepareBodyBytes else { return respond(.status(.payloadTooLarge), context: context) }
            switch handler.checkPIN(query: query, from: remoteAddress) {
            case .failure(let status):
                respond(.status(status), context: context)
            case .success(let credential):
                state = .collecting(route: route, query: query, body: Data(), limit: LocalSend.Limits.prepareBodyBytes, credential: credential)
                startBodyDeadline(contentLength: contentLength, context: context)
            }
        case (.upload, .POST):
            guard lengths.count == 1 else { return respond(.status(.lengthRequired), context: context) }
            switch handler.openUpload(query: query, from: remoteAddress, contentLength: contentLength) {
            case .failure(let status):
                respond(.status(status), context: context)
            case .success(let upload):
                state = .uploading(upload)
                startThroughputCheck(context: context)
            }
        case (.cancel, .POST):
            respond(.status(handler.cancel(query: query, from: remoteAddress)), context: context)
        default:
            respond(.status(.methodNotAllowed), context: context)
        }
    }

    private func dispatch(route: LocalSend.Route, query: [String: String], body: Data, credential: TransferCredential?, context: ChannelHandlerContext) {
        switch route {
        case .register:
            let info = try? LocalSend.decode(LocalSend.DeviceInfo.self, from: body, maxBytes: LocalSend.Limits.registerBodyBytes, maxDepth: LocalSend.Limits.announcementDepth)
            guard let info else { return respond(.status(.badRequest), context: context) }
            respond(handler.deviceInfo(for: info, from: remoteAddress), context: context)
        case .prepareUpload:
            guard let credential else { return respond(.status(.unauthorized), context: context) }
            let loop = context.eventLoop
            handler.prepareUpload(body: body, credential: credential, from: remoteAddress) { [weak self] response in
                loop.execute { self?.respond(response, context: context) }
            }
        default:
            respond(.status(.methodNotAllowed), context: context)
        }
    }

    /// A small body that the app collects must arrive at 8 KB/s or better,
    /// plus 10 seconds. A peer that sends a few bytes and stops is closed.
    private func startBodyDeadline(contentLength: Int64, context: ChannelHandlerContext) {
        let seconds = Int64(LocalSend.Limits.headerDeadline) + contentLength / Int64(LocalSend.Limits.minimumThroughputBytesPerSecond)
        bodyDeadline = context.eventLoop.scheduleTask(in: .seconds(seconds)) { [weak self] in
            guard let self, case .collecting = self.state else { return }
            self.respond(.status(.requestTimeout), context: context)
        }
    }

    /// Upload bodies must arrive at 8 KB/s or better, measured every five seconds.
    private func startThroughputCheck(context: ChannelHandlerContext) {
        bytesSinceCheck = 0
        let needed = Int64(LocalSend.Limits.minimumThroughputBytesPerSecond * 5)
        throughputCheck = context.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(5), delay: .seconds(5)) { [weak self] _ in
            guard let self, case .uploading(let upload) = self.state else { return }
            if self.bytesSinceCheck < needed && upload.written < upload.expectedBytes {
                self.handler.abortUpload(upload)
                self.state = .done
                self.respond(.status(.requestTimeout), context: context)
            }
            self.bytesSinceCheck = 0
        }
    }

    // MARK: Response

    private func respond(_ response: TransferResponse, context: ChannelHandlerContext) {
        headerDeadline?.cancel()
        throughputCheck?.cancel()
        bodyDeadline?.cancel()
        if case .uploading(let upload) = state { handler.abortUpload(upload) }
        state = .done
        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Content-Length", value: String(response.body?.count ?? 0))
        if let type = response.contentType { headers.add(name: "Content-Type", value: type) }
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: response.status, headers: headers))), promise: nil)
        if let body = response.body, !body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in context.close(promise: nil) }
    }

    // MARK: Parsing

    /// Splits "path?query". Refuses fragments, authority forms, and control bytes.
    static func splitURI(_ uri: String) -> (path: String, query: String?)? {
        guard uri.utf8.count <= 4_096, uri.hasPrefix("/"), !uri.contains("#"), !uri.utf8.contains(where: { $0 < 0x21 || $0 > 0x7E }) else { return nil }
        if let q = uri.firstIndex(of: "?") {
            return (String(uri[..<q]), String(uri[uri.index(after: q)...]))
        }
        return (uri, nil)
    }

    /// Strict query parsing: `key=value` pairs, percent-decoding that must
    /// succeed, no duplicate keys, no empty keys.
    static func parseQuery(_ query: String?) -> [String: String]? {
        guard let query else { return [:] }
        guard query.utf8.count <= 2_048 else { return nil }
        var out: [String: String] = [:]
        if query.isEmpty { return out }
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let eq = pair.firstIndex(of: "=") else { return nil }
            let rawKey = String(pair[..<eq]), rawValue = String(pair[pair.index(after: eq)...])
            guard let key = rawKey.removingPercentEncoding, let value = rawValue.removingPercentEncoding, !key.isEmpty else { return nil }
            guard out[key] == nil else { return nil }
            out[key] = value
        }
        return out
    }
}
