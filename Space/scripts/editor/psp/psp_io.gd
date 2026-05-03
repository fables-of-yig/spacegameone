extends RefCounted

# Pure IO for the player sprite editor. Reads/writes:
#   user://Packs/<pack>/Sprites/player_sheet*.png
#   user://Packs/<pack>/Sprites/player_frames.json
#   user://Packs/<pack>/Sprites/player_poses.json
#
# Schema must stay in sync with MV/scripts/player.gd _load_frames / _load_poses.
# frames.json:
#   top-level: {frame_width, frame_height, center_x, center_y, sheet_cols,
#               sheets: [{id, file, z}],
#               frames: [{pose: int, rotation_deg: float,
#                         layers: [{sheet, index}, ...]}, ...]}
#   `index` is the sheet cell number (row-major, zero-based). Entries are
#   appended in order, so the array order IS the animation sequence for
#   that pose. Older data that stores {pose, index} is still accepted and
#   treated as one base-sheet layer.
# poses.json:
#   top-level: {poses: {"<int_id>": {name, dir, mvtype, y_radius, y_offset,
#                                     collision_width, hurtbox_x/y/w/h,
#                                     weapon_anchor_x/y,
#                                     timing: [int], anim_speed, loop_from, transition_to}}}
#
# Default seed matches Content/demo/Sprites/* so a fresh pack has a
# playable baseline movement/combat state set instead of only stand poses,
# and the runtime stops spamming "failed to open player_frames.json" on
# first playtest.

const DEFAULT_FRAME_W: int = 50
const DEFAULT_FRAME_H: int = 44
const DEFAULT_CENTER_X: int = 25
const DEFAULT_CENTER_Y: int = 22
const DEFAULT_SHEET_COLS: int = 10
const BASE_SHEET_ID: String = "base"
const BASE_SHEET_FILE: String = "player_sheet.png"
const PRESET_ROOT_DIR: String = "presets"

const SHIPPED_SEED_PACK: String = "demo"


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % pack_id


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func user_sprites_dir(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Sprites/"


static func shipped_sprites_dir(pack_id: String) -> String:
    return shipped_pack_dir(pack_id) + "Sprites/"


static func user_frames_path(pack_id: String) -> String:
    return user_sprites_dir(pack_id) + "player_frames.json"


static func user_poses_path(pack_id: String) -> String:
    return user_sprites_dir(pack_id) + "player_poses.json"


static func user_sheet_path(pack_id: String) -> String:
    return user_sheet_path_for_file(pack_id, BASE_SHEET_FILE)


static func user_sheet_path_for_file(pack_id: String, file_name: String) -> String:
    return user_sprites_dir(pack_id) + file_name


# Creates missing player sprite authoring files from baked starter data.
# Existing user files are never changed and no shipped/demo files are read.
static func ensure_starter_player_sprites(pack_id: String) -> Array:
    var changed: Array = []
    _ensure_dir(user_sprites_dir(pack_id))
    _write_missing_json(user_frames_path(pack_id), baked_starter_frames_data(), changed)
    _write_missing_json(user_poses_path(pack_id), baked_starter_poses_data(), changed)
    _write_missing_starter_sheet(user_sheet_path(pack_id), changed)
    return changed


# Resolves to the user layer if present, otherwise falls back to the
# shipped layer. Used by the editor to display whatever sheet the
# runtime would actually load.
static func resolved_sheet_path(pack_id: String) -> String:
    return resolved_sheet_path_for_file(pack_id, BASE_SHEET_FILE)


static func resolved_sheet_path_for_file(pack_id: String, file_name: String) -> String:
    var user_path := user_sheet_path_for_file(pack_id, file_name)
    if FileAccess.file_exists(user_path):
        return user_path
    var shipped := shipped_sprites_dir(pack_id) + file_name
    if FileAccess.file_exists(shipped):
        return shipped
    # Last-ditch fallback: the demo pack's sheet, so a brand-new pack has
    # something to look at while the user figures out sprite import.
    return shipped_pack_dir(SHIPPED_SEED_PACK) + "Sprites/" + file_name


# Loads both frames.json and poses.json for a pack. If neither exists in
# the user layer, copies the shipped pack's files (falling back to demo).
# If NOTHING exists anywhere, seeds the defaults and writes them so the
# next playtest succeeds. Returns {"frames": dict, "poses": dict}.
static func load_or_init(pack_id: String) -> Dictionary:
    _ensure_dir(user_sprites_dir(pack_id))

    var frames: Dictionary = _load_or_copy(pack_id, "player_frames.json", default_frames_data())
    var poses: Dictionary = _load_or_copy(pack_id, "player_poses.json", default_poses_data())
    var scaffolded: Dictionary = _ensure_starter_pose_scaffold(pack_id, frames, poses)
    var scaffold_frames_v: Variant = scaffolded.get("frames", frames)
    if typeof(scaffold_frames_v) == TYPE_DICTIONARY:
        frames = scaffold_frames_v
    var scaffold_poses_v: Variant = scaffolded.get("poses", poses)
    if typeof(scaffold_poses_v) == TYPE_DICTIONARY:
        poses = scaffold_poses_v

    # Also make sure all referenced sheet PNGs exist in the user layer.
    # Current demo data can use many source sheets, not only player_sheet.png.
    # Non-fatal if a baseline sheet is not bundled.
    _ensure_user_sheets(pack_id, frames)

    return {"frames": frames, "poses": poses}


static func _load_or_copy(pack_id: String, file_name: String, fallback: Dictionary) -> Dictionary:
    var user_path := user_sprites_dir(pack_id) + file_name
    if FileAccess.file_exists(user_path):
        var data := _read_json(user_path)
        if not data.is_empty():
            return data
    var shipped := shipped_sprites_dir(pack_id) + file_name
    if FileAccess.file_exists(shipped):
        var shipped_data := _read_json(shipped)
        if not shipped_data.is_empty():
            _write_json(user_path, shipped_data)
            return shipped_data
    var demo := shipped_pack_dir(SHIPPED_SEED_PACK) + "Sprites/" + file_name
    if FileAccess.file_exists(demo):
        var demo_data := _read_json(demo)
        if not demo_data.is_empty():
            _write_json(user_path, demo_data)
            return demo_data
    _write_json(user_path, fallback)
    return fallback


static func _ensure_user_sheet(pack_id: String) -> void:
    _ensure_user_sheet_file(pack_id, BASE_SHEET_FILE)


static func _ensure_user_sheets(pack_id: String, frames: Dictionary) -> void:
    var seen: Dictionary = {}
    for sheet_def_v in normalize_sheet_defs(frames.get("sheets", default_sheet_defs())):
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var file_name := str(sheet_def.get("file", "")).strip_edges()
        if file_name.is_empty() or seen.has(file_name):
            continue
        seen[file_name] = true
        _ensure_user_sheet_file(pack_id, file_name)
    if seen.is_empty():
        _ensure_user_sheet_file(pack_id, BASE_SHEET_FILE)


static func _ensure_user_sheet_file(pack_id: String, file_name: String) -> void:
    var user_path := user_sheet_path_for_file(pack_id, file_name)
    if _is_valid_sheet_file(user_path):
        return
    _ensure_dir(user_path.get_base_dir())
    var shipped := shipped_sprites_dir(pack_id) + file_name
    if _is_valid_sheet_file(shipped):
        _copy_file(shipped, user_path)
        return
    var demo := shipped_pack_dir(SHIPPED_SEED_PACK) + "Sprites/" + file_name
    if _is_valid_sheet_file(demo):
        _copy_file(demo, user_path)


static func _is_valid_sheet_file(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return false
    if f.get_length() < 8:
        f.close()
        return false
    var bytes := f.get_buffer(f.get_length())
    f.close()
    var png_signature := PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    for i in range(png_signature.size()):
        if bytes[i] != png_signature[i]:
            return false
    var img := Image.new()
    if img.load_png_from_buffer(bytes) != OK:
        return false
    if img.get_width() <= 0 or img.get_height() <= 0:
        return false
    for y in range(img.get_height()):
        for x in range(img.get_width()):
            if img.get_pixel(x, y).a > 0.01:
                return true
    return false


static func save_frames(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_sprites_dir(pack_id))
    var out_data: Dictionary = data.duplicate(true)
    if not out_data.has("seed_version"):
        out_data["seed_version"] = _resolved_seed_version(pack_id, true)
    return _write_json(user_frames_path(pack_id), out_data)


static func save_poses(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_sprites_dir(pack_id))
    var out_data: Dictionary = _normalize_poses_data(data)
    if not out_data.has("seed_version"):
        out_data["seed_version"] = _resolved_seed_version(pack_id, false)
    if not _validate_poses_data(out_data):
        return false
    return _write_json(user_poses_path(pack_id), out_data)


# Copies an externally-chosen PNG (native OS path from FileDialog) into
# the user pack's Sprites/player_sheet.png. Returns true on success. The
# editor then loads the copy, so the source file is no longer referenced.
static func import_sheet(pack_id: String, source_abs_path: String) -> bool:
    return import_sheet_as(pack_id, source_abs_path, BASE_SHEET_FILE)


static func import_sheet_as(pack_id: String, source_abs_path: String, file_name: String) -> bool:
    _ensure_dir(user_sprites_dir(pack_id))
    var dst := user_sheet_path_for_file(pack_id, file_name)
    var src := FileAccess.open(source_abs_path, FileAccess.READ)
    if src == null:
        push_error("PspIO: cannot open source sheet '%s'" % source_abs_path)
        return false
    var bytes := src.get_buffer(src.get_length())
    src.close()
    var out := FileAccess.open(dst, FileAccess.WRITE)
    if out == null:
        push_error("PspIO: cannot open '%s' for write" % dst)
        return false
    out.store_buffer(bytes)
    out.close()
    return true


# Loads the current user sheet into an ImageTexture suitable for display
# in the editor. Falls back through resolved_sheet_path so the editor
# always shows *something*. Returns null on total failure.
static func load_sheet_texture(pack_id: String) -> Texture2D:
    var path := resolved_sheet_path(pack_id)
    if not FileAccess.file_exists(path):
        return null
    var img := Image.new()
    var err := img.load(path)
    if err != OK:
        push_warning("PspIO: Image.load failed on %s (err=%d)" % [path, err])
        return null
    return ImageTexture.create_from_image(img)


static func load_sheet_textures(pack_id: String, sheet_defs: Array) -> Dictionary:
    var textures: Dictionary = {}
    for sheet_def_v in sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var sheet_id: String = str(sheet_def.get("id", "")).strip_edges()
        var file_name: String = str(sheet_def.get("file", "")).strip_edges()
        if sheet_id.is_empty() or file_name.is_empty():
            continue
        var path := resolved_sheet_path_for_file(pack_id, file_name)
        if not FileAccess.file_exists(path):
            continue
        var img := Image.new()
        var err := img.load(path)
        if err != OK:
            push_warning("PspIO: Image.load failed on %s (err=%d)" % [path, err])
            continue
        textures[sheet_id] = ImageTexture.create_from_image(img)
    return textures


static func default_sheet_defs() -> Array:
    return [
        {
            "id": BASE_SHEET_ID,
            "file": BASE_SHEET_FILE,
            "z": 0,
        }
    ]


static func list_presets(pack_id: String) -> Array:
    var merged: Dictionary = {}
    for base_dir in [
        user_sprites_dir(pack_id),
        shipped_sprites_dir(pack_id),
        shipped_sprites_dir(SHIPPED_SEED_PACK),
    ]:
        _collect_presets_from_base(base_dir, merged)
    var out: Array = []
    for preset_id_v in merged.keys():
        var preset_v: Variant = merged.get(preset_id_v, {})
        if typeof(preset_v) != TYPE_DICTIONARY:
            continue
        var preset: Dictionary = preset_v
        out.append({
            "id": str(preset.get("id", "")),
            "name": str(preset.get("name", preset_id_v)),
            "description": str(preset.get("description", "")),
        })
    _sort_preset_entries_by_name(out)
    return out


static func apply_preset(pack_id: String, preset_id: String) -> bool:
    var preset: Dictionary = load_preset(pack_id, preset_id)
    if preset.is_empty():
        push_error("PspIO: preset '%s' not found" % preset_id)
        return false
    var frames_v: Variant = preset.get("frames", {})
    var poses_v: Variant = preset.get("poses", {})
    if typeof(frames_v) != TYPE_DICTIONARY or typeof(poses_v) != TYPE_DICTIONARY:
        push_error("PspIO: preset '%s' is missing frames/poses data" % preset_id)
        return false
    var preset_dir: String = str(preset.get("preset_dir", "")).strip_edges()
    var frames_data: Dictionary = frames_v
    var poses_data: Dictionary = poses_v
    if not _copy_preset_sheet_files(pack_id, preset_dir, frames_data):
        return false
    return save_frames(pack_id, frames_data) and save_poses(pack_id, poses_data)


static func overwrite_preset(pack_id: String, preset_id: String, frames_data: Dictionary, poses_data: Dictionary) -> bool:
    var preset: Dictionary = load_preset(pack_id, preset_id)
    if preset.is_empty():
        push_error("PspIO: preset '%s' not found for overwrite" % preset_id)
        return false
    var preset_dir: String = str(preset.get("preset_dir", "")).strip_edges()
    if preset_dir.is_empty():
        push_error("PspIO: preset '%s' has no writable preset_dir" % preset_id)
        return false

    var out_frames: Dictionary = frames_data.duplicate(true)
    out_frames["sheets"] = normalize_sheet_defs(out_frames.get("sheets", []))
    var out_poses: Dictionary = poses_data.duplicate(true)
    if not _validate_poses_data(out_poses):
        return false
    if not _copy_current_pack_sheet_files_to_preset(pack_id, preset_dir, out_frames):
        return false

    var manifest_v: Variant = preset.get("manifest", {})
    var manifest: Dictionary = {}
    if typeof(manifest_v) == TYPE_DICTIONARY:
        manifest = (manifest_v as Dictionary).duplicate(true)
    if manifest.is_empty():
        manifest = {
            "id": preset_id,
            "name": preset_id,
            "description": "",
            "frames": "player_frames.json",
            "poses": "player_poses.json",
        }
    if str(manifest.get("id", "")).strip_edges().is_empty():
        manifest["id"] = preset_id
    if str(manifest.get("frames", "")).strip_edges().is_empty():
        manifest["frames"] = "player_frames.json"
    if str(manifest.get("poses", "")).strip_edges().is_empty():
        manifest["poses"] = "player_poses.json"

    var frames_rel: String = str(manifest.get("frames", "player_frames.json")).strip_edges()
    var poses_rel: String = str(manifest.get("poses", "player_poses.json")).strip_edges()
    if not _write_json(preset_dir + frames_rel, out_frames):
        return false
    if not _write_json(preset_dir + poses_rel, out_poses):
        return false
    return _write_json(preset_dir + "preset.json", manifest)


static func load_preset(pack_id: String, preset_id: String) -> Dictionary:
    var trimmed_id: String = preset_id.strip_edges()
    if trimmed_id.is_empty():
        return {}
    for base_dir in [
        user_sprites_dir(pack_id),
        shipped_sprites_dir(pack_id),
        shipped_sprites_dir(SHIPPED_SEED_PACK),
    ]:
        var manifest_path := _preset_manifest_path(base_dir, trimmed_id)
        if not FileAccess.file_exists(manifest_path):
            continue
        var manifest := _read_json(manifest_path)
        if manifest.is_empty():
            continue
        var preset_dir: String = manifest_path.get_base_dir() + "/"
        var frames_file: String = str(manifest.get("frames", "player_frames.json")).strip_edges()
        var poses_file: String = str(manifest.get("poses", "player_poses.json")).strip_edges()
        var frames_data := _read_json(preset_dir + frames_file)
        var poses_data := _read_json(preset_dir + poses_file)
        if frames_data.is_empty() or poses_data.is_empty():
            continue
        return {
            "manifest": manifest,
            "preset_dir": preset_dir,
            "frames": frames_data,
            "poses": poses_data,
        }
    return {}


static func next_import_sheet_file_name(pack_id: String, source_abs_path: String) -> String:
    var source_name: String = source_abs_path.get_file()
    var base_name: String = source_name.get_basename().strip_edges()
    if base_name.is_empty():
        base_name = "sheet"
    base_name = base_name.to_lower().replace(" ", "_")
    var ext: String = source_name.get_extension().to_lower()
    if ext.is_empty():
        ext = "png"
    var candidate: String = "%s.%s" % [base_name, ext]
    var counter: int = 2
    while FileAccess.file_exists(user_sheet_path_for_file(pack_id, candidate)) or FileAccess.file_exists(shipped_sprites_dir(pack_id) + candidate):
        candidate = "%s_%d.%s" % [base_name, counter, ext]
        counter += 1
    return candidate


static func sheet_id_from_file_name(file_name: String) -> String:
    var base_name: String = file_name.get_basename().strip_edges().to_lower()
    if base_name.is_empty():
        return BASE_SHEET_ID
    return base_name.replace(" ", "_")


static func normalize_sheet_defs(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) == TYPE_ARRAY:
        for entry_v in v:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_v
            var sheet_id: String = str(entry.get("id", "")).strip_edges()
            var file_name: String = str(entry.get("file", "")).strip_edges()
            if sheet_id.is_empty() or file_name.is_empty():
                continue
            out.append({
                "id": sheet_id,
                "file": file_name,
                "z": int(entry.get("z", out.size())),
            })
    if out.is_empty():
        out = default_sheet_defs()
    return out


static func normalize_frame_layers(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) == TYPE_ARRAY:
        for layer_v in v:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = layer_v
            var sheet_id: String = str(layer.get("sheet", BASE_SHEET_ID)).strip_edges()
            if sheet_id.is_empty():
                sheet_id = BASE_SHEET_ID
            out.append({
                "sheet": sheet_id,
                "index": int(layer.get("index", 0)),
            })
    if out.is_empty():
        out.append({"sheet": BASE_SHEET_ID, "index": 0})
    return out


static func normalize_frame_entry(v: Variant) -> Dictionary:
    if typeof(v) == TYPE_DICTIONARY:
        var entry: Dictionary = v
        var layers: Array = []
        if entry.has("layers"):
            layers = normalize_frame_layers(entry.get("layers", []))
        else:
            layers = [{"sheet": BASE_SHEET_ID, "index": int(entry.get("index", 0))}]
        return {
            "pose": int(entry.get("pose", 0)),
            "rotation_deg": float(entry.get("rotation_deg", 0.0)),
            "layers": layers,
        }
    return {
        "pose": 0,
        "rotation_deg": 0.0,
        "layers": [{"sheet": BASE_SHEET_ID, "index": int(v)}],
    }


# Default seed - matches Content/demo/Sprites/player_frames.json exactly,
# including the demo's single-frame-per-pose placeholder animation. The
# runtime ignores unused top-level keys but we keep them for authoring
# context (frame size, sheet cols) so the editor can round-trip them.
static func default_frames_data() -> Dictionary:
    var shipped_demo: Dictionary = _read_json(shipped_pack_dir(SHIPPED_SEED_PACK) + "Sprites/player_frames.json")
    if not shipped_demo.is_empty():
        return shipped_demo
    return baked_starter_frames_data()


static func baked_starter_frames_data() -> Dictionary:
    return {
        "frame_width": DEFAULT_FRAME_W,
        "frame_height": DEFAULT_FRAME_H,
        "center_x": DEFAULT_CENTER_X,
        "center_y": DEFAULT_CENTER_Y,
        "sheet_cols": DEFAULT_SHEET_COLS,
        "sheets": default_sheet_defs(),
        "frames": _starter_frame_entries(),
    }


static func default_poses_data() -> Dictionary:
    var shipped_demo: Dictionary = _read_json(shipped_pack_dir(SHIPPED_SEED_PACK) + "Sprites/player_poses.json")
    if not shipped_demo.is_empty():
        return shipped_demo
    return baked_starter_poses_data()


static func baked_starter_poses_data() -> Dictionary:
    return {"poses": _starter_pose_entries()}


static func _ensure_starter_pose_scaffold(pack_id: String, frames_data: Dictionary, poses_data: Dictionary) -> Dictionary:
    var starter_frames_data: Dictionary = default_frames_data()
    var starter_poses_data: Dictionary = default_poses_data()
    if pack_id == SHIPPED_SEED_PACK:
        if _seed_version_is_stale(frames_data, starter_frames_data):
            frames_data = starter_frames_data.duplicate(true)
            _write_json(user_frames_path(pack_id), frames_data)
        if _seed_version_is_stale(poses_data, starter_poses_data):
            poses_data = starter_poses_data.duplicate(true)
            _write_json(user_poses_path(pack_id), poses_data)
    if _looks_like_legacy_placeholder_frames(frames_data):
        frames_data = starter_frames_data.duplicate(true)
        _write_json(user_frames_path(pack_id), frames_data)
    if _looks_like_legacy_placeholder_poses(poses_data):
        poses_data = starter_poses_data.duplicate(true)
        _write_json(user_poses_path(pack_id), poses_data)

    var changed_meta: bool = false
    if _frame_metadata_looks_legacy(frames_data):
        frames_data["frame_width"] = int(starter_frames_data.get("frame_width", DEFAULT_FRAME_W))
        frames_data["frame_height"] = int(starter_frames_data.get("frame_height", DEFAULT_FRAME_H))
        frames_data["center_x"] = int(starter_frames_data.get("center_x", DEFAULT_CENTER_X))
        frames_data["center_y"] = int(starter_frames_data.get("center_y", DEFAULT_CENTER_Y))
        frames_data["sheet_cols"] = int(starter_frames_data.get("sheet_cols", DEFAULT_SHEET_COLS))
        frames_data["sheets"] = normalize_sheet_defs(starter_frames_data.get("sheets", default_sheet_defs())).duplicate(true)
        changed_meta = true

    var changed_poses: bool = false
    var poses_v: Variant = poses_data.get("poses", {})
    var poses: Dictionary = {}
    if typeof(poses_v) == TYPE_DICTIONARY:
        poses = poses_v
    var starter_poses_v: Variant = starter_poses_data.get("poses", _starter_pose_entries())
    var starter_poses: Dictionary = _starter_pose_entries()
    if typeof(starter_poses_v) == TYPE_DICTIONARY:
        starter_poses = starter_poses_v
    for pose_key_v in starter_poses.keys():
        var pose_key: String = str(pose_key_v)
        if poses.has(pose_key):
            continue
        var starter_pose_copy_v: Variant = starter_poses.get(pose_key, {})
        if typeof(starter_pose_copy_v) != TYPE_DICTIONARY:
            continue
        var starter_pose_copy: Dictionary = starter_pose_copy_v
        poses[pose_key] = starter_pose_copy.duplicate(true)
        changed_poses = true
    if changed_poses:
        poses_data["poses"] = poses
        _write_json(user_poses_path(pack_id), poses_data)

    var changed_frames: bool = false
    var frames_v: Variant = frames_data.get("frames", [])
    var frames: Array = []
    if typeof(frames_v) == TYPE_ARRAY:
        frames = frames_v
    var starter_frames_v: Variant = starter_frames_data.get("frames", _starter_frame_entries())
    var starter_frames: Array = _starter_frame_entries()
    if typeof(starter_frames_v) == TYPE_ARRAY:
        starter_frames = starter_frames_v
    var current_by_pose: Dictionary = _group_frames_by_pose(frames)
    var starter_by_pose: Dictionary = _group_frames_by_pose(starter_frames)
    for pose_key_v in starter_poses.keys():
        var pose_key: String = str(pose_key_v)
        var pose_id: int = int(pose_key)
        var current_seq: Array = _frames_for_pose(current_by_pose, pose_id)
        var starter_seq: Array = _frames_for_pose(starter_by_pose, pose_id)
        if _frame_sequence_needs_starter_upgrade(current_seq, starter_seq):
            if starter_seq.is_empty():
                current_by_pose.erase(pose_id)
            else:
                current_by_pose[pose_id] = starter_seq.duplicate(true)
            changed_frames = true

        var current_pose_v: Variant = poses.get(pose_key, null)
        var current_pose: Dictionary = {}
        if typeof(current_pose_v) == TYPE_DICTIONARY:
            current_pose = current_pose_v
        var starter_pose_v: Variant = starter_poses.get(pose_key, null)
        var starter_pose: Dictionary = {}
        if typeof(starter_pose_v) == TYPE_DICTIONARY:
            starter_pose = starter_pose_v
        var final_seq: Array = _frames_for_pose(current_by_pose, pose_id)
        if _pose_needs_starter_upgrade(current_pose, starter_pose, final_seq.size(), starter_seq.size()):
            poses[pose_key] = starter_pose.duplicate(true)
            changed_poses = true

    for current_pose_key_v in current_by_pose.keys():
        var current_pose_id: int = int(current_pose_key_v)
        var starter_seq: Array = _frames_for_pose(starter_by_pose, current_pose_id)
        if not starter_seq.is_empty():
            continue
        var current_seq: Array = _frames_for_pose(current_by_pose, current_pose_id)
        var current_pose_v: Variant = poses.get(str(current_pose_id), null)
        var current_pose: Dictionary = {}
        if typeof(current_pose_v) == TYPE_DICTIONARY:
            current_pose = current_pose_v
        if _pose_should_use_mirrored_frames(current_pose) and _frame_sequence_is_legacy_placeholder(current_seq):
            current_by_pose.erase(current_pose_id)
            changed_frames = true

    if changed_frames or changed_meta:
        frames = _flatten_frames_by_pose(current_by_pose, frames, starter_frames)
        frames_data["frames"] = frames
        _write_json(user_frames_path(pack_id), frames_data)
    if changed_poses:
        poses_data["poses"] = poses
        _write_json(user_poses_path(pack_id), poses_data)
    return {"frames": frames_data, "poses": poses_data}


static func _starter_frame_entries() -> Array:
    return [
        {"pose": 0, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 1, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 9, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 25, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 37, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 41, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 47, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 53, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 59, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 67, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 75, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 135, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 164, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 166, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 201, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 203, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 205, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 207, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 209, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
        {"pose": 211, "layers": [{"sheet": BASE_SHEET_ID, "index": 0}]},
    ]


static func _looks_like_legacy_placeholder_frames(frames_data: Dictionary) -> bool:
    var frame_w: int = int(frames_data.get("frame_width", DEFAULT_FRAME_W))
    var frame_h: int = int(frames_data.get("frame_height", DEFAULT_FRAME_H))
    if frame_w != DEFAULT_FRAME_W or frame_h != DEFAULT_FRAME_H:
        return false
    var frames_v: Variant = frames_data.get("frames", [])
    if typeof(frames_v) != TYPE_ARRAY:
        return false
    var frames: Array = frames_v
    if frames.size() > 24:
        return false
    if frames.is_empty():
        return false
    for frame_v in frames:
        var entry: Dictionary = normalize_frame_entry(frame_v)
        var layers: Array = normalize_frame_layers(entry.get("layers", []))
        if layers.size() != 1:
            return false
        var layer: Dictionary = layers[0]
        if str(layer.get("sheet", BASE_SHEET_ID)).strip_edges() != BASE_SHEET_ID:
            return false
        if int(layer.get("index", -1)) != 0:
            return false
    return true


static func _looks_like_legacy_placeholder_poses(poses_data: Dictionary) -> bool:
    var poses_v: Variant = poses_data.get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        return false
    var poses: Dictionary = poses_v
    var stand_v: Variant = poses.get("1", null)
    if typeof(stand_v) != TYPE_DICTIONARY:
        return false
    var stand: Dictionary = stand_v
    var timing_v: Variant = stand.get("timing", [])
    if typeof(timing_v) != TYPE_ARRAY:
        return false
    var timing: Array = timing_v
    return timing.size() == 1 and int(timing[0]) == 60


static func _starter_pose_entries() -> Dictionary:
    var poses: Dictionary = {}

    _add_starter_pose_pair(poses, 1, "stand", 0, [60], 0, -1)
    _add_starter_pose_pair(poses, 9, "run", 1, [8, 8, 8, 8], 0, -1)
    _add_starter_pose_pair(poses, 25, "spin", 3, [5, 5, 5, 5], 0, -1)
    _add_starter_pose_pair(poses, 37, "turn", 14, [4, 4, 4], -1, 2, 1)
    _add_starter_pose_pair(poses, 41, "fall", 6, [8, 8], 0, -1)
    _add_starter_pose_pair(poses, 47, "turn_air", 23, [4, 4, 4], -1, 42, 41)
    _add_starter_pose_pair(poses, 53, "crouch_transition", 15, [4, 4, 4], -1, 67, 68)
    _add_starter_pose_pair(poses, 59, "crouch_aim_up", 5, [60], 0, -1)
    _add_starter_pose_pair(poses, 67, "crouch", 5, [60], 0, -1)
    _add_starter_pose_pair(poses, 75, "jump_rise", 2, [5, 5, 5, 5], 0, -1)
    _add_starter_pose_pair(poses, 135, "turn_fall", 24, [4, 4, 4], -1, 42, 41)
    _add_starter_pose_pair(poses, 164, "land", 15, [4, 4], -1, 1, 2)
    _add_starter_pose_pair(poses, 166, "land_spin", 15, [4, 4], -1, 1, 2)

    poses["0"] = _starter_pose("forward", 1, 0, 16, 0, 24, [60], 0, -1)
    poses["201"] = _starter_pose("melee_1_right", 1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 1)
    poses["202"] = _starter_pose("melee_1_left", -1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 2)
    poses["203"] = _starter_pose("melee_2_right", 1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 1)
    poses["204"] = _starter_pose("melee_2_left", -1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 2)
    poses["205"] = _starter_pose("melee_3_right", 1, 15, 16, 0, 24, [4, 4, 4, 4, 4], -1, 1)
    poses["206"] = _starter_pose("melee_3_left", -1, 15, 16, 0, 24, [4, 4, 4, 4, 4], -1, 2)
    poses["207"] = _starter_pose("ranged_right", 1, 15, 16, 0, 24, [6, 6, 6], -1, 1)
    poses["208"] = _starter_pose("ranged_left", -1, 15, 16, 0, 24, [6, 6, 6], -1, 2)
    poses["209"] = _starter_pose("ranged_charge_right", 1, 15, 16, 0, 24, [5, 5, 5, 5], -1, 1)
    poses["210"] = _starter_pose("ranged_charge_left", -1, 15, 16, 0, 24, [5, 5, 5, 5], -1, 2)
    poses["211"] = _starter_pose("dodge_roll_right", 1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 1)
    poses["212"] = _starter_pose("dodge_roll_left", -1, 15, 16, 0, 24, [4, 4, 4, 4], -1, 2)

    return poses


static func _add_starter_pose_pair(poses: Dictionary, base_id: int, base_name: String, mvtype: int, timing: Array, loop_from: int, transition_to_right: int, transition_to_left: int = -99999) -> void:
    var left_transition: int = transition_to_left
    if left_transition == -99999:
        left_transition = transition_to_right
    poses[str(base_id)] = _starter_pose("%s_right" % base_name, 1, mvtype, 16, 0, 24, timing, loop_from, transition_to_right)
    poses[str(base_id + 1)] = _starter_pose("%s_left" % base_name, -1, mvtype, 16, 0, 24, timing, loop_from, left_transition)


static func _starter_pose(name: String, dir: int, mvtype: int, y_radius: int, y_offset: int, collision_width: int, timing: Array, loop_from: int, transition_to: int) -> Dictionary:
    return {
        "name": name,
        "dir": dir,
        "mvtype": mvtype,
        "y_radius": y_radius,
        "y_offset": y_offset,
        "collision_x": 0,
        "collision_width": collision_width,
        "hurtbox_x": 0,
        "hurtbox_y": -y_radius,
        "hurtbox_w": collision_width,
        "hurtbox_h": y_radius * 2,
        "weapon_anchor_x": 0,
        "weapon_anchor_y": -24,
        "timing": timing.duplicate(),
        "loop_from": loop_from,
        "transition_to": transition_to,
    }


static func _frame_entries_have_pose(entries: Array, pose_id: int) -> bool:
    for entry_v in entries:
        var entry: Dictionary = normalize_frame_entry(entry_v)
        if int(entry.get("pose", -1)) == pose_id:
            return true
    return false


static func _seed_version_is_stale(current_data: Dictionary, starter_data: Dictionary) -> bool:
    return int(current_data.get("seed_version", 0)) < int(starter_data.get("seed_version", 0))


static func _resolved_seed_version(pack_id: String, frames_file: bool) -> int:
    var file_name: String = "player_poses.json"
    if frames_file:
        file_name = "player_frames.json"
    var user_path: String = user_sprites_dir(pack_id) + file_name
    if FileAccess.file_exists(user_path):
        var user_data: Dictionary = _read_json(user_path)
        if not user_data.is_empty() and user_data.has("seed_version"):
            return int(user_data.get("seed_version", 0))
    var shipped_path: String = shipped_sprites_dir(pack_id) + file_name
    if FileAccess.file_exists(shipped_path):
        var shipped_data: Dictionary = _read_json(shipped_path)
        if not shipped_data.is_empty() and shipped_data.has("seed_version"):
            return int(shipped_data.get("seed_version", 0))
    var starter_data: Dictionary = default_poses_data()
    if frames_file:
        starter_data = default_frames_data()
    return int(starter_data.get("seed_version", 0))


static func _frame_metadata_looks_legacy(frames_data: Dictionary) -> bool:
    return (
        int(frames_data.get("frame_width", DEFAULT_FRAME_W)) == DEFAULT_FRAME_W
        and int(frames_data.get("frame_height", DEFAULT_FRAME_H)) == DEFAULT_FRAME_H
        and int(frames_data.get("center_x", DEFAULT_CENTER_X)) == DEFAULT_CENTER_X
        and int(frames_data.get("center_y", DEFAULT_CENTER_Y)) == DEFAULT_CENTER_Y
    )


static func _group_frames_by_pose(entries: Array) -> Dictionary:
    var grouped: Dictionary = {}
    for entry_v in entries:
        var entry: Dictionary = normalize_frame_entry(entry_v)
        var pose_id: int = int(entry.get("pose", -1))
        if pose_id < 0:
            continue
        var seq: Array = _frames_for_pose(grouped, pose_id)
        seq.append(entry.duplicate(true))
        grouped[pose_id] = seq
    return grouped


static func _frames_for_pose(grouped: Dictionary, pose_id: int) -> Array:
    var seq_v: Variant = grouped.get(pose_id, [])
    if typeof(seq_v) == TYPE_ARRAY:
        return seq_v
    return []


static func _frame_sequence_needs_starter_upgrade(current_seq: Array, starter_seq: Array) -> bool:
    if starter_seq.is_empty():
        return false
    if current_seq.is_empty():
        return true
    if _frame_sequence_is_legacy_placeholder(current_seq):
        if current_seq.size() != starter_seq.size():
            return true
        return not _frame_entries_match(current_seq[0], starter_seq[0])
    return false


static func _frame_sequence_is_legacy_placeholder(seq: Array) -> bool:
    if seq.is_empty():
        return false
    for entry_v in seq:
        var entry: Dictionary = normalize_frame_entry(entry_v)
        var layers: Array = normalize_frame_layers(entry.get("layers", []))
        if layers.size() != 1:
            return false
        var layer: Dictionary = layers[0]
        if str(layer.get("sheet", BASE_SHEET_ID)).strip_edges() != BASE_SHEET_ID:
            return false
        if int(layer.get("index", -1)) != 0:
            return false
    return true


static func _frame_entries_match(a_v: Variant, b_v: Variant) -> bool:
    var a: Dictionary = normalize_frame_entry(a_v)
    var b: Dictionary = normalize_frame_entry(b_v)
    if absf(float(a.get("rotation_deg", 0.0)) - float(b.get("rotation_deg", 0.0))) > 0.001:
        return false
    var a_layers: Array = normalize_frame_layers(a.get("layers", []))
    var b_layers: Array = normalize_frame_layers(b.get("layers", []))
    if a_layers.size() != b_layers.size():
        return false
    var idx: int = 0
    while idx < a_layers.size():
        var a_layer: Dictionary = a_layers[idx]
        var b_layer: Dictionary = b_layers[idx]
        if str(a_layer.get("sheet", BASE_SHEET_ID)).strip_edges() != str(b_layer.get("sheet", BASE_SHEET_ID)).strip_edges():
            return false
        if int(a_layer.get("index", -1)) != int(b_layer.get("index", -1)):
            return false
        idx += 1
    return true


static func _pose_needs_starter_upgrade(current_pose: Dictionary, starter_pose: Dictionary, current_frame_count: int, starter_frame_count: int) -> bool:
    if current_pose.is_empty():
        return true
    var current_timing_v: Variant = current_pose.get("timing", [])
    var starter_timing_v: Variant = starter_pose.get("timing", [])
    var current_timing: Array = []
    if typeof(current_timing_v) == TYPE_ARRAY:
        current_timing = current_timing_v
    var starter_timing: Array = []
    if typeof(starter_timing_v) == TYPE_ARRAY:
        starter_timing = starter_timing_v
    if _timing_is_legacy_placeholder(current_timing):
        if starter_timing.size() > 1:
            return true
        if starter_frame_count > 0 and current_frame_count != starter_frame_count:
            return true
    return false


static func _timing_is_legacy_placeholder(timing: Array) -> bool:
    return timing.size() == 1 and int(timing[0]) == 60


static func _pose_should_use_mirrored_frames(pose: Dictionary) -> bool:
    if pose.is_empty():
        return false
    var pose_name: String = str(pose.get("name", ""))
    if pose_name.ends_with("_left"):
        return true
    if pose_name.ends_with("_right"):
        return false
    return int(pose.get("dir", 1)) < 0


static func _flatten_frames_by_pose(grouped: Dictionary, current_entries: Array, starter_entries: Array) -> Array:
    var ordered_pose_ids: Array = []
    _append_pose_order_from_entries(ordered_pose_ids, current_entries)
    _append_pose_order_from_entries(ordered_pose_ids, starter_entries)
    for pose_key_v in grouped.keys():
        var pose_id: int = int(pose_key_v)
        if ordered_pose_ids.has(pose_id):
            continue
        ordered_pose_ids.append(pose_id)
    ordered_pose_ids.sort()

    var out: Array = []
    for pose_id_v in ordered_pose_ids:
        var pose_id: int = int(pose_id_v)
        var seq: Array = _frames_for_pose(grouped, pose_id)
        for entry_v in seq:
            out.append(normalize_frame_entry(entry_v))
    return out


static func _append_pose_order_from_entries(order: Array, entries: Array) -> void:
    for entry_v in entries:
        var entry: Dictionary = normalize_frame_entry(entry_v)
        var pose_id: int = int(entry.get("pose", -1))
        if pose_id < 0 or order.has(pose_id):
            continue
        order.append(pose_id)


static func _sort_preset_entries_by_name(entries: Array) -> void:
    var i: int = 0
    while i < entries.size():
        var best_idx: int = i
        var j: int = i + 1
        while j < entries.size():
            if _preset_entry_name(entries[j]) < _preset_entry_name(entries[best_idx]):
                best_idx = j
            j += 1
        if best_idx != i:
            var tmp: Variant = entries[i]
            entries[i] = entries[best_idx]
            entries[best_idx] = tmp
        i += 1


static func _preset_entry_name(entry_v: Variant) -> String:
    if typeof(entry_v) != TYPE_DICTIONARY:
        return ""
    var entry: Dictionary = entry_v
    return str(entry.get("name", "")).to_lower()


# JSON + file helpers

static func _read_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    return raw


static func _preset_manifest_path(base_dir: String, preset_id: String) -> String:
    return base_dir + PRESET_ROOT_DIR + "/" + preset_id + "/preset.json"


static func _collect_presets_from_base(base_dir: String, merged: Dictionary) -> void:
    var presets_dir: String = base_dir + PRESET_ROOT_DIR
    if not DirAccess.dir_exists_absolute(presets_dir):
        return
    var dir := DirAccess.open(presets_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var entry := dir.get_next()
        if entry.is_empty():
            break
        if entry.begins_with(".") or not dir.current_is_dir():
            continue
        var manifest_path := presets_dir + "/" + entry + "/preset.json"
        if not FileAccess.file_exists(manifest_path):
            continue
        var manifest := _read_json(manifest_path)
        if manifest.is_empty():
            continue
        var preset_id: String = str(manifest.get("id", entry)).strip_edges()
        if preset_id.is_empty() or merged.has(preset_id):
            continue
        merged[preset_id] = manifest
    dir.list_dir_end()


static func _validate_poses_data(data: Dictionary) -> bool:
    var poses_v: Variant = data.get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        push_error("PspIO: player_poses.json must contain a 'poses' dictionary")
        return false
    var poses: Dictionary = poses_v
    for key in poses.keys():
        var pose_id: String = str(key)
        if not pose_id.is_valid_int():
            push_error("PspIO: pose id '%s' is not numeric" % pose_id)
            return false
        var pose_v: Variant = poses[key]
        if typeof(pose_v) != TYPE_DICTIONARY:
            push_error("PspIO: pose '%s' must be a dictionary" % pose_id)
            return false
        var pose: Dictionary = pose_v
        if int(pose.get("dir", 0)) != 1 and int(pose.get("dir", 0)) != -1:
            push_error("PspIO: pose '%s' must use dir 1 or -1" % pose_id)
            return false
        if int(pose.get("y_radius", 0)) < 2:
            push_error("PspIO: pose '%s' must use y_radius >= 2" % pose_id)
            return false
        if int(pose.get("collision_width", 0)) < 1:
            push_error("PspIO: pose '%s' must use collision_width >= 1" % pose_id)
            return false
        if int(pose.get("hurtbox_w", 0)) < 1 or int(pose.get("hurtbox_h", 0)) < 1:
            push_error("PspIO: pose '%s' must use positive hurtbox dimensions" % pose_id)
            return false
        var timing_v: Variant = pose.get("timing", [])
        if typeof(timing_v) != TYPE_ARRAY:
            push_error("PspIO: pose '%s' must define at least one timing entry" % pose_id)
            return false
        var timing: Array = timing_v
        if timing.is_empty():
            push_error("PspIO: pose '%s' must define at least one timing entry" % pose_id)
            return false
        for frame_ticks in timing:
            if int(frame_ticks) < 1:
                push_error("PspIO: pose '%s' uses timing values < 1" % pose_id)
                return false
        if float(pose.get("anim_speed", 1.0)) <= 0.0:
            push_error("PspIO: pose '%s' must use anim_speed > 0" % pose_id)
            return false
        var frame_boxes_v: Variant = pose.get("frame_boxes", [])
        if typeof(frame_boxes_v) != TYPE_ARRAY:
            push_error("PspIO: pose '%s' frame_boxes must be an array" % pose_id)
            return false
        var frame_boxes: Array = frame_boxes_v
        for box_v in frame_boxes:
            if typeof(box_v) != TYPE_DICTIONARY:
                push_error("PspIO: pose '%s' frame_boxes entries must be dictionaries" % pose_id)
                return false
            var box: Dictionary = box_v
            for box_key in ["y_radius", "y_offset", "collision_x", "collision_width", "hurtbox_x", "hurtbox_y", "hurtbox_w", "hurtbox_h"]:
                if box.has(box_key) and not _is_int_like(box.get(box_key, null)):
                    push_error("PspIO: pose '%s' frame_boxes.%s must be an int" % [pose_id, box_key])
                    return false
    return true


static func _normalize_poses_data(data: Dictionary) -> Dictionary:
    var out: Dictionary = data.duplicate(true)
    var poses_v: Variant = out.get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        return out
    var poses: Dictionary = poses_v
    var normalized_poses: Dictionary = {}
    var int_fields: Array = [
        "dir", "mvtype", "y_radius", "y_offset", "collision_x", "collision_width",
        "hurtbox_x", "hurtbox_y", "hurtbox_w", "hurtbox_h",
        "weapon_anchor_x", "weapon_anchor_y", "loop_from", "transition_to",
    ]
    var box_fields: Array = [
        "y_radius", "y_offset", "collision_x", "collision_width",
        "hurtbox_x", "hurtbox_y", "hurtbox_w", "hurtbox_h",
    ]
    for key in poses.keys():
        var pose_id: String = str(key).strip_edges()
        var pose_v: Variant = poses[key]
        if typeof(pose_v) != TYPE_DICTIONARY:
            normalized_poses[pose_id] = pose_v
            continue
        var pose: Dictionary = (pose_v as Dictionary).duplicate(true)
        for field_v in int_fields:
            var field: String = str(field_v)
            if pose.has(field):
                pose[field] = _normalized_int(pose.get(field, 0), 0)

        var timing_v: Variant = pose.get("timing", [])
        var normalized_timing: Array = []
        if typeof(timing_v) == TYPE_ARRAY:
            for tick_v in timing_v:
                normalized_timing.append(_normalized_int(tick_v, 0))
        pose["timing"] = normalized_timing
        pose["anim_speed"] = _normalized_float(pose.get("anim_speed", 1.0), 1.0)

        var frame_boxes_v: Variant = pose.get("frame_boxes", [])
        var normalized_boxes: Array = []
        if typeof(frame_boxes_v) == TYPE_ARRAY:
            for box_v in frame_boxes_v:
                if typeof(box_v) != TYPE_DICTIONARY:
                    normalized_boxes.append({})
                    continue
                var box: Dictionary = box_v
                var normalized_box: Dictionary = {}
                for field_v in box_fields:
                    var field: String = str(field_v)
                    if box.has(field):
                        normalized_box[field] = _normalized_int(box.get(field, 0), 0)
                normalized_boxes.append(normalized_box)
        pose["frame_boxes"] = normalized_boxes
        normalized_poses[pose_id] = pose
    out["poses"] = normalized_poses
    return out


static func _normalized_int(value: Variant, fallback: int) -> int:
    match typeof(value):
        TYPE_INT, TYPE_FLOAT:
            return int(value)
        _:
            var text: String = str(value).strip_edges()
            if text.is_valid_int():
                return int(text)
    return fallback


static func _normalized_float(value: Variant, fallback: float) -> float:
    match typeof(value):
        TYPE_INT, TYPE_FLOAT:
            return float(value)
        _:
            var text: String = str(value).strip_edges()
            if text.is_valid_float():
                return float(text)
    return fallback


static func _is_int_like(value: Variant) -> bool:
    match typeof(value):
        TYPE_INT:
            return true
        TYPE_FLOAT:
            return is_equal_approx(value, round(value))
        _:
            return str(value).strip_edges().is_valid_int()


static func _write_json(path: String, data: Dictionary) -> bool:
    var slash := path.rfind("/")
    if slash > 0:
        DirAccess.make_dir_recursive_absolute(path.substr(0, slash))
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("PspIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


static func _write_missing_json(path: String, data: Dictionary, changed: Array) -> bool:
    if FileAccess.file_exists(path):
        return false
    if not _write_json(path, data):
        return false
    changed.append(path)
    return true


static func _write_missing_starter_sheet(path: String, changed: Array) -> bool:
    if FileAccess.file_exists(path):
        return false
    var slash := path.rfind("/")
    if slash > 0:
        DirAccess.make_dir_recursive_absolute(path.substr(0, slash))
    var img := _create_starter_sheet_image()
    var err := img.save_png(path)
    if err != OK:
        push_error("PspIO: cannot write starter sheet '%s' (err=%d)" % [path, err])
        return false
    changed.append(path)
    return true


static func _create_starter_sheet_image() -> Image:
    var sheet_w := DEFAULT_FRAME_W * DEFAULT_SHEET_COLS
    var sheet_h := DEFAULT_FRAME_H * DEFAULT_SHEET_COLS
    var img := Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for i in range(DEFAULT_SHEET_COLS * DEFAULT_SHEET_COLS):
        var cell_x := (i % DEFAULT_SHEET_COLS) * DEFAULT_FRAME_W
        var cell_y := int(i / DEFAULT_SHEET_COLS) * DEFAULT_FRAME_H
        _draw_starter_cell(img, cell_x, cell_y, i)
    return img


static func _draw_starter_cell(img: Image, cell_x: int, cell_y: int, index: int) -> void:
    var suit := Color(0.20, 0.72, 0.95, 1.0)
    var visor := Color(1.0, 0.86, 0.28, 1.0)
    var trim := Color(0.08, 0.16, 0.24, 1.0)
    var shade := Color(0.05, 0.40, 0.62, 1.0)
    var pulse := float(index % 4) * 0.04
    _fill_rect_pixels(img, Rect2i(cell_x + 19, cell_y + 7, 12, 9), suit.lightened(pulse))
    _fill_rect_pixels(img, Rect2i(cell_x + 22, cell_y + 10, 9, 3), visor)
    _fill_rect_pixels(img, Rect2i(cell_x + 17, cell_y + 16, 16, 17), suit)
    _fill_rect_pixels(img, Rect2i(cell_x + 20, cell_y + 19, 10, 10), shade)
    _fill_rect_pixels(img, Rect2i(cell_x + 14, cell_y + 18, 5, 12), trim)
    _fill_rect_pixels(img, Rect2i(cell_x + 32, cell_y + 18, 5, 12), trim)
    _fill_rect_pixels(img, Rect2i(cell_x + 19, cell_y + 33, 4, 8), trim)
    _fill_rect_pixels(img, Rect2i(cell_x + 28, cell_y + 33, 4, 8), trim)


static func _fill_rect_pixels(img: Image, rect: Rect2i, color: Color) -> void:
    for y in range(rect.position.y, rect.position.y + rect.size.y):
        for x in range(rect.position.x, rect.position.x + rect.size.x):
            if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
                img.set_pixel(x, y, color)


static func _copy_file(src_path: String, dst_path: String) -> bool:
    var src := FileAccess.open(src_path, FileAccess.READ)
    if src == null:
        return false
    var bytes := src.get_buffer(src.get_length())
    src.close()
    var slash := dst_path.rfind("/")
    if slash > 0:
        DirAccess.make_dir_recursive_absolute(dst_path.substr(0, slash))
    var dst := FileAccess.open(dst_path, FileAccess.WRITE)
    if dst == null:
        return false
    dst.store_buffer(bytes)
    dst.close()
    return true


static func _copy_preset_sheet_files(pack_id: String, preset_dir: String, frames_data: Dictionary) -> bool:
    if preset_dir.is_empty():
        return true
    for sheet_def_v in normalize_sheet_defs(frames_data.get("sheets", [])):
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var file_name: String = str(sheet_def.get("file", "")).strip_edges()
        if file_name.is_empty():
            continue
        var src_path: String = preset_dir + file_name
        if not FileAccess.file_exists(src_path):
            continue
        var dst_path: String = user_sheet_path_for_file(pack_id, file_name)
        if not _copy_file(src_path, dst_path):
            push_error("PspIO: failed to copy preset sheet '%s' into '%s'" % [src_path, dst_path])
            return false
    return true


static func _copy_current_pack_sheet_files_to_preset(pack_id: String, preset_dir: String, frames_data: Dictionary) -> bool:
    for sheet_def_v in normalize_sheet_defs(frames_data.get("sheets", [])):
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var file_name: String = str(sheet_def.get("file", "")).strip_edges()
        if file_name.is_empty():
            continue
        var src_path: String = resolved_sheet_path_for_file(pack_id, file_name)
        if not FileAccess.file_exists(src_path):
            push_error("PspIO: current sheet '%s' not found while overwriting preset" % file_name)
            return false
        var dst_path: String = preset_dir + file_name
        if not _copy_file(src_path, dst_path):
            push_error("PspIO: failed to copy current sheet '%s' into preset '%s'" % [src_path, dst_path])
            return false
    return true


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)
