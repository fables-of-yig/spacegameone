class_name ContentReferenceRefactor
extends RefCounted

const PackPaths := preload("res://Space/scripts/shared/pack_paths.gd")


static func rename_references(pack_id: String, kind: String, old_id: String, new_id: String) -> Dictionary:
	var pid := pack_id.strip_edges()
	var target_kind := kind.strip_edges()
	var from_id := old_id.strip_edges()
	var to_id := new_id.strip_edges()
	var result := {
		"ok": true,
		"changed_files": [],
		"changed_refs": 0,
		"errors": [],
	}
	if pid.is_empty() or target_kind.is_empty() or from_id.is_empty() or to_id.is_empty():
		result["ok"] = false
		result["errors"] = ["Pack id, kind, old id, and new id are required."]
		return result
	if from_id == to_id:
		return result

	_rewrite_file(pid, "Pack.json", result, func(root: Dictionary) -> int:
		return _rewrite_manifest(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Systems/systems.json", result, func(root: Dictionary) -> int:
		return _rewrite_systems(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Factions/factions.json", result, func(root: Dictionary) -> int:
		return _rewrite_factions(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Rooms/rooms.json", result, func(root: Dictionary) -> int:
		return _rewrite_rooms_root(root, target_kind, from_id, to_id)
	)
	for region_id_v in _list_dir_names(pid, "Regions"):
		var rel_path := "Regions/%s/rooms.json" % str(region_id_v)
		_rewrite_file(pid, rel_path, result, func(root: Dictionary) -> int:
			return _rewrite_region_rooms_root(root, target_kind, from_id, to_id)
		)
	_rewrite_file(pid, "Triggers/global.json", result, func(root: Dictionary) -> int:
		return _rewrite_trigger_root(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Items/items.json", result, func(root: Dictionary) -> int:
		return _rewrite_items(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Items/equipment.json", result, func(root: Dictionary) -> int:
		return _rewrite_equipment(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Abilities/abilities.json", result, func(root: Dictionary) -> int:
		return _rewrite_abilities(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Player/attacks.json", result, func(root: Dictionary) -> int:
		return _rewrite_attacks(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Entities/entities.json", result, func(root: Dictionary) -> int:
		return _rewrite_entities(root, target_kind, from_id, to_id)
	)
	_rewrite_file(pid, "Quests/quests.json", result, func(root: Dictionary) -> int:
		return _rewrite_quests(root, target_kind, from_id, to_id)
	)

	for dialogue_id_v in _list_json_file_ids(pid, "Dialogue"):
		var dialogue_id := str(dialogue_id_v).strip_edges()
		if dialogue_id.is_empty():
			continue
		_rewrite_file(pid, "Dialogue/%s.json" % dialogue_id, result, func(root: Dictionary) -> int:
			return _rewrite_dialogue(root, target_kind, from_id, to_id)
		)
	for shop_id_v in _list_json_file_ids(pid, "Shops"):
		var shop_id := str(shop_id_v).strip_edges()
		if shop_id.is_empty():
			continue
		_rewrite_file(pid, "Shops/%s.json" % shop_id, result, func(root: Dictionary) -> int:
			return _rewrite_shop(root, target_kind, from_id, to_id)
		)

	return result


static func rename_room_references(pack_id: String, old_region_id: String, old_room_id: String,
		new_region_id: String, new_room_id: String) -> Dictionary:
	var pid := pack_id.strip_edges()
	var old_region := old_region_id.strip_edges()
	var old_room := old_room_id.strip_edges()
	var new_region := new_region_id.strip_edges()
	var new_room := new_room_id.strip_edges()
	var result := {
		"ok": true,
		"changed_files": [],
		"changed_refs": 0,
		"errors": [],
	}
	if pid.is_empty() or old_region.is_empty() or old_room.is_empty() \
			or new_region.is_empty() or new_room.is_empty():
		result["ok"] = false
		result["errors"] = ["Pack, old room address, and new room address are required."]
		return result
	if old_region == new_region and old_room == new_room:
		return result

	var old_region_room := "%s/%s" % [old_region, old_room]
	var new_region_room := "%s/%s" % [new_region, new_room]

	_rename_exact_room_references(pid, old_region_room, new_region_room, result)

	var scoped_rel_path := "Regions/%s/rooms.json" % new_region
	_rewrite_file(pid, scoped_rel_path, result, func(root: Dictionary) -> int:
		return _rewrite_region_rooms_root(root, "room", old_room, new_room)
	)
	return result


static func _rename_exact_room_references(pack_id: String, old_ref: String, new_ref: String, result: Dictionary) -> void:
	_rewrite_file(pack_id, "Pack.json", result, func(root: Dictionary) -> int:
		return _rewrite_manifest(root, "room", old_ref, new_ref)
	)
	_rewrite_file(pack_id, "Systems/systems.json", result, func(root: Dictionary) -> int:
		return _rewrite_systems(root, "room", old_ref, new_ref)
	)
	_rewrite_file(pack_id, "Rooms/rooms.json", result, func(root: Dictionary) -> int:
		return _rewrite_rooms_root(root, "room", old_ref, new_ref)
	)
	for region_id_v in _list_dir_names(pack_id, "Regions"):
		var rel_path := "Regions/%s/rooms.json" % str(region_id_v)
		_rewrite_file(pack_id, rel_path, result, func(root: Dictionary) -> int:
			return _rewrite_region_rooms_root(root, "room", old_ref, new_ref)
		)
	_rewrite_file(pack_id, "Triggers/global.json", result, func(root: Dictionary) -> int:
		return _rewrite_trigger_root(root, "room", old_ref, new_ref)
	)
	for dialogue_id_v in _list_json_file_ids(pack_id, "Dialogue"):
		var dialogue_id := str(dialogue_id_v).strip_edges()
		if dialogue_id.is_empty():
			continue
		_rewrite_file(pack_id, "Dialogue/%s.json" % dialogue_id, result, func(root: Dictionary) -> int:
			return _rewrite_dialogue(root, "room", old_ref, new_ref)
		)
	_rewrite_file(pack_id, "Quests/quests.json", result, func(root: Dictionary) -> int:
		return _rewrite_quests(root, "room", old_ref, new_ref)
	)


static func _rewrite_manifest(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	if kind == "system":
		count += _replace_string(root, "start_system", old_id, new_id)
	elif kind == "ship_template":
		count += _replace_string(root, "start_ship_template", old_id, new_id)
	elif kind == "region":
		count += _replace_string(root, "start_region", old_id, new_id)
	elif kind == "room":
		count += _replace_string(root, "entry_room", old_id, new_id)
	return count


static func _rewrite_systems(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var systems_v: Variant = root.get("systems", {})
	if typeof(systems_v) != TYPE_DICTIONARY:
		return 0
	var count := 0
	var systems: Dictionary = systems_v
	for system_v in systems.values():
		if typeof(system_v) != TYPE_DICTIONARY:
			continue
		var system: Dictionary = system_v
		if kind == "system":
			count += _replace_array_strings(_as_array(system.get("connections", [])), old_id, new_id)
		if kind == "faction":
			count += _replace_string(system, "faction", old_id, new_id)
		count += _rewrite_system_pois(_as_array(system.get("pois", [])), kind, old_id, new_id)
		count += _rewrite_system_npcs(_as_array(system.get("placed_npcs", [])), kind, old_id, new_id)
	return count


static func _rewrite_system_pois(pois: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for poi_v in pois:
		if typeof(poi_v) != TYPE_DICTIONARY:
			continue
		var poi: Dictionary = poi_v
		if kind == "event":
			count += _replace_string(poi, "event_id", old_id, new_id)
		var planet_v: Variant = poi.get("planet_data", {})
		if typeof(planet_v) != TYPE_DICTIONARY:
			continue
		var planet: Dictionary = planet_v
		if kind == "pack":
			count += _replace_string(planet, "pack_id", old_id, new_id)
		elif kind == "region" or kind == "room":
			# Walk the regions[] entries and rename matching id / spawn_room
			# fields. Phase 5 dropped the planet-level realm_id / spawn_room
			# slots in favour of a per-region list.
			var regions_v: Variant = planet.get("regions", [])
			if typeof(regions_v) != TYPE_ARRAY:
				continue
			for entry_v in regions_v as Array:
				if typeof(entry_v) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = entry_v
				if kind == "region":
					count += _replace_string(entry, "id", old_id, new_id)
				elif kind == "room":
					count += _replace_string(entry, "spawn_room", old_id, new_id)
	return count


static func _rewrite_system_npcs(npcs: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for npc_v in npcs:
		if typeof(npc_v) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_v
		if kind == "ship_template":
			count += _replace_string(npc, "template", old_id, new_id)
		elif kind == "event":
			count += _replace_string(npc, "hail_event_id", old_id, new_id)
		elif kind == "faction":
			count += _replace_string(npc, "faction", old_id, new_id)
	return count


static func _rewrite_rooms_root(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var rooms_v: Variant = root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		return 0
	var count := 0
	for room_v in (rooms_v as Dictionary).values():
		if typeof(room_v) == TYPE_DICTIONARY:
			count += _rewrite_room(room_v as Dictionary, kind, old_id, new_id)
	return count


static func _rewrite_region_rooms_root(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	return _rewrite_rooms_root(root, kind, old_id, new_id)


static func _rewrite_room(room: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for entity_v in _as_array(room.get("entities", [])):
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if kind == "entity":
			count += _replace_string(entity, "type", old_id, new_id)
		var props_v: Variant = entity.get("properties", {})
		if typeof(props_v) != TYPE_DICTIONARY:
			continue
		var props: Dictionary = props_v
		if kind == "item":
			count += _replace_string(props, "item_id", old_id, new_id)
		elif kind == "dialogue":
			count += _replace_string(props, "dialogue_id", old_id, new_id)
		elif kind == "shop":
			count += _replace_string(props, "shop_id", old_id, new_id)
	count += _rewrite_room_links(_as_array(room.get("doors", [])), kind, old_id, new_id)
	count += _rewrite_room_links(_as_array(room.get("zones", [])), kind, old_id, new_id)
	count += _rewrite_trigger_root_value(room.get("triggers", []), kind, old_id, new_id)
	return count


static func _rewrite_room_links(entries: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if kind == "room":
			count += _replace_string(entry, "target_room", old_id, new_id)
			count += _replace_string(entry, "target", old_id, new_id)
			for dest_v in _as_array(entry.get("destinations", [])):
				if typeof(dest_v) == TYPE_DICTIONARY:
					count += _replace_string(dest_v as Dictionary, "target", old_id, new_id)
		elif kind == "item":
			count += _replace_string(entry, "required_item_id", old_id, new_id)
		elif kind == "event":
			count += _replace_string(entry, "event_name", old_id, new_id)
	return count


static func _rewrite_trigger_root(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	return _rewrite_trigger_root_value(root, kind, old_id, new_id)


static func _rewrite_trigger_root_value(value: Variant, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	if typeof(value) == TYPE_ARRAY:
		count += _rewrite_rules(value as Array, kind, old_id, new_id)
	elif typeof(value) == TYPE_DICTIONARY:
		var root: Dictionary = value
		count += _rewrite_rules(_as_array(root.get("triggers", [])), kind, old_id, new_id)
		for lib_v in _as_array(root.get("libraries", [])):
			if typeof(lib_v) != TYPE_DICTIONARY:
				continue
			var lib: Dictionary = lib_v
			count += _rewrite_rules(_as_array(lib.get("triggers", [])), kind, old_id, new_id)
			count += _rewrite_trigger_folders(_as_array(lib.get("folders", [])), kind, old_id, new_id)
	return count


static func _rewrite_trigger_folders(folders: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for folder_v in folders:
		if typeof(folder_v) != TYPE_DICTIONARY:
			continue
		var folder: Dictionary = folder_v
		count += _rewrite_rules(_as_array(folder.get("triggers", [])), kind, old_id, new_id)
		count += _rewrite_trigger_folders(_as_array(folder.get("folders", [])), kind, old_id, new_id)
	return count


static func _rewrite_rules(rules: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for rule_v in rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		if kind == "event":
			count += _replace_string(rule, "event", old_id, new_id)
		count += _rewrite_conditions(_as_array(rule.get("conditions", [])), kind, old_id, new_id)
		count += _rewrite_actions(_as_array(rule.get("actions", [])), kind, old_id, new_id)
	return count


static func _rewrite_conditions(value: Variant, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	if typeof(value) == TYPE_DICTIONARY:
		count += _rewrite_condition(value as Dictionary, kind, old_id, new_id)
	elif typeof(value) == TYPE_ARRAY:
		for cond_v in value as Array:
			if typeof(cond_v) == TYPE_DICTIONARY:
				count += _rewrite_condition(cond_v as Dictionary, kind, old_id, new_id)
	return count


static func _rewrite_condition(condition: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	var ctype := str(condition.get("type", "")).strip_edges()
	if kind == "item" and ctype == "has_item":
		count += _replace_string(condition, "id", old_id, new_id)
	elif kind == "ability" and ctype == "has_ability":
		count += _replace_string(condition, "id", old_id, new_id)
	elif ctype == "payload_eq":
		var key := str(condition.get("key", "")).strip_edges()
		if _payload_key_matches_kind(key, kind):
			count += _replace_string(condition, "value", old_id, new_id)
	elif kind == "quest" and (ctype == "quest_status" or ctype == "quest_stage" or ctype == "quest_objective_done"):
		count += _replace_string(condition, "quest_id", old_id, new_id)
	elif ctype == "and" or ctype == "or":
		count += _rewrite_conditions(_as_array(condition.get("children", [])), kind, old_id, new_id)
	elif ctype == "not":
		count += _rewrite_conditions(condition.get("child", {}), kind, old_id, new_id)
	return count


static func _rewrite_actions(actions: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for action_v in actions:
		if typeof(action_v) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_v
		var atype := str(action.get("type", "")).strip_edges()
		if kind == "dialogue" and atype == "start_dialogue":
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "shop" and atype == "start_shop":
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "quest" and (atype == "quest_start" or atype == "quest_set_stage" or atype == "quest_complete_objective" or atype == "quest_complete_stage" or atype == "quest_complete"):
			count += _replace_string(action, "quest_id", old_id, new_id)
		elif kind == "ability" and (atype == "give_ability" or atype == "revoke_ability"):
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "item" and (atype == "give_item" or atype == "take_item"):
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "entity" and (atype == "spawn_entity" or atype == "despawn_entity" or atype == "spawn_entity_at_zone"):
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "room" and (atype == "teleport_player" or atype == "set_room_weather"):
			count += _replace_string(action, "room", old_id, new_id)
		elif kind == "trigger" and atype == "set_trigger_enabled":
			count += _replace_string(action, "id", old_id, new_id)
		elif kind == "event" and (atype == "fire_event" or atype == "wait_for_event"):
			count += _replace_string(action, "event", old_id, new_id)
		elif kind == "door" and atype == "set_door_locked":
			count += _replace_string(action, "id", old_id, new_id)
	return count


static func _rewrite_items(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "ability" and kind != "attack" and kind != "event":
		return 0
	var count := 0
	for item_v in _as_array(root.get("items", [])):
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var effect := str(item.get("use_effect", "")).strip_edges()
		if kind == "ability" and effect == "grant_ability":
			count += _replace_string(item, "use_arg", old_id, new_id)
		elif kind == "attack" and effect == "set_weapon":
			count += _replace_string(item, "use_arg", old_id, new_id)
		elif kind == "event" and effect == "fire_event":
			count += _replace_string(item, "use_arg", old_id, new_id)
	return count


static func _rewrite_equipment(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "ability" and kind != "attack":
		return 0
	var count := 0
	for entry_v in _as_array(root.get("equipment", [])):
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if kind == "ability":
			count += _replace_string(entry, "granted_ability", old_id, new_id)
			count += _replace_array_strings(_as_array(entry.get("grants_abilities", [])), old_id, new_id)
		elif kind == "attack":
			count += _replace_string(entry, "weapon", old_id, new_id)
	return count


static func _rewrite_abilities(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "projectile":
		return 0
	var count := 0
	for ability_v in _as_array(root.get("abilities", [])):
		if typeof(ability_v) != TYPE_DICTIONARY:
			continue
		var params_v: Variant = (ability_v as Dictionary).get("params", {})
		if typeof(params_v) == TYPE_DICTIONARY:
			count += _replace_string(params_v as Dictionary, "projectile_id", old_id, new_id)
	return count


static func _rewrite_attacks(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "projectile" and kind != "attack":
		return 0
	var count := 0
	for attack_v in _as_array(root.get("attacks", [])):
		if typeof(attack_v) != TYPE_DICTIONARY:
			continue
		var attack: Dictionary = attack_v
		if kind == "projectile":
			count += _replace_string(attack, "projectile_id", old_id, new_id)
		elif kind == "attack":
			count += _replace_string(attack, "charged_attack_id", old_id, new_id)
			count += _replace_string(attack, "combo_next_id", old_id, new_id)
	return count


static func _rewrite_entities(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "behavior" and kind != "item":
		return 0
	var count := 0
	for entity_v in _as_array(root.get("entities", [])):
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if kind == "behavior":
			count += _replace_string(entity, "behavior", old_id, new_id)
		elif kind == "item":
			for drop_v in _as_array(entity.get("item_drops", [])):
				if typeof(drop_v) != TYPE_DICTIONARY:
					continue
				var drop: Dictionary = drop_v
				count += _replace_string(drop, "id", old_id, new_id)
				count += _replace_string(drop, "item_id", old_id, new_id)
	return count


# Renames the top-level faction key AND rewrites every other faction's
# relations dict to follow the rename. Only kicks in for kind == "faction";
# returns 0 otherwise so this file rewrite is a noop for unrelated renames.
static func _rewrite_factions(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "faction":
		return 0
	var factions_v: Variant = root.get("factions", {})
	if typeof(factions_v) != TYPE_DICTIONARY:
		return 0
	var factions: Dictionary = factions_v
	var count := 0
	if factions.has(old_id) and not factions.has(new_id):
		factions[new_id] = factions[old_id]
		factions.erase(old_id)
		count += 1
	for fid_v in factions.keys():
		var entry_v: Variant = factions[fid_v]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var rels_v: Variant = (entry_v as Dictionary).get("relations", {})
		if typeof(rels_v) != TYPE_DICTIONARY:
			continue
		var rels: Dictionary = rels_v
		if rels.has(old_id) and not rels.has(new_id):
			rels[new_id] = rels[old_id]
			rels.erase(old_id)
			(entry_v as Dictionary)["relations"] = rels
			count += 1
	root["factions"] = factions
	return count


static func _rewrite_dialogue(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for line_v in _as_array(root.get("lines", [])):
		if typeof(line_v) != TYPE_DICTIONARY:
			continue
		var line: Dictionary = line_v
		count += _rewrite_conditions(line.get("condition", {}), kind, old_id, new_id)
		count += _rewrite_actions(_as_array(line.get("actions", [])), kind, old_id, new_id)
		if kind == "faction":
			count += _replace_string(line, "speaker_faction", old_id, new_id)
		for choice_v in _as_array(line.get("choices", [])):
			if typeof(choice_v) != TYPE_DICTIONARY:
				continue
			var choice: Dictionary = choice_v
			count += _rewrite_conditions(choice.get("condition", {}), kind, old_id, new_id)
			count += _rewrite_actions(_as_array(choice.get("actions", [])), kind, old_id, new_id)
	return count


static func _rewrite_shop(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	if kind != "item" and kind != "ability" and kind != "attack":
		return 0
	var count := 0
	for item_v in _as_array(root.get("items", [])):
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		if kind == "item":
			count += _replace_string(item, "id", old_id, new_id)
		else:
			var effect := str(item.get("use_effect", "")).strip_edges()
			if kind == "ability" and effect == "grant_ability":
				count += _replace_string(item, "use_arg", old_id, new_id)
			elif kind == "attack" and effect == "set_weapon":
				count += _replace_string(item, "use_arg", old_id, new_id)
	return count


static func _rewrite_quests(root: Dictionary, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for quest_v in _as_array(root.get("quests", [])):
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		for stage_v in _as_array(quest.get("stages", [])):
			if typeof(stage_v) != TYPE_DICTIONARY:
				continue
			var stage: Dictionary = stage_v
			count += _rewrite_quest_objectives(_as_array(stage.get("objectives", [])), kind, old_id, new_id)
			count += _rewrite_quest_rewards(stage.get("rewards", {}), kind, old_id, new_id)
	return count


static func _rewrite_quest_objectives(objectives: Array, kind: String, old_id: String, new_id: String) -> int:
	var count := 0
	for objective_v in objectives:
		if typeof(objective_v) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_v
		var objective_type := str(objective.get("type", "")).strip_edges()
		if kind == "item" and (objective_type == "collect_item" or objective_type == "have_item"):
			count += _replace_first_present_string(objective, ["item_id", "target_item", "id"], old_id, new_id)
		elif kind == "entity" and objective_type == "kill_entity":
			count += _replace_first_present_string(objective, ["entity_id", "target_entity", "id"], old_id, new_id)
		elif kind == "room" and objective_type == "visit_room":
			count += _replace_first_present_string(objective, ["room", "room_id", "room_addr", "target_room"], old_id, new_id)
		elif kind == "dialogue" and objective_type == "talk_dialogue":
			count += _replace_first_present_string(objective, ["dialogue_id", "target_dialogue", "id"], old_id, new_id)
		elif kind == "shop" and objective_type == "open_shop":
			count += _replace_first_present_string(objective, ["shop_id", "target_shop", "id"], old_id, new_id)
		elif kind == "event" and objective_type == "trigger_event":
			count += _replace_first_present_string(objective, ["event", "event_id", "target_event", "id"], old_id, new_id)
	return count


static func _rewrite_quest_rewards(rewards_v: Variant, kind: String, old_id: String, new_id: String) -> int:
	if typeof(rewards_v) != TYPE_DICTIONARY:
		return 0
	var rewards: Dictionary = rewards_v
	var count := 0
	if kind == "item":
		count += _replace_array_string_or_dict_ids(_as_array(rewards.get("items", [])), ["id", "item_id"], old_id, new_id)
	elif kind == "ability":
		count += _replace_array_string_or_dict_ids(_as_array(rewards.get("abilities", [])), ["id", "ability_id"], old_id, new_id)
	elif kind == "event":
		count += _replace_array_strings(_as_array(rewards.get("events", [])), old_id, new_id)
	return count


static func _payload_key_matches_kind(key: String, kind: String) -> bool:
	match kind:
		"item":
			return key == "item_id"
		"entity":
			return key == "entity_id" or key == "entity_type"
		"dialogue":
			return key == "dialogue_id"
		"shop":
			return key == "shop_id"
		"room":
			return key == "room" or key == "room_id" or key == "room_addr"
		"quest":
			return key == "quest_id"
	return false


static func _rewrite_file(pack_id: String, rel_path: String, result: Dictionary, rewriter: Callable) -> void:
	var root := _load_pack_json_root(pack_id, rel_path)
	if root.is_empty():
		return
	var before := root.duplicate(true)
	var changed_refs := int(rewriter.call(root))
	if changed_refs <= 0 or root == before:
		return
	if _write_user_pack_json(pack_id, rel_path, root):
		var changed_files := _as_array(result.get("changed_files", []))
		changed_files.append(rel_path)
		result["changed_files"] = changed_files
		result["changed_refs"] = int(result.get("changed_refs", 0)) + changed_refs
	else:
		result["ok"] = false
		var errors := _as_array(result.get("errors", []))
		errors.append("Could not write %s." % rel_path)
		result["errors"] = errors


static func _load_pack_json_root(pack_id: String, rel_path: String) -> Dictionary:
	for path in _pack_file_paths(pack_id, rel_path):
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


static func _write_user_pack_json(pack_id: String, rel_path: String, data: Dictionary) -> bool:
	var path := PackPaths.writable_pack_file(pack_id, rel_path.strip_edges().trim_prefix("/"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func _pack_file_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges().trim_prefix("/")
	return [
		PackPaths.writable_pack_file(pack_id, clean_path),
		PackPaths.shipped_pack_file(pack_id, clean_path),
	]


static func _pack_dir_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges().trim_prefix("/").rstrip("/")
	return [
		PackPaths.writable_pack_file(pack_id, clean_path),
		PackPaths.shipped_pack_file(pack_id, clean_path),
	]


static func _list_dir_names(pack_id: String, rel_path: String) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	for root in _pack_dir_paths(pack_id, rel_path):
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if dir.current_is_dir() and not name.begins_with(".") and not seen.has(name):
				seen[name] = true
				ids.append(name)
			name = dir.get_next()
		dir.list_dir_end()
	ids.sort()
	return ids


static func _list_json_file_ids(pack_id: String, rel_path: String) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	for root in _pack_dir_paths(pack_id, rel_path):
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if not dir.current_is_dir() and name.ends_with(".json") and not name.begins_with("_"):
				var id := name.get_basename()
				if not seen.has(id):
					seen[id] = true
					ids.append(id)
			name = dir.get_next()
		dir.list_dir_end()
	ids.sort()
	return ids


static func _replace_string(dict: Dictionary, key: String, old_id: String, new_id: String) -> int:
	if not dict.has(key):
		return 0
	if str(dict.get(key, "")).strip_edges() != old_id:
		return 0
	dict[key] = new_id
	return 1


static func _replace_array_strings(arr: Array, old_id: String, new_id: String) -> int:
	var count := 0
	for i in range(arr.size()):
		if str(arr[i]).strip_edges() == old_id:
			arr[i] = new_id
			count += 1
	return count


static func _replace_first_present_string(dict: Dictionary, keys: Array, old_id: String, new_id: String) -> int:
	for key_v in keys:
		var key := str(key_v)
		if dict.has(key):
			return _replace_string(dict, key, old_id, new_id)
	return 0


static func _replace_array_string_or_dict_ids(arr: Array, keys: Array, old_id: String, new_id: String) -> int:
	var count := 0
	for i in range(arr.size()):
		if typeof(arr[i]) == TYPE_DICTIONARY:
			count += _replace_first_present_string(arr[i] as Dictionary, keys, old_id, new_id)
		elif str(arr[i]).strip_edges() == old_id:
			arr[i] = new_id
			count += 1
	return count


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
