import AppKit
import Carbon.HIToolbox

/// Inserts text at the current cursor in whatever app is focused.
///
/// Strategy: **clipboard-paste-and-restore**. It's the one mechanism that works
/// across virtually every Mac app (native, Electron, web) because it rides the
/// app's own paste handling, unlike AXUIElement value-setting which many apps
/// ignore. We save the pasteboard, write our text, synthesize ⌘V, then restore
/// the previous pasteboard contents so the user's clipboard is left untouched.
///
/// Requires Accessibility permission (to post the synthetic ⌘V keystroke).
@MainActor
final class TextInserter {
    enum InsertionError: Error { case accessibilityNotGranted }

    /// Localized name of the app that was frontmost at insertion time, for history.
    private(set) var lastTargetApp: String?

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func insert(_ text: String) throws {
        guard !text.isEmpty else { return }
        guard hasAccessibilityPermission else { throw InsertionError.accessibilityNotGranted }

        lastTargetApp = NSWorkspace.shared.frontmostApplication?.localizedName

        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Self.pressCommandV()

        // Restore the user's clipboard shortly after the paste is consumed.
        // The delay lets the frontmost app read our text before we put the
        // original contents back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.restore(saved, to: pasteboard)
        }
    }

    // MARK: - Pasteboard snapshot/restore

    private struct Item { let type: NSPasteboard.PasteboardType; let data: Data }

    private static func snapshot(_ pb: NSPasteboard) -> [Item] {
        guard let items = pb.pasteboardItems else { return [] }
        var saved: [Item] = []
        for item in items {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append(Item(type: type, data: data))
                }
            }
        }
        return saved
    }

    private static func restore(_ saved: [Item], to pb: NSPasteboard) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        let item = NSPasteboardItem()
        for entry in saved {
            item.setData(entry.data, forType: entry.type)
        }
        pb.writeObjects([item])
    }

    // MARK: - Synthetic ⌘V

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
