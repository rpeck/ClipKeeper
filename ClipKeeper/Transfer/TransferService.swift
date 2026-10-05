import AppKit
import Foundation

/// Phone transfer, as the rest of the app sees it. Owns the identity, the
/// registry, the HTTPS server, discovery, and the accept dialog. Main thread.
@MainActor
final class TransferService: ObservableObject {
    enum State: Equatable {
        case off
        case running(addresses: [String])
        /// Stopped by a rule, such as too many wrong PINs. Needs the user.
        case stopped(String)
        case failed(String)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var log: [TransferLogEntry] = []
    @Published private(set) var impersonationWarning: String?
    @Published private(set) var fingerprint: String?
    /// The port in use. Another program on this Mac can hold the preferred one.
    @Published private(set) var port: Int = LocalSend.defaultPort
    /// Set when macOS refuses to send ClipKeeper's announcements, which is
    /// what the Local Network permission does while it is off.
    @Published private(set) var multicastBlocked = false
    /// The last announcement failed. A Bonjour browse can report "allowed"
    /// while macOS still blocks multicast, so a failed send counts on its own.
    private var announcementsFail = false

    private func updateMulticastBlocked() {
        multicastBlocked = announcementsFail || localNetwork.state == .denied
    }

    /// Called when clips arrive, for the menu bar icon.
    var onReceived: () -> Void = {}

    private let prefs: Preferences
    private let store: ClipStore
    private let vault = TransferVault.standard()
    let registry: DeviceRegistry
    private let budget = PINBudget()
    private var identity: TransferIdentity?
    private var coordinator: ReceiveCoordinator?
    private var server: TransferServer?
    private let discovery = DiscoveryService()
    private let localNetwork = LocalNetworkAccess()
    private var interfaceTimer: Timer?
    private var lastInterfaces: [NetworkInterface] = []
    private var lockObservers: [NSObjectProtocol] = []
    /// The screen lock state, kept apart from any coordinator, so a restart
    /// while the screen is locked starts paused.
    private var screenLocked = TransferService.isScreenLockedNow()
    private var activeDialog: NSAlert?
    /// The port, readable from the server threads.
    private let portLock = NSLock()
    private nonisolated(unsafe) var portForInfo = LocalSend.defaultPort

    nonisolated private func currentPortForInfo() -> Int {
        portLock.lock(); defer { portLock.unlock() }
        return portForInfo
    }

    init(store: ClipStore, database: Database, prefs: Preferences = .shared) {
        self.store = store
        self.prefs = prefs
        registry = DeviceRegistry(database: database, vault: vault)
        devices = registry.all()
        discovery.setVerifiedFingerprints(Set(devices.compactMap(\.verifiedFingerprint)))
        log = registry.recentLog()
        discovery.onChange = { [weak self] in
            Task { @MainActor in self?.refreshDiscovered() }
        }
        discovery.onSendResult = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                // EHOSTUNREACH is what macOS answers while it blocks the app's multicast.
                self.announcementsFail = error == EHOSTUNREACH || error == EPERM || error == EACCES
                self.updateMulticastBlocked()
            }
        }
        localNetwork.onChange = { [weak self] _ in
            guard let self else { return }
            self.updateMulticastBlocked()
            if case .running = self.state { self.discovery.announce() }
        }
        discovery.onImpersonation = { [weak self] address in
            Task { @MainActor in
                self?.impersonationWarning = "A device at \(address) announced this Mac's own fingerprint. Something on this network pretends to be this Mac. On your phones, keep the LocalSend PIN on, and verify this Mac before you send."
            }
        }
    }

    var isEnabled: Bool { prefs.transferEnabled }

    // MARK: Lifecycle

    /// Starts when the preference is on. Safe to call more than once.
    func startIfEnabled() {
        guard prefs.transferEnabled else { stop(); return }
        start()
    }

    func setEnabled(_ on: Bool) {
        prefs.transferEnabled = on
        if on { budget.reset(); start() } else { stop() }
    }

    /// Restarts after a hard stop. The PIN budget starts again from zero.
    func restart() {
        budget.reset()
        start()
    }

    private func start() {
        stopListeners()
        do {
            let id = try identity ?? TransferIdentity.load(vault: vault)
            identity = id
            fingerprint = id.fingerprint
            try registry.load()
        } catch {
            // A key or vault failure stops the feature. Nothing falls back to a weaker store.
            NSLog("transfer: key setup failed: %@", String(describing: error))
            if case TransferVault.VaultError.noSecureEnclave = error {
                state = .failed("This Mac has no Secure Enclave, which phone transfer needs for its key. Phone transfer is off.")
            } else {
                state = .failed("ClipKeeper cannot open its transfer key or PINs. To start again, quit ClipKeeper and delete the folder named transfer in its data folder.")
            }
            return
        }
        guard let identity else { return }
        let interfaces = NetworkInterfaces.allowed(prefs: prefs)
        lastInterfaces = interfaces
        guard !interfaces.isEmpty else {
            NSLog("transfer: no allowed interface")
            state = .failed("No Wi-Fi or Ethernet connection is active.")
            startInterfaceWatch()
            return
        }
        let staging = Database.supportDirectory.appendingPathComponent("staging", isDirectory: true)
        do { try ReceiveCoordinator.prepareStaging(at: staging) } catch {
            state = .failed("ClipKeeper cannot prepare its private staging folder.")
            return
        }

        let prefs = self.prefs
        let discovery = self.discovery
        startLockWatch()
        let coordinator = ReceiveCoordinator(
            registry: registry, budget: budget, stagingDir: staging,
            paused: screenLocked,
            identityInfo: { [weak self, fingerprint = identity.fingerprint, alias = prefs.transferAlias] in
                Self.info(alias: alias, fingerprint: fingerprint, port: self?.currentPortForInfo() ?? LocalSend.defaultPort)
            },
            interfaces: { NetworkInterfaces.allowed(prefs: prefs) },
            noteDevice: { info, address in discovery.note(info: info, address: address) })
        coordinator.askUser = { [weak self] incoming, answer in self?.ask(incoming, answer: answer) ?? answer(false) }
        coordinator.deliverText = { [weak self] text, device in
            guard let self else { return false }
            return self.store.ingestNetworkText(text, deviceName: device) != nil
        }
        coordinator.onHardStop = { [weak self] in self?.hardStop() }
        coordinator.onReceived = { [weak self] _, _ in
            self?.refreshLog()
            self?.onReceived()
        }
        self.coordinator = coordinator

        let server = TransferServer(handler: coordinator)
        do {
            port = try server.start(identity: identity, preferredPort: prefs.transferPort, interfaces: interfaces)
            portLock.lock(); portForInfo = port; portLock.unlock()
        } catch {
            NSLog("transfer: listener failed: %@", String(describing: error))
            state = .failed("ClipKeeper found no free port from \(prefs.transferPort) to \(prefs.transferPort + 9). Phone transfer is off.")
            self.coordinator = nil
            return
        }
        self.server = server
        discovery.start(interfaces: interfaces, info: Self.info(alias: prefs.transferAlias, fingerprint: identity.fingerprint, port: port))
        discovery.announce()
        state = .running(addresses: interfaces.flatMap(\.addressStrings))
        startInterfaceWatch()
        localNetwork.start()
    }

    func stop() {
        localNetwork.stop()
        announcementsFail = false
        multicastBlocked = false
        stopListeners()
        interfaceTimer?.invalidate()
        interfaceTimer = nil
        for o in lockObservers { DistributedNotificationCenter.default().removeObserver(o) }
        lockObservers = []
        state = .off
    }

    private func stopListeners() {
        // First end the coordinator, so work queued on other threads finds it
        // closed and stores nothing. Then refuse the dialog and close sockets.
        coordinator?.shutdown()
        refuseOpenDialog()
        server?.stop()
        server = nil
        coordinator = nil
        discovery.stop()
        discovered = []
    }

    private func hardStop() {
        stopListeners()
        state = .stopped("ClipKeeper stopped phone transfer after \(LocalSend.Limits.pinFailuresTotal) wrong PINs. Someone may be guessing. Issue new PINs to your phones, then press Restart.")
        refreshLog()
    }

    static func info(alias: String, fingerprint: String, port: Int) -> LocalSend.DeviceInfo {
        LocalSend.DeviceInfo(alias: alias, version: LocalSend.version, deviceModel: "Mac", deviceType: "desktop", fingerprint: fingerprint, port: port, scheme: "https", download: false, announce: true)
    }

    /// The description this Mac sends with a transfer.
    var ownInfo: LocalSend.DeviceInfo? {
        guard let fingerprint else { return nil }
        var info = Self.info(alias: prefs.transferAlias, fingerprint: fingerprint, port: port)
        info.announce = nil
        return info
    }

    // MARK: Interfaces and screen lock

    /// A change in the interfaces closes every listener and session, then
    /// starts again on the new list.
    private func startInterfaceWatch() {
        interfaceTimer?.invalidate()
        interfaceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.prefs.transferEnabled else { return }
                if case .stopped = self.state { return }
                let now = NetworkInterfaces.allowed(prefs: self.prefs)
                if now != self.lastInterfaces { self.start() }
            }
        }
    }

    private func startLockWatch() {
        guard lockObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screenLocked = true
                self?.coordinator?.setPaused(true)
                self?.refuseOpenDialog()
            }
        })
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screenLocked = false
                self?.coordinator?.setPaused(false)
            }
        })
    }

    // MARK: The accept dialog

    /// One dialog at a time. Return accepts, Escape refuses. No answer in 60
    /// seconds refuses.
    private func ask(_ incoming: IncomingTransfer, answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Accept from \(incoming.deviceName)?"
        let count = incoming.count == 1 ? "1 text" : "\(incoming.count) texts"
        let size = ByteCountFormatter.string(fromByteCount: incoming.bytes, countStyle: .file)
        alert.informativeText = "\(count), \(size), over the local network.\n\nAccept only if you send from this phone now. The clips go to History, marked as received."
        let accept = alert.addButton(withTitle: "Accept")
        // Return accepts only after 0.7 seconds, so a Return typed in another
        // app at the moment the dialog appears cannot accept it.
        accept.keyEquivalent = ""
        let refuse = alert.addButton(withTitle: "Refuse")
        refuse.keyEquivalent = "\u{1b}"
        alert.icon = NSImage(systemSymbolName: "iphone.and.arrow.forward", accessibilityDescription: nil)
        activeDialog = alert
        NSApp.activate(ignoringOtherApps: true)
        let timeout = Timer(timeInterval: 60, repeats: false) { _ in
            Task { @MainActor in NSApp.abortModal() }
        }
        RunLoop.main.add(timeout, forMode: .modalPanel)
        let arm = Timer(timeInterval: 0.7, repeats: false) { _ in
            Task { @MainActor in accept.keyEquivalent = "\r" }
        }
        RunLoop.main.add(arm, forMode: .modalPanel)
        let response = alert.runModal()
        timeout.invalidate()
        arm.invalidate()
        activeDialog = nil
        answer(response == .alertFirstButtonReturn)
    }

    /// The lock state at this moment, from the window server.
    static func isScreenLockedNow() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func refuseOpenDialog() {
        if activeDialog != nil { NSApp.abortModal() }
    }

    // MARK: Devices

    func refreshDevices() {
        devices = registry.all()
        discovery.setVerifiedFingerprints(Set(devices.compactMap(\.verifiedFingerprint)))
    }

    func refreshLog() { log = registry.recentLog() }

    func refreshDiscovered() { discovered = discovery.discovered }

    /// Adds a phone and returns its PIN, to show to the user.
    func addPhone(named name: String) -> String? {
        guard let (_, pin) = try? registry.addPhone(named: name) else { return nil }
        refreshDevices()
        return pin
    }

    func reissuePIN(for device: PairedDevice) -> String? {
        let pin = try? registry.reissuePIN(for: device.uuid)
        coordinator?.revoke(deviceID: device.uuid)
        refreshDevices()
        return pin
    }

    func pin(for device: PairedDevice) -> String? { registry.pin(for: device.uuid) }

    func remove(_ device: PairedDevice) {
        registry.remove(device.uuid)
        coordinator?.revoke(deviceID: device.uuid)
        refreshDevices()
    }

    func rename(_ device: PairedDevice, to name: String) {
        registry.rename(device.uuid, to: name)
        refreshDevices()
    }

    func forgetVerification(_ device: PairedDevice) {
        registry.setVerifiedFingerprint(nil, for: device.uuid)
        refreshDevices()
    }

    /// Records a fingerprint after the comparison on both screens. Links it
    /// to the paired phone the user picked, or makes a new entry.
    func markVerified(_ discoveredDevice: DiscoveredDevice, as existing: PairedDevice?) {
        if let existing {
            registry.setVerifiedFingerprint(discoveredDevice.fingerprint, for: existing.uuid)
        } else if let device = try? registry.addSendOnlyPhone(named: discoveredDevice.alias) {
            registry.setVerifiedFingerprint(discoveredDevice.fingerprint, for: device.uuid)
        }
        refreshDevices()
    }

    /// Targets for a send: verified devices that are on the network now,
    /// then every other device heard on the network, marked unverified.
    /// Checks the Local Network permission again, after the user changed it.
    func recheckLocalNetwork() {
        localNetwork.recheck()
        discovery.announce()
    }

    /// Announces this Mac, so that devices on the network register with it.
    /// LocalSend answers an announcement with an HTTP register request.
    func announce() { discovery.announce() }

    func sendTargets() -> (verified: [(PairedDevice, DiscoveredDevice)], unverified: [DiscoveredDevice]) {
        refreshDiscovered()
        refreshDevices()
        var verified: [(PairedDevice, DiscoveredDevice)] = []
        var unverified: [DiscoveredDevice] = []
        // Two addresses that claim one fingerprint: at most one is real. Mark
        // neither as verified; the pinned probe before a send tells them apart.
        let claims = Dictionary(grouping: discovered, by: \.fingerprint)
        for d in discovered {
            if claims[d.fingerprint, default: []].count == 1, let paired = devices.first(where: { $0.verifiedFingerprint == d.fingerprint }) {
                verified.append((paired, d))
            } else {
                unverified.append(d)
            }
        }
        return (verified, unverified)
    }

    /// A device at this address did not hold the certificate it announced.
    /// The address is wrong, not the phone: drop the entry, keep the verification.
    /// True when the address sits on the link of an allowed interface now.
    /// Sends go only there, so a send never leaves through a VPN or a route
    /// that a stranger set up.
    func isSendable(_ device: DiscoveredDevice) -> Bool {
        NetworkInterfaces.isOnAllowedLink(device.address, interfaces: NetworkInterfaces.allowed(prefs: prefs))
    }

    func dropDiscovered(_ device: DiscoveredDevice) {
        discovery.remove(id: device.id)
        refreshDiscovered()
    }

    func logSend(device: String, address: String, count: Int, bytes: Int64, outcome: String) {
        registry.log(TransferLogEntry(direction: "out", device: device, address: address, count: count, bytes: bytes, outcome: outcome))
        refreshLog()
    }
}
