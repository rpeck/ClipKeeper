import AppKit
import SwiftUI

/// Owns the window that lists where the stored clips came from, so that
/// the user can find clips that reached this Mac from other devices.
@MainActor
final class AuditWindowController {
    private var window: NSWindow?
    private let store: ClipStore
    /// Shows the shelf with a filter.
    private let showInShelf: (ClipFilter) -> Void

    init(store: ClipStore, showInShelf: @escaping (ClipFilter) -> Void) {
        self.store = store
        self.showInShelf = showInShelf
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Clips from Other Devices"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AuditView(store: store, showInShelf: showInShelf))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AuditView: View {
    @ObservedObject var store: ClipStore
    let showInShelf: (ClipFilter) -> Void
    @State private var summaries: [SourceSummary] = []
    @State private var thisMacCount = 0
    @State private var personalCount = 0
    @State private var pendingDelete: SourceSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clips from other devices")
                    .font(.headline)
                Text("Each row is a device that put clips into ClipKeeper on this Mac: a phone or Mac that sent clips, or Universal Clipboard. Use this list to find clips that must not be here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Divider()

            if summaries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("No stored clip came from another device.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(summaries) { summary in
                    row(summary)
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(thisMacCount == 1 ? "1 clip was copied on this Mac." : "\(thisMacCount) clips were copied on this Mac.")
                    Spacer()
                }
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.red.opacity(0.75))
                    Text(personalCount == 1 ? "1 clip, from any source, has possible personal data." : "\(personalCount) clips, from any source, have possible personal data.")
                    Spacer()
                    Button("Show in Shelf") { showInShelf(ClipFilter(source: .all, personalOnly: true)) }
                        .disabled(personalCount == 0)
                }
                Text("ClipKeeper finds possible personal data with patterns, on this Mac only: email addresses, phone numbers, postal addresses, card numbers, Social Security numbers, IBANs, and keys or tokens. Patterns miss some data and flag some harmless text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 380)
        .onAppear { refresh() }
        .onReceive(store.$changeToken) { _ in refresh() }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let summary = pendingDelete { store.delete(store.clips(from: summary.key)) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This includes pinned clips and clips in collections. You cannot undo this.")
        }
    }

    private var deleteTitle: String {
        guard let summary = pendingDelete else { return "" }
        return summary.count == 1 ? "Delete the clip from \(summary.name)?" : "Delete all \(summary.count) clips from \(summary.name)?"
    }

    private func row(_ summary: SourceSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.isHandoff ? "laptopcomputer.and.iphone" : "iphone.and.arrow.forward")
                .foregroundStyle(summary.isHandoff ? Color.purple : Color.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name).font(.body.weight(.medium))
                Text(countLine(summary))
                    .font(.caption)
                    .foregroundStyle(summary.personalCount > 0 ? Color.red.opacity(0.85) : Color.secondary)
                Text(dateLine(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !summary.kinds.isEmpty {
                    Text(summary.kinds.map(\.displayName).sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button("Show in Shelf") { showInShelf(ClipFilter(source: .device(summary.key))) }
                Button("Delete All…", role: .destructive) { pendingDelete = summary }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func countLine(_ summary: SourceSummary) -> String {
        let clips = summary.count == 1 ? "1 clip" : "\(summary.count) clips"
        guard summary.personalCount > 0 else { return clips }
        return "\(clips), \(summary.personalCount) with possible personal data"
    }

    private func dateLine(_ summary: SourceSummary) -> String {
        let first = summary.first.formatted(date: .abbreviated, time: .shortened)
        let last = summary.last.formatted(date: .abbreviated, time: .shortened)
        return first == last ? first : "\(first) to \(last)"
    }

    private func refresh() {
        summaries = store.sourceSummaries()
        thisMacCount = store.thisMacCount()
        personalCount = store.personalDataCount()
    }
}
