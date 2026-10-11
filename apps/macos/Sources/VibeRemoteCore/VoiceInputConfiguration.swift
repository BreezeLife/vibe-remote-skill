import Foundation

/// Provider choices describe setup, not an observed installation or recording state.
public enum VoiceInputProvider: String, Codable, CaseIterable, Identifiable {
    case appleSpeech, typeless, doubaoIME, wisprFlow, superwhisper, macOSDictation, custom
    public var id: String { rawValue }
    public var isExternal: Bool { self != .appleSpeech }
    public var title: String {
        switch self {
        case .appleSpeech: return "Apple Speech（内置）"
        case .typeless: return "Typeless"
        case .doubaoIME: return "豆包输入法"
        case .wisprFlow: return "Wispr Flow"
        case .superwhisper: return "Superwhisper"
        case .macOSDictation: return "macOS 听写"
        case .custom: return "其他语音输入工具"
        }
    }
    public var label: String { title }
    public var officialURL: URL? {
        let address: String
        switch self {
        case .appleSpeech: return nil
        case .typeless: address = "https://www.typeless.com/help/quickstart/settings"
        case .doubaoIME: address = "https://ime.doubao.com/pc"
        case .wisprFlow: address = "https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation"
        case .superwhisper: address = "https://superwhisper.com/docs/get-started/essential-settings"
        case .macOSDictation: address = "https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac"
        case .custom: return nil
        }
        return URL(string: address)
    }
    public var setupDescription: String {
        switch self {
        case .appleSpeech:
            return "直接识别遥控器音频；默认要求本地识别，可单独启用 Apple 在线识别。"
        case .typeless:
            return "在 Typeless 设置中选择麦克风并核对 Dictate 快捷键；将输入位置保持在 Vibe Remote 接收框。"
        case .doubaoIME:
            return "在豆包输入法中核对语音触发方式与麦克风选择；豆包聊天应用不等同于豆包输入法。"
        case .wisprFlow:
            return "Flow 支持按住说话和免提模式；请核对使用的模式、快捷键和麦克风，并关闭自动发送。"
        case .superwhisper:
            return "在 Superwhisper 中选择听写模式、麦克风和快捷键；输出保留在 Vibe Remote，关闭自动发送。"
        case .macOSDictation:
            return "在系统设置的键盘页面启用听写，核对麦克风与快捷键；听写结果先进入 Vibe Remote。"
        case .custom:
            return "适用于向当前文本框输入文字的语音工具；手动核对麦克风与触发方式，并关闭自动发送。"
        }
    }
}

public enum VoiceTriggerMode: String, Codable, CaseIterable, Identifiable {
    case manual, hold, toggle
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .manual: return "手动启动 / 停止"
        case .hold: return "按住开始，松开结束"
        case .toggle: return "按下启动，再按结束"
        }
    }
}

/// Local setup only: this never stores transcripts, audio or runtime acceptance.
public struct VoiceInputProfile: Codable, Equatable {
    public var provider: VoiceInputProvider
    public var appPath: String?
    public var bundleIdentifier: String?
    public var outputDeviceUID: String?
    public var triggerMode: VoiceTriggerMode
    public var shortcutKeyCode: UInt16?
    public var shortcutModifiers: [KeyModifier]
    public var shortcutNote: String

    public init(provider: VoiceInputProvider, appPath: String? = nil, bundleIdentifier: String? = nil,
                outputDeviceUID: String? = nil, triggerMode: VoiceTriggerMode = .manual,
                shortcutKeyCode: UInt16? = nil, shortcutModifiers: [KeyModifier] = [],
                shortcutNote: String = "") {
        self.provider = provider; self.appPath = appPath; self.bundleIdentifier = bundleIdentifier
        self.outputDeviceUID = outputDeviceUID; self.triggerMode = triggerMode
        self.shortcutKeyCode = shortcutKeyCode; self.shortcutModifiers = shortcutModifiers
        self.shortcutNote = shortcutNote
    }

    /// Physical macOS virtual key codes for F13–F20, in numeric function-key order.
    public static let functionKeyCodes: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 90]

    public var hasSupportedShortcut: Bool {
        guard let shortcutKeyCode else { return false }
        return Self.supportsShortcut(keyCode: shortcutKeyCode, modifiers: shortcutModifiers)
    }

    public static func supportsShortcut(keyCode: UInt16, modifiers: [KeyModifier]) -> Bool {
        let distinct = Set(modifiers)
        guard distinct.count == modifiers.count else { return false }
        return (functionKeyCodes.contains(keyCode) && distinct.isEmpty) ||
               (keyCode == 49 && !distinct.isEmpty)
    }

    public func validate() throws {
        try voiceRequire(provider.isExternal, "内置识别不使用第三方语音配置")
        if let appPath {
            let components = appPath.split(separator: "/", omittingEmptySubsequences: false)
            try voiceRequire(voiceBoundedText(appPath, maximum: 4096) && appPath.hasPrefix("/") &&
                             appPath.hasSuffix(".app") && !appPath.contains("//") &&
                             !components.contains("..") && !components.contains(".") &&
                             (components.last?.count ?? 0) > 4,
                             "语音应用路径必须是本机绝对 .app 路径")
        }
        if let bundleIdentifier {
            try voiceRequire(voiceBoundedText(bundleIdentifier, maximum: 255) &&
                             bundleIdentifier.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil,
                             "语音应用标识无效")
        }
        if let outputDeviceUID {
            try voiceRequire(voiceBoundedText(outputDeviceUID, maximum: 1024), "语音音频设备标识为空、过长或包含控制字符")
        }
        try voiceRequire(voiceBoundedText(shortcutNote, maximum: 512, empty: true), "快捷键说明过长或包含控制字符")
        try voiceRequire(Set(shortcutModifiers).count == shortcutModifiers.count, "语音快捷键修饰键重复")
        if shortcutKeyCode != nil {
            try voiceRequire(hasSupportedShortcut, "语音触发仅支持 F13–F20 或修饰键加空格")
        } else {
            try voiceRequire(shortcutModifiers.isEmpty, "语音快捷键缺少主键")
        }
        // A partial setup remains manual until the user selects a supported key.
        try voiceRequire(triggerMode == .manual || hasSupportedShortcut, "自动语音触发需要先配置受支持的快捷键")
    }
}

public struct VoiceInputConfiguration: Codable, Equatable {
    public var provider: VoiceInputProvider
    public var profiles: [VoiceInputProfile]
    public init(provider: VoiceInputProvider = .appleSpeech, profiles: [VoiceInputProfile] = []) {
        self.provider = provider; self.profiles = profiles
    }
    public func profile(for provider: VoiceInputProvider) -> VoiceInputProfile {
        profiles.first { $0.provider == provider } ?? VoiceInputProfile(provider: provider)
    }
    public mutating func setProfile(_ profile: VoiceInputProfile) {
        profiles.removeAll { $0.provider == profile.provider }
        if profile.provider.isExternal { profiles.append(profile) }
    }
    public func validate() throws {
        try voiceRequire(profiles.count <= VoiceInputProvider.allCases.filter(\.isExternal).count &&
                         Set(profiles.map(\.provider)).count == profiles.count,
                         "语音输入配置重复或过多")
        for profile in profiles { try profile.validate() }
    }
}

private func voiceRequire(_ condition: Bool, _ reason: String) throws {
    if !condition { throw NativeSettingsValidationError(reason) }
}

private func voiceBoundedText(_ value: String, maximum: Int, empty: Bool = false) -> Bool {
    (empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
    value.count <= maximum && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

private struct VoiceConfigurationKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func voiceStrictContainer<K: CodingKey & CaseIterable>(_ decoder: Decoder, _ keys: K.Type) throws -> KeyedDecodingContainer<K> {
    let raw = try decoder.container(keyedBy: VoiceConfigurationKey.self)
    let allowed = Set(K.allCases.map(\.stringValue))
    guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown voice input configuration field"))
    }
    return try decoder.container(keyedBy: K.self)
}

extension VoiceInputProfile {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case provider, appPath, bundleIdentifier, outputDeviceUID, triggerMode, shortcutKeyCode, shortcutModifiers, shortcutNote
    }
    public init(from decoder: Decoder) throws {
        let values = try voiceStrictContainer(decoder, CodingKeys.self)
        self.init(provider: try values.decode(VoiceInputProvider.self, forKey: .provider),
                  appPath: try values.decodeIfPresent(String.self, forKey: .appPath),
                  bundleIdentifier: try values.decodeIfPresent(String.self, forKey: .bundleIdentifier),
                  outputDeviceUID: try values.decodeIfPresent(String.self, forKey: .outputDeviceUID),
                  triggerMode: try values.decodeIfPresent(VoiceTriggerMode.self, forKey: .triggerMode) ?? .manual,
                  shortcutKeyCode: try values.decodeIfPresent(UInt16.self, forKey: .shortcutKeyCode),
                  shortcutModifiers: try values.decodeIfPresent([KeyModifier].self, forKey: .shortcutModifiers) ?? [],
                  shortcutNote: try values.decodeIfPresent(String.self, forKey: .shortcutNote) ?? "")
    }
}

extension VoiceInputConfiguration {
    private enum CodingKeys: String, CodingKey, CaseIterable { case provider, profiles }
    public init(from decoder: Decoder) throws {
        let values = try voiceStrictContainer(decoder, CodingKeys.self)
        self.init(provider: try values.decodeIfPresent(VoiceInputProvider.self, forKey: .provider) ?? .appleSpeech,
                  profiles: try values.decodeIfPresent([VoiceInputProfile].self, forKey: .profiles) ?? [])
    }
}
