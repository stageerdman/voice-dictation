import AppKit
import AVFoundation

/// The live state of a dictation, consumed by the menu-bar icon and HUD.
enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case inserting
    case success
    case error(message: String, isPermission: Bool)
}

/// Orchestrates the one core flow: hold hotkey → record → transcribe → optional
/// cleanup → insert at cursor → save to history → delete the audio file.
/// Each collaborator is injected so pieces stay swappable and testable.
@MainActor
final class DictationController {
    private let hotkey: HotkeyMonitor
    private let recorder: AudioRecorder
    private let transcriber: Transcriber
    private let cleanup: CleanupService
    private let inserter: TextInserter
    private let history: HistoryStore
    private let settings: AppSettings

    /// UI observers.
    var onStateChange: ((DictationState) -> Void)?
    var onLevel: ((Float) -> Void)?

    private(set) var state: DictationState = .idle {
        didSet { onStateChange?(state) }
    }

    init(hotkey: HotkeyMonitor = HotkeyMonitor(),
         recorder: AudioRecorder = AudioRecorder(),
         transcriber: Transcriber = RoutingTranscriber(),
         cleanup: CleanupService = CleanupService(),
         inserter: TextInserter = TextInserter(),
         history: HistoryStore = HistoryStore(),
         settings: AppSettings = .shared) {
        self.hotkey = hotkey
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.inserter = inserter
        self.history = history
        self.settings = settings

        self.recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.onLevel?(level) }
        }
        self.hotkey.onStart = { [weak self] in self?.beginRecording() }
        self.hotkey.onStop = { [weak self] in self?.finishRecording() }
    }

    var historyStore: HistoryStore { history }

    func start() {
        hotkey.start()
        state = .idle
    }

    // MARK: - Recording

    private func beginRecording() {
        // Ignore the trigger if already recording or still processing a prior take.
        switch state {
        case .recording, .transcribing, .inserting: return
        default: break
        }
        do {
            try recorder.start()
            state = .recording
        } catch {
            fail("Couldn't start recording", isPermission: false)
        }
    }

    private func finishRecording() {
        guard state == .recording, let recording = recorder.stop() else {
            if state == .recording { state = .idle }
            return
        }
        state = .transcribing

        let model = settings.transcriptionModel
        let language = settings.language
        let cleanupMode = settings.cleanupMode

        Task { [weak self] in
            await self?.process(recording, model: model, language: language, cleanupMode: cleanupMode)
        }
    }

    // MARK: - Pipeline

    private func process(_ recording: AudioRecorder.Recording,
                         model: TranscriptionModel,
                         language: String,
                         cleanupMode: CleanupMode) async {
        defer { deleteAudio(recording.url) }  // audio is transient — always remove it

        let raw: String
        do {
            raw = try await transcriber.transcribe(audioURL: recording.url, model: model, language: language)
        } catch TranscriptionError.empty {
            fail("No speech heard", isPermission: false)
            return
        } catch {
            fail(error.localizedDescription, isPermission: false)
            return
        }

        let text = await cleanup.clean(raw, mode: cleanupMode)

        state = .inserting
        do {
            try inserter.insert(text)
        } catch TextInserter.InsertionError.accessibilityNotGranted {
            fail("Accessibility access needed", isPermission: true)
            return
        } catch {
            fail("Couldn't insert text", isPermission: false)
            return
        }

        history.add(DictationEntry(
            text: text,
            date: Date(),
            duration: recording.duration,
            targetApp: inserter.lastTargetApp
        ))

        state = .success
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if self?.state == .success { self?.state = .idle }
        }
    }

    private func deleteAudio(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func fail(_ message: String, isPermission: Bool) {
        state = .error(message: message, isPermission: isPermission)
        let delay: UInt64 = isPermission ? 0 : 1_600_000_000
        guard !isPermission else { return }  // permission errors persist until resolved
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            if case .error = self?.state { self?.state = .idle }
        }
    }
}
