import XCTest
@testable import SketchyBarToggleCore

final class AnimatedHideTests: XCTestCase {
    func testHideWaitsForAnimation() {
        var commands: [[String]] = []
        let controller = SketchyBarController { commands.append($0) }
        controller.hide()
        XCTAssertEqual(commands, [["--animate", "sin", "9", "--bar", "y_offset=-34"]])
        let finished = expectation(description: "animation completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(commands.last, ["--bar", "hidden=on", "y_offset=0"])
    }

    func testQuickReturnCancelsDelayedHide() {
        var commands: [[String]] = []
        let controller = SketchyBarController { commands.append($0) }
        controller.hide()
        controller.show()
        let finished = expectation(description: "old hide deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(commands.contains { $0.contains("hidden=on") })
        XCTAssertEqual(commands.last, ["--animate", "sin", "12", "--bar", "y_offset=0"])
    }
}
