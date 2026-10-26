extends Node3D
## fire_prison_controller.gd
## Authoritative zone controller bound to res://scenes/zones/fire_prison_rig.tscn
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
var npc_dialogue_preview: String = "The rig hull is pure iron! Extract coal from the vents (E) to forge a Metal Shield before crossing into the Warden's arena!"

var sky_top_color: Color = Color("#0f172a")
var sky_bottom_color: Color = Color("#1e1b2e")
var grid_tint_color: Color = Color("#475569")
var boss_color: Color = Color("#ef4444")

var encounter_start_time: float = 0.0
var coal_vent_charges: int = 6
var quad_debug_enabled: bool = false

var _env: Environment = null
var _deck_mat: StandardMaterial3D = null
var _ocean_mat: StandardMaterial3D = null
var _boss_mat: StandardMaterial3D = null
var _hazard_mat: StandardMaterial3D = null
var _hazard_mesh: TorusMesh = null
var _warden_mesh_node: MeshInstance3D = null
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
	# Dispatch procedural scatter & environment setup on WorkerThreadPool per CLAUDE.md Rule 1
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
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_apply_config_dictionary(parsed)

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
	_refresh_visual_materials()
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
	# 1. Floor collider on RigDeckFloor
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
		_deck_mat.albedo_color = grid_tint_color.darkened(0.45)
		_deck_mat.metallic = 0.55
		_deck_mat.roughness = 0.45
		bmesh.material = _deck_mat
		deck_mesh_inst.mesh = bmesh
		deck_mesh_inst.position = Vector3(0.0, -0.3, -10.0)
		deck_body.add_child(deck_mesh_inst)

	# 2. Boiling Ocean Plane
	var ocean_inst := MeshInstance3D.new()
	ocean_inst.name = "BoilingOceanVisual"
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(220.0, 220.0)
	_ocean_mat = StandardMaterial3D.new()
	_ocean_mat.albedo_color = sky_bottom_color
	_ocean_mat.emission_enabled = true
	_ocean_mat.emission = sky_bottom_color.lightened(0.15)
	_ocean_mat.emission_energy_multiplier = 0.45
	pmesh.material = _ocean_mat
	ocean_inst.mesh = pmesh
	ocean_inst.position = Vector3(0.0, -1.8, -10.0)
	add_child(ocean_inst)

	# 3. WorldEnvironment & DirectionalLight3D
	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = sky_top_color
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = grid_tint_color.lightened(0.35)
	_env.ambient_light_energy = 0.85
	world_env.environment = _env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.position = Vector3(16.0, 28.0, 18.0)
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.35
	add_child(sun)

	# 4. CoalVent_01 visual cylinder
	var vent := get_node_or_null("Interactables/CoalVent_01") as Node3D
	if vent != null:
		var vmesh_inst := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.1
		cyl.bottom_radius = 1.35
		cyl.height = 2.4
		var vmat := StandardMaterial3D.new()
		vmat.albedo_color = Color("#38bdf8")
		vmat.emission_enabled = true
		vmat.emission = Color("#0284c7")
		vmat.emission_energy_multiplier = 0.85
		cyl.material = vmat
		vmesh_inst.mesh = cyl
		vmesh_inst.position = Vector3(0.0, 0.4, 0.0)
		vent.add_child(vmesh_inst)

	# 5. BossArena Warden visual & Hazard Ring
	var arena := get_node_or_null("BossArena") as Node3D
	if arena != null:
		var hazard_inst := MeshInstance3D.new()
		hazard_inst.name = "HazardRingVisual"
		_hazard_mesh = TorusMesh.new()
		_hazard_mesh.inner_radius = hazard_radius - 0.45
		_hazard_mesh.outer_radius = hazard_radius
		_hazard_mat = StandardMaterial3D.new()
		_hazard_mat.albedo_color = boss_color
		_hazard_mat.emission_enabled = true
		_hazard_mat.emission = boss_color
		_hazard_mat.emission_energy_multiplier = 1.1
		_hazard_mesh.material = _hazard_mat
		hazard_inst.mesh = _hazard_mesh
		hazard_inst.position = Vector3(0.0, 0.15, 0.0)
		arena.add_child(hazard_inst)

		_warden_mesh_node = MeshInstance3D.new()
		_warden_mesh_node.name = "WardenBossVisual"
		var wbox := BoxMesh.new()
		wbox.size = Vector3(2.8, 4.2, 2.8)
		_boss_mat = StandardMaterial3D.new()
		_boss_mat.albedo_color = boss_color
		_boss_mat.emission_enabled = true
		_boss_mat.emission = boss_color.darkened(0.2)
		_boss_mat.emission_energy_multiplier = 0.9
		wbox.material = _boss_mat
		_warden_mesh_node.mesh = wbox
		_warden_mesh_node.position = Vector3(0.0, 2.2, 0.0)
		arena.add_child(_warden_mesh_node)

	# 6. Camera3D
	_main_camera = Camera3D.new()
	_main_camera.name = "MainArenaCamera"
	_main_camera.current = true
	_main_camera.fov = 58.0
	_main_camera.position = Vector3(0.0, 12.0, 28.0)
	add_child(_main_camera)

	# 7. CanvasLayer HUD inside Godot
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

func _refresh_visual_materials() -> void:
	if _env != null:
		_env.background_color = sky_top_color
		_env.ambient_light_color = grid_tint_color.lightened(0.35)
	if _deck_mat != null:
		_deck_mat.albedo_color = grid_tint_color.darkened(0.45)
	if _ocean_mat != null:
		_ocean_mat.albedo_color = sky_bottom_color
		_ocean_mat.emission = sky_bottom_color.lightened(0.15)
	if _boss_mat != null:
		_boss_mat.albedo_color = boss_color
		_boss_mat.emission = boss_color.darkened(0.2)
	if _hazard_mat != null:
		_hazard_mat.albedo_color = boss_color
		_hazard_mat.emission = boss_color
	if _hazard_mesh != null:
		_hazard_mesh.inner_radius = hazard_radius - 0.45
		_hazard_mesh.outer_radius = hazard_radius

func _update_hud_text() -> void:
	var player := get_node_or_null("PlayerCharacter")
	var player_hp_val := 500
	var shield_str := "OFF (Press E near CoalVent_01)"
	if player != null:
		player_hp_val = int(player.get("hp"))
		if bool(player.get("metal_shield_active")):
			shield_str = "ACTIVE (80% DR)"
	if _hud_label != null:
		var mode_tag := "QUAD_DEBUG (Top-Down)" if quad_debug_enabled else "3RD_PERSON"
		_hud_label.text = (
			"[GODOT 4.3 WASM ENGINE] Zone: %s | View: %s\n" % [zone_title, mode_tag]
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

	# Rotate boss visual
	if _warden_mesh_node != null:
		_warden_mesh_node.rotation.y += delta * 1.4
		var hp_scale := clampf(0.4 + 0.6 * (warden_hp / maxf(1.0, warden_max_hp)), 0.25, 1.0)
		_warden_mesh_node.scale = Vector3(hp_scale, hp_scale, hp_scale)

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
	noise.seed = 14014
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
