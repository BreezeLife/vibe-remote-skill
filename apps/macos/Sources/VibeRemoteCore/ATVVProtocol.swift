// Adapted from MiRemoteVoice and fanxeon/mi-ao under the MIT License.
// Copyright (c) 2026 Sima Qingfeng
// Copyright (c) 2026 FanXeon@Poemcoder with Codex
// Protocol reference: Google Voice over BLE 1.0 and b0o/ATVVoice.
// See ../../THIRD_PARTY_NOTICES.md for attribution and license terms.
import Foundation

public enum ATVVVersion: Equatable, Sendable, CustomStringConvertible {
    case v04
    case v10

    public var description: String { self == .v04 ? "0.4" : "1.0" }
}

public enum ATVVCodec: UInt8, Equatable, Sendable, CustomStringConvertible {
    case adpcm8k = 0x01
    case adpcm16k = 0x02

    public var sampleRate: Int { self == .adpcm8k ? 8_000 : 16_000 }
    public var description: String { self == .adpcm8k ? "ADPCM 8 kHz" : "ADPCM 16 kHz" }
}

public struct ATVVCapabilities: Equatable, Sendable {
    public let version: ATVVVersion
    public let codecs: UInt8
    public let interactionModel: UInt8
    public let frameSize: Int

    public init(version: ATVVVersion, codecs: UInt8, interactionModel: UInt8, frameSize: Int) {
        self.version = version
        self.codecs = codecs
        self.interactionModel = interactionModel
        self.frameSize = frameSize
    }

    public var selectedCodec: ATVVCodec? {
        if supports(.adpcm16k) { return .adpcm16k }
        if supports(.adpcm8k) { return .adpcm8k }
        return nil
    }

    public func supports(_ codec: ATVVCodec) -> Bool { codecs & codec.rawValue != 0 }

    fileprivate var validFrameSize: Bool {
        frameSize >= (version == .v04 ? 6 : 1) && frameSize <= Int(UInt16.max)
    }
}

public enum ATVVControlEvent: Equatable, Sendable {
    case audioStop(reason: UInt8)
    case audioStart(reason: UInt8, codec: ATVVCodec, streamID: UInt8)
    case startSearch
    case audioSync(codec: ATVVCodec, sequence: UInt16, predictor: Int16, stepIndex: UInt8)
    case capabilities(ATVVCapabilities)
    case micOpenError(UInt16)
    case unknown(Data)
}

/// A stateful decoder for one connected peripheral, used on the bridge's serial queue.
public final class ATVVProtocol {
    public static let serviceUUID = "AB5E0001-5A21-4F05-BC7D-AF01F617B664"
    public static let txUUID = "AB5E0002-5A21-4F05-BC7D-AF01F617B664"
    public static let rxUUID = "AB5E0003-5A21-4F05-BC7D-AF01F617B664"
    public static let controlUUID = "AB5E0004-5A21-4F05-BC7D-AF01F617B664"

    public private(set) var capabilities: ATVVCapabilities?
    public private(set) var codec: ATVVCodec?
    private var decoder = ADPCMDecoder()
    private var v10Sequence: UInt16 = 0
    private var audioStreamActive = false
    private var hasPendingSyncBeforeStart = false

    public let getCapabilitiesCommand = Data([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03])

    public init() {}

    public func acceptCapabilities(_ capabilities: ATVVCapabilities) throws {
        guard let selected = capabilities.selectedCodec else { throw ATVVError.unsupportedCodec }
        guard capabilities.validFrameSize else { throw ATVVError.invalidFrameSize(capabilities.frameSize) }
        self.capabilities = capabilities
        self.codec = selected
        prepareForAudioStream()
    }

    public func micOpenCommand() throws -> Data {
        guard let capabilities, let codec else { throw ATVVError.negotiationRequired }
        return capabilities.version == .v04
            ? Data([0x0C, 0x00, codec.rawValue]) : Data([0x0C, 0x00])
    }

    public func micCloseCommand(streamID: UInt8) throws -> Data {
        guard let capabilities else { throw ATVVError.negotiationRequired }
        return capabilities.version == .v04 ? Data([0x0D]) : Data([0x0D, streamID])
    }

    public func keepAliveCommand(streamID: UInt8) throws -> Data {
        guard let capabilities else { throw ATVVError.negotiationRequired }
        return capabilities.version == .v04 ? try micOpenCommand() : Data([0x0E, streamID])
    }

    public func parseControl(_ data: Data) -> ATVVControlEvent {
        let bytes = [UInt8](data)
        guard let opcode = bytes.first else { return .unknown(data) }
        switch opcode {
        case 0x00:
            if capabilities?.version == .v10, bytes.count < 2 { return .unknown(data) }
            return .audioStop(reason: bytes.count > 1 ? bytes[1] : 0)
        case 0x04:
            guard let capabilities, let codec else { return .unknown(data) }
            if capabilities.version == .v04 {
                return .audioStart(reason: 0, codec: codec, streamID: 0)
            }
            guard bytes.count >= 4, let incomingCodec = ATVVCodec(rawValue: bytes[2]),
                  capabilities.supports(incomingCodec) else { return .unknown(data) }
            return .audioStart(reason: bytes[1], codec: incomingCodec, streamID: bytes[3])
        case 0x08:
            return .startSearch
        case 0x0A:
            guard let capabilities, capabilities.version == .v10, bytes.count >= 7,
                  let incomingCodec = ATVVCodec(rawValue: bytes[1]),
                  capabilities.supports(incomingCodec), bytes[6] <= 88 else { return .unknown(data) }
            return .audioSync(codec: incomingCodec, sequence: Self.uint16(bytes[2], bytes[3]),
                              predictor: Int16(bitPattern: Self.uint16(bytes[4], bytes[5])),
                              stepIndex: bytes[6])
        case 0x0B:
            guard let caps = Self.parseCapabilities(data) else { return .unknown(data) }
            return .capabilities(caps)
        case 0x0C:
            guard bytes.count >= 3 else { return .unknown(data) }
            return .micOpenError(Self.uint16(bytes[1], bytes[2]))
        default:
            return .unknown(data)
        }
    }

    public static func parseCapabilities(_ data: Data) -> ATVVCapabilities? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == 0x0B else { return nil }
        let capabilities: ATVVCapabilities
        switch uint16(bytes[1], bytes[2]) {
        case 0x0004:
            guard bytes.count >= 9 else { return nil }
            capabilities = ATVVCapabilities(version: .v04, codecs: bytes[4], interactionModel: 0,
                                            frameSize: Int(uint16(bytes[5], bytes[6])))
        case 0x0100:
            guard bytes.count >= 7 else { return nil }
            // Xiaomi firmware 2671 can swap codecs/model. Only use that layout
            // when the standard codec byte contains no supported codec.
            let swap = bytes[3] & 0x03 == 0 && bytes[4] & 0x03 != 0
            capabilities = ATVVCapabilities(version: .v10, codecs: swap ? bytes[4] : bytes[3],
                                            interactionModel: swap ? bytes[3] : bytes[4],
                                            frameSize: Int(uint16(bytes[5], bytes[6])))
        default:
            return nil
        }
        guard capabilities.selectedCodec != nil, capabilities.validFrameSize else { return nil }
        return capabilities
    }

    public func applyAudioSync(codec: ATVVCodec, sequence: UInt16, predictor: Int16, stepIndex: UInt8) {
        guard let capabilities, capabilities.version == .v10,
              capabilities.supports(codec), stepIndex <= 88 else { return }
        self.codec = codec
        v10Sequence = sequence
        decoder.reset(predictor: predictor, stepIndex: stepIndex)
        hasPendingSyncBeforeStart = !audioStreamActive
    }

    /// Reset before MIC_OPEN, so a subsequent sync may arrive on either side of START.
    public func prepareForAudioStream() {
        v10Sequence = 0
        decoder.reset(predictor: 0, stepIndex: 0)
        audioStreamActive = false
        hasPendingSyncBeforeStart = false
    }

    public func beginAudioStream(codec: ATVVCodec) {
        guard let capabilities, capabilities.supports(codec) else {
            endAudioStream()
            return
        }
        let preserveSync = hasPendingSyncBeforeStart && self.codec == codec
        self.codec = codec
        if !preserveSync {
            v10Sequence = 0
            decoder.reset(predictor: 0, stepIndex: 0)
        }
        audioStreamActive = true
        hasPendingSyncBeforeStart = false
    }

    public func endAudioStream() {
        audioStreamActive = false
        hasPendingSyncBeforeStart = false
    }

    public func decodeAudio(_ data: Data) -> (sequence: UInt16, samples: [Int16])? {
        guard audioStreamActive, let capabilities, let codec,
              capabilities.supports(codec) else { return nil }
        let bytes = [UInt8](data)
        switch capabilities.version {
        case .v04:
            guard bytes.count == capabilities.frameSize, bytes.count >= 6, bytes[5] <= 88 else { return nil }
            let sequence = Self.uint16(bytes[0], bytes[1])
            let predictor = Int16(bitPattern: Self.uint16(bytes[3], bytes[4]))
            decoder.reset(predictor: predictor, stepIndex: bytes[5])
            return (sequence, [predictor] + decoder.decode(bytes.dropFirst(6)))
        case .v10:
            // Headerless notifications can contain a shorter chunk (e.g. tail
            // audio). Do not require a header or reset the predictor per chunk.
            guard !bytes.isEmpty, bytes.count <= capabilities.frameSize else { return nil }
            let sequence = v10Sequence
            v10Sequence &+= 1
            return (sequence, decoder.decode(bytes))
        }
    }

    private static func uint16(_ high: UInt8, _ low: UInt8) -> UInt16 {
        UInt16(high) << 8 | UInt16(low)
    }
}
