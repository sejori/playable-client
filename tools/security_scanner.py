#!/usr/bin/env python3
"""
security_scanner.py — Pre-Export Static AST & Resource Sandbox Linter
Enforces Section 2 & Section 8 (CLAUDE.md) rules before any branch is exported to a .pck:
- Strips comments properly while preserving string literals and newlines, and scans across full
  multiline file content (handling multiline expressions like `OS.\\nexecute(`) as well as line-by-line.
- Blocks OS.execute(), OS.create_process(), OS.create_instance(), OS.shell_open(), OS.kill()
- Blocks reflection/dynamic dispatch bypasses: OS.call(, OS.callv(, OS.call_deferred(, Callable(OS,
  ClassDB.instantiate("OS"), ClassDB.class_call_static("OS", load("user://, ResourceLoader.load(,
  JavaScriptBridge.eval(
- Blocks dynamic GDScript.source_code eval injection and inline GDScript sub-resources in .tscn/.tres
  (script/source = ... or [sub_resource type="GDScript"])
- Blocks native GDExtension (.dll, .so, .dylib, .gdextension) inside user .pck resources
- Validates both literal and dynamic/non-literal FileAccess.open / DirAccess.open / make_dir_recursive_absolute
  paths (rejecting variable/concatenated paths unless restricted to res:// or validated via BootLoader)
- Blocks deprecated Godot 3/4.5 symbols (OpenSimplexNoise, SkeletonIK3D)
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

FORBIDDEN_PATTERNS: List[Tuple[str, str]] = [
    (r"\bOS\s*\.\s*execute\s*\(", "Forbidden OS.execute() call"),
    (r"\bOS\s*\.\s*create_process\s*\(", "Forbidden OS.create_process() call"),
    (r"\bOS\s*\.\s*create_instance\s*\(", "Forbidden OS.create_instance() call"),
    (r"\bOS\s*\.\s*shell_open\s*\(", "Forbidden OS.shell_open() call"),
    (r"\bOS\s*\.\s*kill\s*\(", "Forbidden OS.kill() call"),
    (r"\bOS\s*\.\s*call\s*\(", "Forbidden reflection bypass OS.call()"),
    (r"\bOS\s*\.\s*callv\s*\(", "Forbidden reflection bypass OS.callv()"),
    (r"\bOS\s*\.\s*call_deferred\s*\(", "Forbidden reflection bypass OS.call_deferred()"),
    (r"\bCallable\s*\(\s*OS\b", "Forbidden reflection bypass Callable(OS, ...)"),
    (r"\bClassDB\s*\.\s*instantiate\s*\(\s*['\"]OS['\"]\s*\)", "Forbidden ClassDB.instantiate(\"OS\") bypass"),
    (r"\bClassDB\s*\.\s*class_call_static\s*\(\s*['\"]OS['\"]", "Forbidden ClassDB.class_call_static(\"OS\", ...) bypass"),
    (r"\bload\s*\(\s*['\"]user://", "Forbidden load(\"user://...\") arbitrary resource execution"),
    (r"\bResourceLoader\s*\.\s*load\s*\(", "Forbidden ResourceLoader.load() dynamic resource load"),
    (r"\bJavaScriptBridge\s*\.\s*eval\s*\(", "Forbidden JavaScriptBridge.eval() code execution"),
    (r"\.\s*source_code\s*=", "Forbidden dynamic GDScript.source_code injection"),
    (r"\bExpression\s*\.\s*new\s*\(", "Forbidden dynamic Expression eval"),
    (r"\bOpenSimplexNoise\b", "Deprecated Godot 3 OpenSimplexNoise (use FastNoiseLite per CLAUDE.md)"),
    (r"\bSkeletonIK3D\b", "Deprecated SkeletonIK3D (use IKModifier3D per CLAUDE.md)"),
]

INLINE_SUBRESOURCE_PATTERNS: List[Tuple[str, str]] = [
    (r"\bscript/source\s*=", "Forbidden inline GDScript sub-resource (script/source) in scene/resource file"),
    (r"\[sub_resource\s+type\s*=\s*['\"]GDScript['\"]", "Forbidden inline GDScript sub_resource in scene/resource file"),
]

FORBIDDEN_EXTENSIONS = {".dll", ".so", ".dylib", ".gdextension"}

FILE_DIR_CALL_RE = re.compile(
    r"\b(?:FileAccess|DirAccess)\s*\.\s*(?:open|make_dir_recursive_absolute)\s*\(([^,\n\)]+)",
    re.MULTILINE,
)


def strip_comments_preserving_newlines(content: str, ext: str) -> str:
    """
    Strips line comments (#, ;, //) and block comments (/* ... */) outside of string literals
    while preserving all newline characters so line numbers remain accurate.
    """
    result: List[str] = []
    i = 0
    n = len(content)
    in_string: str = ""
    in_line_comment = False
    in_block_comment = False

    while i < n:
        ch = content[i]

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                result.append("\n")
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and i + 1 < n and content[i + 1] == "/":
                in_block_comment = False
                i += 2
            else:
                if ch == "\n":
                    result.append("\n")
                i += 1
            continue

        if in_string:
            result.append(ch)
            if ch == "\\" and i + 1 < n:
                result.append(content[i + 1])
                i += 2
                continue
            if ch == in_string:
                in_string = ""
            i += 1
            continue

        # Not in string or comment
        if ch in ('"', "'"):
            in_string = ch
            result.append(ch)
            i += 1
            continue

        if ch == "#" and ext in {".gd", ".tscn", ".tres"}:
            in_line_comment = True
            i += 1
            continue

        if ch == ";" and ext in {".tscn", ".tres"}:
            in_line_comment = True
            i += 1
            continue

        if ch == "/" and i + 1 < n:
            nxt = content[i + 1]
            if nxt == "/":
                in_line_comment = True
                i += 2
                continue
            if nxt == "*":
                in_block_comment = True
                i += 2
                continue

        result.append(ch)
        i += 1

    return "".join(result)


def _is_literal_path_allowed(literal: str) -> bool:
    if ".." in literal:
        return False
    if literal.startswith("/") or re.match(r"^[A-Za-z]:", literal):
        return False
    if literal.startswith("res://"):
        return True
    if literal.startswith("user://realms/"):
        return True
    return False


def _collect_safe_path_variables(stripped_content: str, rel_path: str) -> Set[str]:
    """
    Identifies local GDScript variables assigned to safe sandboxed path expressions:
    - Variables initialized via `.validate_filename()` (e.g. `var safe_id := realm_id.validate_filename()`)
    - Variables initialized as `"res://..." + ...` (without `..`)
    - Variables initialized as `"user://realms/" + BootLoader...` or `"user://realms/" + <validated_var>...`
    """
    safe_identifiers: Set[str] = set()
    var_assign_re = re.compile(
        r"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z0-9_]+)?\s*:?=\s*([^\n]+)"
    )

    # Pass 1: find identifiers sanitized via .validate_filename()
    for match in var_assign_re.finditer(stripped_content):
        var_name, rhs = match.group(1), match.group(2).strip()
        if ".validate_filename()" in rhs:
            safe_identifiers.add(var_name)

    # Pass 2: find path variables built from res:// or user://realms/ + BootLoader / safe_identifiers
    for _ in range(2):
        for match in var_assign_re.finditer(stripped_content):
            var_name, rhs = match.group(1), match.group(2).strip()
            if _is_path_expression_allowed(rhs, safe_identifiers, rel_path):
                safe_identifiers.add(var_name)

    return safe_identifiers


def _is_path_expression_allowed(expr: str, safe_vars: Set[str], rel_path: str) -> bool:
    expr = expr.strip()
    if not expr:
        return False

    # Case 1: Single string literal
    single_lit = re.match(r'^["\']([^"\']*)["\']$', expr)
    if single_lit:
        return _is_literal_path_allowed(single_lit.group(1))

    # Case 2: Known safe variable
    if expr in safe_vars:
        return True

    # Reject any expression containing '..'
    for lit in re.findall(r'["\']([^"\']*)["\']', expr):
        if ".." in lit:
            return False

    # Case 3: Concatenation starting with "res://"
    if re.match(r'^["\']res://[^"\']*["\']\s*\+', expr):
        return True

    # Case 4: Concatenation starting with "user://realms/" validated via BootLoader or safe_vars
    if re.match(r'^["\']user://realms/[^"\']*["\']\s*\+', expr):
        if "BootLoader." in expr or rel_path.endswith("BootLoader.gd"):
            return True
        for sv in safe_vars:
            if re.search(rf"\b{re.escape(sv)}\b", expr):
                return True

    return False


def scan_file_content(content: str, rel_path: str, ext: str) -> List[Dict[str, object]]:
    violations: List[Dict[str, object]] = []
    stripped = strip_comments_preserving_newlines(content, ext)
    seen: Set[Tuple[int, str, str]] = set()

    def add_violation(line_no: int, rule: str, detail: str) -> None:
        key = (line_no, rule, detail)
        if key not in seen:
            seen.add(key)
            violations.append({
                "file": rel_path,
                "line": line_no,
                "rule": rule,
                "detail": detail,
            })

    # 1. Check inline GDScript sub-resources in .tscn / .tres
    if ext in {".tscn", ".tres"}:
        for pattern, reason in INLINE_SUBRESOURCE_PATTERNS:
            for match in re.finditer(pattern, stripped, flags=re.MULTILINE):
                line_num = stripped.count("\n", 0, match.start()) + 1
                add_violation(line_num, "AST_SANDBOX_VIOLATION", reason)

    # Also prepare an unescaped view for .tscn/.tres so escaped strings inside resources are caught
    surfaces = [stripped]
    if ext in {".tscn", ".tres"} and ('\\"' in stripped or "\\n" in stripped):
        unescaped = stripped.replace('\\"', '"').replace("\\t", " ")
        surfaces.append(unescaped)

    # 2. Scan across full comment-stripped content (catches multiline expressions like `OS.\nexecute(`)
    for surface in surfaces:
        for pattern, reason in FORBIDDEN_PATTERNS:
            for match in re.finditer(pattern, surface, flags=re.MULTILINE | re.DOTALL):
                line_num = surface.count("\n", 0, match.start()) + 1
                add_violation(line_num, "AST_SANDBOX_VIOLATION", reason)

    # 3. Validate FileAccess.open / DirAccess.open / make_dir_recursive_absolute calls (literal & dynamic)
    safe_vars = _collect_safe_path_variables(stripped, rel_path)
    for match in FILE_DIR_CALL_RE.finditer(stripped):
        line_num = stripped.count("\n", 0, match.start()) + 1
        arg_expr = match.group(1).strip()
        if not _is_path_expression_allowed(arg_expr, safe_vars, rel_path):
            add_violation(
                line_num,
                "SANDBOX_PATH_ESCAPE",
                f"Path expression '{arg_expr}' in FileAccess/DirAccess is outside user://realms/<realm_id>/ or res:// sandbox.",
            )

    return violations


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

            file_violations = scan_file_content(content, rel_path, ext)
            violations.extend(file_violations)

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
