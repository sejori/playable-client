#!/usr/bin/env python3
"""
record_template_showcase.py
Universal Showcase Capture & Transcode Pipeline for Playable Starter Templates.
Captures 180 frames @ 60 FPS in Godot (Windows Movie Maker mode) and transcodes to:
- .webm (VP9, CRF 28, 2M)
- .mp4 (H.264, CRF 22, yuv420p)
- -poster.jpg (MJPEG 1 frame @ 1.0s)
"""

import sys
import os
import subprocess
import json
from pathlib import Path

TEMPLATES = {
    "action-rpg": {
        "id": "template-action-rpg",
        "cartridge": "01",
        "title": "Action-RPG Dungeon Crawler",
        "scene": "res://scenes/zones/cartridge_01_action_rpg.tscn",
        "prompt": "Create a dark volcanic cathedral abyss with cracked obsidian pavers, glowing lava hazard vents, and an enraged monolithic Golem Brute guarding the central seal.",
        "result": "Result: Volcanic Golem Abyss",
        "badge": "Action RPG"
    },
    "tick-sandbox": {
        "id": "template-tick-sandbox",
        "cartridge": "02",
        "title": "Tick-Based MMO Sandbox",
        "scene": "res://scenes/zones/cartridge_02_tick_sandbox.tscn",
        "prompt": "Build a nostalgic medieval village square with 600ms tick-synchronized oak tree chopping, iron mining rock veins, banking booth vault, and radial gathering progress rings.",
        "result": "Result: Medieval Lumbridge Square",
        "badge": "Tick Sandbox"
    },
    "voxel-survival": {
        "id": "template-voxel-survival",
        "cartridge": "03",
        "title": "Voxel Sandbox & Survival",
        "scene": "res://scenes/zones/cartridge_03_voxel_survival.tscn",
        "prompt": "Generate a multi-layered procedural block world with stone caves, dirt topsoil, leafy forest canopies, block-step terrain navigation, and a 9-slot building hotbar.",
        "result": "Result: Procedural Block Wilderness",
        "badge": "Voxel Survival"
    },
    "4x-strategy": {
        "id": "template-4x-strategy",
        "cartridge": "04",
        "title": "4X Strategy & Turn-Based Tabletop",
        "scene": "res://scenes/zones/cartridge_04_4x_strategy.tscn",
        "prompt": "Construct an axial hexagonal battlefield with varied biome elevations, strategic plains and mountains, command card action hands, and gold-crested knight pawns.",
        "result": "Result: Hex Tabletop Realm",
        "badge": "4X Strategy"
    },
    "arena-fps": {
        "id": "template-arena-fps",
        "cartridge": "05",
        "title": "Arena Hero FPS",
        "scene": "res://scenes/zones/cartridge_05_arena_fps.tscn",
        "prompt": "Design a high-octane 3-lane sci-fi industrial arena with steel bunker walls, tactical waist-high cover barricades, health recovery pads, and high-velocity blaster combat.",
        "result": "Result: Sci-Fi Bunker Arena",
        "badge": "Arena FPS"
    },
    "collector-tycoon": {
        "id": "template-collector-tycoon",
        "cartridge": "06",
        "title": "Collector & Idle Tycoon",
        "scene": "res://scenes/zones/cartridge_06_collector_tycoon.tscn",
        "prompt": "Create a neon-lit rollercoaster circuit speedway with floating gold tokens, radiant ruby gems, glowing boost pads, and neon 2x multiplier gates.",
        "result": "Result: Neon Speedway Tycoon",
        "badge": "Collector Tycoon"
    }
}

def get_ffmpeg_exe():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"

def run_capture(slug: str):
    if slug not in TEMPLATES:
        print(f"Unknown template slug: {slug}. Available: {list(TEMPLATES.keys())}")
        sys.exit(1)
    
    cfg = TEMPLATES[slug]
    root_dir = Path(__file__).resolve().parent.parent.parent
    client_dir = root_dir / "playable-client"
    web_showcase_dir = root_dir / "playable-web" / "public" / "showcase"
    web_showcase_dir.mkdir(parents=True, exist_ok=True)
    
    avi_rel_path = f"build/capture_{slug}.avi"
    avi_full_path = client_dir / "build" / f"capture_{slug}.avi"
    avi_full_path.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"=== Capturing Showcase: {cfg['title']} ({slug}) ===")
    print(f"Scene: {cfg['scene']}")
    print(f"Prompt: {cfg['prompt']}")
    
    # Run Godot Movie Writer (without --headless on Windows per AGENTS.md Rule 4.2)
    cmd = [
        "godot",
        "--path", str(client_dir),
        "--write-movie", avi_rel_path,
        "--fixed-fps", "60",
        "--quit-after", "180",
        cfg["scene"]
    ]
    print(f"Executing: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error during Godot recording: {res.stderr}")
        sys.exit(res.returncode)
        
    if not avi_full_path.exists():
        print(f"Error: Expected AVI output not found at {avi_full_path}")
        sys.exit(1)
        
    print(f"Recorded AVI: {avi_full_path.stat().st_size} bytes")
    
    # Transcode with ffmpeg
    ffmpeg = get_ffmpeg_exe()
    webm_out = web_showcase_dir / f"{slug}.webm"
    mp4_out = web_showcase_dir / f"{slug}.mp4"
    poster_out = web_showcase_dir / f"{slug}-poster.jpg"
    
    # 1. WebM (VP9)
    cmd_webm = [
        ffmpeg, "-y", "-i", str(avi_full_path),
        "-c:v", "libvpx-vp9", "-b:v", "2M", "-crf", "28", "-an",
        str(webm_out)
    ]
    subprocess.run(cmd_webm, check=True, capture_output=True)
    print(f"Transcoded WebM: {webm_out.name} ({webm_out.stat().st_size} bytes)")
    
    # 2. MP4 (H.264)
    cmd_mp4 = [
        ffmpeg, "-y", "-i", str(avi_full_path),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22", "-an",
        str(mp4_out)
    ]
    subprocess.run(cmd_mp4, check=True, capture_output=True)
    print(f"Transcoded MP4: {mp4_out.name} ({mp4_out.stat().st_size} bytes)")
    
    # 3. Poster Image (JPG at 1.0s)
    cmd_poster = [
        ffmpeg, "-y", "-ss", "00:00:01", "-i", str(avi_full_path),
        "-vframes", "1", "-q:v", "2",
        str(poster_out)
    ]
    subprocess.run(cmd_poster, check=True, capture_output=True)
    print(f"Extracted Poster: {poster_out.name} ({poster_out.stat().st_size} bytes)")
    
    # Update showcase registry JSON
    registry_file = root_dir / "playable-web" / "src" / "data" / "showcase_cartridges.json"
    registry_file.parent.mkdir(parents=True, exist_ok=True)
    
    registry = []
    if registry_file.exists():
        try:
            with open(registry_file, "r", encoding="utf-8") as f:
                registry = json.load(f)
        except Exception:
            registry = []
            
    # Update or append
    item_data = {
        "slug": slug,
        "id": cfg["id"],
        "cartridge": cfg["cartridge"],
        "title": cfg["title"],
        "badge": cfg["badge"],
        "prompt": cfg["prompt"],
        "result": cfg["result"],
        "videoWebm": f"./showcase/{slug}.webm",
        "videoMp4": f"./showcase/{slug}.mp4",
        "poster": f"./showcase/{slug}-poster.jpg"
    }
    
    existing_idx = next((i for i, item in enumerate(registry) if item.get("slug") == slug), None)
    if existing_idx is not None:
        registry[existing_idx] = item_data
    else:
        registry.append(item_data)
        
    with open(registry_file, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2)
        
    print(f"Showcase registry updated at: {registry_file}")
    print(f"=== Showcase for {slug} COMPLETE ===")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: record_template_showcase.py <template-slug>")
        print(f"Available: {list(TEMPLATES.keys())}")
        sys.exit(1)
    run_capture(sys.argv[1])
