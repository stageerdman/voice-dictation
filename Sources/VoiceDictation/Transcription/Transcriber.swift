import Foundation

/// Turns a recorded audio file into text. Implementations are swappable behind
/// this interface so the backend (on-device sidecar, cloud) is a settings choice.
protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, model: TranscriptionModel, language: String) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case sidecarUnavailable(String)
    case failed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .sidecarUnavailable(let d): return "Transcription engine unavailable: \(d)"
        case .failed(let d): return d
        case .empty: return "No speech heard"
        }
    }
}

/// Routes to the on-device Python sidecar for local models and to Groq for the
/// cloud model, keeping the choice behind the `Transcriber` interface.
final class RoutingTranscriber: Transcriber {
    private let sidecar: SidecarTranscriber
    private let groq: GroqTranscriber

    init(sidecar: SidecarTranscriber = SidecarTranscriber(), groq: GroqTranscriber = GroqTranscriber()) {
        self.sidecar = sidecar
        self.groq = groq
    }

    func transcribe(audioURL: URL, model: TranscriptionModel, language: String) async throws -> String {
        if model.isCloud {
            return try await groq.transcribe(audioURL: audioURL, model: model, language: language)
        }
        return try await sidecar.transcribe(audioURL: audioURL, model: model, language: language)
    }
}
