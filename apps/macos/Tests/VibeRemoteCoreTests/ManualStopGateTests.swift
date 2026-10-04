import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class ManualStopGateTests: XCTestCase {
    func testCancelThenAudioStopCannotReviveFromRepeatedStartSearch() throws {
        let handler = ATVVProtocol()
        try handler.acceptCapabilities(ATVVCapabilities(
            version: .v10, codecs: 3, interactionModel: 3, frameSize: 120))
        var gate = ManualStopGate()
        var draft = DraftSession(text: "Keep existing draft")

        XCTAssertEqual(handler.parseControl(Data([0x08])), .startSearch)
        XCTAssertTrue(gate.allowsStart)
        let id = draft.begin()!
        draft.receive("cancel this utterance", session: id)

        draft.cancel()
        gate.requestStop()
        XCTAssertFalse(gate.allowsStart)
        XCTAssertTrue(gate.awaitingStop)
        XCTAssertEqual(handler.parseControl(Data([0x00, 2])), .audioStop(reason: 2))
        XCTAssertTrue(gate.receiveAudioStop())

        // A held key may repeat START_SEARCH after MIC_CLOSE was acknowledged.
        // The cancelled segment must stay closed throughout this connection.
        XCTAssertEqual(handler.parseControl(Data([0x08])), .startSearch)
        XCTAssertFalse(gate.allowsStart)
        XCTAssertFalse(gate.awaitingStop)
        XCTAssertEqual(gate.state, .reconnectRequired)
        draft.receive("late result", session: id)
        XCTAssertEqual(draft.text, "Keep existing draft")
        XCTAssertEqual(draft.phase, .idle)
    }

    func testNaturalReleaseKeepsConnectionAvailableForNextHold() {
        var gate = ManualStopGate()
        XCTAssertFalse(gate.receiveAudioStop())
        XCTAssertTrue(gate.allowsStart)
        XCTAssertEqual(gate.state, .accepting)
    }

    func testOnlyNewConnectionRestoresStartAfterManualStop() {
        var gate = ManualStopGate()
        gate.requestStop()
        gate.requestStop()
        XCTAssertTrue(gate.receiveAudioStop())
        XCTAssertTrue(gate.receiveAudioStop())
        XCTAssertFalse(gate.allowsStart)
        gate = ManualStopGate()
        XCTAssertTrue(gate.allowsStart)
    }
}
