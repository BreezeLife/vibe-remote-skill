# Project instructions

Read PROJECT.md, MEMORY.md, TASKS.md and WORKLOG.md before significant changes.
Project files are the primary source of truth across machines and conversations.

- Explain the plan and identify affected files before editing.
- Prefer incremental, simple changes that respect the current structure.
- Ask before destructive operations; preserve user configuration and drafts.
- Keep fixed button intentions consistent across APP and CLI adapters.
- Separate implemented behavior, installed dependencies, and physical verification.
- Do not infer current focus, recording state or device connectivity from saved configuration.
- Keep sending explicit; unknown state and shell prompts must block submission.
- Run relevant tests and update TASKS.md and WORKLOG.md with actual results.
- Record durable decisions in MEMORY.md; do not log credentials, audio or transcripts.
- Avoid generic promotional writing and unnecessary refactors.

Verification:

```sh
python3 -m unittest discover -s tests -v
python3 skills/vibe-remote/scripts/vibe_remote.py validate skills/vibe-remote/assets/config.default.json
```
