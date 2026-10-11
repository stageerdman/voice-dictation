import Foundation

/// Optional cloud fast path: Groq's hosted Whisper. Only usable when a Groq API
/// key is present (env `GROQ_API_KEY`, loaded from `.env` in dev). Uploads the
/// WAV as multipart form data to the OpenAI-compatible transcription endpoint.
final class GroqTranscriber: Transcriber, @unchecked Sendable {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var apiKey: String? {
        Secrets.shared.groqAPIKey
    }

    func transcribe(audioURL: URL, model: TranscriptionModel, language: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw TranscriptionError.sidecarUnavailable("no GROQ_API_KEY set")
        }
        let audio = try Data(contentsOf: audioURL)

        let boundary = "voicedictation-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-large-v3-turbo")
        if language == "en" || !language.isEmpty { field("language", language) }
        field("response_format", "json")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw TranscriptionError.failed("Groq request failed: \(detail)")
        }

        struct Result: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(Result.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.empty }
        return text
    }
}
