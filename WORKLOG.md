# Worklog

## 2026-09-30

Created a Vibe Remote Codex skill for Doubao/Typeless setup, APP task selection,
and terminal window switching. Inspected installed applications: Doubao 0.5.7,
Codex bundle com.openai.codex, and ChatGPT Classic bundle com.openai.chat.
Typeless, remote bridge, and tmux were not found during the initial dependency check.
Their runtime behavior is pending physical verification.

The helper plans button intentions without injecting GUI keys. Its tmux adapter discovers
an exact registered session, selects a stable window ID, and verifies the result.

Validation passed: 21 unit checks, skill-creator metadata validation, and template schema
validation. Checks cover distinct provider lifecycles, repeat suppression, unknown/shell
and mismatched target guards, explicit CLI AI identity, exact session/window arguments,
selection verification failure, no-wrap boundaries, and installer conflict handling.
Bluetooth audio, APP GUI operations, native terminal switching, and live tmux remain untested.

Installed into /Users/weiqi/.codex/skills/vibe-remote by symlink to the durable local
Git repository /Users/weiqi/.codex/skill-projects/vibe-remote. Remote repository creation
and push were rejected by automatic approval because remote publication was not authorized.
No remote repository was created and no source was uploaded.

## 2026-10-02 — project recovery and public release preparation

The selected Project-VibeRemote directory was empty and had no Git repository. Located
the installed skill's source at ~/.codex/skill-projects/vibe-remote, read all four project
records and recovered its Git history into the selected project directory. The original
checkout was retained. Original main was 2ecf007, following b99ae45.

The share page returned a title without conversation body. Read the existing VibeRemote
chat through Codex and recovered the final explicit request for direct public GitHub
publication, professional project output, and usage instructions with existing hardware.
This supplies authorization that was absent during the original publication attempt.

Added Chinese/English project entry points, practical setup instructions, an MIT license,
project instructions and Linux/macOS GitHub Actions checks. Rechecked bridge guidance
against the upstream SayAll, MiCoding and MiRemoteVoice READMEs. No third-party bridge
source or driver is bundled.

Read-only environment inspection found Codex 26.928.31416, ChatGPT Classic 1.2026.160,
DoubaoIme 0.5.7, and a connected Xiaomi Bluetooth voice remote. No compatible bridge app,
MiRemote/BlackHole virtual audio input, Typeless or tmux was found in checked locations.
The separate MiCoding source folder contains iCloud placeholders; a directory read timed
out, so it was not treated as an installed bridge. No dependency or global setting changed.

Code review reproduced two planner defects: unknown recording values allowed sending
and other focus-dependent actions; Power repeated events bypassed suppression. Added
regression tests before fixing each gate. The 26-test suite then passed, including the
original 21 checks. Dictation cleanup and system volume retain their intended exceptions.

Environment inspection also exposed a Bluetooth-diagnostic false negative: current macOS
may put device names in dictionary keys under connected/disconnected categories instead
of _name. Added four regression checks, observed the expected failures, then fixed the
traversal and normalized explicit legacy connection values. Paired/unknown states remain
unknown; reports expose only device names and connection states. The actual doctor now
reports the Xiaomi voice remote connected, without exposing addresses or serial numbers.

Final local verification passed: 30 unit tests, skill-creator metadata validation, neutral
and local configuration validation, documentation-link/workflow checks and git diff --check.
Updated the known installed symlink to the canonical checkout atomically; the original
source folder remains intact. The installer confirmed this source was already installed.
Created a gitignored local template without overwriting any config; all bindings remain
unverified. Hardware audio, GUI operations and live tmux remain pending physical acceptance.
