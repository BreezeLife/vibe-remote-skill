import AppKit
import ApplicationServices
import Foundation
import VibeRemoteCore

struct ToolApplication: Equatable {
    var bundleIdentifier: String
    var path: String
    var version: String
    var processID: Int32?
}

struct InstalledTool: Identifiable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let appPath: String?
    let version: String?
    var isInstalled: Bool { appPath != nil }
}

// Values and chat contents never enter the tree, saved locators or diagnostic messages.
// Only the exact verified input's value is read separately, while executing an explicit action.
struct ToolAXNode {
    var id: String
    var role: String
    var identifier: String? = nil
    var label: String? = nil
    var editable: Bool = false
    var secure: Bool = false
    var enabled: Bool? = nil
    var actions: [String] = []
    var visible: Bool? = nil
    var contentScopeID: String? = nil
    var inNavigation: Bool = false
    var selected: Bool? = nil
    var shortcutKeyCode: UInt16? = nil
    var shortcutModifiers: [KeyModifier]? = nil
    var scrollPosition: Double? = nil
    var documentURL: String? = nil
    var url: String? = nil
    var subrole: String? = nil
    var modal: Bool? = nil
    var children: [ToolAXNode] = []
}

struct ToolAXObservation {
    var processID: Int32
    var frontmostPID: Int32?
    var focusedWindowID: String?
    var focusedNodeID: String?
    var pointerNodeID: String?
    var windows: [ToolAXNode]
    var complete: Bool
}

@MainActor protocol ToolAXDriver: AnyObject {
    var isTrusted: Bool { get }
    func requestPermission()
    func installedApplication(bundleIdentifier: String) -> ToolApplication?
    func application(bundleIdentifier: String, appPath: String?) throws -> ToolApplication
    func application(at url: URL) throws -> ToolApplication
    func activate(_ application: ToolApplication) async throws
    func openURL(_ url: URL, for application: ToolApplication) async throws
    func snapshot(_ application: ToolApplication) throws -> ToolAXObservation
    func value(of node: ToolAXNode) throws -> String
    func setValue(_ value: String, of node: ToolAXNode) throws
    func focus(_ node: ToolAXNode) throws
    func perform(_ action: String, on node: ToolAXNode) throws
    func pressShortcut(_ shortcut: ActionShortcut, processID: Int32) throws
}

extension ToolAXDriver {
    func openURL(_ url: URL, for application: ToolApplication) async throws {
        throw ToolAdapterError("此辅助功能后端不支持明确会话导航。")
    }
    func pressShortcut(_ shortcut: ActionShortcut, processID: Int32) throws {
        throw ToolAdapterError("此辅助功能后端不支持经过验证的快捷键。")
    }
}

struct ToolAdapterError: LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
}

enum ToolLearningSource { case pointer, focused }
enum ToolControlKind { case send, stop }
enum ToolScrollDirection { case up, down }
enum ToolSubmissionKind { case send, steer }

struct LearnedToolInput {
    let workspaceID: UUID
    let application: ToolApplication
    let windowTitle: String
    let input: AXLocator
}

struct ToolSendConfirmation: Identifiable {
    let id: UUID
    let text: String
    let workspaceID: UUID
    let workspaceName: String
    let kind: ToolSubmissionKind
    fileprivate let control: AXLocator
    fileprivate let workspace: WorkspaceProfile
    fileprivate let application: ToolApplication
}

struct ToolActionOutcome {
    let message: String
    let confirmed: Bool
}

struct ToolCapability: Identifiable {
    var id: String { action.rawValue }
    let action: RemoteAction
    let available: Bool
    let reason: String
}

@MainActor final class ToolAdapter {
    private let driver: ToolAXDriver
    private var pendingConfirmation: UUID?
    private let navigationTimeout: TimeInterval
    // A saved title/project binding never establishes catalog uniqueness after relaunch.
    private var uniqueCodexTitles: [UUID: CodexConversation] = [:]
    // Coordinator provides current capture/draft/workspace/device authorization per serialized operation.
    var authorizeOperation: (() throws -> Void)?
    init(driver: ToolAXDriver, navigationTimeout: TimeInterval = 2) {
        self.driver = driver
        self.navigationTimeout = min(5, max(0.01, navigationTimeout.isFinite ? navigationTimeout : 2))
    }
    convenience init() { self.init(driver: SystemToolAXDriver()) }
    var permissionGranted: Bool { driver.isTrusted }
    func requestPermission() { driver.requestPermission() }

    func openCodexConversation(_ workspace: WorkspaceProfile, knownConversations: [CodexConversation]) async throws -> ToolBinding {
        pendingConfirmation = nil
        uniqueCodexTitles[workspace.id] = nil
        guard workspace.bundleIdentifier == "com.openai.codex", let conversation = workspace.codexConversation else {
            throw fail("请先选择明确的 Codex 会话。")
        }
        try conversation.validate()
        guard knownConversations.filter({ $0.id == conversation.id }) == [conversation] else {
            throw fail("会话目录已变化，无法自动绑定；请刷新后重试。")
        }
        let uniqueTitle = knownConversations.filter { $0.title == conversation.title && $0.projectPath == conversation.projectPath }.count == 1
        let requestedApp = try application(for: workspace)
        try authorizeMutation()
        try await driver.openURL(conversation.canonicalURL, for: requestedApp)
        try authorizeMutation()
        let deadline = ProcessInfo.processInfo.systemUptime + navigationTimeout
        var lastError: Error = fail("尚未观察到目标会话。")
        var openedApp: ToolApplication?
        var discovered: (application: ToolApplication, binding: ToolBinding)?
        repeat {
            try authorizeMutation()
            let app = try application(for: workspace)
            guard app.path == requestedApp.path, app.version == requestedApp.version,
                  requestedApp.processID == nil || app.processID == requestedApp.processID,
                  openedApp == nil || openedApp == app else {
                throw fail("导航期间应用身份或进程已变化，未绑定目标。")
            }
            if app.processID != nil { openedApp = app }
            do {
                let observation = try observed(app)
                let binding = try discoverCodexBinding(conversation, app: app, observation: observation,
                                                       previous: workspace.binding, uniqueTitle: uniqueTitle)
                discovered = (app, binding)
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
            try authorizeMutation()
            if discovered != nil { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        guard let discovered else {
            throw fail("已请求打开会话，但无法验证目标；请手动绑定。\(lastError.localizedDescription)")
        }
        var candidate = workspace
        candidate.binding = discovered.binding
        if uniqueTitle { uniqueCodexTitles[workspace.id] = conversation }
        var completed = false
        defer { if !completed { uniqueCodexTitles[workspace.id] = nil } }
        try authorizeMutation()
        // Retry observations above, never the focus mutation itself.
        try focusInput(candidate)
        let final = try verified(candidate, requireFocusedInput: true)
        guard final.application == discovered.application else { throw fail("聚焦期间应用身份已变化。") }
        let anchor = try resolve(discovered.binding.taskAnchor, in: final.window, purpose: "会话标识")
        let evidence = try conversationEvidence(conversation, window: final.window, input: final.input, anchor: anchor)
        guard evidence.thread || (evidence.project && uniqueTitle) else { throw fail("聚焦后会话身份已无法验证。") }
        completed = true
        return discovered.binding
    }

    private func discoverCodexBinding(_ conversation: CodexConversation, app: ToolApplication,
                                      observation: ToolAXObservation, previous: ToolBinding?, uniqueTitle: Bool) throws -> ToolBinding {
        guard let window = observation.windows.first(where: { $0.id == observation.focusedWindowID }),
              let title = window.label, !title.isEmpty,
              observation.windows.filter({ $0.label == title }).count == 1 else {
            throw fail("当前窗口没有唯一稳定标题。")
        }
        try rejectModal(observation)
        let entries = flattened(window)
        let inputs = entries.filter {
            ["AXTextArea", "AXTextField", "AXComboBox"].contains($0.node.role) && $0.node.editable &&
            !$0.node.secure && $0.node.enabled == true && $0.node.visible == true &&
            !$0.node.inNavigation && $0.node.contentScopeID != nil
        }
        guard inputs.count == 1, let input = inputs.first else { throw fail("没有唯一可验证的 AI 输入框。") }
        try requireInput(input.node, in: window)
        let anchors = entries.filter {
            $0.node.label == conversation.title && (try? requireCurrentAnchor($0.node, input: input.node)) != nil
        }
        guard anchors.count == 1, let anchor = anchors.first else { throw fail("当前主内容区没有唯一且完全匹配的会话标题。") }
        let evidence = try conversationEvidence(conversation, window: window, input: input.node, anchor: anchor.node)
        guard evidence.thread || (evidence.project && uniqueTitle) else { throw fail("缺少当前会话 ID，且标题/项目无法唯一确定目标。") }
        func control(_ kind: ToolControlKind) -> AXLocator? {
            let matches = entries.filter { (try? requireControl($0.node, kind: kind, input: input.node)) != nil }
            guard matches.count == 1, let entry = matches.first else { return nil }
            return makeLocator(entry.node, path: entry.path)
        }
        // Keep separately learned controls when the same live conversation/input is established,
        // including a Stop control which legitimately disappears while the task is idle.
        let reusable = previous.flatMap { binding -> ToolBinding? in
            guard binding.appVersion == app.version, sameIdentity(input.node, binding.input),
                  sameIdentity(anchor.node, binding.taskAnchor) else { return nil }
            return binding
        }
        return ToolBinding(appVersion: app.version, windowTitle: title,
                           input: makeLocator(input.node, path: input.path), taskAnchor: makeLocator(anchor.node, path: anchor.path),
                           sendControl: control(.send) ?? reusable?.sendControl, stopControl: control(.stop) ?? reusable?.stopControl)
    }

    /// Only document/container ancestors of this input describe its current destination.
    /// Sidebar links and URLs inside conversation messages never establish current identity.
    private func conversationEvidence(_ conversation: CodexConversation, window: ToolAXNode,
                                      input: ToolAXNode, anchor: ToolAXNode) throws -> (thread: Bool, project: Bool) {
        guard let entry = flattened(window).first(where: { $0.node.id == input.id }) else { throw fail("输入位置已变化。") }
        var contexts = [window]
        var node = window
        for index in entry.path.dropLast() {
            node = node.children[index]
            if !node.inNavigation && (node.id == input.contentScopeID || ["AXWebArea", "AXDocument"].contains(node.role)) {
                contexts.append(node)
            }
        }
        var threads = Set<String>(), projects = Set<String>()
        func record(_ value: String) {
            guard let url = URL(string: value) else { return }
            if url.scheme == "codex", url.host == "threads", url.query == nil, url.fragment == nil {
                let parts = url.path.split(separator: "/")
                if parts.count == 1, let id = UUID(uuidString: String(parts[0])) { threads.insert(id.uuidString.lowercased()) }
            } else if url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" {
                projects.insert(url.standardizedFileURL.path)
            }
        }
        for context in contexts {
            if let value = context.documentURL { record(value) }
            if let value = context.url { record(value) }
        }
        // An exact UUID on the current title/container is useful; opaque IDs are not guessed.
        for context in contexts + [anchor] {
            if let identifier = context.identifier, let id = UUID(uuidString: identifier) {
                threads.insert(id.uuidString.lowercased())
            }
        }
        guard threads.isEmpty || threads == [conversation.id.lowercased()] else { throw fail("当前会话 ID 与所选会话不一致。") }
        guard projects.isEmpty || projects == [conversation.projectPath] else { throw fail("当前项目路径与所选会话不一致。") }
        return (!threads.isEmpty, !projects.isEmpty)
    }

    private func rejectModal(_ observation: ToolAXObservation) throws {
        let nodes: [ToolAXNode] = observation.windows.flatMap { window in flattened(window).map { $0.node } }
        let blocked = nodes.contains { node in
            guard node.visible != false else { return false }
            return node.modal == true || node.role == "AXSheet" || node.subrole == "AXDialog" || node.subrole == "AXSystemDialog"
        }
        guard !blocked else { throw fail("应用存在对话框或批准提示，请先在工具中处理。") }
    }

    func installedTools() -> [InstalledTool] {
        [("Codex", "com.openai.codex"), ("Claude Desktop", "com.anthropic.claudefordesktop"),
         ("WorkBuddy", "com.tencent.workbuddy.mac"), ("WorkBuddy AI", "com.workbuddy.workbuddy-ai")].map { name, identifier in
            let app = driver.installedApplication(bundleIdentifier: identifier)
            return InstalledTool(name: name, bundleIdentifier: identifier, appPath: app?.path, version: app?.version)
        }
    }

    func application(at url: URL) throws -> InstalledTool {
        let app = try driver.application(at: url)
        try rejectTerminal(app.bundleIdentifier)
        return InstalledTool(name: url.deletingPathExtension().lastPathComponent,
                             bundleIdentifier: app.bundleIdentifier, appPath: app.path, version: app.version)
    }

    func learnInput(for workspace: WorkspaceProfile) throws -> LearnedToolInput {
        let app = try application(for: workspace)
        let observation = try observed(app)
        guard let window = observation.windows.first(where: { $0.id == observation.focusedWindowID }),
              let title = window.label, !title.isEmpty else { throw fail("目标窗口没有稳定标题，无法绑定。") }
        guard observation.windows.filter({ $0.label == title }).count == 1 else { throw fail("多个窗口标题相同，无法唯一绑定。") }
        guard let inputID = observation.focusedNodeID,
              let entry = flattened(window).first(where: { $0.node.id == inputID }) else {
            throw fail("请先在目标应用中点击 AI 输入框，再学习输入。")
        }
        try requireInput(entry.node, in: window)
        let locator = makeLocator(entry.node, path: entry.path)
        _ = try resolve(locator, in: window, purpose: "输入框")
        return LearnedToolInput(workspaceID: workspace.id, application: app, windowTitle: title, input: locator)
    }

    func learnTaskAnchor(for workspace: WorkspaceProfile, input: LearnedToolInput,
                         source: ToolLearningSource = .pointer) throws -> ToolBinding {
        let app = try application(for: workspace)
        guard input.workspaceID == workspace.id, input.application == app else { throw fail("应用或工作区已变化，请重新学习输入框。") }
        let observation = try observed(app)
        let window = try boundWindow(input.windowTitle, observation)
        let inputNode = try resolve(input.input, in: window, purpose: "输入框")
        try requireInput(inputNode, in: window)
        let entry = try selected(source, observation, window)
        guard entry.node.id != inputNode.id, !entry.node.editable, !entry.node.secure,
              !["AXWindow", "AXApplication", "AXWebArea"].contains(entry.node.role),
              entry.node.label?.isEmpty == false || entry.node.identifier?.isEmpty == false else {
            throw fail("会话标识必须是独立、非编辑的任务名称或标题，不能使用输入框或整个窗口。")
        }
        let anchor = makeLocator(entry.node, path: entry.path)
        _ = try resolve(anchor, in: window, purpose: "会话标识")
        try requireCurrentAnchor(entry.node, input: inputNode)
        return ToolBinding(appVersion: app.version, windowTitle: input.windowTitle, input: input.input,
                           taskAnchor: anchor, sendControl: nil, stopControl: nil)
    }

    func learnControl(for workspace: WorkspaceProfile, kind: ToolControlKind,
                      source: ToolLearningSource = .pointer) throws -> ToolBinding {
        let target = try verified(workspace)
        let entry = try selected(source, target.observation, target.window)
        try requireControl(entry.node, kind: kind, input: target.input)
        let locator = makeLocator(entry.node, path: entry.path)
        _ = try resolve(locator, in: target.window, purpose: "操作控件")
        var binding = target.binding
        if kind == .send { binding.sendControl = locator } else { binding.stopControl = locator }
        return binding
    }

    // Capability descriptions never turn a saved test result into live authorization.
    func describeCapabilities(for workspace: WorkspaceProfile) -> [ToolCapability] {
        let actions: [RemoteAction] = [.focusTarget, .insertDraft, .sendDraft, .stopTask, .scrollUp, .scrollDown]
        return actions.map { action in
            let reason: String
            if !permissionGranted { reason = "辅助功能未授权" }
            else if workspace.binding == nil { reason = "尚未绑定输入框和会话" }
            else if action == .sendDraft && (workspace.binding?.sendControl == nil || workspace.binding?.stopControl == nil) {
                reason = "需分别学习发送及停止控件以确认空闲状态"
            } else if action == .stopTask && workspace.binding?.stopControl == nil { reason = "尚未学习停止生成控件" }
            else { reason = "已配置；执行前实时检查，尚未代表实际工具验收" }
            return ToolCapability(action: action, available: false, reason: reason)
        }
    }

    func focus(for workspace: WorkspaceProfile) async throws {
        pendingConfirmation = nil
        _ = try await activated(workspace)
        try focusInput(workspace)
    }

    @discardableResult func insert(_ draft: String, for workspace: WorkspaceProfile, willWrite: ((String) -> Void)? = nil) async throws -> String {
        pendingConfirmation = nil
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail("草稿为空。") }
        _ = try await activated(workspace)
        try focusInput(workspace)
        let target = try verified(workspace, requireFocusedInput: true)
        guard !workspace.shortcuts.contains(where: { $0.action == .insertDraft }) else {
            throw fail("插入仅支持经过读回验证的辅助功能写入。")
        }
        let existing = try driver.value(of: target.input)
        let text = existing.isEmpty ? draft : existing + (existing.hasSuffix("\n") ? "" : "\n") + draft
        // Recheck exact text and target immediately before writing: never overwrite intervening typing.
        let current = try verified(workspace, requireFocusedInput: true)
        guard current.application == target.application, try driver.value(of: current.input) == existing else {
            throw fail("输入或目标在插入前已改变，请重新检查。")
        }
        try authorizeMutation()
        willWrite?(text)
        try driver.setValue(text, of: current.input)
        let after = try verified(workspace, requireFocusedInput: true)
        guard after.application == current.application, try driver.value(of: after.input) == text else {
            throw fail("无法确认插入后的全文；草稿已保留，请检查目标输入，勿直接重试。")
        }
        return text
    }

    func prepareSend(for workspace: WorkspaceProfile) async throws -> ToolSendConfirmation {
        pendingConfirmation = nil
        _ = try await activated(workspace)
        try focusInput(workspace)
        let target = try verified(workspace, requireFocusedInput: true)
        let submission = try readySubmission(target, workspace: workspace)
        let text = try driver.value(of: target.input)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail("目标 AI 输入框为空。") }
        let confirmation = ToolSendConfirmation(id: UUID(), text: text, workspaceID: workspace.id,
                                               workspaceName: workspace.name, kind: submission.kind,
                                               control: submission.locator,
                                               workspace: workspace, application: target.application)
        pendingConfirmation = confirmation.id
        return confirmation
    }

    func confirmSend(_ confirmation: ToolSendConfirmation, for workspace: WorkspaceProfile, willSubmit: (() -> Void)? = nil) async throws -> ToolActionOutcome {
        guard pendingConfirmation == confirmation.id else { throw fail("发送确认已失效，请重新预览。") }
        // Consume before any await: cancellation, errors and repeated callbacks cannot reuse approval.
        pendingConfirmation = nil
        guard confirmation.workspace == workspace else { throw fail("工作区或绑定已改变，请重新预览。") }
        _ = try await activated(workspace)
        try focusInput(workspace)
        let target = try verified(workspace, requireFocusedInput: true)
        guard target.application == confirmation.application else { throw fail("应用版本、路径或进程已改变，请重新预览。") }
        let submission = try readySubmission(target, workspace: workspace)
        guard submission.kind == confirmation.kind, submission.locator == confirmation.control else {
            throw fail("提交方式或控件已变化，请重新预览并确认。")
        }
        guard try driver.value(of: target.input) == confirmation.text else { throw fail("待发送全文已改变，请重新预览。") }
        if confirmation.kind == .steer {
            // Steer is an explicit UI action, never an approval or a configured generic Send key.
            try authorizeMutation()
            willSubmit?()
            try driver.perform("AXPress", on: submission.control)
            do {
                let after = try verified(workspace)
                let previous = flattened(after.window).map(\.node).filter { sameIdentity($0, confirmation.control) }
                if after.application == target.application, try driver.value(of: after.input).isEmpty,
                   previous.isEmpty || (previous.count == 1 && previous[0].enabled == false) {
                    return ToolActionOutcome(message: "已观察到输入清空且引导控件变化；请在工具中核对当前任务。", confirmed: true)
                }
            } catch { /* An uncertain result never retries the action. */ }
            return ToolActionOutcome(message: "已触发引导，但尚未确认工具接收；请在工具中检查，勿自动重发。", confirmed: false)
        }
        try execute(.sendDraft, control: submission.control, target: target, workspace: workspace, willMutate: willSubmit)
        // No retry if AXPress succeeds but the outcome is unknown.
        do {
            let after = try verified(workspace)
            let running = workspace.codexConversation != nil && after.binding.stopControl == nil
                ? try observedCodexRunningState(after) : try runningState(after)
            if running && after.application == target.application {
                return ToolActionOutcome(message: "已观察到绑定任务的停止生成控件；仍需在工具中核对回复。", confirmed: true)
            }
        } catch { /* Report uncertain outcome without re-sending. */ }
        return ToolActionOutcome(message: "已触发发送操作，但未观察到任务开始；请在工具中检查，勿自动重发。", confirmed: false)
    }

    func stop(for workspace: WorkspaceProfile) async throws -> ToolActionOutcome {
        pendingConfirmation = nil
        _ = try await activated(workspace)
        let target = try verified(workspace)
        guard try runningState(target), let locator = target.binding.stopControl else { throw fail("未观察到绑定任务正在生成，不能停止。") }
        // Shortcut stops require focused input too; AXPress is directly scoped to the bound control.
        if workspace.shortcuts.contains(where: { $0.action == .stopTask }) { try focusInput(workspace) }
        let current = try verified(workspace)
        guard current.application == target.application, try runningState(current) else { throw fail("任务状态已改变，停止操作已取消。") }
        let stop = try resolve(locator, in: current.window, purpose: "停止控件")
        try requireControl(stop, kind: .stop, input: current.input)
        try execute(.stopTask, control: stop, target: current, workspace: workspace)
        do {
            let after = try verified(workspace)
            let running = try runningState(after)
            if after.application == current.application && !running {
                return ToolActionOutcome(message: "已观察到绑定任务的停止生成控件消失或禁用。", confirmed: true)
            }
        } catch { /* No blind second stop. */ }
        return ToolActionOutcome(message: "已触发停止操作，但任务是否停止尚未确认；请在工具中检查。", confirmed: false)
    }

    func scroll(_ direction: ToolScrollDirection, for workspace: WorkspaceProfile) async throws {
        pendingConfirmation = nil
        _ = try await activated(workspace)
        let target = try verified(workspace)
        let action = direction == .up ? "AXScrollUp" : "AXScrollDown"
        let semantic: RemoteAction = direction == .up ? .scrollUp : .scrollDown
        let shortcut = workspace.shortcuts.first(where: { $0.action == semantic })
        let areas = flattened(target.window).map(\.node).filter {
            $0.role == "AXScrollArea" && (shortcut != nil || $0.actions.contains(action))
        }
        guard areas.count == 1 else { throw fail("无法唯一确认支持辅助功能滚动的区域，请在目标应用中手动滚动。") }
        try authorizeMutation()
        if let shortcut {
            guard shortcut.isSupported else { throw fail("滚动快捷键不受支持。") }
            try driver.focus(areas[0])
            let focused = try verified(workspace)
            guard focused.application == target.application, focused.observation.focusedNodeID == areas[0].id else {
                throw fail("无法确认焦点位于绑定窗口的滚动区域，未触发快捷键。")
            }
            try authorizeMutation()
            try driver.pressShortcut(shortcut, processID: target.observation.processID)
        } else { try driver.perform(action, on: areas[0]) }
        let after = try verified(workspace)
        let changed = flattened(after.window).map(\.node).first { $0.id == areas[0].id }
        guard let beforePosition = areas[0].scrollPosition, let afterPosition = changed?.scrollPosition,
              beforePosition != afterPosition else { throw fail("已触发滚动，但位置变化未确认（可能已到边界）。") }
    }

    private struct Target {
        let application: ToolApplication
        let binding: ToolBinding
        let observation: ToolAXObservation
        let window: ToolAXNode
        let input: ToolAXNode
    }
    private func fail(_ reason: String) -> ToolAdapterError { ToolAdapterError(reason) }
    private func authorizeMutation() throws {
        try Task.checkCancellation()
        try authorizeOperation?()
    }
    private func rejectTerminal(_ identifier: String) throws {
        let lower = identifier.lowercased()
        let known = ["terminal", "iterm", "warp", "alacritty", "kitty", "wezterm", "ghostty", "hyperterm"]
        guard !known.contains(where: { lower.contains($0) }) else { throw fail("终端或 shell 目标不支持桌面发送，请使用独立 CLI 适配器。") }
    }
    private func application(for workspace: WorkspaceProfile) throws -> ToolApplication {
        guard driver.isTrusted else { throw fail("辅助功能尚未授权，请在连接与权限页明确启用。") }
        try rejectTerminal(workspace.bundleIdentifier)
        let app = try driver.application(bundleIdentifier: workspace.bundleIdentifier, appPath: workspace.appPath)
        guard app.bundleIdentifier == workspace.bundleIdentifier, !app.version.isEmpty else { throw fail("应用身份或版本无法验证。") }
        return app
    }
    private func observed(_ app: ToolApplication) throws -> ToolAXObservation {
        let observation = try driver.snapshot(app)
        guard observation.complete else { throw fail("辅助功能树过大或读取不完整，无法排除歧义。") }
        guard observation.frontmostPID == observation.processID, app.processID == observation.processID else {
            throw fail("目标应用尚未成为前台进程，操作已阻止。")
        }
        return observation
    }
    private func activated(_ workspace: WorkspaceProfile) async throws -> Target {
        let app = try application(for: workspace)
        try authorizeMutation()
        try await driver.activate(app)
        try authorizeMutation()
        return try verified(workspace)
    }
    private func boundWindow(_ title: String, _ observation: ToolAXObservation) throws -> ToolAXNode {
        let matches = observation.windows.filter { $0.label == title }
        guard matches.count == 1 else { throw fail("绑定窗口已消失、改名或存在多个同名窗口，请重新学习。") }
        guard matches[0].id == observation.focusedWindowID else { throw fail("当前窗口不是绑定窗口，请在目标应用中选择正确窗口。") }
        return matches[0]
    }
    private func verified(_ workspace: WorkspaceProfile, requireFocusedInput: Bool = false) throws -> Target {
        let app = try application(for: workspace)
        guard let binding = workspace.binding else { throw fail("请先学习输入框和会话标识。") }
        guard binding.appVersion == app.version else { throw fail("应用版本已改变，旧绑定已停用，请重新学习。") }
        let observation = try observed(app)
        let window = try boundWindow(binding.windowTitle, observation)
        let input = try resolve(binding.input, in: window, purpose: "输入框")
        try requireInput(input, in: window)
        let anchor = try resolve(binding.taskAnchor, in: window, purpose: "会话标识")
        guard anchor.id != input.id, !anchor.editable, !anchor.secure,
              !["AXWindow", "AXApplication", "AXWebArea"].contains(anchor.role),
              anchor.label?.isEmpty == false || anchor.identifier?.isEmpty == false else {
            throw fail("绑定会话标识不再是独立稳定的任务名称，请重新学习。")
        }
        try requireCurrentAnchor(anchor, input: input)
        if workspace.bundleIdentifier == "com.openai.codex", let conversation = workspace.codexConversation {
            try conversation.validate()
            try rejectModal(observation)
            let evidence = try conversationEvidence(conversation, window: window, input: input, anchor: anchor)
            guard evidence.thread || (evidence.project && uniqueCodexTitles[workspace.id] == conversation) else {
                throw fail("当前 Codex 会话身份已无法验证，请重新检查。")
            }
        }
        if requireFocusedInput && observation.focusedNodeID != input.id { throw fail("无法确认焦点位于绑定 AI 输入框。") }
        return Target(application: app, binding: binding, observation: observation, window: window, input: input)
    }
    private func focusInput(_ workspace: WorkspaceProfile) throws {
        let target = try verified(workspace)
        if target.observation.focusedNodeID != target.input.id {
            try authorizeMutation()
            if let shortcut = workspace.shortcuts.first(where: { $0.action == .focusTarget }) {
                guard shortcut.isSupported else { throw fail("聚焦快捷键不受支持。") }
                try driver.pressShortcut(shortcut, processID: target.observation.processID)
            } else { try driver.focus(target.input) }
        }
        _ = try verified(workspace, requireFocusedInput: true)
    }
    private func requireInput(_ input: ToolAXNode, in window: ToolAXNode) throws {
        guard ["AXTextArea", "AXTextField", "AXComboBox"].contains(input.role), input.editable,
              !input.secure, input.enabled == true else { throw fail("输入框必须是已启用、可编辑且非密码的辅助功能文本控件。") }
        let path = flattened(window).first(where: { $0.node.id == input.id })?.path ?? []
        var current = window
        let forbidden = ["terminal", "shell", "console", "终端", "控制台"]
        for index in [-1] + path {
            if index >= 0 { current = current.children[index] }
            let identity = ((current.identifier ?? "") + " " + (current.label ?? "")).lowercased()
            guard !forbidden.contains(where: { identity.contains($0) }) else { throw fail("检测到终端或控制台输入，不能作为 AI 输入绑定。") }
        }
    }
    private func requireCurrentAnchor(_ anchor: ToolAXNode, input: ToolAXNode) throws {
        guard anchor.visible == true, input.visible == true, !anchor.inNavigation, !input.inNavigation,
              let scope = input.contentScopeID, scope == anchor.contentScopeID else {
            throw fail("会话标识必须与输入框处于同一可见的主内容区域；侧栏旧任务名称或隐藏内容不能证明当前任务。")
        }
        let heading = ["AXHeading", "AXStaticText"].contains(anchor.role)
        let selectedTask = ["AXRow", "AXTab", "AXRadioButton"].contains(anchor.role) && anchor.selected == true
        guard heading || selectedTask else {
            throw fail("请选择主内容区的任务标题，或带有实时选中状态的任务项。")
        }
    }
    private func flattened(_ root: ToolAXNode, path: [Int] = []) -> [(node: ToolAXNode, path: [Int])] {
        [(root, path)] + root.children.enumerated().flatMap { flattened($0.element, path: path + [$0.offset]) }
    }
    private func makeLocator(_ node: ToolAXNode, path: [Int]) -> AXLocator {
        AXLocator(path: path, role: node.role, identifier: node.identifier, label: node.label)
    }
    private func sameIdentity(_ node: ToolAXNode, _ locator: AXLocator) -> Bool {
        node.role == locator.role && node.identifier == locator.identifier && node.label == locator.label
    }
    private func resolve(_ locator: AXLocator, in window: ToolAXNode, purpose: String) throws -> ToolAXNode {
        var node = window
        for index in locator.path {
            guard index >= 0 && node.children.indices.contains(index) else { throw fail("\(purpose)的结构已变化，请重新学习。") }
            node = node.children[index]
        }
        guard sameIdentity(node, locator), flattened(window).filter({ sameIdentity($0.node, locator) }).count == 1 else {
            throw fail("\(purpose)已变化或存在歧义，请重新学习。")
        }
        return node
    }
    private func selected(_ source: ToolLearningSource, _ observation: ToolAXObservation,
                          _ window: ToolAXNode) throws -> (node: ToolAXNode, path: [Int]) {
        let id = source == .pointer ? observation.pointerNodeID : observation.focusedNodeID
        guard let id, let entry = flattened(window).first(where: { $0.node.id == id }) else {
            throw fail("未在绑定窗口内找到所选控件，请把鼠标移到控件本身后重试。")
        }
        return entry
    }
    private func requireControl(_ control: ToolAXNode, kind: ToolControlKind, input: ToolAXNode) throws {
        guard control.visible == true, !control.inNavigation, let scope = input.contentScopeID,
              control.contentScopeID == scope else {
            throw fail("操作控件必须与已绑定输入框位于同一可见主内容区；隐藏、侧栏或其他任务的按钮不可使用。")
        }
        guard ["AXButton", "AXMenuItem"].contains(control.role), !control.editable,
              !control.secure, control.actions.contains("AXPress") else { throw fail("所选控件不支持明确的辅助功能按下操作。") }
        let label = (control.label ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let sends = ["send", "send message", "send prompt", "submit prompt", "发送", "发送消息", "发送提示", "提交提示"]
        let stops = ["stop generating", "stop generation", "stop response", "stop task", "cancel generation", "停止生成", "停止回复", "停止任务", "取消生成"]
        guard (kind == .send ? sends : stops).contains(label) else {
            throw fail(kind == .send ? "无法从控件名称确认发送语义，请选择明确的发送消息按钮。" : "无法确认停止 AI 生成语义；通用 Stop/页面停止按钮不支持。")
        }
    }
    private func runningState(_ target: Target) throws -> Bool {
        guard let locator = target.binding.stopControl else { throw fail("尚未绑定停止生成控件，AI 运行状态未知。") }
        let matches = flattened(target.window).filter { sameIdentity($0.node, locator) }
        if matches.isEmpty {
            // A renamed/recreated stop is stale evidence, not absence. Inspect only this task's
            // content scope, including controls whose visibility cannot be established.
            let suspicious = flattened(target.window).map(\.node).contains { node in
                guard let scope = target.input.contentScopeID, node.contentScopeID == scope,
                      !node.inNavigation else { return false }
                // Some apps reuse one button for Send/Stop; the separately learned Send identity
                // is checked for enabled state by readySend, and is not a stale Stop identity.
                if let send = target.binding.sendControl, sameIdentity(node, send) { return false }
                if let identifier = locator.identifier, node.identifier == identifier { return true }
                guard node.visible != false, !node.editable, !node.secure,
                      ["AXButton", "AXMenuItem", "AXLink"].contains(node.role) || node.actions.contains("AXPress") else { return false }
                let identity = ((node.label ?? "") + " " + (node.identifier ?? "")).lowercased()
                return ["stop", "cancel", "abort", "interrupt", "terminate", "pause", "停止", "取消", "中止", "终止", "暂停"].contains {
                    identity.contains($0)
                }
            }
            guard !suspicious else { throw fail("停止控件的名称或标识已变化，当前任务状态未知；请重新学习停止控件。") }
            // Only genuine absence in a complete, scoped observation establishes idle here.
            return false
        }
        let control = try resolve(locator, in: target.window, purpose: "停止控件")
        try requireControl(control, kind: .stop, input: target.input)
        guard let enabled = control.enabled else { throw fail("停止控件启用状态未知，无法判断任务状态。") }
        return enabled
    }
    private func readySend(_ target: Target) throws -> ToolAXNode {
        guard !(try runningState(target)) else { throw fail("绑定任务正在生成，不能发送新输入。") }
        guard let locator = target.binding.sendControl else { throw fail("尚未绑定发送控件。") }
        let control = try resolve(locator, in: target.window, purpose: "发送控件")
        try requireControl(control, kind: .send, input: target.input)
        guard control.enabled == true else { throw fail("发送控件未启用，AI 是否可接收尚未确认。") }
        return control
    }
    private func observedCodexRunningState(_ target: Target) throws -> Bool {
        let nodes = flattened(target.window).map(\.node).filter {
            $0.visible != false && !$0.inNavigation && $0.contentScopeID == target.input.contentScopeID
        }
        let stops = nodes.filter { (try? requireControl($0, kind: .stop, input: target.input)) != nil }
        guard stops.count <= 1 else { throw fail("当前任务的停止控件存在歧义，运行状态未知。") }
        let suspicious = nodes.contains { node in
            if stops.contains(where: { $0.id == node.id }) { return false }
            if (try? requireControl(node, kind: .send, input: target.input)) != nil { return false }
            guard !node.editable, !node.secure else { return false }
            let label = (node.label ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = label + " " + (node.identifier ?? "").lowercased()
            let actionable = ["AXButton", "AXMenuItem", "AXLink"].contains(node.role) || node.actions.contains("AXPress")
            if actionable {
                if label.isEmpty { return true }
                return ["stop", "cancel", "abort", "interrupt", "terminate", "pause", "running", "working", "thinking", "generating",
                        "processing", "queued", "continue", "resume", "retry", "steer", "停止", "取消", "中止", "终止", "暂停",
                        "继续", "重试", "生成中", "思考中", "处理中", "排队", "引导"].contains { identity.contains($0) }
            }
            return ["running", "working", "working…", "thinking", "thinking…", "generating", "processing", "queued",
                    "运行中", "生成中", "思考中", "处理中", "排队中"].contains(label)
        }
        guard !suspicious else { throw fail("当前任务仍有运行或未知操作控件，无法确认可发送。") }
        guard let stop = stops.first else { return false }
        guard let enabled = stop.enabled else { throw fail("停止控件状态未知，无法确认可发送。") }
        return enabled
    }
    private func readyManagedSend(_ target: Target, conversation: CodexConversation) throws -> ToolAXNode {
        let anchor = try resolve(target.binding.taskAnchor, in: target.window, purpose: "会话标识")
        let evidence = try conversationEvidence(conversation, window: target.window, input: target.input, anchor: anchor)
        guard evidence.thread || evidence.project else { throw fail("缺少当前 Codex 会话身份，无法自动确认空闲发送。") }
        // A retained idle Stop locator must not hide another current runtime control.
        let observedRunning = try observedCodexRunningState(target)
        let running = target.binding.stopControl == nil ? observedRunning : (try runningState(target)) || observedRunning
        guard !running else { throw fail("绑定任务正在生成，不能发送新输入。") }
        let control: ToolAXNode
        if let locator = target.binding.sendControl {
            // Stale learned controls do not fall back to a different button.
            control = try resolve(locator, in: target.window, purpose: "发送控件")
            try requireControl(control, kind: .send, input: target.input)
        } else {
            let sends = flattened(target.window).map(\.node).filter { (try? requireControl($0, kind: .send, input: target.input)) != nil }
            guard sends.count == 1, let send = sends.first else { throw fail("没有唯一明确的发送控件。") }
            control = send
        }
        guard control.enabled == true else { throw fail("发送控件未启用，不能确认可接收输入。") }
        return control
    }
    private func readySubmission(_ target: Target, workspace: WorkspaceProfile) throws -> (kind: ToolSubmissionKind, control: ToolAXNode, locator: AXLocator) {
        let entries = flattened(target.window)
        if workspace.bundleIdentifier == "com.openai.codex", workspace.codexConversation != nil {
            try rejectModal(target.observation)
            let approvals = ["approve", "approve once", "approve for this session", "allow", "allow once", "allow for this session",
                             "允许", "允许一次", "始终允许", "批准", "批准一次", "请求批准", "需要批准", "request approval"]
            let waitingApproval = entries.contains { entry in
                let node = entry.node
                guard node.visible != false, !node.inNavigation, node.contentScopeID == target.input.contentScopeID,
                      !node.editable else { return false }
                let label = (node.label ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if ["approval required", "approval requested", "request approval", "permission required", "需要批准", "等待批准", "请求批准", "需要授权"].contains(label) { return true }
                guard ["AXButton", "AXMenuItem"].contains(node.role) else { return false }
                return approvals.contains(label) || label.hasPrefix("approve ") || label.hasPrefix("allow ") ||
                    label.hasPrefix("批准") || label.hasPrefix("允许")
            }
            guard !waitingApproval else { throw fail("当前任务正在等待批准，请直接在 Codex 中处理；引导不能代替批准。") }
            let steerLabels = ["steer", "steer now", "立即引导", "引导", "引导当前任务"]
            let steers = entries.filter { entry in
                let node = entry.node
                return steerLabels.contains((node.label ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) &&
                    node.visible != false && !node.inNavigation && node.contentScopeID == target.input.contentScopeID
            }
            if !steers.isEmpty {
                guard steers.count == 1, let entry = steers.first, entry.node.visible == true,
                      entry.node.enabled == true, !entry.node.editable, !entry.node.secure,
                      ["AXButton", "AXMenuItem"].contains(entry.node.role), entry.node.actions.contains("AXPress") else {
                    throw fail("当前引导控件不明确或不可用，未提交。")
                }
                return (.steer, entry.node, makeLocator(entry.node, path: entry.path))
            }
        }
        let control: ToolAXNode
        if workspace.bundleIdentifier == "com.openai.codex", let conversation = workspace.codexConversation {
            control = try readyManagedSend(target, conversation: conversation)
        } else { control = try readySend(target) }
        guard let entry = entries.first(where: { $0.node.id == control.id }) else { throw fail("发送控件已变化。") }
        return (.send, control, makeLocator(control, path: entry.path))
    }
    private func verifiedShortcut(_ shortcut: ActionShortcut, on control: ToolAXNode) throws {
        guard shortcut.isSupported, control.shortcutKeyCode == shortcut.keyCode,
              let modifiers = control.shortcutModifiers,
              Set(modifiers.map(\.rawValue)) == Set(shortcut.modifiers.map(\.rawValue)) else {
            throw fail("目标控件未公开与配置一致的语义快捷键；请清除自定义快捷键以使用已绑定的辅助功能操作。")
        }
    }
    private func execute(_ action: RemoteAction, control: ToolAXNode, target: Target, workspace: WorkspaceProfile,
                         willMutate: (() -> Void)? = nil) throws {
        try authorizeMutation()
        if let shortcut = workspace.shortcuts.first(where: { $0.action == action }) {
            try verifiedShortcut(shortcut, on: control)
            guard target.observation.focusedNodeID == target.input.id else { throw fail("快捷键要求实时确认 AI 输入焦点。") }
            willMutate?()
            try driver.pressShortcut(shortcut, processID: target.observation.processID)
        } else {
            willMutate?()
            try driver.perform("AXPress", on: control)
        }
    }
}

// Constructing this backend is inert. Permissions are requested only by requestPermission().
@MainActor final class SystemToolAXDriver: ToolAXDriver {
    private var elements: [String: AXUIElement] = [:]
    private var snapshotDeadline: TimeInterval?
    private var snapshotTimedOut = false
    var isTrusted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func installedApplication(bundleIdentifier: String) -> ToolApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let app = try? metadata(at: url, requireUniqueProcess: false), app.bundleIdentifier == bundleIdentifier else { return nil }
        return app
    }
    func application(at url: URL) throws -> ToolApplication {
        try metadata(at: url, requireUniqueProcess: false)
    }
    private func metadata(at url: URL, requireUniqueProcess: Bool) throws -> ToolApplication {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !version.isEmpty else {
            throw ToolAdapterError("请选择具备 bundle ID 和版本号的本机 .app。")
        }
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let combinedVersion = build.map { version + " (" + $0 + ")" } ?? version
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == normalized
        }
        guard !requireUniqueProcess || running.count <= 1 else { throw ToolAdapterError("同一应用存在多个运行实例，请先保留一个明确实例。") }
        return ToolApplication(bundleIdentifier: identifier, path: normalized.path,
                               version: combinedVersion, processID: running.count == 1 ? running.first?.processIdentifier : nil)
    }
    func application(bundleIdentifier: String, appPath: String?) throws -> ToolApplication {
        let url: URL?
        if let appPath { url = URL(fileURLWithPath: appPath) }
        else { url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
        guard let url else { throw ToolAdapterError("未找到该应用，请安装或重新选择 .app。") }
        let app = try metadata(at: url, requireUniqueProcess: true)
        guard app.bundleIdentifier == bundleIdentifier else { throw ToolAdapterError("本机应用的 bundle ID 与工作区不一致。") }
        return app
    }
    func activate(_ application: ToolApplication) async throws {
        let url = URL(fileURLWithPath: application.path)
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try Task.checkCancellation()
        for _ in 0..<10 {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier == application.bundleIdentifier,
               front?.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == application.path { return }
            try await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
        }
        throw ToolAdapterError("激活请求后未观察到目标成为前台应用。")
    }
    func openURL(_ url: URL, for application: ToolApplication) async throws {
        try Task.checkCancellation()
        guard application.bundleIdentifier == "com.openai.codex", url.scheme == "codex", url.host == "threads",
              url.query == nil, url.fragment == nil, url.path.split(separator: "/").count == 1,
              UUID(uuidString: String(url.path.dropFirst())) != nil else {
            throw ToolAdapterError("只允许打开明确的 Codex 会话地址。")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: application.path), configuration: configuration)
        try Task.checkCancellation()
    }
    func snapshot(_ application: ToolApplication) throws -> ToolAXObservation {
        guard isTrusted, let pid = application.processID else { throw ToolAdapterError("目标尚未运行或辅助功能不可用。") }
        snapshotDeadline = ProcessInfo.processInfo.systemUptime + 2
        snapshotTimedOut = false
        defer { snapshotDeadline = nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.1)
        elements.removeAll(keepingCapacity: true)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] else {
            throw ToolAdapterError("应用未提供可读的辅助功能窗口列表。")
        }
        let focusedWindow = elementAttribute(root, kAXFocusedWindowAttribute)
        let focusedElement = elementAttribute(root, kAXFocusedUIElementAttribute)
        var pointerElement: AXUIElement?
        if let event = CGEvent(source: nil) {
            let point = event.location
            _ = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &pointerElement)
        }
        var focusedWindowID: String?, focusedNodeID: String?, pointerNodeID: String?
        var count = 0, complete = true
        func walk(_ element: AXUIElement, id: String, depth: Int, contentScope: String? = nil,
                  inNavigation: Bool = false, ancestorHidden: Bool = false, windowBounds: CGRect? = nil) -> ToolAXNode? {
            guard depth <= 32, count < 4096, withinSnapshotBudget() else { complete = false; return nil }
            count += 1
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let role = attribute(element, kAXRoleAttribute) as? String else { complete = false; return nil }
            let subrole = attribute(element, kAXSubroleAttribute) as? String
            let secure = role == "AXSecureTextField" || subrole == "AXSecureTextField"
            let identifier = attribute(element, kAXIdentifierAttribute) as? String
            // Do not read AXValue here: it can contain whole chat messages or unrelated draft text.
            let label = (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (attribute(element, kAXDescriptionAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
            let roleDescription = (attribute(element, kAXRoleDescriptionAttribute) as? String) ?? ""
            let landmarks = ((subrole ?? "") + " " + roleDescription + " " + (label ?? "")).lowercased()
            let navigation = inNavigation || ["navigation", "sidebar", "侧边栏", "导航"].contains(where: { landmarks.contains($0) })
            let main = subrole == "AXLandmarkMain" || (["AXGroup", "AXDocument"].contains(role) &&
                ["main", "main content", "主要内容", "主内容"].contains(roleDescription.lowercased()))
            let scope = main && !navigation ? id : contentScope
            let hidden = ancestorHidden || (attribute(element, "AXHidden") as? NSNumber)?.boolValue == true ||
                (attribute(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue == true
            let bounds = rectangle(element)
            let visibleWindowBounds = role == "AXWindow" ? bounds : windowBounds
            let visible: Bool? = hidden ? false : bounds.flatMap { rect in
                visibleWindowBounds.map { $0.intersects(rect) && rect.width > 0 && rect.height > 0 }
            }
            var writable = DarwinBoolean(false)
            let textRole = ["AXTextArea", "AXTextField", "AXComboBox"].contains(role)
            guard withinSnapshotBudget() else { complete = false; return nil }
            let editable = textRole && !secure && AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable) == .success && writable.boolValue
            var actionNames: CFArray?
            guard withinSnapshotBudget() else { complete = false; return nil }
            _ = AXUIElementCopyActionNames(element, &actionNames)
            elements[id] = element
            if let focusedWindow, CFEqual(element, focusedWindow) { focusedWindowID = id }
            if let focusedElement, CFEqual(element, focusedElement) { focusedNodeID = id }
            if let pointerElement, CFEqual(element, pointerElement) { pointerNodeID = id }
            var childrenValue: CFTypeRef?
            guard withinSnapshotBudget() else { complete = false; return nil }
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            if ![AXError.success, .attributeUnsupported, .noValue].contains(childrenResult) { complete = false }
            let children = childrenValue as? [AXUIElement] ?? []
            if children.count > 4096 { complete = false }
            let built = children.prefix(4096).enumerated().compactMap {
                walk($0.element, id: id + "/\($0.offset)", depth: depth + 1, contentScope: scope,
                     inNavigation: navigation, ancestorHidden: hidden, windowBounds: visibleWindowBounds)
            }
            let virtualKey = attribute(element, "AXMenuItemCmdVirtualKey") as? NSNumber
            let menuModifiers = attribute(element, "AXMenuItemCmdModifiers") as? NSNumber
            var keyModifiers: [KeyModifier]? = nil
            if let mask = menuModifiers?.intValue {
                var keys: [KeyModifier] = []
                if mask & 1 != 0 { keys.append(.shift) }; if mask & 2 != 0 { keys.append(.option) }
                if mask & 4 != 0 { keys.append(.control) }; if mask & 8 == 0 { keys.append(.command) }
                keyModifiers = keys
            }
            let scrollPosition = role == "AXScrollArea" ? elementAttribute(element, kAXVerticalScrollBarAttribute)
                .flatMap { attribute($0, kAXValueAttribute) as? NSNumber }?.doubleValue : nil
            // AXDocument is a URL string; AXURL is a CFURL. Read document metadata only,
            // never AXValue or arbitrary link targets as current-conversation evidence.
            let documentRole = ["AXWindow", "AXWebArea", "AXDocument"].contains(role) || main
            let documentURL = documentRole ? attribute(element, kAXDocumentAttribute) as? String : nil
            let nodeURL = documentRole ? (attribute(element, kAXURLAttribute) as? URL)?.absoluteString : nil
            return ToolAXNode(id: id, role: role, identifier: identifier, label: label, editable: editable, secure: secure,
                              enabled: (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue,
                              actions: actionNames as? [String] ?? [], visible: visible, contentScopeID: scope,
                              inNavigation: navigation, selected: (attribute(element, kAXSelectedAttribute) as? NSNumber)?.boolValue,
                              shortcutKeyCode: virtualKey.map { $0.uint16Value },
                              shortcutModifiers: keyModifiers, scrollPosition: scrollPosition,
                              documentURL: documentURL, url: nodeURL, subrole: subrole,
                              modal: (attribute(element, kAXModalAttribute) as? NSNumber)?.boolValue, children: built)
        }
        let nodes = windows.enumerated().compactMap { walk($0.element, id: "\(pid):\($0.offset)", depth: 0) }
        guard !snapshotTimedOut else { throw ToolAdapterError("辅助功能读取超过两秒预算，检查不完整；本次操作已阻止。") }
        return ToolAXObservation(processID: pid, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                 focusedWindowID: focusedWindowID, focusedNodeID: focusedNodeID, pointerNodeID: pointerNodeID,
                                 windows: nodes, complete: complete && !snapshotTimedOut)
    }
    private func withinSnapshotBudget() -> Bool {
        guard let deadline = snapshotDeadline else { return true }
        if ProcessInfo.processInfo.systemUptime < deadline { return true }
        snapshotTimedOut = true
        return false
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard withinSnapshotBudget() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func rectangle(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func element(_ node: ToolAXNode) throws -> AXUIElement {
        guard let element = elements[node.id] else { throw ToolAdapterError("辅助功能观察已过期，请重新检查。") }
        return element
    }
    func value(of node: ToolAXNode) throws -> String {
        guard node.editable, !node.secure, let text = attribute(try element(node), kAXValueAttribute) as? String else {
            throw ToolAdapterError("无法读取已绑定输入框的全文。")
        }
        return text
    }
    func setValue(_ value: String, of node: ToolAXNode) throws {
        try Task.checkCancellation()
        guard node.editable, !node.secure,
              AXUIElementSetAttributeValue(try element(node), kAXValueAttribute as CFString, value as CFString) == .success else {
            throw ToolAdapterError("输入框拒绝辅助功能写入；请手动复制草稿。")
        }
    }
    func focus(_ node: ToolAXNode) throws {
        try Task.checkCancellation()
        guard AXUIElementSetAttributeValue(try element(node), kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw ToolAdapterError("输入框不支持辅助功能聚焦。")
        }
    }
    func perform(_ action: String, on node: ToolAXNode) throws {
        try Task.checkCancellation()
        guard node.actions.contains(action), AXUIElementPerformAction(try element(node), action as CFString) == .success else {
            throw ToolAdapterError("目标控件拒绝辅助功能操作，未重试。")
        }
    }
    func pressShortcut(_ shortcut: ActionShortcut, processID: Int32) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { throw ToolAdapterError("快捷键执行前目标已离开前台。") }
        var flags: CGEventFlags = []
        for modifier in shortcut.modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false) else {
            throw ToolAdapterError("无法构造语义快捷键。")
        }
        down.flags = flags; up.flags = flags
        down.postToPid(processID); up.postToPid(processID)
    }
}
