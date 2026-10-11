import Foundation

enum CleanerError: LocalizedError {
    case noKey(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noKey(let k): return "\(k) not set"
        case .requestFailed(let d): return d
        }
    }
}

/// Fast cloud cleanup via Groq's OpenAI-compatible chat completions.
struct GroqCleaner: TextCleaner {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let model = "llama-3.3-70b-versatile"

    func clean(_ text: String) async throws -> String {
        guard let key = Secrets.shared.groqAPIKey else { throw CleanerError.noKey("GROQ_API_KEY") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": CleanupPrompt.system],
                ["role": "user", "content": CleanupPrompt.user(text)],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CleanerError.requestFailed(String(data: data, encoding: .utf8) ?? "Groq cleanup failed")
        }
        struct Resp: Decodable { struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }; let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.choices.first?.message.content ?? text
    }
}

/// Highest-quality cleanup via the Claude Messages API (Haiku for speed).
struct ClaudeCleaner: TextCleaner {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    func clean(_ text: String) async throws -> String {
        guard let key = Secrets.shared.anthropicAPIKey else { throw CleanerError.noKey("ANTHROPIC_API_KEY") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 2048,
            "temperature": 0,
            "system": CleanupPrompt.system,
            "messages": [
                ["role": "user", "content": CleanupPrompt.user(text)],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CleanerError.requestFailed(String(data: data, encoding: .utf8) ?? "Claude cleanup failed")
        }
        struct Resp: Decodable { struct Block: Decodable { let type: String; let text: String? }; let content: [Block] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        let joined = decoded.content.compactMap { $0.text }.joined()
        return joined.isEmpty ? text : joined
    }
}
