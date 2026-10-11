import Foundation
import VibeRemoteCore

final class FakeAudio: RemoteAudioOutputting {
    var onError: ((Error) -> Void)?
    var starts = 0, appends = 0, cancels = 0
    var done: ((Result<Void, Error>) -> Void)?
    var failStart = false
    func availableDevices() -> [RemoteAudioDevice] { [.init(id: "fixture", name: "Fixture", driverBundleID: "fixture")] }
    func start(deviceUID: String, sampleRate: Int) throws { starts += 1; if failStart { throw NSError(domain: "fixture", code: 1) } }
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
print("\(assertions) external dictation assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
