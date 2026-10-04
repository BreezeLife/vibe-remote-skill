import AppKit
import Combine
import VibeRemoteCore

/// All services deliver callbacks on the main queue. No transcript persistence.
final class RemoteModel: ObservableObject {
    @Published private(set) var connectionStatus = "尚未连接遥控器"
    @Published private(set) var ready = false
    @Published private(set) var recognitionEnabled = false
    @Published private(set) var requestingAuthorization = false
    @Published private(set) var draft = DraftSession()
    @Published private(set) var level: Double = -60
    @Published private(set) var sampleCount = 0
    @Published private(set) var sampleRate = 0
    @Published private(set) var message = "连接遥控器并启用语音识别，然后按住遥控器的语音键。"
    @Published var localeIdentifier = "zh-CN"
    @Published var allowServerRecognition = false

    private let bluetooth = BluetoothService()
    private let speech = SpeechService()
    private var speechFailed = false

    init() {
        bluetooth.onStatus = { [weak self] status in self?.connectionStatus = status }
        bluetooth.onReady = { [weak self] ready in self?.ready = ready }
        bluetooth.onLevel = { [weak self] level in self?.level = level }
        bluetooth.onStream = { [weak self] active, rate in self?.streamChanged(active, rate: rate) }
        bluetooth.onSamples = { [weak self] samples, rate in
            guard let self, self.draft.phase == .capturing else { return }
            self.sampleCount += samples.count
            self.speech.append(samples: samples, sampleRate: rate)
        }
        speech.onText = { [weak self] text, _ in
            guard let self, let id = self.draft.sessionID else { return }
            self.draft.receive(text, session: id)
        }
        speech.onError = { [weak self] message in
            guard let self else { return }
            self.speechFailed = true
            self.message = message
        }
        speech.onFinished = { [weak self] in
            guard let self, let id = self.draft.sessionID else { return }
            let wasCapturing = self.draft.phase == .capturing
            self.draft.complete(session: id)
            if wasCapturing { self.bluetooth.stopCapture() }
            if !self.speechFailed {
                self.message = self.draft.canCopy
                    ? "草稿已保留。检查文字后可复制到目标输入框。"
                    : "没有识别到文字。请检查音量指示后重试。"
            }
        }
    }

    var captureLabel: String {
        switch draft.phase {
        case .idle: return "等待说话"
        case .capturing: return "正在收音"
        case .finishing: return "正在整理草稿"
        }
    }

    func connect() { bluetooth.start() }

    func enableRecognition() {
        guard !requestingAuthorization, !draft.isBusy else { return }
        requestingAuthorization = true
        speech.requestAuthorization { [weak self] allowed in
            guard let self else { return }
            self.requestingAuthorization = false
            self.recognitionEnabled = allowed
            self.message = allowed
                ? "语音识别已启用。连接就绪后，按住遥控器语音键说话。"
                : "请在系统设置 → 隐私与安全性 → 语音识别中允许 Vibe Remote，然后重试。"
        }
    }

    func stopCapture() { bluetooth.stopCapture() }

    func cancelUtterance() {
        draft.cancel()
        speech.cancel()
        bluetooth.stopCapture()
        message = "已取消这段听写，之前的草稿已保留。"
    }

    func disconnect() {
        bluetooth.disconnect()
        // Defensive cleanup also covers disconnect before a transport callback.
        if draft.phase == .capturing { finishUtterance() }
    }

    func replaceDraft(_ text: String) { draft.replaceText(text) }

    func copyDraft() {
        guard draft.canCopy else { return }
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
            level = -60
            if draft.phase == .capturing { finishUtterance() }
            return
        }
        guard recognitionEnabled else {
            message = "请先点击「启用语音识别」，完成系统授权后再说话。"
            bluetooth.stopCapture()
            return
        }
        guard !draft.isBusy else {
            bluetooth.stopCapture()
            return
        }
        do {
            try speech.start(localeIdentifier: localeIdentifier,
                             allowServerRecognition: allowServerRecognition)
            draft.begin()
            speechFailed = false
            sampleCount = 0
            sampleRate = rate
            message = "正在从遥控器收音。松开语音键会结束这段听写。"
        } catch {
            message = error.localizedDescription
            bluetooth.stopCapture()
        }
    }

    private func finishUtterance() {
        draft.finishCapture()
        if !speechFailed { message = "收音已结束，正在等待最终识别结果…" }
        speech.finish()
    }
}
