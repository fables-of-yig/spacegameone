class_name UiContract
extends RefCounted

const ELEMENT_TYPES: Array = [
	"panel",
	"label",
	"button",
	"progress_bar",
	"icon",
	"list",
	"grid",
	"separator",
	"tab_bar",
	"conditional",
]

const SCREEN_ORDER: Array = [
	"hud_space",
	"hud_mv",
	"pause",
	"main_menu",
	"inventory",
	"map",
	"shop",
	"dialogue_box",
	"game_over",
	"boss_intro",
]

const SCREEN_DEFS: Dictionary = {
	"hud_space": {
		"label": "HUD (Space)",
		"doc_description": "Used by `Space/scripts/ui/ui_coordinator.gd` as an overlay on the hardcoded space HUD.",
		"mounted": true,
		"host_id": "space_hud_overlay",
	},
	"hud_mv": {
		"label": "HUD (MV)",
		"doc_description": "Used by `MV/scripts/hud.gd` while a hosted MV session is active.",
		"mounted": true,
		"host_id": "mv_hud_overlay",
	},
	"hud": {
		"label": "HUD (Legacy Shared)",
		"doc_description": "Legacy fallback shared HUD screen. New packs should author `hud_space` and `hud_mv` instead.",
		"mounted": true,
		"host_id": "space_hud_overlay",
	},
	"pause": {
		"label": "Pause Menu",
		"doc_description": "Used by `Space/scripts/ui/pause_menu.gd`.",
		"mounted": true,
		"host_id": "pause_menu",
	},
	"main_menu": {
		"label": "Main Menu",
		"doc_description": "Used by `Space/scripts/ui/main_menu.gd`.",
		"mounted": true,
		"host_id": "main_menu",
	},
	"inventory": {
		"label": "Inventory / Pause Screen",
		"doc_description": "Used by `MV/scripts/inventory_screen.gd`.",
		"mounted": true,
		"host_id": "inventory_screen",
	},
	"map": {
		"label": "Map Screen",
		"doc_description": "Used by `MV/scripts/map_screen.gd`.",
		"mounted": true,
		"host_id": "map_screen",
	},
	"shop": {
		"label": "Shop Menu",
		"doc_description": "Used by `MV/scripts/shop_ui.gd`.",
		"mounted": true,
		"host_id": "shop_ui",
	},
	"dialogue_box": {
		"label": "Dialogue Box",
		"doc_description": "Used by `MV/scripts/dialogue_runner.gd`.",
		"mounted": true,
		"host_id": "dialogue_runner",
	},
	"game_over": {
		"label": "Game Over",
		"doc_description": "Used by `MV/scripts/game_over.gd`.",
		"mounted": true,
		"host_id": "game_over",
	},
	"boss_intro": {
		"label": "Cinematic Overlay / Letterbox",
		"doc_description": "Mounted as a generic cinematic / letterbox overlay host via `Space/scripts/ui/cinematic_overlay.gd`.\n  Can be opened from authored UI using `open_screen = boss_intro` or `open_screen = cinematic`.",
		"mounted": true,
		"host_id": "cinematic_overlay",
	},
}

const BINDING_SOURCES: Array = [
	"player.health",
	"player.max_health",
	"player.hp",
	"player.max_hp",
	"player.shields",
	"player.max_shields",
	"player.shield_recharge_rate",
	"player.boost_cd_timer",
	"player.boost_cooldown",
	"player.scan_cooldown",
	"player.scan_cooldown_time",
	"gamemanager.credits",
	"gamemanager.fuel",
	"gamemanager.fuel_capacity",
	"gamemanager.resources_total",
	"gamemanager.current_system",
	"gamemanager.current_poi",
	"player.weapon_modules",
	"player.shield_modules",
	"player.engine_modules",
	"player.reactor_modules",
	"player.primary_group_keys",
	"player.secondary_group_keys",
	"inventory.items",
	"inventory.abilities",
	"inventory.equipment",
	"current_weapon.name",
	"current_weapon.ammo",
	"current_weapon.icon",
	"room.name",
	"room.addr",
	"dialogue.speaker",
	"dialogue.text",
	"dialogue.choices",
	"shop.items",
	"shop.message",
	"map.rooms",
	"quest.active",
	"quest.completed",
	"quest.current.title",
	"quest.current.stage_title",
	"quest.current.status",
	"quest.current.objectives",
]

const BINDING_RATIOS: Array = [
	"player.health_pct",
	"player.shields_pct",
	"gamemanager.fuel_pct",
	"player.boost_ready_pct",
	"player.scan_ready_pct",
]

const DYNAMIC_BINDING_PREFIXES: Array = ["game_var."]

const BINDING_GROUPS: Array = [
	{
		"title": "Space-side bindings",
		"entries": ["player.*", "gamemanager.*"],
	},
	{
		"title": "MV-side bindings via fallback resolver",
		"entries": [
			"player.hp",
			"player.max_hp",
			"inventory.*",
			"current_weapon.*",
			"room.*",
			"dialogue.*",
			"shop.items",
			"shop.message",
			"map.rooms",
			"quest.*",
			"game_var.*",
		],
	},
	{
		"title": "Derived ratio bindings",
		"entries": BINDING_RATIOS,
	},
]

const ACTION_IDS: Array = [
	"open_screen",
	"close_screen",
	"buy_item",
	"sell_item",
	"equip_item",
	"unequip",
	"use_item",
	"save_game",
	"load_game",
	"quit_to_menu",
	"resume",
	"end_dialogue",
	"play_sfx",
	"open_settings",
	"new_game",
	"quit_game",
	"creative_mode",
	"test_fly",
	"test_planet",
	"open_editor",
	"update_game",
	"load_slot",
	"fire_event",
	"choose_dialogue",
]

const ACTION_ARG_RULES: Dictionary = {
	"open_screen": {"required": true},
	"buy_item": {"required": true},
	"sell_item": {"required": true},
	"equip_item": {"required": true},
	"unequip": {"required": true},
	"use_item": {"required": true},
	"play_sfx": {"required": true},
	"load_slot": {"required": true, "integer": true},
	"fire_event": {"required": true},
	"choose_dialogue": {"required": true, "integer": true},
}

const HOSTS: Dictionary = {
	"space_hud_overlay": {
		"screen_id": "hud_space",
		"display_name": "Space HUD Overlay",
		"actions": [],
		"open_targets": [],
		"open_prefixes": [],
	},
	"mv_hud_overlay": {
		"screen_id": "hud_mv",
		"display_name": "MV HUD Overlay",
		"actions": [],
		"open_targets": [],
		"open_prefixes": [],
	},
	"pause_menu": {
		"screen_id": "pause",
		"display_name": "Pause Menu",
		"actions": ["resume", "close_screen", "open_screen", "fire_event", "save_game", "load_game", "quit_to_menu", "play_sfx", "open_settings"],
		"open_targets": ["pause", "boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"main_menu": {
		"screen_id": "main_menu",
		"display_name": "Main Menu",
		"actions": ["open_screen", "new_game", "creative_mode", "test_fly", "test_planet", "open_editor", "update_game", "load_slot", "load_game", "fire_event", "quit_to_menu", "quit_game", "play_sfx", "open_settings"],
		"open_targets": ["main_menu", "boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"inventory_screen": {
		"screen_id": "inventory",
		"display_name": "Inventory Screen",
		"actions": ["close_screen", "resume", "open_screen", "fire_event", "equip_item", "unequip", "use_item", "play_sfx"],
		"open_targets": ["inventory", "map", "boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"map_screen": {
		"screen_id": "map",
		"display_name": "Map Screen",
		"actions": ["close_screen", "resume", "open_screen", "fire_event", "play_sfx"],
		"open_targets": ["map", "inventory", "boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"shop_ui": {
		"screen_id": "shop",
		"display_name": "Shop UI",
		"actions": ["close_screen", "resume", "open_screen", "fire_event", "buy_item", "sell_item", "play_sfx"],
		"open_targets": ["shop", "inventory", "map", "boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"dialogue_runner": {
		"screen_id": "dialogue_box",
		"display_name": "Dialogue Runner",
		"actions": ["close_screen", "end_dialogue", "choose_dialogue", "open_screen", "fire_event", "play_sfx"],
		"open_targets": ["boss_intro", "cinematic"],
		"open_prefixes": ["shop:"],
	},
	"game_over": {
		"screen_id": "game_over",
		"display_name": "Game Over",
		"actions": ["load_game", "load_slot", "quit_to_menu", "quit_game", "close_screen", "open_screen", "fire_event", "play_sfx"],
		"open_targets": ["boss_intro", "cinematic"],
		"open_prefixes": [],
	},
	"cinematic_overlay": {
		"screen_id": "boss_intro",
		"display_name": "Cinematic Overlay",
		"actions": ["close_screen", "resume", "fire_event", "play_sfx"],
		"open_targets": [],
		"open_prefixes": [],
	},
}

const KNOWN_GAPS: Array = [
	"`open_screen` is host-routed, not a universal scene navigation system. Current hosts only support the targets listed in the host action matrix below.",
	"`sell_item`, `unequip`, and `use_item` still rely on `action_args` conventions such as `item_id[:count]`, `slot`, or `item_id[:price]`. `equip_item` uses just `item_id`.",
	"Pack-authored item effects currently support `heal_hp`, `max_hp_up`, `add_gold`, `add_ammo`, `max_ammo_up`, `grant_ability`, `add_var`, `set_flag`, `add_tag`, `fire_event`, `set_weapon`, and `equip_item`.",
	"`set_weapon` and equipment `weapon` can target authored attack ids. Legacy `beam` / `grenade_launcher` values still work as compatibility fallbacks.",
	"Player pose authoring drives per-pose `collision_width`, `hurtbox_x/y/w/h`, and `weapon_anchor_x/y`. Enemy leaf projectiles honor the authored hurtbox area.",
	"Authored attacks can define `charge_ticks` plus `charged_attack_id`, so hold-release charged shots are data-driven instead of beam-only.",
	"Authored ranged attacks can define optional `charge_fx_*` sprite fields for a muzzle-tip charging effect while the fire button is held.",
	"Authored projectiles support explosive detonation fields including `explosive`, `blast_radius`, `explosion_damage`, `explode_on_hit`, `explode_on_timeout`, `bomb_jump`, and `bomb_jump_speed`.",
	"Spike hazard contact samples the authored hurtbox instead of the raw body rectangle.",
	"More complex consumable logic still needs a broader effect system.",
	"Generic enemy body-contact damage runs through the player's authored hurtbox area. Entity defs can author `hp`, `attack_damage`, `contact_damage`, `contact_cooldown`, `move_speed`, `projectile_damage`, and `projectile_speed`, and common AI leaves use those as defaults when their params omit overrides.",
	"The `hud_space`, `hud_mv`, and legacy `hud` screens are display-only today. Buttons and item actions on authored HUD screens are rejected at validation time.",
]


static func screen_ids() -> Array:
	return SCREEN_ORDER.duplicate()


static func screen_label(screen_id: String) -> String:
	return str(SCREEN_DEFS.get(screen_id, {}).get("label", screen_id))


static func screen_host_id(screen_id: String) -> String:
	return str(SCREEN_DEFS.get(screen_id, {}).get("host_id", ""))


static func is_known_screen(screen_id: String) -> bool:
	return SCREEN_DEFS.has(screen_id)


static func screen_mount_is_supported(screen_id: String) -> bool:
	return bool(SCREEN_DEFS.get(screen_id, {}).get("mounted", false))


static func binding_sources() -> Array:
	return BINDING_SOURCES.duplicate()


static func binding_ratios() -> Array:
	return BINDING_RATIOS.duplicate()


static func is_known_binding(binding: String) -> bool:
	if BINDING_SOURCES.has(binding) or BINDING_RATIOS.has(binding):
		return true
	for prefix in DYNAMIC_BINDING_PREFIXES:
		if binding.begins_with(prefix):
			return true
	return false


static func binding_has_runtime_support(binding: String) -> bool:
	return is_known_binding(binding)


static func known_action_ids() -> Array:
	return ACTION_IDS.duplicate()


static func is_known_action(action_id: String) -> bool:
	return ACTION_IDS.has(action_id)


static func action_has_runtime_support(action_id: String) -> bool:
	if not is_known_action(action_id):
		return false
	for host_id_v in HOSTS.keys():
		if host_supports_action(str(host_id_v), action_id):
			return true
	return false


static func host_ids() -> Array:
	var out: Array = []
	for host_id_v in HOSTS.keys():
		out.append(str(host_id_v))
	out.sort()
	return out


static func host_screen_id(host_id: String) -> String:
	return str(HOSTS.get(host_id, {}).get("screen_id", ""))


static func host_supports_action(host_id: String, action_id: String) -> bool:
	var actions_v: Variant = HOSTS.get(host_id, {}).get("actions", [])
	return typeof(actions_v) == TYPE_ARRAY and (actions_v as Array).has(action_id)


static func host_supports_open_target(host_id: String, target: String) -> bool:
	var trimmed := target.strip_edges()
	if trimmed.is_empty():
		return false
	var def: Dictionary = HOSTS.get(host_id, {})
	var targets_v: Variant = def.get("open_targets", [])
	if typeof(targets_v) == TYPE_ARRAY and (targets_v as Array).has(trimmed):
		return true
	var prefixes_v: Variant = def.get("open_prefixes", [])
	if typeof(prefixes_v) == TYPE_ARRAY:
		for prefix_v in prefixes_v:
			var prefix := str(prefix_v)
			if trimmed.begins_with(prefix):
				return true
	return false


static func action_arg_rule(action_id: String) -> Dictionary:
	var rule_v: Variant = ACTION_ARG_RULES.get(action_id, {})
	return rule_v if typeof(rule_v) == TYPE_DICTIONARY else {}


static func render_supported_features_markdown() -> String:
	var lines: Array = []
	lines.append("# Supported Features")
	lines.append("")
	lines.append("This file is generated from `Space/scripts/ui/ui_contract.gd`. It is the current runtime/editor contract for authored UI. If the editor exposes something outside this list, that is a bug.")
	lines.append("")
	lines.append("## Authored Screens Mounted At Runtime")
	lines.append("")
	for screen_id in SCREEN_ORDER:
		var def: Dictionary = SCREEN_DEFS.get(screen_id, {})
		lines.append("- `%s`" % screen_id)
		for doc_line_v in str(def.get("doc_description", "")).split("\n"):
			lines.append("  %s" % str(doc_line_v))
	lines.append("")
	lines.append("## Supported Element Types")
	lines.append("")
	for element_type in ELEMENT_TYPES:
		lines.append("- `%s`" % element_type)
	lines.append("")
	lines.append("## Supported Bindings")
	lines.append("")
	for group_v in BINDING_GROUPS:
		var group: Dictionary = group_v
		lines.append("%s:" % str(group.get("title", "Bindings")))
		var entries_v: Variant = group.get("entries", [])
		if typeof(entries_v) == TYPE_ARRAY:
			for entry_v in entries_v:
				lines.append("- `%s`" % str(entry_v))
		lines.append("")
	lines.append("Notes:")
	lines.append("- Bindings are exact except for `game_var.*`.")
	lines.append("- If a binding resolves to `null`, the runtime now warns and renders a visible diagnostic instead of silently pretending it succeeded.")
	lines.append("")
	lines.append("## Supported Actions")
	lines.append("")
	for action_id in ACTION_IDS:
		lines.append("- `%s`" % action_id)
	lines.append("")
	lines.append("## Host Action Support")
	lines.append("")
	for host_id in host_ids():
		var host: Dictionary = HOSTS.get(host_id, {})
		var screen_id := str(host.get("screen_id", ""))
		lines.append("- `%s` (`%s`)" % [screen_id, host_id])
		var actions_v: Variant = host.get("actions", [])
		if typeof(actions_v) == TYPE_ARRAY and not (actions_v as Array).is_empty():
			lines.append("  Actions: %s" % _inline_code_list(actions_v as Array))
		else:
			lines.append("  Actions: none")
		var targets_v: Variant = host.get("open_targets", [])
		var prefixes_v: Variant = host.get("open_prefixes", [])
		var target_bits: Array = []
		if typeof(targets_v) == TYPE_ARRAY:
			target_bits.append_array(targets_v as Array)
		if typeof(prefixes_v) == TYPE_ARRAY:
			for prefix_v in prefixes_v:
				target_bits.append("%s..." % str(prefix_v))
		if not target_bits.is_empty():
			lines.append("  `open_screen` targets: %s" % _inline_code_list(target_bits))
	lines.append("")
	lines.append("## Known Gaps")
	lines.append("")
	for note in KNOWN_GAPS:
		lines.append("- %s" % note)
	return "\n".join(lines) + "\n"


static func _inline_code_list(items: Array) -> String:
	var out: Array = []
	for item_v in items:
		var item_text := str(item_v)
		out.append("`%s`" % item_text)
	return ", ".join(out)
