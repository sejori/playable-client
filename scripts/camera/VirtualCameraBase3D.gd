class_name VirtualCameraBase3D
extends Node3D
## VirtualCameraBase3D.gd
## Base class for composable virtual cameras in the Universal Camera Substrate (Layer 1).
## Managed and blended by CameraHost3D based on priority.

signal camera_activated()
signal camera_deactivated()

@export var priority: int = 0:
	set(value):
		priority = value
		_notify_host()
@export var fov: float = 75.0
@export var transition_time: float = 0.5
@export var transition_type: Tween.TransitionType = Tween.TRANS_SINE
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var target_path: NodePath
@export var is_active: bool = true:
	set(value):
		var changed := (is_active != value)
		is_active = value
		if changed:
			if is_active:
				camera_activated.emit()
			else:
				camera_deactivated.emit()
			_notify_host()

var _is_discovering: bool = false
var target: Node3D = null:
	get:
		if not _is_discovering and (target == null or not is_instance_valid(target)):
			_auto_discover_target()
		return target
	set(value):
		target = value
var host: Node = null

func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	if target == null:
		_auto_discover_target()
	add_to_group("virtual_cameras")
	_find_and_register_host()
	if target == null:
		call_deferred("_auto_discover_target")

func _auto_discover_target() -> void:
	if _is_discovering:
		return
	_is_discovering = true

	if not target_path.is_empty():
		var node := get_node_or_null(target_path) as Node3D
		if node != null and is_instance_valid(node):
			target = node
			_is_discovering = false
			return

	var tree := get_tree()
	if tree == null:
		_is_discovering = false
		return

	# 1. Look in group "player_character"
	var group_nodes := tree.get_nodes_in_group("player_character")
	for node in group_nodes:
		if node is Node3D and is_instance_valid(node):
			target = node as Node3D
			_is_discovering = false
			return

	# 2. Look for "PlayerCharacter" node in scene hierarchy
	var search_roots: Array[Node] = []
	if tree.current_scene != null:
		search_roots.append(tree.current_scene)
	if get_parent() != null and not search_roots.has(get_parent()):
		search_roots.append(get_parent())
	if tree.root != null and not search_roots.has(tree.root):
		search_roots.append(tree.root)

	for s_root in search_roots:
		var found := s_root.find_child("PlayerCharacter", true, false)
		if found is Node3D and is_instance_valid(found):
			target = found as Node3D
			_is_discovering = false
			return

	_is_discovering = false

func _find_and_register_host() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hosts := tree.get_nodes_in_group("camera_hosts")
	if not hosts.is_empty():
		host = hosts[0]
		if host.has_method("register_vcam"):
			host.call("register_vcam", self)

func _exit_tree() -> void:
	if host != null and host.has_method("unregister_vcam"):
		host.call("unregister_vcam", self)

func _notify_host() -> void:
	if host != null and host.has_method("on_vcam_updated"):
		host.call("on_vcam_updated", self)

func set_target(new_target: Node3D) -> void:
	target = new_target

func update_virtual_camera(_delta: float) -> void:
	pass

func get_desired_global_transform() -> Transform3D:
	return global_transform

func get_desired_fov() -> float:
	return fov
