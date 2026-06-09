---
name: spaceboat-triggers
description: Author, validate, and explain SpaceboatMania ECA triggers, dev-console commands, and event/condition/action JSON for the in-game dev console (backtick `). Use whenever the user asks to "write me a trigger", a console paste, a cutscene/quest/door/spawn/dialogue hook, or any event→condition→action behavior for this game. Source of truth: Space/scripts/editor/dlg/eca_schema.gd; console: MV/scripts/console/dev_console.gd; runtime: MV/scripts/trigger_engine.gd.
---

# SpaceboatMania — Triggers & Console authoring

This skill lets you hand the user **ready-to-paste** trigger JSON and console
commands. The game's logic layer is an **ECA** system: a rule is
`event → conditions (all must pass) → actions (run in order)`.

## How the user uses what you write

1. In game, press **backtick `` ` ``** to open the dev console (works in MV or
   Space; triggers are global).
2. **Paste a trigger** = paste a JSON **object** (one rule), a JSON **array**
   (many rules), or `{"triggers":[ ... ]}`. The console validates it (EcaSchema),
   injects it live (`MvTriggerEngine.add_global_rule`), and persists it to the
   user pack (`PedIO.save_triggers` → `user://Packs/<pack>/...`). A rule whose
   `id` already exists is skipped with a warning.
3. **Test without walking over it:** `fire <event> {json payload}` —
   e.g. `fire interact {"entity_id":"old_mayor"}`.
4. The desktop-style visual editor is the console command `triggers` (alias
   `trig`); dialogue is `dialogue`/`dlg`.

**When the user asks for a behavior, give them the JSON in a fenced block plus a
one-line "paste this in the console (backtick)".** Keep ids short and unique.

## Rule shape

```json
{
  "id": "unique_snake_id",          // required-ish; used for dedupe + set_trigger_enabled
  "event": "interact",              // required; see EVENTS
  "conditions": [ { "type": "..." } ],   // optional; ALL must pass (AND)
  "actions":    [ { "type": "..." } ],   // optional but pointless if empty; run in order
  "enabled": true,                  // optional, default true
  "once": false,                    // optional; if true, fires at most once per session
  "locals": [ { "name": "n", "value": 0 } ],  // optional per-instance variables
  "event_params": { }               // optional event-source binding (see space_proximity_band)
}
```
- Conditions/actions are objects with a `"type"` plus that type's fields (below).
- Unknown event → **warning** (allowed, may be code-fired). Unknown
  condition/action type, or non-array `conditions`/`actions`, or an action
  missing `type` → **error** (rejected). So only use the types listed here.

### Two separate keyspaces (common gotcha)
- **Story flags** (on/off): `set_flag`/`has_flag` — per-session, in PlayerInventory game_vars.
- **Story numbers** (int): `set_var`/`add_var`/`var_eq`/`var_gte` — separate keyspace.
- A flag named `gold` and a number named `gold` do **not** collide.
- **Global flags** (cross-system, survive MV↔Space + save): `set_global_flag`/
  `clear_global_flag`/`has_global_flag`. Use for story/faction state read on both sides.

## Console commands (non-JSON)
- `fire <event> {payload}` — dispatch an event (test triggers).
- `spawn <entity_id>` — spawn an entity at the player (MV).
- `flag <name>=<value>` — set a **global** flag (`true`/`false`/number/string coerced).
- `triggers` / `dialogue` / `workshop` / `wizard <player|enemy>` — open editors (MV).
- Space: `mapedit`, `galaxyedit`, `encounters`, `shipbuilder`, `add_poi <type> <name>`.
- `help`, `clear`.

## EVENTS  (event name → payload keys you can match with `payload_eq`)
Player/world (MV):
- `game_started` () — once at boot after start room loads. Intro/setup.
- `new_game_started` (room, fresh_boot, …) — fresh boot BEFORE game_started; if any rule matches it the auto player-spawn is skipped (place the player yourself with `spawn_player`). Opening cinematic.
- `player_spawn` (room, x, y, zone_id) — every placement/respawn.
- `player_damage` (amount, hp, max_hp, source) · `player_death` (source).
- `pickup` (entity_id, item_id) · `interact` (entity_id, entity_type, dialogue_id).
- `item_gain` (item_id, count, stock_id, shop_id) · `item_loss` (item_id, count, remaining) · `item_use` (item_id, count) · `item_sell` (item_id, price, shop_id).
- `door_enter`/`door_use_attempt`/`door_use_success`/`door_use_blocked`/`door_arrived` (door_id, target_door_id, from_room, enabled, locked, [block_reason], [arrival_door_id]).
- `region_enter` (region_id, music_id, encounter_id, visual_theme, hazard_type, gravity_mult) · `region_exit` (region_id).
- `zone_enter`/`zone_exit` (entity_id, zone_id) — trigger-volume zones (place via F2 Triggers mode).
- `ability_grant`/`ability_revoke` (ability_id).
- `enemy_spawn` (entity_id, room_id) · `enemy_defeated` (entity_id).
- `boss_arena_lock`/`boss_arena_unlock`/`boss_defeated` (entity_id) · `boss_phase` (entity_id, phase).
- `projectile_explode`/`bomb_explode` (radius, damage).
- `dialogue_started`/`dialogue_ended` (dialogue_id) · `dialogue_choice` (dialogue_id, line_index, choice_index, choice_text).
- `shop_opened`/`shop_closed` (shop_id).
- Quests: `quest_started`/`quest_stage_changed`/`quest_stage_completed`/`quest_completed`/`quest_failed` (quest_id, stage_id) · `quest_objective_completed` (quest_id, stage_id, objective_id).
- `trigger_sequence_finished` (rule_id).
- `save_game`/`load_game` (slot, pack_id) · `ui_button` (screen_id, element_id, host, action).

Space (SSB):
- `space_system_enter` (system_id) · `space_station_destroyed` (system_id, station_key) · `space_poi_interact` (system_id, event_id).
- `space_proximity_band` (system_id, band_min, band_max, distance, rule_id) — fires once per entry into a star-distance ring. **Bind it** with `event_params`: `{"system_id":"sol","band_min":2000,"band_max":4000}`.

## CONDITIONS  (type — fields — meaning)
Combine many: they AND together. For OR/NOT use logical wrappers (below).
- `has_item` — id, min_count(int=1) — inventory ≥ min_count of id.
- `has_ability` — id — player has ability.
- `has_tag` — tag — the firing payload carries tag. `has_global_tag` — tag — world tag set (set via add_tag).
- `has_flag` — name, value(bool) — story flag matches. `has_global_flag` — name, value(bool) — cross-system flag matches.
- `var_eq` — name, value(int) — story number == value (unset=0). `var_gte` — name, value(int) — ≥.
- `var_eq_var` — name_a, name_b. `var_gte_var` — name_a, name_b — compare two numbers.
- `quest_status` — quest_id, status (inactive|active|complete|failed). `quest_stage` — quest_id, stage_id. `quest_objective_done` — quest_id, stage_id, objective_id.
- `chance_roll` — percent(float) — true when a d100 roll lands under percent.
- `local_var_eq` — name, value(string). `local_var_gte` — name, value(float) — this rule's locals.
- `payload_eq` — key, value — the firing payload's `key` (stringified) == value. Use the payload keys listed per event.

### Logical wrappers (OR / NOT / nested AND)
`{"type":"or","conditions":[ {...}, {...} ]}`, `{"type":"and","conditions":[…]}`,
`{"type":"not","conditions":[ {...} ]}`. They nest. (These pass console validation
specially — only `and`/`or`/`not` are recognized wrappers.)

## ACTIONS  (type — fields — effect). Run top-to-bottom; `delay`/`wait_*` suspend the sequence.
Flow & timing:
- `comment` — text(opt) — note only. `log` — message — debug print.
- `delay` — seconds(float). `wait_for_event` — event, key(opt), value(opt), timeout(opt float), result_local(opt). `wait_for_move`/`wait_for_anim` — entity, [anim], timeout(opt), result_local(opt). `wait_for_camera`/`wait_for_dialogue` — timeout(opt), result_local(opt).
- `if` — conditions(array), then(array of actions), else(array) — inline branch.
- `random_pick` — options: `[ {"weight":1,"actions":[…]}, … ]` — weighted branch.
- `fire_event` — event, key(opt), value(opt), inherit_payload(bool) — dispatch another event.
- `set_trigger_enabled` — id, enabled(bool).

Player & inventory:
- `give_item`/`take_item` — id, count(int). `heal_player` — amount(int). `damage_player` — amount(int), source(opt). `set_player_invuln` — seconds(float).
- `give_ability`/`revoke_ability` — id.
- `lock_player`/`unlock_player` () — input. `pause_game`/`resume_game` () — sim.
- `teleport_player` — room(opt), x(int), y(int). `spawn_player` — room(opt), zone_id(opt), entry_direction(opt), facing(opt), use_position(bool), x(int), y(int), emit_event(bool).

Entities (MV):
- `spawn_entity` — id, x(int), y(int). `spawn_entity_at_zone` — id, zone_id. `despawn_entity` — id.
- `move_entity_to_zone` — entity("player" or instance/id), zone_id, speed(float). `play_entity_anim` — entity, anim, loop(bool), speed(float). `set_entity_facing` — entity, direction(left|right|toward_zone|away_from_zone), zone_id(opt).

State & story:
- `set_flag` — name, value(bool). `set_var` — name, value(int). `add_var` — name, delta(int).
- `set_local_var` — name, value(string). `add_local_var` — name, delta(float).
- `add_tag`/`remove_tag` — tag.
- `set_global_flag` — name, value(bool). `clear_global_flag` — name.
- Quests: `quest_start` — quest_id, stage_id(opt). `quest_set_stage` — quest_id, stage_id. `quest_complete_objective` — quest_id, stage_id(opt), objective_id. `quest_complete_stage` — quest_id, stage_id(opt). `quest_complete`/`quest_fail` — quest_id.

Presentation:
- `start_dialogue` — id. `end_dialogue` (). `start_shop` — id.
- `show_toast` — message, duration(opt), style(info|success|warning|error).
- `camera_focus` — mode(player|entity|zone|position), target(opt), x(opt), y(opt), duration(opt), speed(opt). `camera_unlock` (). `camera_shake` — intensity(float), duration(float). `screen_flash` — color(html e.g. "ff0000aa"), duration(float).
- `play_sfx` — name. `play_music` — track. `stop_music` (). `set_room_weather` — room(opt), preset(none|rain|snow), color(opt html), intensity(opt), speed(opt). `spawn_fx` — effect_id, x(opt), y(opt).

Doors / flow:
- `set_door_enabled` — id, enabled(bool). `set_door_locked` — id, locked(bool).
- `save_checkpoint` — slot(int). `return_to_space` (). `end_game` ().

Space (SSB):
- `reveal_system` — system_id. `unlock_poi` — system_id, poi_id.
- `space_add_credits`/`space_set_credits` — amount(int).
- `spawn_space_ship` — class, anchor(player|world|system), x(float), y(float), wormhole(bool), delay(opt). `spawn_space_enemies` — class_id, count(int), dist_min(int), dist_max(int), use_wormhole(bool). `space_spawn_ship_on_return` — class, system_id.

> Field kinds: `opt_*` = optional (omit to use the default). Bools are JSON
> `true`/`false`. Numbers are JSON numbers. Always copy the exact field keys
> above — the runtime reads them verbatim.

## Worked examples

**Talk to an NPC once → give an item + set a flag**
```json
{ "id": "mayor_gift", "event": "interact", "once": true,
  "conditions": [ { "type": "payload_eq", "key": "entity_id", "value": "old_mayor" } ],
  "actions": [
    { "type": "start_dialogue", "id": "mayor_intro" },
    { "type": "give_item", "id": "rusty_key", "count": 1 },
    { "type": "set_flag", "name": "met_mayor", "value": true } ] }
```

**Walk into a zone → locked-door cutscene (camera + dialogue), gated by a flag**
```json
{ "id": "gate_ambush", "event": "zone_enter",
  "conditions": [ { "type": "payload_eq", "key": "zone_id", "value": "gate_trap" },
                  { "type": "not", "conditions": [ { "type": "has_flag", "name": "gate_done", "value": true } ] } ],
  "actions": [
    { "type": "lock_player" }, { "type": "set_door_locked", "id": "north_gate", "locked": true },
    { "type": "camera_focus", "mode": "zone", "target": "gate_trap", "duration": 1.0 },
    { "type": "wait_for_camera" }, { "type": "start_dialogue", "id": "gate_warning" },
    { "type": "wait_for_dialogue" }, { "type": "spawn_entity_at_zone", "id": "guard_drone", "zone_id": "gate_trap" },
    { "type": "camera_unlock" }, { "type": "unlock_player" }, { "type": "set_flag", "name": "gate_done", "value": true } ] }
```

**Space ambush when entering a star-distance band**
```json
{ "id": "sol_inner_ambush", "event": "space_proximity_band",
  "event_params": { "system_id": "sol", "band_min": 2000, "band_max": 5000 },
  "actions": [ { "type": "show_toast", "message": "Hostiles inbound!", "style": "warning" },
               { "type": "spawn_space_enemies", "class_id": "raider", "count": 3, "dist_min": 800, "dist_max": 1400, "use_wormhole": true } ] }
```

**Test it:** `fire interact {"entity_id":"old_mayor"}` (or walk over it in game).
