import SwiftUI
import VibeRemoteCore

struct ButtonSettingsView: View {
    @ObservedObject var model: ControlsModel
    @State private var resetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeading(title: "按键", detail: "点击示意图编辑动作；未锁定选择时，实体键只高亮和选择，不执行动作。所有工具共用按键意图。")
            HStack(alignment: .top, spacing: 30) {
                remoteDiagram
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: model.selectedButton.symbol).font(.title2)
                        Text(model.selectedButton.label).font(.title2.bold())
                        Spacer()
                        Toggle("锁定选择", isOn: $model.lockButtonSelection).toggleStyle(.checkbox)
                    }
                    if model.selectedButton == .mic {
                        GroupBox {
                            Text("语音键由 ATVV 音频协议专用。按住收音，松开整理草稿，不额外生成 Fn 或键盘事件。")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    } else {
                        GroupBox("动作") {
                            VStack(alignment: .leading, spacing: 14) {
                                actionPicker("单击", get: { model.mapping.single }, set: { value in model.updateMapping { $0.single = value } })
                                Toggle("启用长按 · 600 ms", isOn: Binding(get: { model.mapping.long != nil }, set: { enabled in
                                    model.updateMapping { $0.long = enabled ? RemoteAction.none : nil }
                                })).disabled(model.mapping.input?.supportsHold != true)
                                if model.mapping.long != nil {
                                    actionPicker("长按", get: { model.mapping.long ?? .none }, set: { value in model.updateMapping { $0.long = value } })
                                }
                                Toggle("启用双击 · 300 ms", isOn: Binding(get: { model.mapping.double != nil }, set: { enabled in
                                    model.updateMapping { $0.double = enabled ? RemoteAction.none : nil }
                                }))
                                if model.mapping.double != nil {
                                    actionPicker("双击", get: { model.mapping.double ?? .none }, set: { value in model.updateMapping { $0.double = value } })
                                    Text("启用双击后，单击会等待 300 ms；长按和双击不会再触发单击。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(8)
                        }.disabled(!model.canEdit)
                        GroupBox("实体键学习") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let input = model.mapping.input {
                                    Label("已学习 · usage \(input.usagePage):\(input.usage) · report \(input.reportID)", systemImage: "checkmark.circle")
                                        .font(.callout.monospacedDigit())
                                    Text(input.supportsHold ? "已观察到按住及松开，可配置长按。" : "当前只确认短按；需要长按时重新学习并按住约 1 秒。")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("尚未学习。先在「连接与权限」中选择遥控器。")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button(model.learningButton == nil ? "学习此键" : "正在等待按住并松开…", action: model.learnButton)
                                        .disabled(model.learningButton != nil || !model.canEdit)
                                    if model.learningButton != nil { Button("取消", action: model.cancelButtonLearning) }
                                    if model.mapping.input != nil { Button("清除键值") { model.updateMapping { $0.input = nil } }.disabled(!model.canEdit) }
                                }
                                Text("学习期间映射暂停。观察模式仍可能触发系统原始按键；独占校准后再验证并启用动作。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("滚动和音量支持持续按住。发送、停止与工作区选择只执行一次。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("恢复默认按键") { resetting = true }.disabled(!model.canEdit)
                Spacer()
                Button("复制配置") { model.exportSettings(toClipboard: true) }
                Button("导入 JSON", action: model.importSettings).disabled(!model.canEdit)
                Button("导出 JSON") { model.exportSettings() }
            }
        }.padding(28)
        .alert("恢复默认动作并清除学习的键值？", isPresented: $resetting) {
            Button("取消", role: .cancel) { }
            Button("恢复") { model.restoreButtonDefaults() }
        } message: { Text("编程工具和草稿会保留。上一份配置会保存为本机备份。") }
    }

    private func actionPicker(_ title: String, get: @escaping () -> RemoteAction,
                              set: @escaping (RemoteAction) -> Void) -> some View {
        Picker(title, selection: Binding(get: get, set: set)) {
            ForEach(RemoteAction.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }
    private var remoteDiagram: some View {
        VStack(spacing: 20) {
            HStack { key(.power); Spacer(); key(.tv) }
            key(.mic)
            VStack(spacing: 8) {
                key(.up)
                HStack(spacing: 10) { key(.left); key(.ok); key(.right) }
                key(.down)
            }
            HStack(spacing: 10) { key(.back); key(.home); key(.menu) }
            HStack(spacing: 24) { key(.volumeDown); key(.volumeUp) }
            Text("XIAOMI REMOTE").font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(2).foregroundStyle(.tertiary).padding(.top, 6)
        }.padding(24).frame(width: 228)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 50))
            .overlay(RoundedRectangle(cornerRadius: 50).stroke(.quaternary))
    }
    private func key(_ button: RemoteButton) -> some View {
        Button { model.selectedButton = button } label: {
            Image(systemName: button.symbol).font(.system(size: button == .ok ? 24 : 17, weight: .medium))
                .frame(width: 46, height: 46)
                .background(model.selectedButton == button ? Color.accentColor.opacity(0.24) : Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().stroke(model.pressedButton == button ? Color.orange : model.selectedButton == button ? .accentColor : .clear, lineWidth: 2))
                .foregroundStyle(button == .mic ? Color.orange : .primary)
        }.buttonStyle(.plain).help(button.label).accessibilityLabel(button.label)
    }
}

extension RemoteButton {
    var symbol: String {
        switch self {
        case .power: return "power"
        case .mic: return "mic.fill"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .ok: return "circle.inset.filled"
        case .back: return "arrow.uturn.backward"
        case .home: return "house"
        case .menu: return "line.3.horizontal"
        case .tv: return "tv"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        }
    }
}
