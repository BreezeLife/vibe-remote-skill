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

## Workflow and boundaries

The intended loop is: choose a workspace, hold to dictate, release into an unsent draft,
inspect the destination and text, explicitly send, then read output or open a preview.
APP adapters select registered tasks; CLI adapters select registered windows or panes.
Browser focus does not redefine the bound AI destination.

Keep three layers separate: the bridge receives physical audio/buttons; this skill defines
configuration and guarded semantic actions; an observed UI adapter or companion executes
those actions. The Python planner never injects GUI keys. Only the tmux selector executes
window selection, against an explicitly verified existing session.

## Repository and continuity

Canonical development checkout: Project-VibeRemote. The existing local Git history was
recovered from ~/.codex/skill-projects/vibe-remote on 2026-10-02 without deleting the original.
Public repository: https://github.com/BreezeLife/vibe-remote-skill (MIT), synchronized on main.

README.md and docs/SETUP.md are the user entry points; README.en.md provides an English
introduction. TASKS.md contains current acceptance state; MEMORY.md stores durable choices,
and WORKLOG.md records evidence chronologically. GitHub Actions checks Python 3.10/3.13 on
Linux and macOS. Local config and runtime observations remain outside Git.
