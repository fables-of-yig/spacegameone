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
const SystemIO = preload("res://Space/scripts/editor/system_io.gd")

const SCHEMA_VERSION: String = "2.0"
const DEFAULT_REALM_ID: String = "realm_main"
const DEFAULT_REALM_NAME: String = "Main"
const DEFAULT_REGION_ID: String = "region_default"
const DEFAULT_CELL_BLOCKS_X: int = 1
const DEFAULT_CELL_BLOCKS_Y: int = 1
const DEFAULT_REGION_GRID_X: int = 128
const DEFAULT_REGION_GRID_Y: int = 96
const DEFAULT_REALM_GRID_X: int = 102
const DEFAULT_REALM_GRID_Y: int = 102
const STARTER_ROOM_ADDR: String = "start"
const STARTER_ROOM_NAME: String = "Start Room"
const STARTER_SOLID_BLOCK: int = 0x8


static func sanitize_content_id(raw_name: String, fallback: String = "item") -> String:
    var source := raw_name.strip_edges()
    if source.is_empty():
        source = fallback.strip_edges()
    var lower := source.to_lower()
    var out := ""
    var last_sep := false
    for i in range(lower.length()):
        var ch := lower.substr(i, 1)
        var code := ch.unicode_at(0)
        var is_ascii_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
        if is_ascii_alnum:
            out += ch
            last_sep = false
        elif ch == "_" or ch == "-" or ch == " ":
            if not out.is_empty() and not last_sep:
                out += "_"
                last_sep = true
    while out.begins_with("_"):
        out = out.substr(1)
    while out.ends_with("_"):
        out = out.substr(0, out.length() - 1)
    if out.is_empty():
        var fallback_id := fallback.to_lower().replace(" ", "_")
        return fallback_id if not fallback_id.strip_edges().is_empty() else "item"
    return out


static func unique_content_id(raw_name: String, used_ids: Dictionary, fallback: String = "item",
        exclude_id: String = "") -> String:
    var base_id := sanitize_content_id(raw_name, fallback)
    var candidate := base_id
    var suffix := 2
    var excluded := exclude_id.strip_edges()
    while used_ids.has(candidate) and candidate != excluded:
        candidate = "%s_%d" % [base_id, suffix]
        suffix += 1
    return candidate


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


static func flat_rooms_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Rooms/rooms.json"


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


static func ensure_starter_world(pack_id: String) -> Dictionary:
    var pid: String = pack_id.strip_edges()
    var files_changed: Array = []
    if pid.is_empty():
        return {
            "ok": false,
            "error": "pack_id_empty",
            "files_changed": files_changed,
        }

    _ensure_pack_dirs(pid)

    var ok := true
    ok = _ensure_starter_realm(pid, files_changed) and ok
    ok = _ensure_starter_region(pid, files_changed) and ok
    ok = _ensure_starter_region_rooms(pid, files_changed) and ok

    _ensure_dir(user_pack_dir(pid) + "Rooms")
    ok = _write_json_if_changed(flat_rooms_json_path(pid), _build_flat_runtime_rooms(pid), files_changed) and ok

    return {
        "ok": ok,
        "pack_id": pid,
        "realm_id": DEFAULT_REALM_ID,
        "region_id": DEFAULT_REGION_ID,
        "room_addr": STARTER_ROOM_ADDR,
        "start_room": runtime_room_addr(DEFAULT_REALM_ID, DEFAULT_REGION_ID, STARTER_ROOM_ADDR),
        "files_changed": files_changed,
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
    var initial_region_name := "Region 1"
    var initial_region_id := sanitize_content_id(initial_region_name, "region")
    realm["start_region"] = initial_region_id
    realm["regions"] = [
        {
            "id": initial_region_id,
            "name": initial_region_name,
            "col": 0,
            "row": 0,
            "span_w": 1,
            "span_h": 1,
        },
    ]
    var ok := save_realm(pack_id, rid, realm)
    if not ok:
        return false
    var region_meta := default_region(initial_region_id, initial_region_name)
    save_region_meta(pack_id, rid, initial_region_id, region_meta)
    save_region_rooms(pack_id, rid, initial_region_id, default_region_rooms(initial_region_id))
    return true


static func delete_realm(pack_id: String, realm_id: String) -> bool:
    var rid: String = realm_id.strip_edges()
    if rid.is_empty():
        return false
    var realms: Array = list_realms(pack_id)
    if realms.size() <= 1:
        return false
    var path := realm_dir(pack_id, rid)
    if not DirAccess.dir_exists_absolute(path):
        return false
    _remove_dir_recursive(path)
    flatten_to_runtime(pack_id)
    return true


static func delete_region(pack_id: String, realm_id: String, region_id: String) -> bool:
    var trimmed_realm_id: String = realm_id.strip_edges()
    var trimmed_region_id: String = region_id.strip_edges()
    if trimmed_realm_id.is_empty() or trimmed_region_id.is_empty():
        return false

    var bundle := load_realm_bundle(pack_id, trimmed_realm_id)
    var realm: Dictionary = bundle.get("realm", {})
    var regions: Array = realm.get("regions", [])
    if regions.size() <= 1:
        return false

    var kept: Array = []
    var removed: bool = false
    var fallback_region_id: String = ""
    for entry_v in regions:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
        var entry_id: String = str(entry.get("id", "")).strip_edges()
        if entry_id == trimmed_region_id:
            removed = true
            continue
        kept.append(entry)
        if fallback_region_id.is_empty():
            fallback_region_id = entry_id
    if not removed or kept.is_empty():
        return false

    realm["regions"] = kept
    if str(realm.get("start_region", "")).strip_edges() == trimmed_region_id:
        realm["start_region"] = fallback_region_id
    if not save_realm(pack_id, trimmed_realm_id, realm):
        return false

    var path := region_dir(pack_id, trimmed_realm_id, trimmed_region_id)
    if DirAccess.dir_exists_absolute(path):
        _remove_dir_recursive(path)
    flatten_to_runtime(pack_id)
    return true


static func rename_realm(pack_id: String, old_realm_id: String, new_realm_id: String,
        new_realm_name: String = "") -> bool:
    var old_id := old_realm_id.strip_edges()
    var new_id := new_realm_id.strip_edges()
    if old_id.is_empty() or new_id.is_empty():
        return false
    var trimmed_name := new_realm_name.strip_edges()
    if old_id == new_id:
        var same_bundle := load_realm_bundle(pack_id, old_id)
        var same_realm: Dictionary = same_bundle.get("realm", {}).duplicate(true)
        if same_realm.is_empty():
            return false
        if not trimmed_name.is_empty():
            same_realm["realm_name"] = trimmed_name
        return save_realm(pack_id, old_id, same_realm)
    if FileAccess.file_exists(realm_json_path(pack_id, new_id)) or DirAccess.dir_exists_absolute(realm_dir(pack_id, new_id)):
        return false

    var bundle := load_realm_bundle(pack_id, old_id)
    var realm: Dictionary = bundle.get("realm", {}).duplicate(true)
    if realm.is_empty():
        return false
    if not trimmed_name.is_empty():
        realm["realm_name"] = trimmed_name
    _migrate_realm_meta(realm, new_id)

    var old_dir := realm_dir(pack_id, old_id)
    var new_dir := realm_dir(pack_id, new_id)
    if not DirAccess.dir_exists_absolute(old_dir):
        return false
    var rename_err := DirAccess.rename_absolute(old_dir, new_dir)
    if rename_err != OK:
        return false
    if not _save_json(realm_json_path(pack_id, new_id), realm):
        return false

    _rewrite_pack_start_realm(pack_id, old_id, new_id)
    _rewrite_system_planet_links(pack_id, old_id, new_id)
    flatten_to_runtime(pack_id)
    return true


static func rename_region(pack_id: String, realm_id: String, old_region_id: String, new_region_id: String,
        new_region_name: String = "") -> bool:
    var trimmed_realm_id := realm_id.strip_edges()
    var old_id := old_region_id.strip_edges()
    var new_id := new_region_id.strip_edges()
    if trimmed_realm_id.is_empty() or old_id.is_empty() or new_id.is_empty():
        return false
    var trimmed_name := new_region_name.strip_edges()
    if old_id == new_id:
        var same_bundle := load_realm_bundle(pack_id, trimmed_realm_id)
        var same_realm: Dictionary = same_bundle.get("realm", {}).duplicate(true)
        var same_regions: Array = same_realm.get("regions", [])
        var found_same := false
        for i in range(same_regions.size()):
            if typeof(same_regions[i]) != TYPE_DICTIONARY:
                continue
            var same_entry: Dictionary = (same_regions[i] as Dictionary).duplicate(true)
            if str(same_entry.get("id", "")).strip_edges() != old_id:
                continue
            if not trimmed_name.is_empty():
                same_entry["name"] = trimmed_name
            same_regions[i] = same_entry
            found_same = true
            break
        if not found_same:
            return false
        same_realm["regions"] = same_regions
        if not _save_json(realm_json_path(pack_id, trimmed_realm_id), same_realm):
            return false
        var same_meta := _load_json_dict(region_json_path(pack_id, trimmed_realm_id, old_id))
        if same_meta.is_empty():
            same_meta = default_region(old_id, trimmed_name if not trimmed_name.is_empty() else old_id)
        if not trimmed_name.is_empty():
            same_meta["name"] = trimmed_name
        migrate_region_meta(same_meta, old_id, str(same_meta.get("name", old_id)))
        if not _save_json(region_json_path(pack_id, trimmed_realm_id, old_id), same_meta):
            return false
        flatten_to_runtime(pack_id)
        return true
    if FileAccess.file_exists(region_json_path(pack_id, trimmed_realm_id, new_id)) \
            or DirAccess.dir_exists_absolute(region_dir(pack_id, trimmed_realm_id, new_id)):
        return false

    var bundle := load_realm_bundle(pack_id, trimmed_realm_id)
    var realm: Dictionary = bundle.get("realm", {}).duplicate(true)
    var regions: Array = realm.get("regions", [])
    var found := false
    for i in range(regions.size()):
        if typeof(regions[i]) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = (regions[i] as Dictionary).duplicate(true)
        if str(entry.get("id", "")).strip_edges() != old_id:
            continue
        entry["id"] = new_id
        if not trimmed_name.is_empty():
            entry["name"] = trimmed_name
        regions[i] = entry
        found = true
        break
    if not found:
        return false
    realm["regions"] = regions
    if str(realm.get("start_region", "")).strip_edges() == old_id:
        realm["start_region"] = new_id
    _migrate_realm_meta(realm, trimmed_realm_id)

    var region_meta := _load_json_dict(region_json_path(pack_id, trimmed_realm_id, old_id))
    if region_meta.is_empty():
        region_meta = default_region(new_id, trimmed_name if not trimmed_name.is_empty() else new_id)
    if not trimmed_name.is_empty():
        region_meta["name"] = trimmed_name
    migrate_region_meta(region_meta, new_id, str(region_meta.get("name", new_id)))

    var rooms_root := load_region_rooms(pack_id, trimmed_realm_id, old_id).duplicate(true)
    rooms_root["region_id"] = new_id

    var old_dir := region_dir(pack_id, trimmed_realm_id, old_id)
    var new_dir := region_dir(pack_id, trimmed_realm_id, new_id)
    if not DirAccess.dir_exists_absolute(old_dir):
        return false
    var rename_err := DirAccess.rename_absolute(old_dir, new_dir)
    if rename_err != OK:
        return false
    if not _save_json(realm_json_path(pack_id, trimmed_realm_id), realm):
        return false
    if not _save_json(region_json_path(pack_id, trimmed_realm_id, new_id), region_meta):
        return false
    if not _save_json(region_rooms_json_path(pack_id, trimmed_realm_id, new_id), rooms_root):
        return false

    _rewrite_system_planet_links(pack_id, trimmed_realm_id, trimmed_realm_id, old_id, new_id)
    flatten_to_runtime(pack_id)
    return true


static func rename_room(pack_id: String, realm_id: String, region_id: String, old_room_addr: String,
        new_room_addr: String, new_room_name: String = "") -> bool:
    var trimmed_realm_id := realm_id.strip_edges()
    var trimmed_region_id := region_id.strip_edges()
    var old_addr := old_room_addr.strip_edges()
    var new_addr := new_room_addr.strip_edges()
    if trimmed_realm_id.is_empty() or trimmed_region_id.is_empty() or old_addr.is_empty() or new_addr.is_empty():
        return false
    var rooms_root := load_region_rooms(pack_id, trimmed_realm_id, trimmed_region_id).duplicate(true)
    var rooms_v: Variant = rooms_root.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return false
    var rooms: Dictionary = rooms_v
    if not rooms.has(old_addr):
        return false
    var trimmed_name := new_room_name.strip_edges()
    if old_addr == new_addr:
        var same_room: Dictionary = (rooms[old_addr] as Dictionary).duplicate(true)
        if not trimmed_name.is_empty():
            same_room["friendly_name"] = trimmed_name
        rooms[old_addr] = same_room
        rooms_root["rooms"] = rooms
        if not _save_json(region_rooms_json_path(pack_id, trimmed_realm_id, trimmed_region_id), rooms_root):
            return false
        flatten_to_runtime(pack_id)
        return true
    if rooms.has(new_addr):
        return false

    var room: Dictionary = (rooms[old_addr] as Dictionary).duplicate(true)
    room["addr"] = new_addr
    if not trimmed_name.is_empty():
        room["friendly_name"] = trimmed_name
    rooms[new_addr] = room
    rooms.erase(old_addr)
    if str(rooms_root.get("start_room", "")).strip_edges() == old_addr:
        rooms_root["start_room"] = new_addr
    for room_key_v in rooms.keys():
        var room_key := str(room_key_v)
        var other_v: Variant = rooms[room_key]
        if typeof(other_v) != TYPE_DICTIONARY:
            continue
        var other: Dictionary = other_v
        var doors_v: Variant = other.get("doors", [])
        if typeof(doors_v) != TYPE_ARRAY:
            continue
        for door_v in doors_v:
            if typeof(door_v) != TYPE_DICTIONARY:
                continue
            var door: Dictionary = door_v
            if str(door.get("target_room", "")).strip_edges() == old_addr:
                door["target_room"] = new_addr
    rooms_root["rooms"] = rooms
    if not _save_json(region_rooms_json_path(pack_id, trimmed_realm_id, trimmed_region_id), rooms_root):
        return false

    _rewrite_system_planet_links(pack_id, trimmed_realm_id, trimmed_realm_id,
        trimmed_region_id, trimmed_region_id, old_addr, new_addr)
    flatten_to_runtime(pack_id)
    return true


static func flatten_to_runtime(pack_id: String) -> void:
    _ensure_dir(user_pack_dir(pack_id) + "Rooms")
    _save_json(flat_rooms_json_path(pack_id), _build_flat_runtime_rooms(pack_id))


static func _build_flat_runtime_rooms(pack_id: String) -> Dictionary:
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
    return flat


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
        "sky_preset": "midnight",
        "sky_top_color": "#050814",
        "sky_bottom_color": "#152743",
        "realm_tile_layers": [
            {"name": "Ground", "tiles": [], "animations": {}},
            {"name": "Structure", "tiles": [], "animations": {}},
            {"name": "Sky", "tiles": [], "animations": {}},
        ],
        "regions": [
            {
                "id": DEFAULT_REGION_ID,
                "name": "Default",
                "col": 0,
                "row": 0,
                "span_w": 1,
                "span_h": 1,
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


static func _ensure_starter_realm(pack_id: String, files_changed: Array) -> bool:
    var path := realm_json_path(pack_id, DEFAULT_REALM_ID)
    if not FileAccess.file_exists(path):
        return _write_json_if_changed(path, _starter_realm(), files_changed)

    var realm := _load_json_dict(path)
    if realm.is_empty():
        realm = _starter_realm()
    else:
        _migrate_realm_meta(realm, DEFAULT_REALM_ID)
        var regions: Array = []
        var regions_v: Variant = realm.get("regions", [])
        if typeof(regions_v) == TYPE_ARRAY:
            regions = (regions_v as Array).duplicate(true)
        var has_default_region := false
        for entry_v in regions:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            if str((entry_v as Dictionary).get("id", "")).strip_edges() == DEFAULT_REGION_ID:
                has_default_region = true
                break
        if not has_default_region:
            var free_cell := _first_free_realm_cell(regions,
                int(realm.get("realm_grid_cells_x", DEFAULT_REALM_GRID_X)),
                int(realm.get("realm_grid_cells_y", DEFAULT_REALM_GRID_Y)))
            regions.append(_starter_region_entry(DEFAULT_REGION_ID, "Default", int(free_cell[0]), int(free_cell[1])))
            realm["regions"] = regions
        if str(realm.get("start_region", "")).strip_edges().is_empty():
            realm["start_region"] = DEFAULT_REGION_ID

    return _write_json_if_changed(path, realm, files_changed)


static func _ensure_starter_region(pack_id: String, files_changed: Array) -> bool:
    var path := region_json_path(pack_id, DEFAULT_REALM_ID, DEFAULT_REGION_ID)
    var region := _starter_region()
    if FileAccess.file_exists(path):
        region = _load_json_dict(path)
        if region.is_empty():
            region = _starter_region()
        else:
            migrate_region_meta(region, DEFAULT_REGION_ID, str(region.get("name", "Default")))
    return _write_json_if_changed(path, region, files_changed)


static func _ensure_starter_region_rooms(pack_id: String, files_changed: Array) -> bool:
    var path := region_rooms_json_path(pack_id, DEFAULT_REALM_ID, DEFAULT_REGION_ID)
    if not FileAccess.file_exists(path):
        return _write_json_if_changed(path, _starter_region_rooms(), files_changed)

    var rooms_root := _load_json_dict(path)
    if rooms_root.is_empty():
        rooms_root = _starter_region_rooms()
    else:
        rooms_root["version"] = str(rooms_root.get("version", "1.0"))
        rooms_root["region_id"] = DEFAULT_REGION_ID
        var rooms: Dictionary = {}
        var rooms_v: Variant = rooms_root.get("rooms", {})
        if typeof(rooms_v) == TYPE_DICTIONARY:
            rooms = rooms_v
        if rooms.is_empty():
            rooms[STARTER_ROOM_ADDR] = _starter_room()
            rooms_root["start_room"] = STARTER_ROOM_ADDR
        else:
            for room_key_v in rooms.keys():
                var room_v: Variant = rooms[room_key_v]
                if typeof(room_v) == TYPE_DICTIONARY:
                    EnvIO.migrate_room_to_layers(room_v)
            var start_room: String = str(rooms_root.get("start_room", "")).strip_edges()
            if start_room.is_empty() or not rooms.has(start_room):
                var room_keys: Array = rooms.keys()
                room_keys.sort()
                rooms_root["start_room"] = str(room_keys[0])
        rooms_root["rooms"] = rooms

    return _write_json_if_changed(path, rooms_root, files_changed)


static func _starter_realm() -> Dictionary:
    var realm := default_realm(DEFAULT_REALM_ID, DEFAULT_REALM_NAME)
    realm["start_region"] = DEFAULT_REGION_ID
    realm["regions"] = [
        _starter_region_entry(DEFAULT_REGION_ID, "Default", 0, 0),
    ]
    return realm


static func _starter_region_entry(region_id: String, region_name: String, col: int, row: int) -> Dictionary:
    return {
        "id": region_id,
        "name": region_name,
        "col": col,
        "row": row,
        "span_w": 1,
        "span_h": 1,
    }


static func _starter_region() -> Dictionary:
    return default_region(DEFAULT_REGION_ID, "Default")


static func _starter_region_rooms() -> Dictionary:
    var rooms_root := default_region_rooms(DEFAULT_REGION_ID)
    rooms_root["start_room"] = STARTER_ROOM_ADDR
    var rooms: Dictionary = {}
    rooms[STARTER_ROOM_ADDR] = _starter_room()
    rooms_root["rooms"] = rooms
    return rooms_root


static func _starter_room() -> Dictionary:
    var room := make_room_from_mask(STARTER_ROOM_ADDR, STARTER_ROOM_NAME,
        _rect_mask(EnvIO.DEFAULT_ROOM_W_BLOCKS, EnvIO.DEFAULT_ROOM_H_BLOCKS),
        0, 0, DEFAULT_CELL_BLOCKS_X, DEFAULT_CELL_BLOCKS_Y, 0)
    room["entities"] = [_starter_player_spawn()]
    _paint_starter_floor(room)
    return room


static func _starter_player_spawn() -> Dictionary:
    var spawn_x := float(EnvIO.BLOCK_SIZE * 5)
    var spawn_y := float(EnvIO.BLOCK_SIZE * (EnvIO.DEFAULT_ROOM_H_BLOCKS - 4))
    return {
        "type": "player_spawn",
        "x": spawn_x,
        "y": spawn_y,
        "position": {
            "x": spawn_x,
            "y": spawn_y,
        },
        "properties": {
            "instance_id": "player_spawn",
        },
    }


static func _paint_starter_floor(room: Dictionary) -> void:
    var collision_v: Variant = room.get("collision", [])
    if typeof(collision_v) != TYPE_ARRAY:
        return
    var collision: Array = collision_v
    var start_row: int = maxi(0, collision.size() - 2)
    for row_idx in range(start_row, collision.size()):
        var row_v: Variant = collision[row_idx]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row: Array = row_v
        for col_idx in range(row.size()):
            row[col_idx] = STARTER_SOLID_BLOCK


static func _rect_mask(width_cells: int, height_cells: int) -> Array:
    var mask: Array = []
    for row in range(maxi(1, height_cells)):
        for col in range(maxi(1, width_cells)):
            mask.append([col, row])
    return mask


static func _first_free_realm_cell(regions: Array, grid_x: int, grid_y: int) -> Array:
    var occupied: Dictionary = {}
    for entry_v in regions:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var col := int(entry.get("col", 0))
        var row := int(entry.get("row", 0))
        occupied["%d,%d" % [col, row]] = true
    for row in range(maxi(1, grid_y)):
        for col in range(maxi(1, grid_x)):
            if not occupied.has("%d,%d" % [col, row]):
                return [col, row]
    return [0, 0]


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
    realm["realm_grid_cells_x"] = maxi(1, int(realm.get("realm_grid_cells_x", DEFAULT_REALM_GRID_X)))
    realm["realm_grid_cells_y"] = maxi(1, int(realm.get("realm_grid_cells_y", DEFAULT_REALM_GRID_Y)))
    realm["sky_preset"] = str(realm.get("sky_preset", "midnight")).strip_edges()
    realm["sky_top_color"] = str(realm.get("sky_top_color", "#050814")).strip_edges()
    realm["sky_bottom_color"] = str(realm.get("sky_bottom_color", "#152743")).strip_edges()
    var normalized_layers: Array = []
    var layers_v: Variant = realm.get("realm_tile_layers", [])
    if typeof(layers_v) == TYPE_ARRAY:
        for layer_v in layers_v:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = (layer_v as Dictionary).duplicate(true)
            if typeof(layer.get("tiles", [])) != TYPE_ARRAY:
                layer["tiles"] = []
            if typeof(layer.get("animations", {})) != TYPE_DICTIONARY:
                layer["animations"] = {}
            normalized_layers.append(layer)
    while normalized_layers.size() < 3:
        normalized_layers.append((defaults.get("realm_tile_layers", [])[normalized_layers.size()] as Dictionary).duplicate(true))
    realm["realm_tile_layers"] = normalized_layers
    var normalized_regions: Array = []
    var regions_v: Variant = realm.get("regions", [])
    if typeof(regions_v) == TYPE_ARRAY:
        for entry_v in regions_v:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
            entry["col"] = int(entry.get("col", 0))
            entry["row"] = int(entry.get("row", 0))
            entry["span_w"] = maxi(1, int(entry.get("span_w", 1)))
            entry["span_h"] = maxi(1, int(entry.get("span_h", 1)))
            normalized_regions.append(entry)
    if normalized_regions.is_empty():
        var default_regions: Array = defaults.get("regions", [])
        normalized_regions = default_regions.duplicate(true)
    realm["regions"] = normalized_regions
    var start_region_id := str(realm.get("start_region", "")).strip_edges()
    if start_region_id.is_empty():
        realm["start_region"] = str((normalized_regions[0] as Dictionary).get("id", DEFAULT_REGION_ID))


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


static func _rewrite_pack_start_realm(pack_id: String, old_realm_id: String, new_realm_id: String) -> void:
    var manifest := _load_pack_manifest(pack_id)
    if manifest.is_empty():
        return
    if str(manifest.get("start_realm", "")).strip_edges() != old_realm_id:
        return
    manifest["start_realm"] = new_realm_id
    _save_json(user_pack_dir(pack_id) + "Pack.json", manifest)


static func _rewrite_system_planet_links(pack_id: String, old_realm_id: String, new_realm_id: String,
        old_region_id: String = "", new_region_id: String = "",
        old_room_addr: String = "", new_room_addr: String = "") -> void:
    var systems := SystemIO.load_or_init(pack_id)
    if systems.is_empty():
        return
    var changed := false
    for sid_v in systems.keys():
        var sid := str(sid_v)
        var sys_v: Variant = systems[sid]
        if typeof(sys_v) != TYPE_DICTIONARY:
            continue
        var sys: Dictionary = sys_v
        var pois_v: Variant = sys.get("pois", [])
        if typeof(pois_v) != TYPE_ARRAY:
            continue
        var pois: Array = pois_v
        var sys_changed := false
        for i in range(pois.size()):
            if typeof(pois[i]) != TYPE_DICTIONARY:
                continue
            var poi: Dictionary = pois[i]
            var planet_data_v: Variant = poi.get("planet_data", null)
            if typeof(planet_data_v) != TYPE_DICTIONARY:
                continue
            var planet_data: Dictionary = planet_data_v
            var target_pack := str(planet_data.get("pack_id", pack_id)).strip_edges()
            if target_pack.is_empty():
                target_pack = pack_id
            if target_pack != pack_id:
                continue
            var poi_changed := false
            if not old_realm_id.is_empty() and str(planet_data.get("realm_id", "")).strip_edges() == old_realm_id:
                planet_data["realm_id"] = new_realm_id
                poi_changed = true
            var spawn_room := str(planet_data.get("spawn_room", "")).strip_edges()
            var rewritten_spawn := _rewrite_room_reference(spawn_room,
                old_realm_id, new_realm_id, old_region_id, new_region_id, old_room_addr, new_room_addr)
            if rewritten_spawn != spawn_room:
                planet_data["spawn_room"] = rewritten_spawn
                poi_changed = true
            if poi_changed:
                poi["planet_data"] = planet_data
                pois[i] = poi
                sys_changed = true
        if sys_changed:
            sys["pois"] = pois
            systems[sid] = sys
            changed = true
    if changed:
        SystemIO.save(pack_id, systems)


static func _rewrite_room_reference(reference: String, old_realm_id: String, new_realm_id: String,
        old_region_id: String, new_region_id: String,
        old_room_addr: String, new_room_addr: String) -> String:
    var trimmed := reference.strip_edges()
    if trimmed.is_empty():
        return ""
    var parts := trimmed.split("/", false)
    if parts.size() == 1:
        if not old_room_addr.is_empty() and parts[0] == old_room_addr and not new_room_addr.is_empty():
            return new_room_addr
        return trimmed
    if parts.size() == 2:
        var region_part := str(parts[0]).strip_edges()
        var room_part := str(parts[1]).strip_edges()
        var changed := false
        if not old_region_id.is_empty() and region_part == old_region_id and not new_region_id.is_empty():
            region_part = new_region_id
            changed = true
        if not old_room_addr.is_empty() and room_part == old_room_addr and not new_room_addr.is_empty():
            room_part = new_room_addr
            changed = true
        if changed:
            return "%s/%s" % [region_part, room_part]
        return trimmed
    var realm_part := str(parts[0]).strip_edges()
    var region_part := str(parts[1]).strip_edges()
    var room_part := str(parts[2]).strip_edges()
    var changed := false
    if not old_realm_id.is_empty() and realm_part == old_realm_id and not new_realm_id.is_empty():
        realm_part = new_realm_id
        changed = true
    if not old_region_id.is_empty() and region_part == old_region_id and not new_region_id.is_empty():
        region_part = new_region_id
        changed = true
    if not old_room_addr.is_empty() and room_part == old_room_addr and not new_room_addr.is_empty():
        room_part = new_room_addr
        changed = true
    if not changed:
        return trimmed
    parts[0] = realm_part
    parts[1] = region_part
    parts[2] = room_part
    return "/".join(parts)


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


static func _write_json_if_changed(path: String, data: Dictionary, files_changed: Array) -> bool:
    if FileAccess.file_exists(path):
        var existing := _load_json_dict(path)
        if existing == data:
            return true
    if not _save_json(path, data):
        return false
    files_changed.append(path)
    return true


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)


static func _remove_dir_recursive(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var entry := dir.get_next()
        if entry.is_empty():
            break
        var full := path.rstrip("/") + "/" + entry
        if dir.current_is_dir():
            _remove_dir_recursive(full)
        else:
            DirAccess.remove_absolute(full)
    dir.list_dir_end()
    DirAccess.remove_absolute(path)
