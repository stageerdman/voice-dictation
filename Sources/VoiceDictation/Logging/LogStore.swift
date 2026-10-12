import Foundation

/// Severity of a logged event. Ordered so `>=` filtering works (error is highest).
enum LogLevel: String, Codable, CaseIterable, Comparable {
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Where in the pipeline an event originated — lets the log read at a glance and
/// map a failure to one obvious home (matches the CODING.md module boundaries).
enum LogCategory: String, Codable, CaseIterable {
    case system        // launch, lifecycle
    case permission    // Accessibility / Microphone / Input Monitoring grants
    case hotkey
    case audio         // recording
    case transcription
    case cleanup
    case insertion
    case sidecar       // raw sidecar stderr
}

/// One logged event. Durable text record only — never any audio.
struct LogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    /// Optional longer context (an error's full description, a stderr line, …).
    let detail: String?

    init(id: UUID = UUID(), date: Date = Date(), level: LogLevel,
         category: LogCategory, message: String, detail: String? = nil) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }
}

/// Persists a rolling app log as JSON in Application Support, alongside history.
/// Thread-safe and append-mostly; capped so a long-running personal tool never
/// grows without bound. The point is diagnosis: when a dictation "records but no
/// text appears", the failing stage is written here instead of flashing for a
/// second in the menu bar and vanishing.
final class LogStore: @unchecked Sendable {
    /// Shared sink so any module can log without threading an instance through.
    static let shared = LogStore()

    /// Newest-first for display.
    private(set) var entries: [LogEntry]

    /// Keep the log bounded — a personal tool won't need more history than this.
    private let cap = 500

    private let fileURL: URL
    private let queue = DispatchQueue(label: "voicedictation.log")

    /// Fires (on the main queue) after any mutation so an open window can refresh.
    var onChange: (() -> Void)?

    /// Default location: ~/Library/Application Support/VoiceDictation/log.json
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("log.json")
    }

    init(fileURL: URL = LogStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.entries = LogStore.load(from: fileURL)
    }

    /// The on-disk file, for "Reveal in Finder".
    var logFileURL: URL { fileURL }

    // MARK: - Writing

    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, detail: String? = nil) {
        let entry = LogEntry(level: level, category: category, message: message, detail: detail)
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.cap { self.entries.removeLast(self.entries.count - self.cap) }
            self.persist()
            DispatchQueue.main.async { self.onChange?() }
        }
    }

    func info(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.info, category, message, detail: detail)
    }

    func warning(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.warning, category, message, detail: detail)
    }

    func error(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.error, category, message, detail: detail)
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.removeAll()
            self.persist()
            DispatchQueue.main.async { self.onChange?() }
        }
    }

    /// Blocks until all queued writes have been applied. For tests and orderly
    /// shutdown — writes are async on the hot path to avoid adding dictation lag.
    func flush() { queue.sync {} }

    // MARK: - Persistence

    private static func load(from url: URL) -> [LogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LogEntry].self, from: data)) ?? []
    }

    /// Must be called on `queue`.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
