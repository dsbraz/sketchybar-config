import AppKit

/// Passive mouse notifications: no timer, event suppression or keyboard capture.
public final class EventTapMonitor {
    private let stateMachine: BarStateMachine
    private let debugLog: ((String) -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var screenFrames: [NSRect] = []

    public init(stateMachine: BarStateMachine, debugLog: ((String) -> Void)? = nil) {
        self.stateMachine = stateMachine
        self.debugLog = debugLog
    }

    @discardableResult public func start() -> Bool {
        stop()
        screenFrames = NSScreen.screens.map(\.frame)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenFrames = NSScreen.screens.map(\.frame)
            self?.handlePosition()
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handlePosition(click: event.type == .leftMouseDown)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handlePosition(click: event.type == .leftMouseDown)
            return event
        }
        handlePosition()
        debugLog?("mouse event monitors installed")
        return globalMonitor != nil && localMonitor != nil
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        globalMonitor = nil
        localMonitor = nil
        screenObserver = nil
    }

    private func handlePosition(click: Bool = false) {
        let point = NSEvent.mouseLocation
        guard let frame = screenFrames.first(where: { $0.contains(point) }) else { return }
        let distance = frame.maxY - point.y
        if click { stateMachine.handleMouseClick(distanceFromTop: distance) }
        stateMachine.handleMousePosition(distanceFromTop: distance)
    }

    deinit { stop() }
}
