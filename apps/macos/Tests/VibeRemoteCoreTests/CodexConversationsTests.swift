import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class CodexConversationsTests: XCTestCase {
    let firstID = "01900000-0000-7000-8000-000000000001"
    let secondID = "01900000-0000-7000-8000-000000000002"
    func testLegacyWorkspaceDecodesWithoutManagedConversation() throws {
        let data = Data(#"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Existing","bundleIdentifier":"com.openai.codex","shortcuts":[]}"#.utf8)
        let workspace = try JSONDecoder().decode(WorkspaceProfile.self, from: data)
        XCTAssertNil(workspace.codexConversation)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as! [String: Any]
        XCTAssertNil(object["codexConversation"])
        try NativeSettings(workspaces: [workspace]).validate()
    }
    func testManagedConversationDescriptorDecodesAsOptionalWorkspaceField() throws {
        let data = Data(#"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Project","bundleIdentifier":"com.openai.codex","shortcuts":[],"codexThreadURL":"codex://threads/01900000-0000-7000-8000-000000000001","codexConversation":{"id":"01900000-0000-7000-8000-000000000001","title":"Task","projectPath":"/Projects/App"}}"#.utf8)
        let workspace = try JSONDecoder().decode(WorkspaceProfile.self, from: data)
        try NativeSettings(workspaces: [workspace]).validate()
        XCTAssertEqual(workspace.name, "Project")
    }

    func testCatalogRetainsOnlySafeNavigationMetadataAndStableSort() throws {
        let response = try JSONSerialization.data(withJSONObject: ["result": ["data": [
            ["id": secondID, "name": "Zebra", "cwd": "/Projects/App/./", "preview": "secret", "turns": [["text":"secret"]], "status": ["type":"active"]] as [String: Any],
            ["id": firstID, "name": "Alpha", "cwd": "/Projects/App"],
            ["id": secondID, "name": "Zebra", "cwd": "/Projects/App"]
        ], "nextCursor": "page2"]])
        let page = try CodexConversationCatalog.parseListResponse(response)
        XCTAssertEqual(page.conversations.map(\.id), [firstID, secondID])
        XCTAssertEqual(page.conversations[1].projectPath, "/Projects/App")
        XCTAssertEqual(page.nextCursor, "page2")
        let encoded = String(decoding: try JSONEncoder().encode(page.conversations), as: UTF8.self)
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("status"))
    }

    func testCatalogFiltersUnsafeRemoteAndSubagentEntriesAndNeverUsesPreviewAsTitle() throws {
        let response = try JSONSerialization.data(withJSONObject: ["result": ["data": [
            ["id": firstID, "cwd": "/Projects/App", "preview": "private first message"],
            ["id": secondID, "cwd": "ssh://host/repo"],
            ["id": secondID, "cwd": "//server/repo"],
            ["id": secondID, "cwd": "/Projects/../private"],
            ["id": "../bad", "cwd": "/Projects/App"],
            ["id": secondID, "cwd": "/Projects/App", "hostId": "cloud"],
            ["id": secondID, "cwd": "/Projects/App", "parentThreadId": firstID]
        ]]] )
        let page = try CodexConversationCatalog.parseListResponse(response)
        XCTAssertEqual(page.conversations.count, 1)
        XCTAssertEqual(page.conversations[0].title, "未命名会话 · " + firstID)
        XCTAssertEqual(page.conversations[0].canonicalURL.absoluteString, "codex://threads/" + firstID)
    }

    func testCatalogRejectsErrorsMalformedPagesAndConflictingThreadScopes() throws {
        for value in [#"{"error":{"message":"secret"}}"#, #"{"result":{}}"#,
                      #"{"result":{"data":[],"nextCursor":4}}"#] {
            XCTAssertThrowsError(try CodexConversationCatalog.parseListResponse(Data(value.utf8)))
        }
        let conflict = try JSONSerialization.data(withJSONObject: ["result": ["data": [
            ["id": firstID, "name": "Task", "cwd": "/One"],
            ["id": firstID, "name": "Task", "cwd": "/Two"]
        ]]])
        XCTAssertThrowsError(try CodexConversationCatalog.parseListResponse(conflict))
    }

    func testDescriptorAndWorkspaceRejectUnexpectedFieldsAndMismatchedDestinations() throws {
        let descriptor = CodexConversation(id: firstID, title: "Task", projectPath: "/Project")
        var workspace = WorkspaceProfile(name: "Task", bundleIdentifier: "com.openai.codex",
            codexThreadURL: descriptor.canonicalURL.absoluteString, codexConversation: descriptor)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceProfile.self, from: JSONEncoder().encode(workspace)), workspace)
        workspace.codexThreadURL = "codex://threads/" + secondID
        XCTAssertThrowsError(try NativeSettings(workspaces: [workspace]).validate())
        let unknown = #"{"id":"01900000-0000-7000-8000-000000000001","title":"Task","projectPath":"/Project","preview":"secret"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(CodexConversation.self, from: Data(unknown.utf8)))
        for path in ["~/Project", "/Project/../Other", "/Project/./", "ssh://host/repo"] {
            XCTAssertThrowsError(try CodexConversation(id: firstID, title: "Task", projectPath: path).validate())
        }
    }

    func testCodexConversationPresetIsOptInAndNavigationNeverRepeats() throws {
        let actions = CodingToolPreset.codexConversationActions
        XCTAssertEqual(actions.first { $0.button == .up }?.single, .previousConversation)
        XCTAssertEqual(actions.first { $0.button == .down }?.single, .nextConversation)
        XCTAssertEqual(actions.first { $0.button == .ok }?.single, .confirmInput)
        XCTAssertEqual(actions.first { $0.button == .left }?.single, .previousWorkspace)
        XCTAssertEqual(CodingToolPreset.codex.buttonActions.first { $0.button == .up }?.single, .scrollUp)
        for action in [RemoteAction.previousConversation, .nextConversation, .confirmInput] {
            XCTAssertFalse(action.allowsRepeat)
            XCTAssertFalse(ActionShortcut(action: action, keyCode: 36).isSupported)
        }
    }
}
