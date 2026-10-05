import Foundation

// Every service is a fake: these model checks never create a Bluetooth central,
// instantiate a speech recognizer, request TCC access or use the pasteboard.
private final class FakeBluetooth: BluetoothServicing {
    var onStatus: ((String) -> Void)?
    var onReady: ((Bool) -> Void)?
    var onStream: ((Bool, Int) -> Void)?
    var onSamples: (([Int16], Int) -> Void)?
    var onLevel: ((Double) -> Void)?
    private(set) var starts = 0
    private(set) var disconnects = 0
    private(set) var captureStops = 0

    func start() { starts += 1 }
    func disconnect() { disconnects += 1 }
    func stopCapture() {
        captureStops += 1
        // The real transport ends audio synchronously after a manual close.
        onStream?(false, 16_000)
    }
    func stream(_ active: Bool, rate: Int = 16_000) { onStream?(active, rate) }
    func samples(_ samples: [Int16] = [0, 1, -1], rate: Int = 16_000) {
        onSamples?(samples, rate)
    }
}

private final class FakeSpeech: SpeechServicing {
    var isAuthorized: Bool
    var onText: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onFinished: (() -> Void)?
    var startError: Error?
    private(set) var authorizationRequests = 0
    private(set) var startOptions: [(locale: String, online: Bool)] = []
    private(set) var appendedFrames: [(samples: [Int16], rate: Int)] = []
    private(set) var finishes = 0
    private(set) var cancels = 0
    var appendError: String?
    var finishError: String?
    private var authorizationCompletion: ((Bool) -> Void)?

    init(authorized: Bool) { isAuthorized = authorized }
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequests += 1
        authorizationCompletion = completion
    }
    func authorize(_ allowed: Bool) {
        isAuthorized = allowed
        let completion = authorizationCompletion
        authorizationCompletion = nil
        completion?(allowed)
    }
    func start(localeIdentifier: String, allowServerRecognition: Bool) throws {
        startOptions.append((localeIdentifier, allowServerRecognition))
        if let startError { throw startError }
    }
    func append(samples: [Int16], sampleRate: Int) {
        appendedFrames.append((samples, sampleRate))
        if let appendError { complete(error: appendError) }
    }
    func finish() {
        finishes += 1
        if let finishError { complete(error: finishError) }
    }
    func cancel() { cancels += 1 }
    func text(_ text: String, final: Bool = false) { onText?(text, final) }
    func complete(error: String? = nil) {
        if let error { onError?(error) }
        onFinished?()
    }
}

private var failures = 0
private var assertions = 0
private var currentCase = ""
private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    assertions += 1
    if !condition() {
        failures += 1
        print("FAIL \(currentCase): \(label)")
    }
}

private func fixture(authorized: Bool = true, enable: Bool = true)
    -> (RemoteModel, FakeBluetooth, FakeSpeech) {
    let bluetooth = FakeBluetooth()
    let speech = FakeSpeech(authorized: authorized)
    let model = RemoteModel(bluetooth: bluetooth, speech: speech)
    if enable {
        model.enableRecognition()
        speech.authorize(authorized)
    }
    bluetooth.onReady?(true)
    model.replaceDraft("prior draft")
    return (model, bluetooth, speech)
}

private func noAuthorizationKeepsTransportAndSignal() {
    let (model, bluetooth, speech) = fixture(authorized: false, enable: false)
    bluetooth.stream(true)
    bluetooth.samples()
    bluetooth.onLevel?(-12)
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "an audio-only hold is busy and cannot expose a copyable draft")
    model.replaceDraft("must not replace during remote audio")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "missing Speech authorization does not close remote audio or disconnect")
    check(speech.startOptions.isEmpty && speech.appendedFrames.isEmpty,
          "unauthorized PCM never reaches Speech")
    check(model.sampleCount == 3 && model.sampleRate == 16_000 && model.level == -12,
          "remote PCM count, negotiated rate and signal remain observable")
    check(model.draft.text == "prior draft" && model.draft.phase == .idle,
          "missing authorization does not begin or change the draft")
    check(model.message.contains("授权"), "authorization issue is explained")
    check(model.recognitionIssue?.contains("授权") == true,
          "authorization is a recognition issue independent of transport readiness")
    bluetooth.stream(false)
    check(bluetooth.captureStops == 0 && speech.finishes == 0,
          "physical release completes an audio-only hold without a synthetic stop")
    check(model.level == -60 && model.draft.text == "prior draft",
          "release resets signal and retains existing text")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "release ends the audio-only hold and restores draft copying")
    check(model.recognitionIssue != nil, "release retains the unresolved authorization issue")
}

private func startFailurePreservesReasonAndTransport() {
    let (model, bluetooth, speech) = fixture()
    speech.startError = SpeechServiceError.unsupportedLocale
    model.localeIdentifier = "unsupported-test-locale"
    bluetooth.stream(true)
    bluetooth.samples()
    bluetooth.onLevel?(-18)
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "failed recognition still leaves an active audio-only hold")
    check(speech.startOptions.count == 1, "recognition was attempted once")
    check(speech.startOptions.first?.locale == "unsupported-test-locale"
          && speech.startOptions.first?.online == false,
          "the model passes the selected locale and local-recognition policy")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "unsupported locale does not close the remote stream")
    check(speech.appendedFrames.isEmpty && model.draft.text == "prior draft",
          "failed start neither forwards PCM nor changes the draft")
    check(model.sampleCount == 3 && model.level == -18,
          "failed recognition still exposes received PCM and signal")
    check(model.message == SpeechServiceError.unsupportedLocale.localizedDescription,
          "the actual locale error remains visible")
    check(model.recognitionIssue == SpeechServiceError.unsupportedLocale.localizedDescription,
          "the recognition issue records the actual start error")
    bluetooth.stream(false)
    check(model.message == SpeechServiceError.unsupportedLocale.localizedDescription,
          "release does not replace the recognition error with a success message")
    check(speech.finishes == 0 && bluetooth.captureStops == 0,
          "a start failure is never finalized or converted into a manual stop")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "physical release restores idle draft controls after start failure")
}

private func persistedAuthorizationIsImmediatelyEnabled() {
    let (model, _, speech) = fixture(authorized: true, enable: false)
    check(model.recognitionEnabled, "a fresh model restores observed OS authorization")
    check(speech.authorizationRequests == 0, "restoring authorization needs no permission request")
    check(model.recognitionIssue == nil && !model.isBusy && model.canCopy,
          "authorized idle models start without a recognition issue")
}

private func authorizationDuringHoldWaitsForNextPress() {
    let (model, bluetooth, speech) = fixture(authorized: false, enable: false)
    model.enableRecognition()
    bluetooth.stream(true)
    speech.authorize(true)
    bluetooth.samples()
    bluetooth.stream(true)
    check(model.recognitionEnabled && !model.requestingAuthorization,
          "authorization completion updates recognition availability")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "authorization does not end ownership of the current physical hold")
    check(model.recognitionIssue?.contains("松开") == true,
          "mid-hold authorization explains the required release before dictating")
    check(speech.startOptions.isEmpty && speech.appendedFrames.isEmpty,
          "authorization and duplicate start cannot start recognition midway through a hold")
    check(model.draft.text == "prior draft", "the in-progress audio-only hold keeps the draft")
    check(bluetooth.captureStops == 0, "authorization flow never manually stops the transport")
    bluetooth.stream(false)
    bluetooth.stream(true)
    bluetooth.samples()
    check(speech.startOptions.count == 1 && speech.appendedFrames.count == 1,
          "the next physical hold begins exactly one recognition session")
    check(model.recognitionIssue == nil, "successful next hold clears the old recognition issue")
}

private func recognitionErrorDuringHoldIgnoresRemainingSpeechInput() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    speech.text("partial fixture")
    speech.complete(error: "synthetic recognizer unavailable")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "an early recognizer error does not close Bluetooth capture")
    check(model.draft.text == "prior draft\npartial fixture" && model.draft.phase == .finishing,
          "partial text remains cancellable until the physical hold ends")
    check(model.message == "synthetic recognizer unavailable", "the recognizer reason is retained")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "early recognition failure keeps remote audio ownership until physical release")
    check(model.recognitionIssue == "synthetic recognizer unavailable",
          "recognition failure remains a distinct visible issue")
    bluetooth.samples([2, 3])
    bluetooth.stream(true)
    speech.text("stale result")
    speech.complete()
    speech.complete(error: "late completed error")
    check(speech.appendedFrames.count == 1 && speech.startOptions.count == 1,
          "remaining PCM and duplicate starts cannot feed or restart the completed recognizer")
    check(model.draft.text == "prior draft\npartial fixture",
          "late speech callbacks cannot replace the retained draft")
    check(model.sampleCount == 5, "remote frame counting continues after the recognizer stops")
    check(model.recognitionIssue == "synthetic recognizer unavailable"
          && model.draft.phase == .finishing,
          "late errors and duplicate completion cannot replace the first issue or lose cancellation")
    bluetooth.stream(false)
    check(speech.finishes == 0 && model.message == "synthetic recognizer unavailable",
          "natural release does not finalize or obscure the already-failed recognizer")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "release makes the retained partial draft copyable")
}

private func earlyFinalResultKeepsTransportUntilRelease() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    speech.text("final fixture", final: true)
    speech.complete()
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "an early final result does not manually close Bluetooth capture")
    check(model.draft.text == "prior draft\nfinal fixture" && model.draft.phase == .finishing,
          "the early final result remains cancellable until physical release")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy && model.recognitionIssue == nil,
          "a settled recognizer leaves the physical hold busy without reporting an error")
    model.replaceDraft("must not edit during remaining audio")
    bluetooth.samples([4, 5])
    bluetooth.stream(true)
    speech.text("stale final", final: true)
    speech.complete(error: "late final error")
    check(speech.startOptions.count == 1 && speech.appendedFrames.count == 1,
          "the remaining hold cannot restart recognition or forward more PCM")
    check(model.draft.text == "prior draft\nfinal fixture", "late final text is ignored")
    check(model.recognitionIssue == nil && model.draft.phase == .finishing,
          "late errors cannot change a completed recognizer or end cancellation ownership")
    bluetooth.stream(false)
    check(speech.finishes == 0 && bluetooth.captureStops == 0,
          "release after an early final result needs no recognition or transport stop")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "physical release exposes the early final draft for explicit copying")
}

private func naturalReleaseFinalizesAndRetainsDraft() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true, rate: 8_000)
    bluetooth.samples([100, -100], rate: 8_000)
    speech.text("partial fixture")
    check(model.draft.phase == .capturing && model.sampleRate == 8_000,
          "a normal hold captures at the negotiated rate")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "capture owns remote audio and blocks copying")
    check(speech.appendedFrames.first?.samples == [100, -100]
          && speech.appendedFrames.first?.rate == 8_000,
          "remote PCM is forwarded unchanged with its negotiated rate")
    bluetooth.stream(false, rate: 8_000)
    bluetooth.stream(false, rate: 8_000)
    check(speech.finishes == 1 && model.draft.phase == .finishing,
          "natural release finalizes exactly once")
    check(!model.isReceivingAudio && model.isBusy && !model.canCopy,
          "pending speech finalization remains busy after physical audio has ended")
    model.replaceDraft("must not replace pending text")
    check(model.draft.text == "prior draft\npartial fixture", "finalization protects pending draft text")
    speech.text("completed fixture", final: true)
    speech.complete()
    check(model.draft.text == "prior draft\ncompleted fixture" && model.draft.canCopy,
          "the completed utterance appends to the prior draft and becomes copyable")
    check(!model.isBusy && model.canCopy && model.recognitionIssue == nil,
          "completed recognition restores model controls without an issue")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "normal release retains the Bluetooth connection")
    bluetooth.stream(true)
    speech.text("second fixture")
    bluetooth.stream(false)
    speech.complete()
    check(speech.startOptions.count == 2 && speech.finishes == 2,
          "two consecutive natural holds each start and finish once")
    check(model.draft.text == "prior draft\ncompleted fixture\nsecond fixture",
          "the second hold appends without erasing prior utterances")
}

private func userCancellationStopsOnceAndRestoresPriorDraft() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    speech.text("cancelled fixture")
    model.cancelUtterance()
    check(bluetooth.captureStops == 1 && bluetooth.disconnects == 0,
          "explicit user cancellation still asks the transport to stop exactly once")
    check(speech.cancels == 1 && speech.finishes == 0,
          "cancellation cancels recognition instead of finalizing it")
    check(model.draft.text == "prior draft" && model.draft.phase == .idle,
          "cancel restores the text from before this utterance")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "the explicit stop callback settles model controls after cancellation")
    bluetooth.samples([6, 7])
    speech.text("late cancelled result", final: true)
    speech.complete()
    check(model.draft.text == "prior draft" && speech.appendedFrames.count == 1,
          "late cancelled callbacks and PCM cannot mutate the prior draft")
}

private func duplicateStreamStartDoesNotRestartOrStopCapture() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    bluetooth.stream(true)
    bluetooth.samples([8, 9])
    check(speech.startOptions.count == 1 && model.draft.phase == .capturing,
          "a duplicate active callback preserves the current recognition session")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "duplicate active callbacks do not become manual stops")
    check(speech.appendedFrames.count == 2 && model.sampleCount == 5,
          "duplicate starts do not reset counters or drop subsequent frames")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "duplicate callbacks preserve the physical hold state")
    bluetooth.stream(false)
    check(speech.finishes == 1, "the single physical hold finalizes once")
}

private func newHoldDuringFinalizationNeverAttachesToOldRecognition() {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    speech.text("first partial")
    bluetooth.stream(false)
    check(model.draft.phase == .finishing && speech.finishes == 1,
          "the first utterance remains pending after release")
    bluetooth.stream(true)
    bluetooth.samples([10, 11])
    check(speech.startOptions.count == 1 && speech.appendedFrames.count == 1,
          "a second hold cannot enter a recognizer still finalizing the first utterance")
    check(model.isReceivingAudio && model.isBusy && !model.canCopy,
          "the overlapping audio-only hold remains observable and busy")
    speech.text("first final", final: true)
    speech.complete()
    bluetooth.samples([12, 13])
    bluetooth.stream(true)
    check(model.draft.text == "prior draft\nfirst final" && model.draft.phase == .idle,
          "old completion settles only the old utterance")
    check(speech.startOptions.count == 1 && speech.appendedFrames.count == 1,
          "old completion and duplicate start do not attach the remaining hold to Speech")
    check(model.sampleCount == 4 && model.isReceivingAudio && !model.canCopy,
          "the overlapping hold keeps its own PCM counter until release")
    bluetooth.stream(false)
    check(!model.isBusy && model.canCopy && speech.finishes == 1,
          "release settles the audio-only hold without finalizing the old recognizer twice")
    bluetooth.stream(true)
    bluetooth.samples([14, 15])
    check(speech.startOptions.count == 2 && speech.appendedFrames.count == 2,
          "a fresh hold after settlement starts a new recognition session")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "overlapping finalization never becomes a manual transport stop")
}

private func authorizationRevocationIsObservedOnEveryHold() {
    let (model, bluetooth, speech) = fixture(authorized: true, enable: false)
    check(model.recognitionEnabled, "the initial OS authorization is observed")
    speech.isAuthorized = false
    bluetooth.stream(true)
    bluetooth.samples()
    check(!model.recognitionEnabled && speech.startOptions.isEmpty && speech.appendedFrames.isEmpty,
          "revoked authorization blocks recognition on the next hold")
    check(model.isReceivingAudio && model.sampleCount == 3 && model.recognitionIssue != nil,
          "revocation retains remote audio diagnostics and explains recognition availability")
    bluetooth.stream(false)
    speech.isAuthorized = true
    bluetooth.stream(true)
    bluetooth.samples()
    check(model.recognitionEnabled && speech.startOptions.count == 1 && speech.appendedFrames.count == 1,
          "authorization restored externally is observed on the following hold")
    check(model.recognitionIssue == nil && bluetooth.captureStops == 0,
          "successful restored recognition clears the issue without stopping transport")
}

private func synchronousPCMFailureKeepsReceivingAudio() {
    let (model, bluetooth, speech) = fixture()
    speech.appendError = "synthetic PCM conversion error"
    bluetooth.stream(true)
    bluetooth.samples()
    bluetooth.onLevel?(-24)
    check(model.isReceivingAudio && model.isBusy && !model.canCopy && model.level == -24,
          "a synchronous PCM error leaves remote audio and signal diagnostics active")
    check(model.recognitionIssue == "synthetic PCM conversion error" && model.draft.phase == .finishing,
          "synchronous recognition failure preserves cancellation and its cause until release")
    bluetooth.samples([16, 17])
    check(speech.appendedFrames.count == 1 && model.sampleCount == 5,
          "subsequent PCM is counted but not sent to the failed recognizer")
    bluetooth.stream(false)
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0 && model.canCopy,
          "synchronous recognition errors never force a Bluetooth stop")
}

private func synchronousFinalizationFailureRetainsDraftAndReason() {
    let (model, bluetooth, speech) = fixture()
    speech.finishError = "synthetic PCM flush error"
    bluetooth.stream(true)
    speech.text("retained partial fixture")
    bluetooth.stream(false)
    check(speech.finishes == 1 && model.draft.phase == .idle,
          "synchronous finalization failure settles the one pending recognition session")
    check(model.draft.text == "prior draft\nretained partial fixture",
          "PCM flush failure retains the partial utterance and prior draft")
    check(model.message == "synthetic PCM flush error"
          && model.recognitionIssue == "synthetic PCM flush error",
          "the synchronous flush cause survives finalization callbacks")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "failed finalization leaves the retained draft available for review")
    bluetooth.stream(false)
    speech.text("late flush result", final: true)
    check(speech.finishes == 1 && model.draft.text == "prior draft\nretained partial fixture",
          "duplicate release and late final text cannot repeat or overwrite failed finalization")
    check(bluetooth.captureStops == 0 && bluetooth.disconnects == 0,
          "a finalization error never becomes a manual transport stop")
}

private func checkCancellationAfterEarlyCompletion(error: String?) {
    let (model, bluetooth, speech) = fixture()
    bluetooth.stream(true)
    bluetooth.samples()
    speech.text("early completed fixture", final: error == nil)
    speech.complete(error: error)
    check(model.draft.phase == .finishing && model.draft.isBusy && model.isReceivingAudio,
          "early recognizer completion keeps cancellation ownership until physical release")
    check(model.draft.text == "prior draft\nearly completed fixture" && bluetooth.captureStops == 0,
          "early completion retains current text without a synthetic transport stop")
    model.cancelUtterance()
    check(model.draft.text == "prior draft" && model.draft.phase == .idle,
          "user cancellation after early completion restores the pre-utterance draft")
    check(bluetooth.captureStops == 1 && speech.cancels == 1 && speech.finishes == 0,
          "explicit cancellation stops once and never re-finalizes the completed recognizer")
    check(!model.isReceivingAudio && !model.isBusy && model.canCopy,
          "cancellation settles audio ownership and restores review controls")
    bluetooth.samples([18, 19])
    speech.text("late completed result", final: true)
    speech.complete()
    check(model.draft.text == "prior draft" && speech.appendedFrames.count == 1,
          "late completed callbacks cannot bring a cancelled utterance back")
    let issueAfterCancel = model.recognitionIssue
    let messageAfterCancel = model.message
    speech.complete(error: "late cancelled error")
    check(model.recognitionIssue == issueAfterCancel && model.message == messageAfterCancel,
          "late errors after cancellation cannot overwrite current feedback")
}

private func userCancellationAfterEarlyFinalRestoresPriorDraft() {
    checkCancellationAfterEarlyCompletion(error: nil)
}

private func userCancellationAfterEarlyErrorRestoresPriorDraft() {
    checkCancellationAfterEarlyCompletion(error: "synthetic early completion error")
}

private func workspaceDraftsAreIsolated() {
    let (model, _, _) = fixture()
    let first = UUID(), second = UUID()
    check(model.selectWorkspace(first), "select first workspace")
    check(model.draft.text.isEmpty, "unbound draft is not silently moved")
    model.replaceDraft("first workspace text")
    check(model.selectWorkspace(second), "select second workspace")
    check(model.draft.text.isEmpty, "second workspace starts independently")
    model.replaceDraft("second workspace text")
    check(model.selectWorkspace(first), "return to first")
    check(model.draft.text == "first workspace text", "first workspace keeps its text")
    check(model.selectWorkspace(nil), "return to unbound draft")
    check(model.draft.text == "prior draft", "original unbound draft remains")
}

private func captureAndFinalizationLockWorkspace() {
    let (model, bluetooth, speech) = fixture()
    let first = UUID(), second = UUID()
    check(model.selectWorkspace(first), "select before capture")
    bluetooth.stream(true)
    check(!model.selectWorkspace(second) && model.workspaceID == first,
          "active audio locks target")
    speech.text("first workspace utterance")
    bluetooth.stream(false)
    check(!model.selectWorkspace(second), "finalization locks target")
    speech.complete()
    check(model.selectWorkspace(second), "settled draft permits switching")
    check(model.draft.text.isEmpty, "late result does not follow destination")
    speech.text("late text")
    check(model.selectWorkspace(first), "can inspect captured workspace")
    check(model.draft.text == "first workspace utterance", "result remains owned by capture target")
}

private let cases: [(String, () -> Void)] = [
    ("workspace draft ownership", workspaceDraftsAreIsolated),
    ("workspace capture lock", captureAndFinalizationLockWorkspace),
    ("no authorization retains audio transport", noAuthorizationKeepsTransportAndSignal),
    ("recognizer start failure retains transport and reason", startFailurePreservesReasonAndTransport),
    ("persisted OS authorization", persistedAuthorizationIsImmediatelyEnabled),
    ("authorization completion during a hold", authorizationDuringHoldWaitsForNextPress),
    ("recognition error during active remote audio", recognitionErrorDuringHoldIgnoresRemainingSpeechInput),
    ("early final result during active remote audio", earlyFinalResultKeepsTransportUntilRelease),
    ("natural release and consecutive holds", naturalReleaseFinalizesAndRetainsDraft),
    ("explicit user cancellation", userCancellationStopsOnceAndRestoresPriorDraft),
    ("duplicate active stream callback", duplicateStreamStartDoesNotRestartOrStopCapture),
    ("a new hold overlaps prior finalization", newHoldDuringFinalizationNeverAttachesToOldRecognition),
    ("OS authorization changes between holds", authorizationRevocationIsObservedOnEveryHold),
    ("synchronous PCM recognition failure", synchronousPCMFailureKeepsReceivingAudio),
    ("synchronous PCM finalization failure", synchronousFinalizationFailureRetainsDraftAndReason),
    ("cancel after an early final result", userCancellationAfterEarlyFinalRestoresPriorDraft),
    ("cancel after an early recognition error", userCancellationAfterEarlyErrorRestoresPriorDraft),
]

for (name, run) in cases {
    currentCase = name
    let before = failures
    run()
    if failures == before { print("PASS \(name)") }
}
print("\(cases.count) model scenarios, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
