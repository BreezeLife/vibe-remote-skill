import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class ButtonGesturesTests: XCTestCase {
    func testClickOccursOnlyOnReleaseAndRepeatedDownIsIgnored() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .ok, single: .sendDraft)
        XCTAssertEqual(engine.process(button: .ok, isDown: true, at: 0, mapping: mapping), [])
        XCTAssertEqual(engine.process(button: .ok, isDown: true, at: 0.1, mapping: mapping), [])
        XCTAssertEqual(engine.process(button: .ok, isDown: false, at: 0.2, mapping: mapping), [GestureTrigger(button: .ok, gesture: .click, action: .sendDraft)])
        XCTAssertEqual(engine.process(button: .ok, isDown: false, at: 0.3, mapping: mapping), [])
    }

    func testHoldSuppressesClickAndNeverRepeatsStop() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .back, single: .cancel, long: .stopTask)
        _ = engine.process(button: .back, isDown: true, at: 0, mapping: mapping)
        XCTAssertEqual(engine.advance(to: 0.59), [])
        XCTAssertEqual(engine.advance(to: 0.6), [GestureTrigger(button: .back, gesture: .hold, action: .stopTask)])
        XCTAssertEqual(engine.advance(to: 5), [])
        XCTAssertEqual(engine.process(button: .back, isDown: false, at: 5.1, mapping: mapping), [])
    }

    func testReleaseAlsoResolvesHoldWhenTimerHasNotRun() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .back, single: .cancel, long: .stopTask)
        _ = engine.process(button: .back, isDown: true, at: 0, mapping: mapping)
        XCTAssertEqual(engine.process(button: .back, isDown: false, at: 0.7, mapping: mapping), [GestureTrigger(button: .back, gesture: .hold, action: .stopTask)])
    }

    func testDoubleClickSuppressesBothSinglesAndSingleWaitsForWindow() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .home, single: .focusTarget, double: .workspacePicker)
        _ = engine.process(button: .home, isDown: true, at: 0, mapping: mapping)
        XCTAssertEqual(engine.process(button: .home, isDown: false, at: 0.05, mapping: mapping), [])
        _ = engine.process(button: .home, isDown: true, at: 0.2, mapping: mapping)
        XCTAssertEqual(engine.process(button: .home, isDown: false, at: 0.25, mapping: mapping), [GestureTrigger(button: .home, gesture: .doubleClick, action: .workspacePicker)])
        XCTAssertEqual(engine.advance(to: 1), [])
        _ = engine.process(button: .home, isDown: true, at: 2, mapping: mapping)
        _ = engine.process(button: .home, isDown: false, at: 2.1, mapping: mapping)
        XCTAssertEqual(engine.advance(to: 2.39), [])
        XCTAssertEqual(engine.advance(to: 2.41), [GestureTrigger(button: .home, gesture: .click, action: .focusTarget)])
    }

    func testOnlyScrollAndVolumeRepeatWithoutBurstingAfterDelayedTimer() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .down, single: .scrollDown)
        _ = engine.process(button: .down, isDown: true, at: 0, mapping: mapping)
        XCTAssertEqual(engine.advance(to: 0.6), [GestureTrigger(button: .down, gesture: .hold, action: .scrollDown)])
        XCTAssertEqual(engine.advance(to: 0.72), [GestureTrigger(button: .down, gesture: .hold, action: .scrollDown, repeated: true)])
        XCTAssertEqual(engine.advance(to: 20), [GestureTrigger(button: .down, gesture: .hold, action: .scrollDown, repeated: true)])
        XCTAssertEqual(engine.process(button: .down, isDown: false, at: 20.01, mapping: mapping), [])
        let send = ButtonMapping(button: .ok, single: .sendDraft)
        _ = engine.process(button: .ok, isDown: true, at: 21, mapping: send)
        XCTAssertEqual(engine.advance(to: 30), [])
        XCTAssertEqual(engine.process(button: .ok, isDown: false, at: 31, mapping: send).count, 1)
    }

    func testPulseBindingCannotHoldOrRepeat() {
        var engine = ButtonGestureEngine()
        let input = HIDBinding(usagePage: 1, usage: 1, descriptorHash: String(repeating: "a", count: 64), supportsHold: false)
        let mapping = ButtonMapping(button: .back, single: .cancel, long: .stopTask, input: input)
        _ = engine.process(button: .back, isDown: true, at: 0, mapping: mapping)
        XCTAssertEqual(engine.advance(to: 5), [])
        XCTAssertEqual(engine.process(button: .back, isDown: false, at: 6, mapping: mapping), [GestureTrigger(button: .back, gesture: .click, action: .cancel)])
    }

    func testResetDropsHeldAndPendingClicks() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .home, single: .focusTarget, long: .copyDraft, double: .workspacePicker)
        _ = engine.process(button: .home, isDown: true, at: 0, mapping: mapping)
        _ = engine.process(button: .home, isDown: false, at: 0.1, mapping: mapping)
        engine.reset()
        XCTAssertEqual(engine.advance(to: 1), [])
        _ = engine.process(button: .home, isDown: true, at: 2, mapping: mapping)
        engine.reset()
        XCTAssertEqual(engine.advance(to: 5), [])
        XCTAssertEqual(engine.process(button: .home, isDown: false, at: 6, mapping: mapping), [])
    }

    func testMappingChangeMismatchedButtonAndInvalidTimeDropGesture() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .ok, single: .sendDraft)
        _ = engine.process(button: .ok, isDown: true, at: 1, mapping: mapping)
        XCTAssertEqual(engine.process(button: .ok, isDown: false, at: 2, mapping: ButtonMapping(button: .ok, single: .stopTask)), [])
        _ = engine.process(button: .ok, isDown: true, at: 3, mapping: mapping)
        XCTAssertEqual(engine.process(button: .ok, isDown: false, at: 2, mapping: mapping), [])
        XCTAssertEqual(engine.process(button: .ok, isDown: true, at: .nan, mapping: mapping), [])
        XCTAssertEqual(engine.process(button: .home, isDown: true, at: 5, mapping: mapping), [])
        XCTAssertEqual(engine.advance(to: 10), [])
    }

    func testMicrophoneNeverProducesHIDActionEvenWithInvalidMapping() {
        var engine = ButtonGestureEngine()
        let mapping = ButtonMapping(button: .mic, single: .sendDraft, long: .stopTask)
        XCTAssertEqual(engine.process(button: .mic, isDown: true, at: 0, mapping: mapping), [])
        XCTAssertEqual(engine.advance(to: 1), [])
        XCTAssertEqual(engine.process(button: .mic, isDown: false, at: 2, mapping: mapping), [])
    }
}
