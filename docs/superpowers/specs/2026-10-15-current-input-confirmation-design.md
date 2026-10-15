# Manual confirmation after current-focus dictation

The user requested a physical button to manually submit text after dictation. Reuse the existing
OK review/confirmation workflow: first press shows the actual bound input's full text, second
press submits. Voice release still only inserts text. An observed Codex Steer remains preferred.

## Scope

- Reuse `sendDraft` / `confirmInput` in current-focus mode; do not change the settings schema,
  calibrated keys or existing presets. Draft mode keeps its existing insertion/review behavior.
- Keep old workspace drafts independent. The current-focus path never inserts, appends or uses
  that draft as submission text. `insertDraft` remains blocked in this mode.
- Voice input needs no workspace; explicit remote submission requires the selected, bound AI
  input to already be focused. Unsupported or terminal targets remain blocked.

## Flow and checks

1. Finish dictation. For external providers, explicitly close preparation after their recording
   and recognition finish. Rearming another hold is still busy and cannot authorize submission.
2. With the target input focused, press OK. Require live voice readiness, exclusive HID and the
   user's current suppression verification. Read and validate the bound target without activating,
   focusing or writing anything. Reject empty text and unavailable Send/Steer state.
3. Show full text and destination in the existing preview. Preserve input destination, workspace
   and draft revision snapshots; the current-focus preview expires after 60 seconds.
4. A separate OK or confirmation button consumes this preview once. Recheck text, application,
   window, actual input identity, focus, task and control. Only the original target or Vibe Remote's
   preview may be frontmost. Returning from the preview may activate the same verified target,
   but must not restore focus to conceal user navigation.
5. Mark a submission attempt before mutation. Unknown outcomes block retry even if the input is
   edited. A confirmed attempt also blocks accidental resubmission of the same text. No generic
   Return fallback or delayed automatic retry is added.

## Implementation areas

- `ToolAdapter`: focused-only preview and confirmation policy, live identity checks, fake-driver tests.
- `ControlsModel`: separate direct-input review/attempt state, invalidation and coordinator tests.
- Settings/voice/button guidance: explain OK's two steps and closing external preparation.
- Version 0.2.10/build 13; package continues targeting only system `/Applications`.

## Verification

Fake-driver tests cover no local draft, no duplicate insertion, wrong foreground/focus/task,
changed content/identity/destination, ongoing provider lifecycle, expiry, device loss, single
consumption and uncertain mutation. Test Send and Steer without invoking real applications.
Build and validate the installer separately. User-led real Codex acceptance remains necessary;
the computer-use tool's Codex access denial must not be bypassed through the adapter.

The eleven short-press hardware mappings and basic audio have already been observed. They do
not establish exclusive suppression, third-party transcription or the new manual-send flow.
