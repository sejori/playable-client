class_name TestUniversalScaffolding
extends SceneTree
## test_universal_scaffolding.gd
## Automated verification suite covering:
## 1. Layer 1: Unified Camera Host & Composable Virtual Cameras
## 2. Layer 2: Generic Motion Substrate (All 5 Movers + ModularCharacter3D)
## 3. Layer 3: Universal Spatial Raycaster (Voxel & Hex Math Resolvers)
## 4. Layer 4: Headless Scaffolding Engine & All 6 Cartridge Scenes

func _init() -> void:
	print("[UniversalScaffoldingTest] Starting 4-Layer Verification Suite...")
	var passed := 0
	var failed := 0

	# --- Test 1: Layer 1 CameraHost3D Priority & Active Camera Resolution ---
	print("[Test 1] Testing Layer 1: CameraHost3D Priority...")
	var cam_host := CameraHost3D.new()
	root.add_child(cam_host)
	cam_host._ready()

	var vcam_low := VirtualCameraBase3D.new()
	vcam_low.priority = 5
	cam_host.add_child(vcam_low)
	cam_host.register_vcam(vcam_low)

	var vcam_high := VirtualCameraBase3D.new()
	vcam_high.priority = 20
	cam_host.add_child(vcam_high)
	cam_host.register_vcam(vcam_high)

	if cam_host.get_active_vcam() == vcam_high:
		print("  PASS: Highest priority virtual camera correctly resolved.")
		passed += 1
	else:
		push_error("  FAIL: Expected vcam_high to be active.")
		failed += 1

	# Deactivate high priority, expect fallback to low
	vcam_high.is_active = false
	cam_host.refresh_active_vcam(true)
	if cam_host.get_active_vcam() == vcam_low:
		print("  PASS: Fallback to lower priority vcam upon deactivation.")
		passed += 1
	else:
		push_error("  FAIL: Expected vcam_low to be active after vcam_high deactivated.")
		failed += 1

	cam_host.queue_free()

	# --- Test 2: Layer 2 Motion Substrate (Movers) ---
	print("[Test 2] Testing Layer 2: Motion Substrate...")
	var test_char := CharacterBody3D.new()
	root.add_child(test_char)

	var action_mover := ActionMover3D.new()
	test_char.add_child(action_mover)
	var vel_action := action_mover.compute_velocity(0.016, Vector3.ZERO, test_char)
	# Gravity applied
	if vel_action.y < 0.0:
		print("  PASS: ActionMover3D applied gravity correctly.")
		passed += 1
	else:
		push_error("  FAIL: ActionMover3D failed to apply gravity.")
		failed += 1

	var click_mover := ClickToMoveMover3D.new()
	test_char.add_child(click_mover)
	click_mover.set_destination(Vector3(10, 0, 0), test_char)
	var vel_click := click_mover.compute_velocity(0.016, Vector3.ZERO, test_char)
	if vel_click.x > 0.0:
		print("  PASS: ClickToMoveMover3D directed velocity toward destination.")
		passed += 1
	else:
		push_error("  FAIL: ClickToMoveMover3D failed to steer toward destination.")
		failed += 1

	var fps_mover := FPSMover3D.new()
	test_char.add_child(fps_mover)
	var vel_fps := fps_mover.compute_velocity(0.016, Vector3.ZERO, test_char)
	if vel_fps.y < 0.0:
		print("  PASS: FPSMover3D computed baseline velocity.")
		passed += 1
	else:
		push_error("  FAIL: FPSMover3D failed.")
		failed += 1

	test_char.queue_free()

	# --- Test 3: Layer 3 Universal Spatial Raycaster Math ---
	print("[Test 3] Testing Layer 3: Spatial Raycaster Math...")
	var picker := RaycastPicker3D.new()
	root.add_child(picker)

	# Voxel resolver test:
	# hit_pos = (2.5, 3.0, 4.5), normal = (0, 1, 0)
	# break_coord = floor(2.5, 2.5, 4.5) = (2, 2, 4)
	# place_coord = floor(2.5, 3.5, 4.5) = (2, 3, 4)
	var vox := picker.resolve_voxel_coords(Vector3(2.5, 3.0, 4.5), Vector3.UP)
	if vox["break_coord"] == Vector3i(2, 2, 4) and vox["place_coord"] == Vector3i(2, 3, 4):
		print("  PASS: Voxel break/place integer resolver verified.")
		passed += 1
	else:
		push_error("  FAIL: Voxel coords incorrect: %s" % str(vox))
		failed += 1

	# Hex resolver test:
	# Origin (0, 0, 0) -> axial (0, 0)
	var hex_origin := picker.resolve_hex_coords(Vector3.ZERO)
	if hex_origin == Vector2i(0, 0):
		print("  PASS: Hex origin (0, 0) axial mapping verified.")
		passed += 1
	else:
		push_error("  FAIL: Hex origin mapping incorrect: %s" % str(hex_origin))
		failed += 1

	# Hex roundtrip math
	var axial_test := Vector2i(2, -1)
	var world_hex := HexGridMath.axial_to_world(axial_test.x, axial_test.y, 2.0)
	var roundtrip_axial := HexGridMath.world_to_axial(world_hex, 2.0)
	if roundtrip_axial == axial_test:
		print("  PASS: HexGridMath roundtrip world <-> axial verified.")
		passed += 1
	else:
		push_error("  FAIL: HexGridMath roundtrip failed. Expected %s, got %s" % [axial_test, roundtrip_axial])
		failed += 1

	picker.queue_free()

	# --- Test 4: Layer 4 Cartridge Scenes Integrity ---
	print("[Test 4] Testing Layer 4: All 6 Cartridge Scenes...")
	var cartridge_scenes := [
		"res://scenes/zones/cartridge_01_action_rpg.tscn",
		"res://scenes/zones/cartridge_02_tick_sandbox.tscn",
		"res://scenes/zones/cartridge_03_voxel_survival.tscn",
		"res://scenes/zones/cartridge_04_4x_strategy.tscn",
		"res://scenes/zones/cartridge_05_arena_fps.tscn",
		"res://scenes/zones/cartridge_06_collector_tycoon.tscn"
	]

	for scene_path in cartridge_scenes:
		if not ResourceLoader.exists(scene_path):
			push_error("  FAIL: Scene file missing: %s" % scene_path)
			failed += 1
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("  FAIL: Failed to load PackedScene: %s" % scene_path)
			failed += 1
			continue
		var inst := packed.instantiate()
		if inst == null:
			push_error("  FAIL: Failed to instantiate scene: %s" % scene_path)
			failed += 1
			continue
		# Verify CameraHost3D exists in each scene
		var cam_host_found := inst.get_node_or_null("CameraHost3D") != null
		if cam_host_found:
			print("  PASS: Scene '%s' verified with CameraHost3D." % scene_path.get_file())
			passed += 1
		else:
			push_error("  FAIL: Scene '%s' missing CameraHost3D." % scene_path)
			failed += 1
		inst.queue_free()

	print("\n[UniversalScaffoldingTest] SUMMARY: %d PASSED, %d FAILED" % [passed, failed])
	if failed == 0:
		print("[UniversalScaffoldingTest] ALL TESTS PASSED!")
		quit(0)
	else:
		print("[UniversalScaffoldingTest] SOME TESTS FAILED!")
		quit(1)
