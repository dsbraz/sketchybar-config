import Foundation

/// Controls SketchyBar visibility through bounded native Mach IPC.
public final class SketchyBarController: BarController {
    private var pendingHide: DispatchWorkItem?
    private var commandRunner: (([String]) -> Void)?
    private let prepareToShow: () -> Void
    private let useFade: Bool
    private let useSmoothSlide: Bool
    private var isHidden = true

    init(commandRunner: @escaping ([String]) -> Void, prepareToShow: @escaping () -> Void = {}, useFade: Bool = false, useSmoothSlide: Bool = false) {
        self.commandRunner = commandRunner
        self.prepareToShow = prepareToShow
        self.useFade = useFade
        self.useSmoothSlide = useSmoothSlide
    }

    public init(nativeMenu: NativeMenuMonitor? = nil) {
        self.useFade = ProcessInfo.processInfo.environment["SKETCHYBAR_TRANSITION"] == "fade"
        self.useSmoothSlide = ProcessInfo.processInfo.environment["SKETCHYBAR_TRANSITION"] == "smooth-slide"
        self.prepareToShow = { nativeMenu?.prepareToShow() }
    }

    public func hide() {
        pendingHide?.cancel()
        // Smooth slide: 16 frames (~267 ms); fade: 18; full slide: 9.
        if useFade {
            run(arguments: ["--animate", "sin", "18"] + fadeProperties(visible: false))
        } else if useSmoothSlide {
            run(arguments: ["--animate", "sin", "16", "--bar", "y_offset=-32"])
        } else {
            run(arguments: ["--animate", "sin", "9", "--bar", "y_offset=-34"])
        }
        let completion = DispatchWorkItem { [weak self] in
            self?.run(arguments: ["--bar", "hidden=on", "y_offset=0"])
            self?.isHidden = true
            self?.pendingHide = nil
        }
        pendingHide = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + (useFade ? 0.33 : (useSmoothSlide ? 16.0 / 60.0 + 0.03 : 0.18)), execute: completion)
    }

    public func show() {
        pendingHide?.cancel()
        pendingHide = nil
        // Complete the layout update while still hidden, before the first frame.
        prepareToShow()
        if useSmoothSlide {
            if isHidden {
                run(arguments: fadeProperties(visible: true) + ["--bar", "hidden=off", "y_offset=-32"])
            }
            isHidden = false
            run(arguments: ["--animate", "sin", "16", "--bar", "y_offset=0"])
            return
        }
        if useFade {
            if isHidden {
                run(arguments: fadeProperties(visible: false) + ["--bar", "hidden=off", "y_offset=0"])
            }
            isHidden = false
            run(arguments: ["--animate", "sin", "18"] + fadeProperties(visible: true))
            return
        }
        // Unhide off-screen, then animate sliding down
        run(arguments: ["--bar", "hidden=off", "y_offset=-50"])
        run(arguments: ["--animate", "sin", "12", "--bar", "y_offset=0"])
    }

    // Palette of the compact-menu configuration. Images have no alpha property,
    // so the app icon scales down/up while the text and backgrounds fade.
    private func fadeProperties(visible: Bool) -> [String] {
        let alpha = visible ? "ff" : "00"
        return [
            "--set", "left_backdrop", "background.color=0x\(alpha)242426",
            "--set", "apple", "icon.color=0x\(alpha)f5f5f7",
            "--set", "front_app", "label.color=0x\(alpha)f5f5f7",
            "icon.background.image.scale=\(visible ? "0.65" : "0.0")",
            "--set", "/^space\\.[0-9]+$/", "icon.color=0x\(alpha)f5f5f7",
            "background.color=0x\(alpha)3b99fc"
        ]
    }

    private func run(arguments: [String]) {
        if let commandRunner = commandRunner {
            commandRunner(arguments)
            return
        }
        SketchyBarIPC.send(arguments)
    }

    deinit {
        pendingHide?.cancel()
    }
}
