import XCTest
@testable import VoiceDictation

final class MLXSidecarTests: XCTestCase {
    /// A GUI app launched from Finder inherits a minimal PATH that omits
    /// Homebrew, so the sidecar can't find `ffmpeg`. `childEnvironment` must
    /// guarantee the Homebrew prefixes are on PATH regardless of what the app
    /// inherited. (Regression: "FFmpeg is not installed or not in your PATH".)
    func testChildEnvironmentAlwaysIncludesHomebrew() {
        let python = URL(fileURLWithPath: "/Users/me/dev/transcriber/.venv/bin/python")
        let env = MLXSidecar.childEnvironment(python: python)
        let path = env["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init)

        XCTAssertTrue(dirs.contains("/opt/homebrew/bin"), "PATH must include Homebrew: \(path)")
        XCTAssertTrue(dirs.contains("/usr/local/bin"), "PATH must include /usr/local/bin: \(path)")
        XCTAssertTrue(dirs.contains("/Users/me/dev/transcriber/.venv/bin"),
                      "PATH must include the venv bin: \(path)")
    }

    /// Homebrew must come first so its tools win, and no dir may be duplicated.
    func testChildEnvironmentPrependsAndDedupes() {
        let python = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        let env = MLXSidecar.childEnvironment(python: python)
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        XCTAssertEqual(dirs.first, "/opt/homebrew/bin", "Homebrew should be first on PATH")
        XCTAssertEqual(dirs.count, Set(dirs).count, "PATH must not contain duplicates: \(dirs)")
    }

    /// A request sent while another is in flight (e.g. a dictation during the
    /// launch-time model warm-up) must queue and succeed, not fail as "busy".
    func testConcurrentRequestsQueueInOrder() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake_sidecar_\(UUID().uuidString).py")
        try """
        import json, sys, time
        for line in sys.stdin:
            req = json.loads(line)
            time.sleep(0.3 if req["op"] == "warm" else 0.0)
            print(json.dumps({"ok": True, "text": req["op"]}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }

        let sidecar = MLXSidecar(pythonURL: URL(fileURLWithPath: "/usr/bin/python3"), scriptURL: script)
        async let warm = sidecar.send(["op": "warm"])
        try await Task.sleep(nanoseconds: 50_000_000)  // warm is in flight
        let take = try await sidecar.send(["op": "transcribe"])
        let warmed = try await warm
        XCTAssertEqual(warmed, "warm")
        XCTAssertEqual(take, "transcribe")
    }
}
