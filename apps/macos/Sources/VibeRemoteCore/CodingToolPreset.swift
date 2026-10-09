import Foundation

/// These presets bind stable intentions to each supported tool; they do not
/// assume that a shortcut, accessibility target, or physical device is ready.
public enum CodingToolPreset: String, CaseIterable, Identifiable {
    case codex, claude, workbuddy

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Desktop"
        case .workbuddy: return "WorkBuddy"
        }
    }
    public var bundleIdentifiers: [String] {
        switch self {
        case .codex: return ["com.openai.codex"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .workbuddy: return ["com.tencent.workbuddy.mac", "com.workbuddy.workbuddy-ai"]
        }
    }
    public var buttonActions: [ButtonActionMapping] {
        NativeSettings.defaultMappings.map(ButtonActionMapping.init)
    }
    public static var codexConversationActions: [ButtonActionMapping] {
        codex.buttonActions.map { mapping in
            var result = mapping
            switch result.button {
            case .up: result.single = .previousConversation
            case .down: result.single = .nextConversation
            case .ok: result.single = .confirmInput
            default: break
            }
            return result
        }
    }
    public static func matching(bundleIdentifier: String) -> CodingToolPreset? {
        allCases.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}
