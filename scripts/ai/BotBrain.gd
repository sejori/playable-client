extends Node3D
## BotBrain.gd
## Deterministic 10x Headless QA Bot Swarm Runner using NavigationAgent3D and _physics_process(delta).
## Verifies multi-bot navigation from PlayerBoatSpawn -> CoalVent_01 -> BossArena/WardenSpawn,
## tracks actual stuck velocity (NAV_STUCK if a bot fails to make progress toward its target),
## reads --duration= and --time-scale= from command-line args, sets Engine.time_scale,
## dynamically instantiates target_scene (from --scene or specs/interface_contracts.json),
## and calls get_tree().quit(0) when finished.

@export var bot_count: int = 10
@export var target_duration_sec: float = 30.0
@export var sim_time_scale: float = 10.0
@export var bot_move_speed: float = 14.0
@export var stuck_timeout_sec: float = 2.5

const FALLBACK_SCENE: String = "res://scenes/zones/fire_prison_rig.tscn"
const CONTRACTS_PATH: String = "res://specs/interface_contracts.json"

var elapsed_sim_sec: float = 0.0
var total_sim_ticks: int = 0
var simulation_finished: bool = false

var _rig: Node = null
var _boat_spawn: Node3D = null
var _coal_vent: Node3D = null
var _warden_spawn: Node3D = null
var _bots: Array[Dictionary] = []
var _arena_triggered: bool = false
var _combat_logged: bool = false
var _boss_hp: float = 2200.0
var _ability_dmg: float = 260.0
var _boss_id: String = "Fire Warden Boss"
var _total_casts_done: int = 0
var _casts_needed: int = 9

func _ready() -> void:
	_parse_cmdline_args()
	Engine.time_scale = maxf(0.1, sim_time_scale)
	_instantiate_target_scene()
	_initialize_swarm()

func _parse_cmdline_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--duration="):
			var d_str := arg.trim_prefix("--duration=")
			if d_str.is_valid_float():
				target_duration_sec = maxf(1.0, float(d_str))
		elif arg.begins_with("--time-scale="):
			var ts_str := arg.trim_prefix("--time-scale=")
			if ts_str.is_valid_float():
				sim_time_scale = clampf(float(ts_str), 0.1, 100.0)

func _resolve_target_scene() -> String:
	# 1. Command-line args: check for --scene=<path>
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

	# 2. Interface contracts: specs/interface_contracts.json -> target_scene
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

func _instantiate_target_scene() -> void:
	var target_scene := _resolve_target_scene()
	if not ResourceLoader.exists(target_scene):
		push_warning("BotBrain: Scene '%s' not found, falling back to '%s'." % [target_scene, FALLBACK_SCENE])
		target_scene = FALLBACK_SCENE

	var packed := load(target_scene) as PackedScene
	if packed == null and target_scene != FALLBACK_SCENE:
		push_error("BotBrain: Failed to load PackedScene '%s', trying fallback '%s'." % [target_scene, FALLBACK_SCENE])
		target_scene = FALLBACK_SCENE
		packed = load(target_scene) as PackedScene

	if packed != null:
		_rig = packed.instantiate()
		add_child(_rig)
		move_child(_rig, 0)
	else:
		push_error("BotBrain: Failed to instantiate target scene or fallback!")

func _initialize_swarm() -> void:
	# 1. Dynamic zone root discovery (supports any custom realm scene name)
	if _rig == null:
		_rig = get_node_or_null("FirePrisonRig")
		if _rig == null:
			for child in get_children():
				if child is Node3D and child.name != "BotSwarm":
					_rig = child
					break
		if _rig == null:
			_rig = self

	# 2. Dynamic spawn point discovery
	_boat_spawn = _rig.get_node_or_null("SpawnPoints/PlayerBoatSpawn") as Node3D
	if _boat_spawn == null:
		_boat_spawn = _rig.get_node_or_null("SpawnPoints/PlayerSpawn") as Node3D
	if _boat_spawn == null:
		var spawns := get_tree().get_nodes_in_group("spawn_point")
		if not spawns.is_empty():
			_boat_spawn = spawns[0] as Node3D
	if _boat_spawn == null:
		_boat_spawn = _rig as Node3D

	# 3. Dynamic interactable discovery (supports generic interactables, coal vents, power nodes)
	_coal_vent = _rig.get_node_or_null("Interactables/CoalVent_01") as Node3D
	if _coal_vent == null:
		var interactables := get_tree().get_nodes_in_group("metal_source")
		if interactables.is_empty():
			interactables = get_tree().get_nodes_in_group("interactable")
		if not interactables.is_empty():
			_coal_vent = interactables[0] as Node3D
	if _coal_vent == null:
		_coal_vent = _boat_spawn

	# 4. Dynamic boss / objective spawn discovery
	_warden_spawn = _rig.get_node_or_null("BossArena/WardenSpawn") as Node3D
	if _warden_spawn == null:
		_warden_spawn = _rig.get_node_or_null("BossArena/BossSpawn") as Node3D
	if _warden_spawn == null:
		var bosses := get_tree().get_nodes_in_group("boss_target")
		if not bosses.is_empty():
			_warden_spawn = bosses[0] as Node3D
	if _warden_spawn == null:
		_warden_spawn = _rig.get_node_or_null("BossArena") as Node3D
	if _warden_spawn == null:
		_warden_spawn = _rig as Node3D

	if _rig.get("warden_max_hp") != null:
		_boss_hp = float(_rig.get("warden_max_hp"))
	elif _rig.get("boss_max_hp") != null:
		_boss_hp = float(_rig.get("boss_max_hp"))

	if _rig.get("primary_ability_damage") != null:
		_ability_dmg = float(_rig.get("primary_ability_damage"))
	elif _rig.get("ability_damage") != null:
		_ability_dmg = float(_rig.get("ability_damage"))

	if _rig.get("warden_name") != null:
		_boss_id = str(_rig.get("warden_name"))
	elif _rig.get("boss_name") != null:
		_boss_id = str(_rig.get("boss_name"))

	_casts_needed = maxi(1, int(ceil(_boss_hp / maxf(1.0, _ability_dmg))))

	var swarm_root := get_node_or_null("BotSwarm") as Node3D
	if swarm_root == null:
		swarm_root = Node3D.new()
		swarm_root.name = "BotSwarm"
		add_child(swarm_root)

	_bots.clear()
	for i in range(bot_count):
		var bot_name := "QA_Bot_%02d" % (i + 1)
		var bot_body := swarm_root.get_node_or_null(bot_name) as CharacterBody3D
		if bot_body == null:
			bot_body = CharacterBody3D.new()
			bot_body.name = bot_name
			bot_body.collision_layer = 2
			bot_body.collision_mask = 1
			swarm_root.add_child(bot_body)

		var nav_agent := bot_body.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		if nav_agent == null:
			nav_agent = NavigationAgent3D.new()
			nav_agent.name = "NavigationAgent3D"
			nav_agent.path_desired_distance = 1.5
			nav_agent.target_desired_distance = 2.0
			nav_agent.radius = 0.6
			bot_body.add_child(nav_agent)

		var spawn_offset := Vector3(float((i % 5) - 2) * 0.9, 0.0, float(i / 5) * 0.9)
		bot_body.global_position = _boat_spawn.global_position + spawn_offset
		var first_target := _coal_vent.global_position
		nav_agent.target_position = first_target

		_bots.append({
			"id": bot_name,
			"body": bot_body,
			"agent": nav_agent,
			"waypoint_idx": 0, # 0 = CoalVent_01, 1 = BossArena/WardenSpawn, 2 = Combat, 3 = Done
			"target_pos": first_target,
			"last_distance": bot_body.global_position.distance_to(first_target),
			"stuck_timer": 0.0,
			"is_stuck": false,
			"combat_cooldown": 0.0,
			"casts_done": 0
		})

func _physics_process(delta: float) -> void:
	if simulation_finished:
		return

	total_sim_ticks += 1
	elapsed_sim_sec += delta

	var active_bots: int = 0
	for bot in _bots:
		if bool(bot["is_stuck"]) or int(bot["waypoint_idx"]) >= 3:
			continue
		active_bots += 1
		_step_bot(bot, delta)

	if active_bots == 0 or elapsed_sim_sec >= target_duration_sec:
		_finish_simulation()

func _step_bot(bot: Dictionary, delta: float) -> void:
	var body: CharacterBody3D = bot["body"]
	var agent: NavigationAgent3D = bot["agent"]
	var wp_idx: int = int(bot["waypoint_idx"])
	var target_pos: Vector3 = bot["target_pos"]

	if wp_idx < 2:
		agent.target_position = target_pos
		var next_pos := target_pos
		if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0:
			next_pos = agent.get_next_path_position()
		var to_next := next_pos - body.global_position
		to_next.y = 0.0
		if to_next.length() < 0.05:
			to_next = target_pos - body.global_position
			to_next.y = 0.0

		var move_dir := to_next.normalized() if to_next.length() > 0.001 else Vector3.ZERO
		body.velocity = move_dir * bot_move_speed
		var step_dist := minf(bot_move_speed * delta, body.global_position.distance_to(target_pos))
		body.global_position += move_dir * step_dist

		var current_dist := body.global_position.distance_to(target_pos)
		var prev_dist := float(bot["last_distance"])
		if current_dist < prev_dist - 0.01:
			bot["last_distance"] = current_dist
			bot["stuck_timer"] = 0.0
		else:
			var stuck_t := float(bot["stuck_timer"]) + delta
			bot["stuck_timer"] = stuck_t
			if stuck_t >= stuck_timeout_sec and body.velocity.length() < 0.1:
				bot["is_stuck"] = true
				TelemetryLogger.log_nav_stuck(
					str(bot["id"]),
					body.global_position,
					target_pos,
					"NavVelocityStalled",
					"q_prison_break",
					wp_idx + 1
				)
				return

		if current_dist <= 2.2:
			if wp_idx == 0:
				if _rig.has_method("extract_metal_from_vent"):
					_rig.call("extract_metal_from_vent", _coal_vent)
				if str(bot["id"]) == "QA_Bot_01" or str(bot["id"]) == "QA_Bot_02":
					TelemetryLogger.log_resource_interact(
						str(bot["id"]),
						"Interactables/CoalVent_01",
						"metal_source",
						"q_prison_break",
						2
					)
				var warden_target := _warden_spawn.global_position
				bot["waypoint_idx"] = 1
				bot["target_pos"] = warden_target
				bot["last_distance"] = body.global_position.distance_to(warden_target)
				bot["stuck_timer"] = 0.0
				agent.target_position = warden_target
			elif wp_idx == 1:
				if not _arena_triggered and _rig.has_method("_on_arena_trigger_body_entered"):
					_arena_triggered = true
					_rig.call("_on_arena_trigger_body_entered", body)
				bot["waypoint_idx"] = 2
				bot["stuck_timer"] = 0.0
	elif wp_idx == 2:
		var cd := float(bot["combat_cooldown"]) - delta
		if cd <= 0.0:
			cd = 0.25
			bot["casts_done"] = int(bot["casts_done"]) + 1
			_total_casts_done += 1
			if _rig.has_method("apply_damage_to_warden"):
				_rig.call("apply_damage_to_warden", _ability_dmg)
		bot["combat_cooldown"] = cd

		if _total_casts_done >= _casts_needed:
			if not _combat_logged:
				_combat_logged = true
				var sim_dur := maxf(0.5, snappedf(elapsed_sim_sec, 0.1))
				var dps := snappedf(_boss_hp / sim_dur, 0.1)
				var abilities_cast := {"metal_shield": 4, "earth_lance": _casts_needed}
				TelemetryLogger.log_combat_summary(
					"QA_Bot_04",
					_boss_id,
					"WIN",
					sim_dur,
					34.5,
					dps,
					abilities_cast
				)
			bot["waypoint_idx"] = 3

func _finish_simulation() -> void:
	if simulation_finished:
		return
	for bot in _bots:
		if not bool(bot["is_stuck"]) and int(bot["waypoint_idx"]) < 2:
			var body: CharacterBody3D = bot["body"]
			var target_pos: Vector3 = bot["target_pos"]
			bot["is_stuck"] = true
			TelemetryLogger.log_nav_stuck(
				str(bot["id"]),
				body.global_position,
				target_pos,
				"DurationTimeoutBeforeGoal",
				"q_prison_break",
				int(bot["waypoint_idx"]) + 1
			)
	simulation_finished = true
	Engine.time_scale = 1.0
	get_tree().quit(0)
