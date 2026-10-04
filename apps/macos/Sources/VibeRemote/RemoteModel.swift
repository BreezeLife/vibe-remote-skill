import AppKit
import Combine
import VibeRemoteCore

/// All services deliver callbacks on the main queue. No transcript persistence.
final class RemoteModel: ObservableObject {
    @Published private(set) var connectionStatus = "尚未连接遥控器"
    @Published private(set) var ready = false
    @Published private(set) var recognitionEnabled = false
    @Published private(set) var requestingAuthorization = false
    @Published private(set) var isReceivingAudio = false
    @Published private(set) var recognitionIssue: String?
    @Published private(set) var draft = DraftSession()
    @Published private(set) var level: Double = -60
    @Published private(set) var sampleCount = 0
    @Published private(set) var sampleRate = 0
    @Published private(set) var message = "连接遥控器并启用语音识别，然后按住遥控器的语音键。"
    @Published var localeIdentifier = "zh-CN"
    @Published var allowServerRecognition = false

    private let bluetooth: BluetoothServicing
    private let speech: SpeechServicing
    private var speechFailed = false
    private var completedDuringHold = false

    init(bluetooth: BluetoothServicing = BluetoothService(),
         speech: SpeechServicing = SpeechService()) {
        self.bluetooth = bluetooth
        self.speech = speech
        recognitionEnabled = speech.isAuthorized
        bluetooth.onStatus = { [weak self] status in self?.connectionStatus = status }
        bluetooth.onReady = { [weak self] ready in self?.ready = ready }
        bluetooth.onLevel = { [weak self] level in self?.level = level }
        bluetooth.onStream = { [weak self] active, rate in self?.streamChanged(active, rate: rate) }
        bluetooth.onSamples = { [weak self] samples, rate in
            guard let self, self.isReceivingAudio else { return }
            self.sampleCount += samples.count
            if self.draft.phase == .capturing {
                self.speech.append(samples: samples, sampleRate: rate)
            }
        }
        speech.onText = { [weak self] text, _ in
            guard let self, !self.completedDuringHold, let id = self.draft.sessionID else { return }
            self.draft.receive(text, session: id)
        }
        speech.onError = { [weak self] message in
            guard let self, !self.completedDuringHold, self.draft.sessionID != nil else { return }
            self.speechFailed = true
            self.recognitionIssue = message
            self.message = message
        }
        speech.onFinished = { [weak self] in
            guard let self, !self.completedDuringHold, let id = self.draft.sessionID else { return }
            if self.isReceivingAudio, self.draft.phase == .capturing {
                // Keep this hold's rollback point until release or explicit cancel.
                // Finishing also prevents any remaining PCM reaching Speech.
                self.completedDuringHold = true
                self.draft.finishCapture()
            } else {
                self.draft.complete(session: id)
            }
            if !self.speechFailed, self.recognitionIssue == nil {
                self.message = self.isReceivingAudio
                    ? "本段识别已结束。请松开语音键，再按住开始下一段。"
                    : self.completedMessage
            }
        }
    }

    var isBusy: Bool { isReceivingAudio || draft.isBusy }
    var canCopy: Bool { !isReceivingAudio && draft.canCopy }

    var captureLabel: String {
        if isReceivingAudio && draft.phase != .capturing { return "收音中 · 未转写" }
        switch draft.phase {
        case .idle: return "等待说话"
        case .capturing: return "收音并转写"
        case .finishing: return "正在整理草稿"
        }
    }

    func connect() { bluetooth.start() }

    func enableRecognition() {
        guard !requestingAuthorization, !isBusy else { return }
        requestingAuthorization = true
        speech.requestAuthorization { [weak self] allowed in
            guard let self else { return }
            self.requestingAuthorization = false
            self.recognitionEnabled = allowed
            if allowed {
                self.message = self.isReceivingAudio
                    ? "语音识别已授权。请先松开语音键，再按住开始听写。"
                    : "语音识别已授权。连接就绪后，按住遥控器语音键说话。"
                // Authorization arriving during a hold must not start a partial utterance.
                self.recognitionIssue = self.isReceivingAudio ? self.message : nil
            } else {
                self.message = "请在系统设置 → 隐私与安全性 → 语音识别中允许 Vibe Remote，然后重试。"
                self.recognitionIssue = self.message
            }
        }
    }

    func stopCapture() { bluetooth.stopCapture() }

    func cancelUtterance() {
        draft.cancel()
        completedDuringHold = false
        speech.cancel()
        bluetooth.stopCapture()
        message = "已取消这段听写，之前的草稿已保留。"
    }

    func disconnect() {
        bluetooth.disconnect()
        // Defensive cleanup also covers disconnect before a transport callback.
        streamChanged(false, rate: sampleRate)
    }

    func replaceDraft(_ text: String) {
        guard !isReceivingAudio else { return }
        draft.replaceText(text)
    }

    func copyDraft() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft.text, forType: .string)
        message = "已复制。切换到目标输入框粘贴，检查后自行发送。"
    }

    func shutdown() {
        speech.cancel()
        bluetooth.disconnect()
    }

    private func streamChanged(_ active: Bool, rate: Int) {
        if !active {
            let wasReceivingAudio = isReceivingAudio
            isReceivingAudio = false
            level = -60
            if completedDuringHold {
                completedDuringHold = false
                if let id = draft.sessionID { draft.complete(session: id) }
            }
            if draft.phase == .capturing {
                finishUtterance()
            } else if wasReceivingAudio, !draft.isBusy, recognitionIssue == nil {
                message = completedMessage
            }
            return
        }
        // One physical hold owns one recognition attempt. Continue measuring audio
        // after a recognition failure, without closing or restarting the BLE stream.
        guard !isReceivingAudio else { return }
        isReceivingAudio = true
        sampleCount = 0
        sampleRate = rate
        recognitionEnabled = speech.isAuthorized
        guard recognitionEnabled else {
            message = "尚未获得语音识别授权。请松开语音键，点击「启用语音识别」后再试。"
            recognitionIssue = message
            return
        }
        guard !draft.isBusy else {
            message = "本次按住未转写：开始时上一段还在整理。请松开语音键，等待完成后重试。"
            recognitionIssue = message
            return
        }
        do {
            try speech.start(localeIdentifier: localeIdentifier,
                             allowServerRecognition: allowServerRecognition)
            draft.begin()
            speechFailed = false
            recognitionIssue = nil
            message = "正在从遥控器收音。松开语音键会结束这段听写。"
        } catch {
            message = error.localizedDescription
            recognitionIssue = message
        }
    }

    private var completedMessage: String {
        draft.canCopy
            ? "草稿已保留。检查文字后可复制到目标输入框。"
            : "没有识别到文字。请检查音量指示后重试。"
    }

    private func finishUtterance() {
        draft.finishCapture()
        if !speechFailed { message = "收音已结束，正在等待最终识别结果…" }
        speech.finish()
    }
}
