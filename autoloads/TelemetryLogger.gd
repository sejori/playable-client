extends Node
## TelemetryLogger.gd
## Emits structured JSONL bot & authoritative server telemetry events matching Section 5.2 schema.

signal telemetry_event_logged(entry: Dictionary)

var current_branch: String = "feat/prison-rig"
var _tick_counter: int = 0
var _buffer: Array[Dictionary] = []

func _physics_process(_delta: float) -> void:
	_tick_counter += 1

func log_nav_stuck(bot_id: String, pos: Vector3, target_pos: Vector3, blocking_collider: String, quest_id: String, quest_step: int) -> Dictionary:
	var entry := {
		"ts": int(Time.get_unix_time_from_system()),
		"tick": _tick_counter,
		"branch": current_branch,
		"bot_id": bot_id,
		"event": "NAV_STUCK",
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"target_pos": [snappedf(target_pos.x, 0.1), snappedf(target_pos.y, 0.1), snappedf(target_pos.z, 0.1)],
		"blocking_collider": blocking_collider,
		"quest_id": quest_id,
		"quest_step": quest_step
	}
	_write_entry(entry)
	return entry

func log_combat_summary(bot_id: String, encounter: String, outcome: String, duration_sec: float, hp_pct: float, dps: float, abilities_used: Dictionary) -> Dictionary:
	var entry := {
		"ts": int(Time.get_unix_time_from_system()),
		"tick": _tick_counter,
		"branch": current_branch,
		"bot_id": bot_id,
		"event": "COMBAT_SUMMARY",
		"encounter": encounter,
		"outcome": outcome,
		"duration_sec": snappedf(duration_sec, 0.1),
		"player_hp_remaining_pct": snappedf(hp_pct, 0.1),
		"dps_dealt": snappedf(dps, 0.1),
		"abilities_used": abilities_used
	}
	_write_entry(entry)
	return entry

func _write_entry(entry: Dictionary) -> void:
	_buffer.append(entry)
	var log_path := "user://realms/" + BootLoader.active_realm_id + "/telemetry.jsonl"
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(entry))
		file.close()
	telemetry_event_logged.emit(entry)
