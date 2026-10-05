import Foundation
import Network

/// Watches the macOS Local Network permission for ClipKeeper.
///
/// macOS has no API that reports this permission. While it is off, macOS
/// drops multicast from the app without an error, so phones and Macs never
/// hear this Mac. A Bonjour browse does report it: the browser waits with the
/// error "policy denied". The browse also makes macOS show the permission
/// prompt, which raw sockets do not reliably do.
///
/// The browse looks for ClipKeeper's own service type and reads nothing from
/// the results; it exists only for this check.
@MainActor
final class LocalNetworkAccess {
    enum State: Equatable {
        case unknown
        case allowed
        case denied
    }

    static let serviceType = "_clipkeeper._tcp"

    /// Called on the main thread when the state changes.
    var onChange: (State) -> Void = { _ in }
    private(set) var state: State = .unknown
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: "local."), using: parameters)
        browser.stateUpdateHandler = { [weak self] newState in
            let mapped: State
            switch newState {
            case .ready:
                mapped = .allowed
            case .waiting(let error), .failed(let error):
                mapped = Self.isPolicyDenied(error) ? .denied : .unknown
            default:
                return
            }
            Task { @MainActor in self?.update(mapped) }
        }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Starts the browse again, for example after the user changed the permission.
    func recheck() {
        stop()
        state = .unknown
        start()
    }

    private func update(_ newState: State) {
        guard newState != state else { return }
        state = newState
        NSLog("transfer: local network permission: %@", String(describing: newState))
        onChange(newState)
    }

    nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }
}
