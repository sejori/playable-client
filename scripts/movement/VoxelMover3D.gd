class_name VoxelMover3D
extends MoverComponentBase
## VoxelMover3D.gd
## Minecraft-style voxel movement controller with automatic 1m block-step climbing,
## water buoyancy, ladder climbing, and discrete grid gravity.
## Primary mover for Cartridge 3: Voxel-Survival.

@export var walk_speed: float = 4.3
@export var sprint_speed: float = 6.2
@export var jump_velocity: float = 7.5
@export var block_step_height: float = 1.05
@export var gravity: float = 24.0
@export var water_swim_speed: float = 3.5

var is_sprinting: bool = false
var in_water: bool = false
var on_ladder: bool = false

func handle_input(event: InputEvent, host: CharacterBody3D) -> void:
	if not is_enabled:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("jump"):
		if in_water or on_ladder:
			host.velocity.y = water_swim_speed
		elif host.is_on_floor():
			host.velocity.y = jump_velocity
			jumped.emit()

	if event.is_action_pressed("sprint"):
		is_sprinting = true
	elif event.is_action_released("sprint"):
		is_sprinting = false

func compute_velocity(delta: float, current_vel: Vector3, host: CharacterBody3D) -> Vector3:
	var vel := current_vel

	if in_water:
		vel.y = move_toward(vel.y, -1.0, 8.0 * delta)
		if Input.is_action_pressed("jump"):
			vel.y = water_swim_speed
		elif Input.is_action_pressed("crouch"):
			vel.y = -water_swim_speed
	elif on_ladder:
		vel.y = 0.0
		if Input.is_action_pressed("move_forward"):
			vel.y = walk_speed * 0.7
		elif Input.is_action_pressed("move_back"):
			vel.y = -walk_speed * 0.7
	elif not host.is_on_floor():
		vel.y -= gravity * delta

	# Horizontal movement
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := host.get_viewport().get_camera_3d()
	var forward := -host.global_transform.basis.z
	var right := host.global_transform.basis.x

	if cam != null:
		var cam_b := cam.global_transform.basis
		forward = -cam_b.z
		forward.y = 0.0
		forward = forward.normalized()
		right = cam_b.x
		right.y = 0.0
		right = right.normalized()

	var move_dir := (right * input_vec.x + forward * -input_vec.y).normalized()
	var speed := sprint_speed if is_sprinting else walk_speed
	if in_water:
		speed = water_swim_speed

	if move_dir.length() > 0.01:
		vel.x = move_dir.x * speed
		vel.z = move_dir.z * speed
		_check_block_step(host, move_dir, delta)
		moved.emit(vel)
	else:
		vel.x = move_toward(vel.x, 0.0, 20.0 * delta)
		vel.z = move_toward(vel.z, 0.0, 20.0 * delta)

	return vel

func _check_block_step(host: CharacterBody3D, move_dir: Vector3, _delta: float) -> void:
	if not host.is_on_floor():
		return
	var space := host.get_world_3d().direct_space_state
	if space == null:
		return

	# Ray 1: Knee height forward check
	var knee_pos := host.global_position + Vector3(0.0, 0.3, 0.0)
	var knee_target := knee_pos + move_dir * 0.75
	var knee_query := PhysicsRayQueryParameters3D.create(knee_pos, knee_target, 1)
	var hit_knee := space.intersect_ray(knee_query)

	# If blocked at knee, check if head space is clear to step up
	if not hit_knee.is_empty():
		var step_pos := host.global_position + Vector3(0.0, block_step_height + 0.1, 0.0)
		var step_target := step_pos + move_dir * 0.75
		var step_query := PhysicsRayQueryParameters3D.create(step_pos, step_target, 1)
		var hit_step := space.intersect_ray(step_query)

		if hit_step.is_empty():
			# Clear above, automatically snap up
			host.global_position.y += block_step_height * 0.5
