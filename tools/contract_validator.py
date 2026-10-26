#!/usr/bin/env python3
"""
contract_validator.py — Headless Scene & Interface Contract Validator
Verifies that target .tscn scenes and bound .gd scripts strictly satisfy
every node path, type, collision layer, group, and signal in /specs/interface_contracts.json.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List


def parse_tscn_nodes(tscn_text: str) -> Dict[str, Dict[str, object]]:
    nodes: Dict[str, Dict[str, object]] = {}
    current_node_path = None
    current_attrs: Dict[str, object] = {}

    for raw_line in tscn_text.splitlines():
        line = raw_line.strip()
        if line.startswith("[node "):
            if current_node_path is not None:
                nodes[current_node_path] = current_attrs

            name_match = re.search(r'name="([^"]+)"', line)
            type_match = re.search(r'type="([^"]+)"', line)
            parent_match = re.search(r'parent="([^"]+)"', line)
            groups_match = re.search(r'groups=\[([^\]]+)\]', line)

            name = name_match.group(1) if name_match else "Root"
            node_type = type_match.group(1) if type_match else "Node"
            parent = parent_match.group(1) if parent_match else None
            groups = [g.strip().strip('"') for g in groups_match.group(1).split(",")] if groups_match else []

            if parent is None:
                current_node_path = "."
            elif parent == ".":
                current_node_path = name
            else:
                current_node_path = f"{parent}/{name}"

            current_attrs = {
                "name": name,
                "type": node_type,
                "parent": parent,
                "groups": groups,
                "properties": {}
            }
        elif line.startswith("[") and not line.startswith("[node "):
            if current_node_path is not None:
                nodes[current_node_path] = current_attrs
                current_node_path = None
        elif current_node_path is not None and "=" in line:
            k, v = [p.strip() for p in line.split("=", 1)]
            current_attrs["properties"][k] = v

    if current_node_path is not None:
        nodes[current_node_path] = current_attrs

    return nodes


def validate_contract(root_dir: Path) -> Dict[str, object]:
    contract_path = root_dir / "specs" / "interface_contracts.json"
    if not contract_path.exists():
        return {"status": "FAIL", "errors": ["Missing specs/interface_contracts.json"]}

    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    errors: List[str] = []

    target_rel = contract["target_scene"].replace("res://", "")
    scene_path = root_dir / target_rel
    if not scene_path.exists():
        return {"status": "FAIL", "errors": [f"Missing target scene: {target_rel}"]}

    tscn_text = scene_path.read_text(encoding="utf-8")
    nodes = parse_tscn_nodes(tscn_text)

    # Check root node type
    root_node = nodes.get(".")
    if not root_node or root_node["type"] != contract["root_node_type"]:
        errors.append(f"Root node type mismatch: expected {contract['root_node_type']}")

    # Check bound script
    bound_script = contract.get("bound_script", "")
    if bound_script and bound_script not in tscn_text:
        errors.append(f"Bound script '{bound_script}' not referenced in {target_rel}")

    # Check required node paths
    for req in contract.get("required_node_paths", []):
        req_path = req["path"]
        req_type = req["type"]
        if req_path not in nodes:
            errors.append(f"Missing required node path '{req_path}' ({req_type})")
            continue
        node_info = nodes[req_path]
        if node_info["type"] != req_type:
            errors.append(f"Node '{req_path}' has type '{node_info['type']}', expected '{req_type}'")
        if "collision_layer" in req:
            expected_layer = str(req["collision_layer"])
            actual_layer = str(node_info["properties"].get("collision_layer", "1"))
            if actual_layer != expected_layer:
                errors.append(f"Node '{req_path}' collision_layer={actual_layer}, expected {expected_layer}")
        if "group" in req:
            if req["group"] not in node_info["groups"]:
                errors.append(f"Node '{req_path}' missing required group '{req['group']}'")

    # Check required signals
    for sig in contract.get("required_signals", []):
        src = sig["source_node"]
        sig_name = sig["signal"].split("(")[0].strip()
        conn_pattern = f'connection signal="{sig_name}" from="{src}"'
        if conn_pattern not in tscn_text:
            errors.append(f"Missing signal connection: {sig_name} from {src}")

    return {
        "status": "PASS" if len(errors) == 0 else "FAIL",
        "sprint_id": contract.get("sprint_id"),
        "target_scene": contract.get("target_scene"),
        "passed": len(contract.get("required_node_paths", [])) + len(contract.get("required_signals", [])) + 2 - len(errors),
        "failed": len(errors),
        "errors": errors,
    }


def main() -> int:
    target = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    report = validate_contract(target)
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
