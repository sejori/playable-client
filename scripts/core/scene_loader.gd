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
	_boot_scene.call_deferred(target_scene)

static func resolve_target_scene() -> String:
	# 1. Check command line arguments for --scene=<path>
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for i in range(all_args.size()):
		var arg := all_args[i]
		var raw_scene := ""
		if arg.begins_with("--scene="):
			raw_scene = arg.trim_prefix("--scene=").strip_edges()
		elif arg.begins_with("scene="):
			raw_scene = arg.trim_prefix("scene=").strip_edges()
		elif arg == "--scene" and i + 1 < all_args.size():
			raw_scene = all_args[i + 1].strip_edges()

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
				if not contract_scene.is_empty() and contract_scene != FALLBACK_SCENE and ResourceLoader.exists(contract_scene):
					return contract_scene

	# 3. Check for any autonomous zone scene in res://scenes/zones/ other than fallback
	var dir := DirAccess.open("res://scenes/zones/")
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".tscn") and file_name != "fire_prison_rig.tscn":
				dir.list_dir_end()
				return "res://scenes/zones/" + file_name
			file_name = dir.get_next()
		dir.list_dir_end()

	# 4. Fallback safely
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
		var instance := packed.instantiate()
		_mount_zone(instance)
		var current_root := get_tree().current_scene
		get_tree().root.add_child(instance)
		get_tree().current_scene = instance
		if current_root != null and current_root != self:
			current_root.queue_free()
		queue_free()
	else:
		push_error("SceneLoader: Fatal: Failed to load target scene and fallback scene.")

func _mount_zone(zone_instance: Node) -> void:
	_ensure_environment_and_lighting(zone_instance)
	_ensure_active_camera(zone_instance)

static func _ensure_environment_and_lighting(zone_instance: Node) -> void:
	var existing_envs := zone_instance.find_children("", "WorldEnvironment", true, false)
	if existing_envs.is_empty():
		var env_node := WorldEnvironment.new()
		env_node.name = "InjectedWorldEnvironment"
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
		env.glow_enabled = true
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.015
		env_node.environment = env
		zone_instance.add_child(env_node)

	var existing_lights := zone_instance.find_children("", "DirectionalLight3D", true, false)
	if existing_lights.is_empty():
		var sun := DirectionalLight3D.new()
		sun.name = "InjectedDirectionalLight3D"
		sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
		sun.light_energy = 1.4
		sun.shadow_enabled = true
		zone_instance.add_child(sun)

static func _ensure_active_camera(root: Node) -> void:
	var existing_cams := root.find_children("", "Camera3D", true, false)
	if existing_cams.is_empty():
		var cam := Camera3D.new()
		cam.name = "ShowcaseAutoCamera"
		cam.current = true
		cam.fov = 55.0
		root.add_child(cam)
		cam.look_at_from_position(Vector3(0.0, 14.0, 26.0), Vector3(0.0, 2.0, 0.0), Vector3.UP)
