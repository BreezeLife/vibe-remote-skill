# Vibe Remote skill

A Codex skill for Xiaomi Bluetooth Remote 2 Pro voice coding: provider-aware dictation,
APP task binding, and native terminal or tmux window switching.

The skill lives in skills/vibe-remote. A Bluetooth/audio bridge supplies hardware events.
APP interaction uses freshly observed computer-use UI; the bundled Python helper selects
only explicitly bound tmux windows, locally or through an existing SSH alias.

Install with Python 3 using scripts/install_skill.py. The installer links the skill into
the Codex skills directory and refuses to overwrite another skill. It installs no driver,
input method, daemon, or SSH configuration.

Run tests with Python's unittest discovery in tests. Validate skill metadata with Codex's
skill-creator quick_validate.py. Hardware and application checks are separate from unit tests.
