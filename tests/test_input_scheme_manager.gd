extends SceneTree
## test_input_scheme_manager.gd
## Automated verification suite for InputSchemeManager, settings persistence,
## and modular touch control dispatching.

func _init() -> void:
	print("========================================")
	print("Running InputSchemeManager Test Suite...")
	print("========================================")
	
	var passed := 0
	var failed := 0
	
	if test_profile_resolution():
		print("[PASS] test_profile_resolution")
		passed += 1
	else:
		printerr("[FAIL] test_profile_resolution")
		failed += 1
		
	if test_settings_persistence():
		print("[PASS] test_settings_persistence")
		passed += 1
	else:
		printerr("[FAIL] test_settings_persistence")
		failed += 1
		
	if test_virtual_thumbstick_action_dispatch():
		print("[PASS] test_virtual_thumbstick_action_dispatch")
		passed += 1
	else:
		printerr("[FAIL] test_virtual_thumbstick_action_dispatch")
		failed += 1
		
	if test_action_cluster_dispatch():
		print("[PASS] test_action_cluster_dispatch")
		passed += 1
	else:
		printerr("[FAIL] test_action_cluster_dispatch")
		failed += 1

	if test_voice_ptt_widget():
		print("[PASS] test_voice_ptt_widget")
		passed += 1
	else:
		printerr("[FAIL] test_voice_ptt_widget")
		failed += 1

	print("========================================")
	print("Results: %d passed, %d failed" % [passed, failed])
	print("========================================")
	
	quit(0 if failed == 0 else 1)

func test_profile_resolution() -> bool:
	var script = load("res://autoloads/InputSchemeManager.gd")
	var ism = script.new()
	root.add_child(ism)
	
	# Default auto profile tests
	# 1. iOS without gamepad -> mobile_touch
	var p_ios = ism.resolve_profile("iOS", true, 0, "")
	if p_ios != "mobile_touch":
		printerr("Expected mobile_touch for iOS without gamepad, got: ", p_ios)
		ism.queue_free()
		return false

	# 2. Linux with touch & joypad (Steam Deck) -> handheld_hybrid
	var p_deck = ism.resolve_profile("Linux", true, 1, "")
	if p_deck != "handheld_hybrid":
		printerr("Expected handheld_hybrid for Steam Deck, got: ", p_deck)
		ism.queue_free()
		return false

	# 3. Windows/macOS without touch or gamepad -> desktop_kbm
	var p_win = ism.resolve_profile("Windows", false, 0, "")
	if p_win != "desktop_kbm":
		printerr("Expected desktop_kbm for Windows without gamepad, got: ", p_win)
		ism.queue_free()
		return false
	var p_mac = ism.resolve_profile("macOS", false, 0, "")
	if p_mac != "desktop_kbm":
		printerr("Expected desktop_kbm for macOS without gamepad, got: ", p_mac)
		ism.queue_free()
		return false

	# 4. Windows with gamepad active -> pure_gamepad
	var p_pad = ism.resolve_profile("Windows", false, 1, "gamepad")
	if p_pad != "pure_gamepad":
		printerr("Expected pure_gamepad for Windows with active gamepad, got: ", p_pad)
		ism.queue_free()
		return false

	# 5. Mobile with gamepad active and keep_voice_ptt_on_screen -> handheld_hybrid
	var p_mobile_hybrid = ism.resolve_profile("iOS", true, 1, "gamepad")
	if p_mobile_hybrid != "handheld_hybrid":
		printerr("Expected handheld_hybrid for iOS with gamepad, got: ", p_mobile_hybrid)
		ism.queue_free()
		return false

	# 6. Forced profile mode override
	ism.update_controls_config({"profile_mode": "pure_gamepad"})
	var p_forced = ism.resolve_profile("iOS", true, 0, "")
	if p_forced != "pure_gamepad":
		printerr("Expected pure_gamepad under forced profile_mode, got: ", p_forced)
		ism.queue_free()
		return false
		
	# Restore auto mode
	ism.update_controls_config({"profile_mode": "auto"})
	ism.queue_free()
	return true

func test_settings_persistence() -> bool:
	var script = load("res://autoloads/InputSchemeManager.gd")
	var ism = script.new()
	root.add_child(ism)
	
	# Update settings
	ism.update_controls_config({
		"touch_opacity": 0.55,
		"touch_stick_mode": "fixed",
		"camera_touch_sensitivity": 1.75
	})
	
	var cfg = ism.get_controls_config()
	if not is_equal_approx(float(cfg.get("touch_opacity", 0.0)), 0.55):
		printerr("Settings update failed for touch_opacity")
		ism.queue_free()
		return false
	if str(cfg.get("touch_stick_mode", "")) != "fixed":
		printerr("Settings update failed for touch_stick_mode")
		ism.queue_free()
		return false
	
	ism.queue_free()
	
	# Reload in fresh instance to verify disk persistence
	var ism2 = script.new()
	root.add_child(ism2)
	var loaded_cfg = ism2.get_controls_config()
	if not is_equal_approx(float(loaded_cfg.get("touch_opacity", 0.0)), 0.55):
		printerr("Settings reload failed to persist touch_opacity")
		ism2.queue_free()
		return false
	if str(loaded_cfg.get("touch_stick_mode", "")) != "fixed":
		printerr("Settings reload failed to persist touch_stick_mode")
		ism2.queue_free()
		return false

	# Restore default settings
	ism2.update_controls_config({
		"profile_mode": "auto",
		"auto_hide_touch_on_gamepad": true,
		"keep_voice_ptt_on_screen": true,
		"touch_stick_mode": "floating",
		"touch_opacity": 0.85,
		"touch_haptic_feedback": true,
		"camera_touch_sensitivity": 1.0,
		"stick_deadzone": 0.15
	})
	ism2.queue_free()
	return true

func test_virtual_thumbstick_action_dispatch() -> bool:
	# Ensure actions exist in InputMap
	_ensure_test_actions()
	
	var stick_scene = load("res://scenes/ui/controls/VirtualThumbstick.tscn")
	var stick = stick_scene.instantiate()
	root.add_child(stick)
	stick.size = Vector2(200, 200)
	stick.stick_mode = "fixed"
	stick.base_position = Vector2(100, 100)
	
	# Simulate drag UP (forward): Y displacement is negative
	stick._start_touch(1, Vector2(100, 40))
	if not Input.is_action_pressed("move_forward"):
		printerr("VirtualThumbstick failed to dispatch move_forward on UP drag")
		stick.queue_free()
		return false
		
	# Release touch
	stick._stop_touch()
	if Input.is_action_pressed("move_forward"):
		printerr("VirtualThumbstick failed to release move_forward on stop touch")
		stick.queue_free()
		return false

	# Simulate drag RIGHT: X displacement is positive
	stick._start_touch(1, Vector2(160, 100))
	if not Input.is_action_pressed("move_right"):
		printerr("VirtualThumbstick failed to dispatch move_right on RIGHT drag")
		stick.queue_free()
		return false
		
	stick._stop_touch()
	if Input.is_action_pressed("move_right"):
		printerr("VirtualThumbstick failed to release move_right on stop touch")
		stick.queue_free()
		return false
		
	stick.queue_free()
	return true

func test_action_cluster_dispatch() -> bool:
	_ensure_test_actions()
	
	var cluster_scene = load("res://scenes/ui/controls/ActionCluster.tscn")
	var cluster = cluster_scene.instantiate()
	root.add_child(cluster)
	
	# Simulate Primary button down
	cluster._on_primary_down()
	if not Input.is_action_pressed("ability_primary"):
		printerr("ActionCluster failed to dispatch ability_primary")
		cluster.queue_free()
		return false
	cluster._on_primary_up()
	if Input.is_action_pressed("ability_primary"):
		printerr("ActionCluster failed to release ability_primary")
		cluster.queue_free()
		return false

	# Simulate Secondary button down
	cluster._on_secondary_down()
	if not Input.is_action_pressed("ability_secondary"):
		printerr("ActionCluster failed to dispatch ability_secondary")
		cluster.queue_free()
		return false
	cluster._on_secondary_up()
	if Input.is_action_pressed("ability_secondary"):
		printerr("ActionCluster failed to release ability_secondary")
		cluster.queue_free()
		return false

	cluster.queue_free()
	return true

func test_voice_ptt_widget() -> bool:
	_ensure_test_actions()
	
	var ptt_scene = load("res://scenes/ui/controls/VoicePTTWidget.tscn")
	var ptt = ptt_scene.instantiate()
	root.add_child(ptt)
	
	ptt._on_ptt_down()
	if not Input.is_action_pressed("voice_architect_ptt"):
		printerr("VoicePTTWidget failed to press voice_architect_ptt")
		ptt.queue_free()
		return false
		
	ptt._on_ptt_up()
	if Input.is_action_pressed("voice_architect_ptt"):
		printerr("VoicePTTWidget failed to release voice_architect_ptt")
		ptt.queue_free()
		return false

	ptt.queue_free()
	return true

func _ensure_test_actions() -> void:
	var actions = ["move_forward", "move_back", "move_left", "move_right", "ability_primary", "ability_secondary", "voice_architect_ptt"]
	for a in actions:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
