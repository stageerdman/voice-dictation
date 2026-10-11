import AVFoundation

/// Captures the microphone to a temporary WAV file while the hotkey is held.
/// Exposes a live input level (0...1) so the UI can draw a waveform. The caller
/// owns the returned file and must delete it once transcription succeeds.
final class AudioRecorder {
    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private(set) var isRecording = false

    /// Most recent input level in 0...1 (RMS-derived), for the HUD meter.
    private(set) var level: Float = 0

    /// Called on the audio thread with each new level sample; hop to main in UI.
    var onLevel: ((Float) -> Void)?

    enum RecorderError: Error { case couldNotCreateFile(Error), engineFailed(Error) }

    func start() throws {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedictation-\(UUID().uuidString).wav")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            throw RecorderError.couldNotCreateFile(error)
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            let lvl = AudioRecorder.rms(buffer)
            self.level = lvl
            self.onLevel?(lvl)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            throw RecorderError.engineFailed(error)
        }

        startTime = Date()
        isRecording = true
    }

    /// Stops capture and returns the finished file plus its duration.
    @discardableResult
    func stop() -> Recording? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let url = audioFile?.url
        audioFile = nil
        startTime = nil
        guard let url else { return nil }
        return Recording(url: url, duration: duration)
    }

    /// Normalized RMS level mapped to a perceptual 0...1 range for metering.
    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        let channel = data[0]
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = (sum / Float(frames)).squareRoot()
        // Map ~-50dB..0dB to 0..1 so quiet speech still moves the meter.
        let db = 20 * log10(max(rms, 1e-7))
        let clamped = max(-50, min(0, db))
        return (clamped + 50) / 50
    }
}
