import XCTest
@testable import SketchyBarToggleCore

final class MenuCoverStateTests: XCTestCase {
    func testGrowthIsImmediateAndShrinkWaitsForStableMenu() {
        var state = MenuCoverState()
        XCTAssertNil(state.update(width: 800, pid: 1, now: 0))
        XCTAssertNotNil(state.update(width: 400, pid: 2, now: 1))
        XCTAssertEqual(state.width, 800)
        XCTAssertNotNil(state.update(width: 400, pid: 2, now: 1.2))
        XCTAssertNil(state.update(width: 400, pid: 2, now: 1.5))
        XCTAssertEqual(state.width, 400)
        XCTAssertNil(state.update(width: 900, pid: 3, now: 1.6))
        XCTAssertEqual(state.width, 900)
    }

    func testRapidSwitchRestartsSettlingAndReturningCancelsShrink() {
        var state = MenuCoverState()
        _ = state.update(width: 900, pid: 1, now: 0)
        _ = state.update(width: 300, pid: 2, now: 1)
        _ = state.update(width: 500, pid: 3, now: 1.3)
        XCTAssertNotNil(state.update(width: 500, pid: 3, now: 1.5))
        XCTAssertEqual(state.width, 900)
        XCTAssertNil(state.update(width: 500, pid: 3, now: 1.8))
        _ = state.update(width: 200, pid: 4, now: 2)
        XCTAssertNil(state.update(width: 500, pid: 3, now: 2.1))
        XCTAssertEqual(state.width, 500)
    }
}
