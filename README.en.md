# Vibe Remote

[中文](README.md) · [Setup guide (中文)](docs/SETUP.md)

A Codex skill for using Xiaomi Bluetooth Remote 2 Pro in voice coding workflows with Doubao, Typeless, Codex / ChatGPT apps, and terminal workspaces.

The package provides setup guidance, a configuration template, a guarded semantic event planner, and an exact-session tmux window selector for local or existing SSH sessions. A separate bridge receives remote audio and buttons. The skill does not install a microphone driver, listen for hardware events, inject GUI keys, or provide a background dispatcher. App operations require current UI observations and available computer-use tools.

## Install

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
I have a Xiaomi Bluetooth Remote 2 Pro. Help me set up SayAll with
Doubao for my current Codex app task. Inspect the installed tools and
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

[MIT License](LICENSE). Third-party bridges are separate projects with their own licenses and installation requirements.
