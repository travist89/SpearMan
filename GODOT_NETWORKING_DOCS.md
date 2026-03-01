# Age of Manwe - Godot Networking Documentation 🤖

Welcome to the **v1.2 Release** of Age of Manwe! This project is a robust Godot 4 multiplayer prototype focusing on survival hunting.

## 🚀 Quick Start
1. **Open the Project**: Load the folder in Godot 4.
2. **Run the Game**: Press **F6** (Run Scene) on `World.tscn`. 
3. **Multiplayer Menu**:
   - **Host**: Starts the server.
   - **Join**: Connects to a local server.
4. **Spawn Selection**: After connecting, choose a spawn location (Cave, Jungle, Altar).

---

## 🛠️ System Architecture

### 1. Robust Spawning (`World.gd`)
We use a centralized **Spawn Dispatcher** logic. Instead of manual instantiation, all dynamic entities (Players, Mammoths, Enemies) are created via the `MultiplayerSpawner.spawn_function`.
- **Atomic Spawning**: Nodes are initialized with their correct position and properties *before* being added to the scene tree. This prevents "clipping through floor" glitches and sync delays.
- **Unique Naming**: Every entity is assigned a unique `spawn_id`. This guarantees identical node paths (`/root/World/Enemy_123`) on all peers, which is essential for stable replication.

### 2. Deterministic World
To ensure all 12 players see the same environment:
- **Seed Sync**: The Server generates a random seed (`12345`) and sends it to all Clients via the `sync_world_settings` RPC.
- **Forced Regeneration**: Clients regenerate their local terrain mesh and static objects (trees, rocks) only after receiving the Server's seed.
- **Explicit Noise**: All `FastNoiseLite` parameters are hardcoded in `World.gd` to prevent platform-specific defaults from causing desyncs.

### 3. Authoritative AI & Combat
- **Server Authority**: AI logic (state machines, pathfinding) and world events (spawning, damage calculation) run **only on the Server**.
- **Physical Damage**: Damage is applied via direct physical collision (`get_slide_collision`). When an AI body touches a player, it calls the player's `take_damage` RPC.
- **Sync Optimization**: Non-local players and AI disable their complex physics logic on clients, relying purely on the `MultiplayerSynchronizer` for smooth position/rotation updates.

### 4. Client-Side Animation smoothing
To ensure smooth animations on clients despite network interpolation gaps (where position updates might pause momentarily):
- **Timeout Logic**: We use a `run_timeout` (0.2s) in `_process` to hold the "Run" state active. This prevents rapid flickering to "Idle" between network ticks.
- **Blending**: `anim_player.play("Run", 0.2)` is used to smoothly transition animation states.

### 5. Proper Object Deletion
When using `MultiplayerSpawner` to manage networked objects:
- **Server Only**: `queue_free()` must **ONLY** be called on the Server. The `MultiplayerSpawner` will automatically detect the deletion and replicate the despawn to all clients.
- **Avoid Manual Despawn**: Clients should **NEVER** manually `queue_free()` networked objects (even in RPCs like `die()`), as this creates "ghost" objects that the spawner can no longer track or delete.

---

## 🎮 Gameplay Features (v1.2)
- **Aggressive Megafauna**: Mammoths will track players from 25m and attack for massive damage.
- **Continuous Spawning**: The world stays populated with a 200-enemy cap, spawning 1 new enemy per second.
- **Flatter Terrain**: The map has been optimized for high-speed combat and better visibility.
- **High-Jump Movement**: Players have enhanced vertical mobility to navigate the landscape.

## 🆘 Troubleshooting
- **Enemies jittering?**: Check if `MultiplayerSynchronizer` is using `Reliable` or `Always` sync modes.
- **Falling through floor?**: Ensure `create_trimesh_shape()` is called during terrain generation on the peer.
- **Cannot see others?**: Verify the `MultiplayerSpawner` name is identical on both instances.

Enjoy the hunt! 🏹🦣
