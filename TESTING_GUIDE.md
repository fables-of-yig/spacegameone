# SpaceboatMania Testing Guide

This is the current runbook for building and testing one canonical authored pack end to end.

The goal is not to prove every feature at once. The goal is to prove that the current editor, validator, and runtime agree on one small but complete authored path.

Read this together with:
- [SUPPORTED_FEATURES.md](/D:/spacegame2/SUPPORTED_FEATURES.md:1)
- [ROADMAP.md](/D:/spacegame2/ROADMAP.md:1)

## What This Guide Proves

The canonical pack should prove:
- pack creation and pack-aware saves
- authored player, attack, projectile, item, and equipment data
- authored UI screens that match the current contract
- authored systems, realms, regions, and MV rooms
- authored entities and behaviors
- authored dialogue, shops, and triggers
- save/load and failure recovery paths

Target route:

`main_menu -> new game -> authored ship in space -> planet POI -> atmosphere overworld -> landing region -> start room -> hallway -> item room -> gate room -> shop/dialogue room -> combat room -> MV return trigger -> atmosphere -> space`

## Source Of Truth

Use these rules while testing:
- If the editor exposes something not listed in [SUPPORTED_FEATURES.md](/D:/spacegame2/SUPPORTED_FEATURES.md:1), that is a bug.
- If save-time validation or pack validation rejects authored data, treat that as blocking.
- If runtime behavior disagrees with the contract after validation passed, that is a runtime bug.
- Do not work around validator failures by editing JSON manually unless the goal is explicitly to debug the validator.

## Prerequisites

- Project root: `D:/spacegame2/project.godot`
- Use one fresh pack name, for example `golden_path`
- Have a Godot 4.x executable available
- If `godot` is not on `PATH`, note the full binary path before starting

## Validation Commands

Use the validator before and during playtesting, not only at the end.

Pack validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_ui_contract.ps1 -PackId golden_path
```

Smoke-pack validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_ui_contract.ps1 -SmokePack
```

Supported-features doc drift check:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_ui_contract.ps1 -SyncDocs -CheckDocs
```

If `godot` is not on `PATH`, pass `-GodotBin`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_ui_contract.ps1 -GodotBin "C:\path\to\godot.exe" -PackId golden_path
```

What pack validation now checks:
- authored UI screens
- UI input-map targets
- pack manifest references
- system / POI / realm / room references
- room dimensions, doors, and hierarchy
- trigger, dialogue, and shop references
- entity / behavior references
- player-content cross references such as attack, projectile, item, equipment, and ability links

## UI Contract Constraints

Keep these in mind while authoring UI:
- Mounted authored screens are currently `hud`, `pause`, `main_menu`, `inventory`, `map`, `shop`, `dialogue_box`, `game_over`, and `boss_intro`
- `hud` is display-only; authored HUD buttons and item actions should be rejected by validation
- `open_screen` is host-routed, not global; use only the targets allowed in [SUPPORTED_FEATURES.md](/D:/spacegame2/SUPPORTED_FEATURES.md:79)
- `dialogue_box` can open `boss_intro`, `cinematic`, and `shop:<shop_id>`
- bindings are exact except for `game_var.*`
- unresolved bindings now produce visible runtime diagnostics instead of silently pretending they worked
- every authored button click emits a trigger event named `ui_button`
- buttons can also use `fire_event` with `action_args = <event_name>`

Practical UI authoring rules:
- Start from seeded stock screens, not blank screens
- Avoid inventing new binding names from memory; copy from [SUPPORTED_FEATURES.md](/D:/spacegame2/SUPPORTED_FEATURES.md:33)
- If a screen needs navigation, confirm the host supports that `open_screen` target before wiring it
- If a list or grid uses an item action, make sure that action is valid for that host

## Recommended Authoring Order

Do the canonical pack in this order:

1. Create the pack.
2. Author the player baseline.
3. Author the starting ship and module baseline.
4. Author one minimal UI slice.
5. Author the world hierarchy in order: system -> realm -> region -> rooms.
6. Author one enemy plus one behavior.
7. Author one dialogue, one shop, and one trigger chain.
8. Validate the pack.
9. Play the pack and note every mismatch.

## Phase 1: Create The Pack

From the main menu:
1. Click `Editor`.
2. Create a new pack, for example `golden_path`.
3. Confirm the suite shell opens on `Campaign`.

Expected result:
- authored data root exists under `user://Packs/<pack>/`
- top tabs show `Campaign`, `Objects`, `World`, `Triggers`, `UI + FX`, `Audio`, `Playtest`
- seeded authored UI screens exist under `user://Packs/<pack>/UI/screens/`
- a default `user://Packs/<pack>/UI/input_map.json` is present or created on first seed/save

## Phase 2: Author The Player Baseline

Suite path:
- `Objects -> Player`

Author the minimum viable player content:
- enough pose/sprite data for idle, run, jump, and one attack pose
- `collision_width`
- `hurtbox_x`
- `hurtbox_y`
- `hurtbox_w`
- `hurtbox_h`
- `weapon_anchor_x`
- `weapon_anchor_y`

Author the minimum viable content set:
- 1 basic attack
- 1 charged attack variant
- 1 projectile
- 1 consumable item
- 1 equipment piece
- 1 progression ability

Recommended ids:
- attack: `blaster_basic`
- charged attack: `blaster_charged`
- projectile: `bolt_basic`
- item: `medkit`
- equipment: `starter_blaster`
- ability: `double_jump`

Exit criteria:
- player content saves cleanly
- attack -> projectile links validate
- charged attack -> attack links validate
- equipment -> attack/ability links validate
- item effects are within the currently supported effect surface

## Phase 3: Author The Starting Ship

Suite path:
- `Campaign -> Starting Ship`

Author:
- 1 starting ship template
- 1 valid core
- a minimal module layout
- any starter combat module needed for the opening space segment

Recommended content:
- ship template: `starter_shuttle`
- one weapon
- one power/core dependency if required by the current ship model

Also verify:
- the ship builder opens from the suite shell
- ship save persists
- `Test Fly` launches the actual space runtime
- defeat during `Test Fly` can recover without losing the authored ship state

Exit criteria:
- the pack manifest points at a real starting ship template
- the ship loads without fallback/default junk
- builder save and reload round-trip correctly

## Phase 4: Author The Minimal UI Slice

Suite path:
- `UI + FX -> UI + Cinematics`

Author only what the canonical pack needs first.

Required screens:
- `main_menu`
- `hud`
- `pause`
- `inventory`
- `shop`
- `dialogue_box`
- `game_over`

Optional but supported:
- `map`
- `boss_intro`

Recommended contents:

`hud`
- HP bar bound to `player.hp` / `player.max_hp`
- weapon label bound to `current_weapon.name`
- no buttons

`pause`
- `resume`
- `save_game`
- `quit_to_menu`

`inventory`
- tab bar
- one list or grid for authored inventory content
- close button

`shop`
- item list bound to `shop.items`
- buy/sell layout only if the current authored flow actually uses both
- close button

`dialogue_box`
- speaker label
- text area
- choice list with `choose_dialogue`

`main_menu`
- `new_game`
- `load_game` or `load_slot`
- `quit_game` or `quit_to_menu`

`game_over`
- `load_game` or `load_slot`
- `quit_to_menu`

If you want art-driven buttons or icons:
- use the `...` picker on `sprite_source`, `sprite_normal`, `sprite_hover`, or `sprite_pressed`
- use `IMPORT` in the texture picker to copy PNG files into the pack-local `Assets/UI` folder
- leave hover/pressed blank if the normal state should be reused

Exit criteria:
- every required screen saves without validation errors
- screen bindings match the supported contract
- screen actions are allowed for that host
- no HUD button/item actions are authored
- button-driven trigger flow is intentionally wired through `ui_button` and/or `fire_event`

## Phase 5: Author The Smallest Useful World

Suite paths:
- `World -> Systems + Planets`
- `World -> Realm + Regions`

Author the world in this hierarchy:

`Pack -> Systems -> Realms -> Regions -> MV Rooms`

Author exactly one slice:
- 1 system
- 1 realm
- 1 region
- 4 to 6 rooms
- 1 planet POI linking the system to the realm

Recommended room ids:
- `start_room`
- `hallway_a`
- `item_room`
- `shop_room`
- `gate_room`
- `boss_room`

System / planet setup:
- author one system
- author one planet POI
- set the POI realm to the test realm id
- leave `Pack Override` blank unless you are intentionally testing cross-pack routing
- leave `Spawn Room` blank for the canonical path

Realm / region setup:
- create one placed region
- set a valid `start_region`
- set enough atmosphere ground/structure content to prove the renderer is alive

Room setup:
- valid room masks
- valid dimensions
- valid room-to-room doors
- one real start room

Exit criteria:
- system, realm, region, and room references all validate
- door targets are real rooms
- the POI -> realm link validates
- the region start room resolves to a real MV room

## Phase 6: Environment Authoring

For each room:
- paint enough tiles to navigate
- add solid collision
- add one hazard somewhere useful
- set room metadata cleanly

Recommended room roles:
- `start_room`: safe intro
- `hallway_a`: traversal
- `item_room`: progression pickup
- `shop_room`: dialogue/shop interaction
- `gate_room`: progression check
- `boss_room`: combat proof room

Exit criteria:
- room data round-trips through the environment tooling
- collision works
- hazards work
- room metadata saves and reloads correctly

## Phase 7: Entity And Behavior

Use the entity and behavior editors from the suite shell.

Create:
- 1 enemy definition
- 1 behavior tree

Recommended ids:
- entity: `crawler_basic`
- behavior: `crawler_patrol`

Entity should define at least:
- `hp`
- `contact_damage`
- `contact_cooldown`
- `move_speed`

Place the entity in `boss_room` or a dedicated combat room.

Exit criteria:
- entity -> behavior reference validates
- room placement references a real entity id
- runtime enemy contact/combat uses authored data rather than hardcoded fallback assumptions

## Phase 8: Dialogue, Shop, Trigger Chain

Use the dialogue, shop, and trigger editors from the suite shell.

Build one connected chain, not disconnected samples.

Recommended chain:
1. In `shop_room`, an NPC starts dialogue `shopkeep_intro`.
2. Dialogue can branch on an item, ability, flag, or variable condition.
3. Dialogue can open a shop or fire a trigger event.
4. Shop sells `medkit` and optionally one progression item.
5. A trigger in `gate_room` checks the progression condition.
6. One authored return interaction exits MV back to the atmosphere overworld.

Recommended authored return setup:
- add an interactable in one MV room
- on `interact`, fire a trigger action `return_to_overworld`
- leave `region_id`, `x`, and `y` blank for the default test path unless you are intentionally testing override routing

Exit criteria:
- dialogue, shop, and trigger validation passes
- there are no dangling ids in conditions or actions
- shop item references are real authored items
- the return path reaches the atmosphere overworld cleanly

## Phase 9: Save / Load / Failure Recovery

Add one clear save/checkpoint moment in the route.

At minimum prove:
- a save action exists in reachable UI
- the authored run can be resumed without manual data edits
- game over can recover through the authored path

Recommended checks:
- pause-menu save/load
- main-menu load slot path
- game-over load slot path

Exit criteria:
- save/load works from reachable authored UI
- game-over recovery is real, not editor-only

## Phase 10: Validate Before Play

Before any serious manual play pass:
1. Run pack validation.
2. Treat every `error` as blocking.
3. Treat every `warning` as suspect until you can explain it concretely.

Common UI validation failures to look for:
- unknown screen ids in `UI/input_map.json`
- unsupported bindings
- unsupported actions for a given host
- invalid `open_screen` targets
- missing required `action_args`
- non-integer args for `load_slot` or `choose_dialogue`
- authoring a target screen reference that does not exist in the pack yet

## Manual Play Checklist

Run the first end-to-end play pass in this order:

1. Authored main menu appears.
2. `new_game` starts the authored pack.
3. The authored starting ship loads in space.
4. HUD bindings display live values without placeholder breakage.
5. Space flight is playable.
6. Planet POI interaction enters the atmosphere overworld.
7. Atmosphere ground content renders correctly.
8. Atmosphere billboard/structure content renders in the right places.
9. Landing on the authored region enters the region start room in MV.
10. The player can move, jump, and attack using authored player content.
11. Authored attack/projectile behavior occurs.
12. Inventory opens and shows authored content.
13. Room transitions work.
14. Hazard damage works.
15. Enemy contact/combat behavior works.
16. Dialogue opens and branches.
17. Shop opens and buying works.
18. Gate logic respects the authored item/ability/flag/variable state.
19. The authored MV return interaction exits back to the atmosphere overworld.
20. Atmosphere exit returns to space cleanly.
21. Pause menu works.
22. Save/load works.
23. Game-over flow works if intentionally triggered.

## What To Record During Testing

For every failure, record:
- pack id
- phase of the run
- which editor authored the data
- which file or content id was involved
- what you expected
- what actually happened
- whether save validation should have caught it
- whether pack validation should have caught it

High-value bugs are:
- runtime failures that should have been rejected at save time
- runtime failures that should have been caught by pack validation
- documentation claims that the code does not actually honor

## Success Criteria

Call the toolchain ready for broader authored content only when all of this is true:
- the canonical pack is created entirely through the pack-aware tools
- validation passes without unexplained errors
- the authored run is playable end to end across space, atmosphere, and MV without code edits
- UI screens obey the published contract
- docs and runtime behavior match
- remaining failures are narrow bugs, not systemic contract lies

## What Not To Do Yet

Avoid these until the canonical pack works:
- building a large world
- polishing visuals heavily
- creating many enemies before one enemy path is proven
- creating many items and abilities before one progression path is proven
- relying on unsupported screen ids, bindings, or actions
- hand-maintaining [SUPPORTED_FEATURES.md](/D:/spacegame2/SUPPORTED_FEATURES.md:1) instead of treating it as generated contract output
