/// A pending layout owns the whole presentation, not only label truncation.
/// Generations reject stale commits after a rapid app/window switch. A failed
/// IPC send leaves the gate closed; only the final successful commit releases it.
struct PresentationGate {
    private(set) var generation: UInt64 = 0
    private var pending = false
    var canPublish: Bool { !pending }
    mutating func begin() -> UInt64 {
        generation &+= 1
        pending = true
        return generation
    }
    func accepts(_ candidate: UInt64) -> Bool { candidate == generation }
    mutating func commit(_ candidate: UInt64) {
        if accepts(candidate) { pending = false }
    }
}
