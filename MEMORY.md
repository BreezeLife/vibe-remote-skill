# Durable decisions

- Keep fixed button intentions across APP and CLI adapters.
- Doubao: hold/release Fn. Typeless: paired start/end taps, currently Fn in the SayAll preset.
- Provider settings and shortcut values must be verified locally.
- Speech release retains a draft. OK explicitly confirms a selection or sends inspected text.
- Bind workspaces explicitly; browser preview must not replace the AI binding.
- Shell/unknown state blocks submission. Stop is scoped to an observed running AI task.
- The skill is not a native remote listener, microphone driver, or overlay application.
- No raw transcripts or credentials in setup records.

## 2026-10-02 continuity and publishing

- Recovered the original VibeRemote chat via Codex read_thread after the public share page
  returned no conversation body. Source: https://chatgpt.com/share/6abe8aa5-7084-83ea-8780-e716cfae947b.
- The final user instruction was to publish directly as open source on GitHub, provide
  professional project output, and explain usage with the hardware already available.
  This supersedes the earlier private-repository suggestion and the 2026-09-30 publication
  rejection. Public synchronization is authorized.
- Continue the existing skill and scripts. A native bridge, persistent overlay and automatic
  dispatcher remain separate work; do not expand this request into building them.
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
