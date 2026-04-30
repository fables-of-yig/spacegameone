# Imported Entity/NPC Setup Plan

Goal: make the imported enemy, boss, NPC, pickup, and FX assets usable as authored, placeable entities in the existing Godot content/editor/runtime systems.

Current diagnosis:

- `Content/demo/Entities/entities.json` has 372 entity definitions, but 354 of the definitions with `sprite_set` point at missing flat paths such as `Sprites/basement_bosses_pack_1`.
- The converted sprite folders already exist mostly under categorized paths: `Content/demo/Sprites/001_Enemies` has about 599 top-level sprite-set folders, and `Content/demo/Sprites/002_NPCs` has about 50.
- `EntIO.list_sprite_sets()` can already discover nested sprite-set folders, so the runtime/editor can use paths like `Sprites/001_Enemies/basement_bosses_pack_1` if the registry points there.
- The room placement modal currently filters only by broad category (`enemy`, `boss`, `interactable`, `pickup`) and presents a long flat dropdown. With hundreds of imports, it needs grouping/search labels or the content will technically exist but be hard to use.
- Runtime dispatch is category-driven in `MV/scripts/room_manager.gd`: `enemy` and `boss` instantiate `MvEnemy`/`MvBoss`, `interactable` instantiates `MvInteractable`, `pickup` instantiates `MvPickup`, and `logic` instantiates `MvTriggerVolume`. The `scene` field is mostly registry/editor metadata for these generic categories.

## Phase 1: Relink Existing Converted Sprite Sets

1. Build a verification script that scans `Content/demo/Sprites/**/poses.json` and all sibling `.png` files.
2. For each entity in `Content/demo/Entities/entities.json`, resolve its `sprite_set` by entity id:
   - Prefer exact folder name matches under `Sprites/001_Enemies`, `Sprites/002_NPCs`, and later categorized folders.
   - If there are duplicate names, prefer category-compatible folders: enemies/bosses under `001_Enemies`, interactables under `002_NPCs`, pickups under a future `003_Pickups`.
   - Record unresolved entries in a report instead of silently leaving broken references.
3. Rewrite only the `sprite_set` paths that can be resolved confidently.
4. Add a repeatable validation command that reports:
   - entity count by category
   - missing `sprite_set` paths
   - sprite sets with no matching entity
   - entities with unknown behaviors
   - sprite folders missing `poses.json`

Success criteria:

- Existing entities point to real nested sprite-set paths.
- Room placement previews load for imported enemies/NPCs.
- Runtime can spawn the relinked entities without placeholder squares unless the source art is genuinely missing.

## Phase 2: Normalize Entity Records

1. Add stable folder metadata to entity definitions without breaking runtime:
   - `placement_folder`: editor grouping path, for example `Enemies/Basement`, `Enemies/Cyberpunk/Police`, `Bosses/Cave`, `NPCs/Town`, `NPCs/Traders`.
   - `source_pack`: original asset pack/folder name.
   - `import_status`: `linked`, `needs_review`, `missing_sprite`, or `fx_only`.
2. Normalize existing stats with the current runtime fields:
   - `movement_mode`
   - `behavior`
   - `hp`
   - `attack_damage`
   - `contact_damage`
   - `contact_cooldown`
   - `move_speed`
   - `projectile_damage`
   - `projectile_speed`
   - `melee_range`
   - `projectile_range`
   - attack trigger frame fields when attack animations exist.
3. Preserve all existing hand-authored entities and user edits. Do not delete registry rows unless the validation report proves they are duplicates.

Success criteria:

- Every imported row can be filtered by useful placement folders.
- Existing behavior editor and entity editor still edit the same JSON records.
- Existing room placements keep working because entity ids stay stable.

## Phase 3: Import Remaining Packs

1. Treat `Content/demo/Sprites/001_Enemies` and `002_NPCs` as the first-class converted source, not the external raw asset folder.
2. For each unregistered sprite-set folder, generate an entity record using the same generic runtime categories:
   - `boss` when the path/name indicates boss or large boss pack.
   - `enemy` for combat actors.
   - `interactable` for town/civilian/trader/NPC packs.
   - `pickup` for coins, keys, chests, items, and collectable objects once the pickup folder is separated.
   - `fx` only for death effects, projectiles, muzzle flashes, explosions, and non-placeable animation helpers.
3. Keep the import idempotent:
   - It must update existing generated records.
   - It must not overwrite hand-authored fields unless explicitly marked as generated/default.
   - It must write an import report every run.
4. Extend or replace `tools/import_npc_enemy_defaults.ps1` so it supports the current nested destination folders and does not regenerate broken flat paths.

Success criteria:

- Dozens of packs become registry-backed entities, not just basement enemies.
- Re-running the importer is safe after new art folders are dropped in.
- Unusable FX/projectile-only folders are reported separately instead of cluttering the placement list.

## Phase 4: Improve Placement UX

1. Update `Space/scripts/editor/env/env_entity_modal.gd` so the entity picker is usable with hundreds of entries:
   - Show `placement_folder / name (id)` in the option label.
   - Sort by `placement_folder`, then `name`, then `id`.
   - Keep the existing category filter so enemy placement only shows `enemy` and `boss`, NPC placement only shows `interactable`, etc.
2. Update the entity editor list to show folder/category context:
   - Keep category color dots.
   - Display `placement_folder` as the secondary label before falling back to `sprite_set`.
3. If OptionButton becomes too unwieldy, replace the modal picker with a searchable list, but do this only after the data is corrected.

Success criteria:

- Designers can find packs by theme/category rather than scrolling hundreds of flat ids.
- The same entity records remain editable through the current Entity Editor and Behavior Editor.

## Phase 5: Pose and Runtime Quality Pass

1. Validate each sprite set has a usable default pose:
   - Prefer `idle.png`.
   - Fall back to `walk.png`, `fly.png`, or the first PNG only when necessary.
2. Normalize `poses.json`:
   - `frames`
   - `fps`
   - `loop_from`
   - optional `y_offset` for foot alignment.
3. Add `anim_aliases` only where automatic runtime aliases are insufficient. Current runtime aliases already map states like `idle`, `move`, `attack`, `hurt`, `death`, `jump`, and `fall`.
4. Add collision/combat tuning passes by archetype:
   - flyers: `movement_mode = fly`, `flyer_basic` or `flyer_ranged`
   - ranged enemies: `ranged_attacker` or `stationary_attacker`
   - jumpers/slimes/toads/imps: `jumper`
   - bosses: `boss_phased`
   - passive NPCs: no combat behavior, optional `npc_idle`

Success criteria:

- Spawned imports animate with sensible default poses.
- Ground/flying enemies use the correct physics and AI leaves.
- Melee/projectile attacks line up with authored attack frames when possible.

## Phase 6: Validation and Regression Tests

1. Add a small scriptable validation pass under `tools/`:
   - Parse `entities.json`.
   - Resolve every `sprite_set` through `EntIO` path rules or direct filesystem path checks.
   - Parse every referenced `poses.json`.
   - Check every non-empty `behavior` exists in `behaviors.json`.
   - Print a compact summary and fail non-zero on broken references.
2. Run the existing content validator after registry updates.
3. Create one test room or fixture room containing representative placements:
   - one basement enemy
   - one non-basement enemy pack
   - one boss
   - one flying enemy
   - one ranged enemy
   - one NPC/interactable
   - one pickup if pickup imports are included.

Success criteria:

- Broken references are caught before opening the editor.
- A room can place and preview multiple imported packs from different categories.
- Runtime spawn uses real sprites and behaviors instead of placeholders.

## Recommended Execution Order

1. Write the validator/report script first.
2. Relink current `entities.json` to the existing nested sprite folders.
3. Verify previews/spawns for a sample of relinked enemies and NPCs.
4. Add `placement_folder` metadata and sort/group editor labels.
5. Generate missing entity records for unregistered sprite sets.
6. Do pose/stat cleanup by archetype, starting with the largest imported pack families.

