import Foundation
import VibeRemoteCore

final class FakeAudio: RemoteAudioOutputting {
    var onError: ((Error) -> Void)?
    var starts = 0, appends = 0, cancels = 0
    var done: ((Result<Void, Error>) -> Void)?
    var failStart = false
    var onStart: (() -> Void)?
    func availableDevices() -> [RemoteAudioDevice] { [.init(id: "fixture", name: "Fixture", driverBundleID: "fixture")] }
    func start(deviceUID: String, sampleRate: Int) throws { starts += 1; onStart?(); if failStart { throw NSError(domain: "fixture", code: 1) } }
    func append(samples: [Int16], sampleRate: Int) throws { appends += 1 }
    func finish(completion: @escaping (Result<Void, Error>) -> Void) { done = completion }
    func cancel() { cancels += 1 }
}
final class FakeKeys: DictationHotkeySending {
    var isAuthorized = true
    var events: [String] = []
    func begin(_ profile: VoiceInputProfile) throws { events.append("begin") }
    func end(_ profile: VoiceInputProfile) throws { events.append("end") }
    func releaseHeldKey() { events.append("release") }
}
final class FakeFocusReference: FocusedInputReference {
    let id = UUID()
    func matches(_ other: FocusedInputReference) -> Bool { (other as? FakeFocusReference)?.id == id }
}
final class FakeFocusDriver: FocusedInputDriver {
    var isTrusted = true
    var reads = 0, writes = 0
    var current = FocusedInputSnapshot(processID: 42, appName: "Fixture Editor", window: FakeFocusReference(),
                                       element: FakeFocusReference(), text: "before", selection: NSRange(location: 6, length: 0))
    func snapshot() throws -> FocusedInputSnapshot { reads += 1; return current }
    func replaceSelectedText(_ text: String, in snapshot: FocusedInputSnapshot) throws { writes += 1 }
}
var assertions = 0, failures = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    assertions += 1
    if !value() { failures += 1; print("FAIL \(label)") }
}
func rejected(_ label: String, _ body: () throws -> Void) {
    assertions += 1
    do { try body(); failures += 1; print("FAIL \(label)") } catch { }
}
func fixture() -> (ExternalDictationController, FakeAudio, FakeKeys, VoiceInputProfile) {
    let audio = FakeAudio(), keys = FakeKeys()
    let controller = ExternalDictationController(audio: audio, hotkeys: keys, monitorFocus: false)
    controller.receiverIsFocused = { true }
    var profile = VoiceInputProfile(provider: .typeless)
    profile.outputDeviceUID = "fixture"; profile.triggerMode = .toggle; profile.shortcutKeyCode = 90
    return (controller, audio, keys, profile)
}
func directFixture() -> (ExternalDictationController, FakeAudio, FakeKeys, VoiceInputProfile, FakeFocusDriver) {
    let audio = FakeAudio(), keys = FakeKeys(), focus = FakeFocusDriver()
    let controller = ExternalDictationController(audio: audio, hotkeys: keys,
                                                 focusedInput: FocusedInputService(driver: focus), monitorFocus: false)
    controller.receiverIsFocused = { false }
    var profile = VoiceInputProfile(provider: .typeless)
    profile.outputDeviceUID = "fixture"; profile.triggerMode = .toggle; profile.shortcutKeyCode = 90
    return (controller, audio, keys, profile, focus)
}
do {
    let (c, a, k, p) = fixture()
    rejected("microphone must be explicitly checked") { try c.prepare(p, microphoneConfirmed: false, shortcutConfirmed: true) }
    rejected("shortcut must be explicitly checked") { try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: false) }
    check(a.starts == 0 && k.events.isEmpty, "configuration and preflight execute nothing")
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    check(c.isBusy, "prepared receiver locks workspace")
    c.startCapture(sampleRate: 16000); c.startCapture(sampleRate: 16000)
    c.append(samples: [1, 2], sampleRate: 16000)
    check(a.starts == 1 && a.appends == 1 && k.events == ["begin"], "one start gesture and audio route")
    c.finishCapture(); c.finishCapture()
    check(c.phase == .draining && k.events == ["begin"], "audio drains before end gesture")
    a.done?(.success(()))
    check(c.phase == .review && k.events == ["begin", "end"], "one matching end and locked review")
    c.resultText = "fixture text"
    check(c.takeResult(providerFinished: false) == nil && c.isBusy, "unknown provider state blocks import")
    check(c.takeResult(providerFinished: true) == "fixture text" && !c.isBusy, "explicit review returns text once")
    check(c.takeResult(providerFinished: true) == nil, "no duplicate import")
}
do {
    let (c, a, k, p) = fixture()
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    c.receiverIsFocused = { false }; c.startCapture(sampleRate: 8000)
    check(a.starts == 0 && k.events.isEmpty && c.phase == .review, "unknown focus blocks both audio and hotkey")
}
do {
    let (c, a, k, p) = fixture()
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    c.startCapture(sampleRate: 16000); c.finishCapture()
    c.interrupt(); a.done?(.success(()))
    check(k.events == ["begin", "release"], "cancelled drain cannot toggle later")
    check(c.isBusy && c.phase == .review, "interruption requires manual provider settlement")
    check(!c.discard(providerFinished: false), "unknown recording blocks closing receiver")
    check(c.discard(providerFinished: true), "explicit discard closes only segment")
}
do {
    let (c, a, k, p) = fixture()
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    c.startCapture(sampleRate: 16000); c.receiverIsFocused = { false }; c.checkFocus()
    check(c.phase == .review && a.cancels > 0 && !k.events.contains("end"), "focus loss halts output without blind toggle")
}
do {
    let (c, a, k, initial) = fixture(); var p = initial; p.triggerMode = .manual
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: false)
    c.startCapture(sampleRate: 8000); c.finishCapture(); a.done?(.success(()))
    check(k.events.isEmpty && c.phase == .review, "manual provider never injects a shortcut")
}
do {
    let (c, a, k, p) = fixture(); a.failStart = true
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    c.startCapture(sampleRate: 16000)
    check(!k.events.contains("begin") && c.phase == .review, "failed route cannot start provider")
}
do {
    let (c, a, k, p) = fixture()
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    c.startCapture(sampleRate: 16000)
    a.onError?(NSError(domain: "fixture-device-lost", code: 1))
    check(c.phase == .review && a.cancels == 1 && k.events == ["begin", "release"], "asynchronous route loss immediately halts without toggle")
    c.finishCapture()
    check(!k.events.contains("end"), "route loss cannot end with a new toggle on release")
}
do {
    let (c, a, k, _) = fixture()
    c.startCapture(sampleRate: 16000); c.append(samples: [1], sampleRate: 16000); c.finishCapture()
    check(!c.isBusy && a.starts == 0 && k.events.isEmpty, "unprepared external mode never forwards audio or keys")
}
do {
    let (c, a, k, p, f) = directFixture()
    for mode in [VoiceTriggerMode.manual, .hold, .toggle] {
        var profile = p; profile.triggerMode = mode
        rejected("direct \(mode) requires auto-send disabled confirmation") {
            try c.prepare(profile, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true)
        }
    }
    check(f.reads == 0 && f.writes == 0 && a.starts == 0 && k.events.isEmpty && !c.isBusy,
          "rejected direct preparation has no focus, audio or key side effects")
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    check(c.destination == .currentFocus && c.phase == .prepared && f.reads == 0,
          "direct preparation arms without capturing the configuration window")
    check(!c.completeDirect(providerFinished: true), "cannot complete an unstarted direct segment")
    c.startCapture(sampleRate: 16000)
    check(c.phase == .capturing && f.reads > 0 && a.starts == 1 && k.events == ["begin"],
          "actual remote hold captures current input without requiring own receiver")
    check(!c.completeDirect(providerFinished: true), "recording direct segment cannot be settled")
    f.current.text = "provider interim text"; f.current.selection = NSRange(location: 21, length: 0)
    c.append(samples: [1], sampleRate: 16000)
    check(a.appends == 1 && c.phase == .capturing, "provider interim insertion does not invalidate target identity")
    c.finishCapture()
    check(!c.completeDirect(providerFinished: true), "draining direct segment cannot be settled")
    let oldCompletion = a.done
    a.done?(.success(()))
    c.resultText = "must not be duplicated"
    check(c.phase == .review && k.events == ["begin", "end"], "direct release ends gesture after audio drain")
    check(c.takeResult(providerFinished: true) == nil && c.isBusy && f.writes == 0,
          "direct provider owns insertion; no draft import or adapter insertion")
    check(!c.completeDirect(providerFinished: false) && c.phase == .review, "unknown provider completion cannot rearm")
    check(c.completeDirect(providerFinished: true) && c.phase == .prepared && c.isBusy && c.profile == p && c.resultText.isEmpty,
          "explicit completion rearms retained direct profile and clears segment text")
    f.current.element = FakeFocusReference()
    c.startCapture(sampleRate: 16000); c.finishCapture()
    oldCompletion?(.success(()))
    check(c.phase == .draining && k.events == ["begin", "end", "begin"], "old segment callback cannot end a newly armed segment")
    a.done?(.success(()))
    check(k.events == ["begin", "end", "begin", "end"] && f.writes == 0,
          "new hold binds new input and never writes or submits text itself")
    check(c.discard(providerFinished: true) && !c.isBusy, "explicit direct discard releases prepared configuration")
}
do {
    let (c, a, k, p, f) = directFixture()
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    f.current.secure = true
    c.startCapture(sampleRate: 16000)
    check(c.phase == .review && a.starts == 0 && k.events.isEmpty && f.writes == 0,
          "unsupported focus retains uncertain manual-state review without audio or trigger")
    check(!c.discard(providerFinished: false), "failed focus capture does not infer provider stopped")
}
do {
    let (c, a, k, p, f) = directFixture()
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    c.startCapture(sampleRate: 16000)
    f.current.element = FakeFocusReference()
    c.append(samples: [1], sampleRate: 16000)
    check(c.phase == .review && a.appends == 0 && a.cancels == 1 && k.events == ["begin", "release"],
          "focus loss during direct stream halts audio without a blind end toggle")
    c.finishCapture()
    check(!k.events.contains("end") && f.writes == 0, "physical release after focus loss does not reactivate provider or write text")
}
do {
    let (c, a, k, p, f) = directFixture()
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    c.startCapture(sampleRate: 16000); c.finishCapture()
    f.current.processID = 43
    a.done?(.success(()))
    check(c.phase == .review && k.events == ["begin", "release"] && a.cancels == 1,
          "focus loss during direct drain blocks completion gesture")
}
do {
    let (c, a, k, p, f) = directFixture()
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    a.onStart = { f.current.element = FakeFocusReference() }
    c.startCapture(sampleRate: 16000)
    check(c.phase == .review && a.cancels == 1 && !k.events.contains("begin"),
          "focus changing during audio setup cannot trigger provider in another field")
}
do {
    let (c, a, k, initial, f) = directFixture(); var p = initial; p.triggerMode = .manual
    try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: false, autoSendDisabled: true)
    c.startCapture(sampleRate: 8000); c.finishCapture(); a.done?(.success(()))
    check(k.events.isEmpty && f.writes == 0 && c.phase == .review, "manual direct mode neither triggers keys nor inserts a second result")
    check(c.completeDirect(providerFinished: true), "manual provider requires explicit completed rearm")
}
do {
    let (c, _, _, p) = fixture()
    rejected("direct destination requires injected focused-input capability") {
        try c.prepare(p, destination: .currentFocus, microphoneConfirmed: true, shortcutConfirmed: true, autoSendDisabled: true)
    }
    try c.prepare(p, microphoneConfirmed: true, shortcutConfirmed: true)
    check(!c.completeDirect(providerFinished: true), "draft destination cannot take direct completion path")
}
print("\(assertions) external dictation assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
