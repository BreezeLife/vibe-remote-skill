import AppKit
import CryptoKit
import Foundation
import VibeRemoteCore

// These tests compile the production coordinator and all adapters, but their only
// side effects are fake-driver calls and files inside a temporary fixture directory.
// No Bluetooth/IOKit/AX driver, recognizer, TCC prompt, pasteboard or GUI is used.
private final class IntegrationBluetooth: BluetoothServicing {
    var discovery = RemoteDiscoveryState()
    var onDiscovery: ((RemoteDiscoveryState) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReady: ((Bool) -> Void)?
    var onStream: ((Bool, Int) -> Void)?
    var onSamples: (([Int16], Int) -> Void)?
    var onLevel: ((Double) -> Void)?
    var stops = 0
    func start() {}
    func discover() {}
    func stopDiscovery() {}
    func selectRemote(_ id: UUID) {}
    func setAutoReconnect(_ enabled: Bool) { discovery.autoReconnectEnabled = enabled; onDiscovery?(discovery) }
    func forgetRemote() { discovery.rememberedID = nil; onDiscovery?(discovery) }
    func disconnect() { onReady?(false) }
    func stopCapture() { stops += 1; onStream?(false, 16_000) }
    func stream(_ active: Bool) { onStream?(active, 16_000) }
}

private final class IntegrationSpeech: SpeechServicing {
    var isAuthorized = true
    var onText: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onFinished: (() -> Void)?
    func requestAuthorization(completion: @escaping (Bool) -> Void) { fatalError("Unexpected permission request") }
    func start(localeIdentifier: String, allowServerRecognition: Bool) throws {}
    func append(samples: [Int16], sampleRate: Int) {}
    func finish() {}
    func cancel() {}
}

private final class IntegrationHID: HIDRemoteDriver {
    static let descriptor = Data([1, 2, 3])
    static let hash = SHA256.hash(data: descriptor).map { String(format: "%02x", $0) }.joined()
    var onInterfacesChanged: (([HIDRemoteInterface]) -> Void)?
    var onValue: ((HIDRemoteValue) -> Void)?
    var onInvalidated: ((String) -> Void)?
    var permission: HIDInputPermission = .granted
    var permissionChecks = 0
    var openIDs = Set<String>()
    func checkPermission() -> HIDInputPermission { permissionChecks += 1; return permission }
    func requestPermission() { fatalError("Unexpected permission request") }
    func startDiscovery() throws {
        onInterfacesChanged?([HIDRemoteInterface(id: "synthetic-interface", physicalID: "synthetic-remote",
            name: "Synthetic Remote", vendorID: 0x2717, productID: 0x32B8, descriptor: Self.descriptor)])
    }
    func stopDiscovery() {}
    func open(interfaceID: String, exclusive: Bool) -> Bool { openIDs.insert(interfaceID); return true }
    func close(interfaceID: String) { openIDs.remove(interfaceID) }
    func emit(_ usage: Int = 40, down: Bool, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        onValue?(HIDRemoteValue(interfaceID: "synthetic-interface", cookie: usage, usagePage: 7,
            usage: usage, reportID: 1, isDown: down, canReportRelease: true, timestamp: time))
    }
    func tap(_ usage: Int = 40, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        emit(usage, down: true, at: time); emit(usage, down: false, at: time + 0.01)
    }
    func disconnect() { onInterfacesChanged?([]) }
}

@MainActor private final class IntegrationAX: ToolAXDriver {
    var isTrusted = true
    var text = "existing synthetic input"
    var writes: [String] = []
    var presses: [String] = []
    var focuses = 0
    var activations = 0
    var activationPaused = false
    var activationContinuation: CheckedContinuation<Void, Never>?
    var snapshotHook: (() -> Void)?
    var frontmostPID: Int32? = 42
    var focusedNodeID: String? = "input"
    var complete = true
    var windows = [ToolAXNode(id: "window", role: "AXWindow", label: "Synthetic Project", children: [
        ToolAXNode(id: "input", role: "AXTextArea", identifier: "composer", label: "Message", editable: true,
                   enabled: true, visible: true, contentScopeID: "synthetic-main"),
        ToolAXNode(id: "anchor", role: "AXHeading", identifier: "synthetic-task", label: "Synthetic Task",
                   visible: true, contentScopeID: "synthetic-main"),
        ToolAXNode(id: "send", role: "AXButton", identifier: "send", label: "Send message", enabled: true,
                   actions: ["AXPress"], visible: true, contentScopeID: "synthetic-main"),
        ToolAXNode(id: "stop", role: "AXButton", identifier: "stop", label: "Stop generating", enabled: false,
                   actions: ["AXPress"], visible: true, contentScopeID: "synthetic-main")
    ])]
    func requestPermission() { fatalError("Unexpected permission request") }
    func installedApplication(bundleIdentifier: String) -> ToolApplication? { nil }
    func application(bundleIdentifier: String, appPath: String?) throws -> ToolApplication {
        ToolApplication(bundleIdentifier: bundleIdentifier, path: "/Applications/Synthetic.app", version: "1.0", processID: 42)
    }
    func application(at url: URL) throws -> ToolApplication { fatalError("Unexpected app lookup") }
    func activate(_ application: ToolApplication) async throws {
        activations += 1
        if activationPaused { await withCheckedContinuation { activationContinuation = $0 } }
    }
    func resumeActivation() {
        activationPaused = false
        let continuation = activationContinuation
        activationContinuation = nil
        continuation?.resume()
    }
    func snapshot(_ application: ToolApplication) throws -> ToolAXObservation {
        let hook = snapshotHook; snapshotHook = nil; hook?()
        return ToolAXObservation(processID: 42, frontmostPID: frontmostPID, focusedWindowID: "window",
            focusedNodeID: focusedNodeID, pointerNodeID: "anchor", windows: windows, complete: complete)
    }
    func value(of node: ToolAXNode) throws -> String { text }
    func setValue(_ value: String, of node: ToolAXNode) throws { writes.append(value); text = value }
    func focus(_ node: ToolAXNode) throws { focuses += 1; focusedNodeID = node.id }
    func perform(_ action: String, on node: ToolAXNode) throws {
        presses.append(node.id)
        if node.id == "send" { windows[0].children[3].enabled = true; windows[0].children[2].enabled = false; text = "" }
    }
    func pressShortcut(_ shortcut: ActionShortcut, processID: Int32) throws { fatalError("Unexpected shortcut") }
}

@MainActor private final class Fixture {
    let directory: URL
    let store: NativeSettingsStore
    let bluetooth = IntegrationBluetooth()
    let speech = IntegrationSpeech()
    let input = IntegrationHID()
    let ax = IntegrationAX()
    let voice: RemoteModel
    let hid: HIDRemoteInputService
    let controls: ControlsModel
    var first: WorkspaceProfile { controls.settings.workspaces[0] }
    var second: WorkspaceProfile { controls.settings.workspaces[1] }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VibeRemote-Integration-\(UUID())", isDirectory: true)
        store = NativeSettingsStore(url: directory.appendingPathComponent("settings.json"))
        let binding = ToolBinding(appVersion: "1.0", windowTitle: "Synthetic Project",
            input: AXLocator(path: [0], role: "AXTextArea", identifier: "composer", label: "Message"),
            taskAnchor: AXLocator(path: [1], role: "AXHeading", identifier: "synthetic-task", label: "Synthetic Task"),
            sendControl: AXLocator(path: [2], role: "AXButton", identifier: "send", label: "Send message"),
            stopControl: AXLocator(path: [3], role: "AXButton", identifier: "stop", label: "Stop generating"))
        let first = WorkspaceProfile(name: "Synthetic Alpha", bundleIdentifier: "test.synthetic", binding: binding)
        let second = WorkspaceProfile(name: "Synthetic Beta", bundleIdentifier: "test.synthetic", binding: binding)
        var settings = NativeSettings(workspaces: [first, second])
        for (button, usage) in [(RemoteButton.ok, 40), (.home, 41), (.left, 42), (.right, 43), (.back, 44)] {
            let index = settings.mappings.firstIndex { $0.button == button }!
            settings.mappings[index].input = HIDBinding(usagePage: 7, usage: usage, reportID: 1, descriptorHash: IntegrationHID.hash)
        }
        try store.save(settings)
        voice = RemoteModel(bluetooth: bluetooth, speech: speech)
        hid = HIDRemoteInputService(driver: input)
        controls = ControlsModel(voice: voice, store: store, hid: hid, adapter: ToolAdapter(driver: ax), showWindow: {})
        controls.selectWorkspace(first.id)
        voice.replaceDraft("synthetic alpha draft")
    }
    func seize() {
        hid.discover(); hid.seize(deviceID: "synthetic-remote")
        controls.setSuppressionConfirmed(true); controls.enableMappings()
    }
    func configureOK(single: RemoteAction, long: RemoteAction? = nil, double: RemoteAction? = nil) {
        controls.selectedButton = .ok
        _ = controls.updateMapping { $0.single = single; $0.long = long; $0.double = double }
    }
    func close() {
        controls.shutdown(); ax.resumeActivation()
        try? FileManager.default.removeItem(at: directory)
    }
}

@main private struct ControlsIntegrationChecks {
    @MainActor static func main() async {
        var assertions = 0, failures = 0, scenarios = 0
        var current = ""
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            if !value() { failures += 1; print("FAIL \(current): \(message)") }
        }
        func waitUntil(_ description: String, _ condition: () -> Bool) async {
            for _ in 0..<500 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            check(false, "timed out: \(description)")
        }
        func settle(_ fixture: Fixture) async {
            await waitUntil("operation completion") { !fixture.controls.operationInProgress }
            // Let Combine's main-queue invalidation observe the completed change.
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        func run(_ name: String, _ operation: (Fixture) async throws -> Void) async {
            scenarios += 1; current = name; let before = failures
            do {
                let fixture = try Fixture()
                defer { fixture.close() }
                try await operation(fixture)
            } catch { check(false, "unexpected error: \(error)") }
            if failures == before { print("PASS \(name)") }
        }
        func preview(_ fixture: Fixture) async {
            fixture.seize()
            fixture.controls.perform(.insertDraft); await settle(fixture)
            check(fixture.ax.writes.count == 1, "explicit insertion writes once")
            fixture.controls.perform(.sendDraft); await settle(fixture)
            check(fixture.controls.pendingSend != nil, "matching inserted draft produces review: \(fixture.controls.status)")
            check(fixture.ax.presses.isEmpty, "preparing review never sends")
        }

        await run("button action edits stay with their workspace and preserve shared calibration") { f in
            let shared = f.controls.settings.mappings
            f.configureOK(single: .insertDraft)
            check(f.controls.mapping.single == .insertDraft, "selected workspace receives edited action")
            check(f.controls.settings.mappings == shared, "workspace edits do not overwrite shared actions or HID keys")
            f.controls.selectWorkspace(f.second.id)
            check(f.controls.mapping.single == .sendDraft, "another workspace keeps its original action")
            f.controls.selectWorkspace(f.first.id)
            check(f.controls.mapping.single == .insertDraft, "switching back restores scoped action")
            f.seize(); f.input.emit(down: true); f.input.emit(down: false)
            await settle(f)
            check(f.ax.writes.count == 1 && f.ax.presses.isEmpty, "physical key dispatch uses scoped insertion without sending")
            check(f.voice.draft.text == "synthetic alpha draft", "configuration preserves the owned draft")
        }
        await run("failed persistence preserves live configuration and drafts") { f in
            let before = f.controls.settings
            let stored = try Data(contentsOf: f.store.url)
            // A directory at the backup destination makes a real atomic store save fail.
            try FileManager.default.createDirectory(at: f.store.backupURL, withIntermediateDirectories: false)
            let saved = f.controls.updateSettings { $0.workspaces[0].name = "Changed synthetic name" }
            check(!saved && f.controls.settings == before, "failed save cannot publish unsaved settings")
            let after = try Data(contentsOf: f.store.url)
            check(after == stored, "failed save preserves original settings bytes")
            check(f.voice.draft.text == "synthetic alpha draft", "failed save retains owned draft")
        }
        await run("tool presets create independent workspaces without replacing existing settings") { f in
            let before = f.controls.settings
            for bundle in ["com.openai.codex", "com.anthropic.claudefordesktop", "com.tencent.workbuddy.mac", "com.workbuddy.workbuddy-ai"] {
                f.controls.addWorkspace(InstalledTool(name: "Synthetic tool", bundleIdentifier: bundle, appPath: nil, version: nil))
                let created = f.controls.workspace!
                check(created.buttonActions == CodingToolPreset.matching(bundleIdentifier: bundle)?.buttonActions, "new tool gets its preset")
                check(created.binding == nil && created.shortcuts.isEmpty, "preset never fabricates verified controls or shortcuts")
            }
            check(f.controls.settings.mappings == before.mappings, "preset creation preserves all calibrated HID keys")
            check(Array(f.controls.settings.workspaces.prefix(2)) == before.workspaces, "existing workspace actions and bindings remain unchanged")
            f.controls.selectWorkspace(f.first.id)
            check(f.voice.draft.text == "synthetic alpha draft", "adding presets retains earlier workspace draft")
        }
        await run("explicit preset restore preserves bindings drafts other workspaces and learned keys") { f in
            var profile = f.first
            profile.bundleIdentifier = "com.openai.codex"
            profile.previewURL = "http://localhost:3000"
            profile.shortcuts = [ActionShortcut(action: .sendDraft, keyCode: 36)]
            f.controls.updateWorkspace(profile)
            f.configureOK(single: .insertDraft)
            let before = f.controls.settings
            check(f.controls.applyToolPreset(to: profile), "supported preset applies")
            var expected = before.workspaces[0]
            expected.buttonActions = CodingToolPreset.codex.buttonActions; expected.shortcuts = []
            check(f.first == expected, "restore changes only scoped actions and optional shortcuts")
            check(f.second == before.workspaces[1] && f.controls.settings.mappings == before.mappings, "other workspace and calibration preserved")
            check(f.voice.draft.text == "synthetic alpha draft" && f.ax.writes.isEmpty && f.ax.presses.isEmpty, "applying preset never inserts or sends")
            let loaded = try f.store.load()
            check(loaded == f.controls.settings, "scoped preset persists and reloads")
            f.controls.selectedButton = .back
            let backInput = f.controls.mapping.input
            _ = f.controls.updateMapping { $0.single = .none }
            f.controls.restoreButtonDefaults()
            check(f.controls.mapping.single == .cancel && f.controls.mapping.input == backInput, "action reset retains calibration")
        }
        for source in ["timer", "input"] {
            await run("\(source) batch drops old actions after switching workspace") { f in
                let third = WorkspaceProfile(name: "Synthetic Gamma", bundleIdentifier: "test.synthetic")
                _ = f.controls.updateSettings { $0.workspaces.append(third) }
                f.configureOK(single: .nextWorkspace, double: .focusTarget)
                f.controls.selectedButton = .left
                _ = f.controls.updateMapping { $0.single = .nextWorkspace; $0.double = .focusTarget }
                f.seize()
                f.input.tap(42); f.input.tap(40)
                if source == "input" {
                    // Deliberately delay the run loop so process() resolves both queued timers.
                    func elapse() { Thread.sleep(forTimeInterval: 0.36) }
                    elapse(); f.input.emit(41, down: true)
                } else {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }
                check(f.voice.workspaceID == f.second.id, "only first workspace switch executes; old OK action cannot jump to third")
            }
        }
        await run("workspace switches retain independent drafts and capture ownership") { f in
            f.controls.selectWorkspace(f.second.id); f.voice.replaceDraft("synthetic beta draft")
            f.controls.selectWorkspace(f.first.id)
            check(f.voice.draft.text == "synthetic alpha draft", "alpha draft retained")
            f.bluetooth.stream(true); f.speech.onText?("synthetic utterance", false)
            f.controls.selectWorkspace(f.second.id)
            check(f.voice.workspaceID == f.first.id, "capture locks the workspace")
            f.bluetooth.stream(false)
            f.controls.selectWorkspace(f.second.id)
            check(f.voice.workspaceID == f.first.id, "recognition finalization still locks the workspace")
            f.speech.onFinished?(); f.controls.selectWorkspace(f.second.id)
            check(f.voice.draft.text == "synthetic beta draft", "beta never receives alpha utterance")
            f.controls.selectWorkspace(f.first.id)
            check(f.voice.draft.text == "synthetic alpha draft\nsynthetic utterance", "utterance stays with its original destination")
        }
        await run("calibration observes one key without executing its mapping") { f in
            f.configureOK(single: .insertDraft)
            f.hid.discover(); f.hid.startObservation(deviceID: "synthetic-remote")
            f.controls.learnButton()
            let now = ProcessInfo.processInfo.systemUptime
            f.input.emit(down: true, at: now); f.input.emit(down: false, at: now + 0.7)
            await settle(f)
            check(f.controls.learningButton == nil && f.controls.mapping.input?.supportsHold == true, "press and release calibrate hold support")
            check(!f.controls.mappingsEnabled && f.ax.activations == 0 && f.ax.writes.isEmpty, "calibration never dispatches an action")
        }
        await run("validated uppercase descriptor matches lowercase device reports") { f in
            f.configureOK(single: .nextWorkspace)
            let saved = f.controls.updateMapping { $0.input?.descriptorHash = IntegrationHID.hash.uppercased() }
            check(saved, "uppercase descriptor is valid configuration")
            f.seize(); f.input.tap(); await settle(f)
            check(f.voice.workspaceID == f.second.id, "descriptor hex case cannot prevent calibrated input matching")
        }
        await run("observation and unconfirmed exclusive input cannot dispatch") { f in
            f.configureOK(single: .insertDraft)
            f.hid.discover(); f.hid.startObservation(deviceID: "synthetic-remote")
            f.controls.setSuppressionConfirmed(true); f.controls.enableMappings(); f.input.tap()
            await settle(f)
            check(!f.controls.suppressionConfirmed && !f.controls.mappingsEnabled, "observation cannot satisfy exclusive suppression")
            f.hid.seize(deviceID: "synthetic-remote"); f.controls.enableMappings(); f.input.tap()
            await settle(f)
            check(f.ax.activations == 0 && f.ax.writes.isEmpty, "exclusive alone still cannot execute")
            f.controls.setSuppressionConfirmed(true); f.controls.enableMappings(); f.input.tap()
            await settle(f)
            check(f.ax.writes.count == 1, "explicit suppression confirmation enables calibrated dispatch")
        }
        await run("button inspection selects keys without invoking their actions") { f in
            f.configureOK(single: .insertDraft); f.seize()
            f.controls.page = .buttons; f.controls.selectedButton = .home
            f.input.tap(); await settle(f)
            check(f.controls.selectedButton == .ok, "unlocked button page follows the physical key")
            check(f.ax.activations == 0 && f.ax.writes.isEmpty, "inspection cannot execute the selected key")
            f.controls.lockButtonSelection = true
            f.input.tap(); await settle(f)
            check(f.ax.writes.count == 1, "explicit execution lock permits calibrated mapping tests")
        }
        for transition in ["open button page", "unlock button page"] {
            await run("\(transition) cancels an already pending hold") { f in
                f.configureOK(single: .none, long: .nextWorkspace); f.seize()
                if transition == "unlock button page" { f.controls.page = .buttons; f.controls.lockButtonSelection = true }
                f.input.emit(down: true)
                if transition == "unlock button page" { f.controls.lockButtonSelection = false }
                else { f.controls.page = .buttons }
                try? await Task.sleep(nanoseconds: 750_000_000)
                check(f.voice.workspaceID == f.first.id, "inspection cannot inherit a hold queued in execution mode")
                check(f.ax.activations == 0 && f.ax.writes.isEmpty, "inspection transition never invokes a tool action")
            }
        }
        await run("workspace picker owns remapped navigation and confirmation buttons") { f in
            f.configureOK(single: .insertDraft, long: .insertDraft, double: .insertDraft)
            f.controls.selectedButton = .right
            _ = f.controls.updateMapping { $0.single = .sendDraft; $0.long = .sendDraft; $0.double = .sendDraft }
            f.seize(); f.controls.perform(.workspacePicker)
            f.input.tap(43); f.input.tap(43)
            check(f.controls.pickerIndex == 2 && f.voice.workspaceID == f.first.id, "physical navigation changes selection before confirmation")
            f.input.tap(); await settle(f)
            check(!f.controls.showingWorkspaces && f.voice.workspaceID == f.second.id, "OK confirms the selected workspace")
            check(f.ax.activations == 0 && f.ax.writes.isEmpty && f.ax.presses.isEmpty, "picker suppresses custom insert/send/hold/double actions")
        }
        await run("action picker executes the selected action once and back dismisses") { f in
            f.configureOK(single: .sendDraft, long: .sendDraft, double: .sendDraft)
            f.controls.selectedButton = .right
            _ = f.controls.updateMapping { $0.single = .none; $0.long = .stopTask; $0.double = .stopTask }
            f.seize(); f.controls.perform(.actionPicker)
            f.input.tap(43); f.input.tap(43)
            check(f.controls.menuActions[f.controls.pickerIndex] == .insertDraft, "navigation works even when its normal single action is disabled")
            f.input.tap(); await settle(f)
            check(!f.controls.showingActions && f.ax.writes.count == 1 && f.ax.presses.isEmpty, "OK invokes selected insert once instead of its send mapping")
            f.controls.perform(.actionPicker); f.input.tap(44)
            check(!f.controls.showingActions && f.ax.presses.isEmpty, "Back dismisses the picker without stopping a task")
        }
        for pending in ["double click", "hold"] {
            await run("production timer resolves a pending \(pending)") { f in
                f.configureOK(single: pending == "hold" ? .none : .nextWorkspace,
                              long: pending == "hold" ? .nextWorkspace : nil,
                              double: pending == "double click" ? .focusTarget : nil)
                f.seize()
                f.input.emit(down: true)
                if pending == "double click" { f.input.emit(down: false) }
                check(f.voice.workspaceID == f.first.id, "gesture waits for its production deadline")
                try? await Task.sleep(nanoseconds: 750_000_000)
                check(f.voice.workspaceID == f.second.id, "the actual coordinator timer dispatches the completed gesture")
            }
            for reset in ["pause", "device loss", "configuration change"] {
                await run("\(reset) cancels pending \(pending)") { f in
                    f.configureOK(single: .nextWorkspace, long: pending == "hold" ? .nextWorkspace : nil,
                                  double: pending == "double click" ? .nextWorkspace : nil)
                    f.seize()
                    let now = ProcessInfo.processInfo.systemUptime
                    f.input.emit(down: true, at: now)
                    if pending == "double click" { f.input.emit(down: false, at: now + 0.01) }
                    switch reset {
                    case "pause": f.controls.pauseMappings(releaseDevice: false)
                    case "device loss": f.input.disconnect(); f.hid.pause(); f.seize()
                    default: _ = f.controls.updateSettings { $0.workspaces[0].name = "Synthetic renamed workspace" }
                    }
                    if reset != "configuration change" { f.controls.enableMappings() }
                    // Use the real timer: ControlsModel intentionally rejects HID time as gesture time.
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    f.input.emit(down: false)
                    check(f.voice.workspaceID == f.first.id, "a discarded gesture cannot switch a workspace later")
                    check(f.ax.writes.isEmpty && f.ax.presses.isEmpty, "discarded gesture never mutates a tool")
                }
            }
        }
        for changed in ["capture", "device", "draft", "permission"] {
            await run("\(changed) change during insertion activation blocks mutation") { f in
                f.seize(); f.ax.activationPaused = true
                f.controls.perform(.insertDraft)
                await waitUntil("paused insertion activation") { f.ax.activationContinuation != nil }
                switch changed {
                case "capture": f.bluetooth.stream(true)
                case "device": f.input.disconnect()
                case "draft": f.voice.replaceDraft("edited synthetic draft")
                default: f.ax.isTrusted = false
                }
                f.ax.resumeActivation(); await settle(f)
                check(f.ax.writes.isEmpty && f.ax.presses.isEmpty, "stale insertion cannot write or press")
                check(!f.controls.operationInProgress, "aborted insertion releases operation state")
            }
        }
        await run("serialized operation rejects overlapping actions and settings") { f in
            f.seize(); f.ax.activationPaused = true; f.controls.perform(.insertDraft)
            await waitUntil("first activation") { f.ax.activationContinuation != nil }
            f.controls.perform(.insertDraft); f.controls.perform(.focusTarget); f.controls.perform(.sendDraft)
            f.controls.selectWorkspace(f.second.id)
            let saved = f.controls.updateSettings { $0.workspaces[0].name = "Must not apply" }
            check(f.ax.activations == 1 && !saved && f.voice.workspaceID == f.first.id, "one operation owns the target and configuration")
            f.ax.resumeActivation(); await settle(f)
            check(f.ax.writes.count == 1 && f.ax.presses.isEmpty, "overlap cannot duplicate insertion or send")
        }
        await run("review and confirmation send once without inserting again") { f in
            await preview(f)
            f.controls.confirmSend(); f.controls.confirmSend(); await settle(f)
            check(f.ax.writes.count == 1 && f.ax.presses == ["send"], "confirmation consumes one review without repeated insertion")
            check(f.controls.pendingSend == nil && f.voice.draft.text == "synthetic alpha draft", "confirmation clears review and preserves local draft")
            f.controls.perform(.sendDraft); await settle(f)
            check(f.controls.pendingSend == nil && f.ax.presses.count == 1, "a sent insertion cannot authorize another send")
        }
        for changed in ["capture", "device", "draft", "permission", "cancel"] {
            await run("\(changed) change during confirmation activation blocks send") { f in
                await preview(f)
                f.ax.activationPaused = true; f.controls.confirmSend()
                await waitUntil("paused confirmation activation") { f.ax.activationContinuation != nil }
                switch changed {
                case "capture": f.bluetooth.stream(true)
                case "device": f.input.disconnect()
                case "draft": f.voice.replaceDraft("edited after confirmation")
                case "permission": f.ax.isTrusted = false
                default: f.controls.perform(.cancel)
                }
                f.ax.resumeActivation(); await settle(f)
                check(f.ax.presses.isEmpty && f.ax.writes.count == 1, "changed live authorization cannot submit reviewed text")
                check(f.controls.pendingSend == nil && !f.controls.operationInProgress, "invalidated confirmation settles without a reusable review")
            }
        }
        for changed in ["draft", "workspace", "settings", "capture", "suppression"] {
            await run("\(changed) invalidates an open review") { f in
                await preview(f)
                switch changed {
                case "draft": f.voice.replaceDraft("new synthetic draft")
                case "workspace": f.controls.selectWorkspace(f.second.id)
                case "settings": _ = f.controls.updateSettings { $0.workspaces[0].name = "Renamed synthetic workspace" }
                case "capture": f.bluetooth.stream(true)
                default: f.controls.setSuppressionConfirmed(false)
                }
                try? await Task.sleep(nanoseconds: 3_000_000)
                check(f.controls.pendingSend == nil, "stale review disappears")
                f.controls.confirmSend(); await settle(f)
                check(f.ax.presses.isEmpty, "closed review never sends")
            }
        }
        await run("cancel dismisses sheets and cancels queued insertion") { f in
            f.controls.showingActions = true; f.controls.showingWorkspaces = true
            f.ax.activationPaused = true; f.controls.perform(.insertDraft)
            await waitUntil("cancelled activation") { f.ax.activationContinuation != nil }
            f.controls.perform(.cancel)
            check(!f.controls.showingActions && !f.controls.showingWorkspaces && f.controls.pendingSend == nil, "cancel dismisses transient selection and review state")
            f.ax.resumeActivation(); await settle(f)
            check(f.ax.writes.isEmpty && f.ax.presses.isEmpty, "cancelled insertion never mutates the target")
        }
        await run("cancel learning keeps old bindings and releases configuration lock") { f in
            f.voice.replaceDraft("")
            let original = f.controls.settings
            f.controls.learn(.input, for: f.first)
            await Task.yield()
            check(f.controls.learningTool && f.controls.operationInProgress, "learning owns configuration while its countdown is pending")
            f.controls.cancelToolLearning(); await settle(f)
            check(!f.controls.learningTool && f.controls.settings == original && !f.controls.hasLearnedInput(for: f.first.id), "cancel leaves old bindings and learned-input state intact")
            check(f.ax.writes.isEmpty && f.ax.presses.isEmpty, "learning cancellation never invokes input actions")
        }
        for change in ["draft", "capture"] {
            await run("\(change) change cancels pending input learning") { f in
                f.voice.replaceDraft("")
                let original = f.controls.settings
                f.controls.learn(.input, for: f.first)
                await Task.yield()
                check(f.controls.learningTool, "learning countdown has started")
                if change == "draft" { f.voice.replaceDraft("synthetic draft created during countdown") }
                else { f.bluetooth.stream(true) }
                await settle(f)
                check(!f.controls.learningTool && f.controls.settings == original && !f.controls.hasLearnedInput(for: f.first.id),
                      "new draft ownership prevents pending input rebinding")
                check(f.ax.activations == 0 && f.ax.writes.isEmpty && f.ax.presses.isEmpty, "cancelled learning has no target side effects")
            }
        }
        for observation in ["incomplete", "unknown focus", "unknown running state"] {
            await run("\(observation) cannot authorize sending") { f in
                f.seize(); f.controls.perform(.insertDraft); await settle(f)
                switch observation {
                case "incomplete": f.ax.complete = false
                case "unknown focus": f.ax.frontmostPID = nil
                default: f.ax.windows[0].children[3].enabled = nil
                }
                f.controls.perform(.sendDraft); await settle(f)
                check(f.controls.pendingSend == nil && f.ax.presses.isEmpty, "unknown live state cannot create a send review")
            }
        }
        print("\(scenarios) controls integration scenarios, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
