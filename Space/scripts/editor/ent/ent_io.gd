extends RefCounted

# Pure IO for the entity sprite editor. Reads/writes the pack's
# entities.json registry and enumerates sprite-set folders under the
# pack's Sprites/ directory.
#
# Mirrors env_io.gd's dual-layer resolution: writes always land under
# Content/<pack>/ (the writable layer), but reads fall back to
# res://Content/<pack>/ when the user layer is empty — so a pristine
# campaign can be opened without an override copy being written until
# the user actually makes a change.

const SHIPPED_SEED_PACK: String = "demo"
const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")


static func user_pack_dir(pack_id: String) -> String:
    return PackPaths.writable_pack_dir(pack_id)


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func entities_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Entities/entities.json"


static func shipped_entities_json_path(pack_id: String) -> String:
    return shipped_pack_dir(pack_id) + "Entities/entities.json"


# Pose metadata lives next to the sprite PNGs so multiple entities can
# share animation settings for the same sprite set without duplicating
# data. Writes always land in the user override layer; reads prefer the
# user layer then fall back to the shipped layer.
static func user_poses_json_path(pack_id: String, sprite_set_rel: String) -> String:
    return user_pack_dir(pack_id) + sprite_set_rel + "/poses.json"


static func shipped_poses_json_path(pack_id: String, sprite_set_rel: String) -> String:
    return shipped_pack_dir(pack_id) + sprite_set_rel + "/poses.json"


# Loads entities.json. Prefers the user override layer, falls back to
# the shipped layer, and synthesizes an empty registry if neither
# exists. Always returns a dict shaped {"entities": Array}.
static func load_or_init(pack_id: String) -> Dictionary:
    _ensure_dir(user_pack_dir(pack_id) + "Entities")
    var user_path := entities_json_path(pack_id)
    if FileAccess.file_exists(user_path):
        return _read_json(user_path)
    var shipped_path := shipped_entities_json_path(pack_id)
    if FileAccess.file_exists(shipped_path):
        return _read_json(shipped_path)
    return {"entities": []}


static func save_entities(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "Entities")
    var path := entities_json_path(pack_id)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("EntIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


# Returns a list of sprite-set folder paths (relative to the pack) that
# contain at least one .png. Scans both the user and shipped pack layers
# and de-dupes by relative path.
static func list_sprite_sets(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        _collect_sprite_sets_recursive(base, "Sprites", seen, out)
    out.sort()
    return out


# Returns the list of PNG filenames inside a sprite-set folder, resolved
# preferring the user layer then falling back to the shipped layer.
static func list_sprite_pngs(pack_id: String, sprite_set_rel: String) -> Array:
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var resolved_rel := _resolve_sprite_set_rel(base, sprite_set_rel)
        if resolved_rel.is_empty():
            continue
        var full: String = base + resolved_rel
        var d := DirAccess.open(full)
        if d == null:
            continue
        var out: Array = []
        d.list_dir_begin()
        var fn := d.get_next()
        while fn != "":
            if not d.current_is_dir() and _is_png_or_imported_png(fn):
                var png_name := _png_name_from_dir_entry(fn)
                if not out.has(png_name):
                    out.append(png_name)
            fn = d.get_next()
        d.list_dir_end()
        out.sort()
        if not out.is_empty():
            return out
    return []


# Loads a PNG from a sprite set into a Texture2D. Prefers user override.
static func load_sprite_png(pack_id: String, sprite_set_rel: String, filename: String) -> Texture2D:
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var resolved_rel := _resolve_sprite_set_rel(base, sprite_set_rel)
        if resolved_rel.is_empty():
            continue
        var path: String = base + resolved_rel + "/" + filename
        if not FileAccess.file_exists(path):
            continue
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            continue
        var bytes := f.get_buffer(f.get_length())
        f.close()
        var image := Image.new()
        if image.load_png_from_buffer(bytes) != OK:
            continue
        return ImageTexture.create_from_image(image)
    return null


# Loads the poses.json for a sprite set, preferring the user layer then
# falling back to the shipped layer. Always returns a Dictionary with a
# "poses" key containing another dict keyed by PNG filename. Missing or
# malformed files yield an empty registry so callers can always write.
static func load_poses(pack_id: String, sprite_set_rel: String) -> Dictionary:
    if sprite_set_rel == "":
        return {"poses": {}}
    for base_v in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var base: String = str(base_v)
        var resolved_rel: String = _resolve_sprite_set_rel(base, sprite_set_rel)
        if resolved_rel.is_empty():
            continue
        var base_path: String = base + resolved_rel + "/poses.json"
        if not FileAccess.file_exists(base_path):
            continue
        var f := FileAccess.open(base_path, FileAccess.READ)
        if f == null:
            continue
        var raw = JSON.parse_string(f.get_as_text())
        f.close()
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        if not raw.has("poses") or typeof(raw["poses"]) != TYPE_DICTIONARY:
            raw["poses"] = {}
        return raw
    return {"poses": {}}


# Writes a poses.json for a sprite set under the user override layer.
# Returns true on success. The file is pretty-printed for diffing.
static func save_poses(pack_id: String, sprite_set_rel: String, data: Dictionary) -> bool:
    if sprite_set_rel == "":
        push_error("EntIO: cannot save poses for empty sprite_set")
        return false
    _ensure_dir(user_pack_dir(pack_id) + sprite_set_rel)
    var path := user_poses_json_path(pack_id, sprite_set_rel)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("EntIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


# Auto-detects frame count for a horizontal sprite strip. Assumes the
# sprite is square-ish per-frame, so a 64x16 PNG is 4 frames, a 32x32
# PNG is 1 frame. Returns max(1, floor(w/h)).
static func autodetect_frame_count(tex: Texture2D) -> int:
    if tex == null:
        return 1
    var w := tex.get_width()
    var h := tex.get_height()
    if h <= 0 or w <= 0:
        return 1
    if w < h:
        return 1
    @warning_ignore("integer_division")
    return max(1, int(w / h))


# Generates an empty entity dict with sane defaults, used when adding
# a new row to the registry.
static func default_entity(id: String) -> Dictionary:
    return {
        "id": id,
        "name": id.capitalize(),
        "category": "enemy",
        "description": "",
        "scene": "",
        "sprite_set": "",
        "behavior": "",
        "movement_mode": "ground",
        "hp": 10,
        "attack_damage": 1,
        "contact_damage": 0,
        "contact_cooldown": 0.8,
        "move_speed": 40,
        "projectile_damage": 1,
        "projectile_speed": 180,
        "melee_range": 24,
        "melee_attack_trigger_frame": -1,
        "projectile_range": 220,
        "projectile_attack_trigger_frame": -1,
    }


# Resolves where a PNG would be copied to by import_sprite_png. Used by
# the conflict pre-flight in the sprite import flow.
static func sprite_png_dest_path(pack_id: String, sprite_set_rel: String,
        source_abs_path: String, dest_filename: String = "") -> String:
    var base := dest_filename if dest_filename != "" else source_abs_path.get_file()
    if not base.to_lower().ends_with(".png"):
        base += ".png"
    return user_pack_dir(pack_id) + sprite_set_rel + "/" + base


# Copies a PNG from an absolute OS path into a sprite-set folder under
# the user override layer. Creates the folder if missing. Always
# overwrites — the conflict pre-flight in entity_editor.gd is expected
# to handle user consent before calling this.
static func import_sprite_png(pack_id: String, sprite_set_rel: String,
        source_abs_path: String, dest_filename: String = "") -> bool:
    if pack_id == "" or sprite_set_rel == "" or source_abs_path == "":
        return false
    _ensure_dir(user_pack_dir(pack_id) + sprite_set_rel)
    var src := FileAccess.open(source_abs_path, FileAccess.READ)
    if src == null:
        push_error("EntIO: cannot open source PNG '%s'" % source_abs_path)
        return false
    var bytes := src.get_buffer(src.get_length())
    src.close()
    if bytes.is_empty():
        push_error("EntIO: source PNG '%s' was empty" % source_abs_path)
        return false
    var dest_path := sprite_png_dest_path(pack_id, sprite_set_rel,
        source_abs_path, dest_filename)
    var dst := FileAccess.open(dest_path, FileAccess.WRITE)
    if dst == null:
        push_error("EntIO: cannot open dest PNG '%s' for write" % dest_path)
        return false
    dst.store_buffer(bytes)
    dst.close()
    return true


static func _collect_sprite_sets_recursive(base: String, rel_dir: String,
        seen: Dictionary, out: Array) -> void:
    var abs_dir := base + rel_dir
    var d := DirAccess.open(abs_dir)
    if d == null:
        return
    var subdirs: Array = []
    d.list_dir_begin()
    var fn := d.get_next()
    while fn != "":
        if d.current_is_dir() and not fn.begins_with("."):
            subdirs.append(fn)
        fn = d.get_next()
    d.list_dir_end()
    subdirs.sort()
    for subdir_v in subdirs:
        var subdir := str(subdir_v)
        var child_rel := rel_dir + "/" + subdir
        var child_abs := base + child_rel
        if _folder_has_png(child_abs) and not seen.has(child_rel):
            seen[child_rel] = true
            out.append(child_rel)
        _collect_sprite_sets_recursive(base, child_rel, seen, out)


static func _resolve_sprite_set_rel(base: String, sprite_set_rel: String) -> String:
    var normalized := sprite_set_rel.replace("\\", "/").strip_edges()
    if normalized.is_empty():
        return ""
    if DirAccess.open(base + normalized) != null:
        return normalized
    var leaf := normalized.get_file().strip_edges()
    if leaf.is_empty():
        return ""
    return _find_sprite_set_rel_recursive(base, "Sprites", leaf)


static func _find_sprite_set_rel_recursive(base: String, rel_dir: String, leaf: String) -> String:
    var abs_dir := base + rel_dir
    var d := DirAccess.open(abs_dir)
    if d == null:
        return ""
    var subdirs: Array = []
    d.list_dir_begin()
    var fn := d.get_next()
    while fn != "":
        if d.current_is_dir() and not fn.begins_with("."):
            subdirs.append(fn)
        fn = d.get_next()
    d.list_dir_end()
    subdirs.sort()
    for subdir_v in subdirs:
        var subdir := str(subdir_v)
        var child_rel := rel_dir + "/" + subdir
        var child_abs := base + child_rel
        if subdir == leaf and _folder_has_png(child_abs):
            return child_rel
        var nested := _find_sprite_set_rel_recursive(base, child_rel, leaf)
        if not nested.is_empty():
            return nested
    return ""


static func _folder_has_png(path: String) -> bool:
    var d := DirAccess.open(path)
    if d == null:
        return false
    d.list_dir_begin()
    var fn := d.get_next()
    while fn != "":
        if not d.current_is_dir() and _is_png_or_imported_png(fn):
            d.list_dir_end()
            return true
        fn = d.get_next()
    d.list_dir_end()
    return false


static func _read_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {"entities": []}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {"entities": []}
    if not raw.has("entities") or typeof(raw["entities"]) != TYPE_ARRAY:
        raw["entities"] = []
    return raw


static func _is_png_or_imported_png(name: String) -> bool:
    var lower := name.to_lower()
    return lower.ends_with(".png") or lower.ends_with(".png.import")


static func _png_name_from_dir_entry(name: String) -> String:
    if name.to_lower().ends_with(".png.import"):
        return name.substr(0, name.length() - ".import".length())
    return name


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)
