import AudioToolbox
import AVFoundation
import ObjCExceptionCatcher

/// Captures the microphone to a temporary WAV file while the hotkey is held.
/// Exposes a live input level (0...1) so the UI can draw a waveform. The caller
/// owns the returned file and must delete it once transcription succeeds.
final class AudioRecorder {
    struct Recording {
        let url: URL
        let duration: TimeInterval
        /// Seconds of audio actually written. Near zero while `duration` is
        /// long means the mic delivered nothing (a wedged device/engine).
        let capturedSeconds: TimeInterval
    }

    /// Recreated whenever it may be stale (route change, failed start, a take
    /// that captured nothing) so one bad take never poisons the next.
    private var engine = AVAudioEngine()
    private var needsFreshEngine = false
    private var configObserver: NSObjectProtocol?
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private(set) var isRecording = false

    /// Most recent input level in 0...1 (RMS-derived), for the HUD meter.
    private(set) var level: Float = 0

    /// Called on the audio thread with each new level sample; hop to main in UI.
    var onLevel: ((Float) -> Void)?

    /// True after the most recent `start()` if the preferred input device
    /// (from Settings) wasn't found — i.e. it disconnected — and recording
    /// silently fell back to the system default instead.
    private(set) var didFallBackToDefaultDevice = false

    enum RecorderError: LocalizedError {
        case couldNotCreateFile(Error), engineFailed(Error), invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFile(let e): return "Couldn't create audio file: \(e.localizedDescription)"
            case .engineFailed(let e): return "Audio engine failed: \(e.localizedDescription)"
            case .invalidInputFormat: return "Microphone reported no usable audio format"
            }
        }
    }

    init() { observeConfigurationChanges() }

    /// Starts capture. If the engine is in a bad state, throws it away and
    /// retries once on a fresh one before giving up.
    func start() throws {
        guard !isRecording else { return }
        if needsFreshEngine { rebuildEngine() }
        do {
            try startOnce()
        } catch {
            rebuildEngine()
            try startOnce()
        }
    }

    /// Discards the current engine for a brand-new one. Cheap; the next
    /// `start()` re-reads the input device and format from scratch.
    func rebuildEngine() {
        try? ObjCExceptionCatcher.catchException { self.engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        engine = AVAudioEngine()
        needsFreshEngine = false
        observeConfigurationChanges()
    }

    private func startOnce() throws {
        didFallBackToDefaultDevice = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedictation-\(UUID().uuidString).wav")
        let input = engine.inputNode
        applyPreferredInputDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.invalidInputFormat
        }

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            throw RecorderError.couldNotCreateFile(error)
        }
        framesWritten = 0
        sampleRate = format.sampleRate

        do {
            // installTap and start can raise NSExceptions (stale format,
            // device gone); catch them so they surface as a normal error.
            var startError: Error?
            try ObjCExceptionCatcher.catchException {
                input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                    guard let self else { return }
                    if (try? self.audioFile?.write(from: buffer)) != nil {
                        self.framesWritten += AVAudioFramePosition(buffer.frameLength)
                    }
                    let lvl = AudioRecorder.rms(buffer)
                    self.level = lvl
                    self.onLevel?(lvl)
                }
                do { try self.engine.start() } catch { startError = error }
            }
            if let startError { throw startError }
        } catch {
            try? ObjCExceptionCatcher.catchException { input.removeTap(onBus: 0) }
            engine.stop()
            audioFile = nil
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.engineFailed(error)
        }

        startTime = Date()
        isRecording = true
    }

    /// Stops capture and returns the finished file plus its duration.
    @discardableResult
    func stop() -> Recording? {
        guard isRecording else { return nil }
        try? ObjCExceptionCatcher.catchException { self.engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        isRecording = false
        level = 0
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let captured = sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
        // A real hold that captured (almost) nothing means the engine/device is
        // wedged — start the next take on a fresh engine.
        if duration > 0.5 && captured < 0.1 { needsFreshEngine = true }
        let url = audioFile?.url
        audioFile = nil
        startTime = nil
        guard let url else { return nil }
        return Recording(url: url, duration: duration, capturedSeconds: captured)
    }

    /// Route/format changes (USB mic replugged, sample-rate switch) leave the
    /// engine stopped with a stale format; rebuild on the next take.
    private func observeConfigurationChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.needsFreshEngine = true
        }
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
