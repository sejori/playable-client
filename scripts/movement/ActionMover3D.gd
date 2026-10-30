class_name ActionMover3D
extends MoverComponentBase
## ActionMover3D.gd
## 3rd-Person Action RPG mover with camera-relative WASD, ground snapping, dodge roll, and jump.

@export var move_speed: float = 9.0
@export var sprint_speed: float = 14.0
@export var acceleration: float = 24.0
@export var friction: float = 20.0
@export var jump_velocity: float = 6.5
@export var gravity: float = 18.0
@export var dodge_speed: float = 18.0
@export var dodge_duration: float = 0.35
@export var camera_path: NodePath

var is_dodging: bool = false
var is_sprinting: bool = false
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD
var _cached_cam: Camera3D = null

func _ready() -> void:
	if not camera_path.is_empty():
		_cached_cam = get_node_or_null(camera_path) as Camera3D

func handle_input(event: InputEvent, host: CharacterBody3D) -> void:
	if not is_enabled:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("jump"):
		if host.is_on_floor() and not is_dodging:
			host.velocity.y = jump_velocity
			jumped.emit()
	if event.is_action_pressed("sprint"):
		is_sprinting = true
	elif event.is_action_released("sprint"):
		is_sprinting = false

	if event.is_action_pressed("dodge") and not is_dodging and host.is_on_floor():
		_start_dodge(host)

func _start_dodge(host: CharacterBody3D) -> void:
	is_dodging = true
	_dodge_timer = dodge_duration
	var horiz_vel := Vector3(host.velocity.x, 0.0, host.velocity.z)
	if horiz_vel.length() > 0.5:
		_dodge_dir = horiz_vel.normalized()
	else:
		_dodge_dir = -host.global_transform.basis.z
	state_changed.emit("dodge")

func compute_velocity(delta: float, current_vel: Vector3, host: CharacterBody3D) -> Vector3:
	var vel := current_vel

	# Apply gravity
	if not host.is_on_floor():
		vel.y -= gravity * delta

	if is_dodging:
		_dodge_timer -= delta
		vel.x = _dodge_dir.x * dodge_speed
		vel.z = _dodge_dir.z * dodge_speed
		if _dodge_timer <= 0.0:
			is_dodging = false
			state_changed.emit("idle")
		return vel

	# Camera-relative directional movement
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := _get_camera()
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT

	if cam != null:
		var cam_basis := cam.global_transform.basis
		forward = -cam_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		right = cam_basis.x
		right.y = 0.0
		right = right.normalized()

	var desired_dir := (right * input_vec.x + forward * -input_vec.y).normalized()
	var target_speed := sprint_speed if is_sprinting else move_speed

	if desired_dir.length() > 0.01:
		vel.x = move_toward(vel.x, desired_dir.x * target_speed, acceleration * delta)
		vel.z = move_toward(vel.z, desired_dir.z * target_speed, acceleration * delta)
		# Face movement direction smoothly
		var look_target := host.global_position + desired_dir
		look_target.y = host.global_position.y
		host.look_at(look_target, Vector3.UP)
		moved.emit(vel)
	else:
		vel.x = move_toward(vel.x, 0.0, friction * delta)
		vel.z = move_toward(vel.z, 0.0, friction * delta)

	return vel

func _get_camera() -> Camera3D:
	if _cached_cam != null and is_instance_valid(_cached_cam):
		return _cached_cam
	var vp := get_viewport()
	if vp != null:
		return vp.get_camera_3d()
	return null
