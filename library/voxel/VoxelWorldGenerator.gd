class_name VoxelWorldGenerator
extends Node3D
## VoxelWorldGenerator.gd
## Procedural 3D voxel terrain and cave generator using FastNoiseLite.
## Generates discrete 1m block coordinates and populates stone, dirt, and cave cavities.

@export var chunk_size_x: int = 16
@export var chunk_size_y: int = 24
@export var chunk_size_z: int = 16
@export var surface_level: int = 12
@export var noise_frequency: float = 0.05
@export var cave_threshold: float = 0.42

var noise: FastNoiseLite = null
var voxel_grid: Dictionary = {} # Vector3i -> int (block_type)

const BLOCK_AIR: int = 0
const BLOCK_DIRT: int = 1
const BLOCK_STONE: int = 2
const BLOCK_WOOD: int = 3
const BLOCK_LEAVES: int = 4
const BLOCK_WATER: int = 5

func _init() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_frequency

func generate_chunk(chunk_origin: Vector3i = Vector3i.ZERO) -> Dictionary:
	voxel_grid.clear()
	for x in range(chunk_size_x):
		for z in range(chunk_size_z):
			var world_x := chunk_origin.x + x
			var world_z := chunk_origin.z + z
			var height_sample := noise.get_noise_2d(float(world_x), float(world_z))
			var col_height := surface_level + int(height_sample * 6.0)

			for y in range(chunk_size_y):
				var world_y := chunk_origin.y + y
				var coord := Vector3i(world_x, world_y, world_z)

				if world_y > col_height:
					continue

				# 3D cave carving sample
				var cave_sample := noise.get_noise_3d(float(world_x) * 1.5, float(world_y) * 1.5, float(world_z) * 1.5)
				if absf(cave_sample) < cave_threshold and world_y < col_height - 2 and world_y > 3:
					# Cave air
					continue

				if world_y == col_height:
					voxel_grid[coord] = BLOCK_DIRT
				elif world_y > col_height - 3:
					voxel_grid[coord] = BLOCK_DIRT
				else:
					voxel_grid[coord] = BLOCK_STONE

	return voxel_grid

func get_block_at(coord: Vector3i) -> int:
	return voxel_grid.get(coord, BLOCK_AIR)

func set_block_at(coord: Vector3i, block_type: int) -> void:
	if block_type == BLOCK_AIR:
		voxel_grid.erase(coord)
	else:
		voxel_grid[coord] = block_type
