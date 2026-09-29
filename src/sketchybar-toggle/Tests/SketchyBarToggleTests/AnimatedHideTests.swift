import XCTest
@testable import SketchyBarToggleCore

final class AnimatedHideTests: XCTestCase {
    func testSmoothSlideStaysOpaqueAndWaitsBeforeHiding() {
        var commands: [[String]] = []
        let controller = SketchyBarController(commandRunner: { commands.append($0) }, useSmoothSlide: true)
        controller.show()
        XCTAssertTrue(commands[0].contains("y_offset=-32"))
        XCTAssertFalse(commands[0].contains("--set"), "Reveal must not repaint item styles")
        controller.hide()
        XCTAssertEqual(commands.last, ["--animate", "sin", "16", "--bar", "y_offset=-32"])
        let finished = expectation(description: "smooth slide completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(commands.contains { $0.contains("hidden=on") })
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(commands.last, ["--bar", "hidden=on", "y_offset=0"])
    }

    func testSmoothSlideReversalDoesNotJumpToStart() {
        var commands: [[String]] = []
        let controller = SketchyBarController(commandRunner: { commands.append($0) }, useSmoothSlide: true)
        controller.show()
        controller.hide()
        commands.removeAll()
        controller.show()
        XCTAssertEqual(commands, [["--animate", "sin", "16", "--bar", "y_offset=0"]])
        let finished = expectation(description: "cancelled smooth slide deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(commands.contains { $0.contains("hidden=on") })
    }

    func testFadeStartsTransparentWithoutMovingTheBar() {
        var commands: [[String]] = []
        let controller = SketchyBarController(commandRunner: { commands.append($0) }, useFade: true)
        controller.show()
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands[0].contains("icon.background.color=0x00242426"))
        XCTAssertTrue(commands[0].contains("hidden=off"))
        XCTAssertTrue(commands[1].contains("icon.background.color=0xff242426"))
        XCTAssertTrue(commands[1].contains("icon.background.image.scale=0.65"))
        XCTAssertFalse(commands.flatMap { $0 }.contains { $0.hasPrefix("y_offset=-") })
    }

    func testReversingFadeDoesNotResetToTransparentOrHideLater() {
        var commands: [[String]] = []
        let controller = SketchyBarController(commandRunner: { commands.append($0) }, useFade: true)
        controller.show()
        controller.hide()
        commands.removeAll()
        controller.show()
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].contains("icon.background.color=0xff242426"))
        let finished = expectation(description: "cancelled fade deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(commands.contains { $0.contains("hidden=on") })
    }

    func testLayoutIsPreparedBeforeFirstVisibleFrame() {
        var prepared = false
        var commands: [[String]] = []
        let controller = SketchyBarController(commandRunner: { command in
            XCTAssertTrue(prepared, "Layout must be ready before unhiding or animating")
            commands.append(command)
        }, prepareToShow: { prepared = true })
        controller.show()
        XCTAssertTrue(prepared)
        XCTAssertEqual(commands.count, 2)
    }

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
