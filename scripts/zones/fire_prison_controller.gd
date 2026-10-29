extends Node3D
## fire_prison_controller.gd
## Dynamic procedural realm controller bound to res://scenes/zones/fire_prison_rig.tscn
## Strictly conforms to /specs/interface_contracts.json (sprint_014_prison_rig).

signal warden_encounter_started(warden_pos: Vector3)
signal coal_vent_extracted(vent_name: String, remaining_charges: int)
signal warden_defeated(duration_sec: float)

@export var max_draw_calls_budget: int = 180
@export var max_active_physics_bodies: int = 64

var zone_title: String = "The Boiling Iron Rig"
var warden_name: String = "Fire Warden Boss"
var warden_spawned: bool = true
var warden_hp: float = 2200.0
var warden_max_hp: float = 2200.0
var primary_ability_name: String = "Earth Lance"
var primary_ability_damage: float = 260.0
var hazard_name: String = "Thermal Fire Ring"
var hazard_radius: float = 11.0
var interactable_label: String = "Resource Node"
var npc_dialogue_preview: String = "Extract coal from the vents (E) to forge a Metal Shield before crossing into the Warden's arena!"

var sky_top_color: Color = Color("#0f172a")
var sky_bottom_color: Color = Color("#1e1b2e")
var grid_tint_color: Color = Color("#475569")
var boss_color: Color = Color("#ef4444")
var noise_seed: int = 14014
var biome_name: String = ""
var environment_fog: String = ""
var environment_lighting: String = ""

var encounter_start_time: float = 0.0
var coal_vent_charges: int = 6
var quad_debug_enabled: bool = false

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _deck_mat: StandardMaterial3D = null
var _ocean_mat: StandardMaterial3D = null
var _boss_mat: StandardMaterial3D = null
var _hazard_mat: StandardMaterial3D = null
var _hazard_mesh: TorusMesh = null
var _warden_mesh_node: Node3D = null
var _boss_core_mesh: MeshInstance3D = null
var _boss_orbiters: Array[Node3D] = []
var _procedural_root: Node3D = null
var _main_camera: Camera3D = null
var _hud_label: Label = null
var _dialogue_label: Label = null
var _projectiles: Array[Dictionary] = []
var _js_bundle_cb: Variant = null
var _js_pck_cb: Variant = null

func _ready() -> void:
	encounter_start_time = Time.get_ticks_msec() / 1000.0
	_load_gdd_design_config()
	_build_3d_arena_visuals()
	_setup_web_js_bridge()
	BootLoader.runtime_config_updated.connect(_apply_config_dictionary)
	BootLoader.realm_pack_mounted.connect(_on_realm_pack_mounted)
	ProceduralJobRunner.run_on_worker_thread(
		"init_fire_prison_environment",
		_generate_rig_procedural_layout,
		_on_rig_procedural_layout_ready
	)

func _load_gdd_design_config() -> void:
	if not BootLoader.runtime_override_config.is_empty():
		_apply_config_dictionary(BootLoader.runtime_override_config)
		return
	var f := FileAccess.open("res://specs/gdd_design.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_config_dictionary(parsed)
	
	# Load Geoff's terrain graph metadata if present
	if ResourceLoader.exists("res://resources/terrain_graphs/fire_ocean_rig.tres"):
		var tres := ResourceLoader.load("res://resources/terrain_graphs/fire_ocean_rig.tres")
		if tres != null:
			if tres.has_meta("seed"):
				noise_seed = int(tres.get_meta("seed"))
			if tres.has_meta("sky_top"):
				sky_top_color = Color.from_string(str(tres.get_meta("sky_top")), sky_top_color)
			if tres.has_meta("sky_bottom"):
				sky_bottom_color = Color.from_string(str(tres.get_meta("sky_bottom")), sky_bottom_color)

func _apply_config_dictionary(cfg: Dictionary) -> void:
	if cfg.has("zone_title"):
		zone_title = str(cfg["zone_title"])
	if cfg.has("boss_name"):
		warden_name = str(cfg["boss_name"])
	if cfg.has("boss_max_hp"):
		warden_max_hp = float(cfg["boss_max_hp"])
		warden_hp = warden_max_hp
	elif cfg.has("combat_parameters") and typeof(cfg["combat_parameters"]) == TYPE_DICTIONARY:
		var cp: Dictionary = cfg["combat_parameters"]
		if cp.has("warden_max_hp"):
			warden_max_hp = float(cp["warden_max_hp"])
			warden_hp = warden_max_hp
		if cp.has("primary_ability_damage"):
			primary_ability_damage = float(cp["primary_ability_damage"])
	if cfg.has("primary_ability_name"):
		primary_ability_name = str(cfg["primary_ability_name"])
	if cfg.has("primary_ability_damage"):
		primary_ability_damage = float(cfg["primary_ability_damage"])
	if cfg.has("interactable_name"):
		interactable_label = str(cfg["interactable_name"])
	if cfg.has("hazard_name"):
		hazard_name = str(cfg["hazard_name"])
	if cfg.has("hazard_radius"):
		hazard_radius = clampf(float(cfg["hazard_radius"]) * 0.14, 5.0, 18.0)
	if cfg.has("npc_dialogue_preview"):
		npc_dialogue_preview = str(cfg["npc_dialogue_preview"])
	if cfg.has("sky_top_hex"):
		sky_top_color = Color.from_string(str(cfg["sky_top_hex"]), sky_top_color)
	if cfg.has("sky_bottom_hex"):
		sky_bottom_color = Color.from_string(str(cfg["sky_bottom_hex"]), sky_bottom_color)
	if cfg.has("grid_tint_hex"):
		grid_tint_color = Color.from_string(str(cfg["grid_tint_hex"]), grid_tint_color)
	if cfg.has("boss_color_hex"):
		boss_color = Color.from_string(str(cfg["boss_color_hex"]), boss_color)
	if cfg.has("noise_seed"):
		noise_seed = int(cfg["noise_seed"])
	if cfg.has("environment") and typeof(cfg["environment"]) == TYPE_DICTIONARY:
		var env_dict: Dictionary = cfg["environment"]
		if env_dict.has("biome"):
			biome_name = str(env_dict["biome"])
		if env_dict.has("fog"):
			environment_fog = str(env_dict["fog"])
		if env_dict.has("lighting"):
			environment_lighting = str(env_dict["lighting"])
	_refresh_visual_materials()
	_generate_procedural_architecture()
	_update_hud_text()

func _on_realm_pack_mounted(_realm_id: String, _pack_path: String) -> void:
	_load_gdd_design_config()

func _setup_web_js_bridge() -> void:
	if not OS.has_feature("web"):
		return
	_js_bundle_cb = JavaScriptBridge.create_callback(_on_js_bundle_received)
	_js_pck_cb = JavaScriptBridge.create_callback(_on_js_pck_received)
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if win != null:
		win.playableHotReloadBundle = _js_bundle_cb
		win.playableMountPckBase64 = _js_pck_cb

func _on_js_bundle_received(args: Array) -> void:
	if args.size() > 0:
		var json_str := str(args[0])
		BootLoader.apply_runtime_config_json(json_str)

func _on_js_pck_received(args: Array) -> void:
	if args.size() >= 2:
		var realm_id := str(args[0])
		var b64 := str(args[1])
		BootLoader.mount_pck_from_base64(realm_id, b64)
		if args.size() >= 3:
			BootLoader.apply_runtime_config_json(str(args[2]))

func _build_3d_arena_visuals() -> void:
	# 1. Floor collider on RigDeckFloor (Physics body required for navigation & standing)
	var deck_body := get_node_or_null("NavigationRegion3D/RigDeckFloor") as StaticBody3D
	if deck_body != null and deck_body.get_node_or_null("DeckCollider") == null:
		var col := CollisionShape3D.new()
		col.name = "DeckCollider"
		var box := BoxShape3D.new()
		box.size = Vector3(52.0, 1.0, 76.0)
		col.shape = box
		col.position = Vector3(0.0, -0.5, -10.0)
		deck_body.add_child(col)

		var deck_mesh_inst := MeshInstance3D.new()
		deck_mesh_inst.name = "DeckVisual"
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(48.0, 0.6, 72.0)
		_deck_mat = StandardMaterial3D.new()
		_deck_mat.albedo_color = grid_tint_color.darkened(0.55)
		_deck_mat.metallic = 0.65
		_deck_mat.roughness = 0.35
		bmesh.material = _deck_mat
		deck_mesh_inst.mesh = bmesh
		deck_mesh_inst.position = Vector3(0.0, -0.3, -10.0)
		deck_body.add_child(deck_mesh_inst)

	# 2. Dynamic Boiling Ocean / Abyssal Fluid Plane
	var ocean_inst := get_node_or_null("BoilingOceanVisual") as MeshInstance3D
	if ocean_inst == null:
		ocean_inst = MeshInstance3D.new()
		ocean_inst.name = "BoilingOceanVisual"
		var pmesh := PlaneMesh.new()
		pmesh.size = Vector2(260.0, 260.0)
		pmesh.subdivide_width = 16
		pmesh.subdivide_depth = 16
		_ocean_mat = StandardMaterial3D.new()
		_ocean_mat.albedo_color = sky_bottom_color.darkened(0.2)
		_ocean_mat.emission_enabled = true
		_ocean_mat.emission = sky_bottom_color.lightened(0.2)
		_ocean_mat.emission_energy_multiplier = 0.6
		_ocean_mat.roughness = 0.2
		pmesh.material = _ocean_mat
		ocean_inst.mesh = pmesh
		ocean_inst.position = Vector3(0.0, -2.2, -10.0)
		add_child(ocean_inst)

	# 3. WorldEnvironment & DirectionalLight3D
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		_env = Environment.new()
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = sky_top_color
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = grid_tint_color.lightened(0.4)
		_env.ambient_light_energy = 0.95
		_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = 0.012
		_env.volumetric_fog_albedo = sky_bottom_color.lightened(0.2)
		_env.glow_enabled = true
		_env.glow_bloom = 0.25
		_env.glow_intensity = 0.75
		world_env.environment = _env
		add_child(world_env)

	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		_sun.position = Vector3(20.0, 32.0, 22.0)
		_sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
		_sun.light_energy = 1.4
		_sun.light_color = grid_tint_color.lightened(0.6)
		_sun.shadow_enabled = true
		add_child(_sun)

	# 4. Generate Rich Procedural Architecture & Pillars
	_generate_procedural_architecture()

	# 5. Dynamic Conduit / Resource Node
	var vent := get_node_or_null("Interactables/CoalVent_01") as Node3D
	if vent != null and vent.get_node_or_null("VentVisual") == null:
		var v_root := Node3D.new()
		v_root.name = "VentVisual"
		
		var base_inst := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.6
		cyl.height = 2.2
		var vmat := StandardMaterial3D.new()
		vmat.albedo_color = Color("#1e293b")
		vmat.metallic = 0.8
		vmat.roughness = 0.3
		cyl.material = vmat
		base_inst.mesh = cyl
		base_inst.position = Vector3(0.0, 0.3, 0.0)
		v_root.add_child(base_inst)

		var crystal_inst := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.2, 1.8, 1.2)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = grid_tint_color.lightened(0.2)
		cmat.emission_enabled = true
		cmat.emission = grid_tint_color.lightened(0.3)
		cmat.emission_energy_multiplier = 1.6
		prism.material = cmat
		crystal_inst.mesh = prism
		crystal_inst.position = Vector3(0.0, 1.8, 0.0)
		v_root.add_child(crystal_inst)

		var omni := OmniLight3D.new()
		omni.light_color = grid_tint_color.lightened(0.4)
		omni.light_energy = 1.8
		omni.omni_range = 7.5
		omni.position = Vector3(0.0, 1.8, 0.0)
		v_root.add_child(omni)

		vent.add_child(v_root)

	# 6. BossArena Warden composite visual & Hazard Ring
	var arena := get_node_or_null("BossArena") as Node3D
	if arena != null:
		if arena.get_node_or_null("HazardRingVisual") == null:
			var hazard_inst := MeshInstance3D.new()
			hazard_inst.name = "HazardRingVisual"
			_hazard_mesh = TorusMesh.new()
			_hazard_mesh.inner_radius = hazard_radius - 0.5
			_hazard_mesh.outer_radius = hazard_radius
			_hazard_mat = StandardMaterial3D.new()
			_hazard_mat.albedo_color = boss_color
			_hazard_mat.emission_enabled = true
			_hazard_mat.emission = boss_color
			_hazard_mat.emission_energy_multiplier = 1.3
			_hazard_mesh.material = _hazard_mat
			hazard_inst.mesh = _hazard_mesh
			hazard_inst.position = Vector3(0.0, 0.15, 0.0)
			arena.add_child(hazard_inst)

		if arena.get_node_or_null("WardenBossVisual") == null:
			_warden_mesh_node = Node3D.new()
			_warden_mesh_node.name = "WardenBossVisual"
			_warden_mesh_node.position = Vector3(0.0, 2.2, 0.0)

			# Central Core
			_boss_core_mesh = MeshInstance3D.new()
			_boss_core_mesh.name = "BossCore"
			var wbox := BoxMesh.new()
			wbox.size = Vector3(2.6, 4.0, 2.6)
			_boss_mat = StandardMaterial3D.new()
			_boss_mat.albedo_color = boss_color
			_boss_mat.emission_enabled = true
			_boss_mat.emission = boss_color.darkened(0.15)
			_boss_mat.emission_energy_multiplier = 0.95
			_boss_mat.metallic = 0.45
			_boss_mat.roughness = 0.35
			wbox.material = _boss_mat
			_boss_core_mesh.mesh = wbox
			_warden_mesh_node.add_child(_boss_core_mesh)

			# Horns / Crown Spikes
			var crown := MeshInstance3D.new()
			var pmesh := PrismMesh.new()
			pmesh.size = Vector3(2.8, 1.8, 1.8)
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = boss_color.darkened(0.3)
			cmat.emission_enabled = true
			cmat.emission = boss_color
			cmat.emission_energy_multiplier = 0.7
			pmesh.material = cmat
			crown.mesh = pmesh
			crown.position = Vector3(0.0, 2.4, 0.0)
			_warden_mesh_node.add_child(crown)

			# Glowing Eye / Heart Core
			var eye := MeshInstance3D.new()
			var smesh := SphereMesh.new()
			smesh.radius = 0.75
			smesh.height = 1.5
			var emat := StandardMaterial3D.new()
			emat.albedo_color = Color("#ffffff")
			emat.emission_enabled = true
			emat.emission = boss_color.lightened(0.3)
			emat.emission_energy_multiplier = 2.4
			smesh.material = emat
			eye.mesh = smesh
			eye.position = Vector3(0.0, 0.3, 0.8)
			_warden_mesh_node.add_child(eye)

			var boss_light := OmniLight3D.new()
			boss_light.light_color = boss_color.lightened(0.2)
			boss_light.light_energy = 2.2
			boss_light.omni_range = 10.0
			boss_light.position = Vector3(0.0, 0.5, 0.0)
			_warden_mesh_node.add_child(boss_light)

			# 3 Orbiting Runic Satellites
			_boss_orbiters.clear()
			for i in range(3):
				var orbiter := Node3D.new()
				orbiter.name = "BossOrbiter_%d" % i
				var omesh_inst := MeshInstance3D.new()
				var obox := BoxMesh.new()
				obox.size = Vector3(0.65, 0.65, 0.65)
				var omat := StandardMaterial3D.new()
				omat.albedo_color = grid_tint_color.lightened(0.3)
				omat.emission_enabled = true
				omat.emission = grid_tint_color.lightened(0.4)
				omat.emission_energy_multiplier = 1.8
				obox.material = omat
				omesh_inst.mesh = obox
				orbiter.add_child(omesh_inst)
				_warden_mesh_node.add_child(orbiter)
				_boss_orbiters.append(orbiter)

			arena.add_child(_warden_mesh_node)

	# 7. Camera3D
	if _main_camera == null:
		_main_camera = Camera3D.new()
		_main_camera.name = "MainArenaCamera"
		_main_camera.current = true
		_main_camera.fov = 58.0
		_main_camera.position = Vector3(0.0, 12.0, 28.0)
		add_child(_main_camera)

	# 8. CanvasLayer HUD inside Godot
	if get_node_or_null("GodotArenaHUD") == null:
		var canvas := CanvasLayer.new()
		canvas.name = "GodotArenaHUD"
		add_child(canvas)

		var panel := PanelContainer.new()
		panel.position = Vector2(14.0, 14.0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.06, 0.11, 0.82)
		style.border_color = Color(0.22, 0.74, 0.97, 0.45)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 8.0
		style.content_margin_bottom = 8.0
		panel.add_theme_stylebox_override("panel", style)
		canvas.add_child(panel)

		_hud_label = Label.new()
		_hud_label.add_theme_font_size_override("font_size", 13)
		_hud_label.add_theme_color_override("font_color", Color("#f8fafc"))
		panel.add_child(_hud_label)

		var bottom_panel := PanelContainer.new()
		bottom_panel.position = Vector2(14.0, 650.0)
		bottom_panel.add_theme_stylebox_override("panel", style)
		canvas.add_child(bottom_panel)

		_dialogue_label = Label.new()
		_dialogue_label.add_theme_font_size_override("font_size", 13)
		_dialogue_label.add_theme_color_override("font_color", Color("#38bdf8"))
		bottom_panel.add_child(_dialogue_label)

	_update_hud_text()

func _generate_procedural_architecture() -> void:
	if _procedural_root != null:
		_procedural_root.queue_free()
	
	_procedural_root = Node3D.new()
	_procedural_root.name = "DynamicProceduralArchitecture"
	add_child(_procedural_root)

	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed

	# Architectural Pillar Material
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = grid_tint_color.darkened(0.35)
	pillar_mat.metallic = 0.5
	pillar_mat.roughness = 0.4

	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = grid_tint_color.lightened(0.2)
	rune_mat.emission_enabled = true
	rune_mat.emission = grid_tint_color.lightened(0.3)
	rune_mat.emission_energy_multiplier = 1.4

	# 1. Perimeter Flank Columns (10 Pillars along Left & Right Arena Edges)
	var z_coords := [-42.0, -28.0, -14.0, 0.0, 14.0]
	for side_val in [-1.0, 1.0]:
		var x_pos: float = float(side_val) * 22.0
		for z_pos in z_coords:
			var pillar_node := Node3D.new()
			pillar_node.position = Vector3(x_pos, 0.0, z_pos)

			# Pedestal Base
			var base_inst := MeshInstance3D.new()
			var bmesh := BoxMesh.new()
			bmesh.size = Vector3(2.4, 0.8, 2.4)
			bmesh.material = pillar_mat
			base_inst.mesh = bmesh
			base_inst.position = Vector3(0.0, 0.4, 0.0)
			pillar_node.add_child(base_inst)

			# Shaft
			var shaft_h := rng.randf_range(6.0, 9.5)
			var shaft_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.85
			cyl.bottom_radius = 1.15
			cyl.height = shaft_h
			cyl.material = pillar_mat
			shaft_inst.mesh = cyl
			shaft_inst.position = Vector3(0.0, 0.8 + shaft_h * 0.5, 0.0)
			pillar_node.add_child(shaft_inst)

			# Emissive Capital / Rune Torus
			var cap_inst := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.65
			tor.outer_radius = 1.15
			tor.material = rune_mat
			cap_inst.mesh = tor
			cap_inst.position = Vector3(0.0, 0.8 + shaft_h, 0.0)
			pillar_node.add_child(cap_inst)

			_procedural_root.add_child(pillar_node)

	# 2. Grand Entrance Archway threshold (z = -18.0)
	var arch_node := Node3D.new()
	arch_node.position = Vector3(0.0, 0.0, -18.0)
	for side_val in [-1.0, 1.0]:
		var p_inst := MeshInstance3D.new()
		var p_cyl := CylinderMesh.new()
		p_cyl.top_radius = 1.1
		p_cyl.bottom_radius = 1.3
		p_cyl.height = 9.0
		p_cyl.material = pillar_mat
		p_inst.mesh = p_cyl
		p_inst.position = Vector3(float(side_val) * 10.5, 4.5, 0.0)
		arch_node.add_child(p_inst)
	
	# Overhead Lintel Beam
	var lintel_inst := MeshInstance3D.new()
	var lbox := BoxMesh.new()
	lbox.size = Vector3(23.0, 1.1, 1.8)
	lbox.material = pillar_mat
	lintel_inst.mesh = lbox
	lintel_inst.position = Vector3(0.0, 8.8, 0.0)
	arch_node.add_child(lintel_inst)

	# Keystone Runestone
	var key_inst := MeshInstance3D.new()
	var key_prism := PrismMesh.new()
	key_prism.size = Vector3(2.2, 1.8, 1.8)
	key_prism.material = rune_mat
	key_inst.mesh = key_prism
	key_inst.position = Vector3(0.0, 9.8, 0.0)
	arch_node.add_child(key_inst)

	_procedural_root.add_child(arch_node)

	# 3. Boss Sanctum Dais & Towering Backdrop Monoliths (z = -46.0)
	var sanctum_node := Node3D.new()
	sanctum_node.position = Vector3(0.0, 0.0, -46.0)
	var backdrop_x := [-9.0, 0.0, 9.0]
	var backdrop_h := [10.5, 13.5, 10.5]
	for i in range(3):
		var b_inst := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(4.5, backdrop_h[i], 2.2)
		bbox.material = pillar_mat
		b_inst.mesh = bbox
		b_inst.position = Vector3(backdrop_x[i], backdrop_h[i] * 0.5, 0.0)
		sanctum_node.add_child(b_inst)

		var b_rune := MeshInstance3D.new()
		var r_box := BoxMesh.new()
		r_box.size = Vector3(2.2, 1.2, 2.4)
		r_box.material = rune_mat
		b_rune.mesh = r_box
		b_rune.position = Vector3(backdrop_x[i], backdrop_h[i] * 0.7, 0.0)
		sanctum_node.add_child(b_rune)

	_procedural_root.add_child(sanctum_node)

	# 4. Abyss / Ocean Spires (Jagged monoliths scattered outside the deck)
	for i in range(12):
		var side_val: float = -1.0 if (i % 2 == 0) else 1.0
		var ox: float = side_val * rng.randf_range(28.0, 48.0)
		var oz: float = rng.randf_range(-54.0, 22.0)
		var oh: float = rng.randf_range(5.0, 14.0)

		var spire_inst := MeshInstance3D.new()
		var scyl := CylinderMesh.new()
		scyl.top_radius = 0.2
		scyl.bottom_radius = rng.randf_range(2.0, 3.8)
		scyl.height = oh
		var smat := StandardMaterial3D.new()
		smat.albedo_color = sky_bottom_color.darkened(0.4)
		smat.roughness = 0.8
		scyl.material = smat
		spire_inst.mesh = scyl
		spire_inst.position = Vector3(ox, -2.0 + oh * 0.5, oz)
		spire_inst.rotation_degrees = Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(0.0, 360.0), rng.randf_range(-8.0, 8.0))
		_procedural_root.add_child(spire_inst)

func _refresh_visual_materials() -> void:
	if _env != null:
		_env.background_color = sky_top_color
		_env.ambient_light_color = grid_tint_color.lightened(0.4)
		_env.volumetric_fog_albedo = sky_bottom_color.lightened(0.2)
	if _sun != null:
		_sun.light_color = grid_tint_color.lightened(0.6)
	if _deck_mat != null:
		_deck_mat.albedo_color = grid_tint_color.darkened(0.55)
	if _ocean_mat != null:
		_ocean_mat.albedo_color = sky_bottom_color.darkened(0.2)
		_ocean_mat.emission = sky_bottom_color.lightened(0.2)
	if _boss_mat != null:
		_boss_mat.albedo_color = boss_color
		_boss_mat.emission = boss_color.darkened(0.15)
	if _hazard_mat != null:
		_hazard_mat.albedo_color = boss_color
		_hazard_mat.emission = boss_color
	if _hazard_mesh != null:
		_hazard_mesh.inner_radius = hazard_radius - 0.5
		_hazard_mesh.outer_radius = hazard_radius

func _update_hud_text() -> void:
	var player := get_node_or_null("PlayerCharacter")
	var player_hp_val := 500
	var shield_str := "OFF (Press E near %s)" % interactable_label
	if player != null:
		player_hp_val = int(player.get("hp"))
		if bool(player.get("metal_shield_active")):
			shield_str = "ACTIVE (80% DR)"
	if _hud_label != null:
		var mode_tag := "QUAD_DEBUG (Top-Down)" if quad_debug_enabled else "3RD_PERSON"
		_hud_label.text = (
			"[GODOT 4.7+ NATIVE ENGINE • JOLT PHYSICS 3D] Zone: %s | View: %s\n" % [zone_title, mode_tag]
			+ "Boss: %s (%d / %d HP) | Hazard: %s\n" % [warden_name, int(warden_hp), int(warden_max_hp), hazard_name]
			+ "Player HP: %d / 500 | Metal Shield: %s | Ability (Space): %s (%d DMG)" % [
				player_hp_val,
				shield_str,
				primary_ability_name,
				int(primary_ability_damage)
			]
		)
	if _dialogue_label != null:
		_dialogue_label.text = 'NPC: "%s"  [WASD: Move | E: Extract Shield | Space: Cast Ability | Q: Toggle QA Camera]' % npc_dialogue_preview

func _process(delta: float) -> void:
	var player := get_node_or_null("PlayerCharacter") as Node3D
	var vent := get_node_or_null("Interactables/CoalVent_01") as Node3D
	var arena := get_node_or_null("BossArena") as Node3D
	var t := Time.get_ticks_msec() / 1000.0

	if Input.is_action_just_pressed("toggle_quad_debug"):
		quad_debug_enabled = not quad_debug_enabled
		_update_hud_text()

	if player != null and vent != null and Input.is_action_just_pressed("ability_secondary"):
		if player.global_position.distance_to(vent.global_position) <= 9.5:
			if extract_metal_from_vent(vent) and player.has_method("set_metal_shield"):
				player.call("set_metal_shield", true)
				_update_hud_text()

	if player != null and Input.is_action_just_pressed("ability_primary"):
		_spawn_ability_projectile(player.global_position + Vector3(0.0, 1.3, -0.8))

	# Update projectiles
	var remaining: Array[Dictionary] = []
	for proj in _projectiles:
		var pnode: MeshInstance3D = proj["node"]
		pnode.global_position.z -= 34.0 * delta
		if arena != null and pnode.global_position.distance_to(arena.global_position + Vector3(0.0, 1.5, 0.0)) <= 4.0:
			apply_damage_to_warden(primary_ability_damage)
			pnode.queue_free()
			_update_hud_text()
		elif pnode.global_position.z < -55.0:
			pnode.queue_free()
		else:
			remaining.append(proj)
	_projectiles = remaining

	# Dynamic Boss Animation: Floating hover bob, rotation & orbiting satellites
	if _warden_mesh_node != null:
		_warden_mesh_node.rotation.y += delta * 1.3
		_warden_mesh_node.position.y = 2.2 + sin(t * 2.2) * 0.35
		var hp_scale := clampf(0.4 + 0.6 * (warden_hp / maxf(1.0, warden_max_hp)), 0.25, 1.0)
		_warden_mesh_node.scale = Vector3(hp_scale, hp_scale, hp_scale)

		for i in range(_boss_orbiters.size()):
			var orb := _boss_orbiters[i]
			var ang: float = t * 2.4 + float(i) * (TAU / 3.0)
			orb.position = Vector3(cos(ang) * 3.4, 0.4 + sin(t * 3.5 + float(i)) * 0.45, sin(ang) * 3.4)
			orb.rotation.y += delta * 3.0

	# Thermal hazard tick near BossArena
	if player != null and arena != null and warden_hp > 0.0:
		var dist := player.global_position.distance_to(arena.global_position)
		if dist <= hazard_radius:
			var shield_on := bool(player.get("metal_shield_active"))
			var dmg_rate := 3.5 if shield_on else 18.0
			var next_hp := maxf(25.0, float(player.get("hp")) - dmg_rate * delta)
			player.set("hp", next_hp)
			_update_hud_text()

	# Camera tracking
	if _main_camera != null and player != null:
		if quad_debug_enabled:
			_main_camera.global_position = Vector3(0.0, 48.0, -8.0)
			_main_camera.look_at(Vector3(0.0, 0.0, -10.0), Vector3.FORWARD)
		else:
			var target_cam := player.global_position + Vector3(0.0, 8.5, 13.5)
			_main_camera.global_position = _main_camera.global_position.lerp(target_cam, minf(1.0, delta * 6.0))
			_main_camera.look_at(player.global_position + Vector3(0.0, 1.2, -6.0), Vector3.UP)

func _spawn_ability_projectile(spawn_pos: Vector3) -> void:
	var pmesh_inst := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#f59e0b")
	mat.emission_enabled = true
	mat.emission = Color("#fbbf24")
	mat.emission_energy_multiplier = 1.4
	sph.material = mat
	pmesh_inst.mesh = sph
	pmesh_inst.global_position = spawn_pos
	add_child(pmesh_inst)
	_projectiles.append({"node": pmesh_inst})

func _generate_rig_procedural_layout() -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.025
	return {
		"seed": noise.seed,
		"ocean_wave_Sample": noise.get_noise_2d(10.0, 20.0),
		"coal_nodes_ready": true
	}

func _on_rig_procedural_layout_ready(_layout_data: Variant) -> void:
	pass

func _on_arena_trigger_body_entered(body: Node3D) -> void:
	if not NetworkManager.can_execute_authoritative_mutation():
		return
	if body != null and (body.name.begins_with("Player") or body.name.begins_with("QA_Bot")):
		warden_spawned = true
		encounter_start_time = Time.get_ticks_msec() / 1000.0
		var spawn_marker := get_node_or_null("BossArena/WardenSpawn") as Marker3D
		var spawn_pos := spawn_marker.global_position if spawn_marker != null else Vector3(0.0, 2.0, -35.0)
		warden_encounter_started.emit(spawn_pos)

func extract_metal_from_vent(vent_node: Node3D) -> bool:
	if coal_vent_charges <= 0:
		return false
	if vent_node != null and vent_node.is_in_group("metal_source"):
		coal_vent_charges -= 1
		coal_vent_extracted.emit(vent_node.name, coal_vent_charges)
		return true
	return false

func apply_damage_to_warden(amount: float) -> void:
	if not warden_spawned:
		return
	if warden_hp <= 0.0:
		warden_hp = warden_max_hp
	warden_hp = maxf(0.0, warden_hp - amount)
	if warden_hp == 0.0:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - encounter_start_time
		warden_defeated.emit(elapsed)
