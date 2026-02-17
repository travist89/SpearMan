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
The world is created using code! It uses a "seed" (like in Minecraft) so that every player sees the exact same hills and valleys. 
- **MultiplayerSpawner**: This is a magical node that tells Godot: *"Whenever the server creates a player or a spear, make sure every client creates one too!"*

### 2. The Player (`Player.gd`)
- **Authority**: In Godot, each player "owns" their own character. We call this the *Multiplayer Authority*. Only you can move your character!
- **MultiplayerSynchronizer**: This node watches your position and rotation. When you move, it tells all the other players: *"Hey, Player 1 moved to this new spot!"*
- **Stats (Health & Stamina)**: We've set these up to sync automatically so everyone can see your health bar update.

### 3. Enemies (`Enemy.gd`)
- **Server Only**: To keep things fair, the AI logic (finding players and chasing them) only runs on the **Host** (the Server). The clients just see the enemy moving because its position is synced.

### 4. Throwing Spears (`Spear.gd`)
- When you click to throw, your game sends an **RPC** (Remote Procedure Call) to the server. 
- It's like calling the server on the phone and saying: *"Hey, I'm throwing a spear now!"*
- The server then spawns the spear for everyone to see.

## 💡 Beginner Tips
- **Nodes**: Everything in Godot is a Node. If you want to add a new property to sync (like a 'score'), you add it to the `MultiplayerSynchronizer`.
- **Signals**: We use signals (like `pressed`) to connect buttons to our code.
- **Scenes**: Prefabs in Unity are called "Scenes" in Godot. The `Player.tscn` is the blueprint for every player.

## 🆘 Troubleshooting
- **I'm moving but others don't see me!**: Make sure the `MultiplayerSynchronizer` in `Player.tscn` has the `position` property added to its list.
- **The Host can move but the Client can't!**: Check `_physics_process` in `Player.gd`. It should check `is_multiplayer_authority()` before moving.

Enjoy making your game! 🚀
