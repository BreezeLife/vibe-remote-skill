import AppKit
import SwiftUI

@main
struct VibeRemoteApp: App {
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        Window("Vibe Remote", id: "remote") {
            RemoteView(model: model)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.shutdown()
                }
        }
        .defaultSize(width: 760, height: 640)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Vibe Remote", systemImage: model.draft.isBusy ? "waveform" : "mic.circle") {
            RemoteMenu(model: model)
        }
    }
}

private struct RemoteMenu: View {
    @ObservedObject var model: RemoteModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.connectionStatus)
        Text(model.captureLabel)
        Divider()
        Button("打开草稿窗口") {
            openWindow(id: "remote")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("复制草稿", action: model.copyDraft).disabled(!model.draft.canCopy)
        Button("结束收音", action: model.stopCapture).disabled(model.draft.phase != .capturing)
        Divider()
        Button("退出 Vibe Remote") {
            model.shutdown()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
