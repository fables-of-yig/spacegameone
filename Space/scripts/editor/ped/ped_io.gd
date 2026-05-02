extends RefCounted

# Shared IO for all non-sprite player-editor tabs (stats, items, equipment,
# abilities, attacks, projectiles). Same layered read pattern as psp_io.gd:
#
#   1. user://Packs/<pack>/<folder>/<file>      (user edits land here)
#   2. res://Content/<pack>/<folder>/<file>     (shipped pack baseline)
#   3. res://Content/demo/<folder>/<file>       (demo pack fallback)
#   4. built-in default dict baked into this file
#
# All saves write to the user layer so the shipped packs stay read-only.

const SHIPPED_SEED_PACK: String = "demo"
const PspIO = preload("res://Space/scripts/editor/psp/psp_io.gd")


# ── Path helpers ─────────────────────────────────────────────────────────

static func user_file(pack_id: String, folder: String, file_name: String) -> String:
    return "user://Packs/%s/%s/%s" % [pack_id, folder, file_name]


static func shipped_file(pack_id: String, folder: String, file_name: String) -> String:
    return "res://Content/%s/%s/%s" % [pack_id, folder, file_name]


static func demo_file(folder: String, file_name: String) -> String:
    return "res://Content/%s/%s/%s" % [SHIPPED_SEED_PACK, folder, file_name]


# Creates the starter authoring files that a new pack needs without
# consulting shipped/demo content. Existing user files are never changed.
static func ensure_starter_player_data(pack_id: String) -> Array:
    var changed: Array = []
    _write_missing_json(user_file(pack_id, "Player", "stats.json"), default_stats(), changed)
    _write_missing_json(user_file(pack_id, "Player", "stats_manifest.json"), default_stats_manifest(), changed)
    _write_missing_json(user_file(pack_id, "Player", "attacks.json"), default_attacks(), changed)
    _write_missing_json(user_file(pack_id, "Items", "items.json"), default_items(), changed)
    _write_missing_json(user_file(pack_id, "Items", "equipment.json"), default_equipment(), changed)
    _write_missing_json(user_file(pack_id, "Abilities", "abilities.json"), default_abilities(), changed)
    _write_missing_json(user_file(pack_id, "Projectiles", "projectiles.json"), default_projectiles(), changed)
    _write_missing_json(user_file(pack_id, "Triggers", "global.json"), default_triggers(), changed)
    _write_missing_json(user_file(pack_id, "Entities", "entities.json"), default_entities(), changed)
    _write_missing_json(user_file(pack_id, "Entities", "behaviors.json"), default_behaviors(), changed)
    return changed


# ── Stats ────────────────────────────────────────────────────────────────

static func load_stats(pack_id: String) -> Dictionary:
    return _load_or_copy(pack_id, "Player", "stats.json", default_stats())


static func save_stats(pack_id: String, data: Dictionary) -> bool:
    return _write_json(user_file(pack_id, "Player", "stats.json"), data)


static func default_stats() -> Dictionary:
    return {
        "base": {
            "level": 1,
            "exp": 0,
            "exp_to_next": 100,
            "hp_max": 50,
            "mp_max": 10,
            "heart_max": 5,
            "str": 5,
            "con": 4,
            "int": 3,
            "lck": 4,
        },
        "growth": {
            "hp_per_level": 4,
            "mp_per_level": 2,
            "heart_per_level": 1,
            "str_per_level": 1,
            "con_per_level": 1,
            "int_per_level": 1,
            "lck_per_level": 1,
            "exp_curve_multiplier": 1.5,
        },
    }


# ── Stats Manifest (user-defined stats with ManiaVar effects) ────────────

static func load_stats_manifest(pack_id: String) -> Dictionary:
    return _load_or_copy(pack_id, "Player", "stats_manifest.json", default_stats_manifest())


static func save_stats_manifest(pack_id: String, data: Dictionary) -> bool:
    return _write_json(user_file(pack_id, "Player", "stats_manifest.json"), data)


static func default_stats_manifest() -> Dictionary:
    return {
        "stats": [
            {
                "id": "str",
                "name": "Strength",
                "description": "Physical power. Scales melee damage.",
                "category": "core",
                "base_value": 5,
                "growth_per_level": 1,
                "effects": [
                    {"target": "melee_damage_mult", "operation": "add", "value": 0.02, "level_threshold": 1},
                ],
            },
            {
                "id": "con",
                "name": "Constitution",
                "description": "Toughness. Reduces damage taken.",
                "category": "core",
                "base_value": 4,
                "growth_per_level": 1,
                "effects": [
                    {"target": "damage_reduction", "operation": "add", "value": 0.5, "level_threshold": 1},
                ],
            },
            {
                "id": "int",
                "name": "Intelligence",
                "description": "Mental acuity. Scales beam/projectile damage.",
                "category": "core",
                "base_value": 3,
                "growth_per_level": 1,
                "effects": [
                    {"target": "projectile_damage_mult", "operation": "add", "value": 0.02, "level_threshold": 1},
                ],
            },
            {
                "id": "lck",
                "name": "Luck",
                "description": "Fortune. Affects criticals and drop rates.",
                "category": "core",
                "base_value": 4,
                "growth_per_level": 1,
                "effects": [],
            },
            {
                "id": "hp_max",
                "name": "Max HP",
                "description": "Maximum hit points.",
                "category": "vital",
                "base_value": 50,
                "growth_per_level": 4,
                "effects": [
                    {"target": "max_hp", "operation": "set", "value": 50, "level_threshold": 1},
                ],
            },
        ],
    }


# ── Items ────────────────────────────────────────────────────────────────

static func load_items(pack_id: String) -> Dictionary:
    return _load_or_copy(pack_id, "Items", "items.json", default_items())


static func save_items(pack_id: String, data: Dictionary) -> bool:
    if not _validate_items(pack_id, data):
        return false
    return _write_json(user_file(pack_id, "Items", "items.json"), data)


static func default_items() -> Dictionary:
    return {
        "items": [
            {
                "id": "coin",
                "name": "Coin",
                "description": "Currency.",
                "max_stack": 9999,
                "price": 1,
                "category": "currency",
                "use_effect": "",
                "use_amount": 0,
                "use_arg": "",
            },
        ],
    }


static func _validate_items(pack_id: String, data: Dictionary) -> bool:
    var items_v: Variant = data.get("items", [])
    if typeof(items_v) != TYPE_ARRAY:
        push_error("PedIO: items.json must contain an 'items' array")
        return false
    var seen_ids: Dictionary = {}
    var attack_ids := _attack_id_set(pack_id)
    var allowed_effects := {
        "": true,
        "heal_hp": true,
        "max_hp_up": true,
        "add_gold": true,
        "add_ammo": true,
        "max_ammo_up": true,
        "damage_up": true,
        "melee_damage_up": true,
        "projectile_damage_up": true,
        "inventory_slots_up": true,
        "grant_ability": true,
        "add_var": true,
        "set_flag": true,
        "add_tag": true,
        "fire_event": true,
        "set_weapon": true,
        "equip_item": true,
    }
    for i in range((items_v as Array).size()):
        var entry_v: Variant = (items_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: items[%d] must be a dictionary" % i)
            return false
        var entry: Dictionary = entry_v
        var item_id := str(entry.get("id", "")).strip_edges()
        if item_id.is_empty():
            push_error("PedIO: items[%d] is missing an id" % i)
            return false
        if seen_ids.has(item_id):
            push_error("PedIO: duplicate item id '%s'" % item_id)
            return false
        seen_ids[item_id] = true

        var max_stack := int(entry.get("max_stack", 1))
        if max_stack < 1:
            push_error("PedIO: item '%s' has invalid max_stack %d" % [item_id, max_stack])
            return false

        var price := int(entry.get("price", 0))
        if price < 0:
            push_error("PedIO: item '%s' has invalid price %d" % [item_id, price])
            return false

        var effect := str(entry.get("use_effect", "")).strip_edges()
        if not allowed_effects.has(effect):
            push_error("PedIO: item '%s' has unknown use_effect '%s'" % [item_id, effect])
            return false

        var amount := int(entry.get("use_amount", 0))
        if amount < 0:
            push_error("PedIO: item '%s' has invalid use_amount %d" % [item_id, amount])
            return false

        var arg := str(entry.get("use_arg", "")).strip_edges()
        if (effect == "grant_ability" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event" or effect == "set_weapon" or effect == "equip_item" or effect == "add_ammo" or effect == "max_ammo_up") and arg.is_empty():
            push_error("PedIO: item '%s' requires use_arg for effect '%s'" % [item_id, effect])
            return false
        if effect == "set_weapon" and not attack_ids.has(arg) and not _supported_weapon_values().has(arg.to_lower()):
            push_error("PedIO: item '%s' uses unknown set_weapon target '%s'" % [item_id, arg])
            return false
    return true


# ── Equipment ────────────────────────────────────────────────────────────

static func load_equipment(pack_id: String) -> Dictionary:
    return _load_or_copy(pack_id, "Items", "equipment.json", default_equipment())


static func save_equipment(pack_id: String, data: Dictionary) -> bool:
    if not _validate_equipment(pack_id, data):
        return false
    return _write_json(user_file(pack_id, "Items", "equipment.json"), data)


static func default_equipment() -> Dictionary:
    return {
        "equipment": [
            {
                "id": "cadet_blade",
                "name": "Cadet Blade",
                "description": "Starter melee weapon wired to the default three-hit authored combo.",
                "slot": "RightHand",
                "grants_abilities": [],
                "stat_mods": {},
                "weapon": "combo_slash_1",
                "secondary_attack": "",
                "secondary_ammo_key": "",
                "secondary_ammo_cost": 1,
                "sprite_sheet": "equipment_sheet.png",
                "frame_width": 16,
                "frame_height": 16,
                "frame_index": 0,
            },
        ],
    }


# Canonical list of equipment slot names (SOTN-style). Used by the
# equipment tab's slot OptionButton and to validate loaded data.
static func equipment_slots() -> Array:
    return [
        "Head", "Body", "LeftHand", "RightHand",
        "Accessory1", "Accessory2", "Cloak",
    ]


# ── Abilities ────────────────────────────────────────────────────────────

static func load_abilities(pack_id: String) -> Dictionary:
    return _load_or_copy(pack_id, "Abilities", "abilities.json", default_abilities())


static func save_abilities(pack_id: String, data: Dictionary) -> bool:
    if not _validate_abilities(pack_id, data):
        return false
    return _write_json(user_file(pack_id, "Abilities", "abilities.json"), data)


static func default_abilities() -> Dictionary:
    return {"abilities": []}


# ── Attacks ──────────────────────────────────────────────────────────────

static func load_attacks(pack_id: String) -> Dictionary:
    var data: Dictionary = _load_or_copy(pack_id, "Player", "attacks.json", default_attacks())
    if pack_id == SHIPPED_SEED_PACK and _seed_version_is_stale(data, demo_file("Player", "attacks.json")):
        data = _read_json(demo_file("Player", "attacks.json"))
        if not data.is_empty():
            _write_json(user_file(pack_id, "Player", "attacks.json"), data)
    return _ensure_starter_attacks(pack_id, data)


static func save_attacks(pack_id: String, data: Dictionary) -> bool:
    var merged := _merge_root_doc_with_existing(pack_id, "Player", "attacks.json", "attacks", data)
    if not _validate_attacks(pack_id, merged):
        return false
    return _write_json(user_file(pack_id, "Player", "attacks.json"), merged)


static func default_attacks() -> Dictionary:
    return {"attacks": _starter_attack_defs()}


# ── Projectiles ──────────────────────────────────────────────────────────

static func load_projectiles(pack_id: String) -> Dictionary:
    var data: Dictionary = _load_or_copy(pack_id, "Projectiles", "projectiles.json", default_projectiles())
    if pack_id == SHIPPED_SEED_PACK and _seed_version_is_stale(data, demo_file("Projectiles", "projectiles.json")):
        data = _read_json(demo_file("Projectiles", "projectiles.json"))
        if not data.is_empty():
            _write_json(user_file(pack_id, "Projectiles", "projectiles.json"), data)
    return _ensure_starter_projectiles(pack_id, data)


static func save_projectiles(pack_id: String, data: Dictionary) -> bool:
    var merged := _merge_root_doc_with_existing(pack_id, "Projectiles", "projectiles.json", "projectiles", data)
    if not _validate_projectiles(merged):
        return false
    return _write_json(user_file(pack_id, "Projectiles", "projectiles.json"), merged)


static func default_projectiles() -> Dictionary:
    return {"projectiles": _starter_projectile_defs()}


# ── Triggers ────────────────────────────────────────────────────────────

static func _starter_attack_defs() -> Array:
    return [
        {
            "id": "beam_shot",
            "name": "Beam Shot",
            "type": "projectile",
            "projectile_id": "beam_basic",
            "cooldown_ticks": 10,
            "cost_mp": 0,
            "player_pose": 207,
            "hold_behavior": "full_auto",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "",
            "hit_frames": [],
            "hitbox_x": 0,
            "hitbox_y": 0,
            "hitbox_w": 0,
            "hitbox_h": 0,
            "damage": 0,
            "knockback": 0,
            "muzzle_x": 20,
            "muzzle_y": -8,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
        {
            "id": "beam_burst",
            "name": "Charged Beam",
            "type": "projectile",
            "projectile_id": "beam_charged",
            "cooldown_ticks": 20,
            "cost_mp": 0,
            "player_pose": 209,
            "hold_behavior": "full_auto",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "",
            "hit_frames": [],
            "hitbox_x": 0,
            "hitbox_y": 0,
            "hitbox_w": 0,
            "hitbox_h": 0,
            "damage": 0,
            "knockback": 0,
            "muzzle_x": 22,
            "muzzle_y": -8,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
        {
            "id": "combo_slash_1",
            "name": "Combo Slash 1",
            "type": "melee",
            "projectile_id": "",
            "cooldown_ticks": 12,
            "cost_mp": 0,
            "player_pose": 201,
            "hold_behavior": "single_press",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "combo_slash_2",
            "hit_frames": [1, 2],
            "hitbox_x": 18,
            "hitbox_y": -6,
            "hitbox_w": 28,
            "hitbox_h": 24,
            "damage": 12,
            "knockback": 55,
            "muzzle_x": 0,
            "muzzle_y": 0,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
        {
            "id": "combo_slash_2",
            "name": "Combo Slash 2",
            "type": "melee",
            "projectile_id": "",
            "cooldown_ticks": 12,
            "cost_mp": 0,
            "player_pose": 203,
            "hold_behavior": "single_press",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "combo_slash_3",
            "hit_frames": [1, 2],
            "hitbox_x": 20,
            "hitbox_y": -8,
            "hitbox_w": 30,
            "hitbox_h": 24,
            "damage": 14,
            "knockback": 75,
            "muzzle_x": 0,
            "muzzle_y": 0,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
        {
            "id": "combo_slash_3",
            "name": "Combo Slash 3",
            "type": "melee",
            "projectile_id": "",
            "cooldown_ticks": 18,
            "cost_mp": 0,
            "player_pose": 205,
            "hold_behavior": "single_press",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "",
            "hit_frames": [2, 3],
            "hitbox_x": 24,
            "hitbox_y": -8,
            "hitbox_w": 34,
            "hitbox_h": 26,
            "damage": 18,
            "knockback": 110,
            "muzzle_x": 0,
            "muzzle_y": 0,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
        {
            "id": "grenade_shot",
            "name": "Grenade Shot",
            "type": "projectile",
            "projectile_id": "grenade",
            "cooldown_ticks": 18,
            "cost_mp": 0,
            "player_pose": 207,
            "hold_behavior": "full_auto",
            "charge_ticks": 0,
            "charged_attack_id": "",
            "combo_next_id": "",
            "hit_frames": [],
            "hitbox_x": 0,
            "hitbox_y": 0,
            "hitbox_w": 0,
            "hitbox_h": 0,
            "damage": 0,
            "knockback": 0,
            "muzzle_x": 18,
            "muzzle_y": -8,
            "sprite_sheet": "",
            "frame_width": 32,
            "frame_height": 32,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 6,
        },
    ]


static func _starter_projectile_defs() -> Array:
    return [
        {
            "id": "beam_basic",
            "name": "Basic Beam",
            "sprite_sheet": "projectiles_sheet.png",
            "frame_width": 16,
            "frame_height": 8,
            "frame_index": 0,
            "frame_count": 1,
            "frame_tick": 10,
            "speed": 400,
            "gravity": 0,
            "lifetime_ticks": 120,
            "damage": 10,
            "pierces": false,
            "homing": false,
            "homing_strength": 0,
            "hitbox_w": 12,
            "hitbox_h": 6,
            "rotate_to_velocity": false,
            "trail_color": "#88ccff",
        },
        {
            "id": "beam_charged",
            "name": "Charged Beam",
            "sprite_sheet": "projectiles_sheet.png",
            "frame_width": 16,
            "frame_height": 8,
            "frame_index": 1,
            "frame_count": 1,
            "frame_tick": 10,
            "speed": 460,
            "gravity": 0,
            "lifetime_ticks": 150,
            "damage": 24,
            "pierces": false,
            "homing": false,
            "homing_strength": 0,
            "hitbox_w": 14,
            "hitbox_h": 8,
            "rotate_to_velocity": false,
            "trail_color": "#66ffff",
        },
        {
            "id": "grenade",
            "name": "Grenade",
            "sprite_sheet": "projectiles_sheet.png",
            "frame_width": 8,
            "frame_height": 8,
            "frame_index": 2,
            "frame_count": 1,
            "frame_tick": 10,
            "speed": 240,
            "gravity": 600,
            "lifetime_ticks": 180,
            "damage": 30,
            "pierces": false,
            "homing": false,
            "homing_strength": 0,
            "hitbox_w": 8,
            "hitbox_h": 8,
            "rotate_to_velocity": true,
            "trail_color": "#ffaa33",
            "explosive": true,
            "blast_radius": 48,
            "explosion_damage": 30,
            "explode_on_hit": true,
            "explode_on_timeout": true,
            "break_blocks": true,
            "bomb_jump": true,
            "bomb_jump_speed": 180,
        },
    ]


static func _ensure_starter_attacks(pack_id: String, data: Dictionary) -> Dictionary:
    var entries_v: Variant = data.get("attacks", [])
    if typeof(entries_v) != TYPE_ARRAY:
        return data
    var entries: Array = entries_v
    var seen_ids: Dictionary = {}
    for i in range(entries.size()):
        var entry_v: Variant = entries[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var attack_id: String = str(entry.get("id", "")).strip_edges()
        if not attack_id.is_empty():
            seen_ids[attack_id] = true
    var changed: bool = false
    for i in range(entries.size()):
        var entry_v: Variant = entries[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var attack_id: String = str(entry.get("id", "")).strip_edges()
        if attack_id == "beam_shot":
            if int(entry.get("player_pose", -1)) == 22:
                entry["player_pose"] = 207
                changed = true
            if str(entry.get("projectile_id", "")).strip_edges().is_empty():
                entry["projectile_id"] = "beam_basic"
                changed = true
            if str(entry.get("hold_behavior", "")).strip_edges() != "full_auto":
                entry["hold_behavior"] = "full_auto"
                changed = true
            if not str(entry.get("charged_attack_id", "")).strip_edges().is_empty():
                entry["charged_attack_id"] = ""
                changed = true
            if int(entry.get("charge_ticks", 0)) != 0:
                entry["charge_ticks"] = 0
                changed = true
        elif attack_id == "sword_slash":
            if int(entry.get("player_pose", -1)) == 40:
                entry["player_pose"] = 201
                changed = true
        entries[i] = entry
    for starter_v in _starter_attack_defs():
        var starter: Dictionary = starter_v
        var starter_id: String = str(starter.get("id", "")).strip_edges()
        if starter_id.is_empty() or seen_ids.has(starter_id):
            continue
        entries.append(starter.duplicate(true))
        seen_ids[starter_id] = true
        changed = true
    if changed:
        data["attacks"] = entries
        _write_json(user_file(pack_id, "Player", "attacks.json"), data)
    return data


static func _ensure_starter_projectiles(pack_id: String, data: Dictionary) -> Dictionary:
    var entries_v: Variant = data.get("projectiles", [])
    if typeof(entries_v) != TYPE_ARRAY:
        return data
    var entries: Array = entries_v
    var seen_ids: Dictionary = {}
    for entry_v in entries:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var projectile_id: String = str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not projectile_id.is_empty():
            seen_ids[projectile_id] = true
    var changed: bool = false
    for starter_v in _starter_projectile_defs():
        var starter: Dictionary = starter_v
        var starter_id: String = str(starter.get("id", "")).strip_edges()
        if starter_id.is_empty() or seen_ids.has(starter_id):
            continue
        entries.append(starter.duplicate(true))
        seen_ids[starter_id] = true
        changed = true
    if changed:
        data["projectiles"] = entries
        _write_json(user_file(pack_id, "Projectiles", "projectiles.json"), data)
    return data


static func load_triggers(pack_id: String) -> Dictionary:
    return TriggerRoot.normalize_root(_load_or_copy(pack_id, "Triggers", "global.json", default_triggers()))


static func save_triggers(pack_id: String, data: Dictionary) -> bool:
    var normalized := TriggerRoot.normalize_root(data)
    if not _validate_triggers(pack_id, normalized):
        return false
    return _write_json(user_file(pack_id, "Triggers", "global.json"), normalized)


static func default_triggers() -> Dictionary:
    return TriggerRoot.default_root()


# Starter Entities/Behaviors

static func default_entities() -> Dictionary:
    return {
        "entities": [
            {
                "id": "pickup",
                "name": "Pickup",
                "category": "pickup",
                "description": "Touch-collectable item. Set item_id on the room instance.",
                "scene": "res://Scenes/Pickup.tscn",
                "sprite_set": "",
                "behavior": "",
                "movement_mode": "ground",
                "hp": 1,
                "attack_damage": 0,
                "contact_damage": 0,
                "contact_cooldown": 0.8,
                "move_speed": 0,
                "projectile_damage": 0,
                "projectile_speed": 0,
                "melee_range": 0,
                "melee_attack_trigger_frame": -1,
                "projectile_range": 0,
                "projectile_attack_trigger_frame": -1,
                "placement_folder": "Core/Pickups",
            },
            {
                "id": "trigger_volume",
                "name": "Trigger Volume",
                "category": "logic",
                "description": "Invisible walk-into zone. Set width, height, tag, and event_name on the room instance.",
                "scene": "res://Scenes/TriggerVolume.tscn",
                "sprite_set": "",
                "behavior": "",
                "movement_mode": "ground",
                "hp": 1,
                "attack_damage": 0,
                "contact_damage": 0,
                "contact_cooldown": 0.8,
                "move_speed": 0,
                "projectile_damage": 0,
                "projectile_speed": 0,
                "melee_range": 0,
                "melee_attack_trigger_frame": -1,
                "projectile_range": 0,
                "projectile_attack_trigger_frame": -1,
                "placement_folder": "Core/Logic",
            },
        ],
    }


static func default_behaviors() -> Dictionary:
    return {
        "behaviors": [
            {
                "id": "npc_idle",
                "name": "NPC Idle",
                "description": "Passive idle behavior.",
                "root": {
                    "type": "action",
                    "name": "idle",
                    "action": "idle",
                    "params": {},
                },
            },
        ],
    }


# ── Dialogue ────────────────────────────────────────────────────────────

static func load_dialogue(pack_id: String, dialogue_id: String) -> Dictionary:
    var file_name := dialogue_id + ".json"
    for path in [
        user_file(pack_id, "Dialogue", file_name),
        shipped_file(pack_id, "Dialogue", file_name),
        demo_file("Dialogue", file_name),
    ]:
        if FileAccess.file_exists(path):
            var d := _read_json(path)
            if not d.is_empty():
                return d
    return {"id": dialogue_id, "lines": []}


static func save_dialogue(pack_id: String, dialogue_id: String, data: Dictionary) -> bool:
    if not _validate_dialogue(pack_id, dialogue_id, data):
        return false
    return _write_json(user_file(pack_id, "Dialogue", dialogue_id + ".json"), data)


static func list_dialogues(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for base in [
        "user://Packs/%s/Dialogue/" % pack_id,
        "res://Content/%s/Dialogue/" % pack_id,
        "res://Content/demo/Dialogue/",
    ]:
        if not DirAccess.dir_exists_absolute(base):
            continue
        var dir := DirAccess.open(base)
        if dir == null:
            continue
        dir.list_dir_begin()
        while true:
            var entry := dir.get_next()
            if entry.is_empty():
                break
            if entry.ends_with(".json") and not entry.begins_with("_"):
                var id := entry.replace(".json", "")
                if not seen.has(id):
                    seen[id] = true
                    out.append(id)
        dir.list_dir_end()
    out.sort()
    return out


# Shop files: user://Packs/<pack>/Shops/<shop_id>.json. Same 3-layer
# cascade as dialogues (user → shipped → demo fallback). Shop JSON shape:
# { "id": "<id>", "items": [{id, name, price, count}, ...] }.
static func list_shops(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for base in [
        "user://Packs/%s/Shops/" % pack_id,
        "res://Content/%s/Shops/" % pack_id,
        "res://Content/demo/Shops/",
    ]:
        if not DirAccess.dir_exists_absolute(base):
            continue
        var dir := DirAccess.open(base)
        if dir == null:
            continue
        dir.list_dir_begin()
        while true:
            var entry := dir.get_next()
            if entry.is_empty():
                break
            if entry.ends_with(".json") and not entry.begins_with("_"):
                var id := entry.replace(".json", "")
                if not seen.has(id):
                    seen[id] = true
                    out.append(id)
        dir.list_dir_end()
    out.sort()
    return out


static func load_shop(pack_id: String, shop_id: String) -> Dictionary:
    var file_name := shop_id + ".json"
    for path in [
        user_file(pack_id, "Shops", file_name),
        shipped_file(pack_id, "Shops", file_name),
        demo_file("Shops", file_name),
    ]:
        if FileAccess.file_exists(path):
            return _read_json(path)
    return {"id": shop_id, "items": []}


static func save_shop(pack_id: String, shop_id: String, data: Dictionary) -> bool:
    if not _validate_shop(pack_id, shop_id, data):
        return false
    return _write_json(user_file(pack_id, "Shops", shop_id + ".json"), data)


static func _validate_equipment(pack_id: String, data: Dictionary) -> bool:
    var entries_v: Variant = data.get("equipment", [])
    if typeof(entries_v) != TYPE_ARRAY:
        push_error("PedIO: equipment.json must contain an 'equipment' array")
        return false
    var valid_slots := equipment_slots()
    var ability_ids := _ability_id_set(pack_id)
    var attack_ids := _attack_id_set(pack_id)
    var supported_weapons := _supported_weapon_values()
    var seen_ids: Dictionary = {}
    for i in range((entries_v as Array).size()):
        var entry_v: Variant = (entries_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: equipment[%d] must be a dictionary" % i)
            return false
        var entry: Dictionary = entry_v
        var equip_id := str(entry.get("id", "")).strip_edges()
        if equip_id.is_empty():
            push_error("PedIO: equipment[%d] is missing an id" % i)
            return false
        if seen_ids.has(equip_id):
            push_error("PedIO: duplicate equipment id '%s'" % equip_id)
            return false
        seen_ids[equip_id] = true
        if str(entry.get("name", "")).strip_edges().is_empty():
            push_error("PedIO: equipment '%s' is missing a name" % equip_id)
            return false

        var slot := str(entry.get("slot", "")).strip_edges()
        if not valid_slots.has(slot):
            push_error("PedIO: equipment '%s' uses invalid slot '%s'" % [equip_id, slot])
            return false

        var grants_v: Variant = entry.get("grants_abilities", [])
        if typeof(grants_v) != TYPE_ARRAY:
            push_error("PedIO: equipment '%s' grants_abilities must be an array" % equip_id)
            return false
        var granted_seen: Dictionary = {}
        for ability_v in grants_v:
            var ability_id := str(ability_v).strip_edges()
            if ability_id.is_empty():
                push_error("PedIO: equipment '%s' contains an empty granted ability id" % equip_id)
                return false
            if granted_seen.has(ability_id):
                push_error("PedIO: equipment '%s' grants ability '%s' more than once" % [equip_id, ability_id])
                return false
            granted_seen[ability_id] = true
            if not ability_ids.has(ability_id):
                push_error("PedIO: equipment '%s' references unknown ability '%s'" % [equip_id, ability_id])
                return false

        var mods_v: Variant = entry.get("stat_mods", {})
        if typeof(mods_v) != TYPE_DICTIONARY:
            push_error("PedIO: equipment '%s' stat_mods must be a dictionary" % equip_id)
            return false
        for key_v in (mods_v as Dictionary).keys():
            var stat_key := str(key_v).strip_edges()
            if stat_key.is_empty():
                push_error("PedIO: equipment '%s' has an empty stat_mods key" % equip_id)
                return false
            var mod_value: Variant = (mods_v as Dictionary)[key_v]
            if typeof(mod_value) != TYPE_INT and typeof(mod_value) != TYPE_FLOAT:
                push_error("PedIO: equipment '%s' stat_mods['%s'] must be numeric" % [equip_id, stat_key])
                return false

        var weapon := str(entry.get("weapon", "")).strip_edges()
        if not weapon.is_empty() and not attack_ids.has(weapon) and not supported_weapons.has(weapon.to_lower()):
            push_error("PedIO: equipment '%s' uses unsupported weapon '%s' (expected authored attack id or legacy beam/grenade_launcher)" % [equip_id, weapon])
            return false

        var secondary_attack := str(entry.get("secondary_attack", "")).strip_edges()
        if not secondary_attack.is_empty() and not attack_ids.has(secondary_attack):
            push_error("PedIO: equipment '%s' uses unknown secondary_attack '%s'" % [equip_id, secondary_attack])
            return false
        if int(entry.get("secondary_ammo_cost", 1)) < 0:
            push_error("PedIO: equipment '%s' has negative secondary_ammo_cost" % equip_id)
            return false

        if int(entry.get("frame_width", 0)) < 1 or int(entry.get("frame_height", 0)) < 1:
            push_error("PedIO: equipment '%s' has invalid sprite frame size" % equip_id)
            return false
        if int(entry.get("frame_index", 0)) < 0:
            push_error("PedIO: equipment '%s' has negative frame_index" % equip_id)
            return false
    return true


static func _validate_abilities(pack_id: String, data: Dictionary) -> bool:
    var entries_v: Variant = data.get("abilities", [])
    if typeof(entries_v) != TYPE_ARRAY:
        push_error("PedIO: abilities.json must contain an 'abilities' array")
        return false
    var projectile_ids := _projectile_id_set(pack_id)
    var seen_ids: Dictionary = {}
    for i in range((entries_v as Array).size()):
        var entry_v: Variant = (entries_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: abilities[%d] must be a dictionary" % i)
            return false
        var entry: Dictionary = entry_v
        var ability_id := str(entry.get("id", "")).strip_edges()
        if ability_id.is_empty():
            push_error("PedIO: abilities[%d] is missing an id" % i)
            return false
        if seen_ids.has(ability_id):
            push_error("PedIO: duplicate ability id '%s'" % ability_id)
            return false
        seen_ids[ability_id] = true
        if str(entry.get("name", "")).strip_edges().is_empty():
            push_error("PedIO: ability '%s' is missing a name" % ability_id)
            return false
        if str(entry.get("category", "")).strip_edges().is_empty():
            push_error("PedIO: ability '%s' is missing a category" % ability_id)
            return false

        var params_v: Variant = entry.get("params", {})
        if typeof(params_v) != TYPE_DICTIONARY:
            push_error("PedIO: ability '%s' params must be a dictionary" % ability_id)
            return false
        for key_v in (params_v as Dictionary).keys():
            var param_key := str(key_v).strip_edges()
            if param_key.is_empty():
                push_error("PedIO: ability '%s' contains an empty params key" % ability_id)
                return false
        var projectile_id := str((params_v as Dictionary).get("projectile_id", "")).strip_edges()
        if not projectile_id.is_empty() and not projectile_ids.has(projectile_id):
            push_error("PedIO: ability '%s' references unknown projectile '%s'" % [ability_id, projectile_id])
            return false
    return true


static func _validate_attacks(pack_id: String, data: Dictionary) -> bool:
    var entries_v: Variant = data.get("attacks", [])
    if typeof(entries_v) != TYPE_ARRAY:
        push_error("PedIO: attacks.json must contain an 'attacks' array")
        return false
    var projectile_ids := _projectile_id_set(pack_id)
    var pose_ids := _pose_id_set(pack_id)
    var attack_ids := _attack_id_set(pack_id)
    var seen_ids: Dictionary = {}
    var valid_types := {"melee": true, "projectile": true}
    for i in range((entries_v as Array).size()):
        var entry_v: Variant = (entries_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: attacks[%d] must be a dictionary" % i)
            return false
        var entry: Dictionary = entry_v
        var attack_id := str(entry.get("id", "")).strip_edges()
        if attack_id.is_empty():
            push_error("PedIO: attacks[%d] is missing an id" % i)
            return false
        if seen_ids.has(attack_id):
            push_error("PedIO: duplicate attack id '%s'" % attack_id)
            return false
        seen_ids[attack_id] = true
        if str(entry.get("name", "")).strip_edges().is_empty():
            push_error("PedIO: attack '%s' is missing a name" % attack_id)
            return false

        var attack_type := str(entry.get("type", "")).strip_edges()
        var hold_behavior := str(entry.get("hold_behavior", "")).strip_edges()
        if hold_behavior.is_empty():
            hold_behavior = "charge_release" if (not str(entry.get("charged_attack_id", "")).strip_edges().is_empty() and int(entry.get("charge_ticks", 0)) > 0) else "full_auto"
        var valid_hold_behaviors := ["full_auto", "single_press", "charge_release"]
        if not valid_types.has(attack_type):
            push_error("PedIO: attack '%s' uses invalid type '%s'" % [attack_id, attack_type])
            return false
        if not valid_hold_behaviors.has(hold_behavior):
            push_error("PedIO: attack '%s' uses invalid hold_behavior '%s'" % [attack_id, hold_behavior])
            return false
        if int(entry.get("cooldown_ticks", 0)) < 0:
            push_error("PedIO: attack '%s' has negative cooldown_ticks" % attack_id)
            return false
        if int(entry.get("cost_mp", 0)) < 0:
            push_error("PedIO: attack '%s' has negative cost_mp" % attack_id)
            return false
        if int(entry.get("charge_ticks", 0)) < 0:
            push_error("PedIO: attack '%s' has negative charge_ticks" % attack_id)
            return false
        if int(entry.get("player_pose", 0)) < 0:
            push_error("PedIO: attack '%s' has negative player_pose" % attack_id)
            return false
        var player_pose := int(entry.get("player_pose", -1))
        if player_pose >= 0 and not pose_ids.has(player_pose):
            push_error("PedIO: attack '%s' references unknown player_pose %d" % [attack_id, player_pose])
            return false
        if int(entry.get("damage", 0)) < 0:
            push_error("PedIO: attack '%s' has negative damage" % attack_id)
            return false
        if int(entry.get("frame_width", 0)) < 1 or int(entry.get("frame_height", 0)) < 1:
            push_error("PedIO: attack '%s' has invalid sprite frame size" % attack_id)
            return false
        if int(entry.get("frame_index", 0)) < 0:
            push_error("PedIO: attack '%s' has negative frame_index" % attack_id)
            return false
        if int(entry.get("frame_count", 0)) < 1:
            push_error("PedIO: attack '%s' must have frame_count >= 1" % attack_id)
            return false
        if int(entry.get("frame_tick", 0)) < 1:
            push_error("PedIO: attack '%s' must have frame_tick >= 1" % attack_id)
            return false
        if int(entry.get("charge_fx_frame_width", 1)) < 1 or int(entry.get("charge_fx_frame_height", 1)) < 1:
            push_error("PedIO: attack '%s' has invalid charge_fx frame size" % attack_id)
            return false
        if int(entry.get("charge_fx_frame_index", 0)) < 0:
            push_error("PedIO: attack '%s' has negative charge_fx_frame_index" % attack_id)
            return false
        if int(entry.get("charge_fx_frame_count", 1)) < 1:
            push_error("PedIO: attack '%s' must have charge_fx_frame_count >= 1" % attack_id)
            return false
        if int(entry.get("charge_fx_frame_tick", 1)) < 1:
            push_error("PedIO: attack '%s' must have charge_fx_frame_tick >= 1" % attack_id)
            return false
        var charged_attack_id := str(entry.get("charged_attack_id", "")).strip_edges()
        if hold_behavior == "charge_release" and charged_attack_id.is_empty():
            push_error("PedIO: attack '%s' must set charged_attack_id when hold_behavior is charge_release" % attack_id)
            return false
        if hold_behavior == "charge_release" and int(entry.get("charge_ticks", 0)) < 1:
            push_error("PedIO: attack '%s' must use charge_ticks >= 1 when hold_behavior is charge_release" % attack_id)
            return false
        if not charged_attack_id.is_empty():
            if charged_attack_id == attack_id:
                push_error("PedIO: attack '%s' cannot charge into itself" % attack_id)
                return false
            if not attack_ids.has(charged_attack_id):
                push_error("PedIO: attack '%s' references unknown charged_attack_id '%s'" % [attack_id, charged_attack_id])
                return false
            if hold_behavior == "charge_release" and int(entry.get("charge_ticks", 0)) < 1:
                push_error("PedIO: attack '%s' must use charge_ticks >= 1 when charged_attack_id is set" % attack_id)
                return false
        var combo_next_id := str(entry.get("combo_next_id", "")).strip_edges()
        if not combo_next_id.is_empty():
            if combo_next_id == attack_id:
                push_error("PedIO: attack '%s' cannot combo into itself" % attack_id)
                return false
            if not attack_ids.has(combo_next_id):
                push_error("PedIO: attack '%s' references unknown combo_next_id '%s'" % [attack_id, combo_next_id])
                return false

        if attack_type == "projectile":
            var projectile_id := str(entry.get("projectile_id", "")).strip_edges()
            if projectile_id.is_empty():
                push_error("PedIO: projectile attack '%s' is missing projectile_id" % attack_id)
                return false
            if not projectile_ids.has(projectile_id):
                push_error("PedIO: attack '%s' references unknown projectile '%s'" % [attack_id, projectile_id])
                return false
        else:
            var hit_frames_v: Variant = entry.get("hit_frames", [])
            if typeof(hit_frames_v) != TYPE_ARRAY or (hit_frames_v as Array).is_empty():
                push_error("PedIO: melee attack '%s' must define at least one hit frame" % attack_id)
                return false
            for frame_v in (hit_frames_v as Array):
                if int(frame_v) < 0:
                    push_error("PedIO: melee attack '%s' contains a negative hit frame" % attack_id)
                    return false
            if int(entry.get("hitbox_w", 0)) < 1 or int(entry.get("hitbox_h", 0)) < 1:
                push_error("PedIO: melee attack '%s' must have positive hitbox dimensions" % attack_id)
                return false
    return true


static func _validate_projectiles(data: Dictionary) -> bool:
    var entries_v: Variant = data.get("projectiles", [])
    if typeof(entries_v) != TYPE_ARRAY:
        push_error("PedIO: projectiles.json must contain a 'projectiles' array")
        return false
    var seen_ids: Dictionary = {}
    for i in range((entries_v as Array).size()):
        var entry_v: Variant = (entries_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: projectiles[%d] must be a dictionary" % i)
            return false
        var entry: Dictionary = entry_v
        var projectile_id := str(entry.get("id", "")).strip_edges()
        if projectile_id.is_empty():
            push_error("PedIO: projectiles[%d] is missing an id" % i)
            return false
        if seen_ids.has(projectile_id):
            push_error("PedIO: duplicate projectile id '%s'" % projectile_id)
            return false
        seen_ids[projectile_id] = true
        if str(entry.get("name", "")).strip_edges().is_empty():
            push_error("PedIO: projectile '%s' is missing a name" % projectile_id)
            return false
        if int(entry.get("frame_width", 0)) < 1 or int(entry.get("frame_height", 0)) < 1:
            push_error("PedIO: projectile '%s' has invalid sprite frame size" % projectile_id)
            return false
        if int(entry.get("frame_index", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative frame_index" % projectile_id)
            return false
        if int(entry.get("frame_count", 0)) < 1:
            push_error("PedIO: projectile '%s' must have frame_count >= 1" % projectile_id)
            return false
        if int(entry.get("frame_tick", 0)) < 1:
            push_error("PedIO: projectile '%s' must have frame_tick >= 1" % projectile_id)
            return false
        if int(entry.get("speed", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative speed" % projectile_id)
            return false
        if int(entry.get("lifetime_ticks", 0)) < 1:
            push_error("PedIO: projectile '%s' must have lifetime_ticks >= 1" % projectile_id)
            return false
        if int(entry.get("damage", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative damage" % projectile_id)
            return false
        if int(entry.get("blast_radius", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative blast_radius" % projectile_id)
            return false
        if int(entry.get("explosion_damage", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative explosion_damage" % projectile_id)
            return false
        if int(entry.get("bomb_jump_speed", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative bomb_jump_speed" % projectile_id)
            return false
        if int(entry.get("homing_strength", 0)) < 0:
            push_error("PedIO: projectile '%s' has negative homing_strength" % projectile_id)
            return false
        if int(entry.get("hitbox_w", 0)) < 1 or int(entry.get("hitbox_h", 0)) < 1:
            push_error("PedIO: projectile '%s' must have positive hitbox dimensions" % projectile_id)
            return false
        if bool(entry.get("explosive", false)):
            if int(entry.get("blast_radius", 0)) < 1:
                push_error("PedIO: explosive projectile '%s' must have blast_radius >= 1" % projectile_id)
                return false
            if not bool(entry.get("explode_on_hit", true)) and not bool(entry.get("explode_on_timeout", false)):
                push_error("PedIO: explosive projectile '%s' must explode on hit and/or timeout" % projectile_id)
                return false
        var trail_color := str(entry.get("trail_color", "")).strip_edges()
        if not trail_color.is_empty() and not Color.html_is_valid(trail_color):
            push_error("PedIO: projectile '%s' has invalid trail_color '%s'" % [projectile_id, trail_color])
            return false
    return true


static func _validate_triggers(pack_id: String, data: Dictionary) -> bool:
    var triggers: Array = TriggerRoot.flatten_rules(data)
    var item_ids := _item_id_set(pack_id)
    var ability_ids := _ability_id_set(pack_id)
    var entity_ids := _entity_id_set(pack_id)
    var dialogue_ids := _id_set_from_list(list_dialogues(pack_id))
    var shop_ids := _id_set_from_list(list_shops(pack_id))
    var seen_ids: Dictionary = {}
    for i in range(triggers.size()):
        var rule_v: Variant = triggers[i]
        if typeof(rule_v) != TYPE_DICTIONARY:
            push_error("PedIO: triggers[%d] must be a dictionary" % i)
            return false
        var rule: Dictionary = rule_v
        var rule_id := str(rule.get("id", "")).strip_edges()
        if rule_id.is_empty():
            push_error("PedIO: triggers[%d] is missing an id" % i)
            return false
        if seen_ids.has(rule_id):
            push_error("PedIO: duplicate trigger id '%s'" % rule_id)
            return false
        seen_ids[rule_id] = true
        var event_name := str(rule.get("event", "")).strip_edges()
        if event_name.is_empty():
            push_error("PedIO: trigger '%s' is missing an event name" % rule_id)
            return false
        if not _validate_trigger_locals(rule.get("locals", []), "trigger '%s' locals" % rule_id):
            return false
        if not _validate_condition_array(rule.get("conditions", []), "trigger '%s' conditions" % rule_id, item_ids, ability_ids):
            return false
        if not _validate_action_array(rule.get("actions", []), "trigger '%s' actions" % rule_id, item_ids, ability_ids, entity_ids, dialogue_ids, shop_ids):
            return false
    return true


static func _validate_trigger_locals(locals_v: Variant, context: String) -> bool:
    if typeof(locals_v) != TYPE_ARRAY:
        push_error("PedIO: %s must be an array" % context)
        return false
    var seen: Dictionary = {}
    for i in range((locals_v as Array).size()):
        var local_v: Variant = (locals_v as Array)[i]
        if typeof(local_v) != TYPE_DICTIONARY:
            push_error("PedIO: %s[%d] must be a dictionary" % [context, i])
            return false
        var local: Dictionary = local_v
        var name := str(local.get("name", "")).strip_edges()
        if name.is_empty():
            push_error("PedIO: %s[%d] is missing a name" % [context, i])
            return false
        if seen.has(name):
            push_error("PedIO: %s has duplicate local '%s'" % [context, name])
            return false
        seen[name] = true
        var type_name := str(local.get("type", "int")).strip_edges().to_lower()
        if type_name != "int" and type_name != "float" and type_name != "bool" and type_name != "string":
            push_error("PedIO: %s local '%s' has unsupported type '%s'" % [context, name, type_name])
            return false
    return true


static func _validate_dialogue(pack_id: String, dialogue_id: String, data: Dictionary) -> bool:
    var saved_id := str(data.get("id", "")).strip_edges()
    if saved_id.is_empty():
        push_error("PedIO: dialogue save is missing an id")
        return false
    if saved_id != dialogue_id:
        push_error("PedIO: dialogue id mismatch ('%s' vs '%s')" % [dialogue_id, saved_id])
        return false
    var lines_v: Variant = data.get("lines", [])
    if typeof(lines_v) != TYPE_ARRAY:
        push_error("PedIO: dialogue '%s' must contain a 'lines' array" % dialogue_id)
        return false
    var item_ids := _item_id_set(pack_id)
    var ability_ids := _ability_id_set(pack_id)
    var entity_ids := _entity_id_set(pack_id)
    var dialogue_ids := _id_set_from_list(list_dialogues(pack_id))
    dialogue_ids[dialogue_id] = true
    var shop_ids := _id_set_from_list(list_shops(pack_id))
    for i in range((lines_v as Array).size()):
        var line_v: Variant = (lines_v as Array)[i]
        if typeof(line_v) != TYPE_DICTIONARY:
            push_error("PedIO: dialogue '%s' line %d must be a dictionary" % [dialogue_id, i])
            return false
        var line: Dictionary = line_v
        var text := str(line.get("text", ""))
        if text.strip_edges().is_empty():
            push_error("PedIO: dialogue '%s' line %d has empty text" % [dialogue_id, i])
            return false
        var cond_v: Variant = line.get("condition", {})
        if typeof(cond_v) != TYPE_NIL and typeof(cond_v) != TYPE_DICTIONARY:
            push_error("PedIO: dialogue '%s' line %d condition must be a dictionary" % [dialogue_id, i])
            return false
        if typeof(cond_v) == TYPE_DICTIONARY and not (cond_v as Dictionary).is_empty():
            if not _validate_condition_dict(cond_v, "dialogue '%s' line %d condition" % [dialogue_id, i], item_ids, ability_ids):
                return false
        if not _validate_action_array(line.get("actions", []), "dialogue '%s' line %d actions" % [dialogue_id, i], item_ids, ability_ids, entity_ids, dialogue_ids, shop_ids):
            return false
        var choices_v: Variant = line.get("choices", [])
        if typeof(choices_v) == TYPE_NIL:
            continue
        if typeof(choices_v) != TYPE_ARRAY:
            push_error("PedIO: dialogue '%s' line %d choices must be an array" % [dialogue_id, i])
            return false
        for j in range((choices_v as Array).size()):
            var choice_v: Variant = (choices_v as Array)[j]
            if typeof(choice_v) != TYPE_DICTIONARY:
                push_error("PedIO: dialogue '%s' line %d choice %d must be a dictionary" % [dialogue_id, i, j])
                return false
            var choice: Dictionary = choice_v
            if str(choice.get("text", "")).strip_edges().is_empty():
                push_error("PedIO: dialogue '%s' line %d choice %d has empty text" % [dialogue_id, i, j])
                return false
            var choice_cond_v: Variant = choice.get("condition", {})
            if typeof(choice_cond_v) != TYPE_NIL and typeof(choice_cond_v) != TYPE_DICTIONARY:
                push_error("PedIO: dialogue '%s' line %d choice %d condition must be a dictionary" % [dialogue_id, i, j])
                return false
            if typeof(choice_cond_v) == TYPE_DICTIONARY and not (choice_cond_v as Dictionary).is_empty():
                if not _validate_condition_dict(choice_cond_v, "dialogue '%s' line %d choice %d condition" % [dialogue_id, i, j], item_ids, ability_ids):
                    return false
            if not _validate_action_array(choice.get("actions", []), "dialogue '%s' line %d choice %d actions" % [dialogue_id, i, j], item_ids, ability_ids, entity_ids, dialogue_ids, shop_ids):
                return false
    return true


static func _validate_shop(pack_id: String, shop_id: String, data: Dictionary) -> bool:
    var saved_id := str(data.get("id", "")).strip_edges()
    if saved_id.is_empty():
        push_error("PedIO: shop save is missing an id")
        return false
    if saved_id != shop_id:
        push_error("PedIO: shop id mismatch ('%s' vs '%s')" % [shop_id, saved_id])
        return false
    var items_v: Variant = data.get("items", [])
    if typeof(items_v) != TYPE_ARRAY:
        push_error("PedIO: shop '%s' must contain an 'items' array" % shop_id)
        return false
    var item_ids := _item_id_set(pack_id)
    var attack_ids := _attack_id_set(pack_id)
    var allowed_effects := {
        "": true,
        "heal_hp": true,
        "max_hp_up": true,
        "add_gold": true,
        "add_ammo": true,
        "max_ammo_up": true,
        "damage_up": true,
        "melee_damage_up": true,
        "projectile_damage_up": true,
        "inventory_slots_up": true,
        "grant_ability": true,
        "add_var": true,
        "set_flag": true,
        "add_tag": true,
        "fire_event": true,
        "set_weapon": true,
        "equip_item": true,
    }
    var seen_stock_ids: Dictionary = {}
    for i in range((items_v as Array).size()):
        var entry_v: Variant = (items_v as Array)[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            push_error("PedIO: shop '%s' item %d must be a dictionary" % [shop_id, i])
            return false
        var entry: Dictionary = entry_v
        var stock_id := str(entry.get("stock_id", "")).strip_edges()
        if not stock_id.is_empty():
            if seen_stock_ids.has(stock_id):
                push_error("PedIO: shop '%s' contains duplicate stock entry id '%s'" % [shop_id, stock_id])
                return false
            seen_stock_ids[stock_id] = true
        var item_id := str(entry.get("id", "")).strip_edges()
        if item_id.is_empty():
            push_error("PedIO: shop '%s' item %d is missing an id" % [shop_id, i])
            return false
        if not item_ids.has(item_id):
            push_error("PedIO: shop '%s' references unknown item '%s'" % [shop_id, item_id])
            return false
        if int(entry.get("price", 0)) < 0:
            push_error("PedIO: shop '%s' item '%s' has negative price" % [shop_id, item_id])
            return false
        if int(entry.get("count", 1)) < 1:
            push_error("PedIO: shop '%s' item '%s' has invalid count" % [shop_id, item_id])
            return false
        var effect := str(entry.get("use_effect", "")).strip_edges()
        if not allowed_effects.has(effect):
            push_error("PedIO: shop '%s' item '%s' has unknown use_effect '%s'" % [shop_id, item_id, effect])
            return false
        if int(entry.get("use_amount", 0)) < 0:
            push_error("PedIO: shop '%s' item '%s' has invalid use_amount" % [shop_id, item_id])
            return false
        var arg := str(entry.get("use_arg", "")).strip_edges()
        if (effect == "grant_ability" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event" or effect == "set_weapon" or effect == "equip_item" or effect == "add_ammo" or effect == "max_ammo_up") and arg.is_empty():
            push_error("PedIO: shop '%s' item '%s' requires use_arg for effect '%s'" % [shop_id, item_id, effect])
            return false
        if effect == "set_weapon" and not attack_ids.has(arg) and not _supported_weapon_values().has(arg.to_lower()):
            push_error("PedIO: shop '%s' item '%s' uses unknown set_weapon target '%s'" % [shop_id, item_id, arg])
            return false
    return true


static func _validate_condition_array(value: Variant, source: String, item_ids: Dictionary, ability_ids: Dictionary) -> bool:
    if typeof(value) == TYPE_NIL:
        return true
    if typeof(value) != TYPE_ARRAY:
        push_error("PedIO: %s must be an array" % source)
        return false
    for i in range((value as Array).size()):
        var cond_v: Variant = (value as Array)[i]
        if typeof(cond_v) != TYPE_DICTIONARY:
            push_error("PedIO: %s entry %d must be a dictionary" % [source, i])
            return false
        if not _validate_condition_dict(cond_v, "%s entry %d" % [source, i], item_ids, ability_ids):
            return false
    return true


static func _validate_condition_dict(cond_v: Variant, source: String, item_ids: Dictionary, ability_ids: Dictionary) -> bool:
    if typeof(cond_v) != TYPE_DICTIONARY:
        push_error("PedIO: %s must be a dictionary" % source)
        return false
    var cond: Dictionary = cond_v
    var cond_type := str(cond.get("type", "")).strip_edges()
    if cond_type.is_empty():
        push_error("PedIO: %s is missing a condition type" % source)
        return false
    if cond_type == "and" or cond_type == "or":
        var children: Variant = cond.get("children", [])
        if typeof(children) != TYPE_ARRAY:
            push_error("PedIO: %s requires a 'children' array" % source)
            return false
        for i in range((children as Array).size()):
            if not _validate_condition_dict((children as Array)[i], "%s child %d" % [source, i], item_ids, ability_ids):
                return false
        return true
    if cond_type == "not":
        if not cond.has("child"):
            push_error("PedIO: %s requires a 'child' condition" % source)
            return false
        return _validate_condition_dict(cond.get("child", {}), "%s child" % source, item_ids, ability_ids)
    var schema := EcaSchema.find_condition_schema(cond_type)
    if schema.is_empty():
        push_error("PedIO: %s uses unknown condition type '%s'" % [source, cond_type])
        return false
    if not _validate_schema_fields(cond, schema.get("fields", []), source):
        return false
    match cond_type:
        "has_item":
            var item_id := str(cond.get("id", "")).strip_edges()
            if not item_ids.has(item_id):
                push_error("PedIO: %s references unknown item '%s'" % [source, item_id])
                return false
        "has_ability":
            var ability_id := str(cond.get("id", "")).strip_edges()
            if not ability_ids.has(ability_id):
                push_error("PedIO: %s references unknown ability '%s'" % [source, ability_id])
                return false
    return true


static func _validate_action_array(value: Variant, source: String, item_ids: Dictionary, ability_ids: Dictionary, entity_ids: Dictionary, dialogue_ids: Dictionary, shop_ids: Dictionary) -> bool:
    if typeof(value) == TYPE_NIL:
        return true
    if typeof(value) != TYPE_ARRAY:
        push_error("PedIO: %s must be an array" % source)
        return false
    for i in range((value as Array).size()):
        var action_v: Variant = (value as Array)[i]
        if typeof(action_v) != TYPE_DICTIONARY:
            push_error("PedIO: %s entry %d must be a dictionary" % [source, i])
            return false
        var action: Dictionary = action_v
        var action_type := str(action.get("type", "")).strip_edges()
        if action_type.is_empty():
            push_error("PedIO: %s entry %d is missing an action type" % [source, i])
            return false
        var schema := EcaSchema.find_action_schema(action_type)
        if schema.is_empty():
            push_error("PedIO: %s entry %d uses unknown action type '%s'" % [source, i, action_type])
            return false
        if not _validate_schema_fields(action, schema.get("fields", []), "%s entry %d" % [source, i]):
            return false
        match action_type:
            "give_item", "take_item":
                var item_id := str(action.get("id", "")).strip_edges()
                if not item_ids.has(item_id):
                    push_error("PedIO: %s entry %d references unknown item '%s'" % [source, i, item_id])
                    return false
            "give_ability", "revoke_ability":
                var ability_id := str(action.get("id", "")).strip_edges()
                if not ability_ids.has(ability_id):
                    push_error("PedIO: %s entry %d references unknown ability '%s'" % [source, i, ability_id])
                    return false
            "spawn_entity", "despawn_entity", "spawn_entity_at_zone":
                var entity_id := str(action.get("id", "")).strip_edges()
                if not entity_ids.has(entity_id):
                    push_error("PedIO: %s entry %d references unknown entity '%s'" % [source, i, entity_id])
                    return false
            "start_dialogue":
                var dialogue_id := str(action.get("id", "")).strip_edges()
                if not dialogue_ids.has(dialogue_id):
                    push_error("PedIO: %s entry %d references unknown dialogue '%s'" % [source, i, dialogue_id])
                    return false
            "start_shop":
                var shop_id := str(action.get("id", "")).strip_edges()
                if not shop_ids.has(shop_id):
                    push_error("PedIO: %s entry %d references unknown shop '%s'" % [source, i, shop_id])
                    return false
    return true


static func _validate_schema_fields(entry: Dictionary, fields: Array, source: String) -> bool:
    for field_v in fields:
        if typeof(field_v) != TYPE_ARRAY:
            continue
        var field_def: Array = field_v
        if field_def.size() < 3:
            continue
        var key := str(field_def[0])
        var kind := str(field_def[2])
        var optional_field: bool = kind.begins_with("opt_")
        if not entry.has(key):
            if optional_field:
                continue
            push_error("PedIO: %s is missing required field '%s'" % [source, key])
            return false
        var value: Variant = entry.get(key)
        match kind:
            "string":
                if str(value).strip_edges().is_empty():
                    push_error("PedIO: %s field '%s' must not be empty" % [source, key])
                    return false
            "opt_string":
                pass
            "int", "float", "bool":
                pass
            "opt_int", "opt_float":
                pass
    return true


static func _item_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var items_v: Variant = load_items(pack_id).get("items", [])
    if typeof(items_v) != TYPE_ARRAY:
        return out
    for entry_v in items_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var item_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not item_id.is_empty():
            out[item_id] = true
    return out


static func _ability_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var abilities_v: Variant = load_abilities(pack_id).get("abilities", [])
    if typeof(abilities_v) != TYPE_ARRAY:
        return out
    for entry_v in abilities_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var ability_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not ability_id.is_empty():
            out[ability_id] = true
    return out


static func _projectile_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var projectiles_v: Variant = load_projectiles(pack_id).get("projectiles", [])
    if typeof(projectiles_v) != TYPE_ARRAY:
        return out
    for entry_v in projectiles_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var projectile_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not projectile_id.is_empty():
            out[projectile_id] = true
    return out


static func _seed_version_is_stale(current_data: Dictionary, shipped_path: String) -> bool:
    var shipped_data: Dictionary = _read_json(shipped_path)
    if shipped_data.is_empty():
        return false
    return int(current_data.get("seed_version", 0)) < int(shipped_data.get("seed_version", 0))


static func _merge_root_doc_with_existing(pack_id: String, folder: String, file_name: String,
        primary_key: String, data: Dictionary) -> Dictionary:
    var merged: Dictionary = {}
    var existing := _read_json(user_file(pack_id, folder, file_name))
    if existing.is_empty():
        existing = _read_json(shipped_file(pack_id, folder, file_name))
    if existing.is_empty():
        existing = _read_json(demo_file(folder, file_name))
    for key_v in existing.keys():
        var key := str(key_v)
        if key == primary_key:
            continue
        merged[key] = existing[key_v]
    for key_v in data.keys():
        merged[key_v] = data[key_v]
    return merged


static func _pose_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var loaded: Dictionary = PspIO.load_or_init(pack_id)
    var poses_root_v: Variant = loaded.get("poses", {})
    if typeof(poses_root_v) != TYPE_DICTIONARY:
        return out
    var poses_v: Variant = (poses_root_v as Dictionary).get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        return out
    for key in (poses_v as Dictionary).keys():
        var key_str := str(key)
        if key_str.is_valid_int():
            out[int(key_str)] = true
    return out


static func _attack_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var attacks_v: Variant = load_attacks(pack_id).get("attacks", [])
    if typeof(attacks_v) != TYPE_ARRAY:
        return out
    for entry_v in attacks_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var attack_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not attack_id.is_empty():
            out[attack_id] = true
    return out


static func _supported_weapon_values() -> Dictionary:
    return {
        "beam": true,
        "grenadelauncher": true,
        "grenade_launcher": true,
        "grenade launcher": true,
    }


static func _entity_id_set(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var raw := _read_json(user_file(pack_id, "Entities", "entities.json"))
    if raw.is_empty():
        raw = _read_json(shipped_file(pack_id, "Entities", "entities.json"))
    if raw.is_empty():
        raw = _read_json(demo_file("Entities", "entities.json"))
    var entities_v: Variant = raw.get("entities", [])
    if typeof(entities_v) != TYPE_ARRAY:
        return out
    for entry_v in entities_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entity_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not entity_id.is_empty():
            out[entity_id] = true
    return out


static func _id_set_from_list(values: Array) -> Dictionary:
    var out: Dictionary = {}
    for value_v in values:
        var id_str := str(value_v).strip_edges()
        if not id_str.is_empty():
            out[id_str] = true
    return out


# ── Load-or-copy core ────────────────────────────────────────────────────
# Read user layer → shipped layer → demo layer → fall back to baked default.
# When the user layer is missing but a shipped/demo copy exists, we write
# that copy into the user layer so subsequent saves have a place to land.

static func _load_or_copy(pack_id: String, folder: String, file_name: String, fallback: Dictionary) -> Dictionary:
    var up := user_file(pack_id, folder, file_name)
    if FileAccess.file_exists(up):
        var d := _read_json(up)
        if not d.is_empty():
            return d
    var sp := shipped_file(pack_id, folder, file_name)
    if FileAccess.file_exists(sp):
        var sd := _read_json(sp)
        if not sd.is_empty():
            _write_json(up, sd)
            return sd
    var dp := demo_file(folder, file_name)
    if FileAccess.file_exists(dp):
        var dd := _read_json(dp)
        if not dd.is_empty():
            _write_json(up, dd)
            return dd
    _write_json(up, fallback)
    return fallback


# ── JSON helpers ─────────────────────────────────────────────────────────

static func _read_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    return raw


static func _write_json(path: String, data: Dictionary) -> bool:
    var slash := path.rfind("/")
    if slash > 0:
        DirAccess.make_dir_recursive_absolute(path.substr(0, slash))
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("PedIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


static func _write_missing_json(path: String, data: Dictionary, changed: Array) -> bool:
    if FileAccess.file_exists(path):
        return false
    if not _write_json(path, data):
        return false
    changed.append(path)
    return true
