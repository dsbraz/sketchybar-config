import AppKit
import ApplicationServices

/// No app-width cache, recursive menu walk, or timer. All coordinates are AX/CG
/// screen points (top-left origin), normalized to the menu's own display.
struct MeasuredMenu: Equatable {
    let display: CGDirectDisplayID
    let end: CGFloat
}

struct DisplayMenuState {
    private(set) var ends: [CGDirectDisplayID: CGFloat] = [:]
    mutating func update(_ measurement: MeasuredMenu?, connected: Set<CGDirectDisplayID>) {
        ends = ends.filter { connected.contains($0.key) }
        if let measurement, connected.contains(measurement.display) {
            ends[measurement.display] = measurement.end
        }
    }
}

enum MenuMeasurement {
    static func displays() -> [CGDirectDisplayID: CGRect]? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return Dictionary(uniqueKeysWithValues: ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) })
    }

    static func menuBar(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func extent(items: [CGRect], displays: [CGRect]) -> CGFloat? {
        guard !items.isEmpty, items.allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull }),
              let first = items.min(by: { $0.minX < $1.minX }),
              let display = displays.first(where: { $0.contains(CGPoint(x: first.midX, y: first.midY)) }) else { return nil }
        let end = items.map(\.maxX).max()! - display.minX
        guard end.isFinite, end > 0, end <= display.width else { return nil }
        return end
    }

    static func capture(pid: pid_t) -> MeasuredMenu? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let menu = menuBar(of: app) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement], !children.isEmpty, children.count <= 128 else { return nil }
        var rects: [CGRect] = []
        let started = ProcessInfo.processInfo.systemUptime
        for child in children {
            // Bound the entire attempt as well as individual IPC calls.
            guard ProcessInfo.processInfo.systemUptime - started < 0.1 else { return nil }
            AXUIElementSetMessagingTimeout(child, 0.02)
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(child,
                [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &values) == .success,
                let pair = values as? [AnyObject], pair.count == 2,
                CFGetTypeID(pair[0]) == AXValueGetTypeID(), CFGetTypeID(pair[1]) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(pair[0] as! AXValue, .cgPoint, &point),
                  AXValueGetValue(pair[1] as! AXValue, .cgSize, &size) else { return nil }
            // Hidden top-level items have no visible geometry.
            if size.width > 0 && size.height > 0 { rects.append(CGRect(origin: point, size: size)) }
        }
        guard let displays = displays(),
              let first = rects.min(by: { $0.minX < $1.minX }),
              let (id, frame) = displays.first(where: { $0.value.contains(CGPoint(x: first.midX, y: first.midY)) }),
              let end = extent(items: rects, displays: [frame]) else { return nil }
        return MeasuredMenu(display: id, end: end)
    }
}
