class_name TurnManager
extends Node
## TurnManager.gd
## Turn-based state machine for 4X strategy and tactical tabletop games.
## Controls turn phases (PlayerTurn, EnemyTurn, Resolution), action points, and round counters.

signal turn_started(round_number: int, current_faction: String)
signal turn_ended(round_number: int, current_faction: String)
signal ap_changed(remaining_ap: int)

enum TurnPhase {
	PLAYER_TURN,
	ENEMY_TURN,
	RESOLUTION
}

@export var max_ap: int = 3
@export var current_round: int = 1

var current_phase: TurnPhase = TurnPhase.PLAYER_TURN
var current_ap: int = 3
var faction_names: Array[String] = ["Player_Blue", "Enemy_Red"]
var active_faction_idx: int = 0

func _ready() -> void:
	current_ap = max_ap
	turn_started.emit(current_round, get_current_faction())

func get_current_faction() -> String:
	return faction_names[active_faction_idx]

func consume_ap(amount: int = 1) -> bool:
	if current_ap >= amount:
		current_ap -= amount
		ap_changed.emit(current_ap)
		return true
	return false

func end_current_turn() -> void:
	turn_ended.emit(current_round, get_current_faction())
	active_faction_idx = (active_faction_idx + 1) % faction_names.size()

	if active_faction_idx == 0:
		current_round += 1
		current_phase = TurnPhase.PLAYER_TURN
	else:
		current_phase = TurnPhase.ENEMY_TURN

	current_ap = max_ap
	ap_changed.emit(current_ap)
	turn_started.emit(current_round, get_current_faction())
