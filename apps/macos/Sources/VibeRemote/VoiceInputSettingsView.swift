import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VibeRemoteCore

struct VoiceInputSettingsView: View {
    @ObservedObject var controls: ControlsModel
    @ObservedObject var voice: RemoteModel
    @ObservedObject var external: ExternalDictationController
    @State private var selected = VoiceInputProvider.appleSpeech
    @State private var destination = VoiceInputDestination.draft
    @State private var profile = VoiceInputProfile(provider: .typeless)
    @State private var devices: [RemoteAudioDevice] = []
    @State private var installed: VoiceProviderAppInfo?
    @State private var microphoneConfirmed = false
    @State private var shortcutConfirmed = false
    @State private var autoSendDisabled = false
    @State private var status = "配置会保存在本机；保存不会启动输入法或开始录音。"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeading(title: "语音输入", detail: "选择识别工具和文字输入位置。可以先保留草稿，也可以直接填入当前光标所在的输入框。")
            if external.isBusy && external.destination == .currentFocus {
                ExternalDirectStatusView(external: external, voice: voice)
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("文字输入位置", selection: $destination) {
                    ForEach(VoiceInputDestination.allCases) { value in Text(value.title).tag(value) }
                }.frame(maxWidth: 520)
                Text(destination == .draft
                     ? "先检查 Vibe Remote 草稿，再决定插入和发送；保留原有工作区流程。"
                     : "保存后，点击目标输入框再按住遥控器。文字填到开始说话时的输入位置，不按回车、不自动发送；原工作区草稿独立保留。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if destination == .currentFocus, let reason = external.currentInputPreparationBlockReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.disabled(!controls.canEdit)
                .onChange(of: destination) { _ in
                    microphoneConfirmed = false; shortcutConfirmed = false; autoSendDisabled = false
                }
            Picker("语音识别工具", selection: $selected) {
                ForEach(VoiceInputProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }.frame(maxWidth: 420).disabled(!controls.canEdit)
            Text(selected.setupDescription).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if selected == .appleSpeech {
                GroupBox("内置识别") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("直接识别遥控器音频，不需要第三方输入法或虚拟麦克风。识别语言与在线选项仍在「听写」页设置。")
                        if destination == .currentFocus {
                            Text("先点击目标应用的可编辑输入框，再按住说话。松开并识别结束后尝试填入；焦点变化或不支持时，在「听写」页保留本段文字供复制，不会自动重试。")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("使用内置 Apple 识别") { save() }.disabled(!controls.canEdit)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                applicationSection
                audioSection
                shortcutSection
                GroupBox("准备与测试") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(destination == .draft
                             ? "1. 先在输入法中选好上面的麦克风，并关闭其自动发送功能。\n2. 准备接收框。手动模式先启动输入法录音，再按住遥控器说话；自动模式直接按住。\n3. 松开后结束输入法，等文字出现，确认识别完成再加入工作区草稿。"
                             : "1. 在输入法中选好上面的麦克风，并关闭自动发送。\n2. 准备听写后，点击目标应用的输入框；手动模式先启动输入法录音，再按住遥控器说话。\n3. 保持目标输入框，等待输入法填入文字。确认输入法结束后，通过菜单栏或此页准备下一段。")
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("已在输入法中选择同一虚拟麦克风", isOn: $microphoneConfirmed)
                        if profile.triggerMode != .manual {
                            Toggle("已设置相同快捷键和触发方式，并关闭输入法自动发送", isOn: $shortcutConfirmed)
                        }
                        if destination == .currentFocus {
                            Toggle("已确认输入法只填文字，不会自动发送（手动触发也需要）", isOn: $autoSendDisabled)
                        }
                        HStack {
                            Button("保存配置") { save() }.disabled(!controls.canEdit)
                            Button("准备第三方听写") { prepare() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!controls.canEdit || !voice.ready || !microphoneConfirmed || profile.outputDeviceUID == nil ||
                                          (profile.triggerMode != .manual && !shortcutConfirmed) ||
                                          (destination == .currentFocus && (!autoSendDisabled || external.currentInputPreparationBlockReason != nil)))
                        }
                        if !voice.ready { Text("遥控器语音通道就绪后才能开始测试；现在可以先保存配置。") }
                        Text("这些确认仅用于本次准备；不代表正在录音或已通过实测。第三方工具可能联网处理并保存音频/文字，以其设置为准。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8).disabled(!controls.canEdit)
                }
            }
            Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(28)
            .onAppear {
                selected = controls.settings.voiceInput?.provider ?? .appleSpeech
                destination = controls.settings.voiceInput?.destination ?? .draft
                loadSelection()
            }
            .onChange(of: selected) { _ in loadSelection() }
    }

    private var applicationSection: some View {
        GroupBox("输入法应用") {
            VStack(alignment: .leading, spacing: 10) {
                Text(installed.map { "已找到 \($0.name) · \($0.version)" } ??
                     (selected == .macOSDictation ? "macOS 系统功能；需在键盘设置中启用听写。" : "未找到应用；可选择已安装的 .app。"))
                if let installed { Text(installed.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    Button("选择 .app") { chooseApp() }
                    Button("刷新") { refresh() }
                    if let url = selected.officialURL { Link("官方配置说明", destination: url) }
                    if selected == .macOSDictation || selected == .doubaoIME {
                        Button("键盘设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
                    } else if let installed {
                        Button("打开应用") { NSWorkspace.shared.open(URL(fileURLWithPath: installed.path)) }
                    }
                }.disabled(!controls.canEdit)
                Text("应用已安装与麦克风、辅助功能授权是独立事项。豆包输入法从系统/用户 Input Methods 目录识别；不会把豆包聊天应用当作输入法。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var audioSection: some View {
        GroupBox("遥控器音频通道") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("虚拟麦克风", selection: Binding(get: { profile.outputDeviceUID }, set: {
                    profile.outputDeviceUID = $0; microphoneConfirmed = false
                })) {
                    Text("请选择已安装的通道").tag(nil as String?)
                    ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                    if let uid = profile.outputDeviceUID, !devices.contains(where: { $0.id == uid }) {
                        Text("上次选择的设备当前不可用").tag(Optional(uid))
                    }
                }.disabled(!controls.canEdit)
                Text("在输入法的麦克风设置中选择同名设备。Vibe Remote 把遥控器声音送入它；不会修改系统默认输入或输出。支持已安装的 MiRemoteV 2ch / BlackHole 2ch。")
                    .font(.callout).foregroundStyle(.secondary)
                if devices.isEmpty {
                    Text("未找到支持的虚拟音频通道。当前版本不附带驱动；可先使用内置 Apple 识别。")
                        .foregroundStyle(.orange)
                }
                Text("若输入法不能单独选麦克风，请先在其界面核对可用方式。仅保存配置不能证明它正在接收遥控器音频。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }

    private var shortcutSection: some View {
        GroupBox("语音键如何启动输入法") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("触发方式", selection: $profile.triggerMode) {
                    Text("手动：使用输入法自己的快捷键").tag(VoiceTriggerMode.manual)
                    Text("按住：按下启动，松开结束").tag(VoiceTriggerMode.hold)
                    Text("切换：开始与结束各点一次").tag(VoiceTriggerMode.toggle)
                }.onChange(of: profile.triggerMode) { _ in shortcutConfirmed = false }
                if profile.triggerMode != .manual {
                    HStack {
                        Picker("快捷键", selection: Binding(get: { profile.shortcutKeyCode }, set: {
                            profile.shortcutKeyCode = $0
                            if $0 != 49 { profile.shortcutModifiers = [] }
                            shortcutConfirmed = false
                        })) {
                            Text("请选择").tag(nil as UInt16?)
                            ForEach(Array(VoiceInputProfile.functionKeyCodes.enumerated()), id: \.offset) { offset, key in
                                Text("F\(offset + 13)").tag(Optional(key))
                            }
                            Text("空格（须组合修饰键）").tag(Optional(UInt16(49)))
                        }.frame(width: 240)
                        ForEach(KeyModifier.allCases, id: \.self) { modifier in
                            Toggle(modifierSymbol(modifier), isOn: Binding(get: { profile.shortcutModifiers.contains(modifier) }, set: { enabled in
                                profile.shortcutModifiers.removeAll { $0 == modifier }
                                if enabled { profile.shortcutModifiers.append(modifier) }
                                shortcutConfirmed = false
                            })).toggleStyle(.checkbox).disabled(profile.shortcutKeyCode != 49)
                        }
                    }
                    if !external.canAutomateShortcut {
                        Text("自动快捷键需要 Vibe Remote 辅助功能权限，请在「连接与权限」中启用。")
                            .foregroundStyle(.orange)
                    }
                }
                TextField("快捷键备注（例如输入法里原来的 Fn）", text: $profile.shortcutNote)
                Text("默认手动模式。若输入法支持修改快捷键，可在两边设置相同的 F20 或带修饰键的空格，再选按住/切换。Fn/地球键不做模拟，不能修改时继续使用手动模式。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(8).disabled(!controls.canEdit)
        }
    }

    private func modifierSymbol(_ value: KeyModifier) -> String {
        switch value { case .command: return "⌘"; case .option: return "⌥"; case .control: return "⌃"; case .shift: return "⇧" }
    }
    private func refresh() {
        devices = external.devices
        let found = VoiceProviderApps.discover(selected, configuredPath: profile.appPath)
        if found != installed { microphoneConfirmed = false; shortcutConfirmed = false; autoSendDisabled = false }
        installed = found
    }
    private func loadSelection() {
        profile = (controls.settings.voiceInput ?? VoiceInputConfiguration()).profile(for: selected)
        microphoneConfirmed = false; shortcutConfirmed = false; autoSendDisabled = false
        refresh()
    }
    @discardableResult
    private func save() -> Bool {
        var config = controls.settings.voiceInput ?? VoiceInputConfiguration()
        config.provider = selected
        config.destination = destination
        if selected.isExternal { config.setProfile(profile) }
        let saved = controls.updateSettings { $0.voiceInput = config }
        status = saved ? "已保存 \(selected.title) · \(destination.title)。输入法设置仍需在对应应用中核对。" : controls.statusText
        return saved
    }
    private func prepare() {
        guard controls.canEdit, voice.ready else { return }
        if destination == .currentFocus, let reason = external.currentInputPreparationBlockReason {
            status = reason
            return
        }
        guard save() else { return }
        do {
            try external.prepare(profile, destination: destination, microphoneConfirmed: microphoneConfirmed,
                                 shortcutConfirmed: shortcutConfirmed, autoSendDisabled: autoSendDisabled)
        }
        catch { status = error.localizedDescription }
        microphoneConfirmed = false; shortcutConfirmed = false; autoSendDisabled = false
    }
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let info = VoiceProviderApps.discover(selected, configuredPath: url.path) else {
            status = "未选择对应输入法应用；请核对 .app 类型。"; return
        }
        profile.appPath = info.path; profile.bundleIdentifier = info.bundleIdentifier
        microphoneConfirmed = false; shortcutConfirmed = false; autoSendDisabled = false
        installed = info
    }
}

/// Direct providers insert their own text. This view only settles their observed
/// completion; it must never import or insert that text a second time.
struct ExternalDirectStatusView: View {
    @ObservedObject var external: ExternalDictationController
    @ObservedObject var voice: RemoteModel
    @State private var providerFinished = false

    var body: some View {
        GroupBox("当前输入框听写") {
            VStack(alignment: .leading, spacing: 12) {
                Text(external.status).fixedSize(horizontal: false, vertical: true)
                Text("文字由输入法直接填入目标；Vibe Remote 不会再次插入。请等输入法完成后再切换输入位置。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("我已确认输入法停止录音、识别完成", isOn: $providerFinished)
                    .disabled(!external.canSettle || voice.isReceivingAudio)
                HStack {
                    if voice.isReceivingAudio || !external.canSettle {
                        Button("中断并检查") { external.interrupt(); voice.stopCapture() }
                    }
                    Button("结束本次准备") { _ = external.discard(providerFinished: providerFinished) }
                        .disabled(!external.canSettle || voice.isReceivingAudio || !providerFinished)
                    Spacer()
                    Button("准备下一段") { _ = external.completeDirect(providerFinished: providerFinished) }
                        .buttonStyle(.borderedProminent)
                        .disabled(external.phase != .review || voice.isReceivingAudio || !providerFinished)
                }
                Text("继续听写可选「准备下一段」。需要用遥控器确认发送时，请先选「结束本次准备」，再回到已绑定输入框按确认键。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: external.phase) { _ in providerFinished = false }
    }
}

struct ExternalDictationSheet: View {
    @ObservedObject var external: ExternalDictationController
    @ObservedObject var voice: RemoteModel
    @State private var providerFinished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(external.profile?.provider.title ?? "第三方") · 听写接收框").font(.title2.bold())
            Text("工作区已锁定。保持此窗口，等待输入法把文字填到下面；这里不会自动发送。")
                .foregroundStyle(.secondary)
            Text(external.status).fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(voice.isReceivingAudio ? "遥控器正在收音" : "等待遥控器音频", systemImage: "waveform")
                ProgressView(value: max(0, min(1, (voice.level + 60) / 60)))
            }
            ExternalDraftReceiver(external: external)
                .frame(minHeight: 180, maxHeight: 280)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Toggle("我已确认输入法停止录音、识别完成，文字已全部出现", isOn: $providerFinished)
                .disabled(!external.canSettle || voice.isReceivingAudio)
            HStack {
                if voice.isReceivingAudio || !external.canSettle {
                    Button("中断并检查") { external.interrupt(); voice.stopCapture() }
                }
                Button("放弃本段并关闭") { _ = external.discard(providerFinished: providerFinished) }
                    .disabled(!external.canSettle || voice.isReceivingAudio || !providerFinished)
                Spacer()
                Button("加入工作区草稿") {
                    guard !voice.isReceivingAudio,
                          let text = external.takeResult(providerFinished: providerFinished) else { return }
                    _ = voice.appendExternalResult(text)
                }.buttonStyle(.borderedProminent)
                    .disabled(external.phase != .review || voice.isReceivingAudio || !providerFinished || external.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("若输入法仍在录音，请先用它自己的结束操作。中断不会猜测切换式输入法的状态。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 680)
            .onChange(of: external.phase) { _ in providerFinished = false }
            .onChange(of: external.resultText) { _ in providerFinished = false }
    }
}

/// Own NSTextView identity is checked locally; this never inspects another app's UI.
private struct ExternalDraftReceiver: NSViewRepresentable {
    @ObservedObject var external: ExternalDictationController
    func makeCoordinator() -> Coordinator { Coordinator(external) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 630, height: 180))
        text.minSize = NSSize(width: 0, height: 180)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.font = .systemFont(ofSize: 15)
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("第三方听写接收框")
        text.delegate = context.coordinator
        scroll.documentView = text; scroll.hasVerticalScroller = true
        external.receiverIsFocused = { [weak text] in
            guard let text, let window = text.window else { return false }
            return NSApp.isActive && window.isKeyWindow && window.firstResponder === text
        }
        DispatchQueue.main.async { [weak text] in
            guard let text else { return }
            text.window?.makeFirstResponder(text)
        }
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
    final class Coordinator: NSObject, NSTextViewDelegate {
        let external: ExternalDictationController
        init(_ external: ExternalDictationController) { self.external = external }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            external.resultText = text.string
        }
    }
}
