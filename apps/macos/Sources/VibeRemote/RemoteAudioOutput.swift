import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct RemoteAudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let driverBundleID: String
}

protocol RemoteAudioOutputting: AnyObject {
    var onError: ((Error) -> Void)? { get set }
    func availableDevices() -> [RemoteAudioDevice]
    func start(deviceUID: String, sampleRate: Int) throws
    func append(samples: [Int16], sampleRate: Int) throws
    func finish(completion: @escaping (Result<Void, Error>) -> Void)
    func cancel()
}

extension RemoteAudioOutputting {
    var onError: ((Error) -> Void)? { get { nil } set {} }
}

struct RemoteAudioDeviceSnapshot: Equatable {
    var objectID: AudioDeviceID
    var uid: String
    var name: String
    var driverBundleID: String
    var inputChannels: Int
    var outputChannels: Int
    var sampleRate: Double
    var alive: Bool

    // Explicit installed loopback identities. Display names and transport alone cannot
    // distinguish a virtual microphone from physical speakers. No driver is bundled.
    var isSupported: Bool {
        ["com.hd838a.MiRemoteV2ch", "audio.existential.BlackHole2ch"].contains(driverBundleID)
            && objectID != kAudioObjectUnknown && !uid.isEmpty && alive
            && inputChannels == 2 && outputChannels == 2
            && sampleRate.isFinite && (8_000...192_000).contains(sampleRate)
    }

    var device: RemoteAudioDevice { .init(id: uid, name: name, driverBundleID: driverBundleID) }

    static func resolve(uid: String, in devices: [Self]) throws -> Self {
        let matches = devices.filter { $0.uid == uid }
        guard !uid.isEmpty, matches.count == 1, let result = matches.first,
              result.isSupported else { throw RemoteAudioOutputError.deviceUnavailable }
        return result
    }

    func matchesRoute(_ other: Self) -> Bool {
        isSupported && other.isSupported && objectID == other.objectID && uid == other.uid
            && driverBundleID == other.driverBundleID && inputChannels == other.inputChannels
            && outputChannels == other.outputChannels && sampleRate == other.sampleRate
    }
}

/// A fixed-capacity mono FIFO. The real-time render callback never allocates or waits
/// for the producer: lock contention renders silence and retains the pending frames.
final class RemoteAudioRing {
    private let lock = NSLock()
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var readOffset = 0
    private var count = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    var pendingFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        lock.lock(); defer { lock.unlock() }
        guard samples.count <= capacity - count else { throw RemoteAudioOutputError.queueFull }
        for index in 0..<samples.count { storage[(readOffset + count + index) % capacity] = samples[index] }
        count += samples.count
    }

    func render(frames: Int, into data: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        // Clear every supplied byte before validating the output layout.
        for buffer in buffers {
            if let pointer = buffer.mData { memset(pointer, 0, Int(buffer.mDataByteSize)) }
        }
        guard frames > 0, buffers.count == 2,
              buffers.allSatisfy({ $0.mNumberChannels == 1 && $0.mData != nil
                  && Int($0.mDataByteSize) >= frames * MemoryLayout<Float>.size }),
              lock.try() else { return }
        defer { lock.unlock() }
        let amount = min(count, frames)
        for buffer in buffers {
            let target = buffer.mData!.assumingMemoryBound(to: Float.self)
            for index in 0..<amount { target[index] = storage[(readOffset + index) % capacity] }
        }
        readOffset = (readOffset + amount) % capacity
        count -= amount
    }

    deinit { storage.deinitialize(count: capacity); storage.deallocate() }
}

/// Sends only remote PCM to one explicitly selected, installed loopback. AUHAL uses
/// a pinned device; no default-output unit, input capture or global device mutation.
final class RemoteAudioOutput: RemoteAudioOutputting {
    var onError: ((Error) -> Void)?
    private let inventory: () -> [RemoteAudioDeviceSnapshot]
    private var unit: AudioUnit?
    private var selected: RemoteAudioDeviceSnapshot?
    private var ring: RemoteAudioRing?
    private var converter: SpeechPCMStream?
    private var sourceRate = 0
    private var deferredError: Error?
    private var generation = UUID()
    private var poll: DispatchWorkItem?
    private var finishing = false
    private var drainStarted: TimeInterval?
    private var emptiedAt: TimeInterval?
    private var completion: ((Result<Void, Error>) -> Void)?

    init(inventory: @escaping () -> [RemoteAudioDeviceSnapshot] = RemoteAudioInventory.read) {
        self.inventory = inventory
    }

    func availableDevices() -> [RemoteAudioDevice] {
        inventory().filter(\.isSupported).map(\.device).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(deviceUID: String, sampleRate: Int) throws {
        precondition(Thread.isMainThread)
        guard unit == nil, !finishing else { throw RemoteAudioOutputError.alreadyRunning }
        guard sampleRate == 8_000 || sampleRate == 16_000 else { throw RemoteAudioOutputError.invalidPCM }
        let device = try RemoteAudioDeviceSnapshot.resolve(uid: deviceUID, in: inventory())
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: device.sampleRate, channels: 1, interleaved: false) else {
            throw RemoteAudioOutputError.invalidPCM
        }
        cancel()
        do {
            var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0, componentFlagsMask: 0)
            guard let component = AudioComponentFindNext(nil, &description) else { throw RemoteAudioOutputError.audioUnit }
            var created: AudioUnit?
            try checked(AudioComponentInstanceNew(component, &created))
            guard let created else { throw RemoteAudioOutputError.audioUnit }
            unit = created
            var enabled: UInt32 = 1
            try checked(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output, 0, &enabled, 4))
            enabled = 0
            try checked(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input, 1, &enabled, 4))
            var deviceID = device.objectID
            try checked(AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)))
            var stream = AudioStreamBasicDescription(mSampleRate: device.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            try checked(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input, 0, &stream, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            let fifo = RemoteAudioRing(capacity: Int(device.sampleRate * 2))
            ring = fifo
            var callback = AURenderCallbackStruct(inputProc: { context, _, _, _, frames, data in
                guard let data else { return noErr }
                Unmanaged<RemoteAudioRing>.fromOpaque(context).takeUnretainedValue()
                    .render(frames: Int(frames), into: data)
                return noErr
            }, inputProcRefCon: Unmanaged.passUnretained(fifo).toOpaque())
            try checked(AudioUnitSetProperty(created, kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            selected = device
            sourceRate = sampleRate
            converter = SpeechPCMStream(outputFormat: format)
            try checked(AudioUnitInitialize(created))
            try validateRoute()
            try checked(AudioOutputUnitStart(created))
            try validateRoute()
            schedulePoll()
        } catch {
            cancel()
            throw error
        }
    }

    func append(samples: [Int16], sampleRate: Int) throws {
        precondition(Thread.isMainThread)
        do {
            if let deferredError { throw deferredError }
            guard !finishing, let converter else { throw RemoteAudioOutputError.notRunning }
            guard sampleRate == sourceRate, samples.count <= sourceRate * 2 else { throw RemoteAudioOutputError.invalidPCM }
            try validateRoute()
            guard !samples.isEmpty else { return }
            if let buffer = try converter.append(samples: samples, sampleRate: sampleRate) { try enqueue(buffer) }
        } catch {
            fail(error)
            throw error
        }
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !finishing else {
            deliverAsync(.failure(RemoteAudioOutputError.alreadyRunning), to: completion)
            return
        }
        do {
            if let deferredError { throw deferredError }
            guard let converter else { throw RemoteAudioOutputError.notRunning }
            try validateRoute()
            for buffer in try converter.finish() { try enqueue(buffer) }
            self.completion = completion
            finishing = true
            drainStarted = ProcessInfo.processInfo.systemUptime
            emptiedAt = nil
            schedulePoll()
        } catch {
            fail(error, notify: false)
            deliverAsync(.failure(error), to: completion)
        }
    }

    private func deliverAsync(_ result: Result<Void, Error>, to callback: @escaping (Result<Void, Error>) -> Void) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard self?.generation == token else { return }
            callback(result)
        }
    }

    /// Silent cancellation invalidates pending completion. No audio or transcript persists.
    func cancel() {
        precondition(Thread.isMainThread)
        generation = UUID()
        poll?.cancel(); poll = nil
        completion = nil
        deferredError = nil
        releaseAudio()
    }

    private func checked(_ status: OSStatus) throws {
        guard status == noErr else { throw RemoteAudioOutputError.audioUnit }
    }

    private func validateRoute() throws {
        guard let unit, let selected else { throw RemoteAudioOutputError.notRunning }
        let actual = try RemoteAudioDeviceSnapshot.resolve(uid: selected.uid, in: inventory())
        guard selected.matchesRoute(actual) else { throw RemoteAudioOutputError.deviceChanged }
        var activeID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try checked(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &activeID, &size))
        guard activeID == selected.objectID else { throw RemoteAudioOutputError.deviceChanged }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer) throws {
        guard let ring, let samples = buffer.floatChannelData?[0] else { throw RemoteAudioOutputError.invalidPCM }
        try ring.append(.init(start: samples, count: Int(buffer.frameLength)))
    }

    private func schedulePoll() {
        poll?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.unit != nil else { return }
            do {
                try self.validateRoute()
                if self.finishing, let started = self.drainStarted {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - started > 3 { throw RemoteAudioOutputError.drainTimeout }
                    if self.ring?.pendingFrames == 0 {
                        if self.emptiedAt == nil { self.emptiedAt = now }
                        // AUHAL has consumed the frames. Keep the pinned device alive briefly
                        // for its loopback input before the caller ends provider dictation.
                        if now - self.emptiedAt! >= 0.15 {
                            let callback = self.completion
                            self.cancel()
                            callback?(.success(()))
                            return
                        }
                    }
                }
                self.schedulePoll()
            } catch { self.fail(error) }
        }
        poll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func fail(_ error: Error, notify: Bool = true) {
        let callback = completion
        let faultHandler = callback == nil && notify ? onError : nil
        cancel()
        deferredError = error
        callback?(.failure(error))
        // API calls and the generation-checked device monitor run on main. A
        // finalizing session uses its completion instead, avoiding duplicate events.
        faultHandler?(error)
    }

    private func releaseAudio() {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        ring = nil
        converter = nil
        selected = nil
        sourceRate = 0
        finishing = false
        drainStarted = nil
        emptiedAt = nil
    }

    deinit { poll?.cancel(); releaseAudio() }
}

private enum RemoteAudioInventory {
    static func read() -> [RemoteAudioDeviceSnapshot] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices = objectIDs(system, kAudioHardwarePropertyDevices)
        // On modern macOS a device's object owner can be the system object, not
        // its driver. Resolve identity through each plug-in's declared device list.
        var drivers: [AudioDeviceID: Set<String>] = [:]
        for plugin in objectIDs(system, kAudioHardwarePropertyPlugInList) {
            guard let bundle = string(plugin, kAudioPlugInPropertyBundleID) else { continue }
            for device in objectIDs(plugin, kAudioPlugInPropertyDeviceList) {
                drivers[device, default: []].insert(bundle)
            }
        }
        return devices.compactMap { id in
            guard let candidates = drivers[id], candidates.count == 1, let driver = candidates.first,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName),
                  let rate: Double = scalar(id, kAudioDevicePropertyNominalSampleRate),
                  let alive: UInt32 = scalar(id, kAudioDevicePropertyDeviceIsAlive) else { return nil }
            return .init(objectID: id, uid: uid, name: name, driverBundleID: driver,
                inputChannels: channels(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channels(id, scope: kAudioDevicePropertyScopeOutput), sampleRate: rate, alive: alive == 1)
        }
    }

    private static func objectIDs(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let stride = MemoryLayout<AudioObjectID>.size
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0, size <= 256 * stride, Int(size) % stride == 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &objects) == noErr,
              Int(size) % stride == 0, Int(size) / stride <= objects.count else { return [] }
        return Array(objects.prefix(Int(size) / stride))
    }

    private static func scalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr,
              size == MemoryLayout<T>.size else { return nil }
        return memory.load(as: T.self)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let result = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        result.initialize(to: nil)
        defer { result.deinitialize(count: 1); result.deallocate() }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, result) == noErr else { return nil }
        // CoreAudio's name, UID and plug-in bundle properties return retained CFStrings.
        return result.pointee?.takeRetainedValue() as String?
    }

    private static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65_536 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        let maximumBuffers = (Int(size) - MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!) / MemoryLayout<AudioBuffer>.size
        guard Int(list.pointee.mNumberBuffers) <= maximumBuffers else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

enum RemoteAudioOutputError: LocalizedError {
    case deviceUnavailable, deviceChanged, invalidPCM, queueFull, audioUnit
    case notRunning, alreadyRunning, drainTimeout
    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "未找到已选择的双向虚拟音频设备，请刷新并重新选择。"
        case .deviceChanged: return "虚拟音频设备或格式已改变，已停止转发；请重新准备听写。"
        case .invalidPCM: return "遥控器音频格式无效或发生变化，已停止转发。"
        case .queueFull: return "虚拟音频输出跟不上遥控器音频，已停止转发；请重新测试。"
        case .audioUnit: return "无法打开指定的虚拟音频输出；没有切换到扬声器或 Mac 麦克风。"
        case .notRunning: return "尚未准备虚拟音频输出。"
        case .alreadyRunning: return "请先结束当前虚拟音频转发。"
        case .drainTimeout: return "虚拟音频排空超时，已停止输出；请检查输入法状态。"
        }
    }
}
