import Foundation

/// Cleanup via the local `claude` CLI (Claude Code) running headless — no API
/// key, uses the machine's existing authentication. The full prompt goes on
/// stdin (no shell, no arg-length limit, no injection from transcript text),
/// mirroring the `transcriber` project's proven approach. A fast model and no
/// extended thinking keep it as quick as the CLI allows.
struct ClaudeCLICleaner: TextCleaner {
    /// Fast, always-ready model for a mechanical edit task.
    private let model = "claude-haiku-4-5-20251001"
    private let timeout: TimeInterval = 60

    private static func binary() -> String? {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     ("~/.claude/local/claude" as NSString).expandingTildeInPath] {
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    func clean(_ text: String) async throws -> String {
        guard let binary = Self.binary() else { throw CleanerError.unavailable("claude CLI not found") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", "--model", model]

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let prompt = "\(CleanupPrompt.system)\n\n\(CleanupPrompt.user(text))"
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        stdin.fileHandleForWriting.closeFile()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CleanerError.requestFailed("claude CLI exited \(process.terminationStatus)")
        }
        return String(data: data, encoding: .utf8) ?? text
    }
}

/// Cleanup via an on-device MLX LLM served by the shared sidecar — fully
/// offline, no network, no key. The model loads once and stays warm.
struct LocalLLMCleaner: TextCleaner {
    func clean(_ text: String) async throws -> String {
        try await MLXSidecar.shared.send([
            "op": "clean",
            "text": text,
        ])
    }
}

enum CleanerError: LocalizedError {
    case unavailable(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let d): return d
        case .requestFailed(let d): return d
        }
    }
}
