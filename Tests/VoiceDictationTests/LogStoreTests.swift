import XCTest
@testable import VoiceDictation

final class LogStoreTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("log-test-\(UUID()).json")
    }

    func testWritePersistsAndSurvivesReload() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = LogStore(fileURL: url)
        store.error(.permission, "Accessibility not granted", detail: "re-grant it")
        store.flush()

        let reloaded = LogStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.level, .error)
        XCTAssertEqual(reloaded.entries.first?.category, .permission)
        XCTAssertEqual(reloaded.entries.first?.message, "Accessibility not granted")
        XCTAssertEqual(reloaded.entries.first?.detail, "re-grant it")
    }

    func testNewestFirstOrdering() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LogStore(fileURL: url)
        store.info(.system, "first")
        store.info(.system, "second")
        store.flush()
        XCTAssertEqual(store.entries.first?.message, "second")
    }

    func testCapTrimsOldestKeepingNewest() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LogStore(fileURL: url)
        for i in 0..<600 { store.info(.system, "e\(i)") }
        store.flush()
        XCTAssertEqual(store.entries.count, 500)       // capped
        XCTAssertEqual(store.entries.first?.message, "e599")  // newest kept
        XCTAssertEqual(store.entries.last?.message, "e100")   // oldest beyond cap trimmed
    }

    func testClearEmptiesAndPersists() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LogStore(fileURL: url)
        store.warning(.sidecar, "x")
        store.flush()
        store.clear()
        store.flush()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(LogStore(fileURL: url).entries.isEmpty)
    }

    func testLevelOrdering() {
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
    }

    func testLevelFilterIncludes() {
        XCTAssertTrue(LevelFilter.all.includes(.info))
        XCTAssertFalse(LevelFilter.warningsAndErrors.includes(.info))
        XCTAssertTrue(LevelFilter.warningsAndErrors.includes(.warning))
        XCTAssertTrue(LevelFilter.warningsAndErrors.includes(.error))
        XCTAssertFalse(LevelFilter.errorsOnly.includes(.warning))
        XCTAssertTrue(LevelFilter.errorsOnly.includes(.error))
    }
}

@MainActor
final class LogModelTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("logmodel-test-\(UUID()).json")
    }

    func testSearchMatchesMessageCategoryAndDetail() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LogStore(fileURL: url)
        store.error(.insertion, "Couldn't insert text", detail: "frontmost was Safari")
        store.info(.transcription, "Transcribed 12 characters")
        store.flush()

        let model = LogModel(store: store)  // seeds entries from the flushed store

        model.search = "safari"   // matches detail
        XCTAssertEqual(model.sections.flatMap(\.entries).count, 1)

        model.search = "insertion"  // matches category
        XCTAssertEqual(model.sections.flatMap(\.entries).count, 1)

        model.search = "transcribed"  // matches message
        XCTAssertEqual(model.sections.flatMap(\.entries).count, 1)
    }

    func testFilterNarrowsToErrors() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LogStore(fileURL: url)
        store.info(.system, "launched")
        store.warning(.sidecar, "slow load")
        store.error(.permission, "no accessibility")
        store.flush()

        let model = LogModel(store: store)  // seeds entries from the flushed store

        model.filter = .errorsOnly
        XCTAssertEqual(model.sections.flatMap(\.entries).map(\.message), ["no accessibility"])
        XCTAssertTrue(model.hasErrors)
    }
}
