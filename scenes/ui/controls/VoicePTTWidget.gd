extends Control
## VoicePTTWidget.gd
## On-screen Push-To-Talk widget integrated with VoiceArchitectClient.
## Activates live spatial audio raycast prompt capture on press and dispatches on release.

@onready var ptt_button: Button = $PTTButton
@onready var status_label: Label = $StatusLabel

var is_pressed: bool = false

func _ready() -> void:
	if ptt_button != null:
		ptt_button.button_down.connect(_on_ptt_down)
		ptt_button.button_up.connect(_on_ptt_up)
	
	var vac := _get_voice_architect()
	if vac != null:
		if vac.has_signal("voice_capture_started"):
			vac.voice_capture_started.connect(_on_remote_voice_capture_started)
		if vac.has_signal("voice_prompt_dispatched"):
			vac.voice_prompt_dispatched.connect(_on_remote_voice_capture_ended)

func _get_voice_architect() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/VoiceArchitectClient")
	return null

func _get_input_scheme_manager() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/InputSchemeManager")
	return null

func _trigger_haptic() -> void:
	var ism := _get_input_scheme_manager()
	if ism != null and ism.has_method("get_controls_config"):
		var cfg: Dictionary = ism.get_controls_config()
		if bool(cfg.get("touch_haptic_feedback", true)):
			Input.vibrate_handheld(40)

func _on_ptt_down() -> void:
	is_pressed = true
	_trigger_haptic()
	Input.action_press("voice_architect_ptt")
	var cam: Camera3D = null
	if get_viewport() != null:
		cam = get_viewport().get_camera_3d()
	var vac := _get_voice_architect()
	if vac != null and vac.has_method("begin_voice_capture"):
		vac.begin_voice_capture(cam)
	_set_recording_visual(true)

func _on_ptt_up() -> void:
	if not is_pressed:
		return
	is_pressed = false
	Input.action_release("voice_architect_ptt")
	var vac := _get_voice_architect()
	if vac != null and vac.has_method("finish_voice_capture"):
		vac.finish_voice_capture("Voice PTT mobile touch prompt")
	_set_recording_visual(false)

func _on_remote_voice_capture_started(_ctx: Dictionary) -> void:
	_set_recording_visual(true)

func _on_remote_voice_capture_ended(_payload: Dictionary) -> void:
	_set_recording_visual(false)

func _set_recording_visual(recording: bool) -> void:
	if status_label != null:
		status_label.text = "REC..." if recording else "MIC"
	if ptt_button != null:
		if recording:
			ptt_button.modulate = Color(1.0, 0.35, 0.35, 1.0)
		else:
			ptt_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
