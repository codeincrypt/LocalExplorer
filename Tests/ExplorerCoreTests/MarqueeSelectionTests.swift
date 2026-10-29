import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import ExplorerCore

final class MarqueeSelectionTests: XCTestCase {
    /// Three tiles in a row, 100 wide with 10 spacing.
    let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 100),
        "b": CGRect(x: 110, y: 0, width: 100, height: 100),
        "c": CGRect(x: 220, y: 0, width: 100, height: 100),
    ]
    let order = ["a", "b", "c"]

    func testRectNormalisesAnyDragDirection() {
        let r = MarqueeMath.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testHitsOnlyTouchedItems() {
        XCTAssertEqual(MarqueeMath.hits(in: CGRect(x: 90, y: 50, width: 30, height: 10), frames: frames), ["a", "b"])
        XCTAssertEqual(MarqueeMath.hits(in: CGRect(x: 105, y: 150, width: 300, height: 50), frames: frames), [])
        XCTAssertEqual(MarqueeMath.hits(in: CGRect(x: -10, y: -10, width: 500, height: 500), frames: frames), ["a", "b", "c"])
    }

    func testMarqueeReplacesSelection() {
        var s = SelectionModel(selected: ["a"])
        s.applyMarquee(hits: ["b", "c"], base: [], order: order)
        XCTAssertEqual(s.selected, ["b", "c"])
        XCTAssertEqual(s.anchor, "b")
        XCTAssertEqual(s.cursor, "c")
    }

    func testMarqueeExtendsBaseSelection() {
        var s = SelectionModel(selected: ["a"])
        s.applyMarquee(hits: ["c"], base: ["a"], order: order)
        XCTAssertEqual(s.selected, ["a", "c"])
    }

    func testShrinkingMarqueeDeselects() {
        var s = SelectionModel()
        s.applyMarquee(hits: ["a", "b"], base: [], order: order)
        s.applyMarquee(hits: ["a"], base: [], order: order)
        XCTAssertEqual(s.selected, ["a"])
        s.applyMarquee(hits: [], base: [], order: order)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.cursor)
    }
}
