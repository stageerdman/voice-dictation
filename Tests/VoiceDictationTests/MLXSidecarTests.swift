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
}
