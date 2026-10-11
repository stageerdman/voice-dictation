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
        window.title = "Voice Dictation Settings"
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

    let hasGroqKey = Secrets.shared.hasGroqKey
    let hasAnthropicKey = Secrets.shared.hasAnthropicKey

    init() {
        model = AppSettings.shared.transcriptionModel
        cleanup = AppSettings.shared.cleanupMode
        language = AppSettings.shared.language
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

            Section("Shortcut") {
                LabeledContent("Hold to dictate") {
                    Text("⌘⌥").font(.body.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(.unemphasizedSelectedContentBackgroundColor)))
                }
                Text("Hold the keys, speak, release to insert.")
                    .font(.caption).foregroundStyle(.secondary)
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
        switch mode { case .none: return "Off"; case .groq: return "Groq"; case .claude: return "Claude" }
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
        case .none:   return "Raw transcription, inserted instantly."
        case .groq:   return "Fast cloud cleanup. Requires Groq API key."
        case .claude: return "Highest quality. Requires Anthropic API key."
        }
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
