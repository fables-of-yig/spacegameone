class_name ContentValidator
extends RefCounted

const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const PspIO := preload("res://Space/scripts/editor/psp/psp_io.gd")
const RegIO := preload("res://Space/scripts/editor/reg/reg_io.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")
const UIIo := preload("res://Space/scripts/editor/ui/ui_io.gd")

# Cross-references all JSON data in a content pack and reports dangling
# references, missing required fields, and type mismatches.

class Issue:
	var severity: String  # "error" or "warning"
	var source: String
	var message: String

	func _init(sev: String, src: String, msg: String):
		severity = sev
		source = src
		message = msg

	func text() -> String:
		return "[%s] %s - %s" % [severity.to_upper(), source, message]


static func validate(pack_id: String) -> Array:
	var issues: Array = []
	var flat_rooms_root := _load_json_root(pack_id, "Rooms", "rooms.json")
	var rooms := _load_flat_rooms(flat_rooms_root)
	var entities := _load_json_array(pack_id, "Entities", "entities.json", "entities")
	var behaviors := _load_json_array(pack_id, "Entities", "behaviors.json", "behaviors")
	var trigger_root := TriggerRoot.normalize_root(_load_json_root(pack_id, "Triggers", "global.json"))
	var triggers := TriggerRoot.flatten_rules(trigger_root)
	var abilities := _load_json_array(pack_id, "Abilities", "abilities.json", "abilities")
	var projectiles := _load_json_array(pack_id, "Projectiles", "projectiles.json", "projectiles")
	var items: Array = PedIO.load_items(pack_id).get("items", [])
	var equipment: Array = PedIO.load_equipment(pack_id).get("equipment", [])
	var attacks: Array = PedIO.load_attacks(pack_id).get("attacks", [])
	var poses_root: Dictionary = PspIO.load_or_init(pack_id).get("poses", {})
	var systems: Dictionary = SystemIO.load_or_init(pack_id)

	var room_addrs: Dictionary = {}
	for r in rooms:
		var addr: String = str(r.get("addr", ""))
		if not addr.is_empty():
			room_addrs[addr] = true

	var entity_ids: Dictionary = {}
	for e in entities:
		var eid: String = str(e.get("id", ""))
		if not eid.is_empty():
			entity_ids[eid] = true

	var behavior_ids: Dictionary = {}
	for behavior in behaviors:
		var behavior_id := str(behavior.get("id", ""))
		if not behavior_id.is_empty():
			behavior_ids[behavior_id] = true

	var ability_ids: Dictionary = {}
	for a in abilities:
		var aid: String = str(a.get("id", ""))
		if not aid.is_empty():
			ability_ids[aid] = true

	var item_ids: Dictionary = {}
	for item in items:
		var item_id := str(item.get("id", ""))
		if not item_id.is_empty():
			item_ids[item_id] = true

	var projectile_ids: Dictionary = {}
	for p in projectiles:
		var pid: String = str(p.get("id", ""))
		if not pid.is_empty():
			projectile_ids[pid] = true

	var attack_ids: Dictionary = {}
	for attack in attacks:
		var attack_id := str(attack.get("id", ""))
		if not attack_id.is_empty():
			attack_ids[attack_id] = true

	var pose_ids: Dictionary = {}
	var poses_v: Variant = poses_root.get("poses", {})
	if typeof(poses_v) == TYPE_DICTIONARY:
		for key in (poses_v as Dictionary).keys():
			var key_str := str(key)
			if key_str.is_valid_int():
				pose_ids[int(key_str)] = true

	var dialogue_ids := _list_dialogue_ids(pack_id)
	var shop_ids := _list_shop_ids(pack_id)

	_validate_pack_manifest(pack_id, issues)
	_validate_ui_screens(pack_id, issues)
	_validate_systems(pack_id, systems, room_addrs, issues)
	_validate_world_hierarchy(pack_id, flat_rooms_root, room_addrs, issues)
	_validate_rooms(rooms, entity_ids, room_addrs, dialogue_ids, shop_ids, ability_ids, item_ids, issues)
	_validate_triggers(triggers, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues)
	_validate_entities(entities, behavior_ids, item_ids, issues)
	_validate_abilities(abilities, projectile_ids, issues)
	_validate_items(items, ability_ids, attack_ids, issues)
	_validate_equipment(equipment, ability_ids, attack_ids, issues)
	_validate_attacks(attacks, projectile_ids, pose_ids, issues)
	_validate_projectiles(projectiles, issues)
	_validate_dialogues(pack_id, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues)
	_validate_shops(pack_id, item_ids, issues)

	return issues


static func _validate_ui_screens(pack_id: String, issues: Array) -> void:
	for screen_id_v in UIIo.list_screens(pack_id):
		var screen_id := str(screen_id_v)
		var data: Dictionary = UIIo.load_screen(pack_id, screen_id)
		var result: Dictionary = UIIo.validate_screen(screen_id, data, pack_id)
		for error_v in result.get("errors", []):
			issues.append(Issue.new("error", "UI screen '%s'" % screen_id, str(error_v)))
		for warning_v in result.get("warnings", []):
			issues.append(Issue.new("warning", "UI screen '%s'" % screen_id, str(warning_v)))

	var input_map: Dictionary = UIIo.load_input_map(pack_id)
	for action_name_v in input_map.keys():
		var screen_id := str(input_map.get(action_name_v, "")).strip_edges()
		if screen_id.is_empty():
			continue
		if not UiContract.is_known_screen(screen_id):
			issues.append(Issue.new("error", "UI input_map",
				"action '%s' targets unknown screen '%s'" % [str(action_name_v), screen_id]))
		elif not UiContract.screen_mount_is_supported(screen_id):
			issues.append(Issue.new("warning", "UI input_map",
				"action '%s' targets screen '%s' which has no mounted runtime host" % [str(action_name_v), screen_id]))


static func _validate_pack_manifest(pack_id: String, issues: Array) -> void:
	var manifest := _load_pack_manifest(pack_id)
	if manifest.is_empty():
		return
	var starter_id := _normalize_ship_template_id(str(manifest.get("start_ship_template", "")))
	if starter_id.is_empty():
		return
	var known_ids := _known_ship_template_ids()
	if not known_ids.has(starter_id):
		issues.append(Issue.new("error", "Pack",
			"start_ship_template '%s' does not match any known ship template" % starter_id))


static func _validate_systems(pack_id: String, systems: Dictionary,
		current_pack_room_addrs: Dictionary, issues: Array) -> void:
	var manifest := _load_pack_manifest(pack_id)
	var start_system := str(manifest.get("start_system", "")).strip_edges()
	if systems.is_empty():
		if not start_system.is_empty():
			issues.append(Issue.new("error", "Pack",
				"start_system '%s' is set but the pack has no authored systems" % start_system))
		return
	if start_system.is_empty():
		issues.append(Issue.new("warning", "Pack",
			"pack has authored systems but start_system is empty"))
	elif not systems.has(start_system):
		issues.append(Issue.new("error", "Pack",
			"start_system '%s' does not exist in Systems/systems.json" % start_system))

	for system_id_v in systems.keys():
		var system_id := str(system_id_v)
		var sys_v: Variant = systems[system_id_v]
		var src := "System '%s'" % system_id
		if typeof(sys_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "system entry is not a dictionary"))
			continue
		var sys: Dictionary = sys_v
		var pos_v: Variant = sys.get("position", [])
		if typeof(pos_v) != TYPE_ARRAY or (pos_v as Array).size() < 2:
			issues.append(Issue.new("error", src, "position must be a [x, y] array"))
		var conns_v: Variant = sys.get("connections", [])
		if typeof(conns_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "connections must be an array"))
		else:
			for conn_v in conns_v:
				var conn_id := str(conn_v).strip_edges()
				if not conn_id.is_empty() and not systems.has(conn_id):
					issues.append(Issue.new("error", src,
						"connection references unknown system '%s'" % conn_id))
		var pois_v: Variant = sys.get("pois", [])
		if typeof(pois_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "pois must be an array"))
			continue
		for i in range((pois_v as Array).size()):
			var poi_v: Variant = (pois_v as Array)[i]
			if typeof(poi_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "poi #%d is not a dictionary" % i))
				continue
			var poi: Dictionary = poi_v
			if str(poi.get("type", "")).strip_edges() != "planet":
				continue
			var poi_src := "%s planet POI #%d" % [src, i]
			var planet_v: Variant = poi.get("planet_data", {})
			if typeof(planet_v) != TYPE_DICTIONARY or (planet_v as Dictionary).is_empty():
				issues.append(Issue.new("error", poi_src, "planet_data is missing"))
				continue
			var planet_data: Dictionary = planet_v
			var target_pack: String = str(planet_data.get("pack_id", "")).strip_edges()
			if target_pack.is_empty():
				target_pack = pack_id
			var target_realm: String = str(planet_data.get("realm_id", "")).strip_edges()
			var target_realms: Dictionary = _realm_ids_for_pack(target_pack)
			if target_realm.is_empty():
				target_realm = _start_realm_for_pack(target_pack)
			elif not target_realms.has(target_realm):
				issues.append(Issue.new("error", poi_src,
					"planet_data.realm_id '%s' does not exist in target pack '%s'" % [target_realm, target_pack]))
			var spawn_room: String = _expand_room_addr_for_validation(
				target_pack,
				target_realm,
				str(planet_data.get("spawn_room", "")).strip_edges())
			if spawn_room.is_empty():
				continue
			var target_rooms: Dictionary = current_pack_room_addrs if target_pack == pack_id else _room_addrs_for_pack(target_pack)
			if target_rooms.is_empty():
				issues.append(Issue.new("warning", poi_src,
					"spawn_room '%s' could not be validated because target pack '%s' has no readable rooms" %
					[spawn_room, target_pack]))
			elif not target_rooms.has(spawn_room):
				issues.append(Issue.new("error", poi_src,
					"spawn_room '%s' does not exist in target pack '%s'" % [spawn_room, target_pack]))


static func _validate_rooms(rooms: Array, entity_ids: Dictionary,
		room_addrs: Dictionary, dialogue_ids: Dictionary, shop_ids: Dictionary,
		ability_ids: Dictionary, item_ids: Dictionary,
		issues: Array) -> void:
	for r in rooms:
		var addr := str(r.get("addr", ""))
		var src := "Room '%s'" % addr

		if addr.is_empty():
			issues.append(Issue.new("error", "Rooms", "room entry missing 'addr'"))
			continue
		if int(r.get("width_blocks", 0)) <= 0:
			issues.append(Issue.new("error", src, "missing or zero 'width_blocks'"))
		if int(r.get("height_blocks", 0)) <= 0:
			issues.append(Issue.new("error", src, "missing or zero 'height_blocks'"))
		if int(r.get("width_px", 0)) <= 0:
			issues.append(Issue.new("error", src, "missing or zero 'width_px'"))
		if int(r.get("height_px", 0)) <= 0:
			issues.append(Issue.new("error", src, "missing or zero 'height_px'"))
		var width_blocks := int(r.get("width_blocks", 0))
		var height_blocks := int(r.get("height_blocks", 0))
		var width_px := int(r.get("width_px", 0))
		var height_px := int(r.get("height_px", 0))
		if width_blocks > 0 and width_px > 0 and width_px != width_blocks * 16:
			issues.append(Issue.new("error", src,
				"width_px %d does not match width_blocks %d * 16" % [width_px, width_blocks]))
		if height_blocks > 0 and height_px > 0 and height_px != height_blocks * 16:
			issues.append(Issue.new("error", src,
				"height_px %d does not match height_blocks %d * 16" % [height_px, height_blocks]))
		var room_realm_id := str(r.get("realm_id", "")).strip_edges()
		var room_region_id := str(r.get("region_id", "")).strip_edges()
		if addr.contains("/"):
			var parts := addr.split("/", false)
			if parts.size() == 3:
				var addr_realm_id := str(parts[0]).strip_edges()
				var addr_region_id := str(parts[1]).strip_edges()
				var local_addr := str(parts[2]).strip_edges()
				if room_realm_id.is_empty():
					issues.append(Issue.new("warning", src,
						"flat room is missing realm_id; expected '%s'" % addr_realm_id))
				elif room_realm_id != addr_realm_id:
					issues.append(Issue.new("error", src,
						"realm_id '%s' does not match addr prefix '%s'" % [room_realm_id, addr_realm_id]))
				if room_region_id.is_empty():
					issues.append(Issue.new("warning", src,
						"flat room is missing region_id; expected '%s'" % addr_region_id))
				elif room_region_id != addr_region_id:
					issues.append(Issue.new("error", src,
						"region_id '%s' does not match addr prefix '%s'" % [room_region_id, addr_region_id]))
				var inner_addr := str(r.get("addr", "")).strip_edges()
				if inner_addr != addr and inner_addr != local_addr:
					issues.append(Issue.new("warning", src,
						"room addr field '%s' does not match flat key '%s'" % [inner_addr, addr]))
			elif parts.size() == 2:
				var legacy_region_id := str(parts[0]).strip_edges()
				if room_region_id.is_empty():
					issues.append(Issue.new("warning", src,
						"legacy flat room is missing region_id; expected '%s'" % legacy_region_id))

		var room_ents: Variant = r.get("entities", [])
		if typeof(room_ents) == TYPE_ARRAY:
			for i in (room_ents as Array).size():
				var e: Variant = room_ents[i]
				if typeof(e) != TYPE_DICTIONARY:
					continue
				var ent: Dictionary = e
				var etype := str(ent.get("type", ""))
				if etype.is_empty():
					issues.append(Issue.new("warning", src,
						"entity #%d has no 'type'" % i))
				elif not entity_ids.has(etype) and etype != "player_spawn":
					issues.append(Issue.new("error", src,
						"entity #%d references unknown type '%s'" % [i, etype]))
				var props_v: Variant = ent.get("properties", {})
				if typeof(props_v) == TYPE_DICTIONARY:
					_validate_room_entity_properties(src, i, props_v, dialogue_ids, item_ids, issues)

		var doors: Variant = r.get("doors", [])
		if typeof(doors) == TYPE_ARRAY:
			for d_v in doors:
				if typeof(d_v) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = d_v
				var target := _room_target_from_door(d)
				var sends_to_overworld := bool(d.get("send_to_overworld", false))
				if not target.is_empty() and not room_addrs.has(target):
					var tags: Variant = d.get("tags", [])
					var is_exit := typeof(tags) == TYPE_ARRAY and (tags as Array).has("exit_to_space")
					if not is_exit and not sends_to_overworld:
						issues.append(Issue.new("error", src,
							"door targets unknown room '%s'" % target))
				var dests: Variant = d.get("destinations", [])
				if typeof(dests) == TYPE_ARRAY:
					for dest in dests:
						if typeof(dest) != TYPE_DICTIONARY:
							continue
						var dt := str(dest.get("target", ""))
						if not dt.is_empty() and not room_addrs.has(dt):
							issues.append(Issue.new("error", src,
								"door destination targets unknown room '%s'" % dt))
		var room_triggers: Variant = r.get("triggers", [])
		if r.has("triggers") and typeof(room_triggers) != TYPE_ARRAY and typeof(room_triggers) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "triggers must be an array or trigger-root dictionary"))
		else:
			_validate_triggers(TriggerRoot.flatten_rules(room_triggers), dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues, src)


static func _validate_triggers(triggers: Array, dialogue_ids: Dictionary,
		shop_ids: Dictionary, ability_ids: Dictionary, item_ids: Dictionary,
		entity_ids: Dictionary, room_addrs: Dictionary, issues: Array,
		scope_src: String = "") -> void:
	for rule in triggers:
		var rid := str(rule.get("id", "(unnamed)"))
		var src := "Trigger '%s'" % rid if scope_src.is_empty() else "%s trigger '%s'" % [scope_src, rid]
		var event := str(rule.get("event", ""))
		if event.is_empty():
			issues.append(Issue.new("warning", src, "missing 'event' field"))
		_validate_trigger_locals(rule.get("locals", []), src, issues)

		var conditions_v: Variant = rule.get("conditions", [])
		if rule.has("conditions") and typeof(conditions_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "conditions is not an array"))
		var actions: Variant = rule.get("actions", [])
		if rule.has("actions") and typeof(actions) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "actions is not an array"))
		if typeof(actions) != TYPE_ARRAY:
			continue
		for act in actions:
			if typeof(act) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "action entry is not a dictionary"))
				continue
			_validate_action_refs(act, src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues)

		_validate_conditions_recursive(conditions_v, src, ability_ids, item_ids, issues)


static func _validate_conditions_recursive(conditions: Variant, src: String,
		ability_ids: Dictionary, item_ids: Dictionary, issues: Array) -> void:
	if typeof(conditions) != TYPE_ARRAY:
		return
	for cond in conditions:
		if typeof(cond) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "condition entry is not a dictionary"))
			continue
		var cond_dict: Dictionary = cond
		var ctype := str(cond_dict.get("type", "")).strip_edges()
		if ctype.is_empty():
			issues.append(Issue.new("error", src, "condition is missing type"))
			continue
		if EcaSchema.find_condition_schema(ctype).is_empty() and ctype != "and" and ctype != "or" and ctype != "not":
			issues.append(Issue.new("error", src, "unknown condition type '%s'" % ctype))
			continue
		if ctype == "has_ability":
			var aid := str(cond_dict.get("id", ""))
			if not aid.is_empty() and not ability_ids.has(aid):
				issues.append(Issue.new("warning", src,
					"condition references unknown ability '%s'" % aid))
		elif ctype == "has_item":
			var item_id := str(cond_dict.get("id", ""))
			if not item_id.is_empty() and not item_ids.has(item_id):
				issues.append(Issue.new("error", src,
					"condition references unknown item '%s'" % item_id))
		elif ctype == "payload_eq":
			if str(cond_dict.get("key", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "payload_eq condition is missing key"))
		elif ctype == "has_tag" or ctype == "entity_has_tag" or ctype == "has_global_tag":
			if str(cond_dict.get("tag", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "%s condition is missing tag" % ctype))
		elif ctype == "has_flag" or ctype == "var_eq" or ctype == "var_gte":
			if str(cond_dict.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "%s condition is missing name" % ctype))
		elif ctype == "local_var_eq" or ctype == "local_var_gte":
			if str(cond_dict.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "%s condition is missing name" % ctype))
		if ctype == "and" or ctype == "or":
			var children: Variant = cond_dict.get("children", [])
			if typeof(children) != TYPE_ARRAY or (children as Array).is_empty():
				issues.append(Issue.new("error", src, "%s condition needs a non-empty children array" % ctype))
			_validate_conditions_recursive(children, src, ability_ids, item_ids, issues)
		if ctype == "not":
			var child: Variant = cond_dict.get("child", {})
			if typeof(child) == TYPE_DICTIONARY:
				_validate_conditions_recursive([child], src, ability_ids, item_ids, issues)
			else:
				issues.append(Issue.new("error", src, "not condition needs a child condition dictionary"))


static func _validate_trigger_locals(locals_v: Variant, src: String, issues: Array) -> void:
	if typeof(locals_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", src, "locals must be an array"))
		return
	var seen: Dictionary = {}
	for i in range((locals_v as Array).size()):
		var local_v: Variant = (locals_v as Array)[i]
		if typeof(local_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "local #%d is not a dictionary" % i))
			continue
		var local: Dictionary = local_v
		var name := str(local.get("name", "")).strip_edges()
		if name.is_empty():
			issues.append(Issue.new("error", src, "local #%d is missing name" % i))
			continue
		if seen.has(name):
			issues.append(Issue.new("error", src, "duplicate local '%s'" % name))
		seen[name] = true
		var type_name := str(local.get("type", "int")).strip_edges().to_lower()
		if type_name != "int" and type_name != "float" and type_name != "bool" and type_name != "string":
			issues.append(Issue.new("error", src, "local '%s' has unsupported type '%s'" % [name, type_name]))


static func _validate_entities(entities: Array, behavior_ids: Dictionary, item_ids: Dictionary, issues: Array) -> void:
	var seen_ids: Dictionary = {}
	var known_categories := {
		"enemy": true,
		"boss": true,
		"interactable": true,
		"pickup": true,
		"logic": true,
		"fx": true,
		"other": true,
	}
	var known_movement_modes := {
		"ground": true,
		"hover": true,
		"fly": true,
	}
	for e in entities:
		var eid := str(e.get("id", ""))
		if eid.is_empty():
			issues.append(Issue.new("error", "Entities", "entry missing 'id'"))
			continue
		if seen_ids.has(eid):
			issues.append(Issue.new("error", "Entity '%s'" % eid, "duplicate id"))
		seen_ids[eid] = true
		var cat := str(e.get("category", ""))
		if cat.is_empty():
			issues.append(Issue.new("warning", "Entity '%s'" % eid,
				"missing 'category' - runtime dispatch won't work"))
		elif not known_categories.has(cat):
			issues.append(Issue.new("error", "Entity '%s'" % eid,
				"uses unknown category '%s'" % cat))
		var behavior_id := str(e.get("behavior", "")).strip_edges()
		if not behavior_id.is_empty() and not behavior_ids.has(behavior_id):
			issues.append(Issue.new("error", "Entity '%s'" % eid,
				"references unknown behavior '%s'" % behavior_id))
		var movement_mode := str(e.get("movement_mode", "ground")).strip_edges().to_lower()
		if movement_mode.is_empty():
			movement_mode = "ground"
		if not known_movement_modes.has(movement_mode):
			issues.append(Issue.new("error", "Entity '%s'" % eid,
				"uses unknown movement_mode '%s'" % movement_mode))
		if int(e.get("hp", 1)) < 1:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "hp must be >= 1"))
		if int(e.get("attack_damage", 0)) < 0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "attack_damage must be >= 0"))
		if int(e.get("contact_damage", 0)) < 0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "contact_damage must be >= 0"))
		if float(e.get("contact_cooldown", 0.0)) < 0.0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "contact_cooldown must be >= 0"))
		if float(e.get("move_speed", 0.0)) < 0.0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "move_speed must be >= 0"))
		if int(e.get("projectile_damage", 0)) < 0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "projectile_damage must be >= 0"))
		if float(e.get("projectile_speed", 0.0)) < 0.0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "projectile_speed must be >= 0"))
		var drops_v: Variant = e.get("item_drops", [])
		if typeof(drops_v) == TYPE_ARRAY:
			for drop_v in drops_v:
				if typeof(drop_v) != TYPE_DICTIONARY:
					issues.append(Issue.new("error", "Entity '%s'" % eid, "item_drops entries must be dictionaries"))
					continue
				var drop: Dictionary = drop_v
				var drop_id := str(drop.get("id", drop.get("item_id", ""))).strip_edges()
				if drop_id.is_empty():
					issues.append(Issue.new("error", "Entity '%s'" % eid, "item_drops entry missing id"))
				elif not item_ids.has(drop_id):
					issues.append(Issue.new("error", "Entity '%s'" % eid, "item_drops references unknown item '%s'" % drop_id))
				var chance := float(drop.get("chance", 1.0))
				if chance < 0.0 or chance > 1.0:
					issues.append(Issue.new("error", "Entity '%s'" % eid, "item_drops chance must be 0..1"))


static func _validate_abilities(abilities: Array, projectile_ids: Dictionary,
		issues: Array) -> void:
	for a in abilities:
		var aid := str(a.get("id", ""))
		if aid.is_empty():
			issues.append(Issue.new("warning", "Abilities", "entry missing 'id'"))
			continue
		var params: Variant = a.get("params", {})
		if typeof(params) == TYPE_DICTIONARY:
			var proj_id := str(params.get("projectile_id", ""))
			if not proj_id.is_empty() and not projectile_ids.has(proj_id):
				issues.append(Issue.new("error", "Ability '%s'" % aid,
					"references unknown projectile '%s'" % proj_id))


static func _validate_items(items: Array, ability_ids: Dictionary,
		attack_ids: Dictionary, issues: Array) -> void:
	for item in items:
		var item_id := str(item.get("id", ""))
		if item_id.is_empty():
			continue
		var effect := str(item.get("use_effect", "")).strip_edges()
		var arg := str(item.get("use_arg", "")).strip_edges()
		if effect == "grant_ability" and not arg.is_empty() and not ability_ids.has(arg):
			issues.append(Issue.new("error", "Item '%s'" % item_id,
				"grant_ability references unknown ability '%s'" % arg))
		elif effect == "set_weapon" and not arg.is_empty() and not attack_ids.has(arg) and not _legacy_weapon_ids().has(arg.to_lower()):
			issues.append(Issue.new("error", "Item '%s'" % item_id,
				"set_weapon references unknown attack '%s'" % arg))
		elif (effect == "add_ammo" or effect == "max_ammo_up" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event") and arg.is_empty():
			issues.append(Issue.new("error", "Item '%s'" % item_id,
				"%s requires use_arg" % effect))


static func _validate_equipment(equipment: Array, ability_ids: Dictionary,
		attack_ids: Dictionary, issues: Array) -> void:
	for entry in equipment:
		var eq_id := str(entry.get("id", ""))
		if eq_id.is_empty():
			continue
		var granted := str(entry.get("granted_ability", "")).strip_edges()
		if not granted.is_empty() and not ability_ids.has(granted):
			issues.append(Issue.new("error", "Equipment '%s'" % eq_id,
				"granted_ability references unknown ability '%s'" % granted))
		var weapon := str(entry.get("weapon", "")).strip_edges()
		if not weapon.is_empty() and not attack_ids.has(weapon) and not _legacy_weapon_ids().has(weapon.to_lower()):
			issues.append(Issue.new("error", "Equipment '%s'" % eq_id,
				"weapon references unknown attack '%s'" % weapon))


static func _validate_attacks(attacks: Array, projectile_ids: Dictionary,
		pose_ids: Dictionary, issues: Array) -> void:
	for attack in attacks:
		var attack_id := str(attack.get("id", ""))
		if attack_id.is_empty():
			continue
		var attack_type := str(attack.get("type", "")).strip_edges()
		var hold_behavior := str(attack.get("hold_behavior", "")).strip_edges()
		if hold_behavior.is_empty():
			hold_behavior = "charge_release" if (not str(attack.get("charged_attack_id", "")).strip_edges().is_empty() and int(attack.get("charge_ticks", 0)) > 0) else "full_auto"
		var valid_hold_behaviors := ["full_auto", "single_press", "charge_release"]
		var pose_id := int(attack.get("player_pose", -1))
		if pose_id >= 0 and not pose_ids.has(pose_id):
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"player_pose references unknown pose id %d" % pose_id))
		if not valid_hold_behaviors.has(hold_behavior):
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"hold_behavior '%s' is not supported" % hold_behavior))
		var charged_attack_id := str(attack.get("charged_attack_id", "")).strip_edges()
		if hold_behavior == "charge_release" and charged_attack_id.is_empty():
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"charge_release hold_behavior requires charged_attack_id"))
		elif hold_behavior == "charge_release" and int(attack.get("charge_ticks", 0)) < 1:
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"charge_release hold_behavior requires charge_ticks >= 1"))
		if not charged_attack_id.is_empty():
			if charged_attack_id == attack_id:
				issues.append(Issue.new("error", "Attack '%s'" % attack_id,
					"charged_attack_id cannot reference itself"))
			elif not _has_attack_id(attacks, charged_attack_id):
				issues.append(Issue.new("error", "Attack '%s'" % attack_id,
					"charged_attack_id references unknown attack '%s'" % charged_attack_id))
			elif hold_behavior == "charge_release" and int(attack.get("charge_ticks", 0)) < 1:
				issues.append(Issue.new("error", "Attack '%s'" % attack_id,
					"charged attack requires charge_ticks >= 1"))
		if int(attack.get("charge_fx_frame_width", 1)) < 1 or int(attack.get("charge_fx_frame_height", 1)) < 1:
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"charge FX frame size must be >= 1"))
		if int(attack.get("charge_fx_frame_index", 0)) < 0:
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"charge FX frame index cannot be negative"))
		if int(attack.get("charge_fx_frame_count", 1)) < 1 or int(attack.get("charge_fx_frame_tick", 1)) < 1:
			issues.append(Issue.new("error", "Attack '%s'" % attack_id,
				"charge FX frame count/tick must be >= 1"))
		if attack_type == "projectile":
			var projectile_id := str(attack.get("projectile_id", "")).strip_edges()
			if projectile_id.is_empty() or not projectile_ids.has(projectile_id):
				issues.append(Issue.new("error", "Attack '%s'" % attack_id,
					"references unknown projectile '%s'" % projectile_id))


static func _validate_projectiles(projectiles: Array, issues: Array) -> void:
	for projectile in projectiles:
		var projectile_id := str(projectile.get("id", ""))
		if projectile_id.is_empty():
			continue
		if bool(projectile.get("explosive", false)):
			if int(projectile.get("blast_radius", 0)) < 1:
				issues.append(Issue.new("error", "Projectile '%s'" % projectile_id,
					"explosive projectile must use blast_radius >= 1"))
			if not bool(projectile.get("explode_on_hit", true)) and not bool(projectile.get("explode_on_timeout", false)):
				issues.append(Issue.new("error", "Projectile '%s'" % projectile_id,
					"explosive projectile never detonates (both explode flags are false)"))


static func _validate_room_entity_properties(room_src: String, index: int,
		props_v: Variant, dialogue_ids: Dictionary, item_ids: Dictionary,
		issues: Array) -> void:
	if typeof(props_v) != TYPE_DICTIONARY:
		return
	var props: Dictionary = props_v
	var src := "%s entity #%d" % [room_src, index]
	var dialogue_id := str(props.get("dialogue_id", "")).strip_edges()
	if not dialogue_id.is_empty() and not dialogue_ids.has(dialogue_id):
		issues.append(Issue.new("error", src,
			"references unknown dialogue '%s'" % dialogue_id))
	var item_id := str(props.get("item_id", "")).strip_edges()
	if not item_id.is_empty() and not item_ids.has(item_id):
		issues.append(Issue.new("error", src,
			"references unknown pickup item '%s'" % item_id))
	if props.has("count") and int(props.get("count", 1)) < 1:
		issues.append(Issue.new("error", src, "count must be >= 1"))
	if props.has("width") and float(props.get("width", 0.0)) <= 0.0:
		issues.append(Issue.new("error", src, "width must be > 0"))
	if props.has("height") and float(props.get("height", 0.0)) <= 0.0:
		issues.append(Issue.new("error", src, "height must be > 0"))
	var event_name := str(props.get("event_name", "")).strip_edges()
	if props.has("event_name") and event_name.is_empty():
		issues.append(Issue.new("warning", src, "event_name is present but empty"))


static func _validate_dialogues(pack_id: String, dialogue_ids: Dictionary,
		shop_ids: Dictionary, ability_ids: Dictionary, item_ids: Dictionary,
		entity_ids: Dictionary, room_addrs: Dictionary, issues: Array) -> void:
	for dialogue_id in dialogue_ids.keys():
		var data := PedIO.load_dialogue(pack_id, str(dialogue_id))
		var lines_v: Variant = data.get("lines", [])
		var src := "Dialogue '%s'" % dialogue_id
		if typeof(lines_v) != TYPE_ARRAY or (lines_v as Array).is_empty():
			issues.append(Issue.new("error", src, "has no lines"))
			continue
		var lines: Array = lines_v
		for i in range(lines.size()):
			var line_v: Variant = lines[i]
			if typeof(line_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "line #%d is not a dictionary" % i))
				continue
			var line: Dictionary = line_v
			var line_src := "%s line #%d" % [src, i]
			if str(line.get("text", "")).strip_edges().is_empty():
				issues.append(Issue.new("warning", line_src, "text is empty"))
			var cond_v: Variant = line.get("condition", {})
			if typeof(cond_v) == TYPE_DICTIONARY and not (cond_v as Dictionary).is_empty():
				_validate_conditions_recursive([cond_v], line_src, ability_ids, item_ids, issues)
			var actions_v: Variant = line.get("actions", [])
			if line.has("actions") and typeof(actions_v) != TYPE_ARRAY:
				issues.append(Issue.new("error", line_src, "actions is not an array"))
			if typeof(actions_v) == TYPE_ARRAY:
				for act_v in actions_v:
					if typeof(act_v) == TYPE_DICTIONARY:
						_validate_action_refs(act_v, line_src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues)
					else:
						issues.append(Issue.new("error", line_src, "action entry is not a dictionary"))
			var choices_v: Variant = line.get("choices", [])
			if line.has("choices") and typeof(choices_v) != TYPE_ARRAY:
				issues.append(Issue.new("error", line_src, "choices is not an array"))
			if typeof(choices_v) != TYPE_ARRAY:
				continue
			for c in range((choices_v as Array).size()):
				var choice_v: Variant = (choices_v as Array)[c]
				if typeof(choice_v) != TYPE_DICTIONARY:
					issues.append(Issue.new("error", line_src, "choice #%d is not a dictionary" % c))
					continue
				var choice: Dictionary = choice_v
				var choice_src := "%s choice #%d" % [line_src, c]
				if str(choice.get("text", "")).strip_edges().is_empty():
					issues.append(Issue.new("warning", choice_src, "text is empty"))
				var choice_cond_v: Variant = choice.get("condition", {})
				if typeof(choice_cond_v) == TYPE_DICTIONARY and not (choice_cond_v as Dictionary).is_empty():
					_validate_conditions_recursive([choice_cond_v], choice_src, ability_ids, item_ids, issues)
				var choice_actions_v: Variant = choice.get("actions", [])
				if choice.has("actions") and typeof(choice_actions_v) != TYPE_ARRAY:
					issues.append(Issue.new("error", choice_src, "actions is not an array"))
				if typeof(choice_actions_v) == TYPE_ARRAY:
					for act_v in choice_actions_v:
						if typeof(act_v) == TYPE_DICTIONARY:
							_validate_action_refs(act_v, choice_src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, issues)
						else:
							issues.append(Issue.new("error", choice_src, "action entry is not a dictionary"))


static func _validate_shops(pack_id: String, item_ids: Dictionary, issues: Array) -> void:
	for shop_id in _list_shop_ids(pack_id).keys():
		var data := PedIO.load_shop(pack_id, str(shop_id))
		var items_v: Variant = data.get("items", [])
		var src := "Shop '%s'" % shop_id
		if typeof(items_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "items is not an array"))
			continue
		var seen_stock_ids: Dictionary = {}
		for i in range((items_v as Array).size()):
			var entry_v: Variant = (items_v as Array)[i]
			if typeof(entry_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "item row #%d is not a dictionary" % i))
				continue
			var entry: Dictionary = entry_v
			var stock_id := str(entry.get("stock_id", "")).strip_edges()
			if not stock_id.is_empty():
				if seen_stock_ids.has(stock_id):
					issues.append(Issue.new("error", src, "item row #%d duplicates shop entry id '%s'" % [i, stock_id]))
				seen_stock_ids[stock_id] = true
			var item_id := str(entry.get("id", "")).strip_edges()
			if item_id.is_empty():
				issues.append(Issue.new("error", src, "item row #%d has empty id" % i))
			elif not item_ids.has(item_id):
				issues.append(Issue.new("error", src, "item row #%d references unknown item '%s'" % [i, item_id]))
			if int(entry.get("price", 0)) < 0:
				issues.append(Issue.new("error", src, "item row #%d has negative price" % i))
			if int(entry.get("count", 1)) < 1:
				issues.append(Issue.new("error", src, "item row #%d has count < 1" % i))
			var effect := str(entry.get("use_effect", "")).strip_edges()
			var arg := str(entry.get("use_arg", "")).strip_edges()
			if (effect == "add_ammo" or effect == "max_ammo_up" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event" or effect == "grant_ability" or effect == "set_weapon") and arg.is_empty():
				issues.append(Issue.new("error", src, "item row #%d effect '%s' requires use_arg" % [i, effect]))


static func _validate_world_hierarchy(pack_id: String, flat_rooms_root: Dictionary,
		flat_room_addrs: Dictionary, issues: Array) -> void:
	var all_realms: Dictionary = RegIO.load_all_realms(pack_id)
	var realm_list_v: Variant = all_realms.get("realm_list", [])
	var realms_v: Variant = all_realms.get("realms", {})
	if typeof(realm_list_v) != TYPE_ARRAY or (realm_list_v as Array).is_empty():
		issues.append(Issue.new("error", "World", "pack has no authored realms"))
		return
	if typeof(realms_v) != TYPE_DICTIONARY:
		issues.append(Issue.new("error", "World", "realm bundle map is malformed"))
		return

	var manifest: Dictionary = _load_pack_manifest(pack_id)
	var start_realm: String = str(manifest.get("start_realm", "")).strip_edges()
	if start_realm.is_empty():
		start_realm = _start_realm_for_pack(pack_id)
	elif not (realms_v as Dictionary).has(start_realm):
		issues.append(Issue.new("error", "Pack",
			"start_realm '%s' does not exist in this pack" % start_realm))

	var expected_flat_rooms: Dictionary = {}
	var expected_start_room := ""
	for realm_entry_v in realm_list_v:
		if typeof(realm_entry_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", "World", "realm list entry is not a dictionary"))
			continue
		var realm_entry: Dictionary = realm_entry_v
		var realm_id: String = str(realm_entry.get("id", "")).strip_edges()
		if realm_id.is_empty():
			issues.append(Issue.new("error", "World", "realm list entry is missing id"))
			continue
		var realm_src := "Realm '%s'" % realm_id
		var bundle_v: Variant = (realms_v as Dictionary).get(realm_id, null)
		if typeof(bundle_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", realm_src, "realm bundle is missing"))
			continue
		var bundle: Dictionary = bundle_v
		var realm: Dictionary = bundle.get("realm", {})
		var regions_meta: Dictionary = bundle.get("regions", {})
		var grid_x := int(realm.get("realm_grid_cells_x", 0))
		var grid_y := int(realm.get("realm_grid_cells_y", 0))
		if grid_x < 1:
			issues.append(Issue.new("error", realm_src, "realm_grid_cells_x must be >= 1"))
		if grid_y < 1:
			issues.append(Issue.new("error", realm_src, "realm_grid_cells_y must be >= 1"))

		var region_entries_v: Variant = realm.get("regions", [])
		if typeof(region_entries_v) != TYPE_ARRAY or (region_entries_v as Array).is_empty():
			issues.append(Issue.new("error", realm_src, "realm has no regions"))
			continue

		var realm_region_ids: Dictionary = {}
		var realm_region_cells: Dictionary = {}
		for i in range((region_entries_v as Array).size()):
			var entry_v: Variant = (region_entries_v as Array)[i]
			if typeof(entry_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", realm_src, "regions[%d] is not a dictionary" % i))
				continue
			var entry: Dictionary = entry_v
			var region_id: String = str(entry.get("id", "")).strip_edges()
			var region_src: String = "%s region #%d" % [realm_src, i]
			if region_id.is_empty():
				issues.append(Issue.new("error", region_src, "region is missing id"))
				continue
			region_src = "Region '%s/%s'" % [realm_id, region_id]
			if realm_region_ids.has(region_id):
				issues.append(Issue.new("error", region_src, "duplicate region id"))
				continue
			realm_region_ids[region_id] = true
			if str(entry.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("warning", region_src, "region name is empty"))
			var col: int = int(entry.get("col", 0))
			var row: int = int(entry.get("row", 0))
			var cell_key: String = "%d,%d" % [col, row]
			if realm_region_cells.has(cell_key):
				issues.append(Issue.new("error", region_src,
					"shares realm cell (%d,%d) with region '%s'" % [col, row, str(realm_region_cells[cell_key])]))
			else:
				realm_region_cells[cell_key] = region_id
			if grid_x > 0 and (col < 0 or col >= grid_x):
				issues.append(Issue.new("error", region_src, "col %d is outside realm grid width %d" % [col, grid_x]))
			if grid_y > 0 and (row < 0 or row >= grid_y):
				issues.append(Issue.new("error", region_src, "row %d is outside realm grid height %d" % [row, grid_y]))
			if not regions_meta.has(region_id):
				issues.append(Issue.new("error", region_src, "region.json is missing"))

		var start_region_id: String = str(realm.get("start_region", "")).strip_edges()
		if start_region_id.is_empty():
			issues.append(Issue.new("error", realm_src, "start_region is empty"))
		elif not realm_region_ids.has(start_region_id):
			issues.append(Issue.new("error", realm_src,
				"start_region '%s' is not present in realm.regions" % start_region_id))

		for region_id_v in regions_meta.keys():
			var region_id: String = str(region_id_v)
			if not realm_region_ids.has(region_id):
				issues.append(Issue.new("warning", "Region '%s/%s'" % [realm_id, region_id],
					"region.json exists but region is not placed in realm.json"))

		for region_id_v in realm_region_ids.keys():
			var region_id: String = str(region_id_v)
			var meta_v: Variant = regions_meta.get(region_id, {})
			var region_src: String = "Region '%s/%s'" % [realm_id, region_id]
			if typeof(meta_v) != TYPE_DICTIONARY:
				continue
			var meta: Dictionary = meta_v
			if str(meta.get("id", "")).strip_edges() != region_id:
				issues.append(Issue.new("error", region_src, "region.json id does not match realm region id"))
			var cell_blocks_x := int(meta.get("cell_blocks_x", 0))
			var cell_blocks_y := int(meta.get("cell_blocks_y", 0))
			var region_grid_x := int(meta.get("grid_cells_x", 0))
			var region_grid_y := int(meta.get("grid_cells_y", 0))
			if cell_blocks_x < 1:
				issues.append(Issue.new("error", region_src, "cell_blocks_x must be >= 1"))
			if cell_blocks_y < 1:
				issues.append(Issue.new("error", region_src, "cell_blocks_y must be >= 1"))
			if region_grid_x < 1:
				issues.append(Issue.new("error", region_src, "grid_cells_x must be >= 1"))
			if region_grid_y < 1:
				issues.append(Issue.new("error", region_src, "grid_cells_y must be >= 1"))

			var rooms_root: Dictionary = RegIO.load_region_rooms(pack_id, realm_id, region_id)
			var start_room: String = str(rooms_root.get("start_room", "")).strip_edges()
			var rooms_v: Variant = rooms_root.get("rooms", {})
			if typeof(rooms_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", region_src, "rooms.json 'rooms' must be a dictionary"))
				continue
			var rooms_dict: Dictionary = rooms_v
			if realm_id == start_realm and region_id == start_region_id:
				if start_room.is_empty():
					issues.append(Issue.new("error", region_src, "start region has no start_room"))
				else:
					expected_start_room = RegIO.runtime_room_addr(realm_id, region_id, start_room)
			elif not start_room.is_empty() and not rooms_dict.has(start_room):
				issues.append(Issue.new("error", region_src,
					"start_room '%s' does not exist in this region" % start_room))

			var occupied_cells: Dictionary = {}
			for room_addr_v in rooms_dict.keys():
				var room_addr: String = str(room_addr_v)
				var room_v: Variant = rooms_dict[room_addr]
				if typeof(room_v) != TYPE_DICTIONARY:
					issues.append(Issue.new("error", region_src,
						"room '%s' is not a dictionary" % room_addr))
					continue
				var room: Dictionary = room_v
				var runtime_room_addr: String = RegIO.runtime_room_addr(realm_id, region_id, room_addr)
				expected_flat_rooms[runtime_room_addr] = true
				var room_src: String = "Room '%s'" % runtime_room_addr
				var base_col: int = int(room.get("region_col", 0))
				var base_row: int = int(room.get("region_row", 0))
				var mask_v: Variant = room.get("mask", [])
				if typeof(mask_v) != TYPE_ARRAY or (mask_v as Array).is_empty():
					issues.append(Issue.new("error", room_src, "mask is missing or empty"))
					continue
				var mask_cells: Dictionary = {}
				var max_dx: int = -1
				var max_dy: int = -1
				for cell_v in mask_v:
					if typeof(cell_v) != TYPE_ARRAY or (cell_v as Array).size() < 2:
						issues.append(Issue.new("error", room_src, "mask contains malformed cell entry"))
						continue
					var cell_arr: Array = cell_v
					var dx: int = int(cell_arr[0])
					var dy: int = int(cell_arr[1])
					if dx < 0 or dy < 0:
						issues.append(Issue.new("error", room_src, "mask cells must be >= 0"))
						continue
					var local_key: String = "%d,%d" % [dx, dy]
					if mask_cells.has(local_key):
						issues.append(Issue.new("warning", room_src,
							"mask duplicates local cell (%d,%d)" % [dx, dy]))
						continue
					mask_cells[local_key] = true
					max_dx = maxi(max_dx, dx)
					max_dy = maxi(max_dy, dy)
					var abs_col: int = base_col + dx
					var abs_row: int = base_row + dy
					if region_grid_x > 0 and (abs_col < 0 or abs_col >= region_grid_x):
						issues.append(Issue.new("error", room_src,
							"occupies region col %d outside grid width %d" % [abs_col, region_grid_x]))
					if region_grid_y > 0 and (abs_row < 0 or abs_row >= region_grid_y):
						issues.append(Issue.new("error", room_src,
							"occupies region row %d outside grid height %d" % [abs_row, region_grid_y]))
					var abs_key: String = "%d,%d" % [abs_col, abs_row]
					if occupied_cells.has(abs_key):
						issues.append(Issue.new("error", room_src,
							"overlaps region cell (%d,%d) already used by room '%s'" %
							[abs_col, abs_row, str(occupied_cells[abs_key])]))
					else:
						occupied_cells[abs_key] = room_addr
				var expected_w: int = maxi(1, max_dx + 1) * maxi(1, cell_blocks_x)
				var expected_h: int = maxi(1, max_dy + 1) * maxi(1, cell_blocks_y)
				if int(room.get("width_blocks", 0)) != expected_w:
					issues.append(Issue.new("error", room_src,
						"width_blocks %d does not match mask/cell size expectation %d" %
						[int(room.get("width_blocks", 0)), expected_w]))
				if int(room.get("height_blocks", 0)) != expected_h:
					issues.append(Issue.new("error", room_src,
						"height_blocks %d does not match mask/cell size expectation %d" %
						[int(room.get("height_blocks", 0)), expected_h]))

			if not start_room.is_empty() and not rooms_dict.has(start_room):
				issues.append(Issue.new("error", region_src,
					"start_room '%s' does not exist in rooms.json" % start_room))

	var flat_start_room := str(flat_rooms_root.get("start_room", "")).strip_edges()
	if expected_start_room.is_empty():
		if not flat_start_room.is_empty() and not flat_room_addrs.has(flat_start_room):
			issues.append(Issue.new("error", "Rooms",
				"flat start_room '%s' is missing from flat rooms.json" % flat_start_room))
	elif flat_start_room != expected_start_room:
		issues.append(Issue.new("error", "Rooms",
			"flat start_room '%s' does not match realm/region start '%s'" %
			[flat_start_room, expected_start_room]))

	for expected_addr in expected_flat_rooms.keys():
		if not flat_room_addrs.has(expected_addr):
			issues.append(Issue.new("error", "Rooms",
				"flat rooms.json is missing room '%s'" % str(expected_addr)))
	for flat_addr in flat_room_addrs.keys():
		if not expected_flat_rooms.has(flat_addr):
			issues.append(Issue.new("warning", "Rooms",
				"flat rooms.json contains room '%s' not present in realm hierarchy" % str(flat_addr)))


static func _legacy_weapon_ids() -> Dictionary:
	return {
		"beam": true,
		"grenadelauncher": true,
		"grenade_launcher": true,
	}


static func _has_attack_id(attacks: Array, attack_id: String) -> bool:
	for attack in attacks:
		if str(attack.get("id", "")).strip_edges() == attack_id:
			return true
	return false


static func _validate_action_refs(action: Dictionary, src: String,
		dialogue_ids: Dictionary, shop_ids: Dictionary, ability_ids: Dictionary,
		item_ids: Dictionary, entity_ids: Dictionary, room_addrs: Dictionary,
		issues: Array) -> void:
	var atype := str(action.get("type", "")).strip_edges()
	if atype.is_empty():
		issues.append(Issue.new("error", src, "action is missing type"))
		return
	if EcaSchema.find_action_schema(atype).is_empty():
		issues.append(Issue.new("error", src, "unknown action type '%s'" % atype))
		return
	match atype:
		"comment":
			pass
		"delay":
			if float(action.get("seconds", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "delay action seconds must be >= 0"))
		"wait_for_event":
			if str(action.get("event", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "wait_for_event action is missing event"))
			if float(action.get("timeout", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "wait_for_event timeout must be >= 0"))
		"wait_for_move":
			if str(action.get("entity", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "wait_for_move action is missing entity"))
			if float(action.get("timeout", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "wait_for_move timeout must be >= 0"))
		"wait_for_anim":
			if str(action.get("entity", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "wait_for_anim action is missing entity"))
			if float(action.get("timeout", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "wait_for_anim timeout must be >= 0"))
		"wait_for_camera":
			if float(action.get("timeout", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "wait_for_camera timeout must be >= 0"))
		"set_local_var":
			if str(action.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "set_local_var action is missing name"))
		"add_local_var":
			if str(action.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "add_local_var action is missing name"))
		"start_dialogue":
			var dialogue_id := str(action.get("id", "")).strip_edges()
			if dialogue_id.is_empty():
				issues.append(Issue.new("error", src, "start_dialogue action is missing id"))
			elif not dialogue_ids.has(dialogue_id):
				issues.append(Issue.new("error", src, "action references unknown dialogue '%s'" % dialogue_id))
		"start_shop":
			var shop_id := str(action.get("id", "")).strip_edges()
			if shop_id.is_empty():
				issues.append(Issue.new("error", src, "start_shop action is missing id"))
			elif not shop_ids.has(shop_id):
				issues.append(Issue.new("error", src, "action references unknown shop '%s'" % shop_id))
		"give_ability", "revoke_ability":
			var ability_id := str(action.get("id", "")).strip_edges()
			if ability_id.is_empty():
				issues.append(Issue.new("error", src, "%s action is missing id" % atype))
			elif not ability_ids.has(ability_id):
				issues.append(Issue.new("error", src, "action references unknown ability '%s'" % ability_id))
		"give_item", "take_item":
			var item_id := str(action.get("id", "")).strip_edges()
			if item_id.is_empty():
				issues.append(Issue.new("error", src, "%s action is missing id" % atype))
			elif not item_ids.has(item_id):
				issues.append(Issue.new("error", src, "action references unknown item '%s'" % item_id))
			if int(action.get("count", 1)) < 1:
				issues.append(Issue.new("error", src, "%s action count must be >= 1" % atype))
		"spawn_entity", "despawn_entity", "spawn_entity_at_zone":
			var entity_id := str(action.get("id", "")).strip_edges()
			if entity_id.is_empty():
				issues.append(Issue.new("error", src, "%s action is missing id" % atype))
			elif not entity_ids.has(entity_id):
				issues.append(Issue.new("error", src, "action references unknown entity '%s'" % entity_id))
			if atype == "spawn_entity_at_zone" and str(action.get("zone_id", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "spawn_entity_at_zone action is missing zone_id"))
		"move_entity_to_zone":
			if str(action.get("entity", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "move_entity_to_zone action is missing entity"))
			if str(action.get("zone_id", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "move_entity_to_zone action is missing zone_id"))
		"play_entity_anim":
			if str(action.get("entity", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "play_entity_anim action is missing entity"))
			if str(action.get("anim", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "play_entity_anim action is missing anim"))
		"set_entity_facing":
			if str(action.get("entity", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "set_entity_facing action is missing entity"))
			var direction := str(action.get("direction", "")).strip_edges().to_lower()
			if direction.is_empty():
				issues.append(Issue.new("error", src, "set_entity_facing action is missing direction"))
			elif direction != "left" and direction != "right" and direction != "toward_zone" and direction != "away_from_zone":
				issues.append(Issue.new("error", src, "set_entity_facing direction must be left/right/toward_zone/away_from_zone"))
			elif (direction == "toward_zone" or direction == "away_from_zone") and str(action.get("zone_id", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "set_entity_facing zone-relative directions require zone_id"))
		"camera_focus":
			var mode := str(action.get("mode", "")).strip_edges().to_lower()
			if mode.is_empty():
				issues.append(Issue.new("error", src, "camera_focus action is missing mode"))
			elif mode != "player" and mode != "entity" and mode != "zone" and mode != "position":
				issues.append(Issue.new("error", src, "camera_focus mode must be player/entity/zone/position"))
			elif (mode == "entity" or mode == "zone") and str(action.get("target", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "camera_focus target is required for entity/zone modes"))
			if float(action.get("duration", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "camera_focus duration must be >= 0"))
			if float(action.get("speed", 0.0)) < 0.0:
				issues.append(Issue.new("error", src, "camera_focus speed must be >= 0"))
		"camera_unlock":
			pass
		"set_room_weather":
			var weather_room := str(action.get("room", "")).strip_edges()
			if not weather_room.is_empty() and not room_addrs.has(weather_room):
				issues.append(Issue.new("error", src, "set_room_weather action references unknown room '%s'" % weather_room))
			var preset := str(action.get("preset", "")).strip_edges().to_lower()
			if preset.is_empty():
				issues.append(Issue.new("error", src, "set_room_weather action is missing preset"))
			elif preset != "none" and preset != "rain" and preset != "snow":
				issues.append(Issue.new("error", src, "set_room_weather preset must be none/rain/snow"))
			if float(action.get("intensity", 0.7)) < 0.0:
				issues.append(Issue.new("error", src, "set_room_weather intensity must be >= 0"))
			if float(action.get("speed", 1.0)) < 0.0:
				issues.append(Issue.new("error", src, "set_room_weather speed must be >= 0"))
		"fire_event":
			if str(action.get("event", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "fire_event action is missing event"))
		"set_trigger_enabled":
			if str(action.get("id", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "set_trigger_enabled action is missing id"))
		"teleport_player":
			var room_addr := str(action.get("room", "")).strip_edges()
			if not room_addr.is_empty() and not room_addrs.has(room_addr):
				issues.append(Issue.new("error", src, "teleport_player action references unknown room '%s'" % room_addr))
		"set_var", "add_var", "set_flag":
			var name := str(action.get("name", "")).strip_edges()
			if name.is_empty():
				issues.append(Issue.new("error", src, "%s action is missing name" % atype))
		"add_tag", "remove_tag":
			var tag := str(action.get("tag", "")).strip_edges()
			if tag.is_empty():
				issues.append(Issue.new("error", src, "%s action is missing tag" % atype))
		"play_sfx":
			if str(action.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", src, "play_sfx action is missing name"))
		"log":
			if str(action.get("message", "")).strip_edges().is_empty():
				issues.append(Issue.new("warning", src, "log action message is empty"))


static func _room_target_from_door(door: Dictionary) -> String:
	var target := str(door.get("target_room", "")).strip_edges()
	if target.is_empty():
		target = str(door.get("target", "")).strip_edges()
	return target


static func _load_json_array(pack_id: String, folder: String,
		file_name: String, key: String) -> Array:
	var raw := _load_json_root(pack_id, folder, file_name)
	if raw.is_empty():
		return []
	var arr: Variant = raw.get(key, [])
	if typeof(arr) == TYPE_ARRAY:
		return arr
	return []


static func _load_json_root(pack_id: String, folder: String, file_name: String) -> Dictionary:
	for path in [
		PedIO.user_file(pack_id, folder, file_name),
		PedIO.shipped_file(pack_id, folder, file_name),
		PedIO.demo_file(folder, file_name),
	]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				return raw
	return {}


static func _load_pack_manifest(pack_id: String) -> Dictionary:
	for path in [
		"user://Packs/%s/Pack.json" % pack_id,
		"res://Content/%s/Pack.json" % pack_id,
		"res://Content/demo/Pack.json",
	]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				return raw
	return {}


static func _known_ship_template_ids() -> Dictionary:
	var ids: Dictionary = {}
	if GameManager.has_method("get_builtin_template_names"):
		for name_v in GameManager.get_builtin_template_names():
			var builtin_id := _normalize_ship_template_id(str(name_v))
			if not builtin_id.is_empty():
				ids[builtin_id] = true
	if GameManager.has_method("get_template_list"):
		for entry_v in GameManager.get_template_list():
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var template_id := _normalize_ship_template_id(str(entry.get("filename", "")))
			if template_id.is_empty():
				template_id = _normalize_ship_template_id(str(entry.get("path", "")))
			if template_id.is_empty():
				template_id = _normalize_ship_template_id(str(entry.get("name", "")))
			if not template_id.is_empty():
				ids[template_id] = true
	return ids


static func _normalize_ship_template_id(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.contains("/"):
		trimmed = trimmed.get_file()
	if trimmed.ends_with(".json"):
		trimmed = trimmed.get_basename()
	return trimmed


static func _load_flat_rooms(root: Dictionary) -> Array:
	var out: Array = []
	if root.is_empty():
		return out
	var rooms_v: Variant = root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		return out
	var rooms: Dictionary = rooms_v
	for room_addr_v in rooms.keys():
		var room_addr := str(room_addr_v)
		var room_v: Variant = rooms[room_addr]
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = (room_v as Dictionary).duplicate(true)
		if str(room.get("addr", "")).strip_edges().is_empty():
			room["addr"] = room_addr
		out.append(room)
	return out


static func _room_addrs_for_pack(pack_id: String) -> Dictionary:
	var addrs: Dictionary = {}
	var flat_rooms := _load_flat_rooms(_load_json_root(pack_id, "Rooms", "rooms.json"))
	for room_v in flat_rooms:
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var addr := str(room.get("addr", "")).strip_edges()
		if not addr.is_empty():
			addrs[addr] = true
	return addrs


static func _realm_ids_for_pack(pack_id: String) -> Dictionary:
	var ids: Dictionary = {}
	var all_realms: Dictionary = RegIO.load_all_realms(pack_id)
	var realm_list_v: Variant = all_realms.get("realm_list", [])
	if typeof(realm_list_v) != TYPE_ARRAY:
		return ids
	for entry_v in realm_list_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var realm_id: String = str((entry_v as Dictionary).get("id", "")).strip_edges()
		if not realm_id.is_empty():
			ids[realm_id] = true
	return ids


static func _start_realm_for_pack(pack_id: String) -> String:
	var manifest: Dictionary = _load_pack_manifest(pack_id)
	var start_realm: String = str(manifest.get("start_realm", "")).strip_edges()
	if not start_realm.is_empty():
		return start_realm
	return RegIO.default_realm_id(pack_id)


static func _expand_room_addr_for_validation(pack_id: String, realm_id: String, room_addr: String) -> String:
	var trimmed: String = room_addr.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.count("/") >= 2:
		return trimmed
	if trimmed.count("/") == 1 and not realm_id.is_empty():
		return "%s/%s" % [realm_id, trimmed]
	if realm_id.is_empty():
		return trimmed
	var bundle: Dictionary = RegIO.load_realm_bundle(pack_id, realm_id)
	var realm: Dictionary = bundle.get("realm", {})
	var region_list: Array = realm.get("regions", [])
	for region_entry_v in region_list:
		if typeof(region_entry_v) != TYPE_DICTIONARY:
			continue
		var region_id: String = str((region_entry_v as Dictionary).get("id", "")).strip_edges()
		if region_id.is_empty():
			continue
		var rooms_root: Dictionary = RegIO.load_region_rooms(pack_id, realm_id, region_id)
		var rooms_v: Variant = rooms_root.get("rooms", {})
		if typeof(rooms_v) != TYPE_DICTIONARY:
			continue
		if (rooms_v as Dictionary).has(trimmed):
			return RegIO.runtime_room_addr(realm_id, region_id, trimmed)
	return trimmed


static func _list_dialogue_ids(pack_id: String) -> Dictionary:
	var ids: Dictionary = {}
	for dir_path in [
		PedIO.user_file(pack_id, "Dialogue", ""),
		PedIO.shipped_file(pack_id, "Dialogue", ""),
		PedIO.demo_file("Dialogue", ""),
	]:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		da.list_dir_begin()
		var fname := da.get_next()
		while not fname.is_empty():
			if fname.ends_with(".json"):
				ids[fname.get_basename()] = true
			fname = da.get_next()
	return ids


static func _list_shop_ids(pack_id: String) -> Dictionary:
	var ids: Dictionary = {}
	for shop_id in PedIO.list_shops(pack_id):
		ids[str(shop_id)] = true
	return ids
