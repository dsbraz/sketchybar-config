import AppKit

/// Pixel-based truncation, recomputed on display/Space changes, never on a timer.
enum AppLabelLayout {
    static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
    static func fit(_ text: String, width: CGFloat) -> String {
        guard textWidth(text) > width else { return text }
        guard textWidth("…") <= width else { return "" }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if textWidth(String(characters.prefix(middle)) + "…") <= width { low = middle }
            else { high = middle - 1 }
        }
        return String(characters.prefix(low)) + "…"
    }
    static func combine(name: String, title: String, width: CGFloat,
                        fit: (String, CGFloat) -> String = AppLabelLayout.fit) -> String {
        guard !title.isEmpty, title != name else { return fit(name, width) }
        let prefix = name + " — "
        let available = width - textWidth(prefix)
        // Keep the app name and omit the separator when no title can fit.
        guard available >= textWidth("…") else { return fit(name, width) }
        return prefix + fit(title, available)
    }

    private static func query(_ name: String) -> Any? {
        guard let response = SketchyBarIPC.send(["--query", name]),
              let data = response.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    static func availableWidth(surfaceWidths: [Int: Int]? = nil) -> CGFloat? {
        guard let displays = query("displays") as? [[String: Any]],
              let item = query("front_app") as? [String: Any],
              let bounds = item["bounding_rects"] as? [String: [String: Any]] else { return nil }
        var widths: [CGFloat] = []
        for display in displays {
            guard let arrangement = display["arrangement-id"] as? Int,
                  let frame = display["frame"] as? [String: Double], let x = frame["x"],
                  let origin = bounds["display-\(arrangement)"]?["origin"] as? [Double] else { continue }
            let surfaceEnd = surfaceWidths?[arrangement].map { CGFloat($0) + CompactSurfaceGeometry.left }
                ?? CompactSurfaceGeometry.end(for: display)
            guard let surfaceEnd else { continue }
            let end = x + surfaceEnd
            // Reserve label inset and comfortable breathing room inside the surface.
            widths.append(max(0, end - origin[0] - 4 - 16))
        }
        // A shared app name must fit on every connected display.
        return widths.min()
    }
}
