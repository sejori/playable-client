class_name ModularEntityTraits
extends Node3D
## ModularEntityTraits.gd
## Universal Composable Entity Traits Component (Phase 3).
## Attaches ambient motion, combat behaviors, harvesting mechanics, collectible magnets,
## hazard pulses, impulse boosters, and dialogue triggers to any modular entity.

@export var traits_config: Array = []

# Parent caching
var parent: Node3D = null
var _initial_parent_y: float = 0.0
var _initial_global_pos: Vector3 = Vector3.ZERO
var _base_scale: Vector3 = Vector3.ONE

# 1. ambient_motion state
var _has_ambient_motion: bool = false
var _ambient_spin_deg_sec: float = 0.0
var _ambient_bob_amp: float = 0.0
var _ambient_bob_speed: float = 2.0
var _ambient_pulse_emission: bool = false
var _ambient_flicker_light: bool = false
var _bob_time: float = 0.0
var _pulse_time: float = 0.0
var _flicker_time: float = 0.0
var _cached_materials: Array[StandardMaterial3D] = []
var _cached_lights: Array[OmniLight3D] = []
var _initial_light_energies: Dictionary = {}

# 2. combat_unit state
var _has_combat_unit: bool = false
var _combat_role: String = "minion"
var _combat_faction: String = "hostile"
var _combat_display_name: String = "Unit"
var _combat_max_hp: float = 100.0
var _combat_current_hp: float = 100.0
var _combat_attack_damage: float = 15.0
var _combat_attack_range: float = 3.0
var _combat_move_speed: float = 3.5
var _combat_projectile_color: Color = Color(1.0, 0.4, 0.1)
var _combat_attack_timer: float = 0.0
var _boss_shockwave_timer: float = 0.0
var _is_defeated: bool = false

# 3. harvestable state
var _has_harvestable: bool = false
var _harvest_resource_name: String = "Resource"
var _harvest_max_charges: int = 5
var _harvest_charges_remaining: int = 5
var _harvest_tick_interval: float = 0.6
var _harvest_respawn_sec: float = 8.0
var _harvest_timer: float = 0.0
var _harvest_respawn_timer: float = 0.0

# 4. collectible state
var _has_collectible: bool = false
var _collectible_item_name: String = "Coin"
var _collectible_score_value: int = 10
var _collectible_magnet_radius: float = 3.5
var _collectible_is_collected: bool = false
var _collectible_respawn_timer: float = 0.0

# 5. hazard_emitter state
var _has_hazard_emitter: bool = false
var _hazard_cycle_sec: float = 4.0
var _hazard_radius: float = 3.0
var _hazard_damage_per_sec: float = 25.0
var _hazard_telegraph_color: Color = Color(1.0, 0.2, 0.0)
var _hazard_cycle_time: float = 0.0
var _hazard_ring_mesh: MeshInstance3D = null
var _hazard_ring_mat: StandardMaterial3D = null

# 6. impulse_pad state
var _has_impulse_pad: bool = false
var _impulse_upward_velocity: float = 0.0
var _impulse_forward_boost: float = 0.0
var _impulse_multiplier: float = 1.0
var _pad_cooldowns: Dictionary = {} # body_id -> tick_msec

# 7. dialogue_trigger state
var _has_dialogue_trigger: bool = false
var _dialogue_path: String = ""
var _dialogue_start_node: String = ""
var _dialogue_prompt_label: String = ""

func _ready() -> void:
	parent = get_parent() as Node3D
	if parent == null:
		push_warning("[ModularEntityTraits] Parent is not a Node3D.")
		return

	_initial_parent_y = parent.position.y
	_initial_global_pos = parent.global_position
	_base_scale = parent.scale
	parent.set_meta("traits_controller", self)

	_init_traits()

func _init_traits() -> void:
	for item in traits_config:
		if not (item is Dictionary):
			continue
		var t_dict: Dictionary = item as Dictionary
		var t_type: String = str(t_dict.get("type", "")).strip_edges().to_lower()

		match t_type:
			"ambient_motion":
				_setup_ambient_motion(t_dict)
			"combat_unit":
				_setup_combat_unit(t_dict)
			"harvestable":
				_setup_harvestable(t_dict)
			"collectible":
				_setup_collectible(t_dict)
			"hazard_emitter":
				_setup_hazard_emitter(t_dict)
			"impulse_pad":
				_setup_impulse_pad(t_dict)
			"dialogue_trigger":
				_setup_dialogue_trigger(t_dict)

# -----------------------------------------------------------------------------
# 1. ambient_motion
# -----------------------------------------------------------------------------
func _setup_ambient_motion(cfg: Dictionary) -> void:
	_has_ambient_motion = true
	_ambient_spin_deg_sec = float(cfg.get("spin_deg_sec", 0.0))
	_ambient_bob_amp = float(cfg.get("bob_amp", 0.0))
	_ambient_bob_speed = float(cfg.get("bob_speed", 2.0))
	_ambient_pulse_emission = bool(cfg.get("pulse_emission", false))
	_ambient_flicker_light = bool(cfg.get("flicker_light", false))

	if _ambient_pulse_emission:
		_cache_parent_materials()
	if _ambient_flicker_light:
		_cache_parent_lights()

func _cache_parent_materials() -> void:
	_cached_materials.clear()
	var meshes := _find_all_meshes(parent)
	for m in meshes:
		var mat := m.get_surface_override_material(0)
		if mat == null and m.mesh != null and m.mesh.material != null:
			mat = m.mesh.material.duplicate()
			m.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			std_mat.emission_enabled = true
			if std_mat.emission == Color.BLACK:
				std_mat.emission = std_mat.albedo_color
			_cached_materials.append(std_mat)

func _cache_parent_lights() -> void:
	_cached_lights.clear()
	var lights := _find_all_omni_lights(parent)
	for l in lights:
		_cached_lights.append(l)
		_initial_light_energies[l.get_instance_id()] = l.light_energy

# -----------------------------------------------------------------------------
# 2. combat_unit
# -----------------------------------------------------------------------------
func _setup_combat_unit(cfg: Dictionary) -> void:
	_has_combat_unit = true
	_combat_role = str(cfg.get("role", "minion")).strip_edges().to_lower()
	_combat_faction = str(cfg.get("faction", "hostile")).strip_edges().to_lower()
	_combat_display_name = str(cfg.get("display_name", "Unit"))
	_combat_max_hp = float(cfg.get("max_hp", 100.0))
	_combat_current_hp = _combat_max_hp
	_combat_attack_damage = float(cfg.get("attack_damage", 15.0))
	_combat_attack_range = float(cfg.get("attack_range", 3.0))
	_combat_move_speed = float(cfg.get("move_speed", 3.5))

	var raw_color: Variant = cfg.get("projectile_color", null)
	if raw_color != null:
		_combat_projectile_color = _parse_color(raw_color, Color(1.0, 0.4, 0.1))
	else:
		if _combat_role == "boss":
			_combat_projectile_color = Color(1.0, 0.25, 0.0)
		elif _combat_faction == "blue_army" or _combat_role == "ally":
			_combat_projectile_color = Color(0.1, 0.7, 1.0)
		else:
			_combat_projectile_color = Color(1.0, 0.4, 0.1)

	parent.add_to_group("combat_unit")
	if _combat_role == "boss":
		parent.add_to_group("boss_target")
	if _combat_faction == "hostile":
		parent.add_to_group("hostile_unit")
	if _combat_role == "ally" or _combat_faction == "blue_army":
		parent.add_to_group("ally_unit")
	if _combat_role == "player":
		parent.add_to_group("player")

	parent.set_meta("display_name", _combat_display_name)
	parent.set_meta("max_hp", _combat_max_hp)
	parent.set_meta("current_hp", _combat_current_hp)
	parent.set_meta("role", _combat_role)
	parent.set_meta("faction", _combat_faction)

func apply_damage(amount: float) -> void:
	if not _has_combat_unit or _is_defeated:
		return

	_combat_current_hp = maxf(0.0, _combat_current_hp - amount)
	parent.set_meta("current_hp", _combat_current_hp)

	# If parent has ModularBossController or take_damage, notify it as well
	if parent.has_method("take_damage"):
		parent.call("take_damage", amount)

	_flash_mesh_damage()
	_spawn_floating_label("-%d" % int(amount), Color(1.0, 0.2, 0.1), Vector3(0.0, 2.0, 0.0))

	if _combat_current_hp <= 0.0:
		_handle_defeat()

func _handle_defeat() -> void:
	if _combat_role == "player":
		_combat_current_hp = _combat_max_hp
		parent.set_meta("current_hp", _combat_max_hp)
		parent.global_position = _initial_global_pos
		_spawn_floating_label("RESPAWN", Color(0.2, 1.0, 0.4), Vector3(0.0, 2.0, 0.0))
		return

	_is_defeated = true
	_spawn_floating_label("DEFEATED!", Color(1.0, 0.85, 0.1), Vector3(0.0, 2.2, 0.0))

	# Defeat animation: scale down and queue respawn or signal
	var tw := create_tween()
	tw.tween_property(parent, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		_combat_current_hp = _combat_max_hp
		parent.set_meta("current_hp", _combat_max_hp)
		parent.global_position = _initial_global_pos
		parent.scale = _base_scale
		_is_defeated = false
	)

func _flash_mesh_damage() -> void:
	var meshes := _find_all_meshes(parent)
	for m in meshes:
		var mat := m.get_surface_override_material(0)
		if mat == null and m.mesh != null and m.mesh.material != null:
			mat = m.mesh.material.duplicate()
			m.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			var orig_albedo := std_mat.albedo_color
			var orig_emission := std_mat.emission
			var orig_energy := std_mat.emission_energy_multiplier
			var orig_enabled := std_mat.emission_enabled
			std_mat.albedo_color = Color(1.0, 0.2, 0.2)
			std_mat.emission_enabled = true
			std_mat.emission = Color(1.0, 0.1, 0.1)
			std_mat.emission_energy_multiplier = 4.0
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_callback(func():
				if is_instance_valid(std_mat):
					std_mat.albedo_color = orig_albedo
					std_mat.emission = orig_emission
					std_mat.emission_energy_multiplier = orig_energy
					std_mat.emission_enabled = orig_enabled
			)

# -----------------------------------------------------------------------------
# 3. harvestable
# -----------------------------------------------------------------------------
func _setup_harvestable(cfg: Dictionary) -> void:
	_has_harvestable = true
	_harvest_resource_name = str(cfg.get("resource_name", "Resource"))
	_harvest_max_charges = int(cfg.get("max_charges", 5))
	_harvest_charges_remaining = _harvest_max_charges
	_harvest_tick_interval = float(cfg.get("tick_interval_sec", 0.6))
	_harvest_respawn_sec = float(cfg.get("respawn_sec", 8.0))

	parent.add_to_group("harvestable")
	parent.set_meta("resource_name", _harvest_resource_name)
	parent.set_meta("max_charges", _harvest_max_charges)
	parent.set_meta("charges_remaining", _harvest_charges_remaining)

func trigger_harvest_tick() -> void:
	if not _has_harvestable or _harvest_charges_remaining <= 0:
		return

	_harvest_charges_remaining -= 1
	parent.set_meta("charges_remaining", _harvest_charges_remaining)

	# Visible scale-pulse tween on parent
	var tw := create_tween()
	tw.tween_property(parent, "scale", _base_scale * 1.15, 0.1)
	tw.tween_property(parent, "scale", _base_scale, 0.1)

	# Rising floating +1 Label3D
	_spawn_floating_label("+1 %s" % _harvest_resource_name, Color(0.2, 0.9, 0.4), Vector3(0.0, 2.2, 0.0))

	# Increment scene metadata
	var scene := get_tree().current_scene
	if scene != null:
		var tot: int = int(scene.get_meta("harvested_total", 0)) + 1
		scene.set_meta("harvested_total", tot)
		var key := "harvested_" + _harvest_resource_name
		var item_tot: int = int(scene.get_meta(key, 0)) + 1
		scene.set_meta(key, item_tot)

	if _harvest_charges_remaining <= 0:
		parent.scale = _base_scale * 0.25
		_harvest_respawn_timer = 0.0

# -----------------------------------------------------------------------------
# 4. collectible
# -----------------------------------------------------------------------------
func _setup_collectible(cfg: Dictionary) -> void:
	_has_collectible = true
	_collectible_item_name = str(cfg.get("item_name", "Coin"))
	_collectible_score_value = int(cfg.get("score_value", 10))
	_collectible_magnet_radius = float(cfg.get("magnet_radius", 3.5))

	parent.add_to_group("collectible")

# -----------------------------------------------------------------------------
# 5. hazard_emitter
# -----------------------------------------------------------------------------
func _setup_hazard_emitter(cfg: Dictionary) -> void:
	_has_hazard_emitter = true
	_hazard_cycle_sec = float(cfg.get("cycle_sec", 4.0))
	_hazard_radius = float(cfg.get("radius", 3.0))
	_hazard_damage_per_sec = float(cfg.get("damage_per_sec", 25.0))
	var raw_col: Variant = cfg.get("telegraph_color", "#ff3300")
	_hazard_telegraph_color = _parse_color(raw_col, Color(1.0, 0.2, 0.0))

	parent.add_to_group("hazard_emitter")

	# Create telegraph TorusMesh child
	_hazard_ring_mesh = MeshInstance3D.new()
	_hazard_ring_mesh.name = "HazardTelegraphRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 1.0
	_hazard_ring_mesh.mesh = torus

	_hazard_ring_mat = StandardMaterial3D.new()
	_hazard_ring_mat.albedo_color = _hazard_telegraph_color
	_hazard_ring_mat.albedo_color.a = 0.65
	_hazard_ring_mat.emission_enabled = true
	_hazard_ring_mat.emission = _hazard_telegraph_color
	_hazard_ring_mat.emission_energy_multiplier = 2.0
	_hazard_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hazard_ring_mesh.set_surface_override_material(0, _hazard_ring_mat)

	_hazard_ring_mesh.position = Vector3(0.0, 0.05, 0.0)
	_hazard_ring_mesh.scale = Vector3(0.15, 1.0, 0.15)
	add_child(_hazard_ring_mesh)

# -----------------------------------------------------------------------------
# 6. impulse_pad
# -----------------------------------------------------------------------------
func _setup_impulse_pad(cfg: Dictionary) -> void:
	_has_impulse_pad = true
	_impulse_upward_velocity = float(cfg.get("upward_velocity", 0.0))
	_impulse_forward_boost = float(cfg.get("forward_boost", 0.0))
	_impulse_multiplier = float(cfg.get("multiplier", 1.0))

	parent.add_to_group("impulse_pad")

# -----------------------------------------------------------------------------
# 7. dialogue_trigger
# -----------------------------------------------------------------------------
func _setup_dialogue_trigger(cfg: Dictionary) -> void:
	_has_dialogue_trigger = true
	_dialogue_path = str(cfg.get("dialogue_path", ""))
	_dialogue_start_node = str(cfg.get("start_node", ""))
	_dialogue_prompt_label = str(cfg.get("prompt_label", "Interact"))

	parent.add_to_group("dialogue_trigger")
	parent.add_to_group("objective")

	parent.set_meta("dialogue_path", _dialogue_path)
	parent.set_meta("start_node", _dialogue_start_node)
	parent.set_meta("prompt_label", _dialogue_prompt_label)

# -----------------------------------------------------------------------------
# Process Loop
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if parent == null or not is_inside_tree():
		return

	if _has_ambient_motion:
		_process_ambient_motion(delta)

	if _has_combat_unit:
		_process_combat_unit(delta)

	if _has_harvestable:
		_process_harvestable(delta)

	if _has_collectible:
		_process_collectible(delta)

	if _has_hazard_emitter:
		_process_hazard_emitter(delta)

	if _has_impulse_pad:
		_process_impulse_pad(delta)

# -----------------------------------------------------------------------------
# Process Helpers
# -----------------------------------------------------------------------------
func _process_ambient_motion(delta: float) -> void:
	if _ambient_spin_deg_sec != 0.0:
		parent.rotate_y(deg_to_rad(_ambient_spin_deg_sec * delta))

	if _ambient_bob_amp > 0.0:
		_bob_time += delta * _ambient_bob_speed
		parent.position.y = _initial_parent_y + sin(_bob_time) * _ambient_bob_amp

	if _ambient_pulse_emission and not _cached_materials.is_empty():
		_pulse_time += delta * 3.0
		var energy: float = 1.2 + 0.8 * sin(_pulse_time)
		for mat in _cached_materials:
			if is_instance_valid(mat):
				mat.emission_energy_multiplier = energy

	if _ambient_flicker_light and not _cached_lights.is_empty():
		_flicker_time += delta * 9.0
		var fl: float = 0.85 + 0.25 * sin(_flicker_time) * cos(_flicker_time * 1.7)
		for l in _cached_lights:
			if is_instance_valid(l):
				var base_e: float = float(_initial_light_energies.get(l.get_instance_id(), 1.0))
				l.light_energy = base_e * fl

func _process_combat_unit(delta: float) -> void:
	if _combat_role == "player" or _is_defeated:
		return

	var is_boss_controlled := (parent is ModularBossController) or parent.has_node("ModularBossController")
	var target := _find_nearest_combat_target()

	if target != null and is_instance_valid(target):
		var target_pos := target.global_position
		var look_pos := Vector3(target_pos.x, parent.global_position.y, target_pos.z)
		if parent.global_position.distance_squared_to(look_pos) > 0.01:
			parent.look_at(look_pos, Vector3.UP)

		var cur_dist := parent.global_position.distance_to(target_pos)

		# Move toward target if not controlled by ModularBossController
		if not is_boss_controlled and cur_dist > _combat_attack_range:
			var move_dir := (target_pos - parent.global_position).normalized()
			move_dir.y = 0.0
			move_dir = move_dir.normalized()
			if parent is CharacterBody3D:
				var cb := parent as CharacterBody3D
				cb.velocity.x = move_dir.x * _combat_move_speed
				cb.velocity.z = move_dir.z * _combat_move_speed
				cb.move_and_slide()
			else:
				parent.global_position += move_dir * _combat_move_speed * delta

		# Fire glowing energy projectile every 1.8s
		_combat_attack_timer += delta
		if _combat_attack_timer >= 1.8:
			_combat_attack_timer = 0.0
			_fire_energy_projectile(target)

	# If boss, also trigger expanding ground-slam shockwave ring every 3.5s
	if _combat_role == "boss":
		_boss_shockwave_timer += delta
		if _boss_shockwave_timer >= 3.5:
			_boss_shockwave_timer = 0.0
			_trigger_boss_shockwave()

func _find_nearest_combat_target() -> Node3D:
	var best_target: Node3D = null
	var best_dist: float = 28.0
	var my_pos := parent.global_position

	var candidates: Array[Node] = []
	if _combat_role == "boss" or _combat_role == "minion" or _combat_faction == "hostile":
		candidates.append_array(get_tree().get_nodes_in_group("player"))
		candidates.append_array(get_tree().get_nodes_in_group("ally_unit"))
	else:
		candidates.append_array(get_tree().get_nodes_in_group("hostile_unit"))
		candidates.append_array(get_tree().get_nodes_in_group("boss_target"))

	for c in candidates:
		if c is Node3D and c != parent and is_instance_valid(c):
			var n := c as Node3D
			if n.has_meta("current_hp") and float(n.get_meta("current_hp")) <= 0.0:
				continue
			var d := my_pos.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best_target = n

	return best_target

func _fire_energy_projectile(target: Node3D) -> void:
	var proj := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	proj.mesh = sm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _combat_projectile_color
	mat.emission_enabled = true
	mat.emission = _combat_projectile_color
	mat.emission_energy_multiplier = 4.0
	proj.set_surface_override_material(0, mat)

	var start_pos := parent.global_position + Vector3(0.0, 1.2, 0.0)
	var target_pos := target.global_position + Vector3(0.0, 1.0, 0.0)
	proj.global_position = start_pos

	var container: Node = get_tree().current_scene
	if container == null:
		container = parent.get_parent()
	if container == null:
		return
	container.add_child(proj)

	var dist := start_pos.distance_to(target_pos)
	var flight_time := clampf(dist / 22.0, 0.1, 1.2)
	var dmg := _combat_attack_damage

	var tw := proj.create_tween()
	tw.tween_property(proj, "global_position", target_pos, flight_time)
	tw.tween_callback(func():
		if is_instance_valid(target):
			damage_entity(target, dmg)
		if is_instance_valid(proj):
			proj.queue_free()
	)

func _trigger_boss_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.set_surface_override_material(0, mat)

	ring.global_position = parent.global_position + Vector3(0.0, 0.1, 0.0)
	ring.scale = Vector3(0.2, 1.0, 0.2)

	var container: Node = get_tree().current_scene
	if container == null:
		container = parent.get_parent()
	if container == null:
		return
	container.add_child(ring)

	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(8.0, 1.0, 8.0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.75)
	var center := parent.global_position
	var dmg := _combat_attack_damage * 0.6
	tw.tween_callback(func():
		var candidates: Array[Node] = []
		candidates.append_array(get_tree().get_nodes_in_group("player"))
		candidates.append_array(get_tree().get_nodes_in_group("ally_unit"))
		for c in candidates:
			if c is Node3D and is_instance_valid(c):
				var n := c as Node3D
				if center.distance_to(n.global_position) <= 8.0:
					damage_entity(n, dmg)
		if is_instance_valid(ring):
			ring.queue_free()
	)

func _process_harvestable(delta: float) -> void:
	if _harvest_charges_remaining <= 0:
		_harvest_respawn_timer += delta
		if _harvest_respawn_timer >= _harvest_respawn_sec:
			_harvest_charges_remaining = _harvest_max_charges
			parent.set_meta("charges_remaining", _harvest_max_charges)
			parent.scale = _base_scale
			_spawn_floating_label("RESTOCKED!", Color(0.2, 1.0, 0.5), Vector3(0.0, 2.0, 0.0))
		return

	# Check distance to player or ally
	var harvest_nearby := false
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("ally_unit"))
	for c in candidates:
		if c is Node3D and is_instance_valid(c):
			var n := c as Node3D
			if parent.global_position.distance_to(n.global_position) <= 3.5:
				harvest_nearby = true
				break

	if harvest_nearby:
		_harvest_timer += delta
		if _harvest_timer >= _harvest_tick_interval:
			_harvest_timer = 0.0
			trigger_harvest_tick()
	else:
		_harvest_timer = 0.0

func _process_collectible(delta: float) -> void:
	if _collectible_is_collected:
		_collectible_respawn_timer += delta
		if _collectible_respawn_timer >= 4.0:
			_collectible_is_collected = false
			parent.global_position = _initial_global_pos
			parent.visible = true
		return

	# Check distance to player
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Node3D and is_instance_valid(p):
			var pn := p as Node3D
			var dist := parent.global_position.distance_to(pn.global_position)
			if dist <= 1.2:
				# Collected!
				_collectible_is_collected = true
				parent.visible = false
				_collectible_respawn_timer = 0.0

				var scene := get_tree().current_scene
				var mult: float = 1.0
				if scene != null:
					mult = float(scene.get_meta("score_multiplier", 1.0))
					var added := int(float(_collectible_score_value) * mult)
					var cur_score: int = int(scene.get_meta("score", 0)) + added
					scene.set_meta("score", cur_score)
					_spawn_floating_label("+%d %s" % [added, _collectible_item_name], Color(1.0, 0.85, 0.1), Vector3(0.0, 1.8, 0.0))
				break
			elif dist <= _collectible_magnet_radius:
				var pull_dir := (pn.global_position - parent.global_position).normalized()
				parent.global_position += pull_dir * 7.5 * delta
				break

func _process_hazard_emitter(delta: float) -> void:
	_hazard_cycle_time += delta
	var progress := fmod(_hazard_cycle_time, _hazard_cycle_sec) / _hazard_cycle_sec
	var current_r: float = lerpf(0.15, _hazard_radius, progress)

	if _hazard_ring_mesh != null and is_instance_valid(_hazard_ring_mesh):
		_hazard_ring_mesh.scale = Vector3(current_r, 1.0, current_r)
		if _hazard_ring_mat != null and is_instance_valid(_hazard_ring_mat):
			var pulse: float = 1.0 + (3.0 * progress if progress > 0.8 else 0.5)
			_hazard_ring_mat.emission_energy_multiplier = pulse

	# Peak expansion applies damage
	if progress >= 0.85:
		var dmg := _hazard_damage_per_sec * delta
		var candidates: Array[Node] = []
		candidates.append_array(get_tree().get_nodes_in_group("player"))
		candidates.append_array(get_tree().get_nodes_in_group("combat_unit"))
		var center := parent.global_position
		for c in candidates:
			if c is Node3D and c != parent and is_instance_valid(c):
				var n := c as Node3D
				if center.distance_to(n.global_position) <= _hazard_radius:
					damage_entity(n, dmg)

func _process_impulse_pad(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var bodies: Array[Node] = []
	bodies.append_array(get_tree().get_nodes_in_group("player"))
	var char_bodies := get_tree().current_scene.find_children("", "CharacterBody3D", true, false) if get_tree().current_scene != null else []
	for cb in char_bodies:
		if not bodies.has(cb):
			bodies.append(cb)

	var pad_pos := parent.global_position

	for b in bodies:
		if b is CharacterBody3D and is_instance_valid(b):
			var body := b as CharacterBody3D
			if pad_pos.distance_to(body.global_position) < 1.8:
				var body_id := body.get_instance_id()
				var last_time: int = int(_pad_cooldowns.get(body_id, 0))
				if now - last_time < 800:
					continue
				_pad_cooldowns[body_id] = now

				if _impulse_upward_velocity > 0.0:
					body.velocity.y = _impulse_upward_velocity
					_spawn_floating_label("JUMP BOOST!", Color(0.2, 1.0, 0.4), Vector3(0.0, 2.0, 0.0))

				if _impulse_forward_boost > 0.0:
					var fwd := -parent.global_transform.basis.z.normalized()
					if fwd.length_squared() < 0.1:
						fwd = -body.global_transform.basis.z.normalized()
					body.velocity.x += fwd.x * _impulse_forward_boost
					body.velocity.z += fwd.z * _impulse_forward_boost
					body.set_meta("speed_boost_until", now + 2500)
					_spawn_floating_label("SPEED BOOST!", Color(1.0, 0.85, 0.1), Vector3(0.0, 2.0, 0.0))

				if _impulse_multiplier > 1.0:
					var scene := get_tree().current_scene
					if scene != null:
						var cur_mult: float = float(scene.get_meta("score_multiplier", 1.0))
						var new_mult: float = minf(16.0, cur_mult * _impulse_multiplier)
						scene.set_meta("score_multiplier", new_mult)
						_spawn_floating_label("SCORE x%d!" % int(new_mult), Color(1.0, 0.2, 0.8), Vector3(0.0, 2.0, 0.0))

# -----------------------------------------------------------------------------
# Static Helpers
# -----------------------------------------------------------------------------
static func damage_entity(target: Node, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_damage"):
		target.call("apply_damage", amount)
	elif target.has_node("ModularEntityTraits"):
		var t: Variant = target.get_node("ModularEntityTraits")
		if t != null and t.has_method("apply_damage"):
			t.call("apply_damage", amount)
	elif target.has_meta("traits_controller"):
		var tc: Variant = target.get_meta("traits_controller")
		if tc != null and tc.has_method("apply_damage"):
			tc.call("apply_damage", amount)
	elif target.has_method("take_damage"):
		target.call("take_damage", amount)

static func ensure_scene_traits(zone_root: Node) -> void:
	if zone_root == null:
		return
	_scan_and_attach_traits_recursive(zone_root)

static func _scan_and_attach_traits_recursive(node: Node) -> void:
	if node is Node3D and node.name != "ModularEntityTraits":
		var has_traits_child: bool = node.has_node("ModularEntityTraits")
		if has_traits_child:
			return

		var traits_to_attach: Array = []
		if node.has_meta("entity_traits"):
			var raw_traits: Variant = node.get_meta("entity_traits")
			if raw_traits is Array:
				traits_to_attach = (raw_traits as Array).duplicate(true)

		if traits_to_attach.is_empty():
			var n_name := node.name.to_lower()
			if node.name == "PlayerCharacter" or node.is_in_group("player"):
				traits_to_attach.append({
					"type": "combat_unit",
					"role": "player",
					"faction": "player",
					"display_name": "Player Hero",
					"max_hp": 100.0,
					"move_speed": 6.0
				})
			elif node.is_in_group("boss_target") or n_name.contains("golem"):
				traits_to_attach.append({
					"type": "combat_unit",
					"role": "boss",
					"faction": "hostile",
					"display_name": "Golem Brute",
					"max_hp": 2400.0,
					"attack_damage": 45.0,
					"attack_range": 4.0,
					"move_speed": 3.2
				})
			elif node.is_in_group("tactical_unit") or n_name.contains("unit_knight"):
				traits_to_attach.append({
					"type": "combat_unit",
					"role": "ally",
					"faction": "blue_army",
					"display_name": "Tactical Knight",
					"max_hp": 120.0,
					"attack_damage": 25.0,
					"attack_range": 2.0,
					"move_speed": 4.0
				})
			elif node.is_in_group("multiplier_gate") or n_name.contains("multiplier_gate"):
				traits_to_attach.append({
					"type": "impulse_pad",
					"multiplier": 2.0
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"pulse_emission": true
				})
			elif n_name.contains("shrine"):
				traits_to_attach.append({
					"type": "dialogue_trigger",
					"prompt_label": "Channel Ancient Altar",
					"dialogue_path": "res://dialogues/prison_break.dialogue",
					"start_node": "altar_seal"
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"bob_amp": 0.08,
					"bob_speed": 1.5,
					"pulse_emission": true
				})
			elif node.is_in_group("harvestable") or n_name.contains("tree") or n_name.contains("rock"):
				var res_name := "Oak Log" if n_name.contains("tree") else "Iron Ore"
				traits_to_attach.append({
					"type": "harvestable",
					"resource_name": res_name,
					"max_charges": 5,
					"tick_interval_sec": 0.6,
					"respawn_sec": 8.0
				})
			elif node.is_in_group("coin_token") or n_name.contains("coin"):
				traits_to_attach.append({
					"type": "collectible",
					"item_name": "Gold Coin",
					"score_value": 10,
					"magnet_radius": 3.5
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"spin_deg_sec": 90.0,
					"bob_amp": 0.15,
					"bob_speed": 3.0
				})
			elif node.is_in_group("gem_token") or n_name.contains("gem"):
				traits_to_attach.append({
					"type": "collectible",
					"item_name": "Ruby Gem",
					"score_value": 50,
					"magnet_radius": 4.0
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"spin_deg_sec": 60.0,
					"bob_amp": 0.2,
					"bob_speed": 2.5,
					"pulse_emission": true
				})
			elif node.is_in_group("jump_pad") or n_name.contains("jump_pad"):
				traits_to_attach.append({
					"type": "impulse_pad",
					"upward_velocity": 12.0,
					"forward_boost": 4.0
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"pulse_emission": true
				})
			elif node.is_in_group("boost_pad") or n_name.contains("boost_pad"):
				traits_to_attach.append({
					"type": "impulse_pad",
					"upward_velocity": 0.0,
					"forward_boost": 18.0
				})
				traits_to_attach.append({
					"type": "ambient_motion",
					"pulse_emission": true
				})
			elif node.is_in_group("hazard") or n_name.contains("hazard_vent") or n_name.contains("lava_vent"):
				traits_to_attach.append({
					"type": "hazard_emitter",
					"cycle_sec": 4.0,
					"radius": 3.0,
					"damage_per_sec": 25.0,
					"telegraph_color": "#ff3300"
				})

		if not traits_to_attach.is_empty():
			var trait_comp: Node3D = (load("res://library/modular/ModularEntityTraits.gd") as GDScript).new() as Node3D
			trait_comp.name = "ModularEntityTraits"
			trait_comp.traits_config = traits_to_attach
			node.add_child(trait_comp)
			node.set_meta("entity_traits", traits_to_attach)
			return

	for child in node.get_children():
		_scan_and_attach_traits_recursive(child)

# -----------------------------------------------------------------------------
# Internal Node & Utility Helpers
# -----------------------------------------------------------------------------
func _spawn_floating_label(text: String, color: Color, local_offset: Vector3 = Vector3(0.0, 1.8, 0.0)) -> void:
	if not is_inside_tree() or parent == null:
		return

	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = color
	lbl.font_size = 36
	lbl.outline_size = 8
	lbl.outline_modulate = Color.BLACK
	var container: Node = get_tree().current_scene
	if container == null:
		container = parent.get_parent()
	if container == null:
		return
	container.add_child(lbl)
	lbl.global_position = parent.global_position + local_offset

	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.2, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(lbl.queue_free)

func _find_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node != _hazard_ring_mesh:
		result.append(node as MeshInstance3D)
	for c in node.get_children():
		if c != self:
			result.append_array(_find_all_meshes(c))
	return result

func _find_all_omni_lights(node: Node) -> Array[OmniLight3D]:
	var result: Array[OmniLight3D] = []
	if node is OmniLight3D:
		result.append(node as OmniLight3D)
	for c in node.get_children():
		result.append_array(_find_all_omni_lights(c))
	return result

func _parse_color(val: Variant, default_color: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		var s := str(val).strip_edges()
		if not s.is_empty():
			if not s.begins_with("#") and (s.length() == 6 or s.length() == 8):
				s = "#" + s
			return Color.from_string(s, default_color)
	return default_color
