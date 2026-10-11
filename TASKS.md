# Tasks

Updated: 2026-10-12 (Asia/Shanghai).

## Current direction: our own macOS app

The user explicitly requested self-developed software, referencing MiRemote's approach
without using its app. The earlier SayAll installation path is superseded. The built-in
Apple Speech path does not require a third-party application or driver. A later
read-only check now finds SayAll and MiRemoteV2ch installed; their installation was
not observed in this development turn and they are not part of the native build.

Repository: https://github.com/BreezeLife/vibe-remote-skill.
Native design: docs/NATIVE-DESIGN.md. Usage: docs/NATIVE-SETUP.md.
Observed on 2026-10-12: system /Applications/Vibe Remote.app is 0.2.7 and a
process runs from that system path; no ~/Applications copy. A user-authorized connection
in the installed app reached ATVV ready at 16 kHz. System BLE and the Xiaomi HID interface
were also observed. A bounded 60-second remote-only HID observer saw zero key events;
button mapping, audio frames and transcription have not yet passed physical acceptance.
The cause of the earlier recurring pairing loss remains unconfirmed. GitHub checks for
6cf811a (run 38160177209) and 90f044a (run 38160245199) completed successfully.
Hosted verification: https://github.com/BreezeLife/vibe-remote-skill/actions.

## 0.2.9 — current-focus voice input

Implementation `f3520b3` is pushed to origin/main; local verification is complete.
User explicitly confirmed direct input at the current cursor, without automatic sending.
This supersedes the earlier draft-first preference below; old configuration retains draft mode.

- [x] Independent provider/destination configuration; strict migration preserves existing settings.
- [x] Native per-hold focus capture, selected-text replacement only, exact target/text/selection
  recheck and single-attempt readback. No Enter, clipboard fallback or automatic submission.
- [x] Preserve failed/interrupted text separately from workspace drafts; block a new utterance
  until it is handled, and block bound draft insert/send/confirm actions in direct mode.
- [x] Distinguish true release from manual stop, watchdog, disconnect and shutdown before
  finalization. External interruption cannot issue another toggle ending gesture.
- [x] Third-party direct mode without receiver activation, explicit disabled-auto-send confirmation
  even for manual trigger, current field checks, and explicit provider-finished rearming.
- [x] Regression checks: core 83; voice model 37 scenarios / 224 assertions; controls integration
  63 scenarios / 211 assertions; focused input 64; external lifecycle 48; audio 46; speech 42;
  HID 48; tool adapter 307; settings 15; catalog 27; provider discovery 21; Python 30, all passed.
  Neutral config validates. Actual app build and final package build passed.
- [x] Fake-service UI renders at 740 pt inspected; direct settings, prepared/review and native
  retained-text views fit without clipping. These are not real target input tests.
- [x] Independently expand 0.2.9/build 12: LocalSystem-only, /Applications, nonrelocation,
  canonical icon identity and strict ad-hoc app signature.
- [ ] Install after current draft safety is confirmed, then select current-focus mode locally.
- [ ] Real key sequence and audio-frame test with user-operated remote; the first observation
  window had no key events. Never label injected events as physical acceptance.
- [ ] Real plain-editor insertion/selection, focus-loss retention, Doubao microphone/shortcut
  and provider completion test. Codex/Claude/WorkBuddy direct input remains unverified.

Package: ~/Downloads/VibeRemote-0.2.9-System-20261012/VibeRemote-0.2.9-arm64.pkg
(3,486,091 bytes; arm64; app ad-hoc signed, installer unsigned/unnotarized).
SHA-256: 6388ce473e2b9b6f0a268d739947cf4e9063f18855a2f903cd9b33edcdddeae5.
Installed/running remains 0.2.7. The app UI channel later returned a native pipe-closed error;
no alternate UI automation was used. No system audio defaults, permissions, provider shortcuts
or real settings were changed. Current update confirmation is pending.

## 0.2.8 — third-party voice input configuration

Implementation commit `6cf811a` is pushed to origin/main; its hosted checks succeeded.
local verification and installer checks below are complete. Installation/physical acceptance remain pending.

- [x] Add native profiles for Typeless, Doubao IME, Wispr Flow, Superwhisper, macOS Dictation
  and custom providers. Preserve older settings, button/workspace profiles and drafts.
- [x] Detect installed provider bundles, including system/user Input Methods; distinguish Doubao
  IME from the chat client. Provide official setup links and a user test guide.
- [x] Implement explicit installed-loopback output selection, mono resampling, pinned AUHAL output,
  bounded buffering, device checks, drain/cancel and stale-callback guards. No driver/default changes.
- [x] Manual default plus optional configured hold/toggle gestures; own focused receiver, no Enter
  or submit, locked draft destination and explicit provider-finished review before appending.
- [x] Fix review findings: reject settings persistence during capture; invalidate preparation
  confirmations after changing provider app; halt the gesture immediately on asynchronous route loss.
- [x] Final regression/build/package verification passed.
- [x] 80 core tests; 26 voice-model scenarios/182 assertions; 21 external lifecycle, 46 audio,
  21 provider discovery, 42 speech, 48 HID, 307 tool, 15 settings, 27 catalog checks; Python 30 and
  neutral configuration validation. Controls integration: 61 scenarios / 197 assertions.
- [x] Isolated SwiftUI render at 740 pt settings / 680 pt receiver inspected; fixed a truncated guide line.
- [x] Independent package expansion verified 0.2.8/build 11, system Applications/LocalSystem-only,
  nonrelocation, canonical icon equality and strict ad-hoc signature.
- [ ] Install after current in-memory drafts are safe to close; system /Applications only.
- [ ] User verifies provider mic choice/shortcut, true remote audio, complete Chinese/English text,
  manual/hold/toggle operation as applicable, focus/device loss and retained old draft.
- [ ] Our own virtual microphone driver and broader device compatibility remain future work.

User chose third-party output first in Vibe Remote, then review/append. Metadata inspection found
Doubao IME 0.5.7 and MiRemoteV 2ch installed; no live provider or remote-audio acceptance is claimed.
Guide: docs/VOICE-PROVIDERS.md.
Package: ~/Downloads/VibeRemote-0.2.8-System-20261012/VibeRemote-0.2.8-arm64.pkg
(3,442,686 bytes; arm64; app ad-hoc signed, package unsigned/unnotarized).
SHA-256: 0f82be3c0da4b3ecb9348e33c7fce3bf04be106fd633d378680e476c2c250626.
Installed/running remains 0.2.7; update awaits current draft-safety confirmation. No settings,
input source, system default audio device, real recording or provider hotkeys were changed.

## 0.2.7 — explicit pairing-loss recovery

- [x] Classify the exact CoreBluetooth pairing-loss error in connection/disconnection and ATVV callbacks.
- [x] Cancel automatic retries for that failed pairing while preserving ordinary bounded reconnect,
  selection, user preference, settings and drafts. Explicit retry after repair remains available.
- [x] Add device-scoped recovery state and an in-app three-step system re-pair guide; distinguish
  everyday wake/reconnect, pairing mode, app Forget Selection and macOS Forget Device.
- [x] Pass 70 core tests, 24 model scenarios/170 assertions, 60 integration scenarios/190 assertions,
  307 adapter assertions, 30 Python tests and neutral configuration validation; recovery regressions
  failed before fixes.
- [x] Independent review and 740 pt fake-service UI render passed; no actual radio/permissions used.
- [x] Release/package build and independent expansion passed: 0.2.7/build 10, strict signature,
  source icon, /Applications payload, nonrelocation and LocalSystem-only domain.
- [x] Correct the prior CI delayed-navigation fixture: observed a 150 ms first snapshot against
  an unrealistically short 100 ms budget, then passed with the production 2 second budget.
- [ ] Install the latest package (0.2.9 supersedes this package) when current drafts are safe.
- [ ] User confirms system re-pair restores ATVV readiness and normal wake/reconnect works afterward.
- [ ] Determine recurring bond-loss trigger (pairing chord, another host, or normal wake); do not
  describe the root cause as resolved based only on error handling tests.

Package: ~/Downloads/VibeRemote-0.2.7-System-20261011/VibeRemote-0.2.7-arm64.pkg
(3,278,394 bytes; arm64; system /Applications only).
SHA-256: ead5202e7da703576514c3f182afe15b3820b5e053d2e4e8a6e7012791f034d5.
The app is ad-hoc signed; installer unsigned/unnotarized. System Bluetooth pairing was not changed.

## 0.2.6 — Codex one-click setup, conversations and test guidance

- [x] Discover the installed Codex by bundle identity and read its bounded local conversation
  metadata through its bundled CLI. Only initialize/initialized/thread/list are allowed;
  no conversation bodies, resume, turn/start or turn/steer calls.
- [x] One-click setup prepares the project/session directory and defaults. Selecting a session
  creates its own draft identity, opens the canonical link and attempts verified input binding.
- [x] Managed preset: up/down switch sessions in the current project; left/right switch projects.
  Boundaries do not wrap. Existing manual profiles, draft identities and custom actions survive.
- [x] First OK inserts and reviews exact text; second explicit confirmation submits. Verified
  same-composer Steer takes precedence over normal Send. Unknown state blocks submission.
- [x] Keep per-session receipts, invalidate review on target/draft/capture changes, and block
  repeated uncertain writes/submissions. After confirmed submission, require deliberate empty
  draft reset before the next instruction so new dictation cannot resend an old prefix.
- [x] Add in-app permissions, navigation, dictation, confirmation and Steer test guidance;
  show metadata/configuration separately from target-specific observed checks.
- [x] Tests: 69 core; 42 Speech; 22 model scenarios/159 assertions; 48 HID; 15 settings;
  307 tool-adapter; 27 catalog assertions; 60 integration scenarios/190 assertions;
  30 Python tests and default configuration validation, all passed.
- [x] Independent review, final release/package build, diff checks and isolated view renders
  (740 pt pages and 960 pt whole window) passed. GitHub workflow includes catalog checks.
- [x] Independently expand package and verify 0.2.6/build 9, LocalSystem-only domain,
  /Applications payload, disabled relocation, canonical icon bytes and strict app signature.
- [x] Later verified 0.2.6/build 9 on disk and process path /Applications on 2026-10-11.
- [ ] User-led real Codex acceptance: two sessions, independent drafts, focus, two-step Send,
  running-task Steer and capability-failure fallback. Computer-use access to Codex was denied;
  injected fixture results are not evidence of real UI compatibility.
- [ ] Physical remote acceptance: pairing, HID exclusivity/no event pass-through, voice holds.
- [ ] Add equivalent managed conversation adapters for Claude and WorkBuddy after Codex acceptance.

Package: ~/Downloads/VibeRemote-0.2.6-System-20261010/VibeRemote-0.2.6-arm64.pkg
(3,268,257 bytes; 0.2.6/build 9; LocalSystem only; /Applications).
SHA-256: f7f250c033791603fc1b6a4d5025032090a371455ae1bd21eccfd12c7ecab88a.
App is ad-hoc signed; package remains unsigned/unnotarized. The installed user's settings,
permissions and remembered remote were not modified by development checks.

## 0.2.5 — find, choose and reconnect a remote

- [x] Add a shared nearby-remote picker to dictation and connection settings.
- [x] Discover ATVV/remote-specific candidates, merge by UUID and distinguish broadcast,
  system-connected and remembered observations; unknown devices never become ready by selection.
- [x] Connect only the selected remote; remember it locally and provide explicit scan/stop/forget.
- [x] Retry unexpected idle disconnection of a verified remote up to three times (2/5/10 sec).
  Manual stop/disconnect, capture-time loss, protocol failures and disabled Bluetooth remain stopped.
- [x] Pass 62 core tests; 22 model scenarios / 159 assertions; 46 integration scenarios /
  149 assertions; 42 Speech, 48 HID, 15 settings, 144 adapter assertions; 30 Python tests
  and neutral config validation. Reconnect-during-capture regression observed before model fix.
- [x] Independent code review found no blocker. Release build, plist, signature and diff checks passed.
- [x] Render production picker empty/5 candidates/connecting/ready and both full pages at 740 pt
  using fake services; no horizontal overflow, list remains bounded to three visible rows.
- [x] Build and independently expand package: version/build, LocalSystem-only domain,
  /Applications payload, canonical enlarged icon bytes and strict app signature match.
- [ ] Finish system installation after the pending administrator dialog, then verify running version/icon.
- [ ] Physically test discovery, deliberate selection, system pairing, idle reconnection and two voice holds.

Package: ~/Downloads/VibeRemote-0.2.5-System-20261009/VibeRemote-0.2.5-arm64.pkg
(3,077,318 bytes; 0.2.5/build 8; LocalSystem only; /Applications).
SHA-256: 8f50e1fc1ea8f3279529a7833b8b2e582f0ded185dfce98733eb2f6a195b980f.
App remains ad-hoc signed and package unsigned/unnotarized. No real scan, pairing, permissions,
HID takeover or audio test was performed by the development checks. User settings and drafts preserved.

## Latest icon design proposal

- [x] Generate the requested remote close-up + prominent Vibe professional icon.
- [x] Save the 1254 × 1254 PNG with alpha and full prompt in Packaging/Artwork/Proposals.

The exact close-up design is now canonical in 0.2.4; the earlier 0.2.3 package omitted it.

## 0.2.4 — ship the enlarged remote + Vibe icon

- [x] Promote the exact close-up PNG; preserve the full-remote variant and generation prompts.
- [x] Regenerate ICNS, inspect 64/128 pixel representations, and verify all ten sizes.
- [x] Build and independently verify package metadata, icon bytes, signature and checksum.
- [x] Pass 30 Python tests, neutral config validation and diff checks; no runtime source changed.
- [x] Inspect the unbound draft and all 9 workspace drafts as empty, quit 0.2.3 and back it up.
- [ ] Complete macOS Installer administrator authorization, then verify installed About icon/version.

Package: ~/Downloads/VibeRemote-0.2.4-System-20261009/VibeRemote-0.2.4-arm64.pkg
(3,009,575 bytes; 0.2.4/build 7; LocalSystem only; /Applications).
SHA-256: 5d25293c148058e74e7259ac0c4db4e3fd789bd86657817ff6bbcd115de4ba19.
Backup: ~/Library/Caches/VibeRemote/PreviousVersions/VibeRemote-0.2.3-20261009-093253.app.backup.
The installed 0.2.3 belongs to root; direct replacement was denied before changing it.
The standard system Installer is open at authorization. User settings remain unchanged.

## 0.2.3 — Pro 2 button layout and tool defaults

- [x] Match all 13 physical keys: power/mic, continuous d-pad, back/home/menu, volume rocker/TV.
- [x] Add Codex, Claude Desktop and WorkBuddy default schemes, covering both WorkBuddy identities.
- [x] Store workspace action overrides separately from shared HID calibration; retain legacy configuration.
- [x] Preserve drafts, bindings and other workspaces when applying presets or resetting actions.
- [x] Drop old-workspace events remaining in an already resolved gesture batch after a switch.
- [x] Pass 54 core tests; 46 integration scenarios / 149 assertions; 15 store and 144 adapter assertions;
  all 30 Python tests and neutral config validation. Regression failures observed before both fixes.
- [x] Review production-view renders at 940/1040 and minimum 740 point widths; no overlap/overflow.
  These use isolated fake services and configuration, not actual tool/device state.
- [x] Build and independently verify 0.2.3 / build 6 system-domain package, payload and signature.
- [x] Later observed user-installed 0.2.3 on 2026-10-09; disk metadata and About window agree.
- [ ] Physically verify all keys and actual Codex/Claude/WorkBuddy bindings and actions.

Artifact: ~/Downloads/VibeRemote-0.2.3-System-20261008/VibeRemote-0.2.3-arm64.pkg
(2,713,828 bytes; arm64, macOS 13+; LocalSystem only; /Applications).
SHA-256: 0a401aa0a130d13cd9f964335332351f64aef4278c7b426efdc0bbd20b016dc7.
Package is unsigned/unnotarized with an ad-hoc-signed app. At delivery on 2026-10-08, the
running system bundle remained 0.2.2 and native inspection failed, so no app was quit or
replaced then. The user subsequently installed 0.2.3. New workspace buttonActions require
0.2.3+; old configuration stays readable, and pre-change settings are backed up when saved.

## 0.2.2 — shared Applications and Pro 2 + Vibe icon

- [x] Move the verified app to the shared /Applications directory requested by the user.
- [x] Make future packages LocalSystem-only, retain identity/version/nonrelocation/close checks.
- [x] Keep development builds in a user cache; update installation docs and CI package step.
- [x] Generate the requested Pro 2 reference icon and prominent Vibe wordmark; preserve earlier designs.
- [x] Build and independently verify system-domain installer, payload path, final icon, signature and SHA.
- [x] Pass all 30 Python tests, neutral config validation and shell/plist/diff checks; code review passed.
- [x] After the user confirmed drafts saved, install 0.2.2 into /Applications with a recoverable old bundle.
- [x] Open the actual system app and observe its 0.2.2 window; verify no personal Applications duplicate.

Artifact: ~/Downloads/VibeRemote-0.2.2-System-20261008-202916/VibeRemote-0.2.2-arm64.pkg
(2,651,235 bytes; 0.2.2 / build 5; arm64, macOS 13+). Installer domain: LocalSystem only.
The app remains ad-hoc signed; package unsigned/unnotarized. The local update deployed the
verified expanded payload into the writable system directory after preserving the old bundle;
it did not run a root Installer transaction or create a new system package receipt.
Backup: ~/Library/Caches/VibeRemote/PreviousVersions/VibeRemote-0.2.1-20261008-204332.app.backup.
Native settings remain per-user and were not modified. No privacy permissions were granted.

## 0.2.1 — app icon and configuration guidance

- [x] Generate an original remote/waveform app icon; preserve transparent source artwork.
- [x] Convert 10 standard icon representations into ICNS and include it in the app bundle.
- [x] Explain workspace fields, accessibility authorization, input/title learning and send gates.
- [x] Build release and installer; verify expanded icon matches source ICNS, all 10 sizes,
  bundle version/icon declaration, strict app signature and independent archive checksum.
- [x] Pass all 30 Python checks, neutral config validation, shell/plist syntax and diff checks.
- [x] Verify the user-installed 0.2.1 bundle/receipt; later superseded locally by 0.2.2 above.

Artifact: ~/Downloads/VibeRemote-0.2.1-20261008-194907/VibeRemote-0.2.1-arm64.pkg
(2,488,333 bytes; version 0.2.1 / build 4). App is ad-hoc signed; package unsigned/unnotarized.
This historical package uses the current-user ~/Applications destination. Use the new
0.2.2 system package above for subsequent installations.
No runtime voice, button or AX adapter behavior changed in 0.2.1.

## 0.2 — visual buttons and coding tools

The user requested SayAll-inspired visual button configuration and Codex/Claude/WorkBuddy
support. Design: docs/superpowers/specs/2026-10-05-visual-controls-design.md.

- [x] Research official SayAll interactions/licensing, local app identities and native HID boundaries.
- [x] Prepare a concrete desktop-first design, with tool capabilities verified separately.
- [x] User approved the desktop-first design and instructed implementation.
- [x] Implement visual button/gesture editing, configuration copy/import/export and four sidebar pages.
- [x] Add Codex, Claude Desktop, WorkBuddy and WorkBuddy AI presets plus custom .app bindings.
- [x] Add device-scoped HID learning, all-interface exclusive capture, session validation and pause/release.
- [x] Add workspace draft isolation and guarded AX focus, append/readback, reviewed send, stop and scroll.
- [x] Add semantic shortcut selection/recording, explicit Codex thread opening and unsent new-draft prefilling.
- [x] Pass core, Speech, voice-model, HID, tool, storage, controller and Python automated checks.
- [x] Launch a separate 0.2 preview and observe its initial native window and sidebar controls.
- [ ] Complete interactive UI inspection (native automation pipe disconnected after initial observation).
- [ ] Verify physical raw-key suppression, gesture calibration and ATVV coexistence.
- [ ] Verify each actual tool's AX input/focus/send/stop capabilities; presets alone do not establish support.
- [x] Build and verify the 0.2 installer, including payload signature and independent SHA-256 check.
- [x] Synchronize implementation commit 544887d to GitHub main without force.
- [x] Pass all five hosted jobs for implementation commit 544887d, including native tests,
  release app and installer verification: https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37284339661.
- [x] Verify 0.2.0 installed metadata after the user installed it; current location recorded above.

Installer: ~/Downloads/VibeRemote-0.2.0-20261005-163035/VibeRemote-0.2.0-arm64.pkg
(661,083 bytes; version 0.2.0 / build 3). App is ad-hoc signed; installer remains unsigned
and unnotarized. Implementation plan: docs/superpowers/plans/2026-10-05-visual-controls.md.
During 0.2 development on 2026-10-05, the installed 0.1.1 window contained new in-memory
draft text, so it was left running. No draft content was copied into records. The independent
preview requested no permissions, opened no tool conversation, and was closed without changing
the installed application. That passive HID inventory found no matching interface; hardware
calibration was not performed. The subsequent installed 0.2.0 metadata is recorded above.

## 0.1.1 — installable package

Latest regenerated package (2026-10-05 10:58, Asia/Shanghai):
~/Downloads/VibeRemote-rebuild-20261005-105806/VibeRemote-0.1.1-arm64.pkg.
Version remains 0.1.1 / build 2; the regenerated archive passed payload signature,
current-user-only domain and SHA-256 checks. The original installed package is retained.

- [x] Build a standard current-user installer and SHA-256 checksum:
  ~/Downloads/VibeRemote-0.1.1-arm64.pkg (Apple Silicon, macOS 13+).
- [x] Restrict the installer to ~/Applications, disable relocation, require closing the
  app, enforce strict bundle identity and check existing versions before replacement.
- [x] Verify the product's sole domain, supported architecture/minimum OS, must-close
  metadata, and signature of the expanded app payload.
- [x] Install the actual .pkg without sudo; receipt records user volume and Applications.
- [x] Reopen the installed 0.1.1 app; confirm one process, current-user ownership and valid
  signature after launch. Package size: 148,738 bytes.
- [x] Add repeatable packaging and payload verification to the native CI workflow.

The installer is unsigned and unnotarized; its contained app has a local ad-hoc signature.
This local installation does not complete clean-machine distribution or hardware acceptance.

## 0.1.1 — voice key disconnect repair

- [x] Trace the reported immediate disconnect and “已手动停止” screenshot to the automatic
  recognition-failure path incorrectly calling manual BLE stop.
- [x] Keep BLE audio/signal observation alive after a missing permission, start failure,
  early final result or recognition error; retry recognition only on the next hold.
- [x] Preserve cancellation until physical release, including after early Speech completion.
- [x] Read actual app Speech authorization at launch and each new hold; show recognition
  issues by the connection panel and distinguish manual stops from capture timeouts.
- [x] Pass 15 fake-service model scenarios / 111 assertions, after reproducing both the
  original disconnect bug and an early-completion cancellation regression.
- [x] Recheck 25 core tests, 42 Speech assertions, 30 Python tests and template validation.
- [x] Build 0.1.1 release and verify its local signature; add model regressions to CI.
- [x] Confirm draft preservation with the user, exit duplicate instances and launch installed 0.1.1.
- [x] Publish the fix as 73bb098 and pass all five hosted jobs, including model regressions:
  https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37245721494.
- [ ] Physically repeat press/release twice and confirm audio, exact Speech capability/error,
  and draft behavior with the repaired app.

The user's report confirms a visible failure during physical use, not its precise Speech
cause. The previous app conflated authorization and recognition failure with manual stop.
Synthetic tests establish the repaired logic; they do not establish working remote audio
or on-device language support on this Mac.

## Native milestone 0.1

- [x] Create a SwiftPM macOS 13+ app with a SwiftUI draft window and menu-bar entry.
- [x] Implement direct ATVV discovery, subscription acknowledgement and capability negotiation.
- [x] Decode remote 8/16 kHz IMA ADPCM, isolate stream synchronization and report signal level.
- [x] Feed Apple Speech from remote PCM, require local recognition by default, make online
  recognition opt-in, and bound finalization while ignoring stale callbacks.
- [x] Preserve drafts, append subsequent utterances, cancel only the current utterance,
  and provide explicit copying without key injection or automatic submission.
- [x] Compile the complete native executable in debug mode on this Apple Silicon Mac.
- [x] Pass 25 native core tests, 42 Speech PCM/session assertions and all 30 Python tests.
- [x] Build the release .app and verify its local ad-hoc signature.
- [x] Synchronize native milestone commit 2960169 to public GitHub main.
- [x] Pass the native app and all four Python hosted jobs for that implementation:
  https://github.com/BreezeLife/vibe-remote-skill/actions/runs/37212405473.
- [x] Verify the local ~/Applications bundle signature and refusal to overwrite unrelated apps.
- [ ] Physically verify Bluetooth permission, pairing/ATVV readiness and real remote audio.
- [ ] Physically verify language support, recognition permissions and two consecutive holds.
- [ ] Physically verify cancellation/disconnection cleanup and explicit draft copying.

Hardware checks remain unchecked regardless of software build/test results. The installed 0.1.1
app does not capture the Mac microphone, expose a virtual input or intercept general
HID keys. Version 0.2 adds explicit device-scoped input; its physical acceptance remains pending.

## Subsequent integration work

- [ ] Develop our own virtual microphone output to support Doubao / Typeless.
- [ ] Physically verify the implemented HID mappings against real device events.
- [x] Add a native workspace picker and guarded desktop APP adapter.
- [ ] Add a separate native CLI runtime adapter; existing Python/tmux helper remains available.
- [x] Implement guarded insertion/submission with fresh AI input and full-text review checks.
- [ ] Complete actual tool acceptance for insertion/submission.
- [ ] Add signed/notarized distribution and repeatable clean-machine acceptance.

## Supporting skill — retained and verified

- [x] Provider profiles, state-guarded planner and exact-session local/SSH tmux switching.
- [x] Chinese/English docs, MIT publication, neutral configuration and skill installer.
- [x] 30 Python unit tests and neutral template validation passed again on 2026-10-04.
- [x] Installed skill symlink points to this canonical checkout; original recovery copy retained.

The Python planner still reports executes:false. Saved bindings do not establish current
focus or recording state. Shell/unknown destinations cannot be submitted to.

## Local environment and preservation

This Mac has macOS 15.7 / arm64, Swift 6.1.2 and Xcode Command Line Tools, without XCTest.
A standalone test script exercises the same core tests; full Xcode CI uses XCTest too.
The 2026-10-04 doctor scan found Codex 26.930.21537, Doubao 0.5.7, SayAll 1.9.21 and
MiRemoteV2ch.driver, but no Bluetooth candidate. On 2026-10-05 the user reported connecting
and then immediately disconnecting on the voice key. Process inspection found two running
0.1.0 Vibe Remote copies (cloud-workspace build and ~/Applications) and no matching SayAll
or remote bridge process. After user confirmation, both were replaced by one running
0.1.1 instance from ~/Applications. Native audio/TCC acceptance remains incomplete.
Use one app instance, and quit competing remote bridges before the next physical test.

Local config remains ignored. Preserve unrelated untracked STATUS.md and .project-pulse/.
