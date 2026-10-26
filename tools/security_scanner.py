#!/usr/bin/env python3
"""
security_scanner.py — Pre-Export Static AST & Resource Sandbox Linter
Enforces Section 2 & Section 8 (CLAUDE.md) rules before any branch is exported to a .pck:
- Blocks OS.execute(), OS.create_process(), OS.shell_open(), OS.kill()
- Blocks dynamic GDScript.source_code eval injection
- Blocks native GDExtension (.dll, .so, .dylib, .gdextension) inside user .pck resources
- Blocks FileAccess / DirAccess paths outside user://realms/ or res:// (read-only)
- Blocks deprecated Godot 3/4.5 symbols (OpenSimplexNoise, SkeletonIK3D)
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List

FORBIDDEN_PATTERNS = [
    (r"\bOS\s*\.\s*execute\s*\(", "Forbidden OS.execute() call"),
    (r"\bOS\s*\.\s*create_process\s*\(", "Forbidden OS.create_process() call"),
    (r"\bOS\s*\.\s*shell_open\s*\(", "Forbidden OS.shell_open() call"),
    (r"\bOS\s*\.\s*kill\s*\(", "Forbidden OS.kill() call"),
    (r"\.source_code\s*=", "Forbidden dynamic GDScript.source_code injection"),
    (r"\bExpression\s*\.\s*new\s*\(", "Forbidden dynamic Expression eval"),
    (r"\bOpenSimplexNoise\b", "Deprecated Godot 3 OpenSimplexNoise (use FastNoiseLite per CLAUDE.md)"),
    (r"\bSkeletonIK3D\b", "Deprecated SkeletonIK3D (use IKModifier3D per CLAUDE.md)"),
]

FORBIDDEN_EXTENSIONS = {".dll", ".so", ".dylib", ".gdextension"}


def scan_repository(root_dir: Path) -> Dict[str, object]:
    violations: List[Dict[str, object]] = []
    files_scanned = 0

    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Skip .git, build, and tools directories
        dirnames[:] = [d for d in dirnames if d not in {".git", "build", ".godot", "tools", "__pycache__"}]
        for fname in filenames:
            fpath = Path(dirpath) / fname
            rel_path = fpath.relative_to(root_dir).as_posix()
            ext = fpath.suffix.lower()

            if ext in FORBIDDEN_EXTENSIONS:
                violations.append({
                    "file": rel_path,
                    "line": 1,
                    "rule": "NO_NATIVE_GDEXTENSION_IN_PCK",
                    "detail": f"Native binary/extension '{fname}' is prohibited inside user .pck bundles."
                })
                continue

            if ext not in {".gd", ".tscn", ".tres", ".gdshader"}:
                continue

            files_scanned += 1
            try:
                content = fpath.read_text(encoding="utf-8")
            except Exception as exc:
                violations.append({
                    "file": rel_path,
                    "line": 1,
                    "rule": "ENCODING_ERROR",
                    "detail": str(exc)
                })
                continue

            for line_num, line in enumerate(content.splitlines(), start=1):
                stripped = line.strip()
                if stripped.startswith("#") or stripped.startswith("//") or stripped.startswith(";"):
                    continue
                for pattern, reason in FORBIDDEN_PATTERNS:
                    if re.search(pattern, line):
                        violations.append({
                            "file": rel_path,
                            "line": line_num,
                            "rule": "AST_SANDBOX_VIOLATION",
                            "detail": reason
                        })

                # Check literal FileAccess.open or DirAccess paths
                if "FileAccess.open" in line or "DirAccess.open" in line or "make_dir_recursive_absolute" in line:
                    for literal in re.findall(r'"([^"]+)"', line):
                        if (
                            literal.startswith("/")
                            or literal.startswith("C:")
                            or literal.startswith("..")
                            or (literal.startswith("user://") and not literal.startswith("user://realms/"))
                        ):
                            violations.append({
                                "file": rel_path,
                                "line": line_num,
                                "rule": "SANDBOX_PATH_ESCAPE",
                                "detail": f"Path '{literal}' escapes user://realms/<realm_id>/ sandbox."
                            })

    status = "PASS" if len(violations) == 0 else "FAIL"
    return {
        "status": status,
        "files_scanned": files_scanned,
        "violation_count": len(violations),
        "violations": violations,
    }


def main() -> int:
    target = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    report = scan_repository(target)
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
