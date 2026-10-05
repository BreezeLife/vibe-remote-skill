import CoreAudio
import Foundation

/// Changes the current output device, without synthesizing another remote key.
enum SystemVolume {
    static func adjust(by delta: Float32) throws {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw VolumeError.unavailable }
        var adjusted = false
        for channel in [UInt32(0), 1, 2] {
            address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { continue }
            var value: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { continue }
            value = max(0, min(1, value + delta))
            guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr else { continue }
            adjusted = true
            if channel == 0 { break }
        }
        if !adjusted { throw VolumeError.unavailable }
    }
    enum VolumeError: LocalizedError {
        case unavailable
        var errorDescription: String? { "当前输出设备不支持系统音量调整，请使用设备本身的音量控制。" }
    }
}
