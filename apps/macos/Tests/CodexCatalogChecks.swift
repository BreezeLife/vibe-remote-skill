import Foundation
import VibeRemoteCore

@main struct CodexCatalogChecks {
    static var assertions = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        assertions += 1
        if !value() { fputs("FAIL \(label)\n", stderr); exit(1) }
    }
    static func fixture(mode: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vibe-catalog-fixture-" + UUID().uuidString)
        let app = root.appendingPathComponent("Fake.app")
        let executable = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.openai.codex", "CFBundleName":"Fixture"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let script = #"""
#!/usr/bin/python3
import json, sys, pathlib, time
base = pathlib.Path(__file__).resolve().parents[5]
mode = "MODE"
pages = 0
for line in sys.stdin:
    message = json.loads(line)
    with (base / 'requests.jsonl').open('a') as log:
        log.write(json.dumps(message) + '\n')
    method = message['method']
    if method == 'initialize':
        print(json.dumps({'id':message['id'],'result':{}}), flush=True)
    elif method == 'initialized':
        continue
    elif method == 'thread/list':
        pages += 1
        if mode == 'timeout':
            time.sleep(10)
        if mode == 'oversize':
            print('x' * 2000000, flush=True)
            continue
        if mode == 'boundary':
            print(' ' * 1048576 + json.dumps({'id':message['id'],'result':{'data':[]}}), flush=True)
            continue
        if mode == 'error':
            print(json.dumps({'id':message['id'],'error':{'message':'private details'}}), flush=True)
            continue
        if mode == 'exit':
            break
        if mode == 'wrongid':
            print(json.dumps({'id':999,'result':{}}), flush=True)
            continue
        data = [{'id':'01900000-0000-7000-8000-00000000000' + str(pages % 2 + 1),
                 'name':'Zulu' if pages == 1 else 'Alpha', 'cwd':'/Project',
                 'preview':'private contents', 'status':{'type':'active'}, 'turns':[]}]
        cursor = 'next' if pages == 1 else None
        if mode == 'loop': cursor = 'same'
        if mode in ['many', 'exact']:
            data = [{'id':'01900000-0000-7000-8000-%012x' % ((pages - 1) * 100 + index),
                     'name':'Task %04d' % ((pages - 1) * 100 + index), 'cwd':'/Project'} for index in range(100)]
            cursor = str(pages) if mode == 'many' or pages < 10 else None
        print(json.dumps({'method':'metadata/notice','params':{}}), flush=True)
        print(json.dumps({'id':message['id'],'result':{'data':data,'nextCursor':cursor}}), flush=True)
    else:
        raise Exception('Unexpected write method')
"""#.replacingOccurrences(of: "MODE", with: mode)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }
    static func main() async throws {
        let app = try fixture(mode: "normal")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let result = try await CodexConversationCatalogService().listConversations(appPath: app.path)
        check(result.map(\.title) == ["Alpha", "Zulu"], "catalog stable title order")
        let requestData = try Data(contentsOf: app.deletingLastPathComponent().appendingPathComponent("requests.jsonl"))
        let requests = try String(decoding: requestData, as: UTF8.self).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        check(requests.map { $0["method"] as! String } == ["initialize","initialized","thread/list","thread/list"], "only read-only allowlist")
        let params = requests[2]["params"] as! [String: Any]
        check(params["useStateDbOnly"] as? Bool == true, "no rollout scan")
        check(params["archived"] as? Bool == false, "nonarchived only")
        check((params["sourceKinds"] as? [String])?.contains("appServer") == true, "include desktop source")
        check((requests[3]["params"] as? [String:Any])?["cursor"] as? String == "next", "pagination cursor")
        let saved = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        check(!saved.contains("private") && !saved.contains("active"), "no text or live state retained")
        let exactApp = try fixture(mode: "exact")
        defer { try? FileManager.default.removeItem(at: exactApp.deletingLastPathComponent()) }
        let exact = try await CodexConversationCatalogService().listConversations(appPath: exactApp.path)
        check(exact.count == 1000, "full capacity returned without silent truncation")
        for mode in ["loop", "many", "oversize", "boundary", "error", "exit", "wrongid", "timeout"] {
            let fixtureApp = try fixture(mode: mode)
            defer { try? FileManager.default.removeItem(at: fixtureApp.deletingLastPathComponent()) }
            let start = Date()
            do {
                _ = try await CodexConversationCatalogService(timeout: 0.5).listConversations(appPath: fixtureApp.path)
                check(false, "\(mode) must fail without partial result")
            } catch {
                check(!error.localizedDescription.contains("private details"), "error does not expose server text")
                check(Date().timeIntervalSince(start) < 2, "bounded \(mode)")
            }
        }
        do {
            _ = try await CodexConversationCatalogService().listConversations(appPath: "/tmp/not-codex.app")
            check(false, "unknown app rejected")
        } catch { check(true, "unknown app rejected") }
        let fallbackApp = try fixture(mode: "normal")
        defer { try? FileManager.default.removeItem(at: fallbackApp.deletingLastPathComponent()) }
        let fallback = fallbackApp.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        try FileManager.default.createDirectory(at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true)
        let primary = fallbackApp.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        // This fixture script's temporary-log parent depth changes at the nested path.
        let fallbackScript = try String(contentsOf: primary).replacingOccurrences(of: "parents[5]", with: "parents[7]")
        try fallbackScript.write(to: fallback, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fallback.path)
        try FileManager.default.removeItem(at: primary)
        let fallbackResult = try await CodexConversationCatalogService().listConversations(appPath: fallbackApp.path)
        check(fallbackResult.count == 2, "bundled nested executable fallback")
        let canceledApp = try fixture(mode: "timeout")
        defer { try? FileManager.default.removeItem(at: canceledApp.deletingLastPathComponent()) }
        let task = Task { try await CodexConversationCatalogService(timeout: 5).listConversations(appPath: canceledApp.path) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; check(false, "cancel should fail") }
        catch { check(error is CancellationError, "cancellation preserved") }
        print("Codex catalog: \(assertions) assertions passed; synthetic process only")
    }
}
