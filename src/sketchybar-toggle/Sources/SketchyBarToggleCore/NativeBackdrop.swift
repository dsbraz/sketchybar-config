import AppKit
import QuartzCore

struct BackdropMotion {
    var from: CGFloat = 32
    var to: CGFloat = 32
    var started: TimeInterval = 0
    var duration: TimeInterval = 0
    func offset(at time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return to }
        let progress = max(0, min(1, (time - started) / duration))
        let eased = (1 - cos(progress * .pi)) / 2
        return from + (to - from) * eased
    }
    mutating func move(to target: CGFloat, at time: TimeInterval, duration: TimeInterval) {
        from = offset(at: time)
        to = target
        started = time
        self.duration = duration
    }
}

private final class BackdropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MaterialView: NSVisualEffectView {
    private let outline = CAShapeLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        switch ProcessInfo.processInfo.environment["SKETCHYBAR_BACKDROP_MATERIAL"] {
        case "popover": material = .popover
        case "menu": material = .menu
        default: material = .hudWindow
        }
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        // NSVisualEffectView's mask clips the actual backdrop filter, not just
        // the tint drawn over a rectangular blur window.
        let mask = NSImage(size: NSSize(width: 21, height: 21), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        mask.resizingMode = .stretch
        maskImage = mask
        outline.fillColor = NSColor.clear.cgColor
        outline.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        outline.lineWidth = 1
        layer?.addSublayer(outline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 9.5, cornerHeight: 9.5, transform: nil)
    }
}

/// Native material windows exist inside the helper; no new process or polling.
public final class NativeBackdrop {
    private let enabled = ProcessInfo.processInfo.environment["SKETCHYBAR_NATIVE_MATERIAL"] != "0"
    private var panels: [CGDirectDisplayID: BackdropPanel] = [:]
    private var frames: [CGDirectDisplayID: NSRect] = [:]
    private var barWindows: [CGDirectDisplayID: Int] = [:]
    private var motion = BackdropMotion()
    private var visible = false
    private var menuEnd: CGFloat?
    private var startupCoverHidden = false

    public init() {}

    public func resize(menuEnd: CGFloat?) {
        guard self.menuEnd != menuEnd else { return }
        self.menuEnd = menuEnd
        refresh(rescanWindows: false)
    }

    public func refresh(rescanWindows: Bool = true) {
        guard enabled else { return }
        let screens = NSScreen.screens
        if rescanWindows { findBarWindows(screens) }
        let ids = Set(screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        for id in Set(panels.keys).subtracting(ids) {
            panels.removeValue(forKey: id)?.close()
            frames.removeValue(forKey: id)
        }
        for screen in screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let notch = screen.safeAreaInsets.top > 0 ? screen.auxiliaryTopLeftArea?.width : nil
            let end = CompactSurfaceGeometry.end(screenWidth: screen.frame.width, notchLeft: notch, menuEnd: menuEnd)
            let frame = NSRect(x: screen.frame.minX + CompactSurfaceGeometry.left,
                               y: screen.frame.maxY - 32, width: end - CompactSurfaceGeometry.left, height: 30)
            if panels[id] == nil {
                startupCoverHidden = false
                let panel = BackdropPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = true
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                // Native menus are level 24. Share level 25 with SketchyBar,
                // ordering below its transparent base window and all its text.
                panel.level = .statusBar
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                panel.contentView = MaterialView(frame: NSRect(origin: .zero, size: frame.size))
                panels[id] = panel
            }
            guard let panel = panels[id] else { continue }
            if frames[id] != frame {
                frames[id] = frame
                panel.setFrame(frame.offsetBy(dx: 0, dy: motion.offset(at: CACurrentMediaTime())), display: true)
            }
            if visible { order(panel, on: id) }
        }
        if visible { hideStartupCover() }
    }

    public func show(duration: TimeInterval) {
        guard enabled else { return }
        if panels.isEmpty { refresh() }
        if !visible {
            motion = BackdropMotion(from: 32, to: 32)
            for (id, panel) in panels {
                guard let frame = frames[id] else { continue }
                panel.setFrame(frame.offsetBy(dx: 0, dy: 32), display: true)
                order(panel, on: id)
            }
        }
        visible = true
        animate(to: 0, duration: duration)
        hideStartupCover()
    }

    private func findBarWindows(_ screens: [NSScreen]) {
        // Read only window metadata on display/Space events, never per app/title
        // or animation frame. No AX menu scans or content capture.
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for screen in screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let display = CGDisplayBounds(id)
            let match = windows.compactMap { window -> (Int, Double)? in
                guard window[kCGWindowOwnerName as String] as? String == "sketchybar",
                      let number = window[kCGWindowNumber as String] as? Int,
                      let bounds = window[kCGWindowBounds as String] as? [String: Double],
                      bounds["Width"] == display.width, bounds["Height"] == 32,
                      bounds["X"] == display.minX, let y = bounds["Y"] else { return nil }
                return (number, abs(y - display.minY))
            }.min { $0.1 < $1.1 }
            if let match { barWindows[id] = match.0 }
        }
    }

    private func order(_ panel: NSPanel, on display: CGDirectDisplayID) {
        if let window = barWindows[display] { panel.order(.below, relativeTo: window) }
        else { panel.orderOut(nil) }
    }

    private func hideStartupCover() {
        guard !startupCoverHidden else { return }
        // The static startup cover remains until the native material exists.
        if SketchyBarIPC.send(["--set", "/menu_surface.*/", "drawing=off"]) != nil {
            startupCoverHidden = true
        }
    }

    public func hide(duration: TimeInterval) {
        guard enabled else { return }
        animate(to: 32, duration: duration)
    }

    public func finishHide() {
        visible = false
        for panel in panels.values { panel.orderOut(nil) }
    }

    private func animate(to target: CGFloat, duration: TimeInterval) {
        let now = CACurrentMediaTime()
        let current = motion.offset(at: now)
        motion.move(to: target, at: now, duration: duration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            // Cubic approximation of sin easing; both layers travel 32 pt over 16/60 s.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
            for (id, panel) in panels {
                guard let base = frames[id] else { continue }
                panel.setFrame(base.offsetBy(dx: 0, dy: current), display: false)
                panel.animator().setFrame(base.offsetBy(dx: 0, dy: target), display: true)
            }
        }
    }
}
