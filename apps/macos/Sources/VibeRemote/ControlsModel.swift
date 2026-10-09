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
    private let codexCatalog: CodexConversationListing
    private var codexCatalogProfiles: [WorkspaceProfile] = []
    private var lastCodexSession: [String: UUID] = [:]
    @Published private(set) var codexSetupStatus = "点击一键配置，读取本机 Codex 会话并准备按键方案。"
    @Published private(set) var codexConversations: [CodexConversation] = []
    @Published private(set) var codexChecks: [String: String] = [:]
    @Published var codexProjectPath = ""

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
    // An attempted mutation may have succeeded even if readback or AX returns an error.
    private var uncertainCodexInsertion = Set<UUID>()
    private var codexSubmission: [UUID: (draft: String, confirmed: Bool)] = [:]
    private var codexClearedAfterSubmission = Set<UUID>()
    private var activeOperation: Task<Void, Never>?
    private var operationGeneration = 0
    private var operationReview: DraftReview?

    init(voice: RemoteModel, store: NativeSettingsStore = NativeSettingsStore(),
         hid: HIDRemoteInputService? = nil, adapter: ToolAdapter? = nil,
         showWindow: (() -> Void)? = nil, codexCatalog: CodexConversationListing? = nil) {
        self.voice = voice
        self.store = store
        self.codexCatalog = codexCatalog ?? CodexConversationCatalogService()
        self.showWindowOverride = showWindow
        self.hid = hid ?? HIDRemoteInputService()
        self.adapter = adapter ?? ToolAdapter()
        do { settings = try store.load() }
        catch { settings = .defaults; status = "配置未载入：\(error.localizedDescription)。原文件已保留，可导入有效配置。" }
        codexCatalogProfiles = settings.workspaces.filter { $0.codexConversation != nil }
        codexConversations = codexCatalogProfiles.compactMap(\.codexConversation)
        self.hid.onInput = { [weak self] input, down, time in self?.receive(input, down: down, time: time) }
        self.hid.onReset = { [weak self] in self?.resetInput() }
        self.hid.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        voice.$draft.sink { [weak self] draft in
            guard let self, let id = self.voice.workspaceID, self.codexSubmission[id]?.confirmed == true,
                  !draft.isBusy, !self.voice.isReceivingAudio, draft.text.isEmpty else { return }
            self.codexClearedAfterSubmission.insert(id)
        }.store(in: &cancellables)
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
    var mapping: ButtonMapping { settings.effectiveMapping(for: selectedButton, workspaceID: voice.workspaceID) }
    var buttonConfigurationScope: String { workspace?.name ?? "通用配置（未绑定工作区）" }
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
        if let id, settings.workspaces.first(where: { $0.id == id })?.codexConversation != nil {
            openCodexSession(id)
            return
        }
        selectWorkspaceLocally(id)
    }
    private func selectWorkspaceLocally(_ id: UUID?) {
        guard !operationInProgress, id == nil || settings.workspaces.contains(where: { $0.id == id }) else { return }
        guard voice.selectWorkspace(id) else { status = "收音和识别整理期间，工作区已锁定。"; return }
        pendingSend = nil
        engine.reset()
    }

    var codexProjectPaths: [String] {
        Array(Set(codexCatalogProfiles.compactMap { $0.codexConversation?.projectPath })).sorted()
    }
    var codexSessionProfiles: [WorkspaceProfile] {
        orderedCodexProfiles(in: codexProjectPath)
    }
    private func orderedCodexProfiles(in path: String) -> [WorkspaceProfile] {
        codexCatalogProfiles.filter { $0.codexConversation?.projectPath == path }.sorted {
            guard let a = $0.codexConversation, let b = $1.codexConversation else { return $0.name < $1.name }
            return a.title == b.title ? a.id < b.id : a.title < b.title
        }.map(latestCodexProfile)
    }

    private func latestCodexProfile(_ candidate: WorkspaceProfile) -> WorkspaceProfile {
        guard var saved = settings.workspaces.first(where: { $0.id == candidate.id }) else { return candidate }
        if saved.codexConversation != candidate.codexConversation || saved.appPath != candidate.appPath { saved.binding = nil }
        saved.codexConversation = candidate.codexConversation
        saved.codexThreadURL = candidate.codexThreadURL
        saved.appPath = candidate.appPath
        return saved
    }

    func configureCodex() {
        guard canEdit else { return }
        guard let app = adapter.installedTools().first(where: { $0.bundleIdentifier == "com.openai.codex" }),
              let path = app.appPath else {
            codexSetupStatus = "未找到 Codex 桌面版；安装后重新配置。"
            codexChecks["installation"] = codexSetupStatus
            return
        }
        codexChecks["installation"] = "已检测到 Codex 桌面版"
        codexSetupStatus = "正在读取本机会话目录…"
        pendingSend = nil
        operationInProgress = true
        operationGeneration += 1
        let generation = operationGeneration
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                let conversations = try await self.codexCatalog.listConversations(appPath: path)
                try Task.checkCancellation()
                guard self.operationGeneration == generation, !self.voice.isBusy else {
                    throw ControlError.message("状态已变化；本次配置已取消。")
                }
                var profiles: [WorkspaceProfile] = []
                for conversation in conversations {
                    // A legacy/manual workspace must never donate its draft identity.
                    let matches = self.settings.workspaces.filter {
                        $0.codexConversation?.id == conversation.id &&
                        $0.codexConversation?.projectPath == conversation.projectPath
                    }
                    guard matches.count <= 1 else {
                        throw ControlError.message("同一会话存在多个配置；请先从已有工作区中明确选择。")
                    }
                    let cached = self.codexCatalogProfiles.first {
                        $0.codexConversation?.id == conversation.id && $0.codexConversation?.projectPath == conversation.projectPath
                    }
                    var profile = matches.first ?? cached ?? WorkspaceProfile(
                        name: String(("Codex · " + conversation.title).prefix(120)),
                        bundleIdentifier: "com.openai.codex", appPath: path,
                        buttonActions: CodingToolPreset.codexConversationActions)
                    if profile.codexConversation != conversation { profile.binding = nil }
                    profile.codexConversation = conversation
                    profile.codexThreadURL = conversation.canonicalURL.absoluteString
                    profile.appPath = path
                    profiles.append(profile)
                }
                self.codexConversations = conversations
                self.codexCatalogProfiles = profiles
                if !self.codexProjectPaths.contains(self.codexProjectPath) {
                    let selected = self.workspace?.codexConversation?.projectPath
                    self.codexProjectPath = selected.flatMap { self.codexProjectPaths.contains($0) ? $0 : nil } ?? self.codexProjectPaths.first ?? ""
                }
                self.codexChecks["catalog"] = "已读取 \(conversations.count) 个本机会话；当前运行状态待检查"
                self.codexSetupStatus = conversations.isEmpty ? "没有可用的本机会话。请先在 Codex 创建或打开一个会话，再重新配置。" :
                    "方案已准备：上下切换同项目会话，左右切换项目。选择会话后自动配置并检查输入框。"
            } catch is CancellationError { self.codexSetupStatus = "配置已取消，已有配置和草稿保留。" }
            catch { self.codexSetupStatus = "未完成配置：\(error.localizedDescription)" }
        }
    }

    func openCodexSession(_ id: UUID) {
        guard canEdit,
              let candidate = codexCatalogProfiles.first(where: { $0.id == id }) ?? settings.workspaces.first(where: { $0.id == id }),
              let conversation = candidate.codexConversation else { return }
        var proposed = settings
        if let index = proposed.workspaces.firstIndex(where: { $0.id == id }) {
            // Preserve customized mappings and shortcuts on later catalog refreshes.
            proposed.workspaces[index] = latestCodexProfile(candidate)
        } else { proposed.workspaces.append(candidate) }
        guard proposed == settings || persist(proposed),
              let profile = settings.workspaces.first(where: { $0.id == id }) else { return }
        let changedSession = voice.workspaceID != id
        selectWorkspaceLocally(id)
        guard voice.workspaceID == id else { return }
        if changedSession {
            codexChecks["input"] = nil
            codexChecks["submission"] = nil
        }
        codexProjectPath = conversation.projectPath
        lastCodexSession[conversation.projectPath] = id
        pendingSend = nil
        engine.reset()
        codexChecks["navigation"] = "已选择会话，正在检查实际窗口和输入框…"
        installOperationGuard(profile, review: nil)
        operationInProgress = true
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                let binding = try await self.adapter.openCodexConversation(profile, knownConversations: self.codexConversations)
                try Task.checkCancellation()
                guard !self.voice.isBusy, self.workspace == profile else {
                    throw ControlError.message("切换期间目标或收音状态已变化；草稿保留，未继续输入。")
                }
                var updated = self.settings
                guard let index = updated.workspaces.firstIndex(where: { $0.id == id }) else { return }
                updated.workspaces[index].binding = binding
                guard self.persist(updated) else { return }
                self.codexChecks["navigation"] = "已核对所选会话并聚焦输入框"
                self.status = "已进入 \(conversation.title)。按住语音键说话，松开后按确认输入。"
            } catch is CancellationError {
                self.codexChecks["navigation"] = "切换已取消；实际窗口状态待重新检查"
                self.status = "切换已取消，所选会话的草稿已保留。"
            } catch {
                self.codexChecks["navigation"] = "未验证：\(error.localizedDescription)"
                self.status = "未完成会话检查：\(error.localizedDescription)。可保留草稿，复制后手动使用。"
            }
        }
    }

    func checkCodexSession() {
        guard let id = workspace?.id, workspace?.codexConversation != nil else {
            codexChecks["navigation"] = "请先从会话列表选择一个目标。"; return
        }
        openCodexSession(id)
    }
    private func moveCodexConversation(_ offset: Int) {
        guard let profile = workspace, let conversation = profile.codexConversation else {
            status = "请先一键配置 Codex 并明确选择一个会话。"; return
        }
        let sessions = orderedCodexProfiles(in: conversation.projectPath)
        guard let current = sessions.firstIndex(where: { $0.id == profile.id }) else {
            status = "当前会话不在目录中，请刷新后重新选择。"; return
        }
        let next = current + offset
        guard sessions.indices.contains(next) else { status = "已到当前项目会话列表的边界。"; return }
        openCodexSession(sessions[next].id)
    }
    private func moveCodexProject(_ offset: Int) {
        guard let path = workspace?.codexConversation?.projectPath,
              let current = codexProjectPaths.firstIndex(of: path) else { return }
        let next = current + offset
        guard codexProjectPaths.indices.contains(next) else { status = "已到 Codex 项目列表的边界。"; return }
        let destination = codexProjectPaths[next]
        let sessions = orderedCodexProfiles(in: destination)
        guard let selected = sessions.first(where: { $0.id == lastCodexSession[destination] }) ?? sessions.first else { return }
        openCodexSession(selected.id)
    }

    private func confirmCodexInput() {
        guard let profile = workspace, profile.codexConversation != nil else {
            status = "确认输入用于一键配置的 Codex 会话。"; return
        }
        if pendingSend != nil { confirmSend(); return }
        let draft = voice.draft.text
        let review = DraftReview(workspaceID: profile.id, draft: draft)
        installOperationGuard(profile, review: review)
        operationInProgress = true
        activeOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            var inserted = false
            do {
                let text: String
                try self.requireCodexInputReady(profile, draft: draft)
                if let receipt = self.insertion[profile.id] {
                    guard receipt.draft == draft else {
                        throw ControlError.message("草稿已变化，目标中可能保留之前插入的内容；请检查后手动使用，避免重复追加。")
                    }
                    text = receipt.text
                } else {
                    text = try await self.insertManagedDraft(draft, for: profile)
                    self.insertion[profile.id] = (draft, text)
                    self.codexChecks["input"] = "草稿已插入，并完成全文核对"
                }
                inserted = true
                guard self.hid.isExclusive, self.suppressionConfirmed else {
                    throw ControlError.message("提交前请完成遥控器独占接管与本次按键验收。")
                }
                self.installOperationGuard(profile, review: review, requiresDevice: true)
                let confirmation = try await self.adapter.prepareSend(for: profile)
                try Task.checkCancellation()
                guard confirmation.text == text, self.workspace == profile,
                      review.matches(workspaceID: self.voice.workspaceID, draft: self.voice.draft.text, busy: self.voice.isBusy),
                      self.hid.isExclusive, self.suppressionConfirmed else {
                    throw ControlError.message("目标或输入内容已变化，请检查后重新确认。")
                }
                self.pendingSend = SendPreview(confirmation: confirmation, review: review, workspace: profile)
                self.codexChecks["submission"] = confirmation.kind == .steer ? "Steer 检查通过；等待明确确认，尚未补充" : "发送检查通过；等待明确确认，尚未发送"
                self.status = self.codexChecks["submission"] ?? "等待确认"
                self.showWindow()
            } catch is CancellationError { self.status = "确认输入已取消；请检查草稿和目标输入框。" }
            catch {
                self.status = (inserted ? "输入已保留；未提交：" : "未完成确认输入：") + error.localizedDescription
                self.codexChecks["submission"] = self.status
            }
        }
    }

    private func requireCodexInputReady(_ profile: WorkspaceProfile, draft: String) throws {
        guard !uncertainCodexInsertion.contains(profile.id) else {
            throw ControlError.message("上次插入结果尚未确认；已阻止再次追加。请在 Codex 检查并手动处理保留的文字。")
        }
        if let previous = codexSubmission[profile.id], !previous.confirmed || !codexClearedAfterSubmission.contains(profile.id) {
            throw ControlError.message(previous.confirmed
                ? "这份草稿已提交；如需新指令，请先清空草稿再重新说话。"
                : "上次提交结果尚未确认；已阻止重发。请在 Codex 检查并手动处理。")
        }
    }
    private func insertManagedDraft(_ draft: String, for profile: WorkspaceProfile) async throws -> String {
        try requireCodexInputReady(profile, draft: draft)
        let text = try await adapter.insert(draft, for: profile, willWrite: { [weak self] _ in
            self?.uncertainCodexInsertion.insert(profile.id)
        })
        uncertainCodexInsertion.remove(profile.id)
        return text
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
        let before = mapping
        var edited = before
        edit(&edited)
        guard edited.button == selectedButton else { return false }
        return updateSettings { settings in
            guard let i = settings.mappings.firstIndex(where: { $0.button == selectedButton }) else { return }
            // Calibration belongs to the device; actions belong to the chosen workspace.
            settings.mappings[i].input = edited.input
            if edited.input?.supportsHold == false { settings.mappings[i].long = nil }
            guard before.single != edited.single || before.long != edited.long || before.double != edited.double else { return }
            if let index = settings.workspaces.firstIndex(where: { $0.id == voice.workspaceID }) {
                var actions = settings.workspaces[index].buttonActions ?? settings.mappings.map(ButtonActionMapping.init)
                guard let actionIndex = actions.firstIndex(where: { $0.button == selectedButton }) else { return }
                // Preserve inactive long-press intentions unless that field was explicitly edited.
                if before.single != edited.single { actions[actionIndex].single = edited.single }
                if before.long != edited.long { actions[actionIndex].long = edited.long }
                if before.double != edited.double { actions[actionIndex].double = edited.double }
                settings.workspaces[index].buttonActions = actions
            } else {
                settings.mappings[i] = edited
            }
        }
    }
    func restoreButtonDefaults() {
        updateSettings { config in
            if let index = config.workspaces.firstIndex(where: { $0.id == voice.workspaceID }) {
                config.workspaces[index].buttonActions = config.workspaces[index].codexConversation != nil
                    ? CodingToolPreset.codexConversationActions : NativeSettings.defaultMappings.map(ButtonActionMapping.init)
            } else {
                config.mappings = NativeSettings.defaultMappings.map { original in
                    var restored = original
                    restored.input = config.mappings.first { $0.button == original.button }?.input
                    if restored.input?.supportsHold == false { restored.long = nil }
                    return restored
                }
            }
        }
    }
    @discardableResult
    func applyToolPreset(to profile: WorkspaceProfile) -> Bool {
        guard let current = settings.workspaces.first(where: { $0.id == profile.id }),
              let preset = CodingToolPreset.matching(bundleIdentifier: current.bundleIdentifier) else { return false }
        return updateSettings { config in
            guard let index = config.workspaces.firstIndex(where: { $0.id == current.id }) else { return }
            config.workspaces[index].buttonActions = current.codexConversation != nil ? CodingToolPreset.codexConversationActions : preset.buttonActions
            config.workspaces[index].shortcuts = []
        }
    }
    func updateWorkspace(_ proposed: WorkspaceProfile) {
        updateSettings { config in
            if let index = config.workspaces.firstIndex(where: { $0.id == proposed.id }) { config.workspaces[index] = proposed }
        }
    }
    func addWorkspace(_ tool: InstalledTool) {
        let profile = WorkspaceProfile(name: tool.name, bundleIdentifier: tool.bundleIdentifier, appPath: tool.appPath,
                                       buttonActions: CodingToolPreset.matching(bundleIdentifier: tool.bundleIdentifier)?.buttonActions)
        if updateSettings({ $0.workspaces.append(profile) }) { selectWorkspace(profile.id) }
    }
    func duplicateWorkspace(_ source: WorkspaceProfile) {
        guard source.codexConversation == nil else {
            status = "每个 Codex 会话已有独立草稿；请从会话列表选择其他会话。"; return
        }
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
                let saved = updateSettings { config in
                    guard let index = config.mappings.firstIndex(where: { $0.button == button }) else { return }
                    config.mappings[index].input = learned
                    if !learned.supportsHold { config.mappings[index].long = nil }
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
        var routedMapping = settings.effectiveMapping(for: mapping.button, workspaceID: voice.workspaceID)
        if showingWorkspaces || showingActions || pendingSend != nil {
            // Physical navigation remains available even if its normal action is disabled/remapped.
            routedMapping.single = .actionPicker
            routedMapping.long = nil
            routedMapping.double = nil
            routedMapping.input?.supportsHold = false
        }
        route(engine.process(button: mapping.button, isDown: down,
                             at: ProcessInfo.processInfo.systemUptime, mapping: routedMapping))
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
        route(engine.advance(to: now))
    }
    private func route(_ events: [GestureTrigger]) {
        let sourceWorkspace = voice.workspaceID
        let sourceGeneration = operationGeneration
        for event in events {
            // Resetting the engine cannot retract a batch it has already returned.
            guard voice.workspaceID == sourceWorkspace, operationGeneration == sourceGeneration else { return }
            route(event)
        }
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
        case .previousConversation, .nextConversation:
            moveCodexConversation(action == .previousConversation ? -1 : 1)
        case .confirmInput:
            confirmCodexInput()
        case .previousWorkspace, .nextWorkspace:
            if workspace?.codexConversation != nil {
                moveCodexProject(action == .previousWorkspace ? -1 : 1)
                return
            }
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
                    let inserted: String
                    if profile.codexConversation != nil {
                        try self.requireCodexInputReady(profile, draft: draft)
                        guard self.insertion[profile.id] == nil else {
                            throw ControlError.message("此会话已有插入记录；请使用「确认输入」核对，避免重复追加。")
                        }
                        inserted = try await self.insertManagedDraft(draft, for: profile)
                    } else { inserted = try await self.adapter.insert(draft, for: profile) }
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
                if profile.codexConversation != nil { try self.requireCodexInputReady(profile, draft: self.voice.draft.text) }
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
                if current.codexConversation != nil { try self.requireCodexInputReady(current, draft: pending.review.draft) }
                let outcome = try await self.adapter.confirmSend(pending.confirmation, for: current, willSubmit: { [weak self] in
                    guard current.codexConversation != nil else { return }
                    self?.codexSubmission[current.id] = (pending.review.draft, false)
                    self?.codexClearedAfterSubmission.remove(current.id)
                })
                if current.codexConversation != nil { self.codexSubmission[current.id] = (pending.review.draft, outcome.confirmed) }
                self.insertion[current.id] = nil
                self.status = outcome.message
                if current.codexConversation != nil { self.codexChecks["submission"] = outcome.message }
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
        if let profile = workspace, profile.codexConversation != nil { openCodexSession(profile.id); return }
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
