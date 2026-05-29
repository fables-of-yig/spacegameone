class_name ContentValidator
extends RefCounted

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const RegIO := preload("res://Space/scripts/shared/reg/reg_io.gd")
const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const BehLoader := preload("res://Space/scripts/runtime/beh/beh_loader.gd")
const PackPaths := preload("res://Space/scripts/shared/pack_paths.gd")
const FactionsIO := preload("res://Space/scripts/shared/factions_io.gd")

const BOOTSTRAP_SCHEMA_VERSION: String = "1.0"
const BOOTSTRAP_REQUIRED_PACK_FIELDS: Array = [
	"schema_version",
	"pack_id",
	"start_system",
	"start_ship_template",
	"start_region",
	"entry_room",
]
const REMOVED_PACK_FIELDS: Array = [
	"start_realm",
]
const REMOVED_DOOR_FIELDS: Array = [
	"send_to_overworld",
	"overworld_region_id",
]
const REMOVED_REGION_FIELDS: Array = [
	"cam_height",
	"horizon",
	"fov_scale",
]
const BOOTSTRAP_REQUIRED_FILES: Array = [
	"Systems/systems.json",
	"Rooms/rooms.json",
	"Player/stats.json",
	"Player/attacks.json",
	"Items/items.json",
	"Items/equipment.json",
	"Abilities/abilities.json",
	"Projectiles/projectiles.json",
	"Entities/entities.json",
	"Entities/behaviors.json",
	"Triggers/global.json",
	"Sprites/player_frames.json",
	"Sprites/player_poses.json",
	"UI/input_map.json",
]

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
	var items := _load_json_array(pack_id, "Items", "items.json", "items")
	var equipment := _load_json_array(pack_id, "Items", "equipment.json", "equipment")
	var attacks := _load_json_array(pack_id, "Player", "attacks.json", "attacks")
	var quests := _load_json_array(pack_id, "Quests", "quests.json", "quests")
	var poses_root := _load_json_root(pack_id, "Sprites", "player_poses.json")
	var systems := _load_systems_existing(pack_id, issues)

	var room_addrs: Dictionary = {}
	for r in rooms:
		var addr: String = str(r.get("addr", ""))
		if not addr.is_empty():
			room_addrs[addr] = true
		var flat_addr: String = str(r.get("_flat_addr", ""))
		if not flat_addr.is_empty():
			room_addrs[flat_addr] = true

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

	var equipment_ids: Dictionary = {}
	for entry in equipment:
		var equipment_id := str(entry.get("id", ""))
		if not equipment_id.is_empty():
			equipment_ids[equipment_id] = true

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

	var quest_ids: Dictionary = {}
	for quest in quests:
		if typeof(quest) != TYPE_DICTIONARY:
			continue
		var quest_id := str((quest as Dictionary).get("id", "")).strip_edges()
		if not quest_id.is_empty():
			quest_ids[quest_id] = true

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
	_validate_required_bootstrap_files(pack_id, issues)
	_validate_ui_screens(pack_id, issues)
	_validate_factions(pack_id, issues)
	_validate_systems(pack_id, systems, room_addrs, issues)
	_validate_world_hierarchy(pack_id, flat_rooms_root, room_addrs, issues)
	_validate_rooms(rooms, entity_ids, room_addrs, dialogue_ids, shop_ids, ability_ids, item_ids, quest_ids, quests, issues)
	_validate_triggers(triggers, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues)
	_validate_behaviors(behaviors, issues)
	_validate_entities(entities, behavior_ids, item_ids, issues)
	_validate_abilities(abilities, projectile_ids, issues)
	_validate_items(items, ability_ids, attack_ids, equipment_ids, issues)
	_validate_equipment(equipment, ability_ids, attack_ids, issues)
	_validate_attacks(attacks, projectile_ids, pose_ids, issues)
	_validate_projectiles(projectiles, issues)
	_validate_dialogues(pack_id, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues)
	_validate_shops(pack_id, item_ids, equipment_ids, issues)
	_validate_quests(quests, item_ids, ability_ids, entity_ids, room_addrs, dialogue_ids, shop_ids, issues)

	return issues


static func _validate_ui_screens(pack_id: String, issues: Array) -> void:
	for required_screen_v in UiContract.screen_ids():
		var required_screen := str(required_screen_v)
		if not UiContract.screen_is_required(required_screen):
			continue
		if not _pack_file_exists(pack_id, "UI/screens/%s.json" % required_screen):
			issues.append(Issue.new("error", "UI screen '%s'" % required_screen,
				"required stock screen file is missing"))

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
			issues.append(Issue.new("error", "UI input_map",
				"action '%s' targets screen '%s' which has no mounted runtime host" % [str(action_name_v), screen_id]))


static func _validate_pack_manifest(pack_id: String, issues: Array) -> void:
	var manifest := _load_pack_manifest(pack_id)
	if manifest.is_empty():
		issues.append(Issue.new("error", "Pack", "Pack.json is missing or malformed"))
		return
	for field_v in BOOTSTRAP_REQUIRED_PACK_FIELDS:
		var field := str(field_v)
		if not manifest.has(field) or str(manifest.get(field, "")).strip_edges().is_empty():
			issues.append(Issue.new("error", "Pack", "Pack.json is missing required field '%s'" % field))
	for removed_field_v in REMOVED_PACK_FIELDS:
		var removed_field := str(removed_field_v)
		if manifest.has(removed_field):
			issues.append(Issue.new("error", "Pack",
				"Pack.json uses removed field '%s' — use 'start_region' instead" % removed_field))
	var schema_v: Variant = manifest.get("schema_version", "")
	if not _schema_version_is_supported(schema_v):
		issues.append(Issue.new("error", "Pack",
			"schema_version must be %s" % BOOTSTRAP_SCHEMA_VERSION))
	var manifest_pack_id := str(manifest.get("pack_id", "")).strip_edges()
	if not manifest_pack_id.is_empty() and manifest_pack_id != pack_id:
		issues.append(Issue.new("error", "Pack",
			"pack_id '%s' does not match selected pack '%s'" % [manifest_pack_id, pack_id]))
	var start_region := str(manifest.get("start_region", "")).strip_edges()
	if not start_region.is_empty():
		var region_ids: Dictionary = _region_ids_for_pack(pack_id)
		if not region_ids.has(start_region):
			issues.append(Issue.new("error", "Pack",
				"start_region '%s' has no matching Regions/%s/region.json" % [start_region, start_region]))
	var entry_room := str(manifest.get("entry_room", "")).strip_edges()
	if not entry_room.is_empty() and entry_room.count("/") > 1:
		issues.append(Issue.new("error", "Pack",
			"entry_room '%s' uses removed 3-slot realm/region/room format — use '<region>/<room>' or '<room>'" % entry_room))
	var starter_id := _normalize_ship_template_id(str(manifest.get("start_ship_template", "")))
	if starter_id.is_empty():
		return
	if not _ship_template_exists(pack_id, starter_id):
		issues.append(Issue.new("error", "Pack",
			"start_ship_template '%s' does not match any known ship template" % starter_id))


static func _validate_required_bootstrap_files(pack_id: String, issues: Array) -> void:
	for rel_path_v in BOOTSTRAP_REQUIRED_FILES:
		var rel_path := str(rel_path_v)
		if not _pack_file_exists(pack_id, rel_path):
			issues.append(Issue.new("error", rel_path, "required bootstrap file is missing"))


static func _validate_factions(pack_id: String, issues: Array) -> void:
	var src := "Factions/factions.json"
	var factions := FactionsIO.load_existing(pack_id)
	if not factions.has("independent"):
		issues.append(Issue.new("error", src,
			"reserved faction id 'independent' is missing — required as runtime fallback"))
	var slug_re := RegEx.new()
	slug_re.compile("^[a-z0-9_]+$")
	for fid_v in factions.keys():
		var fid: String = str(fid_v)
		var entry: Dictionary = factions[fid_v]
		var entry_src: String = "%s [%s]" % [src, fid]
		if slug_re.search(fid) == null:
			issues.append(Issue.new("error", entry_src,
				"id must be a slug (lowercase letters, digits, underscore)"))
		if str(entry.get("name", "")).strip_edges().is_empty():
			issues.append(Issue.new("error", entry_src, "name is required"))
		var disp: String = str(entry.get("disposition_to_player", "neutral"))
		if not FactionsIO.ALLOWED_DISPOSITIONS.has(disp):
			issues.append(Issue.new("error", entry_src,
				"disposition_to_player '%s' is not one of %s" % [disp, FactionsIO.ALLOWED_DISPOSITIONS]))
		var rep: int = int(entry.get("player_rep_start", 0))
		if rep < -100 or rep > 100:
			issues.append(Issue.new("error", entry_src,
				"player_rep_start %d outside allowed range [-100, 100]" % rep))
		var sym: String = str(entry.get("symbol_path", "")).strip_edges()
		if not sym.is_empty():
			var user_abs := PackPaths.writable_pack_file(pack_id, sym)
			var shipped_abs := "res://Content/%s/%s" % [pack_id, sym]
			if not FileAccess.file_exists(user_abs) and not FileAccess.file_exists(shipped_abs):
				issues.append(Issue.new("error", entry_src,
					"symbol_path '%s' does not exist in this pack" % sym))
		var rels_v: Variant = entry.get("relations", {})
		if typeof(rels_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", entry_src, "relations must be a dictionary"))
			continue
		for other_v in (rels_v as Dictionary).keys():
			var other_fid: String = str(other_v)
			if other_fid == fid:
				issues.append(Issue.new("error", entry_src,
					"relations cannot reference this faction's own id"))
				continue
			if not factions.has(other_fid):
				issues.append(Issue.new("error", entry_src,
					"relations references unknown faction '%s'" % other_fid))
			var rel_val: String = str((rels_v as Dictionary)[other_v])
			if not FactionsIO.ALLOWED_RELATIONS.has(rel_val):
				issues.append(Issue.new("error", entry_src,
					"relation to '%s' is '%s', not one of %s" % [other_fid, rel_val, FactionsIO.ALLOWED_RELATIONS]))


static func _validate_systems(pack_id: String, systems: Dictionary,
		current_pack_room_addrs: Dictionary, issues: Array) -> void:
	var manifest := _load_pack_manifest(pack_id)
	var start_system := str(manifest.get("start_system", "")).strip_edges()
	if systems.is_empty():
		issues.append(Issue.new("error", "Systems",
			"Systems/systems.json must contain at least one authored system"))
		return
	if start_system.is_empty():
		issues.append(Issue.new("error", "Pack", "start_system is empty"))
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
		if str(sys.get("name", "")).strip_edges().is_empty():
			issues.append(Issue.new("error", src, "name is required"))
		var pos_v: Variant = sys.get("position", [])
		if typeof(pos_v) != TYPE_ARRAY or (pos_v as Array).size() < 2:
			issues.append(Issue.new("error", src, "position must be a [x, y] array"))
		if float(sys.get("star_size", 0.0)) <= 0.0:
			issues.append(Issue.new("error", src, "star_size must be > 0"))
		if int(sys.get("threat_level", 0)) < 0:
			issues.append(Issue.new("error", src, "threat_level must be >= 0"))
		_validate_optional_texture(pack_id, src, "star_sprite", str(sys.get("star_sprite", "")), issues)
		_validate_optional_texture(pack_id, src, "background_image", str(sys.get("background_image", "")), issues)
		var conns_v: Variant = sys.get("connections", [])
		if typeof(conns_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "connections must be an array"))
		else:
			for conn_v in conns_v:
				var conn_id := str(conn_v).strip_edges()
				if not conn_id.is_empty() and not systems.has(conn_id):
					issues.append(Issue.new("error", src,
						"connection references unknown system '%s'" % conn_id))
		# spawn_triggers used to be validated here; spawning waves is now
		# an ECA action (spawn_space_enemies) gated by ordinary trigger
		# rules in Triggers/global.json, so per-system validation is dead.
		_validate_placed_npcs(pack_id, sys.get("placed_npcs", []), src, issues)
		var pois_v: Variant = sys.get("pois", [])
		if typeof(pois_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", src, "pois must be an array"))
			continue
		var seen_planet_keys: Dictionary = {}
		for i in range((pois_v as Array).size()):
			var poi_v: Variant = (pois_v as Array)[i]
			if typeof(poi_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "poi #%d is not a dictionary" % i))
				continue
			var poi: Dictionary = poi_v
			var poi_type := str(poi.get("type", "")).strip_edges()
			var poi_src := "%s POI #%d" % [src, i]
			if str(poi.get("name", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", poi_src, "name is required"))
			if poi_type.is_empty():
				issues.append(Issue.new("error", poi_src, "type is required"))
			_validate_optional_texture(pack_id, poi_src, "sprite", str(poi.get("sprite", "")), issues)
			if float(poi.get("orbit_dist", 0.0)) < 0.0:
				issues.append(Issue.new("error", poi_src, "orbit_dist must be >= 0"))
			if float(poi.get("visual_scale", 1.0)) <= 0.0:
				issues.append(Issue.new("error", poi_src, "visual_scale must be > 0"))
			if int(poi.get("anim_frames", 1)) < 1:
				issues.append(Issue.new("error", poi_src, "anim_frames must be >= 1"))
			var event_id := str(poi.get("event_id", "")).strip_edges()
			if not event_id.is_empty() and not _space_event_exists(event_id):
				issues.append(Issue.new("error", poi_src,
					"event_id '%s' does not exist" % event_id))
			if bool(poi.get("hidden", false)):
				var hidden_id := str(poi.get("id", "")).strip_edges()
				if hidden_id.is_empty():
					issues.append(Issue.new("error", poi_src,
						"hidden POI requires a stable 'id' so unlock_poi trigger actions can reference it"))
			if poi_type != "planet":
				continue
			poi_src = "%s planet POI #%d" % [src, i]
			var planet_v: Variant = poi.get("planet_data", {})
			if typeof(planet_v) != TYPE_DICTIONARY or (planet_v as Dictionary).is_empty():
				issues.append(Issue.new("error", poi_src, "planet_data is missing"))
				continue
			var planet_data: Dictionary = planet_v
			# Reject removed top-level slots from the old realm shape.
			for legacy_key_v in ["realm_id", "spawn_room", "spawn_pos", "region_id"]:
				var legacy_key := str(legacy_key_v)
				if planet_data.has(legacy_key):
					issues.append(Issue.new("error", poi_src,
						"planet_data uses removed top-level field '%s' — move it into planet_data.regions[]" % legacy_key))
			var target_pack: String = str(planet_data.get("pack_id", "")).strip_edges()
			if target_pack.is_empty():
				issues.append(Issue.new("error", poi_src, "planet_data.pack_id is required"))
				continue
			var poi_id: String = str(planet_data.get("poi_id", "")).strip_edges()
			if poi_id.is_empty():
				issues.append(Issue.new("error", poi_src, "planet_data.poi_id is required (stable id for snapshot keying)"))
			var regions_v: Variant = planet_data.get("regions", null)
			if typeof(regions_v) != TYPE_ARRAY or (regions_v as Array).is_empty():
				issues.append(Issue.new("error", poi_src,
					"planet_data.regions must be a non-empty array of region entries"))
				continue
			var target_region_ids: Dictionary = _region_ids_for_pack(target_pack)
			var target_rooms_by_region: Dictionary = {}
			var seen_region_ids: Dictionary = {}
			for ri in range((regions_v as Array).size()):
				var entry_v: Variant = (regions_v as Array)[ri]
				var entry_src := "%s planet_data.regions[%d]" % [poi_src, ri]
				if typeof(entry_v) != TYPE_DICTIONARY:
					issues.append(Issue.new("error", entry_src, "region entry is not a dictionary"))
					continue
				var entry: Dictionary = entry_v
				var entry_region_id := str(entry.get("id", "")).strip_edges()
				if entry_region_id.is_empty():
					issues.append(Issue.new("error", entry_src, "region entry 'id' is required"))
					continue
				if seen_region_ids.has(entry_region_id):
					issues.append(Issue.new("error", entry_src,
						"duplicate region id '%s' within planet_data.regions[]" % entry_region_id))
					continue
				seen_region_ids[entry_region_id] = true
				if str(entry.get("name", "")).strip_edges().is_empty():
					issues.append(Issue.new("error", entry_src, "region entry 'name' is required"))
				if not target_region_ids.has(entry_region_id):
					issues.append(Issue.new("error", entry_src,
						"region '%s' has no Regions/%s/region.json in target pack '%s'" %
						[entry_region_id, entry_region_id, target_pack]))
				var entry_spawn_room := str(entry.get("spawn_room", "")).strip_edges()
				if entry_spawn_room.is_empty():
					issues.append(Issue.new("error", entry_src, "region entry 'spawn_room' is required"))
				else:
					if entry_spawn_room.find("/") >= 0:
						issues.append(Issue.new("error", entry_src,
							"region entry 'spawn_room' must be a bare room address (no '/') — got '%s'" % entry_spawn_room))
					else:
						var region_rooms := _region_rooms_dict(target_pack, entry_region_id, target_rooms_by_region)
						if region_rooms.is_empty():
							issues.append(Issue.new("error", entry_src,
								"spawn_room '%s' cannot be validated — Regions/%s/rooms.json has no rooms" %
								[entry_spawn_room, entry_region_id]))
						elif not region_rooms.has(entry_spawn_room):
							issues.append(Issue.new("error", entry_src,
								"spawn_room '%s' does not exist in Regions/%s/rooms.json" %
								[entry_spawn_room, entry_region_id]))
						else:
							var runtime_addr: String = RegIO.runtime_room_addr(entry_region_id, entry_spawn_room)
							var target_rooms_index: Dictionary = (
								current_pack_room_addrs if target_pack == pack_id else _room_addrs_for_pack(target_pack)
							)
							if not target_rooms_index.is_empty() and not target_rooms_index.has(runtime_addr):
								issues.append(Issue.new("error", entry_src,
									"spawn_room '%s' resolves to '%s' which is missing from the flat rooms.json — re-flatten the pack" %
									[entry_spawn_room, runtime_addr]))
							var target_room: Dictionary = _room_for_pack(target_pack, runtime_addr)
							if not target_room.is_empty() and not _room_has_player_spawn(target_room):
								issues.append(Issue.new("error", entry_src,
									"spawn_room '%s' has no player_spawn entity" % runtime_addr))
			var planet_key := poi_id
			if planet_key.is_empty():
				planet_key = "%s/%s" % [system_id, str(poi.get("name", i)).strip_edges()]
			if seen_planet_keys.has(planet_key):
				issues.append(Issue.new("error", poi_src,
					"duplicate planet snapshot key '%s' in this system" % planet_key))
			seen_planet_keys[planet_key] = true


static func _validate_placed_npcs(pack_id: String, placed_v: Variant, system_src: String,
		issues: Array) -> void:
	if typeof(placed_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", system_src, "placed_npcs must be an array"))
		return
	var seen_ids: Dictionary = {}
	for i in range((placed_v as Array).size()):
		var npc_v: Variant = (placed_v as Array)[i]
		var src := "%s placed_npc #%d" % [system_src, i]
		if typeof(npc_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "entry is not a dictionary"))
			continue
		var npc: Dictionary = npc_v
		var npc_id := str(npc.get("id", "")).strip_edges()
		if npc_id.is_empty():
			issues.append(Issue.new("error", src, "id is required"))
		elif seen_ids.has(npc_id):
			issues.append(Issue.new("error", src, "duplicate id '%s'" % npc_id))
		seen_ids[npc_id] = true
		var template_id := _normalize_ship_template_id(str(npc.get("template", "")))
		if not template_id.is_empty() and not _ship_template_exists(pack_id, template_id):
			issues.append(Issue.new("error", src,
				"template '%s' does not match any known ship template" % template_id))
		var hail_event_id := str(npc.get("hail_event_id", "")).strip_edges()
		if not hail_event_id.is_empty() and not _space_event_exists(hail_event_id):
			issues.append(Issue.new("error", src,
				"hail_event_id '%s' does not exist" % hail_event_id))
		_validate_optional_texture(pack_id, src, "static_hull_path",
			str(npc.get("static_hull_path", "")), issues)
		if float(npc.get("orbit_dist", 0.0)) < 0.0:
			issues.append(Issue.new("error", src, "orbit_dist must be >= 0"))


static func _validate_rooms(rooms: Array, entity_ids: Dictionary,
		room_addrs: Dictionary, dialogue_ids: Dictionary, shop_ids: Dictionary,
		ability_ids: Dictionary, item_ids: Dictionary, quest_ids: Dictionary, quests: Array,
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
		if r.has("realm_id"):
			issues.append(Issue.new("error", src,
				"room uses removed field 'realm_id' — the realm layer is gone"))
		var room_region_id := str(r.get("region_id", "")).strip_edges()
		if addr.contains("/"):
			var parts := addr.split("/", false)
			if parts.size() > 2:
				issues.append(Issue.new("error", src,
					"room addr '%s' uses removed 3-slot realm/region/room format — use '<region>/<room>'" % addr))
			elif parts.size() == 2:
				var addr_region_id := str(parts[0]).strip_edges()
				if room_region_id.is_empty():
					issues.append(Issue.new("warning", src,
						"flat room is missing region_id; expected '%s'" % addr_region_id))
				elif room_region_id != addr_region_id:
					issues.append(Issue.new("error", src,
						"region_id '%s' does not match addr prefix '%s'" % [room_region_id, addr_region_id]))

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
				for removed_field_v in REMOVED_DOOR_FIELDS:
					var removed_field := str(removed_field_v)
					if d.has(removed_field):
						issues.append(Issue.new("error", src,
							"door uses removed overworld field '%s' — use 'launch_to_space' instead" % removed_field))
				var target := _room_target_from_door(d)
				if not target.is_empty() and target.count("/") > 1:
					issues.append(Issue.new("error", src,
						"door target '%s' uses removed 3-slot realm/region/room format" % target))
				var launches_to_space := bool(d.get("launch_to_space", false))
				if not target.is_empty() and not room_addrs.has(target):
					var tags: Variant = d.get("tags", [])
					var is_exit := typeof(tags) == TYPE_ARRAY and (tags as Array).has("exit_to_space")
					if not is_exit and not launches_to_space:
						issues.append(Issue.new("error", src,
							"door targets unknown room '%s'" % target))
				var dests: Variant = d.get("destinations", [])
				if typeof(dests) == TYPE_ARRAY:
					for dest in dests:
						if typeof(dest) != TYPE_DICTIONARY:
							continue
						var dt := str(dest.get("target", ""))
						if not dt.is_empty() and dt.count("/") > 1:
							issues.append(Issue.new("error", src,
								"door destination target '%s' uses removed 3-slot realm/region/room format" % dt))
						elif not dt.is_empty() and not room_addrs.has(dt):
							issues.append(Issue.new("error", src,
								"door destination targets unknown room '%s'" % dt))
		var room_triggers: Variant = r.get("triggers", [])
		if r.has("triggers") and typeof(room_triggers) != TYPE_ARRAY and typeof(room_triggers) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", src, "triggers must be an array or trigger-root dictionary"))
		else:
			_validate_triggers(TriggerRoot.flatten_rules(room_triggers), dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues, src)


static func _validate_triggers(triggers: Array, dialogue_ids: Dictionary,
		shop_ids: Dictionary, ability_ids: Dictionary, item_ids: Dictionary,
		entity_ids: Dictionary, room_addrs: Dictionary, quest_ids: Dictionary, quests: Array, issues: Array,
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
			_validate_action_refs(act, src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues)

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
		elif ctype == "has_tag" or ctype == "has_global_tag":
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
		if float(e.get("melee_range", 0.0)) < 0.0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "melee_range must be >= 0"))
		if float(e.get("projectile_range", 0.0)) < 0.0:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "projectile_range must be >= 0"))
		if int(e.get("melee_attack_trigger_frame", -1)) < -1:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "melee_attack_trigger_frame must be >= -1 (-1 = none)"))
		if int(e.get("projectile_attack_trigger_frame", -1)) < -1:
			issues.append(Issue.new("error", "Entity '%s'" % eid, "projectile_attack_trigger_frame must be >= -1 (-1 = none)"))
		var scene_path := str(e.get("scene", "")).strip_edges()
		if not scene_path.is_empty() and not ResourceLoader.exists(scene_path):
			issues.append(Issue.new("warning", "Entity '%s'" % eid, "scene '%s' not found" % scene_path))
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


static func _validate_behaviors(behaviors: Array, issues: Array) -> void:
	var seen_ids: Dictionary = {}
	for i in range(behaviors.size()):
		var behavior_v: Variant = behaviors[i]
		if typeof(behavior_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", "Behaviors", "entry #%d is not a dictionary" % i))
			continue
		var behavior: Dictionary = behavior_v
		var behavior_id := str(behavior.get("id", "")).strip_edges()
		var source := "Behavior '%s'" % behavior_id if not behavior_id.is_empty() else "Behavior #%d" % i
		if behavior_id.is_empty():
			issues.append(Issue.new("error", "Behaviors", "entry #%d missing 'id'" % i))
		elif seen_ids.has(behavior_id):
			issues.append(Issue.new("error", source, "duplicate id"))
		seen_ids[behavior_id] = true
		for error_v in BehLoader.validate_behavior(behavior):
			issues.append(Issue.new("error", source, str(error_v)))


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
		attack_ids: Dictionary, equipment_ids: Dictionary, issues: Array) -> void:
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
		elif effect == "equip_item" and not arg.is_empty() and not equipment_ids.has(arg):
			issues.append(Issue.new("error", "Item '%s'" % item_id,
				"equip_item references unknown equipment '%s'" % arg))
		elif (effect == "add_ammo" or effect == "max_ammo_up" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event" or effect == "equip_item") and arg.is_empty():
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
		var secondary_attack := str(entry.get("secondary_attack", "")).strip_edges()
		if not secondary_attack.is_empty() and not attack_ids.has(secondary_attack):
			issues.append(Issue.new("error", "Equipment '%s'" % eq_id,
				"secondary_attack references unknown attack '%s'" % secondary_attack))
		if int(entry.get("secondary_ammo_cost", 1)) < 0:
			issues.append(Issue.new("error", "Equipment '%s'" % eq_id,
				"secondary_ammo_cost cannot be negative"))


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
		entity_ids: Dictionary, room_addrs: Dictionary, quest_ids: Dictionary, quests: Array, issues: Array) -> void:
	for dialogue_id in dialogue_ids.keys():
		var data := _load_json_root(pack_id, "Dialogue", "%s.json" % str(dialogue_id))
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
						_validate_action_refs(act_v, line_src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues)
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
							_validate_action_refs(act_v, choice_src, dialogue_ids, shop_ids, ability_ids, item_ids, entity_ids, room_addrs, quest_ids, quests, issues)
						else:
							issues.append(Issue.new("error", choice_src, "action entry is not a dictionary"))


static func _validate_shops(pack_id: String, item_ids: Dictionary,
		equipment_ids: Dictionary, issues: Array) -> void:
	for shop_id in _list_shop_ids(pack_id).keys():
		var data := _load_json_root(pack_id, "Shops", "%s.json" % str(shop_id))
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
			if (effect == "add_ammo" or effect == "max_ammo_up" or effect == "add_var" or effect == "set_flag" or effect == "add_tag" or effect == "fire_event" or effect == "grant_ability" or effect == "set_weapon" or effect == "equip_item") and arg.is_empty():
				issues.append(Issue.new("error", src, "item row #%d effect '%s' requires use_arg" % [i, effect]))
			elif effect == "equip_item" and not equipment_ids.has(arg):
				issues.append(Issue.new("error", src,
					"item row #%d equip_item references unknown equipment '%s'" % [i, arg]))


static func _validate_quests(quests: Array, item_ids: Dictionary,
		ability_ids: Dictionary, entity_ids: Dictionary, room_addrs: Dictionary,
		dialogue_ids: Dictionary, shop_ids: Dictionary, issues: Array) -> void:
	var seen_quest_ids: Dictionary = {}
	for i in range(quests.size()):
		var quest_v: Variant = quests[i]
		if typeof(quest_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", "Quests", "quest #%d is not a dictionary" % i))
			continue
		var quest: Dictionary = quest_v
		var quest_id := str(quest.get("id", "")).strip_edges()
		var src := "Quest '%s'" % quest_id if not quest_id.is_empty() else "Quest #%d" % i
		if quest_id.is_empty():
			issues.append(Issue.new("error", src, "missing id"))
		elif seen_quest_ids.has(quest_id):
			issues.append(Issue.new("error", src, "duplicate id"))
		seen_quest_ids[quest_id] = true
		if str(quest.get("title", "")).strip_edges().is_empty():
			issues.append(Issue.new("error", src, "missing title"))
		var stages_v: Variant = quest.get("stages", [])
		if typeof(stages_v) != TYPE_ARRAY or (stages_v as Array).is_empty():
			issues.append(Issue.new("error", src, "stages must be a non-empty array"))
			continue
		var seen_stage_ids: Dictionary = {}
		var stages: Array = stages_v
		for stage_i in range(stages.size()):
			var stage_v: Variant = stages[stage_i]
			if typeof(stage_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", src, "stage #%d is not a dictionary" % stage_i))
				continue
			var stage: Dictionary = stage_v
			var stage_id := str(stage.get("id", "")).strip_edges()
			var stage_src := "%s stage '%s'" % [src, stage_id] if not stage_id.is_empty() else "%s stage #%d" % [src, stage_i]
			if stage_id.is_empty():
				issues.append(Issue.new("error", stage_src, "missing id"))
			elif seen_stage_ids.has(stage_id):
				issues.append(Issue.new("error", stage_src, "duplicate id"))
			seen_stage_ids[stage_id] = true
			if str(stage.get("title", "")).strip_edges().is_empty():
				issues.append(Issue.new("error", stage_src, "missing title"))
			_validate_quest_objectives(stage.get("objectives", []), stage_src,
				item_ids, entity_ids, room_addrs, dialogue_ids, shop_ids, issues)
			_validate_quest_rewards(stage.get("rewards", {}), stage_src,
				item_ids, ability_ids, issues)


static func _validate_quest_objectives(objectives_v: Variant, stage_src: String,
		item_ids: Dictionary, entity_ids: Dictionary, room_addrs: Dictionary,
		dialogue_ids: Dictionary, shop_ids: Dictionary, issues: Array) -> void:
	if typeof(objectives_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", stage_src, "objectives must be an array"))
		return
	var objectives: Array = objectives_v
	var seen_objective_ids: Dictionary = {}
	var supported_types := {
		"collect_item": true,
		"have_item": true,
		"kill_entity": true,
		"visit_room": true,
		"talk_dialogue": true,
		"open_shop": true,
		"trigger_event": true,
		"set_flag": true,
		"reach_var": true,
	}
	for i in range(objectives.size()):
		var objective_v: Variant = objectives[i]
		if typeof(objective_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", stage_src, "objective #%d is not a dictionary" % i))
			continue
		var objective: Dictionary = objective_v
		var objective_id := str(objective.get("id", "")).strip_edges()
		var objective_src := "%s objective '%s'" % [stage_src, objective_id] if not objective_id.is_empty() else "%s objective #%d" % [stage_src, i]
		if objective_id.is_empty():
			issues.append(Issue.new("error", objective_src, "missing id"))
		elif seen_objective_ids.has(objective_id):
			issues.append(Issue.new("error", objective_src, "duplicate id"))
		seen_objective_ids[objective_id] = true
		var objective_type := str(objective.get("type", "")).strip_edges()
		if objective_type.is_empty():
			issues.append(Issue.new("error", objective_src, "missing type"))
			continue
		if not supported_types.has(objective_type):
			issues.append(Issue.new("error", objective_src, "unknown type '%s'" % objective_type))
			continue
		match objective_type:
			"collect_item", "have_item":
				_validate_quest_ref(objective, ["item_id", "target_item", "id"], "item",
					item_ids, objective_src, issues)
				_validate_positive_int_field(objective, ["count", "target_count"], objective_src, issues)
			"kill_entity":
				_validate_quest_ref(objective, ["entity_id", "target_entity", "id"], "entity",
					entity_ids, objective_src, issues)
				_validate_positive_int_field(objective, ["count", "target_count"], objective_src, issues)
			"visit_room":
				_validate_quest_ref(objective, ["room", "room_id", "room_addr", "target_room"], "room",
					room_addrs, objective_src, issues)
			"talk_dialogue":
				_validate_quest_ref(objective, ["dialogue_id", "target_dialogue", "id"], "dialogue",
					dialogue_ids, objective_src, issues)
			"open_shop":
				_validate_quest_ref(objective, ["shop_id", "target_shop", "id"], "shop",
					shop_ids, objective_src, issues)
			"trigger_event":
				if _first_nonempty(objective, ["event", "event_id", "target_event", "id"]).is_empty():
					issues.append(Issue.new("error", objective_src, "missing event target"))
			"set_flag":
				if _first_nonempty(objective, ["flag", "flag_name", "name", "id"]).is_empty():
					issues.append(Issue.new("error", objective_src, "missing flag target"))
			"reach_var":
				if _first_nonempty(objective, ["var", "var_name", "name", "id"]).is_empty():
					issues.append(Issue.new("error", objective_src, "missing variable target"))
				if not objective.has("value") and not objective.has("target_value"):
					issues.append(Issue.new("error", objective_src, "missing target value"))


static func _validate_quest_rewards(rewards_v: Variant, stage_src: String,
		item_ids: Dictionary, ability_ids: Dictionary, issues: Array) -> void:
	if typeof(rewards_v) == TYPE_NIL:
		return
	if typeof(rewards_v) != TYPE_DICTIONARY:
		issues.append(Issue.new("error", stage_src, "rewards must be a dictionary"))
		return
	var rewards: Dictionary = rewards_v
	var items_v: Variant = rewards.get("items", [])
	if typeof(items_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", stage_src, "rewards.items must be an array"))
	elif typeof(items_v) == TYPE_ARRAY:
		for i in range((items_v as Array).size()):
			var item_v: Variant = (items_v as Array)[i]
			if typeof(item_v) == TYPE_DICTIONARY:
				var item: Dictionary = item_v
				var item_id := str(item.get("id", item.get("item_id", ""))).strip_edges()
				if item_id.is_empty():
					issues.append(Issue.new("error", stage_src, "reward item #%d is missing id" % i))
				elif not item_ids.has(item_id):
					issues.append(Issue.new("error", stage_src, "reward item #%d references unknown item '%s'" % [i, item_id]))
				if int(item.get("count", 1)) < 1:
					issues.append(Issue.new("error", stage_src, "reward item #%d count must be >= 1" % i))
			elif typeof(item_v) == TYPE_STRING:
				var item_id := str(item_v).strip_edges()
				if item_id.is_empty():
					issues.append(Issue.new("error", stage_src, "reward item #%d is empty" % i))
				elif not item_ids.has(item_id):
					issues.append(Issue.new("error", stage_src, "reward item #%d references unknown item '%s'" % [i, item_id]))
			else:
				issues.append(Issue.new("error", stage_src, "reward item #%d is not a dictionary or string" % i))
	var abilities_v: Variant = rewards.get("abilities", [])
	if typeof(abilities_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", stage_src, "rewards.abilities must be an array"))
	elif typeof(abilities_v) == TYPE_ARRAY:
		for i in range((abilities_v as Array).size()):
			var ability_id := ""
			var ability_v: Variant = (abilities_v as Array)[i]
			if typeof(ability_v) == TYPE_DICTIONARY:
				ability_id = str((ability_v as Dictionary).get("id", (ability_v as Dictionary).get("ability_id", ""))).strip_edges()
			else:
				ability_id = str(ability_v).strip_edges()
			if ability_id.is_empty():
				issues.append(Issue.new("error", stage_src, "reward ability #%d is empty" % i))
			elif not ability_ids.has(ability_id):
				issues.append(Issue.new("error", stage_src, "reward ability #%d references unknown ability '%s'" % [i, ability_id]))
	var events_v: Variant = rewards.get("events", [])
	if typeof(events_v) != TYPE_ARRAY:
		issues.append(Issue.new("error", stage_src, "rewards.events must be an array"))
	elif typeof(events_v) == TYPE_ARRAY:
		for i in range((events_v as Array).size()):
			if str((events_v as Array)[i]).strip_edges().is_empty():
				issues.append(Issue.new("error", stage_src, "reward event #%d is empty" % i))


static func _validate_quest_ref(data: Dictionary, keys: Array, kind: String,
		known_ids: Dictionary, src: String, issues: Array) -> void:
	var id := _first_nonempty(data, keys)
	if id.is_empty():
		issues.append(Issue.new("error", src, "missing %s target" % kind))
	elif not known_ids.has(id):
		issues.append(Issue.new("error", src, "references unknown %s '%s'" % [kind, id]))


static func _validate_positive_int_field(data: Dictionary, keys: Array,
		src: String, issues: Array) -> void:
	for key_v in keys:
		var key := str(key_v)
		if data.has(key) and int(data.get(key, 1)) < 1:
			issues.append(Issue.new("error", src, "%s must be >= 1" % key))


static func _first_nonempty(data: Dictionary, keys: Array) -> String:
	for key_v in keys:
		var value := str(data.get(str(key_v), "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _validate_world_hierarchy(pack_id: String, flat_rooms_root: Dictionary,
		flat_room_addrs: Dictionary, issues: Array) -> void:
	# Walk Regions/<id>/ directly. The realm layer was removed in Phase 6.
	var manifest: Dictionary = _load_pack_manifest(pack_id)
	var start_region: String = str(manifest.get("start_region", "")).strip_edges()
	var region_ids: Array = _list_region_ids_existing(pack_id)
	if region_ids.is_empty():
		issues.append(Issue.new("error", "World", "pack has no authored regions under Regions/"))
		return

	var region_id_set: Dictionary = {}
	for region_id_v in region_ids:
		region_id_set[str(region_id_v)] = true

	if not start_region.is_empty() and not region_id_set.has(start_region):
		issues.append(Issue.new("error", "Pack",
			"start_region '%s' does not match any directory under Regions/" % start_region))

	var expected_flat_rooms: Dictionary = {}
	var expected_start_room := ""
	var start_room_data: Dictionary = {}
	for region_id_v in region_ids:
		var region_id := str(region_id_v)
		var region_src: String = "Region '%s'" % region_id
		var region_meta := _load_pack_json_root(pack_id, "Regions/%s/region.json" % region_id)
		if region_meta.is_empty():
			issues.append(Issue.new("error", region_src, "Regions/%s/region.json is missing or malformed" % region_id))
			continue
		for removed_field_v in REMOVED_REGION_FIELDS:
			var removed_field := str(removed_field_v)
			if region_meta.has(removed_field):
				issues.append(Issue.new("error", region_src,
					"region.json uses removed mode-7 field '%s' — drop it" % removed_field))
		if str(region_meta.get("id", "")).strip_edges() != region_id:
			issues.append(Issue.new("error", region_src,
				"region.json id '%s' does not match directory name" % str(region_meta.get("id", ""))))
		if str(region_meta.get("name", "")).strip_edges().is_empty():
			issues.append(Issue.new("warning", region_src, "region.json 'name' is empty"))
		var cell_blocks_x := int(region_meta.get("cell_blocks_x", 0))
		var cell_blocks_y := int(region_meta.get("cell_blocks_y", 0))
		var region_grid_x := int(region_meta.get("grid_cells_x", 0))
		var region_grid_y := int(region_meta.get("grid_cells_y", 0))
		if cell_blocks_x < 1:
			issues.append(Issue.new("error", region_src, "cell_blocks_x must be >= 1"))
		if cell_blocks_y < 1:
			issues.append(Issue.new("error", region_src, "cell_blocks_y must be >= 1"))
		if region_grid_x < 1:
			issues.append(Issue.new("error", region_src, "grid_cells_x must be >= 1"))
		if region_grid_y < 1:
			issues.append(Issue.new("error", region_src, "grid_cells_y must be >= 1"))

		if not _pack_file_exists(pack_id, "Regions/%s/rooms.json" % region_id):
			issues.append(Issue.new("error", region_src, "rooms.json is missing"))
			continue
		var rooms_root := _load_pack_json_root(pack_id, "Regions/%s/rooms.json" % region_id)
		var rooms_v: Variant = rooms_root.get("rooms", {})
		if typeof(rooms_v) != TYPE_DICTIONARY:
			issues.append(Issue.new("error", region_src, "rooms.json 'rooms' must be a dictionary"))
			continue
		var rooms_dict: Dictionary = rooms_v
		var start_room: String = str(rooms_root.get("start_room", "")).strip_edges()
		if region_id == start_region:
			if start_room.is_empty():
				issues.append(Issue.new("error", region_src, "start region has no start_room"))
			elif not rooms_dict.has(start_room):
				issues.append(Issue.new("error", region_src,
					"start_room '%s' does not exist in rooms.json" % start_room))
			else:
				expected_start_room = RegIO.runtime_room_addr(region_id, start_room)
				var start_room_v: Variant = rooms_dict.get(start_room, {})
				if typeof(start_room_v) == TYPE_DICTIONARY:
					start_room_data = start_room_v
		elif not start_room.is_empty() and not rooms_dict.has(start_room):
			issues.append(Issue.new("error", region_src,
				"start_room '%s' does not exist in rooms.json" % start_room))

		var occupied_cells: Dictionary = {}
		for room_addr_v in rooms_dict.keys():
			var room_addr: String = str(room_addr_v)
			if room_addr.find("/") >= 0:
				issues.append(Issue.new("error", region_src,
					"room key '%s' must be a bare addr (no '/')" % room_addr))
				continue
			var room_v: Variant = rooms_dict[room_addr]
			if typeof(room_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", region_src,
					"room '%s' is not a dictionary" % room_addr))
				continue
			var room: Dictionary = room_v
			var runtime_room_addr: String = RegIO.runtime_room_addr(region_id, room_addr)
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

		_validate_region_variants(pack_id, region_id, rooms_dict, region_src, issues)

	var flat_start_room := str(flat_rooms_root.get("start_room", "")).strip_edges()
	if expected_start_room.is_empty():
		if not flat_start_room.is_empty() and not flat_room_addrs.has(flat_start_room):
			issues.append(Issue.new("error", "Rooms",
				"flat start_room '%s' is missing from flat rooms.json" % flat_start_room))
	elif flat_start_room != expected_start_room:
		issues.append(Issue.new("error", "Rooms",
			"flat start_room '%s' does not match canonical region start '%s'" %
			[flat_start_room, expected_start_room]))
	_validate_bootstrap_entry_room(pack_id, manifest, flat_room_addrs,
		expected_start_room, start_room_data, issues)

	for expected_addr in expected_flat_rooms.keys():
		if not flat_room_addrs.has(expected_addr):
			issues.append(Issue.new("error", "Rooms",
				"flat rooms.json is missing room '%s'" % str(expected_addr)))
	for flat_addr in flat_room_addrs.keys():
		if not expected_flat_rooms.has(flat_addr):
			issues.append(Issue.new("warning", "Rooms",
				"flat rooms.json contains room '%s' not present in Regions/ hierarchy" % str(flat_addr)))


# Validates Regions/<region>/room_variants.json against the region's
# rooms.json. The file is optional — no file or an empty `variants` map
# means "no variants in this region" and is silently accepted.
#
# Errors:
#   - variants key references a room not in this region's rooms.json
#   - variant 'use' references a missing room
#   - variant 'use' equals the canonical key (no-op rule)
#   - variant 'use' targets another canonical variant key (chains banned)
#   - missing/malformed 'when' clause (scope/flag/equals shape)
#
# Warning:
#   - two rules in the same list have identical when-clauses (second is
#     dead — the first match wins at resolve time).
static func _validate_region_variants(pack_id: String, region_id: String,
		rooms_dict: Dictionary, region_src: String, issues: Array) -> void:
	var variants_root := RegIO.load_room_variants(pack_id, region_id)
	var variants_v: Variant = variants_root.get("variants", {})
	if typeof(variants_v) != TYPE_DICTIONARY:
		issues.append(Issue.new("error", region_src,
			"room_variants.json 'variants' must be a dictionary"))
		return
	var variants: Dictionary = variants_v
	if variants.is_empty():
		return
	var canonical_keys: Dictionary = {}
	for canonical_room_v in variants.keys():
		canonical_keys[str(canonical_room_v)] = true
	for canonical_room_v in variants.keys():
		var canonical_room: String = str(canonical_room_v)
		var owner_src: String = "%s room_variants[%s]" % [region_src, canonical_room]
		if not rooms_dict.has(canonical_room):
			issues.append(Issue.new("error", owner_src,
				"variants key '%s' is not a room in this region's rooms.json" % canonical_room))
			continue
		var rules_v: Variant = variants[canonical_room]
		if typeof(rules_v) != TYPE_ARRAY:
			issues.append(Issue.new("error", owner_src,
				"variant rules must be an array of { when, use } entries"))
			continue
		var rules: Array = rules_v
		var seen_when_keys: Dictionary = {}
		for ri in range(rules.size()):
			var rule_v: Variant = rules[ri]
			var rule_src: String = "%s[%d]" % [owner_src, ri]
			if typeof(rule_v) != TYPE_DICTIONARY:
				issues.append(Issue.new("error", rule_src,
					"variant rule must be a dictionary"))
				continue
			var rule: Dictionary = rule_v
			var use_room: String = str(rule.get("use", "")).strip_edges()
			if use_room.is_empty():
				issues.append(Issue.new("error", rule_src, "variant rule 'use' is required"))
			elif use_room == canonical_room:
				issues.append(Issue.new("error", rule_src,
					"variant 'use' targets the same canonical room '%s' — drop the rule" % use_room))
			elif not rooms_dict.has(use_room):
				issues.append(Issue.new("error", rule_src,
					"variant 'use' targets room '%s' which is not in this region's rooms.json" % use_room))
			elif canonical_keys.has(use_room):
				issues.append(Issue.new("error", rule_src,
					"variant 'use' targets '%s' which itself has variants — chains are not allowed" % use_room))
			var when_key: String = _validate_variant_when_clause(rule.get("when", null), rule_src, issues)
			if not when_key.is_empty():
				if seen_when_keys.has(when_key):
					issues.append(Issue.new("warning", rule_src,
						"another rule above has the same condition '%s' — this rule will never match" % when_key))
				else:
					seen_when_keys[when_key] = true


# Validates a single variant 'when' clause. On success, returns a stable
# string key for duplicate-detection (e.g. "planet::flag_name==true"); on
# failure, appends an issue and returns "".
static func _validate_variant_when_clause(when_v: Variant, src: String, issues: Array) -> String:
	if typeof(when_v) != TYPE_DICTIONARY:
		issues.append(Issue.new("error", src,
			"variant 'when' clause is required and must be a dictionary"))
		return ""
	var when_dict: Dictionary = when_v
	var scope: String = str(when_dict.get("scope", "")).strip_edges().to_lower()
	if scope != "planet" and scope != "global":
		issues.append(Issue.new("error", src,
			"variant 'when.scope' must be 'planet' or 'global' (got '%s')" % scope))
		return ""
	var flag_name: String = str(when_dict.get("flag", "")).strip_edges()
	if flag_name.is_empty():
		issues.append(Issue.new("error", src, "variant 'when.flag' is required"))
		return ""
	if not when_dict.has("equals"):
		issues.append(Issue.new("error", src,
			"variant 'when.equals' is required (use null to match an unset flag)"))
		return ""
	var equals_v: Variant = when_dict.get("equals", null)
	var equals_kind: int = typeof(equals_v)
	if equals_kind != TYPE_BOOL and equals_kind != TYPE_INT \
			and equals_kind != TYPE_FLOAT and equals_kind != TYPE_STRING \
			and equals_kind != TYPE_NIL:
		issues.append(Issue.new("error", src,
			"variant 'when.equals' must be bool, int, float, string, or null"))
		return ""
	return "%s::%s==%s" % [scope, flag_name, str(equals_v)]


static func _validate_bootstrap_entry_room(pack_id: String, manifest: Dictionary,
		flat_room_addrs: Dictionary, expected_start_room: String,
		start_room_data: Dictionary, issues: Array) -> void:
	var start_region := str(manifest.get("start_region", "")).strip_edges()
	var entry_room := str(manifest.get("entry_room", "")).strip_edges()
	if entry_room.is_empty():
		return
	if entry_room.count("/") > 1:
		# Already flagged by _validate_pack_manifest; skip secondary spam.
		return
	var normalized_entry_room := _normalize_entry_room(pack_id, start_region, entry_room)
	if normalized_entry_room.is_empty():
		issues.append(Issue.new("error", "Pack", "entry_room could not be resolved"))
		return
	if not flat_room_addrs.has(normalized_entry_room):
		issues.append(Issue.new("error", "Pack",
			"entry_room '%s' resolves to missing room '%s'" % [entry_room, normalized_entry_room]))
	elif not expected_start_room.is_empty() and normalized_entry_room != expected_start_room:
		issues.append(Issue.new("error", "Pack",
			"entry_room '%s' does not match canonical start room '%s'" %
			[normalized_entry_room, expected_start_room]))
	if expected_start_room.is_empty():
		return
	if not _room_has_player_spawn(start_room_data):
		issues.append(Issue.new("error", "Room '%s'" % expected_start_room,
			"start room must contain a player_spawn entity"))


static func _normalize_entry_room(pack_id: String, start_region: String, entry_room: String) -> String:
	var trimmed := entry_room.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.count("/") == 1:
		return trimmed
	if start_region.is_empty():
		return trimmed
	# Bare addr: prepend the configured start_region only if the room exists there.
	var rooms := _region_rooms_dict(pack_id, start_region, {})
	if not rooms.has(trimmed):
		return trimmed
	return RegIO.runtime_room_addr(start_region, trimmed)


static func _room_has_player_spawn(room: Dictionary) -> bool:
	var entities_v: Variant = room.get("entities", [])
	if typeof(entities_v) != TYPE_ARRAY:
		return false
	for entity_v in entities_v:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		if str((entity_v as Dictionary).get("type", "")).strip_edges() == "player_spawn":
			return true
	return false


static func _room_for_pack(pack_id: String, room_addr: String) -> Dictionary:
	var rooms := _load_flat_rooms(_load_json_root(pack_id, "Rooms", "rooms.json"))
	for room_v in rooms:
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var addr := str(room.get("addr", "")).strip_edges()
		var flat_addr := str(room.get("_flat_addr", "")).strip_edges()
		if addr == room_addr or flat_addr == room_addr:
			return room
	return {}


static func _is_vec2_like(value: Variant) -> bool:
	if value is Vector2 or value is Vector2i:
		return true
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).size() >= 2
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return dict.has("x") and dict.has("y")
	return false


static func _numeric_pair_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var arr: Array = value
	if arr.size() < 2:
		return false
	return float(arr[1]) >= float(arr[0])


static func _validate_optional_texture(pack_id: String, source: String, field: String,
		path: String, issues: Array) -> void:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		return
	if not _asset_path_exists(pack_id, trimmed):
		issues.append(Issue.new("error", source, "%s '%s' does not exist" % [field, trimmed]))


static func _asset_path_exists(pack_id: String, path: String) -> bool:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		return true
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return FileAccess.file_exists(trimmed) or ResourceLoader.exists(trimmed)
	return _pack_file_exists(pack_id, trimmed)


static func _space_event_exists(event_id: String) -> bool:
	var trimmed := event_id.strip_edges()
	if trimmed.is_empty() or trimmed.begins_with("proc_"):
		return true
	var data_manager := _autoload_node("DataManager")
	if data_manager != null:
		var events_v: Variant = data_manager.get("events")
		if typeof(events_v) == TYPE_DICTIONARY and (events_v as Dictionary).has(trimmed):
			return true
	return false


static func _enemy_class_exists(class_id: String) -> bool:
	var trimmed := class_id.strip_edges()
	if trimmed.is_empty():
		return false
	var data_manager := _autoload_node("DataManager")
	if data_manager != null:
		var classes_v: Variant = data_manager.get("enemy_classes")
		if typeof(classes_v) == TYPE_DICTIONARY and (classes_v as Dictionary).has(trimmed):
			return true
	for built_in in ["fighter", "scout", "interceptor", "gunship", "bomber", "elite", "boss"]:
		if trimmed == built_in:
			return true
	return false


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
		quest_ids: Dictionary, quests: Array,
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
		"quest_start":
			_validate_quest_action_target(action, src, quest_ids, quests, issues, false, false)
		"quest_set_stage":
			_validate_quest_action_target(action, src, quest_ids, quests, issues, true, false)
		"quest_complete_stage":
			_validate_quest_action_target(action, src, quest_ids, quests, issues, false, false)
		"quest_complete_objective":
			_validate_quest_action_target(action, src, quest_ids, quests, issues, false, true)
		"quest_complete":
			_validate_quest_action_target(action, src, quest_ids, quests, issues, false, false)
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
			if not weather_room.is_empty() and weather_room.count("/") > 1:
				issues.append(Issue.new("error", src,
					"set_room_weather action room '%s' uses removed 3-slot realm/region/room format" % weather_room))
			elif not weather_room.is_empty() and not room_addrs.has(weather_room):
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
			if not room_addr.is_empty() and room_addr.count("/") > 1:
				issues.append(Issue.new("error", src,
					"teleport_player action room '%s' uses removed 3-slot realm/region/room format" % room_addr))
			elif not room_addr.is_empty() and not room_addrs.has(room_addr):
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


static func _validate_quest_action_target(action: Dictionary, src: String,
		quest_ids: Dictionary, quests: Array, issues: Array,
		stage_required: bool, objective_required: bool) -> void:
	var action_type := str(action.get("type", "")).strip_edges()
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	if quest_id.is_empty():
		issues.append(Issue.new("error", src, "%s action is missing quest_id" % action_type))
		return
	if not quest_ids.has(quest_id):
		issues.append(Issue.new("error", src, "action references unknown quest '%s'" % quest_id))
		return
	var quest := _find_quest(quests, quest_id)
	var stage_id := str(action.get("stage_id", "")).strip_edges()
	if stage_required and stage_id.is_empty():
		issues.append(Issue.new("error", src, "%s action is missing stage_id" % action_type))
	elif not stage_id.is_empty() and not _quest_has_stage(quest, stage_id):
		issues.append(Issue.new("error", src, "action references unknown quest stage '%s.%s'" % [quest_id, stage_id]))
	var objective_id := str(action.get("objective_id", "")).strip_edges()
	if objective_required and objective_id.is_empty():
		issues.append(Issue.new("error", src, "%s action is missing objective_id" % action_type))
	elif not objective_id.is_empty():
		if not stage_id.is_empty() and not _quest_stage_has_objective(quest, stage_id, objective_id):
			issues.append(Issue.new("error", src,
				"action references unknown quest objective '%s.%s.%s'" % [quest_id, stage_id, objective_id]))
		elif stage_id.is_empty() and not _quest_has_objective(quest, objective_id):
			issues.append(Issue.new("error", src,
				"action references unknown quest objective '%s.%s'" % [quest_id, objective_id]))


static func _find_quest(quests: Array, quest_id: String) -> Dictionary:
	for quest_v in quests:
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		if str(quest.get("id", "")).strip_edges() == quest_id:
			return quest
	return {}


static func _quest_has_stage(quest: Dictionary, stage_id: String) -> bool:
	for stage_v in _array_or_empty(quest.get("stages", [])):
		if typeof(stage_v) == TYPE_DICTIONARY and str((stage_v as Dictionary).get("id", "")).strip_edges() == stage_id:
			return true
	return false


static func _quest_has_objective(quest: Dictionary, objective_id: String) -> bool:
	for stage_v in _array_or_empty(quest.get("stages", [])):
		if typeof(stage_v) == TYPE_DICTIONARY and _quest_stage_has_objective(quest, str((stage_v as Dictionary).get("id", "")).strip_edges(), objective_id):
			return true
	return false


static func _quest_stage_has_objective(quest: Dictionary, stage_id: String, objective_id: String) -> bool:
	for stage_v in _array_or_empty(quest.get("stages", [])):
		if typeof(stage_v) != TYPE_DICTIONARY:
			continue
		var stage: Dictionary = stage_v
		if str(stage.get("id", "")).strip_edges() != stage_id:
			continue
		for objective_v in _array_or_empty(stage.get("objectives", [])):
			if typeof(objective_v) == TYPE_DICTIONARY and str((objective_v as Dictionary).get("id", "")).strip_edges() == objective_id:
				return true
	return false


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


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
	return _load_pack_json_root(pack_id, "%s/%s" % [folder, file_name])


static func _load_pack_json_root(pack_id: String, rel_path: String) -> Dictionary:
	for path in _pack_file_paths(pack_id, rel_path):
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
	return _load_pack_json_root(pack_id, "Pack.json")


static func _pack_file_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges()
	if clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)
	return [
		PackPaths.writable_pack_file(pack_id, clean_path),
		PackPaths.shipped_pack_file(pack_id, clean_path),
	]


static func _pack_dir_paths(pack_id: String, rel_path: String) -> Array:
	var clean_path := rel_path.strip_edges().rstrip("/")
	if clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)
	return [
		PackPaths.writable_pack_file(pack_id, clean_path),
		PackPaths.shipped_pack_file(pack_id, clean_path),
	]


static func _pack_file_exists(pack_id: String, rel_path: String) -> bool:
	for path in _pack_file_paths(pack_id, rel_path):
		if FileAccess.file_exists(path):
			return true
	return false


static func _load_systems_existing(pack_id: String, issues: Array) -> Dictionary:
	var root := _load_json_root(pack_id, "Systems", "systems.json")
	if root.is_empty():
		return {}
	var systems_v: Variant = root.get("systems", null)
	if typeof(systems_v) != TYPE_DICTIONARY:
		issues.append(Issue.new("error", "Systems/systems.json",
			"root must contain a 'systems' dictionary"))
		return {}
	return (systems_v as Dictionary).duplicate(true)


static func _list_region_ids_existing(pack_id: String) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	for root in _pack_dir_paths(pack_id, "Regions"):
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if dir.current_is_dir() and not name.begins_with(".") and not seen.has(name):
				# Only accept directories that contain a region.json.
				if _pack_file_exists(pack_id, "Regions/%s/region.json" % name):
					seen[name] = true
					ids.append(name)
			name = dir.get_next()
		dir.list_dir_end()
	ids.sort()
	return ids


# Returns the room-addr dictionary for Regions/<region_id>/rooms.json. The
# optional cache lets POI validation avoid re-reading the same region rooms
# for every POI entry that targets it.
static func _region_rooms_dict(pack_id: String, region_id: String,
		cache: Dictionary) -> Dictionary:
	if cache.has(region_id):
		var cached_v: Variant = cache[region_id]
		if typeof(cached_v) == TYPE_DICTIONARY:
			return cached_v
	var root := _load_pack_json_root(pack_id, "Regions/%s/rooms.json" % region_id)
	var rooms_v: Variant = root.get("rooms", {})
	var rooms: Dictionary = rooms_v if typeof(rooms_v) == TYPE_DICTIONARY else {}
	cache[region_id] = rooms
	return rooms


static func _known_ship_template_ids() -> Dictionary:
	var ids: Dictionary = {}
	_collect_ship_template_ids_from_dir("res://Space/data/npc_templates/", ids)
	_collect_ship_template_ids_from_dir("user://npc_templates/", ids)
	var game_manager := _autoload_node("GameManager")
	if game_manager != null and game_manager.has_method("get_builtin_template_names"):
		for name_v in game_manager.get_builtin_template_names():
			var builtin_id := _normalize_ship_template_id(str(name_v))
			if not builtin_id.is_empty():
				ids[builtin_id] = true
	if game_manager != null and game_manager.has_method("get_template_list"):
		for entry_v in game_manager.get_template_list():
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


static func _ship_template_exists(pack_id: String, template_id: String) -> bool:
	if template_id.is_empty():
		return false
	for rel_path in [
		"Ships/%s.json" % template_id,
		"ShipTemplates/%s.json" % template_id,
	]:
		if _pack_file_exists(pack_id, rel_path):
			return true
	return _known_ship_template_ids().has(template_id)


static func _schema_version_is_supported(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return is_equal_approx(float(value), 1.0)
		_:
			return str(value).strip_edges() == BOOTSTRAP_SCHEMA_VERSION


static func _collect_ship_template_ids_from_dir(dir_path: String, ids: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json") and not file_name.begins_with("_"):
			var template_id := _normalize_ship_template_id(file_name)
			if not template_id.is_empty():
				ids[template_id] = true
		file_name = dir.get_next()
	dir.list_dir_end()


static func _autoload_node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


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
		room["_flat_addr"] = room_addr
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
		var flat_addr := str(room.get("_flat_addr", "")).strip_edges()
		if not flat_addr.is_empty():
			addrs[flat_addr] = true
	return addrs


static func _region_ids_for_pack(pack_id: String) -> Dictionary:
	var ids: Dictionary = {}
	for region_id_v in _list_region_ids_existing(pack_id):
		var region_id: String = str(region_id_v).strip_edges()
		if not region_id.is_empty():
			ids[region_id] = true
	return ids


static func _list_dialogue_ids(pack_id: String) -> Dictionary:
	var ids: Dictionary = {}
	for dir_path in [
		PedIO.user_file(pack_id, "Dialogue", ""),
		PedIO.shipped_file(pack_id, "Dialogue", ""),
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
	for dir_path in [
		PackPaths.writable_pack_dir(pack_id) + "Shops/",
		"res://Content/%s/Shops/" % pack_id,
	]:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		da.list_dir_begin()
		var fname := da.get_next()
		while not fname.is_empty():
			if fname.ends_with(".json") and not fname.begins_with("_"):
				ids[fname.get_basename()] = true
			fname = da.get_next()
		da.list_dir_end()
	return ids
