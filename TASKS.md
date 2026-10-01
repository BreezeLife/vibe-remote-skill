# Tasks

Updated: 2026-10-02 (Asia/Shanghai).

## Implemented and checked

- [x] Define provider adapters, fixed intentions, APP task and CLI window contracts.
- [x] Write config template, event planner, tmux selector, installer, and acceptance guide.
- [x] Preserve the original local commits and recover the project into Project-VibeRemote.
- [x] Recover the final request: publish publicly on GitHub and provide practical usage docs.
- [x] Add Chinese/English README, setup guide, MIT license, and GitHub Actions checks.
- [x] Fix unknown recording state permitting actions and repeated workspace-picker events.
- [x] Verify 30 unit tests, skill metadata, neutral/local templates and the Bluetooth diagnostic.
- [x] Update the installed skill link to the canonical checkout while retaining the old copy.
- [x] Publish the public MIT repository and verify main synchronization and all four hosted checks.

Repository: https://github.com/BreezeLife/vibe-remote-skill.
Code-publication checks passed on Linux/macOS with Python 3.10/3.13:
https://github.com/BreezeLife/vibe-remote-skill/actions/runs/36899566684.
The local working tree is clean after the final status synchronization; local configuration
remains ignored. The installed skill points to this project's source.

## Observed environment

Read-only inspection found the Xiaomi voice remote connected in macOS's Bluetooth inventory.
This confirms Bluetooth connection only; audio and physical button behavior remain untested.

| Dependency | Observed result |
| --- | --- |
| Codex | Installed, com.openai.codex, 26.928.31416 (app filename is ChatGPT.app) |
| ChatGPT | Installed, com.openai.chat, 1.2026.160 (ChatGPT Classic.app) |
| Doubao input method | Installed, com.bytedance.inputmethod.doubaoime, 0.5.7 |
| Typeless / SayAll / MiCoding / MiRemoteVoice apps | Not found in the checked application locations or Spotlight |
| MiRemote / BlackHole virtual audio input | Not found in HAL or the audio-device inventory |
| tmux | Not found in PATH or common installation paths |
| MiCoding source project | Present as iCloud placeholders; executable/build state not verified |
| Privacy permissions and current AI input binding | Not observed |

## Next physical acceptance

1. Install or locate a compatible bridge, then verify remote audio in its actual virtual input.
2. Verify Doubao's shortcut and hold/release behavior; confirm release preserves an unsent draft.
3. Bind the current Codex APP window/task/input and test exactly one OK submission.
4. Verify task switching, preview return, cancellation and stopping the identified AI task.
5. If using Typeless, verify its shortcut and paired-tap lifecycle separately.
6. If using CLI windows, bind actual terminal panes; use tmux only after confirming an existing
   session and local/SSH access. Verify the visible terminal after server-side switching.

Do not mark these complete from unit tests, saved config or Bluetooth pairing alone.
