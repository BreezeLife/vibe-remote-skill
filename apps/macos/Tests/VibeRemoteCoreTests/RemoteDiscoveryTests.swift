import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class RemoteDiscoveryTests: XCTestCase {
    func testCandidatesRequireAudioServiceOrRemoteSpecificNames() {
        XCTAssertTrue(RemoteDiscoveryCatalog.isCandidate(name: nil, advertisesAudioService: true))
        for name in ["小米蓝牙遥控器 Pro 2", "Xiaomi Remote", "XIAOMI BLE REMOTE 2", "Mi RC", "Mi RC 2", "Mi-RC"] {
            XCTAssertTrue(RemoteDiscoveryCatalog.isCandidate(name: name, advertisesAudioService: false), name)
        }
        for name: String? in [nil, "", "Xiaomi 15 Ultra", "小米手机", "Xiaomi Watch", "Keyboard", "RC Boat", "Mi Rice Cooker"] {
            XCTAssertFalse(RemoteDiscoveryCatalog.isCandidate(name: name, advertisesAudioService: false), name ?? "nil")
            XCTAssertFalse(RemoteDiscoveryCatalog.isCandidate(name: name, advertisesAudioService: false, advertisesHIDService: true), name ?? "nil")
        }
    }

    func testDuplicateDiscoveryUpgradesRememberedToFreshObservation() throws {
        let id = UUID()
        var catalog = RemoteDiscoveryCatalog()
        catalog.observe(NearbyRemote(id: id, name: "Remembered remote", source: .remembered))
        catalog.observe(NearbyRemote(id: id, name: "System remote", source: .systemConnected))
        XCTAssertEqual(catalog.devices.count, 1)
        XCTAssertEqual(catalog.devices[0].source, .systemConnected)
        catalog.observe(NearbyRemote(id: id, name: "Xiaomi Remote 2", source: .advertisement,
                                     rssi: -45, advertisesAudioService: true))
        catalog.observe(NearbyRemote(id: id, name: "Stale name", source: .remembered))
        catalog.observe(NearbyRemote(id: id, name: "System cached name", source: .systemConnected))
        let found = try XCTUnwrap(catalog.devices.first)
        XCTAssertEqual(found.id, id)
        XCTAssertEqual(found.name, "Xiaomi Remote 2")
        XCTAssertEqual(found.source, .advertisement)
        XCTAssertEqual(found.rssi, -45)
        XCTAssertTrue(found.advertisesAudioService)
        XCTAssertEqual(catalog.devices.count, 1)
    }

    func testNewAdvertisementReplacesOldSignalAndSanitizesUnavailableRSSI() {
        let id = UUID()
        var catalog = RemoteDiscoveryCatalog()
        catalog.observe(NearbyRemote(id: id, name: "Xiaomi Remote", source: .advertisement, rssi: -40))
        catalog.observe(NearbyRemote(id: id, name: "Xiaomi Remote 2", source: .advertisement, rssi: -60))
        XCTAssertEqual(catalog.devices[0].rssi, -60)
        XCTAssertEqual(catalog.devices[0].name, "Xiaomi Remote 2")
        catalog.observe(NearbyRemote(id: id, name: "Xiaomi Remote 2", source: .advertisement, rssi: 127))
        XCTAssertNil(catalog.devices[0].rssi)
    }

    func testSortingIsStableAcrossObservationOrderAndClearDropsOldCandidates() {
        let remotes = [
            NearbyRemote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "A", source: .remembered),
            NearbyRemote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "B", source: .advertisement, rssi: -40),
            NearbyRemote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "A", source: .advertisement, rssi: -60),
            NearbyRemote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "A", source: .advertisement, rssi: -60)
        ]
        var first = RemoteDiscoveryCatalog(), second = RemoteDiscoveryCatalog()
        for remote in remotes { first.observe(remote) }
        for remote in remotes.reversed() { second.observe(remote) }
        XCTAssertEqual(first.devices, second.devices)
        XCTAssertEqual(first.devices.map(\.id), [remotes[1].id, remotes[3].id, remotes[2].id, remotes[0].id])
        first.clear()
        XCTAssertTrue(first.devices.isEmpty)
        XCTAssertEqual(second.devices.count, 4)
    }

    func testRememberedCandidateDoesNotBecomeConnectedOrScanning() {
        let id = UUID()
        let state = RemoteDiscoveryState(devices: [NearbyRemote(id: id, name: "Remembered", source: .remembered)],
                                         rememberedID: id)
        XCTAssertEqual(state.rememberedID, id)
        XCTAssertNil(state.connectingID)
        XCTAssertNil(state.connectedID)
        XCTAssertFalse(state.isScanning)
        XCTAssertTrue(state.autoReconnectEnabled)
        XCTAssertTrue(RemoteDiscoveryState().devices.isEmpty)
    }

    func testReconnectRequiresVerifiedConnectionAndStopsAfterThreeAttempts() {
        var policy = RemoteReconnectPolicy()
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: false))
        policy.verifiedConnection()
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 2)
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 5)
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 10)
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: false))
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: false))
        policy.verifiedConnection()
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 2)
    }

    func testManualStopAndCaptureLossSuspendUntilAnotherVerifiedConnection() {
        var policy = RemoteReconnectPolicy()
        policy.verifiedConnection()
        policy.suspend()
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: false))
        policy.verifiedConnection()
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: true))
        XCTAssertNil(policy.nextDelay(enabled: true, wasCapturing: false))
        policy.verifiedConnection()
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 2)
    }

    func testDisabledAutoReconnectDoesNotConsumeTheRetryBudget() {
        var policy = RemoteReconnectPolicy()
        policy.verifiedConnection()
        XCTAssertNil(policy.nextDelay(enabled: false, wasCapturing: false))
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 2)
        XCTAssertNil(policy.nextDelay(enabled: false, wasCapturing: false))
        XCTAssertEqual(policy.nextDelay(enabled: true, wasCapturing: false), 5)
    }
}
