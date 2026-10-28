extends Node
## InputSchemeManager.gd
## Cross-device input scheme and profile orchestrator.
## Auto-detects touch, gamepad, and mouse/keyboard hardware,
## dynamically routes active input profiles, and manages settings persistence.

signal scheme_changed(scheme_name: String)
signal profile_updated(config: Dictionary)

const SETTINGS_PATH: String = "user://settings.json"

const PROFILE_AUTO: String = "auto"
const PROFILE_MOBILE_TOUCH: String = "mobile_touch"
const PROFILE_HANDHELD_HYBRID: String = "handheld_hybrid"
const PROFILE_DESKTOP_KBM: String = "desktop_kbm"
const PROFILE_PURE_GAMEPAD: String = "pure_gamepad"

const DEFAULT_SETTINGS: Dictionary = {
	"controls": {
		"profile_mode": "auto",
		"auto_hide_touch_on_gamepad": true,
		"keep_voice_ptt_on_screen": true,
		"touch_stick_mode": "floating",
		"touch_opacity": 0.85,
		"touch_haptic_feedback": true,
		"camera_touch_sensitivity": 1.0,
		"stick_deadzone": 0.15
	}
}

var settings: Dictionary = {}
var active_scheme: String = PROFILE_DESKTOP_KBM
var last_input_type: String = "kbm" # "touch", "gamepad", "kbm"
var _stick_deadzone: float = 0.15

func _init() -> void:
	load_settings()

func _ready() -> void:
	load_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	
	var os_name := OS.get_name()
	var has_touch := DisplayServer.is_touchscreen_available()
	var joy_count := Input.get_connected_joypads().size()
	
	if os_name in ["iOS", "Android"]:
		last_input_type = "gamepad" if joy_count > 0 else "touch"
	elif os_name == "Linux" and has_touch:
		last_input_type = "gamepad" if joy_count > 0 else "touch"
	else:
		last_input_type = "gamepad" if joy_count > 0 else "kbm"
	
	refresh_active_scheme(true)

func _input(event: InputEvent) -> void:
	var prev_type := last_input_type
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		last_input_type = "touch"
	elif event is InputEventJoypadButton:
		last_input_type = "gamepad"
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > _stick_deadzone:
			last_input_type = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton:
		last_input_type = "kbm"
	
	if last_input_type != prev_type:
		refresh_active_scheme()

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		last_input_type = "gamepad"
	elif Input.get_connected_joypads().is_empty():
		if DisplayServer.is_touchscreen_available():
			last_input_type = "touch"
		else:
			last_input_type = "kbm"
	refresh_active_scheme()

func resolve_profile(os_name: String, has_touch: bool, joypad_count: int, last_input: String = "") -> String:
	var mode: String = get_controls_config().get("profile_mode", PROFILE_AUTO)
	if mode != PROFILE_AUTO:
		return mode

	var keep_ptt: bool = bool(get_controls_config().get("keep_voice_ptt_on_screen", true))
	var auto_hide: bool = bool(get_controls_config().get("auto_hide_touch_on_gamepad", true))

	if os_name in ["iOS", "Android"]:
		if joypad_count > 0 and (last_input == "gamepad" or last_input == ""):
			if keep_ptt:
				return PROFILE_HANDHELD_HYBRID
			elif auto_hide:
				return PROFILE_PURE_GAMEPAD
		return PROFILE_MOBILE_TOUCH

	if os_name == "Linux" and has_touch:
		# Handheld PC / Steam Deck
		if joypad_count > 0 or last_input == "gamepad":
			return PROFILE_HANDHELD_HYBRID
		return PROFILE_MOBILE_TOUCH

	# Desktop platforms (Windows, macOS, desktop Linux)
	if joypad_count > 0 and (last_input == "gamepad" or last_input == ""):
		if has_touch and keep_ptt:
			return PROFILE_HANDHELD_HYBRID
		return PROFILE_PURE_GAMEPAD

	if has_touch and last_input == "touch":
		return PROFILE_MOBILE_TOUCH

	return PROFILE_DESKTOP_KBM

func refresh_active_scheme(force_emit: bool = false) -> void:
	var os_name := OS.get_name()
	var has_touch := DisplayServer.is_touchscreen_available()
	var joy_count := Input.get_connected_joypads().size()
	var resolved := resolve_profile(os_name, has_touch, joy_count, last_input_type)
	if resolved != active_scheme or force_emit:
		active_scheme = resolved
		scheme_changed.emit(active_scheme)

func get_controls_config() -> Dictionary:
	if not settings.has("controls") or typeof(settings["controls"]) != TYPE_DICTIONARY:
		settings["controls"] = DEFAULT_SETTINGS["controls"].duplicate(true)
	return settings["controls"]

func update_controls_config(new_config: Dictionary) -> void:
	var cfg := get_controls_config()
	for k in new_config.keys():
		cfg[k] = new_config[k]
	settings["controls"] = cfg
	_apply_loaded_settings()
	save_settings()
	profile_updated.emit(cfg)
	refresh_active_scheme()

func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		settings = DEFAULT_SETTINGS.duplicate(true)
		save_settings()
		_apply_loaded_settings()
		return settings

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		settings = DEFAULT_SETTINGS.duplicate(true)
		_apply_loaded_settings()
		return settings

	var content := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		settings = DEFAULT_SETTINGS.duplicate(true)
		_apply_loaded_settings()
		return settings

	settings = DEFAULT_SETTINGS.duplicate(true)
	var loaded_dict: Dictionary = parsed
	for section in loaded_dict.keys():
		if typeof(loaded_dict[section]) == TYPE_DICTIONARY:
			if not settings.has(section):
				settings[section] = {}
			for k in loaded_dict[section].keys():
				settings[section][k] = loaded_dict[section][k]
		else:
			settings[section] = loaded_dict[section]

	_apply_loaded_settings()
	return settings

func save_settings(new_settings: Dictionary = {}) -> bool:
	if not new_settings.is_empty():
		for k in new_settings.keys():
			settings[k] = new_settings[k]
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to open %s for writing." % SETTINGS_PATH)
		return false
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	return true

func _apply_loaded_settings() -> void:
	var cfg := get_controls_config()
	if cfg.has("stick_deadzone"):
		_stick_deadzone = float(cfg["stick_deadzone"])

func should_show_touch_controls() -> bool:
	return active_scheme == PROFILE_MOBILE_TOUCH

func should_show_voice_ptt() -> bool:
	if active_scheme == PROFILE_MOBILE_TOUCH:
		return true
	if active_scheme == PROFILE_HANDHELD_HYBRID:
		return bool(get_controls_config().get("keep_voice_ptt_on_screen", true))
	return false
