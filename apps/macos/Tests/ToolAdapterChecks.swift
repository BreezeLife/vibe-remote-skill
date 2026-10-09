import AppKit
import Foundation
import VibeRemoteCore

// Synthetic only: constructing the adapter below never constructs SystemToolAXDriver.
@MainActor final class FakeToolAXDriver: ToolAXDriver {
    var trusted = true
    var front: Int32 = 42
    var version = "1.0"
    var pid: Int32 = 42
    var windows: [ToolAXNode] = []
    var focusedWindow: String? = "window"
    var focused: String? = "input"
    var pointer: String? = "anchor"
    var text = "existing"
    var presses: [String] = []
    var writes = 0
    var activationWorks = true
    var focusWorks = true
    var writeWorks = true
    var sendChangesState = true
    var stopChangesState = true
    var complete = true
    var snapshotHook: (() -> Void)?
    var activationPaused = false
    var activationContinuation: CheckedContinuation<Void, Never>?
    var shortcuts: [ActionShortcut] = []
    var shortcutFocusWorks = true
    var valuesRead = 0
    var focusHook: (() -> Void)?
    var openedURLs: [URL] = []
    var openHook: (() -> Void)?
    var openPaused = false
    var openContinuation: CheckedContinuation<Void, Never>?
    var steerChangesState = true
    var focuses = 0
    var writeThrows = false
    var pressThrows = false
    var isTrusted: Bool { trusted }
    func requestPermission() { fatalError("Tests must never request permission") }
    func application(bundleIdentifier: String, appPath: String?) throws -> ToolApplication {
        ToolApplication(bundleIdentifier: bundleIdentifier, path: "/Applications/Fake.app", version: version, processID: pid)
    }
    func installedApplication(bundleIdentifier: String) -> ToolApplication? { nil }
    func application(at url: URL) throws -> ToolApplication { try application(bundleIdentifier: "test.fake", appPath: url.path) }
    func activate(_ application: ToolApplication) async throws {
        if activationPaused { await withCheckedContinuation { activationContinuation = $0 } }
        if activationWorks { front = pid }
    }
    func openURL(_ url: URL, for application: ToolApplication) async throws {
        openedURLs.append(url)
        if openPaused { await withCheckedContinuation { openContinuation = $0 } }
        openHook?()
    }
    func snapshot(_ application: ToolApplication) throws -> ToolAXObservation {
        snapshotHook?()
        return ToolAXObservation(processID: pid, frontmostPID: front, focusedWindowID: focusedWindow,
                                 focusedNodeID: focused, pointerNodeID: pointer, windows: windows, complete: complete)
    }
    func value(of node: ToolAXNode) throws -> String { valuesRead += 1; return text }
    func setValue(_ value: String, of node: ToolAXNode) throws {
        writes += 1
        if writeThrows { throw ToolAdapterError("synthetic uncertain write") }
        if writeWorks { text = value }
    }
    func focus(_ node: ToolAXNode) throws { focuses += 1; if focusWorks { focused = node.id }; focusHook?() }
    func perform(_ action: String, on node: ToolAXNode) throws {
        presses.append(node.id)
        if pressThrows { throw ToolAdapterError("synthetic uncertain press") }
        if node.id == "send" && sendChangesState { setRunning(true); text = "" }
        if node.id == "stop" && stopChangesState { setRunning(false) }
        if node.id == "steer" && steerChangesState {
            text = ""
            windows[0].children.removeAll { $0.id == "steer" }
        }
    }
    func pressShortcut(_ shortcut: ActionShortcut, processID: Int32) throws {
        shortcuts.append(shortcut)
        switch shortcut.action {
        case .focusTarget: if shortcutFocusWorks { focused = "input" }
        case .sendDraft: setRunning(true); text = ""
        case .stopTask: setRunning(false)
        case .scrollUp, .scrollDown: windows[0].children[4].scrollPosition = 0.6
        default: break
        }
    }
    func setRunning(_ running: Bool) {
        if let stop = windows[0].children.firstIndex(where: { $0.id == "stop" }) {
            windows[0].children[stop].enabled = running
        } else if running {
            windows[0].children.append(ToolAXNode(id: "stop", role: "AXButton", identifier: "stop", label: "Stop generating",
                enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        }
        if let send = windows[0].children.firstIndex(where: { $0.id == "send" }) { windows[0].children[send].enabled = !running }
    }
    func resetTree() {
        windows = [ToolAXNode(id: "window", role: "AXWindow", label: "Project Alpha", children: [
            ToolAXNode(id: "input", role: "AXTextArea", identifier: "composer", label: "Message", editable: true, enabled: true,
                       visible: true, contentScopeID: "main-content"),
            ToolAXNode(id: "anchor", role: "AXHeading", identifier: "task-alpha", label: "Task Alpha",
                       visible: true, contentScopeID: "main-content"),
            ToolAXNode(id: "send", role: "AXButton", identifier: "send", label: "Send message", enabled: true, actions: ["AXPress"],
                       visible: true, contentScopeID: "main-content"),
            ToolAXNode(id: "stop", role: "AXButton", identifier: "stop", label: "Stop generating", enabled: false, actions: ["AXPress"],
                       visible: true, contentScopeID: "main-content")
        ])]
    }
}

@MainActor func runChecks() async {
    var checks = 0
    var failures = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { failures += 1; print("FAIL: \(message)") }
    }
    func rejects(_ name: String, _ operation: () async throws -> Void) async {
        do { try await operation(); check(false, name) } catch { check(true, name) }
    }
    func fixture() -> (FakeToolAXDriver, ToolAdapter, WorkspaceProfile) {
        let driver = FakeToolAXDriver(); driver.resetTree()
        let input = AXLocator(path: [0], role: "AXTextArea", identifier: "composer", label: "Message")
        let anchor = AXLocator(path: [1], role: "AXHeading", identifier: "task-alpha", label: "Task Alpha")
        let send = AXLocator(path: [2], role: "AXButton", identifier: "send", label: "Send message")
        let stop = AXLocator(path: [3], role: "AXButton", identifier: "stop", label: "Stop generating")
        let binding = ToolBinding(appVersion: "1.0", windowTitle: "Project Alpha", input: input, taskAnchor: anchor,
                                  sendControl: send, stopControl: stop)
        let workspace = WorkspaceProfile(name: "Alpha", bundleIdentifier: "test.fake", binding: binding)
        return (driver, ToolAdapter(driver: driver), workspace)
    }
    func codexFixture() -> (FakeToolAXDriver, ToolAdapter, WorkspaceProfile, CodexConversation) {
        let (driver, _, original) = fixture()
        let conversation = CodexConversation(id: "11111111-1111-4111-8111-111111111111", title: "Task Alpha", projectPath: "/tmp/project-alpha")
        var workspace = original
        workspace.bundleIdentifier = "com.openai.codex"
        workspace.codexConversation = conversation
        driver.windows[0].url = "codex://threads/" + conversation.id
        return (driver, ToolAdapter(driver: driver, navigationTimeout: 0.01), workspace, conversation)
    }
    func addSteer(_ driver: FakeToolAXDriver, label: String = "Steer now") {
        driver.windows[0].children.append(ToolAXNode(id: "steer", role: "AXButton", identifier: "steer-current", label: label,
            enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
    }
    do {
        let (d, a, w) = fixture()
        let inserted = try await a.insert("new draft", for: w)
        check(inserted == "existing\nnew draft" && d.text == inserted, "append preserves existing input")
        let preview = try await a.prepareSend(for: w)
        check(preview.text == inserted, "confirmation contains full input")
        d.front = 99
        let outcome = try await a.confirmSend(preview, for: w)
        check(outcome.confirmed && d.presses == ["send"], "reactivation and semantic send outcome observed")
        await rejects("single-use confirmation") { _ = try await a.confirmSend(preview, for: w) }
        check(d.presses.count == 1, "confirmation replay never presses")
        let stopped = try await a.stop(for: w)
        check(stopped.confirmed && d.presses == ["send", "stop"], "observed task stop")
    } catch { check(false, "happy path: \(error)") }
    for kind in ["permission", "version", "front", "window", "task", "secure", "ambiguous", "incomplete", "focus"] {
        let (d, a, w) = fixture()
        switch kind {
        case "permission": d.trusted = false
        case "version": d.version = "2.0"
        case "front": d.front = 99; d.activationWorks = false
        case "window": d.focusedWindow = "another"
        case "task": d.windows[0].children[1].label = "Other Task"
        case "secure": d.windows[0].children[0].secure = true
        case "ambiguous": var copy = d.windows[0].children[0]; copy.id = "duplicate"; d.windows[0].children.append(copy)
        case "incomplete": d.complete = false
        case "focus": d.focused = "other"; d.focusWorks = false
        default: break
        }
        await rejects("insert rejects \(kind)") { _ = try await a.insert("draft", for: w) }
        check(d.writes == 0 && d.presses.isEmpty, "\(kind) never writes or presses")
    }
    for kind in ["sidebar", "differentContent", "hidden", "unknownVisibility", "noMainScope"] {
        let (d, a, w) = fixture()
        switch kind {
        case "sidebar": d.windows[0].children[1].inNavigation = true
        case "differentContent": d.windows[0].children[0].contentScopeID = "new-task-main"
        case "hidden": d.windows[0].children[1].visible = false
        case "unknownVisibility": d.windows[0].children[1].visible = nil
        case "noMainScope": d.windows[0].children[1].contentScopeID = nil
        default: break
        }
        await rejects("stale/present task anchor rejects \(kind)") { _ = try await a.insert("draft", for: w) }
        check(d.writes == 0, "\(kind) never inserts into different task")
    }
    do {
        let (d, a, w) = fixture(); d.writeWorks = false
        await rejects("write readback mismatch") { _ = try await a.insert("draft", for: w) }
        check(d.text == "existing", "failed insertion preserves fake original")
    }
    for kind in ["text", "binding", "version", "pid", "running", "sendDisabled", "task"] {
        let (d, a, initial) = fixture(); var w = initial
        do {
            let preview = try await a.prepareSend(for: w)
            switch kind {
            case "text": d.text = "changed"
            case "binding": w.name = "Changed workspace"
            case "version": d.version = "2"
            case "pid": d.pid = 55
            case "running": d.setRunning(true)
            case "sendDisabled": d.windows[0].children[2].enabled = false
            case "task": d.windows[0].children[1].identifier = "other"
            default: break
            }
            await rejects("confirmation invalidated by \(kind)") { _ = try await a.confirmSend(preview, for: w) }
            check(d.presses.isEmpty, "\(kind) never sends")
        } catch { check(false, "prepare \(kind): \(error)") }
    }
    do {
        let (d, a, w) = fixture()
        await rejects("stop requires running task") { _ = try await a.stop(for: w) }
        d.setRunning(true); d.stopChangesState = false
        let result = try await a.stop(for: w)
        check(!result.confirmed, "press without changed stop state not called success")
    } catch { check(false, "stop check: \(error)") }
    do {
        let (d, a, w) = fixture()
        let learned = try a.learnInput(for: w)
        let binding = try a.learnTaskAnchor(for: w, input: learned)
        check(binding.input.path == [0] && binding.taskAnchor.path == [1], "learn separate input and anchor")
        check(d.valuesRead == 0, "learning never reads transcript or input values")
        d.pointer = "input"
        await rejects("input cannot be task anchor") { _ = try a.learnTaskAnchor(for: w, input: learned) }
        d.pointer = "stop"; d.windows[0].children[3].label = "Stop"
        await rejects("generic browser stop rejected") { _ = try a.learnControl(for: w, kind: .stop) }
        var terminal = w; terminal.bundleIdentifier = "com.apple.Terminal"
        await rejects("terminal rejected") { _ = try await a.insert("draft", for: terminal) }
        check(d.writes == 0 && d.presses.isEmpty, "learning has no writes/presses")
    } catch { check(false, "learning: \(error)") }
    do {
        let (d, a, w) = fixture(); d.activationPaused = true
        let task = Task { try await a.insert("must not insert", for: w) }
        while d.activationContinuation == nil { await Task.yield() }
        task.cancel(); d.activationContinuation?.resume()
        await rejects("cancellation during activation") { _ = try await task.value }
        check(d.writes == 0 && d.presses.isEmpty && d.shortcuts.isEmpty, "cancelled activation never mutates target")
    }
    do {
        let (d, a, w) = fixture(); d.activationPaused = true
        var allowed = true
        a.authorizeOperation = { if !allowed { throw ToolAdapterError("live operation authorization changed") } }
        let task = Task { try await a.insert("must not insert", for: w) }
        while d.activationContinuation == nil { await Task.yield() }
        allowed = false; d.activationContinuation?.resume()
        await rejects("live authorization changed while activating") { _ = try await task.value }
        check(d.writes == 0 && d.presses.isEmpty && d.shortcuts.isEmpty, "revoked live authorization prevents input mutation")
    }
    do {
        let (d, a, original) = fixture(); var w = original
        w.shortcuts = [ActionShortcut(action: .focusTarget, keyCode: 37, modifiers: [.command])]
        d.focused = "other"
        try await a.focus(for: w)
        check(d.shortcuts.count == 1 && d.focused == "input", "allowed focus shortcut requires verified resulting input")
        d.focused = "other"; d.shortcutFocusWorks = false
        await rejects("focus shortcut cannot establish success itself") { try await a.focus(for: w) }
    } catch { check(false, "focus shortcut: \(error)") }
    for matched in [false, true] {
        let (d, a, original) = fixture(); var w = original
        w.shortcuts = [ActionShortcut(action: .sendDraft, keyCode: 36, modifiers: [.command])]
        if matched { d.windows[0].children[2].shortcutKeyCode = 36; d.windows[0].children[2].shortcutModifiers = [.command] }
        do {
            let preview = try await a.prepareSend(for: w)
            if matched {
                let result = try await a.confirmSend(preview, for: w)
                check(result.confirmed && d.shortcuts.count == 1 && d.presses.isEmpty, "matching observed send key uses verified shortcut")
            } else {
                await rejects("unobserved send key blocked") { _ = try await a.confirmSend(preview, for: w) }
                check(d.shortcuts.isEmpty && d.presses.isEmpty, "no blind send key fallback")
            }
        } catch { check(false, "send shortcut: \(error)") }
    }
    do {
        let (d, a, original) = fixture(); var w = original
        w.shortcuts = [ActionShortcut(action: .scrollDown, keyCode: 125)]
        d.windows[0].children.append(ToolAXNode(id: "scroll", role: "AXScrollArea", enabled: true, scrollPosition: 0.4))
        try await a.scroll(.down, for: w)
        check(d.shortcuts.count == 1 && d.focused == "scroll", "scroll shortcut scoped to observed focused scroll area")
        d.focusWorks = false; d.focused = "input"
        await rejects("scroll focus failure blocks key") { try await a.scroll(.down, for: w) }
        check(d.shortcuts.count == 1, "scroll never falls through to input arrow key")
    } catch { check(false, "scroll shortcut: \(error)") }
    for kind in ["absent", "unknown", "duplicate", "unbound"] {
        let (d, a, original) = fixture(); var w = original
        switch kind {
        case "absent": d.windows[0].children.removeLast()
        case "unknown": d.windows[0].children[3].enabled = nil
        case "duplicate": var duplicate = d.windows[0].children[3]; duplicate.id = "second-stop"; d.windows[0].children.append(duplicate)
        case "unbound": w.binding?.stopControl = nil
        default: break
        }
        if kind == "absent" {
            do { _ = try await a.prepareSend(for: w); check(true, "learned stop absence plus send enabled establishes idle") }
            catch { check(false, "known stop absence: \(error)") }
        } else {
            await rejects("send blocks \(kind) stop state") { _ = try await a.prepareSend(for: w) }
        }
    }
    for index in [2, 3] {
        for kind in ["differentContent", "hidden", "navigation", "unknownVisibility", "noScope"] {
            let (d, a, w) = fixture()
            switch kind {
            case "differentContent": d.windows[0].children[index].contentScopeID = "other-task"
            case "hidden": d.windows[0].children[index].visible = false
            case "navigation": d.windows[0].children[index].inNavigation = true
            case "unknownVisibility": d.windows[0].children[index].visible = nil
            case "noScope": d.windows[0].children[index].contentScopeID = nil
            default: break
            }
            d.pointer = index == 2 ? "send" : "stop"
            await rejects("learning rejects \(kind) control \(index)") {
                _ = try a.learnControl(for: w, kind: index == 2 ? .send : .stop)
            }
            await rejects("send readiness rejects \(kind) control \(index)") { _ = try await a.prepareSend(for: w) }
            if index == 3 {
                d.setRunning(true)
                await rejects("stop rejects \(kind) control") { _ = try await a.stop(for: w) }
            }
            check(d.presses.isEmpty && d.shortcuts.isEmpty, "\(kind) control \(index) never activates")
        }
    }
    for phase in ["prepare", "confirm"] {
        for kind in ["renamed", "identifier", "genericStop", "genericCancel", "unknownVisibility", "opaqueSameIdentifier", "disabledChanged"] {
            let (d, a, w) = fixture()
            do {
                let preview = phase == "confirm" ? try await a.prepareSend(for: w) : nil
                // Some tools keep Send enabled to queue messages while a task is still running.
                d.windows[0].children[3].enabled = true
                switch kind {
                case "renamed": d.windows[0].children[3].label = "Cancel generation"
                case "identifier": d.windows[0].children[3].identifier = "stop-v2"
                case "genericStop":
                    d.windows[0].children[3].label = "Stop"; d.windows[0].children[3].identifier = "control-v2"
                case "genericCancel":
                    d.windows[0].children[3].label = "Cancel"; d.windows[0].children[3].identifier = "control-v2"
                case "unknownVisibility":
                    d.windows[0].children[3].label = "Cancel generation"; d.windows[0].children[3].visible = nil
                case "opaqueSameIdentifier": d.windows[0].children[3].label = "Working…"
                case "disabledChanged":
                    d.windows[0].children[3].label = "Cancel generation"; d.windows[0].children[3].enabled = false
                default: break
                }
                await rejects("\(phase) rejects changed stop \(kind)") {
                    if let preview { _ = try await a.confirmSend(preview, for: w) }
                    else { _ = try await a.prepareSend(for: w) }
                }
                check(d.presses.isEmpty && d.shortcuts.isEmpty, "\(phase) changed \(kind) never sends")
            } catch { check(false, "changed stop fixture: \(error)") }
        }
    }
    for placement in ["otherScope", "navigation", "provablyHidden"] {
        let (d, a, w) = fixture()
        d.windows[0].children.removeLast()
        d.windows[0].children.append(ToolAXNode(id: "unrelated-stop", role: "AXButton", identifier: "other-stop", label: "Cancel",
            enabled: true, actions: ["AXPress"], visible: placement == "provablyHidden" ? false : true,
            contentScopeID: placement == "otherScope" ? "other-panel" : "main-content", inNavigation: placement == "navigation"))
        do {
            _ = try await a.prepareSend(for: w)
            check(true, "true bound-stop absence ignores \(placement) control")
        } catch { check(false, "unrelated \(placement) stop must not imply bound task state: \(error)") }
    }
    do {
        let (d, a, original) = fixture(); var w = original
        // Learned Send and Stop can legitimately alternate on the same button/path.
        w.binding?.sendControl = AXLocator(path: [3], role: "AXButton", identifier: "submit", label: "Send message")
        w.binding?.stopControl = AXLocator(path: [3], role: "AXButton", identifier: "submit", label: "Stop generating")
        d.windows[0].children[3].identifier = "submit"
        d.windows[0].children[3].label = "Send message"
        d.windows[0].children[3].enabled = true
        _ = try await a.prepareSend(for: w)
        check(true, "separately learned Send may replace Stop on same path and identifier")
    } catch { check(false, "known Send/Stop toggle: \(error)") }
    do {
        let (d, a, original) = fixture(); var w = original
        w.shortcuts = [ActionShortcut(action: .stopTask, keyCode: 53)]
        d.setRunning(true); d.focused = "other"
        d.windows[0].children[3].shortcutKeyCode = 53
        d.windows[0].children[3].shortcutModifiers = []
        d.focusHook = {
            d.windows[0].children[3].shortcutKeyCode = 8
            d.windows[0].children[3].shortcutModifiers = [.control]
        }
        await rejects("stop shortcut re-resolves control after focus") { _ = try await a.stop(for: w) }
        check(d.presses.isEmpty && d.shortcuts.isEmpty, "stale stop metadata never emits key")
    }
    do {
        let (d, a, w) = fixture(); d.sendChangesState = false
        let preview = try await a.prepareSend(for: w)
        let result = try await a.confirmSend(preview, for: w)
        check(!result.confirmed && d.presses.count == 1, "send AXPress is not task acceptance without observed transition")
    } catch { check(false, "unconfirmed send: \(error)") }
    do {
        let (d, a, original, conversation) = codexFixture(); var w = original
        w.binding = nil; d.focused = "other"
        let binding = try await a.openCodexConversation(w, knownConversations: [conversation])
        check(d.openedURLs.map(\.absoluteString) == ["codex://threads/" + conversation.id], "navigation opens exact Codex URL once")
        check(binding.taskAnchor.label == conversation.title && d.focused == "input", "exact live thread identity binds and focuses input")
        check(d.writes == 0 && d.presses.isEmpty && d.valuesRead == 0, "navigation never reads or writes draft text or submits")
        w.binding = binding
        d.windows[0].url = "codex://threads/22222222-2222-4222-8222-222222222222"
        await rejects("later insertion rechecks live thread identity") { _ = try await a.insert("draft", for: w) }
        check(d.writes == 0, "new binding never authorizes a different current thread")
    } catch { check(false, "Codex exact navigation: \(error)") }
    do {
        let (d, a, w, conversation) = codexFixture()
        d.windows[0].url = nil
        d.windows[0].children[0].documentURL = "file:///tmp/project-alpha"
        await rejects("input metadata is not project evidence") { _ = try await a.openCodexConversation(w, knownConversations: [conversation]) }
        d.windows[0].children[0].documentURL = nil
        d.windows[0].documentURL = "file:///tmp/project-alpha/./"
        let binding = try await a.openCodexConversation(w, knownConversations: [conversation])
        check(binding.taskAnchor.label == "Task Alpha", "unique exact title plus observed normalized project path can bind")
    } catch { check(false, "Codex title and project navigation: \(error)") }
    for issue in ["wrongThread", "missingScope", "wrongProject", "duplicateTitle", "duplicateInput", "hidden", "sidebar", "wrongTitle", "incomplete", "modal", "unlisted", "wrongFocus"] {
        let (d, a, w, conversation) = codexFixture()
        var catalog = [conversation]
        switch issue {
        case "wrongThread": d.windows[0].url = "codex://threads/22222222-2222-4222-8222-222222222222"
        case "missingScope": d.windows[0].url = nil
        case "wrongProject": d.windows[0].documentURL = "file:///tmp/another-project"
        case "duplicateTitle":
            d.windows[0].url = nil; d.windows[0].documentURL = "file:///tmp/project-alpha"
            catalog.append(CodexConversation(id: "22222222-2222-4222-8222-222222222222", title: conversation.title, projectPath: conversation.projectPath))
        case "duplicateInput": var copy = d.windows[0].children[0]; copy.id = "second-input"; copy.identifier = "composer-two"; d.windows[0].children.append(copy)
        case "hidden": d.windows[0].children[0].visible = false
        case "sidebar": d.windows[0].children[1].inNavigation = true
        case "wrongTitle": d.windows[0].children[1].label = "Task Beta"
        case "incomplete": d.complete = false
        case "modal": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXSheet", visible: true))
        case "unlisted": catalog = []
        case "wrongFocus": d.focused = "other"; d.focusWorks = false
        default: break
        }
        await rejects("auto-binding rejects \(issue)") { _ = try await a.openCodexConversation(w, knownConversations: catalog) }
        check(d.openedURLs.count <= 1 && d.writes == 0 && d.presses.isEmpty, "failed \(issue) navigation never retries URL or submits")
    }
    for change in ["cancel", "authorization", "version", "pid"] {
        let (d, a, w, conversation) = codexFixture(); d.openPaused = true
        var allowed = true
        a.authorizeOperation = { if !allowed { throw ToolAdapterError("revoked") } }
        d.focused = "other"
        let task = Task { try await a.openCodexConversation(w, knownConversations: [conversation]) }
        for _ in 0..<1_000 {
            if d.openContinuation != nil { break }
            await Task.yield()
        }
        guard let continuation = d.openContinuation else {
            check(false, "navigation reaches URL operation for \(change)")
            task.cancel()
            continue
        }
        switch change {
        case "cancel": task.cancel()
        case "authorization": allowed = false
        case "version": d.version = "2.0"
        default: d.pid = 55
        }
        continuation.resume()
        await rejects("navigation rejects \(change) during open") { _ = try await task.value }
        check(d.focused == "other" && d.writes == 0 && d.presses.isEmpty, "stale \(change) navigation does not focus or submit")
    }
    do {
        let (d, _, w, conversation) = codexFixture()
        let a = ToolAdapter(driver: d, navigationTimeout: 0.07)
        d.focused = "other"; d.focusWorks = false
        await rejects("navigation reports unsupported input focus") { _ = try await a.openCodexConversation(w, knownConversations: [conversation]) }
        check(d.focuses == 1, "navigation does not retry a focus mutation after failure")
    }
    do {
        let (d, _, w, conversation) = codexFixture()
        let a = ToolAdapter(driver: d, navigationTimeout: 0.1)
        d.windows[0].url = "codex://threads/22222222-2222-4222-8222-222222222222"
        var snapshots = 0
        d.snapshotHook = {
            snapshots += 1
            if snapshots == 2 { d.windows[0].url = conversation.canonicalURL.absoluteString }
        }
        _ = try await a.openCodexConversation(w, knownConversations: [conversation])
        check(d.openedURLs.count == 1 && snapshots >= 2, "delayed navigation polls evidence without reopening URL")
    } catch { check(false, "delayed navigation: \(error)") }
    for label in ["Steer", "Steer now", "立即引导"] {
        do {
            let (d, a, w, _) = codexFixture(); d.setRunning(true); addSteer(d, label: label)
            let preview = try await a.prepareSend(for: w)
            check(preview.kind == .steer, "live \(label) has priority over running task")
            check(d.presses.isEmpty, "steer preparation requires explicit confirmation")
            let result = try await a.confirmSend(preview, for: w)
            check(result.confirmed && d.presses == ["steer"] && d.shortcuts.isEmpty, "steer confirmation presses only exact semantic control")
            await rejects("steer confirmation is single use") { _ = try await a.confirmSend(preview, for: w) }
        } catch { check(false, "Codex steer \(label): \(error)") }
    }
    do {
        let (d, a, w, _) = codexFixture()
        let preview = try await a.prepareSend(for: w)
        check(preview.kind == .send, "idle Codex without steer preserves normal send")
        addSteer(d)
        await rejects("normal-send confirmation cannot silently turn into steer") { _ = try await a.confirmSend(preview, for: w) }
        check(d.presses.isEmpty, "changed submission kind requires fresh explicit confirmation")
        let steer = try await a.prepareSend(for: w)
        check(steer.kind == .steer, "explicit steer takes precedence even when normal send is enabled")
    } catch { check(false, "submission mode change: \(error)") }
    for issue in ["changedToSend", "changedIdentity", "disabled", "duplicate", "approval", "thread", "text", "cancel"] {
        do {
            let (d, a, w, _) = codexFixture(); d.setRunning(true); addSteer(d)
            let preview = try await a.prepareSend(for: w)
            switch issue {
            case "changedToSend": d.windows[0].children.removeLast(); d.setRunning(false)
            case "changedIdentity": d.windows[0].children[4].identifier = "other-steer"
            case "disabled": d.windows[0].children[4].enabled = false
            case "duplicate": var copy = d.windows[0].children[4]; copy.id = "other"; d.windows[0].children.append(copy)
            case "approval": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXButton", label: "Allow once", enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
            case "thread": d.windows[0].url = "codex://threads/22222222-2222-4222-8222-222222222222"
            case "text": d.text = "changed"
            default: a.authorizeOperation = { throw CancellationError() }
            }
            await rejects("steer confirmation rejects \(issue)") { _ = try await a.confirmSend(preview, for: w) }
            check(d.presses.isEmpty && d.shortcuts.isEmpty, "changed \(issue) never falls through to normal send")
        } catch { check(false, "steer invalidation fixture: \(error)") }
    }
    for issue in ["approval", "approveAndRun", "allowSession", "approvalCard", "modal", "hidden", "unknownVisibility", "navigation", "otherScope", "genericContinue", "duplicate"] {
        let (d, a, w, _) = codexFixture(); d.setRunning(true); addSteer(d)
        switch issue {
        case "approval": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXButton", label: "Approve", enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        case "approveAndRun": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXButton", label: "Approve and run", enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        case "allowSession": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXButton", label: "Allow this session", enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        case "approvalCard": d.windows[0].children.append(ToolAXNode(id: "approval", role: "AXGroup", label: "Approval required", visible: true, contentScopeID: "main-content"))
        case "modal": d.windows[0].modal = true
        case "hidden": d.windows[0].children[4].visible = false
        case "unknownVisibility": d.windows[0].children[4].visible = nil
        case "navigation": d.windows[0].children[4].inNavigation = true
        case "otherScope": d.windows[0].children[4].contentScopeID = "other"
        case "genericContinue": d.windows[0].children[4].label = "Continue"
        default: var copy = d.windows[0].children[4]; copy.id = "other"; d.windows[0].children.append(copy)
        }
        await rejects("steer rejects \(issue)") { _ = try await a.prepareSend(for: w) }
        check(d.presses.isEmpty && d.shortcuts.isEmpty, "\(issue) never triggers approval or submission")
    }
    do {
        let (d, a, w, _) = codexFixture(); d.setRunning(true); addSteer(d); d.steerChangesState = false
        let preview = try await a.prepareSend(for: w)
        let result = try await a.confirmSend(preview, for: w)
        check(!result.confirmed && d.presses == ["steer"], "unchanged steer state reports uncertainty without retry")
        await rejects("uncertain steer confirmation cannot retry") { _ = try await a.confirmSend(preview, for: w) }
        check(d.presses.count == 1, "uncertain steer remains single press")
    } catch { check(false, "uncertain steer: \(error)") }
    do {
        let (d, a, w) = fixture(); d.setRunning(true); addSteer(d)
        await rejects("legacy profile does not infer steer support") { _ = try await a.prepareSend(for: w) }
        check(d.presses.isEmpty, "legacy behavior stays blocked during generation")
    }
    do {
        let (d, a, original, conversation) = codexFixture(); var w = original
        w.binding = nil; d.windows[0].children.removeLast()
        w.binding = try await a.openCodexConversation(w, knownConversations: [conversation])
        check(w.binding?.stopControl == nil, "first idle auto-binding never invents a hidden stop locator")
        let inserted = try await a.insert("new voice draft", for: w)
        let preview = try await a.prepareSend(for: w)
        check(preview.kind == .send && preview.text == inserted && d.presses.isEmpty, "verified idle Codex can preview first normal send without prior stop learning")
        let outcome = try await a.confirmSend(preview, for: w)
        check(d.presses == ["send"] && outcome.confirmed, "fresh observed stop transition confirms ordinary managed send once")
    } catch { check(false, "first idle managed send: \(error)") }
    do {
        let (d, a, w, conversation) = codexFixture(); d.windows[0].children.removeLast()
        let binding = try await a.openCodexConversation(w, knownConversations: [conversation])
        check(binding.stopControl == w.binding?.stopControl, "reopening exact unchanged conversation retains previously learned absent stop")
    } catch { check(false, "preserve prior controls: \(error)") }
    for issue in ["stop", "cancel", "interrupt", "working", "continue", "opaqueRuntime", "approval", "unknownStop", "unknownSend", "duplicateSend", "missingIdentity"] {
        let (d, a, original, _) = codexFixture(); var w = original
        w.binding?.stopControl = nil; w.binding?.sendControl = nil
        d.windows[0].children.removeLast()
        switch issue {
        case "unknownSend": d.windows[0].children[2].visible = nil
        case "duplicateSend": var duplicate = d.windows[0].children[2]; duplicate.id = "second-send"; d.windows[0].children.append(duplicate)
        case "missingIdentity": d.windows[0].url = nil
        default:
            let labels = ["stop": "Stop generating", "cancel": "Cancel", "interrupt": "Interrupt", "working": "Working…",
                          "continue": "Continue", "opaqueRuntime": "More", "approval": "Allow once", "unknownStop": "Stop generating"]
            d.windows[0].children.append(ToolAXNode(id: "runtime", role: "AXButton", identifier: issue == "opaqueRuntime" ? "running-task" : "runtime",
                label: labels[issue], enabled: true, actions: ["AXPress"], visible: issue == "unknownStop" ? nil : true, contentScopeID: "main-content"))
        }
        await rejects("first idle managed send rejects \(issue)") { _ = try await a.prepareSend(for: w) }
        check(d.presses.isEmpty && d.shortcuts.isEmpty, "unknown \(issue) state never submits")
    }
    do {
        let (d, a, original, _) = codexFixture(); var w = original
        w.binding?.stopControl = nil; w.binding?.sendControl = nil; d.windows[0].children.removeLast()
        let preview = try await a.prepareSend(for: w)
        d.windows[0].children[2].identifier = "replacement-send"
        await rejects("fresh managed Send identity change invalidates confirmation") { _ = try await a.confirmSend(preview, for: w) }
        check(d.presses.isEmpty, "changed fresh control requires another confirmation")
        d.windows[0].children[2].identifier = "send"
        d.windows[0].children.append(ToolAXNode(id: "live-stop", role: "AXButton", label: "Stop generating", enabled: true,
            actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        addSteer(d)
        let steer = try await a.prepareSend(for: w)
        check(steer.kind == .steer, "explicit live Steer still wins with first-use managed controls")
    } catch { check(false, "fresh control confirmation checks: \(error)") }
    for label in ["Stop generating", "Cancel"] {
        let (d, a, w, _) = codexFixture()
        d.windows[0].children.append(ToolAXNode(id: "new-live-stop", role: "AXButton", identifier: "new-stop", label: label,
            enabled: true, actions: ["AXPress"], visible: true, contentScopeID: "main-content"))
        await rejects("saved disabled stop cannot hide additional \(label)") { _ = try await a.prepareSend(for: w) }
        check(d.presses.isEmpty, "additional runtime controls block managed send despite old idle locator")
    }
    do {
        let (d, a, w, conversation) = codexFixture()
        let duplicate = CodexConversation(id: "22222222-2222-4222-8222-222222222222", title: conversation.title, projectPath: conversation.projectPath)
        _ = try await a.openCodexConversation(w, knownConversations: [conversation, duplicate])
        check(d.openedURLs.count == 1, "exact current thread ID disambiguates same-title conversations")
        d.windows[0].url = nil
        d.windows[0].documentURL = "file:///tmp/project-alpha"
        await rejects("lost live identity blocks insertion after binding") { _ = try await a.insert("draft", for: w) }
        check(d.writes == 0, "lost current identity cannot inherit prior navigation verification")
    } catch { check(false, "same-title exact identity: \(error)") }
    do {
        let (d, a, original, conversation) = codexFixture(); var w = original
        d.windows[0].url = nil; d.windows[0].documentURL = "file:///tmp/project-alpha"
        w.binding = try await a.openCodexConversation(w, knownConversations: [conversation])
        _ = try await a.insert("draft", for: w)
        check(d.writes == 1, "unique-title navigation authorizes same-session project evidence fallback")
        let freshAdapter = ToolAdapter(driver: d)
        await rejects("saved metadata does not remember runtime title uniqueness") { _ = try await freshAdapter.insert("other", for: w) }
        check(d.writes == 1, "project-only writes need fresh catalog uniqueness after restart")
    } catch { check(false, "runtime title fallback: \(error)") }
    do {
        let (d, a, w, _) = codexFixture()
        d.windows[0].url = nil
        await rejects("managed insertion requires fresh live identity") { _ = try await a.insert("draft", for: w) }
        check(d.writes == 0, "no managed writes when current identity evidence disappears")
    }
    for phase in ["preflight", "authorization", "mutation", "success"] {
        let (d, a, w) = fixture()
        var attempts: [String] = []
        if phase == "preflight" { d.writeWorks = false; d.windows[0].children[0].secure = true }
        if phase == "authorization" { a.authorizeOperation = { throw ToolAdapterError("revoked") } }
        if phase == "mutation" { d.writeThrows = true }
        do { _ = try await a.insert("new draft", for: w, willWrite: { attempts.append($0) }) }
        catch { check(phase != "success", "unexpected insertion callback failure") }
        check(attempts == ((phase == "mutation" || phase == "success") ? ["existing\nnew draft"] : []), "write callback tracks only attempted mutation: \(phase)")
    }
    for kind in ["send", "steer"] {
        for phase in ["preflight", "authorization", "mutation", "success"] {
            do {
                let (d, a, w, _) = codexFixture()
                if kind == "steer" { d.setRunning(true); addSteer(d) }
                let preview = try await a.prepareSend(for: w)
                var attempts = 0
                if phase == "preflight" { d.text = "changed" }
                if phase == "authorization" { a.authorizeOperation = { throw ToolAdapterError("revoked") } }
                if phase == "mutation" { d.pressThrows = true }
                do { _ = try await a.confirmSend(preview, for: w, willSubmit: { attempts += 1 }) }
                catch { check(phase != "success", "unexpected submission callback failure") }
                check(attempts == ((phase == "mutation" || phase == "success") ? 1 : 0), "\(kind) callback tracks only attempted mutation: \(phase)")
            } catch { check(false, "mutation callback fixture: \(error)") }
        }
    }
    print("Tool adapter checks: \(checks) assertions, \(failures) failures (fake AX only)")
    exit(failures == 0 ? 0 : 1)
}
Task { @MainActor in await runChecks() }
dispatchMain()
