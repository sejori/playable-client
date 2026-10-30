class_name VelocityRider3D
extends MoverComponentBase
## VelocityRider3D.gd
## High-speed arcade vehicle and runner mover with forward acceleration, steering, drift, and boost.
## Primary mover for Cartridge 6: Collector Tycoon & Arcade Racers.

@export var base_speed: float = 16.0
@export var max_speed: float = 34.0
@export var acceleration: float = 12.0
@export var braking: float = 24.0
@export var steer_speed: float = 2.4
@export var drift_slip_factor: float = 0.85
@export var boost_multiplier: float = 1.75
@export var jump_pad_velocity: float = 14.0

var current_speed: float = 0.0
var is_drifting: bool = false
var is_boosting: bool = false
var _boost_timer: float = 0.0

func trigger_boost(duration: float = 2.0) -> void:
	is_boosting = true
	_boost_timer = duration
	state_changed.emit("boosting")

func trigger_jump_pad(host: CharacterBody3D, custom_force: float = 0.0) -> void:
	var force := custom_force if custom_force > 0.0 else jump_pad_velocity
	host.velocity.y = force
	jumped.emit()

func handle_input(event: InputEvent, _host: CharacterBody3D) -> void:
	if not is_enabled:
		return
	if event.is_action_pressed("drift"):
		is_drifting = true
	elif event.is_action_released("drift"):
		is_drifting = false

func compute_velocity(delta: float, current_vel: Vector3, host: CharacterBody3D) -> Vector3:
	var vel := current_vel

	if not host.is_on_floor():
		vel.y -= 22.0 * delta

	if is_boosting:
		_boost_timer -= delta
		if _boost_timer <= 0.0:
			is_boosting = false
			state_changed.emit("normal")

	# Throttle / steering
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_right", "move_left")

	# Target forward speed
	var target_max := (max_speed * boost_multiplier) if is_boosting else max_speed
	if throttle > 0.1:
		current_speed = move_toward(current_speed, target_max * throttle, acceleration * delta)
	elif throttle < -0.1:
		current_speed = move_toward(current_speed, -base_speed * 0.5, braking * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, 8.0 * delta)

	# Steer rotation
	if absf(current_speed) > 0.2:
		var steer_amount := steer * steer_speed * delta * signf(current_speed)
		if is_drifting:
			steer_amount *= 1.4
		host.rotate_y(steer_amount)

	var forward := -host.global_transform.basis.z
	var desired_vel := forward * current_speed

	if is_drifting:
		# Blend between current forward velocity and previous velocity
		vel.x = lerpf(vel.x, desired_vel.x, (1.0 - drift_slip_factor) * 10.0 * delta)
		vel.z = lerpf(vel.z, desired_vel.z, (1.0 - drift_slip_factor) * 10.0 * delta)
	else:
		vel.x = desired_vel.x
		vel.z = desired_vel.z

	if absf(current_speed) > 0.1:
		moved.emit(vel)

	return vel
