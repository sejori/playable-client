class_name VirtualChaseCamera3D
extends VirtualCameraBase3D
## VirtualChaseCamera3D.gd
## High-velocity chase camera with steering lag and speed-responsive dynamic FOV.
## Primary camera for Cartridge 6: Collector Tycoon & Arcade Racers.

@export var follow_distance: float = 6.5
@export var follow_height: float = 2.4
@export var lag_factor: float = 8.0
@export var fov_min: float = 65.0
@export var fov_max: float = 95.0
@export var max_speed_reference: float = 30.0

var _current_cam_pos: Vector3 = Vector3.ZERO
var _current_look_pos: Vector3 = Vector3.ZERO
var _dynamic_fov: float = 70.0
var _initialized: bool = false

func update_virtual_camera(delta: float) -> void:
	var target_pos := global_position
	var target_forward := -global_transform.basis.z
	var current_speed: float = 0.0

	if target != null and is_instance_valid(target):
		target_pos = target.global_position
		target_forward = -target.global_transform.basis.z
		if target is CharacterBody3D:
			current_speed = (target as CharacterBody3D).velocity.length()
		elif target.get("linear_velocity") != null:
			current_speed = (target.get("linear_velocity") as Vector3).length()

	var desired_cam_pos := target_pos - target_forward * follow_distance + Vector3.UP * follow_height
	var desired_look_pos := target_pos + Vector3.UP * (follow_height * 0.5)

	if not _initialized:
		_current_cam_pos = desired_cam_pos
		_current_look_pos = desired_look_pos
		_initialized = true

	var t := clampf(delta * lag_factor, 0.0, 1.0)
	_current_cam_pos = _current_cam_pos.lerp(desired_cam_pos, t)
	_current_look_pos = _current_look_pos.lerp(desired_look_pos, t)

	# Dynamic speed FOV warp
	var speed_ratio := clampf(current_speed / max_speed_reference, 0.0, 1.0)
	_dynamic_fov = lerpf(fov_min, fov_max, speed_ratio)

func get_desired_global_transform() -> Transform3D:
	if not _initialized:
		return global_transform
	var forward := (_current_look_pos - _current_cam_pos).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	return Transform3D(basis, _current_cam_pos)

func get_desired_fov() -> float:
	return _dynamic_fov
