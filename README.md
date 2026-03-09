# TestVibeGame - Setup & Instructions

I've set up the core mechanics for your 3rd person spear-throwing game with full multiplayer support!

## Included Files
- **Player.gd / Player.tscn**: The player character with movement, camera, and health/stamina syncing.
- **Spear.gd / Spear.tscn**: The spear projectile with physics and network synchronization.
- **World.tscn**: Procedurally generated terrain with targets, enemies, and collectibles.
- **Mammoth.gd / Mammoth.tscn**: The primary enemy type with complex AI behaviors.

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
   - In the **first window**, click the **Host Game** button.
   - Enter a **Seed Word** (or leave random) and click **Start Game**.
   - In the **second window**, click the **Join Game** button.
   - You should now see both players in the world!

## Controls
- **WASD / Arrow Keys**: Move the character.
- **Shift**: Sprint (drains stamina).
- **Mouse**: Rotate the camera.
- **Left Click**: Attack / Throw Weapon.
- **1, 2, 3**: Switch Weapons (Spear, Rock, Fire Spear).
- **Space**: Jump.
- **Esc**: Release the mouse cursor.

## Mechanics
- **Combat**: 
  - **Spear**: Sticks to enemies/walls. High accuracy.
  - **Rock**: Knocks enemies back. Bounces.
- **Fire Spear**: Ignites trees and enemies.
- **Enemies**: 
  - **Mammoth**: Large megafauna that charges players. Can be headshot for extra effect.
- **Environment**:
  - **Trees**: Interactive forests that can catch fire from Lightning or Fire Spears, spreading fire and damage.
  - **Mustard Lakes**: Water bodies at low elevations.
  - **Weather**: Dynamic lightning strikes that can hit and ignite trees.
- **Collectibles**: Red items restore health, Green items give a temporary speed boost.

## Documentation
For a deeper dive into how the netcode works, check out [GODOT_NETWORKING_DOCS.md](GODOT_NETWORKING_DOCS.md).
