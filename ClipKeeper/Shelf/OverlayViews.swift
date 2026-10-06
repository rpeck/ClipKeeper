import SwiftUI

/// Dims the shelf and shows the active overlay: a picker, a prompt, or a confirmation.
struct OverlayHost: View {
    @ObservedObject var model: ShelfViewModel
    let overlay: ShelfViewModel.Overlay

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { model.overlay = nil }
            Group {
                switch overlay {
                case .picker(let title, let items, let onChoose):
                    PickerOverlay(model: model, title: title, items: items) { item in
                        model.overlay = nil
                        onChoose(item)
                    }
                case .prompt(let title, let placeholder, _, let onCommit):
                    PromptOverlay(model: model, title: title, placeholder: placeholder) { text in
                        model.overlay = nil
                        onCommit(text)
                    }
                case .confirm(let title, let message, let confirmTitle, let onConfirm):
                    ConfirmOverlay(model: model, title: title, message: message, confirmTitle: confirmTitle) {
                        model.overlay = nil
                        onConfirm()
                    }
                case .verify(let title, let message, let code, let onConfirm):
                    VerifyOverlay(model: model, title: title, message: message, code: code) {
                        model.overlay = nil
                        onConfirm()
                    }
                case .message(let title, let message):
                    MessageOverlay(model: model, title: title, message: message)
                case .progress(let title, let onCancel):
                    ProgressOverlay(title: title) {
                        model.overlay = nil
                        onCancel()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
            .padding(24)
        }
    }
}

struct PickerOverlay: View {
    @ObservedObject var model: ShelfViewModel
    let title: String
    let items: [PickerItem]
    let onChoose: (PickerItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let selected = index == model.overlaySelection
                    HStack(spacing: 8) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).frame(width: 16).foregroundStyle(selected ? Color.accentColor : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                            if let sub = item.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if index < 9 {
                            Text("\(index + 1)").font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { onChoose(item) }
                    .onHover { if $0 { model.overlaySelection = index } }
                }
            }
            HintRow(hints: [("↑↓", "Choose"), ("⏎", "Select"), ("esc", "Cancel")])
        }
    }
}

struct PromptOverlay: View {
    @ObservedObject var model: ShelfViewModel
    let title: String
    let placeholder: String
    let onCommit: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField(placeholder, text: $model.promptText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onCommit(model.promptText) }
            HintRow(hints: [("⏎", "Save"), ("esc", "Cancel")])
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

struct ConfirmOverlay: View {
    @ObservedObject var model: ShelfViewModel
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.overlay = nil }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive) { onConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
            HintRow(hints: [("⏎", confirmTitle), ("esc", "Cancel")])
        }
    }
}

/// The comparison screen: the combined fingerprint in groups of four, as
/// LocalSend shows it on its Verify page in text mode.
struct VerifyOverlay: View {
    @ObservedObject var model: ShelfViewModel
    let title: String
    let message: String
    let code: String
    let onConfirm: () -> Void

    private var rows: [String] {
        let groups = stride(from: 0, to: code.count, by: 4).map { i -> String in
            let start = code.index(code.startIndex, offsetBy: i)
            let end = code.index(start, offsetBy: min(4, code.count - i))
            return String(code[start..<end])
        }
        return stride(from: 0, to: groups.count, by: 4).map { groups[$0..<min($0 + 4, groups.count)].joined(separator: " ") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(.system(size: 13, design: .monospaced))
                }
            }
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("They differ") {
                    NSLog("send: verify: the user said the characters differ")
                    model.overlay = nil
                }
                    .keyboardShortcut(.cancelAction)
                Button("They match") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
            }
            HintRow(hints: [("⏎", "They match"), ("esc", "They differ")])
        }
    }
}

struct MessageOverlay: View {
    @ObservedObject var model: ShelfViewModel
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack {
                Spacer()
                Button("OK") { model.overlay = nil }.keyboardShortcut(.defaultAction)
            }
            HintRow(hints: [("⏎", "OK")])
        }
    }
}

struct ProgressOverlay: View {
    let title: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(title).font(.headline)
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
            }
            HintRow(hints: [("esc", "Cancel")])
        }
    }
}

/// A row of key hints, like "⏎ Select   ⎋ Cancel".
struct HintRow: View {
    let hints: [(String, String)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in
                HStack(spacing: 4) {
                    Text(h.0).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    Text(h.1).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
        .padding(.top, 2)
    }
}
