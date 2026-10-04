# Tasks

Updated: 2026-10-04 (Asia/Shanghai).

## Current direction: our own macOS app

The user explicitly requested self-developed software, referencing MiRemote's approach
without using its app. The earlier SayAll installation path is superseded. The current
native application does not require a third-party application or driver. A later
read-only check now finds SayAll and MiRemoteV2ch installed; their installation was
not observed in this development turn and they are not part of the native build.

Repository: https://github.com/BreezeLife/vibe-remote-skill.
Native design: docs/NATIVE-DESIGN.md. Usage: docs/NATIVE-SETUP.md.
Local artifact: build/Vibe Remote.app (0.1.0, arm64, local ad-hoc signature).
Hosted verification: https://github.com/BreezeLife/vibe-remote-skill/actions.

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
- [ ] Physically verify Bluetooth permission, pairing/ATVV readiness and real remote audio.
- [ ] Physically verify language support, recognition permissions and two consecutive holds.
- [ ] Physically verify cancellation/disconnection cleanup and explicit draft copying.

Hardware checks remain unchecked regardless of software build/test results. The current
app does not capture the Mac microphone, expose a virtual input or intercept general
HID keys. Other remote buttons may continue their normal macOS behavior.

## Subsequent integration work

- [ ] Develop our own virtual microphone output to support Doubao / Typeless.
- [ ] Observe real device HID events and implement the existing fixed button intentions.
- [ ] Add an explicit workspace picker and observed APP/CLI target adapters.
- [ ] Implement guarded insertion/submission only after verifying the actual AI input.
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
The latest doctor scan finds Codex 26.930.21537, Doubao 0.5.7, SayAll 1.9.21 and
MiRemoteV2ch.driver. It still finds no Bluetooth candidate, so current remote connectivity
is unconfirmed. No native-app audio/TCC acceptance has been observed. Quit any other
remote bridge before physically testing this app to avoid competing BLE clients.

Local config remains ignored. Preserve unrelated untracked STATUS.md and .project-pulse/.
