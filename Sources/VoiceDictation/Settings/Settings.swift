import Foundation

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

/// How (and whether) to clean up raw transcription before inserting.
enum CleanupMode: String, CaseIterable, Codable, Identifiable {
    case none   // raw text, instant — default
    case groq   // Groq llama, fast cloud
    case claude // Claude, highest quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None (raw, instant)"
        case .groq:   return "Groq (fast)"
        case .claude: return "Claude (best)"
        }
    }

    var needsNetwork: Bool { self != .none }
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
}
