import Foundation
import VibeRemoteCore

var assertions = 0
var failures = 0
func check(_ condition: Bool, _ message: String) {
    assertions += 1
    if !condition { failures += 1; print("FAIL: \(message)") }
}

final class FakeHIDDriver: HIDRemoteDriver {
    var onInterfacesChanged: (([HIDRemoteInterface]) -> Void)?
    var onValue: ((HIDRemoteValue) -> Void)?
    var onInvalidated: ((String) -> Void)?
    var access: HIDInputPermission = .granted
    var permissionChecks = 0
    var permissionRequests = 0
    var discoveries = 0
    var discoveryStops = 0
    var interfaces: [HIDRemoteInterface] = []
    var opens: [(String, Bool)] = []
    var closes: [String] = []
    var openIDs = Set<String>()
    var failOpen: String?
    var duringOpen: (() -> Void)?
    func checkPermission() -> HIDInputPermission { permissionChecks += 1; return access }
    func requestPermission() { permissionRequests += 1 }
    func startDiscovery() throws { discoveries += 1; onInterfacesChanged?(interfaces) }
    func stopDiscovery() { discoveryStops += 1 }
    func open(interfaceID: String, exclusive: Bool) -> Bool {
        opens.append((interfaceID, exclusive))
        if interfaceID == failOpen { return false }
        openIDs.insert(interfaceID)
        let action = duringOpen
        duringOpen = nil
        action?()
        return true
    }
    func close(interfaceID: String) { closes.append(interfaceID); openIDs.remove(interfaceID) }
    func replace(_ next: [HIDRemoteInterface]) { interfaces = next; onInterfacesChanged?(next) }
    func emit(_ id: String = "a", cookie: Int = 1, usage: Int = 40, down: Bool,
              reportID: Int = 1, at: TimeInterval = 1, hold: Bool = true) {
        onValue?(HIDRemoteValue(interfaceID: id, cookie: cookie, usagePage: 7,
                               usage: usage, reportID: reportID, isDown: down,
                               canReportRelease: hold, timestamp: at))
    }
}

func interface(_ id: String, physical: String? = "remote-1", descriptor: Data = Data([1, 2, 3]),
               vendor: Int = 0x2717, product: Int = 0x32B8) -> HIDRemoteInterface {
    HIDRemoteInterface(id: id, physicalID: physical, name: "Remote", vendorID: vendor,
                       productID: product, descriptor: descriptor)
}

func setup(_ interfaces: [HIDRemoteInterface] = [interface("a"), interface("b")])
    -> (HIDRemoteInputService, FakeHIDDriver, String) {
    let driver = FakeHIDDriver()
    driver.interfaces = interfaces
    let service = HIDRemoteInputService(driver: driver, now: { 0 })
    service.discover()
    return (service, driver, service.devices.first?.id ?? "missing")
}

do {
    let driver = FakeHIDDriver()
    let service = HIDRemoteInputService(driver: driver)
    check(driver.permissionChecks == 0 && driver.permissionRequests == 0 && driver.discoveries == 0,
          "initialization performs no permission check/request or discovery")
    check(driver.opens.isEmpty && service.permission == .unknown, "initialization opens nothing")
    driver.access = .notDetermined
    service.discover()
    check(driver.discoveries == 0 && driver.permissionRequests == 0,
          "ungranted discovery never triggers implicit permission prompt")
    service.requestPermission()
    check(driver.permissionRequests == 1, "explicit permission button alone requests access")
    check(driver.opens.isEmpty, "permission request does not open devices")
}

do {
    let (service, driver, selected) = setup([interface("a"), interface("b"),
                                           interface("other", physical: "remote-2"),
                                           interface("keyboard", physical: "keyboard", vendor: 1)])
    check(service.devices.count == 2, "candidate VID/PID filters ordinary keyboard")
    check(service.devices.map(\.interfaceCount).sorted() == [1, 2],
          "identical product devices group only by physical identity")
    check(driver.opens.isEmpty, "discovery does not open any candidate")
    var received: [(HIDBinding, Bool, TimeInterval)] = []
    service.onInput = { received.append(($0, $1, $2)) }
    service.startObservation(deviceID: selected)
    check(service.isObserving && !service.isExclusive, "observation is never exclusive")
    check(driver.opens.allSatisfy { !$0.1 }, "observation uses nonexclusive opens")
    check(service.status.contains("原始") && service.status.contains("系统"),
          "observation explains native system behavior can leak")
    driver.emit("other", down: true)
    driver.emit("keyboard", down: true)
    check(received.isEmpty, "unselected/ordinary keyboard inputs are ignored")
    driver.emit(down: true)
    driver.emit(down: true, at: 1.1)
    driver.emit(down: false, at: 1.8)
    driver.emit(down: false, at: 1.9)
    check(received.count == 2 && received.map { $0.1 } == [true, false],
          "only real initial down and matched release are emitted")
    check(received.last?.0.supportsHold == true, "paired binary release establishes hold capability")
    check(received.first?.0.supportsHold == false, "initial down cannot claim observed hold support")
    check(received.first?.0.usagePage == 7 && received.first?.0.usage == 40 && received.first?.0.reportID == 1,
          "bindings use observed usage page/usage/report ID without keycode guesses")
    check(received.first?.0.descriptorHash == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
          "descriptor fingerprint is SHA256 of actual descriptor bytes")
    service.pause()
    check(driver.openIDs.isEmpty, "pause closes all selected interfaces")
}

do {
    let (service, driver, selected) = setup()
    var resets = 0
    service.onReset = { resets += 1 }
    driver.failOpen = "b"
    service.seize(deviceID: selected)
    check(!service.isExclusive && !service.isObserving && driver.openIDs.isEmpty,
          "partial exclusive failure releases every opened interface and disables mappings")
    check(driver.closes.contains("a"), "partial failure closes successfully opened sibling")
    check(resets > 0, "partial failure tells coordinator to discard pending gestures")
    driver.failOpen = nil
    service.seize(deviceID: selected)
    check(service.isExclusive && driver.openIDs == Set(["a", "b"]),
          "all selected physical interfaces must open before exclusive state is published")
    check(driver.opens.allSatisfy { $0.1 }, "failed seizure never falls back to observation")
    driver.access = .denied
    service.refreshPermission()
    check(!service.isExclusive && driver.openIDs.isEmpty && service.selectedID == nil,
          "revocation immediately releases interfaces and selection")
}

do {
    let (service, driver, selected) = setup()
    var received = 0
    var resets = 0
    service.onInput = { _, _, _ in received += 1 }
    service.onReset = { resets += 1 }
    service.seize(deviceID: selected)
    driver.emit(down: true)
    let before = resets
    driver.replace([interface("a"), interface("b"), interface("new")])
    check(!service.isExclusive && driver.openIDs.isEmpty && resets > before,
          "new sibling interface invalidates complete-device seizure")
    driver.emit(down: false)
    check(received == 1, "reset never synthesizes release or completes pending click")
    service.seize(deviceID: selected)
    driver.replace([interface("a"), interface("new")])
    check(!service.isExclusive && driver.openIDs.isEmpty, "removal of one sibling releases whole group")
    service.seize(deviceID: selected)
    driver.onInvalidated?("系统休眠")
    check(!service.isExclusive && driver.openIDs.isEmpty && service.selectedID == nil,
          "sleep releases physical device and clears session selection")
}

do {
    let (service, driver, selected) = setup([interface("a", physical: nil), interface("b", physical: nil)])
    check(service.devices.count == 2 && service.devices.allSatisfy { !$0.canSeize },
          "missing physical identity never groups identical candidate interfaces")
    service.seize(deviceID: selected)
    check(driver.opens.isEmpty && !service.isExclusive, "unproven physical identity blocks seizure")
    service.startObservation(deviceID: selected)
    check(service.isObserving && driver.openIDs.count == 1, "unproven interface allows explicit observation only")
}

do {
    let (service, driver, selected) = setup([interface("a"), interface("b", descriptor: Data([4, 5]))])
    var received: [(HIDBinding, Bool)] = []
    service.onInput = { binding, down, _ in received.append((binding, down)) }
    service.seize(deviceID: selected)
    driver.emit(cookie: 5, usage: 40, down: true)
    driver.emit("b", cookie: 5, usage: 41, down: true)
    driver.emit("b", cookie: 5, usage: 41, down: false)
    driver.emit(cookie: 5, usage: 40, down: false)
    check(received.map { $0.0.usage } == [40, 41, 41, 40],
          "equal cookies across interfaces cannot release or suppress another key")
    check(received.count >= 2 && received[0].0.descriptorHash != received[1].0.descriptorHash,
          "each interface contributes its own report descriptor")
    received = []
    driver.emit(down: true, hold: false)
    check(received.count == 1 && received.first?.0.supportsHold == false,
          "pulse without release never invents an up or enables hold")
    service.pause()
    check(received.count == 1, "pause does not turn stuck/pulse down into an action")
}

do {
    let (service, driver, selected) = setup()
    var edges: [Bool] = []
    service.onInput = { _, down, _ in edges.append(down) }
    service.seize(deviceID: selected)
    driver.emit("a", down: true)
    driver.emit("b", down: true)
    driver.emit("a", down: false)
    check(edges == [true], "same canonical binding on sibling interface stays held until all real ups")
    driver.emit("b", down: false)
    check(edges == [true, false], "overlapping sibling reports generate one logical edge pair")
    driver.access = .denied
    driver.emit(down: true)
    check(edges == [true, false] && !service.isExclusive, "each raw event rechecks permission before dispatch")
}

do {
    let (service, driver, selected) = setup()
    driver.duringOpen = { driver.replace([interface("a"), interface("b"), interface("new")]) }
    service.seize(deviceID: selected)
    check(!service.isExclusive && driver.openIDs.isEmpty,
          "topology mutation during open cannot leave partial or falsely exclusive capture")
}

do {
    let (service, driver, selected) = setup([interface("a", descriptor: Data())])
    service.seize(deviceID: selected)
    check(!service.isExclusive && driver.opens.isEmpty, "missing report descriptor blocks seizure/calibration")
}

do {
    let driver = FakeHIDDriver()
    driver.interfaces = [interface("a")]
    var time: TimeInterval = 10
    let service = HIDRemoteInputService(driver: driver, now: { time })
    service.discover()
    let selected = service.devices.first?.id ?? "missing"
    var edges: [Bool] = []
    service.onInput = { _, down, _ in edges.append(down) }
    service.seize(deviceID: selected)
    driver.emit(down: true, at: 9)
    driver.emit(down: false, at: 9.5)
    check(edges.isEmpty, "queued input from before successful open cannot create a gesture")
    driver.emit(down: true, at: 12)
    driver.emit(down: false, at: 11)
    check(edges == [true], "out-of-order up cannot prematurely end a held key")
    driver.emit(down: false, at: 13)
    check(edges == [true, false], "ordered real release ends held key")
    time = 20
    service.seize(deviceID: selected)
    driver.emit(down: true, at: 14)
    check(edges == [true, false], "restart rejects queued events from prior capture")
}

do {
    let (service, driver, selected) = setup()
    service.seize(deviceID: selected)
    driver.replace([interface("a"), interface("b"), interface("unrelated", physical: "remote-2")])
    check(service.isExclusive && driver.openIDs == Set(["a", "b"]),
          "new unrelated candidate does not enter selected device capture")
    driver.replace([interface("a", descriptor: Data([9])), interface("b")])
    check(!service.isExclusive && driver.openIDs.isEmpty, "descriptor change invalidates current calibration session")
}

do {
    let driver = FakeHIDDriver()
    driver.interfaces = [interface("a")]
    var service: HIDRemoteInputService? = HIDRemoteInputService(driver: driver, now: { 0 })
    service?.discover()
    service?.seize(deviceID: service?.devices.first?.id ?? "missing")
    check(driver.openIDs == Set(["a"]), "cleanup scenario acquires selected interface")
    service = nil
    check(driver.openIDs.isEmpty && driver.discoveryStops == 1, "service destruction releases inputs and discovery")
}

print("HID input: \(assertions) assertions, \(failures) failures (fake driver; physical acceptance pending)")
exit(failures == 0 ? 0 : 1)
