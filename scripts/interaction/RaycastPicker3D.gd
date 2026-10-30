class_name RaycastPicker3D
extends Node3D
## RaycastPicker3D.gd
## Universal Spatial Raycaster (Layer 3) converting screen coordinates or center-screen reticles
## into genre-specific spatial events:
## - Voxel break/place integer coordinates
## - Axial Hex (Q, R) coordinates for 4X tabletop
## - Hitscan projectile raycasts against Layer 3 (Enemy_Hitbox)
## - Interactable / resource targeting against Layer 4 (Interactable_Resource)

signal voxel_targeted(break_coord: Vector3i, place_coord: Vector3i, normal: Vector3)
signal hex_targeted(q: int, r: int, world_pos: Vector3)
signal hitscan_hit(collider: Object, hit_pos: Vector3, normal: Vector3)
signal hitscan_miss(ray_end: Vector3)
signal interactable_hovered(collider: Object, hit_pos: Vector3)

@export var max_ray_distance: float = 100.0
@export var voxel_reach_distance: float = 6.0
@export var hex_tile_radius: float = 2.0
@export var default_camera_path: NodePath
@export var crosshair_center_mode: bool = false # True for FPS/Voxel, False for Mouse-point (4X, RTS, Sandbox)

var _camera: Camera3D = null

func _ready() -> void:
	if not default_camera_path.is_empty():
		_camera = get_node_or_null(default_camera_path) as Camera3D

func get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	var vp := get_viewport()
	if vp != null:
		return vp.get_camera_3d()
	return null

func cast_ray_from_screen(screen_pos: Vector2, collision_mask: int = 1) -> Dictionary:
	var cam := get_camera()
	if cam == null:
		return {}

	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var to := from + dir * max_ray_distance

	var space := get_world_3d().direct_space_state
	if space == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	return space.intersect_ray(query)

func cast_ray_center(collision_mask: int = 1) -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {}
	var center := vp.get_visible_rect().size * 0.5
	return cast_ray_from_screen(center, collision_mask)

## Voxel Survival Resolver: converts hit pos & normal to integer break/place coords
func resolve_voxel_coords(hit_pos: Vector3, normal: Vector3) -> Dictionary:
	var break_coord := Vector3i(
		int(floor(hit_pos.x - normal.x * 0.5)),
		int(floor(hit_pos.y - normal.y * 0.5)),
		int(floor(hit_pos.z - normal.z * 0.5))
	)
	var place_coord := Vector3i(
		int(floor(hit_pos.x + normal.x * 0.5)),
		int(floor(hit_pos.y + normal.y * 0.5)),
		int(floor(hit_pos.z + normal.z * 0.5))
	)
	voxel_targeted.emit(break_coord, place_coord, normal)
	return {
		"break_coord": break_coord,
		"place_coord": place_coord,
		"normal": normal
	}

## 4X Strategy & Tabletop Resolver: converts world (X, Z) to axial Hex (Q, R)
## Formula: Q = (sqrt(3)/3 * X - 1/3 * Z) / radius, R = (2/3 * Z) / radius
func resolve_hex_coords(world_pos: Vector3) -> Vector2i:
	var x := world_pos.x
	var z := world_pos.z
	var r_radius := hex_tile_radius if hex_tile_radius > 0.0 else 1.0

	var q_float := ((sqrt(3.0) / 3.0) * x - (1.0 / 3.0) * z) / r_radius
	var r_float := ((2.0 / 3.0) * z) / r_radius
	var s_float := -q_float - r_float

	var q_round := int(round(q_float))
	var r_round := int(round(r_float))
	var s_round := int(round(s_float))

	var q_diff := absf(float(q_round) - q_float)
	var r_diff := absf(float(r_round) - r_float)
	var s_diff := absf(float(s_round) - s_float)

	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round

	hex_targeted.emit(q_round, r_round, world_pos)
	return Vector2i(q_round, r_round)

## Arena FPS Resolver: Hitscan raycast against Layer 3 (Enemy_Hitbox)
func fire_hitscan(damage: float = 25.0, collision_mask: int = 1 | 3) -> Dictionary:
	var hit := cast_ray_center(collision_mask)
	if not hit.is_empty():
		var collider: Object = hit.collider
		var pos: Vector3 = hit.position
		var norm: Vector3 = hit.normal
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage, pos, norm)
		hitscan_hit.emit(collider, pos, norm)
		return hit
	else:
		var cam := get_camera()
		var ray_end := (cam.global_position + (-cam.global_transform.basis.z * max_ray_distance)) if cam != null else Vector3.ZERO
		hitscan_miss.emit(ray_end)
		return {}

## Tick Sandbox & Action-RPG Resolver: Detects Layer 4 (Interactable_Resource)
func query_interactable(screen_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var hit: Dictionary
	if crosshair_center_mode or screen_pos == Vector2.ZERO:
		hit = cast_ray_center(4) # Layer 4
	else:
		hit = cast_ray_from_screen(screen_pos, 4)

	if not hit.is_empty():
		interactable_hovered.emit(hit.collider, hit.position)
	return hit
