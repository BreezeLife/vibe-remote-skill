---
name: vibe-remote
description: Configure the self-developed macOS Vibe Remote app for Xiaomi remote dictation, visual button mappings and Codex, Claude or WorkBuddy desktop workspaces. Also supports legacy dictation-provider guidance and exact local or SSH tmux selection. Use for setup, button configuration, voice coding, workspace switching or troubleshooting.
---

# Vibe Remote

Give the remote a stable set of intentions, then adapt those intentions to the bound workspace.
Keep the speech draft, visible target, and explicit submission separate.

## Scope

This skill provides setup guidance, a neutral configuration template, an event planner,
and a working tmux window selector. It is not a Bluetooth/HID/audio driver or a background
button listener. The repository's separately built macOS Vibe Remote app now owns direct
ATVV audio and, in 0.2, visual button configuration, device-scoped HID calibration and
AX desktop adapters for Codex, Claude Desktop, both WorkBuddy identities and custom apps.
See the repository's docs/NATIVE-SETUP.md. Installing this skill alone does not install the app.
Native 0.2.3 uses the Pro 2 physical diagram and explicit Codex/Claude/WorkBuddy default
action presets. Workspace actions are independent; calibrated HID inputs remain shared.
Existing profiles keep their global actions until the user edits or explicitly applies a preset.
Native 0.2.5 adds nearby-remote discovery, explicit selection and bounded idle reconnection.
Saved/discovered devices do not establish audio readiness; manual stops and capture-time loss
require explicit reconnection. See NATIVE-SETUP for pairing and discovery limits.
The user's native-app path requires no SayAll/MiRemote bridge; do not install one implicitly.
Native presets do not prove physical input, focus, insertion, send or stop acceptance.
A virtual microphone, software pointer and native CLI runtime adapter remain future work.
APP operations through this skill use available computer-use tools and freshly observed controls.

## Start with the requested path

- Voice input: read [voice-input.md](references/voice-input.md).
- Codex / ChatGPT APP tasks: read [app-tasks.md](references/app-tasks.md).
- Terminal tabs, panes, local or SSH sessions: read [cli-windows.md](references/cli-windows.md).
- Setup or end-to-end verification: read [acceptance.md](references/acceptance.md).

Resolve this skill directory from the installed SKILL.md location. Run its helper with an
absolute path; never assume the user's working directory is the skill directory:

```sh
python3 <skill-dir>/scripts/vibe_remote.py doctor
python3 <skill-dir>/scripts/vibe_remote.py validate <skill-dir>/assets/config.default.json
```

Copy [config.default.json](assets/config.default.json) to a user-owned config.local.json
before editing. It is this skill's schema, not an import format for SayAll, MiCoding, or
an input method. Never overwrite an existing user config. Verify actual installed app
bundle IDs, provider settings, and bridge capabilities before translating to native settings.
The template's workspace bindings are deliberately unverified and cannot submit a draft.

## Fixed button intentions

| Button | Gesture | Intention |
| --- | --- | --- |
| Power | Click | Open workspace picker; confirm one bound workspace |
| Microphone | Hold / release | Capture speech / finish a draft without sending |
| Up / down | Click or hold | Scroll output; navigate items while a selector is open |
| Left / right | Click | Previous / next registered APP task or CLI window |
| OK | Click | Confirm a selected item, or send an inspected draft in the bound AI input |
| Back | Click | Close a selector, go back, or cancel the current dictation segment |
| Back | Hold | Stop the explicitly identified, running AI task once |
| Home | Click | Return to the bound AI input |
| Menu | Click / hold | Open actions / capture current window for attachment review |
| TV | Click / hold | Open bound preview / request optional companion pointer mode |
| Volume | Click or hold | Retain system volume behavior |

No double-click actions by default. Hold-repeat applies only to scrolling and volume.
Send and stop must not repeat. Unsupported gestures produce no action.
Probe which buttons the bridge actually reports; move unavailable actions into Menu.
Binding survives switching to a browser preview; browser focus does not redefine the AI target.

## Workspace and state contract

Bind APP workspaces to the observed app bundle, window, project/conversation, and input.
Bind CLI workspaces to the terminal, host, and exact tab/pane or tmux session/window.
Showing iTerm2 alone does not establish that a coding assistant is ready for input.
Keep a small ordered registry of tasks/windows so previous/next has a visible destination.
Do not wrap from the last entry to the first without an explicit user preference.

Before dictation starts, lock and visibly identify its draft destination. Use the app's
native draft composer where possible. A separate draft overlay is an optional companion
feature. Release ends capture, drains pending audio, completes the provider gesture,
and leaves text for review. Finish or cancel dictation before changing workspaces.

Before send, freshly confirm: remote connected; target matches the binding; no active
dictation; target is an AI input; draft exists; AI is ready. Unknown state or a shell prompt
blocks submission. APP send uses an observed send control or locally verified shortcut.
CLI submission requires a verified AI prompt, not a generic Enter in an arbitrary terminal.
Before stop, identify the running AI process. Use its observed Stop action or a verified
interrupt in the exact AI pane. Never blindly send Ctrl+C to a shell or another process.

The optional planner accepts a transient state JSON object with fields connected,
target_id, target_confirmed, context (ai_input / selection / output / shell / unknown),
runtime (ready / draft / running / unknown), recording, has_draft,
ai_process_confirmed, selection_confirmed, and repeated. Values must come from current runtime/UI
observations; a saved config is not evidence of current focus or readiness.
The native dispatcher serializes actions and deduplicates calibrated gestures;
other companion dispatchers must supply the same protections;
the stateless planner cannot supply event history. Mark repeat emissions with repeated=true.

```sh
python3 <skill-dir>/scripts/vibe_remote.py plan config.local.json \
  --workspace codex-app --state observed-state.json --button ok --gesture click
```

The planner only returns semantic actions; it never executes GUI keys. A physical bridge
does not automatically call this planner. Configure only actions that the chosen bridge
actually exposes; use a companion dispatcher for unsupported compound actions.
Give every raw key one mapping owner to avoid duplicate Fn, Enter, or task switches.

## Execute and verify

For APPs and native terminal UI, use only available computer-use APIs. Refresh the UI
after each switch, locate actual controls, and update the binding. Do not reuse stale
coordinates, guessed keyboard shortcuts, or a different task's input anchor.
For tmux, use the helper's exact-session window discovery and selector; it checks the
selected window after changing it. It does not create sessions, launch agents, type
prompts, submit text, or alter SSH configuration.

When a dependency is absent, complete available configuration and clearly mark the
physical test as pending. Do not silently install drivers, alter global input settings,
or fabricate a completed remote operation. Persist new skill code with Git.
Report what was configured, what was observed, what was tested, and remaining ToDo.
Never record passwords, tokens, raw audio, or full dictated transcripts in setup logs.
