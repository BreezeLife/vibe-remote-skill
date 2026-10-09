import Foundation

public enum RemoteDiscoverySource: Equatable {
    case advertisement, systemConnected, remembered

    fileprivate var priority: Int {
        switch self {
        case .advertisement: return 2
        case .systemConnected: return 1
        case .remembered: return 0
        }
    }
}

/// A discovery observation is a candidate, never proof of an ATVV handshake.
public struct NearbyRemote: Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var source: RemoteDiscoverySource
    public var rssi: Int?
    public var advertisesAudioService: Bool

    public init(id: UUID, name: String, source: RemoteDiscoverySource, rssi: Int? = nil,
                advertisesAudioService: Bool = false) {
        self.id = id; self.name = name; self.source = source
        self.rssi = rssi == 127 ? nil : rssi
        self.advertisesAudioService = advertisesAudioService
    }
}

public struct RemoteDiscoveryState: Equatable {
    public var devices: [NearbyRemote]
    public var isScanning: Bool
    public var connectingID: UUID?
    public var connectedID: UUID?
    public var rememberedID: UUID?
    public var autoReconnectEnabled: Bool

    public init(devices: [NearbyRemote] = [], isScanning: Bool = false, connectingID: UUID? = nil,
                connectedID: UUID? = nil, rememberedID: UUID? = nil, autoReconnectEnabled: Bool = true) {
        self.devices = devices; self.isScanning = isScanning; self.connectingID = connectingID
        self.connectedID = connectedID; self.rememberedID = rememberedID; self.autoReconnectEnabled = autoReconnectEnabled
    }
}

public struct RemoteDiscoveryCatalog {
    private var observations: [UUID: NearbyRemote] = [:]
    public init() {}
    public var devices: [NearbyRemote] {
        observations.values.sorted { lhs, rhs in
            if lhs.rssi != rhs.rssi {
                if let left = lhs.rssi, let right = rhs.rssi { return left > right }
                return lhs.rssi != nil
            }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
    public mutating func clear() { observations.removeAll() }
    public mutating func observe(_ remote: NearbyRemote) {
        var incoming = remote
        if incoming.rssi == 127 { incoming.rssi = nil }
        if let previous = observations[remote.id] {
            var merged = incoming.source.priority >= previous.source.priority ? incoming : previous
            merged.advertisesAudioService = previous.advertisesAudioService || incoming.advertisesAudioService
            observations[remote.id] = merged
        } else {
            observations[remote.id] = incoming
        }
    }
    public static func isCandidate(name: String?, advertisesAudioService: Bool, advertisesHIDService: Bool = false) -> Bool {
        if advertisesAudioService { return true }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        // A generic Xiaomi name or HID service also identifies phones, watches,
        // keyboards and other devices. Require the remote identity in its name.
        return (name.contains("xiaomi") && name.contains("remote")) ||
               (name.contains("小米") && name.contains("遥控器")) ||
               name.range(of: "^mi[\\s_-]*rc(?:[\\s_-]|[0-9]|$)", options: .regularExpression) != nil
    }
}

public struct RemoteReconnectPolicy {
    private var armed = false
    private var attempt = 0
    private let delays: [TimeInterval] = [2, 5, 10]
    public init() {}
    public mutating func verifiedConnection() { armed = true; attempt = 0 }
    public mutating func suspend() { armed = false; attempt = 0 }
    public mutating func nextDelay(enabled: Bool, wasCapturing: Bool) -> TimeInterval? {
        if wasCapturing { suspend(); return nil }
        guard enabled, armed, attempt < delays.count else { return nil }
        let delay = delays[attempt]
        attempt += 1
        return delay
    }
}
