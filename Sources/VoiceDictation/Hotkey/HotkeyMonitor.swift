import AppKit

/// The set of modifiers `HotkeyMonitor` and `ShortcutRecorder` pay attention
/// to; anything else (fn, caps lock) is ignored.
let relevantHotkeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

/// A push-to-talk trigger: either a bare modifier chord (e.g. ⌘⌃), or a
/// modifier chord plus a regular key (e.g. ⌃V). `keyLabel` is the display
/// glyph captured at record time — `keyCode` alone can't be turned back into
/// a character without knowing the keyboard layout it was captured under.
struct HotkeyChord: Equatable {
    var modifiers: NSEvent.ModifierFlags
    var keyCode: UInt16?
    var keyLabel: String?

    static let `default` = HotkeyChord(modifiers: [.command, .control], keyCode: nil, keyLabel: nil)

    var symbolString: String {
        modifiers.symbolString + (keyLabel ?? "")
    }
}

/// Global hold-to-talk hotkey. Fires `onStart` when the configured chord goes
/// down and `onStop` when it's released — system-wide, while any app is
/// focused. Uses `NSEvent` global monitors (needs Accessibility permission).
///
/// Two trigger shapes are supported:
/// - Modifier-only (e.g. ⌘+⌃): tracked via `.flagsChanged`. Easy to hold and
///   rarely pressed alone, so it's a natural push-to-talk trigger.
/// - Modifier + regular key (e.g. ⌃V): tracked via `.keyDown`/`.keyUp`. Note
///   that a global monitor only *observes* these events — it can't swallow
///   them — so the key still reaches whatever app is focused.
@MainActor
final class HotkeyMonitor {
    /// The chord that triggers dictation while held.
    var chord: HotkeyChord

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var active = false

    init(chord: HotkeyChord = .default) {
        self.chord = chord
    }

    /// Whether a global keyboard monitor can see events — i.e. Accessibility is
    /// granted. Used to surface the permission error honestly.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        guard flagsMonitor == nil, keyMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlagsChanged(event.modifierFlags) }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyEvent(event) }
        }
    }

    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        flagsMonitor = nil
        keyMonitor = nil
        active = false
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard chord.keyCode == nil else {
            // Letter chords start/stop on the key itself; releasing a
            // required modifier early still cuts the hold short.
            if active, !flags.intersection(relevantHotkeyModifiers).contains(chord.modifiers) {
                active = false
                onStop?()
            }
            return
        }
        let relevant = flags.intersection(relevantHotkeyModifiers)
        let down = relevant.contains(chord.modifiers)
        if down && !active {
            active = true
            onStart?()
        } else if !down && active {
            active = false
            onStop?()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let keyCode = chord.keyCode, event.keyCode == keyCode else { return }
        let relevant = event.modifierFlags.intersection(relevantHotkeyModifiers)
        switch event.type {
        case .keyDown:
            guard !active, relevant.contains(chord.modifiers) else { return }
            active = true
            onStart?()
        case .keyUp:
            guard active else { return }
            active = false
            onStop?()
        default:
            break
        }
    }
}

extension NSEvent.ModifierFlags {
    /// Apple's canonical on-screen modifier ordering: ⌃⌥⇧⌘.
    var symbolString: String {
        var out = ""
        if contains(.control) { out += "⌃" }
        if contains(.option) { out += "⌥" }
        if contains(.shift) { out += "⇧" }
        if contains(.command) { out += "⌘" }
        return out
    }
}
