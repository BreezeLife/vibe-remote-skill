import Foundation

/// In-memory draft ownership. Transport/recognition events never submit text.
public struct DraftSession {
    public enum Phase: Equatable { case idle, capturing, finishing }

    public private(set) var text: String
    public private(set) var phase: Phase = .idle
    public private(set) var sessionID: UUID?
    private var priorText = ""

    public init(text: String = "") { self.text = text }

    public var isBusy: Bool { phase != .idle }
    public var canCopy: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    public mutating func begin() -> UUID? {
        guard !isBusy else { return nil }
        priorText = text
        sessionID = UUID()
        phase = .capturing
        return sessionID
    }

    public mutating func receive(_ utterance: String, session: UUID) {
        guard sessionID == session, isBusy, !utterance.isEmpty else { return }
        text = priorText + (priorText.isEmpty ? "" : "\n") + utterance
    }

    public mutating func finishCapture() {
        guard phase == .capturing else { return }
        phase = .finishing
    }

    public mutating func complete(session: UUID) {
        guard sessionID == session else { return }
        resetSession()
    }

    public mutating func cancel() {
        guard isBusy else { return }
        text = priorText
        resetSession()
    }

    @discardableResult
    public mutating func replaceText(_ text: String) -> Bool {
        guard !isBusy else { return false }
        self.text = text
        return true
    }

    private mutating func resetSession() {
        phase = .idle
        sessionID = nil
        priorText = ""
    }
}
