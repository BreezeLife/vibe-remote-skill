# Visual Controls Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement this plan task-by-task. Steps use checkboxes for tracking.

**Goal:** Deliver the approved desktop-first 0.2 app with visual button settings, calibrated device input and guarded Codex/Claude/WorkBuddy actions.

**Architecture:** Keep ATVV and Speech unchanged. Add pure configuration/gesture rules in Core, independently testable HID and AX adapters, and a coordinator that owns live capability checks and workspace-specific in-memory drafts. No saved setting authorizes an action by itself.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, IOKit HID, ApplicationServices AX, SwiftPM and standalone Swift checks.

User approval: “继续实现吧”, 2026-10-05. Execute in this session without another design or execution-choice approval.

## Task 1 — configuration and gesture rules

Files: create `apps/macos/Sources/VibeRemoteCore/RemoteConfiguration.swift`, `ButtonGestures.swift`, and matching `Tests/VibeRemoteCoreTests/*Tests.swift`.

- [x] Define typed buttons, semantic actions, optional hold/double mappings, descriptor-bound HID signatures, AX locators, workspace tool bindings and versioned native settings.
- [x] Write failing tests for duplicate mappings, voice remapping, unknown actions/schema, unsafe URL and shortcut import, descriptor identity, repeated down, long/double suppression and cancellation. Run `bash scripts/test_macos_core.sh` and observe missing-feature failures.
- [x] Implement validated defaults and pure gesture reduction with monotonic injected time. Default hold 0.6 s, double 0.3 s; no repeated send/stop. Only scrolling/volume may repeat.
- [x] Run the same suite to green. Existing protocol/draft tests must still pass.

Contract examples:
```swift
let settings = NativeSettings.defaults
try settings.validate()
let data = try JSONEncoder().encode(settings)
let decoded = try JSONDecoder().decode(NativeSettings.self, from: data)
try decoded.validate()
```

## Task 2 — device-specific input

Files: create `apps/macos/Sources/VibeRemote/HIDRemoteInputService.swift`, `apps/macos/Tests/HIDInputChecks.swift`, `scripts/test_macos_hid.sh`.

- [x] Test the lifecycle through a fake HID driver: selection, partial exclusive-open failure, disconnect/revoke/sleep cancellation, suppressed duplicate edges and explicit enable only.
- [x] Implement lazy candidate discovery for Xiaomi VID/PID. Enumerate all interfaces of the selected physical device, use current-connection IDs only, and open all relevant interfaces exclusively before declaring capture ready.
- [x] Expose observation separately from exclusive calibration. Surface raw usage/report/descriptor edges; never intercept all keyboards. Release handles/timers on pause, sleep, permission loss or removal.
- [x] Compile/run fake checks with no IOHID permission request. Actual suppression and ATVV coexistence remain physical acceptance entries.

## Task 3 — tool adapter

Files: create `apps/macos/Sources/VibeRemote/ToolAdapter.swift`, `apps/macos/Tests/ToolAdapterChecks.swift`, `scripts/test_macos_tools.sh`.

- [x] Test fake accessibility observations first: wrong frontmost PID/window/task, secure/ambiguous input, changed app version, changed text, disabled send, missing running/stop state and shell targets must fail closed.
- [x] Discover four builtin bundle IDs and custom selected apps. Learn the focused input and explicit task anchor; learn send/stop controls by a deliberate countdown/pointing operation.
- [x] Implement activation followed by fresh verification; insert by verified AX value update/readback; prepare a full-text send snapshot and revalidate it immediately before AXPress. Stop requires the bound running-task control. No Chromium page-stop or blind Enter/Ctrl+C fallback.
- [x] Add semantic shortcut configuration/recording behind the same validation. Only verified semantic actions can execute shortcuts. Unsupported capabilities give a useful reason and retain the draft.
- [x] Run fake adapter checks, without launching third-party apps or sending messages.

## Task 4 — storage, drafts and coordinator

Files: create `NativeSettingsStore.swift`, `ControlsModel.swift`; modify `RemoteModel.swift`; extend `RemoteModelChecks.swift`; create `ControlsChecks.swift` and `scripts/test_macos_controls.sh`.

- [x] Test corrupt/unknown settings preserve prior valid data, export/import has no drafts and executes nothing, and write failure does not update in-memory settings.
- [x] Atomically save validated settings at Application Support/Vibe Remote/settings.json, separate from Python settings. Preserve old valid settings and report failed import without replacement.
- [x] Add per-workspace draft switching; capture/finalization lock the workspace. Preserve the original unbound draft and require explicit copy when transferring it.
- [x] Route calibrated gestures through a serialized coordinator. Calibration never dispatches actions. Pause/reset cancels all pending gestures. Require fresh device and target state for actions and snapshot-bound confirmation for sending.
- [x] Run standalone coordinator/model checks and existing voice regressions.

Draft acceptance example:
```swift
model.replaceDraft("unbound")
assert(model.selectWorkspace(firstID))
assert(model.draft.text.isEmpty)
assert(model.selectWorkspace(nil))
assert(model.draft.text == "unbound")
```

## Task 5 — native pages

Files: create `SettingsViews.swift`, `ButtonSettingsView.swift`, `ToolSettingsView.swift`, `ConnectionSettingsView.swift`; modify `RemoteView.swift` and `VibeRemoteApp.swift`.

- [x] Add sidebar pages for dictation, buttons, tools and connection/permissions.
- [x] Build an original remote diagram with selected/pressed states and editor lock. Provide gesture/action pickers, calibration, defaults, profile copying and validated import/export.
- [x] Tool cards show actual installation metadata and workspace capabilities. Add explicit binding/test steps, shortcut picker/recording, preview/thread URLs and separate send/stop controls.
- [x] Show selected workspace and pending full-text send confirmation near the draft; menu offers pause/release. No automatic permission requests at startup.
- [x] Build the full app using `swift build --package-path apps/macos --disable-sandbox`; inspect the running first-party UI where host access permits.

## Task 6 — review and delivery

Files: update `.github/workflows/checks.yml`, `apps/macos/Packaging/Info.plist`, `README.md`, `docs/NATIVE-SETUP.md`, `PROJECT.md`, `MEMORY.md`, `TASKS.md`, `WORKLOG.md`, and `skills/vibe-remote/SKILL.md`.

- [x] Review spec compliance, then code quality/security boundaries; fix substantive findings and rerun the affected tests.
- [x] Run core, Speech, model, HID, tool and coordinator suites, Python unittest discovery, neutral config validation and `git diff --check`.
- [x] Build version 0.2.0 / build 3 installer into a new Downloads directory using `VIBE_PACKAGE_OUTPUT_DIR=... bash scripts/package_macos_app.sh`. Verify payload signature and SHA-256.
- [x] Record actual software checks separately from unperformed physical remote/tool acceptance. Keep failed/unverified actions disabled.
- [x] Commit selected project files, synchronize GitHub without force, and report the installer plus any real-device setup still required. Preserve unrelated STATUS.md and .project-pulse/.

Execution evidence (2026-10-05): all software suites passed; initial native preview window
was observed, then the native automation pipe closed before interactive page inspection.
Physical HID suppression, ATVV coexistence and actual coding-tool actions remain pending.
See TASKS.md and WORKLOG.md for exact delivery and verification results.
