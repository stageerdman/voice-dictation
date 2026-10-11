import Foundation

/// On-device transcription via the shared warm MLX sidecar.
final class SidecarTranscriber: Transcriber, @unchecked Sendable {
    private let sidecar: MLXSidecar

    init(sidecar: MLXSidecar = .shared) {
        self.sidecar = sidecar
    }

    func transcribe(audioURL: URL, model: TranscriptionModel, language: String) async throws -> String {
        let text = try await sidecar.send([
            "op": "transcribe",
            "audio_path": audioURL.path,
            "model": model.backendID,
            "language": language,
        ])
        guard !text.isEmpty else { throw TranscriptionError.empty }
        return text
    }
}
