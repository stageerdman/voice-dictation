import Foundation

/// Drives a long-lived Python process that keeps MLX transcription models warm
/// (the pattern proven in the sibling `transcriber` project). One request at a
/// time: Swift writes a JSON line to stdin, the sidecar replies with a JSON line
/// on stdout. Keeping the process alive avoids paying model-load cost per
/// dictation — the key to low latency.
final class SidecarTranscriber: Transcriber, @unchecked Sendable {
    private let pythonURL: URL
    private let scriptURL: URL

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
    private var pending: CheckedContinuation<String, Error>?
    private let lock = NSLock()

    /// Resolves the interpreter and sidecar script. Both are overridable via
    /// environment so the dev setup can point at the transcriber venv while a
    /// shipped build points into the app bundle's Resources.
    init(pythonURL: URL? = nil, scriptURL: URL? = nil) {
        self.pythonURL = pythonURL ?? SidecarTranscriber.resolvePython()
        self.scriptURL = scriptURL ?? SidecarTranscriber.resolveScript()
    }

    static func resolvePython() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["VOICE_DICTATION_PYTHON"] { return URL(fileURLWithPath: p) }
        // Reuse the transcriber venv, which already has mlx-whisper/parakeet-mlx.
        let venv = ("~/dev/transcriber/.venv/bin/python" as NSString).expandingTildeInPath
        if FileManager.default.isExecutableFile(atPath: venv) { return URL(fileURLWithPath: venv) }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    static func resolveScript() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let s = env["VOICE_DICTATION_SIDECAR"] { return URL(fileURLWithPath: s) }
        // Bundled location (install.sh copies sidecar/ into Resources).
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("sidecar/transcribe_server.py")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        // Dev fallback: alongside the source tree.
        return URL(fileURLWithPath: ("~/dev/voice-dictation/sidecar/transcribe_server.py" as NSString).expandingTildeInPath)
    }

    // MARK: - Process lifecycle

    private func ensureRunning() throws {
        if let p = process, p.isRunning { return }

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw TranscriptionError.sidecarUnavailable("sidecar script not found at \(scriptURL.path)")
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = ["-u", scriptURL.path]  // -u: unbuffered stdio

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.ingest(data) }
        }
        // Drain stderr so the pipe never fills and blocks the child.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        do {
            try proc.run()
        } catch {
            throw TranscriptionError.sidecarUnavailable(error.localizedDescription)
        }

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
    }

    private func ingest(_ data: Data) {
        lock.lock()
        stdoutBuffer.append(data)
        // Responses are newline-delimited JSON objects.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            let cont = pending
            pending = nil
            lock.unlock()
            if let cont { Self.resume(cont, with: line) }
            lock.lock()
        }
        lock.unlock()
    }

    private static func resume(_ cont: CheckedContinuation<String, Error>, with line: Data) {
        struct Response: Decodable { let ok: Bool; let text: String?; let error: String? }
        guard let resp = try? JSONDecoder().decode(Response.self, from: line) else {
            cont.resume(throwing: TranscriptionError.failed("malformed sidecar response"))
            return
        }
        if resp.ok {
            let text = (resp.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { cont.resume(throwing: TranscriptionError.empty) }
            else { cont.resume(returning: text) }
        } else {
            cont.resume(throwing: TranscriptionError.failed(resp.error ?? "transcription failed"))
        }
    }

    // MARK: - Transcriber

    func transcribe(audioURL: URL, model: TranscriptionModel, language: String) async throws -> String {
        try ensureRunning()
        guard let stdin = stdinPipe else {
            throw TranscriptionError.sidecarUnavailable("no stdin pipe")
        }

        let request: [String: String] = [
            "audio_path": audioURL.path,
            "model": model.backendID,
            "language": language,
        ]
        let payload = try JSONSerialization.data(withJSONObject: request)

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            guard pending == nil else {
                lock.unlock()
                cont.resume(throwing: TranscriptionError.failed("a transcription is already in progress"))
                return
            }
            pending = cont
            lock.unlock()

            var line = payload
            line.append(0x0A)
            stdin.fileHandleForWriting.write(line)
        }
    }
}
