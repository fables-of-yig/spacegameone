extends Node

# Player inventory state. Autoloaded as `PlayerInventory`.
# Tracks abilities, items (id → count), equipment (slot → item_id),
# game variables (string → Variant), and weapon type.

signal item_changed(item_id: String, new_count: int)
signal equipment_changed(slot: String, item_id: String)
signal ability_changed(ability_id: String, granted: bool)
signal var_changed(key: String, value: Variant)

enum WeaponType {
	BEAM = 0,
	GRENADE_LAUNCHER = 1,
}

var _abilities: Dictionary = {}
var _items: Dictionary = {}
var _equipment: Dictionary = {}
var _game_vars: Dictionary = {}
var _active_weapon: WeaponType = WeaponType.BEAM
var _active_attack_id: String = ""
var _item_defs_cache: Dictionary = {}
var _equipment_defs_cache: Dictionary = {}
var _attack_defs_cache: Dictionary = {}
var _projectile_defs_cache: Dictionary = {}
var _defs_pack_id: String = ""


# ── Abilities ───────────────────────────────────────────────────────────

func has_ability(id: String) -> bool:
	return _abilities.has(id)


func grant_ability(id: String) -> void:
	if id.is_empty():
		return
	_abilities[id] = true
	ability_changed.emit(id, true)
	MvTriggerEngine.fire_event("ability_grant", { "ability_id": id })


func revoke_ability(id: String) -> void:
	if not _abilities.has(id):
		return
	_abilities.erase(id)
	ability_changed.emit(id, false)
	MvTriggerEngine.fire_event("ability_revoke", { "ability_id": id })


func get_abilities() -> Array:
	return _abilities.keys()


# ── Items ───────────────────────────────────────────────────────────────

func add_item(id: String, count: int = 1) -> void:
	if id.is_empty() or count <= 0:
		return
	var def := get_item_definition(id)
	if bool(def.get("auto_use_on_gain", false)) and _apply_item_effect(def, count):
		return
	_items[id] = _items.get(id, 0) + count
	item_changed.emit(id, _items[id])


func remove_item(id: String, count: int = 1) -> void:
	if not _items.has(id):
		return
	_items[id] = maxi(_items[id] - count, 0)
	if _items[id] == 0:
		_items.erase(id)
	item_changed.emit(id, _items.get(id, 0))
	MvTriggerEngine.fire_event("item_loss", {
		"item_id": id,
		"count": count,
		"remaining": _items.get(id, 0),
	})


func has_item(id: String, min_count: int = 1) -> bool:
	return _items.get(id, 0) >= min_count


func item_count(id: String) -> int:
	return _items.get(id, 0)


# ── Equipment ───────────────────────────────────────────────────────────

func equip(slot: String, item_id: String) -> void:
	if slot.is_empty():
		return
	var prev_item_id := str(_equipment.get(slot, ""))
	if not prev_item_id.is_empty():
		_remove_equipment_effects(prev_item_id)
	_equipment[slot] = item_id
	_apply_equipment_effects(item_id)
	equipment_changed.emit(slot, item_id)


func unequip(slot: String) -> void:
	var prev_item_id := str(_equipment.get(slot, ""))
	if not prev_item_id.is_empty():
		_remove_equipment_effects(prev_item_id)
	_equipment.erase(slot)
	equipment_changed.emit(slot, "")


func equipped_in(slot: String) -> String:
	return _equipment.get(slot, "")


# ── Game variables ──────────────────────────────────────────────────────

func get_var(key: String, default: Variant = null) -> Variant:
	return _game_vars.get(key, default)


func set_var(key: String, value: Variant) -> void:
	_game_vars[key] = value
	var_changed.emit(key, value)


func add_var(key: String, amount: float) -> void:
	_game_vars[key] = float(_game_vars.get(key, 0)) + amount
	var_changed.emit(key, _game_vars[key])


# ── Weapon ──────────────────────────────────────────────────────────────

func get_active_weapon_type() -> WeaponType:
	return _active_weapon


func set_active_weapon_type(w: WeaponType) -> void:
	_active_weapon = w
	var mapped_attack_id := _legacy_attack_id_from_weapon_type(w)
	if not mapped_attack_id.is_empty():
		_active_attack_id = mapped_attack_id
	else:
		_active_attack_id = ""


func get_active_attack_id() -> String:
	_ensure_defs_loaded()
	if not _active_attack_id.is_empty() and _attack_defs_cache.has(_active_attack_id):
		return _active_attack_id
	var equipped_attack_id := _resolve_equipped_attack()
	if not equipped_attack_id.is_empty():
		return equipped_attack_id
	if _active_weapon != WeaponType.BEAM:
		return ""
	return _default_attack_id()


func get_melee_attack_id() -> String:
	_ensure_defs_loaded()
	return _attack_id_for_type("melee", "combo_slash_1")


func get_ranged_attack_id() -> String:
	_ensure_defs_loaded()
	return _attack_id_for_type("projectile", "beam_shot")


func get_secondary_attack_id() -> String:
	_ensure_defs_loaded()
	var config := _resolve_equipped_secondary_config()
	return str(config.get("attack_id", ""))


func get_secondary_ammo_key() -> String:
	_ensure_defs_loaded()
	var config := _resolve_equipped_secondary_config()
	return str(config.get("ammo_key", ""))


func get_secondary_ammo_cost() -> int:
	_ensure_defs_loaded()
	var config := _resolve_equipped_secondary_config()
	return int(config.get("ammo_cost", 1))


func set_active_attack_id(attack_id: String) -> void:
	_ensure_defs_loaded()
	var clean_id := attack_id.strip_edges()
	if clean_id.is_empty() or not _attack_defs_cache.has(clean_id):
		return
	_active_attack_id = clean_id
	_active_weapon = _weapon_type_from_attack_id(clean_id)


func get_item_definition(item_id: String) -> Dictionary:
	_ensure_defs_loaded()
	return (_item_defs_cache.get(item_id, {}) as Dictionary).duplicate(true)


func get_equipment_definition(item_id: String) -> Dictionary:
	_ensure_defs_loaded()
	return (_equipment_defs_cache.get(item_id, {}) as Dictionary).duplicate(true)


func get_attack_definition(attack_id: String) -> Dictionary:
	_ensure_defs_loaded()
	return _normalize_attack_definition((_attack_defs_cache.get(attack_id, {}) as Dictionary).duplicate(true))


func get_projectile_definition(projectile_id: String) -> Dictionary:
	_ensure_defs_loaded()
	return (_projectile_defs_cache.get(projectile_id, {}) as Dictionary).duplicate(true)


func equip_item_by_id(item_id: String) -> bool:
	var def := get_equipment_definition(item_id)
	if def.is_empty():
		return false
	var slot := str(def.get("slot", "")).strip_edges()
	if slot.is_empty():
		return false
	equip(slot, item_id)
	return true


func use_item_definition(item_id: String, count: int = 1) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	if not has_item(item_id, count):
		return false
	var def := get_item_definition(item_id)
	if def.is_empty():
		return false
	if not _apply_item_effect(def, count):
		return false
	remove_item(item_id, count)
	return true


func apply_item_effect_definition(def: Dictionary, count: int = 1) -> bool:
	if count <= 0:
		return false
	return _apply_item_effect(def, count)


func _apply_item_effect(def: Dictionary, count: int = 1) -> bool:
	var effect := str(def.get("use_effect", "")).strip_edges()
	if effect.is_empty():
		return false
	var amount := int(def.get("use_amount", 0))
	var arg := str(def.get("use_arg", "")).strip_edges()
	var player := _get_player()
	match effect:
		"heal_hp":
			if player == null or not player.has_method("heal"):
				return false
			player.heal(maxi(amount, 0) * count)
		"max_hp_up":
			if player == null:
				return false
			player.max_hp += maxi(amount, 0) * count
			player.hp = mini(player.hp + maxi(amount, 0) * count, player.max_hp)
		"add_gold":
			add_var("gold", float(amount) * count)
		"add_ammo":
			if arg.is_empty():
				return false
			var ammo_key := "ammo_%s" % arg
			var max_key := "max_ammo_%s" % arg
			var max_ammo := int(get_var(max_key, 0))
			var current_ammo := int(get_var(ammo_key, max_ammo if max_ammo > 0 else 0))
			var next_ammo := current_ammo + maxi(amount, 0) * count
			if max_ammo > 0:
				next_ammo = mini(next_ammo, max_ammo)
			set_var(ammo_key, next_ammo)
		"max_ammo_up":
			if arg.is_empty():
				return false
			var maxup_ammo_key := "ammo_%s" % arg
			var maxup_max_key := "max_ammo_%s" % arg
			var increase := maxi(amount, 0) * count
			var old_max_ammo := int(get_var(maxup_max_key, 0))
			var new_max_ammo := old_max_ammo + increase
			var maxup_current_ammo := int(get_var(maxup_ammo_key, old_max_ammo if old_max_ammo > 0 else 0))
			set_var(maxup_max_key, new_max_ammo)
			set_var(maxup_ammo_key, mini(maxup_current_ammo + increase, new_max_ammo))
		"damage_up":
			add_var("mv_melee_damage_bonus", float(amount) * count)
			add_var("mv_projectile_damage_bonus", float(amount) * count)
		"melee_damage_up":
			add_var("mv_melee_damage_bonus", float(amount) * count)
		"projectile_damage_up":
			add_var("mv_projectile_damage_bonus", float(amount) * count)
		"inventory_slots_up":
			add_var("inventory_slots_bonus", float(amount) * count)
		"grant_ability":
			if arg.is_empty():
				return false
			for _i in range(count):
				grant_ability(arg)
		"add_var":
			if arg.is_empty():
				return false
			add_var(arg, float(amount) * count)
		"set_flag":
			if arg.is_empty():
				return false
			set_var("flag_%s" % arg, amount != 0)
		"add_tag":
			if arg.is_empty() or MvTriggerEngine == null:
				return false
			var tag_value: Variant
			if amount <= 0:
				tag_value = true
			else:
				tag_value = amount * count
			MvTriggerEngine.set_global_tag(arg, tag_value)
		"fire_event":
			if arg.is_empty() or MvTriggerEngine == null:
				return false
			MvTriggerEngine.fire_event(arg, {
				"item_id": str(def.get("id", "")),
				"stock_id": str(def.get("stock_id", "")),
				"count": count,
			})
		"set_weapon":
			if _attack_defs_cache.has(arg):
				set_active_attack_id(arg)
			else:
				set_active_weapon_type(_weapon_type_from_name(arg))
		"equip_item":
			if arg.is_empty():
				return false
			return equip_item_by_id(arg)
		_:
			return false
	return true


# ── Snapshot / Restore ──────────────────────────────────────────────────

func snapshot() -> Dictionary:
	return {
		"abilities": _abilities.duplicate(),
		"items": _items.duplicate(),
		"equipment": _equipment.duplicate(),
		"game_vars": _game_vars.duplicate(),
		"active_weapon": _active_weapon,
		"active_attack_id": _active_attack_id,
	}


func restore(data: Dictionary) -> void:
	_abilities = data.get("abilities", {}).duplicate()
	_items = data.get("items", {}).duplicate()
	_equipment = data.get("equipment", {}).duplicate()
	_game_vars = data.get("game_vars", {}).duplicate()
	_active_weapon = data.get("active_weapon", WeaponType.BEAM)
	_active_attack_id = str(data.get("active_attack_id", "")).strip_edges()
	_reapply_equipment_state()


func clear() -> void:
	_abilities.clear()
	_items.clear()
	_equipment.clear()
	_game_vars.clear()
	_active_weapon = WeaponType.BEAM
	_active_attack_id = ""
	_item_defs_cache.clear()
	_equipment_defs_cache.clear()
	_attack_defs_cache.clear()
	_projectile_defs_cache.clear()
	_defs_pack_id = ""


# Drops the cached attack/projectile definitions so the next access re-reads
# them from disk. Called by the in-game Player Attack Workshop after it writes
# attacks.json / projectiles.json, so an authored attack is usable immediately
# without a room reload. Unlike clear(), this preserves live inventory state.
func reload_combat_defs() -> void:
	_attack_defs_cache.clear()
	_projectile_defs_cache.clear()
	_defs_pack_id = ""


func _ensure_defs_loaded() -> void:
	var pack_id := MvPackLoader.current_pack.pack_id if MvPackLoader.current_pack != null else "demo"
	if pack_id == _defs_pack_id \
			and not _item_defs_cache.is_empty() \
			and not _equipment_defs_cache.is_empty() \
			and not _attack_defs_cache.is_empty() \
			and not _projectile_defs_cache.is_empty():
		return
	_defs_pack_id = pack_id
	_item_defs_cache.clear()
	_equipment_defs_cache.clear()
	_attack_defs_cache.clear()
	_projectile_defs_cache.clear()

	var items_path := MvPackLoader.resolve_read_cascade(pack_id, "Items", "items.json")
	var items_raw := MvPackLoader.read_json_dict(items_path)
	var items_v: Variant = items_raw.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		for entry_v in items_v:
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var item_id := str(entry.get("id", "")).strip_edges()
			if not item_id.is_empty():
				_item_defs_cache[item_id] = entry.duplicate(true)

	var equip_path := MvPackLoader.resolve_read_cascade(pack_id, "Items", "equipment.json")
	var equip_raw := MvPackLoader.read_json_dict(equip_path)
	var equip_v: Variant = equip_raw.get("equipment", [])
	if typeof(equip_v) == TYPE_ARRAY:
		for entry_v in equip_v:
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var item_id := str(entry.get("id", "")).strip_edges()
			if not item_id.is_empty():
				_equipment_defs_cache[item_id] = entry.duplicate(true)

	var attacks_path := MvPackLoader.resolve_read_cascade(pack_id, "Player", "attacks.json")
	var attacks_raw := MvPackLoader.read_json_dict(attacks_path)
	attacks_raw = _prefer_demo_seeded_data(pack_id, attacks_raw, "Player", "attacks.json")
	var attacks_v: Variant = attacks_raw.get("attacks", [])
	if typeof(attacks_v) == TYPE_ARRAY:
		for entry_v in attacks_v:
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = _normalize_attack_definition(entry_v as Dictionary)
			var attack_id := str(entry.get("id", "")).strip_edges()
			if not attack_id.is_empty():
				_attack_defs_cache[attack_id] = entry.duplicate(true)

	var projectiles_path := MvPackLoader.resolve_read_cascade(pack_id, "Projectiles", "projectiles.json")
	var projectiles_raw := MvPackLoader.read_json_dict(projectiles_path)
	projectiles_raw = _prefer_demo_seeded_data(pack_id, projectiles_raw, "Projectiles", "projectiles.json")
	var projectiles_v: Variant = projectiles_raw.get("projectiles", [])
	if typeof(projectiles_v) == TYPE_ARRAY:
		for entry_v in projectiles_v:
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var projectile_id := str(entry.get("id", "")).strip_edges()
			if not projectile_id.is_empty():
				_projectile_defs_cache[projectile_id] = entry.duplicate(true)


func _prefer_demo_seeded_data(pack_id: String, current_data: Dictionary, folder: String, file_name: String) -> Dictionary:
	if pack_id != "demo":
		return current_data
	var shipped_path := "res://Content/demo/%s/%s" % [folder, file_name]
	var shipped_data := MvPackLoader.read_json_dict(shipped_path)
	if shipped_data.is_empty():
		return current_data
	if int(current_data.get("seed_version", 0)) < int(shipped_data.get("seed_version", 0)):
		return shipped_data
	return current_data


func _apply_equipment_effects(item_id: String) -> void:
	if item_id.is_empty():
		return
	var def := get_equipment_definition(item_id)
	if def.is_empty():
		return
	var grants_v: Variant = def.get("grants_abilities", [])
	if typeof(grants_v) == TYPE_ARRAY:
		for ability_v in grants_v:
			var ability_id := str(ability_v).strip_edges()
			if not ability_id.is_empty():
				grant_ability(ability_id)
	var weapon_name := str(def.get("weapon", "")).strip_edges()
	if not weapon_name.is_empty():
		_apply_weapon_selection(weapon_name)


func _remove_equipment_effects(item_id: String) -> void:
	if item_id.is_empty():
		return
	var def := get_equipment_definition(item_id)
	if def.is_empty():
		return
	var grants_v: Variant = def.get("grants_abilities", [])
	if typeof(grants_v) == TYPE_ARRAY:
		for ability_v in grants_v:
			var ability_id := str(ability_v).strip_edges()
			if ability_id.is_empty():
				continue
			if not _ability_granted_by_other_equipment(ability_id, item_id):
				revoke_ability(ability_id)
	if str(def.get("weapon", "")).strip_edges() != "":
		_active_weapon = _resolve_equipped_weapon()
		_active_attack_id = _resolve_equipped_attack()


func _ability_granted_by_other_equipment(ability_id: String, excluding_item_id: String) -> bool:
	for equipped_item_id_v in _equipment.values():
		var equipped_item_id := str(equipped_item_id_v)
		if equipped_item_id.is_empty() or equipped_item_id == excluding_item_id:
			continue
		var def := get_equipment_definition(equipped_item_id)
		var grants_v: Variant = def.get("grants_abilities", [])
		if typeof(grants_v) != TYPE_ARRAY:
			continue
		if (grants_v as Array).has(ability_id):
			return true
	return false


func _resolve_equipped_weapon() -> WeaponType:
	for slot in _equipment.keys():
		var item_id := str(_equipment.get(slot, ""))
		if item_id.is_empty():
			continue
		var def := get_equipment_definition(item_id)
		var weapon_name := str(def.get("weapon", "")).strip_edges()
		if not weapon_name.is_empty():
			if _attack_defs_cache.has(weapon_name):
				return _weapon_type_from_attack_id(weapon_name)
			return _weapon_type_from_name(weapon_name)
	return WeaponType.BEAM


func _resolve_equipped_attack() -> String:
	for slot in _equipment.keys():
		var item_id := str(_equipment.get(slot, ""))
		if item_id.is_empty():
			continue
		var def := get_equipment_definition(item_id)
		var weapon_name := str(def.get("weapon", "")).strip_edges()
		if weapon_name.is_empty():
			continue
		if _attack_defs_cache.has(weapon_name):
			return weapon_name
		var mapped_attack_id := _legacy_attack_id_from_weapon_name(weapon_name)
		if not mapped_attack_id.is_empty():
			return mapped_attack_id
	return ""


func _resolve_equipped_secondary_config() -> Dictionary:
	for slot in _equipment.keys():
		var item_id := str(_equipment.get(slot, "")).strip_edges()
		if item_id.is_empty():
			continue
		var def := get_equipment_definition(item_id)
		var attack_id := str(def.get("secondary_attack", "")).strip_edges()
		if attack_id.is_empty() or not _attack_defs_cache.has(attack_id):
			continue
		var ammo_key := str(def.get("secondary_ammo_key", "")).strip_edges()
		return {
			"attack_id": attack_id,
			"ammo_key": ammo_key,
			"ammo_cost": maxi(0, int(def.get("secondary_ammo_cost", 1))),
		}
	return {}


func _reapply_equipment_state() -> void:
	_ensure_defs_loaded()
	var equipped_ids: Array = _equipment.values().duplicate()
	_active_weapon = WeaponType.BEAM
	_active_attack_id = ""
	for ability_id in _abilities.keys().duplicate():
		if not _ability_granted_by_current_equipment(str(ability_id)):
			continue
		revoke_ability(str(ability_id))
	for item_id_v in equipped_ids:
		var item_id := str(item_id_v)
		if not item_id.is_empty():
			_apply_equipment_effects(item_id)
	if _active_attack_id.is_empty():
		_active_attack_id = _resolve_equipped_attack()


func _ability_granted_by_current_equipment(ability_id: String) -> bool:
	for equipped_item_id_v in _equipment.values():
		var def := get_equipment_definition(str(equipped_item_id_v))
		var grants_v: Variant = def.get("grants_abilities", [])
		if typeof(grants_v) == TYPE_ARRAY and (grants_v as Array).has(ability_id):
			return true
	return false


func _weapon_type_from_name(weapon_name: String) -> WeaponType:
	var key := weapon_name.strip_edges().to_lower()
	match key:
		"grenadelauncher", "grenade_launcher", "grenade launcher":
			return WeaponType.GRENADE_LAUNCHER
	return WeaponType.BEAM


func _weapon_type_from_attack_id(attack_id: String) -> WeaponType:
	var attack := get_attack_definition(attack_id)
	if attack.is_empty():
		return WeaponType.BEAM
	var projectile_id := str(attack.get("projectile_id", "")).strip_edges().to_lower()
	if projectile_id.find("grenade") >= 0:
		return WeaponType.GRENADE_LAUNCHER
	return WeaponType.BEAM


func _legacy_attack_id_from_weapon_name(weapon_name: String) -> String:
	var key := weapon_name.strip_edges().to_lower()
	match key:
		"beam":
			return "beam_shot" if _attack_defs_cache.has("beam_shot") else ""
		"grenadelauncher", "grenade_launcher", "grenade launcher":
			return "grenade_shot" if _attack_defs_cache.has("grenade_shot") else ""
	return ""


func _legacy_attack_id_from_weapon_type(w: WeaponType) -> String:
	match w:
		WeaponType.GRENADE_LAUNCHER:
			return _legacy_attack_id_from_weapon_name("grenade_launcher")
		_:
			return _legacy_attack_id_from_weapon_name("beam")


func _default_attack_id() -> String:
	if _attack_defs_cache.has("beam_shot"):
		return "beam_shot"
	var keys := _attack_defs_cache.keys()
	if keys.is_empty():
		return ""
	keys.sort()
	return str(keys[0])


func _apply_weapon_selection(weapon_name: String) -> void:
	if _attack_defs_cache.has(weapon_name):
		set_active_attack_id(weapon_name)
		return
	set_active_weapon_type(_weapon_type_from_name(weapon_name))


func _attack_id_for_type(attack_type: String, preferred_id: String) -> String:
	if _attack_matches_type(_active_attack_id, attack_type):
		return _active_attack_id
	var equipped_attack_id := _resolve_equipped_attack_by_type(attack_type)
	if not equipped_attack_id.is_empty():
		return equipped_attack_id
	if _attack_matches_type(preferred_id, attack_type):
		return preferred_id
	return _first_attack_id_by_type(attack_type)


func _attack_matches_type(attack_id: String, attack_type: String) -> bool:
	var clean_id := attack_id.strip_edges()
	if clean_id.is_empty() or not _attack_defs_cache.has(clean_id):
		return false
	var attack := get_attack_definition(clean_id)
	return str(attack.get("type", "")).strip_edges().to_lower() == attack_type


func _resolve_equipped_attack_by_type(attack_type: String) -> String:
	for slot in _equipment.keys():
		var item_id := str(_equipment.get(slot, "")).strip_edges()
		if item_id.is_empty():
			continue
		var def := get_equipment_definition(item_id)
		var weapon_name := str(def.get("weapon", "")).strip_edges()
		if weapon_name.is_empty():
			continue
		var attack_id := weapon_name if _attack_defs_cache.has(weapon_name) else _legacy_attack_id_from_weapon_name(weapon_name)
		if _attack_matches_type(attack_id, attack_type):
			return attack_id
	return ""


func _first_attack_id_by_type(attack_type: String) -> String:
	var attack_ids := _attack_defs_cache.keys()
	attack_ids.sort()
	for attack_id_v in attack_ids:
		var attack_id := str(attack_id_v)
		if _attack_matches_type(attack_id, attack_type):
			return attack_id
	return ""


func _normalize_attack_definition(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var out: Dictionary = entry.duplicate(true)
	var hit_frames_v: Variant = out.get("hit_frames", [])
	var hit_frames: Array = []
	if typeof(hit_frames_v) == TYPE_ARRAY:
		for frame_v in hit_frames_v as Array:
			hit_frames.append(int(frame_v))
	out["hit_frames"] = hit_frames
	for int_key in [
		"cooldown_ticks",
		"cost_mp",
		"player_pose",
		"charge_ticks",
		"hitbox_x",
		"hitbox_y",
		"hitbox_w",
		"hitbox_h",
		"damage",
		"knockback",
		"muzzle_x",
		"muzzle_y",
		"frame_width",
		"frame_height",
		"frame_index",
		"frame_count",
		"frame_tick",
		"charge_fx_frame_width",
		"charge_fx_frame_height",
		"charge_fx_frame_index",
		"charge_fx_frame_count",
		"charge_fx_frame_tick",
	]:
		if out.has(int_key):
			out[int_key] = int(out.get(int_key, 0))
	return out


func _get_player() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("mv_player")
