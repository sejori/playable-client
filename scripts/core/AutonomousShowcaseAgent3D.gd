class_name AutonomousShowcaseAgent3D
extends Node3D

const ModularEntityTraitsScript := preload("res://library/modular/ModularEntityTraits.gd")
## AutonomousShowcaseAgent3D.gd
## Goal-Driven Autonomous Playtester & Camera Director (Phase 5).
## Universally tests and dramatizes any prompted cartridge scene during --showcase-demo / --write-movie.

var protagonist: CharacterBody3D = null

# Camera director state
var _smooth_focus: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.0

# AI Loop Timers
var _attack_timer: float = 0.0
var _harvest_timer: float = 0.0
var _turn_timer: float = 0.0
var _voxel_timer: float = 0.0

# Harvester state
var _current_harvest_target: Node3D = null
var _harvest_ticks_done: int = 0

# Runner state
var _current_runner_target: Node3D = null
var _recent_runner_ids: Dictionary = {} # instance_id -> ticks_msec

# Tactical unit state
var _tactical_clash_cooldown: float = 0.0

func _ready() -> void:
	# Priority 100 ensures camera director runs after CameraHost3D and other controllers
	process_priority = 100
	process_physics_priority = 100

	# Disable any CameraHost3D from overriding showcase camera
	_disable_competing_camera_hosts()

	# Resolve or instantiate the hero protagonist
	_resolve_protagonist()

func _disable_competing_camera_hosts() -> void:
	var hosts := get_tree().get_nodes_in_group("camera_hosts")
	for h in hosts:
		if h is Node:
			(h as Node).set_process(false)

	var sc := get_tree().current_scene
	if sc != null:
		var found_hosts := sc.find_children("", "CameraHost3D", true, false)
		for fh in found_hosts:
			fh.set_process(false)

# -----------------------------------------------------------------------------
# Protagonist Resolution
# -----------------------------------------------------------------------------
func _resolve_protagonist() -> void:
	# 1. Look for existing PlayerCharacter or group "player"
	var player_group := get_tree().get_nodes_in_group("player")
	for node in player_group:
		if node is CharacterBody3D and is_instance_valid(node):
			protagonist = node as CharacterBody3D
			break

	var sc := get_tree().current_scene
	if protagonist == null and sc != null:
		var pc := sc.find_child("PlayerCharacter", true, false)
		if pc is CharacterBody3D:
			protagonist = pc as CharacterBody3D

	if protagonist == null and sc != null:
		var tactical_units := get_tree().get_nodes_in_group("tactical_unit")
		for tu in tactical_units:
			if tu is CharacterBody3D:
				var tu_name := tu.name.to_lower()
				if tu_name.contains("blue") or tu_name.contains("player"):
					protagonist = tu as CharacterBody3D
					break
		if protagonist == null and not tactical_units.is_empty():
			for tu in tactical_units:
				if tu is CharacterBody3D:
					protagonist = tu as CharacterBody3D
					break

	if protagonist == null and sc != null:
		var all_bodies := sc.find_children("", "CharacterBody3D", true, false)
		for b in all_bodies:
			if b is CharacterBody3D:
				protagonist = b as CharacterBody3D
				break

	# 2. If none exists, create a visible hero avatar CharacterBody3D at Vector3(0, 1.0, 6.0)
	if protagonist == null:
		protagonist = CharacterBody3D.new()
		protagonist.name = "PlayerCharacter"
		protagonist.position = Vector3(0.0, 1.0, 6.0)

		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.8
		col.shape = cap
		col.position = Vector3(0.0, 0.9, 0.0)
		protagonist.add_child(col)

		if sc != null:
			sc.add_child(protagonist)
		else:
			add_child(protagonist)

	# 3. Ensure in group "player"
	if not protagonist.is_in_group("player"):
		protagonist.add_to_group("player")

	# 4. Check ground level (start at y = 1.0 if spawned at y > 4.0)
	if protagonist.position.y > 4.0:
		protagonist.position.y = 1.0

	# 5. Disable default input movers on protagonist so Showcase AI drives steering
	var movers := protagonist.find_children("", "MoverComponentBase", true, false)
	for m in movers:
		if "is_enabled" in m:
			m.set("is_enabled", false)

	# 6. Ensure visible 3D mesh (if first-person or empty, attach sleek cyan/steel armor capsule + visor)
	_ensure_visible_hero_mesh()

func _ensure_visible_hero_mesh() -> void:
	if protagonist == null:
		return

	var existing_meshes := protagonist.find_children("", "MeshInstance3D", true, false)
	var has_visible_body := false
	for m in existing_meshes:
		if m is MeshInstance3D and (m as MeshInstance3D).visible and (m as MeshInstance3D).mesh != null:
			has_visible_body = true
			break

	if not has_visible_body:
		var avatar_root := Node3D.new()
		avatar_root.name = "ShowcaseHeroAvatar"

		# Torso / Armor Capsule
		var body_mesh := MeshInstance3D.new()
		body_mesh.name = "ArmorCapsule"
		var cap := CapsuleMesh.new()
		cap.radius = 0.45
		cap.height = 1.8
		body_mesh.mesh = cap

		var steel_mat := StandardMaterial3D.new()
		steel_mat.albedo_color = Color(0.12, 0.20, 0.32) # Sleek steel blue
		steel_mat.metallic = 0.85
		steel_mat.roughness = 0.30
		steel_mat.emission_enabled = true
		steel_mat.emission = Color(0.10, 0.65, 0.95) # Glowing cyan armor trim
		steel_mat.emission_energy_multiplier = 1.8
		body_mesh.set_surface_override_material(0, steel_mat)
		body_mesh.position = Vector3(0.0, 0.9, 0.0)
		avatar_root.add_child(body_mesh)

		# Visor Box
		var visor_mesh := MeshInstance3D.new()
		visor_mesh.name = "Visor"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.16, 0.26)
		visor_mesh.mesh = bm

		var visor_mat := StandardMaterial3D.new()
		visor_mat.albedo_color = Color(0.0, 0.90, 1.0)
		visor_mat.emission_enabled = true
		visor_mat.emission = Color(0.0, 0.90, 1.0)
		visor_mat.emission_energy_multiplier = 4.0
		visor_mesh.set_surface_override_material(0, visor_mat)
		visor_mesh.position = Vector3(0.0, 1.45, -0.32)
		avatar_root.add_child(visor_mesh)

		protagonist.add_child(avatar_root)

# -----------------------------------------------------------------------------
# Utility AI Process Loop
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if protagonist == null or not is_instance_valid(protagonist):
		_resolve_protagonist()
		if protagonist == null:
			return

	# Substrate-specific systems (run concurrently if active)
	if _is_strategy_scene():
		_step_tactical_hex_system(delta)
		return

	_step_voxel_builder_system(delta)

	# Steer protagonist according to current priority goal
	var hostile := _find_nearest_active_hostile()
	var harvestable := _find_nearest_harvestable()
	var collectible := _find_nearest_runner_target()

	if hostile != null:
		# Behavior 3: Combat & Boss Skirmisher
		_physics_combat_skirmisher(delta, hostile)
	elif harvestable != null and not _is_strategy_scene():
		# Behavior 2: Resource Harvester
		_physics_resource_harvester(delta, harvestable)
	elif collectible != null:
		# Behavior 1: Collectible & Impulse Pad Runner
		_physics_runner(delta, collectible)
	else:
		# Default traversal / gentle wander
		_physics_idle_patrol(delta)

# -----------------------------------------------------------------------------
# 1. Collectible & Impulse Pad Runner
# -----------------------------------------------------------------------------
func _physics_runner(delta: float, target: Node3D) -> void:
	var now := Time.get_ticks_msec()
	var is_boosted := protagonist.has_meta("speed_boost_until") and now < int(protagonist.get_meta("speed_boost_until"))
	var speed: float = 16.0 if is_boosted else 10.5

	var target_pos := target.global_position
	var to_target := (target_pos - protagonist.global_position)
	to_target.y = 0.0

	var dist := to_target.length()
	if dist > 0.4:
		var dir := to_target.normalized()
		var face_pos := Vector3(target_pos.x, protagonist.global_position.y, target_pos.z)
		if protagonist.global_position.distance_squared_to(face_pos) > 0.01:
			protagonist.look_at(face_pos, Vector3.UP)
		protagonist.velocity.x = dir.x * speed
		protagonist.velocity.z = dir.z * speed
	else:
		_recent_runner_ids[target.get_instance_id()] = now
		protagonist.velocity.x = 0.0
		protagonist.velocity.z = 0.0

	protagonist.velocity.y -= 19.6 * delta
	protagonist.move_and_slide()

func _find_nearest_runner_target() -> Node3D:
	var now := Time.get_ticks_msec()
	var best_node: Node3D = null
	var best_dist: float = 999.0
	var my_pos := protagonist.global_position

	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("collectible"))
	candidates.append_array(get_tree().get_nodes_in_group("impulse_pad"))
	candidates.append_array(get_tree().get_nodes_in_group("multiplier_gate"))

	for c in candidates:
		if c is Node3D and is_instance_valid(c):
			var n := c as Node3D
			if not n.visible:
				continue
			var inst_id := n.get_instance_id()
			var last_visited: int = int(_recent_runner_ids.get(inst_id, 0))
			if now - last_visited < 3000:
				continue
			var d := my_pos.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best_node = n

	return best_node

# -----------------------------------------------------------------------------
# 2. Resource Harvester
# -----------------------------------------------------------------------------
func _physics_resource_harvester(delta: float, target: Node3D) -> void:
	var target_pos := target.global_position
	var to_target := (target_pos - protagonist.global_position)
	to_target.y = 0.0

	var dist := to_target.length()
	var face_pos := Vector3(target_pos.x, protagonist.global_position.y, target_pos.z)
	if protagonist.global_position.distance_squared_to(face_pos) > 0.01:
		protagonist.look_at(face_pos, Vector3.UP)

	if dist > 2.4:
		var dir := to_target.normalized()
		protagonist.velocity.x = dir.x * 6.5
		protagonist.velocity.z = dir.z * 6.5
	else:
		protagonist.velocity.x = 0.0
		protagonist.velocity.z = 0.0

		_harvest_timer += delta
		if _harvest_timer >= 0.55:
			_harvest_timer = 0.0
			_harvest_ticks_done += 1
			_spawn_harvest_swing_effect(target)

			# Trigger harvesting tick on target
			if target.has_node("ModularEntityTraits"):
				var traits_comp: Variant = target.get_node("ModularEntityTraits")
				if traits_comp != null and traits_comp.has_method("trigger_harvest_tick"):
					traits_comp.call("trigger_harvest_tick")
			elif target.has_meta("traits_controller"):
				var tc: Variant = target.get_meta("traits_controller")
				if tc != null and tc.has_method("trigger_harvest_tick"):
					tc.call("trigger_harvest_tick")
			else:
				_manual_harvest_fallback(target)

			if _harvest_ticks_done >= 3:
				_harvest_ticks_done = 0
				_current_harvest_target = null

	protagonist.velocity.y -= 19.6 * delta
	protagonist.move_and_slide()

func _find_nearest_harvestable() -> Node3D:
	if _current_harvest_target != null and is_instance_valid(_current_harvest_target):
		if _current_harvest_target.has_meta("charges_remaining") and int(_current_harvest_target.get_meta("charges_remaining")) <= 0:
			_current_harvest_target = null
		else:
			return _current_harvest_target

	var nodes := get_tree().get_nodes_in_group("harvestable")
	var best_node: Node3D = null
	var best_dist: float = 999.0
	var my_pos := protagonist.global_position

	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			var node3d := n as Node3D
			if node3d.has_meta("charges_remaining") and int(node3d.get_meta("charges_remaining")) <= 0:
				continue
			var d := my_pos.distance_to(node3d.global_position)
			if d < best_dist:
				best_dist = d
				best_node = node3d

	_current_harvest_target = best_node
	return _current_harvest_target

func _spawn_harvest_swing_effect(target: Node3D) -> void:
	var swing := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.95
	torus.ring_segments = 6
	torus.radial_segments = 16
	swing.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 1.0, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 1.0, 0.65)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swing.set_surface_override_material(0, mat)

	var mid_pos := protagonist.global_position.lerp(target.global_position, 0.55) + Vector3(0.0, 1.1, 0.0)
	swing.global_position = mid_pos
	swing.scale = Vector3(0.2, 0.2, 0.2)

	var sc := get_tree().current_scene
	var container: Node = sc if sc != null else self
	container.add_child(swing)

	var tw := swing.create_tween()
	tw.tween_property(swing, "scale", Vector3(1.8, 0.3, 1.8), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(swing.queue_free)

func _manual_harvest_fallback(target: Node3D) -> void:
	var res_name := str(target.get_meta("resource_name", "Resource"))
	var charges: int = int(target.get_meta("charges_remaining", 5)) - 1
	target.set_meta("charges_remaining", charges)

	var sc := get_tree().current_scene
	if sc != null:
		var tot: int = int(sc.get_meta("harvested_total", 0)) + 1
		sc.set_meta("harvested_total", tot)
		var key := "harvested_" + res_name
		var item_tot: int = int(sc.get_meta(key, 0)) + 1
		sc.set_meta(key, item_tot)

	_spawn_floating_label("+1 %s" % res_name, Color(0.2, 0.9, 0.4), target.global_position + Vector3(0.0, 2.2, 0.0))

# -----------------------------------------------------------------------------
# 3. Combat & Boss Skirmisher
# -----------------------------------------------------------------------------
func _physics_combat_skirmisher(delta: float, hostile: Node3D) -> void:
	var h_pos := hostile.global_position
	var face_pos := Vector3(h_pos.x, protagonist.global_position.y, h_pos.z)
	if protagonist.global_position.distance_squared_to(face_pos) > 0.01:
		protagonist.look_at(face_pos, Vector3.UP)

	var cur_dist := protagonist.global_position.distance_to(h_pos)
	var move_vec := Vector3.ZERO

	# Check for unvisited jump_pad, boost_pad, or collectible pickup within 8.5m
	var now := Time.get_ticks_msec()
	var nearby_pad: Node3D = null
	var pad_dist: float = 999.0

	var interactive_candidates: Array[Node] = []
	interactive_candidates.append_array(get_tree().get_nodes_in_group("jump_pad"))
	interactive_candidates.append_array(get_tree().get_nodes_in_group("boost_pad"))
	interactive_candidates.append_array(get_tree().get_nodes_in_group("impulse_pad"))
	interactive_candidates.append_array(get_tree().get_nodes_in_group("collectible"))

	for c in interactive_candidates:
		if c is Node3D and is_instance_valid(c):
			var n := c as Node3D
			if not n.visible:
				continue
			var inst_id := n.get_instance_id()
			var last_visited: int = int(_recent_runner_ids.get(inst_id, 0))
			if now - last_visited < 3500:
				continue
			var d := protagonist.global_position.distance_to(n.global_position)
			if d <= 8.5 and d < pad_dist:
				pad_dist = d
				nearby_pad = n

	if nearby_pad != null:
		var to_pad := (nearby_pad.global_position - protagonist.global_position).normalized()
		to_pad.y = 0.0
		move_vec = to_pad
		if pad_dist < 1.4:
			_recent_runner_ids[nearby_pad.get_instance_id()] = now
	else:
		# Skirmish ring between 6.0m and 9.0m
		if cur_dist > 9.0:
			move_vec += (h_pos - protagonist.global_position).normalized()
		elif cur_dist < 6.0:
			move_vec -= (h_pos - protagonist.global_position).normalized()
		else:
			# Lateral strafe orbit
			var fwd := (h_pos - protagonist.global_position).normalized()
			var strafe := Vector3(-fwd.z, 0.0, fwd.x)
			move_vec += strafe

	# Repulsion dodge away from any hazard_emitter within 3.5m
	var hazards := get_tree().get_nodes_in_group("hazard_emitter")
	for haz in hazards:
		if haz is Node3D and is_instance_valid(haz):
			var hz_pos := (haz as Node3D).global_position
			var hz_dist := protagonist.global_position.distance_to(hz_pos)
			if hz_dist < 3.5:
				var repulse := (protagonist.global_position - hz_pos).normalized()
				repulse.y = 0.0
				move_vec += repulse * 2.5

	move_vec.y = 0.0
	if move_vec.length_squared() > 0.01:
		move_vec = move_vec.normalized()
		protagonist.velocity.x = move_vec.x * 7.5
		protagonist.velocity.z = move_vec.z * 7.5
	else:
		protagonist.velocity.x = 0.0
		protagonist.velocity.z = 0.0

	protagonist.velocity.y -= 19.6 * delta
	protagonist.move_and_slide()

	# Projectile firing every 0.45s
	_attack_timer += delta
	if _attack_timer >= 0.45:
		_attack_timer = 0.0
		_fire_combat_projectile(hostile)

func _find_nearest_active_hostile() -> Node3D:
	var best_hostile: Node3D = null
	var best_dist: float = 35.0
	var my_pos := protagonist.global_position

	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("boss_target"))
	candidates.append_array(get_tree().get_nodes_in_group("hostile_unit"))

	var combat_units := get_tree().get_nodes_in_group("combat_unit")
	for cu in combat_units:
		if cu is Node3D and not candidates.has(cu):
			if cu.has_meta("role") and (str(cu.get_meta("role")) == "boss" or str(cu.get_meta("role")) == "minion"):
				candidates.append(cu)
			elif cu.has_meta("faction") and str(cu.get_meta("faction")) == "hostile":
				candidates.append(cu)

	for c in candidates:
		if c is Node3D and is_instance_valid(c) and c != protagonist:
			var n := c as Node3D
			if n.has_meta("current_hp") and float(n.get_meta("current_hp")) <= 0.0:
				continue
			var d := my_pos.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best_hostile = n

	return best_hostile

func _fire_combat_projectile(target: Node3D) -> void:
	var proj := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	proj.mesh = sm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.90, 1.0) # Bright cyan
	mat.emission_enabled = true
	mat.emission = Color(0.20, 0.90, 1.0)
	mat.emission_energy_multiplier = 4.0
	proj.set_surface_override_material(0, mat)

	var start_pos := protagonist.global_position + Vector3(0.0, 1.2, 0.0)
	var target_pos := target.global_position + Vector3(0.0, 1.0, 0.0)
	var sc := get_tree().current_scene
	var container: Node = sc if sc != null else self
	container.add_child(proj)
	proj.global_position = start_pos

	var dist := start_pos.distance_to(target_pos)
	var flight_time := clampf(dist / 28.0, 0.1, 0.45)

	var tw := proj.create_tween()
	tw.tween_property(proj, "global_position", target_pos, flight_time)
	tw.tween_callback(func():
		if is_instance_valid(target):
			ModularEntityTraitsScript.damage_entity(target, 75.0)
		if is_instance_valid(proj):
			proj.queue_free()
	)

# -----------------------------------------------------------------------------
# 4. Tactical Hex Commander
# -----------------------------------------------------------------------------
func _step_tactical_hex_system(delta: float) -> void:
	if not _is_strategy_scene():
		return

	_turn_timer += delta
	if _turn_timer < 0.85:
		return
	_turn_timer = 0.0

	var sc := get_tree().current_scene
	var tm: TurnManager = null
	var tms := get_tree().get_nodes_in_group("turn_manager")
	if not tms.is_empty() and tms[0] is TurnManager:
		tm = tms[0] as TurnManager
	elif sc != null:
		var found_tms := sc.find_children("", "TurnManager", true, false)
		if not found_tms.is_empty():
			tm = found_tms[0] as TurnManager

	if tm != null:
		var did_consume := tm.consume_ap(1)
		if not did_consume or tm.current_ap <= 0:
			tm.end_current_turn()
			_spawn_floating_label("ROUND ADVANCED", Color(0.3, 0.85, 1.0), Vector3(0.0, 3.2, 0.0))
		else:
			_spawn_floating_label("TACTICAL COMMAND", Color(1.0, 0.85, 0.2), Vector3(0.0, 3.2, 0.0))

	# Advance opposing tactical units toward each other across the hex board
	_advance_tactical_knights()

func _advance_tactical_knights() -> void:
	var units := get_tree().get_nodes_in_group("tactical_unit")
	if units.is_empty():
		units = get_tree().get_nodes_in_group("combat_unit")

	var blue_knights: Array[Node3D] = []
	var red_knights: Array[Node3D] = []

	for u in units:
		if u is Node3D and is_instance_valid(u):
			var n := u as Node3D
			if n.has_meta("current_hp") and float(n.get_meta("current_hp")) <= 0.0:
				continue
			var faction: String = str(n.get_meta("faction", "")).to_lower()
			var uname: String = n.name.to_lower()
			if faction == "blue_army" or uname.contains("blue") or faction == "player":
				blue_knights.append(n)
			elif faction == "hostile" or uname.contains("crimson") or uname.contains("red"):
				red_knights.append(n)

	if blue_knights.is_empty() or red_knights.is_empty():
		return

	# Pair the closest blue and red knight
	var closest_blue: Node3D = null
	var closest_red: Node3D = null
	var min_dist: float = 999.0

	for bk in blue_knights:
		for rk in red_knights:
			var d := bk.global_position.distance_to(rk.global_position)
			if d < min_dist:
				min_dist = d
				closest_blue = bk
				closest_red = rk

	if closest_blue != null and closest_red != null:
		if min_dist <= 3.2:
			# Combat clash!
			ModularEntityTraitsScript.damage_entity(closest_red, 40.0)
			_spawn_floating_label("TACTICAL STRIKE -40", Color(1.0, 0.3, 0.2), closest_red.global_position + Vector3(0.0, 2.2, 0.0))
			_spawn_tactical_bolt(closest_blue.global_position + Vector3(0.0, 1.0, 0.0), closest_red.global_position + Vector3(0.0, 1.0, 0.0), Color(0.1, 0.8, 1.0))
			_spawn_tactical_bolt(closest_red.global_position + Vector3(0.0, 1.0, 0.0), closest_blue.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.2, 0.1))
		else:
			var step_dir := (closest_red.global_position - closest_blue.global_position).normalized()
			step_dir.y = 0.0
			var next_b := closest_blue.global_position + step_dir * 1.2
			var next_r := closest_red.global_position - step_dir * 1.2

			var tw_b := closest_blue.create_tween()
			tw_b.tween_property(closest_blue, "global_position", next_b, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			var tw_r := closest_red.create_tween()
			tw_r.tween_property(closest_red, "global_position", next_r, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			closest_blue.look_at(Vector3(closest_red.global_position.x, closest_blue.global_position.y, closest_red.global_position.z), Vector3.UP)
			closest_red.look_at(Vector3(closest_blue.global_position.x, closest_red.global_position.y, closest_blue.global_position.z), Vector3.UP)

			_spawn_tactical_bolt(next_b + Vector3(0.0, 1.0, 0.0), next_r + Vector3(0.0, 1.0, 0.0), Color(0.2, 0.7, 1.0))

# -----------------------------------------------------------------------------
# 5. Voxel Builder & Miner
# -----------------------------------------------------------------------------
func _step_voxel_builder_system(delta: float) -> void:
	if not _is_voxel_scene():
		return

	_voxel_timer += delta
	if _voxel_timer < 0.75:
		return
	_voxel_timer = 0.0

	var sc := get_tree().current_scene
	if sc == null or protagonist == null:
		return

	var edits: int = int(sc.get_meta("voxel_edits", 0)) + 1
	sc.set_meta("voxel_edits", edits)

	# Spawn / mine a visible 1x1x1 terraced voxel block near protagonist
	var block := MeshInstance3D.new()
	block.name = "ShowcaseVoxel_%d" % edits
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	block.mesh = bm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.68, 0.28) if (edits % 2 == 0) else Color(0.48, 0.35, 0.20)
	mat.roughness = 0.85
	block.set_surface_override_material(0, mat)

	var angle: float = float(edits) * 1.3
	var offset := Vector3(cos(angle) * 2.4, 0.5, sin(angle) * 2.4)
	block.global_position = protagonist.global_position + offset
	block.scale = Vector3(0.01, 0.01, 0.01)

	sc.add_child(block)

	var tw := block.create_tween()
	tw.tween_property(block, "scale", Vector3(1.0, 1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.5)
	tw.tween_property(block, "scale", Vector3(0.01, 0.01, 0.01), 0.22)
	tw.tween_callback(block.queue_free)

	_spawn_floating_label("+1 Voxel Block", Color(0.3, 1.0, 0.5), block.global_position + Vector3(0.0, 1.4, 0.0))

# -----------------------------------------------------------------------------
# Idle Patrol Traversal
# -----------------------------------------------------------------------------
func _physics_idle_patrol(delta: float) -> void:
	var objectives := get_tree().get_nodes_in_group("objective")
	var target_pos := Vector3.ZERO
	if not objectives.is_empty() and objectives[0] is Node3D:
		target_pos = (objectives[0] as Node3D).global_position

	var to_obj := (target_pos - protagonist.global_position)
	to_obj.y = 0.0
	if to_obj.length() > 3.0:
		var dir := to_obj.normalized()
		protagonist.velocity.x = dir.x * 5.0
		protagonist.velocity.z = dir.z * 5.0
	else:
		protagonist.velocity.x = 0.0
		protagonist.velocity.z = 0.0

	protagonist.velocity.y -= 19.6 * delta
	protagonist.move_and_slide()

# -----------------------------------------------------------------------------
# Cinematic Action Camera Director
# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		var sc := get_tree().current_scene
		if sc != null:
			var cams := sc.find_children("", "Camera3D", true, false)
			if not cams.is_empty():
				cam = cams[0] as Camera3D
				cam.current = true

	if cam == null or protagonist == null or not is_instance_valid(protagonist):
		return

	# Compute smooth focus point blending 70% protagonist + 30% target
	var best_target := _find_best_camera_target()
	var target_pos := best_target.global_position if best_target != null else protagonist.global_position
	var raw_focus := protagonist.global_position * 0.7 + target_pos * 0.3 + Vector3(0.0, 1.4, 0.0)

	if _smooth_focus == Vector3.ZERO:
		_smooth_focus = raw_focus
	else:
		_smooth_focus = _smooth_focus.lerp(raw_focus, clampf(delta * 5.5, 0.0, 1.0))

	# Orbit around _smooth_focus at 16.0 deg/s
	_orbit_angle += deg_to_rad(16.0 * delta)

	var is_hex := _is_strategy_scene()
	var radius: float = 13.5 if is_hex else 11.5
	var height: float = 11.0 if is_hex else 5.8

	var cam_pos := _smooth_focus + Vector3(cos(_orbit_angle) * radius, height, sin(_orbit_angle) * radius)

	cam.fov = 58.0
	cam.look_at_from_position(cam_pos, _smooth_focus, Vector3.UP)

func _find_best_camera_target() -> Node3D:
	var hostile := _find_nearest_active_hostile()
	if hostile != null:
		return hostile

	var harvestable := _find_nearest_harvestable()
	if harvestable != null:
		return harvestable

	var runner := _find_nearest_runner_target()
	if runner != null:
		return runner

	var objectives := get_tree().get_nodes_in_group("objective")
	for o in objectives:
		if o is Node3D and is_instance_valid(o):
			return o as Node3D

	return null

# -----------------------------------------------------------------------------
# Helper Queries
# -----------------------------------------------------------------------------
func _is_strategy_scene() -> bool:
	var sc := get_tree().current_scene
	if sc == null:
		return false
	if sc.has_meta("hex_substrate") or not get_tree().get_nodes_in_group("hex_tile").is_empty():
		return true
	return sc.find_children("", "TurnManager", true, false).size() > 0

func _is_voxel_scene() -> bool:
	var sc := get_tree().current_scene
	if sc == null:
		return false
	if sc.has_meta("voxel_substrate"):
		return true
	return sc.find_children("", "VoxelWorldGenerator", true, false).size() > 0

func _spawn_floating_label(text: String, color: Color, world_pos: Vector3) -> void:
	if not is_inside_tree():
		return

	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = color
	lbl.font_size = 36
	lbl.outline_size = 8
	lbl.outline_modulate = Color.BLACK
	var sc := get_tree().current_scene
	var container: Node = sc if sc != null else self
	container.add_child(lbl)
	lbl.global_position = world_pos

	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.2, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(lbl.queue_free)


func _spawn_tactical_bolt(from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var bolt := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	bolt.mesh = sm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	bolt.set_surface_override_material(0, mat)

	var sc := get_tree().current_scene
	var container: Node = sc if sc != null else self
	container.add_child(bolt)
	bolt.global_position = from_pos

	var tw := bolt.create_tween()
	tw.tween_property(bolt, "global_position", to_pos, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(bolt.queue_free)
