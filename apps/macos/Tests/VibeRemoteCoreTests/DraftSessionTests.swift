import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class DraftSessionTests: XCTestCase {
    func testReleaseRetainsDraftAndNeverMakesItCopyableBeforeFinalization() {
        var draft = DraftSession(text: "Existing")
        let id = draft.begin()!
        draft.receive("New words", session: id)
        XCTAssertEqual(draft.text, "Existing\nNew words")
        XCTAssertFalse(draft.canCopy)
        draft.finishCapture()
        XCTAssertEqual(draft.phase, .finishing)
        XCTAssertFalse(draft.canCopy)
        draft.complete(session: id)
        XCTAssertEqual(draft.phase, .idle)
        XCTAssertEqual(draft.text, "Existing\nNew words")
        XCTAssertTrue(draft.canCopy)
    }

    func testPartialResultsReplaceOnlyTheCurrentUtterance() {
        var draft = DraftSession(text: "Prior")
        let id = draft.begin()!
        draft.receive("hello", session: id)
        draft.receive("hello world", session: id)
        XCTAssertEqual(draft.text, "Prior\nhello world")
        draft.receive("", session: id)
        XCTAssertEqual(draft.text, "Prior\nhello world")
    }

    func testCancelRestoresExistingTextAndRejectsLateResult() {
        var draft = DraftSession(text: "Keep this")
        let first = draft.begin()!
        draft.receive("discard", session: first)
        draft.cancel()
        XCTAssertEqual(draft.text, "Keep this")
        let second = draft.begin()!
        draft.receive("stale", session: first)
        draft.complete(session: first)
        XCTAssertEqual(draft.sessionID, second)
        XCTAssertEqual(draft.phase, .capturing)
        draft.receive("new", session: second)
        XCTAssertEqual(draft.text, "Keep this\nnew")
    }

    func testBusySessionBlocksNewRecordingAndEditing() {
        var draft = DraftSession(text: "Original")
        let id = draft.begin()!
        XCTAssertNil(draft.begin())
        XCTAssertFalse(draft.replaceText("overwrite"))
        draft.finishCapture()
        XCTAssertNil(draft.begin())
        XCTAssertFalse(draft.replaceText("overwrite"))
        draft.complete(session: id)
        XCTAssertTrue(draft.replaceText("Edited"))
        XCTAssertEqual(draft.text, "Edited")
    }

    func testEmptyUtteranceAndIdleCancelKeepExistingDraft() {
        var draft = DraftSession(text: "  exact spaces  ")
        let id = draft.begin()!
        draft.finishCapture()
        draft.complete(session: id)
        draft.cancel()
        XCTAssertEqual(draft.text, "  exact spaces  ")
        XCTAssertTrue(draft.replaceText(" \n"))
        XCTAssertFalse(draft.canCopy)
    }
}
