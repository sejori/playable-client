# playable-client (Open-Core Universal Client & Action-RPG Cartridge)

**License:** MIT  
**Engine:** Godot 4.7+ (`JoltPhysics3D` default, `IKModifier3D`, `FastNoiseLite`)

## Overview

`playable-client` is the open-source Universal Client and Starter Cartridge #1 (`template-action-rpg` — **The Boiling Iron Rig**) for `playable.gg`.

### Included Core Systems
- **`autoloads/BootLoader.gd`**: Detects `--headless` / `--server` mode and streams/mounts AST-sandboxed `.pck` resource packs inside `user://realms/<realm_id>/`.
- **`autoloads/PuppetServer.gd`**: Local HTTP server (`127.0.0.1:9090`) implementing `/health`, `/state`, `/teleport`, `/input`, and `/screenshot?mode=quad_debug`.
- **`autoloads/TelemetryLogger.gd`**: Structured JSONL telemetry emitter (`NAV_STUCK`, `COMBAT_SUMMARY`).
- **`autoloads/ProceduralJobRunner.gd`**: `WorkerThreadPool` task dispatcher for off-main-thread procedural generation.
- **`autoloads/NetworkManager.gd`**: Authoritative ENet UDP (`7777+`) multiplayer peer manager.
- **`autoloads/VoiceArchitectClient.gd`**: Push-to-talk (`L1`) + 3D camera raycast anchor client.
- **`tools/security_scanner.py` & `tools/contract_validator.py`**: Static AST sandbox linter and scene contract verifier.
