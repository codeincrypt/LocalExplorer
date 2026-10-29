import XCTest
@testable import ExplorerCore

final class PhotoSequenceTests: XCTestCase {
    func testStepsForwardAndBackward() {
        let sequence = PhotoSequence(ids: ["a", "b", "c"], current: "b")
        XCTAssertEqual(sequence.target(offset: 1), "c")
        XCTAssertEqual(sequence.target(offset: -1), "a")
        XCTAssertEqual(sequence.positionDescription, "2 of 3")
    }

    func testStopsAtEnds() {
        let start = PhotoSequence(ids: ["a", "b", "c"], current: "a")
        XCTAssertNil(start.target(offset: -1))
        XCTAssertFalse(start.hasPrevious)
        XCTAssertTrue(start.hasNext)

        let end = PhotoSequence(ids: ["a", "b", "c"], current: "c")
        XCTAssertNil(end.target(offset: 1))
        XCTAssertFalse(end.hasNext)
        XCTAssertTrue(end.hasPrevious)
    }

    func testLargeOffsetClampsToEnd() {
        let sequence = PhotoSequence(ids: ["a", "b", "c"], current: "a")
        XCTAssertEqual(sequence.target(offset: 10), "c")
    }

    func testUnknownCurrentHasNoTarget() {
        let sequence = PhotoSequence(ids: ["a", "b"], current: "zzz")
        XCTAssertNil(sequence.currentID)
        XCTAssertNil(sequence.target(offset: 1))
        XCTAssertNil(sequence.positionDescription)
        XCTAssertFalse(sequence.hasNext)
    }

    func testEmptySequence() {
        let sequence = PhotoSequence(ids: [], current: nil)
        XCTAssertNil(sequence.target(offset: 1))
        XCTAssertNil(sequence.first)
    }
}
