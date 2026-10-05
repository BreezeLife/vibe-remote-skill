import AppKit
import Combine
import CryptoKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import VibeRemoteCore

enum HIDInputPermission: String {
    case unknown, notDetermined, granted, denied
}

struct HIDRemoteDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let interfaceCount: Int
    let canSeize: Bool
}

/// IDs and cookies are scoped to this driver instance; none are configuration.
struct HIDRemoteInterface: Equatable {
    let id: String
    let physicalID: String?
    let name: String
    let vendorID: Int
    let productID: Int
    let descriptor: Data
}

struct HIDRemoteValue {
    let interfaceID: String
    let cookie: Int
    let usagePage: Int
    let usage: Int
    let reportID: Int
    let isDown: Bool
    let canReportRelease: Bool
    let timestamp: TimeInterval
}

protocol HIDRemoteDriver: AnyObject {
    var onInterfacesChanged: (([HIDRemoteInterface]) -> Void)? { get set }
    var onValue: ((HIDRemoteValue) -> Void)? { get set }
    var onInvalidated: ((String) -> Void)? { get set }
    func checkPermission() -> HIDInputPermission
    func requestPermission()
    func startDiscovery() throws
    func stopDiscovery()
    func open(interfaceID: String, exclusive: Bool) -> Bool
    func close(interfaceID: String)
}

/// Lifecycle and all callbacks are main-thread confined. Initialization is inert.
final class HIDRemoteInputService: ObservableObject {
    @Published private(set) var permission: HIDInputPermission = .unknown
    @Published private(set) var status = "按键输入尚未启用"
    @Published private(set) var devices: [HIDRemoteDevice] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var isExclusive = false
    @Published private(set) var isObserving = false
    var onInput: ((HIDBinding, Bool, TimeInterval) -> Void)?
    var onReset: (() -> Void)?
    private let driver: HIDRemoteDriver
    private let now: () -> TimeInterval
    private var interfaces: [String: HIDRemoteInterface] = [:]
    private var hashes: [String: String] = [:]
    private var opened = Set<String>()
    private var epoch = 0
    private var activeSince: TimeInterval = 0
    private var discovering = false
    private struct Source: Hashable {
        let interfaceID: String
        let cookie: Int
        let reportID: Int
        let usagePage: Int
        let usage: Int
    }
    private struct Press {
        let binding: HIDBinding
        let canReportRelease: Bool
        let timestamp: TimeInterval
    }
    private var pressed: [Source: Press] = [:]

    init(driver: HIDRemoteDriver = IOKitRemoteDriver(),
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.driver = driver
        self.now = now
        driver.onInterfacesChanged = { [weak self] in self?.updateInterfaces($0) }
        driver.onValue = { [weak self] in self?.receive($0) }
        driver.onInvalidated = { [weak self] reason in
            self?.pause()
            self?.status = reason + "；按键已释放，请重新发现并选择设备"
        }
    }

    func refreshPermission() {
        precondition(Thread.isMainThread)
        permission = driver.checkPermission()
        if permission != .granted && (discovering || selectedID != nil) {
            pause()
            status = "输入监控未授权；按键已释放"
        }
    }

    func requestPermission() {
        precondition(Thread.isMainThread)
        driver.requestPermission()
        refreshPermission()
        status = permission == .granted ? "输入监控已授权；请发现并选择设备" : "请在系统设置中允许输入监控，再刷新权限"
    }

    func discover() {
        precondition(Thread.isMainThread)
        refreshPermission()
        guard permission == .granted else {
            status = "请先点击授权输入监控，再发现设备"
            return
        }
        guard !discovering else { return }
        do {
            discovering = true
            try driver.startDiscovery()
            status = devices.isEmpty ? "正在发现小米遥控器 HID 接口" : "请选择本次连接的遥控器"
        } catch {
            pause()
            status = "HID 发现失败；设备未接管"
        }
    }

    func startObservation(deviceID: String) { start(deviceID: deviceID, exclusive: false) }
    func seize(deviceID: String) { start(deviceID: deviceID, exclusive: true) }

    func pause() {
        precondition(Thread.isMainThread)
        reset()
        discovering = false
        driver.stopDiscovery()
        interfaces.removeAll()
        hashes.removeAll()
        devices.removeAll()
        status = "按键已暂停，设备已释放"
    }

    private func start(deviceID: String, exclusive: Bool) {
        precondition(Thread.isMainThread)
        reset()
        refreshPermission()
        guard permission == .granted, discovering,
              let device = devices.first(where: { $0.id == deviceID }) else {
            status = "请先授权、发现并选择本次连接的设备"
            return
        }
        let members = group(deviceID).sorted { $0.id < $1.id }
        guard !members.isEmpty, members.allSatisfy({ !$0.descriptor.isEmpty }),
              !exclusive || device.canSeize else {
            status = "无法确认设备所有接口或报告描述符；独占映射不可用"
            return
        }
        selectedID = deviceID
        let attempt = epoch
        for member in members {
            // DeviceOpen may request TCC implicitly: never call it without grant.
            guard driver.checkPermission() == .granted else {
                reset()
                permission = driver.checkPermission()
                status = "输入监控授权已变化；设备已释放"
                return
            }
            let success = driver.open(interfaceID: member.id, exclusive: exclusive)
            guard success, attempt == epoch else {
                if success { driver.close(interfaceID: member.id) }
                reset()
                status = exclusive ? "未能独占所有接口；映射保持关闭，设备已释放" : "观察失败；设备已释放"
                return
            }
            opened.insert(member.id)
        }
        // Protect against reentrant topology/permission changes during an open.
        guard members == group(deviceID).sorted(by: { $0.id < $1.id }),
              driver.checkPermission() == .granted else {
            reset()
            status = "设备或授权已变化；请重新选择"
            return
        }
        activeSince = now()
        isExclusive = exclusive
        isObserving = !exclusive
        status = exclusive ? "已独占全部已识别接口；请先完成本次原始按键抑制及语音共存测试" : "仅观察；原始按键仍可能触发系统或当前应用"
    }

    private func group(_ id: String) -> [HIDRemoteInterface] {
        interfaces.values.filter { ($0.physicalID ?? $0.id) == id }
    }

    private func updateInterfaces(_ discovered: [HIDRemoteInterface]) {
        precondition(Thread.isMainThread)
        guard discovering else { return }
        let previousGroup = selectedID.map { group($0).sorted { $0.id < $1.id } }
        interfaces = Dictionary(uniqueKeysWithValues: discovered.filter {
            $0.vendorID == 0x2717 && $0.productID == 0x32B8
        }.map { ($0.id, $0) })
        hashes = interfaces.mapValues { SHA256.hash(data: $0.descriptor).map { String(format: "%02x", $0) }.joined() }
        let groups = Dictionary(grouping: interfaces.values) { $0.physicalID ?? $0.id }
        devices = groups.map { id, members in
            HIDRemoteDevice(id: id, name: members.first?.name ?? "小米遥控器",
                            interfaceCount: members.count,
                            canSeize: members.allSatisfy { $0.physicalID != nil && !$0.descriptor.isEmpty })
        }.sorted { $0.id < $1.id }
        if let id = selectedID, previousGroup != group(id).sorted(by: { $0.id < $1.id }) {
            reset()
            status = "设备断连或 HID 接口发生变化；映射已停止，请重新选择"
        }
    }

    private func receive(_ value: HIDRemoteValue) {
        precondition(Thread.isMainThread)
        guard isExclusive || isObserving else { return }
        refreshPermission()
        guard permission == .granted, isExclusive || isObserving,
              opened.contains(value.interfaceID), let hash = hashes[value.interfaceID],
              value.timestamp.isFinite, value.timestamp >= activeSince,
              (1...65_535).contains(value.usagePage), (1...65_535).contains(value.usage),
              (0...255).contains(value.reportID) else { return }
        let source = Source(interfaceID: value.interfaceID, cookie: value.cookie,
                            reportID: value.reportID, usagePage: value.usagePage, usage: value.usage)
        let binding = HIDBinding(usagePage: value.usagePage, usage: value.usage,
                                 reportID: value.reportID, descriptorHash: hash, supportsHold: false)
        if value.isDown {
            guard pressed[source] == nil else { return }
            let alreadyHeld = pressed.values.contains { $0.binding == binding }
            pressed[source] = Press(binding: binding, canReportRelease: value.canReportRelease,
                                    timestamp: value.timestamp)
            if !alreadyHeld { onInput?(binding, true, value.timestamp) }
        } else {
            guard let previous = pressed[source], value.timestamp >= previous.timestamp else { return }
            pressed.removeValue(forKey: source)
            guard !pressed.values.contains(where: { $0.binding == previous.binding }) else { return }
            let released = HIDBinding(usagePage: previous.binding.usagePage, usage: previous.binding.usage,
                                      reportID: previous.binding.reportID, descriptorHash: previous.binding.descriptorHash,
                                      supportsHold: previous.canReportRelease && value.canReportRelease)
            onInput?(released, false, value.timestamp)
        }
    }

    private func reset() {
        epoch += 1
        isExclusive = false
        isObserving = false
        selectedID = nil
        pressed.removeAll()
        let previous = opened
        opened.removeAll()
        for id in previous { driver.close(interfaceID: id) }
        onReset?()
    }

    deinit {
        for id in opened { driver.close(interfaceID: id) }
        driver.stopDiscovery()
    }
}

/// Thin IOKit boundary. No CGEventTap, global key interception or ATVV operations.
/// IOHIDManagerOptionIndependentDevices prevents discovery from opening devices.
final class IOKitRemoteDriver: HIDRemoteDriver {
    var onInterfacesChanged: (([HIDRemoteInterface]) -> Void)?
    var onValue: ((HIDRemoteValue) -> Void)?
    var onInvalidated: ((String) -> Void)?
    private var manager: IOHIDManager?
    private var hidDevices: [String: IOHIDDevice] = [:]
    private var interfaces: [String: HIDRemoteInterface] = [:]
    // This identifier can contain a transport address. It never leaves memory,
    // appears in UI/logs, or becomes the saved descriptor/key binding.
    private var physicalIDs: [String: String] = [:]
    private var openOptions: [String: IOOptionBits] = [:]
    private var sleepObserver: NSObjectProtocol?

    func checkPermission() -> HIDInputPermission {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }

    func requestPermission() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    func startDiscovery() throws {
        precondition(Thread.isMainThread)
        guard manager == nil else { return }
        guard checkPermission() == .granted else { throw HIDDriverError.unavailable }
        let created = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        manager = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(created, [kIOHIDVendorIDKey: 0x2717, kIOHIDProductIDKey: 0x32B8] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(created, { context, result, _, device in
            guard let context else { return }
            let owner = Unmanaged<IOKitRemoteDriver>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else {
                owner.onInvalidated?("HID 接口发现失效")
                return
            }
            owner.add(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(created, { context, _, _, device in
            guard let context else { return }
            Unmanaged<IOKitRemoteDriver>.fromOpaque(context).takeUnretainedValue().remove(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // IndependentDevices explicitly stops this manager open propagating.
        guard IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            stopDiscovery()
            throw HIDDriverError.unavailable
        }
        if let existing = IOHIDManagerCopyDevices(created) as? Set<IOHIDDevice> {
            for device in existing { add(device) }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onInvalidated?("系统休眠") }
    }

    func stopDiscovery() {
        for id in Array(openOptions.keys) { close(interfaceID: id) }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        hidDevices.removeAll()
        interfaces.removeAll()
        physicalIDs.removeAll()
    }

    func open(interfaceID: String, exclusive: Bool) -> Bool {
        precondition(Thread.isMainThread)
        guard checkPermission() == .granted, openOptions[interfaceID] == nil,
              let device = hidDevices[interfaceID] else { return false }
        let options = IOOptionBits(exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
        guard IOHIDDeviceOpen(device, options) == kIOReturnSuccess else { return false }
        openOptions[interfaceID] = options
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context else { return }
            let owner = Unmanaged<IOKitRemoteDriver>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else {
                owner.onInvalidated?("HID 输入已失效")
                return
            }
            owner.receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return true
    }

    func close(interfaceID: String) {
        guard let options = openOptions.removeValue(forKey: interfaceID),
              let device = hidDevices[interfaceID] else { return }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, options)
    }

    private func add(_ device: IOHIDDevice) {
        guard manager != nil, !hidDevices.values.contains(device) else { return }
        let id = UUID().uuidString
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        let physical = IOHIDDeviceGetProperty(device, kIOHIDPhysicalDeviceUniqueIDKey as CFString) as? String
        var physicalID: String?
        if let transport, !transport.isEmpty, let physical, !physical.isEmpty {
            // Length prefix prevents separator-containing identities colliding.
            let key = "\(transport.utf8.count):\(transport)\(physical)"
            if physicalIDs[key] == nil { physicalIDs[key] = UUID().uuidString }
            physicalID = physicalIDs[key]
        }
        let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data ?? Data()
        hidDevices[id] = device
        interfaces[id] = HIDRemoteInterface(
            id: id, physicalID: physicalID,
            name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "小米遥控器",
            vendorID: (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0,
            productID: (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0,
            descriptor: descriptor)
        onInterfacesChanged?(Array(interfaces.values))
    }

    private func remove(_ device: IOHIDDevice) {
        guard let id = hidDevices.first(where: { $0.value == device })?.key else { return }
        // Keep the object until all callbacks have released its siblings.
        close(interfaceID: id)
        interfaces.removeValue(forKey: id)
        onInterfacesChanged?(Array(interfaces.values))
        hidDevices.removeValue(forKey: id)
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let id = hidDevices.first(where: { $0.value == device })?.key,
              openOptions[id] != nil else { return }
        let type = IOHIDElementGetType(element)
        // Only binary input elements have an unambiguous observed up/down.
        // Analog axes/vendor payloads are not guessed into button presses.
        guard type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_ScanCodes ||
                type == kIOHIDElementTypeInput_Misc else { return }
        let integer = IOHIDValueGetIntegerValue(value)
        guard IOHIDElementGetLogicalMin(element) == 0,
              IOHIDElementGetLogicalMax(element) == 1,
              integer == 0 || integer == 1 else { return }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return }
        let timestamp = Double(IOHIDValueGetTimeStamp(value)) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        onValue?(HIDRemoteValue(interfaceID: id, cookie: Int(IOHIDElementGetCookie(element)),
                               usagePage: Int(IOHIDElementGetUsagePage(element)),
                               usage: Int(IOHIDElementGetUsage(element)),
                               reportID: Int(IOHIDElementGetReportID(element)), isDown: integer != 0,
                               canReportRelease: !IOHIDElementIsRelative(element), timestamp: timestamp))
    }

    deinit { stopDiscovery() }
}

private enum HIDDriverError: Error { case unavailable }
