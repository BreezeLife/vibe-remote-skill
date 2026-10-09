import Foundation

/// Persisted navigation metadata only. This does not establish live task state.
public struct CodexConversation: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let projectPath: String
    public init(id: String, title: String, projectPath: String) {
        self.id = id; self.title = title; self.projectPath = projectPath
    }
    public var canonicalURL: URL {
        var parts = URLComponents()
        parts.scheme = "codex"; parts.host = "threads"; parts.path = "/" + id
        return parts.url!
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, id.count == 36,
              Self.validText(title, limit: 512),
              Self.normalizedLocalPath(projectPath) == projectPath else {
            throw NativeSettingsValidationError("Codex 会话标识、标题或本地项目路径无效")
        }
    }
    static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func normalizedLocalPath(_ value: String) -> String? {
        guard validText(value, limit: 4096), value.hasPrefix("/"), !value.hasPrefix("//"),
              !value.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }
    private enum CodingKeys: String, CodingKey { case id, title, projectPath }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        guard raw.allKeys.allSatisfy({ ["id", "title", "projectPath"].contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown conversation field"))
        }
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try fields.decode(String.self, forKey: .id),
                  title: try fields.decode(String.self, forKey: .title),
                  projectPath: try fields.decode(String.self, forKey: .projectPath))
        try validate()
    }
}

public struct CodexConversationPage: Equatable {
    public let conversations: [CodexConversation]
    public let nextCursor: String?
    /// Includes excluded entries, so pagination bounds cannot be bypassed by malformed data.
    public let entryCount: Int
}

public enum CodexConversationCatalog {
    /// Parses the list envelope, retaining neither previews, transcripts nor runtime state.
    public static func parseListResponse(_ data: Data) throws -> CodexConversationPage {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["error"] == nil,
              let result = response["result"] as? [String: Any],
              let entries = result["data"] as? [[String: Any]] else {
            throw NativeSettingsValidationError("Codex 会话目录响应无效")
        }
        var cursor: String?
        if let value = result["nextCursor"], !(value is NSNull) {
            guard let text = value as? String, CodexConversation.validText(text, limit: 4096) else {
                throw NativeSettingsValidationError("Codex 会话目录分页标识无效")
            }
            cursor = text
        }
        var records: [String: CodexConversation] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String, UUID(uuidString: id) != nil, id.count == 36,
                  let cwd = entry["cwd"] as? String,
                  let path = CodexConversation.normalizedLocalPath(cwd),
                  entry["parentThreadId"] == nil || entry["parentThreadId"] is NSNull,
                  isLocal(entry) else { continue }
            let name = entry["name"] as? String
            let title = name.flatMap { CodexConversation.validText($0, limit: 512) ? $0 : nil }
                ?? "未命名会话 · \(id)"
            let record = CodexConversation(id: id.lowercased(), title: title, projectPath: path)
            if let previous = records[record.id], previous.projectPath != record.projectPath {
                throw NativeSettingsValidationError("同一 Codex 会话出现了不同的项目路径，请刷新后重试")
            }
            if records[record.id] == nil { records[record.id] = record }
        }
        return CodexConversationPage(conversations: sorted(Array(records.values)), nextCursor: cursor,
                                     entryCount: entries.count)
    }
    public static func sorted(_ conversations: [CodexConversation]) -> [CodexConversation] {
        conversations.sorted {
            if $0.projectPath != $1.projectPath { return $0.projectPath < $1.projectPath }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
    }
    private static func isLocal(_ entry: [String: Any]) -> Bool {
        // This service talks only to a local stdio server. Reject any future explicit
        // host/cloud annotation rather than opening it as a local desktop thread.
        for key in ["hostId", "host", "remoteHost", "cloudTaskId"] {
            if let value = entry[key], !(value is NSNull), value as? String != "local" { return false }
        }
        if let source = entry["source"] as? String,
           !["cli", "vscode", "appServer"].contains(source) { return false }
        if let source = entry["source"], !(source is String), !(source is NSNull) { return false }
        return true
    }
}
