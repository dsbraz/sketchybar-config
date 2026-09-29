import Foundation

/// Controls SketchyBar visibility by shelling out to the `sketchybar` CLI.
public final class SketchyBarController: BarController {
    private let sketchybarPath: String
    private var pendingHide: DispatchWorkItem?
    private var commandRunner: (([String]) -> Void)?
    private let prepareToShow: () -> Void

    init(commandRunner: @escaping ([String]) -> Void, prepareToShow: @escaping () -> Void = {}) {
        self.sketchybarPath = "/opt/homebrew/bin/sketchybar"
        self.commandRunner = commandRunner
        self.prepareToShow = prepareToShow
    }

    public init() {
        let script = ProcessInfo.processInfo.environment["SKETCHYBAR_BEFORE_SHOW"]
        self.prepareToShow = {
            guard let script, FileManager.default.fileExists(atPath: script) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script]
            var environment = ProcessInfo.processInfo.environment
            environment["NAME"] = "front_app"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch { }
        }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/sketchybar") {
            sketchybarPath = "/opt/homebrew/bin/sketchybar"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/sketchybar") {
            sketchybarPath = "/usr/local/bin/sketchybar"
        } else {
            sketchybarPath = "sketchybar"
        }
    }

    public func hide() {
        pendingHide?.cancel()
        // Nine SketchyBar animation frames are approximately 150 ms.
        run(arguments: ["--animate", "sin", "9", "--bar", "y_offset=-34"])
        let completion = DispatchWorkItem { [weak self] in
            self?.run(arguments: ["--bar", "hidden=on", "y_offset=0"])
            self?.pendingHide = nil
        }
        pendingHide = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: completion)
    }

    public func show() {
        pendingHide?.cancel()
        pendingHide = nil
        // Complete the layout update while still hidden, before the first frame.
        prepareToShow()
        // Unhide off-screen, then animate sliding down
        run(arguments: ["--bar", "hidden=off", "y_offset=-50"])
        run(arguments: ["--animate", "sin", "12", "--bar", "y_offset=0"])
    }

    private func run(arguments: [String]) {
        if let commandRunner = commandRunner {
            commandRunner(arguments)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sketchybarPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // sketchybar may not be running — fail silently
        }
    }

    deinit {
        pendingHide?.cancel()
    }
}
