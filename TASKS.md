# Tasks

Updated: 2026-10-09 (Asia/Shanghai).

## Current direction: our own macOS app

The user explicitly requested self-developed software, referencing MiRemote's approach
without using its app. The earlier SayAll installation path is superseded. The current
native application does not require a third-party application or driver. A later
read-only check now finds SayAll and MiRemoteV2ch installed; their installation was
not observed in this development turn and they are not part of the native build.

Repository: https://github.com/BreezeLife/vibe-remote-skill.
Native design: docs/NATIVE-DESIGN.md. Usage: docs/NATIVE-SETUP.md.
Observed on 2026-10-09: /Applications/Vibe Remote.app, 0.2.3 / build 6, matching the user's
About screenshot and actual window. The current-user copy is absent. The 0.2.4 icon update
is ready; the system Installer is awaiting administrator authorization. Hardware and tool
capability acceptance remain separate.
Hosted verification: https://github.com/BreezeLife/vibe-remote-skill/actions.

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
