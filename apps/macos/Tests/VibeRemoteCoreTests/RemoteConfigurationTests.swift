import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class RemoteConfigurationTests: XCTestCase {
    func testDefaultsRoundTripWithAllButtonsAndReservedMicrophone() throws {
        let settings = NativeSettings.defaults
        try settings.validate()
        let decoded = try JSONDecoder().decode(NativeSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(Set(settings.mappings.map(\.button)), Set(RemoteButton.allCases))
        XCTAssertEqual(settings.mappings.first { $0.button == .mic }?.single, RemoteAction.none)
        XCTAssertEqual(settings.mappings.first { $0.button == .ok }?.single, .sendDraft)
        XCTAssertEqual(settings.mappings.first { $0.button == .back }?.long, .stopTask)
        XCTAssertEqual(settings.mappings.first { $0.button == .menu }?.single, .actionPicker)
    }

    func testUnknownVersionActionAndScriptFieldsAreRejected() throws {
        var settings = NativeSettings.defaults
        settings.schemaVersion = 2
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        settings.format = "vibe-remote-python"
        XCTAssertThrowsError(try settings.validate())
        let encoded = try JSONEncoder().encode(NativeSettings.defaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["script"] = "arbitrary command"
        XCTAssertThrowsError(try JSONDecoder().decode(NativeSettings.self, from: JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "script")
        var mappings = try XCTUnwrap(object["mappings"] as? [[String: Any]])
        mappings[0]["single"] = "executeShell"
        object["mappings"] = mappings
        XCTAssertThrowsError(try JSONDecoder().decode(NativeSettings.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testDuplicateButtonsInputsAndWorkspacesAreRejected() throws {
        var settings = NativeSettings.defaults
        settings.mappings.append(settings.mappings[0])
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        settings.mappings[0].input = sampleInput()
        settings.mappings[2].input = sampleInput()
        // Hold capability is metadata, not a distinct physical input.
        settings.mappings[2].input?.supportsHold = false
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        let workspace = WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex")
        settings.workspaces = [workspace, workspace]
        XCTAssertThrowsError(try settings.validate())
    }

    func testMicrophoneBindingsAndUnsupportedHoldCannotBeImported() throws {
        var settings = NativeSettings.defaults
        let mic = try XCTUnwrap(settings.mappings.firstIndex { $0.button == .mic })
        settings.mappings[mic].input = sampleInput()
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        settings.mappings[mic].single = .sendDraft
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        let back = try XCTUnwrap(settings.mappings.firstIndex { $0.button == .back })
        settings.mappings[back].input = sampleInput(supportsHold: false)
        XCTAssertThrowsError(try settings.validate())
    }

    func testMalformedHIDBoundsAreRejected() {
        for input in [HIDBinding(usagePage: -1, usage: 1, descriptorHash: String(repeating: "a", count: 64)),
                      HIDBinding(usagePage: 1, usage: 65_536, descriptorHash: String(repeating: "a", count: 64)),
                      HIDBinding(usagePage: 1, usage: 1, reportID: 256, descriptorHash: String(repeating: "a", count: 64)),
                      HIDBinding(usagePage: 1, usage: 1, descriptorHash: "device serial number")] {
            var settings = NativeSettings.defaults
            settings.mappings[0].input = input
            XCTAssertThrowsError(try settings.validate())
        }
    }

    func testOnlyExplicitSafePreviewAndCodexThreadURLsAreAccepted() throws {
        var settings = NativeSettings.defaults
        var workspace = WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex",
                                         previewURL: "http://localhost:3000/path?q=hello",
                                         codexThreadURL: "codex://threads/01a0f870-15e4-7762-abbb-a4e75396a652")
        settings.workspaces = [workspace]
        try settings.validate()
        for url in ["file:///tmp/a", "javascript:alert(1)", "https://", "https://user:secret@example.org", "https://example.org/\n"] {
            workspace.previewURL = url
            settings.workspaces = [workspace]
            XCTAssertThrowsError(try settings.validate())
        }
        workspace.previewURL = nil
        for url in ["codex://new", "codex://threads/a?prompt=x", "codex://threads/a#b", "codex://threads/../a", "codex://threads/a/b", "codex://threads/%61", "https://threads/a"] {
            workspace.codexThreadURL = url
            settings.workspaces = [workspace]
            XCTAssertThrowsError(try settings.validate())
        }
        workspace.codexThreadURL = "codex://threads/safe-id"
        workspace.bundleIdentifier = "com.anthropic.claudefordesktop"
        settings.workspaces = [workspace]
        XCTAssertThrowsError(try settings.validate())
    }

    func testPathsTerminalsAndOversizedLocatorsFailClosed() throws {
        var settings = NativeSettings.defaults
        var workspace = WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex", appPath: "/Applications/ChatGPT.app")
        settings.workspaces = [workspace]
        try settings.validate()
        for path in ["~/Applications/Codex.app", "/Applications/../Secrets.app", "/tmp/file.sh", "https://x/App.app"] {
            workspace.appPath = path
            settings.workspaces = [workspace]
            XCTAssertThrowsError(try settings.validate())
        }
        workspace.appPath = nil
        for bundle in ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty"] {
            workspace.bundleIdentifier = bundle
            settings.workspaces = [workspace]
            XCTAssertThrowsError(try settings.validate())
        }
        workspace.bundleIdentifier = "com.openai.codex"
        let anchor = AXLocator(path: [0], role: "AXStaticText", identifier: "task-1")
        for input in [AXLocator(path: Array(repeating: 0, count: 33), role: "AXTextArea"),
                      AXLocator(path: [-1], role: "AXTextArea"),
                      AXLocator(path: [4096], role: "AXTextArea"),
                      AXLocator(path: [1], role: "AXTextArea", label: String(repeating: "x", count: 513))] {
            workspace.binding = ToolBinding(appVersion: "1", windowTitle: "Task", input: input, taskAnchor: anchor)
            settings.workspaces = [workspace]
            XCTAssertThrowsError(try settings.validate())
        }
    }

    func testLocatorRejectsPersistedInputValue() throws {
        let data = Data(#"{"path":[0],"role":"AXTextArea","value":"private draft"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AXLocator.self, from: data))
    }

    func testIdentifiersRejectTrailingNewlinesInsteadOfMatchingOnlyPrefix() {
        var settings = NativeSettings.defaults
        settings.mappings[0].input = HIDBinding(usagePage: 1, usage: 1, descriptorHash: String(repeating: "a", count: 64) + "\n")
        XCTAssertThrowsError(try settings.validate())
        settings = .defaults
        settings.workspaces = [WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex\n")]
        XCTAssertThrowsError(try settings.validate())
        settings.workspaces = [WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex", codexThreadURL: "codex://threads/task\n")]
        XCTAssertThrowsError(try settings.validate())
    }

    func testShortcutsCannotDisguiseSendStopOrArbitraryCommands() throws {
        let invalid = [ActionShortcut(action: .focusTarget, keyCode: 36),
                       ActionShortcut(action: .focusTarget, keyCode: 36, modifiers: [.command]),
                       ActionShortcut(action: .focusTarget, keyCode: 53),
                       ActionShortcut(action: .focusTarget, keyCode: 8, modifiers: [.control]),
                       ActionShortcut(action: .copyDraft, keyCode: 8, modifiers: [.command]),
                       ActionShortcut(action: .sendDraft, keyCode: 12, modifiers: [.command]),
                       ActionShortcut(action: .scrollDown, keyCode: 36),
                       ActionShortcut(action: .sendDraft, keyCode: 36, modifiers: [.command, .command])]
        for shortcut in invalid {
            XCTAssertFalse(shortcut.isSupported)
            var settings = NativeSettings.defaults
            settings.workspaces = [WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex", shortcuts: [shortcut])]
            XCTAssertThrowsError(try settings.validate())
        }
        for shortcut in [ActionShortcut(action: .sendDraft, keyCode: 36),
                         ActionShortcut(action: .sendDraft, keyCode: 76, modifiers: [.command]),
                         ActionShortcut(action: .stopTask, keyCode: 53),
                         ActionShortcut(action: .stopTask, keyCode: 8, modifiers: [.control]),
                         ActionShortcut(action: .scrollUp, keyCode: 126),
                         ActionShortcut(action: .focusTarget, keyCode: 37, modifiers: [.command])] {
            XCTAssertTrue(shortcut.isSupported)
            var settings = NativeSettings.defaults
            settings.workspaces = [WorkspaceProfile(name: "Codex", bundleIdentifier: "com.openai.codex", shortcuts: [shortcut])]
            try settings.validate()
        }
    }

    private func sampleInput(supportsHold: Bool = true) -> HIDBinding {
        HIDBinding(usagePage: 12, usage: 233, reportID: 1, descriptorHash: String(repeating: "a", count: 64), supportsHold: supportsHold)
    }
}
