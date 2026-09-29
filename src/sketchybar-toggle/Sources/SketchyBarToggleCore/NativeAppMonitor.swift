import AppKit
import ApplicationServices

struct NativeAppSnapshot: Equatable {
    let pid: pid_t
    let app: String
    let name: String
    let windowTitle: String

    init(pid: pid_t, app: String, name: String, windowTitle: String = "") {
        self.pid = pid
        self.app = app
        self.name = name
        self.windowTitle = windowTitle
    }

    static func capture() -> NativeAppSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? ""
        var title = ""
        if AXIsProcessTrusted() {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                var text: CFTypeRef?
                if AXUIElementCopyAttributeValue(value as! AXUIElement, kAXTitleAttribute as CFString, &text) == .success {
                    title = text as? String ?? ""
                }
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        return Self(pid: app.processIdentifier, app: app.bundleIdentifier ?? name, name: name, windowTitle: title)
    }
}

/// AppKit supplies the app name; AX observes window titles and top-level menus.
public final class NativeAppMonitor {
    private let queue = DispatchQueue(label: "sketchybar.native-app", qos: .userInteractive)
    private var tokens: [NSObjectProtocol] = []
    private var lastSent: NativeAppSnapshot?
    private var lastPresentation: NativeAppPresentation?
    public var onMenuChange: (([CGDirectDisplayID: CGFloat], pid_t, UInt64) -> Void)?
    private var menuState = DisplayMenuState()
    private var measuredPID: pid_t?
    private var observedMenu: AXUIElement?
    private var presentationGate = PresentationGate()
    private var labelWidth: CGFloat = 520
    private var appliedSurfaceWidths: [Int: Int]?
    private var layoutDirty = true
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private var pendingTitleUpdate: DispatchWorkItem?
    private let refreshLock = NSLock()
    private var refreshPending = false
    private var labelRenderer = AppLabelRenderer()

    public init() {}

    public static func probe() -> Bool {
        let trusted = AXIsProcessTrusted()
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let end = pid.flatMap { MenuMeasurement.capture(pid: $0) }
        print("accessibility=\(trusted) app_available=\(NativeAppSnapshot.capture() != nil) menu_end=\(end.map { String(Double($0.end)) } ?? "unavailable")")
        return trusted
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
        refresh()
        return true
    }

    public func refreshLayout() {
        queue.async { [weak self] in
            self?.layoutDirty = true
            self?.update(force: true, measureMenu: false)
        }
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

    private func cancelTitleUpdate() {
        pendingTitleUpdate?.cancel()
        pendingTitleUpdate = nil
    }

    private func refreshTitle(_ window: AXUIElement) {
        queue.async { [weak self] in
            guard let self, self.pendingTitleUpdate == nil,
                  let observed = self.observedWindow, CFEqual(observed, window) else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingTitleUpdate = nil
                guard let observed = self.observedWindow, CFEqual(observed, window),
                      let previous = self.lastSent, self.observedPID == previous.pid,
                      self.presentationGate.canPublish else { return }
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
                      let title = value as? String else { self.refresh(); return }
                self.present(NativeAppSnapshot(pid: previous.pid, app: previous.app,
                                               name: previous.name, windowTitle: title))
            }
            self.pendingTitleUpdate = work
            // One event-triggered read of the newest title, never a repeating timer.
            self.queue.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    /// The layout owner commits width and the fitted app name in one Mach transaction.
    /// AX events keep using the last applied width while a shrink is pending.
    public func applyLayout(arguments: [String], widths: [Int: Int], generation: UInt64, publish: Bool) -> Bool {
        queue.sync {
            guard presentationGate.accepts(generation) else { return false }
            // Growing one monitor while another awaits shrink must not publish
            // the new app name before the final geometry transaction.
            guard publish else {
                return arguments.isEmpty || SketchyBarIPC.send(arguments) != nil
            }
            let width = AppLabelLayout.availableWidth(surfaceWidths: widths) ?? labelWidth
            let snapshot = NativeAppSnapshot.capture() ?? lastSent
            let presentation = snapshot.map { labelRenderer.render($0, width: width) }
            let combined = arguments + (presentation?.updates(after: lastPresentation) ?? [])
            guard combined.isEmpty || SketchyBarIPC.send(combined) != nil else { return false }
            presentationGate.commit(generation)
            appliedSurfaceWidths = widths
            labelWidth = width
            layoutDirty = false
            if let snapshot, let presentation {
                lastSent = snapshot
                lastPresentation = presentation
            }
            return true
        }
    }

    public func prepareToShow() {
        queue.sync { update(force: true) }
    }

    private func observe(_ pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        if observedPID == pid { observeFocusedWindow(pid); return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        cancelTitleUpdate()
        observer = nil
        observedWindow = nil
        observedMenu = nil
        observedPID = nil
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            let monitor = Unmanaged<NativeAppMonitor>.fromOpaque(context).takeUnretainedValue()
            if notification as String == kAXTitleChangedNotification { monitor.refreshTitle(element) }
            else { monitor.refresh() }
        }, &newObserver) == .success, let newObserver else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
                     kAXMenuOpenedNotification, kAXMenuClosedNotification] {
            AXObserverAddNotification(newObserver, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observedPID = pid
        observer = newObserver
        observeFocusedWindow(pid)
        if let menu = MenuMeasurement.menuBar(of: element) {
            observedMenu = menu
            // Optional: applications may return notificationUnsupported.
            for name in [kAXLayoutChangedNotification, kAXResizedNotification] {
                AXObserverAddNotification(newObserver, menu, name as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }

    private func observeFocusedWindow(_ pid: pid_t) {
        guard let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        var window: AXUIElement?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() { window = (value as! AXUIElement) }
        if let old = observedWindow {
            if let window, CFEqual(old, window) { return }
            AXObserverRemoveNotification(observer, old, kAXTitleChangedNotification as CFString)
        }
        cancelTitleUpdate()
        observedWindow = window
        if let window {
            AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func update(force: Bool = false, measureMenu: Bool = true) {
        guard let snapshot = NativeAppSnapshot.capture() else { return }
        observe(snapshot.pid)
        if measureMenu {
            let measurement = MenuMeasurement.capture(pid: snapshot.pid)
            // Reject stale measurements if focus changed during AX calls.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid else { return }
            let previousEnds = menuState.ends
            if let connected = MenuMeasurement.displays() {
                menuState.update(measurement, connected: Set(connected.keys))
            }
            if menuState.ends != previousEnds || measuredPID != snapshot.pid || !presentationGate.canPublish {
                measuredPID = snapshot.pid
                if let onMenuChange {
                    let generation = presentationGate.begin()
                    onMenuChange(menuState.ends, snapshot.pid, generation)
                }
            }
        }
        guard force || layoutDirty || snapshot != lastSent else { return }
        if layoutDirty {
            if let width = AppLabelLayout.availableWidth(surfaceWidths: appliedSurfaceWidths) { labelWidth = width; layoutDirty = false }
        }
        present(snapshot)
    }

    private func present(_ snapshot: NativeAppSnapshot) {
        // Covers app changes and reveal refreshes.
        guard presentationGate.canPublish else { return }
        let presentation = labelRenderer.render(snapshot, width: labelWidth)
        let arguments = presentation.updates(after: lastPresentation)
        // Failed sends do not advance state, so a later event can retry.
        if arguments.isEmpty || SketchyBarIPC.send(arguments) != nil {
            lastSent = snapshot
            lastPresentation = presentation
        }
    }

    deinit {
        pendingTitleUpdate?.cancel()
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}


extension NativeAppSnapshot {
    func presentation(width: CGFloat) -> NativeAppPresentation {
        var renderer = AppLabelRenderer()
        return renderer.render(self, width: width)
    }
}

/// Compare what was actually rendered, including truncation at the old width.
/// A forced AX refresh/reveal does not force a redraw of unchanged content.
struct NativeAppPresentation: Equatable {
    let app: String
    let label: String

    func updates(after previous: NativeAppPresentation?) -> [String] {
        var properties: [String] = []
        if label != previous?.label {
            properties += ["--set", "front_app", "label=\(label)"]
        }
        if app != previous?.app {
            properties += ["--set", "front_app_icon", "icon.background.image=app.\(app)"]
        }
        return properties
    }
}
