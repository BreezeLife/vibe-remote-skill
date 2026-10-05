import Foundation
import VibeRemoteCore

/// Configuration only: drafts, device identities and observed capabilities never enter this store.
struct NativeSettingsStore {
    let url: URL
    var backupURL: URL { url.deletingLastPathComponent().appendingPathComponent("settings.previous.json") }

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Vibe Remote/settings.json")) {
        self.url = url
    }

    func load() throws -> NativeSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        return try Self.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    func save(_ settings: NativeSettings) throws {
        let data = try Self.encode(settings)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            if (try? Self.decode(previous)) != nil {
                try previous.write(to: backupURL, options: .atomic)
            } else {
                // Preserve damaged source for recovery; never replace the last valid backup with it.
                let damaged = directory.appendingPathComponent("settings-damaged-\(UUID()).json")
                try previous.write(to: damaged, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    static func decode(_ data: Data) throws -> NativeSettings {
        guard data.count <= 1_048_576 else { throw SettingsError.tooLarge }
        let settings = try JSONDecoder().decode(NativeSettings.self, from: data)
        try settings.validate()
        return settings
    }

    static func encode(_ settings: NativeSettings) throws -> Data {
        try settings.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        guard data.count <= 1_048_576 else { throw SettingsError.tooLarge }
        return data
    }

    enum SettingsError: LocalizedError {
        case tooLarge
        var errorDescription: String? { "配置文件超过 1 MB；请检查文件是否为 Vibe Remote 原生配置。" }
    }
}
