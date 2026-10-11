import Foundation

/// Reads optional API keys. Both default paths are honored so the app works
/// with no secrets: the environment first (how a shipped app would inject them),
/// then a `.env` file in the dev working tree. Keys are never written anywhere.
final class Secrets: Sendable {
    static let shared = Secrets()

    private let values: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         dotEnvURL: URL? = Secrets.defaultDotEnvURL()) {
        var merged = Secrets.parseDotEnv(dotEnvURL)
        // Environment wins over .env.
        for (k, v) in environment { merged[k] = v }
        values = merged
    }

    var groqAPIKey: String? { nonEmpty("GROQ_API_KEY") }
    var anthropicAPIKey: String? { nonEmpty("ANTHROPIC_API_KEY") }

    var hasGroqKey: Bool { groqAPIKey != nil }
    var hasAnthropicKey: Bool { anthropicAPIKey != nil }

    private func nonEmpty(_ key: String) -> String? {
        guard let v = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    private static func defaultDotEnvURL() -> URL? {
        let dev = ("~/dev/voice-dictation/.env" as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: dev) ? URL(fileURLWithPath: dev) : nil
    }

    private static func parseDotEnv(_ url: URL?) -> [String: String] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }
}
