class_name MoverComponentBase
extends Node
## MoverComponentBase.gd
## Abstract base component for the Generic Motion Substrate (Layer 2).
## Plugs into ModularCharacter3D or any CharacterBody3D to compute velocity and handle movement input.

signal moved(velocity: Vector3)
signal jumped()
signal state_changed(new_state: String)

@export var is_enabled: bool = true

func compute_velocity(_delta: float, current_vel: Vector3, _host: CharacterBody3D) -> Vector3:
	return current_vel

func handle_input(_event: InputEvent, _host: CharacterBody3D) -> void:
	pass

func on_physics_step(_delta: float, _host: CharacterBody3D) -> void:
	pass
