# CLAUDE.md — Autonomous Godot 4.7+ Studio Constitution

## 1. Engine & Environment Rules
- **Target Engine:** Godot 4.7.2-stable (Headless Linux CLI & Universal Client).
- **Default 3D Physics:** `JoltPhysics3D` (`physics/3d/physics_engine="JoltPhysics3D"`). Never use legacy Bullet assumptions.
- **Skeletal IK:** Use Godot 4.7+ native `IKModifier3D` nodes on `Skeleton3D`—never use deprecated `SkeletonIK3D`.
- **Noise Generation:** Always use Godot 4's native `FastNoiseLite`. Never reference Godot 3's `OpenSimplexNoise`.
- **Thread Safety:** Never run procedural generation (`SimpleXTerrain`, `godot-wfc`, `ProtonScatter`, or voxel meshing) synchronously inside `_ready()` on the main thread. Always dispatch heavy generation through `ProceduralJobRunner.run_on_worker_thread()`.

## 2. Multi-Agent File-System Jails
Respect strict role boundaries when executing tickets from `/specs/project_board.json`:
- **Jenny (Orchestrator):** Writes only to `/specs/project_board.json` and `/specs/roadmap.md`.
- **John (Narrative/Design):** Writes only to `/specs/gdd_design.json`, `/data/pandora/**/*.json`, `/data/gloot/**/*.json`, and `/dialogues/**/*.dialogue`.
- **Jane (Systems/Netcode):** Writes only to `/specs/interface_contracts.json`, `/scripts/**/*.gd`, `/autoloads/**/*.gd`, and `/tests/**/*.gd`.
- **Geoff (World/VFX/Audio):** Writes only to `/scenes/**/*.tscn`, `/resources/**/*.tres`, `/shaders/**/*.gdshader`, and `/audio/**/*.tres`. Must obey every node path, signal, and collision layer defined in `/specs/interface_contracts.json`.

## 3. Mandatory Verification Loop (Run Before Committing)
No agent may mark a ticket `DONE` until all four checks return exit code `0`:
1. **Static Security Linter:** `python3 tools/security_scanner.py` (Blocks `OS.execute`, `OS.create_process`, dynamic `GDExtension` loads, and file access outside `user://realms/`).
2. **Headless Syntax & Type Check:** `godot --headless --check-only --path .`
3. **Automated Unit & Contract Tests:** `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/`
4. **Bot Swarm & Visual Probe (For Scene/Gameplay Changes):**
   - Run 60s at 10x speed: `godot --headless --path . --time-scale 10.0 res://scenes/qa/bot_runner.tscn`
   - Verify zero `SCRIPT_ERROR`, `NAV_STUCK`, or `QUEST_SOFTLOCK` in `/tmp/telemetry.jsonl`.
   - Capture 4-panel visual check: `curl -s "http://127.0.0.1:9090/screenshot?mode=quad_debug"` and inspect `/tmp/agent_vision/latest_quad.png`.
