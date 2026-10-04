import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class ATVVTests: XCTestCase {
    private func negotiated(_ version: ATVVVersion = .v10,
                            codecs: UInt8 = 0x03,
                            frameSize: Int = 8) throws -> ATVVProtocol {
        let handler = ATVVProtocol()
        try handler.acceptCapabilities(ATVVCapabilities(
            version: version, codecs: codecs, interactionModel: 0x03,
            frameSize: frameSize))
        return handler
    }

    func testMicrophoneCommandsRequireNegotiation() {
        let handler = ATVVProtocol()
        XCTAssertThrowsError(try handler.micOpenCommand())
        XCTAssertThrowsError(try handler.micCloseCommand(streamID: 7))
        XCTAssertThrowsError(try handler.keepAliveCommand(streamID: 7))
        handler.beginAudioStream(codec: .adpcm16k)
        XCTAssertNil(handler.decodeAudio(Data([0x12])))
    }

    func testMicrophoneCommandsRespectNegotiatedVersion() throws {
        let modern = try negotiated()
        XCTAssertEqual(modern.getCapabilitiesCommand, Data([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03]))
        XCTAssertEqual(try modern.micOpenCommand(), Data([0x0C, 0x00]))
        XCTAssertEqual(try modern.micCloseCommand(streamID: 7), Data([0x0D, 0x07]))
        XCTAssertEqual(try modern.keepAliveCommand(streamID: 7), Data([0x0E, 0x07]))
        let legacy = try negotiated(.v04)
        XCTAssertEqual(try legacy.micOpenCommand(), Data([0x0C, 0x00, 0x02]))
        XCTAssertEqual(try legacy.micCloseCommand(streamID: 7), Data([0x0D]))
        XCTAssertEqual(try legacy.keepAliveCommand(streamID: 7), Data([0x0C, 0x00, 0x02]))
    }

    func testCapabilitiesParseBothVersionsAndPrefer16k() throws {
        let legacy = try XCTUnwrap(ATVVProtocol.parseCapabilities(
            Data([0x0B, 0x00, 0x04, 0x00, 0x03, 0x00, 0x07, 0x00, 0x14])))
        XCTAssertEqual(legacy.version, .v04)
        XCTAssertEqual(legacy.frameSize, 7)
        XCTAssertEqual(legacy.selectedCodec, .adpcm16k)
        let modern = try XCTUnwrap(ATVVProtocol.parseCapabilities(
            Data([0x0B, 0x01, 0x00, 0x03, 0x03, 0x00, 0x78])))
        XCTAssertEqual(modern.version, .v10)
        XCTAssertEqual(modern.frameSize, 120)
        XCTAssertEqual(modern.interactionModel, 3)
        XCTAssertEqual(modern.selectedCodec?.sampleRate, 16_000)
    }

    func testXiaomiSwappedCapabilitiesOnlyApplyWhenStandardCodecIsInvalid() throws {
        let swapped = try XCTUnwrap(ATVVProtocol.parseCapabilities(
            Data([0x0B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x78])))
        XCTAssertEqual(swapped.codecs, 3)
        XCTAssertEqual(swapped.interactionModel, 0)
        let standard = try XCTUnwrap(ATVVProtocol.parseCapabilities(
            Data([0x0B, 0x01, 0x00, 0x01, 0x03, 0x00, 0x78])))
        XCTAssertEqual(standard.codecs, 1)
        XCTAssertEqual(standard.interactionModel, 3)
    }

    func testUnsupportedCodecsAndInvalidFrameSizesAreRejected() {
        let handler = ATVVProtocol()
        XCTAssertThrowsError(try handler.acceptCapabilities(ATVVCapabilities(
            version: .v10, codecs: 4, interactionModel: 0, frameSize: 20)))
        for (version, size) in [(ATVVVersion.v10, 0), (.v10, -1),
                                (.v10, 65_536), (.v04, 5)] {
            XCTAssertThrowsError(try handler.acceptCapabilities(ATVVCapabilities(
                version: version, codecs: 3, interactionModel: 0, frameSize: size)))
        }
        XCTAssertNil(handler.capabilities)
    }

    func testMalformedCapabilityMessagesAreIgnored() {
        for bytes: [UInt8] in [[], [0x0B], [0x0B, 0x01, 0x00],
                              [0x0B, 0x02, 0x00, 3, 3, 0, 20],
                              [0x0B, 0x01, 0x00, 4, 0, 0, 20],
                              [0x0B, 0x01, 0x00, 3, 3, 0, 0],
                              [0x0B, 0, 4, 0, 3, 0, 5, 0, 20]] {
            XCTAssertNil(ATVVProtocol.parseCapabilities(Data(bytes)), "\(bytes)")
        }
    }

    func testMalformedControlMessagesDoNotInventAudioStartOrSync() throws {
        let handler = try negotiated()
        for bytes: [UInt8] in [[], [0x04], [0x04, 3], [0x04, 3, 2],
                              [0x04, 3, 0, 1], [0x04, 3, 4, 1],
                              [0x0A], [0x0A, 2, 0, 0, 0, 0],
                              [0x0A, 4, 0, 0, 0, 0, 0],
                              [0x0A, 2, 0, 0, 0, 0, 89], [0x0C]] {
            let data = Data(bytes)
            XCTAssertEqual(handler.parseControl(data), .unknown(data), "\(bytes)")
        }
        let unnegotiated = ATVVProtocol()
        let start = Data([0x04, 3, 2, 1])
        XCTAssertEqual(unnegotiated.parseControl(start), .unknown(start))
    }

    func testControlRejectsCodecsNotAdvertisedByTheRemote() throws {
        let handler = try negotiated(codecs: 1)
        for data in [Data([0x04, 3, 2, 1]), Data([0x0A, 2, 0, 0, 0, 0, 0])] {
            XCTAssertEqual(handler.parseControl(data), .unknown(data))
        }
        handler.beginAudioStream(codec: .adpcm16k)
        XCTAssertNil(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(handler.codec, .adpcm8k)
    }

    func testControlMessagesDecodeNetworkByteOrder() throws {
        let handler = try negotiated()
        XCTAssertEqual(handler.parseControl(Data([0x04, 3, 2, 7])),
                       .audioStart(reason: 3, codec: .adpcm16k, streamID: 7))
        XCTAssertEqual(handler.parseControl(Data([0x0A, 2, 0x12, 0x34, 0xFB, 0x2E, 20])),
                       .audioSync(codec: .adpcm16k, sequence: 0x1234,
                                  predictor: -1234, stepIndex: 20))
        XCTAssertEqual(handler.parseControl(Data([0x00, 2])), .audioStop(reason: 2))
        XCTAssertEqual(handler.parseControl(Data([0x08])), .startSearch)
        XCTAssertEqual(handler.parseControl(Data([0x0C, 0x0F, 0x80])), .micOpenError(0x0F80))
        let legacy = try negotiated(.v04, codecs: 1)
        XCTAssertEqual(legacy.parseControl(Data([0x04])),
                       .audioStart(reason: 0, codec: .adpcm8k, streamID: 0))
    }

    func testADPCMDecodesTheHighNibbleFirst() {
        var decoder = ADPCMDecoder()
        decoder.reset(predictor: 0, stepIndex: 0)
        XCTAssertEqual(decoder.decode([0x12, 0x34]), [1, 4, 8, 15])
        decoder.reset(predictor: 0, stepIndex: 0)
        XCTAssertEqual(decoder.decode([0xF1]), [-11, -5])
    }

    func testADPCMUsesCanonicalStepSizesAtHighIndices() {
        var decoder = ADPCMDecoder()
        decoder.reset(predictor: 0, stepIndex: 61)
        XCTAssertEqual(decoder.decode([0x00]), [312, 596])
    }

    func testV04FramesUseTheirOwnHeaderAndDecoderState() throws {
        let handler = try negotiated(.v04, frameSize: 7)
        handler.beginAudioStream(codec: .adpcm16k)
        let first = try XCTUnwrap(handler.decodeAudio(Data([1, 2, 0, 0, 0, 0, 0x12])))
        XCTAssertEqual(first.sequence, 0x0102)
        XCTAssertEqual(first.samples, [0, 1, 4])
        let next = try XCTUnwrap(handler.decodeAudio(Data([1, 3, 0, 0, 100, 0, 0x12])))
        XCTAssertEqual(next.sequence, 0x0103)
        XCTAssertEqual(next.samples, [100, 101, 104])
        XCTAssertNil(handler.decodeAudio(Data([1, 2, 0, 0, 0, 0])))
        XCTAssertNil(handler.decodeAudio(Data([1, 2, 0, 0, 0, 89, 0x12])))
    }

    func testV10HeaderlessChunksRetainStateAndRejectInvalidPayloads() throws {
        let handler = try negotiated(frameSize: 8)
        handler.beginAudioStream(codec: .adpcm16k)
        let first = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        let next = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(first.sequence, 0)
        XCTAssertEqual(first.samples, [1, 4])
        XCTAssertEqual(next.sequence, 1)
        XCTAssertEqual(next.samples, [5, 8])
        XCTAssertNil(handler.decodeAudio(Data()))
        XCTAssertNil(handler.decodeAudio(Data(repeating: 0, count: 9)))
        handler.endAudioStream()
        XCTAssertNil(handler.decodeAudio(Data([0x12])))
    }

    func testFreshAudioSyncBeforeStartSurvivesTheStartEvent() throws {
        let handler = try negotiated()
        handler.prepareForAudioStream()
        handler.applyAudioSync(codec: .adpcm16k, sequence: 42, predictor: 1234, stepIndex: 20)
        handler.beginAudioStream(codec: .adpcm16k)
        let frame = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(frame.sequence, 42)
        XCTAssertEqual(frame.samples, [1252, 1279])
    }

    func testAudioSyncAfterStartResynchronizesAndSequenceWraps() throws {
        let handler = try negotiated()
        handler.beginAudioStream(codec: .adpcm16k)
        _ = handler.decodeAudio(Data([0x77]))
        handler.applyAudioSync(codec: .adpcm8k, sequence: 0xFFFF, predictor: -100, stepIndex: 0)
        let synced = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(handler.codec, .adpcm8k)
        XCTAssertEqual(synced.sequence, 0xFFFF)
        XCTAssertEqual(synced.samples, [-99, -96])
        XCTAssertEqual(handler.decodeAudio(Data([0x00]))?.sequence, 0)
    }

    func testSyncDuringOneStreamDoesNotLeakIntoTheNextStream() throws {
        let handler = try negotiated()
        handler.beginAudioStream(codec: .adpcm16k)
        _ = handler.decodeAudio(Data([0x77]))
        handler.applyAudioSync(codec: .adpcm16k, sequence: 70, predictor: -2000, stepIndex: 30)
        _ = handler.decodeAudio(Data([0x77]))
        handler.endAudioStream()
        handler.beginAudioStream(codec: .adpcm16k)
        let restarted = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(restarted.sequence, 0)
        XCTAssertEqual(restarted.samples, [1, 4])
    }

    func testInvalidSyncDoesNotReplaceAValidNegotiatedCodec() throws {
        let handler = try negotiated(codecs: 1)
        handler.applyAudioSync(codec: .adpcm16k, sequence: 42, predictor: 1234, stepIndex: 20)
        handler.beginAudioStream(codec: .adpcm8k)
        let frame = try XCTUnwrap(handler.decodeAudio(Data([0x12])))
        XCTAssertEqual(handler.codec, .adpcm8k)
        XCTAssertEqual(frame.sequence, 0)
        XCTAssertEqual(frame.samples, [1, 4])
    }
}
