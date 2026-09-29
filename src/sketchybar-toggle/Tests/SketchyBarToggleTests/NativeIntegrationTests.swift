import XCTest
@testable import SketchyBarToggleCore

final class NativeIntegrationTests: XCTestCase {
    func testMachArgumentsPreserveTitlesWithoutShellParsing() {
        let title = "label=João's \"window\" $(echo unsafe) — 😀"
        let bytes = SketchyBarIPC.encode(["--set", "front_app", title])
        XCTAssertEqual(Array(bytes.suffix(2)), [0, 0])
        let fields = bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(fields, ["--set", "front_app", title])
    }
    func testSpaceNumbersMatchBarAcrossDisplaysAndFullscreenSlots() {
        let displays: [[String: Any]] = [
            ["Current Space": ["id64": 20], "Spaces": [["id64": 10, "type": 0], ["id64": 15, "type": 4], ["id64": 20, "type": 0]]],
            ["Current Space": ["id64": 30], "Spaces": [["id64": 30, "type": 0]]]
        ]
        XCTAssertEqual(SpaceLayout.parse(displays), [NativeSpace(index: 1, id: 10, selected: false), NativeSpace(index: 3, id: 20, selected: true), NativeSpace(index: 4, id: 30, selected: true)])
    }
    func testIncompleteTopologyDoesNotEraseExistingSpaces() {
        XCTAssertNil(SpaceLayout.parse([]))
        XCTAssertNil(SpaceLayout.parse([["Spaces": [["id64": 10]]]]))
    }
}
