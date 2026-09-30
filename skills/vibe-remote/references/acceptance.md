# Acceptance and diagnosis

Separate implemented skill functions, installed dependencies, and observed hardware behavior.

| Capability | This package provides | Runtime dependency / evidence |
| --- | --- | --- |
| Doubao / Typeless / other dictation | Provider presets, lifecycle planner, setup guide | Installed provider, tested shortcut, working audio bridge |
| Button semantics | Fixed intentions and state gates | Real bridge events or companion dispatcher |
| APP task switching | Task binding and computer-use procedure | Available UI tools, observed task controls |
| Native terminal tabs/panes | Binding and computer-use procedure | Observed terminal UI and exact AI pane |
| Local / SSH tmux switching | Executable Python discovery and selection helper | Installed tmux, existing session; existing SSH access for remote |
| Permanent overlay / pointer | Product contract only | Companion application; not included |

## Checks

1. Run doctor and configuration validation.
2. Verify one mapping owner per button and the actual provider shortcut.
3. Record a remote-audio sample using the observed virtual input.
4. Hold microphone, release, and confirm text remains an unsent draft.
5. Press OK once in an AI composer; confirm exactly one submission.
6. Open a selector and press OK; confirm selection without submission.
7. Switch APP tasks; confirm visible destination and input after each switch.
8. Switch CLI windows/panes; confirm host, project, and AI prompt after each switch.
9. Open preview and use Home; confirm return to the original AI target.
10. While a task runs, hold Back; confirm only that AI task stops.
11. Test disconnected remote, unknown focus, missing task, shell prompt, held buttons,
    and dictation still draining. None should submit or blindly interrupt.

The planner and tmux selector have unit tests with controlled state and command responses.
Those tests do not prove Bluetooth audio, input-method behavior, GUI task switching,
live tmux visibility, or physical button integration. Mark each of those pending until
observed. Do not invent device connectivity from a saved profile.

Doctor is read-only. Its optional Bluetooth scan reports candidate names/connectivity
without dumping addresses or all system information. OS privacy permissions must be
checked using supported system UI; missing UI evidence is reported as not observed.

Report results in Chinese by default: configured items, verified items, remaining ToDo.
Keep records concise and exclude credentials, raw audio, and dictated transcript contents.
