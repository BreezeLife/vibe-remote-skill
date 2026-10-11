import Foundation
#if !VIBE_STANDALONE_TESTS
import XCTest
#endif
@testable import VibeRemoteCore

final class VoiceInputConfigurationTests: XCTestCase {
    func testExternalProviderConfigurationSurvivesNativeRoundTrip() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(NativeSettings.defaults)) as? [String: Any])
        let voice: [String: Any] = ["provider": "typeless", "profiles": [
            ["provider": "typeless", "triggerMode": "manual", "shortcutModifiers": [], "shortcutNote": "先完成语音应用设置"]
        ]]
        object["voiceInput"] = voice
        let decoded = try JSONDecoder().decode(NativeSettings.self, from: JSONSerialization.data(withJSONObject: object))
        try decoded.validate()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let saved = try XCTUnwrap(encoded["voiceInput"] as? [String: Any])
        XCTAssertEqual(saved["provider"] as? String, "typeless")
        let profiles = try XCTUnwrap(saved["profiles"] as? [[String: Any]])
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?["triggerMode"] as? String, "manual")
    }

    func testLegacySettingsKeepBuiltinSpeechAndOmitProviderConfiguration() throws {
        let encoded = try JSONEncoder().encode(NativeSettings.defaults)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["voiceInput"])
        let decoded = try JSONDecoder().decode(NativeSettings.self, from: encoded)
        XCTAssertNil(decoded.voiceInput)
        XCTAssertEqual((decoded.voiceInput ?? VoiceInputConfiguration()).provider, .appleSpeech)
    }

    func testAllPresetsRequireExplicitExternalShortcutSetup() throws {
        let configuration = VoiceInputConfiguration()
        XCTAssertEqual(configuration.provider, .appleSpeech)
        XCTAssertTrue(configuration.profiles.isEmpty)
        XCTAssertEqual(VoiceInputProvider.allCases.count, 7)
        for provider in VoiceInputProvider.allCases {
            XCTAssertFalse(provider.title.isEmpty)
            XCTAssertFalse(provider.setupDescription.isEmpty)
            let profile = configuration.profile(for: provider)
            XCTAssertEqual(profile.provider, provider)
            XCTAssertEqual(profile.triggerMode, .manual)
            XCTAssertNil(profile.shortcutKeyCode)
            XCTAssertNil(profile.appPath)
            XCTAssertNil(profile.bundleIdentifier)
            XCTAssertNil(profile.outputDeviceUID)
            XCTAssertFalse(profile.hasSupportedShortcut)
            if provider.isExternal { try profile.validate() }
        }
    }

    func testProfilesRemainIndependentWhenSwitchingProvider() throws {
        var configuration = VoiceInputConfiguration(provider: .typeless)
        let typeless = VoiceInputProfile(provider: .typeless, appPath: "/Applications/Typeless.app",
                                        bundleIdentifier: "com.example.typeless", outputDeviceUID: "synthetic-loopback",
                                        triggerMode: .toggle, shortcutKeyCode: 90)
        let doubao = VoiceInputProfile(provider: .doubaoIME, shortcutNote: "使用应用内的快捷键")
        configuration.setProfile(typeless)
        configuration.setProfile(doubao)
        configuration.provider = .doubaoIME
        try configuration.validate()
        XCTAssertEqual(configuration.profile(for: .typeless), typeless)
        XCTAssertEqual(configuration.profile(for: .doubaoIME), doubao)
        var changed = typeless
        changed.outputDeviceUID = "synthetic-second-device"
        configuration.setProfile(changed)
        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertEqual(configuration.provider, .doubaoIME)
        XCTAssertEqual(configuration.profile(for: .typeless), changed)
        XCTAssertEqual(configuration.profile(for: .doubaoIME), doubao)
    }

    func testMissingAppAndAudioDeviceAllowManualPartialConfiguration() throws {
        for provider in VoiceInputProvider.allCases.filter(\.isExternal) {
            let config = VoiceInputConfiguration(provider: provider, profiles: [VoiceInputProfile(provider: provider)])
            var settings = NativeSettings.defaults
            settings.voiceInput = config
            try settings.validate()
            XCTAssertEqual(try JSONDecoder().decode(NativeSettings.self, from: JSONEncoder().encode(settings)), settings)
        }
    }

    func testProfilesRejectDuplicateAndBuiltinEntries() throws {
        let profile = VoiceInputProfile(provider: .typeless)
        XCTAssertThrowsError(try VoiceInputConfiguration(profiles: [profile, profile]).validate())
        XCTAssertThrowsError(try VoiceInputConfiguration(profiles: [.init(provider: .appleSpeech)]).validate())
        XCTAssertThrowsError(try VoiceInputConfiguration(profiles: Array(repeating: profile, count: 7)).validate())
        var config = VoiceInputConfiguration(profiles: [profile])
        config.setProfile(.init(provider: .appleSpeech))
        XCTAssertEqual(config.profiles, [profile])
        var settings = NativeSettings.defaults
        settings.voiceInput = VoiceInputConfiguration(profiles: [profile, profile])
        XCTAssertThrowsError(try settings.validate())
    }

    func testVoiceTriggersRejectSendStopTypingAndIncompleteChords() throws {
        for key: UInt16 in [0, 8, 36, 48, 49, 53, 63, 76, 123, 126] {
            let profile = VoiceInputProfile(provider: .typeless, triggerMode: .toggle, shortcutKeyCode: key)
            XCTAssertFalse(profile.hasSupportedShortcut)
            XCTAssertThrowsError(try profile.validate())
        }
        for mode in [VoiceTriggerMode.hold, .toggle] {
            XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, triggerMode: mode).validate())
        }
        XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, shortcutModifiers: [.command]).validate())
        XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, shortcutKeyCode: 49,
                                                  shortcutModifiers: [.option, .option]).validate())
        XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, shortcutKeyCode: 90,
                                                  shortcutModifiers: [.command]).validate())
        // Manual mode does not make dangerous stored keycodes acceptable.
        XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, shortcutKeyCode: 36).validate())
    }

    func testVoiceTriggersAcceptFunctionKeysAndModifierSpace() throws {
        for key in VoiceInputProfile.functionKeyCodes {
            for mode in [VoiceTriggerMode.manual, .hold, .toggle] {
                let profile = VoiceInputProfile(provider: .typeless, triggerMode: mode, shortcutKeyCode: key)
                XCTAssertTrue(profile.hasSupportedShortcut)
                try profile.validate()
            }
        }
        for modifiers: [KeyModifier] in [[.option], [.command, .shift], [.control, .option, .shift]] {
            let profile = VoiceInputProfile(provider: .superwhisper, triggerMode: .toggle,
                                            shortcutKeyCode: 49, shortcutModifiers: modifiers)
            XCTAssertTrue(profile.hasSupportedShortcut)
            try profile.validate()
        }
    }

    func testExternalAppPathsIdentifiersAndMetadataAreBounded() throws {
        for path in ["~/Applications/Voice.app", "/Applications/../Voice.app", "/tmp/./Voice.app", "/tmp//Voice.app",
                     "/tmp/Voice.sh", "https://host/Voice.app", "/Applications/.app", "/tmp/Voice\n.app",
                     "/" + String(repeating: "x", count: 4096) + ".app"] {
            XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, appPath: path).validate())
        }
        for path in ["/Applications/Typeless.app", "/Library/Input Methods/DoubaoIme.app", "/Users/example/Applications/Voice.app"] {
            try VoiceInputProfile(provider: .custom, appPath: path).validate()
        }
        for identifier in ["", "app", "com.example.app\n", "com.example/Voice", String(repeating: "x", count: 256) + ".app"] {
            XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, bundleIdentifier: identifier).validate())
        }
        for uid in ["", "  ", "virtual\nmic", String(repeating: "x", count: 1025)] {
            XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, outputDeviceUID: uid).validate())
        }
        for note in ["line\nline", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try VoiceInputProfile(provider: .custom, shortcutNote: note).validate())
        }
    }

    func testStrictProviderDecodeRejectsRuntimeAndPrivateFields() throws {
        for field in ["recording", "verified", "ready", "transcript", "audio", "command", "script"] {
            let top = Data("{\"provider\":\"typeless\",\"profiles\":[],\"\(field)\":null}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(VoiceInputConfiguration.self, from: top))
            let nested = Data("{\"provider\":\"typeless\",\"\(field)\":null}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(VoiceInputProfile.self, from: nested))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(VoiceInputConfiguration.self,
                                                       from: Data(#"{"provider":"unknownTool"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(VoiceInputProfile.self,
                                                       from: Data(#"{"provider":"typeless","triggerMode":"shell"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(VoiceInputProfile.self,
                                                       from: Data(#"{"provider":"typeless","shortcutKeyCode":65536}"#.utf8)))
    }
}
