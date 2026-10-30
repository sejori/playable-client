class_name HexGridMath
extends RefCounted
## HexGridMath.gd
## Axial coordinate math library for pointy-topped Hex grids.
## Formulas:
## Axial: (q, r), Cube: (q, r, s) where q + r + s = 0.
## World X = radius * sqrt(3) * (q + r / 2.0)
## World Z = radius * 3.0 / 2.0 * r

const SQRT_3: float = 1.732050807568877

static func axial_to_world(q: int, r: int, radius: float = 2.0) -> Vector3:
	var x: float = radius * SQRT_3 * (float(q) + float(r) * 0.5)
	var z: float = radius * 1.5 * float(r)
	return Vector3(x, 0.0, z)

static func world_to_axial(world_pos: Vector3, radius: float = 2.0) -> Vector2i:
	var x := world_pos.x
	var z := world_pos.z
	var r_radius := radius if radius > 0.0 else 1.0

	var q_float := ((SQRT_3 / 3.0) * x - (1.0 / 3.0) * z) / r_radius
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

	return Vector2i(q_round, r_round)

static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := absi(a.x - b.x)
	var dr := absi(a.y - b.y)
	var ds := absi((-a.x - a.y) - (-b.x - b.y))
	return maxi(dq, maxi(dr, ds))

static func get_neighbors(hex: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(hex.x + 1, hex.y),
		Vector2i(hex.x + 1, hex.y - 1),
		Vector2i(hex.x, hex.y - 1),
		Vector2i(hex.x - 1, hex.y),
		Vector2i(hex.x - 1, hex.y + 1),
		Vector2i(hex.x, hex.y + 1)
	]
