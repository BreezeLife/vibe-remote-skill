import AppKit
import SwiftUI
import VibeRemoteCore

struct SettingsViews: View {
    @ObservedObject var voice: RemoteModel
    @ObservedObject var controls: ControlsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Vibe Remote", systemImage: "dpad.fill").font(.headline)
                    Text("遥控器 · 编程工作区").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 14)
                VStack(spacing: 5) {
                    ForEach(ControlsModel.Page.allCases) { page in
                        Button {
                            controls.page = page
                        } label: {
                            Label(page.rawValue, systemImage: page.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(controls.page == page ? Color.accentColor.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(controls.mappingsEnabled ? "按键映射已启用" : "按键映射已暂停",
                          systemImage: controls.mappingsEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .font(.caption).foregroundStyle(controls.mappingsEnabled ? Color.green : .secondary)
                    Button("暂停并释放设备") { controls.pauseMappings() }.font(.caption)
                    Text("0.2 · 桌面应用预览版").font(.caption2).foregroundStyle(.tertiary)
                }
            }.padding(16).frame(width: 185).background(.bar)
            Divider()
            VStack(spacing: 0) {
                workspaceBar
                Divider()
                ScrollView {
                    Group {
                        switch controls.page {
                        case .dictation: RemoteView(model: voice, editsLocked: controls.operationInProgress)
                        case .buttons: ButtonSettingsView(model: controls)
                        case .tools: ToolSettingsView(model: controls)
                        case .connection: ConnectionSettingsView(model: controls, voice: voice, hid: controls.hid)
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(controls.statusText).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if controls.learningTool { Button("取消学习", action: controls.cancelToolLearning) }
                    if controls.operationInProgress { ProgressView().controlSize(.small) }
                }.padding(14).background(.bar)
            }.frame(minWidth: 740)
        }.frame(minWidth: 960, minHeight: 720)
            .sheet(item: $controls.pendingSend) { preview in
                VStack(alignment: .leading, spacing: 16) {
                    Label("确认发送到 \(preview.workspace.name)", systemImage: "paperplane")
                        .font(.title2.bold())
                    Text("\(preview.workspace.bundleIdentifier) · \(preview.workspace.binding?.windowTitle ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("以下是目标输入框中的完整内容。确认时会再次核对目标、文字和任务状态。")
                    ScrollView { Text(preview.confirmation.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                        .frame(minHeight: 200, maxHeight: 400).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("返回检查") { controls.pendingSend = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("确认发送", action: controls.confirmSend).buttonStyle(.borderedProminent)
                    }
                }.padding(24).frame(width: 640)
            }
            .sheet(isPresented: $controls.showingWorkspaces) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("选择工作区").font(.title2.bold())
                    Text("每个工作区保留自己的内存草稿。")
                    Button { controls.selectWorkspace(nil); controls.showingWorkspaces = false } label: {
                        Label("未绑定草稿", systemImage: controls.pickerIndex == 0 ? "arrow.right.circle.fill" : "circle")
                    }
                    ForEach(Array(controls.settings.workspaces.enumerated()), id: \.element.id) { index, profile in
                        Button { controls.selectWorkspace(profile.id); controls.showingWorkspaces = false } label: {
                            Label(profile.name, systemImage: controls.pickerIndex == index + 1 ? "arrow.right.circle.fill" : "circle")
                        }
                    }
                    Button("关闭") { controls.showingWorkspaces = false }.keyboardShortcut(.cancelAction)
                }.padding(24).frame(minWidth: 340)
            }
            .sheet(isPresented: $controls.showingActions) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("动作菜单").font(.title2.bold())
                    ForEach(Array(controls.menuActions.enumerated()), id: \.element) { index, action in
                        Button { controls.showingActions = false; controls.perform(action) } label: {
                            Label(action.label, systemImage: controls.pickerIndex == index ? "arrow.right.circle.fill" : "circle")
                        }
                            .disabled(controls.safety.blockReason(for: action) != nil)
                    }
                    Button("关闭") { controls.showingActions = false }.keyboardShortcut(.cancelAction)
                }.padding(24).frame(minWidth: 300)
            }
    }

    private var workspaceBar: some View {
        HStack(spacing: 12) {
            Picker("草稿工作区", selection: Binding(get: { voice.workspaceID }, set: controls.selectWorkspace)) {
                Text("未绑定草稿").tag(nil as UUID?)
                ForEach(controls.settings.workspaces) { Text($0.name).tag(Optional($0.id)) }
            }.frame(maxWidth: 320).disabled(voice.isBusy || controls.operationInProgress)
            Spacer()
            if controls.workspace != nil {
                Button("聚焦") { controls.perform(.focusTarget) }.disabled(!controls.canEdit)
                Button("插入草稿") { controls.perform(.insertDraft) }.disabled(!voice.canCopy || !controls.canEdit)
                Button("预览发送") { controls.perform(.sendDraft) }
                    .disabled(controls.safety.blockReason(for: .sendDraft) != nil)
            } else {
                Button("添加编程工具") { controls.page = .tools }
            }
        }.padding(14)
    }
}

extension ControlsModel {
    var statusText: String { status }
}

struct SettingsHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
