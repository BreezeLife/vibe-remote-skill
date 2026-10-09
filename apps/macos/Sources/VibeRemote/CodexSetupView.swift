import SwiftUI
import VibeRemoteCore

struct CodexSetupView: View {
    @ObservedObject var model: ControlsModel
    @State private var showsChecks = false
    @State private var showsGuide = false

    init(model: ControlsModel, showsChecks: Bool = false, showsGuide: Bool = false) {
        self.model = model
        _showsChecks = State(initialValue: showsChecks)
        _showsGuide = State(initialValue: showsGuide)
    }

    private let checkLabels: [(String, String)] = [
        ("installation", "应用安装"), ("catalog", "会话目录"), ("navigation", "会话定位"),
        ("input", "输入框"), ("submission", "发送 / 补充输入")
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Codex", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("一键配置 Codex", action: model.configureCodex)
                        .buttonStyle(.borderedProminent).disabled(!model.canEdit)
                        .help("读取本机会话目录并准备默认按键；选择会话后配置目标。")
                }
                Text("读取本机会话目录并准备默认按键。选择会话后自动配置并尝试聚焦；已有手动工作区、草稿和自定义按键会保留。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.codexSetupStatus).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.codexProjectPaths.isEmpty {
                    CodexSessionNavigationView(model: model)
                    sessionList
                } else {
                    Text("先点击「一键配置 Codex」，再选择项目与会话。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("检查所选会话", action: model.checkCodexSession)
                        .disabled(!model.canEdit || model.workspace?.codexConversation == nil)
                        .help("打开所选会话并检查输入框聚焦；不插入或提交文字。")
                    if !model.accessibilityGranted {
                        Button("启用辅助功能", action: model.requestAccessibility)
                    }
                    Spacer(minLength: 0)
                    Text("检查只定位和聚焦，不发送测试消息。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                DisclosureGroup("安装与上次检查结果", isExpanded: $showsChecks) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(checkLabels, id: \.0) { key, label in
                            if key == "navigation" {
                                Divider()
                                Text(model.workspace?.codexConversation.map { "检查目标：\($0.title)" } ?? "尚未选择 Codex 会话")
                                    .fontWeight(.medium)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(alignment: .top, spacing: 14) {
                                Text(label).frame(width: 105, alignment: .leading)
                                Text(model.codexChecks[key] ?? "尚未检查")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("会话定位、输入与提交结果只记录所选会话的上次检查，不会持续跟踪 Codex 窗口。目录已读取或按键已配置不代表实机能力已通过；每次操作仍会验证当前目标。")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).padding(.top, 8)
                }

                DisclosureGroup("实机测试指引", isExpanded: $showsGuide) {
                    VStack(alignment: .leading, spacing: 12) {
                        guideStep("1", title: "检查权限与遥控器", detail: "在「连接与权限」中连接语音遥控器，启用语音识别、输入监控和辅助功能。完成 HID 独占接管、实体键学习，并验证本次连接的原始按键不穿透、语音仍能收音，再启用动作。")
                        guideStep("2", title: "选择项目和会话", detail: "先在同一项目选择两个会话，用遥控器上 / 下切换；左 / 右切换项目。每次检查 Codex 标题、输入框聚焦和草稿归属，确认目标后再说话。")
                        guideStep("3", title: "按住说话，松开检查草稿", detail: "语音松开后保留为未发送草稿。切换会话再返回，确认每个会话保留自己的草稿。")
                        guideStep("4", title: "第一次 OK：确认输入", detail: "第一次按 OK 将草稿插入所选输入框；控件与状态检查通过时打开完整内容确认页。先检查目标和文字，再按一次 OK 或点击确认按钮提交。")
                        guideStep("5", title: "检查运行中的补充输入", detail: "任务运行时，若实时识别到 Steer / 补充输入控件，优先使用它，确认页会明确显示「补充当前任务」。缺少所需能力时保留草稿和已插入文字，由你检查后手动发送。")
                        Text("提交后草稿仍保留；下一条指令请先清空草稿再说话。提交或写入结果不确定时会阻止重复 OK，请检查 Codex 后手动处理。")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("前往连接与权限") { model.page = .connection }
                    }.padding(.top, 8)
                }
            }.padding(10)
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当前项目的会话").font(.caption.weight(.semibold))
                Spacer()
                Text("\(model.codexSessionProfiles.count) 个").font(.caption).foregroundStyle(.secondary)
            }
            if model.codexSessionProfiles.isEmpty {
                Text("这个项目尚无可选会话；可刷新配置，或在 Codex 中先创建会话。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.codexSessionProfiles) { profile in
                            Button { model.openCodexSession(profile.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: model.voice.workspaceID == profile.id ? "checkmark.circle.fill" : "bubble.left")
                                        .foregroundStyle(model.voice.workspaceID == profile.id ? Color.accentColor : Color.secondary)
                                    Text(profile.codexConversation?.title ?? profile.name)
                                        .font(.callout).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if model.voice.workspaceID == profile.id {
                                        Text("当前草稿工作区").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10).frame(height: 52)
                                .background(model.voice.workspaceID == profile.id ? Color.accentColor.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!model.canEdit)
                            .help("打开此会话并尝试聚焦输入框。")
                            .accessibilityLabel("打开会话：\(profile.codexConversation?.title ?? profile.name)")
                            if profile.id != model.codexSessionProfiles.last?.id { Divider() }
                        }
                    }
                }
                .frame(height: CGFloat(min(model.codexSessionProfiles.count, 4)) * 53)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
        }
    }

    private func guideStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.weight(.semibold)).frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Metadata selection is separate from successful navigation or input focus.
struct CodexSessionNavigationView: View {
    @ObservedObject var model: ControlsModel

    private var currentIndex: Int? {
        model.codexSessionProfiles.firstIndex { $0.id == model.voice.workspaceID }
    }

    var body: some View {
        HStack(spacing: 10) {
            Picker("项目", selection: $model.codexProjectPath) {
                Text("选择项目").tag("")
                ForEach(model.codexProjectPaths, id: \.self) { path in Text(path).tag(path) }
            }
            .frame(minWidth: 150, maxWidth: .infinity)
            .help(model.codexProjectPath.isEmpty ? "选择 Codex 项目" : model.codexProjectPath)
            Picker("会话", selection: Binding<UUID?>(
                get: { currentIndex == nil ? nil : model.voice.workspaceID },
                set: { if let id = $0 { model.openCodexSession(id) } })) {
                Text("选择会话").tag(nil as UUID?)
                ForEach(model.codexSessionProfiles) { profile in
                    Text(profile.codexConversation?.title ?? profile.name).tag(Optional(profile.id))
                }
            }.frame(minWidth: 150, maxWidth: .infinity)
            Button { model.perform(.previousConversation) } label: { Image(systemName: "chevron.up") }
                .disabled(currentIndex == nil || currentIndex == 0)
                .help("上一个会话 · 当前项目内")
                .accessibilityLabel("上一个会话")
            Button { model.perform(.nextConversation) } label: { Image(systemName: "chevron.down") }
                .disabled(currentIndex == nil || currentIndex == model.codexSessionProfiles.count - 1)
                .help("下一个会话 · 当前项目内")
                .accessibilityLabel("下一个会话")
        }.disabled(!model.canEdit)
    }
}
