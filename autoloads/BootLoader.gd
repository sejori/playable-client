extends Node
## BootLoader.gd
## Universal Client & Dedicated Server bootstrapper.
## Detects --headless / --server flags, binds default InputMap actions,
## and streams/mounts AST-sandboxed .pck realms via ProjectSettings.load_resource_pack().

signal realm_pack_mounted(realm_id: String, pack_path: String)
signal boot_mode_resolved(mode: String)
signal runtime_config_updated(config: Dictionary)

var is_headless_server: bool = false
var is_sandboxed_pck: bool = true
var active_realm_id: String = ""
var runtime_override_config: Dictionary = {}

func _ready() -> void:
	_setup_default_input_bindings()
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	for arg in cmd_args:
		if arg == "--server" or arg == "--headless":
			is_headless_server = true
		elif arg.begins_with("--realm="):
			active_realm_id = arg.trim_prefix("--realm=")
	if not active_realm_id.is_empty():
		_ensure_realm_sandbox_dir(active_realm_id)
	var mode_str := "HEADLESS_SERVER" if is_headless_server else "UNIVERSAL_CLIENT"
	boot_mode_resolved.emit(mode_str)

func _setup_default_input_bindings() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_back", KEY_S)
	_bind_key("move_back", KEY_DOWN)
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("ability_primary", KEY_SPACE)
	_bind_key("ability_secondary", KEY_E)
	_bind_key("voice_architect_ptt", KEY_V)
	if not InputMap.has_action("toggle_quad_debug"):
		InputMap.add_action("toggle_quad_debug")
	_bind_key("toggle_quad_debug", KEY_Q)

	# Standard Gamepad bindings
	_bind_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_bind_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_bind_joy_button("ability_primary", JOY_BUTTON_A)
	_bind_joy_button("ability_secondary", JOY_BUTTON_X)
	_bind_joy_button("voice_architect_ptt", JOY_BUTTON_LEFT_SHOULDER)

func _bind_key(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	InputMap.action_add_event(action_name, ev)

func _bind_joy_button(action_name: String, button_index: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	InputMap.action_add_event(action_name, ev)

func _bind_joy_axis(action_name: String, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	InputMap.action_add_event(action_name, ev)

func _ensure_realm_sandbox_dir(realm_id: String) -> void:
	var safe_id := realm_id.validate_filename()
	var dir_path := "user://realms/" + safe_id
	DirAccess.make_dir_recursive_absolute(dir_path)

func mount_realm_pck(realm_id: String, pck_virtual_path: String) -> bool:
	if not pck_virtual_path.begins_with("user://realms/"):
		push_error("Security Violation: Refusing to mount .pck outside user://realms/ sandbox.")
		return false
	var loaded := ProjectSettings.load_resource_pack(pck_virtual_path, true)
	if loaded:
		active_realm_id = realm_id
		realm_pack_mounted.emit(realm_id, pck_virtual_path)
	return loaded

func mount_pck_from_base64(realm_id: String, base64_pck: String) -> bool:
	var safe_id := realm_id.validate_filename()
	_ensure_realm_sandbox_dir(safe_id)
	var pck_path := "user://realms/" + safe_id + "/patch.pck"
	var raw_bytes := Marshalls.base64_to_raw(base64_pck)
	if raw_bytes.is_empty():
		return false
	var file := FileAccess.open(pck_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(raw_bytes)
	file.close()
	return mount_realm_pck(safe_id, pck_path)

func apply_runtime_config_json(json_str: String) -> bool:
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	runtime_override_config = parsed
	runtime_config_updated.emit(runtime_override_config)
	return true
