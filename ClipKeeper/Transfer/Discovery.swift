import Foundation

/// A device heard on the local network. Announcements are data: nothing in
/// this record grants any trust, and the fingerprint here is only what the
/// device claimed. Verification happens on the comparison screen.
struct DiscoveredDevice: Identifiable, Hashable {
    var alias: String
    var fingerprint: String
    var address: String
    var port: Int
    var deviceModel: String?
    var deviceType: String?
    var lastSeen: Date

    /// Address and port, because an impostor can claim any fingerprint.
    var id: String { "\(address):\(port)" }

    var isPhone: Bool { deviceType == "mobile" }

    /// The fields a person sees. A change in `lastSeen` alone is not news.
    var visibleKey: String { [alias, fingerprint, address, String(port), deviceModel ?? "", deviceType ?? ""].joined(separator: "|") }
}

/// Multicast discovery for LocalSend, IPv4 only. One receive socket per
/// allowed interface, tied to that interface with IP_BOUND_IF, so a datagram
/// that arrives on a VPN or any other interface never reaches the parser.
/// Every socket option is explicit: membership per interface, TTL 1,
/// loopback off. A failed option closes the socket.
final class DiscoveryService {
    /// The device table changed in a way a person can see. Called on the
    /// discovery queue, at most twice a second.
    var onChange: (() -> Void)?
    /// An announcement could not be sent. The value is the errno, or 0 after
    /// a send works again. macOS answers EHOSTUNREACH when its Local Network
    /// permission blocks the app.
    var onSendResult: ((Int32) -> Void)?
    /// Something else on the network announced this Mac's own fingerprint.
    /// Called once per new address.
    var onImpersonation: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.raymondpeck.ClipKeeper.discovery")
    private var receivers: [(socket: Int32, source: DispatchSourceRead, iface: NetworkInterface)] = []
    private var interfaces: [NetworkInterface] = []
    private var ownFingerprint = ""
    private var ownInfo: LocalSend.DeviceInfo?
    private var devices: [String: DiscoveredDevice] = [:]
    private var replyTimes: [String: Date] = [:]
    private var replyWindow: [Date] = []
    private var warnedAddresses: Set<String> = []
    private var changePending = false
    private var budgetWindowStart = Date()
    private var budgetUsed = 0
    private var lastSendErrno: Int32 = -1
    private var verifiedFingerprints: Set<String> = []

    /// At most this many datagrams are parsed per second, from all sources together.
    static let datagramsPerSecond = 100

    deinit { stopLocked() }

    // MARK: Lifecycle

    /// Starts listening. `info` is the announcement this Mac sends.
    func start(interfaces: [NetworkInterface], info: LocalSend.DeviceInfo) {
        queue.sync {
            stopLocked()
            self.interfaces = interfaces
            ownFingerprint = info.fingerprint
            ownInfo = info
            for iface in interfaces { openReceiveSocket(for: iface) }
        }
    }

    func stop() { queue.sync { stopLocked() } }

    private func stopLocked() {
        for r in receivers {
            r.source.cancel()
            close(r.socket)
        }
        receivers = []
        devices = [:]
        warnedAddresses = []
    }

    /// The current table, newest first, without expired entries.
    var discovered: [DiscoveredDevice] {
        queue.sync {
            pruneLocked()
            return devices.values.sorted { $0.lastSeen > $1.lastSeen }
        }
    }

    /// Records a device that spoke to the HTTP server directly, such as a
    /// phone that sent `register`. Same limits as an announcement.
    func note(info: LocalSend.DeviceInfo, address: String) {
        queue.async { [weak self] in
            guard let self, self.takeBudget() else { return }
            _ = self.recordLocked(info: info, address: address)
        }
    }

    func remove(id: String) {
        queue.sync {
            if devices.removeValue(forKey: id) != nil { scheduleChangeLocked() }
        }
    }

    // MARK: Announce

    /// Sends one announcement on every allowed interface.
    func announce() {
        queue.async { [weak self] in self?.multicastLocked(isResponse: false) }
    }

    /// An announcement, or with `isResponse` the reply to one. LocalSend
    /// accepts a multicast reply with `announce` false in place of an HTTP
    /// `register` call, so this Mac never opens a connection to an address
    /// that a stranger on the network chose.
    private func multicastLocked(isResponse: Bool) {
        guard var info = ownInfo else { return }
        info.announce = !isResponse
        guard let payload = try? JSONEncoder().encode(info) else { return }
        var result: Int32 = 0
        for iface in interfaces {
            guard let first = iface.ipv4.first else { continue }
            let error = send(payload, from: iface, address: first.address)
            if error != 0 { result = error }
        }
        if result != lastSendErrno {
            lastSendErrno = result
            if result != 0 { NSLog("discovery: an announcement failed: %s", strerror(result)) }
            onSendResult?(result)
        }
    }

    /// Sends one datagram. Returns 0, or the errno of the step that failed.
    private func send(_ payload: Data, from iface: NetworkInterface, address: UInt32) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return errno }
        defer { close(fd) }
        var index = UInt32(if_nametoindex(iface.name))
        // if_nametoindex does not set errno, so name the failure here.
        guard index != 0 else { return ENXIO }
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else { return errno }
        var ifaceAddr = in_addr(s_addr: address.bigEndian)
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifaceAddr, socklen_t(MemoryLayout<in_addr>.size)) == 0 else { return errno }
        var ttl: UInt8 = 1
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size)) == 0 else { return errno }
        var loop: UInt8 = 0
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size)) == 0 else { return errno }
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(UInt16(LocalSend.multicastPort).bigEndian)
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, LocalSend.multicastGroup, &dest.sin_addr)
        let sent = payload.withUnsafeBytes { raw in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent < 0 ? errno : 0
    }

    // MARK: Receive

    /// One socket for one interface. Any option that fails closes the socket,
    /// so discovery never runs with weaker settings than intended.
    private func openReceiveSocket(for iface: NetworkInterface) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        var ok = true
        var yes: Int32 = 1
        ok = ok && setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0
        ok = ok && setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0
        var index = UInt32(if_nametoindex(iface.name))
        ok = ok && index != 0 && setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(LocalSend.multicastPort).bigEndian)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        ok = ok && withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
        for entry in iface.ipv4 where ok {
            var req = ip_mreq()
            inet_pton(AF_INET, LocalSend.multicastGroup, &req.imr_multiaddr)
            req.imr_interface = in_addr(s_addr: entry.address.bigEndian)
            ok = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &req, socklen_t(MemoryLayout<ip_mreq>.size)) == 0
        }
        ok = ok && fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0
        guard ok else {
            NSLog("discovery: socket setup failed on %@ (errno %d); discovery is off on it", iface.name, errno)
            close(fd)
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readDatagrams(fd: fd, iface: iface) }
        source.resume()
        receivers.append((fd, source, iface))
    }

    private func readDatagrams(fd: Int32, iface: NetworkInterface) {
        var buffer = [UInt8](repeating: 0, count: 2_048)
        // At most 32 datagrams per wake-up, so one socket cannot hold the queue.
        for _ in 0..<32 {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &fromLen)
                }
            }
            guard n > 0 else { return }
            // Read and drop when over budget, so the socket buffer drains.
            guard takeBudget() else { continue }
            guard from.sin_family == sa_family_t(AF_INET) else { continue }
            let source = UInt32(bigEndian: from.sin_addr.s_addr)
            handle(datagram: Data(buffer[0..<Int(n)]), from: source, on: iface)
        }
    }

    /// A global budget of datagrams per second. Past it, input is read and dropped.
    private func takeBudget() -> Bool {
        let now = Date()
        if now.timeIntervalSince(budgetWindowStart) >= 1 {
            budgetWindowStart = now
            budgetUsed = 0
        }
        guard budgetUsed < Self.datagramsPerSecond else { return false }
        budgetUsed += 1
        return true
    }

    private func handle(datagram: Data, from source: UInt32, on iface: NetworkInterface) {
        guard datagram.count <= LocalSend.Limits.announcementBytes else { return }
        // The source must be on the link of the interface that received it.
        guard iface.isOnLink(source) else { return }
        guard let info = try? LocalSend.decode(LocalSend.DeviceInfo.self, from: datagram, maxBytes: LocalSend.Limits.announcementBytes, maxDepth: LocalSend.Limits.announcementDepth) else { return }
        let address = NetworkInterfaces.string(fromIPv4: source)
        let isOwnAddress = interfaces.contains { $0.ipv4.contains { $0.address == source } }
        if let fp = LocalSend.cleanFingerprint(info.fingerprint), fp == ownFingerprint {
            if !isOwnAddress, warnedAddresses.count < 16, warnedAddresses.insert(address).inserted {
                onImpersonation?(address)
            }
            return
        }
        guard recordLocked(info: info, address: address) != nil else { return }
        if info.announce == true, shouldReply(to: address) {
            multicastLocked(isResponse: true)
        }
    }

    /// Validates and stores one device. Returns nil when a field is bad.
    private func recordLocked(info: LocalSend.DeviceInfo, address: String) -> DiscoveredDevice? {
        guard let alias = LocalSend.cleanAlias(info.alias),
              let fingerprint = LocalSend.cleanFingerprint(info.fingerprint),
              let port = LocalSend.cleanPort(info.port),
              fingerprint != ownFingerprint else { return nil }
        // Plain HTTP peers are never offered, and there is no setting to allow them.
        guard info.scheme?.lowercased() == "https" else { return nil }
        pruneLocked()
        let device = DiscoveredDevice(alias: alias, fingerprint: fingerprint, address: address, port: port,
                                      deviceModel: info.deviceModel.flatMap(LocalSend.cleanAlias), deviceType: info.deviceType.flatMap(LocalSend.cleanAlias), lastSeen: Date())
        let previous = devices[device.id]
        // One host cannot fill the list from many ports.
        if previous == nil, devices.values.filter({ $0.address == address }).count >= 2 { return nil }
        if previous == nil, devices.count >= LocalSend.Limits.discoveredDevices {
            // Full: drop the oldest entry.
            if let oldest = devices.values.min(by: { $0.lastSeen < $1.lastSeen }) { devices[oldest.id] = nil }
        }
        devices[device.id] = device
        if previous?.visibleKey != device.visibleKey { scheduleChangeLocked() }
        return device
    }

    /// At most one change notice in flight, and at most two a second.
    private func scheduleChangeLocked() {
        guard !changePending else { return }
        changePending = true
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.changePending = false
            self.onChange?()
        }
    }

    /// Fingerprints that the user verified. Their entries stay for 12 hours,
    /// so a send works even when this Mac cannot announce itself to ask
    /// again. Safe: every send pins the certificate, so a stranger who takes
    /// over the address gets nothing.
    func setVerifiedFingerprints(_ fingerprints: Set<String>) {
        queue.async { [weak self] in self?.verifiedFingerprints = fingerprints }
    }

    private func pruneLocked() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-LocalSend.Limits.discoveredTTL)
        let verifiedCutoff = now.addingTimeInterval(-LocalSend.Limits.verifiedDeviceTTL)
        devices = devices.filter { entry in
            let limit = verifiedFingerprints.contains(entry.value.fingerprint) ? verifiedCutoff : cutoff
            return entry.value.lastSeen > limit
        }
    }

    /// At most one reply per source every 10 seconds, and 20 per minute in total.
    private func shouldReply(to address: String) -> Bool {
        let now = Date()
        replyWindow = replyWindow.filter { now.timeIntervalSince($0) < 60 }
        guard replyWindow.count < LocalSend.Limits.registerRepliesPerMinute else { return false }
        if let last = replyTimes[address], now.timeIntervalSince(last) < LocalSend.Limits.registerRepliesPerSourceSeconds { return false }
        replyTimes[address] = now
        replyWindow.append(now)
        if replyTimes.count > 256 { replyTimes = replyTimes.filter { now.timeIntervalSince($0.value) < 60 } }
        return true
    }
}
