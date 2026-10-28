extends Control
## ActionCluster.gd
## On-screen action button cluster for primary and secondary elemental abilities.
## Dispatches ability_primary and ability_secondary actions to the Godot InputMap.

@onready var primary_button: Button = $PrimaryButton
@onready var secondary_button: Button = $SecondaryButton

func _ready() -> void:
	if primary_button != null:
		primary_button.button_down.connect(_on_primary_down)
		primary_button.button_up.connect(_on_primary_up)
	if secondary_button != null:
		secondary_button.button_down.connect(_on_secondary_down)
		secondary_button.button_up.connect(_on_secondary_up)

func _get_input_scheme_manager() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/InputSchemeManager")
	return null

func _trigger_haptic() -> void:
	var ism := _get_input_scheme_manager()
	if ism != null and ism.has_method("get_controls_config"):
		var cfg: Dictionary = ism.get_controls_config()
		if bool(cfg.get("touch_haptic_feedback", true)):
			Input.vibrate_handheld(35)

func _on_primary_down() -> void:
	_trigger_haptic()
	Input.action_press("ability_primary")

func _on_primary_up() -> void:
	Input.action_release("ability_primary")

func _on_secondary_down() -> void:
	_trigger_haptic()
	Input.action_press("ability_secondary")

func _on_secondary_up() -> void:
	Input.action_release("ability_secondary")
