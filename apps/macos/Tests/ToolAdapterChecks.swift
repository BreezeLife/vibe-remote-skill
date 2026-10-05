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
    func snapshot(_ application: ToolApplication) throws -> ToolAXObservation {
        snapshotHook?()
        return ToolAXObservation(processID: pid, frontmostPID: front, focusedWindowID: focusedWindow,
                                 focusedNodeID: focused, pointerNodeID: pointer, windows: windows, complete: complete)
    }
    func value(of node: ToolAXNode) throws -> String { valuesRead += 1; return text }
    func setValue(_ value: String, of node: ToolAXNode) throws { writes += 1; if writeWorks { text = value } }
    func focus(_ node: ToolAXNode) throws { if focusWorks { focused = node.id }; focusHook?() }
    func perform(_ action: String, on node: ToolAXNode) throws {
        presses.append(node.id)
        if node.id == "send" && sendChangesState { setRunning(true); text = "" }
        if node.id == "stop" && stopChangesState { setRunning(false) }
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
        windows[0].children[3].enabled = running
        windows[0].children[2].enabled = !running
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
    print("Tool adapter checks: \(checks) assertions, \(failures) failures (fake AX only)")
    exit(failures == 0 ? 0 : 1)
}
Task { @MainActor in await runChecks() }
dispatchMain()
