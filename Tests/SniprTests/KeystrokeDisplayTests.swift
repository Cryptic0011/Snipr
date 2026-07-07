import AppKit
import XCTest
@testable import Snipr

final class KeystrokeDisplayTests: XCTestCase {
    func testPlainCharacterUppercases() {
        XCTAssertEqual(KeystrokeDisplay.text(keyCode: 0, modifiers: [], characters: "a"), "A")
    }

    func testModifiersPrefixInCanonicalOrder() {
        XCTAssertEqual(
            KeystrokeDisplay.text(keyCode: 1, modifiers: [.command, .shift], characters: "s"),
            "⇧⌘S"
        )
    }

    func testSpecialKeysUseSymbols() {
        XCTAssertEqual(KeystrokeDisplay.text(keyCode: 53, modifiers: [], characters: "\u{1B}"), "Esc")
        XCTAssertEqual(KeystrokeDisplay.text(keyCode: 36, modifiers: [.command], characters: "\r"), "⌘⏎")
        XCTAssertEqual(KeystrokeDisplay.text(keyCode: 126, modifiers: [], characters: nil), "↑")
    }

    func testControlCharactersWithoutMappingAreDropped() {
        // keyCode 96 = F5; charactersIgnoringModifiers is a function-key
        // control scalar we don't map — only modifiers should remain.
        XCTAssertEqual(
            KeystrokeDisplay.text(keyCode: 96, modifiers: [.command], characters: "\u{F708}"),
            "⌘"
        )
    }
}
