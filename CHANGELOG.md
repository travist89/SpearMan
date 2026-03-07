# Changelog

## [Unreleased] - 2026-03-07

### Added
- **Mammoth Enemy Improvements:**
  - Added randomized tail length and girth scaling (synced over network).
  - Implemented body part-specific hit detection (Head, Tail, Legs) by reparenting collision shapes to visual bones.
  - Added complex death animation logic where the Mammoth falls over using a Tween on a separate `VisualRoot` node, decoupling it from physics rotation.
  - Added "Rear Up" intimidation animation state.
- **World Generation:**
  - Added Seed input UI to ensure all players generate the exact same terrain.
  - Unified terrain height calculation logic (`get_height_at`) to ensure objects (Trees, Rocks, Grass) snap perfectly to the ground.
  - Added "Mustard Lakes" (yellow water) at low elevations.
- **Combat & Gameplay:**
  - Added "Fire Spear" weapon (switched via keys 1-3).
  - Added "Grass Patch" logic: grass catches fire from Fire Spears, spreads to neighbors, and damages entities standing in it.
  - Added "Rock" weapon with knockback physics.
  - Added "Collectible" items (Health and Speed) with proper server-side validation.
- **Documentation:**
  - Added extensive comments to all major script files (`Mammoth.gd`, `World.gd`, `Player.gd`, `Spear.gd`, etc.) explaining network architecture and game logic.

### Changed
- **Removed Cat Enemy:** The generic `Cat.gd` and `Enemy.tscn` have been removed in favor of the more complex Mammoth AI.
- **Optimization:**
  - Reduced Grass Patch density significantly to improve performance.
  - Implemented AI tick rate throttling (Mammoths update logic 5 times/second instead of 60).
  - Added players to a "players" group for faster lookup by AI.
- **Refactoring:**
  - `Spear.gd` now handles "sticky" logic using `RemoteTransform3D` instead of reparenting, ensuring network stability.
  - `World.gd` now manages the day/night cycle and environment settings centrally.

## [Fixed] - 2026-03-01

### Critical Bug Fixes
- **Infinite Enemy Spawning & Sync Issues:**
  - Fixed a critical bug in `World.gd` where `MultiplayerSpawner.spawn_path` was set to `.` (the spawner itself) instead of `..` (the World node).
  - This caused spawned enemies to be children of the spawner, hiding them from `World.gd`'s enemy count logic (`get_children()`), which led to an infinite loop of spawning cats and mammoths.
  - This flood of spawn packets caused network congestion, `ERR_INVALID_DATA` errors on clients, and prevented enemies from appearing correctly.

- **Mammoth "Standing Up" After Death (Host Side):**
  - Fixed a visual glitch where the Mammoth would fall over but then snap back to an upright position and potentially "run in place" on the Host machine.
  - **Solution:** Implemented a "Visual Root" pattern in `Mammoth.gd`.
    - Created a `VisualRoot` node at runtime.
    - Reparented all visual meshes (`Body`, `Head`, `Legs`, etc.) to this `VisualRoot`.
    - Updated the death logic to tween the rotation of `VisualRoot` instead of the root physics node.
    - This ensures that even if the server's physics logic (like `look_at()`) resets the root node's rotation, the visual model remains fallen over.

- **Console Errors:**
  - **Invalid UIDs:** Fixed invalid Unique ID references in `World.tscn` for `Rock.tscn`, `Target.tscn`, and Collectibles.
  - **Multiplayer Active Check:** Added checks in `World.gd` to ensure `multiplayer.has_multiplayer_peer()` is true before accessing network features, preventing "Multiplayer instance isn't currently active" errors.
  - **Replication Config Spam:** Fixed C++ errors caused by improper `MultiplayerSynchronizer` cleanup in `Mammoth.gd`. Now replaces the config with an empty one before freeing the node.
  - **Animation Track Errors:** Updated all animation tracks in `Mammoth.gd` (Idle, Run, RearUp, Dead) to reference the new `VisualRoot` hierarchy (`VisualRoot/Head:rotation`, etc.), resolving "couldn't resolve track" errors.

### Code Improvements
- **Mammoth.gd:**
  - Added robust guards in `_physics_process` to stop logic execution when dead (`is_dead`, `health <= 0`, `state == "dead"`).
  - Explicitly disables collisions and stops animations upon death to prevent "zombie" behavior.
- **World.gd:**
  - Improved spawn logic to be safer and cleaner hierarchy-wise.
