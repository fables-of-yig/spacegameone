extends RefCounted

# Region IO.
#
# Pack layout:
#   Content/<pack>/Regions/<region_id>/region.json
#   Content/<pack>/Regions/<region_id>/rooms.json
#   Content/<pack>/Rooms/rooms.json   -- flat runtime view
#
# Runtime room addresses are flattened as:
#   <region_id>/<room_addr>

const EnvIO = preload("res://Space/scripts/shared/env/env_io.gd")
const SystemIO = preload("res://Space/scripts/shared/system_io.gd")
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")

const SCHEMA_VERSION: String = "3.0"
const DEFAULT_REGION_ID: String = "region_default"
const DEFAULT_REGION_NAME: String = "Default"
const DEFAULT_CELL_BLOCKS_X: int = 1
const DEFAULT_CELL_BLOCKS_Y: int = 1
const DEFAULT_REGION_GRID_X: int = 128
const DEFAULT_REGION_GRID_Y: int = 96
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
    return PackPaths.writable_pack_dir(pack_id)


static func regions_dir(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Regions/"


static func region_dir(pack_id: String, region_id: String) -> String:
    return regions_dir(pack_id) + region_id + "/"


static func region_json_path(pack_id: String, region_id: String) -> String:
    return region_dir(pack_id, region_id) + "region.json"


static func region_rooms_json_path(pack_id: String, region_id: String) -> String:
    return region_dir(pack_id, region_id) + "rooms.json"


static func region_variants_json_path(pack_id: String, region_id: String) -> String:
    return region_dir(pack_id, region_id) + "room_variants.json"


static func flat_rooms_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Rooms/rooms.json"


static func runtime_room_addr(region_id: String, room_addr: String) -> String:
    return "%s/%s" % [region_id, room_addr]


static func parse_room_addr(addr: String) -> Dictionary:
    var trimmed := addr.strip_edges()
    if trimmed.is_empty():
        return {"region_id": "", "room_addr": ""}
    var slash := trimmed.find("/")
    if slash < 0:
        return {"region_id": "", "room_addr": trimmed}
    return {
        "region_id": trimmed.substr(0, slash),
        "room_addr": trimmed.substr(slash + 1),
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
    ok = _ensure_starter_region(pid, files_changed) and ok
    ok = _ensure_starter_region_rooms(pid, files_changed) and ok

    _ensure_dir(user_pack_dir(pid) + "Rooms")
    ok = _write_json_if_changed(flat_rooms_json_path(pid), _build_flat_runtime_rooms(pid), files_changed) and ok

    return {
        "ok": ok,
        "pack_id": pid,
        "region_id": DEFAULT_REGION_ID,
        "room_addr": STARTER_ROOM_ADDR,
        "start_room": runtime_room_addr(DEFAULT_REGION_ID, STARTER_ROOM_ADDR),
        "files_changed": files_changed,
    }


static func list_regions(pack_id: String) -> Array:
    _ensure_pack_dirs(pack_id)
    _ensure_default_region(pack_id)

    var out: Array = []
    var root := regions_dir(pack_id)
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if dir.current_is_dir() and not name.begins_with("."):
            var region := _load_json_dict(region_json_path(pack_id, name))
            if region.is_empty():
                region = default_region(name, name.capitalize())
                _save_json(region_json_path(pack_id, name), region)
            out.append({
                "id": name,
                "name": str(region.get("name", name)),
            })
        name = dir.get_next()
    dir.list_dir_end()
    out.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("id", "")) < str(b.get("id", "")))
    return out


static func default_region_id(pack_id: String) -> String:
    var regions: Array = list_regions(pack_id)
    if not regions.is_empty():
        return str((regions[0] as Dictionary).get("id", DEFAULT_REGION_ID))
    return DEFAULT_REGION_ID


static func load_region(pack_id: String, region_id: String) -> Dictionary:
    _ensure_pack_dirs(pack_id)
    var rid := region_id.strip_edges()
    if rid.is_empty():
        rid = default_region_id(pack_id)
    var region := _load_json_dict(region_json_path(pack_id, rid))
    if region.is_empty():
        region = default_region(rid, rid.capitalize())
        _save_json(region_json_path(pack_id, rid), region)
    else:
        migrate_region_meta(region, rid, str(region.get("name", rid)))
    return region


static func save_region_meta(pack_id: String, region_id: String, region_meta: Dictionary) -> bool:
    _ensure_dir(region_dir(pack_id, region_id))
    migrate_region_meta(region_meta, region_id, str(region_meta.get("name", region_id)))
    return _save_json(region_json_path(pack_id, region_id), region_meta)


static func load_region_rooms(pack_id: String, region_id: String) -> Dictionary:
    _ensure_dir(region_dir(pack_id, region_id))
    var path := region_rooms_json_path(pack_id, region_id)
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


static func save_region_rooms(pack_id: String, region_id: String, rooms_data: Dictionary) -> bool:
    _ensure_dir(region_dir(pack_id, region_id))
    var ok := _save_json(region_rooms_json_path(pack_id, region_id), rooms_data)
    flatten_to_runtime(pack_id)
    return ok


# Loads Regions/<region>/room_variants.json. Returns the default shape
# (empty variants map) when the file is missing or malformed so callers can
# treat "no file" and "file with no rules" identically. The on-disk shape:
#
#   {
#     "version": "1.0",
#     "variants": {
#       "<canonical_room_id>": [
#         {
#           "when": { "scope": "planet"|"global", "flag": "<name>", "equals": <value> },
#           "use":  "<alternate_room_id>"
#         },
#         ...
#       ],
#       ...
#     }
#   }
#
# Variant resolution at room-load time walks each rule in order and returns
# the first `use` whose `when` matches the current PlanetaryInterface flag
# state — see MvRoomManager.resolve_room_addr (added in slice 2).
static func load_room_variants(pack_id: String, region_id: String) -> Dictionary:
    var path := region_variants_json_path(pack_id, region_id)
    if not FileAccess.file_exists(path):
        return default_room_variants(region_id)
    var data := _load_json_dict(path)
    if data.is_empty():
        return default_room_variants(region_id)
    if typeof(data.get("variants", null)) != TYPE_DICTIONARY:
        data["variants"] = {}
    if str(data.get("version", "")).is_empty():
        data["version"] = "1.0"
    return data


static func save_room_variants(pack_id: String, region_id: String, variants_data: Dictionary) -> bool:
    _ensure_dir(region_dir(pack_id, region_id))
    return _save_json(region_variants_json_path(pack_id, region_id), variants_data)


static func default_room_variants(region_id: String) -> Dictionary:
    return {
        "version": "1.0",
        "region_id": region_id,
        "variants": {},
    }


static func create_region(pack_id: String, region_id: String, region_name: String) -> bool:
    var rid: String = region_id.strip_edges()
    if rid.is_empty():
        return false
    if FileAccess.file_exists(region_json_path(pack_id, rid)):
        return true
    var display_name := region_name.strip_edges()
    if display_name.is_empty():
        display_name = rid.capitalize()
    var region_meta := default_region(rid, display_name)
    if not save_region_meta(pack_id, rid, region_meta):
        return false
    save_region_rooms(pack_id, rid, default_region_rooms(rid))
    return true


static func delete_region(pack_id: String, region_id: String) -> bool:
    var rid: String = region_id.strip_edges()
    if rid.is_empty():
        return false
    var regions: Array = list_regions(pack_id)
    if regions.size() <= 1:
        return false
    var path := region_dir(pack_id, rid)
    if not DirAccess.dir_exists_absolute(path):
        return false
    _remove_dir_recursive(path)
    _rewrite_poi_region_links(pack_id, rid, "", "", "")
    flatten_to_runtime(pack_id)
    return true


static func rename_region(pack_id: String, old_region_id: String, new_region_id: String,
        new_region_name: String = "") -> bool:
    var old_id := old_region_id.strip_edges()
    var new_id := new_region_id.strip_edges()
    if old_id.is_empty() or new_id.is_empty():
        return false
    var trimmed_name := new_region_name.strip_edges()

    if old_id == new_id:
        var same_meta := _load_json_dict(region_json_path(pack_id, old_id))
        if same_meta.is_empty():
            same_meta = default_region(old_id, trimmed_name if not trimmed_name.is_empty() else old_id)
        if not trimmed_name.is_empty():
            same_meta["name"] = trimmed_name
        migrate_region_meta(same_meta, old_id, str(same_meta.get("name", old_id)))
        if not _save_json(region_json_path(pack_id, old_id), same_meta):
            return false
        flatten_to_runtime(pack_id)
        return true

    if FileAccess.file_exists(region_json_path(pack_id, new_id)) \
            or DirAccess.dir_exists_absolute(region_dir(pack_id, new_id)):
        return false

    var region_meta := _load_json_dict(region_json_path(pack_id, old_id))
    if region_meta.is_empty():
        region_meta = default_region(new_id, trimmed_name if not trimmed_name.is_empty() else new_id)
    region_meta["id"] = new_id
    if not trimmed_name.is_empty():
        region_meta["name"] = trimmed_name
    migrate_region_meta(region_meta, new_id, str(region_meta.get("name", new_id)))

    var rooms_root := load_region_rooms(pack_id, old_id).duplicate(true)
    rooms_root["region_id"] = new_id

    var old_dir := region_dir(pack_id, old_id)
    var new_dir := region_dir(pack_id, new_id)
    if not DirAccess.dir_exists_absolute(old_dir):
        return false
    var rename_err := DirAccess.rename_absolute(old_dir, new_dir)
    if rename_err != OK:
        return false
    if not _save_json(region_json_path(pack_id, new_id), region_meta):
        return false
    if not _save_json(region_rooms_json_path(pack_id, new_id), rooms_root):
        return false

    _rewrite_poi_region_links(pack_id, old_id, new_id, "", "")
    flatten_to_runtime(pack_id)
    return true


static func rename_room(pack_id: String, region_id: String, old_room_addr: String,
        new_room_addr: String, new_room_name: String = "") -> bool:
    var trimmed_region_id := region_id.strip_edges()
    var old_addr := old_room_addr.strip_edges()
    var new_addr := new_room_addr.strip_edges()
    if trimmed_region_id.is_empty() or old_addr.is_empty() or new_addr.is_empty():
        return false
    var rooms_root := load_region_rooms(pack_id, trimmed_region_id).duplicate(true)
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
        if not _save_json(region_rooms_json_path(pack_id, trimmed_region_id), rooms_root):
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
    if not _save_json(region_rooms_json_path(pack_id, trimmed_region_id), rooms_root):
        return false

    _rewrite_poi_region_links(pack_id, trimmed_region_id, trimmed_region_id, old_addr, new_addr)
    flatten_to_runtime(pack_id)
    return true


static func flatten_to_runtime(pack_id: String) -> void:
    _ensure_dir(user_pack_dir(pack_id) + "Rooms")
    _save_json(flat_rooms_json_path(pack_id), _build_flat_runtime_rooms(pack_id))


static func _build_flat_runtime_rooms(pack_id: String) -> Dictionary:
    var pack_manifest: Dictionary = _load_pack_manifest(pack_id)
    var desired_start_region: String = str(pack_manifest.get("start_region", "")).strip_edges()

    var flat_rooms: Dictionary = {}
    var start_key: String = ""
    var regions: Array = list_regions(pack_id)
    for region_entry_v in regions:
        var region_entry: Dictionary = region_entry_v
        var region_id: String = str(region_entry.get("id", ""))
        if region_id.is_empty():
            continue
        var region_rooms := _load_json_dict(region_rooms_json_path(pack_id, region_id))
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
            _prefix_room_door_targets(room, region_id)
            room["region_id"] = region_id
            room["addr"] = runtime_room_addr(region_id, room_addr)
            flat_rooms[room["addr"]] = room
        var local_start := str(region_rooms.get("start_room", "")).strip_edges()
        if region_id == desired_start_region and not local_start.is_empty():
            start_key = runtime_room_addr(region_id, local_start)
        elif start_key.is_empty() and desired_start_region.is_empty() and not local_start.is_empty():
            start_key = runtime_room_addr(region_id, local_start)

    if start_key.is_empty() and not flat_rooms.is_empty():
        start_key = str(flat_rooms.keys()[0])

    return {
        "version": "5.0",
        "start_room": start_key,
        "rooms": flat_rooms,
    }


static func get_region_start_room(pack_id: String, region_id: String) -> String:
    if region_id.strip_edges().is_empty():
        return ""
    var rooms_root := load_region_rooms(pack_id, region_id)
    var room_addr: String = str(rooms_root.get("start_room", "")).strip_edges()
    if room_addr.is_empty():
        return ""
    return runtime_room_addr(region_id, room_addr)


static func migrate_region_meta(region: Dictionary, region_id: String, region_name: String) -> void:
    var defaults := default_region(region_id, region_name)
    for key in defaults.keys():
        if not region.has(key):
            region[key] = defaults[key]
    # Strip legacy mode-7 camera fields if present.
    region.erase("cam_height")
    region.erase("horizon")
    region.erase("fov_scale")
    region["version"] = "2.0"
    region["id"] = region_id
    if str(region.get("name", "")).strip_edges().is_empty():
        region["name"] = region_name


static func default_region(region_id: String, region_name: String) -> Dictionary:
    return {
        "version": "2.0",
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


static func _ensure_default_region(pack_id: String) -> void:
    if FileAccess.file_exists(region_json_path(pack_id, DEFAULT_REGION_ID)):
        return
    var any_region_exists: bool = false
    var root := regions_dir(pack_id)
    var dir := DirAccess.open(root)
    if dir != null:
        dir.list_dir_begin()
        var name := dir.get_next()
        while name != "":
            if dir.current_is_dir() and not name.begins_with("."):
                if FileAccess.file_exists(region_json_path(pack_id, name)):
                    any_region_exists = true
                    break
            name = dir.get_next()
        dir.list_dir_end()
    if any_region_exists:
        return
    create_region(pack_id, DEFAULT_REGION_ID, DEFAULT_REGION_NAME)


static func _ensure_starter_region(pack_id: String, files_changed: Array) -> bool:
    var path := region_json_path(pack_id, DEFAULT_REGION_ID)
    var region := _starter_region()
    if FileAccess.file_exists(path):
        region = _load_json_dict(path)
        if region.is_empty():
            region = _starter_region()
        else:
            migrate_region_meta(region, DEFAULT_REGION_ID, str(region.get("name", DEFAULT_REGION_NAME)))
    return _write_json_if_changed(path, region, files_changed)


static func _ensure_starter_region_rooms(pack_id: String, files_changed: Array) -> bool:
    var path := region_rooms_json_path(pack_id, DEFAULT_REGION_ID)
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


static func _starter_region() -> Dictionary:
    return default_region(DEFAULT_REGION_ID, DEFAULT_REGION_NAME)


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


static func _ensure_pack_dirs(pack_id: String) -> void:
    _ensure_dir(user_pack_dir(pack_id))
    _ensure_dir(regions_dir(pack_id))


static func _prefix_room_door_targets(room: Dictionary, region_id: String) -> void:
    var doors_v: Variant = room.get("doors", [])
    if typeof(doors_v) != TYPE_ARRAY:
        return
    for door_v in doors_v:
        if typeof(door_v) != TYPE_DICTIONARY:
            continue
        var door: Dictionary = door_v
        door["target_room"] = _prefix_room_ref(str(door.get("target_room", "")), region_id)
        var dests_v: Variant = door.get("destinations", [])
        if typeof(dests_v) != TYPE_ARRAY:
            continue
        for dest_v in dests_v:
            if typeof(dest_v) != TYPE_DICTIONARY:
                continue
            var dest: Dictionary = dest_v
            dest["target"] = _prefix_room_ref(str(dest.get("target", "")), region_id)


static func _prefix_room_ref(target: String, region_id: String) -> String:
    var trimmed := target.strip_edges()
    if trimmed.is_empty():
        return ""
    if trimmed.find("/") >= 0:
        return trimmed
    return runtime_room_addr(region_id, trimmed)


static func _rewrite_poi_region_links(pack_id: String, old_region_id: String, new_region_id: String,
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
            var regions_v: Variant = planet_data.get("regions", [])
            if typeof(regions_v) != TYPE_ARRAY:
                continue
            var regions: Array = regions_v
            var poi_changed := false
            var kept: Array = []
            for entry_v in regions:
                if typeof(entry_v) != TYPE_DICTIONARY:
                    continue
                var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
                var entry_region := str(entry.get("id", "")).strip_edges()
                if entry_region == old_region_id:
                    if new_region_id.is_empty():
                        # Region deleted; drop the link entirely.
                        poi_changed = true
                        continue
                    entry["id"] = new_region_id
                    poi_changed = true
                    if not old_room_addr.is_empty() and str(entry.get("spawn_room", "")).strip_edges() == old_room_addr:
                        entry["spawn_room"] = new_room_addr
                kept.append(entry)
            if poi_changed:
                planet_data["regions"] = kept
                poi["planet_data"] = planet_data
                pois[i] = poi
                sys_changed = true
        if sys_changed:
            sys["pois"] = pois
            systems[sid] = sys
            changed = true
    if changed:
        SystemIO.save(pack_id, systems)


static func _load_pack_manifest(pack_id: String) -> Dictionary:
    for path in [
        PackPaths.writable_pack_file(pack_id, "Pack.json"),
        PackPaths.shipped_pack_file(pack_id, "Pack.json"),
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
