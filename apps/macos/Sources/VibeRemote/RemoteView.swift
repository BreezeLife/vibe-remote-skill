import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: RemoteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Vibe Remote").font(.largeTitle.weight(.semibold))
                    Text("按住说话 · 松开成稿 · 确认后使用")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("开发预览 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1")")
                    .font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: model.ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(model.ready ? Color.green : Color.secondary)
                        Text(model.connectionStatus).font(.callout)
                        Spacer()
                        Button("连接遥控器", action: model.connect).disabled(model.isBusy)
                        Button("断开", action: model.disconnect)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                        Text(model.captureLabel).frame(width: 105, alignment: .leading)
                        ProgressView(value: max(0, min(1, (model.level + 60) / 60)))
                            .tint(model.isReceivingAudio ? .orange : .accentColor)
                            .accessibilityLabel("遥控器音量")
                        Text(model.sampleRate > 0
                             ? String(format: "%.1f 秒 · %d kHz", Double(model.sampleCount) / Double(model.sampleRate), model.sampleRate / 1000)
                             : "等待音频")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                    if let issue = model.recognitionIssue {
                        Label(issue, systemImage: "exclamationmark.bubble")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(6)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("识别语言", selection: $model.localeIdentifier) {
                        Text("普通话").tag("zh-CN")
                        Text("English (US)").tag("en-US")
                    }.frame(width: 220).disabled(model.isBusy)
                    Toggle("允许 Apple 在线识别", isOn: $model.allowServerRecognition)
                        .disabled(model.isBusy)
                    Text(model.allowServerRecognition
                         ? "已允许音频交给 Apple 语音服务处理。"
                         : "默认仅本机识别；缺少语言支持时会提示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.recognitionEnabled ? "语音识别已授权" : "启用语音识别",
                       action: model.enableRecognition)
                    .disabled(model.recognitionEnabled || model.requestingAuthorization || model.isBusy)
                    .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("草稿").font(.headline)
                    Spacer()
                    Text("仅保留在内存中，退出前请复制")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextEditor(text: Binding(get: { model.draft.text }, set: { model.replaceDraft($0) }))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .disabled(model.isBusy)
                    .accessibilityLabel("听写草稿")
                    .frame(minHeight: 150)
            }

            HStack {
                Text(model.message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                if model.isBusy {
                    if model.draft.isBusy {
                        Button("取消本段", action: model.cancelUtterance)
                    }
                    Button("结束收音", action: model.stopCapture)
                        .disabled(!model.isReceivingAudio)
                } else {
                    Button("复制草稿", action: model.copyDraft)
                        .buttonStyle(.borderedProminent).disabled(!model.canCopy)
                }
            }.frame(minHeight: 44)
            Text("首版直接连接小米遥控器，使用 macOS 语音识别。豆包虚拟麦克风与其他按键映射仍在开发计划中。")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(minWidth: 700, minHeight: 610)
    }
}
