import AVFoundation
import CoreAudio
import Foundation

var failures = 0
var assertions = 0
func check(_ condition: Bool, _ label: String) {
    assertions += 1
    if !condition { failures += 1; print("FAIL: \(label)") }
}
func rejects(_ label: String, _ work: () throws -> Void) {
    do { try work(); check(false, label) } catch { check(true, label) }
}

let valid = RemoteAudioDeviceSnapshot(objectID: 11, uid: "fixture-loop", name: "Loop",
    driverBundleID: "com.hd838a.MiRemoteV2ch", inputChannels: 2, outputChannels: 2,
    sampleRate: 48_000, alive: true)
check(valid.isSupported, "installed supported duplex driver is eligible")
var other = valid
other.driverBundleID = "com.apple.audio.CoreAudio"
check(!other.isSupported, "physical/default devices are never eligible")
other.name = "MiRemoteV 2ch"
check(!other.isSupported, "a matching display name cannot authorize another driver")
other = valid; other.driverBundleID = "audio.existential.BlackHole2ch"
check(other.isSupported, "official BlackHole 2ch identity is eligible")
other.driverBundleID = "audio.existential.BlackHole2ch.fake"
check(!other.isSupported, "bundle prefix matching is forbidden")
other = valid; other.inputChannels = 0
check(!other.isSupported, "output-only device is ineligible")
other = valid; other.outputChannels = 0
check(!other.isSupported, "input-only device is ineligible")
other = valid; other.alive = false
check(!other.isSupported, "offline device is ineligible")
other = valid; other.sampleRate = 0
check(!other.isSupported, "zero sample rate is ineligible")
other = valid; other.sampleRate = .nan
check(!other.isSupported, "non-finite sample rate is ineligible")
other = valid; other.uid = ""
check(!other.isSupported, "empty UID is ineligible")
check(try RemoteAudioDeviceSnapshot.resolve(uid: valid.uid, in: [valid]) == valid,
      "explicit selected UID resolves")
rejects("missing selected UID never falls back") {
    _ = try RemoteAudioDeviceSnapshot.resolve(uid: "missing", in: [valid])
}
rejects("ambiguous device UID fails closed") {
    _ = try RemoteAudioDeviceSnapshot.resolve(uid: valid.uid, in: [valid, valid])
}
rejects("same UID on changed driver fails closed") {
    var changed = valid; changed.driverBundleID = "com.apple.audio.CoreAudio"
    _ = try RemoteAudioDeviceSnapshot.resolve(uid: valid.uid, in: [changed])
}
check(valid.matchesRoute(valid), "unchanged live route is accepted")
other = valid; other.objectID = 12
check(!valid.matchesRoute(other), "recreated device object invalidates the route")
other = valid; other.sampleRate = 44_100
check(!valid.matchesRoute(other), "native sample-rate change invalidates the route")
other = valid; other.alive = false
check(!valid.matchesRoute(other), "device loss invalidates the route")
other = valid; other.name = "Renamed loopback"
check(valid.matchesRoute(other), "display name does not redefine route identity")

let ring = RemoteAudioRing(capacity: 8)
func put(_ samples: [Float]) throws {
    try samples.withUnsafeBufferPointer { try ring.append($0) }
}
func take(_ frames: Int) -> [[Float]] {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                              channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for channel in 0..<2 { for i in 0..<frames { buffer.floatChannelData![channel][i] = 99 } }
    ring.render(frames: frames, into: buffer.mutableAudioBufferList)
    return (0..<2).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: frames)) }
}
try put([1, 2, 3, 4, 5])
check(ring.pendingFrames == 5, "ring retains a bounded FIFO")
let first = take(3)
check(first[0] == [1, 2, 3] && first[1] == first[0], "mono frames duplicate to both output channels")
check(ring.pendingFrames == 2, "render removes only consumed frames")
try put([6, 7, 8, 9, 10, 11])
rejects("full queue rejects rather than losing earlier audio") { try put([12]) }
check(ring.pendingFrames == 8, "failed append leaves prior queued frames intact")
let wrapped = take(8)
check(wrapped[0] == [4, 5, 6, 7, 8, 9, 10, 11], "wrapped queue preserves order")
check(wrapped[1] == wrapped[0], "wrapped stereo channels agree")
check(take(3) == [[0, 0, 0], [0, 0, 0]], "empty queue emits silence, not uninitialized memory")
try put([0.5, -0.5])
check(take(4)[0] == [0.5, -0.5, 0, 0], "short queue pads only its missing tail")
rejects("packet larger than capacity is rejected atomically") { try put(Array(repeating: 1, count: 9)) }
check(ring.pendingFrames == 0, "oversized packet cannot partially enter queue")

for rate in [8_000, 16_000] {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                              channels: 1, interleaved: false)!
    let converter = SpeechPCMStream(outputFormat: format)
    let frequencyStep = 2.0 * Double.pi * 200.0 / Double(rate)
    let input: [Int16] = (0..<(rate / 10)).map { Int16(sin(Double($0) * frequencyStep) * 16_384.0) }
    var buffers = [AVAudioPCMBuffer]()
    if let buffer = try converter.append(samples: input, sampleRate: rate) { buffers.append(buffer) }
    buffers += try converter.finish()
    let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
    let energy = buffers.reduce(0.0) { sum, buffer in
        sum + (0..<Int(buffer.frameLength)).reduce(0.0) { $0 + Double(buffer.floatChannelData![0][$1] * buffer.floatChannelData![0][$1]) }
    }
    check(frames >= 4_800 && frames < 6_000, "\(rate) Hz remote audio becomes bounded 48 kHz frames")
    check(energy > 100, "\(rate) Hz non-silent audio survives conversion")
}

// Inject an empty inventory: no AudioUnit is created, no microphone/output accessed.
let unavailable = RemoteAudioOutput(inventory: { [] })
var faults = 0
unavailable.onError = { _ in faults += 1; check(Thread.isMainThread, "audio faults arrive on main thread") }
check(unavailable.availableDevices().isEmpty, "empty inventory remains empty")
rejects("starting an absent device fails before hardware access") {
    try unavailable.start(deviceUID: "absent", sampleRate: 16_000)
}
rejects("unsupported source rate fails before hardware access") {
    try unavailable.start(deviceUID: "absent", sampleRate: 48_000)
}
rejects("append without an active route is blocked") {
    try unavailable.append(samples: [1], sampleRate: 16_000)
}
check(faults == 1, "append fault immediately informs owner")
var finishResult: Result<Void, Error>?
unavailable.finish { finishResult = $0; check(Thread.isMainThread, "finish callback uses main thread") }
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
if case .failure = finishResult { check(true, "finish without a route fails") }
else { check(false, "finish without a route fails") }
check(faults == 1, "finish error uses only completion, not a duplicate fault event")
unavailable.cancel()
unavailable.cancel()
check(true, "idle cancellation is idempotent")
var staleFinishDelivered = false
unavailable.finish { _ in staleFinishDelivered = true }
unavailable.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(!staleFinishDelivered, "cancellation invalidates queued immediate-error completion")
print("\(assertions) audio output assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
