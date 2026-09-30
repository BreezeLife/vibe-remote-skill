# APP task adapter

Support Codex and ChatGPT by observing their actual task/conversation UI. Do not assume
that the two applications have identical navigation, shortcuts, or permission controls.

## Discover and bind

1. Inspect the actual app bundle and visible window. Do not identify it solely by a label
   such as “ChatGPT”: the installed Codex app may use that display name.
2. Register a short ordered set of target tasks. Each record needs the app, window, task
   or conversation anchor, and native input location. Avoid storing full conversation text.
3. Confirm the current target on screen before marking its configuration verified.
4. Bind a preview URL if useful. Opening preview preserves the task binding.
5. A selected registry item becomes the active workspace only after observed confirmation.

A task_anchor in the config is setup metadata. It does not by itself drive the app.
The agent must find the corresponding task through currently observed UI.

## Operations

| Intention | APP operation and verification |
| --- | --- |
| Previous / next | Select the adjacent registered task using the observed sidebar/list or a locally verified shortcut; then verify its title/project |
| Home | Activate the bound app/window, select its bound task, and focus its observed draft input |
| Dictate | Lock that input; use the configured bridge/provider and preserve existing draft text |
| OK in selector | Confirm the observed selected item; do not also send text |
| OK in composer | Confirm target, ready state, draft, and no active dictation; use the observed Send control |
| Back click | Close the observed overlay or return within the bound task |
| Back hold | Use the observed Stop control of the running task; verify it stopped |
| Menu hold | Capture the intended window; review target and image before attachment |
| TV click | Open the registered preview; retain the AI binding |

If a task is missing, renamed, or ambiguous, pause the dependent action and repair its
binding. Do not create a new task as a substitute without the user's instruction.
Do not cycle arbitrary recent applications with a generic global app switch.

For native terminal tabs and panes, follow cli-windows.md instead of treating the entire
terminal app as one task. When returning from preview, prove both the app and task/pane.

## Bridge integration boundary

Use bridge settings only for actions it actually exposes. A static Home shortcut can
activate an app; selecting an exact task may additionally need agent computer use or a
companion dispatcher. This skill does not install a background agent.

If Fn and navigation mapping are split across tools, assign each raw event to one owner.
Where the bridge lacks a task-aware action, report it as a companion integration ToDo.
A permanent target banner, picker overlay, and software pointer are companion UI features.

Reference: [MiCoding](https://github.com/zhangtuansia/MiCoding).
