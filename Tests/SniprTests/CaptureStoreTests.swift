import XCTest
@testable import Snipr

final class CaptureStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testAddCapturePersistsImageAndMetadata() throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let item = try store.addCapture(
            pngData: samplePNGData(),
            pixelSize: CGSize(width: 10, height: 8),
            displayID: 42
        )

        XCTAssertEqual(store.items.map(\.id), [item.id])
        XCTAssertEqual(item.pixelWidth, 10)
        XCTAssertEqual(item.pixelHeight, 8)
        XCTAssertEqual(item.displayID, 42)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.appending(path: "captures.json").path))
    }

    func testNewStoreLoadsPersistedCaptures() throws {
        let firstStore = CaptureStore(rootDirectory: tempRoot)
        let item = try firstStore.addCapture(
            pngData: samplePNGData(),
            pixelSize: CGSize(width: 6, height: 4),
            displayID: nil
        )

        let secondStore = CaptureStore(rootDirectory: tempRoot)

        XCTAssertEqual(secondStore.items.count, 1)
        XCTAssertEqual(secondStore.items.first?.id, item.id)
        XCTAssertEqual(secondStore.items.first?.sourceType, .area)
    }

    func testDeleteRemovesMetadataAndFile() throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let item = try store.addCapture(
            pngData: samplePNGData(),
            pixelSize: CGSize(width: 10, height: 8),
            displayID: nil
        )

        try store.delete(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path))
        XCTAssertTrue(CaptureStore(rootDirectory: tempRoot).items.isEmpty)
    }

    func testClearStackRemovesAllMetadataAndFiles() throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let first = try store.addCapture(pngData: samplePNGData(), pixelSize: CGSize(width: 1, height: 1), displayID: nil)
        let second = try store.addCapture(pngData: samplePNGData(), pixelSize: CGSize(width: 2, height: 2), displayID: nil)

        try store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.fileURL.path))
        XCTAssertTrue(CaptureStore(rootDirectory: tempRoot).items.isEmpty)
    }

    private func samplePNGData() -> Data {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
    }
}
