import AudioToolbox
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

    /// True after the most recent `start()` if the preferred input device
    /// (from Settings) wasn't found — i.e. it disconnected — and recording
    /// silently fell back to the system default instead.
    private(set) var didFallBackToDefaultDevice = false

    enum RecorderError: Error { case couldNotCreateFile(Error), engineFailed(Error) }

    func start() throws {
        guard !isRecording else { return }
        didFallBackToDefaultDevice = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedictation-\(UUID().uuidString).wav")
        let input = engine.inputNode
        applyPreferredInputDevice(to: input)
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

    /// Points the engine's input at the user's preferred device, falling
    /// back to the system default (and flagging it) if that device isn't
    /// currently connected. Re-applied on every `start()` since a disconnect
    /// can happen between dictations. A no-op when no preference is set —
    /// leaving the engine's own default-device management untouched avoids
    /// re-pinning the HAL unit to a device it's already on, which stales the
    /// node's cached format and crashes `installTap` with a format mismatch.
    private func applyPreferredInputDevice(to input: AVAudioInputNode) {
        guard let preferredUID = AppSettings.shared.preferredInputDeviceUID else { return }
        guard let resolvedID = AudioDeviceDirectory.deviceID(forUID: preferredUID) else {
            didFallBackToDefaultDevice = true
            return
        }
        guard let audioUnit = input.audioUnit else { return }
        var deviceID = resolvedID
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                              &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        // Force the node to re-derive its format against the new device's
        // native rate before `outputFormat(forBus:)` is read in `start()`.
        engine.reset()
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
