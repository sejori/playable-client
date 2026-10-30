extends SceneTree
## scaffold.gd
## Headless Scaffolding Engine (Layer 6) for generating minimal, crash-proof 3D zone substrates across 6 genres:
## 1. arena (Action-RPG)
## 2. town_square (Tick Sandbox)
## 3. voxel_plot (Voxel Survival)
## 4. hex_board (4X Strategy)
## 5. three_lane_fps (Arena FPS)
## 6. circuit_track (Collector Tycoon)
##
## Guarantees the 5 core mechanical invariants:
## - Static collision floor (StaticBody3D + CollisionShape3D)
## - Lighting baseline (DirectionalLight3D + WorldEnvironment)
## - Navigation substrate (NavigationRegion3D)
## - Player spawn & avatar (Marker3D PlayerSpawn + CharacterBody3D PlayerCharacter)
## - Active camera substrate (CameraHost3D + genre VirtualCamera)
##
## Usage:
## godot --headless --path playable-client -s res://tools/scaffold.gd -- pattern=<pattern> output=<path>

const CameraHost3DScript = preload("res://scripts/camera/CameraHost3D.gd")
const VirtualFollowCamera3DScript = preload("res://scripts/camera/VirtualFollowCamera3D.gd")
const VirtualIsometricCamera3DScript = preload("res://scripts/camera/VirtualIsometricCamera3D.gd")
const VirtualFPVCamera3DScript = preload("res://scripts/camera/VirtualFPVCamera3D.gd")
const VirtualTabletopCamera3DScript = preload("res://scripts/camera/VirtualTabletopCamera3D.gd")
const VirtualChaseCamera3DScript = preload("res://scripts/camera/VirtualChaseCamera3D.gd")

const ActionMover3DScript = preload("res://scripts/movement/ActionMover3D.gd")
const ClickToMoveMover3DScript = preload("res://scripts/movement/ClickToMoveMover3D.gd")
const VoxelMover3DScript = preload("res://scripts/movement/VoxelMover3D.gd")
const FPSMover3DScript = preload("res://scripts/movement/FPSMover3D.gd")
const VelocityRider3DScript = preload("res://scripts/movement/VelocityRider3D.gd")

const TickServerScript = preload("res://library/sandbox/TickServer.gd")
const VoxelWorldGeneratorScript = preload("res://library/voxel/VoxelWorldGenerator.gd")
const VoxelHotbarScript = preload("res://library/voxel/VoxelHotbar.gd")
const HexGridMathScript = preload("res://library/strategy/HexGridMath.gd")
const TurnManagerScript = preload("res://library/strategy/TurnManager.gd")
const CommandCardHandScript = preload("res://library/strategy/CommandCardHand.gd")

func _init() -> void:
	var pattern := "arena"
	var output_path := "res://scenes/zones/scaffolded_zone.tscn"

	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg in all_args:
		if arg.begins_with("pattern="):
			pattern = arg.trim_prefix("pattern=").strip_edges()
		elif arg.begins_with("--pattern="):
			pattern = arg.trim_prefix("--pattern=").strip_edges()
		elif arg.begins_with("output="):
			output_path = arg.trim_prefix("output=").strip_edges()
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=").strip_edges()

	print("[ScaffoldEngine] Generating neutral pattern '%s' -> '%s'..." % [pattern, output_path])

	var root_node: Node3D = null
	match pattern:
		"arena":
			root_node = _build_arena_pattern()
		"town_square":
			root_node = _build_town_square_pattern()
		"voxel_plot":
			root_node = _build_voxel_plot_pattern()
		"hex_board":
			root_node = _build_hex_board_pattern()
		"three_lane_fps":
			root_node = _build_three_lane_fps_pattern()
		"circuit_track":
			root_node = _build_circuit_track_pattern()
		_:
			push_warning("[ScaffoldEngine] Unknown pattern '%s', defaulting to arena." % pattern)
			root_node = _build_arena_pattern()

	if root_node == null:
		push_error("[ScaffoldEngine] Failed to build scene root!")
		quit(1)
		return

	_set_owner_recursive(root_node, root_node)

	var packed := PackedScene.new()
	var pack_result := packed.pack(root_node)
	if pack_result != OK:
		push_error("[ScaffoldEngine] Failed to pack scene! Error code: %d" % pack_result)
		quit(1)
		return

	var save_result := ResourceSaver.save(packed, output_path)
	if save_result != OK:
		push_error("[ScaffoldEngine] Failed to save PackedScene to '%s'! Error code: %d" % [output_path, save_result])
		quit(1)
		return

	print("[ScaffoldEngine] Successfully scaffolded neutral substrate '%s' -> '%s'!" % [pattern, output_path])
	quit(0)

func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)

func _add_default_environment(root: Node3D) -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)

# ==============================================================================
# 1. Pattern: ARENA (Action-RPG Substrate)
# ==============================================================================
func _build_arena_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "ActionRpgArena"
	root.set_script(load("res://scripts/zones/arena_zone.gd"))

	_add_default_environment(root)

	# Navigation Region & Ground Floor
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.6
	nav_mesh.agent_max_slope = 40.0
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-24, 0, -48), Vector3(-24, 0, 24), Vector3(24, 0, 24), Vector3(24, 0, -48)
	])
	nav_mesh.polygons = [PackedInt32Array([0, 1, 2, 3])]
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundFloor"
	floor_body.collision_layer = 1
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(48, 0.4, 72)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "GroundMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = floor_box.size
	floor_mesh.mesh = box_mesh
	floor_body.add_child(floor_mesh)

	nav_region.add_child(floor_body)

	# Generic Player Spawn
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)

	var p_spawn := Marker3D.new()
	p_spawn.name = "PlayerSpawn"
	p_spawn.position = Vector3(0.0, 1.2, 0.0)
	spawns.add_child(p_spawn)

	# Camera Host & Follow Camera
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var follow_cam := VirtualFollowCamera3DScript.new()
	follow_cam.name = "VirtualFollowCamera"
	follow_cam.priority = 10
	follow_cam.distance = 9.0
	follow_cam.target_path = NodePath("../../PlayerCharacter")
	cam_host.add_child(follow_cam)

	# Player Character
	var hero_scene := load("res://library/characters/hero_humanoid.tscn") as PackedScene
	if hero_scene != null:
		var hero := hero_scene.instantiate() as CharacterBody3D
		hero.name = "PlayerCharacter"
		hero.position = Vector3(0.0, 1.2, 0.0)
		root.add_child(hero)
		follow_cam.target = hero

	return root

# ==============================================================================
# 2. Pattern: TOWN_SQUARE (Tick Sandbox Substrate)
# ==============================================================================
func _build_town_square_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "TickSandboxTown"

	_add_default_environment(root)

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.5
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-20, 0, -20), Vector3(-20, 0, 20), Vector3(20, 0, 20), Vector3(20, 0, -20)
	])
	nav_mesh.polygons = [PackedInt32Array([0, 1, 2, 3])]
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

	var ground := StaticBody3D.new()
	ground.name = "GroundFloor"
	ground.collision_layer = 1
	var g_col := CollisionShape3D.new()
	var g_box := BoxShape3D.new()
	g_box.size = Vector3(40, 0.4, 40)
	g_col.shape = g_box
	ground.add_child(g_col)

	var g_mesh := MeshInstance3D.new()
	g_mesh.name = "GroundMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = g_box.size
	g_mesh.mesh = box_mesh
	ground.add_child(g_mesh)

	nav_region.add_child(ground)

	# Generic Player Spawn
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)
	var p_spawn := Marker3D.new()
	p_spawn.name = "PlayerSpawn"
	p_spawn.position = Vector3(0.0, 0.5, 0.0)
	spawns.add_child(p_spawn)

	# Deterministic 600ms Tick Server
	var tick_server := TickServerScript.new()
	tick_server.name = "TickServer"
	root.add_child(tick_server)

	# Camera Host with Isometric Camera
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var iso_cam := VirtualIsometricCamera3DScript.new()
	iso_cam.name = "VirtualIsometricCamera"
	iso_cam.priority = 10
	iso_cam.distance = 18.0
	iso_cam.target_path = NodePath("../../PlayerCharacter")
	cam_host.add_child(iso_cam)

	# Player Character with ClickToMove mover
	var hero_scene := load("res://library/characters/hero_humanoid.tscn") as PackedScene
	if hero_scene != null:
		var hero := hero_scene.instantiate() as CharacterBody3D
		hero.name = "PlayerCharacter"
		hero.position = Vector3(0.0, 0.5, 0.0)
		var old_mover := hero.get_node_or_null("ActionMover3D")
		if old_mover != null:
			old_mover.queue_free()
		var click_mover := ClickToMoveMover3DScript.new()
		click_mover.name = "ClickToMoveMover3D"
		hero.add_child(click_mover)
		root.add_child(hero)
		iso_cam.target = hero

	return root

# ==============================================================================
# 3. Pattern: VOXEL_PLOT (Voxel Survival Substrate)
# ==============================================================================
func _build_voxel_plot_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "VoxelSurvivalPlot"

	_add_default_environment(root)

	# Voxel Generator & Grid
	var generator := VoxelWorldGeneratorScript.new()
	generator.name = "VoxelWorldGenerator"
	root.add_child(generator)

	# Spawns
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)
	var p_spawn := Marker3D.new()
	p_spawn.name = "PlayerSpawn"
	p_spawn.position = Vector3(8.0, 14.0, 8.0)
	spawns.add_child(p_spawn)

	# Base plot terrain
	var plot_root := Node3D.new()
	plot_root.name = "VoxelPlotTerrain"
	root.add_child(plot_root)

	var dirt_scene := load("res://library/voxel/voxel_dirt.tscn") as PackedScene
	var stone_scene := load("res://library/voxel/voxel_stone.tscn") as PackedScene

	for x in range(0, 16, 2):
		for z in range(0, 16, 2):
			if dirt_scene != null:
				var dirt := dirt_scene.instantiate() as Node3D
				dirt.position = Vector3(x, 12, z)
				plot_root.add_child(dirt)
			if stone_scene != null:
				var stone := stone_scene.instantiate() as Node3D
				stone.position = Vector3(x, 10, z)
				plot_root.add_child(stone)

	# Wireframe cursor box & Hotbar selector
	var cursor_scene := load("res://library/voxel/voxel_cursor_box.tscn") as PackedScene
	if cursor_scene != null:
		var cursor := cursor_scene.instantiate() as Node3D
		cursor.name = "VoxelCursorBox"
		root.add_child(cursor)

	var hotbar := VoxelHotbarScript.new()
	hotbar.name = "VoxelHotbar"
	root.add_child(hotbar)

	# Camera Host with FPV Camera
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var fpv_cam := VirtualFPVCamera3DScript.new()
	fpv_cam.name = "VirtualFPVCamera"
	fpv_cam.priority = 10
	fpv_cam.target_path = NodePath("../../PlayerCharacter")
	cam_host.add_child(fpv_cam)

	# Player Character with VoxelMover
	var hero_scene := load("res://library/characters/hero_humanoid.tscn") as PackedScene
	if hero_scene != null:
		var hero := hero_scene.instantiate() as CharacterBody3D
		hero.name = "PlayerCharacter"
		hero.position = Vector3(8.0, 14.0, 8.0)
		var old_mover := hero.get_node_or_null("ActionMover3D")
		if old_mover != null:
			old_mover.queue_free()
		var voxel_mover := VoxelMover3DScript.new()
		voxel_mover.name = "VoxelMover3D"
		hero.add_child(voxel_mover)
		root.add_child(hero)
		fpv_cam.target = hero

	return root

# ==============================================================================
# 4. Pattern: HEX_BOARD (4X Strategy Substrate)
# ==============================================================================
func _build_hex_board_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "StrategyHexBoard"

	_add_default_environment(root)

	var turn_manager := TurnManagerScript.new()
	turn_manager.name = "TurnManager"
	root.add_child(turn_manager)

	var card_hand := CommandCardHandScript.new()
	card_hand.name = "CommandCardHand"
	root.add_child(card_hand)

	# Hex Tiles Board (3 concentric rings: radius 0, 1, 2 = 19 hex tiles)
	var board_root := Node3D.new()
	board_root.name = "HexTiles"
	root.add_child(board_root)

	var plains_scene := load("res://library/strategy/hex_plains.tscn") as PackedScene
	var mtn_scene := load("res://library/strategy/hex_mountain.tscn") as PackedScene
	var water_scene := load("res://library/strategy/hex_water.tscn") as PackedScene
	var forest_scene := load("res://library/strategy/hex_forest.tscn") as PackedScene

	var tile_scenes := [plains_scene, forest_scene, mtn_scene, water_scene]

	for q in range(-2, 3):
		for r in range(-2, 3):
			if HexGridMathScript.hex_distance(Vector2i.ZERO, Vector2i(q, r)) <= 2:
				var world_pos := HexGridMathScript.axial_to_world(q, r, 2.0)
				var scene_idx := (absi(q * 3 + r * 7)) % tile_scenes.size()
				var chosen_scene: PackedScene = tile_scenes[scene_idx]
				if chosen_scene != null:
					var tile := chosen_scene.instantiate() as Node3D
					tile.name = "Hex_%d_%d" % [q, r]
					tile.position = world_pos
					board_root.add_child(tile)

	# Unit Figurine
	var knight_scene := load("res://library/strategy/unit_pawn_knight.tscn") as PackedScene
	if knight_scene != null:
		var knight := knight_scene.instantiate() as CharacterBody3D
		knight.name = "KnightPawn_Blue"
		knight.add_to_group("player_character")
		knight.position = HexGridMathScript.axial_to_world(0, 0, 2.0) + Vector3(0.0, 0.5, 0.0)
		root.add_child(knight)

	# Tactical Tabletop Camera
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var table_cam := VirtualTabletopCamera3DScript.new()
	table_cam.name = "VirtualTabletopCamera"
	table_cam.priority = 10
	table_cam.elevation = 18.0
	table_cam.target_path = NodePath("../../KnightPawn_Blue")
	cam_host.add_child(table_cam)

	return root

# ==============================================================================
# 5. Pattern: THREE_LANE_FPS (Arena FPS Substrate)
# ==============================================================================
func _build_three_lane_fps_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "ArenaFpsThreeLane"

	_add_default_environment(root)

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.5
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-24, 0, -36), Vector3(-24, 0, 36), Vector3(24, 0, 36), Vector3(24, 0, -36)
	])
	nav_mesh.polygons = [PackedInt32Array([0, 1, 2, 3])]
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundFloor"
	floor_body.collision_layer = 1
	var f_col := CollisionShape3D.new()
	var f_box := BoxShape3D.new()
	f_box.size = Vector3(48, 0.4, 72)
	f_col.shape = f_box
	floor_body.add_child(f_col)

	var f_mesh := MeshInstance3D.new()
	f_mesh.name = "GroundMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = f_box.size
	f_mesh.mesh = box_mesh
	floor_body.add_child(f_mesh)

	nav_region.add_child(floor_body)

	# Generic Player Spawn
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)

	var p_spawn := Marker3D.new()
	p_spawn.name = "PlayerSpawn"
	p_spawn.position = Vector3(0.0, 1.0, 0.0)
	spawns.add_child(p_spawn)

	# FPV Camera Host
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var fpv_cam := VirtualFPVCamera3DScript.new()
	fpv_cam.name = "VirtualFPVCamera"
	fpv_cam.priority = 10
	fpv_cam.target_path = NodePath("../../PlayerCharacter")
	cam_host.add_child(fpv_cam)

	# Player Character with FPSMover3D
	var hero_scene := load("res://library/characters/hero_humanoid.tscn") as PackedScene
	if hero_scene != null:
		var hero := hero_scene.instantiate() as CharacterBody3D
		hero.name = "PlayerCharacter"
		hero.position = Vector3(0.0, 1.0, 0.0)
		var old_mover := hero.get_node_or_null("ActionMover3D")
		if old_mover != null:
			old_mover.queue_free()
		var fps_mover := FPSMover3DScript.new()
		fps_mover.name = "FPSMover3D"
		hero.add_child(fps_mover)

		var blaster_scene := load("res://library/fps/fps_viewmodel_blaster.tscn") as PackedScene
		if blaster_scene != null:
			var blaster := blaster_scene.instantiate() as Node3D
			hero.add_child(blaster)

		root.add_child(hero)
		fpv_cam.target = hero

	return root

# ==============================================================================
# 6. Pattern: CIRCUIT_TRACK (Collector Tycoon Substrate)
# ==============================================================================
func _build_circuit_track_pattern() -> Node3D:
	var root := Node3D.new()
	root.name = "CollectorTycoonCircuit"

	_add_default_environment(root)

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.8
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-30, 0, -30), Vector3(-30, 0, 30), Vector3(30, 0, 30), Vector3(30, 0, -30)
	])
	nav_mesh.polygons = [PackedInt32Array([0, 1, 2, 3])]
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundFloor"
	floor_body.collision_layer = 1
	var f_col := CollisionShape3D.new()
	var f_box := BoxShape3D.new()
	f_box.size = Vector3(60, 0.4, 60)
	f_col.shape = f_box
	floor_body.add_child(f_col)

	var f_mesh := MeshInstance3D.new()
	f_mesh.name = "GroundMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = f_box.size
	f_mesh.mesh = box_mesh
	floor_body.add_child(f_mesh)

	nav_region.add_child(floor_body)

	# Generic Player Spawn
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)

	var p_spawn := Marker3D.new()
	p_spawn.name = "PlayerSpawn"
	p_spawn.position = Vector3(0.0, 0.6, 0.0)
	spawns.add_child(p_spawn)

	# Chase Camera Host
	var cam_host := CameraHost3DScript.new()
	cam_host.name = "CameraHost3D"
	root.add_child(cam_host)

	var chase_cam := VirtualChaseCamera3DScript.new()
	chase_cam.name = "VirtualChaseCamera"
	chase_cam.priority = 10
	chase_cam.target_path = NodePath("../../PlayerCharacter")
	cam_host.add_child(chase_cam)

	# Collector Cart Vehicle
	var vehicle_scene := load("res://library/tycoon/collector_cart_vehicle.tscn") as PackedScene
	if vehicle_scene != null:
		var cart := vehicle_scene.instantiate() as CharacterBody3D
		cart.name = "PlayerCharacter"
		cart.position = Vector3(0.0, 0.6, 0.0)
		root.add_child(cart)
		chase_cam.target = cart

	return root
