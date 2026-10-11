import Foundation
import VibeRemoteCore

/// Observed bundle metadata only. Finding an app does not establish its permissions,
/// selected microphone, shortcut configuration or current recording state.
struct VoiceProviderAppInfo: Equatable {
    let name: String
    let path: String
    let bundleIdentifier: String
    let version: String
}

enum VoiceProviderApps {
    static func discover(_ provider: VoiceInputProvider,
                         configuredPath: String? = nil) -> VoiceProviderAppInfo? {
        guard provider != .appleSpeech, provider != .macOSDictation else { return nil }

        // An explicit selection is authoritative: a missing or mismatched bundle
        // must not silently fall back to a different installed copy.
        if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard (configuredPath as NSString).isAbsolutePath,
                  let info = inspect(URL(fileURLWithPath: configuredPath)),
                  matches(info, provider: provider) else { return nil }
            return info
        }
        guard provider != .custom else { return nil }

        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     home.appendingPathComponent("Applications", isDirectory: true),
                     URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true),
                     home.appendingPathComponent("Library/Input Methods", isDirectory: true)]
        for root in roots {
            guard let entries = manager.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            var candidates: [URL] = []
            // Inspect immediate entries only; never recursively traverse applications,
            // home folders or user-selected paths during an installation refresh.
            for _ in 0..<512 {
                guard let url = entries.nextObject() as? URL else { break }
                if url.pathExtension.lowercased() == "app" { candidates.append(url) }
            }
            for url in candidates.sorted(by: { $0.path < $1.path }) {
                if let info = inspect(url), matches(info, provider: provider) { return info }
            }
        }
        return nil
    }

    private static func inspect(_ url: URL) -> VoiceProviderAppInfo? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return nil }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let infoURL = canonicalURL.appendingPathComponent("Contents/Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: infoURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576,
              let data = try? Data(contentsOf: infoURL),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              dictionary["CFBundlePackageType"] as? String == "APPL",
              let identifier = text(dictionary["CFBundleIdentifier"]),
              identifier.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#, options: .regularExpression) != nil,
              let name = text(dictionary["CFBundleDisplayName"]) ?? text(dictionary["CFBundleName"]),
              let executable = text(dictionary["CFBundleExecutable"]),
              executable != ".", executable != "..", !executable.contains("/"),
              FileManager.default.isExecutableFile(atPath: canonicalURL
                .appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path)
        else { return nil }
        let shortVersion = text(dictionary["CFBundleShortVersionString"])
        let build = text(dictionary["CFBundleVersion"])
        let version: String
        if let shortVersion, let build, shortVersion != build {
            version = "\(shortVersion) (\(build))"
        } else {
            version = shortVersion ?? build ?? "版本未知"
        }
        return VoiceProviderAppInfo(name: name, path: canonicalURL.path,
                                    bundleIdentifier: identifier, version: version)
    }

    private static func matches(_ info: VoiceProviderAppInfo, provider: VoiceInputProvider) -> Bool {
        switch provider {
        case .appleSpeech, .macOSDictation: return false
        case .doubaoIME:
            // The Doubao chat client is a different product, even if its filename
            // or user-facing title happens to include the same brand.
            return info.bundleIdentifier == "com.bytedance.inputmethod.doubaoime"
        case .typeless: return info.name.caseInsensitiveCompare("Typeless") == .orderedSame
        case .wisprFlow:
            return ["Wispr Flow", "WisprFlow"].contains {
                info.name.caseInsensitiveCompare($0) == .orderedSame
            }
        case .superwhisper: return info.name.caseInsensitiveCompare("superwhisper") == .orderedSame
        case .custom: return true
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return trimmed
    }
}
