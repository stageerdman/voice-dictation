import AppKit
import SwiftUI

/// A small bottom-center capsule shown only while the user is actively holding
/// the hotkey (recording) and during the brief transcribing tail. It proves the
/// mic is hearing them with a live level meter, never steals focus (so inserted
/// text lands in the right app), and vanishes the moment text is inserted.
@MainActor
final class RecordingHUD {
    private var panel: NSPanel?
    private let model = HUDModel()

    func showRecording(reduceMotion: Bool) {
        model.mode = .recording
        model.reduceMotion = reduceMotion
        present()
    }

    func showTranscribing() {
        model.mode = .transcribing
        present()
    }

    func update(level: Float) {
        model.level = level
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        model.level = 0
    }

    private func present() {
        if panel == nil { panel = makePanel() }
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.minY + 96
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()  // show without taking key focus
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 112, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }
}

/// Observable state the SwiftUI HUD renders from.
@MainActor
final class HUDModel: ObservableObject {
    enum Mode { case recording, transcribing }
    @Published var mode: Mode = .recording
    @Published var level: Float = 0
    var reduceMotion = false
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            content
        }
        .frame(width: 112, height: 36)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .recording:
            WaveformBars(level: model.level, reduceMotion: model.reduceMotion)
        case .transcribing:
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }
}

/// Seven bars whose heights follow the mic level, tinted recording-red.
private struct WaveformBars: View {
    let level: Float
    let reduceMotion: Bool
    private let count = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let maxH: CGFloat = 20
        if reduceMotion { return maxH * 0.5 }
        // Center bars taller; scale by level with a small floor so it's alive.
        let center = Double(count - 1) / 2
        let dist = abs(Double(index) - center) / center          // 0 at center, 1 at edges
        let shape = 1.0 - 0.55 * dist
        let lvl = max(0.08, Double(level))
        return maxH * CGFloat(min(1.0, lvl * shape + 0.08))
    }
}
