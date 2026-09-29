import Foundation
import NativeBridge

/// Pass each argument as bytes, preserving quotes and spaces in window titles.
enum SketchyBarIPC {
    private static let lock = NSLock()
    static func encode(_ arguments: [String]) -> [UInt8] {
        arguments.flatMap { Array($0.replacingOccurrences(of: "\0", with: "").utf8) + [0] } + [0]
    }
    @discardableResult static func send(_ arguments: [String]) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let bytes = encode(arguments)
        return bytes.withUnsafeBytes { buffer in
            guard let response = sb_request(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count) else { return nil }
            defer { free(response) }
            let text = String(cString: response)
            return text.contains("[!]") ? nil : text
        }
    }
}

public final class NativeBarEvents {
    private static var handler: (() -> Void)?
    public init() {}
    public func start(onChange: @escaping () -> Void) -> Bool {
        Self.handler = onChange
        let name = "com.dsbraz.sketchybar.\(getpid())"
        guard sb_listen(name, { bytes, count in
            guard let bytes, count > 0 else { return }
            // SketchyBar sends 'k' when the registered item is destroyed.
            if count == 2 && bytes.pointee == 107 { return }
            NativeBarEvents.handler?()
        }) else { return false }
        return SketchyBarIPC.send(["--set", "spaces_observer", "mach_helper=\(name)",
                                  "--subscribe", "spaces_observer", "space_change", "display_change", "system_woke"]) != nil
    }
}
