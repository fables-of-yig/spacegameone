# Authoring Systems Execution Plan

Goal: make SpaceboatMania a top-to-bottom authoring tool for a large-scale open-universe metroidvania/space game. The target breadth is Warcraft 3 World Editor: worlds, triggers, entities, AI, quests, shops, dialogue, UI, gameplay data, and Space/MV traversal, but with creator-facing recipes instead of raw JSON and id wiring.

Every supported feature must follow this path:

`editor -> JSON pack data -> validation -> pack load -> runtime behavior -> smoke test -> docs`

## Phase 0: Contract Truth And Fallback Lockdown

Status: completed.

Rules:

- `SUPPORTED_FEATURES.md` must be generated from `Space/scripts/ui/ui_contract.gd`.
- Unknown or unmounted authored UI screens are validation errors.
- Missing live data for known UI bindings resolves to `null` so runtime diagnostics render visibly.
- Behavior trees cannot fall back from unknown actions/conditions to `idle` or `always`.
- Content validation must not borrow demo JSON to prove another pack is valid.

Initial completed work:

- Synced authored UI support docs with the runtime contract.
- Promoted unknown/unmounted UI screens from warnings to errors.
- Added `shop:<id>` target validation for authored UI `open_screen` actions.
- Changed MV UI binding resolver missing-source behavior from zero/empty placeholders to `null`.
- Made behavior action/condition lookup fail closed.
- Added behavior tree validation for unknown node types, bad child counts, and unknown leaves.
- Made content validation strict for generic JSON roots, pack manifests, dialogue ids, and shop ids.
- Fixed validation CLI compile blockers from direct autoload symbol references.

## Phase 1: Pack Bootstrap And Campaign Start

Status: completed.

Build a fresh-pack workflow that creates a playable authored campaign without relying on demo fallback.

Required bootstrap data:

- `Pack.json` with `schema_version`, `pack_id`, `start_system`, `start_ship_template`, `start_realm`, and `entry_room`.
- `Systems/systems.json` with a start system and one planet POI wired to authored landing data.
- Starter ship and module data, preferably pack-scoped.
- Realm/region/room hierarchy with a start room and player spawn.
- Stock UI screens and input map.
- Player stats, attacks, items, equipment, abilities, projectiles, sprites, and poses.

Open decisions:

- Whether `start_ship_template` points to global NPC templates temporarily or pack-local `Ships/*.json`.
- Whether module definitions become pack-local immediately or use an overlay on global module data.
- Canonical room start path: `start_realm + realm.start_region + region.start_room`, with `entry_room` as compatibility.

## Phase 2: Runtime Integration Spine

Make Space, planet landing, MV, save/load, and return-to-space agree on authored identity and state.

Status: completed.

Required work:

- Planet destination contract: `pack_id`, `realm_id`, `region_id`, `spawn_room`, `spawn_pos`, return/orbit state, stable planet snapshot key.
- Remove silent demo routing for authored planet POIs.
- Expand `PlanetaryInterface` snapshots for room, player, inventory, vars, planet flags, and global flags where appropriate.
- Validate Space POI events, NPC hail events/templates, hull/static sprite paths, spawn trigger enemy classes, star/POI/background assets.
- Expose system background image authoring.

Initial completed work:

- Space planet POIs now carry a stable `planet_key` derived from system/id/name, so multiple planets in one pack no longer collide on one pack-level snapshot.
- `PlanetaryInterface` snapshots are keyed by planet identity and now include MV player, room, inventory, room state, map visited data, trigger global tags, planet flags, and global flags.
- MV return-to-overworld snapshots current MV state before tearing down the room layer.
- Hosted MV landings now require an explicit staged pack id; standalone dev can still boot `demo`.
- Authored planet landing no longer silently falls through to the demo manifest.
- Added authored trigger action `return_to_space`.
- Space saves now persist active pack id and `PlanetaryInterface` state.
- Validator coverage now checks more of authored systems, planet identity, planet region/spawn position, system/POI assets, spawn triggers, and placed NPC references.
- Trigger runtime snapshots now include persistent rule locals and runtime rule enabled/disabled state.
- Added `tools/phase2_runtime_smoke.gd`, a headless smoke that bootstraps a pack, stages a planet landing, snapshots MV state, clears state, restores it, and verifies inventory, room state, map visited state, trigger tags, planet flags, and player snapshot data.
- Added `tools/runtime_smoke_cli.gd`, a fuller authored-route smoke that instantiates `Space/scenes/main.tscn`, enters the real MV scene through the Space planet handler, seeds observable progression state, returns to Space, and verifies Space save/load preserves the planet snapshot.
- The system editor now exposes `background_image` authoring with picker/import/clear behavior.
- Fresh pack bootstrap now writes a pack-local starter player sheet, and the MV player scene no longer preloads the demo player texture.
- The authored MV HUD waits for its player/room data sources before mounting, so missing bindings still diagnose real authoring errors without producing teardown noise.
- Beehave debugger capture cleanup now unregisters cleanly during headless shutdown.
- Phase 2 validation is now covered by `tools/validate_ui_contract.ps1 -RuntimeSmoke -AuthoredRouteSmoke`.

## Phase 3: Golden Open-Universe Pack

Status: completed.

Create one canonical pack that proves the whole authoring stack.

Required route:

- Authored systems and two planets.
- One overworld realm and one MV region.
- Multiple connected rooms with doors.
- NPC, dialogue, shop, trigger chain, item/ability pickup, locked gate.
- Enemy with behavior tree and drops.
- Boss intro/cinematic.
- POI event and system background.
- Space -> planet/atmosphere -> MV -> return-to-space loop.
- Save/load through authored progression.

Initial completed work:

- Added `tools/golden_pack_cli.gd`, a reproducible golden-path pack generator and runtime smoke harness.
- The generated `golden_path` pack includes two authored systems, two planet POIs, one event POI, a realm/region hierarchy, five connected MV rooms, player spawns, door zones, a locked boss gate, an exit-to-space door, a pickup, an NPC, dialogue, a shop, an enemy behavior tree, a trigger-volume boss intro, and a boss-defeat progression chain.
- Static validation now proves the pack has no missing references across manifest, systems, POIs, rooms, entities, behaviors, items, abilities, dialogue, shops, triggers, and world hierarchy.
- Runtime smoke boots through `Space/scenes/main.tscn` into the authored MV room and verifies the pickup trigger grants `phase_dash`, sets progression vars/tags, unlocks `gate_to_boss`, and the boss-defeat trigger grants `boss_core`, unlocks `boss_exit`, and records completion.
- `tools/validate_ui_contract.ps1 -GoldenPathSmoke` now runs the golden-path rebuild, validation, and runtime smoke from the same project validation entrypoint.

## Phase 4: Natural-Language Authoring

Replace raw schema editing with creator-facing recipes and pickers.

Examples:

- Make a locked door that needs a key.
- Make an NPC conversation that opens a shop.
- Make a planet land in this region.
- Make an ability gate.
- Make a boss intro play.
- Make a UI button fire a trigger.

Advanced JSON can remain available, but it must still validate.

Status: in progress.

Initial completed work:

- Added a Trigger Editor `Recipe` menu with creator-facing rule starters for key pickup gate unlocks, NPC conversation triggers, boss intro zones, boss-defeat rewards, and UI-button story events.
- Moved recipe generation into `Space/scripts/editor/dlg/trigger_recipes.gd` so recipes are reusable and headlessly testable instead of being locked inside UI code.
- Added `tools/trigger_recipe_smoke.gd`, which bootstraps a pack, seeds the referenced items/abilities/entities/dialogue, emits all trigger recipes, saves them through `PedIO.save_triggers`, and validates them with `ContentValidator`.
- `tools/validate_ui_contract.ps1 -TriggerRecipeSmoke` now runs the recipe schema smoke from the standard validation entrypoint.
- Added `Space/scripts/editor/recipes/planet_landing_boss_recipe.gd`, a reusable world recipe that creates a valid planet landing route, realm/region rooms, key pickup, locked gate, boss intro zone, boss reward triggers, and a system planet POI with explicit `region_id`.
- Added `tools/world_recipe_smoke.gd` and `tools/validate_ui_contract.ps1 -WorldRecipeSmoke` to prove the world recipe produces a zero-error pack from a fresh bootstrap.
- Added a World hub tile, `LANDING + BOSS GATE`, that runs the validated world recipe from the creator-facing content hub and reports the resulting validation status in the existing status panel.

## Phase 5: Scale And Production Readiness

Add large-pack ergonomics:

- Prefabs/templates for rooms, NPCs, quests, shops, enemies, POIs, ships, and UI screens.
- Dependency graph: what references this id?
- Batch validation and repair suggestions.
- Pack migration tooling.
- Asset import manifests that create authorable content.
- First-class quest schema with stages, objectives, rewards, save state, and journal/map visibility.

Status: in progress.

Initial completed work:

- Added `Space/scripts/editor/content_reference_index.gd`, a reusable dependency index that scans pack definitions and typed references across Pack.json, systems, realms/regions/rooms, entities, items, equipment, abilities, attacks, global and room triggers, dialogues, shops, and quests.
- Added `tools/reference_index_cli.gd` for headless inspection:
  - `scan --pack <id>` prints definition/reference counts by kind.
  - `refs --pack <id> --kind <kind> --id <id>` prints the source fields that reference one authored id.
- Added `tools/reference_index_smoke.gd`, which builds the validated landing/boss recipe pack and asserts the index finds boss item drops, trigger reward/spawn references, and manifest room references.
- Added `tools/validate_ui_contract.ps1 -ReferenceIndexSmoke` so the dependency index is covered by the standard validation entrypoint.
- Added a `REFERENCE LOOKUP` tile in the suite Playtest tab. It opens an in-editor lookup dialog where authors choose a content kind, enter an id, and see every source field that references it.
- Added reference-aware entity authoring guards: entity delete now shows the references that will break before confirming, and entity rename warns when the id is already used by rooms, triggers, or other authored data.
- Added `Space/scripts/editor/content_reference_refactor.gd`, a reusable rename service that rewrites known typed references across Pack.json, systems, flat and regional rooms, global and room triggers, dialogues, shops, quests, items, equipment, abilities, attacks, and entity drops/behaviors.
- Entity rename now uses the refactor service, so renaming an entity id updates known room placements, trigger payload checks, and trigger spawn/despawn actions instead of only warning.
- Behavior rename now uses the same refactor path, so entities bound to a behavior id are updated when that behavior id changes.
- Item registry rename in the Shop/Items editor now uses the refactor service, so pickups, locked doors, trigger item checks/actions, shop stock, and entity drops can follow an item id change.
- Room rename in the Region Editor now runs a safe room-reference rewrite after the structural `RegIO.rename_room`, then reflattens runtime rooms so manifest entry rooms, planet spawn rooms, room links, and trigger room actions stay coherent.
- The refactor service now has a room-address helper that handles full `realm/region/room` references, `region/room` references, and region-scoped local room references without blindly rewriting local ids everywhere.
- The dependency index and refactor service now track attack combo follow-up refs in addition to charged attack refs.
- Player editor Ability, Attack, and Projectile id edits now call the shared refactor service; attack id edits also update currently open attack chain refs in memory.
- `tools/reference_refactor_smoke.gd` now proves entity, behavior, item, system, room, ability, projectile, attack, dialogue, and shop renames update references and still validate through `tools/validate_ui_contract.ps1 -ReferenceRefactorSmoke`.
- Added `Space/scripts/editor/quest_io.gd` plus first-class quest validation for stages, objectives, rewards, and references to items, abilities, entities, rooms, dialogues, shops, and events.
- Added quest dependency/refactor coverage so quest objectives and rewards appear in reference lookup and follow typed id renames.
- Added `Space/scripts/editor/quest_editor.gd`, mounted from the content hub and editor chooser, so authors can create quests, stages, objectives, and rewards without touching JSON.
- Quest progress is explicitly trigger-driven, WC3-style: trigger events/conditions decide when to run, and quest actions start quests, set stages, complete objectives/stages, or complete quests. Runtime quest state is stored inside the trigger snapshot.
- Added `tools/quest_schema_smoke.gd` and `tools/validate_ui_contract.ps1 -QuestSchemaSmoke`, proving a quest can be authored, validated, indexed, refactored, and revalidated.
