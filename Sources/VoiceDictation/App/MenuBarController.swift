import AppKit
import UserNotifications

/// Owns the menu-bar status item: the `waveform` glyph whose color/animation
/// reflects dictation state, the dropdown menu, and the recording HUD. Follows
/// the recording-feedback spec — red+pulse while listening, dim breathe while
/// transcribing, a green check on success, orange on error; only permission
/// errors raise a notification.
@MainActor
final class MenuBarController {
    private let controller: DictationController
    private let statusItem: NSStatusItem
    private let hud = RecordingHUD()

    private var settingsWindow: SettingsWindowController?
    private var historyWindow: HistoryWindowController?
    private var headerItem: NSMenuItem!
    private var permissionItem: NSMenuItem!

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(controller: DictationController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        buildMenu()
        apply(.idle)

        controller.onStateChange = { [weak self] state in self?.apply(state) }
        controller.onLevel = { [weak self] level in self?.hud.update(level: level) }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.symbol("waveform")
        button.image?.isTemplate = true
        button.setAccessibilityLabel("Voice Dictator, ready")
        button.wantsLayer = true
    }

    private static func symbol(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium, scale: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Voice Dictator")?
            .withSymbolConfiguration(cfg)
        // `withSymbolConfiguration` returns a non-template image; force template so
        // the menu bar renders it adaptively (white on a dark bar) like every other
        // status item, instead of as a hard-to-see black glyph. State tints
        // (red/green/orange) still apply via `contentTintColor`.
        image?.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        headerItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let dictate = NSMenuItem(title: "Dictate", action: nil, keyEquivalent: "")
        dictate.isEnabled = false
        dictate.toolTip = "Hold ⌘⌥ anywhere, speak, release"
        // Show the binding on the trailing side.
        dictate.title = "Dictate                     ⌘⌥ hold"
        menu.addItem(dictate)

        menu.addItem(.separator())

        menu.addItem(withTitle: "History…", action: #selector(openHistory), keyEquivalent: "y").target = self
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = AppSettings.shared.launchAtLogin ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Voice Dictator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if historyWindow == nil {
            historyWindow = HistoryWindowController(store: controller.historyStore, log: controller.logStore)
        }
        historyWindow?.showWindow(nil)
        historyWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        AppSettings.shared.launchAtLogin.toggle()
        sender.state = AppSettings.shared.launchAtLogin ? .on : .off
        LaunchAtLogin.setEnabled(AppSettings.shared.launchAtLogin)
    }

    // MARK: - State rendering

    private func apply(_ state: DictationState) {
        guard let button = statusItem.button else { return }
        button.layer?.removeAllAnimations()
        button.alphaValue = 1
        permissionItem.isHidden = true

        switch state {
        case .idle:
            button.image = Self.symbol("waveform")
            button.contentTintColor = nil
            button.setAccessibilityLabel("Voice Dictator, ready")
            headerItem.title = "Ready"
            hud.hide()

        case .recording:
            button.image = Self.symbol("waveform")
            button.contentTintColor = .systemRed
            button.setAccessibilityLabel("Voice Dictator, listening")
            headerItem.title = "Listening…"
            if !reduceMotion { pulse(button, from: 1.0, to: 0.45, duration: 1.1) }
            hud.showRecording(reduceMotion: reduceMotion)

        case .transcribing:
            button.image = Self.symbol("waveform")
            button.contentTintColor = .secondaryLabelColor
            button.setAccessibilityLabel("Voice Dictator, transcribing")
            headerItem.title = "Transcribing…"
            if !reduceMotion { pulse(button, from: 0.8, to: 0.5, duration: 0.8) }
            hud.showTranscribing()

        case .inserting:
            button.contentTintColor = nil
            hud.hide()

        case .success:
            button.image = Self.symbol("checkmark")
            button.contentTintColor = .systemGreen
            button.setAccessibilityLabel("Voice Dictator, text inserted")
            headerItem.title = "Inserted"
            hud.hide()
            announce("Text inserted")

        case .error(let message, let isPermission):
            button.image = Self.symbol("exclamationmark.triangle")
            button.contentTintColor = .systemOrange
            button.setAccessibilityLabel("Voice Dictator, \(message)")
            headerItem.title = message
            hud.hide()
            announce(message)
            if isPermission { showPermissionHelp(message) }
        }
    }

    private func pulse(_ view: NSView, from: Float, to: Float, duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(anim, forKey: "pulse")
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Permission failures persist in the menu with a one-click fix that
    /// deep-links to the right System Settings pane.
    private func showPermissionHelp(_ message: String) {
        let isMic = message.lowercased().contains("microphone")
        permissionItem.isHidden = false
        permissionItem.title = isMic ? "Enable Microphone…" : "Enable Text Insertion…"
        permissionItem.action = isMic ? #selector(openMicSettings) : #selector(openAccessibilitySettings)
        permissionItem.target = self

        let content = UNMutableNotificationContent()
        if isMic {
            content.title = "Voice Dictator can't hear you"
            content.body = "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone."
        } else {
            content.title = "Voice Dictator can't type for you"
            content.body = "Grant Accessibility so dictated text can be inserted: System Settings → Privacy & Security → Accessibility. If it's already listed, a rebuild invalidated it — remove it with “–” and re-add."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            if granted { UNUserNotificationCenter.current().add(request) }
        }
    }

    @objc private func openMicSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
