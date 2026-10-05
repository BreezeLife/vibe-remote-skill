import SwiftUI
import VibeRemoteCore

struct ConnectionSettingsView: View {
    @ObservedObject var model: ControlsModel
    @ObservedObject var voice: RemoteModel
    @ObservedObject var hid: HIDRemoteInputService
    @State private var selectedDevice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeading(title: "连接与权限", detail: "语音和按键是独立连接。只有点击对应按钮时才请求权限或接管设备。")
            GroupBox("语音连接") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(voice.connectionStatus, systemImage: voice.ready ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        Spacer()
                        Button("连接遥控器", action: voice.connect).disabled(voice.isBusy)
                        Button("断开", action: voice.disconnect)
                    }
                    HStack {
                        Text(voice.recognitionEnabled ? "语音识别已授权" : "语音识别尚未授权")
                        Spacer()
                        Button("启用语音识别", action: voice.enableRecognition)
                            .disabled(voice.recognitionEnabled || voice.isBusy || voice.requestingAuthorization)
                    }
                    Text("已配对不等于正在收音；请在听写页检查真实音量和草稿。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("按键输入监控") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(permissionLabel, systemImage: hid.permission == .granted ? "checkmark.circle" : "keyboard")
                        Spacer()
                        Button("授权输入监控", action: hid.requestPermission).disabled(hid.permission == .granted)
                        Button("刷新权限", action: hid.refreshPermission)
                    }
                    Text(hid.status).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("遥控器", selection: $selectedDevice) {
                            Text("请选择本次连接的设备").tag(nil as String?)
                            ForEach(hid.devices) { device in
                                Text("\(device.name) · \(device.interfaceCount) 个接口").tag(Optional(device.id))
                            }
                        }
                        Button("发现设备", action: hid.discover).disabled(hid.permission != .granted)
                    }
                    HStack {
                        Button("开始观察") { if let selectedDevice { hid.startObservation(deviceID: selectedDevice) } }
                            .disabled(selectedDevice == nil)
                        Button("独占接管并校准") { if let selectedDevice { hid.seize(deviceID: selectedDevice) } }
                            .disabled(!canSeize)
                        Button("暂停并释放设备") { model.pauseMappings() }
                    }
                    Text("观察模式不会屏蔽原始按键。独占接管要求完整识别同一遥控器的相关接口；信息不足或其他应用占用时会拒绝启用映射。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("本次连接验收").font(.headline)
                    Text("在独占模式下校准后，检查确认键没有触发系统回车、音量没有重复变化，并按住语音键验证仍能收音。每次重新连接都需重新确认。")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("我已验证本次连接的按键不穿透，且语音收音正常", isOn: Binding(
                        get: { model.suppressionConfirmed }, set: model.setSuppressionConfirmed))
                        .disabled(!hid.isExclusive)
                    HStack {
                        Button("启用已配置动作", action: model.enableMappings)
                            .buttonStyle(.borderedProminent)
                            .disabled(!hid.isExclusive || !model.suppressionConfirmed || model.mappingsEnabled)
                        Button("前往校准按键") { model.page = .buttons }
                        Text(model.mappingsEnabled ? "已启用" : "保持暂停")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
            GroupBox("编程工具辅助功能") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(model.accessibilityGranted ? "辅助功能已授权" : "辅助功能尚未授权", systemImage: "hand.point.up.left")
                        Spacer()
                        Button("启用辅助功能", action: model.requestAccessibility).disabled(model.accessibilityGranted)
                        Button("刷新", action: model.refreshTools)
                    }
                    Text("用于观察你绑定的窗口、定位输入框和操作已校准的控件。配置不会自动发送，也不会读取或保存整段会话正文。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
        }.padding(28)
            .onChange(of: hid.devices) { devices in
                if !devices.contains(where: { $0.id == selectedDevice }) { selectedDevice = nil }
            }
    }
    private var canSeize: Bool { hid.devices.first { $0.id == selectedDevice }?.canSeize == true }
    private var permissionLabel: String {
        switch hid.permission {
        case .granted: return "输入监控已授权"
        case .denied: return "输入监控被拒绝；请到系统设置重新授权"
        case .notDetermined: return "尚未请求输入监控"
        case .unknown: return "输入监控状态未知"
        }
    }
}
