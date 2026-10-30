class_name Inventory28Slot
extends Node
## Inventory28Slot.gd
## Classic 28-slot OSRS-style grid inventory manager.

signal item_added(slot_idx: int, item_id: String, count: int)
signal item_removed(slot_idx: int, item_id: String)
signal inventory_full()

const MAX_SLOTS: int = 28
var slots: Array[Dictionary] = []

func _ready() -> void:
	clear()

func clear() -> void:
	slots.clear()
	for i in range(MAX_SLOTS):
		slots.append({"id": "", "count": 0})

func add_item(item_id: String, count: int = 1) -> bool:
	# 1. Search for existing stack if stackable
	for i in range(MAX_SLOTS):
		if slots[i]["id"] == item_id:
			slots[i]["count"] += count
			item_added.emit(i, item_id, slots[i]["count"])
			return true

	# 2. Search for first empty slot
	for i in range(MAX_SLOTS):
		if slots[i]["id"] == "":
			slots[i]["id"] = item_id
			slots[i]["count"] = count
			item_added.emit(i, item_id, count)
			return true

	inventory_full.emit()
	return false

func remove_item(slot_idx: int, count: int = 1) -> bool:
	if slot_idx < 0 or slot_idx >= MAX_SLOTS:
		return false
	if slots[slot_idx]["id"] == "":
		return false

	var id := str(slots[slot_idx]["id"])
	var current: int = int(slots[slot_idx]["count"])
	if current <= count:
		slots[slot_idx]["id"] = ""
		slots[slot_idx]["count"] = 0
		item_removed.emit(slot_idx, id)
	else:
		slots[slot_idx]["count"] = current - count
	return true

func count_item(item_id: String) -> int:
	var total: int = 0
	for slot in slots:
		if slot["id"] == item_id:
			total += int(slot["count"])
	return total
