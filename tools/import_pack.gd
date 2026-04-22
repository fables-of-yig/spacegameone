extends SceneTree

# import_pack.gd — Drop external asset packs into a SpaceboatMania content pack.
#
# Walks a source folder (typically D:/SpaceAssetsNoisey/<pack-name>/), detects
# the layout (character, tileset, or spaceship pack), copies the PNGs into
# the right destination under res://Content/<pack-id>/ or res://Space/art/,
# and (for character packs) appends entity definitions to entities.json so
# the new sprites show up in the LevelEditor placement palette immediately.
#
# Usage:
#   godot --headless --script res://tools/import_pack.gd -- \
#       --source "D:/SpaceAssetsNoisey/basement-enemies-pixel-art-sprite-pack" \
#       --pack demo
#   godot --headless --script res://tools/import_pack.gd -- \
#       --source "D:/SpaceAssetsNoisey/basement-tileset-pixel-art" \
#       --pack demo
#   godot --headless --script res://tools/import_pack.gd -- \
#       --source "D:/SpaceAssetsNoisey/Enemy_SpaceShip_Game_Sprites" \
#       --pack demo
#
# After ingesting, run:
#   godot --headless --import
# to refresh Godot's resource import cache so the new PNGs become loadable.
#
# Pattern detection:
#   - Numbered subfolders (1/, 2/, 3/) with PNGs inside → CHARACTER pack.
#     Each numbered folder becomes one entity sprite_set. PNG filenames
#     become animation names (Idle.png → idle, Walk.png → walk, etc.).
#   - PNG/Ships/ subfolder with Ship_NN.png files → SPACESHIP pack.
#     Copies into res://Space/art/ships/<pack-slug>/ for SSB to pick up
#     via npc_ship/enemy_ship static_hull paths.
#   - Tile_NN.png files at root or "Tiles" subfolder → TILESET pack.
#     Finds Tiles.png (full atlas) if present, copies to tileset_NN_atlas.png
#     plus _lo and _hi variants (priority split is identity for now —
#     fix later via the priority-mask workflow).

const USAGE = """
import_pack.gd — Asset pack ingester for SpaceboatMania.

Usage:
  godot --headless --script res://tools/import_pack.gd -- \\
      --source <abs-path> --pack <pack-id> \\
      [--type <auto|character|tileset|spaceship>]

Examples:
  --source "D:/SpaceAssetsNoisey/basement-enemies-pixel-art-sprite-pack" --pack demo
  --source "D:/SpaceAssetsNoisey/basement-tileset-pixel-art" --pack demo
  --source "D:/SpaceAssetsNoisey/Enemy_SpaceShip_Game_Sprites" --pack demo

Run 'godot --headless --import' after ingestion to refresh the import cache.
"""

func _init():
    var args = OS.get_cmdline_user_args()
    var source: String = ""
    var pack_id: String = ""
    var pack_type: String = "auto"

    var i := 0
    while i < args.size():
        var a: String = args[i]
        match a:
            "--source":
                if i + 1 < args.size():
                    source = args[i + 1]
                i += 2
            "--pack":
                if i + 1 < args.size():
                    pack_id = args[i + 1]
                i += 2
            "--type":
                if i + 1 < args.size():
                    pack_type = args[i + 1]
                i += 2
            "--help", "-h":
                print(USAGE)
                quit(0)
                return
            _:
                i += 1

    if source == "" or pack_id == "":
        print(USAGE)
        quit(1)
        return

    if not DirAccess.dir_exists_absolute(source):
        push_error("import_pack: source not found: " + source)
        quit(1)
        return

    var pack_dir := "res://Content/" + pack_id
    if not DirAccess.dir_exists_absolute(pack_dir):
        push_error("import_pack: pack '" + pack_id + "' does not exist at " + pack_dir)
        push_error("Create it manually first by copying res://Content/demo as a template.")
        quit(1)
        return

    var detected: String = pack_type
    if detected == "auto":
        detected = _detect_pack_type(source)

    print("import_pack: source='%s' pack='%s' type='%s'" % [source, pack_id, detected])

    var imported: Array = []
    match detected:
        "character":
            imported = _import_character_pack(source, pack_id)
        "tileset":
            imported = _import_tileset_pack(source, pack_id)
        "spaceship":
            imported = _import_spaceship_pack(source, pack_id)
        _:
            push_error("import_pack: unknown pack type '" + detected + "' — pass --type explicitly")
            quit(1)
            return

    print("import_pack: imported %d item(s):" % imported.size())
    for item in imported:
        print("  - " + str(item))
    print("import_pack: done. Run 'godot --headless --import' to refresh imports.")
    quit(0)

# ─── Pattern detection ────────────────────────────────────────────────────

func _detect_pack_type(source: String) -> String:
    var has_numbered_dirs := false
    var has_tiles_atlas := false
    var has_tile_files := false
    var has_png_ships := false

    var d := DirAccess.open(source)
    if d == null:
        return "unknown"

    d.list_dir_begin()
    while true:
        var entry := d.get_next()
        if entry == "":
            break
        if d.current_is_dir():
            if entry.is_valid_int():
                has_numbered_dirs = true
            if entry == "PNG":
                if DirAccess.dir_exists_absolute(source + "/PNG/Ships"):
                    has_png_ships = true
            if entry.findn("tile") >= 0:
                has_tiles_atlas = true
        else:
            if entry.begins_with("Tile_") and entry.to_lower().ends_with(".png"):
                has_tile_files = true
    d.list_dir_end()

    if has_png_ships:
        return "spaceship"
    if has_numbered_dirs:
        # Disambiguate: if the numbered dirs look like enemy/character folders
        # (have Idle.png / Walk.png inside), call it character.
        var first_num := _first_numbered_subdir(source)
        if first_num != "":
            var nd := DirAccess.open(first_num)
            if nd != null:
                nd.list_dir_begin()
                while true:
                    var fn := nd.get_next()
                    if fn == "":
                        break
                    if not nd.current_is_dir() and fn.to_lower().ends_with(".png"):
                        nd.list_dir_end()
                        return "character"
                nd.list_dir_end()
    if has_tile_files or has_tiles_atlas:
        return "tileset"
    return "unknown"

func _first_numbered_subdir(source: String) -> String:
    var d := DirAccess.open(source)
    if d == null:
        return ""
    d.list_dir_begin()
    while true:
        var entry := d.get_next()
        if entry == "":
            break
        if d.current_is_dir() and entry.is_valid_int():
            d.list_dir_end()
            return source + "/" + entry
    d.list_dir_end()
    return ""

# ─── Importers ────────────────────────────────────────────────────────────

func _import_character_pack(source: String, pack_id: String) -> Array:
    var imported: Array = []
    var pack_slug := _slugify(source.get_file())
    var sprites_dir := "res://Content/" + pack_id + "/Sprites"
    DirAccess.make_dir_recursive_absolute(sprites_dir)

    var d := DirAccess.open(source)
    if d == null:
        return imported

    var subdirs: Array = []
    d.list_dir_begin()
    while true:
        var entry := d.get_next()
        if entry == "":
            break
        if d.current_is_dir() and not entry.begins_with("."):
            subdirs.append(entry)
    d.list_dir_end()
    subdirs.sort()

    var entries_to_add: Array = []

    for sub in subdirs:
        var sub_path: String = source + "/" + sub
        var sub_slug: String = _slugify(sub)
        var sprite_set_name: String = pack_slug + "_" + sub_slug
        var dest: String = sprites_dir + "/" + sprite_set_name
        DirAccess.make_dir_recursive_absolute(dest)

        var sub_d := DirAccess.open(sub_path)
        if sub_d == null:
            continue
        var copied_anims: Array = []
        sub_d.list_dir_begin()
        while true:
            var fn: String = sub_d.get_next()
            if fn == "":
                break
            if sub_d.current_is_dir():
                continue
            if not fn.to_lower().ends_with(".png"):
                continue
            var lower: String = fn.to_lower()
            var src_file: String = sub_path + "/" + fn
            var dst_file: String = dest + "/" + lower
            if _copy_file(src_file, dst_file):
                copied_anims.append(lower.get_basename())
        sub_d.list_dir_end()

        if copied_anims.size() == 0:
            continue

        var entity_id: String = pack_slug + "_" + sub_slug
        var sprite_set_rel: String = "Sprites/" + sprite_set_name
        var anims_str: String = ""
        for k in range(copied_anims.size()):
            if k > 0:
                anims_str += ", "
            anims_str += String(copied_anims[k])
        entries_to_add.append({
            "id": entity_id,
            "name": (pack_slug + " " + sub_slug).replace("_", " ").capitalize(),
            "description": "Imported from %s/%s — animations: %s" % [source.get_file(), sub, anims_str],
            "scene": "res://Scenes/Enemy.tscn",
            "category": "enemy",
            "sprite_set": sprite_set_rel,
        })
        imported.append("%s (%d anims)" % [entity_id, copied_anims.size()])

    if entries_to_add.size() > 0:
        _append_to_entities_json(pack_id, entries_to_add)
    return imported

func _import_tileset_pack(source: String, pack_id: String) -> Array:
    var imported: Array = []
    var tilesets_dir := "res://Content/" + pack_id + "/Tilesets"
    DirAccess.make_dir_recursive_absolute(tilesets_dir)

    var next_idx := _next_tileset_index(tilesets_dir)

    # Look for a full atlas first ("Tiles.png" or any *Tiles.png variant).
    var atlas_path := _find_first_file(source, "Tiles.png")
    if atlas_path == "":
        atlas_path = _find_first_file(source, "tiles.png")

    if atlas_path != "":
        var dest_atlas := tilesets_dir + "/tileset_%02d_atlas.png" % next_idx
        var dest_lo    := tilesets_dir + "/tileset_%02d_atlas_lo.png" % next_idx
        var dest_hi    := tilesets_dir + "/tileset_%02d_atlas_hi.png" % next_idx
        _copy_file(atlas_path, dest_atlas)
        _copy_file(atlas_path, dest_lo)
        # Hi variant is a transparent placeholder of the same dimensions —
        # nothing renders in front of the player by default. To elevate
        # specific tiles, paint tileset_NN_priority_mask.png alongside the
        # atlas (white pixels over the sub-tiles you want hi-priority) or
        # craft a real _hi.png with the elevated content.
        _write_transparent_image_like(atlas_path, dest_hi)
        # Default priority JSON — zero-mask for all tiles. Replaced at runtime
        # by tileset_NN_priority_mask.png if present.
        var priority_path := tilesets_dir + "/tileset_%02d_priority.json" % next_idx
        var pjf := FileAccess.open(priority_path, FileAccess.WRITE)
        if pjf != null:
            pjf.store_string('{"masks": []}')
            pjf.close()
        imported.append("tileset_%02d (atlas: %s, hi=transparent placeholder)" % [next_idx, atlas_path.get_file()])
    else:
        # No full atlas found; look for Tile_NN.png files and stitch them.
        var tile_files := _find_files_named(source, "Tile_", ".png")
        if tile_files.size() > 0:
            tile_files.sort()
            var stitched := _stitch_tile_files(tile_files)
            if stitched != null:
                var dest_atlas2 := tilesets_dir + "/tileset_%02d_atlas.png" % next_idx
                var dest_lo2    := tilesets_dir + "/tileset_%02d_atlas_lo.png" % next_idx
                var dest_hi2    := tilesets_dir + "/tileset_%02d_atlas_hi.png" % next_idx
                stitched.save_png(dest_atlas2)
                stitched.save_png(dest_lo2)
                stitched.save_png(dest_hi2)
                imported.append("tileset_%02d (stitched %d tiles)" % [next_idx, tile_files.size()])
    return imported

func _import_spaceship_pack(source: String, _pack_id: String) -> Array:
    var imported: Array = []
    var pack_slug := _slugify(source.get_file())
    var dest_dir := "res://Space/art/ships/" + pack_slug
    DirAccess.make_dir_recursive_absolute(dest_dir)

    var ships_dir := source + "/PNG/Ships"
    if DirAccess.dir_exists_absolute(ships_dir):
        var d := DirAccess.open(ships_dir)
        d.list_dir_begin()
        while true:
            var fn: String = d.get_next()
            if fn == "":
                break
            if d.current_is_dir():
                continue
            if not fn.to_lower().ends_with(".png"):
                continue
            if _copy_file(ships_dir + "/" + fn, dest_dir + "/" + fn.to_lower()):
                imported.append(fn)
        d.list_dir_end()
    else:
        # Fallback: walk the source for any PNG and copy flat.
        var pngs := _find_all_pngs(source)
        for p in pngs:
            var leaf := String(p).get_file().to_lower()
            if _copy_file(p, dest_dir + "/" + leaf):
                imported.append(leaf)
    return imported

# ─── Helpers ──────────────────────────────────────────────────────────────

func _write_transparent_image_like(template_path: String, dst_path: String) -> bool:
    var img := Image.new()
    if img.load(template_path) != OK:
        push_warning("transparent_image_like: failed to load template " + template_path)
        return false
    var blank := Image.create(img.get_width(), img.get_height(), false, img.get_format())
    blank.fill(Color(0, 0, 0, 0))
    return blank.save_png(dst_path) == OK

func _copy_file(src: String, dst: String) -> bool:
    var sf := FileAccess.open(src, FileAccess.READ)
    if sf == null:
        push_warning("copy_file: cannot open " + src)
        return false
    var bytes := sf.get_buffer(sf.get_length())
    sf.close()
    var df := FileAccess.open(dst, FileAccess.WRITE)
    if df == null:
        push_warning("copy_file: cannot write " + dst)
        return false
    df.store_buffer(bytes)
    df.close()
    return true

func _find_first_file(search_root: String, name: String) -> String:
    var d := DirAccess.open(search_root)
    if d == null:
        return ""
    d.list_dir_begin()
    while true:
        var entry: String = d.get_next()
        if entry == "":
            break
        var full: String = search_root + "/" + entry
        if d.current_is_dir() and not entry.begins_with("."):
            var nested := _find_first_file(full, name)
            if nested != "":
                d.list_dir_end()
                return nested
        elif entry == name:
            d.list_dir_end()
            return full
    d.list_dir_end()
    return ""

func _find_files_named(search_root: String, prefix: String, suffix: String) -> Array:
    var out: Array = []
    var d := DirAccess.open(search_root)
    if d == null:
        return out
    d.list_dir_begin()
    while true:
        var entry: String = d.get_next()
        if entry == "":
            break
        var full: String = search_root + "/" + entry
        if d.current_is_dir() and not entry.begins_with("."):
            for nested in _find_files_named(full, prefix, suffix):
                out.append(nested)
        elif entry.begins_with(prefix) and entry.to_lower().ends_with(suffix.to_lower()):
            out.append(full)
    d.list_dir_end()
    return out

func _find_all_pngs(search_root: String) -> Array:
    var out: Array = []
    var d := DirAccess.open(search_root)
    if d == null:
        return out
    d.list_dir_begin()
    while true:
        var entry: String = d.get_next()
        if entry == "":
            break
        var full: String = search_root + "/" + entry
        if d.current_is_dir() and not entry.begins_with("."):
            for nested in _find_all_pngs(full):
                out.append(nested)
        elif entry.to_lower().ends_with(".png"):
            out.append(full)
    d.list_dir_end()
    return out

func _stitch_tile_files(tile_files: Array) -> Image:
    if tile_files.size() == 0:
        return null
    var first := Image.new()
    if first.load(tile_files[0]) != OK:
        return null
    var tw := first.get_width()
    var th := first.get_height()
    var cols: int = int(ceil(sqrt(float(tile_files.size()))))
    @warning_ignore("integer_division")
    var rows: int = int(ceil(float(tile_files.size()) / float(cols)))
    var atlas := Image.create(cols * tw, rows * th, false, first.get_format())
    atlas.fill(Color(0, 0, 0, 0))
    for i in tile_files.size():
        var img := Image.new()
        if img.load(tile_files[i]) != OK:
            continue
        var x: int = (i % cols) * tw
        @warning_ignore("integer_division")
        var y: int = (i / cols) * th
        atlas.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i(x, y))
    return atlas

func _next_tileset_index(tilesets_dir: String) -> int:
    var idx := 0
    while idx < 99:
        var test := tilesets_dir + "/tileset_%02d_atlas.png" % idx
        if not FileAccess.file_exists(test):
            return idx
        idx += 1
    return idx

func _append_to_entities_json(pack_id: String, new_entries: Array) -> void:
    var path := "res://Content/" + pack_id + "/Entities/entities.json"
    var existing: Dictionary = {}
    var existing_entities: Array = []

    DirAccess.make_dir_recursive_absolute("res://Content/" + pack_id + "/Entities")

    if FileAccess.file_exists(path):
        var f := FileAccess.open(path, FileAccess.READ)
        if f != null:
            var raw: Variant = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(raw) == TYPE_DICTIONARY:
                existing = raw as Dictionary
                if existing.has("entities") and typeof(existing["entities"]) == TYPE_ARRAY:
                    existing_entities = existing["entities"] as Array

    var existing_ids := {}
    for e in existing_entities:
        if typeof(e) == TYPE_DICTIONARY and e.has("id"):
            existing_ids[e["id"]] = true

    var added := 0
    for ne in new_entries:
        if existing_ids.has(ne["id"]):
            print("  skip duplicate id: " + ne["id"])
            continue
        existing_entities.append(ne)
        added += 1

    existing["entities"] = existing_entities

    var out := FileAccess.open(path, FileAccess.WRITE)
    if out == null:
        push_error("cannot write " + path)
        return
    out.store_string(JSON.stringify(existing, "  "))
    out.close()
    print("entities.json: added %d entry/entries to %s" % [added, path])

func _slugify(s: String) -> String:
    var lower: String = s.to_lower()
    var out: String = ""
    for c in lower:
        if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
            out += c
        elif c == " " or c == "-" or c == "_":
            out += "_"
    while out.find("__") >= 0:
        out = out.replace("__", "_")
    return out
