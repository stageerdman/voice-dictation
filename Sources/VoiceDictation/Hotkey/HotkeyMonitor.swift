import AppKit

/// Global hold-to-talk hotkey. Fires `onStart` when the configured modifier
/// chord goes down and `onStop` when it's released — system-wide, while any app
/// is focused. Uses an `NSEvent` global monitor (needs Accessibility permission).
///
/// Modifier-only chords (e.g. ⌘+⌃) are intentional: they're easy to hold and
/// rarely pressed alone, so they make a natural push-to-talk trigger.
@MainActor
final class HotkeyMonitor {
    /// The modifier chord that triggers dictation while held.
    var chord: NSEvent.ModifierFlags

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var monitor: Any?
    private var active = false

    init(chord: NSEvent.ModifierFlags = [.command, .control]) {
        self.chord = chord
    }

    /// Whether a global keyboard monitor can see events — i.e. Accessibility is
    /// granted. Used to surface the permission error honestly.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.modifierFlags) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        active = false
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let relevant = flags.intersection([.command, .option, .control, .shift])
        let down = relevant.contains(chord)
        if down && !active {
            active = true
            onStart?()
        } else if !down && active {
            active = false
            onStop?()
        }
    }
}
