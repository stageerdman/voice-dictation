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
    private var pending: CheckedContinuation<String, Error>?
    private let lock = NSLock()

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

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.ingest(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        do { try proc.run() }
        catch { throw TranscriptionError.sidecarUnavailable(error.localizedDescription) }

        process = proc
        stdinPipe = stdin
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
