import AppKit
import SwiftUI

/// Level filter for the Log view. Default `.all` so a failure is never hidden
/// behind a too-narrow filter (an "Accessibility not granted" line is a warning,
/// not always an error).
enum LevelFilter: String, CaseIterable, Identifiable {
    case all
    case warningsAndErrors
    case errorsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:               return "All"
        case .warningsAndErrors: return "Warnings & Errors"
        case .errorsOnly:        return "Errors"
        }
    }

    func includes(_ level: LogLevel) -> Bool {
        switch self {
        case .all:               return true
        case .warningsAndErrors: return level >= .warning
        case .errorsOnly:        return level == .error
        }
    }

    /// Message shown when this filter hides everything but the log isn't empty.
    var emptyMessage: String {
        switch self {
        case .all:               return "No events logged."
        case .warningsAndErrors: return "No warnings or errors logged."
        case .errorsOnly:        return "No errors logged."
        }
    }
}

@MainActor
final class LogModel: ObservableObject {
    @Published private(set) var entries: [LogEntry]
    @Published var search = ""
    @Published var filter: LevelFilter = .all

    private let store: LogStore

    init(store: LogStore) {
        self.store = store
        self.entries = store.entries
        store.onChange = { [weak self] in
            guard let self else { return }
            self.entries = store.entries
        }
    }

    /// Whether any error exists — drives the unseen-error dot on the switcher.
    var hasErrors: Bool { entries.contains { $0.level == .error } }

    private var matching: [LogEntry] {
        entries.filter { entry in
            guard filter.includes(entry.level) else { return false }
            guard !search.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(search)
                || entry.category.rawValue.localizedCaseInsensitiveContains(search)
                || (entry.detail?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Day-grouped sections (newest first), matching History's grouping.
    var sections: [(title: String, entries: [LogEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: matching) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (Self.sectionTitle(day), groups[day]!.sorted { $0.date > $1.date })
        }
    }

    func clear() {
        store.clear()
        entries = store.entries
    }

    var logFileURL: URL { store.logFileURL }

    /// Plain-text dump of the currently visible (filtered/searched) lines.
    func copyableText() -> String {
        matching.map(Self.line).joined(separator: "\n")
    }

    static func line(_ e: LogEntry) -> String {
        var s = "\(Self.stamp.string(from: e.date))  [\(e.level.rawValue.uppercased())]  \(e.category.rawValue)  \(e.message)"
        if let d = e.detail, !d.isEmpty { s += "  — \(d)" }
        return s
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    private static func sectionTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .weekOfYear)
            ? "EEEE, MMM d" : "MMMM d, yyyy"
        return f.string(from: day)
    }
}

struct LogView: View {
    @ObservedObject var model: LogModel

    var body: some View {
        Group {
            if model.isEmpty {
                EmptyLog(filtered: false, message: "Dictation activity and any errors will show up here.")
            } else if model.sections.allSatisfy({ $0.entries.isEmpty }) || model.sections.isEmpty {
                EmptyLog(filtered: true, message: model.filter.emptyMessage)
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(model.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct LogRow: View {
    let entry: LogEntry
    @State private var expanded = false

    private var expandable: Bool { (entry.detail?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.glyph(entry.level))
                    .foregroundStyle(Self.tint(entry.level))
                    .frame(width: 16, alignment: .center)
                    .font(.system(size: 13))
                Text(Self.time.string(from: entry.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                CategoryPill(entry.category)
                Text(entry.message)
                    .font(.system(size: 13))
                    .foregroundStyle(entry.level == .info ? .secondary : .primary)
                    .lineLimit(expanded ? nil : 1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if expandable {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            if expanded, let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11.5).monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if expandable { expanded.toggle() } }
        .contextMenu {
            Button("Copy Line") { copy(LogModel.line(entry)) }
            if let d = entry.detail, !d.isEmpty {
                Button("Copy Detail") { copy(d) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue), \(entry.category.rawValue), \(Self.time.string(from: entry.date)), \(entry.message)")
        .accessibilityHint(expandable ? "Double-tap to show detail" : "")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func glyph(_ level: LogLevel) -> String {
        switch level {
        case .error:   return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle"
        }
    }

    private static func tint(_ level: LogLevel) -> Color {
        switch level {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .secondary
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

/// Small category tag — scannable without competing with the message.
private struct CategoryPill: View {
    let category: LogCategory
    init(_ category: LogCategory) { self.category = category }

    var body: some View {
        Text(category.rawValue.capitalized)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .fixedSize()
    }
}

private struct EmptyLog: View {
    let filtered: Bool
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: filtered ? "line.3.horizontal.decrease.circle" : "checkmark.seal")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(filtered ? "No matching events" : "No events yet").fontWeight(.medium)
            Text(message)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
