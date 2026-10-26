#!/usr/bin/env python3
"""
Unit tests for playable-client/tools/security_scanner.py
Verifies that all sandbox escape and reflection/multiline bypass vectors in Section 2.4 are blocked
while legitimate client code passes cleanly.
"""

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent.parent / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import security_scanner  # noqa: E402


class TestSecurityScanner(unittest.TestCase):
    def _scan_snippet(self, filename: str, content: str):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            file_path = root / filename
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(content, encoding="utf-8")
            return security_scanner.scan_repository(root)

    def test_clean_repository_passes(self):
        repo_root = Path(__file__).resolve().parent.parent
        report = security_scanner.scan_repository(repo_root)
        self.assertEqual(report["status"], "PASS", f"Unexpected violations: {report['violations']}")
        self.assertEqual(report["violation_count"], 0)

    def test_multiline_os_execute_blocked(self):
        code = """extends Node
func _ready() -> void:
    OS.
        # sneaky comment between OS. and execute
        execute("sh", ["-c", "id"])
"""
        report = self._scan_snippet("scripts/exploit.gd", code)
        self.assertEqual(report["status"], "FAIL")
        self.assertGreaterEqual(report["violation_count"], 1)

    def test_reflection_and_dynamic_dispatch_bypasses_blocked(self):
        vectors = [
            'OS.call("execute", "sh")',
            'OS.callv("execute", ["sh"])',
            'OS.call_deferred("shell_open", "http://evil.tld")',
            'var fn = Callable(OS, "execute")',
            'var inst = ClassDB.instantiate("OS")',
            'var r = load("user://malicious.tres")',
            'var r2 = ResourceLoader.load("user://payload.tscn")',
            'JavaScriptBridge.eval("window.location=\'https://evil.tld\'")',
        ]
        for snippet in vectors:
            with self.subTest(snippet=snippet):
                code = f"extends Node\nfunc _ready() -> void:\n\t{snippet}\n"
                report = self._scan_snippet("scripts/bypass.gd", code)
                self.assertEqual(report["status"], "FAIL", f"Bypass not caught: {snippet}")

    def test_inline_gdscript_subresource_in_tscn_and_tres_blocked(self):
        tscn_content = """[gd_scene load_steps=2 format=3]
[sub_resource type="GDScript" id="GDScript_1"]
script/source = "extends Node\\nfunc _ready():\\n\\tOS.execute('calc.exe', [])\\n"
[node name="Root" type="Node3D"]
script = SubResource("GDScript_1")
"""
        report = self._scan_snippet("scenes/injected.tscn", tscn_content)
        self.assertEqual(report["status"], "FAIL")
        self.assertGreaterEqual(report["violation_count"], 1)

        tres_content = """[gd_resource type="Resource" format=3]
[sub_resource type="GDScript" id="GDScript_evil"]
script/source = "extends Resource\\n"
"""
        report_tres = self._scan_snippet("resources/injected.tres", tres_content)
        self.assertEqual(report_tres["status"], "FAIL")

    def test_dynamic_and_non_literal_file_access_paths_validated(self):
        # 1. Arbitrary variable path must fail
        bad_var_code = """extends Node
func read_secret(user_supplied_path: String) -> void:
    var f := FileAccess.open(user_supplied_path, FileAccess.READ)
"""
        self.assertEqual(self._scan_snippet("scripts/bad_var.gd", bad_var_code)["status"], "FAIL")

        # 2. Concatenated user:// escape must fail
        bad_concat_code = """extends Node
func write_escape(sub: String) -> void:
    var f := FileAccess.open("user://" + sub, FileAccess.WRITE)
"""
        self.assertEqual(self._scan_snippet("scripts/bad_concat.gd", bad_concat_code)["status"], "FAIL")

        # 3. Dynamic DirAccess.open must fail
        bad_dir_code = """extends Node
func list_root(target_dir: String) -> void:
    var d := DirAccess.open(target_dir)
"""
        self.assertEqual(self._scan_snippet("scripts/bad_dir.gd", bad_dir_code)["status"], "FAIL")

        # 4. Path traversal in res:// must fail
        traversal_code = """extends Node
func read_traversal() -> void:
    var f := FileAccess.open("res://../../etc/passwd", FileAccess.READ)
"""
        self.assertEqual(self._scan_snippet("scripts/traversal.gd", traversal_code)["status"], "FAIL")

        # 5. Validated BootLoader user://realms/ path or res:// path must pass
        valid_code = """extends Node
func write_log() -> void:
    var log_path := "user://realms/" + BootLoader.active_realm_id + "/telemetry.jsonl"
    var f := FileAccess.open(log_path, FileAccess.WRITE)
    var cfg := FileAccess.open("res://specs/gdd_design.json", FileAccess.READ)
"""
        self.assertEqual(self._scan_snippet("scripts/valid_io.gd", valid_code)["status"], "PASS")

    def test_comments_do_not_trigger_false_positives(self):
        comment_only = """extends Node
# OS.execute("rm", ["-rf", "/"])
# JavaScriptBridge.eval("alert(1)")
func _ready() -> void:
    var color := "#0f172a"
"""
        report = self._scan_snippet("scripts/commented.gd", comment_only)
        self.assertEqual(report["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
