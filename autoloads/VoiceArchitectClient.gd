extends Node
## VoiceArchitectClient.gd
## Captures Hold-L1 (voice_architect_ptt) audio + 3D camera raycast target coordinates
## and relays live world-building prompts to the Control Plane Whisper endpoint.

signal voice_capture_started(raycast_context: Dictionary)
signal voice_prompt_dispatched(prompt_payload: Dictionary)
signal voice_prompt_response_received(result: int, response_code: int, response_body: Dictionary)

var is_recording: bool = false
var last_raycast_context: Dictionary = {}
var _http_request: HTTPRequest = null

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "VoiceArchitectHTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_request_completed)

func begin_voice_capture(camera: Camera3D) -> Dictionary:
	is_recording = true
	last_raycast_context = sample_camera_raycast(camera)
	voice_capture_started.emit(last_raycast_context)
	return last_raycast_context

func sample_camera_raycast(camera: Camera3D, max_distance: float = 120.0) -> Dictionary:
	if camera == null:
		return {"hit": false, "hit_pos": [0.0, 0.0, 0.0], "target_node": ""}
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z * max_distance)
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "hit_pos": [to.x, to.y, to.z], "target_node": "sky_or_terrain"}
	var pos: Vector3 = result.get("position", Vector3.ZERO)
	var collider: Object = result.get("collider", null)
	var collider_name: String = str((collider as Node).name) if collider is Node else "unknown"
	return {
		"hit": true,
		"hit_pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"target_node": collider_name
	}

func finish_voice_capture(transcribed_text: String) -> Dictionary:
	is_recording = false
	var payload := {
		"realm_id": BootLoader.active_realm_id,
		"transcript": transcribed_text,
		"spatial_anchor": last_raycast_context,
		"timestamp": int(Time.get_unix_time_from_system())
	}
	voice_prompt_dispatched.emit(payload)
	_dispatch_to_server(payload)
	return payload

func _dispatch_to_server(payload: Dictionary) -> void:
	if _http_request == null or not is_inside_tree():
		return
	var base_url: String = AuthManager.server_url.trim_suffix("/")
	var target_url := base_url + "/api/voice-architect"
	var headers := AuthManager.get_auth_headers()
	var json_body := JSON.stringify(payload)
	var err := _http_request.request(target_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_warning("VoiceArchitectClient: HTTP dispatch failed with code %d" % err)

func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_dict: Dictionary = {}
	var text := body.get_string_from_utf8()
	if not text.is_empty():
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			body_dict = parsed
	voice_prompt_response_received.emit(result, response_code, body_dict)
