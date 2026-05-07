import XCTest
@testable import Snipr

@MainActor
final class OCRHistoryStoreTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "OCRHistoryStoreTests-" + UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    func testAppendIgnoresWhitespaceOnlyEntries() {
        let store = OCRHistoryStore(defaults: makeIsolatedDefaults())
        store.append(text: "   \n\t  ")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEntriesAreOrderedNewestFirst() {
        let store = OCRHistoryStore(defaults: makeIsolatedDefaults())
        store.append(text: "first")
        store.append(text: "second")
        XCTAssertEqual(store.entries.first?.text, "second")
        XCTAssertEqual(store.entries.last?.text, "first")
    }

    func testDuplicatesAreDeduplicatedAndPromoted() {
        let store = OCRHistoryStore(defaults: makeIsolatedDefaults())
        store.append(text: "alpha")
        store.append(text: "beta")
        store.append(text: "alpha")
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.text, "alpha")
    }

    func testCapAtMaxEntriesEvictsOldest() {
        let store = OCRHistoryStore(defaults: makeIsolatedDefaults())
        for index in 0..<(OCRHistoryStore.maxEntries + 5) {
            store.append(text: "entry-\(index)")
        }
        XCTAssertEqual(store.entries.count, OCRHistoryStore.maxEntries)
        // Newest first — confirm the oldest were dropped.
        XCTAssertEqual(store.entries.first?.text, "entry-\(OCRHistoryStore.maxEntries + 4)")
        XCTAssertFalse(store.entries.contains(where: { $0.text == "entry-0" }))
    }

    func testRoundTripPersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let storeA = OCRHistoryStore(defaults: defaults)
        storeA.append(text: "persist me")
        let storeB = OCRHistoryStore(defaults: defaults)
        XCTAssertEqual(storeB.entries.first?.text, "persist me")
    }

    func testPreviewReturnsFirstNonEmptyLine() {
        let entry = OCRHistoryEntry(text: "\n  \nfirst line\nsecond line")
        XCTAssertEqual(entry.preview, "first line")
    }

    func testClearEmptiesEntries() {
        let store = OCRHistoryStore(defaults: makeIsolatedDefaults())
        store.append(text: "a")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}
