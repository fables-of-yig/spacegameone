extends RefCounted

const SHIPPED_SEED_PACK: String = "demo"
const FILE_NAME: String = "systems.json"
const FOLDER: String = "Systems"
const LEGACY_ATLAS_PATH: String = "res://Space/data/systems/sector_atlas.json"
const STARTER_SYSTEM_ID: String = "start"
const STARTER_PLANET_NAME: String = "Starter Planet"
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")


static func user_file(pack_id: String) -> String:
    return PackPaths.writable_pack_file(pack_id, "%s/%s" % [FOLDER, FILE_NAME])


static func shipped_file(pack_id: String) -> String:
    return "res://Content/%s/%s/%s" % [pack_id, FOLDER, FILE_NAME]


static func demo_file() -> String:
    return "res://Content/%s/%s/%s" % [SHIPPED_SEED_PACK, FOLDER, FILE_NAME]


static func load_or_init(pack_id: String) -> Dictionary:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        pid = SHIPPED_SEED_PACK
    for path in [user_file(pid), shipped_file(pid), demo_file(), LEGACY_ATLAS_PATH]:
        var data := _read_systems(path)
        if not data.is_empty():
            return data
    return {}


static func load_existing(pack_id: String) -> Dictionary:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return {}
    for path in [user_file(pid), shipped_file(pid)]:
        var data := _read_systems_strict(path)
        if not data.is_empty():
            return data
    return {}


static func ensure_starter_system(pack_id: String, region_id: String,
        room_addr: String) -> String:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return ""

    var systems := load_existing(pid)
    var system_v: Variant = systems.get(STARTER_SYSTEM_ID, null)
    var system_data: Dictionary = {}
    if typeof(system_v) == TYPE_DICTIONARY:
        system_data = (system_v as Dictionary).duplicate(true)
    else:
        system_data = _starter_system(pid, region_id, room_addr)

    _ensure_starter_planet(system_data, pid, region_id, room_addr)
    systems[STARTER_SYSTEM_ID] = system_data

    if not save(pid, systems):
        return ""
    return STARTER_SYSTEM_ID


static func save(pack_id: String, systems: Dictionary) -> bool:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return false
    var path := user_file(pid)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify({"systems": systems}, "\t"))
    file.close()
    return true


static func exists(pack_id: String) -> bool:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return false
    for path in [user_file(pid), shipped_file(pid)]:
        if FileAccess.file_exists(path):
            return true
    return false


static func _starter_system(pack_id: String, region_id: String,
        room_addr: String) -> Dictionary:
    return {
        "name": "Start System",
        "position": [500, 500],
        "star_class": "G",
        "star_color": [1.0, 0.96, 0.78],
        "star_size": 60,
        "star_sprite": "",
        "star_anim_frames": 1,
        "star_anim_fps": 0.0,
        "star_gravity": 0,
        "background_image": "",
        "description": "Campaign starting system.",
        "threat_level": 1,
        "faction": "independent",
        "connections": [],
        "pois": [_starter_planet_poi(pack_id, region_id, room_addr)],
        "placed_npcs": [],
    }


static func _starter_planet_poi(pack_id: String, region_id: String,
        room_addr: String) -> Dictionary:
    var poi_id: String = "starter_planet"
    return {
        "id": poi_id,
        "name": STARTER_PLANET_NAME,
        "type": "planet",
        "description": "Authored campaign landing point.",
        "event_id": "",
        "orbit_dist": 900,
        "orbit_angle": 0,
        "sprite": "",
        "visual_scale": 1.0,
        "anim_frames": 1,
        "anim_fps": 0.0,
        "gravity_radius": 0,
        "planet_data": _starter_planet_data(pack_id, poi_id, region_id, room_addr),
    }


# planet_data follows the region-only shape:
#   { pack_id, poi_id, regions: [{ id, name, spawn_room }] }
# The spawn point inside the room comes from the room's player_spawn entity
# at land time. The old realm_id / top-level spawn_room / spawn_pos slots
# are gone.
static func _starter_planet_data(pack_id: String, poi_id: String, region_id: String,
        room_addr: String) -> Dictionary:
    var region_entry: Dictionary = {
        "id": region_id.strip_edges(),
        "name": region_id.strip_edges().capitalize(),
        "spawn_room": room_addr.strip_edges(),
    }
    return {
        "name": STARTER_PLANET_NAME,
        "pack_id": pack_id.strip_edges(),
        "poi_id": poi_id.strip_edges(),
        "regions": [region_entry],
        "sky_color": [0.35, 0.5, 0.8],
        "horizon_color": [0.5, 0.6, 0.35],
        "terrain_colors": [[0.16, 0.3, 0.16], [0.1, 0.22, 0.1], [0.08, 0.18, 0.06]],
        "roughness": 0.6,
        "turret_count": [0, 0],
        "patrol_count": [0, 0],
        "surface_pois": [],
    }


static func _ensure_starter_planet(system_data: Dictionary, pack_id: String,
        region_id: String, room_addr: String) -> void:
    var pois_v: Variant = system_data.get("pois", [])
    var pois: Array = []
    if typeof(pois_v) == TYPE_ARRAY:
        pois = (pois_v as Array).duplicate(true)

    var planet_idx: int = -1
    for i in range(pois.size()):
        var poi_v: Variant = pois[i]
        if typeof(poi_v) == TYPE_DICTIONARY and str((poi_v as Dictionary).get("type", "")).strip_edges() == "planet":
            planet_idx = i
            break

    if planet_idx < 0:
        pois.append(_starter_planet_poi(pack_id, region_id, room_addr))
    else:
        var poi: Dictionary = (pois[planet_idx] as Dictionary).duplicate(true)
        if str(poi.get("name", "")).strip_edges().is_empty():
            poi["name"] = STARTER_PLANET_NAME
        poi["type"] = "planet"
        var existing_poi_id: String = str(poi.get("id", "")).strip_edges()
        if existing_poi_id.is_empty():
            existing_poi_id = "starter_planet"
            poi["id"] = existing_poi_id

        var planet_v: Variant = poi.get("planet_data", {})
        var planet_data: Dictionary = {}
        if typeof(planet_v) == TYPE_DICTIONARY:
            planet_data = (planet_v as Dictionary).duplicate(true)
        # Strip legacy realm slots + the retired top-level spawn_pos if present.
        planet_data.erase("realm_id")
        planet_data.erase("region_id")
        planet_data.erase("spawn_room")
        planet_data.erase("spawn_pos")
        if str(planet_data.get("name", "")).strip_edges().is_empty():
            planet_data["name"] = str(poi.get("name", STARTER_PLANET_NAME))
        planet_data["pack_id"] = pack_id.strip_edges()
        planet_data["poi_id"] = existing_poi_id

        var regions_v: Variant = planet_data.get("regions", null)
        var regions: Array = regions_v if typeof(regions_v) == TYPE_ARRAY else []
        # Upsert the starter region entry by id.
        var starter_entry: Dictionary = {
            "id": region_id.strip_edges(),
            "name": region_id.strip_edges().capitalize(),
            "spawn_room": room_addr.strip_edges(),
        }
        var matched: bool = false
        for ri in range(regions.size()):
            if typeof(regions[ri]) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = regions[ri]
            if str(entry.get("id", "")).strip_edges() == starter_entry["id"]:
                entry["spawn_room"] = starter_entry["spawn_room"]
                # Strip the retired per-region spawn_pos field if a prior
                # save left one behind.
                entry.erase("spawn_pos")
                if str(entry.get("name", "")).strip_edges().is_empty():
                    entry["name"] = starter_entry["name"]
                regions[ri] = entry
                matched = true
                break
        if not matched:
            regions.append(starter_entry)
        planet_data["regions"] = regions
        poi["planet_data"] = planet_data
        pois[planet_idx] = poi

    system_data["pois"] = pois
    if typeof(system_data.get("connections", [])) != TYPE_ARRAY:
        system_data["connections"] = []
    # spawn_triggers was the legacy per-system enemy-spawn stub; replaced
    # by ECA rules in Triggers/global.json. Strip stale arrays on read so
    # packs don't round-trip dead data.
    system_data.erase("spawn_triggers")
    if typeof(system_data.get("placed_npcs", [])) != TYPE_ARRAY:
        system_data["placed_npcs"] = []


static func _read_systems(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var root: Dictionary = parsed
    var systems_v: Variant = root.get("systems", null)
    if typeof(systems_v) == TYPE_DICTIONARY:
        return (systems_v as Dictionary).duplicate(true)
    var out: Dictionary = {}
    for key_v in root.keys():
        var value_v: Variant = root[key_v]
        if typeof(value_v) == TYPE_DICTIONARY:
            out[str(key_v)] = (value_v as Dictionary).duplicate(true)
    return out


static func _read_systems_strict(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var root: Dictionary = parsed
    var systems_v: Variant = root.get("systems", null)
    if typeof(systems_v) != TYPE_DICTIONARY:
        return {}
    return (systems_v as Dictionary).duplicate(true)
