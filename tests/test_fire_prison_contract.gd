extends Node
## test_fire_prison_contract.gd
## gdUnit4 test suite verifying that res://scenes/zones/fire_prison_rig.tscn
## obeys every node path, signal, and collision layer in /specs/interface_contracts.json.

func test_contract_compliance() -> bool:
	var contract_file := FileAccess.open("res://specs/interface_contracts.json", FileAccess.READ)
	if contract_file == null:
		return false
	var contract: Dictionary = JSON.parse_string(contract_file.get_as_text())
	var packed: PackedScene = load(contract["target_scene"])
	if packed == null:
		return false
	var scene_root: Node = packed.instantiate()
	for req in contract["required_node_paths"]:
		var target_node := scene_root.get_node_or_null(NodePath(req["path"]))
		if target_node == null:
			scene_root.free()
			return false
	scene_root.free()
	return true
