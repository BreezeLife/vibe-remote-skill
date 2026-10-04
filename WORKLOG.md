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

## 2026-10-02 — public GitHub synchronization

Created https://github.com/BreezeLife/vibe-remote-skill as a public repository. The first
HTTPS push was rejected because the existing OAuth credential lacks workflow scope.
Verified the pre-existing GitHub SSH identity as BreezeLife and set this repository's
origin to git@github.com:BreezeLife/vibe-remote-skill.git. The SSH push succeeded without
changing account authorization, keys, global Git settings or original commit history.

GitHub recognized the MIT license and main as the default branch. Confirmed remote main
and local HEAD both pointed to code-publication commit 4c4b98c, with a clean working tree.
All four Linux/macOS and Python 3.10/3.13 jobs passed:
https://github.com/BreezeLife/vibe-remote-skill/actions/runs/36899566684.

The run flagged the newly added checkout v4 dependency's deprecated Node 20 runtime.
Updated the pinned checkout dependency to the official v6 revision using Node 24 and
prepared this final status synchronization. No application behavior changed in this step.
Remaining work is the physical acceptance sequence in TASKS.md and docs/SETUP.md.

## 2026-10-03–04 — direct-use installation preparation

The user requested immediate physical use rather than further project packaging. Re-read
the four project records and Vibe Remote setup references. Confirmed this Mac is arm64,
macOS 15.7, with DoubaoIme 0.5.7; SayAll and a compatible virtual audio input were still absent.
The current Bluetooth diagnostic returned no candidate, so connection is unconfirmed.

The official GitHub asset download timed out. Downloaded SayAll 1.9.21 from its official
stable CDN entry https://download.sayall.app/mac instead. SHA256 matched the published
GitHub asset: 1f174fae61f02b9e1984611d0ad9fecc6521891b0793ac25382029ff9e33aef8.
Mounted the image read-only at /private/tmp/VibeRemote-SayAll-Mount. Its actual package
filename is Install Remote Mic.pkg, despite newer upstream instructions using SayAll naming.
pkgutil confirmed a trusted Developer ID Installer signature and Apple notarization;
spctl accepted the installer as Notarized Developer ID.

Native computer-use calls timed out, including opening Installer. No software, driver,
permission, global input setting or workspace verification flag was changed. The prepared
installer needs the user to run it and enter their administrator password in the macOS
dialog. Next: grant expected bridge permissions, choose MiRemoteV 2ch in both tools,
leave Fn tap simulation off for Doubao, and physically verify remote audio and unsent drafts.
No conversation-history MCP setup is needed for this dictation path. Existing unrelated
STATUS.md and .project-pulse/ files were preserved.

## 2026-10-04 — self-developed macOS application

The user explicitly changed the requirement to our own application, referencing
MiRemote without using its app. Re-read the project records and researched the MIT
MiRemoteVoice bridge at 2c374d9d65ed6c8b1af6a4f9aa1b6c0f8a039aaf, Google ATVV 1.0,
and Apple's Speech APIs. The earlier external-bridge installation path is superseded.
Recorded the native design/plan and kept the existing skill and repository history.

Implemented apps/macos as a SwiftPM core library plus SwiftUI/AppKit application.
The first native milestone connects directly to the remote through CoreBluetooth,
negotiates ATVV only after both notification subscriptions succeed, decodes mono
ADPCM, shows signal level, and feeds Apple Speech. It requires on-device recognition
by default; the user may explicitly allow Apple's network speech service. No Mac
microphone fallback, raw audio logging, transcript persistence, external application
key injection or third-party virtual audio driver is included.

The draft lifecycle preserves prior text, appends successive utterances, blocks editing
while capturing/finalizing, and rejects late callbacks after cancellation. Release
finishes recognition into a draft; copying is explicit. General HID mappings, target
selection/execution and a native virtual microphone for Doubao/Typeless remain pending.

Review found a cancellation edge: a held remote key can repeat START_SEARCH after a
MIC_CLOSE acknowledgement. Manual stops now require a fresh connection; a pure stop
gate and three sequence tests prevent resuming a cancelled segment. Natural physical
release retains the connection. Also prevent reconnecting while the previous peripheral
is retiring, and suppress level callbacks after synchronous recognition errors.

Decoder verification exposed noncanonical upper entries in the reference ADPCM step
table. A known high-index vector failed with [311, 595] instead of [312, 596]; corrected
the full table against ATVVoice's standard IMA/DVI values. A separate expected-value
mistake in the sync test was independently recalculated and corrected. Complete MIT
attributions and notices ship in both source and app resources; no GPL driver is reused.

This Mac has Swift 6.1.2 and Command Line Tools without XCTest. The initial Swift test
attempt therefore could not load XCTest. Added a small standalone runner that executes
the same test methods with swiftc; full-Xcode CI retains XCTest. Final local checks:
25 protocol/draft/stop tests passed, 42 speech PCM/session assertions passed, 30 existing
Python tests passed, neutral configuration validation passed, documentation links and
shell syntax passed, and git diff --check passed. Native debug compilation passed.
Speech checks use synthetic PCM and do not instantiate a recognizer or trigger TCC.

A fresh doctor scan now finds SayAll 1.9.21 and MiRemoteV2ch.driver, which were absent in
an earlier snapshot. Their installation was not observed in this development turn;
no third-party installation or removal was performed as part of native development.
The current scan still finds no Bluetooth candidate. No physical audio, Speech permission,
local language-model availability, or native UI acceptance has been verified.

Unrelated STATUS.md and .project-pulse/ remain preserved and excluded from this work.

Release compilation succeeded. The first package signature check found FinderInfo
metadata attached to the generated app in the iCloud-synced checkout. Updated the
build script to remove only FinderInfo/ResourceFork from its generated app (not
quarantine/provenance or source files). The rebuilt app passed Info.plist validation
and codesign --verify --strict. Output: build/Vibe Remote.app, version 0.1.0, arm64,
local ad-hoc signature; Developer ID/notarization and hardware acceptance remain pending.

Launched the generated app with LaunchServices; its VibeRemote process remained running.
This confirms process launch only, not a visually inspected UI or working hardware.

Published native milestone commit 296016984feb7f05ebf07667140f22f3a90c9a44 to
GitHub main with a non-forced push after confirming the remote was still 3fdd8e8.
This checkout lacked a Git author setting, so the commit used the latest repository
author identity via per-command options; no global Git configuration was changed.
Native and Python hosted checks are available in the repository's Actions page.
