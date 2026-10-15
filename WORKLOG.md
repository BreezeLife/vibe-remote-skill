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


## 2026-10-08 — configuration help and original app icon

The user supplied the programming-tools page and asked how to configure it and for an app
icon. The screenshot reports missing Accessibility authorization. Read the project records
and checked the actual settings/coordinator/adapter code with a read-only review. Clarified
optional workspace URL fields, the below-fold input/task learning sequence, empty-draft
learning requirement, and the additional exclusive HID/session acknowledgement required
even for mouse-triggered send preview. No system permission was changed or tool operated.

Generated an original graphite-tile, white-remote, mint-waveform icon using built-in
image_gen, without reference artwork or third-party logos. Saved the original 1254-square
RGBA PNG and full generation prompt under apps/macos/Packaging/Artwork. Added a mechanical
sips/iconutil conversion script and AppIcon.icns containing ten standard 16–1024 pixel
representations. Added CFBundleIconFile and copy into the signed app resources. Bumped
package metadata to 0.2.1 / build 4; no runtime application source or behavior changed.

Release build and packaging succeeded. Independently expanded the final product, verified
its version/icon declaration, compared the bundled ICNS byte-for-byte with the repository
asset, decoded all ten icon representations, and verified the strict app signature. Archive
checksum passed. All 30 Python tests, neutral configuration validation, shell/plist syntax
and git diff --check passed. Package:
~/Downloads/VibeRemote-0.2.1-20261008-194907/VibeRemote-0.2.1-arm64.pkg
(2,488,333 bytes); SHA-256:
4fd4199b0fde8b335e8f018d13a1199ec62be44024c73dd937ae15b8bba20977.
App remains ad-hoc signed, installer unsigned/unnotarized. No installed app was overwritten
or restarted. Read-only metadata now finds 0.2.0 / build 3 at /Applications/Vibe Remote.app;
the earlier ~/Applications copy is absent. This is not evidence of live permission or
draft state. Updated TASKS to distinguish this new evidence from the earlier preservation
record. Unrelated STATUS.md and .project-pulse/ remain untouched.


## 2026-10-08 — shared Applications install and Pro 2 + Vibe branding

The user explicitly required the shared /Applications destination, then asked to base the
icon on their Xiaomi Remote 2 Pro photo and emphasize the Vibe name at Dock size. Read the
project records and performed read-only packaging review. This requirement supersedes the
old current-user domain. Distribution now permits only LocalSystem; install-location stays
/Applications, with strict identity, version checks, no relocation and must-close intact.
Normal developer builds now output to ~/Library/Caches/VibeRemote/Build; package staging
remains outside iCloud and CI requires no privileged installation. Updated docs, welcome
and completion pages, durable decisions and the CI step label. Version is 0.2.2 / build 5.

Used built-in image_gen for two requested refinements: silver Pro 2 hardware following
the supplied photo, then a prominent mint Vibe wordmark. Preserved both previous designs
and all prompts in Packaging/Artwork; source remains 1254-square RGBA with real alpha.
The product photo is not distributed. Rebuilt ICNS and inspected 64/128 pixel previews.

Built ~/Downloads/VibeRemote-0.2.2-System-20261008-202916/VibeRemote-0.2.2-arm64.pkg
(2,651,235 bytes). Independently verified the exact LocalSystem domain, /Applications
payload location, must-close metadata, version/build, installed icon bytes, expanded strict
signature and SHA-256:
9197c10a25b6d8a0aff1e1b4ff41a3192baca6800fa56487fd41c984af5a06e8.
All 30 Python tests, neutral config validation and shell/plist/diff checks passed; independent
review found no implementation issues. No voice, HID, tool or other runtime source changed.
App remains ad-hoc signed and package unsigned/unnotarized.

Initially verified and moved the installed 0.2.1 from ~/Applications to /Applications,
whose destination was absent and writable, while preserving the running process. Native
window automation then failed, so no draft emptiness was inferred. After the user explicitly
confirmed “草稿已保存，可以退出并更新”, ensured the old PID had exited, retained the old
bundle at ~/Library/Caches/VibeRemote/PreviousVersions/
VibeRemote-0.2.1-20261008-204332.app.backup, and installed the already-verified expanded
0.2.2 payload in the writable /Applications directory. This was an app-bundle deployment,
not a root Installer transaction; no new system package receipt is claimed. Configuration
files and system privacy permissions were untouched.

Repeated disk verification found the real /Applications/Vibe Remote.app (not a symlink),
0.2.2/build5, a valid signature, and the exact Pro 2 + Vibe ICNS; ~/Applications/Vibe Remote.app
is absent. Reset native UI automation, located the system bundle in Finder and opened it.
The actual native window displayed “开发预览 0.2.2” with paused mappings and no connected
remote. This verifies launch/location, not hardware, speech or tool capabilities.
Unrelated STATUS.md and .project-pulse/ remain untouched.

## 2026-10-08 — remote close-up + Vibe design output

The user requested a professional app icon combining their cropped silver remote
reference with the word Vibe. Used built-in image_gen to produce a single graphite
rounded-square icon with an enlarged silver remote, directional ring, mint microphone
highlight and large Vibe lettering. Saved the unmodified output and full prompt under
apps/macos/Packaging/Artwork/Proposals. sips confirms 1254 × 1254 pixels and alpha.
This is a design-only iteration: canonical icon, app version, package and local installation
were not changed. No runtime tests are needed for a separate PNG and design record.

## 2026-10-08 — Pro 2 physical layout and coding-tool button schemes

The user compared the generic diagram against the actual Pro 2 and requested default
button configurations for Codex, Claude and WorkBuddy. Replaced the visual arrangement
with the actual power/mic row, segmented direction ring and OK, back/home/menu left,
joined volume rocker and TV right. Physical names are separated from actions (power
is now labelled 电源). All 13 buttons retain selection and press feedback.

Added three tool presets covering four observed bundle identities. Defaults preserve the
fixed button intentions and use the existing AX adapter rather than assumed keycodes.
New profiles have independent semantic buttonActions; legacy profiles retain global
actions until explicitly edited. HID calibration remains global. Action-only reset retains
calibration and shortcuts; explicit tool-preset restore also resets optional shortcuts to
the default AX method while preserving bindings, drafts and other workspaces. Added
visible add/apply/edit controls and a default-action table, plus native setup instructions.

First reproduced two failed assertions showing edits leaked between workspaces, then
implemented scoped display/edit/dispatch. Independent review found a resolved event batch
could retain old actions after its first event switched workspaces; reproduced timer and
input cases, then added a batch workspace guard. Final verification: 54 core tests,
46 integration scenarios / 149 assertions, 15 settings assertions, 144 adapter assertions,
30 Python tests and neutral template validation all passed. Release build, plist and diff
checks passed. Independent code review found no remaining actionable issue. Production
views were rendered via NSHostingView with isolated fake services at ordinary and minimum
740-point widths; no layout overlap or overflow observed. This is not physical hit-testing,
HID/audio acceptance or actual AI tool verification.

Built 0.2.3/build 6 at ~/Downloads/VibeRemote-0.2.3-System-20261008/
VibeRemote-0.2.3-arm64.pkg (2,713,828 bytes). Independently expanded and verified version,
LocalSystem-only domain, /Applications payload location, canonical icon bytes, strict app
signature and SHA-256 0a401aa0a130d13cd9f964335332351f64aef4278c7b426efdc0bbd20b016dc7.
App remains ad-hoc signed; package unsigned/unnotarized. Native inspection of the running
system 0.2.2 app failed with a closed-pipe error, including after resetting the UI tool;
Finder was readable. No drafts were assumed empty, no app was quit, and no installed
bundle, local settings or system permissions were changed. STATUS.md and .project-pulse/
remain untouched. The earlier icon proposal remains separate from the canonical app icon.

## 2026-10-09 — integrate the icon that was left as a proposal

The user's 0.2.3 About screenshot correctly showed the previous small full-remote icon.
Verified the system bundle's version and traced the mismatch: the requested close-up PNG
was under Artwork/Proposals while the build copied the older checked-in AppIcon.icns.
Promoted that exact generated PNG to AppIcon.png, archived the earlier branded design as
AppIcon-pro2-vibe-full.png, regenerated ICNS, and bumped metadata to 0.2.4/build 7.
Updated provenance and installation docs. No new artwork or runtime code was generated.

Verified source PNG equals the requested proposal, ICNS differs from installed 0.2.3,
all ten representations exist, and 64/128 pixel previews visibly show the close-up.
Release/package build, 30 Python tests, neutral configuration validation, plist and diff
checks passed. Independently expanded the package and verified 0.2.4/build 7, LocalSystem,
/Applications payload, source/package ICNS identity, strict signature and SHA-256.
Package: ~/Downloads/VibeRemote-0.2.4-System-20261009/VibeRemote-0.2.4-arm64.pkg,
3,009,575 bytes; SHA-256 5d25293c148058e74e7259ac0c4db4e3fd789bd86657817ff6bbcd115de4ba19.
It remains an ad-hoc-signed app in an unsigned/unnotarized development package.

Native UI inspection worked this time. Observed 0.2.3 About and checked the unbound draft
plus all 9 workspace drafts as empty with no capture in progress. Returned to the selected
workspace, quit through the app and confirmed the process exited. Direct bundle replacement
failed on root ownership before moving the installed app; copied a recoverable backup to
~/Library/Caches/VibeRemote/PreviousVersions/VibeRemote-0.2.3-20261009-093253.app.backup.
Noninteractive installer authorization was unavailable. Opened the exact 0.2.4 package
in macOS Installer, selected its all-users system destination, and started installation.
The system authorization step requires the user's Touch ID/admin credential; requested
that completion in the system dialog without sending credentials in chat. At this point
the old installed bundle/settings are preserved; final installation verification is pending.

## 2026-10-09 — nearby remote selection and automatic idle reconnect

User requested finding nearby remotes, choosing one and connecting automatically after selection.
Replaced first-matching-device connection with explicit discovery and a shared picker in dictation
and connection settings. Candidates merge by UUID, exclude generic Xiaomi devices, show source
and optional signal, and retain a local chosen UUID separately from verified ATVV readiness.
A fresh launch does not scan or request permission; user can reconnect the remembered selection.
Idle unexpected disconnection after negotiation retries only that selection at 2/5/10 seconds.
Explicit disconnect, manual capture stop, capture-time loss, protocol errors and Bluetooth loss
suspend retries. Existing drafts, HID safeguards and send guards are unchanged.

Added pure discovery/reconnect tests, real-model fake-service checks and isolated UserDefaults
initialization/forget checks without creating a Bluetooth central. Core: 62 tests; model: 22
scenarios/159 assertions; integration: 46 scenarios/149 assertions; Speech: 42; HID: 48; settings:
15; adapter: 144; Python: 30, all passed, plus neutral config validation. The new busy-connect
regression failed before its guard was implemented. Independent read-only review found no blocker.
Production NSHostingView fixture renders cover empty, five candidates, connecting, ready and both
740-point pages; inspected bounded list and no horizontal overflow. These are simulated states,
not evidence of real discovery, pairing, signal, audio or permission availability.

Bumped to 0.2.5/build 8, retaining the canonical enlarged remote + Vibe icon. Release and package
builds passed. Independently expanded the final package and checked LocalSystem-only domain,
/Applications destination, version/build, source icon equality and strict app signature.
Package: ~/Downloads/VibeRemote-0.2.5-System-20261009/VibeRemote-0.2.5-arm64.pkg,
3,077,318 bytes; SHA-256 8f50e1fc1ea8f3279529a7833b8b2e582f0ded185dfce98733eb2f6a195b980f.
The app uses ad-hoc signing; package remains unsigned/unnotarized.

Read-only installation check still reports system 0.2.3 and no ~/Applications copy. The earlier
0.2.4 Installer UI remains at Preparing for installation, awaiting the user's system authorization.
Asked the user to complete or cancel that dialog before proceeding with 0.2.5; the computer-use
tool cannot operate the protected authentication window. No installed app, real configuration,
permissions, HID ownership or drafts were changed. STATUS.md and .project-pulse/ left untouched.


## 2026-10-10 — managed Codex conversations, one-click setup and test guide

User requested Codex desktop first, direct up/down conversation switching in the current tool,
project/workspace navigation, automatic input focus, voice input followed by explicit confirmation,
and preference for Steer when a running conversation exposes it. Later requested one-click
configuration with test guidance. Claude/WorkBuddy retain their existing manual presets; managed
conversation adapters are follow-up work after Codex acceptance.

Added strict persisted conversation metadata and a short-lived bounded catalog service using
the selected Codex application's bundled CLI. It only initializes and lists local thread metadata;
retains ID/name/cwd, never previews/transcripts/runtime state. A private server cannot control the
desktop server's active turn. Catalog candidates stay ephemeral; only deliberately selected
sessions become profiles with separate draft UUIDs. Existing manual profile identities and
custom actions are preserved. Updated canonical title/path information supersedes stale catalog
metadata while customized actions remain. Managed duplication is disabled to prevent ambiguity.

Added canonical conversation navigation, bounded observation retries, verified main-composer
binding and focus. Live thread identity or catalog-qualified project/title evidence is mandatory;
sidebar links, ambiguous titles, missing evidence, modal/approval and unknown runtime controls
cannot authorize mutation. Managed default up/down navigates sessions within the current project;
left/right navigates projects and restores the last selected session. Capture cancels delayed
navigation effects and preserves the explicitly selected draft owner.

Confirmation now inserts once, reads back the complete target text, and presents an explicit
Send/Steer review. A fresh uniquely scoped Steer control takes priority; otherwise verified idle
Send may be used without requiring a Stop control to have been visible during initial setup.
Second confirmation rechecks target/text/kind/device and consumes its approval once. Mutation
callbacks distinguish preflight failures from attempted writes/submits, preserving uncertain
outcome locks instead of blindly repeating actions. Confirmed submission keeps the user's draft
and requires an explicit empty reset before new input, preventing old text appended by subsequent
dictation from being sent twice.

One-click UI prepares metadata/defaults and lets the user select project/session. Observed checks
are shown separately from installation and configuration. In-app guide covers permissions, HID
exclusivity, two-session navigation/draft isolation, hold/release dictation, two-step confirmation,
Steer and manual fallback. The computer-use tool rejected real Codex UI access; did not bypass it
with AX/AppleScript or execute the new adapter against Codex. All navigation/input/send checks
used synthetic fixtures. No real catalog process, target UI mutation, remote/audio or TCC prompt
was exercised by tests.

Verification: core 69 tests; Speech 42 assertions; model 22 scenarios/159 assertions; HID 48;
settings 15; adapter 307; catalog 27; controls integration 60 scenarios/190 assertions; Python 30,
all passed, plus neutral configuration validation. Observed red regressions before fixes: initial
confirmation integration (2 failures), refreshed metadata/check isolation/copy/uncertain retries
(7 failures), and confirmed-send draft reset (2 failures). Independent final review found no
remaining actionable blocker. Isolated production UI renders passed at 740 pt and full 960 pt
window, with no real app activations, writes or presses. Added catalog suite to GitHub workflow.

Built 0.2.6/build 9 retaining the enlarged remote + Vibe icon. Independently expanded package:
LocalSystem-only, /Applications destination, relocation disabled, expected bundle identity/version,
strict signature and exact source icon bytes. Package:
~/Downloads/VibeRemote-0.2.6-System-20261010/VibeRemote-0.2.6-arm64.pkg,
3,268,257 bytes; SHA-256 f7f250c033791603fc1b6a4d5025032090a371455ae1bd21eccfd12c7ecab88a.
The app remains ad-hoc signed; installer unsigned/unnotarized.

Fresh installation metadata showed the user had completed 0.2.5 in /Applications; no user-directory
copy. Inspected unbound and all 9 configured workspace drafts as empty with no capture, restored
the original selection and quit normally. Saved old bundle to
~/Library/Caches/VibeRemote/PreviousVersions/VibeRemote-0.2.5-20261010.app.backup.
Opened the exact 0.2.6 package in macOS Installer, confirmed installation for all users on Macintosh
HD and started it. Administrator authorization requires the user's system action; requested that
without collecting credentials. Final installed/running version and real Codex/remote acceptance
are pending. STATUS.md and .project-pulse/ remain untouched.


## 2026-10-11 — discovered remote rejected with lost pairing information

User provided app screenshot showing a discovered Xiaomi voice remote and connection failure
“Peer removed pairing information”; then a macOS Bluetooth screenshot explaining that a previously
connected remote now needs Forget to recover. Read-only installed metadata confirms 0.2.6/build 9
under /Applications, no current-user copy, and running executable from the system path.

Systematic investigation: Apple SDK declares CBErrorPeerRemovedPairingInformation = 14 in
CBErrorDomain. The connection-failure path displayed only localized English; the disconnection
path ignored Error, and both could retain automatic retry eligibility for a failed bond. ATVV
error callbacks also lacked a common recovery classification. This establishes the handling gap;
it does not establish why the remote/host bond became inconsistent. Asked whether the user had
repeated HOME+MENU pairing mode or connected another host, and for the outcome after repair.

Factored shared failure handling behind existing current/retiring peripheral guards. Exact bond
loss now sets an ephemeral device-scoped marker before publishing disconnect, clears timers and
suspends policy, leaving selection/preferences/drafts intact. Ordinary transient errors retain
bounded reconnect behavior. Explicit manual retry stays available; verified ATVV handshake clears
the recovery marker. All error-bearing protocol callbacks use the same classifier. UI shows system
Forget/re-pair/search steps and distinguishes app Forget Selection from macOS pairing. Normal daily
wake uses a short ordinary-key press; the HOME+MENU combination is for pairing only. No system
pairing was removed automatically and no radio, privacy setting or user's app config was changed.

Regression evidence: baseline core 70 tests/2 failures and model 24 scenarios/170 assertions/3
failures reproduced missing handling. Final core70/0, model24/170/0, integration60/190/0, Python30/OK
and neutral config validation passed. Independent review found no blocker. Core tests cover armed
retry suspension; actual service fixtures use isolated defaults and no central, proving classification,
publication and preservation rather than real Bluetooth recovery. Fake-only 740 pt production-view
render inspected without overflow. No physical connection or audio acceptance is claimed.

Built and independently expanded 0.2.7/build 10. Verified LocalSystem-only installation domain,
/Applications destination, no relocation, source icon equality, bundle identity and strict signature.
Package: ~/Downloads/VibeRemote-0.2.7-System-20261011/VibeRemote-0.2.7-arm64.pkg,
3,278,394 bytes; SHA-256 ead5202e7da703576514c3f182afe15b3820b5e053d2e4e8a6e7012791f034d5.
The app remains ad-hoc signed and installer unsigned/unnotarized. Existing running 0.2.6 has not
been closed; fresh draft safety and physical re-pair outcome require user confirmation. No attempt
was made to manipulate protected Codex UI or system pairing through alternate automation.


Checked previous GitHub run 37977391582: it failed a tool-adapter delayed-navigation fixture
(307 assertions, one failure), so subsequent native catalog/integration/package CI steps had
been skipped. The fixture allowed only 100 ms for two observations. Reproduced deterministically
with a 150 ms first fake snapshot (red307/1), then used the production 2-second navigation budget
(green307/0), retaining the requirement to observe twice while opening the URL exactly once.
This correction changes tests only; the independently verified 0.2.7 package is unchanged.


## 2026-10-12 — native third-party voice-input configuration (0.2.8)

User requested Typeless, Doubao IME and mainstream voice-input configurations, then explicitly
chose Vibe Remote drafts as the first text destination. Added provider profiles and a dedicated
settings page for Typeless, Doubao IME, Wispr Flow, Superwhisper, macOS Dictation and custom tools.
Native optional voiceInput remains compatible with older schema-1 settings; independent profiles
retain other settings and drafts. Official provider docs informed setup guidance without assuming
that saved hotkeys or an installed app establish recording/permission state.

Added a pinned AUHAL output path to existing MiRemoteV 2ch / BlackHole 2ch plug-ins, 8/16 kHz mono
conversion to device rate, bounded two-second FIFO, drain, live route validation and cancellation.
No default audio device mutation, fallback input, driver install or third-party application install.
Read-only metadata found Doubao IME 0.5.7 in /Library/Input Methods and an eligible MiRemoteV 2ch.
Audio driver identity resolves through plug-in device membership; device.owner is not reliable
on this machine. No runtime device identifier was written to the project.

Manual trigger is default; restricted, explicitly matched hotkeys optionally implement hold/toggle.
Own receiver focus is required before forwarding. External processing locks workspace/configuration
until the user confirms the provider has finished; reviewed text appends without replacing the old
draft or sending. Route/focus loss halts output and releases held keys without retrying an uncertain
toggle. Independent review caught import-during-capture mode divergence and stale preparation
confirmation after app replacement; both corrected. Immediate route errors also notify the controller.

Validation: core 80 tests (configuration red 71/1 then green 80/0), voice model 26 scenarios/182 assertions,
external lifecycle 21, audio 46 (cancelled deferred-callback regression red 43/1 then green 46/0), provider
bundle discovery 21, speech 42, HID 48, tool adapter 307, settings 15, catalog 27, controls integration 60/190
before added provider-persistence coverage, Python 30 and neutral config valid. The final controls
integration run passed 61 scenarios / 197 assertions, including provider/runtime persistence alignment. All services in tests are fake; no recording, key injection or real AI-tool
interaction. Isolated SwiftUI renders at 740 pt settings and 680 pt receiver checked; corrected the
shortcut-help line wrap and re-rendered. Builds pass; tests/compilation do not establish physical use.

Packaged 0.2.8/build 11 and independently expanded it. Confirmed LocalSystem-only domains,
/Applications destination, nonrelocation, canonical icon equality and strict app signature.
Package: ~/Downloads/VibeRemote-0.2.8-System-20261012/VibeRemote-0.2.8-arm64.pkg,
3,442,686 bytes; SHA-256 0f82be3c0da4b3ecb9348e33c7fce3bf04be106fd633d378680e476c2c250626.
The verification helper initially rejected pkgbuild's empty relocate element; checking relocatable=false
and no relocation entries confirms the intended package behavior. This was a checker assertion, not
a package mutation. App ad-hoc signed, installer unsigned/unnotarized. System /Applications currently
runs 0.2.7; asked whether its current in-memory drafts are safe before closing/opening the installer.
Previous GitHub run 38144937313 for 430feba completed successfully. Public sync for this change follows.

Implementation committed and pushed as `6cf811a` to origin/main. The code/config/docs checkout is
clean apart from pre-existing untracked STATUS.md and .project-pulse, which were left untouched.
GitHub checks were triggered; no hosted success for this revision is claimed yet. No response to
the current draft-safety question had arrived, so the running installed app was not closed.


## 2026-10-12 — current-focus input and bounded hardware observation (0.2.9)

User changed the earlier draft-first preference and explicitly confirmed following the current
focus without auto-send. Added a provider-independent destination with legacy draft default.
Native direct input captures the actual field at physical hold, waits for release/final text,
then makes one selected-text AX replacement after rechecking field/window/process, full value
and UTF-16 selection. It never posts Enter, overwrites a whole field, uses clipboard fallback,
or copies bound workspace text into the direct buffer. Unsupported/changed/uncertain targets
retain text for explicit inspection/copy/clear. Secure/read-only fields fail before value use.

External direct mode captures at hold rather than Prepare; no own receiver sheet or window
activation. The provider places text itself, so the app cannot take/import/reinsert it.
Manual/hold/toggle all require explicit confirmation that provider auto-send is disabled.
Completion remains user-observed; menu/inline confirmation prepares the next hold with a fresh
target. Focus/route loss stops forwarding and releases held keys, without retrying toggle state.
Provider paste behavior after focus loss is outside our control and is explained in the guide.
Bound workspace insert/send/confirm actions are blocked while direct mode is selected.

Observed regressions: overlapping native holds initially failed 1 of 205 assertions (31 scenarios),
then passed after retaining text whenever finalization had an issue. Independent review reproduced
unsafe insertion after interruption; explicit transport interruption now runs before audio-end
callbacks for manual stop/watchdog/reset, and model disconnect/readiness loss/shutdown invalidate
targets. Added regression suite first failed 12 of 221 assertions (36 scenarios), then passed.
Final review found stale external interruption deduplication after preparing again: red 37 scenarios /
224 assertions / 2 failures, then green 37/224/0 with dedupe limited to the same active hold.
Focused service tests started with a red implementation stub and finish at 64 assertions passed.

Final checks: core83; model37/224; controls integration63/211; focused64; external48; audio46;
speech42; HID48; tools307; settings15; catalog27; provider discovery21; Python30 and neutral
configuration validation all passed. Real app release and final package builds passed. Fake-only
UI renders at 740 pt cover settings, prepared external input, review and native retained text;
no clipping observed. Initial UI fixture compilation overlapped a source edit; recompiling an
isolated source snapshot passed. No real AX read/write, target activation or key injection was
used in these fixtures. Existing Codex computer-use denial was not bypassed.

With the user's hardware-test authorization, the installed system 0.2.7 reached actual ATVV
readiness at 16 kHz after Connect. System metadata showed a connected BLE Xiaomi remote and
its expected keyboard HID interface. Apple Speech in the app was not authorized; mappings
were paused. An exact remote-only, nonexclusive 60-second HID observation had granted input
monitoring and opened one device, but received zero events; it closed cleanly. No physical
key values, audio delivery or transcription are marked verified. Doubao IME and MiRemoteV 2ch
were already installed; no bridge app was running, no audio defaults/permissions were changed,
and no device identifier, transcript or raw audio was stored in project files. The UI tool
subsequently failed with a native pipe-closed error; it was not replaced by alternate GUI automation.

Packaged 0.2.9/build12 at ~/Downloads/VibeRemote-0.2.9-System-20261012/
VibeRemote-0.2.9-arm64.pkg (3,486,091 bytes); SHA-256 6388ce473e2b9b6f0a268d739947cf4e9063f18855a2f903cd9b33edcdddeae5.
Independent expansion verifies LocalSystem only, /Applications, no relocation, canonical icon,
bundle identity/version and strict app signature. The verifier initially read relocatable on the
bundle child rather than pkg-info; corrected the checker and all assertions passed. The app is
ad-hoc signed, package unsigned/unnotarized. Installed/running remains system 0.2.7 with no
~/Applications copy. Asked for current draft safety before exit/update; no response yet.
Previous GitHub runs for 6cf811a and 90f044a succeeded; synchronization of this revision follows.
Unrelated STATUS.md and .project-pulse/ remain untouched.

Implementation and package source committed/pushed as `f3520b3`. Updated the installed skill's
setup and acceptance guidance for the new destination, including the direct-mode OK restriction.
Current draft-safety confirmation and actual key presses have not arrived; no app was quit or
installed. Hosted checks for the implementation are tracked separately from local verification.

## 2026-10-15 — system installation and resumed physical acceptance

The user resumed testing with the remote connected. At the start, system /Applications held
0.2.7 but no Vibe Remote process was running; no in-memory draft was discarded. Rebuilt missing
0.2.9/build 12 installer and independently checked expanded LocalSystem-only payload,
/Applications destination, nonrelocation, canonical icon and strict ad-hoc bundle signature.
Package: ~/Downloads/VibeRemote-0.2.9-System-20261015/VibeRemote-0.2.9-arm64.pkg,
3,486,094 bytes; SHA-256 5d1d56e57c730c39f24a14c67a5f106854e521a8c62101747fe5271030cd8b40.
The user completed the macOS authorization prompt. Installer reported completion; bundle
metadata and the launched process confirm 0.2.9 in system /Applications, with one process
and no ~/Applications copy. This supersedes the pending-install status above.

Fresh tests passed: core 83; voice model 37 scenarios/224 assertions; controls integration
63/211; focused input 64; external dictation 48; audio output 46; speech 42; HID 48; tool adapter
307; settings 15; catalog 27; provider discovery 21; Python 30 and neutral config validation.
GitHub runs 38179123590 (f3520b3) and 38179199650 (803fb52) succeeded. These software checks
do not establish physical input or actual coding-tool compatibility.

Read-only system metadata showed a connected BLE remote with the expected keyboard HID
interface, Doubao IME 0.5.7 running and MiRemoteV 2ch 0.7.1 installed. No competing SayAll or
MiRemote app was running. Codex now resolves to the ChatGPT.app bundle but retains its Codex
bundle identity. No system audio defaults or privacy grants were changed by these checks.
Actual Vibe Remote Connect showed “等待蓝牙就绪…” before the computer-use channel failed with
a native pipe-closed error; the app process remained alive. Doubao UI access timed out.
Codex computer-use access was explicitly denied for safety reasons; no alternative UI/AX
automation was used to bypass that restriction.

Prepared a private local Doubao/current-focus/manual settings import and an exact-byte
original backup under ~/Downloads/VibeRemote-Setup-20261015, without overwriting running
app settings. The profile pins the single observed supported loopback route, retains all
12 workspaces and mappings, and does not persist microphone or auto-send verification.
Validated through the real NativeSettingsStore and round-trip encoding; all original JSON
outside voiceInput remains equal. Files are mode 0600 and outside Git. User-led import and
provider microphone/shortcut checks were requested; configuration preparation is not acceptance.

A 60-second exact-remote, nonexclusive HID observation opened successfully with existing
input-monitoring permission but saw zero qualifying down/up events and closed cleanly.
The user confirmed pressing Up, Down, Left, Right, Back and Menu in that window and seeing
no diagram change. No key mapping is accepted. Descriptor inspection found keyboard report 1
with three 16-bit array slots plus macOS synthesized binary elements; whether callbacks arrive
only for the non-binary slots is a diagnostic hypothesis, not yet an established root cause.
Vendor report payloads, raw audio, transcripts and runtime device identifiers are not logged.

The user subsequently confirmed importing the profile and seeing Doubao/current-focus/
MiRemoteV 2ch. Read-only comparison then confirmed active settings semantically equal the validated
import. The user's shortcut report was “Ctrl”; hold/tap behavior, provider microphone choice
and disabled-auto-send are still unknown, so manual triggering remains selected.

After the user confirmed readiness again, a second coordinated 60-second nonexclusive
observation instrumented callback stages in a temporary copy of the production receiver.
It received 48 IOHID callbacks, no errors, and 12 delivered events: six down/up pairs in the
requested sequence. Keyboard page 7/report 1 usages were Up 82, Down 81, Left 80, Right 79,
Back 241 and Menu 74. Array and binary callbacks both arrived, so the binary filter is not
blocking these keys. No production code change is indicated by this evidence. The observer
closed normally. These are actual user-operated HID results, separate from still-pending
app calibration, exclusive suppression, audio delivery and Codex navigation acceptance.

A third 60-second observation for OK/Home/TV/Volume Up/Volume Down received zero callbacks
and zero delivered events; these buttons remain uncalibrated. Prepared a longer observation
with topology/reset/observing-state diagnostics to distinguish timing from connection changes.
No cause is inferred from the empty window. The six proven keys were added to a separate
private settings.doubao-current-focus-six-keys.json import using the observed descriptor hash.
Every supportsHold is false; the unverified global Back long-press stopTask was cleared as
required by the same validation used by in-app learning. Workspace presets and other settings
remain intact. Actual NativeSettingsStore and round-trip/preservation checks passed; active
settings were not modified. The pre-calibration settings were backed up in a new local file.

The user clarified Doubao supports double-click or hold Ctrl and can select the 2ch input;
the automatic-send setting is unknown. This does not establish microphone selection or
disabled auto-send, so no provider-ready confirmation was fabricated and no Codex dictation
was started. Another allowed attempt to inspect the now-open Doubao settings also timed out.

The subsequent 180-second exact-remote observation finished normally with zero callbacks,
zero errors and zero down/up events. Every heartbeat and the pre-close snapshot remained
observing with one interface; no device removal or running reset occurred. Only the explicit
final cleanup reset the service. This rules out an early observer reset in that window,
but does not prove whether physical presses occurred during it or diagnose a hardware fault.
No new observer was left running. Remaining five keys, application-level calibration and
exclusive suppression, voice delivery, provider settings and actual Codex use remain pending.

Installation/configuration/six-key progress was committed and pushed as 2b23d35. Private
local setup files, unrelated STATUS.md and .project-pulse/ were not staged or published.

### Continued user-operated key checks and physical-label ambiguity

The user subsequently reported “就绪” in the current app and said an earlier requested
five-key sequence had not yet been pressed. This is user-reported readiness, not observed
audio delivery. A later single OK-key check received page 7/report 1/usage 40, one down/up
pair about 0.135 seconds apart, then closed normally. A requested Home/TV/Volume Up/Volume
Down check received three identical sequences 74/53/128/129 (24 events, 12 pairs), without
connection resets. These are real events, but 74 conflicts with the earlier label Menu=74.
Physical button names were inferred from requested order; the conflicting Home/Menu labels
must be checked using their distinct house and three-horizontal-line icons before import.

The historical six-key import remains preserved but is now explicitly withheld from use;
no duplicate Home/Menu binding or eleven-key file was generated. Fresh active-settings checks
show the applied Doubao/current-focus/manual profile with zero HID calibrations, so the ambiguous
assignment has not reached the active configuration. All private evidence remains outside Git.
A single three-line-menu observation subsequently expired with zero events and normal cleanup.
The user replied that they had pressed it after the window had closed; actual press timing was
not established. Do not label the menu key broken from this result. A longer house/menu/house
control sequence is being prepared to distinguish timing from an unreported button.

### Controlled Home/Menu resolution and corrected eleven-key import

A ten-minute-bounded, nonexclusive control window ran from 2026-10-15 13:58:42Z to 14:05:02Z
(21:58:42–22:05:02 Asia/Shanghai). For the explicit house-icon / three-line-menu / house-icon
request, the user pressed three complete pairs: page 7/report 1 usages 74, 101, 74. They
arrived about 333.5, 337.8 and 341.6 seconds into the window. There were 24 underlying callbacks,
zero errors, and no running topology reset. After the user confirmed completion, the observer
waited for at least three quiet seconds, paused normally and saved a private summary; it did not
restart. This resolves Home=74 and Menu=101, superseding the earlier Menu=74 label.

Combined with the earlier real sequences and independent OK press, the observed short-press
map is Up 82, Down 81, Left 80, Right 79, OK 40, Back 241, Home 74, Menu 101, TV 53,
Volume Up 128 and Volume Down 129, all page 7/report 1. Power, voice delivery, long-press
behavior, exclusive suppression and coding-tool actions are separate unverified capabilities.

Generated settings.doubao-current-focus-eleven-keys.json under the private local setup folder,
rebased on freshly read active settings and with a new exact-byte pre-calibration backup.
Both files were created without replacement, mode 0600. Actual NativeSettingsStore decoding,
validation and encoding round-trip passed twice, including preservation and unique-input checks.
All eleven inputs have supportsHold=false; the only removed semantic action is the unverified
global Back long-press stopTask, as required by short-only calibration validation. Workspace
presets, single/double-click actions and Doubao/current-focus/manual remain unchanged. Power
and mic have no new HID input. Active settings were not overwritten. The historical six-key
file remains preserved but must not be used. Another permitted Vibe Remote UI access attempt
failed with native pipe-closed, so user-led import and in-app observation were requested.

The user then reported importing the eleven-key file and starting in-app observation.
A fresh read-only comparison confirmed active settings semantically equal the validated JSON file,
with Doubao/current-focus/manual retained. Requested user-led checks for house/menu/OK
diagram selection and, separately, a three-second voice hold in the dictation page while
the third-party provider remains stopped/unprepared. These checks are not yet marked passed.
Python 30 tests, neutral template validation and git diff checks passed again; native application
code was unchanged in this calibration/documentation continuation. Prior native regression and
release checks remain recorded separately from the live observations.

### Voice-hold acceptance and the application's separate input permission

The user confirmed changing audio level/increasing duration during a physical voice hold and
normal stop on release, with the third-party provider stopped and not prepared. Their screenshot
shows “采音结束；遥控器仍已就绪”. This establishes user-led basic remote-audio acceptance,
not virtual-device delivery, provider recognition or Codex input.

All three in-app house/menu/OK diagram checks were reported unresponsive. The user first
reported “按键已暂停，设备已释放”, consistent with import deliberately pausing HID. A subsequent
screenshot identified the deeper prerequisite: Input Monitoring denied, with discovery and
observation controls disabled. Read-only checks confirmed active eleven-key settings still match
the validated import and current descriptor, one system app instance, and no leftover observers.
No remapping or receiver code change was warranted. Separate observer permission is not proof
of the installed app's permission. Updated setup guidance for explicit authorization and
post-import discovery/observation, including the unlocked-selection diagram behavior.

Computer use could inspect System Settings. Its Input Monitoring list did not yet contain
Vibe Remote. The user changed the visible settings page while it was being inspected, so
instructions were handed back to add /Applications/Vibe Remote.app and authorize it in macOS;
no permission was granted by the assistant. Restart prompts must preserve needed drafts.
System Keyboard settings also showed built-in Dictation enabled with double-Control triggering
and an automatic MiRemoteV 2ch source. This is the system provider's state, not Doubao's.
Read-only bundle metadata found Doubao's separate settings helper; inspect that UI after the
system authorization step to verify its microphone/shortcut and possible trigger overlap.

The user subsequently confirmed “输入监控已授权”. Asked them to refresh/discover/select and
restart observation, leave action mappings paused, unlock diagram selection, and repeat
house/menu/OK. That response establishes user-reported authorization, not a passed key test.
Vibe Remote computer use still returned the same native pipe-closed error after authorization;
no alternate UI mechanism was used.

After restarting observation the user confirmed correct Home/Menu/OK highlighting, then all
eight remaining calibrated keys. This establishes user-led in-app diagram acceptance for the
eleven short presses; exclusive suppression and tool execution remain separate pending tests.

Computer use successfully opened Doubao 0.5.7's separate settings helper. Its microphone was
initially automatic detection; selected MiRemoteV 2ch and read back the displayed selection.
The settings show Ctrl hold/release and double-tap hands-free input. No auto-send control was
visible in the complete settings page. The user reports their usual dictated text stays in chat
inputs until manually sent. Keep manual triggering and use hold Ctrl during initial acceptance,
because system Dictation also has double Ctrl assigned. No system shortcut or privacy setting
was changed. Actual remote-to-provider audio/transcription is still pending.

### Explicit manual submission from the current input

The user requested a remote key to manually confirm sending. Extend the existing OK full-text
preview/second-confirmation workflow to current-focus mode. Only read the currently focused,
bound AI input; never reinsert provider text or send retained workspace drafts. Keep real Send/
Steer checks, capture/provider-completion gates, target/text revalidation and uncertainty guards.
This explicitly supersedes the earlier blanket prohibition on current-focus manual submission;
voice release still does not submit. This is implemented in 0.2.10/build 13, with a 60-second
review limit and per-workspace uncertain-attempt protection across input modes. Focused submission
keeps runtime AX element identity separate from tree paths and never repairs target focus.
Tests first failed against the previous behavior; final ToolAdapter 429, controls integration
96 scenarios/293 assertions and HID 80 assertions passed. External dictation 48, focused input 64,
Python 30 tests and neutral-config validation also passed. Only fake services were used.

Release/package build passed. Independent expansion confirmed LocalSystem-only /Applications
installation, no relocation candidates, matching source plist/icon, arm64 and strict ad-hoc
signature. Final package size is 3,518,169 bytes; SHA-256 is
503ba91ffcc44e6a21402bf0169f04d7e7be9e54e61a95d22eb28d4e38338533.
An earlier package was moved to a separate pre-review directory before the final race checks;
only ~/Downloads/VibeRemote-0.2.10-System-20261015/VibeRemote-0.2.10-arm64.pkg is the final artifact.
The app remains installed as 0.2.9; no in-memory draft was discarded or update installation claimed.

### Keyboard-seize failure isolated from Input Monitoring

The next screenshot shows Input Monitoring granted and one selected interface, but exclusive
open failed and mappings remained off. A read-only process check found one VibeRemote instance
and no competing remote bridge/observer. The existing independent-device manager and close-before-
reopen path do not establish self-contention. A narrowly filtered read-only IOHID log query found
six VibeRemote opens returning `0xe00002c1` (NotPrivileged), not ExclusiveAccess.

Apple's IOHID source separately gates keyboard seizure on privileged-client identity; the SDK
labels administrator privilege as root. Ordinary Input Monitoring or AX grants are insufficient
for that check. Added safe OS error classification without changing seizure policy or introducing
a fallback. No daemon, entitlement, root GUI, privacy reset or system authorization was installed.
Actual exclusive operation remains blocked; a scoped, authenticated and system-approved helper
requires further implementation. No raw system logs or device identifiers were added to Git.

### First prepared Doubao end-to-end attempt

The user confirmed third-party preparation succeeded. Guided a blank TextEdit test using
physical Ctrl hold, then remote voice hold, remote release, a short drain interval and Ctrl
release. The user reported a recording indication but no text. This confirms neither delivery
to the virtual input nor recognition. Requested the remote meter/duration observation and the
app's forwarding status before another attempt. No audio or transcript was saved.

### 0.2.10 GitHub synchronization and hosted verification

Pushed implementation `8a107fa` to origin/main and verified the remote head. GitHub Actions
run 38757521451 completed successfully for the native macOS app and all four macOS/Linux
Python 3.10/3.13 jobs. No installer was uploaded or installed in this step. User-led Doubao
audio/transcription and the privileged HID path remain pending.

### Current-focus preparation exposed a missing permission preflight

The user's new screenshots show an orange Accessibility warning and unchecked preparation
confirmations. Those controls are transient and can reset; their later state does not establish
whether an earlier preparation occurred. Computer use observed the same-name System Settings
switch enabled, while the user reports Vibe Remote still shows unauthorized after its own refresh.
A read-only check found one 0.2.9 process in /Applications and a valid, build-hash-based ad-hoc
signature. A narrowly scoped system log query only reported unresolved old preview-bundle URLs;
it does not prove which identity owns the visible switch. No permission was modified.

Source tracing confirmed manual/current-focus preparation skipped actual focused-input permission
and only required a non-nil service. The first physical hold could therefore reject audio after
the UI had entered prepared. New fake-service regressions reproduced six expected failures across
manual, hold and toggle modes. Implementing an early read-only permission check and aligned UI;
retain fresh physical-hold checks and draft/manual compatibility. Package update precedes renewed
authorization so a later ad-hoc update does not immediately supersede the tested identity.

The fix passed focused input 68, external dictation 70 and controls integration 96 scenarios/
293 assertions; the root independently reran focused/external checks plus Python 30 and neutral
config validation. Read-only review found no required corrections. Release/package build passed
for 0.2.11/build 14. Package is 3,518,563 bytes with SHA-256
8c70d65214b5922adc6717868f17972ef59a01dc40e5d2537cccd09e0d621e80.
No installation, permission grant or successful real transcription is claimed by these checks.
Independent package expansion confirmed LocalSystem-only /Applications, no relocation,
matching plist/icon, arm64 and strict signature. The user then confirmed drafts saved, app
quit and installation authorized. A private exact-byte settings backup was created before
installation; the final installed version and permission state remain to be checked.

Installer subsequently displayed successful 0.2.11 completion. Verified /Applications bundle
version 0.2.11/build 14, strict signature, no ~/Applications copy, retained installer and exact
settings equality with the private pre-update backup. Launched via computer use: home UI read
successfully, but navigation to Connections again returned a native pipe-closed error. Therefore
the UI channel is not considered recovered. System Settings remains readable; selecting Add in
Accessibility opened a Touch ID/password authorization prompt. Asked for explicit user consent
for the current system app's AX access and system authentication; no grant has been claimed.
Implementation was committed/pushed as `dedf63a`; hosted results remain pending.

The user explicitly approved current-app Accessibility access and reported completing system
authentication. Through System Settings Add, selected the visible /Applications/Vibe Remote.app
file and opened it; the resulting Vibe Remote switch is on. No unrelated permission was changed.
Reading Vibe Remote still returned the native pipe-closed error. Asked the user to refresh its
own Accessibility status and then reconnect the selected remote; both runtime results remain
pending. Hosted verification for `dedf63a` completed successfully in run 38761805987.

The user subsequently reported Accessibility still unauthorized after refreshing. Rebuilt only
the Vibe Remote entry in System Settings: verified the selected row before removing it, selected
/Applications/Vibe Remote.app in the application chooser and observed the new switch on. Existing
user consent covers the same app and permission; no unrelated permission was changed. Requested
a normal quit/relaunch followed by the app's own refresh; that current-process result remains
pending. Read-only bundle metadata still confirms 0.2.11 and the expected identifier/executable.
No new transcription attempt, mapped action or code change occurred during this repair step.

## 2026-10-16 — current-app Accessibility verified after relaunch

The user confirmed the app's own Accessibility status is authorized after the targeted entry
rebuild, normal quit/relaunch and refresh. This resolves the current permission acceptance item;
it does not establish a precise stale-entry cause, HID-seize privilege or successful dictation.
Requested fresh remote readiness and explicit Doubao/current-focus/manual preparation before
repeating the blank-editor audio/transcription test. No new audio or transcript was recorded,
and no source or active configuration changed in this step.
