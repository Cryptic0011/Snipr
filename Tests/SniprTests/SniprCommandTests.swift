import Carbon
import XCTest
@testable import Snipr

final class SniprCommandTests: XCTestCase {
    func testAllCommandsMatchMVPOrder() {
        XCTAssertEqual(
            SniprCommand.all.map(\.id),
            [.captureToolbar, .captureArea, .captureWindow, .recordArea, .ocrSelection, .showOCRHistory, .pickColor, .scanQR, .toggleDesktopIcons, .scrollingCapture, .openHistory, .clearStack, .openSettings, .quit]
        )
    }

    func testURLSchemeParsesRawValueDashedAndAliasForms() throws {
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://captureArea"))), .captureArea)
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://capture-area"))), .captureArea)
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://SCROLLING_CAPTURE"))), .scrollingCapture)
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://capture"))), .captureArea)
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://record"))), .recordArea)
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://ocr"))), .ocrSelection)
        // No-authority form (`snipr:capture`) puts the token in the path.
        XCTAssertEqual(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr:capture"))), .captureArea)
    }

    func testURLSchemeRejectsWrongSchemeAndUnknownCommands() throws {
        XCTAssertNil(SniprCommandID(url: try XCTUnwrap(URL(string: "https://capture-area"))))
        XCTAssertNil(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://make-coffee"))))
        XCTAssertNil(SniprCommandID(url: try XCTUnwrap(URL(string: "snipr://"))))
    }

    func testBlankSearchReturnsAllCommands() {
        XCTAssertEqual(SniprCommand.filtered(by: "   "), SniprCommand.all)
    }

    func testSearchMatchesTitleAndSubtitleTokens() {
        XCTAssertEqual(SniprCommand.filtered(by: "capture").map(\.id), [.captureToolbar, .captureArea, .captureWindow, .scrollingCapture])
        XCTAssertEqual(SniprCommand.filtered(by: "toolbar").map(\.id), [.captureToolbar])
        XCTAssertEqual(SniprCommand.filtered(by: "record").map(\.id), [.recordArea])
        XCTAssertEqual(SniprCommand.filtered(by: "scroll stitch").map(\.id), [.scrollingCapture])
        XCTAssertEqual(SniprCommand.filtered(by: "local captures").map(\.id), [.openHistory])
    }

    func testSearchRequiresEveryTokenToMatch() {
        XCTAssertEqual(SniprCommand.filtered(by: "open settings").map(\.id), [.openSettings])
        XCTAssertTrue(SniprCommand.filtered(by: "open missing").isEmpty)
    }

    func testShortcutHintsFollowRebinding() {
        var bindings = HotKeyDefaults.bindings
        bindings[.captureArea] = HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: hotKeyModifiers(command: true, option: true),
            isEnabled: true
        )
        bindings[.ocr]?.isEnabled = false

        let commands = SniprCommand.all(bindings: bindings)
        XCTAssertEqual(commands.first { $0.id == .captureArea }?.shortcut, bindings[.captureArea]?.displayText)
        XCTAssertEqual(commands.first { $0.id == .ocrSelection }?.shortcut, "")
        // Non-hotkey commands keep their fixed system shortcuts.
        XCTAssertEqual(commands.first { $0.id == .openSettings }?.shortcut, "⌘,")
    }
}
