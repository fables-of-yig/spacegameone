class_name ContentReferenceIndex
extends RefCounted


static func build(pack_id: String) -> Dictionary:
	var pid := pack_id.strip_edges()
	var index := {
		"pack_id": pid,
		"definitions": [],
		"references": [],
		"_seen_def_keys": {},
	}
	if pid.is_empty():
		index.erase("_seen_def_keys")
		return index

	_scan_manifest(pid, index)
	_scan_catalog(pid, "Items/items.json", "items", "item", index)
	_scan_catalog(pid, "Items/equipment.json", "equipment", "equipment", index)
	_scan_catalog(pid, "Abilities/abilities.json", "abilities", "ability", index)
	_scan_catalog(pid, "Projectiles/projectiles.json", "projectiles", "projectile", index)
	_scan_catalog(pid, "Player/attacks.json", "attacks", "attack", index)
	_scan_catalog(pid, "Entities/entities.json", "entities", "entity", index)
	_scan_catalog(pid, "Entities/behaviors.json", "behaviors", "behavior", index)
	_scan_world(pid, index)
	_scan_systems(pid, index)
	_scan_global_triggers(pid, index)
	_scan_dialogues(pid, index)
	_scan_shops(pid, index)
	_scan_quests(pid, index)
	_scan_catalog_refs(pid, index)

	index.erase("_seen_def_keys")
	return index


static func find_references(pack_id: String, kind: String, id: String) -> Array:
	return find_references_in_index(build(pack_id), kind, id)


static func find_references_in_index(index: Dictionary, kind: String, id: String) -> Array:
	var out: Array = []
	var target_kind := kind.strip_edges()
	var target_id := id.strip_edges()
	if target_kind.is_empty() or target_id.is_empty():
		return out
	for ref_v in _as_array(index.get("references", [])):
		if typeof(ref_v) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_v
		if str(ref.get("kind", "")) == target_kind and str(ref.get("id", "")) == target_id:
			out.append(ref.duplicate(true))
	return out


static func summary_lines(index: Dictionary, kind: String = "", id: String = "") -> Array:
	var lines: Array = []
	var definitions := _as_array(index.get("definitions", []))
	var references := _as_array(index.get("references", []))
	var target_kind := kind.strip_edges()
	var target_id := id.strip_edges()
	if target_kind.is_empty() or target_id.is_empty():
		var def_counts := _count_by_kind(definitions)
		var ref_counts := _count_by_kind(references)
		lines.append("Pack '%s': %d definitions, %d references" % [
			str(index.get("pack_id", "")),
			definitions.size(),
			references.size(),
		])
		for key_v in def_counts.keys():
			var key := str(key_v)
			lines.append("  %s: %d definitions, %d references" % [
				key,
				int(def_counts.get(key, 0)),
				int(ref_counts.get(key, 0)),
			])
		return lines

	var refs := find_references_in_index(index, target_kind, target_id)
	lines.append("%s '%s': %d reference(s)" % [target_kind, target_id, refs.size()])
	for ref_v in refs:
		var ref: Dictionary = ref_v
		lines.append("  %s %s (%s)" % [
			str(ref.get("source", "")),
			str(ref.get("field", "")),
			str(ref.get("role", "")),
		])
	return lines


static func _scan_manifest(pack_id: String, index: Dictionary) -> void:
	var manifest := _load_pack_json_root(pack_id, "Pack.json")
	if manifest.is_empty():
		return
	var source := "Pack.json"
	_add_ref(index, "system", str(manifest.get("start_system", "")).strip_edges(), source, "start_system", "start system")
	_add_ref(index, "ship_template", str(manifest.get("start_ship_template", "")).strip_edges(), source, "start_ship_template", "start ship")
	_add_ref(index, "realm", str(manifest.get("start_realm", "")).strip_edges(), source, "start_realm", "start realm")
	_add_ref(index, "room", str(manifest.get("entry_room", "")).strip_edges(), source, "entry_room", "entry room")


static func _scan_catalog(pack_id: String, rel_path: String, key: String, kind: String, index: Dictionary) -> void:
	var root := _load_pack_json_root(pack_id, rel_path)
	var entries := _as_array(root.get(key, []))
	for i in range(entries.size()):
		var entry_v: Variant = entries[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var id := str(entry.get("id", "")).strip_edges()
		if id.is_empty():
			continue
		_add_def(index, kind, id, "%s:%d" % [rel_path, i], str(entry.get("name", "")))


static func _scan_catalog_refs(pack_id: String, index: Dictionary) -> void:
	_scan_item_refs(pack_id, index)
	_scan_equipment_refs(pack_id, index)
	_scan_ability_refs(pack_id, index)
	_scan_attack_refs(pack_id, index)
	_scan_entity_refs(pack_id, index)


static func _scan_item_refs(pack_id: String, index: Dictionary) -> void:
	var items := _as_array(_load_pack_json_root(pack_id, "Items/items.json").get("items", []))
	for item_v in items:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var source := "Item '%s'" % str(item.get("id", "")).strip_edges()
		var effect := str(item.get("use_effect", "")).strip_edges()
		var arg := str(item.get("use_arg", "")).strip_edges()
		match effect:
			"grant_ability":
				_add_ref(index, "ability", arg, source, "use_arg", "granted by item")
			"set_weapon":
				_add_ref(index, "attack", arg, source, "use_arg", "selected weapon")
			"fire_event":
				_add_ref(index, "event", arg, source, "use_arg", "fires event")


static func _scan_equipment_refs(pack_id: String, index: Dictionary) -> void:
	var equipment := _as_array(_load_pack_json_root(pack_id, "Items/equipment.json").get("equipment", []))
	for entry_v in equipment:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var source := "Equipment '%s'" % str(entry.get("id", "")).strip_edges()
		_add_ref(index, "ability", str(entry.get("granted_ability", "")).strip_edges(), source, "granted_ability", "equipment grant")
		for ability_v in _as_array(entry.get("grants_abilities", [])):
			_add_ref(index, "ability", str(ability_v).strip_edges(), source, "grants_abilities", "equipment grant")
		_add_ref(index, "attack", str(entry.get("weapon", "")).strip_edges(), source, "weapon", "equipment weapon")


static func _scan_ability_refs(pack_id: String, index: Dictionary) -> void:
	var abilities := _as_array(_load_pack_json_root(pack_id, "Abilities/abilities.json").get("abilities", []))
	for ability_v in abilities:
		if typeof(ability_v) != TYPE_DICTIONARY:
			continue
		var ability: Dictionary = ability_v
		var source := "Ability '%s'" % str(ability.get("id", "")).strip_edges()
		var params_v: Variant = ability.get("params", {})
		if typeof(params_v) == TYPE_DICTIONARY:
			_add_ref(index, "projectile", str((params_v as Dictionary).get("projectile_id", "")).strip_edges(), source, "params.projectile_id", "ability projectile")


static func _scan_attack_refs(pack_id: String, index: Dictionary) -> void:
	var attacks := _as_array(_load_pack_json_root(pack_id, "Player/attacks.json").get("attacks", []))
	for attack_v in attacks:
		if typeof(attack_v) != TYPE_DICTIONARY:
			continue
		var attack: Dictionary = attack_v
		var source := "Attack '%s'" % str(attack.get("id", "")).strip_edges()
		_add_ref(index, "projectile", str(attack.get("projectile_id", "")).strip_edges(), source, "projectile_id", "attack projectile")
		_add_ref(index, "attack", str(attack.get("charged_attack_id", "")).strip_edges(), source, "charged_attack_id", "charged attack")
		_add_ref(index, "attack", str(attack.get("combo_next_id", "")).strip_edges(), source, "combo_next_id", "combo follow-up")


static func _scan_entity_refs(pack_id: String, index: Dictionary) -> void:
	var entities := _as_array(_load_pack_json_root(pack_id, "Entities/entities.json").get("entities", []))
	for entity_v in entities:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		var source := "Entity '%s'" % str(entity.get("id", "")).strip_edges()
		_add_ref(index, "behavior", str(entity.get("behavior", "")).strip_edges(), source, "behavior", "entity behavior")
		for drop_v in _as_array(entity.get("item_drops", [])):
			if typeof(drop_v) != TYPE_DICTIONARY:
				continue
			var drop: Dictionary = drop_v
			_add_ref(index, "item", str(drop.get("id", drop.get("item_id", ""))).strip_edges(), source, "item_drops", "entity drop")


static func _scan_world(pack_id: String, index: Dictionary) -> void:
	for realm_id_v in _list_dir_names(pack_id, "Realms"):
		var realm_id := str(realm_id_v)
		var realm := _load_pack_json_root(pack_id, "Realms/%s/realm.json" % realm_id)
		_add_def(index, "realm", realm_id, "Realms/%s/realm.json" % realm_id, str(realm.get("name", realm.get("realm_name", ""))))
		for region_id_v in _list_dir_names(pack_id, "Realms/%s/Regions" % realm_id):
			var region_id := str(region_id_v)
			var region := _load_pack_json_root(pack_id, "Realms/%s/Regions/%s/region.json" % [realm_id, region_id])
			_add_def(index, "region", "%s/%s" % [realm_id, region_id],
				"Realms/%s/Regions/%s/region.json" % [realm_id, region_id],
				str(region.get("name", region.get("region_name", ""))))

	var rooms_root := _load_pack_json_root(pack_id, "Rooms/rooms.json")
	var rooms_v: Variant = rooms_root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		return
	var rooms: Dictionary = rooms_v
	for room_addr_v in rooms.keys():
		var room_addr := str(room_addr_v).strip_edges()
		var room_v: Variant = rooms[room_addr_v]
		if room_addr.is_empty() or typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		_add_def(index, "room", room_addr, "Rooms/rooms.json:%s" % room_addr, str(room.get("name", room.get("friendly_name", ""))))
		_scan_room(room_addr, room, index)


static func _scan_room(room_addr: String, room: Dictionary, index: Dictionary) -> void:
	var source := "Room '%s'" % room_addr
	var entities := _as_array(room.get("entities", []))
	for i in range(entities.size()):
		var entity_v: Variant = entities[i]
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		_add_ref(index, "entity", str(entity.get("type", "")).strip_edges(), source, "entities[%d].type" % i, "placed entity")
		var props_v: Variant = entity.get("properties", {})
		if typeof(props_v) == TYPE_DICTIONARY:
			var props: Dictionary = props_v
			_add_ref(index, "item", str(props.get("item_id", "")).strip_edges(), source, "entities[%d].properties.item_id" % i, "pickup item")
			_add_ref(index, "dialogue", str(props.get("dialogue_id", "")).strip_edges(), source, "entities[%d].properties.dialogue_id" % i, "entity dialogue")
			_add_ref(index, "shop", str(props.get("shop_id", "")).strip_edges(), source, "entities[%d].properties.shop_id" % i, "entity shop")

	_scan_room_links(_as_array(room.get("doors", [])), source, "doors", index)
	_scan_room_links(_as_array(room.get("zones", [])), source, "zones", index)
	_scan_trigger_rules(TriggerRoot.flatten_rules(room.get("triggers", [])), "%s triggers" % source, index)


static func _scan_room_links(entries: Array, source: String, field: String, index: Dictionary) -> void:
	for i in range(entries.size()):
		var entry_v: Variant = entries[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var prefix := "%s[%d]" % [field, i]
		_add_ref(index, "room", str(entry.get("target_room", entry.get("target", ""))).strip_edges(), source, "%s.target_room" % prefix, "room link")
		_add_ref(index, "item", str(entry.get("required_item_id", "")).strip_edges(), source, "%s.required_item_id" % prefix, "lock requirement")
		_add_ref(index, "event", str(entry.get("event_name", "")).strip_edges(), source, "%s.event_name" % prefix, "zone event")
		for dest_v in _as_array(entry.get("destinations", [])):
			if typeof(dest_v) != TYPE_DICTIONARY:
				continue
			_add_ref(index, "room", str((dest_v as Dictionary).get("target", "")).strip_edges(), source, "%s.destinations.target" % prefix, "room link")


static func _scan_systems(pack_id: String, index: Dictionary) -> void:
	var root := _load_pack_json_root(pack_id, "Systems/systems.json")
	var systems_v: Variant = root.get("systems", {})
	if typeof(systems_v) != TYPE_DICTIONARY:
		return
	var systems: Dictionary = systems_v
	for system_id_v in systems.keys():
		var system_id := str(system_id_v).strip_edges()
		var system_v: Variant = systems[system_id_v]
		if system_id.is_empty() or typeof(system_v) != TYPE_DICTIONARY:
			continue
		var system: Dictionary = system_v
		var source := "System '%s'" % system_id
		_add_def(index, "system", system_id, "Systems/systems.json:%s" % system_id, str(system.get("name", "")))
		for connection_v in _as_array(system.get("connections", [])):
			_add_ref(index, "system", str(connection_v).strip_edges(), source, "connections", "system connection")
		_scan_system_pois(source, _as_array(system.get("pois", [])), index)
		_scan_system_spawn_triggers(source, _as_array(system.get("spawn_triggers", [])), index)
		_scan_system_npcs(source, _as_array(system.get("placed_npcs", [])), index)


static func _scan_system_pois(source: String, pois: Array, index: Dictionary) -> void:
	for i in range(pois.size()):
		var poi_v: Variant = pois[i]
		if typeof(poi_v) != TYPE_DICTIONARY:
			continue
		var poi: Dictionary = poi_v
		var poi_source := "%s POI #%d" % [source, i]
		_add_ref(index, "event", str(poi.get("event_id", "")).strip_edges(), poi_source, "event_id", "poi event")
		var planet_v: Variant = poi.get("planet_data", {})
		if typeof(planet_v) != TYPE_DICTIONARY:
			continue
		var planet: Dictionary = planet_v
		var realm_id := str(planet.get("realm_id", "")).strip_edges()
		var region_id := str(planet.get("region_id", "")).strip_edges()
		_add_ref(index, "realm", realm_id, poi_source, "planet_data.realm_id", "planet landing")
		if not realm_id.is_empty() and not region_id.is_empty():
			_add_ref(index, "region", "%s/%s" % [realm_id, region_id], poi_source, "planet_data.region_id", "planet landing")
		_add_ref(index, "room", str(planet.get("spawn_room", "")).strip_edges(), poi_source, "planet_data.spawn_room", "planet spawn")


static func _scan_system_spawn_triggers(source: String, triggers: Array, index: Dictionary) -> void:
	for i in range(triggers.size()):
		var trigger_v: Variant = triggers[i]
		if typeof(trigger_v) != TYPE_DICTIONARY:
			continue
		for spawn_v in _as_array((trigger_v as Dictionary).get("spawns", [])):
			if typeof(spawn_v) == TYPE_DICTIONARY:
				_add_ref(index, "enemy_class", str((spawn_v as Dictionary).get("class", "")).strip_edges(),
					source, "spawn_triggers[%d].spawns.class" % i, "space spawn")


static func _scan_system_npcs(source: String, npcs: Array, index: Dictionary) -> void:
	for i in range(npcs.size()):
		var npc_v: Variant = npcs[i]
		if typeof(npc_v) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_v
		_add_ref(index, "ship_template", str(npc.get("template", "")).strip_edges(), source, "placed_npcs[%d].template" % i, "placed npc")
		_add_ref(index, "event", str(npc.get("hail_event_id", "")).strip_edges(), source, "placed_npcs[%d].hail_event_id" % i, "npc hail")


static func _scan_global_triggers(pack_id: String, index: Dictionary) -> void:
	var root := TriggerRoot.normalize_root(_load_pack_json_root(pack_id, "Triggers/global.json"))
	for rule_v in TriggerRoot.flatten_rules(root):
		if typeof(rule_v) == TYPE_DICTIONARY:
			_add_def(index, "trigger", str((rule_v as Dictionary).get("id", "")).strip_edges(),
				"Triggers/global.json", str((rule_v as Dictionary).get("name", "")))
	_scan_trigger_rules(TriggerRoot.flatten_rules(root), "Triggers/global.json", index)


static func _scan_dialogues(pack_id: String, index: Dictionary) -> void:
	for dialogue_id_v in _list_json_file_ids(pack_id, "Dialogue"):
		var dialogue_id := str(dialogue_id_v).strip_edges()
		if dialogue_id.is_empty():
			continue
		var dialogue := _load_pack_json_root(pack_id, "Dialogue/%s.json" % dialogue_id)
		_add_def(index, "dialogue", dialogue_id, "Dialogue/%s.json" % dialogue_id, str(dialogue.get("name", "")))
		var lines := _as_array(dialogue.get("lines", []))
		for i in range(lines.size()):
			var line_v: Variant = lines[i]
			if typeof(line_v) != TYPE_DICTIONARY:
				continue
			var line: Dictionary = line_v
			var source := "Dialogue '%s' line #%d" % [dialogue_id, i]
			_scan_conditions(line.get("condition", {}), source, "condition", index)
			_scan_actions(_as_array(line.get("actions", [])), source, "actions", index)
			var choices := _as_array(line.get("choices", []))
			for c in range(choices.size()):
				var choice_v: Variant = choices[c]
				if typeof(choice_v) != TYPE_DICTIONARY:
					continue
				var choice: Dictionary = choice_v
				var choice_source := "%s choice #%d" % [source, c]
				_scan_conditions(choice.get("condition", {}), choice_source, "condition", index)
				_scan_actions(_as_array(choice.get("actions", [])), choice_source, "actions", index)


static func _scan_shops(pack_id: String, index: Dictionary) -> void:
	for shop_id_v in _list_json_file_ids(pack_id, "Shops"):
		var shop_id := str(shop_id_v).strip_edges()
		if shop_id.is_empty():
			continue
		var shop := _load_pack_json_root(pack_id, "Shops/%s.json" % shop_id)
		_add_def(index, "shop", shop_id, "Shops/%s.json" % shop_id, str(shop.get("name", "")))
		var items := _as_array(shop.get("items", []))
		for i in range(items.size()):
			var item_v: Variant = items[i]
			if typeof(item_v) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = item_v
			var source := "Shop '%s' row #%d" % [shop_id, i]
			_add_ref(index, "item", str(item.get("id", "")).strip_edges(), source, "id", "shop stock")
			var effect := str(item.get("use_effect", "")).strip_edges()
			var arg := str(item.get("use_arg", "")).strip_edges()
			if effect == "grant_ability":
				_add_ref(index, "ability", arg, source, "use_arg", "shop stock effect")
			elif effect == "set_weapon":
				_add_ref(index, "attack", arg, source, "use_arg", "shop stock effect")


static func _scan_quests(pack_id: String, index: Dictionary) -> void:
	var quests := _as_array(_load_pack_json_root(pack_id, "Quests/quests.json").get("quests", []))
	for q in range(quests.size()):
		var quest_v: Variant = quests[q]
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		var quest_id := str(quest.get("id", "")).strip_edges()
		if quest_id.is_empty():
			continue
		_add_def(index, "quest", quest_id, "Quests/quests.json:%d" % q, str(quest.get("title", "")))
		var stages := _as_array(quest.get("stages", []))
		for s in range(stages.size()):
			var stage_v: Variant = stages[s]
			if typeof(stage_v) != TYPE_DICTIONARY:
				continue
			var stage: Dictionary = stage_v
			var stage_source := "Quest '%s' stage '%s'" % [quest_id, str(stage.get("id", s)).strip_edges()]
			_scan_quest_objectives(_as_array(stage.get("objectives", [])), stage_source, index)
			_scan_quest_rewards(stage.get("rewards", {}), stage_source, index)


static func _scan_quest_objectives(objectives: Array, source: String, index: Dictionary) -> void:
	for i in range(objectives.size()):
		var objective_v: Variant = objectives[i]
		if typeof(objective_v) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_v
		var field := "objectives[%d]" % i
		match str(objective.get("type", "")).strip_edges():
			"collect_item", "have_item":
				_add_ref(index, "item", _first_nonempty(objective, ["item_id", "target_item", "id"]), source, field, "quest objective")
			"kill_entity":
				_add_ref(index, "entity", _first_nonempty(objective, ["entity_id", "target_entity", "id"]), source, field, "quest objective")
			"visit_room":
				_add_ref(index, "room", _first_nonempty(objective, ["room", "room_id", "room_addr", "target_room"]), source, field, "quest objective")
			"talk_dialogue":
				_add_ref(index, "dialogue", _first_nonempty(objective, ["dialogue_id", "target_dialogue", "id"]), source, field, "quest objective")
			"open_shop":
				_add_ref(index, "shop", _first_nonempty(objective, ["shop_id", "target_shop", "id"]), source, field, "quest objective")
			"trigger_event":
				_add_ref(index, "event", _first_nonempty(objective, ["event", "event_id", "target_event", "id"]), source, field, "quest objective")


static func _scan_quest_rewards(rewards_v: Variant, source: String, index: Dictionary) -> void:
	if typeof(rewards_v) != TYPE_DICTIONARY:
		return
	var rewards: Dictionary = rewards_v
	for i in range(_as_array(rewards.get("items", [])).size()):
		var item_v: Variant = _as_array(rewards.get("items", []))[i]
		if typeof(item_v) == TYPE_DICTIONARY:
			_add_ref(index, "item", str((item_v as Dictionary).get("id", (item_v as Dictionary).get("item_id", ""))).strip_edges(),
				source, "rewards.items[%d]" % i, "quest reward")
		else:
			_add_ref(index, "item", str(item_v).strip_edges(), source, "rewards.items[%d]" % i, "quest reward")
	for i in range(_as_array(rewards.get("abilities", [])).size()):
		var ability_v: Variant = _as_array(rewards.get("abilities", []))[i]
		if typeof(ability_v) == TYPE_DICTIONARY:
			_add_ref(index, "ability", str((ability_v as Dictionary).get("id", (ability_v as Dictionary).get("ability_id", ""))).strip_edges(),
				source, "rewards.abilities[%d]" % i, "quest reward")
		else:
			_add_ref(index, "ability", str(ability_v).strip_edges(), source, "rewards.abilities[%d]" % i, "quest reward")
	for i in range(_as_array(rewards.get("events", [])).size()):
		_add_ref(index, "event", str(_as_array(rewards.get("events", []))[i]).strip_edges(),
			source, "rewards.events[%d]" % i, "quest reward")


static func _scan_trigger_rules(rules: Array, source: String, index: Dictionary) -> void:
	for rule_v in rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		var rule_source := "%s trigger '%s'" % [source, str(rule.get("id", "")).strip_edges()]
		_add_ref(index, "event", str(rule.get("event", "")).strip_edges(), rule_source, "event", "trigger event")
		_scan_conditions(_as_array(rule.get("conditions", [])), rule_source, "conditions", index)
		_scan_actions(_as_array(rule.get("actions", [])), rule_source, "actions", index)


static func _scan_conditions(value: Variant, source: String, field: String, index: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_scan_condition(value as Dictionary, source, field, index)
	elif typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		for i in range(arr.size()):
			if typeof(arr[i]) == TYPE_DICTIONARY:
				_scan_condition(arr[i] as Dictionary, source, "%s[%d]" % [field, i], index)


static func _scan_condition(condition: Dictionary, source: String, field: String, index: Dictionary) -> void:
	var ctype := str(condition.get("type", "")).strip_edges()
	match ctype:
		"has_item":
			_add_ref(index, "item", str(condition.get("id", "")).strip_edges(), source, field, "condition")
		"has_ability":
			_add_ref(index, "ability", str(condition.get("id", "")).strip_edges(), source, field, "condition")
		"payload_eq":
			var key := str(condition.get("key", "")).strip_edges()
			var value := str(condition.get("value", "")).strip_edges()
			match key:
				"item_id":
					_add_ref(index, "item", value, source, field, "payload match")
				"entity_id", "entity_type":
					_add_ref(index, "entity", value, source, field, "payload match")
				"dialogue_id":
					_add_ref(index, "dialogue", value, source, field, "payload match")
				"shop_id":
					_add_ref(index, "shop", value, source, field, "payload match")
				"room", "room_id", "room_addr":
					_add_ref(index, "room", value, source, field, "payload match")
				"quest_id":
					_add_ref(index, "quest", value, source, field, "payload match")
		"quest_status", "quest_stage", "quest_objective_done":
			_add_ref(index, "quest", str(condition.get("quest_id", "")).strip_edges(), source, field, "condition")
		"and", "or":
			_scan_conditions(_as_array(condition.get("children", [])), source, "%s.children" % field, index)
		"not":
			_scan_conditions(condition.get("child", {}), source, "%s.child" % field, index)


static func _scan_actions(actions: Array, source: String, field: String, index: Dictionary) -> void:
	for i in range(actions.size()):
		var action_v: Variant = actions[i]
		if typeof(action_v) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_v
		var action_field := "%s[%d]" % [field, i]
		match str(action.get("type", "")).strip_edges():
			"start_dialogue":
				_add_ref(index, "dialogue", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"start_shop":
				_add_ref(index, "shop", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"quest_start", "quest_set_stage", "quest_complete_objective", "quest_complete_stage", "quest_complete":
				_add_ref(index, "quest", str(action.get("quest_id", "")).strip_edges(), source, action_field, "action")
			"give_ability", "revoke_ability":
				_add_ref(index, "ability", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"give_item", "take_item":
				_add_ref(index, "item", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"spawn_entity", "despawn_entity", "spawn_entity_at_zone":
				_add_ref(index, "entity", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"teleport_player", "set_room_weather":
				_add_ref(index, "room", str(action.get("room", "")).strip_edges(), source, action_field, "action")
			"set_trigger_enabled":
				_add_ref(index, "trigger", str(action.get("id", "")).strip_edges(), source, action_field, "action")
			"fire_event", "wait_for_event":
				_add_ref(index, "event", str(action.get("event", "")).strip_edges(), source, action_field, "action")
			"set_door_locked":
				_add_ref(index, "door", str(action.get("id", "")).strip_edges(), source, action_field, "action")


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


static func _pack_file_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges()
	if clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)
	return [
		"user://Packs/%s/%s" % [pack_id, clean_path],
		"res://Content/%s/%s" % [pack_id, clean_path],
	]


static func _pack_dir_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges().rstrip("/")
	if clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)
	return [
		"user://Packs/%s/%s" % [pack_id, clean_path],
		"res://Content/%s/%s" % [pack_id, clean_path],
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


static func _add_def(index: Dictionary, kind: String, id: String, source: String, name: String = "") -> void:
	var clean_kind := kind.strip_edges()
	var clean_id := id.strip_edges()
	if clean_kind.is_empty() or clean_id.is_empty():
		return
	var seen_v: Variant = index.get("_seen_def_keys", {})
	if typeof(seen_v) != TYPE_DICTIONARY:
		seen_v = {}
	var seen: Dictionary = seen_v
	var key := "%s:%s" % [clean_kind, clean_id]
	if seen.has(key):
		return
	seen[key] = true
	index["_seen_def_keys"] = seen
	var defs := _as_array(index.get("definitions", []))
	defs.append({
		"kind": clean_kind,
		"id": clean_id,
		"name": name.strip_edges(),
		"source": source,
	})
	index["definitions"] = defs


static func _add_ref(index: Dictionary, kind: String, id: String, source: String, field: String, role: String) -> void:
	var clean_kind := kind.strip_edges()
	var clean_id := id.strip_edges()
	if clean_kind.is_empty() or clean_id.is_empty():
		return
	var refs := _as_array(index.get("references", []))
	refs.append({
		"kind": clean_kind,
		"id": clean_id,
		"source": source,
		"field": field,
		"role": role,
	})
	index["references"] = refs


static func _count_by_kind(entries: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var kind := str((entry_v as Dictionary).get("kind", "")).strip_edges()
		if kind.is_empty():
			continue
		counts[kind] = int(counts.get(kind, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	var sorted: Dictionary = {}
	for key_v in keys:
		sorted[key_v] = counts[key_v]
	return sorted


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _first_nonempty(data: Dictionary, keys: Array) -> String:
	for key_v in keys:
		var value := str(data.get(str(key_v), "")).strip_edges()
		if not value.is_empty():
			return value
	return ""
