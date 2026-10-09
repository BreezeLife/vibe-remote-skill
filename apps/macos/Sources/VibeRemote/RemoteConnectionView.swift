import AppKit
import SwiftUI
import VibeRemoteCore

/// The same explicit device picker is used in dictation and connection settings.
struct RemoteConnectionView: View {
    @ObservedObject var model: RemoteModel
    var editsLocked = false

    private var discovery: RemoteDiscoveryState { model.discovery }
    private var connectionActive: Bool {
        model.ready || discovery.connectingID != nil || discovery.connectedID != nil
    }
    private var canSelect: Bool { !editsLocked && !model.isBusy && !connectionActive }
    private var canForget: Bool { canSelect && !discovery.isScanning && discovery.rememberedID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(model.ready ? Color.green : Color.secondary)
                Text(model.connectionStatus)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if discovery.isScanning || discovery.connectingID != nil {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(discovery.isScanning ? "正在扫描遥控器" : "正在连接遥控器")
                }
            }

            HStack(spacing: 10) {
                Button(discovery.isScanning ? "停止搜索" : "搜索附近遥控器") {
                    if discovery.isScanning { model.stopDiscovery() }
                    else { model.discoverRemotes() }
                }
                .disabled(!discovery.isScanning && !canSelect)
                .help("扫描附近广播和系统已有连接；发现设备后，由你点击选择。")
                if discovery.rememberedID != nil {
                    Button("连接已选遥控器", action: model.connect)
                        .disabled(!canSelect)
                        .help("尝试连接上次选择的遥控器；记录本身不表示设备在线。")
                }
                Spacer(minLength: 0)
                Button(discovery.connectingID != nil ? "取消连接" : "断开", action: model.disconnect)
                    .disabled(!connectionActive && !discovery.isScanning &&
                              !(discovery.autoReconnectEnabled && discovery.rememberedID != nil))
                    .help("断开当前连接，并停止本次自动重连。")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("可选设备").font(.caption.weight(.semibold))
                    Spacer()
                    Text(discovery.isScanning ? "正在扫描…" : "\(discovery.devices.count) 台")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if discovery.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(discovery.isScanning ? "正在查找，请按一下遥控器将其唤醒。" : "点击「搜索附近遥控器」开始查找。")
                            .font(.callout)
                        Text("列表中的设备仍需连接并完成语音协议验证。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(discovery.devices) { device in
                                deviceRow(device)
                                if device.id != discovery.devices.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(height: CGFloat(min(discovery.devices.count, 3)) * 65)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .accessibilityLabel("可选择的语音遥控器")
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Toggle("自动重连已选遥控器", isOn: Binding(
                    get: { discovery.autoReconnectEnabled }, set: model.setAutoReconnect))
                    .toggleStyle(.checkbox)
                    .disabled(editsLocked || model.isBusy)
                    .help("空闲时意外断开最多重试 3 次，仅连接已选设备；重新打开应用后仍需点击连接。")
                Spacer(minLength: 0)
                Button("忘记选择", action: model.forgetRemote)
                    .disabled(!canForget)
                    .help("仅清除此应用记住的遥控器；不会取消 macOS 的蓝牙配对。")
            }
            Text("本次运行中空闲意外断开时，最多重试 3 次。手动断开、手动结束收音或重新打开应用后，请点击连接。上次选择不代表当前在线。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                Text(connectionActive ? "切换遥控器前，请先断开当前连接。" :
                     "未发现设备时，先唤醒遥控器并检查蓝牙配对；如 macOS 要求配对确认，请在系统提示中完成。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("蓝牙设置", action: openBluetoothSettings)
                    .help("打开 macOS 系统设置中的蓝牙页面。")
            }
        }
    }

    private func deviceRow(_ device: NearbyRemote) -> some View {
        let ready = model.ready && discovery.connectedID == device.id
        let connecting = discovery.connectingID == device.id
        let verifying = discovery.connectedID == device.id && !ready
        let state = ready ? "语音已就绪" : connecting ? "正在连接" : verifying ? "验证语音协议" : "点击连接"
        return Button { model.selectRemote(device.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: ready ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(ready ? Color.green : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(device)).font(.callout.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(sourceLabel(device)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(state).font(.caption.weight(.medium))
                        .foregroundStyle(ready ? Color.green : connecting || verifying ? Color.orange : Color.accentColor)
                    if let rssi = device.rssi {
                        Text("信号 \(rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .help("本次搜索观察到的广播信号强度，不能直接换算为距离。")
                    } else if discovery.rememberedID == device.id {
                        Text("上次选择").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).frame(height: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ready || connecting ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .help(canSelect ? "连接 \(displayName(device))；完成协议验证后才能使用语音。" : "切换遥控器前，请先断开并等待当前操作结束。")
        .accessibilityLabel("\(displayName(device))，\(sourceLabel(device))")
        .accessibilityValue(state)
    }

    private func displayName(_ device: NearbyRemote) -> String {
        let name = device.name.isEmpty ? "未命名遥控器" : device.name
        let duplicates = discovery.devices.filter { $0.name == device.name }.count > 1
        return duplicates ? "\(name) · \(device.id.uuidString.suffix(6))" : name
    }

    private func sourceLabel(_ device: NearbyRemote) -> String {
        let ready = model.ready && discovery.connectedID == device.id
        switch device.source {
        case .advertisement:
            return device.advertisesAudioService ? "本次发现 · 广播含语音服务" : ready ? "本次发现" : "本次发现 · 语音待验证"
        case .systemConnected:
            return ready ? "来自系统已有蓝牙连接" : "系统已连接 · 语音待验证"
        case .remembered:
            return ready ? "来自上次选择" : "上次选择 · 当前是否在线未知"
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}
