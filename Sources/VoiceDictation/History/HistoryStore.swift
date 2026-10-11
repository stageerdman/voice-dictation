import Foundation

/// One saved dictation. Audio is never kept — only this text record.
struct DictationEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    /// Recording length in seconds.
    let duration: TimeInterval
    /// App the text was inserted into (localized name), if known.
    let targetApp: String?

    init(id: UUID = UUID(), text: String, date: Date, duration: TimeInterval, targetApp: String?) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
        self.targetApp = targetApp
    }
}

/// Persists dictation history as a JSON file in Application Support. Small and
/// append-mostly; a personal tool won't accumulate enough to need a database.
final class HistoryStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "voicedictation.history")
    private(set) var entries: [DictationEntry]

    /// Default location: ~/Library/Application Support/VoiceDictation/history.json
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.entries = HistoryStore.load(from: fileURL)
    }

    private static func load(from url: URL) -> [DictationEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DictationEntry].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Newest-first for display.
    func add(_ entry: DictationEntry) {
        queue.sync {
            entries.insert(entry, at: 0)
            persist()
        }
    }

    func delete(id: UUID) {
        queue.sync {
            entries.removeAll { $0.id == id }
            persist()
        }
    }

    func clear() {
        queue.sync {
            entries.removeAll()
            persist()
        }
    }
}
