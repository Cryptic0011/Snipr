import XCTest
@testable import Snipr

final class SniprCommandTests: XCTestCase {
    func testAllCommandsMatchMVPOrder() {
        XCTAssertEqual(
            SniprCommand.all.map(\.id),
            [.captureArea, .recordArea, .openHistory, .clearStack, .openSettings, .quit]
        )
    }

    func testBlankSearchReturnsAllCommands() {
        XCTAssertEqual(SniprCommand.filtered(by: "   "), SniprCommand.all)
    }

    func testSearchMatchesTitleAndSubtitleTokens() {
        XCTAssertEqual(SniprCommand.filtered(by: "capture").map(\.id), [.captureArea])
        XCTAssertEqual(SniprCommand.filtered(by: "record").map(\.id), [.recordArea])
        XCTAssertEqual(SniprCommand.filtered(by: "local captures").map(\.id), [.openHistory])
    }

    func testSearchRequiresEveryTokenToMatch() {
        XCTAssertEqual(SniprCommand.filtered(by: "open settings").map(\.id), [.openSettings])
        XCTAssertTrue(SniprCommand.filtered(by: "open missing").isEmpty)
    }
}
