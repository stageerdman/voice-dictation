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
        requestMicrophoneAccess()
        promptAccessibilityIfNeeded()
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
