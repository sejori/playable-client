class_name VirtualCinematicCamera3D
extends VirtualCameraBase3D
## VirtualCinematicCamera3D.gd
## Keyframe/focus tracking camera for boss intros, cutscenes, and dramatic reveals.

@export var look_at_target_path: NodePath
@export var tracking_speed: float = 6.0
@export var roll_degrees: float = 0.0

var look_at_node: Node3D = null
var _current_look_at: Vector3 = Vector3.ZERO
var _has_look_at: bool = false

func _ready() -> void:
	super._ready()
	if not look_at_target_path.is_empty():
		look_at_node = get_node_or_null(look_at_target_path) as Node3D

func set_look_at_node(node: Node3D) -> void:
	look_at_node = node

func update_virtual_camera(delta: float) -> void:
	var target_focus: Vector3 = global_position + (-global_transform.basis.z * 10.0)
	if look_at_node != null and is_instance_valid(look_at_node):
		target_focus = look_at_node.global_position
	elif target != null and is_instance_valid(target):
		target_focus = target.global_position

	if not _has_look_at:
		_current_look_at = target_focus
		_has_look_at = true
	else:
		_current_look_at = _current_look_at.lerp(target_focus, clampf(delta * tracking_speed, 0.0, 1.0))

func get_desired_global_transform() -> Transform3D:
	var cam_pos := global_position
	var look_target := _current_look_at if _has_look_at else (cam_pos + Vector3.FORWARD)
	var forward := (look_target - cam_pos).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	if absf(roll_degrees) > 0.01:
		basis = basis.rotated(forward, deg_to_rad(roll_degrees))
	return Transform3D(basis, cam_pos)
