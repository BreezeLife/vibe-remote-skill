# Codex desktop conversation mode

User direction (2026-10-10): implement Codex desktop first; UP/DOWN directly select the
previous/next conversation in the current project, focus its composer, dictate an isolated
draft, and explicitly confirm input. Prefer Steer when the selected running task exposes
that capability. Add one-click setup and an honest guided test flow. Claude/WorkBuddy
retain their current behavior until separate adapters are verified.

## Data and navigation

Use the installed Codex bundle identity, not its display name. Query the bundled CLI's
stable app-server thread/list through a bounded read-only client. Keep only ID, name and
normalized local project path, never preview/turn contents. A separate server is a catalog
source, not the desktop's active runtime: never resume/start/steer via that private server.

Catalog entries stay in memory; selection creates or reuses an explicitly managed profile
with its own UUID, thread ID and project path. Legacy profiles are not silently migrated.
This keeps existing per-profile drafts, insertion receipts and confirmation ownership
independent for each conversation. Persist only selected conversations; preserve other
profiles, calibrated inputs, customized actions and settings backups.

UP/DOWN use a stable catalog order inside the selected project, no wrap and no long-press
repeat. LEFT/RIGHT in managed Codex mode move between project groups, using an explicit
known session in the destination; power retains the workspace picker. Selecting a session
requests its canonical deep link in the exact Codex bundle and checks live identity before
focusing. A URL-open success, remembered descriptor, catalog status or matching sidebar
label alone never proves the active input. Exact live thread identity can establish catalog
membership; title fallback also requires unique title, live project identity and same main
content scope. Unsupported observations remain blocked and offer manual copy guidance.

Every navigation invalidates the pending confirmation and resets gesture batches. Drafts
remain owned by the user's selected destination; capture/finalization prevents further
switching. Cancellation, permission/device loss or capture during an awaited operation
prevents subsequent mutation. No automated rollback navigation or repeated submissions.

## Confirmation and Steer

Managed Codex OK first inserts a settled draft (or reuses an exact previous insertion
receipt), then prepares a full-text review if current capabilities permit. The next explicit
OK confirms that review. Unsupported submission leaves the inserted input/draft intact.
A live, unique, enabled Steer control in the verified task's composer has precedence over
normal send. Confirmation rechecks the same kind, input and target; a runtime change
cancels it instead of falling back to another action. Approval/permission dialogs are not
Steer. Unknown post-click outcome is reported without retry. Existing HID exclusive and
session suppression checks still gate actual submission.

## Setup and verification

One-click setup locates Codex, reads metadata and prepares the scoped default scheme.
User selects a project/session; only actual navigation/focus/input/submit observations mark
those capabilities verified. OS privacy authorization and physical key calibration remain
explicit. Guided checks cover two sessions, isolated drafts, voice hold/release, insertion,
normal send, Steer priority, cancellation and unknown state; they never send test prompts
automatically. Current computer-use tooling denies Codex window access, so development
must use injected fixtures and disclose that live desktop acceptance is pending.

Affected code: RemoteConfiguration/CodingToolPreset and new catalog types/service;
ToolAdapter navigation/autobinding/Steer; ControlsModel setup/routing/confirmation;
ToolSettingsView, SettingsViews and new setup panel; corresponding tests, package version,
setup docs and project records. Deliver an installer to system /Applications and sync GitHub.
