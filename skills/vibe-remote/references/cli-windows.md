# CLI window adapter

Offer both existing native terminal UI and deterministic tmux selection. Do not force tmux
onto someone who only needs their existing iTerm2 or Terminal tabs.

## Native tabs and panes

Use current computer-use observations to register the terminal app, tab/window title, pane,
host, project, and coding assistant. Switch through observed controls or locally verified
shortcuts. Re-observe the destination after every switch. The tab title alone does not prove
that a running AI is accepting prompts.

Previous/next cycles only the registered coding panes. Home returns to the exact bound
AI pane. Submit and interrupt are allowed only after verifying that pane's AI state.
A generic shell or unknown process blocks both actions.
Before voice input, verify the AI's draft/multiline mechanism preserves recognition text
without submitting embedded newlines. Otherwise capture a separate draft first and adapt
its supported paste mechanism; do not dictate directly into an unverified line prompt.

## tmux helper: local or existing SSH alias

The helper is suitable when the user already has an attached tmux session. It never creates
sessions, connects an unattached client, launches an agent, or sends commands into a pane.

In a user-owned config copy, set tmux_session to a simple exact session name and mark
verified true only after observation. Set host to null for local use, or an existing SSH
alias such as mini for remote use. Native terminal workspaces may leave tmux_session null.

```sh
python3 <skill-dir>/scripts/vibe_remote.py windows config.local.json --workspace cli-local
python3 <skill-dir>/scripts/vibe_remote.py switch config.local.json --workspace cli-local --direction next
python3 <skill-dir>/scripts/vibe_remote.py switch config.local.json --workspace cli-mini --window @3
```

Discovery queries only the exact bound session. Selection targets its stable window ID,
then queries again to verify it became current. At the first or last registered tmux window,
an adjacent switch stays in place; it never wraps. tmux indices need not be consecutive.

SSH uses the existing client configuration and BatchMode; the helper reads no credential
files, changes no SSH settings, and does not prompt for passwords. Remote arguments are
quoted and session/alias names are restricted. It selects the server-side session; verify
that the displayed terminal is attached to that session before reporting a visible switch.

The helper treats every window of the bound tmux session as registered. Use a dedicated
coding session if unrelated windows should be excluded. A window's title does not prove
that its current pane is an AI input.

## Physical button integration

A bridge may invoke a helper only if it exposes a supported external-command action.
Otherwise configure a verified terminal shortcut or use a companion dispatcher.
tmux's standard prefix is Ctrl+B followed by n/p, but the user's prefix and key bindings
may differ. Do not inject these before verifying the current tmux client and configuration.

For screenshots or images, use the particular coding CLI's supported attachment mechanism.
Do not type local image paths into a remote SSH session and assume the files exist there.
This skill implements no image upload transport.

References:

- [tmux Getting Started](https://github.com/tmux/tmux/wiki/Getting-Started)
- [tmux manual source](https://github.com/tmux/tmux/blob/master/tmux.1)
- [Windows reference: miremote-vibe](https://github.com/qi-o/miremote-vibe)
