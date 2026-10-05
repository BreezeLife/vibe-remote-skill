import AppKit
import SwiftUI

@main
struct VibeRemoteApp: App {
    @StateObject private var model: RemoteModel
    @StateObject private var controls: ControlsModel

    init() {
        let voice = RemoteModel()
        _model = StateObject(wrappedValue: voice)
        _controls = StateObject(wrappedValue: ControlsModel(voice: voice))
    }

    var body: some Scene {
        Window("Vibe Remote", id: "remote") {
            SettingsViews(voice: model, controls: controls)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    controls.shutdown()
                }
        }
        .defaultSize(width: 1100, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Vibe Remote", systemImage: model.isBusy ? "waveform" : "mic.circle") {
            RemoteMenu(model: model, controls: controls)
        }
    }
}

private struct RemoteMenu: View {
    @ObservedObject var model: RemoteModel
    @ObservedObject var controls: ControlsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.connectionStatus)
        Text(model.captureLabel)
        Divider()
        Button("打开草稿窗口") {
            openWindow(id: "remote")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("暂停按键并释放设备") { controls.pauseMappings() }
        Button("复制草稿", action: model.copyDraft).disabled(!model.canCopy)
        Button("结束收音", action: model.stopCapture).disabled(!model.isReceivingAudio)
        Divider()
        Button("退出 Vibe Remote") {
            controls.shutdown()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
