class_name ModularBossController
extends CharacterBody3D
## ModularBossController.gd
## Procedural multi-phase boss controller with telegraphing, phase transitions, and combat logging.

signal phase_changed(new_phase: int)
signal boss_defeated()
signal damage_taken(amount: float, remaining_hp: float)

@export var boss_name: String = "Volcanic Golem Brute"
@export var max_hp: float = 2400.0
@export var current_hp: float = 2400.0
@export var attack_damage: float = 45.0
@export var phase_2_threshold: float = 0.5
@export var phase_3_threshold: float = 0.2

var current_phase: int = 1
var is_invulnerable: bool = false
var _target_player: Node3D = null

func _ready() -> void:
	collision_layer = 3 # Layer 3: Enemy_Hitbox
	collision_mask = 1 | 2 # Environment & Player
	add_to_group("boss_target")
	current_hp = max_hp

func take_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
	if is_invulnerable or current_hp <= 0.0:
		return

	current_hp = maxf(0.0, current_hp - amount)
	damage_taken.emit(amount, current_hp)

	var hp_ratio := current_hp / max_hp
	if hp_ratio <= phase_3_threshold and current_phase < 3:
		_transition_to_phase(3)
	elif hp_ratio <= phase_2_threshold and current_phase < 2:
		_transition_to_phase(2)

	if current_hp <= 0.0:
		boss_defeated.emit()

func _transition_to_phase(new_phase: int) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

func apply_damage_to_warden(amount: float) -> void:
	take_damage(amount)
