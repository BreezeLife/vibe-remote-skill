import AVFoundation
import Foundation
import Speech

struct SpeechSessionState {
    private(set) var id: UUID?

    mutating func begin() -> UUID {
        let next = UUID()
        id = next
        return next
    }

    func matches(_ candidate: UUID) -> Bool {
        id == candidate
    }

    mutating func complete(_ candidate: UUID) -> Bool {
        guard matches(candidate) else { return false }
        id = nil
        return true
    }
}

/// Receives remote PCM only. Calls and callbacks are confined to the main queue.
final class SpeechService {
    var onText: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onFinished: (() -> Void)?

    private var session = SpeechSessionState()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pcmStream: SpeechPCMStream?
    private var finalizationDeadline: DispatchWorkItem?
    private var finishing = false
    private var lastText = ""

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .notDetermined {
            completion(status == .authorized)
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start(localeIdentifier: String, allowServerRecognition: Bool) throws {
        precondition(Thread.isMainThread)
        guard session.id == nil else { throw SpeechServiceError.sessionActive }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechServiceError.authorizationRequired
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw SpeechServiceError.unsupportedLocale
        }
        guard allowServerRecognition || recognizer.supportsOnDeviceRecognition else {
            throw SpeechServiceError.localRecognitionUnavailable
        }
        guard recognizer.isAvailable else { throw SpeechServiceError.recognizerUnavailable }

        recognizer.queue = .main
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = !allowServerRecognition

        let id = session.begin()
        self.recognizer = recognizer
        self.request = request
        pcmStream = SpeechPCMStream(outputFormat: request.nativeAudioFormat)
        finishing = false
        lastText = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.session.matches(id) else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty { self.lastText = text }
                    self.onText?(self.lastText, result.isFinal)
                    if result.isFinal {
                        self.complete(id)
                        return
                    }
                }
                if let error {
                    self.complete(id, error: error.localizedDescription)
                }
            }
        }
    }

    func append(samples: [Int16], sampleRate: Int) {
        precondition(Thread.isMainThread)
        guard !samples.isEmpty, !finishing, let id = session.id,
              let request, let pcmStream else { return }
        do {
            if let buffer = try pcmStream.append(samples: samples, sampleRate: sampleRate) {
                request.append(buffer)
            }
        } catch {
            complete(id, error: error.localizedDescription)
        }
    }

    func finish() {
        precondition(Thread.isMainThread)
        guard !finishing, let id = session.id, let request else { return }
        finishing = true
        do {
            if let pcmStream {
                for buffer in try pcmStream.finish() {
                    request.append(buffer)
                }
            }
        } catch {
            complete(id, error: error.localizedDescription)
            return
        }
        request.endAudio()
        let deadline = DispatchWorkItem { [weak self] in
            self?.complete(id, error: "语音识别等待最终结果超时，已保留收到的草稿。")
        }
        finalizationDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: deadline)
    }

    /// Cancels silently; late recognition results cannot modify a new draft.
    func cancel() {
        precondition(Thread.isMainThread)
        guard let id = session.id, session.complete(id) else { return }
        releaseRecognition()
        lastText = ""
    }

    private func complete(_ id: UUID, error: String? = nil) {
        guard session.complete(id) else { return }
        releaseRecognition()
        // Keep partial text on both errors and timeouts. Only a new start or
        // explicit cancellation resets it; these paths never emit an empty draft.
        if let error { onError?(error) }
        onFinished?()
    }

    private func releaseRecognition() {
        finalizationDeadline?.cancel()
        finalizationDeadline = nil
        let previousTask = task
        task = nil
        request = nil
        recognizer = nil
        pcmStream = nil
        finishing = false
        previousTask?.cancel()
    }

    static func audioBuffer(samples: [Int16], sampleRate: Int) -> AVAudioPCMBuffer? {
        guard (sampleRate == 8_000 || sampleRate == 16_000), !samples.isEmpty,
              samples.count <= Int(AVAudioFrameCount.max),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(sampleRate), channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = Float(sample) / 32_768
        }
        return buffer
    }

    deinit {
        finalizationDeadline?.cancel()
        task?.cancel()
    }
}

/// Maintains one converter across packets so resampling keeps its stream state.
final class SpeechPCMStream {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputSampleRate: Int?
    private var ended = false

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func append(samples: [Int16], sampleRate: Int) throws -> AVAudioPCMBuffer? {
        guard !ended else { throw SpeechServiceError.audioEnded }
        guard let input = SpeechService.audioBuffer(samples: samples, sampleRate: sampleRate) else {
            throw SpeechServiceError.invalidAudio
        }
        if let inputSampleRate, inputSampleRate != sampleRate {
            throw SpeechServiceError.sampleRateChanged
        }
        inputSampleRate = sampleRate
        if input.format.isEqual(outputFormat) { return input }
        if converter == nil {
            guard let created = AVAudioConverter(from: input.format, to: outputFormat) else {
                throw SpeechServiceError.conversionFailed
            }
            created.primeMethod = .none
            converter = created
        }
        guard let converter else { throw SpeechServiceError.conversionFailed }
        let capacity = ceil(Double(input.frameLength) * outputFormat.sampleRate / Double(sampleRate)) + 32
        guard capacity > 0, capacity <= Double(AVAudioFrameCount.max),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                           frameCapacity: AVAudioFrameCount(capacity)) else {
            throw SpeechServiceError.conversionFailed
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { throw SpeechServiceError.conversionFailed }
        return output.frameLength > 0 ? output : nil
    }

    func finish() throws -> [AVAudioPCMBuffer] {
        guard !ended else { return [] }
        ended = true
        guard let converter else { return [] }
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<8 {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1_024) else {
                throw SpeechServiceError.conversionFailed
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error, error == nil else { throw SpeechServiceError.conversionFailed }
            if output.frameLength > 0 { buffers.append(output) }
            if status == .endOfStream || (status == .inputRanDry && output.frameLength == 0) {
                return buffers
            }
        }
        throw SpeechServiceError.conversionFailed
    }
}

enum SpeechServiceError: LocalizedError {
    case sessionActive, authorizationRequired, unsupportedLocale
    case localRecognitionUnavailable, recognizerUnavailable
    case invalidAudio, sampleRateChanged, conversionFailed, audioEnded

    var errorDescription: String? {
        switch self {
        case .sessionActive: return "请先结束当前语音识别。"
        case .authorizationRequired: return "请先允许 VibeRemote 使用语音识别。"
        case .unsupportedLocale: return "Apple Speech 不支持所选语言。"
        case .localRecognitionUnavailable:
            return "所选语言的本机识别不可用。请检查 macOS 听写语言，或明确选择允许 Apple 网络识别。"
        case .recognizerUnavailable: return "Apple 语音识别当前不可用，请稍后重试。"
        case .invalidAudio: return "遥控器音频格式无效，需要 8 kHz 或 16 kHz 单声道 PCM。"
        case .sampleRateChanged: return "遥控器采样率在录音中改变，已保留收到的草稿。"
        case .conversionFailed: return "遥控器音频转换失败，已保留收到的草稿。"
        case .audioEnded: return "音频输入已经结束。"
        }
    }
}
