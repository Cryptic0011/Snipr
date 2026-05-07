import XCTest
@testable import Snipr

final class HotKeyServiceTests: XCTestCase {
    /// Phase 0 acceptance criterion pins the Carbon HotKey signature to
    /// 0x534E5052 — the literal big-endian-natural packing of "SNPR". Asserts
    /// the FourCharCode helper used by `HotKeyService.register` produces it.
    func testFourCharCodeForSNPRMatchesCanonicalSignature() {
        XCTAssertEqual("SNPR".fourCharCode, 0x534E5052)
    }

    func testFourCharCodePacksFirstFourASCIIBytes() {
        XCTAssertEqual("ABCD".fourCharCode, 0x41424344)
        XCTAssertEqual("snpr".fourCharCode, 0x736E7072)
    }
}
