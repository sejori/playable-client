extends Node
## AuthManager.gd
## Client Authentication & Credential Subsystem.
## Supports CLI arguments (--auth-token=<jwt>, --api-key=<key>, --server-url=<url>),
## session persistence to user://auth_session.json, Bearer & API-Key headers, and mock token fallbacks.

signal auth_state_changed(is_authenticated: bool, mode: String)
signal auth_error(error_message: String)

const AUTH_SESSION_PATH: String = "user://auth_session.json"
const DEFAULT_SERVER_URL: String = "https://playable-server-yy32pk5s3q-nw.a.run.app"
const MOCK_FALLBACK_TOKEN: String = "mock_client_guest@playable.local"

var active_session_token: String = ""
var active_api_key: String = ""
var server_url: String = DEFAULT_SERVER_URL

func _ready() -> void:
	# First try loading persistent session
	load_session()
	
	# CLI arguments take precedence over saved session
	_parse_cli_arguments()
	
	var mode := "ANONYMOUS_MOCK"
	if not active_session_token.is_empty():
		mode = "JWT_BEARER"
	elif not active_api_key.is_empty():
		mode = "API_KEY"
	
	auth_state_changed.emit(is_authenticated(), mode)

func _parse_cli_arguments() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	var has_cli_creds: bool = false
	
	for arg in all_args:
		if arg.begins_with("--auth-token="):
			active_session_token = arg.trim_prefix("--auth-token=").strip_edges()
			has_cli_creds = true
		elif arg.begins_with("--api-key="):
			active_api_key = arg.trim_prefix("--api-key=").strip_edges()
			has_cli_creds = true
		elif arg.begins_with("--server-url="):
			server_url = arg.trim_prefix("--server-url=").strip_edges()
			has_cli_creds = true
		elif arg.begins_with("--server="):
			server_url = arg.trim_prefix("--server=").strip_edges()
			has_cli_creds = true

	if has_cli_creds:
		save_session()

func get_auth_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not active_session_token.is_empty():
		headers.append("Authorization: Bearer " + active_session_token)
	elif not active_api_key.is_empty():
		headers.append("X-Playable-Key: " + active_api_key)
	else:
		# In test / dev environments, use deterministic mock token
		headers.append("Authorization: Bearer " + MOCK_FALLBACK_TOKEN)
	return headers

func is_authenticated() -> bool:
	return not active_session_token.is_empty() or not active_api_key.is_empty()

func set_session(token: String, persist: bool = true) -> void:
	active_session_token = token
	if persist:
		save_session()
	auth_state_changed.emit(is_authenticated(), "JWT_BEARER")

func set_api_key(key: String, persist: bool = true) -> void:
	active_api_key = key
	if persist:
		save_session()
	auth_state_changed.emit(is_authenticated(), "API_KEY")

func clear_session() -> void:
	active_session_token = ""
	active_api_key = ""
	if FileAccess.file_exists(AUTH_SESSION_PATH):
		DirAccess.remove_absolute(AUTH_SESSION_PATH)
	auth_state_changed.emit(false, "ANONYMOUS_MOCK")

func save_session() -> bool:
	var session_data := {
		"active_session_token": active_session_token,
		"active_api_key": active_api_key,
		"server_url": server_url,
		"updated_at": int(Time.get_unix_time_from_system())
	}
	var file := FileAccess.open(AUTH_SESSION_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to open auth session file for writing: " + AUTH_SESSION_PATH)
		return false
	file.store_string(JSON.stringify(session_data, "\t"))
	file.close()
	return true

func load_session() -> bool:
	if not FileAccess.file_exists(AUTH_SESSION_PATH):
		return false
	var file := FileAccess.open(AUTH_SESSION_PATH, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if data.has("active_session_token"):
		active_session_token = str(data["active_session_token"])
	if data.has("active_api_key"):
		active_api_key = str(data["active_api_key"])
	if data.has("server_url") and not str(data["server_url"]).is_empty():
		server_url = str(data["server_url"])
	return true
