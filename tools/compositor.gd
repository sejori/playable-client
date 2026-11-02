extends SceneTree
## compositor.gd
## Headless Scene Compositor (Layer 6.5)
## Reads a declarative JSON composition spec, instantiates modular prefabs
## from the asset library, sets transforms/materials, updates navigation,
## generates procedural substrates, attaches composable entity traits,
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

	# Idempotent Category Clearing: Unless "append": true is explicitly passed,
	# replace sub-containers so repeated calls replace rather than stack duplicate bodies.
	var should_append: bool = bool(spec.get("append", false))
	if not should_append:
		for group_name in ["Architecture", "Hazards", "Interactables", "Lighting", "Characters", "Nature", "Substrate"]:
			var old_grp: Node = entities_root.get_node_or_null(group_name)
			if old_grp != null:
				entities_root.remove_child(old_grp)
				old_grp.free()

	# Sub-containers for clean node organization
	var arch_group := _get_or_create_subgroup(entities_root, "Architecture")
	var hazard_group := _get_or_create_subgroup(entities_root, "Hazards")
	var interact_group := _get_or_create_subgroup(entities_root, "Interactables")
	var light_group := _get_or_create_subgroup(entities_root, "Lighting")
	var char_group := _get_or_create_subgroup(entities_root, "Characters")
	var nature_group := _get_or_create_subgroup(entities_root, "Nature")
	var substrate_group := _get_or_create_subgroup(entities_root, "Substrate")

	# Support Declarative "substrate" Block (Phase 3)
	if spec.has("substrate") and spec["substrate"] is Dictionary:
		_apply_substrate(scene_root, spec["substrate"] as Dictionary)

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
			var rot_arr: Variant = ent_dict["rotation_degrees"]
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

		# Attach Composable Entity Traits (Phase 3)
		# Merge asset_entry default_traits with ent_dict traits (where ent_dict overrides by type)
		var default_traits_raw: Variant = asset_entry.get("default_traits", [])
		var custom_traits_raw: Variant = ent_dict.get("traits", [])
		var default_traits: Array = (default_traits_raw as Array).duplicate(true) if default_traits_raw is Array else []
		var custom_traits: Array = (custom_traits_raw as Array).duplicate(true) if custom_traits_raw is Array else []

		var merged_traits: Array = []
		var custom_types: Dictionary = {}
		for ct in custom_traits:
			if ct is Dictionary and (ct as Dictionary).has("type"):
				custom_types[str((ct as Dictionary)["type"]).strip_edges().to_lower()] = ct

		for dt in default_traits:
			if dt is Dictionary and (dt as Dictionary).has("type"):
				var t_type: String = str((dt as Dictionary)["type"]).strip_edges().to_lower()
				if custom_types.has(t_type):
					var dt_copy: Dictionary = (dt as Dictionary).duplicate(true)
					var ct_dict: Dictionary = custom_types[t_type] as Dictionary
					for k in ct_dict:
						dt_copy[k] = ct_dict[k]
					merged_traits.append(dt_copy)
					custom_types.erase(t_type)
				else:
					merged_traits.append((dt as Dictionary).duplicate(true))

		for ct_type in custom_types:
			merged_traits.append((custom_types[ct_type] as Dictionary).duplicate(true))

		if not merged_traits.is_empty():
			var traits_script_path := "res://library/modular/ModularEntityTraits.gd"
			if ResourceLoader.exists(traits_script_path):
				var traits_script: Variant = load(traits_script_path)
				var trait_node: Node3D = traits_script.new()
				trait_node.name = "ModularEntityTraits"
				trait_node.set("traits_config", merged_traits)
				inst.add_child(trait_node)
				inst.set_meta("entity_traits", merged_traits)

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
			"nature":
				nature_group.add_child(inst)
			"substrate":
				substrate_group.add_child(inst)
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

# -----------------------------------------------------------------------------
# Procedural Substrate Generators (Phase 3)
# -----------------------------------------------------------------------------
func _apply_substrate(scene_root: Node3D, substrate: Dictionary) -> void:
	var sub_type: String = str(substrate.get("type", "flat_arena")).strip_edges().to_lower()
	var entities_root := scene_root.get_node_or_null("Entities") as Node3D
	if entities_root == null:
		entities_root = Node3D.new()
		entities_root.name = "Entities"
		scene_root.add_child(entities_root)

	var substrate_group := _get_or_create_subgroup(entities_root, "Substrate")

	match sub_type:
		"flat_arena":
			_apply_flat_arena_substrate(scene_root, substrate_group, substrate)
		"voxel_terraced":
			_apply_voxel_terraced_substrate(scene_root, substrate_group, substrate)
		"hex_grid":
			_apply_hex_grid_substrate(scene_root, substrate_group, substrate)
		"scattered_grove":
			_apply_scattered_grove_substrate(scene_root, substrate_group, substrate)
		_:
			push_warning("[Compositor] Unknown substrate type: '%s'. Defaulting to flat_arena." % sub_type)
			_apply_flat_arena_substrate(scene_root, substrate_group, substrate)

func _apply_flat_arena_substrate(scene_root: Node3D, substrate_group: Node3D, substrate: Dictionary) -> void:
	var floor_size: float = float(substrate.get("size", 48.0))

	# Update existing GroundFloor if present
	var ground_floor := scene_root.find_child("GroundFloor", true, false) as StaticBody3D
	if ground_floor != null:
		var col := ground_floor.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if col != null and col.shape is BoxShape3D:
			(col.shape as BoxShape3D).size = Vector3(floor_size, 0.4, floor_size)

		var mesh_inst: MeshInstance3D = null
		var meshes := ground_floor.find_children("", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			mesh_inst = meshes[0] as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh is BoxMesh:
			(mesh_inst.mesh as BoxMesh).size = Vector3(floor_size, 0.4, floor_size)

		if substrate.has("floor_color") or substrate.has("floor_albedo"):
			var raw_col: Variant = substrate.get("floor_color", substrate.get("floor_albedo", null))
			if raw_col != null and mesh_inst != null:
				var f_mat := StandardMaterial3D.new()
				f_mat.albedo_color = _parse_color(raw_col, Color(0.2, 0.22, 0.24, 1.0))
				f_mat.roughness = 0.85
				f_mat.metallic = 0.15
				mesh_inst.set_surface_override_material(0, f_mat)

	# Optional glowing liquid / lava sub-plane
	if substrate.has("liquid_color") or substrate.has("liquid_level"):
		var liquid_col := _parse_color(substrate.get("liquid_color", "#ff4400"), Color(1.0, 0.27, 0.0))
		var liquid_y: float = float(substrate.get("liquid_level", -0.5))
		var liquid_size: float = floor_size * 1.5

		var liquid_plane := MeshInstance3D.new()
		liquid_plane.name = "LiquidSubPlane"
		var pm := PlaneMesh.new()
		pm.size = Vector2(liquid_size, liquid_size)
		liquid_plane.mesh = pm

		var l_mat := StandardMaterial3D.new()
		l_mat.albedo_color = liquid_col
		l_mat.emission_enabled = true
		l_mat.emission = liquid_col
		l_mat.emission_energy_multiplier = 3.0
		l_mat.roughness = 0.15
		liquid_plane.set_surface_override_material(0, l_mat)

		liquid_plane.position = Vector3(0.0, liquid_y, 0.0)
		substrate_group.add_child(liquid_plane)

func _apply_voxel_terraced_substrate(scene_root: Node3D, substrate_group: Node3D, _substrate: Dictionary) -> void:
	# Clean up legacy VoxelPlotTerrain if present (from old cartridge_03)
	var legacy_voxel := scene_root.find_child("VoxelPlotTerrain", true, false)
	if legacy_voxel != null:
		legacy_voxel.get_parent().remove_child(legacy_voxel)
		legacy_voxel.free()

	# Ensure PlayerCharacter is positioned cleanly at ground level
	var player_char := scene_root.find_child("PlayerCharacter", true, false) as Node3D
	if player_char != null:
		player_char.position = Vector3(0.0, 1.2, 0.0)

	var terrace_root := Node3D.new()
	terrace_root.name = "VoxelTerrace"
	substrate_group.add_child(terrace_root)

	var block_prefab_path := "res://library/modular/voxel/voxel_block_base.tscn"
	var block_prefab: PackedScene = null
	if ResourceLoader.exists(block_prefab_path):
		block_prefab = load(block_prefab_path) as PackedScene

	# Materials for terraced tiers
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.22, 0.65, 0.26)
	grass_mat.roughness = 0.85

	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.46, 0.32, 0.18)
	dirt_mat.roughness = 0.9

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.40, 0.42, 0.45)
	stone_mat.roughness = 0.8

	# Multi-elevation terraced hills around a walkable center
	var step_size := 2.0
	for x_step in range(-7, 8):
		for z_step in range(-7, 8):
			var wx: float = float(x_step) * step_size
			var wz: float = float(z_step) * step_size
			var dist: float = sqrt(wx * wx + wz * wz)

			if dist <= 4.0:
				continue

			var target_y: float = 0.0
			var block_mat: StandardMaterial3D = grass_mat

			if dist > 4.0 and dist <= 7.0:
				target_y = 1.0
				block_mat = grass_mat
			elif dist > 7.0 and dist <= 10.5:
				target_y = 2.0
				block_mat = dirt_mat
			elif dist > 10.5:
				target_y = 3.0
				block_mat = stone_mat

			var block: Node3D = null
			if block_prefab != null:
				block = block_prefab.instantiate() as Node3D
			else:
				var sb := StaticBody3D.new()
				sb.collision_layer = 1
				var col := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(step_size, 1.0, step_size)
				col.shape = bs
				col.position.y = 0.5
				sb.add_child(col)

				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = bs.size
				mi.mesh = bm
				mi.position.y = 0.5
				sb.add_child(mi)
				block = sb

			block.name = "Voxel_%d_%d" % [x_step, z_step]
			block.scale = Vector3(step_size, 1.0, step_size)
			block.position = Vector3(wx, target_y - 0.5, wz)

			# Clear scene_file_path and child owners so PackedScene serializes mesh and materials directly
			block.scene_file_path = ""
			for c in block.get_children():
				c.owner = null

			var mesh_nodes := block.find_children("", "MeshInstance3D", true, false)
			for mn in mesh_nodes:
				(mn as MeshInstance3D).set_surface_override_material(0, block_mat)

			terrace_root.add_child(block)

	# Translucent water plane
	var water_plane := MeshInstance3D.new()
	water_plane.name = "TranslucentWaterPlane"
	var wpm := PlaneMesh.new()
	wpm.size = Vector2(36.0, 36.0)
	water_plane.mesh = wpm

	var w_mat := StandardMaterial3D.new()
	w_mat.albedo_color = Color(0.12, 0.48, 0.88, 0.65)
	w_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	w_mat.roughness = 0.1
	w_mat.metallic = 0.2
	water_plane.set_surface_override_material(0, w_mat)
	water_plane.position = Vector3(0.0, -0.2, 0.0)
	terrace_root.add_child(water_plane)

	# Attach VoxelWorldGenerator
	var gen_script_path := "res://library/voxel/VoxelWorldGenerator.gd"
	if ResourceLoader.exists(gen_script_path):
		var gen_script: Variant = load(gen_script_path)
		var gen_node: Node3D = gen_script.new()
		gen_node.name = "VoxelWorldGenerator"
		terrace_root.add_child(gen_node)

	scene_root.set_meta("voxel_substrate", true)

func _apply_hex_grid_substrate(scene_root: Node3D, substrate_group: Node3D, substrate: Dictionary) -> void:
	# Clean up legacy HexTiles if present (from old cartridge_04)
	var legacy_hex := scene_root.find_child("HexTiles", true, false)
	if legacy_hex != null:
		legacy_hex.get_parent().remove_child(legacy_hex)
		legacy_hex.free()

	var hex_grid_root := Node3D.new()
	hex_grid_root.name = "HexGrid"
	substrate_group.add_child(hex_grid_root)

	var grid_radius: int = int(substrate.get("radius", 4))
	var hex_radius: float = float(substrate.get("hex_radius", 2.0))

	# Load rich biome prefabs if available
	var plains_prefab_path := "res://library/strategy/hex_plains.tscn"
	var forest_prefab_path := "res://library/strategy/hex_forest.tscn"
	var mountain_prefab_path := "res://library/strategy/hex_mountain.tscn"
	var water_prefab_path := "res://library/strategy/hex_water.tscn"
	var tile_prefab_path := "res://library/modular/strategy/hex_tile_base.tscn"

	var plains_prefab: PackedScene = load(plains_prefab_path) as PackedScene if ResourceLoader.exists(plains_prefab_path) else null
	var forest_prefab: PackedScene = load(forest_prefab_path) as PackedScene if ResourceLoader.exists(forest_prefab_path) else null
	var mountain_prefab: PackedScene = load(mountain_prefab_path) as PackedScene if ResourceLoader.exists(mountain_prefab_path) else null
	var water_prefab: PackedScene = load(water_prefab_path) as PackedScene if ResourceLoader.exists(water_prefab_path) else null
	var tile_prefab: PackedScene = load(tile_prefab_path) as PackedScene if ResourceLoader.exists(tile_prefab_path) else null

	# Biome materials
	var plains_mat := StandardMaterial3D.new()
	plains_mat.albedo_color = Color(0.22, 0.68, 0.28) # Emerald
	plains_mat.roughness = 0.8

	var forest_mat := StandardMaterial3D.new()
	forest_mat.albedo_color = Color(0.12, 0.45, 0.18) # Deep green
	forest_mat.roughness = 0.85

	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.albedo_color = Color(0.42, 0.45, 0.48) # Slate
	mountain_mat.roughness = 0.75

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.15, 0.50, 0.90, 0.85) # Azure
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.15

	var sqrt3: float = 1.732050807568877

	for q in range(-grid_radius, grid_radius + 1):
		var r1 := maxi(-grid_radius, -q - grid_radius)
		var r2 := mini(grid_radius, -q + grid_radius)
		for r in range(r1, r2 + 1):
			var wx: float = hex_radius * sqrt3 * (float(q) + float(r) * 0.5)
			var wz: float = hex_radius * 1.5 * float(r)

			var dist: int = maxi(absi(q), maxi(absi(r), absi(-q - r)))
			var biome_name := "plains"
			var biome_mat := plains_mat
			var elevation_y: float = 0.0

			if dist == 0:
				biome_name = "plains"
				biome_mat = plains_mat
				elevation_y = 0.0
			elif dist == grid_radius and (q + r) % 2 == 0:
				biome_name = "mountain"
				biome_mat = mountain_mat
				elevation_y = 0.35
			elif (q * 3 + r * 5) % 7 == 0:
				biome_name = "water"
				biome_mat = water_mat
				elevation_y = -0.15
			elif (q * 2 + r * 3) % 4 == 0:
				biome_name = "forest"
				biome_mat = forest_mat
				elevation_y = 0.0

			var tile: Node3D = null
			var used_rich_prefab := false

			match biome_name:
				"forest":
					if forest_prefab != null:
						tile = forest_prefab.instantiate() as Node3D
						used_rich_prefab = true
				"mountain":
					if mountain_prefab != null:
						tile = mountain_prefab.instantiate() as Node3D
						used_rich_prefab = true
				"water":
					if water_prefab != null:
						tile = water_prefab.instantiate() as Node3D
						used_rich_prefab = true
				_:
					if plains_prefab != null:
						tile = plains_prefab.instantiate() as Node3D
						used_rich_prefab = true

			if tile == null:
				if tile_prefab != null:
					tile = tile_prefab.instantiate() as Node3D
				else:
					var sb := StaticBody3D.new()
					sb.collision_layer = 1
					var col := CollisionShape3D.new()
					var cs := CylinderShape3D.new()
					cs.radius = hex_radius
					cs.height = 0.5
					col.shape = cs
					col.position.y = 0.25
					sb.add_child(col)

					var mi := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.radial_segments = 6
					cm.top_radius = hex_radius
					cm.bottom_radius = hex_radius
					cm.height = 0.5
					mi.mesh = cm
					mi.position.y = 0.25
					sb.add_child(mi)
					tile = sb

			tile.name = "HexTile_%d_%d" % [q, r]
			tile.position = Vector3(wx, elevation_y, wz)
			tile.set_meta("hex_q", q)
			tile.set_meta("hex_r", r)
			tile.set_meta("biome", biome_name)
			if not tile.is_in_group("hex_tile"):
				tile.add_to_group("hex_tile")

			if not used_rich_prefab:
				# Clear scene_file_path and child owners so PackedScene serializes mesh and biome materials directly
				tile.scene_file_path = ""
				for c in tile.get_children():
					c.owner = null

				var meshes := tile.find_children("", "MeshInstance3D", true, false)
				for m in meshes:
					(m as MeshInstance3D).set_surface_override_material(0, biome_mat)

			hex_grid_root.add_child(tile)

	# Ensure TurnManager node is added to scene_root
	if scene_root.get_node_or_null("TurnManager") == null:
		var tm_path := "res://library/strategy/TurnManager.gd"
		if ResourceLoader.exists(tm_path):
			var tm_script: Variant = load(tm_path)
			var tm: Node = tm_script.new()
			tm.name = "TurnManager"
			scene_root.add_child(tm)

	scene_root.set_meta("hex_substrate", true)

func _apply_scattered_grove_substrate(scene_root: Node3D, substrate_group: Node3D, substrate: Dictionary) -> void:
	var grove_root := Node3D.new()
	grove_root.name = "ScatteredGrove"
	substrate_group.add_child(grove_root)

	var tree_path := "res://library/modular/nature/oak_tree.tscn"
	var rock_path := "res://library/modular/nature/iron_rock.tscn"
	var torch_path := "res://library/modular/interactive/omni_torch_brazier.tscn"

	var tree_scene := load(tree_path) as PackedScene if ResourceLoader.exists(tree_path) else null
	var rock_scene := load(rock_path) as PackedScene if ResourceLoader.exists(rock_path) else null
	var torch_scene := load(torch_path) as PackedScene if ResourceLoader.exists(torch_path) else null

	var item_count: int = int(substrate.get("density", 14))
	var clearing_radius: float = float(substrate.get("clearing_radius", 5.0))

	for i in range(item_count):
		var angle: float = (float(i) / float(item_count)) * TAU + sin(float(i) * 2.3) * 0.15
		var dist: float = clearing_radius + 2.0 + fmod(absf(sin(float(i) * 4.7) * 4.0), 5.5)

		var px: float = cos(angle) * dist
		var pz: float = sin(angle) * dist
		var rot_y: float = rad_to_deg(angle + PI * 0.5)

		var inst: Node3D = null
		var default_traits: Array = []
		var asset_id := ""

		var mod_idx := i % 3
		if mod_idx == 0 and tree_scene != null:
			inst = tree_scene.instantiate() as Node3D
			asset_id = "nature_oak_tree"
			default_traits = [
				{
					"type": "harvestable",
					"resource_name": "Oak Log",
					"max_charges": 5,
					"tick_interval_sec": 0.6,
					"respawn_sec": 8.0
				}
			]
		elif mod_idx == 1 and rock_scene != null:
			inst = rock_scene.instantiate() as Node3D
			asset_id = "nature_iron_rock"
			default_traits = [
				{
					"type": "harvestable",
					"resource_name": "Iron Ore",
					"max_charges": 4,
					"tick_interval_sec": 0.6,
					"respawn_sec": 10.0
				}
			]
		elif torch_scene != null:
			inst = torch_scene.instantiate() as Node3D
			asset_id = "light_torch_brazier"
			default_traits = [
				{
					"type": "ambient_motion",
					"flicker_light": true
				}
			]

		if inst != null:
			inst.name = "%s_%d" % [asset_id, i]
			inst.position = Vector3(px, 0.0, pz)
			inst.rotation_degrees.y = rot_y

			if not default_traits.is_empty():
				var traits_script_path := "res://library/modular/ModularEntityTraits.gd"
				if ResourceLoader.exists(traits_script_path):
					var traits_script: Variant = load(traits_script_path)
					var trait_node: Node3D = traits_script.new()
					trait_node.name = "ModularEntityTraits"
					trait_node.set("traits_config", default_traits)
					inst.add_child(trait_node)
					inst.set_meta("entity_traits", default_traits)

			grove_root.add_child(inst)

	scene_root.set_meta("scattered_grove", true)

# -----------------------------------------------------------------------------
# Environment & Palette Application
# -----------------------------------------------------------------------------
func _apply_palette(root: Node3D, palette: Dictionary) -> void:
	var env_node: WorldEnvironment = root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		var envs := root.find_children("", "WorldEnvironment", true, false)
		if not envs.is_empty():
			env_node = envs[0] as WorldEnvironment

	if env_node != null and env_node.environment != null:
		var env: Environment = env_node.environment

		var sky_top_val: Variant = palette.get("sky_top", palette.get("sky_top_color", palette.get("sky_top_hex", null)))
		var sky_horiz_val: Variant = palette.get("sky_horizon", palette.get("sky_bottom_color", palette.get("sky_bottom_hex", null)))
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

		var fog_dens: Variant = palette.get("volumetric_fog_density", palette.get("fog_density", null))
		if fog_dens != null:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = float(fog_dens)

		var fog_col: Variant = palette.get("volumetric_fog_color", palette.get("fog_albedo", null))
		if fog_col != null:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_albedo = _parse_color(fog_col, Color(0.5, 0.2, 0.1, 1.0))

	var sun: DirectionalLight3D = root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		var lights := root.find_children("", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			sun = lights[0] as DirectionalLight3D

	if sun != null:
		var sun_energy: Variant = palette.get("sun_energy", palette.get("sun_light_energy", null))
		if sun_energy != null:
			sun.light_energy = float(sun_energy)

		var sun_color: Variant = palette.get("sun_color", palette.get("sun_light_color", null))
		if sun_color != null:
			sun.light_color = _parse_color(sun_color, Color.WHITE)

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
		var cam_host_script: Variant = load(cam_host_script_path)
		cam_host = cam_host_script.new()
	else:
		cam_host = Camera3D.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var follow_cam_path := "res://scripts/camera/VirtualFollowCamera3D.gd"
	if ResourceLoader.exists(follow_cam_path):
		var follow_script: Variant = load(follow_cam_path)
		var vcam: Node3D = follow_script.new()
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
		if child.scene_file_path != "":
			# Child is an instanced PackedScene. Internal nodes already have owner == child.
			# Only set owner = scene_owner on newly added dynamic nodes (like ModularEntityTraits).
			_set_owner_for_dynamic_children(child, scene_owner)
		else:
			_set_owner_recursive(child, scene_owner)

func _set_owner_for_dynamic_children(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		if child.owner == null or child.owner == scene_owner:
			child.owner = scene_owner
			_set_owner_for_dynamic_children(child, scene_owner)
