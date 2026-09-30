# Voice providers

Read the user's installed provider settings before editing anything. A physical microphone
key is a capture gesture; the bridge translates that into the provider's actual shortcut.
Do not equate input-method dictation with a ChatGPT voice conversation.

## Doubao preset

With SayAll on macOS:

1. Pair the Xiaomi remote and verify the bridge actually receives its audio.
2. Select the bridge's MiRemoteV 2ch virtual input in the bridge and Doubao if present.
   Do not create or assume a device that is missing.
3. Verify Doubao's local voice shortcut is hold Fn.
4. Turn OFF SayAll's “语音键模拟 Fn 点按” for the hold/release profile.
5. Focus the bound draft input before capture. Hold the microphone button while speaking.
6. Release: end capture, drain queued audio, then release Fn. Leave the result for review.
7. Press OK only after the target and draft are confirmed.

If the installed Doubao version uses another shortcut, adapt to its observed settings.
Never switch the global input source or capture a user's existing draft without authorization.

## Typeless preset

For the SayAll Fn toggle integration documented by its author:

- Verify the actual Typeless shortcut; it may have been changed by the user.
- Turn ON “语音键模拟 Fn 点按” for the paired-tap profile.
- Physical microphone hold: start capture and emit the first Fn tap.
- Physical release: end capture, drain audio, then emit the second Fn tap.
- Do not emit a second start tap through another mapper.
- Review the resulting draft; release is not send.

The same physical hold/release has different provider key lifecycles. Switching providers
must also change the bridge preset; changing this skill's JSON alone does not change a bridge.

MiCoding documents another Typeless integration using F20. Treat it as a separate profile
with a locally verified shortcut. Its documented audio implementation currently needs
calibration; do not promise that its microphone path supplies decoded remote audio.

## Other providers

Add a voice_profiles entry and select it with voice_provider:

- behavior: hold_key — hold the configured key at start, release after audio drains.
- behavior: paired_taps — tap the configured key at start and again after audio drains.
- key: the exact locally verified shortcut name.

A key string is descriptive; this skill does not inject it. Test the bridge's ability to
emit that shortcut before recommending it. A provider that needs unsupported gestures
requires a companion adapter.

## Verify audio separately

Use an observed audio-recording interface (for example QuickTime) to check the remote
input before testing text recognition. Compare remote input to the Mac microphone so
success cannot be attributed to the wrong device. Test short Chinese and English phrases,
technical terms, cancellation, disconnect/reconnect, and return from preview.

If available, retain the original audio/input settings before changing them. Stop or cancel
dictation through the bridge's actual cancellation action; if cancellation is unsupported,
end capture, review the draft, and remove only the newly dictated segment with consent.
Do not replace the entire existing composer text.

Primary references, checked 2026-09-30:

- [SayAll / remote-mic-app](https://github.com/HD838A/remote-mic-app)
- [MiCoding](https://github.com/zhangtuansia/MiCoding)
- [MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice)

These tools evolve. Re-read their current README before installation or bridge-specific changes.
