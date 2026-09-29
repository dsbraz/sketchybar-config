import AppKit
import NativeBridge

struct NativeSpace: Equatable {
    let index: Int
    let id: UInt64
    let selected: Bool
}

enum SpaceLayout {
    // Keep SketchyBar's Mission Control indices, including fullscreen slots;
    // only ordinary desktop Spaces get visible items.
    static func parse(_ displays: [[String: Any]]) -> [NativeSpace]? {
        var result: [NativeSpace] = []
        var seen = Set<UInt64>()
        var index = 0
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let current = display["Current Space"] as? [String: Any],
                  let active = current["id64"] as? NSNumber else { return nil }
            for space in spaces {
                guard let id = space["id64"] as? NSNumber,
                      let type = space["type"] as? NSNumber else { return nil }
                guard seen.insert(id.uint64Value).inserted else { continue }
                index += 1
                if type.intValue == 0 {
                    result.append(NativeSpace(index: index, id: id.uint64Value, selected: id == active))
                }
            }
        }
        return result.isEmpty ? nil : result
    }
}

public final class NativeSpaceMonitor {
    private let queue = DispatchQueue(label: "sketchybar.native-spaces")
    private var timer: DispatchSourceTimer?
    private var previous: [NativeSpace]?
    public init() {}
    static func snapshot() -> [NativeSpace]? {
        guard let raw = sb_copy_spaces() else { return nil }
        return SpaceLayout.parse(raw as NSArray as? [[String: Any]] ?? [])
    }
    public static func probe() -> Bool {
        guard let spaces = snapshot() else { print("spaces=unavailable"); return false }
        print("spaces=\(spaces.map { String($0.index) }.joined(separator: ",")) active=\(spaces.filter(\.selected).map { String($0.index) }.joined(separator: ","))")
        return true
    }
    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Reconcile topology too: adding an inactive desktop has no active-Space event.
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.update() }
        self.timer = timer
        timer.resume()
    }
    public func refresh() { queue.async { [weak self] in self?.update() } }
    private func update() {
        guard let spaces = Self.snapshot(), spaces != previous,
              let response = SketchyBarIPC.send(["--query", "bar"]),
              let data = response.data(using: .utf8),
              let bar = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = bar["items"] as? [String], items.contains("front_app") else { return }
        let wanted = Set(spaces.map { "space.\($0.index)" })
        var args: [String] = []
        for item in items where item.range(of: "^space\\.[0-9]+$", options: .regularExpression) != nil && !wanted.contains(item) {
            args += ["--remove", item]
        }
        for space in spaces {
            let name = "space.\(space.index)"
            if !items.contains(name) { args += ["--add", "space", name, "left"] }
            args += ["--set", name, "space=\(space.index)", "icon=\(space.index)",
                     "icon.color=0xfff5f5f7", "icon.padding_left=9", "icon.padding_right=9",
                     "label.drawing=off", "background.color=0xff3b99fc",
                     "background.drawing=\(space.selected ? "on" : "off")", "script=", "updates=off"]
        }
        args += ["--reorder", "apple"] + spaces.map { "space.\($0.index)" } + ["front_app"]
        if SketchyBarIPC.send(args) != nil { previous = spaces }
    }
    deinit { timer?.cancel() }
}
