import XCTest
@testable import VoiceDictation

final class HistoryStoreTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("history-test-\(UUID()).json")
    }

    func testAddPersistsAndSurvivesReload() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HistoryStore(fileURL: url)
        let entry = DictationEntry(text: "hello world", date: Date(), duration: 1.2, targetApp: "Notes")
        store.add(entry)

        // A fresh store reading the same file must see the entry.
        let reloaded = HistoryStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.text, "hello world")
        XCTAssertEqual(reloaded.entries.first?.targetApp, "Notes")
    }

    func testNewestFirstOrdering() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)
        store.add(DictationEntry(text: "first", date: Date(), duration: 1, targetApp: nil))
        store.add(DictationEntry(text: "second", date: Date(), duration: 1, targetApp: nil))
        XCTAssertEqual(store.entries.first?.text, "second")
    }

    func testDeleteAndClear() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)
        let a = DictationEntry(text: "a", date: Date(), duration: 1, targetApp: nil)
        let b = DictationEntry(text: "b", date: Date(), duration: 1, targetApp: nil)
        store.add(a); store.add(b)
        store.delete(id: a.id)
        XCTAssertEqual(store.entries.map(\.text), ["b"])
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}
