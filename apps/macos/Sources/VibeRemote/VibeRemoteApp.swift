import AppKit
import SwiftUI

@main
struct VibeRemoteApp: App {
    @StateObject private var model: RemoteModel
    @StateObject private var controls: ControlsModel
    @StateObject private var external: ExternalDictationController

    init() {
        let focusedInput = FocusedInputService()
        let externalInput = ExternalDictationController(focusedInput: focusedInput)
        let voice = RemoteModel(externalInput: externalInput, focusedInput: focusedInput)
        _external = StateObject(wrappedValue: externalInput)
        _model = StateObject(wrappedValue: voice)
        _controls = StateObject(wrappedValue: ControlsModel(voice: voice))
    }

    var body: some Scene {
        Window("Vibe Remote", id: "remote") {
            SettingsViews(voice: model, controls: controls, external: external)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    controls.shutdown()
                }
        }
        .defaultSize(width: 1100, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Vibe Remote", systemImage: model.isBusy ? "waveform" : "mic.circle") {
            RemoteMenu(model: model, controls: controls, external: external)
        }
    }
}

private struct RemoteMenu: View {
    @ObservedObject var model: RemoteModel
    @ObservedObject var controls: ControlsModel
    @ObservedObject var external: ExternalDictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.connectionStatus)
        Text(model.captureLabel)
        Divider()
        Button(model.inputDestination == .currentFocus ? "打开 Vibe Remote 设置" : "打开草稿窗口") {
            openWindow(id: "remote")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("暂停按键并释放设备") { controls.pauseMappings() }
        Button(model.inputDestination == .currentFocus ? "复制保留文字" : "复制草稿", action: model.copyDraft)
            .disabled(!model.canCopy)
        Button("结束收音", action: model.stopCapture).disabled(!model.isReceivingAudio)
        if external.isBusy && external.destination == .currentFocus {
            Divider()
            Text("先确认输入法已停止录音、识别完成")
            Button("输入法已结束，准备下一段") {
                _ = external.completeDirect(providerFinished: true)
            }.disabled(external.phase != .review || model.isReceivingAudio)
            Button("输入法已结束，关闭本次准备") {
                _ = external.discard(providerFinished: true)
            }.disabled(!external.canSettle || model.isReceivingAudio)
        }
        Divider()
        Button("退出 Vibe Remote") {
            controls.shutdown()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
