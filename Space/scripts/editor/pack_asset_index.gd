extends RefCounted

const SHIPPED_SEED_PACK: String = "demo"


static func normalized_pack_id(pack_id: String) -> String:
    var pid: String = pack_id.strip_edges()
    if pid.is_empty():
        return SHIPPED_SEED_PACK
    return pid


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % normalized_pack_id(pack_id)


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % normalized_pack_id(pack_id)


static func list_pack_pngs(pack_id: String, rel_dir: String) -> Array:
    var trimmed: String = rel_dir.strip_edges()
    while trimmed.begins_with("/"):
        trimmed = trimmed.substr(1)
    while trimmed.ends_with("/"):
        trimmed = trimmed.substr(0, trimmed.length() - 1)
    if trimmed.is_empty():
        return []
    var out: Array = []
    var seen: Dictionary = {}
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        _scan_pngs_relative(base, trimmed, trimmed, out, seen)
    out.sort()
    return out


static func list_system_sprite_paths(pack_id: String) -> Array:
    var out: Array = []
    var seen: Dictionary = {}
    var pack_roots: Array = [
        "Systems",
        "Systems/AstralBodies",
        "Projectiles",
        "Beams",
        "Sprites/VFX",
        "Sprites/AstralBodies",
    ]
    for rel_root_v in pack_roots:
        var rel_root: String = str(rel_root_v)
        for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
            _scan_pngs_absolute(base, rel_root, out, seen)
    for abs_root_v in [
        "res://Space/art/vfx",
        "res://Space/art/projectiles",
    ]:
        _scan_abs_png_root(str(abs_root_v), out, seen)
    out.sort()
    return out


static func list_ship_hull_paths() -> Array:
    var out: Array = []
    var seen: Dictionary = {}
    _scan_abs_png_root("res://Space/art/ships", out, seen)
    var filtered: Array = []
    for path_v in out:
        var path: String = str(path_v)
        if _looks_like_ship_hull(path):
            filtered.append(path)
    if filtered.is_empty():
        filtered = out
    filtered.sort()
    return filtered


static func list_portrait_entries(pack_id: String) -> Array:
    var pid: String = normalized_pack_id(pack_id)
    var manifest: Variant = load_json_cascade(pid, "Portraits/manifest.json", {})
    var entries: Array = []
    if typeof(manifest) == TYPE_DICTIONARY:
        var portraits_v: Variant = (manifest as Dictionary).get("portraits", [])
        if typeof(portraits_v) == TYPE_ARRAY:
            for entry_v in portraits_v:
                if typeof(entry_v) != TYPE_DICTIONARY:
                    continue
                var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
                var id_val: String = str(entry.get("id", "")).strip_edges()
                var file_val: String = str(entry.get("file", "")).strip_edges()
                if id_val.is_empty() or file_val.is_empty():
                    continue
                entry["id"] = id_val
                entry["file"] = file_val
                entries.append(entry)
    if entries.is_empty():
        for rel_path_v in list_pack_pngs(pid, "Portraits"):
            var rel_path: String = str(rel_path_v)
            if rel_path.to_lower().ends_with(".png"):
                entries.append({
                    "id": rel_path.get_file().get_basename(),
                    "file": rel_path,
                    "aliases": [],
                })
    entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a.get("id", "")).to_lower() < str(b.get("id", "")).to_lower()
    )
    return entries


static func list_portrait_ids(pack_id: String) -> Array:
    var out: Array = []
    for entry_v in list_portrait_entries(pack_id):
        var entry: Dictionary = entry_v
        var id_val: String = str(entry.get("id", "")).strip_edges()
        if not id_val.is_empty():
            out.append(id_val)
    return out


static func build_portrait_map(pack_id: String) -> Dictionary:
    var mapping: Dictionary = {}
    for entry_v in list_portrait_entries(pack_id):
        var entry: Dictionary = entry_v
        var id_val: String = str(entry.get("id", "")).strip_edges()
        var rel_file: String = str(entry.get("file", "")).strip_edges()
        var abs_path: String = resolve_pack_asset(pack_id, rel_file)
        if id_val.is_empty() or abs_path.is_empty():
            continue
        mapping[id_val] = abs_path
        mapping[id_val.to_upper()] = abs_path
        var aliases_v: Variant = entry.get("aliases", [])
        if typeof(aliases_v) == TYPE_ARRAY:
            for alias_v in aliases_v:
                var alias: String = str(alias_v).strip_edges()
                if alias.is_empty():
                    continue
                mapping[alias] = abs_path
                mapping[alias.to_upper()] = abs_path
    return mapping


static func resolve_pack_asset(pack_id: String, rel_path: String) -> String:
    var clean: String = rel_path.strip_edges()
    if clean.is_empty():
        return ""
    if clean.begins_with("res://") or clean.begins_with("user://"):
        return clean
    var user_path: String = user_pack_dir(pack_id) + clean
    if FileAccess.file_exists(user_path):
        return user_path
    var shipped_path: String = shipped_pack_dir(pack_id) + clean
    if FileAccess.file_exists(shipped_path):
        return shipped_path
    return ""


static func load_json_cascade(pack_id: String, rel_path: String, fallback: Variant) -> Variant:
    var clean: String = rel_path.strip_edges()
    if clean.is_empty():
        return fallback
    for path in [user_pack_dir(pack_id) + clean, shipped_pack_dir(pack_id) + clean]:
        if not FileAccess.file_exists(path):
            continue
        var f: FileAccess = FileAccess.open(path, FileAccess.READ)
        if f == null:
            continue
        var raw: Variant = JSON.parse_string(f.get_as_text())
        f.close()
        if raw != null:
            return raw
    return fallback


static func _scan_pngs_relative(base_path: String, rel_root: String, current_rel: String,
        out: Array, seen: Dictionary) -> void:
    var dir: DirAccess = DirAccess.open(base_path + current_rel)
    if dir == null:
        return
    dir.list_dir_begin()
    var name: String = dir.get_next()
    while name != "":
        if name.begins_with("."):
            name = dir.get_next()
            continue
        if dir.current_is_dir():
            _scan_pngs_relative(base_path, rel_root, current_rel + "/" + name, out, seen)
        elif name.to_lower().ends_with(".png"):
            var rel_path: String = current_rel + "/" + name
            if not seen.has(rel_path):
                seen[rel_path] = true
                out.append(rel_path)
        name = dir.get_next()
    dir.list_dir_end()


static func _scan_pngs_absolute(base_path: String, rel_root: String, out: Array, seen: Dictionary) -> void:
    _scan_abs_png_root(base_path + rel_root, out, seen)


static func _scan_abs_png_root(root_path: String, out: Array, seen: Dictionary) -> void:
    var dir: DirAccess = DirAccess.open(root_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var name: String = dir.get_next()
    while name != "":
        if name.begins_with("."):
            name = dir.get_next()
            continue
        var full_path: String = root_path + "/" + name if not root_path.ends_with("/") else root_path + name
        if dir.current_is_dir():
            _scan_abs_png_root(full_path, out, seen)
        elif name.to_lower().ends_with(".png"):
            if not seen.has(full_path):
                seen[full_path] = true
                out.append(full_path)
        name = dir.get_next()
    dir.list_dir_end()


static func _looks_like_ship_hull(path: String) -> bool:
    var lower: String = path.to_lower()
    for banned_v in [
        "exhaust",
        "turbo",
        "flight_",
        "thruster",
        "thrust",
        "smoke",
        "fire",
        "weapon",
        "projectile",
        "effect",
        "fx/",
    ]:
        if lower.find(str(banned_v)) >= 0:
            return false
    var base: String = path.get_file().to_lower()
    for hint_v in ["ship", "fighter", "shuttle", "cargo", "vessel", "frigate", "cruiser"]:
        if base.find(str(hint_v)) >= 0:
            return true
    return false
