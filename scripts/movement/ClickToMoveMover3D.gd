class_name ClickToMoveMover3D
extends MoverComponentBase
## ClickToMoveMover3D.gd
## Tick-synchronized click-to-move mover using NavigationAgent3D.
## In OSRS mode, movements advance by 1-2 discrete tile steps per 600ms deterministic tick.
## Primary mover for Cartridge 2: Tick-Based Sandbox.

signal destination_reached(target_pos: Vector3)
signal tick_advanced(current_tile: Vector3i)

@export var tick_interval_sec: float = 0.6
@export var run_mode: bool = false
@export var walk_tiles_per_tick: int = 1
@export var run_tiles_per_tick: int = 2
@export var tile_size: float = 1.0
@export var smooth_interpolation: bool = true
@export var move_speed: float = 5.0

var _target_destination: Vector3
var _has_destination: bool = false
var _tick_timer: float = 0.0
var _nav_agent: NavigationAgent3D = null
var _waypoints: Array[Vector3] = []
var _current_target_wp: Vector3

func _ready() -> void:
	_target_destination = Vector3.ZERO
	_current_target_wp = Vector3.ZERO

func setup_nav_agent(agent: NavigationAgent3D) -> void:
	_nav_agent = agent

func set_destination(dest: Vector3, host: CharacterBody3D) -> void:
	_target_destination = dest
	_has_destination = true
	if _nav_agent != null:
		_nav_agent.target_position = dest
	else:
		_waypoints = [dest]

func handle_input(event: InputEvent, host: CharacterBody3D) -> void:
	if not is_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam := host.get_viewport().get_camera_3d()
		if cam != null:
			var mouse_pos := host.get_viewport().get_mouse_position()
			var from := cam.project_ray_origin(mouse_pos)
			var to := from + cam.project_ray_normal(mouse_pos) * 1000.0
			var space := host.get_world_3d().direct_space_state
			if space != null:
				var query := PhysicsRayQueryParameters3D.create(from, to, 1) # Environment_Static
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					set_destination(hit.position, host)

func compute_velocity(delta: float, current_vel: Vector3, host: CharacterBody3D) -> Vector3:
	var vel := current_vel
	if not host.is_on_floor():
		vel.y -= 18.0 * delta

	if not _has_destination:
		vel.x = move_toward(vel.x, 0.0, 15.0 * delta)
		vel.z = move_toward(vel.z, 0.0, 15.0 * delta)
		return vel

	_tick_timer += delta
	if _tick_timer >= tick_interval_sec:
		_tick_timer -= tick_interval_sec
		_process_tick(host)

	# Steer toward current target waypoint
	var target_wp := _current_target_wp if _current_target_wp != Vector3.ZERO else _target_destination
	var diff := target_wp - host.global_position
	diff.y = 0.0

	if diff.length() < 0.2:
		if _target_destination.distance_to(host.global_position) < 0.5:
			_has_destination = false
			vel.x = 0.0
			vel.z = 0.0
			destination_reached.emit(host.global_position)
			state_changed.emit("idle")
			return vel
		elif not _waypoints.is_empty():
			_current_target_wp = _waypoints.pop_front()

	var dir := diff.normalized()
	var speed := (move_speed * 1.8) if run_mode else move_speed
	vel.x = dir.x * speed
	vel.z = dir.z * speed

	if dir.length() > 0.01:
		var look_target := host.global_position + dir
		look_target.y = host.global_position.y
		host.look_at(look_target, Vector3.UP)
		moved.emit(vel)

	return vel

func _process_tick(host: CharacterBody3D) -> void:
	var tile_coord := Vector3i(
		int(round(host.global_position.x / tile_size)),
		int(round(host.global_position.y / tile_size)),
		int(round(host.global_position.z / tile_size))
	)
	tick_advanced.emit(tile_coord)

	if _nav_agent != null and not _nav_agent.is_navigation_finished():
		var next_path_pos := _nav_agent.get_next_path_position()
		_current_target_wp = next_path_pos
