# Durable decisions

- Keep fixed button intentions across APP and CLI adapters.
- Doubao: hold/release Fn. Typeless: paired start/end taps, currently Fn in the SayAll preset.
- Provider settings and shortcut values must be verified locally.
- Speech release retains a draft. OK explicitly confirms a selection or sends inspected text.
- Bind workspaces explicitly; browser preview must not replace the AI binding.
- Shell/unknown state blocks submission. Stop is scoped to an observed running AI task.
- The Python skill remains a planner, not a native listener. The separately built macOS
  application introduced on 2026-10-04 owns native Bluetooth/audio and draft UI.
- No raw transcripts or credentials in setup records.

## 2026-10-02 continuity and publishing

- Recovered the original VibeRemote chat via Codex read_thread after the public share page
  returned no conversation body. Source: https://chatgpt.com/share/6abe8aa5-7084-83ea-8780-e716cfae947b.
- The final user instruction was to publish directly as open source on GitHub, provide
  professional project output, and explain usage with the hardware already available.
  This supersedes the earlier private-repository suggestion and the 2026-09-30 publication
  rejection. Public synchronization is authorized.
- The 2026-10-02 scope was the existing skill and scripts; native development was then
  deferred. This limitation is superseded by the explicit 2026-10-04 native-app request.
- Preserve original commits b99ae45 and 2ecf007. Project-VibeRemote is the primary development
  checkout; the previous skill-projects checkout is retained as a recovery copy.
- The installed ~/.codex/skills/vibe-remote symlink now points into the primary checkout's
  skills/vibe-remote directory. Update here; do not continue editing the retained old copy.
- Publish this project's original code/docs as MIT in BreezeLife/vibe-remote-skill.
- Public publishing is complete. This checkout's origin uses the existing authenticated
  GitHub SSH connection; HTTPS OAuth lacks workflow scope and rejected the initial push.
  No account reauthorization, new key or global Git setting was required.
- A missing or non-boolean recording observation is unknown, not evidence capture stopped.
  Require explicit recording=false before starting/sending or changing workspaces.
- System volume and dictation cleanup remain available independently of normal focus gates.
  Workspace-picker events, like submission, must not repeat.

## 2026-10-04 — self-developed application

- The user explicitly requested our own better application, referencing MiRemote but
  not using its app. Stop the previously prepared SayAll installation path. No third-party
  app or driver is required by the first native milestone.
- Keep the existing repository/history and supporting skill; add the app under apps/macos.
- First milestone: direct CoreBluetooth ATVV audio → Apple Speech → editable in-memory
  draft → explicit copy. General HID mappings, guarded app execution and our own virtual
  microphone for Doubao/Typeless remain subsequent work.
- Default to on-device recognition. Lack of local language support is an explicit error;
  using Apple's speech service requires the user to enable the online option.
- Reuse only appropriately attributed MIT protocol/bridge code. Do not bundle or patch
  the BlackHole-derived GPL driver from the reference project. Native notices include
  MiRemoteVoice, mi-ao and ATVVoice attribution and retained MIT license texts.
- A new utterance appends to the existing draft; cancellation restores its prior text.
  Finalizing blocks editing/copying until settled, and stale speech callbacks are ignored.
- Native app privacy authorization and real remote audio acceptance must be observed;
  build/tests do not establish hardware success. No microphone fallback to the Mac.
