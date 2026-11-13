import AppKit

/// Captures a new push-to-talk chord for Settings: a local hold-then-release
/// gesture that mirrors `HotkeyMonitor` itself, so recording a shortcut feels
/// like using it. Hold modifiers, then either release them back to nothing
/// (captures a modifier-only chord) or press a regular key while they're held
/// (captures that key plus the modifiers held so far).
@MainActor
final class ShortcutRecorder {
    private(set) var isCapturing = false
    private var monitor: Any?
    private var maxFlags: NSEvent.ModifierFlags = []

    /// Fires on every modifier change while capturing, so the UI can mirror
    /// the keys live as they're pressed.
    var onLiveChange: ((NSEvent.ModifierFlags) -> Void)?
    /// Fires once capture finishes: either a modifier-only release, or a
    /// regular key pressed while modifiers were held.
    var onFinish: ((HotkeyChord) -> Void)?

    func begin() {
        guard monitor == nil else { return }
        isCapturing = true
        maxFlags = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.cancel() }  // Escape
                else { self.handleKeyDown(event) }
                return event
            }
            self.handleFlagsChanged(event.modifierFlags)
            return event
        }
    }

    func cancel() {
        guard monitor != nil else { return }
        end()
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let relevant = flags.intersection(relevantHotkeyModifiers)
        if !relevant.isEmpty {
            maxFlags.formUnion(relevant)
            onLiveChange?(maxFlags)
        } else if !maxFlags.isEmpty {
            let captured = maxFlags
            end()
            onFinish?(HotkeyChord(modifiers: captured, keyCode: nil, keyLabel: nil))
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !maxFlags.isEmpty else { return }  // a bare letter isn't a valid chord
        let captured = maxFlags
        let label = Self.label(for: event)
        end()
        onFinish?(HotkeyChord(modifiers: captured, keyCode: event.keyCode, keyLabel: label))
    }

    private static func label(for event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(event.keyCode)"
    }

    private func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isCapturing = false
        maxFlags = []
    }
}
