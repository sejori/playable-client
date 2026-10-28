extends CanvasLayer
## TouchControlsOverlay.gd
## Root CanvasLayer coordinating on-screen touch and hybrid controls across devices.
## Adapts widget visibility and opacity according to InputSchemeManager state.

signal camera_look_requested(relative: Vector2)

@onready var look_zone: Control = $TouchLookZone
@onready var thumbstick: Control = $VirtualThumbstick
@onready var action_cluster: Control = $ActionCluster
@onready var voice_ptt: Control = $VoicePTTWidget

func _ready() -> void:
	layer = 10
	if look_zone != null and look_zone.has_signal("camera_look_dragged"):
		look_zone.camera_look_dragged.connect(_on_camera_look_dragged)
	
	var ism := _get_input_scheme_manager()
	if ism != null:
		if ism.has_signal("scheme_changed"):
			ism.scheme_changed.connect(_on_scheme_changed)
		if ism.has_signal("profile_updated"):
			ism.profile_updated.connect(_on_profile_updated)
		_apply_scheme(str(ism.get("active_scheme")))
		if ism.has_method("get_controls_config"):
			_apply_config(ism.get_controls_config())
	else:
		_apply_scheme("desktop_kbm")

func _get_input_scheme_manager() -> Node:
	return get_node_or_null("/root/InputSchemeManager")

func _on_camera_look_dragged(relative: Vector2) -> void:
	camera_look_requested.emit(relative)

func _on_scheme_changed(new_scheme: String) -> void:
	_apply_scheme(new_scheme)

func _on_profile_updated(config: Dictionary) -> void:
	_apply_config(config)
	var ism := _get_input_scheme_manager()
	if ism != null:
		_apply_scheme(str(ism.get("active_scheme")))

func _apply_scheme(scheme: String) -> void:
	match scheme:
		"mobile_touch":
			visible = true
			if thumbstick != null:
				thumbstick.visible = true
			if look_zone != null:
				look_zone.visible = true
			if action_cluster != null:
				action_cluster.visible = true
			if voice_ptt != null:
				voice_ptt.visible = true
		"handheld_hybrid":
			visible = true
			if thumbstick != null:
				thumbstick.visible = false
			if look_zone != null:
				look_zone.visible = false
			if action_cluster != null:
				action_cluster.visible = false
			if voice_ptt != null:
				var show_ptt: bool = true
				var ism := _get_input_scheme_manager()
				if ism != null and ism.has_method("should_show_voice_ptt"):
					show_ptt = ism.should_show_voice_ptt()
				voice_ptt.visible = show_ptt
		"desktop_kbm", "pure_gamepad":
			visible = false
		_:
			visible = false

func _apply_config(cfg: Dictionary) -> void:
	var opacity: float = float(cfg.get("touch_opacity", 0.85))
	var root_ctrl := get_node_or_null("ControlRoot") as Control
	if root_ctrl != null:
		root_ctrl.modulate.a = opacity
	else:
		for child in get_children():
			if child is CanvasItem:
				child.modulate.a = opacity

	if thumbstick != null and cfg.has("touch_stick_mode"):
		thumbstick.set("stick_mode", str(cfg["touch_stick_mode"]))
	if look_zone != null and cfg.has("camera_touch_sensitivity"):
		look_zone.set("sensitivity", float(cfg["camera_touch_sensitivity"]))
