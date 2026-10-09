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

## 2026-10-05 — transport and recognition failures

- Keep physical audio reception separate from Speech lifecycle. A missing permission,
  failed start, early final result or recognition error must not call the manual BLE stop
  path. Keep measuring remote audio until physical release, preserve existing/partial
  drafts, and allow at most one recognition attempt per physical hold.
- When recognition finishes before physical release, keep the current utterance
  cancellable until release. Ignore late text/error/completion while retaining its rollback.
- Only explicit manual stops and capture watchdogs use the stop gate that requires
  reconnecting. Report timeout causes separately from a user-requested stop.
- Read Speech authorization from the current app's OS identity at startup and each
  new hold. A command-line probe's permission result does not establish app permission.
- Show recognition errors next to transport/audio status. Permission granted does not
  establish local language availability; neither establishes successful physical audio.
- Test the actual RemoteModel through injected service interfaces, in addition to core
  protocol and Speech PCM tests. Synthetic tests never instantiate real Bluetooth or
  recognition services, request permissions, or access the user's clipboard.

## 2026-10-05 — installer distribution

Historical decision: the installation domain and destination below were superseded by
the user's 2026-10-08 system Applications requirement. Other packaging safeguards remain.

- Distribute a standard current-user `.pkg`, installing only to ~/Applications.
  Disable system/other-volume domains and bundle relocation so an update cannot select
  the old cloud-workspace bundle. Require closing Vibe Remote before installing.
- Keep strict bundle identity and version checks. No installer scripts, privileged helper,
  driver, automatic privacy grants or automatic launch are included in the package.
- Build/stage signed app bundles outside iCloud; archive files may live in Downloads or
  the ignored build/packages directory. Label the actual native architecture and minimum OS.
- This development package contains an ad-hoc-signed app; the installer itself is unsigned
  and unnotarized. Do not describe it as Developer ID signed or clean-machine accepted.

## 2026-10-05 — visual controls and coding tools

- User approved the desktop-first 0.2 design with “继续实现吧”. Keep CLI as a separate
  exact-session adapter; do not treat a desktop terminal as a verified AI input.
- Independently implement SayAll-inspired interactions; do not copy its GPL client
  or proprietary assets into this MIT project.
- Native settings use `vibe-remote-native` schema 1 at Application Support/Vibe Remote,
  separate from Python settings. Keep validated backups; imports execute nothing and
  preserve existing workspace/draft ownership. Never persist drafts or runtime HID IDs.
- Device discovery is explicit and uses independent IOHID handles. Device-specific
  exclusive control must succeed across the selected device interfaces; missing physical
  identity/descriptor blocks seizure. Observation never authorizes mapped execution.
- User verifies raw-key suppression and ATVV coexistence for each captured connection.
  Losing device/permission or changing configuration cancels pending gestures and reviews.
- Drafts belong to individual workspace UUIDs, including a separate unbound draft.
  Capture/finalization locks selection. Learning a different target requires an empty
  draft and unchanged workspace both before and after the learning countdown.
- Live AX checks verify process, version, window, active content task anchor, input and
  semantic controls. Send needs exact full-text review; stop needs observed running state.
  Saved shortcuts are semantic implementations only, never a bypass for missing state.
- Explicit Codex thread navigation and new-draft prefilling are independent actions;
  neither substitutes for missing bindings nor sends automatically.


## 2026-10-08 — app icon

- Keep the original generated icon PNG and its prompt in apps/macos/Packaging/Artwork.
  Regenerate ICNS with scripts/build_macos_icon.sh; normal builds consume the checked-in
  ICNS and need no image-generation service. The design is a white remote with mint audio
  bars on a graphite tile; no third-party branding. App icon metadata starts in 0.2.1.
  That visual is preserved as AppIcon-v1.png; the later user-requested Pro 2 + Vibe design
  replaces it from 0.2.2, with both edit prompts in Artwork/README.md.

## 2026-10-08 — system Applications installation

- The user explicitly requires the shared system Applications directory, /Applications,
  rather than ~/Applications. This supersedes the current-user installation decision
  recorded on 2026-10-05; preserve that older entry as history.
- Starting with 0.2.2 / build 5, packages allow only LocalSystem and install to
  /Applications/Vibe Remote.app. Use the GUI Installer with administrator authorization,
  or `sudo installer -pkg <package> -target /`. Keep current-user/other-volume domains
  disabled, bundle relocation disabled, and existing identity/version/close-app checks.
- Ordinary builds default to ~/Library/Caches/VibeRemote/Build so development does not
  write to system Applications or require administrator access. Package builds continue
  staging signed bundles in a local temporary directory outside iCloud.
- Moving the app does not move native settings: they remain per user under
  ~/Library/Application Support/Vibe Remote. Preserve configuration and in-memory drafts;
  installing an update still requires copying any needed draft before exiting the app.

- The final 0.2.2 icon follows the user's Pro 2 hardware photograph and adds a large mint
  Vibe wordmark for Dock recognition. Keep alpha and mechanical ICNS conversion; retain the
  earlier icon variants. The photo itself is not bundled and Xiaomi/MI wordmarks are omitted.

## 2026-10-08 — Pro 2 layout and tool presets

- Match the actual Pro 2 hardware in the interactive diagram: power/mic at top,
  circular d-pad, back/home/menu left, vertical volume rocker/TV right.
- Codex, Claude Desktop and both WorkBuddy identities use consistent default button
  intentions and independently bound workspaces. Do not invent raw HID values or tool shortcuts.
- In 0.2.3, optional workspace buttonActions override semantic actions only. HID calibration
  stays global. Old schema-1 profiles without overrides preserve their prior behavior.
- Applying a preset is explicit and restores that workspace's actions and default AX method;
  retain learned inputs, bindings, other workspaces and drafts. Action-only reset retains shortcuts too.
- Discard remaining events in a resolved gesture batch after a workspace switch.
- New configurations containing buttonActions require 0.2.3+; retain backups before downgrading.

## 2026-10-09 — use the requested close-up icon in the app

- The large remote + Vibe image was only a proposal and did not ship in 0.2.3. The user
  reported the old icon in About. Promote the exact proposal to canonical AppIcon.png
  and regenerate AppIcon.icns; app/package builds copy ICNS and do not regenerate it.
- Version 0.2.4/build 7 ships the close-up. Preserve the 0.2.2–0.2.3 full-remote source
  as AppIcon-pro2-vibe-full.png and keep all generation prompts.
- Verify the selected PNG, ICNS sizes, package and installed resource identity, then
  observe the running About window; a generated preview alone is not an app update.
