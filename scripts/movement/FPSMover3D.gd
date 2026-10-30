class_name FPSMover3D
extends MoverComponentBase
## FPSMover3D.gd
## High-response 60Hz Arena FPS movement controller with instant directional strafing,
## crouch sliding, sprint acceleration, and zero-latency air control.
## Primary mover for Cartridge 5: Arena FPS.

@export var base_speed: float = 7.5
@export var sprint_multiplier: float = 1.45
@export var crouch_speed: float = 3.5
@export var jump_velocity: float = 6.8
@export var gravity: float = 20.0
@export var air_control_factor: float = 0.4
@export var normal_height: float = 1.8
@export var crouch_height: float = 1.0

var is_sprinting: bool = false
var is_crouching: bool = false
var is_sliding: bool = false
var _slide_timer: float = 0.0

func handle_input(event: InputEvent, host: CharacterBody3D) -> void:
	if not is_enabled:
		return
	if event.is_action_pressed("jump") and host.is_on_floor():
		host.velocity.y = jump_velocity
		jumped.emit()

	if event.is_action_pressed("sprint"):
		is_sprinting = true
	elif event.is_action_released("sprint"):
		is_sprinting = false

	if event.is_action_pressed("crouch"):
		is_crouching = true
		if is_sprinting and host.is_on_floor():
			is_sliding = true
			_slide_timer = 0.6
	elif event.is_action_released("crouch"):
		is_crouching = false
		is_sliding = false

func compute_velocity(delta: float, current_vel: Vector3, host: CharacterBody3D) -> Vector3:
	var vel := current_vel

	if not host.is_on_floor():
		vel.y -= gravity * delta

	# Adjust collision shape height if available
	var col := host.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		var cap := col.shape as CapsuleShape3D
		var target_h := crouch_height if is_crouching else normal_height
		cap.height = move_toward(cap.height, target_h, 8.0 * delta)

	if is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0 or not host.is_on_floor():
			is_sliding = false

	# Instant strafe direction based on host yaw
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -host.global_transform.basis.z
	var right := host.global_transform.basis.x
	var move_dir := (right * input_vec.x + forward * -input_vec.y).normalized()

	var target_speed := base_speed
	if is_sliding:
		target_speed = base_speed * sprint_multiplier * 1.3
	elif is_sprinting:
		target_speed = base_speed * sprint_multiplier
	elif is_crouching:
		target_speed = crouch_speed

	if host.is_on_floor():
		if move_dir.length() > 0.01:
			vel.x = move_dir.x * target_speed
			vel.z = move_dir.z * target_speed
			moved.emit(vel)
		else:
			vel.x = move_toward(vel.x, 0.0, 35.0 * delta)
			vel.z = move_toward(vel.z, 0.0, 35.0 * delta)
	else:
		# Air control
		if move_dir.length() > 0.01:
			var air_accel := 25.0 * air_control_factor * delta
			vel.x = move_toward(vel.x, move_dir.x * target_speed, air_accel)
			vel.z = move_toward(vel.z, move_dir.z * target_speed, air_accel)

	return vel
