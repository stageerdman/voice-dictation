import Foundation

/// A single long-lived Python process that keeps MLX models warm and serves
/// both transcription and local-LLM cleanup. One request at a time: Swift writes
/// a JSON line to stdin, the sidecar replies with a JSON line on stdout. Sharing
/// one process means the model-load cost is paid once, not per dictation — the
/// key to low latency (the pattern proven in the `transcriber` project).
///
/// Protocol: request `{"op": "transcribe"|"clean", ...}`,
///           response `{"ok": true, "text": "..."}` | `{"ok": false, "error": "..."}`.
final class MLXSidecar: @unchecked Sendable {
    static let shared = MLXSidecar()

    private let pythonURL: URL
    private let scriptURL: URL

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: CheckedContinuation<String, Error>?
    private let lock = NSLock()
    private let log = LogStore.shared

    init(pythonURL: URL? = nil, scriptURL: URL? = nil) {
        self.pythonURL = pythonURL ?? MLXSidecar.resolvePython()
        self.scriptURL = scriptURL ?? MLXSidecar.resolveScript()
    }

    static func resolvePython() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["VOICE_DICTATION_PYTHON"] { return URL(fileURLWithPath: p) }
        let venv = ("~/dev/transcriber/.venv/bin/python" as NSString).expandingTildeInPath
        if FileManager.default.isExecutableFile(atPath: venv) { return URL(fileURLWithPath: venv) }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    static func resolveScript() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let s = env["VOICE_DICTATION_SIDECAR"] { return URL(fileURLWithPath: s) }
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("sidecar/transcribe_server.py")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: ("~/dev/voice-dictation/sidecar/transcribe_server.py" as NSString).expandingTildeInPath)
    }

    /// Environment for the sidecar process. A GUI app launched from Finder /
    /// `/Applications` inherits LaunchServices' minimal `PATH`
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`), which omits Homebrew — so
    /// `parakeet-mlx` / `mlx-whisper` can't find `ffmpeg` and transcription
    /// fails with "FFmpeg is not installed or not in your PATH". Prepend the
    /// Homebrew prefixes and the Python venv's own `bin` so the audio decoder is
    /// always resolvable regardless of how the app was launched.
    static func childEnvironment(python: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var prefixes = ["/opt/homebrew/bin", "/usr/local/bin"]
        // The venv's bin dir (…/bin/python → …/bin) often holds tools too.
        prefixes.append(python.deletingLastPathComponent().path)
        let existing = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        var seen = Set<String>()
        let merged = (prefixes + existing).filter { seen.insert($0).inserted && !$0.isEmpty }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    // MARK: - Request

    /// Sends one request and returns the trimmed `text` from the response.
    /// Throws `TranscriptionError.failed` on an `ok:false` reply.
    func send(_ request: [String: String]) async throws -> String {
        try ensureRunning()
        guard let stdin = stdinPipe else {
            throw TranscriptionError.sidecarUnavailable("no stdin pipe")
        }
        let payload = try JSONSerialization.data(withJSONObject: request)

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            guard pending == nil else {
                lock.unlock()
                cont.resume(throwing: TranscriptionError.failed("sidecar is busy"))
                return
            }
            pending = cont
            lock.unlock()

            var line = payload
            line.append(0x0A)
            stdin.fileHandleForWriting.write(line)
        }
    }

    // MARK: - Process lifecycle

    private func ensureRunning() throws {
        if let p = process, p.isRunning { return }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw TranscriptionError.sidecarUnavailable("sidecar script not found at \(scriptURL.path)")
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = ["-u", scriptURL.path]
        proc.environment = MLXSidecar.childEnvironment(python: pythonURL)

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.ingest(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.ingestStderr(data) }
        }

        do { try proc.run() }
        catch { throw TranscriptionError.sidecarUnavailable(error.localizedDescription) }

        process = proc
        stdinPipe = stdin
        log.info(.sidecar, "Sidecar started", detail: "\(pythonURL.path) \(scriptURL.path)")
    }

    /// Surface the sidecar's stderr lines in the app log so model loads and
    /// Python-side failures are visible instead of silently discarded.
    private func ingestStderr(_ data: Data) {
        lock.lock()
        stderrBuffer.append(data)
        var lines: [String] = []
        while let nl = stderrBuffer.firstIndex(of: 0x0A) {
            let lineData = stderrBuffer.subdata(in: stderrBuffer.startIndex..<nl)
            stderrBuffer.removeSubrange(stderrBuffer.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                lines.append(s)
            }
        }
        lock.unlock()
        for line in lines {
            let level: LogLevel = line.lowercased().contains("error") ? .warning : .info
            log.log(level, .sidecar, line)
        }
    }

    private func ingest(_ data: Data) {
        lock.lock()
        stdoutBuffer.append(data)
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
            cont.resume(returning: (resp.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            cont.resume(throwing: TranscriptionError.failed(resp.error ?? "sidecar error"))
        }
    }
}
