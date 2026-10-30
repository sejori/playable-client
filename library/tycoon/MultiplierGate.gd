class_name MultiplierGate
extends Area3D
## MultiplierGate.gd
## Multiplier archway trigger (+50% or 2x tokens) for runner and tycoon tracks.

signal multiplier_activated(multiplier: float)

@export var multiplier_factor: float = 2.0

func _ready() -> void:
	collision_layer = 4 # Layer 4: Interactable
	collision_mask = 2 # Player
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_character") or body.collision_layer & 2:
		multiplier_activated.emit(multiplier_factor)
