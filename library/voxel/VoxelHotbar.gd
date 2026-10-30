class_name VoxelHotbar
extends Node
## VoxelHotbar.gd
## 9-slot Voxel Hotbar inventory selector.

signal active_slot_changed(slot_index: int, block_id: String)

@export var selected_slot: int = 0
var slots: Array[String] = [
	"voxel_dirt",
	"voxel_stone",
	"voxel_wood",
	"voxel_leaves",
	"voxel_water",
	"", "", "", ""
]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var code: int = event.keycode
		if code >= KEY_1 and code <= KEY_9:
			select_slot(code - KEY_1)

func select_slot(index: int) -> void:
	if index >= 0 and index < 9:
		selected_slot = index
		active_slot_changed.emit(selected_slot, slots[selected_slot])

func get_active_block_id() -> String:
	return slots[selected_slot]
