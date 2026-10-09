import Foundation
import VibeRemoteCore

/// Narrow interfaces keep model-level capture/recognition policy testable without
/// connecting hardware, requesting permission or sending audio to a recognizer.
protocol BluetoothServicing: AnyObject {
    var discovery: RemoteDiscoveryState { get }
    var onDiscovery: ((RemoteDiscoveryState) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    var onReady: ((Bool) -> Void)? { get set }
    var onStream: ((Bool, Int) -> Void)? { get set }
    var onSamples: (([Int16], Int) -> Void)? { get set }
    var onLevel: ((Double) -> Void)? { get set }
    func start()
    func discover()
    func stopDiscovery()
    func selectRemote(_ id: UUID)
    func setAutoReconnect(_ enabled: Bool)
    func forgetRemote()
    func disconnect()
    func stopCapture()
}

protocol SpeechServicing: AnyObject {
    var isAuthorized: Bool { get }
    var onText: ((String, Bool) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func start(localeIdentifier: String, allowServerRecognition: Bool) throws
    func append(samples: [Int16], sampleRate: Int)
    func finish()
    func cancel()
}

extension BluetoothService: BluetoothServicing {}
extension SpeechService: SpeechServicing {}
