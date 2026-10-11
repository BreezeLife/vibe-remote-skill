import Foundation
import VibeRemoteCore

var failures = 0
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    assertions += 1
    if !condition() { failures += 1; print("FAIL \(label)") }
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("vibe-provider-app-fixtures-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

func bundle(_ filename: String, name: String?, id: String,
            kind: String = "APPL", executable: String = "Provider", present: Bool = true) throws -> URL {
    let path = directory.appendingPathComponent(filename + ".app")
    let contents = path.appendingPathComponent("Contents")
    let bin = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": kind,
                             "CFBundleExecutable": executable,
                             "CFBundleShortVersionString": "1.2", "CFBundleVersion": "3"]
    info["CFBundleName"] = name
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    if present {
        let executableURL = bin.appendingPathComponent(executable)
        // Metadata inspection needs executable permission; no fixture is ever run.
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    }
    return path
}

let doubao = try bundle("DifferentFilename", name: "豆包输入法", id: "com.bytedance.inputmethod.doubaoime")
let observed = VoiceProviderApps.discover(.doubaoIME, configuredPath: doubao.path)
check(observed?.name == "豆包输入法", "Doubao identity accepted independent of filename")
check(observed?.bundleIdentifier == "com.bytedance.inputmethod.doubaoime", "reports observed bundle identifier")
check(observed?.version == "1.2 (3)", "reports observed version and build")
check(observed?.path == doubao.resolvingSymlinksInPath().path, "reports canonical path")

let chat = try bundle("DoubaoIME", name: "豆包输入法", id: "com.fixture.doubao.chat")
check(VoiceProviderApps.discover(.doubaoIME, configuredPath: chat.path) == nil,
      "chat cannot masquerade as input method by filename or title")
let typeless = try bundle("Renamed", name: "Typeless", id: "observed.vendor.typeless")
check(VoiceProviderApps.discover(.typeless, configuredPath: typeless.path)?.bundleIdentifier == "observed.vendor.typeless",
      "name-based discovery reports observed identifier rather than assuming one")
let misleading = try bundle("Typeless", name: "Unrelated", id: "observed.unrelated")
check(VoiceProviderApps.discover(.typeless, configuredPath: misleading.path) == nil,
      "filename alone cannot override mismatched metadata")
let nameless = try bundle("TypelessWithoutName", name: nil, id: "observed.nameless")
check(VoiceProviderApps.discover(.custom, configuredPath: nameless.path) == nil,
      "missing name metadata is rejected")
let wispr = try bundle("Flow", name: "Wispr Flow", id: "observed.vendor.wispr")
check(VoiceProviderApps.discover(.wisprFlow, configuredPath: wispr.path) != nil, "Flow metadata matched")
let superwhisper = try bundle("SW", name: "Superwhisper", id: "observed.vendor.superwhisper")
check(VoiceProviderApps.discover(.superwhisper, configuredPath: superwhisper.path) != nil,
      "Superwhisper metadata matched case-insensitively")

check(VoiceProviderApps.discover(.custom, configuredPath: misleading.path) != nil,
      "custom accepts an explicitly selected valid app")
check(VoiceProviderApps.discover(.custom) == nil, "custom never discovers arbitrary applications")
let wrongKind = try bundle("NotAnApp", name: "Typeless", id: "valid.id", kind: "BNDL")
check(VoiceProviderApps.discover(.custom, configuredPath: wrongKind.path) == nil, "requires APPL package type")
let invalidID = try bundle("BadID", name: "Typeless", id: "bad id")
check(VoiceProviderApps.discover(.custom, configuredPath: invalidID.path) == nil, "requires valid bundle identifier")
let noExecutable = try bundle("MissingExecutable", name: "Typeless", id: "valid.id", present: false)
check(VoiceProviderApps.discover(.custom, configuredPath: noExecutable.path) == nil, "requires executable file")
let unsafeExecutable = try bundle("UnsafeExecutable", name: "Typeless", id: "valid.id",
                                 executable: "../escape", present: false)
check(VoiceProviderApps.discover(.custom, configuredPath: unsafeExecutable.path) == nil,
      "rejects executable path traversal")

check(VoiceProviderApps.discover(.typeless, configuredPath: directory.appendingPathComponent("missing.app").path) == nil,
      "explicit missing selection never falls back to another installed app")
check(VoiceProviderApps.discover(.typeless, configuredPath: misleading.path) == nil,
      "explicit mismatched selection never falls back to another installed app")
check(VoiceProviderApps.discover(.custom, configuredPath: "relative.app") == nil, "rejects relative path")
check(VoiceProviderApps.discover(.appleSpeech, configuredPath: typeless.path) == nil,
      "native recognition does not bind arbitrary applications")
check(VoiceProviderApps.discover(.macOSDictation, configuredPath: typeless.path) == nil,
      "system dictation does not bind arbitrary applications")

print("\(assertions) provider application assertions; \(failures) failures")
exit(failures == 0 ? 0 : 1)
