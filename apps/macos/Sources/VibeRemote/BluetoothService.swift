// ATVV connection flow adapted from MiRemoteVoice's BLEBridge.swift:
// https://github.com/VincentKingHsu/MiRemoteVoice
// Copyright (c) 2026 Sima Qingfeng. MIT License.
// See this project's third-party notices for the retained license.
// Only ATVV audio/control are subscribed; no HID keys or Mac microphone are read.

import CoreBluetooth
import Foundation
import VibeRemoteCore

final class BluetoothService: NSObject {
    var onDiscovery: ((RemoteDiscoveryState) -> Void)?
    private(set) var discovery: RemoteDiscoveryState
    var onStatus: ((String) -> Void)?
    var onReady: ((Bool) -> Void)?
    var onStream: ((Bool, Int) -> Void)?
    var onSamples: (([Int16], Int) -> Void)?
    /// RMS level in dBFS, clamped to -60...0; silence is -60.
    var onLevel: ((Double) -> Void)?

    private static let serviceUUID = CBUUID(string: ATVVProtocol.serviceUUID)
    private static let commandUUID = CBUUID(string: ATVVProtocol.txUUID)
    private static let audioUUID = CBUUID(string: ATVVProtocol.rxUUID)
    private static let controlUUID = CBUUID(string: ATVVProtocol.controlUUID)
    // Bluetooth SIG: Human Interface Device = 0x1812 (0x180D is Heart Rate).
    private static let hidUUID = CBUUID(string: "1812")
    private static let savedPeripheralKey = "VibeRemote.verifiedATVVPeripheral"
    private static let selectedPeripheralKey = "VibeRemote.selectedATVVPeripheral"
    private static let autoReconnectKey = "VibeRemote.autoReconnectATVV"
    private let defaults: UserDefaults
    private var catalog = RemoteDiscoveryCatalog()
    private var candidates: [UUID: CBPeripheral] = [:]
    private var scanRequested = false
    private var targetRemoteID: UUID?
    private var reconnectPolicy = RemoteReconnectPolicy()
    private var isReconnectAttempt = false
    private var scanTimer: Timer?
    private var reconnectTimer: Timer?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    // Keep a cancelled attempt separate until CoreBluetooth confirms its end.
    // Otherwise a quick reconnect can reuse its object before old callbacks arrive.
    private var retiringPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var audioCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var audioNotificationConfirmed = false
    private var controlNotificationConfirmed = false
    private var capabilitiesRequested = false
    private var connectionRequested = false
    private var ready = false
    private var protocolHandler = ATVVProtocol()

    private var opening = false
    private var streaming = false
    private var manualStopGate = ManualStopGate()
    private var pendingStopReason: String?
    private var streamID: UInt8 = 0
    private var streamStartedAt: TimeInterval = 0
    private var lastAudioAt: TimeInterval = 0
    private var lastStartSearchAt: TimeInterval = -.infinity
    private var levelSumSquares = 0.0
    private var levelSampleCount = 0
    private var lastLevelAt: TimeInterval = 0

    private var connectionTimer: Timer?
    private var captureTimer: Timer?
    private var keepAliveTimer: Timer?
    private var streamWatchdog: Timer?

    // Loading a remembered selection never creates a central, prompts, or claims readiness.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let selected = defaults.string(forKey: Self.selectedPeripheralKey)
            ?? defaults.string(forKey: Self.savedPeripheralKey)
        discovery = RemoteDiscoveryState(
            rememberedID: selected.flatMap(UUID.init(uuidString:)),
            autoReconnectEnabled: defaults.object(forKey: Self.autoReconnectKey) == nil
                ? true : defaults.bool(forKey: Self.autoReconnectKey))
        super.init()
    }

    /// Explicitly reconnect the saved selection, or show candidates on first use.
    func start() { beginDiscovery(reconnectRemembered: true) }

    /// An explicit scan never auto-selects even a previously used remote.
    func discover() { beginDiscovery(reconnectRemembered: false) }

    private func beginDiscovery(reconnectRemembered: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.beginDiscovery(reconnectRemembered: reconnectRemembered)
            }
            return
        }
        guard retiringPeripheral == nil else {
            onStatus?("正在结束上一次连接，请稍后重试")
            return
        }
        guard peripheral == nil else { return }
        stopScanning()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectPolicy.suspend()
        isReconnectAttempt = false
        catalog.clear()
        candidates.removeAll()
        targetRemoteID = reconnectRemembered ? discovery.rememberedID : nil
        connectionRequested = targetRemoteID != nil
        scanRequested = true
        discovery.connectingID = targetRemoteID
        publishDiscovery()
        onStatus?("等待蓝牙就绪…")
        if let central {
            handleCentralState(central)
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func stopDiscovery() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopDiscovery() }
            return
        }
        guard peripheral == nil else { return }
        stopScanning()
        scanRequested = false
        connectionRequested = false
        targetRemoteID = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectPolicy.suspend()
        isReconnectAttempt = false
        discovery.connectingID = nil
        publishDiscovery()
        onStatus?("搜索已停止；可以选择已发现的遥控器连接")
    }

    func selectRemote(_ id: UUID) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.selectRemote(id) }
            return
        }
        guard peripheral == nil, retiringPeripheral == nil,
              let central, central.state == .poweredOn, let candidate = candidates[id] else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectPolicy.suspend()
        isReconnectAttempt = false
        discovery.rememberedID = id
        defaults.set(id.uuidString, forKey: Self.selectedPeripheralKey)
        targetRemoteID = id
        connectionRequested = true
        connect(candidate, using: central)
    }

    func setAutoReconnect(_ enabled: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setAutoReconnect(enabled) }
            return
        }
        discovery.autoReconnectEnabled = enabled
        defaults.set(enabled, forKey: Self.autoReconnectKey)
        if !enabled {
            reconnectPolicy.suspend()
            if reconnectTimer != nil || isReconnectAttempt {
                resetConnection(status: "已关闭自动重连；点击连接可重试", cancel: true)
            }
        } else if ready {
            reconnectPolicy.verifiedConnection()
        }
        publishDiscovery()
    }

    func forgetRemote() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.forgetRemote() }
            return
        }
        guard peripheral == nil, retiringPeripheral == nil else { return }
        stopDiscovery()
        discovery.rememberedID = nil
        defaults.removeObject(forKey: Self.selectedPeripheralKey)
        defaults.removeObject(forKey: Self.savedPeripheralKey)
        catalog.clear()
        candidates.removeAll()
        publishDiscovery()
        onStatus?("已忘记所选遥控器；重新搜索后选择一只")
    }

    private func publishDiscovery() {
        discovery.devices = catalog.devices
        onDiscovery?(discovery)
    }

    private func record(_ candidate: CBPeripheral, source: RemoteDiscoverySource,
                        name: String? = nil, rssi: Int? = nil, audioService: Bool = false) {
        candidates[candidate.identifier] = candidate
        catalog.observe(NearbyRemote(id: candidate.identifier,
            name: name ?? candidate.name ?? "未命名语音遥控器", source: source,
            rssi: rssi, advertisesAudioService: audioService))
        publishDiscovery()
    }

    private func stopScanning() {
        central?.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        discovery.isScanning = false
    }

    func disconnect() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.disconnect() }
            return
        }
        if opening || streaming { sendCloseCommand() }
        resetConnection(status: "已断开；点击连接可重新连接", cancel: true)
    }

    func stopCapture() {
        stopCapture(reason: "已手动停止")
    }

    private func stopCapture(reason: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopCapture(reason: reason) }
            return
        }
        guard ready, opening || streaming, manualStopGate.allowsStart else { return }
        pendingStopReason = reason
        reconnectPolicy.suspend()
        manualStopGate.requestStop()
        guard sendCloseCommand() else { return }
        finishAudio()
        onStatus?("\(reason)；正在关闭遥控器采音…")
        // An AUDIO_STOP after MIC_CLOSE cannot prove physical key release.
        // Its acknowledgement must disconnect, never permit another search.
        captureTimer = timer(after: 3) { [weak self] in
            guard let self, self.manualStopGate.awaitingStop else { return }
            self.fail("\(reason)；遥控器未确认停止采音，请重新连接")
        }
    }

    private func findRemote(using central: CBCentralManager) {
        guard scanRequested, peripheral == nil, central.state == .poweredOn else { return }
        stopScanning()
        for candidate in central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]) {
            record(candidate, source: .systemConnected, audioService: true)
        }
        for candidate in central.retrieveConnectedPeripherals(withServices: [Self.hidUUID])
            where RemoteDiscoveryCatalog.isCandidate(name: candidate.name, advertisesAudioService: false,
                                                      advertisesHIDService: true) {
            record(candidate, source: .systemConnected)
        }
        if let identifier = discovery.rememberedID {
            for candidate in central.retrievePeripherals(withIdentifiers: [identifier]) {
                // A cached CBPeripheral is not proof that the remote is nearby or connected.
                record(candidate, source: .remembered)
            }
        }
        if connectionRequested, let targetRemoteID, let candidate = candidates[targetRemoteID] {
            connect(candidate, using: central)
            return
        }
        // Xiaomi firmware may omit ATVV from advertisements. Filter remote-specific
        // names after scanning, but never connect the first arbitrary matching device.
        onStatus?(connectionRequested ? "正在寻找已选遥控器；请按键唤醒…" : "正在搜索附近遥控器；发现后请选择一只连接")
        discovery.isScanning = true
        publishDiscovery()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer = timer(after: 20) { [weak self] in
            guard let self else { return }
            let retry = self.isReconnectAttempt
            self.stopScanning()
            self.scanRequested = false
            self.connectionRequested = false
            self.discovery.connectingID = nil
            self.publishDiscovery()
            self.onStatus?(self.catalog.devices.isEmpty
                ? "未发现遥控器；请唤醒或进入配对模式后重新搜索"
                : "搜索完成；请选择遥控器。仅有历史记录的设备可能尚未唤醒")
            if retry { self.scheduleReconnect(wasCapturing: false) }
        }
    }

    private func connect(_ candidate: CBPeripheral, using central: CBCentralManager) {
        guard connectionRequested, candidate.identifier == targetRemoteID,
              peripheral == nil, retiringPeripheral == nil else { return }
        stopScanning()
        scanRequested = false
        peripheral = candidate
        candidate.delegate = self
        discovery.connectingID = candidate.identifier
        publishDiscovery()
        onStatus?("正在连接 \(candidate.name ?? "语音遥控器")…")
        connectionTimer?.invalidate()
        connectionTimer = timer(after: 15) { [weak self] in
            guard let self else { return }
            let retry = self.isReconnectAttempt
            self.resetConnection(status: "遥控器连接超时；请唤醒设备，必要时在系统蓝牙设置中配对",
                                 cancel: true, retainReconnectPolicy: retry)
            if retry { self.scheduleReconnect(wasCapturing: false) }
        }
        central.connect(candidate, options: nil)
    }

    private func scheduleReconnect(wasCapturing: Bool) {
        guard let id = discovery.rememberedID,
              let delay = reconnectPolicy.nextDelay(enabled: discovery.autoReconnectEnabled,
                                                     wasCapturing: wasCapturing) else {
            isReconnectAttempt = false
            discovery.connectingID = nil
            publishDiscovery()
            return
        }
        isReconnectAttempt = true
        discovery.connectingID = id
        publishDiscovery()
        onStatus?("连接中断；\(Int(delay)) 秒后重连已选遥控器。点击断开可取消")
        reconnectTimer = timer(after: delay) { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            guard self.retiringPeripheral == nil, self.peripheral == nil,
                  let central = self.central, central.state == .poweredOn else {
                self.resetConnection(status: "暂时无法重连；请检查蓝牙状态后点击连接", cancel: true)
                return
            }
            self.targetRemoteID = id
            self.connectionRequested = true
            self.scanRequested = true
            self.findRemote(using: central)
        }
    }

    private func armConnectionTimeout(_ interval: TimeInterval, message: String) {
        connectionTimer?.invalidate()
        connectionTimer = timer(after: interval) { [weak self] in self?.fail(message) }
    }

    private func timer(after interval: TimeInterval, action: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @discardableResult
    private func writeCommand(_ data: Data) -> Bool {
        guard let peripheral, peripheral.state == .connected,
              let characteristic = commandCharacteristic else {
            fail("ATVV 命令通道不可用，请重新连接")
            return false
        }
        let type: CBCharacteristicWriteType
        if characteristic.properties.contains(.write) {
            type = .withResponse
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            guard peripheral.canSendWriteWithoutResponse else {
                fail("蓝牙发送队列繁忙，ATVV 命令未发送；请重新连接")
                return false
            }
            type = .withoutResponse
        } else {
            fail("ATVV 命令通道不支持写入，请重新连接")
            return false
        }
        peripheral.writeValue(data, for: characteristic, type: type)
        return true
    }

    @discardableResult
    private func sendCloseCommand() -> Bool {
        do {
            return writeCommand(try protocolHandler.micCloseCommand(streamID: streamID))
        } catch {
            fail("无法关闭遥控器采音：\(error.localizedDescription)")
            return false
        }
    }

    private func requestCapabilitiesIfSubscribed() {
        guard !capabilitiesRequested,
              commandCharacteristic != nil, audioCharacteristic != nil, controlCharacteristic != nil,
              audioNotificationConfirmed, controlNotificationConfirmed else { return }
        capabilitiesRequested = true
        onStatus?("已连接，正在协商遥控器音频能力…")
        writeCommand(protocolHandler.getCapabilitiesCommand)
    }

    private func acceptCapabilities(_ capabilities: ATVVCapabilities) {
        guard capabilitiesRequested, !ready else { return }
        do {
            try protocolHandler.acceptCapabilities(capabilities)
            guard let codec = protocolHandler.codec else {
                fail("遥控器未提供可用的音频编码")
                return
            }
            connectionTimer?.invalidate()
            connectionTimer = nil
            ready = true
            isReconnectAttempt = false
            reconnectPolicy.verifiedConnection()
            discovery.connectingID = nil
            discovery.connectedID = peripheral?.identifier
            publishDiscovery()
            if let peripheral {
                defaults.set(peripheral.identifier.uuidString,
                             forKey: Self.savedPeripheralKey)
            }
            onStatus?("遥控器已就绪（\(codec.sampleRate) Hz）；按住语音键说话")
            onReady?(true)
        } catch {
            fail("ATVV 能力协商失败：\(error.localizedDescription)")
        }
    }

    private func handleControl(_ data: Data) {
        switch protocolHandler.parseControl(data) {
        case .capabilities(let capabilities):
            acceptCapabilities(capabilities)
        case .startSearch:
            guard ready, !opening, !streaming, manualStopGate.allowsStart else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastStartSearchAt >= 0.5 else { return }
            lastStartSearchAt = now
            protocolHandler.prepareForAudioStream()
            opening = true
            streamID = 0
            do {
                guard writeCommand(try protocolHandler.micOpenCommand()) else { return }
                onStatus?("正在打开遥控器麦克风…")
                captureTimer?.invalidate()
                captureTimer = timer(after: 5) { [weak self] in
                    guard let self, self.opening else { return }
                    self.fail("遥控器未开始传送音频，请重新连接")
                }
            } catch {
                fail("无法打开遥控器麦克风：\(error.localizedDescription)")
            }
        case .audioStart(_, let codec, let identifier):
            guard ready else { return }
            if !manualStopGate.allowsStart {
                streamID = identifier
                sendCloseCommand()
                return
            }
            if streaming {
                // Repeated AUDIO_START for the same stream must not reset ADPCM.
                if streamID == identifier, protocolHandler.codec == codec { return }
                fail("收到冲突的遥控器音频流，请重新连接")
                return
            }
            // Some Xiaomi firmware sends AUDIO_START without START_SEARCH.
            // The core preserves a fresh AUDIO_SYNC, or resets stale state.
            protocolHandler.beginAudioStream(codec: codec)
            streamID = identifier
            opening = false
            streaming = true
            captureTimer?.invalidate()
            captureTimer = nil
            streamStartedAt = ProcessInfo.processInfo.systemUptime
            lastAudioAt = streamStartedAt
            lastLevelAt = streamStartedAt
            levelSumSquares = 0
            levelSampleCount = 0
            startStreamTimers()
            onStatus?("正在接收遥控器音频；松开语音键结束")
            onStream?(true, codec.sampleRate)
        case .audioStop:
            if manualStopGate.receiveAudioStop() {
                let reason = pendingStopReason ?? "采音已停止"
                resetConnection(status: "\(reason)；重新连接后继续", cancel: true)
                return
            }
            finishAudio()
            if ready { onStatus?("采音结束；遥控器仍已就绪") }
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            guard ready, manualStopGate.allowsStart else { return }
            protocolHandler.applyAudioSync(codec: codec, sequence: sequence,
                                           predictor: predictor, stepIndex: stepIndex)
        case .micOpenError(let code):
            fail(String(format: "遥控器拒绝采音（0x%04X），请重新连接", code))
        case .unknown:
            if data.first == 0x0B {
                // A malformed capability response cannot produce a ready state.
                if let capabilities = ATVVProtocol.parseCapabilities(data) {
                    acceptCapabilities(capabilities)
                } else {
                    fail("遥控器返回了无法识别的 ATVV 能力")
                }
            }
        }
    }

    private func startStreamTimers() {
        keepAliveTimer?.invalidate()
        let keepAlive = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, self.ready, self.streaming, self.manualStopGate.allowsStart else { return }
            do {
                self.writeCommand(try self.protocolHandler.keepAliveCommand(streamID: self.streamID))
            } catch {
                self.fail("遥控器采音保活失败：\(error.localizedDescription)")
            }
        }
        keepAliveTimer = keepAlive
        RunLoop.main.add(keepAlive, forMode: .common)
        streamWatchdog?.invalidate()
        let watchdog = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.streaming else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.streamStartedAt >= 90 {
                self.stopCapture(reason: "采音达到 90 秒时限，已停止")
            } else if now - self.lastAudioAt >= 8 {
                self.stopCapture(reason: "连续 8 秒未收到有效音频，采音已停止")
            }
        }
        streamWatchdog = watchdog
        RunLoop.main.add(watchdog, forMode: .common)
    }

    private func handleAudio(_ data: Data) {
        guard ready, streaming, manualStopGate.allowsStart,
              let frame = protocolHandler.decodeAudio(data), !frame.samples.isEmpty,
              let codec = protocolHandler.codec else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastAudioAt = now
        onSamples?(frame.samples, codec.sampleRate)
        // A sample consumer may synchronously stop or disconnect the transport.
        guard ready, streaming, manualStopGate.allowsStart else { return }
        for sample in frame.samples {
            let value = Double(sample)
            levelSumSquares += value * value
        }
        levelSampleCount += frame.samples.count
        if now - lastLevelAt >= 0.15 {
            let rms = sqrt(levelSumSquares / Double(max(1, levelSampleCount)))
            let db = rms > 0 ? 20 * log10(rms / 32768) : -60
            onLevel?(max(-60, min(0, db)))
            levelSumSquares = 0
            levelSampleCount = 0
            lastLevelAt = now
        }
    }

    private func finishAudio() {
        let rate = protocolHandler.codec?.sampleRate ?? 16_000
        opening = false
        streaming = false
        protocolHandler.endAudioStream()
        captureTimer?.invalidate()
        captureTimer = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        streamWatchdog?.invalidate()
        streamWatchdog = nil
        levelSumSquares = 0
        levelSampleCount = 0
        onStream?(false, rate)
        onLevel?(-60)
    }

    private func fail(_ message: String) {
        resetConnection(status: message, cancel: true)
    }

    private func resetConnection(status: String, cancel: Bool, retainReconnectPolicy: Bool = false) {
        connectionRequested = false
        scanRequested = false
        targetRemoteID = nil
        isReconnectAttempt = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        if !retainReconnectPolicy { reconnectPolicy.suspend() }
        stopScanning()
        discovery.connectingID = nil
        discovery.connectedID = nil
        publishDiscovery()
        connectionTimer?.invalidate()
        connectionTimer = nil
        ready = false
        manualStopGate = ManualStopGate()
        pendingStopReason = nil
        finishAudio()
        let previous = peripheral
        peripheral = nil
        previous?.delegate = nil
        commandCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
        audioNotificationConfirmed = false
        controlNotificationConfirmed = false
        capabilitiesRequested = false
        streamID = 0
        lastStartSearchAt = -.infinity
        protocolHandler = ATVVProtocol()
        if cancel, let previous, previous.state != .disconnected {
            retiringPeripheral = previous
            central?.cancelPeripheralConnection(previous)
        }
        onReady?(false)
        onStatus?(status)
    }

    private func handleCentralState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if scanRequested, peripheral == nil, !central.isScanning {
                findRemote(using: central)
            }
        case .unknown:
            if peripheral != nil || ready || streaming || opening || discovery.isScanning || reconnectTimer != nil {
                resetConnection(status: "蓝牙状态未知；请检查系统设置后重新连接", cancel: true)
            } else {
                onStatus?("等待蓝牙状态…")
            }
        case .poweredOff:
            resetConnection(status: "蓝牙未开启；开启后点击连接", cancel: true)
        case .unauthorized:
            resetConnection(status: "蓝牙访问未授权；请在系统隐私设置中授权", cancel: true)
        case .unsupported:
            resetConnection(status: "这台 Mac 不支持所需的蓝牙连接", cancel: true)
        case .resetting:
            resetConnection(status: "蓝牙正在重置；恢复后点击连接", cancel: true)
        @unknown default:
            resetConnection(status: "蓝牙状态未知；请检查系统设置后重新连接", cancel: true)
        }
    }
}

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState(central)
    }

    func centralManager(_ central: CBCentralManager, didDiscover candidate: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard discovery.isScanning, peripheral == nil else { return }
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? candidate.name
        let audioService = advertised.contains(Self.serviceUUID)
        guard RemoteDiscoveryCatalog.isCandidate(name: name, advertisesAudioService: audioService,
                                                  advertisesHIDService: advertised.contains(Self.hidUUID)) else { return }
        record(candidate, source: .advertisement, name: name, rssi: RSSI.intValue, audioService: audioService)
        if connectionRequested, candidate.identifier == targetRemoteID {
            connect(candidate, using: central)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect candidate: CBPeripheral) {
        guard connectionRequested, candidate === peripheral else {
            central.cancelPeripheralConnection(candidate)
            return
        }
        onStatus?("已连接，正在检查 ATVV 音频服务…")
        armConnectionTimeout(10, message: "ATVV 服务握手超时；请唤醒遥控器后重新连接")
        candidate.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect candidate: CBPeripheral,
                        error: Error?) {
        if candidate === retiringPeripheral {
            retiringPeripheral = nil
            return
        }
        guard candidate === peripheral else { return }
        let retry = isReconnectAttempt
        resetConnection(status: "连接失败：\(error?.localizedDescription ?? "请唤醒遥控器，必要时到系统蓝牙设置中配对")",
                        cancel: false, retainReconnectPolicy: retry)
        if retry { scheduleReconnect(wasCapturing: false) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral candidate: CBPeripheral,
                        error: Error?) {
        if candidate === retiringPeripheral {
            retiringPeripheral = nil
            return
        }
        guard candidate === peripheral else { return }
        let wasCapturing = opening || streaming || !manualStopGate.allowsStart
        let retry = (ready || isReconnectAttempt) && !wasCapturing
        resetConnection(status: wasCapturing
                        ? "收音时连接中断；请松开语音键，再点击连接"
                        : "遥控器已断开；点击连接可重新连接",
                        cancel: false, retainReconnectPolicy: retry)
        if retry { scheduleReconnect(wasCapturing: wasCapturing) }
    }
}

extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ candidate: CBPeripheral, didDiscoverServices error: Error?) {
        guard candidate === peripheral else { return }
        if let error { return fail("ATVV 服务发现失败：\(error.localizedDescription)") }
        guard let service = candidate.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            return fail("该设备没有 ATVV 音频服务；请确认是小米语音遥控器")
        }
        candidate.discoverCharacteristics([Self.commandUUID, Self.audioUUID, Self.controlUUID],
                                          for: service)
    }

    func peripheral(_ candidate: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard candidate === peripheral, service.uuid == Self.serviceUUID else { return }
        if let error { return fail("ATVV 特征发现失败：\(error.localizedDescription)") }
        let characteristics = service.characteristics ?? []
        commandCharacteristic = characteristics.first { $0.uuid == Self.commandUUID }
        audioCharacteristic = characteristics.first { $0.uuid == Self.audioUUID }
        controlCharacteristic = characteristics.first { $0.uuid == Self.controlUUID }
        guard let command = commandCharacteristic,
              command.properties.contains(.write) || command.properties.contains(.writeWithoutResponse),
              let audio = audioCharacteristic,
              audio.properties.contains(.notify) || audio.properties.contains(.indicate),
              let control = controlCharacteristic,
              control.properties.contains(.notify) || control.properties.contains(.indicate) else {
            return fail("ATVV 缺少所需的命令、音频或控制通道")
        }
        onStatus?("已连接，正在订阅遥控器音频与控制…")
        candidate.setNotifyValue(true, for: audio)
        candidate.setNotifyValue(true, for: control)
    }

    func peripheral(_ candidate: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard candidate === peripheral,
              characteristic === audioCharacteristic || characteristic === controlCharacteristic else { return }
        if let error { return fail("ATVV 通知订阅失败：\(error.localizedDescription)") }
        guard characteristic.isNotifying else { return fail("ATVV 音频通知被关闭，请重新连接") }
        if characteristic === audioCharacteristic { audioNotificationConfirmed = true }
        if characteristic === controlCharacteristic { controlNotificationConfirmed = true }
        requestCapabilitiesIfSubscribed()
    }

    func peripheral(_ candidate: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard candidate === peripheral, characteristic === commandCharacteristic else { return }
        if let error { fail("ATVV 命令发送失败：\(error.localizedDescription)") }
    }

    func peripheral(_ candidate: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard candidate === peripheral else { return }
        guard characteristic === controlCharacteristic || characteristic === audioCharacteristic else { return }
        if let error { return fail("ATVV 数据接收失败：\(error.localizedDescription)") }
        guard let data = characteristic.value else { return }
        if characteristic === controlCharacteristic { handleControl(data) }
        if characteristic === audioCharacteristic { handleAudio(data) }
    }
}
