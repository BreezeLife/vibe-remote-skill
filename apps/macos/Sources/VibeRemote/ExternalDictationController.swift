import AppKit
import Combine
import VibeRemoteCore

protocol DictationHotkeySending: AnyObject {
    var isAuthorized: Bool { get }
    func begin(_ profile: VoiceInputProfile) throws
    func end(_ profile: VoiceInputProfile) throws
    func releaseHeldKey()
}

/// Only a locally configured, restricted shortcut is emitted; no Enter, paste or send action.
final class DictationHotkeys: DictationHotkeySending {
    private var held: (UInt16, CGEventFlags)?
    var isAuthorized: Bool { CGPreflightPostEventAccess() }

    func begin(_ profile: VoiceInputProfile) throws {
        guard profile.triggerMode != .manual else { return }
        guard isAuthorized, let key = profile.shortcutKeyCode else {
            throw ExternalDictationError.message("请先授权 Vibe Remote 辅助功能，并配置输入法快捷键。")
        }
        var flags: CGEventFlags = []
        for modifier in profile.shortcutModifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        try post(key, flags: flags, down: true)
        if profile.triggerMode == .hold { held = (key, flags) }
        else { try post(key, flags: flags, down: false) }
    }
    func end(_ profile: VoiceInputProfile) throws {
        if profile.triggerMode == .hold { releaseHeldKey() }
        else if profile.triggerMode == .toggle { try begin(profile) }
    }
    func releaseHeldKey() {
        guard let (key, flags) = held else { return }
        held = nil
        try? post(key, flags: flags, down: false)
    }
    private func post(_ key: UInt16, flags: CGEventFlags, down: Bool) throws {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else {
            throw ExternalDictationError.message("无法生成输入法快捷键；请在输入法中手动停止。")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
    deinit { releaseHeldKey() }
}

enum ExternalDictationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The external provider owns its recording/transcription state. A shortcut is only
/// an attempted gesture; the user must observe completion before importing its text.
final class ExternalDictationController: ObservableObject, ExternalDictationHandling {
    enum Phase: Equatable { case idle, prepared, capturing, draining, review }
    @Published private(set) var phase: Phase = .idle { didSet { onChange?() } }
    @Published private(set) var status = "选择语音输入法并检查音频与快捷键。"
    @Published var resultText = ""
    @Published private(set) var profile: VoiceInputProfile?
    var onChange: (() -> Void)?
    var receiverIsFocused: () -> Bool = { false }
    var isBusy: Bool { phase != .idle }
    var canSettle: Bool { phase == .review || phase == .prepared }
    var canAutomateShortcut: Bool { hotkeys.isAuthorized }
    var devices: [RemoteAudioDevice] { audio.availableDevices() }
    private let audio: RemoteAudioOutputting
    private let hotkeys: DictationHotkeySending
    private let monitorFocus: Bool
    private var focusTimer: Timer?
    private var generation = UUID()

    init(audio: RemoteAudioOutputting = RemoteAudioOutput(),
         hotkeys: DictationHotkeySending = DictationHotkeys(), monitorFocus: Bool = true) {
        self.audio = audio; self.hotkeys = hotkeys; self.monitorFocus = monitorFocus
        audio.onError = { [weak self] error in
            guard let self, self.phase == .capturing else { return }
            self.fail(error.localizedDescription)
        }
    }

    func prepare(_ profile: VoiceInputProfile, microphoneConfirmed: Bool, shortcutConfirmed: Bool) throws {
        guard !isBusy else { throw ExternalDictationError.message("请先处理当前接收框。") }
        try profile.validate()
        guard profile.provider != .appleSpeech, microphoneConfirmed,
              let uid = profile.outputDeviceUID, devices.contains(where: { $0.id == uid }) else {
            throw ExternalDictationError.message("请选择已安装的虚拟音频通道，并在输入法中选择同一麦克风。")
        }
        guard profile.triggerMode == .manual || (shortcutConfirmed && hotkeys.isAuthorized) else {
            throw ExternalDictationError.message("请检查输入法快捷键并授权辅助功能；也可使用手动模式。")
        }
        self.profile = profile
        generation = UUID()
        resultText = ""
        status = profile.triggerMode == .manual
            ? "接收框准备好后，请用输入法自己的快捷键开始识别，再按住遥控器说话；松开后手动结束输入法。"
            : "按住遥控器说话。输入法快捷键只尝试启动/结束识别，实际状态以输入法提示为准。"
        phase = .prepared
    }

    func startCapture(sampleRate: Int) {
        guard phase == .prepared, let profile, let uid = profile.outputDeviceUID else {
            if phase == .idle { status = "请先在「语音输入」点击「准备第三方听写」。" }
            return
        }
        guard receiverIsFocused() else {
            status = "接收框未聚焦；本次没有转交音频或启动输入法。请确认输入法已结束后重新准备。"
            phase = .review
            return
        }
        do {
            try audio.start(deviceUID: uid, sampleRate: sampleRate)
            if profile.triggerMode != .manual { try hotkeys.begin(profile) }
            phase = .capturing
            status = "正在向选定的虚拟麦克风转交遥控器音频；请检查输入法的录音指示。"
            if monitorFocus {
                focusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkFocus() }
            }
        } catch { fail(error.localizedDescription) }
    }

    func append(samples: [Int16], sampleRate: Int) {
        guard phase == .capturing else { return }
        checkFocus()
        guard phase == .capturing else { return }
        do { try audio.append(samples: samples, sampleRate: sampleRate) }
        catch { fail(error.localizedDescription) }
    }

    func finishCapture() {
        guard phase == .capturing, let profile else { return }
        phase = .draining
        let expected = generation
        audio.finish { [weak self] outcome in
            guard let self, self.generation == expected, self.phase == .draining else { return }
            switch outcome {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success:
                guard self.receiverIsFocused() else {
                    self.fail("接收框失去焦点；请在输入法中手动结束，避免文字落到其他窗口。")
                    return
                }
                do {
                    if profile.triggerMode != .manual { try self.hotkeys.end(profile) }
                    self.focusTimer?.invalidate(); self.focusTimer = nil
                    self.status = profile.triggerMode == .manual
                        ? "音频已转交。请手动结束输入法，等文字落入下方接收框，再确认加入草稿。"
                        : "音频已转交，已尝试结束快捷键。等待文字出现并确认输入法已停止，再加入草稿。"
                    self.phase = .review
                } catch { self.fail(error.localizedDescription) }
            }
        }
    }

    func checkFocus() {
        guard phase == .capturing || phase == .draining else { return }
        if !receiverIsFocused() { fail("接收框失去焦点，已停止音频转交。请手动结束输入法，再检查文字。") }
    }

    func interrupt() {
        guard isBusy else { return }
        fail("音频转交已中断。请在输入法中手动停止，并检查接收框；原工作区草稿保持不变。")
    }

    func takeResult(providerFinished: Bool) -> String? {
        guard phase == .review, providerFinished,
              !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let text = resultText
        reset()
        return text
    }
    @discardableResult
    func discard(providerFinished: Bool) -> Bool {
        guard canSettle, providerFinished else { return false }
        reset()
        return true
    }
    private func fail(_ reason: String) {
        generation = UUID()
        audio.cancel()
        // A release cannot start a new recording. An uncertain toggle can, so never retry it.
        hotkeys.releaseHeldKey()
        focusTimer?.invalidate(); focusTimer = nil
        status = reason
        phase = .review
    }
    private func reset() {
        generation = UUID()
        focusTimer?.invalidate(); focusTimer = nil
        resultText = ""; profile = nil
        phase = .idle
    }
    deinit { focusTimer?.invalidate(); audio.cancel(); hotkeys.releaseHeldKey() }
}
