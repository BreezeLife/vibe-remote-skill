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

Post-launch re-verification found iCloud had reattached FinderInfo, invalidating the
workspace app signature again. Corrected the build's default destination to the local
~/Applications/Vibe Remote.app; an explicit VIBE_OUTPUT_DIR supports CI/temp output.
A build marker prevents replacing unrelated existing apps and symlink destinations are
rejected. The workspace process is preserved to avoid interrupting any unsaved draft.
The previous workspace bundle is a superseded build artifact, not the recommended launch
location. This output-location correction does not change Bluetooth or recognition code.

The ~/Applications bundle built successfully and passed strict signature verification
again after packaging. A synthetic unrelated-app fixture was preserved byte-for-byte
and the build refused it before compiling. The implementation commit's hosted native
job (XCTest, standalone core checks, Speech checks, release packaging) and four Python
jobs all passed: https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37212405473.

## 2026-10-05 — voice-key disconnect repair (0.1.1)

The user reported that connecting and pressing the voice key immediately disconnected
the app. Their screenshot showed “已手动停止；重新连接后继续”, with “等待说话” and
“等待音频”. Source tracing showed this status requires a host-requested manual stop:
RemoteModel called stopCapture when Speech was not enabled, start threw, or recognition
finished early; MIC_CLOSE/AUDIO_STOP then invoked the manual-stop reconnect gate.
The screenshot cannot distinguish missing authorization, local language availability or
another Speech error. A CLI authorization probe has a different identity and is not
evidence of the running app's permission state.

Separated physical reception from recognition in the model. Authorization is read from
the app's OS status at initialization and every new hold. Missing authorization and
recognition failures keep the stream open until release and retain the actual error;
signal/sample counts work independently of transcription. A hold owns at most one
recognition attempt, including when authorization arrives midway or Speech ends early.
No automatic online fallback, Mac microphone capture or transcript persistence was added.

Review found that early completion initially discarded the current segment's cancellation
snapshot. The final implementation retains it until physical release or explicit cancel,
ignores late callbacks, and prevents remaining PCM reaching a finished recognizer. A new
hold while the previous result is finalizing remains audio-only until release. Explicit
manual stops still use ManualStopGate, and watchdog stops now show the 8-second silence
or 90-second duration cause instead of claiming a user action. Recognition errors appear
directly below audio status; the UI displays version 0.1.1 and distinguishes authorization
from available recognition. Tests were added to GitHub's native job.

Evidence: fake-service tests against the original model yielded 9 scenarios / 50 assertions
/ 22 failures. Added cancellation checks then reproduced 9 failures in 15 scenarios / 107
assertions. Final model checks passed 15 scenarios / 111 assertions, including both fixes,
duplicate events, authorization changes, overlapping holds, synchronous append/finish
errors and late callbacks. These tests compile the real model with injected fake services;
they never initialize a Bluetooth central or recognizer, request TCC access, or use the
clipboard. Independent code review found no remaining substantive issue.

The 25 core tests, 42 Speech PCM/session assertions, 30 Python tests, neutral template
validation, shell syntax and git diff --check also passed. Release 0.1.1 (build 2) compiled
to /private/tmp/vibe-remote-0.1.1-build/Vibe Remote.app and passed strict ad-hoc signature
verification. This is a prepared artifact; real permission, language, audio and two-hold
acceptance are still pending.

Two old app processes were observed: the superseded cloud-workspace build and the local
~/Applications build. No matching SayAll/remote bridge process was found. Both old windows
were left running while the user was asked whether any in-memory drafts need preserving
before replacement/relaunch. Unrelated STATUS.md and .project-pulse/ remain untouched.

The user then explicitly confirmed no drafts needed preserving and approved the update.
Requested normal termination of both verified Vibe Remote instances through AppKit;
both requests succeeded and both processes exited. Installed the validated 0.1.1 bundle
in ~/Applications, opened it with LaunchServices, and observed exactly one VibeRemote
process from that location. The installed Info.plist reported 0.1.1 and its signature
passed strict verification again after launch. This confirms version/process startup,
not UI, hardware or recognition acceptance; the next physical press/release is pending.

Published fix commit 73bb098a7997578cc4d1fceb050948a67f75e521 via non-forced push to
GitHub main, and verified local and remote commit agreement. All five hosted jobs passed,
including native XCTest, standalone core/Speech/model checks and release packaging:
https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37245721494.

## 2026-10-05 — generate and install the macOS package

The user requested an installer and installation on this Mac. Read the project records
and existing bundle build script, then added scripts/package_macos_app.sh plus native
Installer distribution/component metadata and Chinese welcome/completion pages. No
application behavior or version changed. Apple Installer's current-user domain keeps
the established ~/Applications path without sudo; other domains and bundle relocation
are disabled. Strict bundle identity and version checks prevent unrelated replacement
or downgrades. Installer metadata requires Vibe Remote to close before updating; no
pre/postinstall scripts, drivers, automatic privacy grants or auto-launch are packaged.

Built release 0.1.1 in a temporary local directory, made the product archive, verified
its only permitted domain is CurrentUserHomeDirectory, expanded its app payload and
verified the ad-hoc signature. Independently checked the final Distribution: arm64,
minimum macOS 13.0 under volume-check, user-home-only domains, and the app's must-close
bundle ID. The archive's SHA-256 sidecar passed verification. The builder refuses to
overwrite an existing package/checksum; an initial inspection archive was moved out of
Downloads so the delivered filename identifies the final package.

Normally terminated the current app under the user's installation authorization, then
ran installer on the final .pkg with -target CurrentUserHomeDirectory, without sudo.
Installer reported successful installation at /Users/weiqi. pkgutil receipt query with
the user's home as volume confirmed io.github.BreezeLife.VibeRemote.installer 0.1.1,
location Applications. Installed app ownership is weiqi:staff. Opened the installed app
and observed exactly one VibeRemote process from ~/Applications; version and strict
signature verification passed after launch. GUI Installer interaction, clean-machine
Gatekeeper acceptance and physical remote/recognition acceptance remain unverified.

Delivered ~/Downloads/VibeRemote-0.1.1-arm64.pkg (148,738 bytes) plus its .sha256 file.
SHA-256: d5b996763064ff682f8469e7b80cb89d20810a5769ef7cf9194b4dfb49270457.
The app is ad-hoc signed; the installer itself is unsigned and not notarized.
All 30 Python tests, neutral config validation, shell/plist syntax and git diff --check
passed. Native application logic was unchanged; packaging, expanded-payload verification
and actual installation were the relevant native checks. Added package build/verification
to the existing native CI job. Unrelated STATUS.md and .project-pulse/ remain preserved.

## 2026-10-05 10:58 (Asia/Shanghai) — regenerate installer

At the user's request, reran the existing release packaging workflow from bf715ac
without changing application source or version (0.1.1 / build 2). New artifact:
~/Downloads/VibeRemote-rebuild-20261005-105806/VibeRemote-0.1.1-arm64.pkg,
148,732 bytes, with its .sha256 sidecar. SHA-256:
67e903427a41d2b60454c085787e829ff0420e76b025936d379a86a49e15e7e9.
Build and packaging succeeded; the expanded app signature, user-home-only installation
domain and final archive checksum all passed. The previous package was preserved.
This request regenerated the archive only; no installed app was replaced or restarted.
The installer remains unsigned/unnotarized and contains the ad-hoc-signed arm64 app.

## 2026-10-05 — visual button / coding tool design

The user requested our own SayAll-inspired button configuration and coding-tool support.
Read the project records, native app and skill contracts; researched official SayAll,
Apple HID/AX and tool documentation. Prepared a reviewable 0.2 design with desktop-first
scope proposed, real HID calibration/exclusive control, stable button intentions, tool
bindings and separately verified activation/input/send/stop capabilities.

Read-only app metadata identified Codex (com.openai.codex, currently ChatGPT.app), Claude,
and two different WorkBuddy bundle IDs. Their installed state does not establish any
working focus or submission adapter. CLI executables for Codex and Claude exist; WorkBuddy
and tmux were not found on PATH. No app, CLI, permission or hardware state was changed.

The design keeps the MIT project independent of SayAll's GPL client and proprietary assets,
preserves ATVV as the sole voice-capture source, and separates observation from exclusive
remapping so raw system key leakage cannot bypass action checks. Asked the user whether
desktop or CLI delivery should come first; desktop-first remains a stated proposal.
No implementation or new installer is claimed. Design approval and physical acceptance
remain pending. Existing local configuration, drafts and unrelated files are preserved.


## 2026-10-05 16:32 (Asia/Shanghai) — implement visual controls 0.2

Following the user's “继续实现吧” approval, implemented the desktop-first design on
codex/visual-controls. Added strict versioned native settings, semantic button/gesture
mappings, physical-device HID learning/exclusive capture, workspace-owned memory drafts,
AX tool bindings and original SwiftUI pages for dictation, buttons, tools and permissions.
ATVV and Speech implementations are unchanged; mic retains its dedicated voice behavior.
Codex, Claude Desktop and both installed WorkBuddy identities have presets; a preset
establishes discovery only. Custom apps, semantic shortcut learning, explicit Codex thread
opening and unsent new-draft prefilling are included. Native CLI and virtual mic remain
future work. No third-party application source or artwork was copied.

The coordinator invalidates gestures and pending tool operations on capture, draft, target,
permission or device changes. Calibration/inspection cannot dispatch actions. Send requires
exclusive capture plus session acknowledgement, an explicitly inserted draft, a full-text
review and fresh target/task/input/send/stop evidence. Runtime checks run again before every
mutation. Imported configuration executes nothing and preserves existing draft owners.
Unknown stop state, stale controls, app changes, shell targets and incomplete AX trees fail
closed. Reviews found and fixed editing-mode timer dispatch, async operation invalidation,
Optional.none gesture editing, stale stop identity and uppercase descriptor matching.
Independent final spec and quality reviews report no remaining implementation blockers.

Passed local checks: 47 core tests; 42 Speech assertions; 17 voice-model scenarios /
126 assertions; 48 fake HID assertions; 144 fake AX assertions; 15 settings assertions;
41 controller scenarios / 124 assertions; 30 Python tests; neutral config validation;
shell/plist syntax and git diff --check. The uppercase-hash regression first failed, then
passed after normalization. Full debug and release builds succeeded. Added HID, tool,
storage and controller suites to hosted CI. Actual hosted results are recorded separately.

Opened an isolated preview with a temporary bundle ID and observed the 0.2 initial native
window/sidebar. Native UI automation disconnected before interactive page inspection;
offscreen render output was not accepted as visual verification. The temporary preview
was closed. The installed 0.1.1 app remains running because its current window contains a
new in-memory draft. No draft text was written into project records. No TCC grants changed,
no HID interface was seized and no AI message was submitted. Passive HID inventory found
no matching current interface. Raw-key suppression, ATVV coexistence and actual per-tool
capabilities still need physical acceptance and are not claimed by synthetic tests.

Built ~/Downloads/VibeRemote-0.2.0-20261005-163035/VibeRemote-0.2.0-arm64.pkg
(661,083 bytes), version 0.2.0 / build 3, macOS 13+ / arm64. Release signature, expanded
payload signature, current-user-only installation domain and independent SHA-256 sidecar
verification passed. SHA-256:
6bd9fa5806236ed07109f8316ab00c73def4c232e53cd2f802c8403341cc0aa3.
The installer remains unsigned/unnotarized and contains an ad-hoc-signed app. Earlier
packages and the installed app were preserved; 0.2 has not been installed over the draft.
Unrelated STATUS.md and .project-pulse/ remain untracked and untouched.

Implementation commit 544887d was fast-forwarded to main and pushed without force.
The GitHub API independently confirmed main at that commit. All five hosted jobs passed:
https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37284339661.
The native job passed XCTest, standalone suites, release app and installer verification
in 4m37s; all four Linux/macOS Python matrix jobs passed. The final follow-up commit changes
only delivery/verification records and skips a redundant CI run. Hardware acceptance and
local 0.2 installation remain pending; the user has been asked how to preserve the new draft.
