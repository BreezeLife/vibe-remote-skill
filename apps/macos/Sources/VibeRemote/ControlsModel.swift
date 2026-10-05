import AppKit
import Combine
import UniformTypeIdentifiers
import VibeRemoteCore

@MainActor
final class ControlsModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case dictation = "听写", buttons = "按键", tools = "编程工具", connection = "连接与权限"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dictation: return "waveform"
            case .buttons: return "dpad"
            case .tools: return "chevron.left.forwardslash.chevron.right"
            case .connection: return "antenna.radiowaves.left.and.right"
            }
        }
    }
    enum LearnKind { case input, anchor, send, stop }
    struct SendPreview: Identifiable {
        let id = UUID()
        let confirmation: ToolSendConfirmation
        let review: DraftReview
        let workspace: WorkspaceProfile
    }

    let voice: RemoteModel
    let hid: HIDRemoteInputService
    let adapter: ToolAdapter
    private let store: NativeSettingsStore
    private let showWindowOverride: (() -> Void)?
    @Published private(set) var settings: NativeSettings
    @Published var page: Page = .dictation { didSet { engine.reset() } }
    @Published var selectedButton: RemoteButton = .ok
    @Published var lockButtonSelection = false { didSet { engine.reset() } }
    @Published private(set) var pressedButton: RemoteButton?
    @Published private(set) var status = "在「按键」学习实体键，在「编程工具」绑定工作区。"
    @Published private(set) var suppressionConfirmed = false
    @Published private(set) var mappingsEnabled = false
    @Published private(set) var learningButton: RemoteButton?
    @Published private(set) var operationInProgress = false
    @Published private(set) var learningTool = false
    @Published private(set) var installedTools: [InstalledTool] = []
    @Published var pendingSend: SendPreview?
    @Published var showingWorkspaces = false
    @Published var showingActions = false
    @Published var pickerIndex = 0
    let menuActions: [RemoteAction] = [.focusTarget, .copyDraft, .insertDraft, .sendDraft, .stopTask, .preview]
    @Published private(set) var capabilityResults: [UUID: [String]] = [:]
    @Published private(set) var capabilityChecks: [UUID: [RemoteAction: String]] = [:]

    private var engine = ButtonGestureEngine()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var permissionTick: TimeInterval = 0
    private var calibrationDown: (HIDBinding, TimeInterval)?
    private var learnedInputs: [UUID: LearnedToolInput] = [:]
    private var learningTask: Task<Void, Never>?
    private var insertion: [UUID: (draft: String, text: String)] = [:]
    private var activeOperation: Task<Void, Never>?
    private var operationGeneration = 0
    private var operationReview: DraftReview?

    init(voice: RemoteModel, store: NativeSettingsStore = NativeSettingsStore(),
         hid: HIDRemoteInputService? = nil, adapter: ToolAdapter? = nil,
         showWindow: (() -> Void)? = nil) {
        self.voice = voice
        self.store = store
        self.showWindowOverride = showWindow
        self.hid = hid ?? HIDRemoteInputService()
        self.adapter = adapter ?? ToolAdapter()
        do { settings = try store.load() }
        catch { settings = .defaults; status = "配置未载入：\(error.localizedDescription)。原文件已保留，可导入有效配置。" }
        self.hid.onInput = { [weak self] input, down, time in self?.receive(input, down: down, time: time) }
        self.hid.onReset = { [weak self] in self?.resetInput() }
        self.hid.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        voice.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.voice.isBusy {
                    self.activeOperation?.cancel()
                    self.learningTask?.cancel()
                }
                if let review = self.operationReview,
                   !review.matches(workspaceID: self.voice.workspaceID, draft: self.voice.draft.text, busy: self.voice.isBusy) {
                    self.activeOperation?.cancel()
                    self.learningTask?.cancel()
                }
                if let pending = self.pendingSend,
                   !pending.review.matches(workspaceID: self.voice.workspaceID,
                                           draft: self.voice.draft.text, busy: self.voice.isBusy) {
                    self.pendingSend = nil
                    self.status = "草稿或目标已变化，请重新预览后再发送。"
                }
                self.objectWillChange.send()
            }
        }.store(in: &cancellables)
        // Permission queries do not prompt; device discovery remains explicit.
        self.hid.refreshPermission()
        installedTools = self.adapter.installedTools()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var workspace: WorkspaceProfile? { settings.workspaces.first { $0.id == voice.workspaceID } }
    var mapping: ButtonMapping { settings.mappings.first { $0.button == selectedButton }! }
    var canEdit: Bool { !voice.isBusy && !operationInProgress }
    var accessibilityGranted: Bool { adapter.permissionGranted }
    var safety: ActionSafety {
        ActionSafety(exclusiveDevice: hid.isExclusive, suppressionConfirmed: suppressionConfirmed,
                     busy: voice.isBusy, operationInProgress: operationInProgress,
                     hasWorkspace: workspace != nil, hasDraft: voice.canCopy)
    }

    func refreshTools() { installedTools = adapter.installedTools(); objectWillChange.send() }
    func requestAccessibility() { adapter.requestPermission(); objectWillChange.send() }
    func selectWorkspace(_ id: UUID?) {
        guard !operationInProgress, id == nil || settings.workspaces.contains(where: { $0.id == id }) else { return }
        guard voice.selectWorkspace(id) else { status = "收音和识别整理期间，工作区已锁定。"; return }
        pendingSend = nil
        engine.reset()
    }

    @discardableResult
    func updateSettings(_ edit: (inout NativeSettings) -> Void) -> Bool {
        guard !voice.isBusy, !operationInProgress else { status = "请等待当前操作结束再修改配置。"; return false }
        var proposed = settings
        edit(&proposed)
        return persist(proposed)
    }

    @discardableResult
    private func persist(_ proposed: NativeSettings) -> Bool {
        do {
            try store.save(proposed)
            settings = proposed
            engine.reset()
            pendingSend = nil
            capabilityResults = [:]
            capabilityChecks = [:]
            status = "配置已保存。执行动作时仍会重新检查实际目标。"
            return true
        } catch { status = "未保存：\(error.localizedDescription)"; return false }
    }

    @discardableResult
    func updateMapping(_ edit: (inout ButtonMapping) -> Void) -> Bool {
        updateSettings { settings in
            guard let i = settings.mappings.firstIndex(where: { $0.button == selectedButton }) else { return }
            edit(&settings.mappings[i])
        }
    }
    func restoreButtonDefaults() { updateSettings { $0.mappings = NativeSettings.defaults.mappings } }
    func updateWorkspace(_ proposed: WorkspaceProfile) {
        updateSettings { config in
            if let index = config.workspaces.firstIndex(where: { $0.id == proposed.id }) { config.workspaces[index] = proposed }
        }
    }
    func addWorkspace(_ tool: InstalledTool) {
        let profile = WorkspaceProfile(name: tool.name, bundleIdentifier: tool.bundleIdentifier, appPath: tool.appPath)
        if updateSettings({ $0.workspaces.append(profile) }) { selectWorkspace(profile.id) }
    }
    func duplicateWorkspace(_ source: WorkspaceProfile) {
        var copy = source
        copy.id = UUID()
        copy.name += " 副本"
        if updateSettings({ $0.workspaces.append(copy) }) { selectWorkspace(copy.id) }
    }
    func chooseCustomApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { addWorkspace(try adapter.application(at: url)) }
        catch { status = error.localizedDescription }
    }

    func exportSettings(toClipboard: Bool = false) {
        do {
            let data = try NativeSettingsStore.encode(settings)
            if toClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                status = "已复制配置 JSON（不含草稿）。"
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "VibeRemote-settings.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            status = "已导出配置，不包含草稿、音频或设备身份。"
        } catch { status = error.localizedDescription }
    }
    func importSettings() {
        guard canEdit else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try NativeSettingsStore.decode(Data(contentsOf: url))
            // Preserve existing destinations and their draft ownership. A changed
            // imported destination gets a fresh ID rather than taking an old draft.
            for i in imported.workspaces.indices {
                if let old = settings.workspaces.first(where: { $0.id == imported.workspaces[i].id }),
                   old != imported.workspaces[i] { imported.workspaces[i].id = UUID() }
            }
            let ids = Set(imported.workspaces.map(\.id))
            imported.workspaces += settings.workspaces.filter { !ids.contains($0.id) }
            hid.pause()
            if persist(imported) { status = "已导入按键配置及工作区；已有工作区和草稿已保留。映射保持暂停。" }
        } catch { status = "导入失败，当前配置未变：\(error.localizedDescription)" }
    }

    func setSuppressionConfirmed(_ confirmed: Bool) {
        suppressionConfirmed = confirmed && hid.isExclusive
        if !suppressionConfirmed { revokeOperation(); mappingsEnabled = false; engine.reset(); pendingSend = nil }
    }
    func enableMappings() {
        guard hid.isExclusive, suppressionConfirmed, learningButton == nil, !learningTool else {
            status = "先独占接管设备，校准按键并验证系统原始事件没有穿透。"; return
        }
        engine.reset()
        mappingsEnabled = true
        status = "映射已启用。语音键仍由 ATVV 处理。"
    }
    func pauseMappings(releaseDevice: Bool = true) {
        revokeOperation()
        mappingsEnabled = false
        engine.reset()
        pendingSend = nil
        learningButton = nil
        calibrationDown = nil
        if releaseDevice { hid.pause() }
        status = "映射已暂停。"
    }
    private func resetInput() {
        revokeOperation()
        mappingsEnabled = false
        suppressionConfirmed = false
        learningButton = nil
        pressedButton = nil
        calibrationDown = nil
        engine.reset()
        pendingSend = nil
    }
    func learnButton() {
        guard selectedButton != .mic, canEdit, hid.isObserving || hid.isExclusive else {
            status = "先在连接页选择设备并开始观察或独占校准。"; return
        }
        mappingsEnabled = false
        engine.reset()
        pendingSend = nil
        learningButton = selectedButton
        calibrationDown = nil
        status = "按住 \(selectedButton.label) 约 1 秒再松开。学习期间不执行映射。"
    }
    func cancelButtonLearning() { learningButton = nil; calibrationDown = nil; engine.reset() }

    private func sameInput(_ a: HIDBinding, _ b: HIDBinding) -> Bool {
        a.usagePage == b.usagePage && a.usage == b.usage && a.reportID == b.reportID && a.descriptorHash.lowercased() == b.descriptorHash.lowercased()
    }
    private func receive(_ input: HIDBinding, down: Bool, time: TimeInterval) {
        if let button = learningButton {
            if down, calibrationDown == nil { calibrationDown = (input, time) }
            if !down, let (started, start) = calibrationDown, sameInput(started, input) {
                var learned = input
                learned.supportsHold = input.supportsHold && time - start >= 0.5
                learningButton = nil
                calibrationDown = nil
                selectedButton = button
                let saved = updateMapping { mapping in
                    mapping.input = learned
                    if !learned.supportsHold { mapping.long = nil }
                }
                if !saved { return }
                status = "已学习 \(button.label)：usage \(input.usagePage):\(input.usage)，\(learned.supportsHold ? "支持长按" : "仅短按；可重新学习长按")。"
            }
            return
        }
        guard let mapping = settings.mappings.first(where: { $0.input.map { sameInput($0, input) } ?? false }) else { return }
        pressedButton = down ? mapping.button : nil
        if page == .buttons, !lockButtonSelection, !showingWorkspaces, !showingActions, pendingSend == nil {
            if down { selectedButton = mapping.button }
            engine.reset()
            return
        }
        guard mappingsEnabled, hid.isExclusive, suppressionConfirmed, !learningTool else { return }
        var routedMapping = mapping
        if showingWorkspaces || showingActions || pendingSend != nil {
            // Physical navigation remains available even if its normal action is disabled/remapped.
            routedMapping.single = .actionPicker
            routedMapping.long = nil
            routedMapping.double = nil
            routedMapping.input?.supportsHold = false
        }
        for event in engine.process(button: mapping.button, isDown: down,
                                    at: ProcessInfo.processInfo.systemUptime, mapping: routedMapping) {
            route(event)
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - permissionTick > 1 {
            permissionTick = now
            hid.refreshPermission()
            if !adapter.permissionGranted { pendingSend = nil }
        }
        guard mappingsEnabled, hid.isExclusive, suppressionConfirmed, !learningTool else { return }
        if page == .buttons, !lockButtonSelection, !showingWorkspaces, !showingActions, pendingSend == nil {
            engine.reset()
            return
        }
        for event in engine.advance(to: now) { route(event) }
    }

    func hasLearnedInput(for id: UUID) -> Bool { learnedInputs[id] != nil }
    func learn(_ kind: LearnKind, for profile: WorkspaceProfile) {
        guard canEdit else { return }
        if kind == .input || kind == .anchor {
            guard voice.workspaceID != profile.id || voice.draft.text.isEmpty else {
                status = "该工作区已有草稿；请新建工作区绑定另一个目标，以保留草稿归属。"; return
            }
        }
        learningTask?.cancel()
        let review = DraftReview(workspaceID: profile.id, draft: voice.draft.text)
        operationReview = review
        mappingsEnabled = false
        engine.reset()
        pendingSend = nil
        operationInProgress = true
        learningTool = true
        learningTask = Task { [weak self] in
            guard let self else { return }
            defer { self.operationInProgress = false; self.learningTool = false; self.operationReview = nil }
            do {
                for second in (1...5).reversed() {
                    let instruction = kind == .input ? "切换到工具并点击输入框" : "切换到工具，把鼠标停在要学习的会话标题/控件上"
                    self.status = "\(second) 秒后学习：\(instruction)。"
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                try Task.checkCancellation()
                guard self.workspace == profile,
                      review.matches(workspaceID: self.voice.workspaceID, draft: self.voice.draft.text, busy: self.voice.isBusy),
                      !(kind == .input || kind == .anchor) || self.voice.draft.text.isEmpty else {
                    throw ControlError.message("学习期间草稿或工作区已变化，旧绑定已保留。")
                }
                if kind == .input {
                    self.learnedInputs[profile.id] = try self.adapter.learnInput(for: profile)
                    self.status = "输入框已暂存。下一步学习同一窗口内当前会话的独有标题，完成绑定。"
                } else {
                    var updated = profile
                    if kind == .anchor {
                        guard let input = self.learnedInputs[profile.id] else { throw ControlError.message("请先学习输入框。") }
                        updated.binding = try self.adapter.learnTaskAnchor(for: profile, input: input)
                    } else {
                        updated.binding = try self.adapter.learnControl(for: profile, kind: kind == .send ? .send : .stop)
                    }
                    var proposed = self.settings
                    guard let i = proposed.workspaces.firstIndex(where: { $0.id == profile.id }) else { return }
                    proposed.workspaces[i] = updated
                    _ = self.persist(proposed)
                }
            } catch is CancellationError { self.status = "已取消学习，旧绑定已保留。" }
            catch { self.status = "未完成学习：\(error.localizedDescription)" }
        }
    }
    func cancelToolLearning() { learningTask?.cancel() }

    func showWindow() {
        if let showWindowOverride { showWindowOverride(); return }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Vibe Remote" })?.makeKeyAndOrderFront(nil)
    }
    func perform(_ action: RemoteAction) {
        if action == .none { return }
        if let reason = safety.blockReason(for: action) {
            status = reason
            if let profile = workspace { recordCheck(action, profile: profile, result: "当前检查失败：" + reason) }
            return
        }
        switch action {
        case .none: break
        case .workspacePicker:
            pendingSend = nil; showingActions = false; pickerIndex = 0; engine.reset()
            page = .dictation; showingWorkspaces = true; showWindow()
        case .actionPicker:
            pendingSend = nil; showingWorkspaces = false; pickerIndex = 0; engine.reset()
            showingActions = true; showWindow()
        case .cancel:
            revokeOperation()
            pendingSend = nil
            showingActions = false
            showingWorkspaces = false
            if voice.isBusy { voice.cancelUtterance() }
        case .copyDraft: voice.copyDraft()
        case .previousWorkspace, .nextWorkspace:
            let all = settings.workspaces
            let current = all.firstIndex(where: { $0.id == voice.workspaceID })
            let index = current.map { $0 + (action == .nextWorkspace ? 1 : -1) } ?? 0
            guard all.indices.contains(index) else { status = "已到已登记工作区的边界。"; return }
            selectWorkspace(all[index].id)
        case .preview:
            guard let value = workspace?.previewURL, let url = URL(string: value) else { status = "请先配置 HTTP(S) 预览地址。"; return }
            NSWorkspace.shared.open(url)
        case .volumeUp, .volumeDown:
            do { try SystemVolume.adjust(by: action == .volumeUp ? 0.0625 : -0.0625) }
            catch { status = error.localizedDescription }
        case .sendDraft:
            if pendingSend != nil, NSApp.isActive { confirmSend(); return }
            prepareSend()
        default: executeToolAction(action)
        }
    }

    private func executeToolAction(_ action: RemoteAction) {
        guard let profile = workspace else { return }
        let draft = voice.draft.text
        recordCheck(action, profile: profile, result: "正在检查…")
        installOperationGuard(profile, review: action == .insertDraft ? DraftReview(workspaceID: profile.id, draft: draft) : nil)
        operationInProgress = true
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                var confirmed = true
                switch action {
                case .focusTarget:
                    try await self.adapter.focus(for: profile)
                    self.status = "已重新验证并聚焦绑定输入框。"
                case .insertDraft:
                    let inserted = try await self.adapter.insert(draft, for: profile)
                    self.insertion[profile.id] = (draft, inserted)
                    self.status = "已插入并读回验证。检查工具输入，再选择「预览发送」。"
                case .stopTask:
                    let outcome = try await self.adapter.stop(for: profile)
                    self.status = outcome.message
                    confirmed = outcome.confirmed
                case .scrollUp, .scrollDown:
                    try await self.adapter.scroll(action == .scrollUp ? .up : .down, for: profile)
                    self.status = "已向绑定窗口发送滚动操作。"
                default: return
                }
                self.recordCheck(action, profile: profile, result: (confirmed ? "上次检查通过：" : "操作结果未确认：") + self.status)
            } catch {
                self.status = "\(action.label)未完成：\(error.localizedDescription)"
                self.recordCheck(action, profile: profile, result: "当前检查失败：" + error.localizedDescription)
            }
        }
    }

    private func prepareSend() {
        guard let profile = workspace else { return }
        guard let inserted = insertion[profile.id], inserted.draft == voice.draft.text else {
            status = "请先插入当前草稿，再预览发送；发送动作不会重复插入文字。"
            recordCheck(.sendDraft, profile: profile, result: "当前检查失败：" + status)
            return
        }
        let review = DraftReview(workspaceID: profile.id, draft: voice.draft.text)
        installOperationGuard(profile, review: review, requiresDevice: true)
        operationInProgress = true
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                let confirmation = try await self.adapter.prepareSend(for: profile)
                guard confirmation.text == inserted.text,
                      review.matches(workspaceID: self.voice.workspaceID, draft: self.voice.draft.text, busy: self.voice.isBusy),
                      self.hid.isExclusive, self.suppressionConfirmed else {
                    throw ControlError.message("输入内容、工作区或设备状态已变化，请重新插入并检查。")
                }
                self.recordCheck(.sendDraft, profile: profile, result: "预览检查通过，等待确认；尚未发送。")
                self.pendingSend = SendPreview(confirmation: confirmation, review: review, workspace: profile)
                self.showWindow()
            } catch {
                self.status = "无法预览发送：\(error.localizedDescription)"
                self.recordCheck(.sendDraft, profile: profile, result: "当前检查失败：" + error.localizedDescription)
            }
        }
    }
    func confirmSend() {
        guard let pending = pendingSend else { return }
        pendingSend = nil
        guard let current = workspace, current == pending.workspace,
              pending.review.matches(workspaceID: voice.workspaceID, draft: voice.draft.text, busy: voice.isBusy),
              safety.blockReason(for: .sendDraft) == nil else { status = "确认已失效，请重新预览。"; return }
        installOperationGuard(current, review: pending.review, requiresDevice: true)
        operationInProgress = true
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                let outcome = try await self.adapter.confirmSend(pending.confirmation, for: current)
                self.insertion[current.id] = nil
                self.status = outcome.message
                self.recordCheck(.sendDraft, profile: current, result: (outcome.confirmed ? "上次观察到任务开始：" : "操作结果未确认：") + outcome.message)
            } catch {
                self.status = "发送未完成：\(error.localizedDescription)"
                self.recordCheck(.sendDraft, profile: current, result: "当前检查失败：" + error.localizedDescription)
            }
        }
    }
    private func recordCheck(_ action: RemoteAction, profile: WorkspaceProfile, result: String) {
        guard [.focusTarget, .insertDraft, .sendDraft, .stopTask, .scrollUp, .scrollDown].contains(action) else { return }
        capabilityChecks[profile.id, default: [:]][action] = result
        capabilityResults[profile.id, default: []].append("\(action.label)：\(result)")
        capabilityResults[profile.id] = Array(capabilityResults[profile.id, default: []].suffix(4))
    }
    func capabilityDescription(_ capability: ToolCapability, for profile: WorkspaceProfile) -> String {
        capabilityChecks[profile.id]?[capability.action] ?? capability.reason
    }
    private func revokeOperation() {
        operationGeneration += 1
        activeOperation?.cancel()
        learningTask?.cancel()
    }
    private func installOperationGuard(_ profile: WorkspaceProfile, review: DraftReview?, requiresDevice: Bool = false) {
        operationGeneration += 1
        let generation = operationGeneration
        operationReview = review
        adapter.authorizeOperation = { [weak self] in
            guard let self, self.operationGeneration == generation, !self.voice.isBusy,
                  self.workspace == profile,
                  review?.matches(workspaceID: self.voice.workspaceID, draft: self.voice.draft.text, busy: self.voice.isBusy) ?? true,
                  !requiresDevice || (self.hid.isExclusive && self.suppressionConfirmed) else {
                throw ControlError.message("操作前草稿、目标或设备状态已变化，动作已取消。")
            }
        }
    }
    private func finishOperation() {
        operationInProgress = false
        operationReview = nil
        adapter.authorizeOperation = nil
    }
    private func route(_ event: GestureTrigger) {
        if showingWorkspaces || showingActions {
            // Picker context owns the physical controls regardless of their tool mapping.
            guard event.gesture == .click, !event.repeated else { return }
            let count = showingWorkspaces ? settings.workspaces.count + 1 : menuActions.count
            switch event.button {
            case .up, .left: pickerIndex = max(0, pickerIndex - 1)
            case .down, .right: pickerIndex = min(max(0, count - 1), pickerIndex + 1)
            case .back: showingWorkspaces = false; showingActions = false; engine.reset()
            case .ok:
                if showingWorkspaces {
                    let id = pickerIndex == 0 ? nil : settings.workspaces[pickerIndex - 1].id
                    showingWorkspaces = false
                    selectWorkspace(id)
                } else {
                    let action = menuActions[pickerIndex]
                    showingActions = false
                    engine.reset()
                    perform(action)
                }
            default: break
            }
            return
        }
        if pendingSend != nil {
            guard event.gesture == .click, !event.repeated else { return }
            if event.button == .back { pendingSend = nil }
            else if event.button == .ok, NSApp.isActive { confirmSend() }
            return
        }
        perform(event.action)
    }
    func openCodexThread() {
        guard canEdit, let profile = workspace, profile.bundleIdentifier == "com.openai.codex",
              let value = profile.codexThreadURL, let url = URL(string: value) else { return }
        pendingSend = nil
        NSWorkspace.shared.open(url)
        status = "已请求打开明确的 Codex 会话；工具动作仍需实际窗口和输入绑定通过检查。"
    }
    func prefillNewCodexDraft() {
        guard canEdit, voice.canCopy, workspace?.bundleIdentifier == "com.openai.codex" else { return }
        var components = URLComponents()
        components.scheme = "codex"; components.host = "new"
        components.queryItems = [URLQueryItem(name: "prompt", value: voice.draft.text)]
        guard let url = components.url else { return }
        pendingSend = nil
        NSWorkspace.shared.open(url)
        status = "已请求在 Codex 预填新会话草稿，不会发送。原工作区绑定保持不变；新会话需另建工作区绑定。"
    }
    func shutdown() {
        learningTask?.cancel()
        activeOperation?.cancel()
        timer?.invalidate()
        hid.pause()
        voice.shutdown()
    }
    enum ControlError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
