extends Node3D
## fire_prison_controller.gd
## Authoritative zone controller bound to res://scenes/zones/fire_prison_rig.tscn
## Strictly conforms to /specs/interface_contracts.json (sprint_014_prison_rig).

signal warden_encounter_started(warden_pos: Vector3)
signal coal_vent_extracted(vent_name: String, remaining_charges: int)
signal warden_defeated(duration_sec: float)

@export var max_draw_calls_budget: int = 180
@export var max_active_physics_bodies: int = 64

var warden_spawned: bool = false
var warden_hp: float = 2200.0
var encounter_start_time: float = 0.0
var coal_vent_charges: int = 6

func _ready() -> void:
	# Dispatch procedural scatter & environment setup on WorkerThreadPool per CLAUDE.md Rule 1
	ProceduralJobRunner.run_on_worker_thread(
		"init_fire_prison_environment",
		_generate_rig_procedural_layout,
		_on_rig_procedural_layout_ready
	)

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
	if warden_spawned:
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
	if not warden_spawned or warden_hp <= 0.0:
		return
	warden_hp = maxf(0.0, warden_hp - amount)
	if warden_hp == 0.0:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - encounter_start_time
		warden_defeated.emit(elapsed)
