import XCTest
@testable import VoiceDictation

final class SettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsAreFastAndRaw() {
        let s = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(s.transcriptionModel, .parakeet)
        XCTAssertEqual(s.cleanupMode, .none)
        XCTAssertEqual(s.language, "en")
        XCTAssertEqual(s.hotkeyChord, HotkeyChord(modifiers: [.command, .control], keyCode: nil, keyLabel: nil))
        XCTAssertNil(s.preferredInputDeviceUID)
    }

    func testRoundTrip() {
        let defaults = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.transcriptionModel = .whisperTurbo
        s.cleanupMode = .localLLM
        s.language = "de"
        s.hotkeyChord = HotkeyChord(modifiers: [.command, .option], keyCode: nil, keyLabel: nil)
        s.preferredInputDeviceUID = "some-device-uid"

        // A new instance over the same defaults must read the saved values.
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.transcriptionModel, .whisperTurbo)
        XCTAssertEqual(reloaded.cleanupMode, .localLLM)
        XCTAssertEqual(reloaded.language, "de")
        XCTAssertEqual(reloaded.hotkeyChord, HotkeyChord(modifiers: [.command, .option], keyCode: nil, keyLabel: nil))
        XCTAssertEqual(reloaded.preferredInputDeviceUID, "some-device-uid")
    }

    func testHotkeyChordRoundTripsWithKeyCode() {
        let defaults = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.hotkeyChord = HotkeyChord(modifiers: [.control], keyCode: 9, keyLabel: "V")

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hotkeyChord, HotkeyChord(modifiers: [.control], keyCode: 9, keyLabel: "V"))
    }

    func testLockChordDefaultsToOptionCommandVAndRoundTrips() {
        let defaults = freshDefaults()
        let s = AppSettings(defaults: defaults)
        XCTAssertEqual(s.lockChord, HotkeyChord(modifiers: [.option, .command], keyCode: 9, keyLabel: "V"))

        s.lockChord = HotkeyChord(modifiers: [.command, .shift, .control], keyCode: nil, keyLabel: nil)
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.lockChord, HotkeyChord(modifiers: [.command, .shift, .control], keyCode: nil, keyLabel: nil))
        // Independent of the push-to-talk chord.
        XCTAssertEqual(reloaded.hotkeyChord, .default)
    }

    func testHotkeyChordChangePostsNotification() {
        let s = AppSettings(defaults: freshDefaults())
        let expectation = expectation(forNotification: .voiceDictatorHotkeyChordChanged, object: nil)
        s.hotkeyChord = HotkeyChord(modifiers: [.control, .shift], keyCode: nil, keyLabel: nil)
        wait(for: [expectation], timeout: 1)
    }

    func testBackendIDsAreStable() {
        XCTAssertEqual(TranscriptionModel.parakeet.backendID, "mlx-community/parakeet-tdt-0.6b-v3")
        XCTAssertTrue(TranscriptionModel.groqTurbo.isCloud)
        XCTAssertFalse(TranscriptionModel.parakeet.isCloud)
    }
}

final class SecretsTests: XCTestCase {
    func testParsesDotEnvAndTrimsQuotes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("env-\(UUID()).env")
        try """
        # a comment
        GROQ_API_KEY="gsk_abc123"
        ANTHROPIC_API_KEY=sk-ant-xyz
        EMPTY=
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let secrets = Secrets(environment: [:], dotEnvURL: url)
        XCTAssertEqual(secrets.groqAPIKey, "gsk_abc123")
        XCTAssertEqual(secrets.anthropicAPIKey, "sk-ant-xyz")
        XCTAssertTrue(secrets.hasGroqKey)
    }

    func testEnvironmentOverridesDotEnv() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("env-\(UUID()).env")
        try "GROQ_API_KEY=from_file".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let secrets = Secrets(environment: ["GROQ_API_KEY": "from_env"], dotEnvURL: url)
        XCTAssertEqual(secrets.groqAPIKey, "from_env")
    }

    func testMissingKeysAreNil() {
        let secrets = Secrets(environment: [:], dotEnvURL: nil)
        XCTAssertNil(secrets.groqAPIKey)
        XCTAssertFalse(secrets.hasAnthropicKey)
    }
}
