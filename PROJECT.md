# Vibe Remote

Our own macOS application for Xiaomi Bluetooth Remote 2 Pro voice coding, with a
supporting Codex skill for workspace bindings, guarded button intentions and tmux.

The user changed direction on 2026-10-04: develop our own application, referencing
MiRemote's technical approach without installing or using its application. The
previous third-party bridge installation plan is superseded.

## Architecture and current scope

`apps/macos` is a SwiftPM project for macOS 13+. VibeRemoteCore owns ATVV packet
parsing, IMA ADPCM decoding and in-memory draft lifecycle. The native executable
uses CoreBluetooth to receive remote audio, Apple Speech to transcribe it, and
SwiftUI to show connection, signal and editable drafts. Local speech recognition
is required by default; Apple's online service requires an explicit opt-in.

The first milestone is remote audio → transcription → review → explicit copy.
It does not expose a virtual microphone to Doubao/Typeless or execute the remaining
remote button mappings. Those are subsequent integration milestones, not implied
by a successful build. No audio or transcripts are persisted by this application.

`skills/vibe-remote` retains the original Python configuration/planner/tmux tools.
Its planner returns semantic actions and never injects GUI keys. The exact-session
tmux selector remains its only executable adapter. Installing the skill alone does
not install or start the native application.

## Product principles

The intended complete loop is: choose a workspace, hold to dictate, release into an
unsent draft, inspect the destination and text, explicitly send, then read output or
open a preview. Keep button intentions consistent across APP and CLI adapters.
Browser focus must not redefine the bound AI destination. Unknown focus/recording
state and shell prompts block automatic submission. The first native milestone uses
explicit copying while these execution adapters are still absent.

Distinguish implemented behavior, installed artifacts, current connection state and
physical acceptance. A paired device or saved UUID does not prove a working audio
stream. Keep raw audio, transcripts, credentials and runtime device identifiers out
of Git. Respect third-party licenses and ship required notices with adapted code.

## Build, tests and continuity

Canonical checkout: Project-VibeRemote. The original recovery copy at
~/.codex/skill-projects/vibe-remote is retained. Public repository:
https://github.com/BreezeLife/vibe-remote-skill (MIT original code and MIT notices).

Native design and build/use steps: docs/NATIVE-DESIGN.md and docs/NATIVE-SETUP.md.
Run `bash scripts/test_macos_core.sh`, `bash scripts/test_macos_speech.sh`,
`bash scripts/test_macos_model.sh` and `bash scripts/build_macos_app.sh`.
Existing skill checks use Python unittest discovery
and the config validator. CI checks both native and Python paths.

Read PROJECT.md, MEMORY.md, TASKS.md and WORKLOG.md before significant changes.
TASKS.md records acceptance, MEMORY.md durable decisions, WORKLOG.md dated evidence.
