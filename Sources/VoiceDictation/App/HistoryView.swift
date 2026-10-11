import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    init(store: HistoryStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "History"
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 520, height: 400)
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: HistoryView(
            model: HistoryModel(store: store),
            onReinsert: { [weak self] text in self?.reinsert(text) }
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    /// Re-insert hides the window, lets the previous app regain focus, then runs
    /// the same insertion path as live dictation.
    private func reinsert(_ text: String) {
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            try? TextInserter().insert(text)
        }
    }
}

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var entries: [DictationEntry]
    @Published var search = ""
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
        self.entries = store.entries
    }

    var filtered: [DictationEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    /// Day-grouped sections (newest first). Collapsed to a flat list while searching.
    var sections: [(title: String, entries: [DictationEntry])] {
        if !search.isEmpty { return [("", filtered)] }
        let cal = Calendar.current
        let groups = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (Self.sectionTitle(day), groups[day]!.sorted { $0.date > $1.date })
        }
    }

    func delete(_ entry: DictationEntry) {
        store.delete(id: entry.id)
        entries = store.entries
    }

    private static func sectionTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .weekOfYear)
            ? "EEEE, MMM d" : "MMMM yyyy"
        return f.string(from: day)
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let onReinsert: (String) -> Void

    var body: some View {
        Group {
            if model.entries.isEmpty {
                EmptyHistory()
            } else {
                list
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search dictations")
        .safeAreaInset(edge: .bottom) { privacyFootnote }
    }

    private var list: some View {
        List {
            ForEach(model.sections, id: \.title) { section in
                Section(section.title.isEmpty ? "Results" : section.title) {
                    ForEach(section.entries) { entry in
                        HistoryRow(entry: entry,
                                   onCopy: { copy(entry.text) },
                                   onReinsert: { onReinsert(entry.text) },
                                   onDelete: { model.delete(entry) })
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var privacyFootnote: some View {
        Text("History stores text only. Audio is deleted the moment it's transcribed — it never leaves your Mac.")
            .font(.footnote).foregroundStyle(.tertiary)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    let entry: DictationEntry
    let onCopy: () -> Void
    let onReinsert: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(expanded ? nil : 1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(metadata).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if hovering {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy")
                    Button(action: onReinsert) { Image(systemName: "arrow.down.to.line") }
                        .buttonStyle(.borderless).help("Re-insert at cursor")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Re-insert at Cursor", action: onReinsert)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.text). \(metadata)")
    }

    private var metadata: String {
        var parts = [Self.time.string(from: entry.date), Self.duration(entry.duration)]
        if let app = entry.targetApp { parts.append(app) }
        return parts.joined(separator: " · ")
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct EmptyHistory: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No dictations yet").fontWeight(.medium)
            Text("Hold ⌘⌥ anywhere, speak, and release. Your words land at the cursor — and show up here.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
