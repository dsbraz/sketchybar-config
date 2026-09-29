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

final class AppLabelUpdateTests: XCTestCase {
    func testChangingAppNameDoesNotReloadUnchangedAppIcon() {
        let before = NativeAppPresentation(app: "com.example.app", label: "Old")
        let after = NativeAppPresentation(app: "com.example.app", label: "New")
        XCTAssertEqual(after.updates(after: before), ["--set", "front_app", "label=New"])
        XCTAssertEqual(after.updates(after: after), [])
    }
    func testSwitchingAppReloadsIconEvenWhenNameIsIdentical() {
        let before = NativeAppPresentation(app: "a", label: "Window")
        let after = NativeAppPresentation(app: "b", label: "Window")
        XCTAssertEqual(after.updates(after: before), ["--set", "front_app_icon", "icon.background.image=app.b"])
    }
    func testHiddenTailChangesDoNotSendAnUpdate() {
        let prefix = String(repeating: "Visible title ", count: 10)
        let before = NativeAppSnapshot(pid: 1, app: "a", name: prefix + "old tail").presentation(width: 150)
        let after = NativeAppSnapshot(pid: 1, app: "a", name: prefix + "new tail").presentation(width: 150)
        XCTAssertTrue(after.label.hasSuffix("…"))
        XCTAssertEqual(after.updates(after: before), [])
    }
    func testWidthChangeUpdatesPreviouslyClippedAppName() {
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "A long window title that should become visible")
        let narrow = snapshot.presentation(width: 70)
        let wide = snapshot.presentation(width: 500)
        XCTAssertNotEqual(narrow.label, wide.label)
        XCTAssertEqual(wide.updates(after: narrow), ["--set", "front_app", "label=\(snapshot.name)"])
        XCTAssertEqual(wide.updates(after: wide), [])
    }
    func testFirstPresentationSetsTextAndIconInOneTransaction() {
        let presentation = NativeAppPresentation(app: "a", label: "Window")
        XCTAssertEqual(presentation.updates(after: nil), ["--set", "front_app", "label=Window",
                       "--set", "front_app_icon", "icon.background.image=app.a"])
    }
    func testAppNameFitsAvailablePixelsAndPreservesGraphemes() {
        let text = String(repeating: "João 👨‍👩‍👧‍👦 — WWW iii ", count: 8)
        let fitted = AppLabelLayout.fit(text, width: 530)
        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertLessThanOrEqual(AppLabelLayout.textWidth(fitted), 530)
        XCTAssertTrue(text.hasPrefix(String(fitted.dropLast())))
        XCTAssertEqual(AppLabelLayout.fit("Curto", width: 530), "Curto")
        XCTAssertEqual(AppLabelLayout.fit(text, width: 0), "")
    }
}

final class CompactGeometryTests: XCTestCase {
    func testNotchEdgeDefinesSurfaceRegardlessOfWindowOrApp() {
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 1512, notchLeft: 663.5), 653)
    }
    func testExternalMonitorsEndNearCenterAtAnyWidth() {
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 2560, notchLeft: nil), 1270)
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 1080, notchLeft: nil), 530)
    }
}

final class BackdropMotionTests: XCTestCase {
    func testSinMotionHasCorrectEndpointsAndMidpoint() {
        let motion = BackdropMotion(from: 0, to: 32, started: 10, duration: 16.0 / 60.0)
        XCTAssertEqual(motion.offset(at: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(motion.offset(at: 10 + 8.0 / 60.0), 16, accuracy: 0.0001)
        XCTAssertEqual(motion.offset(at: 11), 32, accuracy: 0.0001)
    }
    func testReversingMotionStartsAtCurrentPosition() {
        var motion = BackdropMotion(from: 0, to: 32, started: 10, duration: 0.4)
        motion.move(to: 0, at: 10.2, duration: 0.4)
        XCTAssertEqual(motion.offset(at: 10.2), 16, accuracy: 0.0001)
        XCTAssertEqual(motion.offset(at: 10.6), 0, accuracy: 0.0001)
    }
}

final class MenuMeasurementTests: XCTestCase {
    func testExtentUsesMenuDisplayRatherThanPrimaryDisplayOrigin() {
        let display = CGRect(x: -1512, y: 592, width: 1512, height: 982)
        let items = [CGRect(x: -1496, y: 592, width: 32, height: 32),
                     CGRect(x: -1464, y: 592, width: 150, height: 32),
                     CGRect(x: -1200, y: 592, width: 90, height: 32)]
        XCTAssertEqual(MenuMeasurement.extent(items: items, displays: [CGRect(x: 0, y: 0, width: 2560, height: 1440), display]), 402)
    }
    func testMissingOrInvalidGeometryDoesNotBecomeZeroWidth() {
        let displays = [CGRect(x: 0, y: 0, width: 1080, height: 1920)]
        XCTAssertNil(MenuMeasurement.extent(items: [], displays: displays))
        XCTAssertNil(MenuMeasurement.extent(items: [.zero], displays: displays))
        XCTAssertNil(MenuMeasurement.extent(items: [CGRect(x: 20, y: 0, width: 2000, height: 32)], displays: displays))
    }
    func testMeasuredMenusCanExpandAndShrinkWithoutAppCache() {
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 2560, notchLeft: nil, menuEnd: 900), 912)
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 2560, notchLeft: nil, menuEnd: 450), 462)
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 2560, notchLeft: nil, menuEnd: 100), 320)
        XCTAssertEqual(CompactSurfaceGeometry.end(screenWidth: 1080, notchLeft: nil, menuEnd: 1400), 1074)
    }
}

final class PerDisplayMenuTests: XCTestCase {
    func testSwitchOnOneMonitorDoesNotResizeOtherMonitor() {
        var state = DisplayMenuState()
        state.update(MeasuredMenu(display: 1, end: 600), connected: [1, 2])
        state.update(MeasuredMenu(display: 2, end: 400), connected: [1, 2])
        state.update(MeasuredMenu(display: 2, end: 850), connected: [1, 2])
        XCTAssertEqual(state.ends, [1: 600, 2: 850])
    }
    func testFailedReadingPreservesConnectedMonitorAndDisconnectDropsStaleState() {
        var state = DisplayMenuState()
        state.update(MeasuredMenu(display: 1, end: 600), connected: [1, 2])
        state.update(MeasuredMenu(display: 2, end: 400), connected: [1, 2])
        state.update(nil, connected: [2])
        XCTAssertEqual(state.ends, [2: 400])
        state.update(nil, connected: [1, 2])
        XCTAssertEqual(state.ends, [2: 400])
    }
}

final class MenuCoverageTransitionTests: XCTestCase {
    func testGrowthIsImmediateWhileOtherDisplayWaitsToShrink() {
        XCTAssertEqual(MenuCoverageTransition.coveringWidths(current: [1: 800, 2: 400], target: [1: 450, 2: 700]), [1: 800, 2: 700])
    }
    func testRapidSmallerMenusKeepOriginalCoverageUntilFinalCommit() {
        let first = MenuCoverageTransition.coveringWidths(current: [1: 900], target: [1: 400])
        let second = MenuCoverageTransition.coveringWidths(current: first, target: [1: 600])
        XCTAssertEqual(first, [1: 900])
        XCTAssertEqual(second, [1: 900])
        XCTAssertEqual(MenuCoverageTransition.coveringWidths(current: second, target: [1: 1100]), [1: 1100])
    }
    func testDisplayRemovalAndFirstMeasurementDoNotKeepPhantomCoverage() {
        XCTAssertEqual(MenuCoverageTransition.coveringWidths(current: [1: 800], target: [2: 500]), [2: 500])
    }
}

final class PresentationGateTests: XCTestCase {
    func testShorterAppNameCannotPublishWhileBackgroundWaitsToShrink() {
        var gate = PresentationGate()
        var visible = NativeAppPresentation(app: "old", label: "A much longer window title")
        let next = NativeAppPresentation(app: "new", label: "Short")
        let generation = gate.begin()
        // Both the regular app update and a later AX title notification used to
        // reach present() here, despite a pending geometry transaction.
        for _ in 0..<2 {
            if gate.canPublish { visible = next }
            XCTAssertEqual(visible.label, "A much longer window title")
            XCTAssertEqual(visible.app, "old")
        }
        gate.commit(generation)
        if gate.canPublish { visible = next }
        XCTAssertEqual(visible, next)
    }
    func testOldShrinkCannotReleaseNewerPendingPresentation() {
        var gate = PresentationGate()
        let old = gate.begin()
        let latest = gate.begin()
        XCTAssertFalse(gate.accepts(old))
        gate.commit(old)
        XCTAssertFalse(gate.canPublish)
        gate.commit(latest)
        XCTAssertTrue(gate.canPublish)
    }
    func testUnchangedGeometryStillNeedsSuccessfulPresentationCommit() {
        var gate = PresentationGate()
        let generation = gate.begin()
        XCTAssertTrue(gate.accepts(generation))
        // A no-op width update or failed send must not release title-only events.
        XCTAssertFalse(gate.canPublish)
        gate.commit(generation)
        XCTAssertTrue(gate.canPublish)
    }
}

final class AppLabelRendererTests: XCTestCase {
    func testRepeatedAppSnapshotDoesNotMeasureOrRedrawItsName() {
        var measurements = 0
        var renderer = AppLabelRenderer { text, _ in measurements += 1; return text }
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty")
        let first = renderer.render(snapshot, width: 200)
        for _ in 0..<10 {
            let next = renderer.render(snapshot, width: 200)
            XCTAssertEqual(next.updates(after: first), [])
        }
        XCTAssertEqual(first.label, "Ghostty")
        XCTAssertEqual(measurements, 1)
    }
    func testSameTextReusesMeasurementButAppChangeStillUpdatesIcon() {
        var measurements = 0
        var renderer = AppLabelRenderer { text, _ in measurements += 1; return text }
        let first = renderer.render(NativeAppSnapshot(pid: 1, app: "a", name: "Window"), width: 200)
        let next = renderer.render(NativeAppSnapshot(pid: 2, app: "b", name: "Window"), width: 200)
        XCTAssertEqual(next.updates(after: first), ["--set", "front_app_icon", "icon.background.image=app.b"])
        XCTAssertEqual(measurements, 1)
    }
    func testTextAndWidthChangesInvalidateTheSingleCurrentMeasurement() {
        var measurements = 0
        var renderer = AppLabelRenderer { text, width in measurements += 1; return "\(text):\(width)" }
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "Window")
        _ = renderer.render(snapshot, width: 200)
        _ = renderer.render(snapshot, width: 100)
        _ = renderer.render(NativeAppSnapshot(pid: 1, app: "a", name: "Other"), width: 100)
        XCTAssertEqual(measurements, 3)
    }
    func testApplicationNameIsPreservedLiterally() {
        var renderer = AppLabelRenderer { text, _ in text }
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "⠙ App — Beta")
        XCTAssertEqual(renderer.render(snapshot, width: 200).label, snapshot.name)
    }
}

final class AppAndWindowLabelTests: XCTestCase {
    func testNamePrecedesWindowTitle() {
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: "Project")
        XCTAssertEqual(snapshot.presentation(width: 500).label, "Ghostty — Project")
    }
    func testOnlyWindowTitleIsTruncatedWhenNameFits() {
        let snapshot = NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: String(repeating: "Project 👨‍👩‍👧‍👦 ", count: 20))
        let label = snapshot.presentation(width: 180).label
        XCTAssertTrue(label.hasPrefix("Ghostty — "))
        XCTAssertTrue(label.hasSuffix("…"))
        XCTAssertLessThanOrEqual(AppLabelLayout.textWidth(label), 180)
    }
    func testMissingDuplicateOrUnfittableTitleDoesNotLeaveDanglingSeparator() {
        for title in ["", "Ghostty"] {
            XCTAssertEqual(NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: title).presentation(width: 500).label, "Ghostty")
        }
        let width = AppLabelLayout.textWidth("Ghostty") + 1
        XCTAssertEqual(NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: "Project").presentation(width: width).label, "Ghostty")
    }
    func testWindowTitleChangesDoNotReloadAppIconAndSpinnerPhasesDoNotRemeasure() {
        var measurements = 0
        var renderer = AppLabelRenderer { text, _ in measurements += 1; return text }
        let first = renderer.render(NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: "⠋ Building"), width: 500)
        let next = renderer.render(NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: "⠙ Building"), width: 500)
        XCTAssertEqual(next.updates(after: first), [])
        XCTAssertEqual(measurements, 1)
        let finished = renderer.render(NativeAppSnapshot(pid: 1, app: "a", name: "Ghostty", windowTitle: "Finished"), width: 500)
        XCTAssertEqual(finished.updates(after: next), ["--set", "front_app", "label=Ghostty — Finished"])
    }
}
