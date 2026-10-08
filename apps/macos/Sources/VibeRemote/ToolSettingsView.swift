import AppKit
import SwiftUI
import VibeRemoteCore

struct ToolSettingsView: View {
    @ObservedObject var model: ControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeading(title: "编程工具", detail: "先选择应用，再绑定具体工作区。安装状态、绑定配置与真实动作的检查结果分别显示。")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(model.installedTools) { tool in
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            if let path = tool.appPath {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 38, height: 38)
                            } else { Image(systemName: "app.dashed").font(.largeTitle).foregroundStyle(.secondary) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tool.name).font(.headline)
                                Text(tool.version.map { "已安装 · \($0)" } ?? "未检测到安装").font(.caption).foregroundStyle(.secondary)
                                Text(tool.bundleIdentifier).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                                if let preset = CodingToolPreset.matching(bundleIdentifier: tool.bundleIdentifier) {
                                    Text("\(preset.title) 默认按键 · 添加后可单独调整")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("使用默认方案添加工作区") { model.addWorkspace(tool) }.disabled(!model.canEdit)
                                } else {
                                    Button("添加工作区") { model.addWorkspace(tool) }.disabled(!model.canEdit)
                                }
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }
            HStack {
                Button("选择其他 .app", action: model.chooseCustomApp).disabled(!model.canEdit)
                Button("刷新安装状态", action: model.refreshTools)
                Spacer()
                Text("CLI 通过独立适配接入；此处不绑定普通终端。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if let profile = model.workspace {
                WorkspaceEditor(model: model, profile: profile).id(profile.id)
            } else {
                Label("添加一个工作区，或在窗口顶部选择已登记的工作区。", systemImage: "cursorarrow.click")
                    .foregroundStyle(.secondary).padding(.vertical, 24)
            }
        }.padding(28)
    }
}

private struct WorkspaceEditor: View {
    @ObservedObject var model: ControlsModel
    let profile: WorkspaceProfile
    @State private var name: String
    @State private var preview: String
    @State private var thread: String
    @State private var stopping = false
    @State private var applyingPreset = false

    init(model: ControlsModel, profile: WorkspaceProfile) {
        self.model = model; self.profile = profile
        _name = State(initialValue: profile.name)
        _preview = State(initialValue: profile.previewURL ?? "")
        _thread = State(initialValue: profile.codexThreadURL ?? "")
    }
    private var current: WorkspaceProfile { model.settings.workspaces.first { $0.id == profile.id } ?? profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("工作区设置").font(.title2.bold())
                Spacer()
                Button("复制工作区") { model.duplicateWorkspace(current) }.disabled(!model.canEdit)
            }
            if let preset = CodingToolPreset.matching(bundleIdentifier: current.bundleIdentifier) {
                GroupBox("\(preset.title) 按键方案") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(current.buttonActions == nil ? "沿用已有通用配置；可主动应用本工具默认方案。" :
                             current.buttonActions == preset.buttonActions && current.shortcuts.isEmpty ?
                             "已使用默认方案；动作只作用于这个工作区。" : "已使用自定义方案；动作只作用于这个工作区。")
                            .font(.callout)
                        HStack {
                            Button("应用默认方案") { applyingPreset = true }.disabled(!model.canEdit)
                            Button("编辑本工作区按键") { model.page = .buttons }
                        }
                        DisclosureGroup("查看默认按键对照") {
                            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                                GridRow {
                                    Text("实体按键").bold(); Text("单击").bold(); Text("按住 / 长按").bold()
                                }
                                ForEach(preset.buttonActions, id: \.button) { action in
                                    GridRow {
                                        Text(action.button.label)
                                        Text(action.button == .mic ? "—" : action.button == .ok ? "确认选择 / 预览并确认发送" : action.single.label)
                                        Text(action.button == .mic ? "按住说话，松开成稿" :
                                             action.long?.label ?? (action.single.allowsRepeat ? "持续\(action.single.label)" : "—"))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }.font(.caption).padding(.top, 8)
                        }
                        Text("三种工具保持相同按键习惯，目标跟随工作区。默认不启用双击。语音专用键无需 HID 学习；其他实体键仍需学习，目标输入与发送/停止控件仍需绑定。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("工作区名称", text: $name)
                    TextField("预览地址 · https://…", text: $preview)
                    if current.bundleIdentifier == "com.openai.codex" {
                        TextField("精确会话入口 · codex://threads/…（可选）", text: $thread)
                    }
                    if current.bundleIdentifier == "com.openai.codex" {
                        HStack {
                            Button("打开绑定会话", action: model.openCodexThread).disabled(current.codexThreadURL == nil)
                            Button("在 Codex 预填新草稿", action: model.prefillNewCodexDraft).disabled(!model.voice.canCopy)
                        }
                    }
                    HStack {
                        Button("保存工作区信息") {
                            var updated = current
                            updated.name = name
                            updated.previewURL = preview.isEmpty ? nil : preview
                            updated.codexThreadURL = thread.isEmpty ? nil : thread
                            model.updateWorkspace(updated)
                        }
                        Text("会话入口只用于定位；不会自动新建或发送。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.textFieldStyle(.roundedBorder).padding(8)
            }.disabled(!model.canEdit)
            GroupBox("绑定输入与会话") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("每步有 5 秒准备时间。先点击目标输入框，再把鼠标停在当前会话独有的标题上。不要选择侧栏中其他会话的标题。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("1. 学习输入框") { model.learn(.input, for: current) }
                        Button("2. 学习会话标题") { model.learn(.anchor, for: current) }
                            .disabled(!model.hasLearnedInput(for: current.id))
                        Button("测试聚焦") { model.perform(.focusTarget) }.disabled(current.binding == nil)
                    }
                    if let binding = current.binding {
                        Text("已保存窗口：\(binding.windowTitle)\n会话标记：\(binding.taskAnchor.label ?? binding.taskAnchor.identifier ?? "")\n绑定版本：\(binding.appVersion)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text(model.hasLearnedInput(for: current.id) ? "输入框已暂存，继续学习会话标题。" : "尚未绑定；仅安装应用不会启用自动输入。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.disabled(!model.canEdit || !model.accessibilityGranted)
            GroupBox("发送与停止") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("分别把鼠标停在真正的发送、停止生成按钮上学习。停止按钮可能只在任务运行时出现；没有可确认的状态时保持禁用。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("学习发送按钮") { model.learn(.send, for: current) }
                        Button("学习停止按钮") { model.learn(.stop, for: current) }
                        Spacer()
                        Button("停止当前任务") { stopping = true }
                            .disabled(current.binding?.stopControl == nil)
                    }.disabled(current.binding == nil || !model.canEdit || !model.accessibilityGranted)
                    ForEach(model.adapter.describeCapabilities(for: current)) { capability in
                        HStack(alignment: .top) {
                            Text(capability.action.label).frame(width: 125, alignment: .leading)
                            Text(model.capabilityDescription(capability, for: current)).foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                    if let results = model.capabilityResults[current.id], !results.isEmpty {
                        Divider()
                        Text("本次运行的操作结果").font(.caption.bold())
                        ForEach(Array(results.suffix(4).enumerated()), id: \.offset) { _, result in
                            Text(result).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            ShortcutSettingsView(model: model, workspace: current)
        }
        .alert("停止这个工作区正在运行的任务？", isPresented: $stopping) {
            Button("取消", role: .cancel) { }
            Button("停止任务") { model.perform(.stopTask) }
        } message: { Text("只有实际会话和停止生成控件通过实时检查时，才会执行。") }
        .alert("应用当前工具的默认按键方案？", isPresented: $applyingPreset) {
            Button("取消", role: .cancel) { }
            Button("应用") { model.applyToolPreset(to: current) }
        } message: {
            Text("将恢复「\(current.name)」的按键动作，并将自定义工具快捷键恢复为默认辅助功能方式。其他工作区、已学习的实体键值、绑定和草稿会保留；上一份配置会备份。")
        }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var model: ControlsModel
    let workspace: WorkspaceProfile
    @State private var action: RemoteAction = .focusTarget
    @State private var key: UInt16 = 37
    @State private var command = true
    @State private var option = false
    @State private var control = false
    @State private var shift = false
    @StateObject private var recorder = ShortcutRecorder()
    private let actions: [RemoteAction] = [.focusTarget, .scrollUp, .scrollDown, .sendDraft, .stopTask]
    private let keys: [(UInt16, String)] = [(37, "L"), (34, "I"), (36, "Return"), (76, "Enter"), (53, "Esc"),
                                         (8, "C"), (126, "↑"), (125, "↓"), (116, "Page Up"), (121, "Page Down")]
    private var candidate: ActionShortcut {
        var modifiers: [KeyModifier] = []
        if command { modifiers.append(.command) }; if option { modifiers.append(.option) }
        if control { modifiers.append(.control) }; if shift { modifiers.append(.shift) }
        return ActionShortcut(action: action, keyCode: key, modifiers: modifiers)
    }
    var body: some View {
        DisclosureGroup("工具动作快捷键（可选）") {
            VStack(alignment: .leading, spacing: 12) {
                Text("默认使用已验证的辅助功能控件。快捷键只实现指定动作；控件未暴露等价快捷键时会拒绝执行，保留默认配置更合适。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("动作", selection: $action) { ForEach(actions, id: \.self) { Text($0.label).tag($0) } }
                    Picker("按键", selection: $key) { ForEach(keys, id: \.0) { Text($0.1).tag($0.0) } }.frame(width: 180)
                }
                HStack {
                    Toggle("⌘", isOn: $command); Toggle("⌥", isOn: $option)
                    Toggle("⌃", isOn: $control); Toggle("⇧", isOn: $shift)
                    Spacer()
                    Button(recorder.isRecording ? "取消录制" : "录制快捷键") {
                        if recorder.isRecording { recorder.cancel() }
                        else {
                            model.pauseMappings(releaseDevice: false)
                            recorder.start { event in
                            key = event.keyCode
                            command = event.modifierFlags.contains(.command)
                            option = event.modifierFlags.contains(.option)
                            control = event.modifierFlags.contains(.control)
                            shift = event.modifierFlags.contains(.shift)
                        } }
                    }
                }.toggleStyle(.checkbox)
                HStack {
                    Button("保存此动作快捷键") {
                        var copy = workspace
                        copy.shortcuts.removeAll { $0.action == action }
                        copy.shortcuts.append(candidate)
                        model.updateWorkspace(copy)
                    }.disabled(!candidate.isSupported)
                    Button("恢复此动作默认方式") {
                        var copy = workspace; copy.shortcuts.removeAll { $0.action == action }; model.updateWorkspace(copy)
                    }
                    if !candidate.isSupported { Text("该组合不符合此动作的限制。") .font(.caption).foregroundStyle(.orange) }
                }
                if recorder.isRecording { Text("请在本窗口按组合键；Esc 取消，10 秒自动结束。") .font(.caption) }
                ForEach(workspace.shortcuts, id: \.action) { item in
                    Text("\(item.action.label)：\(item.modifiers.map(\.rawValue).joined(separator: "+")) · key \(item.keyCode)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
        }.disabled(!model.canEdit).onDisappear { recorder.cancel() }
    }
}

@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var timeout: Timer?
    func start(_ receive: @escaping (NSEvent) -> Void) {
        cancel()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode != 53 { receive(event) }
            self.cancel()
            return nil
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }
    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; timeout?.invalidate(); timeout = nil; isRecording = false
    }
}
