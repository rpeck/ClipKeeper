import dnssd
import Foundation

/// Mac-to-Mac discovery through Bonjour (DNS-SD).
///
/// macOS can block an app's own multicast while it still lets the system's
/// Bonjour service work for that app. A Mac whose announcements are blocked
/// can then still be found: the system sends the multicast for it.
///
/// - Publish: one `_clipkeeper._tcp` registration per allowed interface, in
///   the `local.` domain only. The TXT record holds the fingerprint and the
///   protocol version, the data that the LocalSend announcement carries.
/// - Browse: per allowed interface, `local.` only. Each result is resolved
///   once to a host in `.local.` and then to one IPv4 address on that
///   interface, kept only when the address is on the link of that
///   interface. A result only adds an entry to the list of nearby devices,
///   which grants no trust: a first send still needs the fingerprint
///   comparison, and every send pins the certificate.
///
/// Memory safety with the C callbacks: every callback context is a retained
/// box that holds a weak reference to its owner, released only after its
/// DNSServiceRef is deallocated. A DNSServiceRef is never deallocated inside
/// its own callback; the release runs on the queue after the callback returns.
final class BonjourDiscovery {
    static let serviceType = "_clipkeeper._tcp"
    static let domain = "local."
    /// Lookups in flight plus results found, together.
    static let maxEntries = 32
    /// New lookups per 10 seconds.
    static let maxStartsPerWindow = 20

    /// Called on the Bonjour queue with a validated device.
    var onFound: ((LocalSend.DeviceInfo, String) -> Void)?
    /// A registration from another address carries this Mac's fingerprint.
    var onImpersonation: ((String) -> Void)?
    /// Services that the browse reported and not yet removed: key → type and
    /// domain. Bounded. Each refresh looks up again any that are missing.
    private var known: [String: (index: UInt32, name: String, type: String, domain: String)] = [:]
    static let maxKnown = 64

    let queue = DispatchQueue(label: "com.raymondpeck.ClipKeeper.bonjour")
    private var operations: [Operation] = []
    private var pending: [String: PendingResolve] = [:]
    private var interfaces: [UInt32: NetworkInterface] = [:]
    private var ownFingerprint = ""
    /// Key ("index|name") → what was found and when, refreshed every 30 seconds.
    private var current: [String: (info: LocalSend.DeviceInfo, address: String, since: Date)] = [:]
    private var refresh: DispatchSourceTimer?
    private var windowStart = Date()
    private var startsInWindow = 0

    /// A DNSServiceRef with the context box that its callbacks receive.
    final class Operation {
        let ref: DNSServiceRef
        let box: Unmanaged<ContextBox>
        init(ref: DNSServiceRef, box: Unmanaged<ContextBox>) {
            self.ref = ref
            self.box = box
        }
    }

    /// What a C callback receives. Weak references only, so a late callback
    /// after a stop finds nothing to act on.
    final class ContextBox {
        weak var owner: BonjourDiscovery?
        weak var resolve: PendingResolve?
        init(owner: BonjourDiscovery?, resolve: PendingResolve? = nil) {
            self.owner = owner
            self.resolve = resolve
        }
    }

    deinit {
        // Release on the queue after any running callback; never wait here.
        let operations = self.operations
        let resolves = Array(pending.values)
        let queue = self.queue
        queue.async {
            for op in operations { Self.release(op) }
            for resolve in resolves { resolve.cancel(on: queue) }
        }
    }

    func start(interfaces list: [NetworkInterface], alias: String, port: Int, fingerprint: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.ownFingerprint = fingerprint
            let txt = Self.txtRecord(fingerprint: fingerprint)
            for iface in list {
                let index = if_nametoindex(iface.name)
                guard index != 0 else { continue }
                self.interfaces[index] = iface
                self.register(index: index, alias: alias, port: port, txt: txt)
                self.browse(index: index)
            }
            self.startRefresh()
        }
    }

    /// Clears the state at once; only the release of the handles waits for
    /// any running callback. Call from outside the Bonjour queue.
    func stop() {
        queue.sync { stopLocked() }
    }

    private func stopLocked() {
        refresh?.cancel()
        refresh = nil
        let old = operations
        operations = []
        for resolve in pending.values { resolve.cancel(on: queue) }
        pending = [:]
        interfaces = [:]
        current = [:]
        known = [:]
        // Deferred, so a callback that is running now returns first.
        queue.async { for op in old { Self.release(op) } }
    }

    static func release(_ op: Operation) {
        DNSServiceRefDeallocate(op.ref)
        op.box.release()
    }

    // MARK: Publish

    private static func txtRecord(fingerprint: String) -> [UInt8] {
        var out: [UInt8] = []
        for entry in ["fp=\(fingerprint)", "v=\(LocalSend.version)"] {
            let bytes = Array(entry.utf8)
            out.append(UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        return out
    }

    private func register(index: UInt32, alias: String, port: Int, txt: [UInt8]) {
        var ref: DNSServiceRef?
        let box = Unmanaged.passRetained(ContextBox(owner: self))
        let status = txt.withUnsafeBufferPointer { buffer in
            DNSServiceRegister(&ref, 0, index, alias, Self.serviceType, Self.domain, nil,
                               UInt16(port).bigEndian, UInt16(buffer.count), buffer.baseAddress,
                               bonjourRegisterReply, box.toOpaque())
        }
        guard status == kDNSServiceErr_NoError, let ref else {
            box.release()
            NSLog("bonjour: register failed on interface %u: %d", index, status)
            return
        }
        DNSServiceSetDispatchQueue(ref, queue)
        operations.append(Operation(ref: ref, box: box))
    }

    // MARK: Browse and resolve

    private func browse(index: UInt32) {
        var ref: DNSServiceRef?
        let box = Unmanaged.passRetained(ContextBox(owner: self))
        let status = DNSServiceBrowse(&ref, 0, index, Self.serviceType, Self.domain, bonjourBrowseReply, box.toOpaque())
        guard status == kDNSServiceErr_NoError, let ref else {
            box.release()
            NSLog("bonjour: browse failed on interface %u: %d", index, status)
            return
        }
        DNSServiceSetDispatchQueue(ref, queue)
        operations.append(Operation(ref: ref, box: box))
    }

    private func key(_ index: UInt32, _ name: String) -> String { "\(index)|\(name)" }

    func handleBrowse(flags: DNSServiceFlags, index: UInt32, name: String, type: String, domain: String) {
        guard interfaces[index] != nil, domain.lowercased() == Self.domain else { return }
        let key = key(index, name)
        if flags & DNSServiceFlags(kDNSServiceFlagsAdd) == 0 {
            // Stop refreshing it. Never delete what was learned another way;
            // the nearby list's own expiry applies.
            pending.removeValue(forKey: key)?.cancel(on: queue)
            current[key] = nil
            known[key] = nil
            return
        }
        if known[key] == nil, known.count < Self.maxKnown { known[key] = (index, name, type, domain) }
        startResolve(key: key, index: index, name: name, type: type, domain: domain)
    }

    private func startResolve(key: String, index: UInt32, name: String, type: String, domain: String) {
        guard pending[key] == nil, takeStart() else { return }
        // One shared cap. A full table drops its oldest result rather than
        // refusing new devices for good.
        while pending.count + current.count >= Self.maxEntries {
            guard let oldest = current.min(by: { $0.value.since < $1.value.since })?.key else { return }
            current[oldest] = nil
        }
        let resolve = PendingResolve(owner: self, key: key, index: index, name: name)
        pending[key] = resolve
        resolve.start(type: type, domain: domain)
    }

    private func takeStart() -> Bool {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 10 {
            windowStart = now
            startsInWindow = 0
        }
        guard startsInWindow < Self.maxStartsPerWindow else { return false }
        startsInWindow += 1
        return true
    }

    func finish(_ resolve: PendingResolve) {
        resolve.cancel(on: queue)
        if pending[resolve.key] === resolve { pending[resolve.key] = nil }
    }

    /// The last step: an IPv4 address on the link of the interface it came in on.
    func found(_ resolve: PendingResolve, address: UInt32) {
        defer { finish(resolve) }
        guard pending[resolve.key] === resolve,
              let iface = interfaces[resolve.index], iface.isOnLink(address),
              let fingerprint = resolve.fingerprint,
              let port = resolve.port else { return }
        if fingerprint == ownFingerprint {
            let isOwnAddress = interfaces.values.contains { $0.ipv4.contains { $0.address == address } }
            if !isOwnAddress { onImpersonation?(NetworkInterfaces.string(fromIPv4: address)) }
            return
        }
        let info = LocalSend.DeviceInfo(alias: resolve.name, version: LocalSend.version, deviceModel: "Mac", deviceType: "desktop",
                                        fingerprint: fingerprint, port: port, scheme: "https", download: nil, announce: nil)
        let text = NetworkInterfaces.string(fromIPv4: address)
        current[resolve.key] = (info, text, Date())
        onFound?(info, text)
    }

    private func startRefresh() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for entry in self.current.values { self.onFound?(entry.info, entry.address) }
            // A known service pushed out of the table comes back here, within the rate limit.
            for (key, service) in self.known where self.current[key] == nil && self.pending[key] == nil {
                self.startResolve(key: key, index: service.index, name: service.name, type: service.type, domain: service.domain)
            }
        }
        timer.resume()
        refresh = timer
    }
}

/// One lookup: service name → host and TXT → one IPv4 address. Each step
/// takes its first answer only. Times out after five seconds.
final class PendingResolve {
    weak var owner: BonjourDiscovery?
    let key: String
    let index: UInt32
    let name: String
    private(set) var fingerprint: String?
    private(set) var port: Int?
    private var resolveOp: BonjourDiscovery.Operation?
    private var addressOp: BonjourDiscovery.Operation?
    private var resolved = false
    private var done = false
    private var timeout: DispatchWorkItem?

    init(owner: BonjourDiscovery, key: String, index: UInt32, name: String) {
        self.owner = owner
        self.key = key
        self.index = index
        self.name = name
    }

    func start(type: String, domain: String) {
        guard let owner else { return }
        var ref: DNSServiceRef?
        let box = Unmanaged.passRetained(BonjourDiscovery.ContextBox(owner: owner, resolve: self))
        let status = DNSServiceResolve(&ref, 0, index, name, type, domain, bonjourResolveReply, box.toOpaque())
        guard status == kDNSServiceErr_NoError, let ref else {
            box.release()
            return owner.finish(self)
        }
        DNSServiceSetDispatchQueue(ref, owner.queue)
        resolveOp = BonjourDiscovery.Operation(ref: ref, box: box)
        let item = DispatchWorkItem { [weak self] in
            guard let self, let owner = self.owner else { return }
            owner.finish(self)
        }
        timeout = item
        owner.queue.asyncAfter(deadline: .now() + 5, execute: item)
    }

    func resolved(host: String, port: UInt16, txt: UnsafeRawBufferPointer) {
        guard !done, !resolved, let owner else { return }
        resolved = true
        // The first answer only: stop the resolve after this callback returns.
        if let op = resolveOp {
            resolveOp = nil
            owner.queue.async { BonjourDiscovery.release(op) }
        }
        // A host outside .local. would mean a DNS query beyond this network.
        guard host.lowercased().hasSuffix(".local.") else { return owner.finish(self) }
        self.port = LocalSend.cleanPort(Int(UInt16(bigEndian: port)))
        var length: UInt8 = 0
        if let base = txt.baseAddress, let value = TXTRecordGetValuePtr(UInt16(txt.count), base, "fp", &length), length == 64 {
            let bytes = UnsafeRawBufferPointer(start: value, count: Int(length))
            if let raw = String(bytes: bytes, encoding: .utf8) { fingerprint = LocalSend.cleanFingerprint(raw) }
        }
        guard fingerprint != nil, self.port != nil else { return owner.finish(self) }
        var ref: DNSServiceRef?
        let box = Unmanaged.passRetained(BonjourDiscovery.ContextBox(owner: owner, resolve: self))
        let status = DNSServiceGetAddrInfo(&ref, 0, index, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host, bonjourAddressReply, box.toOpaque())
        guard status == kDNSServiceErr_NoError, let ref else {
            box.release()
            return owner.finish(self)
        }
        DNSServiceSetDispatchQueue(ref, owner.queue)
        addressOp = BonjourDiscovery.Operation(ref: ref, box: box)
    }

    func address(_ value: UInt32) {
        guard !done, let owner else { return }
        owner.found(self, address: value)
    }

    /// Stops both lookups. Their release runs after the current callback.
    func cancel(on queue: DispatchQueue) {
        done = true
        timeout?.cancel()
        timeout = nil
        let ops = [resolveOp, addressOp].compactMap { $0 }
        resolveOp = nil
        addressOp = nil
        queue.async { for op in ops { BonjourDiscovery.release(op) } }
    }
}

// MARK: C callbacks. They run on the Bonjour queue.

private let bonjourRegisterReply: DNSServiceRegisterReply = { _, _, error, _, _, _, _ in
    if error != kDNSServiceErr_NoError { NSLog("bonjour: registration error %d", error) }
}

private let bonjourBrowseReply: DNSServiceBrowseReply = { _, flags, index, error, name, type, domain, context in
    guard error == kDNSServiceErr_NoError, let context, let name, let type, let domain else { return }
    let box = Unmanaged<BonjourDiscovery.ContextBox>.fromOpaque(context).takeUnretainedValue()
    box.owner?.handleBrowse(flags: flags, index: index, name: String(cString: name), type: String(cString: type), domain: String(cString: domain))
}

private let bonjourResolveReply: DNSServiceResolveReply = { _, _, _, error, _, host, port, txtLength, txt, context in
    guard let context else { return }
    let box = Unmanaged<BonjourDiscovery.ContextBox>.fromOpaque(context).takeUnretainedValue()
    guard let resolve = box.resolve else { return }
    guard error == kDNSServiceErr_NoError, let host else {
        box.owner?.finish(resolve)
        return
    }
    resolve.resolved(host: String(cString: host), port: port, txt: UnsafeRawBufferPointer(start: txt, count: Int(txtLength)))
}

private let bonjourAddressReply: DNSServiceGetAddrInfoReply = { _, flags, _, error, _, address, _, context in
    guard let context, error == kDNSServiceErr_NoError, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
          let address, address.pointee.sa_family == sa_family_t(AF_INET) else { return }
    let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    Unmanaged<BonjourDiscovery.ContextBox>.fromOpaque(context).takeUnretainedValue().resolve?.address(value)
}
