# TestVibeGame - Setup & Instructions

I've set up the core mechanics for your 3rd person spear-throwing game with full multiplayer support!

## Included Files
- **Player.gd / Player.tscn**: The player character with movement, camera, and health/stamina syncing.
- **Spear.gd / Spear.tscn**: The spear projectile with physics and network synchronization.
- **World.tscn**: Procedurally generated terrain with targets, enemies, and collectibles.

## How to Play
1. Open the project in Godot 4.
2. Open **World.tscn**.
3. Press **F5** to run the main scene.

## 🌐 Multiplayer Setup (Testing with Instances)
To test the multiplayer on your own computer, you need to run two or more instances of the game:

1. **Enable Multiple Instances**:
   - In the Godot Editor, go to the top menu: **Debug** > **Run Multiple Instances**.
   - Select **Run 2 Instances** (or more).
2. **Start the Game**:
   - Press **F5** to run the game. Two windows will open.
3. **Connect**:
   - In the **first window**, click the **Host** button.
   - In the **second window**, click the **Join** button.
   - You should now see both players in the world!

## Controls
- **WASD / Arrow Keys**: Move the character.
- **Shift**: Sprint (drains stamina).
- **Mouse**: Rotate the camera.
- **Left Click**: Throw a spear.
- **Space**: Jump.
- **Esc**: Release the mouse cursor.

## Mechanics
- **Health**: Syncs across the network. If it reaches 0, you will respawn at the center.
- **Stamina**: Required for sprinting. Regens over time.
- **Enemies**: Will chase you and deal damage on contact.
- **Collectibles**: Red items restore health, Green items give a temporary speed boost.

## Documentation
For a deeper dive into how the netcode works, check out [GODOT_NETWORKING_DOCS.md](GODOT_NETWORKING_DOCS.md).
