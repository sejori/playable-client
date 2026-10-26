extends RefCounted
class_name ElementalAbility
## elemental_ability.gd
## Forge GAS-compatible elemental combat skills (metal_shield, earth_lance).

var ability_id: String
var chi_cost: float
var cooldown_sec: float
var base_damage: float
var requires_metal_source: bool

func _init(p_id: String, p_cost: float, p_cooldown: float, p_damage: float, p_requires_metal: bool = false) -> void:
	ability_id = p_id
	chi_cost = p_cost
	cooldown_sec = p_cooldown
	base_damage = p_damage
	requires_metal_source = p_requires_metal

func can_activate(current_chi: float, has_metal_nearby: bool) -> bool:
	if current_chi < chi_cost:
		return false
	if requires_metal_source and not has_metal_nearby:
		return false
	return true
