# In-Game Authoring Roadmap — Triggers · Dialogue · Space

Plan for bringing the remaining authoring surfaces online inside the running game
(the `feature/in-game-authoring` work). Everything writes to the same JSON
content packs (copy-on-write to `user://Packs/<id>/`), is validated before save,
and is verified by headless scene-boot (LSP lint is unavailable in the worktree).

## Where we are (done)

The **MV (platformer)** side is essentially a live editor:

- **F2 edit mode** (`MV/scripts/console/edit_mode.gd`) — modes Tiles / Collision /
  Entities / Shaders; multi-tileset folder-tree palette (upload, name, organize,
  collapse); multi-tile drag brush; animated tiles; collision paint + overlay;
  free-draw shader regions + inline editor (move/resize/tint/strength/speed).
- **Environment panel** — weather, whole-room shader, parallax backdrop import.
- **Combat Workshop** + **player/enemy wizards** — entity + behavior authoring.
- **Dev console** (`MV/scripts/console/dev_console.gd`, backtick) — cross-engine
  autoload that survives the MV↔Space swap.

Cross-engine glue already exists: `PlanetaryInterface.edit_session_active` flags
an open authoring overlay across the scene swap; `DevConsole` is one autoload
instance routing commands by context.

## What's NOT online (the three frontiers)

| Frontier | State today | Gap |
|---|---|---|
| **Triggers** | Console: paste trigger JSON → validate (`EcaSchema`) → live-inject (`MvTriggerEngine.add_global_rule`) → persist (`PedIO.save_triggers`); `fire <event>` test. | No **visual** editor — no in-world zone placement, no form-based event/condition/action builder. JSON-paste only. |
| **Dialogue** | Desktop only (`Space/scripts/editor/dialogue_editor.gd` + external HTML). Runtime playback = `MvDialogueRunner.start(id)`. | **No in-game authoring** at all. |
| **Space (SSB)** | Console `add_poi <type> <name>` → live place + `SystemIO` save; ship builder (`CreativeModeController`/`main.builder`) openable in-game. | No **spatial editor** — can't drag/move POIs, edit system layout or encounters; ship builder not folded into the edit session. |

---

## Shared infrastructure (reuse, don't rebuild)

- **Validation/schema**: `EcaSchema` (`Space/scripts/editor/dlg/eca_schema.gd`) —
  `EVENT_TYPES`, `ACTION_TYPES`, condition schemas, `EVENT_PAYLOAD_FIELDS`,
  `find_action_schema`/`find_condition_schema`/`event_type_names`. This already
  drives the console paste path and the workshop's WHEN→DO rows.
- **Trigger runtime**: `MvTriggerEngine` — `add_global_rule`/`add_room_rule`
  (live inject), `fire_event` (test), `set_room_triggers`; events include
  `interact`, `zone_enter`/`zone_exit`, `pickup`, item/quest/dialogue events.
- **Trigger persistence**: `PedIO.load_triggers`/`save_triggers`
  (`Triggers/global.json`, validated via `_validate_triggers`); `TriggerRoot`
  normalize/flatten. Rule shape ≈ `{id, event, conditions:[], actions:[]}`.
- **Dialogue**: `Dialogue/<id>.json` = `{lines:[{speaker,text,choices:[…]}…]}`;
  `MvDialogueRunner.start(id)` plays it; `interact` payload carries a
  `dialogue_id`; a `start_dialogue`/`dialogue` ECA action begins one.
- **Space**: `SystemIO.load_or_init`/save (`Systems/systems.json` = `{systems}`);
  POI ≈ `{id, type, name, orbit_dist, orbit_angle, planet_data:{regions…}}`
  (polar placement around the star); `_spawn.spawn_system_pois(sys_id)` respawns;
  desktop ref `Space/scripts/editor/system_editor.gd`.
- **UI kit**: `NebulaTheme` + `NebulaUi` (work_panel, step_rail, labeled, buttons,
  section_header) — every new overlay should use these. Modal editors render at
  native res (game is native 1920 + camera zoom now).
- **Cross-engine session**: `PlanetaryInterface.edit_session_active`; promote
  shared edit state here if Space/MV need to share an "editing" flag.

---

## Frontier 1 — Triggers go visual (recommended first)

**Goal:** author gameplay logic in-world without hand-writing JSON.

- **T1 — Trigger list + form builder (MV overlay).** A panel listing the pack's
  global rules; add/edit a rule via forms: event `Select` (from
  `EcaSchema.EVENT_TYPES`), conditions list, actions list (reuse the workshop's
  WHEN→DO row UI + `EcaSchema` field kinds). Live-inject + `PedIO.save_triggers`.
  Reuses the console's `_inject_and_persist`.
- **T2 — In-world trigger zones.** A "Triggers" F2 mode: drag a rectangle to
  place a `zone_enter`/`zone_exit` trigger volume (store as a room zone with a
  `zone_id`); attach a rule to it. Reuses the shader-region marquee + the
  collision/overlay drawing patterns. Persist zones into the room JSON.
- **T3 — Test loop.** "Fire" button per rule (→ `fire_event`), and a live "this
  rule just fired" flash, so you build→test without walking over.
- **Risks:** room-scoped vs global rules (console does global; zones are
  room-scoped → use `add_room_rule` + persist to the room); exact rule key names
  (confirm via `TriggerRoot`). Validation must stay the hard gate.

## Frontier 2 — Dialogue in-game (biggest greenfield)

**Goal:** write/branch conversations live and attach them to entities/triggers.

- **D1 — Dialogue IO + list.** Load/save `Dialogue/<id>.json` (mirror `EntIO`/
  `EffIO`: `load_or_init`/`save`, copy-on-write). A list panel of dialogues +
  create-new. (Reader exists in `MvDialogueRunner._load_dialogue`.)
- **D2 — Line editor.** Edit the `lines[]` of a dialogue: speaker, text, and
  per-line `choices[]` (label + goto/next + optional condition/action). Use the
  step-rail/work-panel idiom. Validate before save.
- **D3 — Attach + test.** Attach a dialogue to an entity (the `interact` event's
  `dialogue_id`) or a trigger action (`start_dialogue`); a "Play" button →
  `MvDialogueRunner.start(id)` to preview in-game.
- **Risks:** branch/goto integrity (validate referenced line ids/choices);
  choice conditions/actions overlap with the ECA model (reuse `EcaSchema`); scope
  (start with linear + simple choices, then conditions).

## Frontier 3 — Space live editor (brings the 2nd engine online)

**Goal:** the SSB equivalent of F2 — author the star-map/system live.

- **S1 — POI placement/move.** Extend the Space console path into a spatial mode:
  click-place and **drag-move** POIs (convert drag position ↔ `orbit_dist`/
  `orbit_angle`), edit name/type/`planet_data.regions`. Reuse `SystemIO` +
  `_spawn.spawn_system_pois` for live respawn; persist to `systems.json`.
- **S2 — System + encounter editing.** Add/edit systems, links, and encounters
  (re-target `system_editor.gd` logic); live respawn.
- **S3 — Ship builder integration.** Fold the existing builder
  (`main.builder`/`CreativeModeController`, `toggle_ship_builder`) into the
  unified edit session so build→test-fly→land is one continuous authoring loop;
  bridge via `PlanetaryInterface.edit_session_active`.
- **Risks:** POI polar coords (not x/y) — drag math; the ship builder is the
  canonical builder (do NOT rebuild — only the AI-recording/clone path is dead);
  Space console renders on the root window (full profile) — no scale juggling.

---

## Sequencing & dependencies

1. **Triggers visual (T1→T3)** — highest leverage, builds straight on the proven
   console/`EcaSchema` foundation; unblocks authoring real gameplay logic. Its
   form-builder UI (event/condition/action rows) is **reused by Dialogue choices
   and Space encounters**, so doing it first pays compounding interest.
2. **Dialogue (D1→D3)** — depends on the T1 ECA-row UI for choice conditions/
   actions; otherwise independent. Largest build.
3. **Space editor (S1→S3)** — independent of 1–2; can run in parallel. S3 (ship
   builder) is mostly integration, low risk.

Each slice: implement narrow → validate (the editor's hard gate) → smallest
smoke (boot + targeted) → dogfood → commit. No stubs claimed as done.

## Conventions (carried from the MV work)

- New overlays use `NebulaUi`/`NebulaTheme`; modal editors render at native res.
- Persist on explicit save (Ctrl+S / a Save button); copy-on-write to the user
  pack; validation is a blocker, not a warning.
- Verify headless: `--import` after `class_name` changes; boot MV/Space scenes;
  per-file indentation (tabs in console files, 4-space in `room_manager`/`main`).
- Stage explicit paths only; never `git add -A` (≈4570 `.png.import` churn).
