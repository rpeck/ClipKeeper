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
