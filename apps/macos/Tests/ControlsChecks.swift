import Foundation
import VibeRemoteCore

var failures = 0
var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, _ label: String) {
    assertions += 1
    do { if try !condition() { failures += 1; print("FAIL \(label)") } }
    catch { failures += 1; print("FAIL \(label): \(error)") }
}
func rejected(_ label: String, _ action: () throws -> Void) {
    assertions += 1
    do { try action(); failures += 1; print("FAIL \(label)") } catch { }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibe-settings-checks-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let url = directory.appendingPathComponent("settings.json")
let store = NativeSettingsStore(url: url)
check(try store.load() == .defaults, "missing settings load defaults")
try store.save(.defaults)
let original = try Data(contentsOf: url)
check(try store.load() == .defaults, "atomic settings round trip")
var changed = NativeSettings.defaults
changed.workspaces = [WorkspaceProfile(name: "Fixture", bundleIdentifier: "com.openai.codex")]
try store.save(changed)
check(try store.load() == changed, "valid update saved")
check(try Data(contentsOf: store.backupURL) == original, "previous valid settings retained")
rejected("malformed imported data rejected") { _ = try NativeSettingsStore.decode(Data("{bad".utf8)) }
rejected("unknown format rejected") { _ = try NativeSettingsStore.decode(Data("{\"format\":\"skill\",\"schemaVersion\":99}".utf8)) }
check(try store.load() == changed, "failed import leaves active file untouched")
var invalid = changed
invalid.workspaces.append(changed.workspaces[0])
rejected("invalid settings rejected before write") { try store.save(invalid) }
check(try store.load() == changed, "failed save preserves current settings")
try Data("damaged settings".utf8).write(to: url)
rejected("corrupt current settings do not silently load defaults") { _ = try store.load() }
try store.save(.defaults)
let archived = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("settings-damaged-") }
check(archived.count == 1, "damaged settings retained on explicit replacement")
check(try Data(contentsOf: store.backupURL) == original, "last valid backup survives damaged replacement")
let export = try NativeSettingsStore.encode(changed)
check(try NativeSettingsStore.decode(export) == changed, "export contains configuration only and is reusable")
rejected("oversized import rejected") { _ = try NativeSettingsStore.decode(Data(repeating: 32, count: 1_048_577)) }
let unwritable = NativeSettingsStore(url: url.appendingPathComponent("settings.json"))
rejected("write failure is surfaced") { try unwritable.save(.defaults) }
print("\(assertions) settings assertions; \(failures) failures")
exit(failures == 0 ? 0 : 1)
