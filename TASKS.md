# Tasks

Updated: 2026-10-05 (Asia/Shanghai).

## Current direction: our own macOS app

The user explicitly requested self-developed software, referencing MiRemote's approach
without using its app. The earlier SayAll installation path is superseded. The current
native application does not require a third-party application or driver. A later
read-only check now finds SayAll and MiRemoteV2ch installed; their installation was
not observed in this development turn and they are not part of the native build.

Repository: https://github.com/BreezeLife/vibe-remote-skill.
Native design: docs/NATIVE-DESIGN.md. Usage: docs/NATIVE-SETUP.md.
Local artifact: ~/Applications/Vibe Remote.app (0.1.1, arm64, local ad-hoc signature).
During the earlier 0.1.1 upgrade the user confirmed no drafts needed preservation; both old
copies exited normally. The current instance now contains a new draft (see 0.2 below).
One 0.1.1 instance is running from ~/Applications, with its signature verified after launch.
Hosted verification: https://github.com/BreezeLife/vibe-remote-skill/actions.

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
- [ ] Synchronize the implementation and verification records to GitHub.
- [ ] Install 0.2 locally after preserving the current 0.1.1 in-memory draft.

Installer: ~/Downloads/VibeRemote-0.2.0-20261005-163035/VibeRemote-0.2.0-arm64.pkg
(661,083 bytes; version 0.2.0 / build 3). App is ad-hoc signed; installer remains unsigned
and unnotarized. Implementation plan: docs/superpowers/plans/2026-10-05-visual-controls.md.
The installed 0.1.1 package does not yet include these features. Its current window contains
new in-memory draft text, so it was left running. No draft content was copied into records.
The independent preview requested no permissions, opened no tool conversation, and was closed
without changing the installed application. A passive HID inventory found no matching current
interface; hardware calibration was not performed.

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
