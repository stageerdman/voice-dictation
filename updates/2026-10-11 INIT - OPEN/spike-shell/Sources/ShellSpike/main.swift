// ShellSpike — Phase 0 throwaway spike for Voice Dictation.
//
// Goal: prove the native-Swift app shell in isolation —
//   1. menu-bar presence (NSStatusItem, no Dock icon),
//   2. a global hold-to-talk hotkey (hold ⌘+⌥, release to stop) that fires
//      logged events even when another app is focused,
//   3. mic capture to a temp WAV file while held, logging duration.
//
// It intentionally does NOT transcribe or insert text — that is Phase 1/2.
// Run with:  swift run ShellSpike   (grant Microphone + Input Monitoring when asked)

import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: Any?

    // Recording state
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recording = false
    private var startTime: Date?

    // ⌘+⌥ held together is our hold-to-talk chord.
    private let chord: NSEvent.ModifierFlags = [.command, .option]

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(idle: true)
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold ⌘+⌥ to record", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ShellSpike", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        requestMicThenStartHotkey()
        log("launched — menu-bar item is live; hold ⌘+⌥ anywhere to test the hotkey")
    }

    private func requestMicThenStartHotkey() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            self.log(granted ? "microphone permission: GRANTED" : "microphone permission: DENIED")
        }
        // Global monitor sees modifier changes system-wide (needs Input Monitoring/Accessibility).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] ev in
            // Global monitors are delivered on the main thread.
            MainActor.assumeIsolated { self?.handleFlags(ev.modifierFlags) }
        }
        if monitor == nil {
            log("WARNING: could not install global monitor — grant Input Monitoring in System Settings")
        }
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let held = flags.intersection([.command, .option, .control, .shift])
        let chordDown = held.contains(chord)
        if chordDown && !recording {
            startRecording()
        } else if !chordDown && recording {
            stopRecording()
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellspike-\(ProcessInfo.processInfo.globallyUniqueString).wav")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            log("ERROR: could not open audio file: \(error.localizedDescription)")
            return
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            try? self?.audioFile?.write(from: buf)
        }
        do {
            try engine.start()
        } catch {
            log("ERROR: engine failed to start: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            return
        }
        recording = true
        startTime = Date()
        setIcon(idle: false)
        log("● recording → \(url.lastPathComponent)")
    }

    private func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recording = false
        setIcon(idle: true)
        let dur = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let where_ = audioFile?.url.lastPathComponent ?? "?"
        audioFile = nil
        log(String(format: "■ stopped — %.2fs captured to %@", dur, where_))
    }

    private func setIcon(idle: Bool) {
        guard let button = statusItem.button else { return }
        let name = idle ? "mic" : "mic.fill"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "ShellSpike") {
            img.isTemplate = true
            button.image = img
            button.title = ""
        } else {
            // Guaranteed-visible fallback if the SF Symbol can't load.
            button.image = nil
            button.title = idle ? "🎙︎" : "🔴"
        }
    }

    nonisolated private func log(_ msg: String) {
        let line = "[ShellSpike] " + msg + "\n"
        FileHandle.standardError.write(Data(line.utf8))
        // Also append to a fixed logfile so the app can be launched detached
        // (via `open`) and still have its activity inspected.
        let path = "/tmp/shellspike.log"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
