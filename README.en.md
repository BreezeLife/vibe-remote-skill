# Vibe Remote

[中文](README.md) · [Setup guide (中文)](docs/SETUP.md)

A self-developed macOS app for Xiaomi Bluetooth Remote 2 Pro, with a supporting
Codex skill for guarded workspace actions and terminal navigation.

## Native developer preview

The native app receives remote ATVV audio directly, transcribes it through Apple
Speech, and keeps an editable unsent draft for explicit copying. It requires macOS
13+ and Xcode Command Line Tools, with no third-party app or virtual driver.

```sh
bash scripts/test_macos_core.sh
bash scripts/build_macos_app.sh
open "build/Vibe Remote.app"
```

On-device recognition is required by default. An explicit opt-in allows Apple's
speech service when local recognition is unavailable. The app does not persist audio
or transcript history. Copy any text you need before quitting.

This locally signed developer preview still requires physical remote/permission
acceptance. Doubao/Typeless virtual microphone output, general HID mapping and
application execution adapters are future milestones. See the [native setup guide](docs/NATIVE-SETUP.md),
[design](docs/NATIVE-DESIGN.md) and [third-party notices](apps/macos/THIRD_PARTY_NOTICES.md).

The existing Python skill below remains separate: its planner returns semantic actions;
only its explicitly bound local/SSH tmux selector executes window changes.

## Install the supporting skill

Requires Python 3.10+. Keep the checkout in a stable location; the installer creates a symlink and refuses to replace an existing unrelated skill.

```sh
git clone https://github.com/BreezeLife/vibe-remote-skill.git
cd vibe-remote-skill
python3 scripts/install_skill.py
```

The default destination is `${CODEX_HOME:-$HOME/.codex}/skills/vibe-remote`. Installation does not install or configure a bridge, input method, or SSH connection.

## Use with Codex

```text
$vibe-remote
I have a Xiaomi Bluetooth Remote 2 Pro. Inspect the native app and
current project status before configuring my Codex workflow. Inspect the tools and
actual shortcuts, preserve my existing configuration, and verify remote
audio and the visible task before enabling the workspace binding.
Report what is configured, verified, and still pending.
```

Copy the [default configuration](skills/vibe-remote/assets/config.default.json) to `config.local.json` in the checkout root without overwriting an existing config. This local file is ignored by Git. All template workspaces start with `verified: false`. This JSON is not a bridge import format. Follow the [setup guide](docs/SETUP.md) for the safe copy command, provider settings, task bindings, tmux commands, and physical acceptance checks.

Use the installed skill's absolute path for diagnostics:

```sh
VIBE_SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/vibe-remote"
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" doctor
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" validate "$VIBE_SKILL_DIR/assets/config.default.json"
```

Dictation release leaves a draft. Send and stop require a verified AI target and current runtime evidence. A saved binding is not proof of current focus; shell or unknown state blocks submission.

## Tests and license

```sh
python3 -m unittest discover -s tests -v
```

Unit tests cover planner guards, provider lifecycles, tmux selection, and installer conflicts. Bluetooth audio, provider behavior, GUI switching, and physical integration require separate [acceptance checks](skills/vibe-remote/references/acceptance.md).

[MIT License](LICENSE). Adapted native protocol code retains upstream MIT notices in the source tree and app bundle. No third-party driver is bundled.
