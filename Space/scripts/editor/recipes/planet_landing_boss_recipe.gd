extends RefCounted

const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const RegIO := preload("res://Space/scripts/editor/reg/reg_io.gd")
const EnvIO := preload("res://Space/scripts/editor/env/env_io.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")
const TriggerRecipes := preload("res://Space/scripts/editor/dlg/trigger_recipes.gd")
const PackPaths := preload("res://Space/scripts/editor/pack_paths.gd")

const REGION_ID := RegIO.DEFAULT_REGION_ID
const RECIPE_POI_ID := "recipe_landing"
const LANDING_ROOM := "landing"
const GATE_ROOM := "gate_room"
const BOSS_ROOM := "boss_room"
const ROOM_W := EnvIO.DEFAULT_ROOM_W_BLOCKS
const ROOM_H := EnvIO.DEFAULT_ROOM_H_BLOCKS
const FLOOR_BLOCK := RegIO.STARTER_SOLID_BLOCK


static func apply(pack_id: String, options: Dictionary = {}) -> Dictionary:
	var pid := pack_id.strip_edges()
	if pid.is_empty():
		return {"ok": false, "errors": ["Pack id is empty."]}
	var item_id := str(options.get("key_item_id", "key_silver")).strip_edges()
	var boss_id := str(options.get("boss_entity_id", "golden_boss")).strip_edges()
	var planet_name := str(options.get("planet_name", "Recipe Landing")).strip_edges()
	var system_id := str(options.get("system_id", SystemIO.STARTER_SYSTEM_ID)).strip_edges()
	if item_id.is_empty():
		item_id = "key_silver"
	if boss_id.is_empty():
		boss_id = "golden_boss"
	if planet_name.is_empty():
		planet_name = "Recipe Landing"
	if system_id.is_empty():
		system_id = SystemIO.STARTER_SYSTEM_ID

	if not _write_manifest(pid, system_id):
		return {"ok": false, "errors": ["Could not write Pack.json."]}
	if not _write_data(pid, item_id, boss_id):
		return {"ok": false, "errors": ["Could not write recipe items/entities."]}
	if not _write_world(pid, item_id):
		return {"ok": false, "errors": ["Could not write recipe rooms."]}
	if not _write_system(pid, system_id, planet_name):
		return {"ok": false, "errors": ["Could not write recipe system POI."]}
	if not _write_triggers(pid):
		return {"ok": false, "errors": ["Could not write recipe triggers."]}

	var issues := ContentValidator.validate(pid)
	var errors: Array = []
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			errors.append("%s - %s" % [issue_v.source, issue_v.message])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"issue_count": issues.size(),
		"pack_id": pid,
		"system_id": system_id,
		"planet_name": planet_name,
		"start_room": RegIO.runtime_room_addr(REGION_ID, LANDING_ROOM),
	}


static func _write_manifest(pack_id: String, system_id: String) -> bool:
	var path := PackPaths.writable_pack_file(pack_id, "Pack.json")
	var manifest := _read_json(path)
	manifest["schema_version"] = str(manifest.get("schema_version", "1.0"))
	manifest["pack_id"] = pack_id
	if str(manifest.get("name", "")).strip_edges().is_empty():
		manifest["name"] = pack_id.capitalize()
	if str(manifest.get("version", "")).strip_edges().is_empty():
		manifest["version"] = "0.1.0"
	manifest["start_system"] = system_id
	manifest["start_ship_template"] = str(manifest.get("start_ship_template", "startship"))
	manifest["start_region"] = REGION_ID
	manifest["entry_room"] = RegIO.runtime_room_addr(REGION_ID, LANDING_ROOM)
	return _write_json(path, manifest)


static func _write_data(pack_id: String, item_id: String, boss_id: String) -> bool:
	var abilities := PedIO.load_abilities(pack_id)
	var ability_entries: Array = _as_array(abilities.get("abilities", []))
	_upsert_by_id(ability_entries, {"id": "phase_dash", "name": "Phase Dash", "category": "movement", "description": "Recipe-created gate ability.", "params": {}})
	abilities["abilities"] = ability_entries
	if not PedIO.save_abilities(pack_id, abilities):
		return false
	var items := PedIO.load_items(pack_id)
	var item_entries: Array = _as_array(items.get("items", []))
	_upsert_by_id(item_entries, {"id": "coin", "name": "Coin", "description": "Currency.", "max_stack": 9999, "price": 1, "category": "currency", "use_effect": "", "use_amount": 0, "use_arg": ""})
	_upsert_by_id(item_entries, {"id": item_id, "name": item_id.capitalize(), "description": "Recipe-created gate key.", "max_stack": 1, "price": 25, "category": "key", "use_effect": "", "use_amount": 0, "use_arg": ""})
	_upsert_by_id(item_entries, {"id": "boss_core", "name": "Boss Core", "description": "Recipe-created boss reward.", "max_stack": 9, "price": 100, "category": "quest", "use_effect": "", "use_amount": 0, "use_arg": ""})
	items["items"] = item_entries
	if not PedIO.save_items(pack_id, items):
		return false
	var entities := EntIO.load_or_init(pack_id)
	var entity_entries: Array = _as_array(entities.get("entities", []))
	_upsert_by_id(entity_entries, _entity("pickup", "Pickup", "pickup", 1))
	_upsert_by_id(entity_entries, _entity("trigger_volume", "Trigger Volume", "logic", 1))
	_upsert_by_id(entity_entries, _entity(boss_id, boss_id.capitalize(), "boss", 120))
	entities["entities"] = entity_entries
	return EntIO.save_entities(pack_id, entities)


static func _as_array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if typeof(value) == TYPE_ARRAY else []


static func _upsert_by_id(entries: Array, entry: Dictionary) -> void:
	var id := str(entry.get("id", "")).strip_edges()
	if id.is_empty():
		return
	for i in range(entries.size()):
		if typeof(entries[i]) == TYPE_DICTIONARY and str((entries[i] as Dictionary).get("id", "")).strip_edges() == id:
			entries[i] = entry
			return
	entries.append(entry)


static func _entity(id: String, display_name: String, category: String, hp: int) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"category": category,
		"description": "",
		"scene": "",
		"sprite_set": "",
		"behavior": "",
		"movement_mode": "ground",
		"hp": hp,
		"attack_damage": 0,
		"contact_damage": 8 if category == "boss" else 0,
		"contact_cooldown": 0.8,
		"move_speed": 30 if category == "boss" else 0,
		"projectile_damage": 0,
		"projectile_speed": 0,
		"melee_range": 24,
		"melee_attack_trigger_frame": -1,
		"projectile_range": 0,
		"projectile_attack_trigger_frame": -1,
		"item_drops": [{"id": "boss_core", "chance": 1.0, "count": 1}] if category == "boss" else [],
	}


static func _write_world(pack_id: String, item_id: String) -> bool:
	var region := RegIO.default_region(REGION_ID, "Recipe Region")
	region["cell_blocks_x"] = ROOM_W
	region["cell_blocks_y"] = ROOM_H
	region["grid_cells_x"] = 6
	region["grid_cells_y"] = 2
	if not RegIO.save_region_meta(pack_id, REGION_ID, region):
		return false

	var rooms := {
		LANDING_ROOM: _room(LANDING_ROOM, "Recipe Landing", 0, [
			{"type": "player_spawn", "x": 80.0, "y": 208.0, "properties": {"instance_id": "player_spawn"}},
			{"type": "pickup", "x": 220.0, "y": 208.0, "properties": {"instance_id": "recipe_key_pickup", "item_id": item_id, "count": 1}},
		], [
			_door("landing_to_gate", GATE_ROOM, "gate_to_landing", "right", 28, 11, 2, 3),
		]),
		GATE_ROOM: _room(GATE_ROOM, "Recipe Gate", 1, [], [
			_door("gate_to_landing", LANDING_ROOM, "landing_to_gate", "left", 0, 11, 2, 3),
			_door("gate_to_boss", BOSS_ROOM, "boss_to_gate", "right", 28, 11, 2, 3, true, item_id),
		]),
		BOSS_ROOM: _room(BOSS_ROOM, "Recipe Boss", 2, [], [
			_door("boss_to_gate", GATE_ROOM, "gate_to_boss", "left", 0, 11, 2, 3),
			_trigger_zone("boss_intro", 12, 9, 5, 5),
			_exit_door("boss_exit", 28, 9, 2, 5),
		]),
	}
	return RegIO.save_region_rooms(pack_id, REGION_ID, {
		"version": "3.0",
		"region_id": REGION_ID,
		"start_room": LANDING_ROOM,
		"rooms": rooms,
	})


static func _room(addr: String, friendly_name: String, region_col: int, entities: Array, zones: Array) -> Dictionary:
	var room := RegIO.make_room_from_mask(addr, friendly_name, [[0, 0]], region_col, 0, ROOM_W, ROOM_H, 0)
	_paint_floor(room)
	room["entities"] = entities
	room["zones"] = zones
	room["doors"] = zones.duplicate(true)
	return room


static func _paint_floor(room: Dictionary) -> void:
	var collision_v: Variant = room.get("collision", [])
	if typeof(collision_v) != TYPE_ARRAY:
		return
	var collision: Array = collision_v
	for y in range(maxi(0, ROOM_H - 2), ROOM_H):
		if y >= collision.size() or typeof(collision[y]) != TYPE_ARRAY:
			continue
		var row: Array = collision[y]
		for x in range(row.size()):
			row[x] = FLOOR_BLOCK


static func _door(id: String, target_room: String, target_door_id: String, direction: String,
		x_blocks: float, y_blocks: float, width_blocks: float, height_blocks: float,
		locked: bool = false, required_item_id: String = "") -> Dictionary:
	var zone := EnvIO.default_zone()
	zone["id"] = id
	zone["name"] = id.capitalize()
	zone["kind"] = "door"
	zone["target_room"] = RegIO.runtime_room_addr(REGION_ID, target_room)
	zone["target_door_id"] = target_door_id
	zone["direction"] = direction
	zone["x_blocks"] = x_blocks
	zone["y_blocks"] = y_blocks
	zone["width_blocks"] = width_blocks
	zone["height_blocks"] = height_blocks
	zone["locked"] = locked
	zone["required_item_id"] = required_item_id
	zone["required_item_count"] = 1
	zone["blocked_event_name"] = "%s_blocked" % id if locked else ""
	return zone


static func _exit_door(id: String, x_blocks: float, y_blocks: float, width_blocks: float, height_blocks: float) -> Dictionary:
	var zone := EnvIO.default_zone()
	zone["id"] = id
	zone["name"] = "Return to Space"
	zone["kind"] = "door"
	zone["target_room"] = ""
	zone["target_door_id"] = ""
	zone["direction"] = "right"
	zone["x_blocks"] = x_blocks
	zone["y_blocks"] = y_blocks
	zone["width_blocks"] = width_blocks
	zone["height_blocks"] = height_blocks
	zone["locked"] = true
	zone["tags"] = ["exit_to_space"]
	return zone


static func _trigger_zone(id: String, x_blocks: float, y_blocks: float, width_blocks: float, height_blocks: float) -> Dictionary:
	var zone := EnvIO.default_zone()
	zone["id"] = id
	zone["name"] = "Boss Intro"
	zone["kind"] = "trigger"
	zone["x_blocks"] = x_blocks
	zone["y_blocks"] = y_blocks
	zone["width_blocks"] = width_blocks
	zone["height_blocks"] = height_blocks
	zone["event_name"] = "zone_enter"
	zone["once"] = true
	return zone


static func _write_system(pack_id: String, system_id: String, planet_name: String) -> bool:
	var systems := SystemIO.load_existing(pack_id)
	var system: Dictionary = systems.get(system_id, {})
	if system.is_empty():
		system = {
			"name": system_id.capitalize(),
			"position": [500, 500],
			"star_class": "G",
			"star_color": [1.0, 0.93, 0.68],
			"star_size": 64,
			"star_sprite": "",
			"star_anim_frames": 1,
			"star_anim_fps": 0.0,
			"star_gravity": 0,
			"background_image": "",
			"description": "Recipe-created system.",
			"threat_level": 1,
			"faction": "independent",
			"connections": [],
			"pois": [],
			"spawn_triggers": [],
			"placed_npcs": [],
		}
	var pois: Array = []
	var existing_pois_v: Variant = system.get("pois", [])
	if typeof(existing_pois_v) == TYPE_ARRAY:
		for poi_v in existing_pois_v:
			if typeof(poi_v) != TYPE_DICTIONARY:
				continue
			var poi: Dictionary = poi_v
			if str(poi.get("type", "")).strip_edges() == "planet":
				continue
			pois.append(poi.duplicate(true))
	pois.append({
		"id": RECIPE_POI_ID,
		"name": planet_name,
		"type": "planet",
		"description": "Recipe-created landing route.",
		"event_id": "",
		"orbit_dist": 900,
		"orbit_angle": 0,
		"sprite": "",
		"visual_scale": 1.0,
		"anim_frames": 1,
		"anim_fps": 0.0,
		"gravity_radius": 0,
		"planet_data": {
			"name": planet_name,
			"pack_id": pack_id,
			"poi_id": RECIPE_POI_ID,
			"regions": [{
				"id": REGION_ID,
				"name": "Recipe Region",
				"spawn_room": LANDING_ROOM,
				"spawn_pos": [80.0, 208.0],
			}],
			"planet_key": "recipe_landing",
			"sky_color": [0.35, 0.43, 0.62],
			"horizon_color": [0.72, 0.58, 0.32],
			"terrain_colors": [[0.18, 0.22, 0.26], [0.25, 0.22, 0.17], [0.09, 0.11, 0.14]],
			"roughness": 0.62,
			"turret_count": [0, 0],
			"patrol_count": [0, 0],
			"surface_pois": [],
		},
	})
	system["pois"] = pois
	systems[system_id] = system
	return SystemIO.save(pack_id, systems)


static func _write_triggers(pack_id: String) -> bool:
	var rules := [
		TriggerRecipes.build_recipe_rule(TriggerRecipes.PICKUP_UNLOCKS_GATE, pack_id),
		TriggerRecipes.build_recipe_rule(TriggerRecipes.BOSS_INTRO, pack_id),
		TriggerRecipes.build_recipe_rule(TriggerRecipes.BOSS_DEFEATED, pack_id),
	]
	return PedIO.save_triggers(pack_id, {"triggers": rules, "libraries": []})


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


static func _write_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true
