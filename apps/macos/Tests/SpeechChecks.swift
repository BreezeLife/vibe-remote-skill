import AVFoundation
import Foundation

var failures = 0
var assertions = 0
func check(_ condition: Bool, _ label: String) {
    assertions += 1
    if !condition {
        failures += 1
        print("FAIL: \(label)")
    }
}

var state = SpeechSessionState()
let first = state.begin()
check(state.matches(first), "begun session accepts its own callbacks")
let second = state.begin()
check(!state.matches(first), "new session rejects old callbacks")
check(state.matches(second), "new session remains active")
check(!state.complete(first), "stale completion cannot finish current session")
check(state.complete(second), "current completion is delivered once")
check(!state.complete(second), "duplicate completion is ignored")
check(!state.matches(second), "finished session rejects callbacks")

for rate in [8_000, 16_000] {
    let buffer = SpeechService.audioBuffer(samples: [-32_768, -16_384, 0, 16_384, 32_767], sampleRate: rate)
    check(buffer != nil, "\(rate)Hz remote PCM converts to an audio buffer")
    if let buffer {
        check(buffer.format.commonFormat == .pcmFormatFloat32, "buffer uses Float32")
        check(buffer.format.channelCount == 1, "buffer is mono")
        check(buffer.format.sampleRate == Double(rate), "negotiated sample rate is preserved")
        check(buffer.frameLength == 5, "sample count becomes frame length")
        if let data = buffer.floatChannelData?[0] {
            check(data[0] == -1, "Int16 minimum scales to -1")
            check(data[1] == -0.5, "negative PCM preserves polarity")
            check(data[2] == 0, "silence stays zero")
            check(data[3] == 0.5, "positive PCM scales correctly")
            check(abs(data[4] - 0.9999695) < 0.000001, "Int16 maximum does not clip above one")
        } else {
            check(false, "Float32 channel data exists")
        }
    }
}
check(SpeechService.audioBuffer(samples: [], sampleRate: 16_000) == nil, "empty frames are rejected")
check(SpeechService.audioBuffer(samples: [0], sampleRate: 0) == nil, "zero rate is rejected")
check(SpeechService.audioBuffer(samples: [0], sampleRate: -1) == nil, "negative rate is rejected")
let nativeFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
let nativeStream = SpeechPCMStream(outputFormat: nativeFormat)
let nativeFrames = try nativeStream.append(samples: [0, 16_384, -16_384], sampleRate: 16_000)
check(nativeFrames?.frameLength == 3, "native format PCM passes through")
let resampledStream = SpeechPCMStream(outputFormat: nativeFormat)
var resampledFrames = 0
for _ in 0..<3 {
    if let frame = try resampledStream.append(samples: Array(repeating: 0, count: 128), sampleRate: 8_000) {
        resampledFrames += Int(frame.frameLength)
        check(frame.format.isEqual(nativeFormat), "converted frames use Speech native format")
        if let samples = frame.floatChannelData?[0] {
            check((0..<Int(frame.frameLength)).allSatisfy { samples[$0] == 0 }, "resampling silence preserves zero samples")
        }
    }
}
check(resampledFrames == 768, "streamed packet durations scale exactly by 16k/8k")
for frame in try resampledStream.finish() {
    resampledFrames += Int(frame.frameLength)
}
let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false)!
let latencyProbe = AVAudioConverter(from: sourceFormat, to: nativeFormat)!
latencyProbe.primeMethod = .none
// Converter filter context is available only after the first conversion.
let probeInput = SpeechService.audioBuffer(samples: Array(repeating: 0, count: 128), sampleRate: 8_000)!
let probeOutput = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: 512)!
var probeSupplied = false
var probeError: NSError?
_ = latencyProbe.convert(to: probeOutput, error: &probeError) { _, status in
    if probeSupplied { status.pointee = .noDataNow; return nil }
    probeSupplied = true
    status.pointee = .haveData
    return probeInput
}
let maximumTail = Int(ceil(Double(latencyProbe.primeInfo.leadingFrames + latencyProbe.primeInfo.trailingFrames) * 2))
check(resampledFrames >= 768 && resampledFrames <= 768 + maximumTail + 4,
      "end-of-stream drains only the converter's documented filter tail")
var rejectedAfterEnd = false
do {
    _ = try resampledStream.append(samples: [0], sampleRate: 8_000)
} catch {
    rejectedAfterEnd = true
}
check(rejectedAfterEnd, "PCM append is rejected after end of audio")
let audibleStream = SpeechPCMStream(outputFormat: nativeFormat)
let tone = (0..<256).map { Int16(sin(Double($0) * 2 * .pi * 100 / 8_000) * 16_384) }
var energy: Double = 0
var audibleBuffers: [AVAudioPCMBuffer] = []
if let buffer = try audibleStream.append(samples: tone, sampleRate: 8_000) { audibleBuffers.append(buffer) }
audibleBuffers.append(contentsOf: try audibleStream.finish())
for buffer in audibleBuffers {
    if let channel = buffer.floatChannelData?[0] {
        for i in 0..<Int(buffer.frameLength) { energy += Double(channel[i] * channel[i]) }
    }
}
check(energy > 1, "non-silent PCM survives sample rate conversion")
let changedRateStream = SpeechPCMStream(outputFormat: nativeFormat)
_ = try changedRateStream.append(samples: [0, 0], sampleRate: 16_000)
var rejectedRateChange = false
do { _ = try changedRateStream.append(samples: [0, 0], sampleRate: 8_000) }
catch { rejectedRateChange = true }
check(rejectedRateChange, "a stream cannot change sample rates midway")
print("\(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
