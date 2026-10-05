import Foundation

/// Transport/draft gates, followed by the adapter's independent live AX checks.
public struct ActionSafety {
    public var exclusiveDevice: Bool
    public var suppressionConfirmed: Bool
    public var busy: Bool
    public var operationInProgress: Bool
    public var hasWorkspace: Bool
    public var hasDraft: Bool

    public init(exclusiveDevice: Bool, suppressionConfirmed: Bool, busy: Bool,
                operationInProgress: Bool, hasWorkspace: Bool, hasDraft: Bool) {
        self.exclusiveDevice = exclusiveDevice
        self.suppressionConfirmed = suppressionConfirmed
        self.busy = busy
        self.operationInProgress = operationInProgress
        self.hasWorkspace = hasWorkspace
        self.hasDraft = hasDraft
    }

    public func blockReason(for action: RemoteAction) -> String? {
        if action == .none { return nil }
        if action == .cancel || action == .volumeUp || action == .volumeDown { return nil }
        if operationInProgress { return "上一项操作尚未结束。" }
        if busy { return "收音或识别整理期间不能切换目标或执行工具操作。" }
        if [.focusTarget, .insertDraft, .sendDraft, .stopTask, .scrollUp, .scrollDown, .preview].contains(action),
           !hasWorkspace { return "请先选择并绑定一个工作区。" }
        if [.copyDraft, .insertDraft, .sendDraft].contains(action), !hasDraft { return "没有可用的草稿。" }
        if action == .sendDraft && (!exclusiveDevice || !suppressionConfirmed) {
            return "请先独占接管遥控器，并验证原始按键没有穿透系统。"
        }
        return nil
    }
}

/// A review belongs to exactly one destination and one settled draft revision.
public struct DraftReview: Equatable {
    public let workspaceID: UUID
    public let draft: String
    public init(workspaceID: UUID, draft: String) { self.workspaceID = workspaceID; self.draft = draft }
    public func matches(workspaceID: UUID?, draft: String, busy: Bool) -> Bool {
        !busy && self.workspaceID == workspaceID && self.draft == draft
    }
}
