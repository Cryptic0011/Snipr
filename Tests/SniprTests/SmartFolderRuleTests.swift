import XCTest
@testable import Snipr

final class SmartFolderRuleTests: XCTestCase {
    func testCaseInsensitiveContainsMatch() {
        let rule = SmartFolderRule(appPattern: "safari", subfolder: "Browsers")
        XCTAssertTrue(rule.matches(appName: "Safari"))
        XCTAssertTrue(rule.matches(appName: "SAFARI Technology Preview"))
    }

    func testPartialContainsMatch() {
        let rule = SmartFolderRule(appPattern: "Code", subfolder: "Editors")
        XCTAssertTrue(rule.matches(appName: "Visual Studio Code"))
        XCTAssertTrue(rule.matches(appName: "Code"))
        XCTAssertFalse(rule.matches(appName: "Xcode") == false) // sanity: contains "Code"
        XCTAssertTrue(rule.matches(appName: "Xcode"))
    }

    func testEmptyPatternMatchesNothing() {
        let rule = SmartFolderRule(appPattern: "", subfolder: "Catchall")
        XCTAssertFalse(rule.matches(appName: "Safari"))
        XCTAssertFalse(rule.matches(appName: ""))
        XCTAssertFalse(rule.matches(appName: nil))
    }

    func testWhitespaceOnlyPatternMatchesNothing() {
        let rule = SmartFolderRule(appPattern: "   ", subfolder: "Catchall")
        XCTAssertFalse(rule.matches(appName: "Safari"))
    }

    func testNilOrEmptyAppNameNeverMatches() {
        let rule = SmartFolderRule(appPattern: "Safari", subfolder: "Browsers")
        XCTAssertFalse(rule.matches(appName: nil))
        XCTAssertFalse(rule.matches(appName: ""))
    }

    func testRouterReturnsFirstMatch() {
        let rules = [
            SmartFolderRule(appPattern: "Safari", subfolder: "Browsers"),
            SmartFolderRule(appPattern: "Safari", subfolder: "Other")
        ]
        XCTAssertEqual(SmartFolderRouter.subfolder(forAppName: "Safari", rules: rules), "Browsers")
    }

    func testRouterReturnsNilWhenNoMatch() {
        let rules = [
            SmartFolderRule(appPattern: "Safari", subfolder: "Browsers")
        ]
        XCTAssertNil(SmartFolderRouter.subfolder(forAppName: "Xcode", rules: rules))
        XCTAssertNil(SmartFolderRouter.subfolder(forAppName: nil, rules: rules))
    }

    func testRouterIgnoresEmptyDestination() {
        let rules = [
            SmartFolderRule(appPattern: "Safari", subfolder: "   ")
        ]
        XCTAssertNil(SmartFolderRouter.subfolder(forAppName: "Safari", rules: rules))
    }

    func testRouterReturnsNilForEmptyRules() {
        XCTAssertNil(SmartFolderRouter.subfolder(forAppName: "Safari", rules: []))
    }
}
