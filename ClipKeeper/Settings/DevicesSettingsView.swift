import AppKit
import SwiftUI

/// Settings › Devices: the switch, this Mac's name and fingerprint, the
/// network interfaces, the phones with their PINs, and the transfer log.
struct DevicesSettingsView: View {
    @ObservedObject var transfer: TransferService
    @ObservedObject var prefs: Preferences
    @State private var shownPIN: [String: Bool] = [:]
    @State private var newPhoneName = ""
    @State private var justIssued: (name: String, pin: String)?
    @State private var aliasDraft = ""
    @State private var confirmRemove: PairedDevice?

    var body: some View {
        Form {
            Section {
                Toggle("Send and receive clips with phones and Macs on this network", isOn: Binding(get: { prefs.transferEnabled }, set: { transfer.setEnabled($0) }))
                statusLine
                Text("Local network only. Phones use the LocalSend app; other Macs use ClipKeeper or LocalSend. Every transfer to this Mac needs the sender's PIN, and you accept each one. Received clips never fetch link titles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let warning = transfer.impersonationWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red)
                }
            }
            Section("This Mac") {
                HStack {
                    Text("Name on phones")
                    TextField("", text: $aliasDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitAlias() }
                    Button("Set") { commitAlias() }.disabled(aliasDraft == prefs.transferAlias)
                }
                if let fp = transfer.fingerprint {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fingerprint").font(.caption).foregroundStyle(.secondary)
                        Text(LocalSend.formatFingerprint(fp)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }
                Label("The key lives in this Mac's Secure Enclave and cannot leave it. The PINs are sealed with a key that only this Mac can derive.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                interfacesPicker
            }
            Section("Phones and Macs") {
                if transfer.devices.isEmpty {
                    Text("No devices yet. Add one to get its PIN.").foregroundStyle(.secondary)
                }
                ForEach(transfer.devices) { device in deviceRow(device) }
                HStack {
                    TextField("Device name, such as “My Pixel” or “Work Mac”", text: $newPhoneName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addPhone() }
                    Button("Add Device") { addPhone() }.disabled(newPhoneName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let issued = justIssued {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PIN for \(issued.name):").font(.callout)
                        Text(TransferPIN.display(issued.pin)).font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("The device asks for this PIN when it sends to this Mac. Type it there, with or without the space.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Recent transfers") {
                if transfer.log.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(transfer.log.prefix(12)) { entry in
                    HStack {
                        Image(systemName: entry.direction == "in" ? "arrow.down.circle" : "arrow.up.circle").foregroundStyle(.secondary)
                        Text(entry.device)
                        Text(entry.outcome).foregroundStyle(entry.outcome == "received" || entry.outcome == "sent" ? Color.secondary : Color.orange)
                        Spacer()
                        Text(entry.time, style: .relative).font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            aliasDraft = prefs.transferAlias
            transfer.refreshDevices()
            transfer.refreshLog()
        }
        .confirmationDialog("Remove \(confirmRemove?.name ?? "this phone")?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let d = confirmRemove { transfer.remove(d) }
                confirmRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        } message: {
            Text("Its PIN stops working at once. To send to it again, verify it again.")
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch transfer.state {
        case .off:
            Label("Off", systemImage: "circle").foregroundStyle(.secondary)
        case .running(let addresses):
            Label("On, at \(addresses.joined(separator: ", ")), port \(prefs.transferPort)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .stopped(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label(reason, systemImage: "hand.raised.fill").foregroundStyle(.red)
                Button("Restart") { transfer.restart() }
            }
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var interfacesPicker: some View {
        let eligible = NetworkInterfaces.eligible()
        let chosen = Set(prefs.transferInterfaces)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Networks").font(.caption).foregroundStyle(.secondary)
            if eligible.isEmpty {
                Text("No Wi-Fi or Ethernet connection is active.").foregroundStyle(.secondary)
            }
            ForEach(eligible) { iface in
                Toggle("\(iface.displayName) (\(iface.name), \(iface.addressStrings.joined(separator: ", ")))", isOn: Binding(
                    get: { chosen.isEmpty || chosen.contains(iface.name) },
                    set: { on in
                        var set = chosen.isEmpty ? Set(eligible.map(\.name)) : chosen
                        if on { set.insert(iface.name) } else { set.remove(iface.name) }
                        prefs.transferInterfaces = Array(set).sorted()
                        transfer.startIfEnabled()
                    }))
            }
            Text("VPN, virtual, and cellular connections are never used.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func deviceRow(_ device: PairedDevice) -> some View {
        let pin = transfer.pin(for: device)
        let visible = shownPIN[device.uuid] ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "iphone.and.arrow.forward")
                Text(device.name).font(.body.weight(.medium))
                Spacer()
                Button("New PIN") {
                    if let p = transfer.reissuePIN(for: device) { justIssued = (device.name, p); shownPIN[device.uuid] = true }
                }
                Button("Remove") { confirmRemove = device }
            }
            HStack(spacing: 6) {
                Text("PIN:").foregroundStyle(.secondary)
                if let pin {
                    Text(visible ? TransferPIN.display(pin) : "•••• ••••").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button(visible ? "Hide" : "Show") { shownPIN[device.uuid] = !visible }.buttonStyle(.link)
                } else {
                    Text("none. Press New PIN.").foregroundStyle(.orange)
                }
            }
            .font(.callout)
            HStack(spacing: 6) {
                if device.verifiedFingerprint != nil {
                    Label("Verified for sending", systemImage: "checkmark.shield").foregroundStyle(.green)
                    Button("Forget") { transfer.forgetVerification(device) }.buttonStyle(.link)
                } else {
                    Label("Not verified for sending yet. Send a clip to it with ⌘⇧K to verify it.", systemImage: "shield.slash").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func addPhone() {
        let name = newPhoneName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let pin = transfer.addPhone(named: name) else { return }
        justIssued = (name, pin)
        newPhoneName = ""
    }

    private func commitAlias() {
        prefs.transferAlias = aliasDraft
        aliasDraft = prefs.transferAlias
        transfer.startIfEnabled()
    }
}
