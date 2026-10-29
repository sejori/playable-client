class_name SceneLoader
extends Node
## scene_loader.gd
## Universal Generic Scene Loader for Playable cartridges.
## Dynamically boots target scene specified via --scene=<path> CLI flag
## or specs/interface_contracts.json, falling back safely to fire_prison_rig.tscn.

const FALLBACK_SCENE: String = "res://scenes/zones/fire_prison_rig.tscn"
const CONTRACTS_PATH: String = "res://specs/interface_contracts.json"

func _ready() -> void:
	var target_scene := resolve_target_scene()
	_boot_scene(target_scene)

static func resolve_target_scene() -> String:
	# 1. Check command line arguments for --scene=<path>
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--scene="):
			var raw_scene := arg.trim_prefix("--scene=").strip_edges()
			if not raw_scene.is_empty():
				if raw_scene.begins_with("res://"):
					return raw_scene
				elif not raw_scene.begins_with("user://") and not raw_scene.begins_with("/"):
					return "res://" + raw_scene.trim_prefix("./")
				return raw_scene

	# 2. Check specs/interface_contracts.json -> target_scene
	if FileAccess.file_exists(CONTRACTS_PATH):
		var file := FileAccess.open(CONTRACTS_PATH, FileAccess.READ)
		if file != null:
			var content := file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(content)
			if parsed is Dictionary and parsed.has("target_scene"):
				var contract_scene := str(parsed["target_scene"]).strip_edges()
				if not contract_scene.is_empty():
					return contract_scene

	# 3. Fallback safely
	return FALLBACK_SCENE

func _boot_scene(scene_path: String) -> void:
	var path_to_load := scene_path
	if not ResourceLoader.exists(path_to_load):
		push_warning("SceneLoader: Scene '%s' not found. Falling back to '%s'." % [path_to_load, FALLBACK_SCENE])
		path_to_load = FALLBACK_SCENE

	var packed := load(path_to_load) as PackedScene
	if packed == null and path_to_load != FALLBACK_SCENE:
		push_error("SceneLoader: Failed to load PackedScene at '%s'. Trying fallback '%s'." % [path_to_load, FALLBACK_SCENE])
		path_to_load = FALLBACK_SCENE
		packed = load(path_to_load) as PackedScene

	if packed != null:
		var err := get_tree().change_scene_to_packed(packed)
		if err != OK:
			push_error("SceneLoader: change_scene_to_packed failed with error: %d" % err)
	else:
		push_error("SceneLoader: Fatal: Failed to load target scene and fallback scene.")
