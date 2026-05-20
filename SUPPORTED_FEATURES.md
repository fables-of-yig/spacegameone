# Supported Features

This file is generated from `Space/scripts/ui/ui_contract.gd`. It is the current runtime/editor contract for authored UI. If the editor exposes something outside this list, that is a bug.

## Authored Screens Mounted At Runtime

- `hud_space`
  Used by `Space/scripts/ui/ui_coordinator.gd` as an overlay on the hardcoded space HUD.
- `hud_mv`
  Used by `MV/scripts/hud.gd` while a hosted MV session is active.
- `pause`
  Used by `Space/scripts/ui/pause_menu.gd`.
- `main_menu`
  Used by `Space/scripts/ui/main_menu.gd`.
- `inventory`
  Used by `MV/scripts/inventory_screen.gd`.
- `map`
  Used by `MV/scripts/map_screen.gd`.
- `shop`
  Used by `MV/scripts/shop_ui.gd`.
- `dialogue_box`
  Used by `MV/scripts/dialogue_runner.gd`.
- `game_over`
  Used by `MV/scripts/game_over.gd`.
- `boss_intro`
  Mounted as a generic cinematic / letterbox overlay host via `Space/scripts/ui/cinematic_overlay.gd`.
    Can be opened from authored UI using `open_screen = boss_intro` or `open_screen = cinematic`.

## Supported Element Types

- `panel`
- `label`
- `button`
- `progress_bar`
- `icon`
- `list`
- `grid`
- `separator`
- `tab_bar`
- `conditional`

## Supported Bindings

Space-side bindings:
- `player.*`
- `gamemanager.*`

MV-side bindings via fallback resolver:
- `player.hp`
- `player.max_hp`
- `inventory.*`
- `current_weapon.*`
- `room.*`
- `dialogue.*`
- `shop.items`
- `shop.message`
- `map.rooms`
- `quest.*`
- `game_var.*`

Derived ratio bindings:
- `player.health_pct`
- `player.shields_pct`
- `gamemanager.fuel_pct`
- `player.boost_ready_pct`
- `player.scan_ready_pct`

Notes:
- Bindings are exact except for `game_var.*`.
- If a binding resolves to `null`, the runtime now warns and renders a visible diagnostic instead of silently pretending it succeeded.

## Supported Actions

- `open_screen`
- `close_screen`
- `buy_item`
- `sell_item`
- `equip_item`
- `unequip`
- `use_item`
- `save_game`
- `load_game`
- `quit_to_menu`
- `resume`
- `end_dialogue`
- `play_sfx`
- `open_settings`
- `new_game`
- `quit_game`
- `creative_mode`
- `test_fly`
- `test_planet`
- `open_editor`
- `update_game`
- `load_slot`
- `fire_event`
- `choose_dialogue`

## Host Action Support

- `boss_intro` (`cinematic_overlay`)
  Actions: `close_screen`, `resume`, `fire_event`, `play_sfx`
- `dialogue_box` (`dialogue_runner`)
  Actions: `close_screen`, `end_dialogue`, `choose_dialogue`, `open_screen`, `fire_event`, `play_sfx`
  `open_screen` targets: `boss_intro`, `cinematic`, `shop:...`
- `game_over` (`game_over`)
  Actions: `load_game`, `load_slot`, `quit_to_menu`, `quit_game`, `close_screen`, `open_screen`, `fire_event`, `play_sfx`
  `open_screen` targets: `boss_intro`, `cinematic`
- `inventory` (`inventory_screen`)
  Actions: `close_screen`, `resume`, `open_screen`, `fire_event`, `equip_item`, `unequip`, `use_item`, `play_sfx`
  `open_screen` targets: `inventory`, `map`, `boss_intro`, `cinematic`
- `main_menu` (`main_menu`)
  Actions: `open_screen`, `new_game`, `creative_mode`, `test_fly`, `test_planet`, `open_editor`, `update_game`, `load_slot`, `load_game`, `fire_event`, `quit_to_menu`, `quit_game`, `play_sfx`, `open_settings`
  `open_screen` targets: `main_menu`, `boss_intro`, `cinematic`
- `map` (`map_screen`)
  Actions: `close_screen`, `resume`, `open_screen`, `fire_event`, `play_sfx`
  `open_screen` targets: `map`, `inventory`, `boss_intro`, `cinematic`
- `hud_mv` (`mv_hud_overlay`)
  Actions: none
- `pause` (`pause_menu`)
  Actions: `resume`, `close_screen`, `open_screen`, `fire_event`, `save_game`, `load_game`, `quit_to_menu`, `play_sfx`, `open_settings`
  `open_screen` targets: `pause`, `boss_intro`, `cinematic`
- `shop` (`shop_ui`)
  Actions: `close_screen`, `resume`, `open_screen`, `fire_event`, `buy_item`, `sell_item`, `play_sfx`
  `open_screen` targets: `shop`, `inventory`, `map`, `boss_intro`, `cinematic`
- `hud_space` (`space_hud_overlay`)
  Actions: none

## Known Gaps

- `open_screen` is host-routed, not a universal scene navigation system. Current hosts only support the targets listed in the host action matrix below.
- `sell_item`, `unequip`, and `use_item` still rely on `action_args` conventions such as `item_id[:count]`, `slot`, or `item_id[:price]`. `equip_item` uses just `item_id`.
- Pack-authored item effects currently support `heal_hp`, `max_hp_up`, `add_gold`, `add_ammo`, `max_ammo_up`, `grant_ability`, `add_var`, `set_flag`, `add_tag`, `fire_event`, `set_weapon`, and `equip_item`.
- `set_weapon` and equipment `weapon` can target authored attack ids. Legacy `beam` / `grenade_launcher` values still work as compatibility fallbacks.
- Player pose authoring drives per-pose `collision_width`, `hurtbox_x/y/w/h`, and `weapon_anchor_x/y`. Enemy leaf projectiles honor the authored hurtbox area.
- Authored attacks can define `charge_ticks` plus `charged_attack_id`, so hold-release charged shots are data-driven instead of beam-only.
- Authored ranged attacks can define optional `charge_fx_*` sprite fields for a muzzle-tip charging effect while the fire button is held.
- Authored projectiles support explosive detonation fields including `explosive`, `blast_radius`, `explosion_damage`, `explode_on_hit`, `explode_on_timeout`, `bomb_jump`, and `bomb_jump_speed`.
- Spike hazard contact samples the authored hurtbox instead of the raw body rectangle.
- More complex consumable logic still needs a broader effect system.
- Generic enemy body-contact damage runs through the player's authored hurtbox area. Entity defs can author `hp`, `attack_damage`, `contact_damage`, `contact_cooldown`, `move_speed`, `projectile_damage`, and `projectile_speed`, and common AI leaves use those as defaults when their params omit overrides.
- The `hud_space`, `hud_mv`, and legacy `hud` screens are display-only today. Buttons and item actions on authored HUD screens are rejected at validation time.
- Landing on a POI opens the Space-side region picker (`Space/scripts/ui/region_picker_panel.gd`, mounted by `UICoordinator.setup_region_picker`) listing the POI's `planet_data.regions[]`; selection calls `PlanetaryInterface.begin_landing(pack_id, poi_id, region_id, spawn_room)`. The picker is fired by the `interact` action (E key) when the ship is in range of a landable POI. The spawn point inside the room comes from that room's `player_spawn` entity — regions do not carry pixel coordinates.
- POIs authored with `hidden: true` are skipped during system spawn until an `unlock_poi` trigger action records the POI's `id` in `GameManager.unlocked_pois`. The unlock survives save/load; the new POI appears on the next system entry (not live in the current session). POIs without a stable `id` cannot be unlocked.
- Pack manifest `start_region` names the default region; per-region authoring lives in `Content/<pack>/Regions/<region_id>/` and the runtime view is the flattened `Rooms/rooms.json` regenerated by `RegIO.flatten_to_runtime`. Room addresses are `<region>/<room>` or bare `<room>`; the 3-slot realm/region/room form is rejected by the validator.
- Doors set `launch_to_space: true` (legacy `exit_to_space` tag still honored) to route the player back to Space; the removed `send_to_overworld` / `overworld_region_id` fields are rejected by the validator.
