# Native remote implementation plan

**Goal:** Produce our own runnable macOS remote dictation app with no third-party
application or driver requirement, and synchronize the source and actual status.

**Architecture:** SwiftPM core library plus a SwiftUI/AppKit executable. Bluetooth
delivers ATVV PCM to Apple Speech; a small draft state machine owns unsent text.

**Stack:** Swift 5.9+, macOS 13+, CoreBluetooth, Speech, AVFoundation, SwiftUI.

## Work and file ownership

- [x] Protocol: `apps/macos/Sources/VibeRemoteCore/ATVVProtocol.swift`,
  `ADPCMDecoder.swift`, protocol tests and `THIRD_PARTY_NOTICES.md`. Begin with
  malformed packet, command negotiation and sync-isolation tests; adapt the MIT
  protocol with complete attributions and run those tests.
- [x] Transport: `apps/macos/Sources/VibeRemote/BluetoothService.swift`. Discover
  paired or advertising remotes, subscribe, negotiate capabilities, stream PCM,
  handle stop/disconnect/errors/timeouts and report observed status only.
- [x] Speech: `apps/macos/Sources/VibeRemote/SpeechService.swift`. Authorize on
  demand; feed mono float buffers from remote PCM; require local recognition unless
  explicitly opted into Apple's service; bound finalization and reject stale callbacks.
- [x] Draft/UI: core draft lifecycle tests first, then implementation, observable
  model and SwiftUI editor/status window. Preserve existing text across cancelled
  or failed utterances; explicit copy only; clear copy/edit state when busy.
- [x] Packaging: app metadata, reproducible build script, local signature, notices;
  update CI to exercise native tests/build and preserve Python checks.
- [x] Verify: `bash scripts/test_macos_core.sh`,
  `bash scripts/test_macos_speech.sh`, `bash scripts/build_macos_app.sh`, Python unittest discovery and template
  validation, `git diff --check`. Inspect the generated bundle and launch if possible.
- [ ] Record: update PROJECT/MEMORY/TASKS/WORKLOG and entry guides with implemented
  vs physically verified behavior. Commit only related source/docs, push to the
  authorized public repository, and inspect hosted checks.

Hardware and permission interaction occurs only after a concrete app is built.
No installation of the previously prepared SayAll package is part of this plan.
