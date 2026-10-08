import SwiftUI
import VibeRemoteCore

struct ButtonSettingsView: View {
    @ObservedObject var model: ControlsModel
    @State private var resetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeading(title: "按键", detail: "按小米遥控器 Pro 2 实物排列。点击对应按键配置动作；未锁定选择时，实体键只高亮和选择。")
            VStack(alignment: .leading, spacing: 5) {
                Label("当前方案：\(model.buttonConfigurationScope)", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text("动作随顶部工作区切换；实体键值只需学习一次，各工作区共用。Codex、Claude、WorkBuddy 默认方案可在「编程工具」中添加或恢复。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                Button("恢复本方案默认动作") { resetting = true }.disabled(!model.canEdit)
                Spacer()
                Button("复制配置") { model.exportSettings(toClipboard: true) }
                Button("导入 JSON", action: model.importSettings).disabled(!model.canEdit)
                Button("导出 JSON") { model.exportSettings() }
            }
        }.padding(28)
        .alert("恢复当前方案的默认动作？", isPresented: $resetting) {
            Button("取消", role: .cancel) { }
            Button("恢复") { model.restoreButtonDefaults() }
        } message: { Text("仅恢复「\(model.buttonConfigurationScope)」的按键动作；已学习的实体键值、工具快捷键、绑定与草稿会保留。上一份配置会保存为本机备份。") }
    }

    private func actionPicker(_ title: String, get: @escaping () -> RemoteAction,
                              set: @escaping (RemoteAction) -> Void) -> some View {
        Picker(title, selection: Binding(get: get, set: set)) {
            ForEach(RemoteAction.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }
    private var remoteDiagram: some View {
        VStack(spacing: 18) {
            HStack {
                key(.power, shape: Circle(), width: 40, height: 40, light: true)
                Spacer()
                key(.mic, shape: Circle(), width: 40, height: 40, light: true)
            }.padding(.horizontal, 9)

            ZStack {
                Circle().fill(Color(white: 0.10))
                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                directionKey(.up, startAngle: -135, x: 0, y: -57)
                directionKey(.right, startAngle: -45, x: 57, y: 0)
                directionKey(.down, startAngle: 45, x: 0, y: 57)
                directionKey(.left, startAngle: 135, x: -57, y: 0)
                key(.ok, shape: Circle(), width: 62, height: 62)
            }.frame(width: 164, height: 164)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    key(.back)
                    key(.home)
                    key(.menu)
                }
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        key(.volumeUp, shape: RemoteRockerHalf(top: true), width: 48, height: 54)
                        key(.volumeDown, shape: RemoteRockerHalf(top: false), width: 48, height: 54)
                    }
                    key(.tv)
                }
            }
            Spacer(minLength: 24)
            VStack(spacing: 5) {
                Text("PRO 2").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2)
                Text("Vibe Remote").font(.system(size: 10, weight: .medium))
            }.foregroundStyle(Color(white: 0.32))
        }
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 22)
        .frame(width: 196, height: 564)
        .background {
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient(colors: [Color(white: 0.56), Color(white: 0.87), Color(white: 0.70), Color(white: 0.57)],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("小米遥控器 Pro 2 按键示意图")
    }

    private func key(_ button: RemoteButton) -> some View {
        key(button, shape: Circle(), width: 48, height: 48)
    }

    private func directionKey(_ button: RemoteButton, startAngle: Double, x: CGFloat, y: CGFloat) -> some View {
        key(button, shape: RemoteDirectionSegment(startAngle: startAngle), width: 164, height: 164,
            iconOffset: CGSize(width: x, height: y))
    }

    private func key<Surface: Shape>(_ button: RemoteButton, shape: Surface, width: CGFloat, height: CGFloat,
                                     light: Bool = false, iconOffset: CGSize = .zero) -> some View {
        let selected = model.selectedButton == button
        let pressed = model.pressedButton == button
        return Button { model.selectedButton = button } label: {
            ZStack {
                shape.fill(light ? Color.white.opacity(0.16) : Color(white: 0.12))
                if selected { shape.fill(Color.accentColor.opacity(light ? 0.25 : 0.38)) }
                if pressed { shape.fill(Color.orange.opacity(0.32)) }
                keySymbol(button)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(light ? Color(white: 0.16) : Color(white: 0.92))
                    .offset(iconOffset)
                shape.stroke(pressed ? Color.orange : selected ? Color.accentColor : (light ? Color.black.opacity(0.45) : Color.white.opacity(0.18)),
                             lineWidth: pressed || selected ? 2.5 : 1)
            }
            .frame(width: width, height: height)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(button.label)
        .accessibilityLabel(button.label)
        .accessibilityValue(pressed ? "实体键按下" : selected ? "已选中" : "未选中")
    }

    @ViewBuilder private func keySymbol(_ button: RemoteButton) -> some View {
        if button == .ok {
            Text("OK").font(.system(size: 11, weight: .semibold))
        } else if button == .tv {
            Text("TV").font(.system(size: 8, weight: .semibold))
                .frame(width: 18, height: 13)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1))
        } else {
            Image(systemName: button.symbol)
        }
    }
}

private struct RemoteDirectionSegment: Shape {
    let startAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2 - 1
        let innerRadius: CGFloat = 35
        let start = Angle.degrees(startAngle + 0.5)
        let end = Angle.degrees(startAngle + 89.5)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct RemoteRockerHalf: Shape {
    let top: Bool

    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        if top {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

extension RemoteButton {
    var symbol: String {
        switch self {
        case .power: return "power"
        case .mic: return "mic"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .ok: return "circle.inset.filled"
        case .back: return "chevron.left"
        case .home: return "house"
        case .menu: return "line.3.horizontal"
        case .tv: return "tv"
        case .volumeUp: return "plus"
        case .volumeDown: return "minus"
        }
    }
}
