import Foundation
import Darwin
import VibeRemoteCore

protocol CodexConversationListing {
    func listConversations(appPath: String) async throws -> [CodexConversation]
}

/// A short-lived, read-only catalog client. Its runtime status does not describe
/// the desktop app's active turns, and it never loads or resumes a conversation.
struct CodexConversationCatalogService: CodexConversationListing {
    private let timeout: TimeInterval
    init(timeout: TimeInterval = 8) { self.timeout = min(max(timeout, 0.1), 30) }

    func listConversations(appPath: String) async throws -> [CodexConversation] {
        let cancellation = CatalogCancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let executable = try Self.executable(in: appPath)
                        let session = try CatalogProcess(executable: executable, timeout: timeout, cancellation: cancellation)
                        defer { session.close() }
                        continuation.resume(returning: try Self.readCatalog(session))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }

    private static func executable(in appPath: String) throws -> URL {
        let app = URL(fileURLWithPath: appPath).standardizedFileURL
        guard appPath.hasPrefix("/"), app.path == appPath, app.pathExtension == "app",
              Bundle(url: app)?.bundleIdentifier == "com.openai.codex" else { throw CatalogError.application }
        for relative in ["Contents/Resources/codex-cli/bin/codex",
                         "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"] {
            let candidate = app.appendingPathComponent(relative)
            // No PATH lookup or shell invocation: use the chosen installed app's CLI.
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw CatalogError.application
    }

    private static func readCatalog(_ session: CatalogProcess) throws -> [CodexConversation] {
        try session.send(["id":0, "method":"initialize", "params":[
            "clientInfo":["name":"vibe_remote_catalog", "title":"Vibe Remote", "version":"1"],
            "capabilities":NSNull()
        ]])
        _ = try session.response(id: 0)
        try session.send(["method":"initialized"])
        var cursor: String?
        var seenCursors = Set<String>()
        var records: [String:CodexConversation] = [:]
        var totalEntries = 0
        for pageNumber in 1...10 {
            var params: [String:Any] = ["limit":100, "sortKey":"created_at", "sortDirection":"asc",
                "modelProviders":[String](), "sourceKinds":["cli","vscode","appServer"],
                "archived":false, "useStateDbOnly":true]
            if let cursor { params["cursor"] = cursor }
            try session.send(["id":pageNumber, "method":"thread/list", "params":params])
            let page = try CodexConversationCatalog.parseListResponse(session.response(id: pageNumber))
            totalEntries += page.entryCount
            guard totalEntries <= 1000 else { throw CatalogError.capacity }
            for record in page.conversations {
                if let old = records[record.id], old.projectPath != record.projectPath { throw CatalogError.response }
                if records[record.id] == nil { records[record.id] = record }
            }
            guard let next = page.nextCursor else {
                return CodexConversationCatalog.sorted(Array(records.values))
            }
            guard seenCursors.insert(next).inserted else { throw CatalogError.response }
            cursor = next
        }
        throw CatalogError.capacity
    }
}

private enum CatalogError: LocalizedError {
    case application, launch, response, timeout, capacity, output
    var errorDescription: String? {
        switch self {
        case .application: return "未找到所选 Codex 应用内的会话目录工具，请更新 Codex 后重试"
        case .launch: return "无法启动 Codex 会话目录工具"
        case .response: return "Codex 会话目录暂不可用，请刷新或更新 Codex 后重试"
        case .timeout: return "读取 Codex 会话目录超时，请重试"
        case .capacity: return "Codex 会话目录达到本次读取上限（最多 1000 项或 10 页），未导入部分结果"
        case .output: return "Codex 会话目录响应过大，未导入部分结果"
        }
    }
}

private final class CatalogCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    func cancel() { lock.lock(); canceled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = canceled; lock.unlock()
        if value { throw CancellationError() }
    }
}

/// Blocking pipe I/O stays on a background queue. poll bounds every wait and
/// prevents a silent or malformed child process from hanging the application.
private final class CatalogProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: TimeInterval
    private let cancellation: CatalogCancellation
    private var buffer = Data()
    private var received = 0
    private var closed = false

    init(executable: URL, timeout: TimeInterval, cancellation: CatalogCancellation) throws {
        self.cancellation = cancellation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        try cancellation.check()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        // Server diagnostics may contain private values; do not collect or surface them.
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CatalogError.launch }
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        let inputFD = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(inputFD, F_SETFL, fcntl(inputFD, F_GETFL) | O_NONBLOCK)
        // A closed child pipe must yield EPIPE, not terminate the host application.
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
    }
    deinit { close() }
    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        if process.isRunning {
            process.terminate()
            // Only our own catalog child is eligible; an unresponsive child cannot
            // outlive its bounded request. Never signal the desktop process.
            let child = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
    func send(_ request: [String:Any]) throws {
        guard let method = request["method"] as? String,
              ["initialize","initialized","thread/list"].contains(method) else { throw CatalogError.response }
        var bytes = try JSONSerialization.data(withJSONObject: request)
        bytes.append(10)
        try bytes.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                try wait(fd: input.fileHandleForWriting.fileDescriptor, events: Int16(POLLOUT))
                let count = Darwin.write(input.fileHandleForWriting.fileDescriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if count > 0 { sent += count }
                else if errno != EINTR && errno != EAGAIN { throw CatalogError.response }
            }
        }
    }
    func response(id: Int) throws -> Data {
        while true {
            let line = try nextLine()
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String:Any] else { throw CatalogError.response }
            if let responseID = object["id"] as? Int {
                guard responseID == id, object["error"] == nil, object["result"] != nil else { throw CatalogError.response }
                return line
            }
            // Read-only listing may emit notifications; never answer a server request.
            guard object["id"] == nil, object["method"] is String else { throw CatalogError.response }
        }
    }
    private func nextLine() throws -> Data {
        while true {
            try checkDeadline()
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard line.count <= 1_048_576 else { throw CatalogError.output }
                guard !line.isEmpty else { continue }
                return line
            }
            guard buffer.count <= 1_048_576 else { throw CatalogError.output }
            try wait(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN))
            var chunk = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &chunk, chunk.count)
            if count > 0 {
                received += count
                guard received <= 8_388_608 else { throw CatalogError.output }
                buffer.append(contentsOf: chunk.prefix(count))
            } else if count == 0 { throw CatalogError.response }
            else if errno != EINTR && errno != EAGAIN { throw CatalogError.response }
        }
    }
    private func checkDeadline() throws {
        try cancellation.check()
        if ProcessInfo.processInfo.systemUptime >= deadline { throw CatalogError.timeout }
    }
    private func wait(fd: Int32, events: Int16) throws {
        while true {
            try checkDeadline()
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, 50)
            if result > 0 {
                if descriptor.revents & events != 0 { return }
                throw CatalogError.response
            }
            if result < 0 && errno != EINTR { throw CatalogError.response }
        }
    }
}
