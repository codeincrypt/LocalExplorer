import XCTest
@testable import ExplorerCore

final class ThisMacTests: XCTestCase {
    func testThisMacURLIsRecognisedAndNeverARealFolder() {
        XCTAssertTrue(ThisMac.isThisMac(ThisMac.url))
        XCTAssertTrue(ThisMac.isThisMac(URL(fileURLWithPath: "/.this-mac/")))
        XCTAssertFalse(ThisMac.isThisMac(URL(fileURLWithPath: "/")))
        XCTAssertFalse(ThisMac.isThisMac(URL(fileURLWithPath: "/Users")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ThisMac.url.path))
    }

    func testBreadcrumbsAndAbbreviationForThisMac() {
        let crumbs = PathBreadcrumbs.components(for: ThisMac.url, home: URL(fileURLWithPath: "/Users/me"))
        XCTAssertEqual(crumbs.map(\.name), [ThisMac.title])
        XCTAssertEqual(crumbs.first?.url, ThisMac.url)
        XCTAssertEqual(PathBreadcrumbs.abbreviated(ThisMac.url, home: URL(fileURLWithPath: "/Users/me")), ThisMac.title)
    }

    func testHistoryTreatsThisMacLikeAnyLocation() {
        var history = NavigationHistory(start: URL(fileURLWithPath: "/"))
        history.visit(ThisMac.url)
        XCTAssertTrue(ThisMac.isThisMac(history.current))
        XCTAssertEqual(history.goBack()?.path, "/")
        XCTAssertTrue(ThisMac.isThisMac(history.goForward() ?? URL(fileURLWithPath: "/")))
    }

    func testCapacityUsage() {
        let usage = CapacityUsage(total: 63_300_000_000, available: 18_300_000_000)
        XCTAssertEqual(usage.used, 45_000_000_000)
        XCTAssertEqual(usage.usedFraction, 45.0 / 63.3, accuracy: 0.0001)
        XCTAssertFalse(usage.isLow)
        XCTAssertEqual(usage.summary, "18.3 GB free of 63.3 GB")
    }

    func testCapacityIsLowAtNinetyPercentUsed() {
        XCTAssertTrue(CapacityUsage(total: 1000, available: 100).isLow)
        XCTAssertFalse(CapacityUsage(total: 1000, available: 101).isLow)
    }

    func testCapacityClampsInconsistentValues() {
        let over = CapacityUsage(total: 100, available: 500)
        XCTAssertEqual(over.available, 100)
        XCTAssertEqual(over.usedFraction, 0)
        let empty = CapacityUsage(total: 0, available: 0)
        XCTAssertEqual(empty.usedFraction, 0)
        XCTAssertFalse(empty.isLow)
        XCTAssertEqual(CapacityUsage(total: 100, available: -5).available, 0)
    }

    func testCapacityOfRealVolume() throws {
        let usage = try XCTUnwrap(FileSystemFacts.capacity(at: URL(fileURLWithPath: "/")))
        XCTAssertGreaterThan(usage.total, 0)
        XCTAssertLessThanOrEqual(usage.available, usage.total)
    }
}
