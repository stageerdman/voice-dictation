import AppKit
import SwiftUI

/// Which surface the window is showing. The window hosts both History and the
/// activity/error Log behind a single segmented switcher.
enum WindowMode: String, CaseIterable, Identifiable {
    case history, log
    var id: String { rawValue }
    var title: String { self == .history ? "History" : "Log" }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    init(store: HistoryStore, log: LogStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Voice Dictator"
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 520, height: 400)
        window.center()
        super.init(window: window)
        let root = HistoryWindowRoot(
            historyModel: HistoryModel(store: store),
            logModel: LogModel(store: log),
            onReinsert: { [weak self] text in self?.reinsert(text) }
        )
        let hosting = NSHostingController(rootView: root)
        window.contentViewController = hosting
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

/// Top-level window content: the History ↔ Log switcher plus the shared chrome
/// (search field, bottom footnote). The segmented switcher lives in the window
/// toolbar; Log-only actions and the active search prompt follow the mode.
struct HistoryWindowRoot: View {
    @ObservedObject var historyModel: HistoryModel
    @ObservedObject var logModel: LogModel
    let onReinsert: (String) -> Void

    @State private var mode: WindowMode = .history
    /// Set once the user has looked at the Log this session, so the unseen-error
    /// dot stops nagging after they've seen it.
    @State private var sawLog = false
    @State private var confirmingClear = false

    private var showErrorDot: Bool { !sawLog && mode != .log && logModel.hasErrors }

    var body: some View {
        content
            .frame(minWidth: 520, minHeight: 400)
            .searchable(text: activeSearch, placement: .toolbar,
                        prompt: mode == .history ? "Search dictations" : "Search log")
            .safeAreaInset(edge: .bottom) { privacyFootnote }
            .toolbar {
                ToolbarItem(placement: .principal) { switcher }
                if mode == .log { logToolbar }
            }
            .onChange(of: mode) { _, newValue in if newValue == .log { sawLog = true } }
            .confirmationDialog("Clear the log?", isPresented: $confirmingClear) {
                Button("Clear Log", role: .destructive) { logModel.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all logged events. It can't be undone.")
            }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .history: HistoryView(model: historyModel, onReinsert: onReinsert)
        case .log:     LogView(model: logModel)
        }
    }

    private var switcher: some View {
        Picker("View", selection: $mode) {
            ForEach(WindowMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .overlay(alignment: .topTrailing) {
            if showErrorDot {
                Circle().fill(.red).frame(width: 7, height: 7).offset(x: 3, y: -3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(showErrorDot ? "unseen errors in Log" : "")
    }

    @ToolbarContentBuilder private var logToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Filter by level", selection: $logModel.filter) {
                    ForEach(LevelFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: logModel.filter == .all
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Filter by level")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { copyAll() } label: { Label("Copy All", systemImage: "doc.on.doc") }
                Button { NSWorkspace.shared.activateFileViewerSelecting([logModel.logFileURL]) } label: {
                    Label("Reveal Log File in Finder", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) { confirmingClear = true } label: {
                    Label("Clear Log…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More")
        }
    }

    private var activeSearch: Binding<String> {
        mode == .history ? $historyModel.search : $logModel.search
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logModel.copyableText(), forType: .string)
    }

    private var privacyFootnote: some View {
        Text("History & log store text only. Audio is deleted the moment it's transcribed — it never leaves your Mac.")
            .font(.footnote).foregroundStyle(.tertiary)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
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
                if !entry.inserted {
                    Text("Not inserted")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                        .help("This transcription wasn't pasted — copy or re-insert it from here.")
                }
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
        .accessibilityLabel("\(entry.text). \(metadata)\(entry.inserted ? "" : ". Not inserted")")
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
            Text("Hold ⌘⌃ anywhere, speak, and release. Your words land at the cursor — and show up here.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
