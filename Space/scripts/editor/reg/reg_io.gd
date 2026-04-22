extends RefCounted

# Multi-realm world IO.
#
# Pack layout (user layer):
#   user://Packs/<pack>/Realms/<realm_id>/realm.json
#   user://Packs/<pack>/Realms/<realm_id>/Regions/<region_id>/region.json
#   user://Packs/<pack>/Realms/<realm_id>/Regions/<region_id>/rooms.json
#   user://Packs/<pack>/Rooms/rooms.json   -- flat runtime view
#
# Runtime room addresses are flattened as:
#   <realm_id>/<region_id>/<room_addr>
#
# Legacy migration:
#   Older packs stored exactly one realm at the pack root:
#     user://Packs/<pack>/realm.json
#     user://Packs/<pack>/Regions/<region_id>/...
#     user://Packs/<pack>/Rooms/rooms.json
#   On first load, that layout is copied into Realms/realm_main/.

const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")

const SCHEMA_VERSION: String = "2.0"
const DEFAULT_REALM_ID: String = "realm_main"
const DEFAULT_REALM_NAME: String = "Main"
const DEFAULT_REGION_ID: String = "region_default"
const DEFAULT_CELL_BLOCKS_X: int = 1
const DEFAULT_CELL_BLOCKS_Y: int = 1
const DEFAULT_REGION_GRID_X: int = 128
const DEFAULT_REGION_GRID_Y: int = 96
const DEFAULT_REALM_GRID_X: int = 32
const DEFAULT_REALM_GRID_Y: int = 32


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % pack_id


static func realms_dir(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Realms/"


static func realm_dir(pack_id: String, realm_id: String) -> String:
    return realms_dir(pack_id) + realm_id + "/"


static func realm_json_path(pack_id: String, realm_id: String) -> String:
    return realm_dir(pack_id, realm_id) + "realm.json"


static func regions_dir(pack_id: String, realm_id: String) -> String:
    return realm_dir(pack_id, realm_id) + "Regions/"


static func region_dir(pack_id: String, realm_id: String, region_id: String) -> String:
    return regions_dir(pack_id, realm_id) + region_id + "/"


static func region_json_path(pack_id: String, realm_id: String, region_id: String) -> String:
    return region_dir(pack_id, realm_id, region_id) + "region.json"


static func region_rooms_json_path(pack_id: String, realm_id: String, region_id: String) -> String:
    return region_dir(pack_id, realm_id, region_id) + "rooms.json"


static func runtime_room_addr(realm_id: String, region_id: String, room_addr: String) -> String:
    return "%s/%s/%s" % [realm_id, region_id, room_addr]


static func load_or_init(pack_id: String, realm_id: String = "") -> Dictionary:
    _ensure_pack_dirs(pack_id)
    _migrate_or_seed(pack_id)
    var active_realm_id: String = realm_id.strip_edges()
    if active_realm_id.is_empty():
        active_realm_id = default_realm_id(pack_id)
    return load_realm_bundle(pack_id, active_realm_id)


static func load_realm_bundle(pack_id: String, realm_id: String) -> Dictionary:
    _ensure_pack_dirs(pack_id)
    _migrate_or_seed(pack_id)

    var rid: String = realm_id.strip_edges()
    if rid.is_empty():
        rid = default_realm_id(pack_id)

    var realm := _load_json_dict(realm_json_path(pack_id, rid))
    if realm.is_empty():
        realm = default_realm(rid, DEFAULT_REALM_NAME)
        _save_json(realm_json_path(pack_id, rid), realm)
    else:
        _migrate_realm_meta(realm, rid)

    var regions: Dictionary = {}
    var region_list: Array = realm.get("regions", [])
    for entry_v in region_list:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var region_id: String = str(entry.get("id", "")).strip_edges()
        if region_id.is_empty():
            continue
        var region_meta := _load_json_dict(region_json_path(pack_id, rid, region_id))
        if region_meta.is_empty():
            region_meta = default_region(region_id, str(entry.get("name", region_id)))
            _save_json(region_json_path(pack_id, rid, region_id), region_meta)
        else:
            migrate_region_meta(region_meta, region_id, str(entry.get("name", region_id)))
        regions[region_id] = region_meta
    return {
        "realm": realm,
        "regions": regions,
        "realm_id": rid,
    }


static func load_all_realms(pack_id: String) -> Dictionary:
    _ensure_pack_dirs(pack_id)
    _migrate_or_seed(pack_id)

    var realm_list: Array = list_realms(pack_id)
    var realms: Dictionary = {}
    for entry_v in realm_list:
        var entry: Dictionary = entry_v
        var realm_id: String = str(entry.get("id", ""))
        realms[realm_id] = load_realm_bundle(pack_id, realm_id)
    return {
        "realm_list": realm_list,
        "realms": realms,
    }


static func list_realms(pack_id: String) -> Array:
    _ensure_pack_dirs(pack_id)
    _migrate_or_seed(pack_id)

    var out: Array = []
    var root := realms_dir(pack_id)
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if dir.current_is_dir() and not name.begins_with("."):
            var realm := _load_json_dict(realm_json_path(pack_id, name))
            if realm.is_empty():
                realm = default_realm(name, name.capitalize())
                _save_json(realm_json_path(pack_id, name), realm)
            out.append({
                "id": name,
                "name": str(realm.get("realm_name", realm.get("name", name))),
            })
        name = dir.get_next()
    dir.list_dir_end()
    out.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("id", "")) < str(b.get("id", "")))
    return out


static func default_realm_id(pack_id: String) -> String:
    var realms: Array = list_realms(pack_id)
    if not realms.is_empty():
        return str((realms[0] as Dictionary).get("id", DEFAULT_REALM_ID))
    return DEFAULT_REALM_ID


static func save_realm(pack_id: String, realm_id: String, realm: Dictionary) -> bool:
    var rid: String = realm_id.strip_edges()
    if rid.is_empty():
        return false
    _ensure_pack_dirs(pack_id)
    realm["id"] = rid
    _migrate_realm_meta(realm, rid)
    var ok := _save_json(realm_json_path(pack_id, rid), realm)
    flatten_to_runtime(pack_id)
    return ok


static func save_region_meta(pack_id: String, realm_id: String, region_id: String, region_meta: Dictionary) -> bool:
    _ensure_dir(region_dir(pack_id, realm_id, region_id))
    migrate_region_meta(region_meta, region_id, str(region_meta.get("name", region_id)))
    return _save_json(region_json_path(pack_id, realm_id, region_id), region_meta)


static func load_region_rooms(pack_id: String, realm_id: String, region_id: String) -> Dictionary:
    _ensure_dir(region_dir(pack_id, realm_id, region_id))
    var path := region_rooms_json_path(pack_id, realm_id, region_id)
    if not FileAccess.file_exists(path):
        var fresh := default_region_rooms(region_id)
        _save_json(path, fresh)
        return fresh
    var data := _load_json_dict(path)
    if data.is_empty():
        return default_region_rooms(region_id)
    var rooms_v: Variant = data.get("rooms", {})
    if typeof(rooms_v) == TYPE_DICTIONARY:
        var rooms: Dictionary = rooms_v
        for key in rooms.keys():
            var room_v: Variant = rooms[key]
            if typeof(room_v) == TYPE_DICTIONARY:
                EnvIO.migrate_room_to_layers(room_v)
    return data


static func save_region_rooms(pack_id: String, realm_id: String, region_id: String, rooms_data: Dictionary) -> bool:
    _ensure_dir(region_dir(pack_id, realm_id, region_id))
    var ok := _save_json(region_rooms_json_path(pack_id, realm_id, region_id), rooms_data)
    flatten_to_runtime(pack_id)
    return ok


static func create_realm(pack_id: String, realm_id: String, realm_name: String) -> bool:
    var rid: String = realm_id.strip_edges()
    if rid.is_empty():
        return false
    if FileAccess.file_exists(realm_json_path(pack_id, rid)):
        return true
    var realm := default_realm(rid, realm_name if not realm_name.strip_edges().is_empty() else rid.capitalize())
    var ok := save_realm(pack_id, rid, realm)
    if not ok:
        return false
    var region_meta := default_region(DEFAULT_REGION_ID, "Default")
    save_region_meta(pack_id, rid, DEFAULT_REGION_ID, region_meta)
    save_region_rooms(pack_id, rid, DEFAULT_REGION_ID, default_region_rooms(DEFAULT_REGION_ID))
    return true


static func flatten_to_runtime(pack_id: String) -> void:
    _ensure_dir(user_pack_dir(pack_id) + "Rooms")
    var pack_manifest: Dictionary = _load_pack_manifest(pack_id)
    var desired_start_realm: String = str(pack_manifest.get("start_realm", "")).strip_edges()

    var flat_rooms: Dictionary = {}
    var start_key: String = ""
    var realms: Array = list_realms(pack_id)
    for realm_entry_v in realms:
        var realm_entry: Dictionary = realm_entry_v
        var realm_id: String = str(realm_entry.get("id", ""))
        if realm_id.is_empty():
            continue
        var bundle := load_realm_bundle(pack_id, realm_id)
        var realm: Dictionary = bundle.get("realm", {})
        var start_region_id: String = str(realm.get("start_region", "")).strip_edges()
        var region_list: Array = realm.get("regions", [])
        for region_entry_v in region_list:
            if typeof(region_entry_v) != TYPE_DICTIONARY:
                continue
            var region_id: String = str((region_entry_v as Dictionary).get("id", "")).strip_edges()
            if region_id.is_empty():
                continue
            var region_rooms := _load_json_dict(region_rooms_json_path(pack_id, realm_id, region_id))
            var rooms_v: Variant = region_rooms.get("rooms", {})
            if typeof(rooms_v) != TYPE_DICTIONARY:
                continue
            var rooms: Dictionary = rooms_v
            for room_addr_v in rooms.keys():
                var room_addr: String = str(room_addr_v)
                var room_v: Variant = rooms[room_addr]
                if typeof(room_v) != TYPE_DICTIONARY:
                    continue
                var room: Dictionary = (room_v as Dictionary).duplicate(true)
                _prefix_room_door_targets(room, realm_id, region_id)
                room["realm_id"] = realm_id
                room["region_id"] = region_id
                room["addr"] = runtime_room_addr(realm_id, region_id, room_addr)
                flat_rooms[room["addr"]] = room
            if start_key.is_empty() and desired_start_realm.is_empty():
                if region_id == start_region_id:
                    var local_start := str(region_rooms.get("start_room", "")).strip_edges()
                    if not local_start.is_empty():
                        start_key = runtime_room_addr(realm_id, region_id, local_start)
            elif realm_id == desired_start_realm and region_id == start_region_id:
                var desired_local_start := str(region_rooms.get("start_room", "")).strip_edges()
                if not desired_local_start.is_empty():
                    start_key = runtime_room_addr(realm_id, region_id, desired_local_start)

    if start_key.is_empty() and not flat_rooms.is_empty():
        start_key = str(flat_rooms.keys()[0])

    var flat := {
        "version": "4.0",
        "start_room": start_key,
        "rooms": flat_rooms,
    }
    _save_json(user_pack_dir(pack_id) + "Rooms/rooms.json", flat)


static func get_realm_start_room(pack_id: String, realm_id: String) -> String:
    var bundle := load_realm_bundle(pack_id, realm_id)
    var realm: Dictionary = bundle.get("realm", {})
    var start_region_id: String = str(realm.get("start_region", "")).strip_edges()
    if start_region_id.is_empty():
        return ""
    return get_region_start_room(pack_id, realm_id, start_region_id)


static func get_region_start_room(pack_id: String, realm_id: String, region_id: String) -> String:
    if realm_id.strip_edges().is_empty() or region_id.strip_edges().is_empty():
        return ""
    var rooms_root := load_region_rooms(pack_id, realm_id, region_id)
    var room_addr: String = str(rooms_root.get("start_room", "")).strip_edges()
    if room_addr.is_empty():
        return ""
    return runtime_room_addr(realm_id, region_id, room_addr)


static func migrate_region_meta(region: Dictionary, region_id: String, region_name: String) -> void:
    var defaults := default_region(region_id, region_name)
    for key in defaults.keys():
        if not region.has(key):
            region[key] = defaults[key]
    region["version"] = "1.1"
    region["id"] = region_id
    if str(region.get("name", "")).strip_edges().is_empty():
        region["name"] = region_name


static func default_realm(realm_id: String = DEFAULT_REALM_ID, realm_name: String = DEFAULT_REALM_NAME) -> Dictionary:
    return {
        "version": SCHEMA_VERSION,
        "id": realm_id,
        "realm_name": realm_name,
        "start_region": DEFAULT_REGION_ID,
        "realm_grid_cells_x": DEFAULT_REALM_GRID_X,
        "realm_grid_cells_y": DEFAULT_REALM_GRID_Y,
        "realm_tile_layers": [
            {"name": "Ground", "tiles": []},
            {"name": "Structure", "tiles": []},
            {"name": "Sky", "tiles": []},
        ],
        "regions": [
            {
                "id": DEFAULT_REGION_ID,
                "name": "Default",
                "col": 0,
                "row": 0,
            },
        ],
    }


static func default_region(region_id: String, region_name: String) -> Dictionary:
    return {
        "version": "1.1",
        "id": region_id,
        "name": region_name,
        "cell_blocks_x": DEFAULT_CELL_BLOCKS_X,
        "cell_blocks_y": DEFAULT_CELL_BLOCKS_Y,
        "grid_cells_x": DEFAULT_REGION_GRID_X,
        "grid_cells_y": DEFAULT_REGION_GRID_Y,
        "music_id": "",
        "encounter_id": "",
        "gravity_mult": 1.0,
        "visual_theme": "",
        "hazard_type": "",
        "cam_height": 120.0,
        "horizon": 0.35,
        "fov_scale": 1.5,
    }


static func default_region_rooms(region_id: String) -> Dictionary:
    return {
        "version": "1.0",
        "region_id": region_id,
        "start_room": "",
        "rooms": {},
    }


static func make_room_from_mask(addr: String, friendly: String, mask: Array,
        origin_col: int, origin_row: int, cell_bx: int, cell_by: int,
        tileset_id: int = 0) -> Dictionary:
    if mask.is_empty():
        return {}
    var max_dx: int = 0
    var max_dy: int = 0
    for cell in mask:
        max_dx = maxi(max_dx, int(cell[0]))
        max_dy = maxi(max_dy, int(cell[1]))
    var cells_w := max_dx + 1
    var cells_h := max_dy + 1
    var w_blocks := cells_w * cell_bx
    var h_blocks := cells_h * cell_by
    var room := EnvIO.default_room(addr, friendly, w_blocks, h_blocks, tileset_id)
    room["region_col"] = origin_col
    room["region_row"] = origin_row
    room["mask"] = mask.duplicate(true)
    return room


static func _ensure_pack_dirs(pack_id: String) -> void:
    _ensure_dir(user_pack_dir(pack_id))
    _ensure_dir(realms_dir(pack_id))


static func _migrate_or_seed(pack_id: String) -> void:
    var realms := _list_existing_realm_ids(pack_id)
    if not realms.is_empty():
        return

    var legacy_realm := _load_json_dict(_legacy_realm_json_path(pack_id))
    var legacy_flat_rooms := _load_json_dict(user_pack_dir(pack_id) + "Rooms/rooms.json")

    if not legacy_realm.is_empty():
        _migrate_legacy_hierarchy(pack_id, legacy_realm)
        return

    if not legacy_flat_rooms.is_empty():
        _migrate_flat_rooms_into_default_realm(pack_id, legacy_flat_rooms)
        return

    create_realm(pack_id, DEFAULT_REALM_ID, DEFAULT_REALM_NAME)


static func _migrate_legacy_hierarchy(pack_id: String, legacy_realm: Dictionary) -> void:
    var realm := legacy_realm.duplicate(true)
    realm["id"] = DEFAULT_REALM_ID
    _migrate_realm_meta(realm, DEFAULT_REALM_ID)
    save_realm(pack_id, DEFAULT_REALM_ID, realm)

    var region_list: Array = realm.get("regions", [])
    if region_list.is_empty():
        var fallback_realm := default_realm(DEFAULT_REALM_ID, str(realm.get("realm_name", DEFAULT_REALM_NAME)))
        save_realm(pack_id, DEFAULT_REALM_ID, fallback_realm)
        region_list = fallback_realm.get("regions", [])

    for entry_v in region_list:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var region_id: String = str(entry.get("id", "")).strip_edges()
        if region_id.is_empty():
            continue
        var region_meta := _load_json_dict(_legacy_region_json_path(pack_id, region_id))
        if region_meta.is_empty():
            region_meta = default_region(region_id, str(entry.get("name", region_id)))
        else:
            migrate_region_meta(region_meta, region_id, str(entry.get("name", region_id)))
        save_region_meta(pack_id, DEFAULT_REALM_ID, region_id, region_meta)

        var rooms := _load_json_dict(_legacy_region_rooms_json_path(pack_id, region_id))
        if rooms.is_empty():
            rooms = default_region_rooms(region_id)
        save_region_rooms(pack_id, DEFAULT_REALM_ID, region_id, rooms)

    flatten_to_runtime(pack_id)


static func _migrate_flat_rooms_into_default_realm(pack_id: String, legacy: Dictionary) -> void:
    var realm := default_realm(DEFAULT_REALM_ID, DEFAULT_REALM_NAME)
    save_realm(pack_id, DEFAULT_REALM_ID, realm)

    var region_meta := default_region(DEFAULT_REGION_ID, "Default")
    save_region_meta(pack_id, DEFAULT_REALM_ID, DEFAULT_REGION_ID, region_meta)

    var region_rooms := default_region_rooms(DEFAULT_REGION_ID)
    var rooms_v: Variant = legacy.get("rooms", {})
    var start_v: Variant = legacy.get("start_room", "")
    if typeof(rooms_v) == TYPE_DICTIONARY:
        var rooms: Dictionary = rooms_v
        var addrs: Array = rooms.keys()
        addrs.sort()
        var col: int = 0
        var row: int = 0
        var row_h: int = 0
        var grid_w: int = DEFAULT_REGION_GRID_X
        for addr_key in addrs:
            var room_v: Variant = rooms[addr_key]
            if typeof(room_v) != TYPE_DICTIONARY:
                continue
            var room: Dictionary = room_v
            EnvIO.migrate_room_to_layers(room)
            var w_blocks := int(room.get("width_blocks", DEFAULT_CELL_BLOCKS_X))
            var h_blocks := int(room.get("height_blocks", DEFAULT_CELL_BLOCKS_Y))
            var cells_w: int = maxi(1, int(ceil(float(w_blocks) / float(DEFAULT_CELL_BLOCKS_X))))
            var cells_h: int = maxi(1, int(ceil(float(h_blocks) / float(DEFAULT_CELL_BLOCKS_Y))))
            if col + cells_w > grid_w:
                col = 0
                row += row_h + 1
                row_h = 0
            var mask: Array = []
            for dy in cells_h:
                for dx in cells_w:
                    mask.append([dx, dy])
            room["region_col"] = col
            room["region_row"] = row
            room["mask"] = mask
            (region_rooms["rooms"] as Dictionary)[str(addr_key)] = room
            col += cells_w + 1
            row_h = maxi(row_h, cells_h)
        if typeof(start_v) == TYPE_STRING and str(start_v) != "":
            region_rooms["start_room"] = str(start_v)

    save_region_rooms(pack_id, DEFAULT_REALM_ID, DEFAULT_REGION_ID, region_rooms)
    flatten_to_runtime(pack_id)


static func _migrate_realm_meta(realm: Dictionary, realm_id: String) -> void:
    var defaults := default_realm(realm_id, str(realm.get("realm_name", realm.get("name", DEFAULT_REALM_NAME))))
    for key in defaults.keys():
        if not realm.has(key):
            realm[key] = defaults[key]
    realm["version"] = SCHEMA_VERSION
    realm["id"] = realm_id
    if str(realm.get("realm_name", "")).strip_edges().is_empty():
        realm["realm_name"] = str(realm.get("name", DEFAULT_REALM_NAME))


static func _prefix_room_door_targets(room: Dictionary, realm_id: String, region_id: String) -> void:
    var doors_v: Variant = room.get("doors", [])
    if typeof(doors_v) != TYPE_ARRAY:
        return
    for door_v in doors_v:
        if typeof(door_v) != TYPE_DICTIONARY:
            continue
        var door: Dictionary = door_v
        door["target_room"] = _prefix_room_ref(str(door.get("target_room", "")), realm_id, region_id)
        var dests_v: Variant = door.get("destinations", [])
        if typeof(dests_v) != TYPE_ARRAY:
            continue
        for dest_v in dests_v:
            if typeof(dest_v) != TYPE_DICTIONARY:
                continue
            var dest: Dictionary = dest_v
            dest["target"] = _prefix_room_ref(str(dest.get("target", "")), realm_id, region_id)


static func _prefix_room_ref(target: String, realm_id: String, region_id: String) -> String:
    var trimmed := target.strip_edges()
    if trimmed.is_empty():
        return ""
    var slash_count: int = trimmed.count("/")
    if slash_count >= 2:
        return trimmed
    if slash_count == 1:
        return "%s/%s" % [realm_id, trimmed]
    return runtime_room_addr(realm_id, region_id, trimmed)


static func _list_existing_realm_ids(pack_id: String) -> Array:
    var out: Array = []
    var dir := DirAccess.open(realms_dir(pack_id))
    if dir == null:
        return out
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if dir.current_is_dir() and not name.begins_with(".") and FileAccess.file_exists(realm_json_path(pack_id, name)):
            out.append(name)
        name = dir.get_next()
    dir.list_dir_end()
    out.sort()
    return out


static func _legacy_realm_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "realm.json"


static func _legacy_regions_dir(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Regions/"


static func _legacy_region_json_path(pack_id: String, region_id: String) -> String:
    return _legacy_regions_dir(pack_id) + region_id + "/region.json"


static func _legacy_region_rooms_json_path(pack_id: String, region_id: String) -> String:
    return _legacy_regions_dir(pack_id) + region_id + "/rooms.json"


static func _load_pack_manifest(pack_id: String) -> Dictionary:
    for path in [
        "user://Packs/%s/Pack.json" % pack_id,
        "res://Content/%s/Pack.json" % pack_id,
        "res://Content/demo/Pack.json",
    ]:
        if FileAccess.file_exists(path):
            return _load_json_dict(path)
    return {}


static func _load_json_dict(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    return raw


static func _save_json(path: String, data: Dictionary) -> bool:
    var slash := path.rfind("/")
    if slash > 0:
        DirAccess.make_dir_recursive_absolute(path.substr(0, slash))
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("RegIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)
