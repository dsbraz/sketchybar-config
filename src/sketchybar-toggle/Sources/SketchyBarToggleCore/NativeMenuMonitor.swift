import AppKit
import ApplicationServices

struct MenuCoverState {
    private(set) var width: Int?
    private var pending: (width: Int, pid: pid_t, since: TimeInterval)?

    mutating func update(width newWidth: Int, pid: pid_t, now: TimeInterval) -> TimeInterval? {
        guard let width, newWidth < width else {
            width = newWidth
            pending = nil
            return nil
        }
        if pending?.width != newWidth || pending?.pid != pid {
            pending = (newWidth, pid, now)
        }
        let remaining = 0.4 - (now - pending!.since)
        if remaining <= 0 {
            self.width = newWidth
            pending = nil
            return nil
        }
        return remaining
    }
}

private struct NativeMenuSnapshot: Equatable {
    let pid: pid_t
    let app: String
    let title: String
    let menuWidth: Int?

    static func capture() -> NativeMenuSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? ""
        guard AXIsProcessTrusted() else {
            return Self(pid: app.processIdentifier, app: app.bundleIdentifier ?? name, title: name, menuWidth: nil)
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        let window = attribute(element, kAXFocusedWindowAttribute) as! AXUIElement?
        let title = window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? name
        var width: Int?
        if let menu = attribute(element, kAXMenuBarAttribute) as! AXUIElement?,
           let children = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] {
            var first: CGPoint?
            var right = -CGFloat.greatestFiniteMagnitude
            for item in children {
                guard let p = attribute(item, kAXPositionAttribute),
                      let s = attribute(item, kAXSizeAttribute),
                      CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { continue }
                var point = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
                      AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0 else { continue }
                first = first ?? point
                right = max(right, point.x + size.width)
            }
            if let first {
                var count: UInt32 = 0
                CGGetActiveDisplayList(0, nil, &count)
                var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
                CGGetActiveDisplayList(count, &displays, &count)
                if let display = displays.prefix(Int(count)).first(where: { CGDisplayBounds($0).contains(first) }) {
                    width = Int(ceil(right - CGDisplayBounds(display).minX))
                }
            }
        }
        // Discard a snapshot captured across an application switch.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        return Self(pid: app.processIdentifier, app: app.bundleIdentifier ?? name,
                    title: title.isEmpty ? name : title, menuWidth: width)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

/// Reads AX in one resident serial queue; emits a single direct Mach transaction.
/// Retains only current transition state, not a cache of applications or widths.
public final class NativeMenuMonitor {
    private let queue = DispatchQueue(label: "sketchybar.native-menu", qos: .userInteractive)
    private var tokens: [NSObjectProtocol] = []
    private var timer: DispatchSourceTimer?
    private var settle: DispatchWorkItem?
    private var state = MenuCoverState()
    private var lastSent: NativeMenuSnapshot?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private let refreshLock = NSLock()
    private var refreshPending = false

    public init() {}

    public static func probe() -> Bool {
        let trusted = AXIsProcessTrusted()
        let snapshot = trusted ? NativeMenuSnapshot.capture() : nil
        print("accessibility=\(trusted) menu_width=\(snapshot?.menuWidth.map(String.init) ?? "unavailable")")
        return trusted && snapshot?.menuWidth != nil
    }

    public func start() -> Bool {
        // Keep observers alive while the user grants Accessibility.
        // AppKit app names and Spaces remain available without AX access.
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.refresh()
            })
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.update() }
        self.timer = timer
        timer.resume()
        return true
    }

    public func refresh() {
        refreshLock.lock()
        guard !refreshPending else { refreshLock.unlock(); return }
        refreshPending = true
        refreshLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshLock.lock()
            self.refreshPending = false
            self.refreshLock.unlock()
            self.update()
        }
    }

    public func prepareToShow() {
        queue.sync { update(force: true) }
    }

    private func observe(_ pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        if observedPID == pid { observeFocusedWindow(pid); return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedWindow = nil
        observedPID = nil
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            Unmanaged<NativeMenuMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }, &newObserver) == .success, let newObserver else { return }
        let element = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(newObserver, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observedPID = pid
        observer = newObserver
        observeFocusedWindow(pid)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }

    private func observeFocusedWindow(_ pid: pid_t) {
        guard let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let window = value as! AXUIElement
        if let old = observedWindow {
            if CFEqual(old, window) { return }
            AXObserverRemoveNotification(observer, old, kAXTitleChangedNotification as CFString)
        }
        observedWindow = window
        AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    private func update(force: Bool = false) {
        guard let snapshot = NativeMenuSnapshot.capture() else { return }
        observe(snapshot.pid)
        settle?.cancel()
        settle = nil
        if let width = snapshot.menuWidth,
           let delay = state.update(width: width, pid: snapshot.pid, now: ProcessInfo.processInfo.systemUptime) {
            let work = DispatchWorkItem { [weak self] in self?.update() }
            settle = work
            queue.asyncAfter(deadline: .now() + delay + 0.01, execute: work)
            return
        }
        guard force || snapshot != lastSent else { return }
        var args: [String] = []
        if let width = snapshot.menuWidth { args += ["--set", "menu_cover_end", "icon.width=\(width)"] }
        args += ["--set", "front_app", "label=\(snapshot.title)", "icon.background.image=app.\(snapshot.app)"]
        if SketchyBarIPC.send(args) != nil { lastSent = snapshot }
    }

    deinit {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        timer?.cancel()
        settle?.cancel()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}
