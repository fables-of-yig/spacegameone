extends RefCounted

# Pure IO functions for the environment editor. Reads/writes rooms.json
# from user://Packs/<pack_id>/Rooms/rooms.json, seeds fresh packs with a
# starter room + a copy of the demo tileset, and exposes tileset discovery
# helpers.
#
# Schema notes (must match MvRoomManager._parse_room_info):
#   top-level: {version, start_room, rooms: {addr -> room}}
#   per room: addr, friendly_name, width_screens, height_screens,
#             width_blocks, height_blocks, width_px, height_px, tileset,
#             tile_layers, collision, bts, slopes, doors, entities, triggers
#
# tile_layers is an ordered array of tile-layer dicts:
#   {name, role, scroll_speed_x, scroll_speed_y, tiles}
# role ∈ {"bg", "main", "fg"} determines runtime z-order (bg behind player,
# main at player z, fg in front). scroll_speed is a per-axis parallax
# multiplier — 1.0 moves with the world, 0.0 stays locked to camera, 0.5
# moves at half speed. Layers of the same role render in array order.
#
# Legacy rooms that still carry layer1/layer1_hi/layer2 + has_layer2 are
# auto-migrated on load by migrate_room_to_layers; the next save writes
# only the new shape.
#
# Tile values are packed via MvTileValue (bits 0-9 idx, 10 hflip,
# 11 vflip, 12-19 tileset id, 20 present flag).

const BLOCK_SIZE: int = 16
const DEFAULT_ROOM_W_BLOCKS: int = 30
const DEFAULT_ROOM_H_BLOCKS: int = 17
const SHIPPED_SEED_PACK: String = "demo"
const TriggerRoot = preload("res://Space/scripts/shared/trigger_root.gd")

const ROLE_BG: String = "bg"
const ROLE_MAIN: String = "main"
const ROLE_FG: String = "fg"

const PARALLAX_DEFAULTS := [
    {"name": "far", "scroll_speed_x": 0.18, "scroll_speed_y": 0.12},
    {"name": "mid", "scroll_speed_x": 0.45, "scroll_speed_y": 0.18},
    {"name": "near", "scroll_speed_x": 0.78, "scroll_speed_y": 0.24},
]


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % pack_id


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func rooms_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Rooms/rooms.json"


static func slope_shapes_path(pack_id: String) -> String:
    var user_path := user_pack_dir(pack_id) + "SlopeShapes.json"
    if FileAccess.file_exists(user_path):
        return user_path
    var shipped_path := shipped_pack_dir(pack_id) + "SlopeShapes.json"
    if FileAccess.file_exists(shipped_path):
        return shipped_path
    var fallback_path := shipped_pack_dir(SHIPPED_SEED_PACK) + "SlopeShapes.json"
    if FileAccess.file_exists(fallback_path):
        return fallback_path
    return ""


static func load_slope_shapes(pack_id: String) -> Array:
    var path := slope_shapes_path(pack_id)
    if path.is_empty():
        return []
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_warning("EnvIO: cannot open %s" % path)
        return []
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        push_warning("EnvIO: invalid slope shape file %s" % path)
        return []
    var shapes_v: Variant = (raw as Dictionary).get("shapes", [])
    if typeof(shapes_v) != TYPE_ARRAY:
        return []
    var out: Array = []
    for shape_v in shapes_v:
        if typeof(shape_v) != TYPE_ARRAY:
            continue
        var row: Array = []
        for y_v in shape_v:
            row.append(int(y_v))
        out.append(row)
    return out


# Loads rooms.json for a user pack. If the file doesn't exist, seeds the
# pack with a default starter room and (if no tilesets are present) copies
# tileset_00 from the shipped demo pack so the editor has something to
# paint with. Returns the full rooms-data dict. All rooms are migrated to
# the tile_layers schema before returning.
static func load_or_init(pack_id: String) -> Dictionary:
    _ensure_dir(user_pack_dir(pack_id) + "Rooms")
    _ensure_dir(user_pack_dir(pack_id) + "Tilesets")
    _seed_tilesets_if_empty(pack_id)

    var path := rooms_json_path(pack_id)
    if not FileAccess.file_exists(path):
        var fresh := default_rooms_data()
        save_rooms(pack_id, fresh)
        return fresh

    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("EnvIO: cannot open %s for read" % path)
        return default_rooms_data()
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        push_error("EnvIO: %s is not a JSON object, reinitializing" % path)
        var fallback := default_rooms_data()
        save_rooms(pack_id, fallback)
        return fallback
    _migrate_rooms_data(raw)
    return raw


static func _migrate_rooms_data(data: Dictionary) -> void:
    var rooms_v: Variant = data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return
    var rooms: Dictionary = rooms_v
    for key in rooms.keys():
        var room_v: Variant = rooms[key]
        if typeof(room_v) == TYPE_DICTIONARY:
            migrate_room_to_layers(room_v)


# Create a new tileset from one or more source PNGs.
#
# Single-file path: byte-copies the PNG verbatim into
# user://Packs/<pack>/Tilesets/tileset_NN_atlas.png — original encoding
# preserved, no re-packing.
#
# Multi-file path: loads every source, walks each one's logical tiles
# (tile_size × tile_size sub-rects), and composes them all into a new
# atlas 16 logical tiles wide (or fewer if the total is < 16). The output
# is saved via Image.save_png.
#
# tile_size is the authoring pixel size of one logical tile (multiple of
# BLOCK_SIZE). Storage stays at 16-px cells; larger tiles paint as N×N
# metatile brushes where N = tile_size / BLOCK_SIZE. When tile_size
# differs from BLOCK_SIZE we write a sidecar tileset_NN_meta.json so the
# editor remembers the slicing next launch.
#
# Returns the new tileset index, or -1 on failure.
static func import_tileset(pack_id: String, src_paths: PackedStringArray, tile_size: int = BLOCK_SIZE) -> int:
    if tile_size < BLOCK_SIZE or tile_size % BLOCK_SIZE != 0:
        push_error("EnvIO: tile_size must be ≥ %d and a multiple of %d (got %d)" % [BLOCK_SIZE, BLOCK_SIZE, tile_size])
        return -1
    if src_paths.is_empty():
        push_error("EnvIO: no source files provided")
        return -1

    var indices := list_tileset_indices(pack_id)
    var next_idx: int = 0
    while next_idx in indices:
        next_idx += 1
    if next_idx >= 100:
        push_error("EnvIO: tileset index exhausted (100 max)")
        return -1

    var dst_dir := user_pack_dir(pack_id) + "Tilesets/"
    _ensure_dir(dst_dir)
    var dst_path := dst_dir + "tileset_%02d_atlas.png" % next_idx

    if src_paths.size() == 1:
        # Byte-copy the single source verbatim so we don't re-encode.
        var path: String = src_paths[0]
        var check := _validate_tileset_source(path, tile_size)
        if check.is_empty():
            return -1
        var src := FileAccess.open(path, FileAccess.READ)
        if src == null:
            push_error("EnvIO: cannot read tileset source %s" % path)
            return -1
        var bytes := src.get_buffer(src.get_length())
        src.close()
        var dst := FileAccess.open(dst_path, FileAccess.WRITE)
        if dst == null:
            push_error("EnvIO: cannot write %s" % dst_path)
            return -1
        dst.store_buffer(bytes)
        dst.close()
        print("[EnvIO] imported tileset %d for pack '%s' from %s (%d×%d, tile_size=%d)" % [next_idx, pack_id, path, int(check["w"]), int(check["h"]), tile_size])
    else:
        # Multi-source: compose into a new atlas image.
        var out_img := _compose_tileset_atlas(src_paths, tile_size)
        if out_img == null:
            return -1
        if out_img.save_png(dst_path) != OK:
            push_error("EnvIO: cannot write composed atlas %s" % dst_path)
            return -1
        print("[EnvIO] imported tileset %d for pack '%s' from %d sources (%d×%d, tile_size=%d)" % [next_idx, pack_id, src_paths.size(), out_img.get_width(), out_img.get_height(), tile_size])

    # Clear any stale tombstone from a prior deletion at this idx — we're
    # reusing the slot, so the new tileset must not be suppressed by an
    # old "deleted" marker in the sidecar.
    var existing_meta := _load_tileset_meta(pack_id, next_idx)
    if existing_meta.has("deleted"):
        existing_meta.erase("deleted")
        _write_tileset_meta(pack_id, next_idx, existing_meta)

    if tile_size != BLOCK_SIZE:
        save_tileset_size(pack_id, next_idx, tile_size)
    return next_idx


# Append one or more PNGs' worth of logical tiles to an existing tileset
# atlas. The atlas width is preserved — we only grow height — so every
# previously-painted tile keeps its linearized sub-tile idx. The tileset's
# tile_size comes from its sidecar (via load_tileset_size); every source
# must divide cleanly by it.
#
# If the atlas currently only lives in the shipped layer, it's copied
# into the user layer first so we're not mutating res://.
#
# Returns the number of logical tiles appended, or -1 on hard failure.
static func append_to_tileset(pack_id: String, tileset_idx: int, src_paths: PackedStringArray) -> int:
    if src_paths.is_empty():
        push_warning("EnvIO: no source files to append")
        return 0

    var tile_size := load_tileset_size(pack_id, tileset_idx)

    var user_path := user_pack_dir(pack_id) + "Tilesets/tileset_%02d_atlas.png" % tileset_idx
    if not FileAccess.file_exists(user_path):
        var shipped_path := shipped_pack_dir(pack_id) + "Tilesets/tileset_%02d_atlas.png" % tileset_idx
        if not FileAccess.file_exists(shipped_path):
            push_error("EnvIO: tileset %d atlas not found" % tileset_idx)
            return -1
        _ensure_dir(user_pack_dir(pack_id) + "Tilesets/")
        _copy_file(shipped_path, user_path)

    var existing := _load_png_image(user_path)
    if existing == null:
        push_error("EnvIO: cannot load existing atlas %s" % user_path)
        return -1
    var existing_w := existing.get_width()
    var existing_h := existing.get_height()
    if existing_w <= 0 or existing_h <= 0:
        push_error("EnvIO: existing atlas has zero dimensions")
        return -1
    if existing_w % tile_size != 0 or existing_h % tile_size != 0:
        push_error("EnvIO: existing atlas %d×%d not divisible by tile_size %d" % [existing_w, existing_h, tile_size])
        return -1
    if existing.get_format() != Image.FORMAT_RGBA8:
        existing.convert(Image.FORMAT_RGBA8)

    @warning_ignore("integer_division")
    var atlas_cols: int = existing_w / tile_size
    @warning_ignore("integer_division")
    var existing_rows: int = existing_h / tile_size
    var existing_tile_count: int = atlas_cols * existing_rows

    # Collect every new logical tile from the source files. Each source
    # contributes (pw/tile_size) * (ph/tile_size) tiles in row-major order.
    var new_tiles := _collect_logical_tiles(src_paths, tile_size)
    if new_tiles.is_empty():
        push_warning("EnvIO: no valid tiles to append")
        return 0

    var total_count: int = existing_tile_count + new_tiles.size()
    var new_rows: int = int(ceil(float(total_count) / float(atlas_cols)))
    var new_h: int = new_rows * tile_size

    var out_img := Image.create_empty(existing_w, new_h, false, Image.FORMAT_RGBA8)
    out_img.fill(Color(0, 0, 0, 0))
    out_img.blit_rect(existing, Rect2i(0, 0, existing_w, existing_h), Vector2i(0, 0))

    for i in new_tiles.size():
        var slot: int = existing_tile_count + i
        var col: int = slot % atlas_cols
        @warning_ignore("integer_division")
        var row: int = slot / atlas_cols
        var dst_pos := Vector2i(col * tile_size, row * tile_size)
        var tile: Dictionary = new_tiles[i]
        out_img.blit_rect(tile["image"], tile["rect"], dst_pos)

    if out_img.save_png(user_path) != OK:
        push_error("EnvIO: cannot save appended atlas %s" % user_path)
        return -1
    print("[EnvIO] appended %d tiles to tileset %d (now %d×%d, %d total tiles)" % [new_tiles.size(), tileset_idx, existing_w, new_h, total_count])
    return new_tiles.size()


# Removes a tileset from this pack. Three cases:
#   1. User-layer atlas only → delete atlas + sidecar outright.
#   2. User-layer + shipped atlas → delete user-layer atlas, write a
#      tombstone sidecar ({"deleted": true}) so list_tileset_indices
#      suppresses it on subsequent loads. We can't touch res:// itself.
#   3. Shipped-layer only → write the tombstone directly.
# Returns true if anything was deleted/suppressed, false otherwise.
static func delete_tileset(pack_id: String, tileset_idx: int) -> bool:
    var user_atlas := user_pack_dir(pack_id) + "Tilesets/tileset_%02d_atlas.png" % tileset_idx
    var shipped_atlas := shipped_pack_dir(pack_id) + "Tilesets/tileset_%02d_atlas.png" % tileset_idx
    var user_meta := tileset_meta_path(pack_id, tileset_idx, "user")

    var had_any := false
    if FileAccess.file_exists(user_atlas):
        DirAccess.remove_absolute(user_atlas)
        had_any = true

    if FileAccess.file_exists(shipped_atlas):
        # Shipped copy persists; leave a tombstone so the tileset doesn't
        # reappear in list_tileset_indices.
        _ensure_dir(user_pack_dir(pack_id) + "Tilesets/")
        var meta := _load_tileset_meta(pack_id, tileset_idx)
        meta["deleted"] = true
        _write_tileset_meta(pack_id, tileset_idx, meta)
        had_any = true
    else:
        # No shipped copy — drop the sidecar too so nothing dangles.
        if FileAccess.file_exists(user_meta):
            DirAccess.remove_absolute(user_meta)

    if not had_any:
        push_warning("EnvIO: tileset %d not found, nothing to delete" % tileset_idx)
        return false
    print("[EnvIO] deleted tileset %d for pack '%s'" % [tileset_idx, pack_id])
    return true


# Loads a PNG file into an Image. Returns null on failure.
static func _load_png_image(path: String) -> Image:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return null
    var bytes := f.get_buffer(f.get_length())
    f.close()
    var img := Image.new()
    if img.load_png_from_buffer(bytes) != OK:
        return null
    return img


# Validates that `path` points at a PNG usable as a tileset source at the
# given tile_size, and returns a small dict with its dimensions + loaded
# Image on success. Returns an empty dict on any failure (caller should
# push_error or push_warning with its own context).
static func _validate_tileset_source(path: String, tile_size: int) -> Dictionary:
    var img := _load_png_image(path)
    if img == null:
        push_error("EnvIO: %s is not a valid PNG" % path)
        return {}
    var w := img.get_width()
    var h := img.get_height()
    if w < BLOCK_SIZE or h < BLOCK_SIZE:
        push_error("EnvIO: %s must be at least %d×%d (got %d×%d)" % [path, BLOCK_SIZE, BLOCK_SIZE, w, h])
        return {}
    if w % BLOCK_SIZE != 0 or h % BLOCK_SIZE != 0:
        push_error("EnvIO: %s dims %d×%d must be multiples of %d" % [path, w, h, BLOCK_SIZE])
        return {}
    if tile_size > w or tile_size > h:
        push_error("EnvIO: %s %d×%d smaller than tile_size %d" % [path, w, h, tile_size])
        return {}
    if w % tile_size != 0 or h % tile_size != 0:
        push_error("EnvIO: %s %d×%d not a multiple of tile_size %d" % [path, w, h, tile_size])
        return {}
    return {"w": w, "h": h, "image": img}


# Walks every source PNG and produces a flat list of {image, rect} entries,
# one per logical tile in row-major order within each source. Invalid
# sources are skipped with a warning so a partial batch still succeeds.
static func _collect_logical_tiles(src_paths: PackedStringArray, tile_size: int) -> Array:
    var tiles: Array = []
    for path in src_paths:
        var check := _validate_tileset_source(path, tile_size)
        if check.is_empty():
            push_warning("EnvIO: skipping invalid source %s" % path)
            continue
        var img: Image = check["image"]
        if img.get_format() != Image.FORMAT_RGBA8:
            img.convert(Image.FORMAT_RGBA8)
        var w: int = int(check["w"])
        var h: int = int(check["h"])
        @warning_ignore("integer_division")
        var tc: int = w / tile_size
        @warning_ignore("integer_division")
        var tile_rows: int = h / tile_size
        for r in tile_rows:
            for c in tc:
                tiles.append({
                    "image": img,
                    "rect": Rect2i(c * tile_size, r * tile_size, tile_size, tile_size),
                })
    return tiles


# Composes a brand-new atlas from the provided sources. Layout is 16
# logical tiles wide (or fewer when the total count is < 16). Returns
# null if no valid tiles were found across all sources.
static func _compose_tileset_atlas(src_paths: PackedStringArray, tile_size: int) -> Image:
    var tiles := _collect_logical_tiles(src_paths, tile_size)
    if tiles.is_empty():
        push_error("EnvIO: no valid tiles from sources")
        return null
    var target_cols: int = mini(16, tiles.size())
    var target_rows: int = int(ceil(float(tiles.size()) / float(target_cols)))
    var out_w: int = target_cols * tile_size
    var out_h: int = target_rows * tile_size
    var out_img := Image.create_empty(out_w, out_h, false, Image.FORMAT_RGBA8)
    out_img.fill(Color(0, 0, 0, 0))
    for i in tiles.size():
        var tile: Dictionary = tiles[i]
        var col: int = i % target_cols
        @warning_ignore("integer_division")
        var row: int = i / target_cols
        var dst_pos := Vector2i(col * tile_size, row * tile_size)
        out_img.blit_rect(tile["image"], tile["rect"], dst_pos)
    return out_img


# Sidecar for per-tileset authoring metadata. Lives next to the atlas PNG
# as tileset_NN_meta.json and currently stores {tile_size, name}. Reads
# fall back user→shipped so user overrides take precedence; writes always
# go to the user layer. All public accessors (load_tileset_size,
# save_tileset_size, load_tileset_name, save_tileset_name) load-merge-save
# through _load_tileset_meta / _write_tileset_meta so setting one key
# doesn't clobber the others.
static func tileset_meta_path(pack_id: String, tileset_idx: int, layer: String = "user") -> String:
    var base: String
    if layer == "shipped":
        base = shipped_pack_dir(pack_id) + "Tilesets/"
    else:
        base = user_pack_dir(pack_id) + "Tilesets/"
    return base + "tileset_%02d_meta.json" % tileset_idx


static func _load_tileset_meta(pack_id: String, tileset_idx: int) -> Dictionary:
    for layer in ["user", "shipped"]:
        var path := tileset_meta_path(pack_id, tileset_idx, layer)
        if not FileAccess.file_exists(path):
            continue
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            continue
        var raw = JSON.parse_string(f.get_as_text())
        f.close()
        if typeof(raw) == TYPE_DICTIONARY:
            return raw
    return {}


static func _write_tileset_meta(pack_id: String, tileset_idx: int, meta: Dictionary) -> bool:
    var dir := user_pack_dir(pack_id) + "Tilesets/"
    _ensure_dir(dir)
    var path := tileset_meta_path(pack_id, tileset_idx, "user")
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("EnvIO: cannot write %s" % path)
        return false
    f.store_string(JSON.stringify(meta, "  "))
    f.close()
    return true


# Returns the authoring tile size (in pixels) for a given tileset. Falls
# back to BLOCK_SIZE when the sidecar is missing or the stored value is
# invalid — matches how every pre-sidecar tileset already behaves.
static func load_tileset_size(pack_id: String, tileset_idx: int) -> int:
    var meta := _load_tileset_meta(pack_id, tileset_idx)
    var ts: int = int(meta.get("tile_size", BLOCK_SIZE))
    if ts >= BLOCK_SIZE and ts % BLOCK_SIZE == 0:
        return ts
    return BLOCK_SIZE


# Load-merge-saves the sidecar so we preserve `name` (and any future
# keys) alongside the updated tile_size. Writes to the user layer.
static func save_tileset_size(pack_id: String, tileset_idx: int, tile_size: int) -> bool:
    if tile_size < BLOCK_SIZE or tile_size % BLOCK_SIZE != 0:
        push_error("EnvIO: refusing to save tile_size %d (must be ≥ %d and a multiple of %d)" % [tile_size, BLOCK_SIZE, BLOCK_SIZE])
        return false
    var meta := _load_tileset_meta(pack_id, tileset_idx)
    meta["tile_size"] = tile_size
    return _write_tileset_meta(pack_id, tileset_idx, meta)


# Returns the display name for a tileset. Falls back to "Tileset NN" so
# the UI always has something to render, even for tilesets that were
# imported before the name field existed.
static func load_tileset_name(pack_id: String, tileset_idx: int) -> String:
    var meta := _load_tileset_meta(pack_id, tileset_idx)
    var raw := str(meta.get("name", "")).strip_edges()
    if raw.is_empty():
        return "Tileset %02d" % tileset_idx
    return raw


# Load-merge-saves the sidecar so `tile_size` survives a rename. Empty
# or whitespace-only names are rejected.
static func save_tileset_name(pack_id: String, tileset_idx: int, display_name: String) -> bool:
    var trimmed := display_name.strip_edges()
    if trimmed.is_empty():
        push_warning("EnvIO: refusing to save empty tileset name")
        return false
    var meta := _load_tileset_meta(pack_id, tileset_idx)
    meta["name"] = trimmed
    return _write_tileset_meta(pack_id, tileset_idx, meta)


static func save_rooms(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "Rooms")
    var path := rooms_json_path(pack_id)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("EnvIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


# Skeleton for a freshly created campaign. One room "start" at the default
# 30x17 block size with empty tile layers and no entities.
static func default_rooms_data() -> Dictionary:
    var start := default_room("start", "Start Room",
        DEFAULT_ROOM_W_BLOCKS, DEFAULT_ROOM_H_BLOCKS, 0)
    return {
        "version": "3.0",
        "start_room": "start",
        "rooms": {"start": start},
    }


# Builds a blank room dict matching the runtime's expected schema. All
# layer arrays are zero-filled; slopes/doors/entities/triggers are empty.
# Starts with a single "Main" tile layer — authors add bg/fg layers from
# the editor sidebar as needed.
static func default_room(addr: String, friendly: String, w_blocks: int, h_blocks: int, tileset_id: int = 0) -> Dictionary:
    var w_px := w_blocks * BLOCK_SIZE
    var h_px := h_blocks * BLOCK_SIZE
    var w_screens := float(w_blocks) / float(DEFAULT_ROOM_W_BLOCKS)
    var h_screens := float(h_blocks) / float(DEFAULT_ROOM_H_BLOCKS)
    return {
        "addr": addr,
        "friendly_name": friendly,
        "width_screens": w_screens,
        "height_screens": h_screens,
        "width_blocks": float(w_blocks),
        "height_blocks": float(h_blocks),
        "width_px": float(w_px),
        "height_px": float(h_px),
        "tileset": float(tileset_id),
        "parallax_layers": default_parallax_layers(),
        "tile_layers": [
            default_tile_layer("Main", ROLE_MAIN, 1.0, 1.0, h_blocks, w_blocks),
        ],
        "collision": _make_2d_array(h_blocks, w_blocks, 0),
        "bts": _make_2d_array(h_blocks, w_blocks, 0),
        "slopes": [],
        "doors": [],
        "entities": [],
        "triggers": TriggerRoot.default_root(),
    }


# Builds a blank tile-layer dict. `tiles` is a zero-filled rows × cols 2D
# array; scroll speeds default per role via default_scroll_for_role but can
# be overridden by the caller.
static func default_tile_layer(layer_name: String, role: String, sx: float, sy: float, rows: int, cols: int) -> Dictionary:
    return {
        "name": layer_name,
        "role": role,
        "scroll_speed_x": sx,
        "scroll_speed_y": sy,
        "tiles": _make_2d_array(rows, cols, 0),
        "animations": {},
    }


static func default_parallax_layers() -> Array:
    var out: Array = []
    for entry_v in PARALLAX_DEFAULTS:
        var entry: Dictionary = entry_v
        out.append({
            "name": str(entry.get("name", "")),
            "image": "",
            "scroll_speed_x": float(entry.get("scroll_speed_x", 1.0)),
            "scroll_speed_y": float(entry.get("scroll_speed_y", 1.0)),
        })
    return out


static func normalize_parallax_layers(room: Dictionary) -> void:
    var normalized: Array = default_parallax_layers()
    var existing_v: Variant = room.get("parallax_layers", [])
    if typeof(existing_v) == TYPE_ARRAY:
        var existing: Array = existing_v
        for i in mini(existing.size(), normalized.size()):
            var src_v: Variant = existing[i]
            if typeof(src_v) != TYPE_DICTIONARY:
                continue
            var src: Dictionary = src_v
            var dst: Dictionary = normalized[i]
            if src.has("name"):
                dst["name"] = str(src.get("name", dst["name"]))
            dst["image"] = str(src.get("image", src.get("path", dst["image"])))
            dst["scroll_speed_x"] = float(src.get("scroll_speed_x", dst["scroll_speed_x"]))
            dst["scroll_speed_y"] = float(src.get("scroll_speed_y", dst["scroll_speed_y"]))
    elif room.has("backdrop_image") and not str(room.get("backdrop_image", "")).is_empty():
        var legacy_idx := 1
        normalized[legacy_idx]["image"] = str(room.get("backdrop_image", ""))
        normalized[legacy_idx]["scroll_speed_x"] = float(room.get("backdrop_scroll_speed_x", normalized[legacy_idx]["scroll_speed_x"]))
        normalized[legacy_idx]["scroll_speed_y"] = float(room.get("backdrop_scroll_speed_y", normalized[legacy_idx]["scroll_speed_y"]))
    room["parallax_layers"] = normalized


# Converts a legacy room (with layer1/layer1_hi/layer2 + has_layer2 keys)
# into the new tile_layers array shape. Idempotent: no-op if tile_layers is
# already present and non-empty. Strips the legacy keys so subsequent saves
# only write the new schema.
static func migrate_room_to_layers(room: Dictionary) -> void:
    normalize_parallax_layers(room)
    var existing_v: Variant = room.get("tile_layers")
    if typeof(existing_v) == TYPE_ARRAY and (existing_v as Array).size() > 0:
        return

    var rows := int(room.get("height_blocks", 0))
    var cols := int(room.get("width_blocks", 0))
    var layers: Array = []

    var has_layer2 := bool(room.get("has_layer2", false))
    var layer2_v: Variant = room.get("layer2")
    if has_layer2 and typeof(layer2_v) == TYPE_ARRAY and (layer2_v as Array).size() > 0:
        layers.append({
            "name": "Background",
            "role": ROLE_BG,
            "scroll_speed_x": 0.5,
            "scroll_speed_y": 0.5,
            "tiles": layer2_v,
        })

    var layer1_v: Variant = room.get("layer1")
    if typeof(layer1_v) == TYPE_ARRAY and (layer1_v as Array).size() > 0:
        layers.append({
            "name": "Main",
            "role": ROLE_MAIN,
            "scroll_speed_x": 1.0,
            "scroll_speed_y": 1.0,
            "tiles": layer1_v,
        })

    var layer1_hi_v: Variant = room.get("layer1_hi")
    if typeof(layer1_hi_v) == TYPE_ARRAY and (layer1_hi_v as Array).size() > 0:
        layers.append({
            "name": "Foreground",
            "role": ROLE_FG,
            "scroll_speed_x": 1.0,
            "scroll_speed_y": 1.0,
            "tiles": layer1_hi_v,
        })

    if layers.is_empty():
        layers.append(default_tile_layer("Main", ROLE_MAIN, 1.0, 1.0, rows, cols))

    room["tile_layers"] = layers
    room.erase("layer1")
    room.erase("layer1_hi")
    room.erase("layer2")
    room.erase("has_layer2")


# Returns sorted list of tileset indices discoverable for this pack,
# scanning both the user override layer and the shipped layer. Entries
# whose user-layer sidecar is tombstoned with `{"deleted": true}` are
# filtered out — that's how delete_tileset suppresses shipped-only
# tilesets that we can't actually remove from res://.
static func list_tileset_indices(pack_id: String) -> Array:
    var indices: Array = []
    var seen: Dictionary = {}
    for base in [user_pack_dir(pack_id) + "Tilesets/", shipped_pack_dir(pack_id) + "Tilesets/"]:
        var dir := DirAccess.open(base)
        if dir == null:
            continue
        dir.list_dir_begin()
        var fn := dir.get_next()
        while fn != "":
            if not dir.current_is_dir() \
                    and fn.begins_with("tileset_") \
                    and fn.ends_with("_atlas.png"):
                var n := fn.substr(8, 2)
                if n.is_valid_int():
                    var idx := int(n)
                    if not seen.has(idx):
                        seen[idx] = true
                        indices.append(idx)
            fn = dir.get_next()
        dir.list_dir_end()
    var filtered: Array = []
    for idx in indices:
        var meta := _load_tileset_meta(pack_id, int(idx))
        if bool(meta.get("deleted", false)):
            continue
        filtered.append(idx)
    filtered.sort()
    return filtered


# Loads a tileset atlas PNG as a Texture2D. Tries the user override layer
# first, falls back to the shipped layer, then returns null.
static func load_tileset_texture(pack_id: String, tileset_idx: int) -> Texture2D:
    var fn := "tileset_%02d_atlas.png" % tileset_idx
    for base in [user_pack_dir(pack_id) + "Tilesets/", shipped_pack_dir(pack_id) + "Tilesets/"]:
        var path: String = base + fn
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


static func load_backdrop_texture(pack_id: String, rel_path: String) -> Texture2D:
    var trimmed := rel_path.strip_edges()
    if trimmed.is_empty():
        return null
    if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
        return load(trimmed) as Texture2D
    var candidates := [
        user_pack_dir(pack_id) + trimmed,
        shipped_pack_dir(pack_id) + trimmed,
    ]
    for path in candidates:
        if not FileAccess.file_exists(path):
            continue
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            continue
        var bytes := f.get_buffer(f.get_length())
        f.close()
        var image := Image.new()
        if image.load_png_from_buffer(bytes) == OK:
            return ImageTexture.create_from_image(image)
        var tex := load(path)
        if tex is Texture2D:
            return tex
    return null


static func import_backdrops(pack_id: String, src_paths: PackedStringArray) -> Array:
    var out: Array = []
    if src_paths.is_empty():
        return out
    var dst_dir: String = user_pack_dir(pack_id) + "Backdrops/Parallax/"
    _ensure_dir(dst_dir)
    var batch_names: Dictionary = {}
    for src_path_v in src_paths:
        var src_path: String = str(src_path_v).strip_edges()
        if src_path.is_empty():
            continue
        var file_name: String = _sanitize_asset_file_name(src_path.get_file())
        if file_name.is_empty():
            file_name = "parallax.png"
        var file_key: String = file_name.to_lower()
        if batch_names.has(file_key) or FileAccess.file_exists(dst_dir + file_name):
            file_name = _unique_file_name(dst_dir, file_name)
        batch_names[file_name.to_lower()] = true
        var dst_path: String = dst_dir + file_name
        if not _copy_file_checked(src_path, dst_path):
            push_error("EnvIO: failed to import backdrop '%s'" % src_path)
            continue
        out.append("Backdrops/Parallax/" + file_name)
    return out


# If the user pack has no tileset atlases at all, copy tileset_00 from the
# shipped demo pack so a fresh campaign has at least one tileset to paint
# with. Users can replace/add tilesets later via the (future) Phase 2
# tileset importer.
static func _seed_tilesets_if_empty(pack_id: String) -> void:
    var user_ts_dir := user_pack_dir(pack_id) + "Tilesets/"
    var dir := DirAccess.open(user_ts_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    var fn := dir.get_next()
    while fn != "":
        if not dir.current_is_dir() and fn.begins_with("tileset_") and fn.ends_with("_atlas.png"):
            dir.list_dir_end()
            return
        fn = dir.get_next()
    dir.list_dir_end()

    # Also skip seeding if the pack already has shipped tilesets (i.e. it's
    # a known shipped pack the user is overriding).
    var shipped_ts_dir := shipped_pack_dir(pack_id) + "Tilesets/"
    if DirAccess.dir_exists_absolute(shipped_ts_dir):
        return

    var seed_dir := "res://Content/%s/Tilesets/" % SHIPPED_SEED_PACK
    if not DirAccess.dir_exists_absolute(seed_dir):
        return
    for name in ["tileset_00_atlas.png"]:
        _copy_file(seed_dir + name, user_ts_dir + name)


static func _copy_file(from_path: String, to_path: String) -> void:
    var src := FileAccess.open(from_path, FileAccess.READ)
    if src == null:
        return
    var bytes := src.get_buffer(src.get_length())
    src.close()
    var dst := FileAccess.open(to_path, FileAccess.WRITE)
    if dst == null:
        return
    dst.store_buffer(bytes)
    dst.close()


static func _copy_file_checked(from_path: String, to_path: String) -> bool:
    var src := FileAccess.open(from_path, FileAccess.READ)
    if src == null:
        return false
    var bytes := src.get_buffer(src.get_length())
    src.close()
    var dst := FileAccess.open(to_path, FileAccess.WRITE)
    if dst == null:
        return false
    dst.store_buffer(bytes)
    dst.close()
    return true


static func _sanitize_asset_file_name(file_name: String) -> String:
    var trimmed: String = file_name.strip_edges()
    if trimmed.is_empty():
        return ""
    var base_name: String = trimmed.get_basename().to_lower()
    var ext: String = trimmed.get_extension().to_lower()
    if ext.is_empty():
        ext = "png"
    var out: String = ""
    for i in range(base_name.length()):
        var ch: String = base_name.substr(i, 1)
        var code: int = ch.unicode_at(0)
        var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
        if ok:
            out += ch
        else:
            out += "_"
    while out.find("__") >= 0:
        out = out.replace("__", "_")
    out = out.trim_prefix("_").trim_suffix("_")
    if out.is_empty():
        out = "parallax"
    return "%s.%s" % [out, ext]


static func _unique_file_name(dst_dir: String, file_name: String) -> String:
    var base_name: String = file_name.get_basename()
    var ext: String = file_name.get_extension()
    var counter: int = 2
    var candidate: String = file_name
    while FileAccess.file_exists(dst_dir + candidate):
        candidate = "%s_%d.%s" % [base_name, counter, ext]
        counter += 1
    return candidate


# ─── Spike profiles ──────────────────────────────────────────────────────
#
# spike_profiles.json lives in user://Packs/<pack_id>/Hazards/ and holds an
# array of spike profile dicts indexed by BTS byte value. Profile 0 is always
# the default (auto-created if missing).

static func spike_profiles_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Hazards/spike_profiles.json"


static func default_spike_profile() -> Dictionary:
    return {
        "id": 0,
        "name": "default",
        "damage": 10,
        "effect": "none",
        "effect_duration": 0.0,
        "effect_tick_damage": 0,
        "effect_tick_interval": 0.5,
        "effect_speed_mult": 1.0,
        "knockback": "push_away",
    }


static func load_spike_profiles(pack_id: String) -> Array:
    var path := spike_profiles_path(pack_id)
    if FileAccess.file_exists(path):
        var f := FileAccess.open(path, FileAccess.READ)
        if f != null:
            var raw = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(raw) == TYPE_ARRAY:
                if raw.is_empty():
                    raw.append(default_spike_profile())
                return raw
    # File missing or invalid — return a single default profile.
    return [default_spike_profile()]


static func save_spike_profiles(pack_id: String, profiles: Array) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "Hazards")
    var path := spike_profiles_path(pack_id)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("EnvIO: cannot write %s" % path)
        return false
    f.store_string(JSON.stringify(profiles, "  "))
    f.close()
    return true


static func add_spike_profile(pack_id: String, profile: Dictionary) -> int:
    var profiles := load_spike_profiles(pack_id)
    var next_id: int = 0
    for p in profiles:
        if typeof(p) == TYPE_DICTIONARY:
            var pid := int(p.get("id", 0))
            if pid >= next_id:
                next_id = pid + 1
    if next_id > 255:
        push_error("EnvIO: spike profile limit reached (256 max)")
        return -1
    profile["id"] = next_id
    profiles.append(profile)
    save_spike_profiles(pack_id, profiles)
    return next_id


static func update_spike_profile(pack_id: String, profile_id: int, updates: Dictionary) -> bool:
    var profiles := load_spike_profiles(pack_id)
    for p in profiles:
        if typeof(p) == TYPE_DICTIONARY and int(p.get("id", -1)) == profile_id:
            for key in updates.keys():
                p[key] = updates[key]
            return save_spike_profiles(pack_id, profiles)
    push_warning("EnvIO: spike profile %d not found" % profile_id)
    return false


static func delete_spike_profile(pack_id: String, profile_id: int) -> bool:
    if profile_id == 0:
        push_warning("EnvIO: cannot delete the default spike profile (id 0)")
        return false
    var profiles := load_spike_profiles(pack_id)
    var filtered: Array = []
    for p in profiles:
        if typeof(p) == TYPE_DICTIONARY and int(p.get("id", -1)) != profile_id:
            filtered.append(p)
    if filtered.size() == profiles.size():
        return false
    return save_spike_profiles(pack_id, filtered)


static func get_spike_profile_by_id(profiles: Array, profile_id: int) -> Dictionary:
    for p in profiles:
        if typeof(p) == TYPE_DICTIONARY and int(p.get("id", -1)) == profile_id:
            return p
    return {}


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)


static func _make_2d_array(rows: int, cols: int, fill: int) -> Array:
    var out: Array = []
    for r in rows:
        var row: Array = []
        row.resize(cols)
        row.fill(fill)
        out.append(row)
    return out
