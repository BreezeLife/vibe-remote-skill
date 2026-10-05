#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
import Foundation
@testable import VibeRemoteCore

final class ActionSafetyTests: XCTestCase {
    func testSendRequiresEveryLivePrecondition() {
        let valid = ActionSafety(exclusiveDevice: true, suppressionConfirmed: true, busy: false,
                                 operationInProgress: false, hasWorkspace: true, hasDraft: true)
        XCTAssertNil(valid.blockReason(for: .sendDraft))
        var state = valid
        state.exclusiveDevice = false
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
        state = valid; state.suppressionConfirmed = false
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
        state = valid; state.busy = true
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
        state = valid; state.hasWorkspace = false
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
        state = valid; state.hasDraft = false
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
        state = valid; state.operationInProgress = true
        XCTAssertTrue(state.blockReason(for: .sendDraft) != nil)
    }

    func testCancelAndVolumeRemainAvailableDuringCapture() {
        let state = ActionSafety(exclusiveDevice: true, suppressionConfirmed: true, busy: true,
                                 operationInProgress: false, hasWorkspace: false, hasDraft: false)
        XCTAssertNil(state.blockReason(for: .cancel))
        XCTAssertNil(state.blockReason(for: .volumeUp))
        XCTAssertTrue(state.blockReason(for: .nextWorkspace) != nil)
        XCTAssertTrue(state.blockReason(for: .stopTask) != nil)
    }

    func testSnapshotRejectsChangedDraftAndDestination() {
        let id = UUID()
        let snapshot = DraftReview(workspaceID: id, draft: "reviewed")
        XCTAssertTrue(snapshot.matches(workspaceID: id, draft: "reviewed", busy: false))
        XCTAssertFalse(snapshot.matches(workspaceID: UUID(), draft: "reviewed", busy: false))
        XCTAssertFalse(snapshot.matches(workspaceID: id, draft: "edited", busy: false))
        XCTAssertFalse(snapshot.matches(workspaceID: id, draft: "reviewed", busy: true))
    }
}
