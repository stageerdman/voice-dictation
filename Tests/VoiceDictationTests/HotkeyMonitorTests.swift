import AppKit
import XCTest
@testable import VoiceDictation

@MainActor
final class HotkeyMonitorTests: XCTestCase {
    private let vKey: UInt16 = 9
    private let optCmd: NSEvent.ModifierFlags = [.option, .command]

    private func monitor(hold: HotkeyChord = .default, lock: HotkeyChord = .lockDefault)
        -> (HotkeyMonitor, events: () -> [String]) {
        let m = HotkeyMonitor(chord: hold, lockChord: lock)
        var log: [String] = []
        m.onStart = { log.append("start") }
        m.onStop = { log.append("stop") }
        m.onLockToggle = { log.append("lock") }
        return (m, { log })
    }

    func testLockChordFiresOncePerPressIgnoringRepeats() {
        let (m, events) = monitor()
        m.handleFlagsChanged(optCmd)
        m.handleKey(code: vKey, isDown: true, isRepeat: false, flags: optCmd)
        m.handleKey(code: vKey, isDown: true, isRepeat: true, flags: optCmd)
        m.handleKey(code: vKey, isDown: false, isRepeat: false, flags: optCmd)
        m.handleFlagsChanged([])
        XCTAssertEqual(events(), ["lock"])
    }

    func testLockChordNeedsItsModifiers() {
        let (m, events) = monitor()
        m.handleKey(code: vKey, isDown: true, isRepeat: false, flags: [.command])  // plain ⌘V paste
        XCTAssertEqual(events(), [])
    }

    func testLockPressedDuringOverlappingModifierHoldReportsBoth() {
        // Hold chord ⌘⌥ is a subset of lock ⌥⌘V: hold starts, then V locks.
        let (m, events) = monitor(hold: HotkeyChord(modifiers: optCmd, keyCode: nil, keyLabel: nil))
        m.handleFlagsChanged(optCmd)
        m.handleKey(code: vKey, isDown: true, isRepeat: false, flags: optCmd)
        m.handleFlagsChanged([])
        XCTAssertEqual(events(), ["start", "lock", "stop"])
    }

    func testModifierOnlyLockChordLatchesUntilReleased() {
        let lock = HotkeyChord(modifiers: [.command, .control, .shift], keyCode: nil, keyLabel: nil)
        let (m, events) = monitor(hold: HotkeyChord(modifiers: [.option, .shift], keyCode: nil, keyLabel: nil), lock: lock)
        m.handleFlagsChanged([.command, .control])
        m.handleFlagsChanged([.command, .control, .shift])
        m.handleFlagsChanged([.command, .control, .shift, .option])  // extra key, still the same press
        m.handleFlagsChanged([])
        m.handleFlagsChanged([.command, .control, .shift])
        XCTAssertEqual(events().filter { $0 == "lock" }.count, 2)
    }
}
