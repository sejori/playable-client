class_name TickServer
extends Node
## TickServer.gd
## Deterministic 600ms server tick loop orchestrator for OSRS-style sandbox progression.
## Emits tick(tick_id) every 0.6s and coordinates world harvesting, combat cycles, and movement.

signal tick(tick_id: int)

@export var tick_rate_sec: float = 0.6
@export var auto_start: bool = true

var current_tick: int = 0
var _timer: float = 0.0

func _process(delta: float) -> void:
	if not auto_start:
		return
	_timer += delta
	while _timer >= tick_rate_sec:
		_timer -= tick_rate_sec
		current_tick += 1
		tick.emit(current_tick)

func reset() -> void:
	current_tick = 0
	_timer = 0.0
