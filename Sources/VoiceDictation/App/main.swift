import AppKit
import AVFoundation

/// App entry. Menu-bar-only (`.accessory`): no Dock icon, no main window. Wires
/// the dictation controller to the menu-bar UI and requests the permissions the
/// core flow needs (Microphone to hear, Accessibility to insert + hotkey).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controller = DictationController()
        menuBar = MenuBarController(controller: controller)

        controller.start()
        logStartupSelfCheck()
        requestMicrophoneAccess()
        promptAccessibilityIfNeeded()
    }

    /// Record the permission state at launch. The global hotkey and text
    /// insertion both need Accessibility, which fails *silently* when missing —
    /// and an ad-hoc rebuild resets the grant. Logging it here means "records but
    /// no text" has an explanation in the Log instead of a vanishing icon flash.
    private func logStartupSelfCheck() {
        let log = controller.logStore
        log.info(.system, "Voice Dictator launched")

        let ax = AXIsProcessTrusted()
        log.log(ax ? .info : .error, .permission,
                ax ? "Accessibility: granted" : "Accessibility: NOT granted — hotkey and text insertion will silently fail",
                detail: ax ? nil : "Grant it in System Settings → Privacy & Security → Accessibility, then relaunch. After an ad-hoc rebuild this grant resets because the code signature changed.")

        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let micOK = mic == .authorized
        log.log(micOK ? .info : .warning, .permission,
                "Microphone: \(Self.describe(mic))",
                detail: micOK ? nil : "Enable it in System Settings → Privacy & Security → Microphone.")
    }

    private static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:    return "granted"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "not yet requested"
        @unknown default:    return "unknown"
        }
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// Nudge the Accessibility grant on first launch (needed for the global
    /// hotkey and for inserting text). Shows the system prompt once.
    private func promptAccessibilityIfNeeded() {
        if AXIsProcessTrusted() { return }
        // Literal value of kAXTrustedCheckOptionPrompt (a global the Swift 6
        // concurrency checker won't let us touch directly).
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
