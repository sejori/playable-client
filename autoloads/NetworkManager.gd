extends Node
## NetworkManager.gd
## ENet UDP (Port 7777+) & WebRTC room joiner with authoritative server guards.

signal room_joined(room_code: String, peer_id: int)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

const DEFAULT_SERVER_PORT: int = 7777
const MAX_CLIENTS: int = 32

var active_room_code: String = ""
var is_authority: bool = false

func start_authoritative_server(port: int = DEFAULT_SERVER_PORT, max_players: int = MAX_CLIENTS, room_code: String = "TEST-4821") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active_room_code = room_code
	is_authority = true
	multiplayer.peer_connected.connect(func(id: int): player_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): player_disconnected.emit(id))
	return OK

func join_room_by_endpoint(host: String, port: int, room_code: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active_room_code = room_code
	is_authority = false
	room_joined.emit(room_code, multiplayer.get_unique_id())
	return OK

func can_execute_authoritative_mutation() -> bool:
	return is_authority or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
