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
    /// ⌥⌘V (key code 9 is V on ANSI layouts).
    static let lockDefault = HotkeyChord(modifiers: [.option, .command], keyCode: 9, keyLabel: "V")

    var symbolString: String {
        modifiers.symbolString + (keyLabel ?? "")
    }
}

/// Global hold-to-talk hotkey. Fires `onStart` when the configured chord goes
/// down and `onStop` when it's released — system-wide, while any app is
/// focused. Separately, fires `onLockToggle` each time the lock chord is
/// pressed (hands-free mode; the controller decides what a press means). Uses `NSEvent` global monitors (needs Accessibility permission).
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
    /// The chord pressed (not held) to toggle hands-free dictation.
    var lockChord: HotkeyChord

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onLockToggle: (() -> Void)?

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var active = false
    /// Latch for a modifier-only lock chord, so one press fires once.
    private var lockModifiersDown = false

    init(chord: HotkeyChord = .default, lockChord: HotkeyChord = .lockDefault) {
        self.chord = chord
        self.lockChord = lockChord
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
            MainActor.assumeIsolated {
                self?.handleKey(code: event.keyCode, isDown: event.type == .keyDown,
                                isRepeat: event.type == .keyDown && event.isARepeat,
                                flags: event.modifierFlags)
            }
        }
    }

    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        flagsMonitor = nil
        keyMonitor = nil
        active = false
        lockModifiersDown = false
    }

    // Handlers take plain values (not NSEvent) so tests can drive them.

    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        handleLockFlags(flags)
        handleHoldFlags(flags)
    }

    func handleKey(code: UInt16, isDown: Bool, isRepeat: Bool, flags: NSEvent.ModifierFlags) {
        if isDown, !isRepeat, let lockCode = lockChord.keyCode, code == lockCode,
           flags.intersection(relevantHotkeyModifiers).contains(lockChord.modifiers) {
            onLockToggle?()
        }
        handleHoldKey(code: code, isDown: isDown, flags: flags)
    }

    private func handleLockFlags(_ flags: NSEvent.ModifierFlags) {
        guard lockChord.keyCode == nil else { return }
        let down = flags.intersection(relevantHotkeyModifiers).contains(lockChord.modifiers)
        if down && !lockModifiersDown { onLockToggle?() }
        lockModifiersDown = down
    }

    private func handleHoldFlags(_ flags: NSEvent.ModifierFlags) {
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

    private func handleHoldKey(code: UInt16, isDown: Bool, flags: NSEvent.ModifierFlags) {
        guard let keyCode = chord.keyCode, code == keyCode else { return }
        let relevant = flags.intersection(relevantHotkeyModifiers)
        if isDown {
            guard !active, relevant.contains(chord.modifiers) else { return }
            active = true
            onStart?()
        } else {
            guard active else { return }
            active = false
            onStop?()
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
