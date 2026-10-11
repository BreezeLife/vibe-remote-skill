import AppKit
import Combine
import VibeRemoteCore

/// All services deliver callbacks on the main queue. No transcript persistence.
final class RemoteModel: ObservableObject {
    @Published private(set) var discovery: RemoteDiscoveryState
    @Published private(set) var connectionStatus = "尚未连接遥控器"
    @Published private(set) var ready = false
    @Published private(set) var recognitionEnabled = false
    @Published private(set) var requestingAuthorization = false
    @Published private(set) var isReceivingAudio = false
    @Published private(set) var recognitionIssue: String?
    @Published private(set) var draft = DraftSession()
    @Published private(set) var workspaceID: UUID?
    @Published private(set) var level: Double = -60
    @Published private(set) var sampleCount = 0
    @Published private(set) var sampleRate = 0
    @Published private(set) var message = "连接遥控器并启用语音识别，然后按住遥控器的语音键。"
    @Published var localeIdentifier = "zh-CN"
    @Published var allowServerRecognition = false
    @Published private(set) var usesExternalInput = false
    @Published private(set) var inputDestination: VoiceInputDestination = .draft
    @Published private(set) var directDraft = DraftSession()
    private let focusedInput: FocusedInputServicing?
    private var focusedTarget: FocusedInputTarget?

    private var recognitionDraft: DraftSession {
        get { inputDestination == .currentFocus ? directDraft : draft }
        set { if inputDestination == .currentFocus { directDraft = newValue } else { draft = newValue } }
    }
    var displayedDraft: DraftSession { recognitionDraft }

    private let bluetooth: BluetoothServicing
    private let speech: SpeechServicing
    private let externalInput: ExternalDictationHandling?
    private var speechFailed = false
    private var completedDuringHold = false
    private var captureInterruptionHandled = false
    private var workspaceDrafts: [UUID: DraftSession] = [:]
    private var unboundDraft = DraftSession()

    init(bluetooth: BluetoothServicing = BluetoothService(),
         speech: SpeechServicing = SpeechService(), externalInput: ExternalDictationHandling? = nil,
         focusedInput: FocusedInputServicing? = nil) {
        self.bluetooth = bluetooth
        self.speech = speech
        self.externalInput = externalInput
        self.focusedInput = focusedInput
        discovery = bluetooth.discovery
        externalInput?.onChange = { [weak self] in self?.objectWillChange.send() }
        recognitionEnabled = speech.isAuthorized
        bluetooth.onDiscovery = { [weak self] state in self?.discovery = state }
        bluetooth.onStatus = { [weak self] status in self?.connectionStatus = status }
        bluetooth.onReady = { [weak self] ready in
            guard let self else { return }
            if !ready { self.captureInterrupted("遥控器连接已中断") }
            self.ready = ready
        }
        bluetooth.onCaptureInterrupted = { [weak self] reason in self?.captureInterrupted(reason) }
        bluetooth.onLevel = { [weak self] level in self?.level = level }
        bluetooth.onStream = { [weak self] active, rate in self?.streamChanged(active, rate: rate) }
        bluetooth.onSamples = { [weak self] samples, rate in
            guard let self, self.isReceivingAudio else { return }
            self.sampleCount += samples.count
            if self.usesExternalInput {
                if !self.captureInterruptionHandled { self.externalInput?.append(samples: samples, sampleRate: rate) }
            } else if self.recognitionDraft.phase == .capturing {
                self.speech.append(samples: samples, sampleRate: rate)
            }
        }
        speech.onText = { [weak self] text, _ in
            guard let self, !self.completedDuringHold, let id = self.recognitionDraft.sessionID else { return }
            self.recognitionDraft.receive(text, session: id)
        }
        speech.onError = { [weak self] message in
            guard let self, !self.completedDuringHold, self.recognitionDraft.sessionID != nil else { return }
            self.speechFailed = true
            self.recognitionIssue = message
            self.message = message
        }
        speech.onFinished = { [weak self] in
            guard let self, !self.completedDuringHold, let id = self.recognitionDraft.sessionID else { return }
            if self.isReceivingAudio, self.recognitionDraft.phase == .capturing {
                // Keep this hold's rollback point until release or explicit cancel.
                // Finishing also prevents any remaining PCM reaching Speech.
                self.completedDuringHold = true
                self.recognitionDraft.finishCapture()
            } else {
                self.completeRecognition(session: id)
            }
            if !self.speechFailed, self.recognitionIssue == nil, self.inputDestination == .draft || self.isReceivingAudio {
                self.message = self.isReceivingAudio
                    ? "本段识别已结束。请松开语音键，再按住开始下一段。"
                    : self.completedMessage
            }
        }
    }

    var isBusy: Bool { isReceivingAudio || draft.isBusy || directDraft.isBusy || externalInput?.isBusy == true }
    var canCopy: Bool { !isBusy && recognitionDraft.canCopy }

    var captureLabel: String {
        if usesExternalInput { return isReceivingAudio ? "收音 · 外部输入法" : "外部输入法" }
        if isReceivingAudio && recognitionDraft.phase != .capturing { return "收音中 · 未转写" }
        switch recognitionDraft.phase {
        case .idle: return "等待说话"
        case .capturing: return "收音并转写"
        case .finishing: return "正在整理文字"
        }
    }

    func connect() {
        guard !isBusy else { return }
        bluetooth.start()
    }
    func discoverRemotes() {
        guard !isBusy else { return }
        bluetooth.discover()
    }
    func stopDiscovery() { bluetooth.stopDiscovery() }
    func selectRemote(_ id: UUID) {
        guard !isBusy else { return }
        bluetooth.selectRemote(id)
    }
    func setAutoReconnect(_ enabled: Bool) { bluetooth.setAutoReconnect(enabled) }
    func forgetRemote() {
        guard !isBusy else { return }
        bluetooth.forgetRemote()
    }

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

    func stopCapture() {
        captureInterrupted("已手动停止采音")
        bluetooth.stopCapture()
    }

    func cancelUtterance() {
        if usesExternalInput {
            captureInterrupted("已取消音频转交")
            bluetooth.stopCapture()
            message = "已停止音频转交。请确认输入法已停止，再处理接收框中的文字。"
            return
        }
        recognitionDraft.cancel()
        focusedTarget = nil
        completedDuringHold = false
        speech.cancel()
        bluetooth.stopCapture()
        message = "已取消这段听写，之前的草稿已保留。"
    }

    func disconnect() {
        captureInterrupted("已断开遥控器")
        bluetooth.disconnect()
        // Defensive cleanup also covers disconnect before a transport callback.
        streamChanged(false, rate: sampleRate)
    }

    func replaceDraft(_ text: String) {
        guard !isBusy else { return }
        recognitionDraft.replaceText(text)
    }

    @discardableResult
    func setInputDestination(_ destination: VoiceInputDestination) -> Bool {
        guard !isBusy else { return false }
        inputDestination = destination
        focusedTarget = nil
        recognitionIssue = nil
        return true
    }

    @discardableResult
    func setExternalInputEnabled(_ enabled: Bool) -> Bool {
        guard !isBusy else { return false }
        usesExternalInput = enabled
        recognitionIssue = nil
        return true
    }

    @discardableResult
    func appendExternalResult(_ text: String) -> Bool {
        guard usesExternalInput, inputDestination == .draft, !isBusy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let result = draft.replaceText(draft.text + (draft.text.isEmpty ? "" : "\n") + text)
        if result { message = "第三方识别文字已追加到当前草稿；仍需检查后确认输入。" }
        return result
    }

    /// Moving between destinations never moves text. Capture and finalization
    /// keep the same destination, including audio-only holds after Speech errors.
    @discardableResult
    func selectWorkspace(_ id: UUID?) -> Bool {
        guard !isBusy else { return false }
        guard id != workspaceID else { return true }
        if let current = workspaceID { workspaceDrafts[current] = draft }
        else { unboundDraft = draft }
        workspaceID = id
        draft = id.map { workspaceDrafts[$0] ?? DraftSession() } ?? unboundDraft
        message = "已切换工作区；各工作区草稿分别保留在内存中。"
        return true
    }

    func copyDraft() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recognitionDraft.text, forType: .string)
        message = "已复制。切换到目标输入框粘贴，检查后自行发送。"
    }

    func shutdown() {
        captureInterrupted("应用正在退出")
        speech.cancel()
        bluetooth.disconnect()
    }

    private func captureInterrupted(_ reason: String) {
        if usesExternalInput {
            // Deduplicate callbacks from one active hold only. A later prepared/review
            // provider still needs cleanup, even when no remote audio is arriving.
            if externalInput?.isBusy == true, !isReceivingAudio || !captureInterruptionHandled {
                externalInput?.interrupt()
            }
            captureInterruptionHandled = true
            return
        }
        guard !captureInterruptionHandled else { return }
        captureInterruptionHandled = true
        // Draft mode retains its existing finalization behavior. Automatic insertion must
        // distinguish a physical release from disconnect, watchdog or manual interruption.
        guard inputDestination == .currentFocus, focusedTarget != nil || directDraft.isBusy else { return }
        focusedTarget = nil
        speechFailed = true
        recognitionIssue = "\(reason)；本段文字将保留，不会自动填入。"
        message = recognitionIssue ?? reason
    }

    private func streamChanged(_ active: Bool, rate: Int) {
        if !active {
            let wasReceivingAudio = isReceivingAudio
            isReceivingAudio = false
            level = -60
            if usesExternalInput {
                if wasReceivingAudio, !captureInterruptionHandled { externalInput?.finishCapture() }
                return
            }
            if completedDuringHold {
                completedDuringHold = false
                if let id = recognitionDraft.sessionID { completeRecognition(session: id) }
            }
            if recognitionDraft.phase == .capturing {
                finishUtterance()
            } else if wasReceivingAudio, !recognitionDraft.isBusy, recognitionIssue == nil, inputDestination == .draft {
                message = completedMessage
            }
            return
        }
        // One physical hold owns one recognition attempt. Continue measuring audio
        // after a recognition failure, without closing or restarting the BLE stream.
        guard !isReceivingAudio else { return }
        isReceivingAudio = true
        captureInterruptionHandled = false
        sampleCount = 0
        sampleRate = rate
        if usesExternalInput {
            guard let externalInput else {
                recognitionIssue = "第三方语音通道不可用；请在「语音输入」配置后重试。"
                return
            }
            externalInput.startCapture(sampleRate: rate)
            return
        }
        recognitionEnabled = speech.isAuthorized
        guard recognitionEnabled else {
            message = "尚未获得语音识别授权。请松开语音键，点击「启用语音识别」后再试。"
            recognitionIssue = message
            return
        }
        guard !recognitionDraft.isBusy else {
            message = "本次按住未转写：开始时上一段还在整理。请松开语音键，等待完成后重试。"
            recognitionIssue = message
            return
        }
        do {
            if inputDestination == .currentFocus {
                guard directDraft.text.isEmpty else {
                    throw PendingFocusedText()
                }
                guard let focusedInput else { throw FocusedInputError.unavailable }
                focusedTarget = try focusedInput.capture()
            }
            try speech.start(localeIdentifier: localeIdentifier,
                             allowServerRecognition: allowServerRecognition)
            recognitionDraft.begin()
            speechFailed = false
            recognitionIssue = nil
            message = "正在从遥控器收音。松开语音键会结束这段听写。"
        } catch {
            focusedTarget = nil
            message = error.localizedDescription
            recognitionIssue = message
        }
    }

    private func completeRecognition(session: UUID) {
        recognitionDraft.complete(session: session)
        guard inputDestination == .currentFocus else { return }
        // Consume the target before attempting any mutation, including uncertain failures.
        let target = focusedTarget
        focusedTarget = nil
        guard !speechFailed, recognitionIssue == nil else { return }
        guard directDraft.canCopy else { message = "没有识别到文字，请重试。"; return }
        do {
            guard let target, let focusedInput else { throw FocusedInputError.unavailable }
            try focusedInput.insert(directDraft.text, into: target)
            directDraft.replaceText("")
            message = "已填入 \(target.appName) 的输入框，未发送。"
        } catch {
            recognitionIssue = error.localizedDescription
            message = "文字已保留。\(error.localizedDescription)"
        }
    }

    private var completedMessage: String {
        recognitionDraft.canCopy
            ? "草稿已保留。检查文字后可复制到目标输入框。"
            : "没有识别到文字。请检查音量指示后重试。"
    }

    private func finishUtterance() {
        recognitionDraft.finishCapture()
        if !speechFailed { message = "收音已结束，正在等待最终识别结果…" }
        speech.finish()
    }
}

private struct PendingFocusedText: LocalizedError {
    var errorDescription: String? { "上一段文字尚待处理，请先检查目标输入框，复制或清空保留文字后再说话。" }
}
