import XCTest
@testable import ExplorerCore

final class NavigationTests: XCTestCase {
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/a/b"), c = URL(fileURLWithPath: "/a/b/c")

    func testBackForward() {
        var h = NavigationHistory(start: a)
        h.visit(b); h.visit(c)
        XCTAssertTrue(h.canGoBack)
        XCTAssertEqual(h.goBack(), b)
        XCTAssertEqual(h.goBack(), a)
        XCTAssertNil(h.goBack())
        XCTAssertEqual(h.goForward(), b)
        XCTAssertEqual(h.current, b)
    }

    func testVisitClearsForwardAndIgnoresSameLocation() {
        var h = NavigationHistory(start: a)
        h.visit(b); h.goBack()
        h.visit(a)
        XCTAssertTrue(h.canGoForward)
        h.visit(c)
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.backStack, [a])
    }

    func testHistoryLimit() {
        var h = NavigationHistory(start: a, limit: 3)
        for i in 0..<10 { h.visit(URL(fileURLWithPath: "/p\(i)")) }
        XCTAssertEqual(h.backStack.count, 3)
    }

    func testBreadcrumbsInsideHome() {
        let home = URL(fileURLWithPath: "/Users/kartik")
        let crumbs = PathBreadcrumbs.components(for: URL(fileURLWithPath: "/Users/kartik/Pictures/Selected"), home: home)
        XCTAssertEqual(crumbs.map(\.name), ["kartik", "Pictures", "Selected"])
        XCTAssertEqual(crumbs.last?.url.path, "/Users/kartik/Pictures/Selected")
    }

    func testBreadcrumbsOutsideHome() {
        let crumbs = PathBreadcrumbs.components(for: URL(fileURLWithPath: "/Volumes/Flash/DCIM"), home: URL(fileURLWithPath: "/Users/k"), rootName: "Macintosh HD")
        XCTAssertEqual(crumbs.map(\.name), ["Macintosh HD", "Volumes", "Flash", "DCIM"])
        XCTAssertEqual(crumbs[1].url.path, "/Volumes")
    }

    func testIsDescendant() {
        XCTAssertTrue(PathBreadcrumbs.isDescendant(c, of: a))
        XCTAssertFalse(PathBreadcrumbs.isDescendant(a, of: a))
        XCTAssertTrue(PathBreadcrumbs.isDescendant(a, of: a, orEqual: true))
        XCTAssertFalse(PathBreadcrumbs.isDescendant(URL(fileURLWithPath: "/ab"), of: a))
    }

    func testAbbreviatedPath() {
        let home = URL(fileURLWithPath: "/Users/k")
        XCTAssertEqual(PathBreadcrumbs.abbreviated(URL(fileURLWithPath: "/Users/k/Documents"), home: home), "~/Documents")
        XCTAssertEqual(PathBreadcrumbs.abbreviated(home, home: home), "~")
        XCTAssertEqual(PathBreadcrumbs.abbreviated(URL(fileURLWithPath: "/tmp"), home: home), "/tmp")
    }

    func testPathInput() {
        let home = URL(fileURLWithPath: "/Users/k"), base = URL(fileURLWithPath: "/Users/k/Documents")
        XCTAssertEqual(PathInputParser.resolve("~", relativeTo: base, home: home)?.path, "/Users/k")
        XCTAssertEqual(PathInputParser.resolve("~/Downloads/", relativeTo: base, home: home)?.path, "/Users/k/Downloads")
        XCTAssertEqual(PathInputParser.resolve("/tmp/../var", relativeTo: base, home: home)?.path, "/var")
        XCTAssertEqual(PathInputParser.resolve("Projects", relativeTo: base, home: home)?.path, "/Users/k/Documents/Projects")
        XCTAssertEqual(PathInputParser.resolve("..", relativeTo: base, home: home)?.path, "/Users/k")
        XCTAssertEqual(PathInputParser.resolve("file:///Applications", relativeTo: base, home: home)?.path, "/Applications")
        XCTAssertEqual(PathInputParser.resolve("\"/Volumes/My Disk\"", relativeTo: base, home: home)?.path, "/Volumes/My Disk")
        XCTAssertNil(PathInputParser.resolve("https://example.com", relativeTo: base, home: home))
        XCTAssertNil(PathInputParser.resolve("   ", relativeTo: base, home: home))
    }

    func testRecentLocations() {
        var r = RecentLocations(limit: 3)
        r.record(a); r.record(b); r.record(a); r.record(c); r.record(URL(fileURLWithPath: "/z"))
        XCTAssertEqual(r.paths, ["/z", "/a/b/c", "/a"])
    }
}

final class SelectionTests: XCTestCase {
    let order = ["a", "b", "c", "d", "e", "f", "g"]

    func testPlainClickSelectsOne() {
        var s = SelectionModel()
        s.click("c", order: order)
        XCTAssertEqual(s.selected, ["c"])
        s.click("e", order: order)
        XCTAssertEqual(s.selected, ["e"])
    }

    func testCommandClickToggles() {
        var s = SelectionModel()
        s.click("a", order: order)
        s.click("c", order: order, modifiers: .toggle)
        XCTAssertEqual(s.selected, ["a", "c"])
        s.click("a", order: order, modifiers: .toggle)
        XCTAssertEqual(s.selected, ["c"])
    }

    func testShiftClickSelectsRangeFromAnchor() {
        var s = SelectionModel()
        s.click("b", order: order)
        s.click("e", order: order, modifiers: .extend)
        XCTAssertEqual(s.selected, ["b", "c", "d", "e"])
        s.click("a", order: order, modifiers: .extend)
        XCTAssertEqual(s.selected, ["a", "b"])
    }

    func testCommandShiftAddsRange() {
        var s = SelectionModel()
        s.click("a", order: order)
        s.click("e", order: order, modifiers: .toggle)
        s.click("g", order: order, modifiers: [.toggle, .extend])
        XCTAssertEqual(s.selected, ["a", "e", "f", "g"])
    }

    func testArrowKeysInList() {
        var s = SelectionModel()
        XCTAssertEqual(s.move(.down, order: order, arrangement: .list), "a")
        XCTAssertEqual(s.move(.down, order: order, arrangement: .list), "b")
        XCTAssertEqual(s.move(.down, order: order, arrangement: .list, extend: true), "c")
        XCTAssertEqual(s.selected, ["b", "c"])
        XCTAssertEqual(s.move(.up, order: order, arrangement: .list), "b")
        XCTAssertEqual(s.selected, ["b"])
        XCTAssertEqual(s.move(.end, order: order, arrangement: .list), "g")
        XCTAssertEqual(s.move(.down, order: order, arrangement: .list), "g")
    }

    func testArrowKeysInGrid() {
        var s = SelectionModel()
        s.click("b", order: order)
        XCTAssertEqual(s.move(.down, order: order, arrangement: .rowMajor(columns: 3)), "e")
        XCTAssertEqual(s.move(.down, order: order, arrangement: .rowMajor(columns: 3)), "g") // last row is partial
        XCTAssertEqual(s.move(.up, order: order, arrangement: .rowMajor(columns: 3)), "d")
        XCTAssertEqual(s.move(.right, order: order, arrangement: .rowMajor(columns: 3)), "e")
    }

    func testArrowKeysInColumnMajor() {
        var s = SelectionModel()
        s.click("a", order: order)
        XCTAssertEqual(s.move(.right, order: order, arrangement: .columnMajor(rows: 3)), "d")
        XCTAssertEqual(s.move(.right, order: order, arrangement: .columnMajor(rows: 3)), "g")
        XCTAssertEqual(s.move(.left, order: order, arrangement: .columnMajor(rows: 3)), "d")
        XCTAssertEqual(s.move(.down, order: order, arrangement: .columnMajor(rows: 3)), "e")
    }

    func testReconcileKeepsSurvivors() {
        var s = SelectionModel()
        s.selectAll(order: order)
        s.reconcile(with: ["a", "c", "z"])
        XCTAssertEqual(s.selected, ["a", "c"])
        XCTAssertNotNil(s.cursor)
    }

    func testReplaceFromTable() {
        var s = SelectionModel()
        s.replace(with: ["c", "e"], order: order)
        XCTAssertEqual(s.anchor, "c")
        XCTAssertEqual(s.cursor, "e")
    }

    func testGridMath() {
        XCTAssertEqual(GridLayoutMath.columns(availableWidth: 500, itemWidth: 100, spacing: 12, padding: 12), 4)
        XCTAssertEqual(GridLayoutMath.columns(availableWidth: 50, itemWidth: 100, spacing: 12), 1)
        XCTAssertEqual(GridLayoutMath.rows(availableHeight: 240, rowHeight: 22, spacing: 2), 10)
    }
}
