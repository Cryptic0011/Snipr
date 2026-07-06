import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Snipr

final class MultiFileDragViewTests: XCTestCase {
    func testDragPasteboardItemPublishesCompatibilityTypes() {
        let item = FileDragPasteboardItem.make(url: URL(fileURLWithPath: "/tmp/Snipr Test.png"))
        let types = item.types

        XCTAssertTrue(
            types.contains(.fileURL),
            "Finder and most file destinations should see the modern public.file-url flavor."
        )
        XCTAssertTrue(
            types.contains(.URL),
            "Messages and older AppKit drop targets should see the Apple URL pasteboard flavor."
        )
        XCTAssertTrue(
            types.contains(.string),
            "Text-oriented drop targets should be able to fall back to the file path."
        )
    }

    func testDragPasteboardItemProvidesExpectedPayloads() {
        let url = URL(fileURLWithPath: "/tmp/Snipr Test.png")
        let item = FileDragPasteboardItem.make(url: url)

        XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
        XCTAssertEqual(item.string(forType: .sniprPublicURL), url.absoluteString)
        XCTAssertEqual(item.string(forType: .URL), url.absoluteString)
        XCTAssertEqual(item.string(forType: .string), url.path)
    }

    func testDragPasteboardItemCanBeWrittenToPasteboard() {
        let pasteboard = NSPasteboard(name: .init("SniprDragWriterPasteboardTests"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }

        let url = URL(fileURLWithPath: "/tmp/Snipr Test.png")
        XCTAssertTrue(pasteboard.writeObjects([FileDragPasteboardItem.make(url: url)]))
        XCTAssertTrue(pasteboard.types?.contains(.fileURL) == true)
        XCTAssertTrue(pasteboard.types?.contains(.sniprPublicURL) == true)
        XCTAssertTrue(pasteboard.types?.contains(.URL) == true)
        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
    }
}
