import AppKit
import AVFoundation
import SwiftUI

/// Hosts the SwiftUI settings in a standard preferences-style window.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Voice Dictator Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        self.init(window: window)
    }
}

/// Observable bridge over `AppSettings.shared` so SwiftUI controls bind directly.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var model: TranscriptionModel {
        didSet { AppSettings.shared.transcriptionModel = model }
    }
    @Published var cleanup: CleanupMode {
        didSet { AppSettings.shared.cleanupMode = cleanup }
    }
    @Published var language: String {
        didSet { AppSettings.shared.language = language }
    }
    @Published var hotkeyChord: HotkeyChord {
        didSet { AppSettings.shared.hotkeyChord = hotkeyChord }
    }
    @Published var lockChord: HotkeyChord {
        didSet { AppSettings.shared.lockChord = lockChord }
    }

    let hasGroqKey = Secrets.shared.hasGroqKey
    let hasAnthropicKey = Secrets.shared.hasAnthropicKey

    init() {
        model = AppSettings.shared.transcriptionModel
        cleanup = AppSettings.shared.cleanupMode
        language = AppSettings.shared.language
        hotkeyChord = AppSettings.shared.hotkeyChord
        lockChord = AppSettings.shared.lockChord
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "mic") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @StateObject private var m = SettingsModel()

    private var onDeviceModels: [TranscriptionModel] { TranscriptionModel.allCases.filter { !$0.isCloud } }

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $m.model) {
                    Section("On-device") {
                        ForEach(onDeviceModels) { Text($0.displayName).tag($0) }
                    }
                    Section("Cloud") {
                        if m.hasGroqKey {
                            Text(TranscriptionModel.groqTurbo.displayName).tag(TranscriptionModel.groqTurbo)
                        } else {
                            Text("Groq · needs API key").tag(TranscriptionModel.groqTurbo).disabled(true)
                        }
                    }
                }
                Text(modelSubtitle(m.model))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Transcription")
            } footer: {
                Text("Runs entirely on your Mac unless you choose a cloud model.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Cleanup", selection: $m.cleanup) {
                    ForEach(CleanupMode.allCases) { Text(shortName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(cleanupSubtitle(m.cleanup))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("AI Cleanup")
            } footer: {
                Text("Tidies grammar and filler after transcription. Off is instant.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ShortcutField(label: "Hold to dictate",
                              caption: "Hold the keys, speak, release to insert.",
                              chord: $m.hotkeyChord,
                              other: m.lockChord, otherLabel: "Hands-free")
                ShortcutField(label: "Hands-free",
                              caption: "Press once to start, again to insert. Press while holding to keep listening.",
                              chord: $m.lockChord,
                              other: m.hotkeyChord, otherLabel: "Hold to dictate")
            }

            Section("Language") {
                Picker("Language", selection: $m.language) {
                    Text("English").tag("en")
                    Text("Auto-detect").tag("")
                }
                Text("English is tuned best. Other languages depend on the model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortName(_ mode: CleanupMode) -> String {
        switch mode {
        case .none: return "Off"
        case .claudeCLI: return "Claude CLI"
        case .localLLM: return "Local LLM"
        }
    }

    private func modelSubtitle(_ model: TranscriptionModel) -> String {
        switch model {
        case .parakeet:       return "On-device · ~60× realtime · auto language"
        case .whisperTurbo:   return "On-device · fast · high quality"
        case .whisperLargeV3: return "On-device · most accurate · slower"
        case .whisperMedium:  return "On-device · balanced"
        case .whisperSmall:   return "On-device · light"
        case .whisperTiny:    return "On-device · lightest · least accurate"
        case .groqTurbo:      return "Cloud · fastest · needs network + key"
        }
    }

    private func cleanupSubtitle(_ mode: CleanupMode) -> String {
        switch mode {
        case .none:      return "Raw transcription, inserted instantly."
        case .claudeCLI: return "Best quality via the local Claude CLI. No key; needs network. A few seconds."
        case .localLLM:  return "On-device MLX model. Fully private, no network. A few seconds."
        }
    }
}

/// Lets the user rebind a shortcut (push-to-talk or hands-free lock): click "Change…", hold the new
/// keys (mirroring the trigger gesture itself), then either release to
/// finalize a modifier-only chord or press a regular key to pair it with the
/// modifiers held so far. Modifier-only chords need at least two modifiers so
/// they can't fire from ordinary typing; a letter chord needs just one.
private struct ShortcutField: View {
    let label: String
    let caption: String
    @Binding var chord: HotkeyChord
    /// The other shortcut, which this one must not duplicate.
    let other: HotkeyChord
    let otherLabel: String
    @State private var recorder = ShortcutRecorder()
    @State private var isCapturing = false
    @State private var liveSymbols = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    Text(isCapturing ? (liveSymbols.isEmpty ? "Press keys…" : liveSymbols) : chord.symbolString)
                        .font(.body.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(.unemphasizedSelectedContentBackgroundColor)))
                    Button(isCapturing ? "Cancel" : "Change…") {
                        isCapturing ? cancel() : begin()
                    }
                }
            }
            Text(errorText ?? caption)
                .font(.caption)
                .foregroundStyle(errorText == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        .onDisappear { recorder.cancel() }
    }

    private func begin() {
        errorText = nil
        liveSymbols = ""
        isCapturing = true
        recorder.onLiveChange = { flags in liveSymbols = flags.symbolString }
        recorder.onFinish = { finish($0) }
        recorder.begin()
    }

    private func cancel() {
        recorder.cancel()
        isCapturing = false
        liveSymbols = ""
        errorText = nil
    }

    private func finish(_ captured: HotkeyChord) {
        isCapturing = false
        liveSymbols = ""
        guard captured != chord else { return }  // changed their mind, or picked the same chord
        guard captured != other else {
            errorText = "Already used for \(otherLabel)."
            return
        }
        let modifierCount = [NSEvent.ModifierFlags.command, .option, .control, .shift]
            .filter { captured.modifiers.contains($0) }.count
        let minimumModifiers = captured.keyCode == nil ? 2 : 1
        guard modifierCount >= minimumModifiers else {
            errorText = captured.keyCode == nil
                ? "Needs at least two keys, like ⌘⌃."
                : "Needs at least one modifier, like ⌃V."
            return
        }
        chord = captured
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                              userInfo: [.announcement: "\(label) shortcut changed to \(captured.symbolString)",
                                         .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

private struct AdvancedSettings: View {
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        AppSettings.shared.launchAtLogin = new
                        LaunchAtLogin.setEnabled(new)
                    }
            }

            Section("Permissions") {
                PermissionRow(name: "Microphone", granted: micGranted,
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                PermissionRow(name: "Accessibility", granted: AXIsProcessTrusted(),
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            Section {
                Button("Clear History…", role: .destructive) { confirmClear() }
            } footer: {
                Text("History stores text only. Audio is deleted the moment it's transcribed — it never leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var micGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This permanently removes every saved dictation. It can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryStore().clear()
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let settingsURL: String

    var body: some View {
        LabeledContent(name) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else {
                Button("Open Settings…") {
                    NSWorkspace.shared.open(URL(string: settingsURL)!)
                }
            }
        }
    }
}
