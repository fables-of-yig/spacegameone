extends RefCounted

# Pure IO for the audio editor. Reads/writes the pack's
# Audio/clips.json registry, enumerates .ogg files under Audio/, and
# handles OGG imports from absolute OS paths.
#
# Mirrors ent_io.gd's dual-layer resolution: writes land in the user
# override layer, reads fall back to the shipped layer.


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % pack_id


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func clips_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Audio/clips.json"


static func shipped_clips_json_path(pack_id: String) -> String:
    return shipped_pack_dir(pack_id) + "Audio/clips.json"


# Loads clips.json. Prefers the user override layer, falls back to the
# shipped layer, else returns an empty registry.
static func load_or_init(pack_id: String) -> Dictionary:
    _ensure_dir(user_pack_dir(pack_id) + "Audio")
    var user_path := clips_json_path(pack_id)
    if FileAccess.file_exists(user_path):
        return _read_json(user_path)
    var shipped_path := shipped_clips_json_path(pack_id)
    if FileAccess.file_exists(shipped_path):
        return _read_json(shipped_path)
    return {"clips": []}


static func save_clips(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "Audio")
    var path := clips_json_path(pack_id)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("AudIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


# Lists every Audio/<folder>/ that contains at least one .ogg file,
# resolved across the user + shipped layers and de-duped. Folder paths
# are returned as pack-relative strings (e.g. "Audio/footsteps").
static func list_audio_folders(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var audio_dir: String = base + "Audio"
        var d := DirAccess.open(audio_dir)
        if d == null:
            continue
        d.list_dir_begin()
        var fn := d.get_next()
        while fn != "":
            if d.current_is_dir() and not fn.begins_with("."):
                var rel := "Audio/" + fn
                if not seen.has(rel):
                    if _folder_has_ogg(base + rel):
                        seen[rel] = true
                        out.append(rel)
            fn = d.get_next()
        d.list_dir_end()
    out.sort()
    return out


# Lists the .ogg filenames inside a specific Audio/<folder>/, preferring
# the user layer then falling back to the shipped layer.
static func list_oggs_in_folder(pack_id: String, folder_rel: String) -> Array:
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var full: String = base + folder_rel
        var d := DirAccess.open(full)
        if d == null:
            continue
        var out: Array = []
        d.list_dir_begin()
        var fn := d.get_next()
        while fn != "":
            if not d.current_is_dir() and fn.to_lower().ends_with(".ogg"):
                out.append(fn)
            fn = d.get_next()
        d.list_dir_end()
        out.sort()
        if not out.is_empty():
            return out
    return []


# Resolves where an OGG would land if copied into an Audio subfolder.
# Used by the conflict pre-flight in audio_editor.gd.
static func audio_dest_path(pack_id: String, folder_rel: String,
        source_abs_path: String, dest_filename: String = "") -> String:
    var base := dest_filename if dest_filename != "" else source_abs_path.get_file()
    if not base.to_lower().ends_with(".ogg"):
        base += ".ogg"
    return user_pack_dir(pack_id) + folder_rel + "/" + base


# Copies an OGG from an absolute OS path into an Audio subfolder under
# the user override layer. Creates the folder if missing. Always
# overwrites — the caller is expected to run the conflict pre-flight
# before calling this.
#
# Streams the copy in 1 MB chunks so arbitrarily-large tracks don't
# have to fit in memory as a single PackedByteArray allocation.
static func import_ogg(pack_id: String, folder_rel: String,
        source_abs_path: String, dest_filename: String = "") -> bool:
    if pack_id == "" or folder_rel == "" or source_abs_path == "":
        return false
    _ensure_dir(user_pack_dir(pack_id) + folder_rel)
    var src := FileAccess.open(source_abs_path, FileAccess.READ)
    if src == null:
        push_error("AudIO: cannot open source OGG '%s'" % source_abs_path)
        return false
    var dest_path := audio_dest_path(pack_id, folder_rel,
        source_abs_path, dest_filename)
    var dst := FileAccess.open(dest_path, FileAccess.WRITE)
    if dst == null:
        src.close()
        push_error("AudIO: cannot open dest OGG '%s' for write" % dest_path)
        return false
    var total: int = src.get_length()
    var copied: int = 0
    var chunk_size: int = 1 << 20  # 1 MB
    while copied < total:
        var remaining: int = total - copied
        var to_read: int = mini(chunk_size, remaining)
        var bytes := src.get_buffer(to_read)
        if bytes.is_empty():
            break
        dst.store_buffer(bytes)
        copied += bytes.size()
    src.close()
    dst.close()
    if copied == 0:
        push_error("AudIO: source OGG '%s' was empty" % source_abs_path)
        return false
    if copied != total:
        push_warning("AudIO: import copied %d/%d bytes from '%s'" \
            % [copied, total, source_abs_path])
    else:
        print("[AudIO] imported %d bytes from '%s'" % [copied, source_abs_path])
    return true


# Loads an OGG file into an AudioStreamOggVorbis. Prefers user layer,
# falls back to the shipped layer. Returns null if neither exists.
static func load_ogg_stream(pack_id: String, file_rel: String) -> AudioStream:
    for base in [user_pack_dir(pack_id), shipped_pack_dir(pack_id)]:
        var path: String = base + file_rel
        if not FileAccess.file_exists(path):
            continue
        var stream := AudioStreamOggVorbis.load_from_file(path)
        if stream != null:
            return stream
    return null


# Default clip dict for new registry entries.
static func default_clip(id: String, file_rel: String = "") -> Dictionary:
    return {
        "id": id,
        "file": file_rel,
        "start_sec": 0.0,
        "end_sec": -1.0,
        "tags": [],
    }


static func _folder_has_ogg(path: String) -> bool:
    var d := DirAccess.open(path)
    if d == null:
        return false
    d.list_dir_begin()
    var fn := d.get_next()
    while fn != "":
        if not d.current_is_dir() and fn.to_lower().ends_with(".ogg"):
            d.list_dir_end()
            return true
        fn = d.get_next()
    d.list_dir_end()
    return false


static func _read_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {"clips": []}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {"clips": []}
    if not raw.has("clips") or typeof(raw["clips"]) != TYPE_ARRAY:
        raw["clips"] = []
    return raw


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)
