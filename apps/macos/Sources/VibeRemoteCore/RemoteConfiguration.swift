import Foundation

public enum RemoteButton: String, Codable, CaseIterable, Identifiable {
    case power, mic, up, down, left, right, ok, back, home, menu, tv, volumeUp, volumeDown
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .power: return "电源"
        case .mic: return "语音"
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .ok: return "确认"
        case .back: return "返回"
        case .home: return "主页"
        case .menu: return "菜单"
        case .tv: return "电视"
        case .volumeUp: return "音量 +"
        case .volumeDown: return "音量 −"
        }
    }
}

public enum RemoteAction: String, Codable, CaseIterable, Identifiable {
    case none, workspacePicker, actionPicker, focusTarget, copyDraft, insertDraft, sendDraft
    case cancel, stopTask, previousWorkspace, nextWorkspace, scrollUp, scrollDown, preview, volumeUp, volumeDown
    case previousConversation, nextConversation, confirmInput
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "不执行"
        case .workspacePicker: return "选择工作区"
        case .actionPicker: return "动作菜单"
        case .focusTarget: return "聚焦目标输入框"
        case .copyDraft: return "复制草稿"
        case .insertDraft: return "插入草稿"
        case .sendDraft: return "明确发送草稿"
        case .cancel: return "取消"
        case .stopTask: return "停止当前任务"
        case .previousWorkspace: return "上一个工作区"
        case .nextWorkspace: return "下一个工作区"
        case .previousConversation: return "上一个会话"
        case .nextConversation: return "下一个会话"
        case .confirmInput: return "确认输入"
        case .scrollUp: return "向上滚动"
        case .scrollDown: return "向下滚动"
        case .preview: return "打开预览"
        case .volumeUp: return "调高音量"
        case .volumeDown: return "调低音量"
        }
    }
    public var allowsRepeat: Bool { self == .scrollUp || self == .scrollDown || self == .volumeUp || self == .volumeDown }
}

public enum ButtonGesture: String, Codable, CaseIterable, Identifiable {
    case click, doubleClick, hold
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .click: return "单击"
        case .doubleClick: return "双击"
        case .hold: return "长按"
        }
    }
}

public struct HIDBinding: Codable, Equatable, Hashable {
    public var usagePage: Int
    public var usage: Int
    public var reportID: Int
    public var descriptorHash: String
    public var supportsHold: Bool
    public init(usagePage: Int, usage: Int, reportID: Int = 0, descriptorHash: String, supportsHold: Bool = true) {
        self.usagePage = usagePage; self.usage = usage; self.reportID = reportID
        self.descriptorHash = descriptorHash; self.supportsHold = supportsHold
    }
}

public struct ButtonMapping: Codable, Equatable {
    public var button: RemoteButton
    public var single: RemoteAction
    public var long: RemoteAction?
    public var double: RemoteAction?
    public var input: HIDBinding?
    public init(button: RemoteButton, single: RemoteAction = .none, long: RemoteAction? = nil,
                double: RemoteAction? = nil, input: HIDBinding? = nil) {
        self.button = button; self.single = single; self.long = long; self.double = double; self.input = input
    }
}

/// Workspace actions share physical HID calibration from the global button mapping.
public struct ButtonActionMapping: Codable, Equatable {
    public var button: RemoteButton
    public var single: RemoteAction
    public var long: RemoteAction?
    public var double: RemoteAction?
    public init(button: RemoteButton, single: RemoteAction = .none, long: RemoteAction? = nil,
                double: RemoteAction? = nil) {
        self.button = button; self.single = single; self.long = long; self.double = double
    }
    public init(_ mapping: ButtonMapping) {
        self.init(button: mapping.button, single: mapping.single, long: mapping.long, double: mapping.double)
    }
}

/// An accessibility location never contains an input value or a transcript.
public struct AXLocator: Codable, Equatable {
    public var path: [Int]
    public var role: String
    public var identifier: String?
    public var label: String?
    public init(path: [Int] = [], role: String, identifier: String? = nil, label: String? = nil) {
        self.path = path; self.role = role; self.identifier = identifier; self.label = label
    }
}

public struct ToolBinding: Codable, Equatable {
    public var appVersion: String
    public var windowTitle: String
    public var input: AXLocator
    public var taskAnchor: AXLocator
    public var sendControl: AXLocator?
    public var stopControl: AXLocator?
    public init(appVersion: String, windowTitle: String, input: AXLocator, taskAnchor: AXLocator,
                sendControl: AXLocator? = nil, stopControl: AXLocator? = nil) {
        self.appVersion = appVersion; self.windowTitle = windowTitle; self.input = input
        self.taskAnchor = taskAnchor; self.sendControl = sendControl; self.stopControl = stopControl
    }
}

public enum KeyModifier: String, Codable, CaseIterable, Hashable {
    case command, option, control, shift
}

/// A shortcut describes an implementation, never permission to execute it.
public struct ActionShortcut: Codable, Equatable {
    public var action: RemoteAction
    public var keyCode: UInt16
    public var modifiers: [KeyModifier]
    public init(action: RemoteAction, keyCode: UInt16, modifiers: [KeyModifier] = []) {
        self.action = action; self.keyCode = keyCode; self.modifiers = modifiers
    }
    public var isSupported: Bool {
        let keys = Set(modifiers)
        guard keys.count == modifiers.count else { return false }
        switch action {
        case .focusTarget:
            // These are candidates only; the adapter must verify the input after focus.
            return (keyCode == 37 && (keys == [.command] || keys == [.command, .shift])) ||
                   (keyCode == 34 && keys == [.command, .shift])
        case .scrollUp: return (keyCode == 126 || keyCode == 116) && keys.isEmpty
        case .scrollDown: return (keyCode == 125 || keyCode == 121) && keys.isEmpty
        case .sendDraft: return (keyCode == 36 || keyCode == 76) && (keys.isEmpty || keys == [.command])
        case .stopTask: return (keyCode == 53 && keys.isEmpty) || (keyCode == 8 && keys == [.control])
        default: return false
        }
    }
}

public struct WorkspaceProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIdentifier: String
    public var appPath: String?
    public var binding: ToolBinding?
    public var previewURL: String?
    public var codexThreadURL: String?
    public var shortcuts: [ActionShortcut]
    public var buttonActions: [ButtonActionMapping]?
    public var codexConversation: CodexConversation?
    public init(id: UUID = UUID(), name: String, bundleIdentifier: String, appPath: String? = nil,
                binding: ToolBinding? = nil, previewURL: String? = nil, codexThreadURL: String? = nil,
                shortcuts: [ActionShortcut] = [], buttonActions: [ButtonActionMapping]? = nil,
                codexConversation: CodexConversation? = nil) {
        self.id = id; self.name = name; self.bundleIdentifier = bundleIdentifier; self.appPath = appPath
        self.binding = binding; self.previewURL = previewURL; self.codexThreadURL = codexThreadURL
        self.shortcuts = shortcuts
        self.buttonActions = buttonActions
        self.codexConversation = codexConversation
    }
}

public struct NativeSettings: Codable, Equatable {
    public var format: String
    public var schemaVersion: Int
    public var mappings: [ButtonMapping]
    public var workspaces: [WorkspaceProfile]
    public init(format: String = "vibe-remote-native", schemaVersion: Int = 1,
                mappings: [ButtonMapping] = NativeSettings.defaultMappings, workspaces: [WorkspaceProfile] = []) {
        self.format = format; self.schemaVersion = schemaVersion; self.mappings = mappings; self.workspaces = workspaces
    }
    public static var defaults: NativeSettings { NativeSettings() }
    public static var defaultMappings: [ButtonMapping] {
        [.init(button: .power, single: .workspacePicker), .init(button: .mic),
         .init(button: .up, single: .scrollUp), .init(button: .down, single: .scrollDown),
         .init(button: .left, single: .previousWorkspace), .init(button: .right, single: .nextWorkspace),
         .init(button: .ok, single: .sendDraft), .init(button: .back, single: .cancel, long: .stopTask),
         .init(button: .home, single: .focusTarget), .init(button: .menu, single: .actionPicker),
         .init(button: .tv, single: .preview), .init(button: .volumeUp, single: .volumeUp),
         .init(button: .volumeDown, single: .volumeDown)]
    }
    public func effectiveMapping(for button: RemoteButton, workspaceID: UUID?) -> ButtonMapping {
        guard var mapping = mappings.first(where: { $0.button == button }) else {
            return ButtonMapping(button: button)
        }
        if let workspaceID,
           let actions = workspaces.first(where: { $0.id == workspaceID })?.buttonActions,
           let action = actions.first(where: { $0.button == button }) {
            mapping.single = action.single
            mapping.long = action.long
            mapping.double = action.double
        }
        // A preset retains its intended hold action for a future calibrated key;
        // an input observed as pulses cannot execute that hold in this session.
        if mapping.input?.supportsHold == false { mapping.long = nil }
        return mapping
    }
    public func validate() throws {
        try require(format == "vibe-remote-native" && schemaVersion == 1, "不支持的原生配置格式或版本")
        try require(mappings.count == RemoteButton.allCases.count && Set(mappings.map(\.button)).count == mappings.count,
                    "配置必须为每个实体按键保留一项映射")
        var inputs = Set<String>()
        for mapping in mappings {
            if mapping.button == .mic {
                try require(mapping.single == .none && mapping.long == nil && mapping.double == nil && mapping.input == nil,
                            "语音键仅供 ATVV 使用，不能配置 HID 动作")
            }
            guard let input = mapping.input else { continue }
            try require((1...65535).contains(input.usagePage) && (1...65535).contains(input.usage) &&
                        (0...255).contains(input.reportID) && matches(input.descriptorHash, "^[0-9a-fA-F]{64}$"),
                        "HID 输入标识无效")
            let signature = "\(input.descriptorHash.lowercased()):\(input.usagePage):\(input.usage):\(input.reportID)"
            try require(inputs.insert(signature).inserted, "同一 HID 输入不能映射到多个按键")
            try require(input.supportsHold || mapping.long == nil || mapping.long == RemoteAction.none,
                        "脉冲输入不支持长按动作")
        }
        try require(workspaces.count <= 100 && Set(workspaces.map(\.id)).count == workspaces.count,
                    "工作区过多或标识重复")
        for workspace in workspaces { try workspace.validate() }
    }
}

public struct NativeSettingsValidationError: LocalizedError, Equatable {
    public let reason: String
    public var errorDescription: String? { reason }
    public init(_ reason: String) { self.reason = reason }
}

private func require(_ condition: Bool, _ reason: String) throws {
    if !condition { throw NativeSettingsValidationError(reason) }
}

private func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

private func boundedText(_ value: String, maximum: Int, empty: Bool = false) -> Bool {
    (empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
    value.count <= maximum && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

private extension WorkspaceProfile {
    func validate() throws {
        try require(boundedText(name, maximum: 120), "工作区名称为空或过长")
        try require(bundleIdentifier.count <= 255 && matches(bundleIdentifier, "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"),
                    "应用标识无效")
        let bundle = bundleIdentifier.lowercased()
        if let codexConversation {
            try codexConversation.validate()
            try require(bundleIdentifier == "com.openai.codex" &&
                        codexThreadURL == codexConversation.canonicalURL.absoluteString,
                        "Codex 会话描述与目标应用或会话地址不一致")
        }
        let terminalBundles: Set<String> = ["dev.warp.warp-stable", "dev.warp.warp-preview", "com.mitchellh.ghostty",
                                            "net.kovidgoyal.kitty", "org.alacritty", "org.wezfurlong.wezterm",
                                            "co.zeit.hyper", "com.googlecode.iterm2"]
        try require(!bundle.contains("terminal") && !bundle.contains("iterm") && !terminalBundles.contains(bundle),
                    "普通终端不能作为桌面 AI 输入目标")
        if let appPath {
            let components = appPath.split(separator: "/", omittingEmptySubsequences: false)
            try require(boundedText(appPath, maximum: 4096) && appPath.hasPrefix("/") && appPath.hasSuffix(".app") &&
                        !appPath.contains("//") && !components.contains("..") && !components.contains("."),
                        "应用路径必须是本机绝对 .app 路径")
        }
        if let previewURL {
            let url = URLComponents(string: previewURL)
            try require(boundedText(previewURL, maximum: 4096) && !previewURL.contains("\\") &&
                        (url?.scheme == "http" || url?.scheme == "https") &&
                        url?.host?.isEmpty == false && url?.user == nil && url?.password == nil && url?.url != nil,
                        "预览仅支持不含凭据的完整 HTTP(S) 地址")
        }
        if let codexThreadURL {
            try require(bundleIdentifier == "com.openai.codex" && codexThreadURL.count <= 256 &&
                        matches(codexThreadURL, "^codex://threads/[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"),
                        "Codex 会话地址必须是明确的 codex://threads/<id>")
        }
        if let binding {
            try require(boundedText(binding.appVersion, maximum: 120) && boundedText(binding.windowTitle, maximum: 512),
                        "绑定需要有效的应用版本和窗口标题")
            for locator in [binding.input, binding.taskAnchor] + [binding.sendControl, binding.stopControl].compactMap({ $0 }) {
                try locator.validate()
            }
            try require(binding.input.role != "AXSecureTextField", "不能绑定密码输入框")
            try require(binding.taskAnchor.identifier?.isEmpty == false || binding.taskAnchor.label?.isEmpty == false,
                        "会话定位需要独立的标识或标签")
        }
        try require(shortcuts.count <= 5 && Set(shortcuts.map(\.action)).count == shortcuts.count,
                    "工具动作快捷键重复或过多")
        try require(shortcuts.allSatisfy(\.isSupported), "此快捷键不属于受支持的工具动作")
        if let buttonActions {
            try require(buttonActions.count == RemoteButton.allCases.count &&
                        Set(buttonActions.map(\.button)).count == buttonActions.count,
                        "工作区方案必须为每个实体按键保留一项动作")
            for mapping in buttonActions where mapping.button == .mic {
                try require(mapping.single == .none && mapping.long == nil && mapping.double == nil,
                            "语音键仅供 ATVV 使用，不能配置工作区动作")
            }
        }
    }
}

private extension AXLocator {
    func validate() throws {
        try require(path.count <= 32 && path.allSatisfy { (0...4095).contains($0) }, "辅助功能控件路径过深或索引无效")
        try require(role.count <= 64 && matches(role, "^AX[A-Za-z][A-Za-z0-9]*$"), "辅助功能控件角色无效")
        for value in [identifier, label].compactMap({ $0 }) {
            try require(boundedText(value, maximum: 512, empty: true), "辅助功能控件标识或标签过长或包含控制字符")
        }
    }
}

// Codable normally ignores unknown properties. For imports, reject them at every
// level so script fields, persisted input values, and future schemas fail closed.
private struct ConfigurationKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func strictContainer<K: CodingKey & CaseIterable>(_ decoder: Decoder, _ keys: K.Type) throws -> KeyedDecodingContainer<K> {
    let raw = try decoder.container(keyedBy: ConfigurationKey.self)
    let allowed = Set(K.allCases.map(\.stringValue))
    guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown native configuration field"))
    }
    return try decoder.container(keyedBy: K.self)
}

extension HIDBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable { case usagePage, usage, reportID, descriptorHash, supportsHold }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(usagePage: try values.decode(Int.self, forKey: .usagePage),
                  usage: try values.decode(Int.self, forKey: .usage),
                  reportID: try values.decode(Int.self, forKey: .reportID),
                  descriptorHash: try values.decode(String.self, forKey: .descriptorHash),
                  supportsHold: try values.decodeIfPresent(Bool.self, forKey: .supportsHold) ?? true)
    }
}

extension ButtonMapping {
    private enum CodingKeys: String, CodingKey, CaseIterable { case button, single, long, double, input }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(button: try values.decode(RemoteButton.self, forKey: .button),
                  single: try values.decode(RemoteAction.self, forKey: .single),
                  long: try values.decodeIfPresent(RemoteAction.self, forKey: .long),
                  double: try values.decodeIfPresent(RemoteAction.self, forKey: .double),
                  input: try values.decodeIfPresent(HIDBinding.self, forKey: .input))
    }
}

extension ButtonActionMapping {
    private enum CodingKeys: String, CodingKey, CaseIterable { case button, single, long, double }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(button: try values.decode(RemoteButton.self, forKey: .button),
                  single: try values.decode(RemoteAction.self, forKey: .single),
                  long: try values.decodeIfPresent(RemoteAction.self, forKey: .long),
                  double: try values.decodeIfPresent(RemoteAction.self, forKey: .double))
    }
}

extension AXLocator {
    private enum CodingKeys: String, CodingKey, CaseIterable { case path, role, identifier, label }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(path: try values.decode([Int].self, forKey: .path), role: try values.decode(String.self, forKey: .role),
                  identifier: try values.decodeIfPresent(String.self, forKey: .identifier),
                  label: try values.decodeIfPresent(String.self, forKey: .label))
    }
}

extension ToolBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable { case appVersion, windowTitle, input, taskAnchor, sendControl, stopControl }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(appVersion: try values.decode(String.self, forKey: .appVersion),
                  windowTitle: try values.decode(String.self, forKey: .windowTitle),
                  input: try values.decode(AXLocator.self, forKey: .input),
                  taskAnchor: try values.decode(AXLocator.self, forKey: .taskAnchor),
                  sendControl: try values.decodeIfPresent(AXLocator.self, forKey: .sendControl),
                  stopControl: try values.decodeIfPresent(AXLocator.self, forKey: .stopControl))
    }
}

extension ActionShortcut {
    private enum CodingKeys: String, CodingKey, CaseIterable { case action, keyCode, modifiers }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(action: try values.decode(RemoteAction.self, forKey: .action),
                  keyCode: try values.decode(UInt16.self, forKey: .keyCode),
                  modifiers: try values.decode([KeyModifier].self, forKey: .modifiers))
    }
}

extension WorkspaceProfile {
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, bundleIdentifier, appPath, binding, previewURL, codexThreadURL, shortcuts, buttonActions, codexConversation }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), name: try values.decode(String.self, forKey: .name),
                  bundleIdentifier: try values.decode(String.self, forKey: .bundleIdentifier),
                  appPath: try values.decodeIfPresent(String.self, forKey: .appPath),
                  binding: try values.decodeIfPresent(ToolBinding.self, forKey: .binding),
                  previewURL: try values.decodeIfPresent(String.self, forKey: .previewURL),
                  codexThreadURL: try values.decodeIfPresent(String.self, forKey: .codexThreadURL),
                  shortcuts: try values.decode([ActionShortcut].self, forKey: .shortcuts),
                  buttonActions: try values.decodeIfPresent([ButtonActionMapping].self, forKey: .buttonActions),
                  codexConversation: try values.decodeIfPresent(CodexConversation.self, forKey: .codexConversation))
    }
}

extension NativeSettings {
    private enum CodingKeys: String, CodingKey, CaseIterable { case format, schemaVersion, mappings, workspaces }
    public init(from decoder: Decoder) throws {
        let values = try strictContainer(decoder, CodingKeys.self)
        self.init(format: try values.decode(String.self, forKey: .format),
                  schemaVersion: try values.decode(Int.self, forKey: .schemaVersion),
                  mappings: try values.decode([ButtonMapping].self, forKey: .mappings),
                  workspaces: try values.decode([WorkspaceProfile].self, forKey: .workspaces))
    }
}
