class_name SceneReactiveOverlay
extends CanvasLayer
## SceneReactiveOverlay.gd
## Universal Trait-Driven Reactive UI & Dialogue Balloon Overlay (Phase 4).
## Dynamically binds encounter boss bars, mode pills, trait telemetry,
## 3D billboard nameplates, and native .dialogue balloon overlays
## according to active scene traits and entities.

const DEFAULT_DIALOGUE_PATH: String = "res://dialogues/prison_break.dialogue"
const GDD_DESIGN_PATH: String = "res://specs/gdd_design.json"

# GDD design cached values
var _gdd_boss_name: String = ""
var _gdd_boss_max_hp: float = 2400.0
var _gdd_zone_title: String = ""
var _gdd_dialogue_preview: String = ""

# Dialogue parsing cache: file_path -> { node_title -> { "title": String, "speaker": String, "text": String, "choices": Array } }
var _dialogue_cache: Dictionary = {}
var _active_dialogue_node_key: String = ""
var _current_line_text: String = ""
var _typewriter_progress: float = 0.0

# Timers
var _elapsed_time: float = 0.0
var _scan_nameplates_timer: float = 0.0

# UI Controls
var _root_control: Control = null

# Top Header
var _top_header_panel: PanelContainer = null
var _boss_container: VBoxContainer = null
var _boss_title_label: Label = null
var _boss_hp_bar: ProgressBar = null
var _boss_hp_label: Label = null
var _mode_pill_container: PanelContainer = null
var _mode_pill_label: Label = null

# Telemetry
var _telemetry_panel: PanelContainer = null
var _player_hp_bar: ProgressBar = null
var _player_hp_label: Label = null
var _score_row: Label = null
var _harvest_row: Label = null
var _turn_row: Label = null
var _voxel_row: Label = null
var _hostiles_row: Label = null

# Dialogue Balloon
var _dialogue_balloon_panel: PanelContainer = null
var _speaker_label: Label = null
var _dialogue_text_label: Label = null
var _choice_label: Label = null

func _init() -> void:
	layer = 10

func _ready() -> void:
	layer = 10
	_load_gdd_design()
	_load_and_cache_dialogue(DEFAULT_DIALOGUE_PATH)
	_build_ui()
	_ensure_world_nameplates()

# -----------------------------------------------------------------------------
# UI Construction
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "OverlayRoot"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	_build_top_header()
	_build_telemetry_panel()
	_build_dialogue_balloon()

func _build_top_header() -> void:
	_top_header_panel = PanelContainer.new()
	_top_header_panel.name = "TopHeaderPanel"
	_top_header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_header_panel.anchor_left = 0.5
	_top_header_panel.anchor_right = 0.5
	_top_header_panel.anchor_top = 0.0
	_top_header_panel.anchor_bottom = 0.0
	_top_header_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top_header_panel.grow_vertical = Control.GROW_DIRECTION_END
	_top_header_panel.offset_left = -190.0
	_top_header_panel.offset_right = 190.0
	_top_header_panel.offset_top = 16.0
	_top_header_panel.custom_minimum_size = Vector2(380, 54)

	var header_style := _create_panel_style(
		Color(0.08, 0.10, 0.15, 0.90),
		Color(0.30, 0.40, 0.55, 0.75),
		8,
		1
	)
	_top_header_panel.add_theme_stylebox_override("panel", header_style)
	_root_control.add_child(_top_header_panel)

	# 1. Boss Container
	_boss_container = VBoxContainer.new()
	_boss_container.name = "BossContainer"
	_boss_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_container.add_theme_constant_override("separation", 3)
	_top_header_panel.add_child(_boss_container)

	_boss_title_label = Label.new()
	_boss_title_label.name = "BossTitleLabel"
	_boss_title_label.text = "ENCOUNTER BOSS"
	_boss_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_title_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.22))
	_boss_title_label.add_theme_font_size_override("font_size", 13)
	_boss_container.add_child(_boss_title_label)

	var bar_margin := MarginContainer.new()
	bar_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_container.add_child(bar_margin)

	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.name = "BossHpBar"
	_boss_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_hp_bar.custom_minimum_size = Vector2(356, 18)
	_boss_hp_bar.show_percentage = false
	_style_progress_bar(_boss_hp_bar, Color(0.92, 0.24, 0.14), Color(0.12, 0.12, 0.16, 0.92))
	bar_margin.add_child(_boss_hp_bar)

	_boss_hp_label = Label.new()
	_boss_hp_label.name = "BossHpLabel"
	_boss_hp_label.text = "2400 / 2400 HP"
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.90))
	_boss_hp_label.add_theme_font_size_override("font_size", 11)
	bar_margin.add_child(_boss_hp_label)

	# 2. Mode Pill Container
	_mode_pill_container = PanelContainer.new()
	_mode_pill_container.name = "ModePillContainer"
	_mode_pill_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := _create_panel_style(
		Color(0.06, 0.12, 0.20, 0.92),
		Color(0.20, 0.65, 0.95, 0.75),
		16,
		1
	)
	_mode_pill_container.add_theme_stylebox_override("panel", pill_style)
	_top_header_panel.add_child(_mode_pill_container)

	_mode_pill_label = Label.new()
	_mode_pill_label.name = "ModePillLabel"
	_mode_pill_label.text = "OBJECTIVE TRIAL"
	_mode_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_pill_label.add_theme_color_override("font_color", Color(0.35, 0.88, 1.0))
	_mode_pill_label.add_theme_font_size_override("font_size", 12)
	_mode_pill_container.add_child(_mode_pill_label)

func _build_telemetry_panel() -> void:
	_telemetry_panel = PanelContainer.new()
	_telemetry_panel.name = "TelemetryPanel"
	_telemetry_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_telemetry_panel.anchor_left = 0.0
	_telemetry_panel.anchor_right = 0.0
	_telemetry_panel.anchor_top = 0.0
	_telemetry_panel.anchor_bottom = 0.0
	_telemetry_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_telemetry_panel.grow_vertical = Control.GROW_DIRECTION_END
	_telemetry_panel.offset_left = 18.0
	_telemetry_panel.offset_top = 18.0
	_telemetry_panel.custom_minimum_size = Vector2(280, 0)

	var panel_style := _create_panel_style(
		Color(0.06, 0.08, 0.12, 0.90),
		Color(0.25, 0.35, 0.50, 0.70),
		8,
		1
	)
	_telemetry_panel.add_theme_stylebox_override("panel", panel_style)
	_root_control.add_child(_telemetry_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "TelemetryVBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	_telemetry_panel.add_child(vbox)

	# Header
	var title_lbl := Label.new()
	title_lbl.text = "REALM TELEMETRY"
	title_lbl.add_theme_color_override("font_color", Color(0.55, 0.70, 0.90))
	title_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title_lbl)

	# Player HP Bar
	var hp_header_box := HBoxContainer.new()
	hp_header_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_header_box)

	var player_lbl := Label.new()
	player_lbl.text = "PLAYER HP"
	player_lbl.add_theme_color_override("font_color", Color(0.30, 0.90, 0.55))
	player_lbl.add_theme_font_size_override("font_size", 11)
	player_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_header_box.add_child(player_lbl)

	_player_hp_label = Label.new()
	_player_hp_label.name = "PlayerHpLabel"
	_player_hp_label.text = "100 / 100 HP"
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_hp_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.90))
	_player_hp_label.add_theme_font_size_override("font_size", 11)
	hp_header_box.add_child(_player_hp_label)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.name = "PlayerHpBar"
	_player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hp_bar.custom_minimum_size = Vector2(256, 12)
	_player_hp_bar.show_percentage = false
	_player_hp_bar.max_value = 100.0
	_player_hp_bar.value = 100.0
	_style_progress_bar(_player_hp_bar, Color(0.18, 0.82, 0.38), Color(0.12, 0.14, 0.18, 0.90))
	vbox.add_child(_player_hp_bar)

	# Separator
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Dynamic Rows
	_score_row = Label.new()
	_score_row.name = "ScoreRow"
	_score_row.text = "SCORE: 0  |  MULTIPLIER: x1"
	_score_row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_score_row.add_theme_font_size_override("font_size", 11)
	_score_row.visible = false
	vbox.add_child(_score_row)

	_harvest_row = Label.new()
	_harvest_row.name = "HarvestRow"
	_harvest_row.text = "RESOURCES HARVESTED: 0"
	_harvest_row.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	_harvest_row.add_theme_font_size_override("font_size", 11)
	_harvest_row.visible = false
	vbox.add_child(_harvest_row)

	_turn_row = Label.new()
	_turn_row.name = "TurnRow"
	_turn_row.text = "ROUND: 1 | PHASE: Player | AP: 3/3"
	_turn_row.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0))
	_turn_row.add_theme_font_size_override("font_size", 11)
	_turn_row.visible = false
	vbox.add_child(_turn_row)

	_voxel_row = Label.new()
	_voxel_row.name = "VoxelRow"
	_voxel_row.text = "VOXEL HOTBAR: [1] Grass  [2] Dirt  [3] Stone  |  BLOCKS MODIFIED: 0"
	_voxel_row.add_theme_color_override("font_color", Color(0.95, 0.78, 0.38))
	_voxel_row.add_theme_font_size_override("font_size", 10)
	_voxel_row.visible = false
	vbox.add_child(_voxel_row)

	_hostiles_row = Label.new()
	_hostiles_row.name = "HostilesRow"
	_hostiles_row.text = "ACTIVE HOSTILES: 0"
	_hostiles_row.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	_hostiles_row.add_theme_font_size_override("font_size", 11)
	_hostiles_row.visible = false
	vbox.add_child(_hostiles_row)

func _build_dialogue_balloon() -> void:
	_dialogue_balloon_panel = PanelContainer.new()
	_dialogue_balloon_panel.name = "DialogueBalloonPanel"
	_dialogue_balloon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_balloon_panel.anchor_left = 0.5
	_dialogue_balloon_panel.anchor_right = 0.5
	_dialogue_balloon_panel.anchor_top = 1.0
	_dialogue_balloon_panel.anchor_bottom = 1.0
	_dialogue_balloon_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialogue_balloon_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue_balloon_panel.offset_left = -280.0
	_dialogue_balloon_panel.offset_right = 280.0
	_dialogue_balloon_panel.offset_top = -120.0
	_dialogue_balloon_panel.offset_bottom = -24.0
	_dialogue_balloon_panel.custom_minimum_size = Vector2(560, 96)
	_dialogue_balloon_panel.visible = false
	_dialogue_balloon_panel.modulate.a = 0.0

	var balloon_style := _create_panel_style(
		Color(0.06, 0.08, 0.12, 0.94),
		Color(0.85, 0.68, 0.22, 0.85),
		8,
		2
	)
	_dialogue_balloon_panel.add_theme_stylebox_override("panel", balloon_style)
	_root_control.add_child(_dialogue_balloon_panel)

	var balloon_vbox := VBoxContainer.new()
	balloon_vbox.name = "DialogueVBox"
	balloon_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balloon_vbox.add_theme_constant_override("separation", 4)
	_dialogue_balloon_panel.add_child(balloon_vbox)

	# Top row: Speaker Badge
	var top_hbox := HBoxContainer.new()
	top_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balloon_vbox.add_child(top_hbox)

	var speaker_pill := PanelContainer.new()
	speaker_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := _create_panel_style(
		Color(0.20, 0.18, 0.08, 0.85),
		Color(0.85, 0.70, 0.20, 0.70),
		4,
		1
	)
	pill_style.content_margin_left = 8
	pill_style.content_margin_right = 8
	pill_style.content_margin_top = 2
	pill_style.content_margin_bottom = 2
	speaker_pill.add_theme_stylebox_override("panel", pill_style)
	top_hbox.add_child(speaker_pill)

	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.text = "SCOUT"
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.30))
	_speaker_label.add_theme_font_size_override("font_size", 11)
	speaker_pill.add_child(_speaker_label)

	# Dialogue Text Label (with autowrap & typewriter)
	_dialogue_text_label = Label.new()
	_dialogue_text_label.name = "DialogueTextLabel"
	_dialogue_text_label.text = "Be ready, danger awaits in this realm!"
	_dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_text_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_dialogue_text_label.add_theme_font_size_override("font_size", 14)
	balloon_vbox.add_child(_dialogue_text_label)

	# Choice Prompt Badge
	var choice_hbox := HBoxContainer.new()
	choice_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balloon_vbox.add_child(choice_hbox)

	var choice_spacer := Control.new()
	choice_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_hbox.add_child(choice_spacer)

	var choice_pill := PanelContainer.new()
	choice_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var choice_pill_style := _create_panel_style(
		Color(0.12, 0.18, 0.25, 0.85),
		Color(0.30, 0.70, 0.95, 0.70),
		4,
		1
	)
	choice_pill_style.content_margin_left = 8
	choice_pill_style.content_margin_right = 8
	choice_pill_style.content_margin_top = 2
	choice_pill_style.content_margin_bottom = 2
	choice_pill.add_theme_stylebox_override("panel", choice_pill_style)
	choice_hbox.add_child(choice_pill)

	_choice_label = Label.new()
	_choice_label.name = "ChoiceLabel"
	_choice_label.text = "[E] Engage Boss (3000 HP)"
	_choice_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	_choice_label.add_theme_font_size_override("font_size", 11)
	choice_pill.add_child(_choice_label)

# -----------------------------------------------------------------------------
# Style Helpers
# -----------------------------------------------------------------------------
func _create_panel_style(bg: Color, border: Color, radius: int = 8, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _style_progress_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = bg_color
	bg_sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill_color
	fill_sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_sb)

# -----------------------------------------------------------------------------
# Process Loop
# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	_elapsed_time += delta
	_scan_nameplates_timer += delta
	if _scan_nameplates_timer >= 0.5:
		_scan_nameplates_timer = 0.0
		_ensure_world_nameplates()

	_update_header()
	_update_telemetry()
	_update_dialogue_balloon(delta)
	_update_world_nameplates()

# -----------------------------------------------------------------------------
# 1. Top Header Update
# -----------------------------------------------------------------------------
func _update_header() -> void:
	var boss: Node = _find_boss_node()
	if boss != null and is_instance_valid(boss):
		_boss_container.visible = true
		_mode_pill_container.visible = false

		var b_name: String = ""
		if boss.has_meta("display_name"):
			b_name = str(boss.get_meta("display_name"))
		elif not _gdd_boss_name.is_empty():
			b_name = _gdd_boss_name
		elif boss.get("display_name") != null:
			b_name = str(boss.get("display_name"))
		elif boss.get("warden_name") != null:
			b_name = str(boss.get("warden_name"))
		else:
			b_name = "Boss Encounter"
		_boss_title_label.text = b_name.to_upper()

		var cur_hp: float = 2400.0
		var max_hp: float = 2400.0

		if boss.has_meta("current_hp"):
			cur_hp = float(boss.get_meta("current_hp"))
		elif boss.get("current_hp") != null:
			cur_hp = float(boss.get("current_hp"))
		elif boss.get("warden_hp") != null:
			cur_hp = float(boss.get("warden_hp"))
		elif boss.get("health") != null:
			cur_hp = float(boss.get("health"))

		if boss.has_meta("max_hp"):
			max_hp = float(boss.get_meta("max_hp"))
		elif boss.get("max_hp") != null:
			max_hp = float(boss.get("max_hp"))
		elif boss.get("warden_max_hp") != null:
			max_hp = float(boss.get("warden_max_hp"))
		elif boss.get("max_health") != null:
			max_hp = float(boss.get("max_health"))
		elif _gdd_boss_max_hp > 0.0:
			max_hp = _gdd_boss_max_hp

		_boss_hp_bar.max_value = max_hp
		_boss_hp_bar.value = cur_hp
		_boss_hp_label.text = "%d / %d HP" % [int(cur_hp), int(max_hp)]
	else:
		_boss_container.visible = false
		_mode_pill_container.visible = true
		_mode_pill_label.text = _determine_realm_title()

func _find_boss_node() -> Node:
	var boss_nodes := get_tree().get_nodes_in_group("boss_target")
	for b: Node in boss_nodes:
		if is_instance_valid(b):
			return b

	var combat_units := get_tree().get_nodes_in_group("combat_unit")
	for u: Node in combat_units:
		if is_instance_valid(u):
			if u.has_meta("role") and str(u.get_meta("role")).to_lower() == "boss":
				return u
			var un: String = u.name.to_lower()
			if un.contains("boss") or un.contains("golem") or un.contains("warden"):
				return u

	var sc := get_tree().current_scene
	if sc != null and is_instance_valid(sc):
		if sc.get("warden_spawned") == true and sc.get("warden_hp") != null:
			return sc

	return null

func _determine_realm_title() -> String:
	var sc := get_tree().current_scene
	if sc == null:
		return "OBJECTIVE TRIAL"

	if sc.has_meta("hex_substrate") or not get_tree().get_nodes_in_group("hex_grid").is_empty() or sc.find_children("", "TurnManager", true, false).size() > 0:
		return "4X TACTICAL COMMAND — HEX GRID"

	if sc.has_meta("voxel_substrate") or sc.find_children("", "VoxelWorldGenerator", true, false).size() > 0 or not get_tree().get_nodes_in_group("voxel").is_empty():
		return "VOXEL SURVIVAL FRONTIER"

	if not get_tree().get_nodes_in_group("collectible").is_empty() or not get_tree().get_nodes_in_group("impulse_pad").is_empty() or sc.has_meta("score_multiplier"):
		return "ARCADE COLLECTOR — MULTIPLIER TRIAL"

	if not get_tree().get_nodes_in_group("harvestable").is_empty() or sc.has_meta("scattered_grove"):
		return "RESOURCE SANCTUARY — TICK HARVESTING"

	if not get_tree().get_nodes_in_group("hostile_unit").is_empty():
		return "COMBAT ENCOUNTER — SURVIVAL ARENA"

	if not _gdd_zone_title.is_empty():
		return _gdd_zone_title.substr(0, 42).to_upper()

	return "PLAYABLE REALM — OBJECTIVE TRIAL"

# -----------------------------------------------------------------------------
# 2. Telemetry Panel Update
# -----------------------------------------------------------------------------
func _update_telemetry() -> void:
	var sc := get_tree().current_scene
	var player := _find_player_node()

	# Player HP
	var p_cur_hp: float = 100.0
	var p_max_hp: float = 100.0
	if player != null and is_instance_valid(player):
		if player.has_meta("current_hp"):
			p_cur_hp = float(player.get_meta("current_hp"))
		elif player.get("current_hp") != null:
			p_cur_hp = float(player.get("current_hp"))
		elif player.get("health") != null:
			p_cur_hp = float(player.get("health"))

		if player.has_meta("max_hp"):
			p_max_hp = float(player.get_meta("max_hp"))
		elif player.get("max_hp") != null:
			p_max_hp = float(player.get("max_hp"))
		elif player.get("max_health") != null:
			p_max_hp = float(player.get("max_health"))

	_player_hp_bar.max_value = p_max_hp
	_player_hp_bar.value = p_cur_hp
	_player_hp_label.text = "%d / %d HP" % [int(p_cur_hp), int(p_max_hp)]

	# 1. Collectible / Impulse Pad
	var coll_nodes := get_tree().get_nodes_in_group("collectible")
	var pad_nodes := get_tree().get_nodes_in_group("impulse_pad")
	if not coll_nodes.is_empty() or not pad_nodes.is_empty():
		_score_row.visible = true
		var cur_score: int = int(sc.get_meta("score", 0)) if sc != null else 0
		var mult: float = float(sc.get_meta("score_multiplier", 1.0)) if sc != null else 1.0
		if mult == floorf(mult):
			_score_row.text = "SCORE: %d  |  MULTIPLIER: x%d" % [cur_score, int(mult)]
		else:
			_score_row.text = "SCORE: %d  |  MULTIPLIER: x%.1f" % [cur_score, mult]
	else:
		_score_row.visible = false

	# 2. Harvestable
	var harv_nodes := get_tree().get_nodes_in_group("harvestable")
	if not harv_nodes.is_empty():
		_harvest_row.visible = true
		var tot_harv: int = int(sc.get_meta("harvested_total", 0)) if sc != null else 0
		var oak: int = int(sc.get_meta("harvested_Oak Log", 0)) if sc != null else 0
		var iron: int = int(sc.get_meta("harvested_Iron Ore", 0)) if sc != null else 0
		if oak > 0 or iron > 0:
			_harvest_row.text = "RESOURCES HARVESTED: %d (Oak: %d, Iron: %d)" % [tot_harv, oak, iron]
		else:
			_harvest_row.text = "RESOURCES HARVESTED: %d" % tot_harv
	else:
		_harvest_row.visible = false

	# 3. TurnManager
	var tm_nodes := get_tree().get_nodes_in_group("turn_manager")
	var tm: Node = tm_nodes[0] if not tm_nodes.is_empty() else null
	if tm == null and sc != null:
		var found_tms := sc.find_children("", "TurnManager", true, false)
		if not found_tms.is_empty():
			tm = found_tms[0]

	if tm != null and is_instance_valid(tm):
		_turn_row.visible = true
		var r_num: int = int(tm.get("current_round")) if tm.get("current_round") != null else 1
		var f_name: String = "Player"
		if tm.has_method("get_current_faction"):
			f_name = str(tm.call("get_current_faction"))
		elif tm.get("current_phase") != null:
			f_name = str(tm.get("current_phase"))
		var c_ap: int = int(tm.get("current_ap")) if tm.get("current_ap") != null else 3
		var m_ap: int = int(tm.get("max_ap")) if tm.get("max_ap") != null else 3
		_turn_row.text = "ROUND: %d | PHASE: %s | AP: %d/%d" % [r_num, f_name, c_ap, m_ap]
	else:
		_turn_row.visible = false

	# 4. VoxelWorldGenerator / voxel_substrate
	var is_voxel := false
	if sc != null and sc.has_meta("voxel_substrate"):
		is_voxel = true
	elif sc != null and not sc.find_children("", "VoxelWorldGenerator", true, false).is_empty():
		is_voxel = true

	if is_voxel:
		_voxel_row.visible = true
		var edits: int = int(sc.get_meta("voxel_edits", 0)) if sc != null else 0
		_voxel_row.text = "VOXEL HOTBAR: [1] Grass  [2] Dirt  [3] Stone  |  BLOCKS MODIFIED: %d" % edits
	else:
		_voxel_row.visible = false

	# 5. Hostile units
	var hostiles := get_tree().get_nodes_in_group("hostile_unit")
	var boss_units := get_tree().get_nodes_in_group("boss_target")
	if not hostiles.is_empty() or not boss_units.is_empty():
		_hostiles_row.visible = true
		var active_count: int = 0
		for h: Node in hostiles:
			if is_instance_valid(h):
				if h.has_meta("current_hp") and float(h.get_meta("current_hp")) <= 0.0:
					continue
				active_count += 1
		for b: Node in boss_units:
			if is_instance_valid(b) and not hostiles.has(b):
				if b.has_meta("current_hp") and float(b.get_meta("current_hp")) <= 0.0:
					continue
				active_count += 1
		_hostiles_row.text = "ACTIVE HOSTILES: %d" % active_count
	else:
		_hostiles_row.visible = false

func _find_player_node() -> Node:
	var players := get_tree().get_nodes_in_group("player")
	for p: Node in players:
		if is_instance_valid(p):
			return p
	var sc := get_tree().current_scene
	if sc != null and is_instance_valid(sc):
		var p := sc.find_child("PlayerCharacter", true, false)
		if p != null and is_instance_valid(p):
			return p
	return null

# -----------------------------------------------------------------------------
# 3. 3D World Nameplates
# -----------------------------------------------------------------------------
func _ensure_world_nameplates() -> void:
	var groups := ["combat_unit", "harvestable", "dialogue_trigger", "objective", "impulse_pad", "jump_pad", "boost_pad", "multiplier_gate"]
	for g: String in groups:
		var nodes: Array[Node] = get_tree().get_nodes_in_group(g)
		for node: Node in nodes:
			if node is Node3D and is_instance_valid(node):
				var n3d := node as Node3D
				if n3d.get_node_or_null("WorldNameplate3D") == null:
					_attach_nameplate(n3d)

func _attach_nameplate(entity: Node3D) -> void:
	if entity.is_in_group("player") or entity.name == "PlayerCharacter":
		return
	if entity.has_meta("role") and str(entity.get_meta("role")).to_lower() == "player":
		return

	var height := _calculate_entity_height(entity)
	var lbl := Label3D.new()
	lbl.name = "WorldNameplate3D"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 28
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	lbl.no_depth_test = false
	lbl.position = Vector3(0.0, height + 0.6, 0.0)
	lbl.text = entity.name
	entity.add_child(lbl)

func _calculate_entity_height(node: Node3D) -> float:
	var col_shapes := node.find_children("", "CollisionShape3D", true, false)
	for cs: Node in col_shapes:
		var c_shape: Shape3D = (cs as CollisionShape3D).shape
		if c_shape is CapsuleShape3D:
			return (cs as Node3D).position.y + (c_shape as CapsuleShape3D).height * 0.5
		elif c_shape is BoxShape3D:
			return (cs as Node3D).position.y + (c_shape as BoxShape3D).size.y * 0.5
		elif c_shape is CylinderShape3D:
			return (cs as Node3D).position.y + (c_shape as CylinderShape3D).height * 0.5

	var meshes := node.find_children("", "MeshInstance3D", true, false)
	var max_top: float = 0.0
	for m: Node in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.mesh.get_aabb()
			var top := mi.position.y + aabb.end.y * mi.scale.y
			if top > max_top:
				max_top = top
	if max_top > 0.4:
		return max_top

	var n_name := node.name.to_lower()
	if node.is_in_group("boss_target") or n_name.contains("golem") or n_name.contains("boss"):
		return 3.2
	if node.is_in_group("harvestable") or n_name.contains("tree"):
		return 3.5
	if n_name.contains("rock"):
		return 1.4
	if node.is_in_group("combat_unit"):
		return 1.8
	return 1.6

func _update_world_nameplates() -> void:
	var groups := ["combat_unit", "harvestable", "dialogue_trigger", "objective", "impulse_pad", "jump_pad", "boost_pad", "multiplier_gate"]
	var visited: Dictionary = {}

	for g: String in groups:
		var nodes: Array[Node] = get_tree().get_nodes_in_group(g)
		for n: Node in nodes:
			if n is Node3D and is_instance_valid(n):
				var id := n.get_instance_id()
				if visited.has(id):
					continue
				visited[id] = true

				var n3d := n as Node3D
				var nameplate: Label3D = n3d.get_node_or_null("WorldNameplate3D") as Label3D
				if nameplate == null:
					continue

				# 1. combat_unit (role != "player")
				if n3d.is_in_group("combat_unit") or n3d.has_meta("role"):
					var role: String = str(n3d.get_meta("role", "")).to_lower()
					if role == "player" or n3d.is_in_group("player") or n3d.name == "PlayerCharacter":
						nameplate.visible = false
						continue

					var cur_hp: int = int(float(n3d.get_meta("current_hp", 100.0)))
					var max_hp: int = int(float(n3d.get_meta("max_hp", 100.0)))
					var disp_name: String = str(n3d.get_meta("display_name", n3d.name))

					nameplate.visible = true
					if cur_hp <= 0:
						nameplate.text = "%s\n[DEFEATED]" % disp_name
						nameplate.modulate = Color(0.6, 0.6, 0.6, 0.7)
					else:
						nameplate.text = "%s\n[%d / %d HP]" % [disp_name, cur_hp, max_hp]
						if n3d.is_in_group("hostile_unit") or role == "boss" or str(n3d.get_meta("faction", "")).to_lower() == "hostile":
							nameplate.modulate = Color(1.0, 0.35, 0.20) # red/orange
						else:
							nameplate.modulate = Color(0.20, 0.85, 1.0) # cyan for allies
					continue

				# 2. harvestable
				if n3d.is_in_group("harvestable") or n3d.has_meta("resource_name"):
					var res_name: String = str(n3d.get_meta("resource_name", "Resource"))
					var charges: int = int(n3d.get_meta("charges_remaining", 0))
					var max_ch: int = int(n3d.get_meta("max_charges", 5))
					nameplate.visible = true
					nameplate.text = "%s\n[%d / %d]" % [res_name, charges, max_ch]
					nameplate.modulate = Color(0.20, 0.95, 0.40) # emerald green
					continue

				# 3. impulse_pad
				if n3d.is_in_group("impulse_pad") or n3d.is_in_group("multiplier_gate") or n3d.is_in_group("jump_pad") or n3d.is_in_group("boost_pad"):
					var mult: float = float(n3d.get_meta("multiplier", 1.0))
					var up_vel: float = float(n3d.get_meta("upward_velocity", 0.0))
					var fwd_boost: float = float(n3d.get_meta("forward_boost", 0.0))

					if n3d.has_meta("traits_controller"):
						var tc: Variant = n3d.get_meta("traits_controller")
						if tc != null:
							if tc.get("_impulse_multiplier") != null:
								mult = float(tc.get("_impulse_multiplier"))
							if tc.get("_impulse_upward_velocity") != null:
								up_vel = float(tc.get("_impulse_upward_velocity"))
							if tc.get("_impulse_forward_boost") != null:
								fwd_boost = float(tc.get("_impulse_forward_boost"))

					var nl := n3d.name.to_lower()
					if mult <= 1.0 and (n3d.is_in_group("multiplier_gate") or nl.contains("multiplier_gate")):
						mult = 2.0

					if mult > 1.0:
						nameplate.visible = true
						nameplate.text = "x%d MULTIPLIER" % int(mult)
						nameplate.modulate = Color(0.95, 0.25, 1.0) # neon magenta
						continue
					elif up_vel > 0.0 or n3d.is_in_group("jump_pad") or nl.contains("jump"):
						nameplate.visible = true
						nameplate.text = "[ JUMP PAD ]"
						nameplate.modulate = Color(0.20, 0.90, 1.0) # bright cyan
						continue
					elif fwd_boost > 0.0 or n3d.is_in_group("boost_pad") or nl.contains("boost"):
						nameplate.visible = true
						nameplate.text = ">> SPEED BOOST >>"
						nameplate.modulate = Color(1.0, 0.65, 0.15) # neon orange
						continue

				# 4. dialogue_trigger / objective
				if n3d.is_in_group("dialogue_trigger") or n3d.is_in_group("objective"):
					var prompt: String = str(n3d.get_meta("prompt_label", "Interact"))
					nameplate.visible = true
					nameplate.text = "[ %s ]" % prompt
					nameplate.modulate = Color(1.0, 0.85, 0.20) # gold
					continue

# -----------------------------------------------------------------------------
# 4. Dialogue Balloon & Parser
# -----------------------------------------------------------------------------
func _load_and_cache_dialogue(path: String) -> Dictionary:
	if _dialogue_cache.has(path):
		var cached: Variant = _dialogue_cache[path]
		if cached is Dictionary:
			return cached as Dictionary

	var parsed := parse_dialogue_file(path)
	_dialogue_cache[path] = parsed
	return parsed

func parse_dialogue_file(path: String) -> Dictionary:
	var nodes: Dictionary = {}
	var safe_dialogue_path := "res://" + path.trim_prefix("res://")
	if not FileAccess.file_exists(safe_dialogue_path):
		return nodes

	var file := FileAccess.open(safe_dialogue_path, FileAccess.READ)
	if file == null:
		return nodes

	var current_node_title: String = "start_encounter"
	var current_speaker: String = "Scout"
	var current_lines: Array[String] = []
	var current_choices: Array[String] = []

	while not file.eof_reached():
		var raw_line := file.get_line()
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("~"):
			if not current_lines.is_empty() or not current_choices.is_empty():
				nodes[current_node_title] = {
					"title": current_node_title,
					"speaker": current_speaker,
					"text": " ".join(current_lines),
					"choices": current_choices.duplicate()
				}
				current_lines.clear()
				current_choices.clear()
			current_node_title = line.trim_prefix("~").strip_edges()
			current_speaker = "Scout"
		elif line.begins_with("-"):
			var choice_text := line.trim_prefix("-").strip_edges()
			if not choice_text.is_empty():
				current_choices.append(choice_text)
		elif line.begins_with("=>"):
			pass
		elif line.contains(":"):
			var parts := line.split(":", true, 1)
			current_speaker = parts[0].strip_edges()
			if parts.size() > 1 and not parts[1].strip_edges().is_empty():
				current_lines.append(parts[1].strip_edges())
		else:
			current_lines.append(line)

	if not current_lines.is_empty() or not current_choices.is_empty():
		nodes[current_node_title] = {
			"title": current_node_title,
			"speaker": current_speaker,
			"text": " ".join(current_lines),
			"choices": current_choices.duplicate()
		}

	file.close()
	return nodes

func _update_dialogue_balloon(delta: float) -> void:
	var should_show := false
	var target_path := DEFAULT_DIALOGUE_PATH
	var target_node_name := _determine_opening_dialogue_node()
	var trigger_prompt := ""

	# 1. Opening encounter (0.5s to 4.5s)
	if _elapsed_time >= 0.5 and _elapsed_time <= 4.5:
		should_show = true
		target_path = DEFAULT_DIALOGUE_PATH
		target_node_name = _determine_opening_dialogue_node()

	# 2. Check nearby dialogue_trigger (< 4.5m)
	var player := _find_player_node()
	if player is Node3D and is_instance_valid(player):
		var p_pos := (player as Node3D).global_position
		var triggers := get_tree().get_nodes_in_group("dialogue_trigger")
		var nearest_dist: float = 999.0
		var nearest_trigger: Node3D = null
		for t: Node in triggers:
			if t is Node3D and is_instance_valid(t):
				var d := p_pos.distance_to((t as Node3D).global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest_trigger = t as Node3D

		if nearest_trigger != null and nearest_dist < 4.5:
			should_show = true
			if nearest_trigger.has_meta("dialogue_path"):
				var custom_path: String = str(nearest_trigger.get_meta("dialogue_path")).strip_edges()
				if not custom_path.is_empty() and FileAccess.file_exists(custom_path):
					target_path = custom_path
			if nearest_trigger.has_meta("start_node"):
				var sn: String = str(nearest_trigger.get_meta("start_node")).strip_edges()
				if not sn.is_empty():
					target_node_name = sn
			if nearest_trigger.has_meta("prompt_label"):
				trigger_prompt = str(nearest_trigger.get_meta("prompt_label")).strip_edges()

	# Apply visibility / fade
	if should_show:
		_dialogue_balloon_panel.visible = true
		_dialogue_balloon_panel.modulate.a = move_toward(_dialogue_balloon_panel.modulate.a, 1.0, delta * 4.0)
		_set_active_dialogue_node(target_path, target_node_name, trigger_prompt)

		# Typewriter reveal
		if _dialogue_text_label.visible_characters < _current_line_text.length():
			_typewriter_progress += delta * 36.0
			_dialogue_text_label.visible_characters = int(_typewriter_progress)
	else:
		_dialogue_balloon_panel.modulate.a = move_toward(_dialogue_balloon_panel.modulate.a, 0.0, delta * 3.0)
		if _dialogue_balloon_panel.modulate.a <= 0.01:
			_dialogue_balloon_panel.visible = false
			_active_dialogue_node_key = ""

func _determine_opening_dialogue_node() -> String:
	var cached_nodes := _load_and_cache_dialogue(DEFAULT_DIALOGUE_PATH)
	if cached_nodes.has("start_encounter"):
		var raw_se: Variant = cached_nodes["start_encounter"]
		if raw_se is Dictionary:
			var se_dict: Dictionary = raw_se as Dictionary
			var text: String = str(se_dict.get("text", "")).strip_edges()
			if not text.is_empty() and text != "Be ready, danger awaits in this realm!":
				return "start_encounter"

	if _find_boss_node() != null:
		return "start_encounter"

	var sc := get_tree().current_scene
	if sc != null:
		if sc.has_meta("hex_substrate") or not get_tree().get_nodes_in_group("hex_grid").is_empty() or sc.find_children("", "TurnManager", true, false).size() > 0:
			return "tactical_command"
		if sc.has_meta("voxel_substrate") or not sc.find_children("", "VoxelWorldGenerator", true, false).is_empty() or not get_tree().get_nodes_in_group("voxel").is_empty():
			return "voxel_frontier"
		if not get_tree().get_nodes_in_group("collectible").is_empty() or not get_tree().get_nodes_in_group("impulse_pad").is_empty() or sc.has_meta("score_multiplier"):
			return "collector_trial"
		if not get_tree().get_nodes_in_group("harvestable").is_empty() or sc.has_meta("scattered_grove"):
			return "harvest_sanctuary"

	return "start_encounter"

func _set_active_dialogue_node(path: String, node_title: String, prompt_fallback: String) -> void:
	var key := path + "::" + node_title
	if _active_dialogue_node_key == key:
		return
	_active_dialogue_node_key = key

	var cached_nodes := _load_and_cache_dialogue(path)
	var node_info: Dictionary = {}
	if cached_nodes.has(node_title):
		var raw_node: Variant = cached_nodes[node_title]
		if raw_node is Dictionary:
			node_info = raw_node as Dictionary
	elif not prompt_fallback.is_empty():
		pass
	elif not cached_nodes.is_empty() and cached_nodes.has("start_encounter"):
		node_info = cached_nodes["start_encounter"] as Dictionary
	elif not cached_nodes.is_empty():
		var first_key: Variant = cached_nodes.keys()[0]
		node_info = cached_nodes[first_key] as Dictionary

	var speaker: String = "Scout"
	var text: String = ""
	var choices: Array = []

	if not node_info.is_empty():
		speaker = str(node_info.get("speaker", "Scout"))
		text = str(node_info.get("text", ""))
		var raw_c: Variant = node_info.get("choices", [])
		if raw_c is Array:
			choices = raw_c as Array
	else:
		if not prompt_fallback.is_empty():
			speaker = "Ancient Altar"
			text = "The ancient altar hums with mystical energy. Channel your power to unlock the realm's secrets."
			choices = [prompt_fallback]
		elif not _gdd_dialogue_preview.is_empty():
			speaker = "Guide"
			text = _gdd_dialogue_preview
			choices = ["Engage Encounter"]
		else:
			speaker = "Scout"
			text = "Be ready, danger awaits in this realm!"
			choices = ["Engage Boss (3000 HP)"]

	_speaker_label.text = speaker.to_upper()
	_current_line_text = text
	_dialogue_text_label.text = text
	_typewriter_progress = 0.0
	_dialogue_text_label.visible_characters = 0

	if not choices.is_empty():
		_choice_label.text = "[E] " + str(choices[0])
		_choice_label.get_parent().visible = true
	else:
		_choice_label.text = "[E] Continue"
		_choice_label.get_parent().visible = true

# -----------------------------------------------------------------------------
# 5. GDD Specs Loading
# -----------------------------------------------------------------------------
func _load_gdd_design() -> void:
	if not FileAccess.file_exists(GDD_DESIGN_PATH):
		return
	var f := FileAccess.open(GDD_DESIGN_PATH, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed is Dictionary:
		var p_dict: Dictionary = parsed as Dictionary
		_gdd_boss_name = str(p_dict.get("boss_name", ""))
		_gdd_boss_max_hp = float(p_dict.get("boss_max_hp", 2400.0))
		_gdd_zone_title = str(p_dict.get("zone_title", ""))
		_gdd_dialogue_preview = str(p_dict.get("npc_dialogue_preview", ""))
