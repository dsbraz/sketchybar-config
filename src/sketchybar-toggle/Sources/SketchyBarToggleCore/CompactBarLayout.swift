import AppKit

/// Event-driven menu coverage, with compact display geometry as the AX fallback.
enum CompactSurfaceGeometry {
    static let left: CGFloat = 6
    static func end(screenWidth: CGFloat, notchLeft: CGFloat?, menuEnd: CGFloat? = nil) -> CGFloat {
        if let menuEnd, menuEnd.isFinite, menuEnd > 0 {
            return min(screenWidth - left, ceil(max(320, menuEnd + 12)))
        }
        return floor(max(left, (notchLeft ?? screenWidth / 2) - 10))
    }
    static func end(for display: [String: Any], menuEnds: [CGDirectDisplayID: CGFloat] = [:]) -> CGFloat? {
        guard let frame = display["frame"] as? [String: Double], let width = frame["w"],
              let id = display["DirectDisplayID"] as? UInt32 else { return nil }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        let notch = (screen?.safeAreaInsets.top ?? 0) > 0 ? screen?.auxiliaryTopLeftArea?.width : nil
        return end(screenWidth: width, notchLeft: notch, menuEnd: menuEnds[id])
    }
}

enum MenuCoverageTransition {
    static func coveringWidths(current: [Int: Int], target: [Int: Int]) -> [Int: Int] {
        target.mapValues { $0 }.reduce(into: [:]) { result, item in
            result[item.key] = max(current[item.key] ?? item.value, item.value)
        }
    }
}

public final class CompactBarLayout {
    private var previous: [Int: Int] = [:]
    private var pendingShrink: DispatchWorkItem?
    public var applyTransaction: (([String], [Int: Int], UInt64, Bool) -> Bool)?
    public init() {}

    @discardableResult public func refresh(menuEnds: [CGDirectDisplayID: CGFloat] = [:], generation: UInt64 = 0) -> Bool {
        guard let response = SketchyBarIPC.send(["--query", "displays"]),
              let data = response.data(using: .utf8),
              let displays = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        var widths: [Int: Int] = [:]
        for display in displays {
            guard let arrangement = display["arrangement-id"] as? Int,
                  let end = CompactSurfaceGeometry.end(for: display, menuEnds: menuEnds) else { continue }
            widths[arrangement] = Int(end - CompactSurfaceGeometry.left)
        }
        guard !widths.isEmpty else { return false }
        pendingShrink?.cancel()
        pendingShrink = nil
        let covering = MenuCoverageTransition.coveringWidths(current: previous, target: widths)
        guard apply(covering, generation: generation, publish: covering == widths) else { return false }
        if covering != widths {
            let work = DispatchWorkItem { [weak self] in _ = self?.apply(widths, generation: generation, publish: true) }
            pendingShrink = work
            // A single event-driven commit; no polling or intermediate widths.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        return true
    }

    private func apply(_ widths: [Int: Int], generation: UInt64, publish: Bool) -> Bool {
        guard widths != previous else {
            // No geometry change still needs to release a pending new title.
            return publish ? (applyTransaction?([], widths, generation, true) ?? true) : true
        }
        guard let response = SketchyBarIPC.send(["--query", "bar"]),
              let data = response.data(using: .utf8),
              let bar = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = bar["items"] as? [String] else { return false }
        var arguments: [String] = []
        let wanted = Set(widths.keys.map { "menu_surface.\($0)" })
        for item in items where item.hasPrefix("menu_surface.") && !wanted.contains(item) {
            arguments += ["--remove", item]
        }
        for display in widths.keys.sorted() {
            let item = "menu_surface.\(display)"
            if !items.contains(item) { arguments += ["--add", "item", item, "left"] }
            else if previous[display] == widths[display] { continue }
            // width=0 leaves the content cursor unchanged; icon.width sets the
            // actual backing window width. Offsetting 2 then undoing it keeps
            // the Apple icon aligned with the native menu bar.
            arguments += ["--set", item, "display=\(display)", "width=0", "y_offset=0",
                          "padding_left=2", "padding_right=0", "icon=", "icon.width=\(widths[display]!)",
                          "icon.padding_left=0", "icon.padding_right=0", "label.drawing=off",
                          "background.drawing=off", "icon.background.drawing=on", "icon.background.color=0x33242426",
                          "icon.background.height=30", "icon.background.corner_radius=10",
                          "icon.background.border_width=1", "icon.background.border_color=0x26ffffff",
                          "icon.background.y_offset=-1", "blur_radius=30", "shadow=off", "updates=off",
                          "--move", item, "before", "apple"]
        }
        let sent = applyTransaction?(arguments, widths, generation, publish) ?? (arguments.isEmpty || SketchyBarIPC.send(arguments) != nil)
        guard sent else { return false }
        previous = widths
        return true
    }

    deinit { pendingShrink?.cancel() }
}
