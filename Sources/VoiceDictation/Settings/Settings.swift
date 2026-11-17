import AppKit
import Foundation

extension Notification.Name {
    /// Posted by `AppSettings`' chord setters whenever the push-to-talk or lock
    /// chord changes, so the live `HotkeyMonitor` and menu-bar label can stay
    /// in sync without a direct reference to Settings.
    static let voiceDictatorHotkeyChordChanged = Notification.Name("VoiceDictator.hotkeyChordChanged")
}

/// A transcription backend the user can choose. On-device options need no key;
/// the cloud option is only usable when a Groq key is present.
enum TranscriptionModel: String, CaseIterable, Codable, Identifiable {
    case parakeet        // mlx-community/parakeet-tdt-0.6b-v3 — fastest, default
    case whisperTurbo    // mlx-community/whisper-large-v3-turbo
    case whisperLargeV3  // mlx-community/whisper-large-v3-mlx
    case whisperMedium   // mlx-community/whisper-medium-mlx
    case whisperSmall    // mlx-community/whisper-small-mlx
    case whisperTiny     // mlx-community/whisper-tiny-mlx
    case groqTurbo       // Groq whisper-large-v3-turbo (cloud, needs key)

    var id: String { rawValue }

    /// Identifier handed to the sidecar (an HF repo for on-device models).
    var backendID: String {
        switch self {
        case .parakeet:       return "mlx-community/parakeet-tdt-0.6b-v3"
        case .whisperTurbo:   return "mlx-community/whisper-large-v3-turbo"
        case .whisperLargeV3: return "mlx-community/whisper-large-v3-mlx"
        case .whisperMedium:  return "mlx-community/whisper-medium-mlx"
        case .whisperSmall:   return "mlx-community/whisper-small-mlx"
        case .whisperTiny:    return "mlx-community/whisper-tiny-mlx"
        case .groqTurbo:      return "groq/whisper-large-v3-turbo"
        }
    }

    var isCloud: Bool { self == .groqTurbo }

    var displayName: String {
        switch self {
        case .parakeet:       return "Parakeet (fastest)"
        case .whisperTurbo:   return "Whisper Turbo"
        case .whisperLargeV3: return "Whisper Large v3 (most accurate)"
        case .whisperMedium:  return "Whisper Medium"
        case .whisperSmall:   return "Whisper Small"
        case .whisperTiny:    return "Whisper Tiny"
        case .groqTurbo:      return "Groq Cloud (Whisper Turbo)"
        }
    }
}

/// How (and whether) to clean up raw transcription before inserting. Both
/// cleanup backends run with no API key: the local `claude` CLI (authenticated
/// Claude Code) or an on-device MLX LLM.
enum CleanupMode: String, CaseIterable, Codable, Identifiable {
    case none       // raw text, instant — default
    case claudeCLI  // headless `claude -p` (fast model), best quality, needs network
    case localLLM   // on-device MLX LLM, fully offline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "None (raw, instant)"
        case .claudeCLI: return "Claude CLI"
        case .localLLM:  return "Local LLM"
        }
    }

    var needsNetwork: Bool { self == .claudeCLI }
}

/// User settings, persisted to `UserDefaults`. Deliberately small; each piece is
/// independent so adding an option is a one-line change here plus the UI.
/// `@unchecked Sendable`: the only stored property is a thread-safe `UserDefaults`.
final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let model = "transcriptionModel"
        static let cleanup = "cleanupMode"
        static let language = "language"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeyChord = "hotkeyChord"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyKeyLabel = "hotkeyKeyLabel"
        static let preferredInputDevice = "preferredInputDeviceUID"
        static let lockChord = "lockChord"
        static let lockKeyCode = "lockKeyCode"
        static let lockKeyLabel = "lockKeyLabel"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var transcriptionModel: TranscriptionModel {
        get { defaults.string(forKey: Key.model).flatMap(TranscriptionModel.init) ?? .parakeet }
        set { defaults.set(newValue.rawValue, forKey: Key.model) }
    }

    var cleanupMode: CleanupMode {
        get { defaults.string(forKey: Key.cleanup).flatMap(CleanupMode.init) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.cleanup) }
    }

    /// Two-letter language hint for Whisper models (Parakeet auto-detects).
    var language: String {
        get { defaults.string(forKey: Key.language) ?? "en" }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// The chord held to trigger dictation. Defaults to ⌘+⌃.
    var hotkeyChord: HotkeyChord {
        get { chord(Key.hotkeyChord, Key.hotkeyKeyCode, Key.hotkeyKeyLabel, default: .default) }
        set { setChord(newValue, Key.hotkeyChord, Key.hotkeyKeyCode, Key.hotkeyKeyLabel) }
    }

    /// The chord pressed once to start hands-free (locked) dictation and again
    /// to stop and insert. Defaults to ⌥⌘V.
    var lockChord: HotkeyChord {
        get { chord(Key.lockChord, Key.lockKeyCode, Key.lockKeyLabel, default: .lockDefault) }
        set { setChord(newValue, Key.lockChord, Key.lockKeyCode, Key.lockKeyLabel) }
    }

    private func chord(_ modsKey: String, _ codeKey: String, _ labelKey: String,
                       default fallback: HotkeyChord) -> HotkeyChord {
        guard let raw = defaults.object(forKey: modsKey) as? UInt else { return fallback }
        let modifiers = NSEvent.ModifierFlags(rawValue: raw)
        guard let rawKeyCode = defaults.object(forKey: codeKey) as? Int else {
            return HotkeyChord(modifiers: modifiers, keyCode: nil, keyLabel: nil)
        }
        return HotkeyChord(modifiers: modifiers, keyCode: UInt16(rawKeyCode),
                           keyLabel: defaults.string(forKey: labelKey))
    }

    private func setChord(_ chord: HotkeyChord, _ modsKey: String, _ codeKey: String, _ labelKey: String) {
        defaults.set(chord.modifiers.rawValue, forKey: modsKey)
        if let keyCode = chord.keyCode {
            defaults.set(Int(keyCode), forKey: codeKey)
            defaults.set(chord.keyLabel, forKey: labelKey)
        } else {
            defaults.removeObject(forKey: codeKey)
            defaults.removeObject(forKey: labelKey)
        }
        NotificationCenter.default.post(name: .voiceDictatorHotkeyChordChanged, object: nil)
    }

    /// The Core Audio UID of the mic to record from. `nil` means "system
    /// default" — the common case, and also the automatic fallback if this
    /// device disconnects.
    var preferredInputDeviceUID: String? {
        get { defaults.string(forKey: Key.preferredInputDevice) }
        set { defaults.set(newValue, forKey: Key.preferredInputDevice) }
    }
}
