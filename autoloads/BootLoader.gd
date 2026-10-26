extends Node
## BootLoader.gd
## Universal Client & Dedicated Server bootstrapper.
## Detects --headless / --server flags and streams/mounts AST-sandboxed .pck realms.

signal realm_pack_mounted(realm_id: String, pack_path: String)
signal boot_mode_resolved(mode: String)

var is_headless_server: bool = false
var is_sandboxed_pck: bool = true
var active_realm_id: String = "default_prison_rig"

func _ready() -> void:
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	for arg in cmd_args:
		if arg == "--server" or arg == "--headless":
			is_headless_server = true
		elif arg.begins_with("--realm="):
			active_realm_id = arg.trim_prefix("--realm=")
	_ensure_realm_sandbox_dir(active_realm_id)
	var mode_str := "HEADLESS_SERVER" if is_headless_server else "UNIVERSAL_CLIENT"
	boot_mode_resolved.emit(mode_str)

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
