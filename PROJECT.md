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

Version 0.2 extends remote audio → transcription → review with visual button settings,
calibrated device-specific HID input, per-workspace in-memory drafts and guarded desktop
tool adapters. Presets identify Codex, Claude Desktop and two WorkBuddy applications;
custom .app bindings are also supported. Input learning and exclusive suppression must
be verified on the actual remote; AX focus/input/send/stop capabilities require usable
live app metadata. A preset or build does not establish physical or tool acceptance.
Version 0.2.3 matches the Pro 2 physical layout and supplies Codex, Claude and WorkBuddy
presets. Workspace actions are independent overrides; calibrated HID remains shared.
Legacy profiles retain their global actions until explicitly edited or given a preset.
Version 0.2.5 adds explicit nearby-remote selection and bounded idle reconnection. Discovery
observations and saved identifiers never establish ATVV readiness; manual/capture stops
require an explicit connection action. No audio or transcripts are persisted.
Doubao/Typeless virtual microphone remains future work.

`skills/vibe-remote` retains the original Python configuration/planner/tmux tools.
Its planner returns semantic actions and never injects GUI keys. The exact-session
tmux selector remains its only executable adapter. Installing the skill alone does
not install or start the native application.

## Product principles

The intended complete loop is: choose a workspace, hold to dictate, release into an
unsent draft, inspect the destination and text, explicitly send, then read output or
open a preview. Keep button intentions consistent across APP and CLI adapters.
Browser focus must not redefine the bound AI destination. Unknown focus/recording
state and shell prompts block automatic submission. The native app requires
explicit insertion and full-text send confirmation, plus live workspace and device checks.
Unsupported AX capabilities preserve the draft for explicit manual copying.

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
`bash scripts/test_macos_model.sh`, `bash scripts/test_macos_hid.sh`,
`bash scripts/test_macos_tools.sh`, `bash scripts/test_macos_controls.sh`,
`bash scripts/test_macos_integration.sh` and `bash scripts/build_macos_app.sh`.
Normal builds output to ~/Library/Caches/VibeRemote/Build without writing to system
application directories. `bash scripts/package_macos_app.sh` stages the app in a local
temporary directory and produces a `.pkg` plus SHA-256 file. From 0.2.2, the package uses
only the LocalSystem domain and installs to /Applications/Vibe Remote.app through the
GUI Installer or `sudo installer -pkg <package> -target /`. This follows the user's explicit
2026-10-08 requirement and supersedes the earlier ~/Applications installation policy.
The package includes no driver or privileged installer script.
Existing skill checks use Python unittest discovery
and the config validator. CI checks both native and Python paths.

Read PROJECT.md, MEMORY.md, TASKS.md and WORKLOG.md before significant changes.
TASKS.md records acceptance, MEMORY.md durable decisions, WORKLOG.md dated evidence.
