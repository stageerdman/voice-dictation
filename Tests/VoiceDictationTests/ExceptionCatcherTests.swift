import AVFoundation
import ObjCExceptionCatcher
import XCTest

/// AVAudioEngine signals bad states with NSExceptions, which Swift can't catch.
/// Uncaught inside the hotkey callback they silently killed every later press,
/// so the recorder routes them through this shim — lock in that it works.
final class ExceptionCatcherTests: XCTestCase {
    func testConvertsNSExceptionToError() {
        XCTAssertThrowsError(try ObjCExceptionCatcher.catchException {
            NSException(name: .internalInconsistencyException, reason: "boom", userInfo: nil).raise()
        }) { error in
            XCTAssertEqual(error.localizedDescription, "boom")
        }
    }

    func testPassesThroughWhenNoException() throws {
        var ran = false
        try ObjCExceptionCatcher.catchException { ran = true }
        XCTAssertTrue(ran)
    }
}
