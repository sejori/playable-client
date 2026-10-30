class_name VirtualFollowCamera3D
extends VirtualCameraBase3D
## VirtualFollowCamera3D.gd
## 3rd-Person Orbiting SpringArm camera with collision probe and distance damping.
## Primary camera for Cartridge 1: Action-RPG.

@export var distance: float = 9.0
@export var min_distance: float = 3.0
@export var max_distance: float = 16.0
@export var follow_offset: Vector3 = Vector3(0.0, 1.8, 0.0)
@export var collision_mask: int = 1 # Collides with Environment_Static
@export var probe_radius: float = 0.25
@export var mouse_sensitivity: float = 0.003
@export var pitch_min_deg: float = -45.0
@export var pitch_max_deg: float = 75.0

var yaw: float = 0.0
var pitch: float = 20.0
var _current_distance: float = 9.0
var _target_transform: Transform3D

func _ready() -> void:
	super._ready()
	_current_distance = distance
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity * (180.0 / PI), pitch_min_deg, pitch_max_deg)
		_update_transform()

func update_virtual_camera(delta: float) -> void:
	_resolve_collision(delta)
	_update_transform()

func _resolve_collision(delta: float) -> void:
	var pivot := _get_pivot_position()
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var desired_cam_dir := rot * Vector3.BACK
	var desired_pos := pivot + desired_cam_dir * distance

	var space_state := get_world_3d().direct_space_state
	if space_state != null:
		var query := PhysicsRayQueryParameters3D.create(pivot, desired_pos, collision_mask)
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_dist: float = pivot.distance_to(hit.position) - probe_radius
			_current_distance = lerpf(_current_distance, clampf(hit_dist, min_distance, max_distance), delta * 20.0)
		else:
			_current_distance = lerpf(_current_distance, distance, delta * 10.0)
	else:
		_current_distance = distance

func _get_pivot_position() -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position + follow_offset
	return global_position + follow_offset

func _update_transform() -> void:
	var pivot := _get_pivot_position()
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var cam_pos := pivot + rot * (Vector3.BACK * _current_distance)
	_target_transform = Transform3D(rot, cam_pos)

func get_desired_global_transform() -> Transform3D:
	return _target_transform
