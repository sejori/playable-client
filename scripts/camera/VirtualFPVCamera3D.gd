class_name VirtualFPVCamera3D
extends VirtualCameraBase3D
## VirtualFPVCamera3D.gd
## 1st-Person Camera attached to player eye height with pitch clamping and weapon/head bob.
## Primary camera for Cartridge 3: Voxel-Survival and Cartridge 5: Arena FPS.

@export var eye_height: float = 1.65
@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -85.0
@export var pitch_max_deg: float = 85.0
@export var head_bob_frequency: float = 8.0
@export var head_bob_amplitude: float = 0.04

var yaw: float = 0.0
var pitch: float = 0.0
var _bob_timer: float = 0.0
var _bob_offset: Vector3 = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity * (180.0 / PI), pitch_min_deg, pitch_max_deg)

func update_virtual_camera(delta: float) -> void:
	if target != null and is_instance_valid(target) and target is CharacterBody3D:
		var speed := (target as CharacterBody3D).velocity.length()
		if speed > 0.5 and (target as CharacterBody3D).is_on_floor():
			_bob_timer += delta * head_bob_frequency * (speed / 6.0)
			_bob_offset.y = sin(_bob_timer) * head_bob_amplitude
			_bob_offset.x = cos(_bob_timer * 0.5) * head_bob_amplitude * 0.5
		else:
			_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * 10.0)

func get_desired_global_transform() -> Transform3D:
	var eye_pos: Vector3 = global_position + Vector3(0.0, eye_height, 0.0)
	if target != null and is_instance_valid(target):
		eye_pos = target.global_position + Vector3(0.0, eye_height, 0.0)
	eye_pos += _bob_offset

	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	return Transform3D(rot, eye_pos)
