import Foundation

public enum ATVVError: LocalizedError, Equatable {
    case negotiationRequired
    case unsupportedCodec
    case invalidFrameSize(Int)

    public var errorDescription: String? {
        switch self {
        case .negotiationRequired:
            return "尚未完成遥控器音频协议协商。"
        case .unsupportedCodec:
            return "遥控器未提供受支持的 ADPCM 8/16 kHz 音频编码。"
        case .invalidFrameSize(let size):
            return "遥控器报告的音频帧长度无效：\(size)。"
        }
    }
}
