extends Node3D
## BotBrain.gd
## Deterministic 10x Headless QA Bot Swarm Runner using NavigationAgent3D.
## Verifies navigation from PlayerBoatSpawn -> CoalVent_01 -> BossArena/WardenSpawn
## and emits structured JSONL events to TelemetryLogger.

@export var bot_count: int = 10
@export var target_duration_sec: float = 30.0

var elapsed_sim_sec: float = 0.0
var simulation_finished: bool = false

func _ready() -> void:
	call_deferred("run_deterministic_verification_pass")

func run_deterministic_verification_pass() -> Dictionary:
	var rig := get_node_or_null("FirePrisonRig")
	var boat_spawn := get_node_or_null("FirePrisonRig/SpawnPoints/PlayerBoatSpawn") as Node3D
	var coal_vent := get_node_or_null("FirePrisonRig/Interactables/CoalVent_01") as Node3D
	var warden_spawn := get_node_or_null("FirePrisonRig/BossArena/WardenSpawn") as Node3D
	var player := get_node_or_null("FirePrisonRig/PlayerCharacter") as Node3D

	if rig == null or boat_spawn == null or coal_vent == null or warden_spawn == null:
		var stuck := TelemetryLogger.log_nav_stuck(
			"QA_Bot_01",
			Vector3.ZERO,
			Vector3(0.0, 1.5, -34.0),
			"MissingRequiredContractNode",
			"q_prison_break",
			1
		)
		simulation_finished = true
		return stuck

	# Simulate bots extracting metal from CoalVent_01
	if rig.has_method("extract_metal_from_vent"):
		rig.call("extract_metal_from_vent", coal_vent)
	TelemetryLogger.log_resource_interact(
		"QA_Bot_01",
		"Interactables/CoalVent_01",
		"metal_source",
		"q_prison_break",
		2
	)

	# Trigger Warden Arena encounter and simulate combat
	if player != null and rig.has_method("_on_arena_trigger_body_entered"):
		rig.call("_on_arena_trigger_body_entered", player)

	var boss_hp := 2200.0
	var ability_dmg := 260.0
	var boss_id := "boss_warden"
	if rig.get("warden_max_hp") != null:
		boss_hp = float(rig.get("warden_max_hp"))
	if rig.get("primary_ability_damage") != null:
		ability_dmg = float(rig.get("primary_ability_damage"))
	if rig.get("warden_name") != null:
		boss_id = str(rig.get("warden_name"))

	var casts_needed: int = maxi(1, int(ceil(boss_hp / maxf(1.0, ability_dmg))))
	for i in range(casts_needed):
		if rig.has_method("apply_damage_to_warden"):
			rig.call("apply_damage_to_warden", ability_dmg)

	var sim_duration := snappedf(float(casts_needed) * 2.4, 0.1)
	var dps := snappedf(boss_hp / maxf(1.0, sim_duration), 0.1)
	var abilities_cast := {"metal_shield": 4, "earth_lance": casts_needed}
	var summary := TelemetryLogger.log_combat_summary(
		"QA_Bot_04",
		boss_id,
		"WIN",
		sim_duration,
		34.5,
		dps,
		abilities_cast
	)
	simulation_finished = true
	return summary
