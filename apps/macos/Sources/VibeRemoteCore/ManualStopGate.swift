/// ATVV AUDIO_STOP does not prove the user released the physical voice key.
/// After a host-requested stop, only a new connection may accept another start.
public struct ManualStopGate {
    public enum State: Equatable { case accepting, awaitingStop, reconnectRequired }

    public private(set) var state: State = .accepting
    public init() {}

    public var allowsStart: Bool { state == .accepting }
    public var awaitingStop: Bool { state == .awaitingStop }

    public mutating func requestStop() {
        if state == .accepting { state = .awaitingStop }
    }

    /// Returns whether the transport must disconnect instead of remaining ready.
    @discardableResult
    public mutating func receiveAudioStop() -> Bool {
        guard state != .accepting else { return false }
        state = .reconnectRequired
        return true
    }
}
