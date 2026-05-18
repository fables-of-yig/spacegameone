# Roadmap

The goal is to make this repository a usable game-authoring tool where editor-authored data reliably becomes runtime behavior.

## Phase 0: Baseline Truth

- Maintain `SUPPORTED_FEATURES.md` as the current editor/runtime contract.
- Remove or hard-flag any editor surface that does not map to a real runtime path.
- Treat silent fallback and null-bound UI as bugs.

## Phase 1: UI Vertical Slice

Target:
- Authored UI screens save cleanly, validate before save, and mount into runtime hosts.

Done in this phase:
- Screen save validation.
- Pack validation now includes authored UI screens and input-map targets.
- Property panel scrolling and property writeback fixes.
- Shared authored screen runtime for Space and MV hosts.
- Mounted authored screens:
  - `hud`
  - `pause`
  - `main_menu`
  - `inventory`
  - `map`
  - `shop`
  - `dialogue_box`
  - `game_over`
  - `boss_intro`

Still open in this phase:
- Better host coverage for `open_screen`.
- Richer item/equipment action semantics beyond direct inventory mutation.
- Better icon binding support for dynamic sprite sources.

Acceptance criteria:
- If a screen is exposed in the editor and marked supported, it loads in runtime.
- Known bad bindings/actions are rejected or warned loudly at save time.
- Supported bindings resolve to live data instead of placeholder nulls.

## Phase 2: Authored Gameplay Data

Target:
- Player, item, ability, projectile, and equipment editor output drives gameplay directly.

Work:
- Define one authoritative pack schema for player/gameplay content.
- Validate cross-references before runtime.
- Remove duplicated defaults between editor and runtime.

Acceptance criteria:
- An authored player setup changes live gameplay without script edits.

## Phase 3: Dialogue, Triggers, Shops

Target:
- Quest/event-style authored flows work end to end.

Work:
- Standardize conditions, actions, and effect schemas.
- Validate trigger/dialogue/shop references.
- Add diagnostics for failed trigger conditions.

Acceptance criteria:
- A creator can build a simple authored quest/shop/dialogue loop entirely in-editor.

## Phase 4: World Authoring

Target:
- Region, room, environment, entity, and behavior data round-trip from editor to runtime.

Work:
- Lock the pack -> system -> POI -> region -> room -> entity hierarchy.
- Validate room references, door targets, and behavior references.
- Add migration/versioning for saved content.

Acceptance criteria:
- A creator can author a small world and traverse it in runtime.

Done in this phase:
- Removed the Realm data layer and the mode-7 atmosphere overworld. Pack layout is now `Content/<pack>/Regions/<region_id>/{region.json,rooms.json}` with a flattened `Rooms/rooms.json` runtime view; POIs own `planet_data.regions[]` and landing routes through the Space-side region picker via `PlanetaryInterface.begin_landing`. Door schema dropped `send_to_overworld` / `overworld_region_id` in favor of `launch_to_space: bool`.

## Phase 5: Validation And Smoke Tests

Target:
- Catch regressions before manual playthroughs.

Work:
- Build validation scripts for authored content.
- Create one golden pack that touches every supported path.
- Maintain a smoke checklist for boot, pack load, UI load, room load, player content, dialogue, and shop flow.

Acceptance criteria:
- The golden pack proves the toolchain still works after changes.
