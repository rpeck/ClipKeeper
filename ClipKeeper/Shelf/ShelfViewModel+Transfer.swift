import Foundation

/// The send flow in the shelf: pick a device, verify it once, send, and
/// answer a PIN prompt when the phone asks for one. All keyboard.
extension ShelfViewModel {
    func showSendPicker(for clips: [Clip]) {
        guard let transfer else { return }
        guard transfer.isEnabled, case .running = transfer.state else {
            showToast("Turn on phone transfer in Settings › Devices")
            return
        }
        let items = TransferSender.items(for: clips, store: store)
        guard !items.isEmpty else {
            showToast("Files clips cannot go to a phone yet")
            return
        }
        let targets = transfer.sendTargets()
        guard !targets.verified.isEmpty || !targets.unverified.isEmpty else {
            showToast("No phone found. Open LocalSend on the phone, on the same Wi-Fi.")
            return
        }
        var pickerItems: [PickerItem] = []
        for (paired, found) in targets.verified {
            pickerItems.append(PickerItem(id: "v:" + found.id, title: paired.name, subtitle: "Verified · \(found.address)", symbol: "checkmark.shield"))
        }
        for found in targets.unverified {
            let model = found.deviceModel.map { " · \($0)" } ?? ""
            pickerItems.append(PickerItem(id: "u:" + found.id, title: found.alias, subtitle: "Not verified\(model) · \(found.address)", symbol: "questionmark.circle"))
        }
        overlaySelection = 0
        let count = items.count
        overlay = .picker(title: count == 1 ? "Send to…" : "Send \(count) items to…", items: pickerItems) { [weak self] item in
            guard let self else { return }
            if item.id.hasPrefix("v:"), let pair = targets.verified.first(where: { "v:" + $0.1.id == item.id }) {
                self.send(items, to: pair.1, name: pair.0.name, pin: nil)
            } else if let found = targets.unverified.first(where: { "u:" + $0.id == item.id }) {
                self.verify(found, then: items)
            }
        }
    }

    /// Proves that the device holds the certificate it announced, then shows
    /// the combined fingerprint for comparison with the phone's Verify page.
    private func verify(_ device: DiscoveredDevice, then items: [OutgoingItem]) {
        guard let transfer, let mine = transfer.fingerprint else { return }
        guard transfer.isSendable(device) else { return showToast("That device is not on an allowed network") }
        let sender = TransferSender(address: device.address, port: device.port, fingerprint: device.fingerprint)
        overlay = .progress(title: "Connecting to \(device.alias)…") { [weak self] in self?.sendTask?.cancel() }
        sendTask = Task { @MainActor [weak self] in
            do {
                _ = try await sender.probe()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.overlay = nil
                self.showToast((error as? SendError)?.message ?? "The device did not answer")
                return
            }
            guard let self, !Task.isCancelled else { return }
            let code = TransferSender.combinedFingerprint(mine, device.fingerprint)
            let message = "On the phone, open LocalSend. Tap this Mac in the device list, then Verify, then Text. Compare all of the characters. Send only if they match."
            self.overlay = .verify(title: "Verify \(device.alias)", message: message, code: code) { [weak self] in
                self?.chooseRecord(for: device, then: items)
            }
        }
    }

    /// Links the verified fingerprint to a phone the user already added, or to a new entry.
    private func chooseRecord(for device: DiscoveredDevice, then items: [OutgoingItem]) {
        guard let transfer else { return }
        let candidates = transfer.devices.filter { $0.verifiedFingerprint == nil }
        let finish: (PairedDevice?) -> Void = { [weak self] existing in
            transfer.markVerified(device, as: existing)
            self?.send(items, to: device, name: existing?.name ?? device.alias, pin: nil)
        }
        guard !candidates.isEmpty else { return finish(nil) }
        var pickerItems = candidates.map { PickerItem(id: $0.uuid, title: $0.name, subtitle: "Already added in Settings", symbol: "iphone") }
        pickerItems.append(PickerItem(id: "__new__", title: "A new device: \(device.alias)", symbol: "plus"))
        overlaySelection = 0
        overlay = .picker(title: "Which device is this?", items: pickerItems) { item in
            finish(candidates.first { $0.uuid == item.id })
        }
    }

    private func send(_ items: [OutgoingItem], to device: DiscoveredDevice, name: String, pin: String?) {
        guard let transfer, let info = transfer.ownInfo else { return }
        guard transfer.isSendable(device) else { return showToast("That device is not on an allowed network") }
        let sender = TransferSender(address: device.address, port: device.port, fingerprint: device.fingerprint)
        let bytes = Int64(items.reduce(0) { $0 + $1.data.count })
        overlay = .progress(title: "Sending to \(name)…") { [weak self] in
            self?.sendTask?.cancel()
            Task { await sender.cancel() }
        }
        sendTask = Task { @MainActor [weak self] in
            do {
                let outcome = try await sender.send(items, from: info, pin: pin)
                guard let self, !Task.isCancelled else { return }
                switch outcome {
                case .sent:
                    self.overlay = nil
                    transfer.logSend(device: name, address: device.address, count: items.count, bytes: bytes, outcome: "sent")
                    self.showToast("Sent to \(name)")
                case .needsPIN:
                    self.askPhonePIN(items, to: device, name: name)
                }
            } catch {
                guard let self else { return }
                let sendError = (error as? SendError) ?? .network
                if Task.isCancelled || sendError == .cancelled {
                    transfer.logSend(device: name, address: device.address, count: items.count, bytes: 0, outcome: "cancelled")
                    return
                }
                self.overlay = nil
                if sendError == .fingerprintMismatch {
                    // Something at this address claimed the phone's fingerprint. The
                    // address is wrong, not the phone: keep the verification.
                    transfer.dropDiscovered(device)
                }
                transfer.logSend(device: name, address: device.address, count: items.count, bytes: 0, outcome: "failed")
                self.showToast(sendError.message)
            }
        }
    }

    /// The phone has a receive PIN. Ask for it. The PIN goes only to this
    /// verified device, over the pinned connection, and is not stored.
    private func askPhonePIN(_ items: [OutgoingItem], to device: DiscoveredDevice, name: String) {
        promptText = ""
        overlay = .prompt(title: "PIN for \(name)", placeholder: "The PIN that LocalSend on the phone uses", initial: "") { [weak self] pin in
            let clean = pin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            self?.send(items, to: device, name: name, pin: clean)
        }
    }
}
