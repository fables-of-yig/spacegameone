extends RefCounted

const SHIPPED_SEED_PACK: String = "demo"
const FILE_NAME: String = "systems.json"
const FOLDER: String = "Systems"
const LEGACY_ATLAS_PATH: String = "res://Space/data/systems/sector_atlas.json"


static func user_file(pack_id: String) -> String:
    return "user://Packs/%s/%s/%s" % [pack_id, FOLDER, FILE_NAME]


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
