extends SceneTree
## compositor.gd
## Headless Scene Compositor (Layer 6.5)
## Reads a declarative JSON composition spec, instantiates modular prefabs
## from the asset library, sets transforms/materials, updates navigation,
## and packs the resulting 3D zone to disk.
##
## Usage:
## godot --headless --path playable-client -s res://tools/compositor.gd -- spec=<json_path>

const MANIFEST_PATH := "res://library/modular/manifests/system_modular_manifest.json"

var asset_cache: Dictionary = {}

func _init() -> void:
	var spec_path := ""
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg in all_args:
		if arg.begins_with("spec="):
			spec_path = arg.trim_prefix("spec=").strip_edges()
		elif arg.begins_with("--spec="):
			spec_path = arg.trim_prefix("--spec=").strip_edges()

	if spec_path.is_empty():
		push_error("[Compositor] Missing required parameter: spec=<path_to_json>")
		quit(1)
		return

	print("[Compositor] Loading composition spec: %s" % spec_path)
	var spec_file := FileAccess.open(spec_path, FileAccess.READ)
	if spec_file == null:
		push_error("[Compositor] Failed to open spec file at: %s" % spec_path)
		quit(1)
		return

	var spec_text := spec_file.get_as_text()
	spec_file.close()

	var test_json_conv := JSON.new()
	var parse_err := test_json_conv.parse(spec_text)
	if parse_err != OK:
		push_error("[Compositor] Invalid JSON in spec file: %s" % test_json_conv.get_error_message())
		quit(1)
		return

	var spec: Dictionary = test_json_conv.data
	_load_manifest()

	var target_scene_path: String = spec.get("target_scene", "res://scenes/zones/arena_zone.tscn")
	var output_path: String = spec.get("output_path", target_scene_path)

	var scene_root: Node3D = null
	if ResourceLoader.exists(target_scene_path):
		var packed_target := load(target_scene_path) as PackedScene
		if packed_target != null:
			scene_root = packed_target.instantiate() as Node3D
			print("[Compositor] Loaded existing scene root: %s" % target_scene_path)

	if scene_root == null:
		push_warning("[Compositor] Target scene '%s' not found. Creating new base Node3D." % target_scene_path)
		scene_root = Node3D.new()
		scene_root.name = "ComposedZone"

	# Apply palette / environment settings if provided
	if spec.has("palette") and spec["palette"] is Dictionary:
		_apply_palette(scene_root, spec["palette"])

	# Ensure Entities container node exists
	var entities_root: Node3D = scene_root.get_node_or_null("Entities") as Node3D
	if entities_root == null:
		entities_root = Node3D.new()
		entities_root.name = "Entities"
		scene_root.add_child(entities_root)

	# Sub-containers for clean node organization
	var arch_group := _get_or_create_subgroup(entities_root, "Architecture")
	var hazard_group := _get_or_create_subgroup(entities_root, "Hazards")
	var interact_group := _get_or_create_subgroup(entities_root, "Interactables")
	var light_group := _get_or_create_subgroup(entities_root, "Lighting")

	# Instantiate entities
	var entities: Array = spec.get("entities", [])
	var placed_count := 0

	for item in entities:
		if not (item is Dictionary):
			continue
		var ent_dict: Dictionary = item
		var asset_id: String = ent_dict.get("asset_id", "")
		var asset_path: String = ent_dict.get("path", "")

		if asset_path.is_empty() and asset_cache.has(asset_id):
			asset_path = asset_cache[asset_id].get("path", "")

		if asset_path.is_empty() or not ResourceLoader.exists(asset_path):
			push_warning("[Compositor] Unknown or missing asset: id='%s', path='%s'" % [asset_id, asset_path])
			continue

		var packed_prefab := load(asset_path) as PackedScene
		if packed_prefab == null:
			push_warning("[Compositor] Failed to load PackedScene at: %s" % asset_path)
			continue

		var inst := packed_prefab.instantiate() as Node3D
		if inst == null:
			continue

		# Position
		var pos_arr: Array = ent_dict.get("position", [0.0, 0.0, 0.0])
		if pos_arr.size() >= 3:
			inst.position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

		# Rotation
		var rot_y: float = float(ent_dict.get("rotation_y_deg", 0.0))
		if rot_y != 0.0:
			inst.rotation_degrees = Vector3(0.0, rot_y, 0.0)

		# Scale
		var scale_arr: Array = ent_dict.get("scale", [1.0, 1.0, 1.0])
		if scale_arr.size() >= 3:
			inst.scale = Vector3(float(scale_arr[0]), float(scale_arr[1]), float(scale_arr[2]))

		# Custom Tag or Params
		if ent_dict.has("tag"):
			inst.set_meta("entity_tag", str(ent_dict["tag"]))
		if ent_dict.has("params") and ent_dict["params"] is Dictionary:
			inst.set_meta("custom_params", ent_dict["params"])

		# Routing to sub-group by category
		var category: String = ent_dict.get("category", "")
		if category.is_empty() and asset_cache.has(asset_id):
			category = asset_cache[asset_id].get("category", "")

		match category:
			"hazard":
				hazard_group.add_child(inst)
			"interactable":
				interact_group.add_child(inst)
			"lighting":
				light_group.add_child(inst)
			_:
				arch_group.add_child(inst)

		placed_count += 1

	print("[Compositor] Successfully placed %d modular entities into scene." % placed_count)

	# Update owner recursively
	_set_owner_recursive(scene_root, scene_root)

	# Save scene
	var packed_out := PackedScene.new()
	var pack_res := packed_out.pack(scene_root)
	if pack_res != OK:
		push_error("[Compositor] Failed to pack composed scene (error code: %d)" % pack_res)
		quit(1)
		return

	var save_res := ResourceSaver.save(packed_out, output_path)
	if save_res != OK:
		push_error("[Compositor] Failed to save scene to: %s (error code: %d)" % [output_path, save_res])
		quit(1)
		return

	print("[Compositor] Successfully composed and saved: %s" % output_path)
	quit(0)

func _load_manifest() -> void:
	if not ResourceLoader.exists(MANIFEST_PATH):
		return
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) == OK and json.data is Dictionary:
		var arr: Array = json.data.get("assets", [])
		for a in arr:
			if a is Dictionary and a.has("id"):
				asset_cache[a["id"]] = a

func _get_or_create_subgroup(parent: Node3D, group_name: String) -> Node3D:
	var existing := parent.get_node_or_null(group_name) as Node3D
	if existing != null:
		return existing
	var new_group := Node3D.new()
	new_group.name = group_name
	parent.add_child(new_group)
	return new_group

func _apply_palette(root: Node3D, palette: Dictionary) -> void:
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		var env: Environment = env_node.environment
		if palette.has("volumetric_fog_density"):
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = float(palette["volumetric_fog_density"])
		if palette.has("volumetric_fog_color"):
			env.volumetric_fog_albedo = Color.from_string(palette["volumetric_fog_color"], Color(0.5, 0.2, 0.1, 1.0))

	var sun := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		if palette.has("sun_light_energy"):
			sun.light_energy = float(palette["sun_light_energy"])
		if palette.has("sun_light_color"):
			sun.light_color = Color.from_string(palette["sun_light_color"], Color.WHITE)

func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)
