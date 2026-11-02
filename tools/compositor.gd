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

	var result := compose_from_manifest(spec)
	quit(result)

func compose_from_manifest(spec: Dictionary) -> int:
	var target_scene_path: String = spec.get("target_scene", "res://scenes/zones/arena_zone.tscn")
	var output_path: String = spec.get("output_path", target_scene_path)

	var scene_root: Node3D = null
	if ResourceLoader.exists(target_scene_path):
		var packed_target := load(target_scene_path) as PackedScene
		if packed_target != null:
			scene_root = packed_target.instantiate() as Node3D
			print("[Compositor] Loaded existing scene root: %s" % target_scene_path)

	# Invariant: Never create a bare Node3D without substrate.
	# Build 5-invariant substrate if target scene not found.
	if scene_root == null:
		push_warning("[Compositor] Target scene '%s' not found. Instantiating 5-invariant substrate." % target_scene_path)
		scene_root = _build_default_substrate()
		print("[Compositor] Built default 5-invariant substrate.")

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
	var char_group := _get_or_create_subgroup(entities_root, "Characters")

	# Idempotent Category Clearing: Unless "append": true is explicitly passed,
	# clear existing children inside sub-containers so repeated calls replace rather than stack duplicate bodies.
	var should_append: bool = bool(spec.get("append", false))
	if not should_append:
		var category_groups: Array[Node3D] = [arch_group, hazard_group, interact_group, light_group, char_group]
		for grp in category_groups:
			for child in grp.get_children():
				child.free()

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

		# Position & Coordinate Normalization
		var pos_arr: Array = ent_dict.get("position", [0.0, 0.0, 0.0])
		var pos_x: float = 0.0
		var pos_y: float = 0.0
		var pos_z: float = 0.0
		if pos_arr.size() >= 3:
			pos_x = float(pos_arr[0])
			pos_y = float(pos_arr[1])
			pos_z = float(pos_arr[2])

		# Normalize double-offset Y coordinates:
		# Modular prefabs already offset child mesh/collision upward by height * 0.5.
		# If pos_y > 0.0 and bbox_size is [sx, sy, sz] and abs(pos_y - sy * 0.5) <= 0.25
		# (or for arch_pillar_monolith where legacy prompt passed y = 4.0 for a 6m pillar, pos_y >= 1.5),
		# normalize pos_y = 0.0 so walls, pillars, and forcefield doors rest flush on floor.
		var asset_entry: Dictionary = asset_cache.get(asset_id, {})
		var bbox_size: Array = []
		if asset_entry.has("bbox_size") and asset_entry["bbox_size"] is Array:
			bbox_size = asset_entry["bbox_size"]
		elif asset_entry.has("aabb") and asset_entry["aabb"] is Dictionary:
			bbox_size = asset_entry["aabb"].get("size", [])

		if pos_y > 0.0:
			if bbox_size.size() == 3:
				var half_h: float = float(bbox_size[1]) * 0.5
				if absf(pos_y - half_h) <= 0.25:
					pos_y = 0.0
			if asset_id == "arch_pillar_monolith" and pos_y >= 1.5 and pos_y <= 4.5:
				pos_y = 0.0

		inst.position = Vector3(pos_x, pos_y, pos_z)

		# Rotation: Support both "rotation_degrees": [rx, ry, rz] and "rotation_y_deg": ry
		if ent_dict.has("rotation_degrees"):
			var rot_arr = ent_dict["rotation_degrees"]
			if rot_arr is Array and rot_arr.size() >= 3:
				inst.rotation_degrees = Vector3(float(rot_arr[0]), float(rot_arr[1]), float(rot_arr[2]))
		elif ent_dict.has("rotation_y_deg"):
			var rot_y: float = float(ent_dict.get("rotation_y_deg", 0.0))
			inst.rotation_degrees.y = rot_y

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
			"hazard", "hazards":
				hazard_group.add_child(inst)
			"interactable", "interactables", "interactive":
				interact_group.add_child(inst)
			"lighting", "light":
				light_group.add_child(inst)
			"characters", "character":
				char_group.add_child(inst)
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
		return 1

	var save_res := ResourceSaver.save(packed_out, output_path)
	if save_res != OK:
		push_error("[Compositor] Failed to save scene to: %s (error code: %d)" % [output_path, save_res])
		return 1

	print("[Compositor] Successfully composed and saved: %s" % output_path)
	return 0

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

func _parse_color(val: Variant, default_color: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		var s: String = str(val).strip_edges()
		if not s.is_empty():
			if not s.begins_with("#") and (s.length() == 6 or s.length() == 8):
				s = "#" + s
			return Color.from_string(s, default_color)
	return default_color

func _apply_palette(root: Node3D, palette: Dictionary) -> void:
	var env_node: WorldEnvironment = root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		var envs := root.find_children("", "WorldEnvironment", true, false)
		if not envs.is_empty():
			env_node = envs[0] as WorldEnvironment

	if env_node != null and env_node.environment != null:
		var env: Environment = env_node.environment

		# Sky colors: Support sky_top / sky_top_color / sky_top_hex and sky_horizon / sky_bottom_color / sky_bottom_hex
		var sky_top_val = palette.get("sky_top", palette.get("sky_top_color", palette.get("sky_top_hex", null)))
		var sky_horiz_val = palette.get("sky_horizon", palette.get("sky_bottom_color", palette.get("sky_bottom_hex", null)))
		if sky_top_val != null or sky_horiz_val != null:
			if env.sky == null:
				env.sky = Sky.new()
			if env.sky.sky_material == null:
				env.sky.sky_material = ProceduralSkyMaterial.new()
			if env.sky.sky_material is ProceduralSkyMaterial:
				var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
				if sky_top_val != null:
					sky_mat.sky_top_color = _parse_color(sky_top_val, sky_mat.sky_top_color)
				if sky_horiz_val != null:
					var horiz_col := _parse_color(sky_horiz_val, sky_mat.sky_horizon_color)
					sky_mat.sky_horizon_color = horiz_col
					sky_mat.ground_bottom_color = horiz_col.darkened(0.3)
					sky_mat.ground_horizon_color = horiz_col

		# Fog: Support both fog_density / volumetric_fog_density and fog_albedo / volumetric_fog_color
		var fog_dens = palette.get("volumetric_fog_density", palette.get("fog_density", null))
		if fog_dens != null:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = float(fog_dens)

		var fog_col = palette.get("volumetric_fog_color", palette.get("fog_albedo", null))
		if fog_col != null:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_albedo = _parse_color(fog_col, Color(0.5, 0.2, 0.1, 1.0))

	# Sun: Support both sun_energy / sun_light_energy and sun_color / sun_light_color
	var sun: DirectionalLight3D = root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		var lights := root.find_children("", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			sun = lights[0] as DirectionalLight3D

	if sun != null:
		var sun_energy = palette.get("sun_energy", palette.get("sun_light_energy", null))
		if sun_energy != null:
			sun.light_energy = float(sun_energy)

		var sun_color = palette.get("sun_color", palette.get("sun_light_color", null))
		if sun_color != null:
			sun.light_color = _parse_color(sun_color, Color.WHITE)

	# Floor Tinting: Support floor_albedo / grid_tint_hex (or derive darkened tint from fog_albedo / sky_horizon)
	# Apply StandardMaterial3D (roughness = 0.85, metallic = 0.15) to NavigationRegion3D/GroundFloor/MeshInstance3D
	var ground_mesh_node: MeshInstance3D = null
	var ground_floor := root.find_child("GroundFloor", true, false)
	if ground_floor != null:
		var meshes := ground_floor.find_children("", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			ground_mesh_node = meshes[0] as MeshInstance3D

	var floor_col: Color = Color(0.2, 0.22, 0.24, 1.0)
	var has_floor_tint := false
	if palette.has("floor_albedo"):
		floor_col = _parse_color(palette["floor_albedo"], floor_col)
		has_floor_tint = true
	elif palette.has("grid_tint_hex"):
		floor_col = _parse_color(palette["grid_tint_hex"], floor_col)
		has_floor_tint = true
	elif palette.has("fog_albedo"):
		floor_col = _parse_color(palette["fog_albedo"], floor_col).darkened(0.4)
		has_floor_tint = true
	elif palette.has("volumetric_fog_color"):
		floor_col = _parse_color(palette["volumetric_fog_color"], floor_col).darkened(0.4)
		has_floor_tint = true
	elif palette.has("sky_horizon"):
		floor_col = _parse_color(palette["sky_horizon"], floor_col).darkened(0.6)
		has_floor_tint = true

	if ground_mesh_node != null and has_floor_tint:
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = floor_col
		floor_mat.roughness = 0.85
		floor_mat.metallic = 0.15
		ground_mesh_node.set_surface_override_material(0, floor_mat)
		if ground_mesh_node.mesh != null:
			ground_mesh_node.mesh.material = floor_mat

func _build_default_substrate() -> Node3D:
	var root := Node3D.new()
	root.name = "ComposedZone"
	var arena_script_path := "res://scripts/zones/arena_zone.gd"
	if ResourceLoader.exists(arena_script_path):
		root.set_script(load(arena_script_path))

	# 1. WorldEnvironment
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
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
	root.add_child(env_node)

	# 2. DirectionalLight3D
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)

	# 3. NavigationRegion3D with GroundFloor StaticBody3D
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.6
	nav_mesh.agent_max_slope = 40.0
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-24, 0, -24), Vector3(-24, 0, 24), Vector3(24, 0, 24), Vector3(24, 0, -24)
	])
	nav_mesh.polygons = [PackedInt32Array([0, 1, 2, 3])]
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundFloor"
	floor_body.collision_layer = 1
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(48.0, 0.4, 48.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "GroundMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = floor_box.size
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.22, 0.24, 1.0)
	floor_mat.roughness = 0.85
	floor_mat.metallic = 0.15
	box_mesh.material = floor_mat
	floor_mesh.mesh = box_mesh
	floor_body.add_child(floor_mesh)
	nav_region.add_child(floor_body)

	# 4. PlayerCharacter CharacterBody3D
	var hero_path := "res://library/characters/hero_humanoid.tscn"
	var hero: CharacterBody3D = null
	if ResourceLoader.exists(hero_path):
		var hero_scene := load(hero_path) as PackedScene
		if hero_scene != null:
			hero = hero_scene.instantiate() as CharacterBody3D
	if hero == null:
		hero = CharacterBody3D.new()
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.height = 1.8
		col.shape = cap
		hero.add_child(col)
	hero.name = "PlayerCharacter"
	hero.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(hero)

	# 5. CameraHost3D Camera3D
	var cam_host_script_path := "res://scripts/camera/CameraHost3D.gd"
	var cam_host: Node3D = null
	if ResourceLoader.exists(cam_host_script_path):
		var cam_host_script = load(cam_host_script_path)
		cam_host = cam_host_script.new()
	else:
		cam_host = Camera3D.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var follow_cam_path := "res://scripts/camera/VirtualFollowCamera3D.gd"
	if ResourceLoader.exists(follow_cam_path):
		var follow_script = load(follow_cam_path)
		var vcam = follow_script.new()
		vcam.name = "VirtualFollowCamera"
		vcam.priority = 10
		vcam.distance = 9.0
		vcam.target_path = NodePath("../../PlayerCharacter")
		cam_host.add_child(vcam)
		if "target" in vcam:
			vcam.target = hero

	return root

func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)
