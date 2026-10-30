class_name CameraHost3D
extends Node3D
## CameraHost3D.gd
## Universal Camera Substrate (Layer 1) - Priority-based virtual camera host with smooth tweening.
## Manages the active Camera3D and smoothly blends position, rotation, and FOV toward the
## highest-priority active VirtualCameraBase3D node.

signal active_camera_changed(old_cam: VirtualCameraBase3D, new_cam: VirtualCameraBase3D)

@export var camera_path: NodePath
@export var smooth_follow_speed: float = 12.0
@export var default_fov: float = 75.0

var primary_camera: Camera3D = null
var active_vcam: VirtualCameraBase3D = null
var _virtual_cameras: Array[VirtualCameraBase3D] = []

# Blending state
var _is_blending: bool = false
var _blend_timer: float = 0.0
var _blend_duration: float = 0.0
var _blend_start_transform: Transform3D
var _blend_start_fov: float = 75.0
var _blend_trans_type: Tween.TransitionType = Tween.TRANS_SINE
var _blend_ease_type: Tween.EaseType = Tween.EASE_IN_OUT

func _ready() -> void:
	add_to_group("camera_hosts")
	_ensure_primary_camera()
	_collect_scene_vcams()
	refresh_active_vcam(true)

func _ensure_primary_camera() -> void:
	if not camera_path.is_empty():
		primary_camera = get_node_or_null(camera_path) as Camera3D
	if primary_camera == null:
		primary_camera = get_node_or_null("Camera3D") as Camera3D
	if primary_camera == null:
		for child in get_children():
			if child is Camera3D:
				primary_camera = child
				break
	if primary_camera == null:
		primary_camera = Camera3D.new()
		primary_camera.name = "Camera3D"
		primary_camera.current = true
		primary_camera.fov = default_fov
		add_child(primary_camera)
	else:
		primary_camera.current = true

func _collect_scene_vcams() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("virtual_cameras"):
		if node is VirtualCameraBase3D and not _virtual_cameras.has(node):
			register_vcam(node)

func register_vcam(vcam: VirtualCameraBase3D) -> void:
	if not _virtual_cameras.has(vcam):
		_virtual_cameras.append(vcam)
		vcam.host = self
		refresh_active_vcam()

func unregister_vcam(vcam: VirtualCameraBase3D) -> void:
	_virtual_cameras.erase(vcam)
	if active_vcam == vcam:
		active_vcam = null
		refresh_active_vcam()

func on_vcam_updated(_vcam: VirtualCameraBase3D) -> void:
	refresh_active_vcam()

func refresh_active_vcam(instant_snap: bool = false) -> void:
	var highest: VirtualCameraBase3D = null
	var highest_priority: int = -999999

	for vcam in _virtual_cameras:
		if is_instance_valid(vcam) and vcam.is_active:
			if vcam.priority > highest_priority:
				highest_priority = vcam.priority
				highest = vcam

	if highest != active_vcam:
		var prev := active_vcam
		active_vcam = highest
		active_camera_changed.emit(prev, active_vcam)

		if active_vcam != null and primary_camera != null:
			if instant_snap or active_vcam.transition_time <= 0.0:
				_is_blending = false
				primary_camera.global_transform = active_vcam.get_desired_global_transform()
				primary_camera.fov = active_vcam.get_desired_fov()
			else:
				_is_blending = true
				_blend_timer = 0.0
				_blend_duration = maxf(0.01, active_vcam.transition_time)
				_blend_start_transform = primary_camera.global_transform
				_blend_start_fov = primary_camera.fov
				_blend_trans_type = active_vcam.transition_type
				_blend_ease_type = active_vcam.ease_type

func _process(delta: float) -> void:
	if primary_camera == null:
		return

	if active_vcam == null or not is_instance_valid(active_vcam):
		refresh_active_vcam()
		if active_vcam == null:
			return

	active_vcam.update_virtual_camera(delta)
	var target_transform := active_vcam.get_desired_global_transform()
	var target_fov := active_vcam.get_desired_fov()

	if _is_blending:
		_blend_timer += delta
		var t := clampf(_blend_timer / _blend_duration, 0.0, 1.0)
		var factor := Tween.interpolate_value(0.0, 1.0, _blend_timer, _blend_duration, _blend_trans_type, _blend_ease_type) as float
		factor = clampf(factor, 0.0, 1.0)

		# Slerp rotation and lerp position
		var cur_origin := _blend_start_transform.origin.lerp(target_transform.origin, factor)
		var cur_basis := _blend_start_transform.basis.slerp(target_transform.basis, factor)
		primary_camera.global_transform = Transform3D(cur_basis, cur_origin)
		primary_camera.fov = lerpf(_blend_start_fov, target_fov, factor)

		if t >= 1.0:
			_is_blending = false
	else:
		if smooth_follow_speed > 0.0:
			var weight := clampf(smooth_follow_speed * delta, 0.0, 1.0)
			var cur_origin := primary_camera.global_transform.origin.lerp(target_transform.origin, weight)
			var cur_basis := primary_camera.global_transform.basis.slerp(target_transform.basis, weight)
			primary_camera.global_transform = Transform3D(cur_basis, cur_origin)
			primary_camera.fov = lerpf(primary_camera.fov, target_fov, weight)
		else:
			primary_camera.global_transform = target_transform
			primary_camera.fov = target_fov

func get_active_vcam() -> VirtualCameraBase3D:
	return active_vcam

func get_camera_3d() -> Camera3D:
	return primary_camera
