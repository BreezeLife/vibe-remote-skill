# Vibe Remote native app — 2026-10-04

0.2 扩展已按 [可视化按键与编程工具设计](superpowers/specs/2026-10-05-visual-controls-design.md) 实现；以下保留 0.1 音频/草稿架构背景。当前使用与能力限制见 [原生上手指南](NATIVE-SETUP.md)。

The user has explicitly requested our own macOS application, referencing MiRemote's
approach without installing or using its application. This supersedes the earlier
skill-only / third-party-bridge plan.

## First independently usable milestone

Build a macOS 13+ Swift application that receives Xiaomi Bluetooth Remote 2 Pro ATVV
audio directly, decodes it to PCM, transcribes it into an editable in-memory draft,
and lets the user copy that draft explicitly. A status window and menu-bar entry
show Bluetooth readiness, capture state, signal level and actionable errors.
Speech release finishes recognition; it never injects Enter into another application.

Use Apple Speech, with on-device recognition required by default. If the selected
locale/device lacks local support, explain that limitation. An explicit, initially
disabled option permits Apple's speech service; no silent cloud fallback is allowed.
Audio and transcripts are not saved in logs or project files.

Three options were considered: direct PCM-to-Speech (selected for this first
milestone), an independently developed HAL input device for Doubao/Typeless (next
integration milestone), or a third-party app/driver (excluded by the user). Apple
Speech does not expose a virtual microphone to Doubao. This first milestone must
be labelled accordingly rather than implying complete provider compatibility.

## Components and boundaries

- `apps/macos/Sources/VibeRemoteCore`: platform-independent ATVV/IMA ADPCM and
  draft lifecycle. Tests verify packet parsing, session isolation and draft retention.
- `apps/macos/Sources/VibeRemote`: CoreBluetooth transport, Apple Speech adapter,
  observable app state, SwiftUI window and menu-bar entry.
- `apps/macos/Packaging` and `scripts/build_macos_app.sh`: reproducible local
  `.app` bundle, usage descriptions, ad-hoc signature and bundled license notices.
- Existing Python skill: unchanged semantic planner/tmux functionality, retained
  for later native task adapters. It does not automatically become an executor.

Only request Bluetooth when the user connects, and Speech authorization when
the user enables recognition. CoreBluetooth receives the remote audio directly;
no Mac microphone capture, privileged HAL install or accessibility control is
needed for the first milestone. Connecting a device is distinct from negotiating
ATVV readiness. Saved identity never proves a current connection.

Handshake waits for audio and control subscriptions before requesting capabilities.
MIC_OPEN resets the decoder before AUDIO_SYNC; AUDIO_START preserves a fresh sync.
Each stream is isolated from previous predictor state. Duplicate start requests
are suppressed; disconnect, radio loss and timeout end capture. Late recognizer
callbacks cannot replace a later draft or undo a user cancellation.

New dictation appends to the current draft after finalization. During capture or
finalization, the editor and copy action are disabled. Cancelling rolls back only
the current utterance. Existing drafts survive failed starts and transport errors.
No device key other than the ATVV voice control is intercepted in this milestone;
general HID mapping and guarded app/CLI execution remain explicit next steps.

## Attribution

The protocol implementation references the MIT MiRemoteVoice bridge at revision
`2c374d9d65ed6c8b1af6a4f9aa1b6c0f8a039aaf`, including upstream MIT attributions.
No BlackHole-derived GPL driver, binary patcher, third-party app or audio recording
is bundled. Full notices ship inside the app as well as in the source tree.

## Acceptance

Automated: Swift protocol/draft tests, debug and release build, app bundle metadata
and signature verification, existing Python tests/config validation, whitespace
checks. These establish software behavior, not physical remote compatibility.

Physical: launch the built app, authorize Bluetooth/Speech, pair/wake the remote,
observe ATVV-ready state, hold voice and observe audio/transcription, release into
an unsent editable draft, copy explicitly, cancel without losing an earlier draft,
then disconnect during capture and verify capture cleanup. Verify a second hold
does not inherit the first decoder/recognition session. Report any unavailable
permission, local speech model or hardware result without claiming success.
