# Welcome to the test-vibe-game Godot Project! 🤖

Hi there! If you're just starting with Godot and want to know how multiplayer works, you're in the right place. This game uses Godot 4's high-level multiplayer tools to make everything sync up.

## 🚀 Getting Started
1. **Open the Project**: Open this folder in Godot 4.
2. **Run the Game**: Click the Play button (top right).
3. **Multiplayer Menu**: 
   - **Host**: Click this on the first window to start the server.
   - **Join**: Run a second instance of the game and click "Join" to connect!

## 🛠️ How it Works (The Simple Version)

### 1. The World (`World.gd`)
The world is created using code! It uses a fixed "seed" (like in Minecraft) so that every player generates the exact same hills, valleys, trees, and rocks locally.
- **Deterministic Generation**: We use `seed(12345)` to ensure that `randf()` produces the same random numbers on every computer. This keeps the world in sync without sending huge amounts of data.
- **MultiplayerSpawner**: This is a magical node that tells Godot: *"Whenever the server creates a player or a spear, make sure every client creates one too!"*

### 2. The Player (`Player.gd`)
- **Authority**: In Godot, each player "owns" their own character. We call this the *Multiplayer Authority*. Only you can move your character!
- **MultiplayerSynchronizer**: This node watches your position and rotation. When you move, it tells all the other players: *"Hey, Player 1 moved to this new spot!"*
- **Stats (Health & Stamina)**: We've set these up to sync automatically so everyone can see your health bar update.

### 3. Enemies (`Enemy.gd`)
- **Server Only**: To keep things fair, the AI logic (finding players and chasing them) only runs on the **Host** (the Server). The clients just see the enemy moving because its position is synced via the `MultiplayerSynchronizer`.

### 4. Throwing Spears (Input in `Player.gd`)
- When you click to throw, your `Player.gd` script sends an **RPC** (Remote Procedure Call) named `throw_projectile` to the server.
- It's like calling the server on the phone and saying: *"Hey, I'm throwing a spear now!"*
- The server then spawns the spear scene (`Spear.tscn`) for everyone to see using the `MultiplayerSpawner`.

## 💡 Beginner Tips
- **Nodes**: Everything in Godot is a Node. If you want to add a new property to sync (like a 'score'), you add it to the `MultiplayerSynchronizer`.
- **Signals**: We use signals (like `pressed`) to connect buttons to our code.
- **Scenes**: Prefabs in Unity are called "Scenes" in Godot. The `Player.tscn` is the blueprint for every player.

## 🆘 Troubleshooting
- **I'm moving but others don't see me!**: Make sure the `MultiplayerSynchronizer` in `Player.tscn` has the `position` property added to its list.
- **The Host can move but the Client can't!**: Check `_physics_process` in `Player.gd`. It should check `is_multiplayer_authority()` before moving.

## 🐛 Critical Fixes Log

### 1. Client Spawning Below Host / Stuck in Ground
We encountered an issue where clients would spawn underground or significantly below the host. This was caused by two things:
1.  **Non-Deterministic Terrain**: The random seed was different for every player, so the "ground" was in a different place for the client than the server. We fixed this by setting a fixed seed `seed(12345)`.
2.  **Physics Conflict**: The client's physics engine was applying gravity to *other* players while the network was trying to set their position. We fixed this by disabling local gravity/input for non-authority players in `Player.gd`.

### 2. Players Not Seeing Each Other / Desync on Join
After implementing the spawn selection menu, players stopped seeing each other. This was caused by a race condition where the client instantiated the player node *before* receiving the correct position from the server, causing it to potentially fall through the world or desync.

**The Fix:**
-   **`MultiplayerSpawner.spawn_function`**: We switched to using Godot's dedicated `spawn_function`. This allows us to pass the initialization data (ID, location index) to the spawner, which then runs a custom `_spawn_player` function on **both** the Server and Client.
-   **Atomic Spawning**: Inside `_spawn_player`, we calculate the exact spawn position (using the deterministic noise) and set `player.position` **before** the node is added to the scene tree. This ensures the player exists at the correct location on frame 1, preventing any physics glitches.
-   **Sync Seed & Regenerate**: We added a `sync_world_settings` RPC that forces the client to use the exact same random seed and noise parameters as the server, and then **regenerates the terrain** locally. This guarantees the ground is identical for everyone.

### 3. Enemy Sync / Invisible "Big" Enemies
We found that "Big Enemies" were not appearing correctly on clients (appearing as normal small enemies). This was because the server was swapping the script (`Enemy.gd` -> `BigEnemy.gd`) at runtime, which does not replicate to clients.

**The Fix:**
-   **Unified Script**: We merged `BigEnemy.gd` into `Enemy.gd` and added an `@export var is_big` flag to toggle behavior.
-   **Custom Spawn Logic**: We extended the `MultiplayerSpawner.spawn_function` to handle enemies too. It passes `{"is_big": true}` to the spawn function, ensuring that when the enemy is instantiated on the client, it immediately knows it should be Big and applies the correct scale and stats before adding it to the tree.

## v1.0 Release Notes 🏆
The project is now considered stable for multiplayer gameplay!
-   **Deterministic World**: Everyone sees the same terrain.
-   **Robust Spawning**: Players spawn safely above ground.
-   **Synced Enemies**: All enemy types appear correctly for all players.

## v1.1 Release Notes 🦣
New content and stability fixes!
-   **New Enemy: Mammoth**: Added a massive new megafauna that wanders peacefully but flees when attacked.
-   **Projectile Fixes**: Restored the spear and rock throwing mechanics to a working state using optimized RPC logic.
-   **Code Cleanup**: Removed obsolete scripts and unified enemy spawning logic.

## v1.2 Release Notes 🔥
Increased intensity and density!
-   **Aggressive Mammoths**: Mammoths are no longer peaceful; they will detect and chase players from a distance.
-   **High Density Spawning**: Increased the enemy population limit to 200 and set the spawn rate to 1 enemy per second on the server.
-   **Mammoth Dominance**: Increased the spawn probability of Mammoths to 40%.

Enjoy making your game! 🚀
