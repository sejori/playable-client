class_name VirtualKillcamCamera3D
extends VirtualCameraBase3D
## VirtualKillcamCamera3D.gd
## Death replay / dynamic killer-tracking camera with dramatic slow dolly.

@export var killer_path: NodePath
@export var victim_path: NodePath
@export var zoom_in_speed: float = 3.5

var killer_node: Node3D = null
var victim_node: Node3D = null
var _progress: float = 0.0

func _ready() -> void:
	super._ready()
	if not killer_path.is_empty():
		killer_node = get_node_or_null(killer_path) as Node3D
	if not victim_path.is_empty():
		victim_node = get_node_or_null(victim_path) as Node3D

func setup_replay(killer: Node3D, victim: Node3D) -> void:
	killer_node = killer
	victim_node = victim
	_progress = 0.0

func update_virtual_camera(delta: float) -> void:
	_progress += delta * zoom_in_speed

func get_desired_global_transform() -> Transform3D:
	var v_pos := global_position
	if victim_node != null and is_instance_valid(victim_node):
		v_pos = victim_node.global_position
	var k_pos := v_pos + Vector3.FORWARD * 5.0
	if killer_node != null and is_instance_valid(killer_node):
		k_pos = killer_node.global_position

	var dir_to_killer := (k_pos - v_pos).normalized()
	if dir_to_killer.length_squared() < 0.001:
		dir_to_killer = Vector3.BACK

	var cam_pos := v_pos - dir_to_killer * 4.0 + Vector3.UP * 2.5
	var look_target := k_pos + Vector3.UP * 1.5

	var forward := (look_target - cam_pos).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	return Transform3D(basis, cam_pos)
