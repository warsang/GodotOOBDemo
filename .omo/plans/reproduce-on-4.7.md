# Plan: Reproduce Godot OOB Spawn Vulnerability on 4.7

## Objective
Create a Minimal Reproduction Project (MRP) that demonstrates the uint32 overflow vulnerability in `SceneReplicationInterface::on_spawn_receive()` on **Godot 4.7-stable**, satisfying the Godot maintainers' requirement for a supported version.

## Background

### Vulnerability Confirmed in 4.7
The vulnerable code pattern is **identical** in Godot 4.7:

**File:** `modules/multiplayer/scene_replication_interface.cpp`  
**Line 586:**
```cpp
ERR_FAIL_COND_V_MSG(name_len + (sync_len * 4) > uint32_t(p_buffer_len - ofs), ...)
```

**Overflow math:**
- `sync_len = 0x40000001` (1,073,741,825)
- `sync_len * 4` wraps to `4` in uint32
- `name_len + 4` = `20 + 4` = `24`
- `uint32_t(p_buffer_len - ofs)` = `24`
- `24 > 24` = false → **check PASSES**

The loop at lines 588-591 then iterates ~1 billion times, reading OOB.

### Current State
- Godot 4.7-stable binary downloaded: `godot-4.7-binary/Godot_v4.7-stable_win64.exe`
- Source cloned to `godot-4.7/` for reference
- Existing exploit in `godot-3d-multiplayer-template/` targets 4.4.1

## Implementation Steps

### Step 1: Create MRP Directory Structure
```
mrp-4.7/
├── project.godot
├── scenes/
│   └── main.tscn
└── scripts/
    └── exploit.gd
```

### Step 2: Create `project.godot`
Minimal project configuration:
- Name: "MRP 4.7"
- Main scene: `res://scenes/main.tscn`
- Autoload: `Exploit` → `res://scripts/exploit.gd`
- Renderer: `gl_compatibility` (fastest startup)

### Step 3: Create `scenes/main.tscn`
Simple scene with:
- Root `Node` named "Main"
- Child `MultiplayerSpawner` named "Spawner"
- Attach `exploit.gd` script to root

### Step 4: Create `scripts/exploit.gd`
The exploit script with:
- `GODOT_MODE=server` / `GODOT_MODE=client` environment variable support
- Server: listens on port 4545, grants authority to connecting peer
- Client: connects, sends SIMPLIFY_PATH, then sends malicious SPAWN packet

**Key packet structure for malicious SPAWN:**
```
[0]    cmd = 4 (SPAWN)
[1]    scene_id = 0
[2-5]  cache_id = 0xDEADBEEF (matches SIMPLIFY_PATH)
[6-9]  net_id = 1
[10-13] sync_len = 0x40000001 (THE TRIGGER)
[14-17] name_len = 11 ("ExploitNode")
[18-21] sync_ids[0] = 0
[22-32] name = "ExploitNode"
```

### Step 5: Test the MRP
1. Start server: `Godot_v4.7-stable_win64.exe --path mrp-4.7 --headless` with `GODOT_MODE=server`
2. Start client: `Godot_v4.7-stable_win64.exe --path mrp-4.7` with `GODOT_MODE=client`
3. Observe server crash or error

### Step 6: (Optional) Build Godot 4.7 with ASAN
For definitive proof, build Godot 4.7 with AddressSanitizer:
```powershell
cd godot-4.7
scons platform=windows target=editor dev_build=yes use_asan=yes debug_symbols=yes
```
Then run the MRP and capture the symbolized ASAN report.

## Expected Outcome
- Server crashes or logs an error when processing the malformed SPAWN packet
- If built with ASAN: `heap-buffer-overflow` at `decode_uint32` → `on_spawn_receive`
- Provides definitive proof the vulnerability exists in Godot 4.7-stable

## Files to Create
1. `mrp-4.7/project.godot`
2. `mrp-4.7/scenes/main.tscn`
3. `mrp-4.7/scripts/exploit.gd`

## Success Criteria
- MRP runs without errors on Godot 4.7-stable
- Server crashes or ASAN reports heap-buffer-overflow
- Can be submitted to GitHub issue #121640 as evidence
