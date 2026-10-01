import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills/vibe-remote/scripts/vibe_remote.py"
spec = importlib.util.spec_from_file_location("vibe_remote", SCRIPT)
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


class FakeTmux:
    def __init__(self, fail_verification=False, malformed=False):
        self.current = "@2"
        self.calls = []
        self.fail_verification = fail_verification
        self.malformed = malformed

    def __call__(self, command, **kwargs):
        self.calls.append(command)
        if command[1] == "list-windows":
            if self.malformed:
                stdout = "invalid\twindow\n"
            else:
                stdout = "\n".join(
                    f"{wid}\t{index}\t{int(wid == self.current)}\t{name}"
                    for wid, index, name in (("@2", 1, "AI A"), ("@7", 4, "AI B")))
            return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")
        if command[1] == "select-window":
            if not self.fail_verification:
                self.current = command[-1].rsplit(":", 1)[1]
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        raise AssertionError(command)


class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "skills/vibe-remote/assets/config.default.json").read_text())
        self.app = dict(self.config["workspaces"][0], verified=True,
                        window_title="Project", task_anchor="Task A")
        self.cli = dict(self.config["workspaces"][2], verified=True, tmux_session="coding")
        self.state = dict(connected=True, target_id=self.app["id"], target_confirmed=True,
                          context="ai_input", runtime="draft", recording=False, has_draft=True)

    def plan(self, button, gesture="click", workspace=None, **changes):
        state = dict(self.state, **changes)
        return remote.plan_event(self.config, workspace or self.app, state, button, gesture)

    def test_template_is_valid_but_not_verified(self):
        self.assertEqual(remote.validate_config(self.config), [])
        result = self.plan("ok", workspace=self.config["workspaces"][0])
        self.assertFalse(result["allowed"])

    def test_provider_start_lifecycles_differ(self):
        self.assertIn("hold_provider_key", self.plan("mic", "hold")["actions"])
        self.config["voice_provider"] = "typeless"
        actions = self.plan("mic", "hold")["actions"]
        self.assertIn("tap_provider_key", actions)
        self.assertNotIn("hold_provider_key", actions)

    def test_release_finishes_without_submit_even_when_disconnected(self):
        result = self.plan("mic", "release", recording=True, connected=False, target_id="other")
        self.assertTrue(result["allowed"])
        self.assertEqual(result["intent"], "finish_draft")
        self.assertEqual(result["actions"][-1], "retain_draft")
        self.assertIn("release_provider_key", result["actions"])
        self.assertNotIn("invoke_observed_send", result["actions"])
        self.config["voice_provider"] = "typeless"
        self.assertIn("tap_provider_key",
                      self.plan("mic", "release", recording=True)["actions"])

    def test_release_without_recording_is_blocked(self):
        self.assertFalse(self.plan("mic", "release")["allowed"])

    def test_repeated_release_cannot_toggle_provider_again(self):
        self.config["voice_provider"] = "typeless"
        self.assertFalse(self.plan("mic", "release", recording=True, repeated=True)["allowed"])

    def test_send_rejects_shell_unknown_wrong_target_and_recording(self):
        cases = [dict(context="shell"), dict(context="unknown"), dict(target_id="other"),
                 dict(target_confirmed=False), dict(connected=False), dict(recording=True),
                 dict(runtime="running"), dict(has_draft=False), dict(repeated=True)]
        for change in cases:
            with self.subTest(change=change):
                self.assertFalse(self.plan("ok", **change)["allowed"])

    def test_selector_confirmation_does_not_send(self):
        self.assertFalse(self.plan("ok", context="selection")["allowed"])
        result = self.plan("ok", context="selection", selection_confirmed=True)
        self.assertEqual(result["intent"], "confirm_selection")
        self.assertNotIn("invoke_observed_send", result["actions"])

    def test_stop_needs_running_identified_ai_and_does_not_repeat(self):
        self.assertFalse(self.plan("back", "hold", runtime="ready",
                                   ai_process_confirmed=True)["allowed"])
        self.assertFalse(self.plan("back", "hold", runtime="running")["allowed"])
        self.assertTrue(self.plan("back", "hold", runtime="running",
                                  ai_process_confirmed=True)["allowed"])
        self.assertFalse(self.plan("back", "hold", runtime="running",
                                   ai_process_confirmed=True, repeated=True)["allowed"])
        self.assertFalse(self.plan("back", "release")["allowed"])
        for context in ("shell", "unknown"):
            self.assertFalse(self.plan("back", "hold", runtime="running", context=context,
                                       ai_process_confirmed=True)["allowed"])

    def test_cli_submission_needs_an_identified_ai(self):
        arguments = dict(workspace=self.cli, target_id=self.cli["id"])
        self.assertFalse(self.plan("ok", **arguments)["allowed"])
        result = self.plan("ok", ai_process_confirmed=True, **arguments)
        self.assertEqual(result["intent"], "submit_draft")

    def test_invalid_provider_type_is_a_validation_error(self):
        self.config["voice_provider"] = ["doubao"]
        self.assertTrue(remote.validate_config(self.config))

    def test_navigation_is_blocked_during_capture(self):
        for button in ("right", "home", "power", "menu", "tv"):
            self.assertFalse(self.plan(button, recording=True)["allowed"])

    def test_actions_require_confirmed_inactive_recording(self):
        actions = (("mic", "hold", {}), ("ok", "click", {}),
                   ("right", "click", {}), ("power", "click", {}),
                   ("back", "hold", {"runtime": "running", "ai_process_confirmed": True}))
        for button, gesture, changes in actions:
            self.assertTrue(self.plan(button, gesture, **changes)["allowed"])
            for recording in ("missing", None, 0, "unknown"):
                with self.subTest(button=button, gesture=gesture, recording=recording):
                    state = dict(self.state, **changes)
                    if recording == "missing":
                        state.pop("recording")
                    else:
                        state["recording"] = recording
                    result = remote.plan_event(self.config, self.app, state, button, gesture)
                    self.assertFalse(result["allowed"])

    def test_initial_workspace_picker_requires_confirmed_inactive_recording(self):
        workspace = self.config["workspaces"][0]
        self.assertTrue(self.plan("power", workspace=workspace, connected=False,
                                  target_confirmed=False)["allowed"])
        for recording in ("missing", None, 0, "unknown"):
            with self.subTest(recording=recording):
                state = dict(self.state, connected=False, target_confirmed=False)
                if recording == "missing":
                    state.pop("recording")
                else:
                    state["recording"] = recording
                result = remote.plan_event(self.config, workspace, state, "power", "click")
                self.assertFalse(result["allowed"])

    def test_power_click_must_not_repeat(self):
        for workspace in (self.app, self.config["workspaces"][0]):
            with self.subTest(verified=workspace["verified"]):
                self.assertFalse(self.plan("power", workspace=workspace,
                                           repeated=True)["allowed"])

    def test_recording_cleanup_remains_allowed_after_disconnect(self):
        for provider, finish in (("doubao", "release_provider_key"),
                                 ("typeless", "tap_provider_key")):
            self.config["voice_provider"] = provider
            for button, gesture, intent in (("mic", "release", "finish_draft"),
                                             ("back", "click", "cancel_dictation_segment")):
                with self.subTest(provider=provider, button=button):
                    result = self.plan(button, gesture, recording=True, connected=False,
                                       target_id="other", target_confirmed=False)
                    self.assertTrue(result["allowed"])
                    self.assertEqual(result["intent"], intent)
                    self.assertIn(finish, result["actions"])
                    self.assertNotIn("invoke_observed_send", result["actions"])

    def test_volume_does_not_require_recording_observation(self):
        for recording in ("missing", None, 0, "unknown", True):
            for button in ("volume_up", "volume_down"):
                with self.subTest(recording=recording, button=button):
                    state = dict(self.state, connected=False, target_confirmed=False,
                                 repeated=True)
                    if recording == "missing":
                        state.pop("recording")
                    else:
                        state["recording"] = recording
                    result = remote.plan_event(self.config, self.config["workspaces"][0],
                                               state, button, "hold")
                    self.assertTrue(result["allowed"])
                    self.assertEqual(result["actions"], ["adjust_system_volume"])

    def test_app_and_cli_have_different_switch_intentions(self):
        self.assertEqual(self.plan("right")["intent"], "task_next")
        self.assertEqual(self.plan("right", workspace=self.cli,
                                   target_id=self.cli["id"])["intent"], "window_next")

    def test_tmux_selects_stable_id_across_nonconsecutive_indices_and_verifies(self):
        runner = FakeTmux()
        result = remote.switch_window(self.cli, direction="next", runner=runner)
        self.assertTrue(result["changed"])
        self.assertEqual(result["window"], "@7")
        self.assertEqual(runner.calls[0][3], "=coding")
        self.assertEqual(runner.calls[1], ["tmux", "select-window", "-t", "=coding:@7"])
        self.assertEqual(len(runner.calls), 3)
        self.assertFalse(result["visible_gui_verified"])

    def test_tmux_boundary_does_not_wrap_or_mutate(self):
        runner = FakeTmux()
        result = remote.switch_window(self.cli, direction="previous", runner=runner)
        self.assertFalse(result["changed"])
        self.assertEqual(len(runner.calls), 1)

    def test_tmux_rejects_other_session_window(self):
        runner = FakeTmux()
        with self.assertRaises(ValueError):
            remote.switch_window(self.cli, window_id="@999", runner=runner)
        self.assertEqual(len(runner.calls), 1)

    def test_malformed_tmux_output_never_selects(self):
        runner = FakeTmux(malformed=True)
        with self.assertRaises(RuntimeError):
            remote.switch_window(self.cli, direction="next", runner=runner)
        self.assertEqual(len(runner.calls), 1)

    def test_failed_verification_is_reported_without_retry(self):
        runner = FakeTmux(fail_verification=True)
        with self.assertRaisesRegex(RuntimeError, "could not be verified"):
            remote.switch_window(self.cli, direction="next", runner=runner)
        self.assertEqual(len(runner.calls), 3)

    def test_ssh_and_session_argument_injection_rejected(self):
        for host in ("-oProxyCommand=bad", "mini;echo bad", "mini$(bad)", "user@host"):
            with self.subTest(host=host), self.assertRaises(ValueError):
                remote.require_tmux_binding(dict(self.cli, host=host))
        for session in ("coding:1", "-a", "coding;echo", "coding$(bad)"):
            with self.subTest(session=session), self.assertRaises(ValueError):
                remote.require_tmux_binding(dict(self.cli, tmux_session=session))

    def test_remote_command_is_one_quoted_literal(self):
        args = ["list-windows", "-t", "=coding", "-F", "#{window_id}\t#{window_name}"]
        command = remote.command_for(dict(self.cli, host="mini"), args)
        self.assertEqual(command[:7], ["ssh", "-o", "BatchMode=yes", "-o",
                                      "ConnectTimeout=8", "--", "mini"])
        import shlex
        self.assertEqual(shlex.split(command[7]), ["tmux"] + args)
        self.assertEqual(len(command), 8)

    def test_verified_app_requires_observed_window_and_task(self):
        self.config["workspaces"][0]["verified"] = True
        self.assertTrue(remote.validate_config(self.config))
        self.config["workspaces"][0] = self.app
        self.assertEqual(remote.validate_config(self.config), [])

    def test_installer_is_idempotent_and_refuses_unrelated_skill(self):
        with tempfile.TemporaryDirectory() as temp:
            args = ["python3", str(ROOT / "scripts/install_skill.py"), "--destination", temp]
            installed = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertEqual(subprocess.run(args, capture_output=True).returncode, 0)
            target = Path(temp) / "vibe-remote"
            target.unlink()
            target.mkdir()
            marker = target / "keep.txt"
            marker.write_text("existing user content")
            rejected = subprocess.run(args, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(marker.read_text(), "existing user content")


class BluetoothDoctorTests(unittest.TestCase):
    def candidates(self, inventory):
        result = subprocess.CompletedProcess(
            ["system_profiler", "SPBluetoothDataType", "-json"], 0,
            stdout=json.dumps(inventory), stderr="")
        with patch.object(remote.platform, "system", return_value="Darwin"), \
                patch.object(remote.Path, "is_dir", return_value=False), \
                patch.object(remote.subprocess, "run", return_value=result):
            return remote.doctor(scan_bluetooth=True)["bluetooth_candidates"]

    def test_keyed_device_names_use_connected_and_disconnected_categories(self):
        inventory = {"SPBluetoothDataType": [{
            "device_connected": [{"小米蓝牙语音遥控器": {"device_paired": "attrib_yes"}},
                                 {"Keyboard": {"device_paired": "attrib_yes"}}],
            "device_not_connected": [{"Mi RC 2": {"device_paired": "attrib_yes"}}]
        }]}
        self.assertEqual(self.candidates(inventory), [
            {"name": "小米蓝牙语音遥控器", "connected": True},
            {"name": "Mi RC 2", "connected": False}])

    def test_legacy_names_normalize_explicit_connection_fields(self):
        inventory = {"SPBluetoothDataType": [{"_items": [
            {"_name": "Mi RC", "device_connected": "attrib_yes"},
            {"_name": "Xiaomi Remote Legacy", "connected": False},
            {"_name": "Mi RC Disconnected", "connected": "No"}
        ]}]}
        self.assertEqual(self.candidates(inventory), [
            {"name": "Mi RC", "connected": True},
            {"name": "Xiaomi Remote Legacy", "connected": False},
            {"name": "Mi RC Disconnected", "connected": False}])

    def test_paired_or_unknown_state_does_not_imply_connected(self):
        inventory = {"devices": [
            {"Xiaomi Remote": {"device_paired": "attrib_yes"}},
            {"Mi RC Unknown": {"connected": "unknown"}},
            {"_name": "Remote Numeric", "connected": 1}
        ]}
        self.assertEqual(self.candidates(inventory), [
            {"name": "Xiaomi Remote", "connected": None},
            {"name": "Mi RC Unknown", "connected": None},
            {"name": "Remote Numeric", "connected": None}])

    def test_bluetooth_output_contains_only_names_and_connection_states(self):
        inventory = {"_items": [{
            "_name": "Mi RC", "connected": True,
            "device_address": "private-address", "device_serialNumber": "private-serial"
        }]}
        candidates = self.candidates(inventory)
        self.assertEqual(candidates, [{"name": "Mi RC", "connected": True}])
        serialized = json.dumps(candidates)
        self.assertNotIn("private-address", serialized)
        self.assertNotIn("private-serial", serialized)


if __name__ == "__main__":
    unittest.main()
