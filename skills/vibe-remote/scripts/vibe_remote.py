#!/usr/bin/env python3
"""Read-only setup checks, guarded event planning, and exact tmux window selection."""
import argparse
import json
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

HOST = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
SESSION = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,79}\Z")
WINDOW = re.compile(r"@[0-9]+\Z")
BUTTONS = ("power", "mic", "up", "down", "left", "right", "ok", "back",
           "home", "menu", "tv", "volume_up", "volume_down")
GESTURES = ("click", "hold", "release")


def output(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def read_json(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def valid_pattern(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def validate_config(config):
    errors = []
    if not isinstance(config, dict):
        return ["Configuration must be a JSON object"]
    if config.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    profiles = config.get("voice_profiles")
    if not isinstance(profiles, dict) or not profiles:
        errors.append("voice_profiles must be a nonempty object")
        profiles = {}
    for name, profile in profiles.items():
        if not isinstance(profile, dict):
            errors.append(f"voice_profiles.{name} must be an object")
            continue
        if profile.get("behavior") not in ("hold_key", "paired_taps"):
            errors.append(f"voice_profiles.{name}.behavior is unsupported")
        if not isinstance(profile.get("key"), str) or not profile["key"].strip():
            errors.append(f"voice_profiles.{name}.key is required")
        if name == "doubao" and (
                profile.get("behavior") != "hold_key" or
                profile.get("simulate_fn_tap") is not False):
            errors.append("Doubao preset requires hold_key and simulate_fn_tap=false")
        if name == "typeless" and (
                profile.get("behavior") != "paired_taps" or
                profile.get("simulate_fn_tap") is not True):
            errors.append("Typeless preset requires paired_taps and simulate_fn_tap=true")
    selected_provider = config.get("voice_provider")
    if not isinstance(selected_provider, str) or selected_provider not in profiles:
        errors.append("voice_provider must select an existing profile")
    if not isinstance(config.get("audio_device"), str) or not config["audio_device"].strip():
        errors.append("audio_device is required")
    workspaces = config.get("workspaces")
    if not isinstance(workspaces, list) or not workspaces:
        return errors + ["workspaces must be a nonempty array"]
    identifiers = set()
    for item in workspaces:
        if not isinstance(item, dict):
            errors.append("Every workspace must be an object")
            continue
        identifier = item.get("id")
        if not isinstance(identifier, str) or not identifier.strip():
            errors.append("Workspace id is required")
        elif identifier in identifiers:
            errors.append(f"Duplicate workspace: {identifier}")
        else:
            identifiers.add(identifier)
        if not isinstance(item.get("verified"), bool):
            errors.append(f"{identifier}: verified must be a boolean")
        if item.get("mode") == "app":
            if not isinstance(item.get("app_bundle_id"), str) or not item["app_bundle_id"]:
                errors.append(f"{identifier}: app_bundle_id is required")
            if item.get("verified") is True and any(
                    not isinstance(item.get(field), str) or not item[field].strip()
                    for field in ("window_title", "task_anchor")):
                errors.append(f"{identifier}: verified APP needs window_title and task_anchor")
        elif item.get("mode") == "cli":
            if not isinstance(item.get("terminal_app"), str) or not item["terminal_app"]:
                errors.append(f"{identifier}: terminal_app is required")
            host, session = item.get("host"), item.get("tmux_session")
            if host is not None and not valid_pattern(HOST, host):
                errors.append(f"{identifier}: unsafe SSH alias")
            if session is not None and not valid_pattern(SESSION, session):
                errors.append(f"{identifier}: use a simple exact tmux session name")
        else:
            errors.append(f"{identifier}: mode must be app or cli")
        preview = item.get("preview_url")
        if preview is not None and (
                not isinstance(preview, str) or
                not preview.startswith(("https://", "http://"))):
            errors.append(f"{identifier}: preview_url must be http(s) or null")
    return errors


def load_config(path):
    config = read_json(path)
    errors = validate_config(config)
    if errors:
        raise ValueError("; ".join(errors))
    return config


def get_workspace(config, identifier):
    for workspace in config["workspaces"]:
        if workspace["id"] == identifier:
            return workspace
    raise ValueError(f"Workspace is not registered: {identifier}")


def plan_event(config, workspace, state, button, gesture):
    """Describe intentions only. Observed state is supplied by the caller."""
    if not isinstance(state, dict):
        raise ValueError("State must be a JSON object")
    if button not in BUTTONS or gesture not in GESTURES:
        raise ValueError("Unsupported button or gesture")
    base = {"executes": False, "workspace": workspace["id"], "mode": workspace["mode"],
            "button": button, "gesture": gesture}

    def allow(intent, actions):
        return dict(base, allowed=True, intent=intent, actions=actions)

    def block(reason):
        return dict(base, allowed=False, reason=reason, actions=[])

    profile = config["voice_profiles"][config["voice_provider"]]
    finish = ("release_provider_key" if profile["behavior"] == "hold_key"
              else "tap_provider_key")
    # Cleanup may be necessary even after disconnection or a focus change.
    if button == "mic" and gesture == "release":
        if state.get("repeated") is True:
            return block("Dictation finish must not repeat")
        if state.get("recording") is not True:
            return block("No active dictation to finish")
        return allow("finish_draft",
                     ["end_remote_capture", "drain_pending_audio", finish, "retain_draft"])
    if button in ("volume_up", "volume_down") and gesture in ("click", "hold"):
        return allow(button, ["adjust_system_volume"])
    if button == "back" and gesture == "click" and state.get("recording") is True:
        if state.get("repeated") is True:
            return block("Dictation cancellation must not repeat")
        return allow("cancel_dictation_segment",
                     ["end_remote_capture", "drain_pending_audio", finish,
                      "request_verified_segment_cancel"])
    if button == "power" and gesture == "click":
        if state.get("recording") is True:
            return block("Finish or cancel dictation before choosing a workspace")
        return allow("choose_workspace", ["open_workspace_picker"])
    if gesture == "release":
        return block("No mapped release action")
    if state.get("connected") is not True:
        return block("Remote connection is not confirmed")
    if workspace.get("verified") is not True:
        return block("Workspace binding is not verified")
    if (state.get("target_id") != workspace["id"] or
            state.get("target_confirmed") is not True):
        return block("Current target does not match the confirmed binding")
    if state.get("repeated") is True and button not in (
            "up", "down", "volume_up", "volume_down"):
        return block("This button action must not repeat")
    if state.get("recording") is True:
        return block("Finish or cancel dictation before another action")
    context, runtime = state.get("context"), state.get("runtime")
    if button == "mic" and gesture == "hold":
        if context != "ai_input" or runtime not in ("ready", "draft"):
            return block("A ready AI draft input must be confirmed")
        start = ("hold_provider_key" if profile["behavior"] == "hold_key"
                 else "tap_provider_key")
        return allow("start_dictation",
                     ["lock_draft_target", "focus_verified_draft_input", start,
                      "begin_remote_capture", "show_capture_ready"])
    if button == "ok" and gesture == "click":
        if context == "selection":
            if state.get("selection_confirmed") is not True:
                return block("Selected item is not observed")
            return allow("confirm_selection", ["confirm_observed_selected_item"])
        if (context != "ai_input" or runtime not in ("ready", "draft") or
                state.get("has_draft") is not True):
            return block("An inspected draft in a ready AI input is required")
        if workspace["mode"] == "cli" and state.get("ai_process_confirmed") is not True:
            return block("The exact CLI AI process must be confirmed before submission")
        action = ("invoke_observed_send" if workspace["mode"] == "app"
                  else "submit_confirmed_ai_input")
        return allow("submit_draft", [action, "observe_submission"])
    if button == "back" and gesture == "hold":
        if (runtime != "running" or context not in ("ai_input", "output") or
                state.get("ai_process_confirmed") is not True):
            return block("The running AI task must be explicitly identified")
        action = ("invoke_observed_stop" if workspace["mode"] == "app"
                  else "interrupt_bound_ai_once")
        return allow("stop_ai", [action, "observe_stop"])
    if button == "back" and gesture == "click":
        return allow("go_back", ["close_observed_selector_or_go_back"])
    if button in ("left", "right") and gesture == "click":
        suffix = "previous" if button == "left" else "next"
        noun = "task" if workspace["mode"] == "app" else "window"
        return allow(f"{noun}_{suffix}",
                     [f"select_registered_{noun}_{suffix}", "observe_and_rebind_target"])
    if button in ("up", "down") and gesture in ("click", "hold"):
        noun = "selection" if context == "selection" else "output"
        return allow(f"{noun}_{button}", [f"navigate_{noun}_{button}"])
    if button == "home" and gesture == "click":
        return allow("return_ai_input", ["activate_bound_workspace", "verify_and_focus_ai_input"])
    if button == "menu" and gesture == "click":
        return allow("open_actions", ["open_action_picker"])
    if button == "menu" and gesture == "hold":
        return allow("capture_window", ["capture_verified_window", "review_pending_attachment"])
    if button == "tv" and gesture == "click":
        if not workspace.get("preview_url"):
            return block("No preview URL is registered")
        return allow("open_preview", ["open_registered_preview", "retain_ai_binding"])
    if button == "tv" and gesture == "hold":
        return allow("request_pointer", ["request_optional_companion_pointer"])
    return block("No mapped action")


def command_for(workspace, arguments):
    command = ["tmux"] + list(arguments)
    host = workspace.get("host")
    if host is None:
        return command
    if not valid_pattern(HOST, host):
        raise ValueError("Unsafe SSH alias")
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            "--", host, shlex.join(command)]


def run_tmux(workspace, arguments, runner=subprocess.run):
    result = runner(command_for(workspace, arguments), capture_output=True,
                    text=True, timeout=12, check=False)
    if result.returncode != 0:
        # Error text is intentionally omitted; it can contain sensitive host details.
        raise RuntimeError(f"tmux/SSH command failed (exit {result.returncode})")
    return result.stdout


def require_tmux_binding(workspace):
    if workspace.get("mode") != "cli" or workspace.get("verified") is not True:
        raise ValueError("An explicitly verified CLI workspace is required")
    if not valid_pattern(SESSION, workspace.get("tmux_session")):
        raise ValueError("Set a simple exact tmux_session before using this helper")
    if workspace.get("host") is not None and not valid_pattern(HOST, workspace["host"]):
        raise ValueError("Unsafe SSH alias")


def list_windows(workspace, runner=subprocess.run):
    require_tmux_binding(workspace)
    rows = run_tmux(workspace, [
        "list-windows", "-t", "=" + workspace["tmux_session"], "-F",
        "#{window_id}\t#{window_index}\t#{window_active}\t#{window_name}"
    ], runner)
    windows = []
    for line in rows.splitlines():
        parts = line.split("\t", 3)
        if (len(parts) != 4 or not valid_pattern(WINDOW, parts[0]) or
                not parts[1].isdigit() or parts[2] not in ("0", "1")):
            raise RuntimeError("Unexpected tmux window response; no selection performed")
        windows.append({"id": parts[0], "index": int(parts[1]),
                        "active": parts[2] == "1", "name": parts[3]})
    if (not windows or sum(item["active"] for item in windows) != 1 or
            len({item["id"] for item in windows}) != len(windows) or
            len({item["index"] for item in windows}) != len(windows)):
        raise RuntimeError("Ambiguous tmux window state; no selection performed")
    return sorted(windows, key=lambda item: item["index"])


def switch_window(workspace, direction=None, window_id=None, runner=subprocess.run):
    if (direction is None) == (window_id is None):
        raise ValueError("Specify exactly one direction or window ID")
    if direction is not None and direction not in ("previous", "next"):
        raise ValueError("Direction must be previous or next")
    windows = list_windows(workspace, runner)
    current_position = next(i for i, item in enumerate(windows) if item["active"])
    current = windows[current_position]
    if window_id is not None:
        matches = [item for item in windows if item["id"] == window_id]
        if not matches:
            raise ValueError("Window is not in the bound session")
        target = matches[0]
    else:
        position = current_position + (-1 if direction == "previous" else 1)
        target = windows[position] if 0 <= position < len(windows) else current
    changed = target["id"] != current["id"]
    if changed:
        run_tmux(workspace, ["select-window", "-t",
                            "=" + workspace["tmux_session"] + ":" + target["id"]], runner)
        after = list_windows(workspace, runner)
        if not any(item["id"] == target["id"] and item["active"] for item in after):
            raise RuntimeError("Selection was attempted but could not be verified; do not retry blindly")
    return {"changed": changed, "window": target["id"], "name": target["name"],
            "host": workspace.get("host"), "session": workspace["tmux_session"],
            "visible_gui_verified": False}


def doctor(scan_bluetooth=False):
    found = []
    names = ("doubao", "typeless", "sayall", "micoding", "chatgpt", "codex",
             "remotemic", "miremote")
    for root in (Path("/Applications"), Path.home() / "Applications",
                 Path("/Library/Input Methods")):
        if not root.is_dir():
            continue
        for app in sorted(root.glob("*.app")):
            if not any(name in app.name.lower().replace(" ", "") for name in names):
                continue
            info_path = app / "Contents" / "Info.plist"
            try:
                with info_path.open("rb") as stream:
                    info = plistlib.load(stream)
            except (OSError, plistlib.InvalidFileException):
                continue
            found.append({"name": app.name, "path": str(app),
                          "bundle_id": info.get("CFBundleIdentifier"),
                          "version": info.get("CFBundleShortVersionString")})
    drivers = []
    hal = Path("/Library/Audio/Plug-Ins/HAL")
    if hal.is_dir():
        drivers = [item.name for item in sorted(hal.iterdir())
                   if any(name in item.name.lower() for name in ("miremote", "blackhole"))]
    report = {"platform": platform.system(), "apps": found, "audio_driver_candidates": drivers,
              "commands": {name: shutil.which(name) for name in ("tmux", "ssh", "codex")},
              "privacy_permissions": "not_observed",
              "physical_remote_audio": "not_tested",
              "app_task_switching": "requires_current_ui_observation"}
    if scan_bluetooth:
        if platform.system() != "Darwin":
            raise ValueError("Bluetooth scan is supported only on macOS")
        result = subprocess.run(["system_profiler", "SPBluetoothDataType", "-json"],
                                capture_output=True, text=True, timeout=20, check=False)
        if result.returncode:
            raise RuntimeError("Bluetooth inventory failed")
        candidates = []

        def visit(value):
            if isinstance(value, dict):
                name = str(value.get("_name", ""))
                if any(part in name.lower() for part in ("mi rc", "xiaomi", "小米", "remote")):
                    connected = value.get("device_connected", value.get("connected"))
                    candidates.append({"name": name, "connected": connected})
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        visit(json.loads(result.stdout))
        report["bluetooth_candidates"] = candidates
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    diagnosis = commands.add_parser("doctor", help="Inspect relevant installed dependencies")
    diagnosis.add_argument("--bluetooth", action="store_true")
    for name in ("validate", "plan", "windows", "switch"):
        command = commands.add_parser(name)
        command.add_argument("config", type=Path)
        if name != "validate":
            command.add_argument("--workspace", required=True)
        if name == "plan":
            command.add_argument("--state", type=Path, required=True)
            command.add_argument("--button", choices=BUTTONS, required=True)
            command.add_argument("--gesture", choices=GESTURES, required=True)
        if name == "switch":
            selection = command.add_mutually_exclusive_group(required=True)
            selection.add_argument("--direction", choices=("previous", "next"))
            selection.add_argument("--window")
    args = parser.parse_args()
    try:
        if args.command == "doctor":
            output(doctor(args.bluetooth))
            return
        config = load_config(args.config)
        if args.command == "validate":
            output({"valid": True, "workspaces": len(config["workspaces"]),
                    "voice_provider": config["voice_provider"],
                    "hardware_verified": False})
            return
        workspace = get_workspace(config, args.workspace)
        if args.command == "plan":
            output(plan_event(config, workspace, read_json(args.state), args.button, args.gesture))
        elif args.command == "windows":
            output({"workspace": workspace["id"], "windows": list_windows(workspace),
                    "visible_gui_verified": False})
        else:
            output(switch_window(workspace, args.direction, args.window))
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        output({"error": str(error), "action_completed": False})
        sys.exit(2)


if __name__ == "__main__":
    main()
