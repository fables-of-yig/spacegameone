class_name MvRoomManager
extends Node2D

const _MvInteractable := preload("res://MV/scripts/interactable.gd")
const _MvPickup := preload("res://MV/scripts/pickup.gd")
const _MvTriggerVolume := preload("res://MV/scripts/trigger_volume.gd")
const _MvBoss := preload("res://MV/scripts/boss.gd")

# Loads room definitions from the current content pack, builds a dynamic
# stack of TileMapLayers per room (bg layers behind the player, main at
# player z, fg layers attached to a foreground host), greedy-merges solid
# cells into StaticBody2D colliders, and exposes per-pixel slope sampling
# for the Player controller.
#
# Tile layers are world-locked. Backdrop parallax is handled separately by
# the authored far/mid/near backdrop images in room metadata; painted room
# art and painted collision intentionally live in the same coordinate space.
#
# Port notes: entity spawning, triggers, boss HUD, and editor hooks are
# deferred — they were explicitly scoped out of the C#→GDScript port. Raw
# trigger + entity data IS preserved per room so the JSON round-trip stays
# forward-compatible when those systems come back.

const BLOCK_SIZE: int = 16

const ROLE_BG: String = "bg"
const ROLE_MAIN: String = "main"
const ROLE_FG: String = "fg"

# Block type nibble values — stored in each room's collision[row][col]. The
# 6 "solid family" types greedy-merge into rectangle colliders; slopes get
# per-cell convex polygon colliders built from SlopeShapes; everything else
# is air / handled out-of-band.
const BT_AIR:           int = 0x0
const BT_SLOPE:         int = 0x1
const BT_AIR_SPECIAL:   int = 0x2
const BT_TREADMILL_AIR: int = 0x3
const BT_SHOOT_AIR:     int = 0x4
const BT_H_COPY:        int = 0x5
const BT_BOMB_AIR:      int = 0x6
const BT_GRAPPLE_AIR:   int = 0x7
const BT_SOLID:         int = 0x8
const BT_DOOR:          int = 0x9
const BT_SPIKE:         int = 0xA
const BT_CRUMBLE:       int = 0xB
const BT_SHOOT_SOLID:   int = 0xC
const BT_V_COPY:        int = 0xD
const BT_BOMB_SOLID:    int = 0xE
const BT_GRAPPLE_BLOCK: int = 0xF

# Live TileMapLayer stack for the current room. Each entry:
#   {node: TileMapLayer, role: String, scroll_speed: Vector2}
# Populated in load_room, freed on room change. bg/main layers are parented
# to self; fg layers are parented to _fg_host (attached by Main before the
# first room loads).
var _tile_layers: Array = []
var _tile_animator: MvRoomRenderer = null
var _fg_host: Node2D = null
var _backdrop_root: Node2D = null
var _backdrop_layers: Array = []
var _crumble_fx_root: Node2D = null

var _collision_container: Node2D
var _entities_container: Node2D
var _tileset_mgr: MvTilesetManager
var _pack: MvPackRef = null
var _current_room_addr: String = ""
var _rooms: Dictionary = {}   # addr -> room info dict
var _start_room: String = ""

# Per-pixel slope surface Y offsets, loaded from SlopeShapes.json at boot.
# Each entry is 16 ints giving the surface Y (0..16, 16 = no floor) per
# x-pixel within a 16px slope cell. Shape 0 is typically flat-air.
var _slope_shapes: Array = []  # Array[Array[int]]

# Spike profiles loaded from the pack's Hazards/spike_profiles.json.
# Array of dicts keyed by profile id. Runtime looks up BTS byte → profile.
var _spike_profiles: Dictionary = {}  # id (int) -> profile dict
var _active_crumbles: Dictionary = {}

const CRUMBLE_FADE_SECONDS: float = 0.2
const CRUMBLE_RESPAWN_SECONDS: float = 4.0
const CRUMBLE_PERSIST_UNTIL_RELOAD_BIT: int = 0x01


func _ready() -> void:
    _backdrop_root = Node2D.new()
    _backdrop_root.name = "Backdrop"
    _backdrop_root.z_index = -100
    add_child(_backdrop_root)

    _crumble_fx_root = Node2D.new()
    _crumble_fx_root.name = "CrumbleFx"
    _crumble_fx_root.z_index = 50
    add_child(_crumble_fx_root)

    _collision_container = Node2D.new()
    _collision_container.name = "Collision"
    add_child(_collision_container)

    _entities_container = Node2D.new()
    _entities_container.name = "Entities"
    add_child(_entities_container)

    _pack = MvPackLoader.current_pack
    if _pack == null:
        push_error("MvRoomManager: no content pack loaded; call MvPackLoader.load_pack before adding RoomManager to the tree")
        return

    _tileset_mgr = MvTilesetManager.new(_pack)
    _load_slope_shapes(_pack.slope_shapes_path())
    _load_spike_profiles(_pack.spike_profiles_path())
    _load_room_data(_pack.rooms_path())


# Main calls this during boot to hand us a Node2D that renders in front of
# the player. FG-role tile layers get parented here so they draw on top.
# Must be called before load_room; if called later, already-loaded FG
# layers aren't reparented — Main's boot order guarantees it happens first.
func attach_foreground_layer(host: Node2D) -> void:
    _fg_host = host


func _process(_delta: float) -> void:
    var cam := get_viewport().get_camera_2d()
    if cam == null:
        _tick_active_crumbles(_delta)
        return
    var cam_pos: Vector2 = cam.get_screen_center_position()
    for entry in _backdrop_layers:
        var node: Sprite2D = entry.get("node") as Sprite2D
        if node == null:
            continue
        _update_backdrop_layer_transform(entry, cam, cam_pos)
    _tick_active_crumbles(_delta)


func _load_slope_shapes(path: String) -> void:
    # Optional per-pack asset. Packs without custom slopes can omit the file
    # entirely; _slope_shapes stays empty and try_get_slope_floor is a no-op.
    if not FileAccess.file_exists(path):
        return
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("MvRoomManager: failed to open %s" % path)
        return
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        push_error("MvRoomManager: failed to parse %s" % path)
        return
    var shapes: Array = raw.get("shapes", [])
    _slope_shapes = []
    for sh in shapes:
        var row: Array = []
        for v in sh:
            row.append(int(v))
        _slope_shapes.append(row)


func _load_spike_profiles(path: String) -> void:
    _spike_profiles.clear()
    # Default profile always exists even if no file is present.
    _spike_profiles[0] = {
        "id": 0, "name": "default", "damage": 10,
        "effect": "none", "effect_duration": 0.0,
        "effect_tick_damage": 0, "effect_tick_interval": 0.5,
        "effect_speed_mult": 1.0, "knockback": "push_away",
    }
    if not FileAccess.file_exists(path):
        return
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_ARRAY:
        return
    for entry in raw:
        if typeof(entry) == TYPE_DICTIONARY:
            var pid := int(entry.get("id", 0))
            _spike_profiles[pid] = entry
    print("[MvRoomManager] loaded %d spike profile(s)" % _spike_profiles.size())


# Query whether a world-space point overlaps a BT_SPIKE cell. Returns the
# spike profile dict with added "cx"/"cy" keys (cell center in world px)
# if a spike is found, or an empty dict if not.
func query_spike_at(world_pos: Vector2) -> Dictionary:
    var info: Dictionary = current_room()
    if info.is_empty():
        return {}
    var col_arr: Array = info.get("collision", [])
    if col_arr.is_empty():
        return {}
    var col := int(world_pos.x / BLOCK_SIZE)
    var row := int(world_pos.y / BLOCK_SIZE)
    if row < 0 or row >= col_arr.size():
        return {}
    var crow: Variant = col_arr[row]
    if typeof(crow) != TYPE_ARRAY:
        return {}
    var crow_arr: Array = crow
    if col < 0 or col >= crow_arr.size():
        return {}
    var block := int(crow_arr[col]) & 0xF
    if block != BT_SPIKE:
        return {}
    # Look up the profile via BTS byte.
    var bts_val: int = 0
    var bts: Array = info.get("bts", [])
    if row < bts.size():
        var brow: Variant = bts[row]
        if typeof(brow) == TYPE_ARRAY:
            var brow_arr: Array = brow
            if col < brow_arr.size():
                bts_val = int(brow_arr[col])
    var profile: Dictionary = _spike_profiles.get(bts_val, _spike_profiles.get(0, {}))
    if profile.is_empty():
        return {}
    # Return a copy with cell center coordinates for knockback direction.
    var result := profile.duplicate()
    result["cx"] = float(col) * BLOCK_SIZE + BLOCK_SIZE * 0.5
    result["cy"] = float(row) * BLOCK_SIZE + BLOCK_SIZE * 0.5
    return result


func notify_crumble_contacts(world_points: Array) -> void:
    if world_points.is_empty():
        return
    var seen: Dictionary = {}
    for point_v in world_points:
        if typeof(point_v) != TYPE_VECTOR2:
            continue
        var point: Vector2 = point_v
        var col := int(point.x / BLOCK_SIZE)
        var row := int(point.y / BLOCK_SIZE)
        var key := "%d,%d" % [row, col]
        if seen.has(key):
            continue
        seen[key] = true
        _start_crumble_at_cell(row, col)


func _start_crumble_at_cell(row: int, col: int) -> bool:
    var info: Dictionary = current_room()
    if info.is_empty():
        return false
    var collision: Array = info.get("collision", [])
    if row < 0 or row >= collision.size():
        return false
    var row_v: Variant = collision[row]
    if typeof(row_v) != TYPE_ARRAY:
        return false
    var crow: Array = row_v
    if col < 0 or col >= crow.size():
        return false
    if int(crow[col]) != BT_CRUMBLE:
        return false
    var key := "%d,%d" % [row, col]
    if _active_crumbles.has(key):
        return false

    var state := {
        "row": row,
        "col": col,
        "phase": "fade",
        "timer": 0.0,
        "original_collision": int(crow[col]),
        "original_bts": _get_bts_value(info, row, col),
        "reload_only": _crumble_is_reload_only(_get_bts_value(info, row, col)),
        "visuals": _capture_crumble_visuals(info, row, col),
    }
    _clear_tile_cell_on_main_layers(info, Vector2i(col, row))
    _active_crumbles[key] = state
    return true


func _tick_active_crumbles(delta: float) -> void:
    if _active_crumbles.is_empty():
        return
    var finished: Array = []
    for key_v in _active_crumbles.keys():
        var key := str(key_v)
        var state: Dictionary = _active_crumbles[key]
        state["timer"] = float(state.get("timer", 0.0)) + delta
        _refresh_crumble_overlays(state)
        var phase := str(state.get("phase", "fade"))
        if phase == "fade":
            var fade_t := clampf(float(state.get("timer", 0.0)) / CRUMBLE_FADE_SECONDS, 0.0, 1.0)
            _set_crumble_overlay_alpha(state, 1.0 - fade_t)
            if float(state.get("timer", 0.0)) >= CRUMBLE_FADE_SECONDS:
                _remove_crumble_collision(state)
                _free_crumble_overlays(state)
                state["phase"] = "latched" if bool(state.get("reload_only", false)) else "hole"
                state["timer"] = 0.0
        elif phase == "hole":
            if float(state.get("timer", 0.0)) >= CRUMBLE_RESPAWN_SECONDS:
                _restore_crumble_cell(state)
                finished.append(key)
        _active_crumbles[key] = state
    for key in finished:
        _active_crumbles.erase(key)


func _capture_crumble_visuals(info: Dictionary, row: int, col: int) -> Array:
    var visuals: Array = []
    var data_layers_v: Variant = info.get("tile_layers", [])
    if typeof(data_layers_v) != TYPE_ARRAY:
        return visuals
    var data_layers: Array = data_layers_v
    for data_idx in data_layers.size():
        var layer_v: Variant = data_layers[data_idx]
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        var layer_data: Dictionary = _normalize_runtime_tile_layer_entry(layer_v)
        if str(layer_data.get("role", ROLE_MAIN)) == ROLE_BG:
            continue
        var tiles_v: Variant = layer_data.get("tiles", [])
        if typeof(tiles_v) != TYPE_ARRAY or row < 0 or row >= (tiles_v as Array).size():
            continue
        var tiles: Array = tiles_v
        var row_v: Variant = tiles[row]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row_arr: Array = row_v
        if col < 0 or col >= row_arr.size():
            continue
        var packed_value := int(row_arr[col])
        if packed_value == 0:
            continue
        var runtime_node := _find_runtime_layer_node(data_idx, layer_data)
        var overlay := _create_crumble_overlay(runtime_node, packed_value, Vector2i(col, row))
        visuals.append({
            "data_idx": data_idx,
            "packed": packed_value,
            "overlay": overlay,
            "runtime_node": runtime_node,
            "cell": Vector2i(col, row),
        })
    return visuals


func _find_runtime_layer_node(data_idx: int, layer_data: Dictionary) -> TileMapLayer:
    var normalized := _normalize_runtime_tile_layer_entry(layer_data)
    var expected_name := "TileLayer_%02d_%s" % [data_idx, str(normalized.get("name", "Layer"))]
    for entry in _tile_layers:
        var node: TileMapLayer = entry.get("node") as TileMapLayer
        if node != null and node.name == expected_name:
            return node
    return null


func _create_crumble_overlay(layer_node: TileMapLayer, packed_value: int, cell: Vector2i) -> Sprite2D:
    if layer_node == null or layer_node.tile_set == null or _crumble_fx_root == null:
        return null
    var unpacked := MvTileValue.unpack_full(packed_value)
    var source_id := int(unpacked.get("tileset", 0))
    var atlas_cols := _get_atlas_cols_for_source(layer_node, source_id)
    var metatile_idx := int(unpacked.get("idx", 0))
    var atlas_coords := Vector2i(metatile_idx % atlas_cols, metatile_idx / atlas_cols)
    var src := layer_node.tile_set.get_source(source_id)
    if not (src is TileSetAtlasSource):
        return null
    var atlas_source := src as TileSetAtlasSource
    if atlas_source.texture == null:
        return null
    var tile_size := atlas_source.texture_region_size
    if tile_size.x <= 0 or tile_size.y <= 0:
        tile_size = Vector2i(BLOCK_SIZE, BLOCK_SIZE)
    var atlas := AtlasTexture.new()
    atlas.atlas = atlas_source.texture
    atlas.region = Rect2(Vector2(atlas_coords.x * tile_size.x, atlas_coords.y * tile_size.y), Vector2(tile_size.x, tile_size.y))
    var spr := Sprite2D.new()
    spr.texture = atlas
    spr.centered = true
    spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    spr.flip_h = bool(unpacked.get("hflip", false))
    spr.flip_v = bool(unpacked.get("vflip", false))
    var parent := layer_node.get_parent()
    if parent != null:
        parent.add_child(spr)
    else:
        _crumble_fx_root.add_child(spr)
    spr.position = layer_node.position + Vector2((float(cell.x) + 0.5) * BLOCK_SIZE, (float(cell.y) + 0.5) * BLOCK_SIZE)
    spr.z_index = layer_node.z_index + 1
    return spr


func _refresh_crumble_overlays(state: Dictionary) -> void:
    var visuals: Array = state.get("visuals", [])
    for visual_v in visuals:
        if typeof(visual_v) != TYPE_DICTIONARY:
            continue
        var visual: Dictionary = visual_v
        var spr: Sprite2D = visual.get("overlay") as Sprite2D
        var layer_node: TileMapLayer = visual.get("runtime_node") as TileMapLayer
        var cell: Vector2i = visual.get("cell", Vector2i.ZERO)
        if spr == null or layer_node == null:
            continue
        spr.position = layer_node.position + Vector2((float(cell.x) + 0.5) * BLOCK_SIZE, (float(cell.y) + 0.5) * BLOCK_SIZE)


func _set_crumble_overlay_alpha(state: Dictionary, alpha: float) -> void:
    var visuals: Array = state.get("visuals", [])
    for visual_v in visuals:
        if typeof(visual_v) != TYPE_DICTIONARY:
            continue
        var spr: Sprite2D = (visual_v as Dictionary).get("overlay") as Sprite2D
        if spr != null:
            spr.modulate.a = alpha


func _free_crumble_overlays(state: Dictionary) -> void:
    var visuals: Array = state.get("visuals", [])
    for visual_v in visuals:
        if typeof(visual_v) != TYPE_DICTIONARY:
            continue
        var spr: Sprite2D = (visual_v as Dictionary).get("overlay") as Sprite2D
        if spr != null:
            spr.queue_free()


func _remove_crumble_collision(state: Dictionary) -> void:
    var info: Dictionary = current_room()
    if info.is_empty():
        return
    var row := int(state.get("row", -1))
    var col := int(state.get("col", -1))
    var collision: Array = info.get("collision", [])
    if row < 0 or row >= collision.size():
        return
    var row_arr: Array = collision[row]
    if col < 0 or col >= row_arr.size():
        return
    row_arr[col] = BT_AIR
    _set_bts_value(info, row, col, 0)
    _build_collision(info)


func _restore_crumble_cell(state: Dictionary) -> void:
    var info: Dictionary = current_room()
    if info.is_empty():
        return
    _free_crumble_overlays(state)
    var row := int(state.get("row", -1))
    var col := int(state.get("col", -1))
    var collision: Array = info.get("collision", [])
    if row < 0 or row >= collision.size():
        return
    var row_arr: Array = collision[row]
    if col < 0 or col >= row_arr.size():
        return
    row_arr[col] = int(state.get("original_collision", BT_CRUMBLE))
    _set_bts_value(info, row, col, int(state.get("original_bts", 0)))
    var visuals: Array = state.get("visuals", [])
    for visual_v in visuals:
        if typeof(visual_v) != TYPE_DICTIONARY:
            continue
        var visual: Dictionary = visual_v
        var runtime_node: TileMapLayer = visual.get("runtime_node") as TileMapLayer
        var packed_value := int(visual.get("packed", 0))
        var cell: Vector2i = visual.get("cell", Vector2i(col, row))
        if runtime_node != null and packed_value != 0:
            MvRoomRenderer.update_cell(runtime_node, cell.x, cell.y, packed_value)
        var data_idx := int(visual.get("data_idx", -1))
        _restore_data_layer_cell(info, data_idx, cell, packed_value)
    _build_collision(info)


func _restore_data_layer_cell(info: Dictionary, data_idx: int, cell: Vector2i, packed_value: int) -> void:
    var data_layers_v: Variant = info.get("tile_layers", [])
    if typeof(data_layers_v) != TYPE_ARRAY:
        return
    var data_layers: Array = data_layers_v
    if data_idx < 0 or data_idx >= data_layers.size():
        return
    var layer_v: Variant = data_layers[data_idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    var tiles_v: Variant = (layer_v as Dictionary).get("tiles", [])
    if typeof(tiles_v) != TYPE_ARRAY:
        return
    var tiles: Array = tiles_v
    if cell.y < 0 or cell.y >= tiles.size():
        return
    var row_v: Variant = tiles[cell.y]
    if typeof(row_v) != TYPE_ARRAY:
        return
    var row_arr: Array = row_v
    if cell.x >= 0 and cell.x < row_arr.size():
        row_arr[cell.x] = packed_value


func _reset_active_crumbles(restore_tiles: bool = true) -> void:
    if _active_crumbles.is_empty():
        return
    for key_v in _active_crumbles.keys():
        var state: Dictionary = _active_crumbles[key_v]
        if restore_tiles:
            _restore_crumble_cell(state)
        else:
            _free_crumble_overlays(state)
    _active_crumbles.clear()


func _get_bts_value(info: Dictionary, row: int, col: int) -> int:
    var bts: Array = info.get("bts", [])
    if row < 0 or row >= bts.size():
        return 0
    var row_v: Variant = bts[row]
    if typeof(row_v) != TYPE_ARRAY:
        return 0
    var row_arr: Array = row_v
    if col < 0 or col >= row_arr.size():
        return 0
    return int(row_arr[col])


func _set_bts_value(info: Dictionary, row: int, col: int, value: int) -> void:
    var bts: Array = info.get("bts", [])
    if row < 0 or row >= bts.size():
        return
    var row_v: Variant = bts[row]
    if typeof(row_v) != TYPE_ARRAY:
        return
    var row_arr: Array = row_v
    if col < 0 or col >= row_arr.size():
        return
    row_arr[col] = value


static func _crumble_is_reload_only(bts_value: int) -> bool:
    return (bts_value & CRUMBLE_PERSIST_UNTIL_RELOAD_BIT) != 0


func _get_atlas_cols_for_source(map: TileMapLayer, source_id: int) -> int:
    if map == null or map.tile_set == null:
        return 1
    var ts := map.tile_set
    var src_count := ts.get_source_count()
    for i in src_count:
        var sid := ts.get_source_id(i)
        if sid != source_id:
            continue
        var src := ts.get_source(sid)
        if src is TileSetAtlasSource and (src as TileSetAtlasSource).texture != null:
            var atlas_src := src as TileSetAtlasSource
            var tile_size := atlas_src.texture_region_size.x
            if tile_size < 1:
                tile_size = BLOCK_SIZE
            return maxi(1, atlas_src.texture.get_width() / tile_size)
    return 1


func _load_room_data(path: String) -> void:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("MvRoomManager: failed to open %s" % path)
        return
    var text := f.get_as_text()
    f.close()

    var raw = JSON.parse_string(text)
    if typeof(raw) != TYPE_DICTIONARY:
        push_error("MvRoomManager: failed to parse %s" % path)
        return

    _start_room = str(raw.get("start_room", ""))
    var rooms: Dictionary = raw.get("rooms", {})
    for key in rooms.keys():
        var addr := str(key)
        var info := _parse_room_info(addr, rooms[key])
        _rooms[addr] = info

    print("[MvRoomManager] loaded %d room(s), start=%s" % [_rooms.size(), _start_room])


func _parse_room_info(addr: String, r: Dictionary) -> Dictionary:
    var info: Dictionary = {
        "addr": addr,
        "name": str(r.get("friendly_name", addr)),
        "backdrop_image": str(r.get("backdrop_image", "")),
        "backdrop_scroll_speed_x": float(r.get("backdrop_scroll_speed_x", 0.94)),
        "backdrop_scroll_speed_y": float(r.get("backdrop_scroll_speed_y", 0.97)),
        "parallax_layers": _parse_parallax_layers(r),
        "width_screens":  int(r.get("width_screens", 0)),
        "height_screens": int(r.get("height_screens", 0)),
        "width_blocks":   int(r.get("width_blocks", 0)),
        "height_blocks":  int(r.get("height_blocks", 0)),
        "width_px":       int(r.get("width_px", 0)),
        "height_px":      int(r.get("height_px", 0)),
        "tileset":        int(r.get("tileset", 0)),
        "doors":          [],
        "tile_layers":    [],
        "collision":      [],
        "bts":            [],
        "slopes":         [],
        "slope_grid":     [],
        "entities":       [],
        "raw_triggers":   [],
    }

    if r.has("doors"):
        for d in r["doors"]:
            var di: Dictionary = {
                "target":        str(d.get("target_room", "")),
                "direction":     str(d.get("direction", "")),
                "cap_block_x":   int(d.get("cap_x", 0)),
                "cap_block_y":   int(d.get("cap_y", 0)),
                "dest_pixel_x":  int(d.get("dest_x", 0)),
                "dest_pixel_y":  int(d.get("dest_y", 0)),
                "send_to_overworld": bool(d.get("send_to_overworld", false)),
                "tags":          [],
                "destinations": [],
            }
            if d.has("tags") and typeof(d["tags"]) == TYPE_ARRAY:
                for t in d["tags"]:
                    di["tags"].append(str(t))
            if d.has("destinations") and typeof(d["destinations"]) == TYPE_ARRAY:
                # Raw pass-through — the condition layer is deferred with
                # the rest of the trigger/flow rebuild.
                di["destinations"] = (d["destinations"] as Array).duplicate(true)
            info["doors"].append(di)

    info["collision"] = _parse_2d(r.get("collision", []))
    info["bts"]       = _parse_2d(r.get("bts", []))
    info["tile_layers"] = _parse_tile_layers(r)

    # Migration for pre-multi-tileset data: any cell whose packed value has
    # tileset_id == 0 (the old default) gets the room's primary tileset
    # OR'd in, so existing rooms render through the correct multi-source
    # ID. No-op for rooms whose primary tileset IS 0.
    if info["tileset"] != 0:
        for layer_entry in info["tile_layers"]:
            _migrate_layer_tileset_ids(layer_entry["tiles"], info["tileset"])

    if r.has("slopes"):
        for s in r["slopes"]:
            info["slopes"].append({
                "row":   int(s["row"]),
                "col":   int(s["col"]),
                "shape": int(s["shape"]),
                "hflip": bool(s["hflip"]),
                "vflip": bool(s["vflip"]),
            })

    if r.has("entities") and typeof(r["entities"]) == TYPE_ARRAY:
        for e in r["entities"]:
            if typeof(e) != TYPE_DICTIONARY:
                continue
            var ei: Dictionary = {
                "type":     str(e.get("type", "")),
                "position": Vector2(float(e.get("x", 0)), float(e.get("y", 0))),
                "instance_id": "",
                "tags":     [],
                "properties": {},
            }
            if e.has("tags") and typeof(e["tags"]) == TYPE_ARRAY:
                for t in e["tags"]:
                    ei["tags"].append(str(t))
            if e.has("properties") and typeof(e["properties"]) == TYPE_DICTIONARY:
                ei["properties"] = (e["properties"] as Dictionary).duplicate(true)
            ei["instance_id"] = str(ei["properties"].get("instance_id",
                _fallback_entity_instance_id(ei["type"], ei["position"]))).strip_edges()
            info["entities"].append(ei)

    # Forward-compat: pass raw trigger dicts straight through so the JSON
    # round-trip preserves them even before the trigger system is rebuilt.
    if r.has("triggers") and (typeof(r["triggers"]) == TYPE_ARRAY or typeof(r["triggers"]) == TYPE_DICTIONARY):
        info["raw_triggers"] = (r["triggers"] as Array).duplicate(true) if typeof(r["triggers"]) == TYPE_ARRAY else (r["triggers"] as Dictionary).duplicate(true)

    return info


func _parse_parallax_layers(r: Dictionary) -> Array:
    var defaults := [
        {"name": "far", "image": "", "scroll_speed_x": 0.18, "scroll_speed_y": 0.12},
        {"name": "mid", "image": "", "scroll_speed_x": 0.45, "scroll_speed_y": 0.18},
        {"name": "near", "image": "", "scroll_speed_x": 0.78, "scroll_speed_y": 0.24},
    ]
    var normalized: Array = []
    var raw_v: Variant = r.get("parallax_layers", [])
    if typeof(raw_v) == TYPE_ARRAY:
        var raw: Array = raw_v
        for i in defaults.size():
            var merged: Dictionary = defaults[i].duplicate(true)
            if i < raw.size() and typeof(raw[i]) == TYPE_DICTIONARY:
                var src: Dictionary = raw[i]
                merged["name"] = str(src.get("name", merged["name"]))
                merged["image"] = str(src.get("image", src.get("path", "")))
                merged["scroll_speed_x"] = float(src.get("scroll_speed_x", merged["scroll_speed_x"]))
                merged["scroll_speed_y"] = float(src.get("scroll_speed_y", merged["scroll_speed_y"]))
            normalized.append(merged)
        return normalized
    if not str(r.get("backdrop_image", "")).is_empty():
        for entry_v in defaults:
            normalized.append((entry_v as Dictionary).duplicate(true))
        var mid := normalized[1] as Dictionary
        mid["image"] = str(r.get("backdrop_image", ""))
        mid["scroll_speed_x"] = float(r.get("backdrop_scroll_speed_x", mid["scroll_speed_x"]))
        mid["scroll_speed_y"] = float(r.get("backdrop_scroll_speed_y", mid["scroll_speed_y"]))
        return normalized
    for entry_v in defaults:
        normalized.append((entry_v as Dictionary).duplicate(true))
    return normalized


func _parse_tile_layers(r: Dictionary) -> Array:
    # Prefer the new schema (r.tile_layers); fall back to legacy
    # layer1/layer1_hi/layer2+has_layer2 fields. Output is always a
    # non-empty array so load_room has something to render.
    var result: Array = []
    var new_v: Variant = r.get("tile_layers")
    if typeof(new_v) == TYPE_ARRAY and (new_v as Array).size() > 0:
        for entry_v in new_v:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = _normalize_runtime_tile_layer_entry(entry_v)
            var tiles_v: Variant = entry.get("tiles", [])
            if typeof(tiles_v) != TYPE_ARRAY:
                continue
            var anims_v: Variant = entry.get("animations", {})
            var anims_dict: Dictionary = {}
            if typeof(anims_v) == TYPE_DICTIONARY:
                anims_dict = anims_v
            result.append({
                "name": str(entry.get("name", "Layer")),
                "role": str(entry.get("role", ROLE_MAIN)),
                "scroll_speed_x": float(entry.get("scroll_speed_x", 1.0)),
                "scroll_speed_y": float(entry.get("scroll_speed_y", 1.0)),
                "tiles": _parse_2d(tiles_v),
                "animations": anims_dict,
            })
        if not result.is_empty():
            return result

    # Legacy path: layer2 (bg parallax) → layer1 (main) → layer1_hi (fg).
    var has_layer2: bool = bool(r.get("has_layer2", false))
    var layer2_v: Variant = r.get("layer2")
    if has_layer2 and typeof(layer2_v) == TYPE_ARRAY and (layer2_v as Array).size() > 0:
        result.append({
            "name": "Background",
            "role": ROLE_BG,
            "scroll_speed_x": 0.5,
            "scroll_speed_y": 0.5,
            "tiles": _parse_2d(layer2_v),
        })

    var layer1_v: Variant = r.get("layer1")
    var layer1_arr: Array = []
    if typeof(layer1_v) == TYPE_ARRAY:
        layer1_arr = _parse_2d(layer1_v)
    if not layer1_arr.is_empty():
        result.append({
            "name": "Main",
            "role": ROLE_MAIN,
            "scroll_speed_x": 1.0,
            "scroll_speed_y": 1.0,
            "tiles": layer1_arr,
        })

    var layer1_hi_v: Variant = r.get("layer1_hi")
    if typeof(layer1_hi_v) == TYPE_ARRAY and (layer1_hi_v as Array).size() > 0:
        result.append({
            "name": "Foreground",
            "role": ROLE_FG,
            "scroll_speed_x": 1.0,
            "scroll_speed_y": 1.0,
            "tiles": _parse_2d(layer1_hi_v),
        })
    elif not layer1_arr.is_empty():
        # Synthesize an empty FG layer so the editor has a painting target
        # when it loads this room. Same shape as main.
        result.append({
            "name": "Foreground",
            "role": ROLE_FG,
            "scroll_speed_x": 1.0,
            "scroll_speed_y": 1.0,
            "tiles": _blank_matching(layer1_arr),
        })

    return result


static func _migrate_layer_tileset_ids(layer: Array, default_tileset_id: int) -> void:
    for row in layer.size():
        var line: Array = layer[row]
        for col in line.size():
            var v: int = line[col]
            if v == 0:
                continue
            if MvTileValue.get_tileset_id(v) == 0:
                line[col] = MvTileValue.set_tileset_id(v, default_tileset_id)

static func _normalized_scroll_for_role(role: String, sx: float, sy: float) -> Vector2:
    return Vector2.ONE


static func _normalize_layer_role(raw_role: String, layer_name: String = "") -> String:
    var role := raw_role.strip_edges().to_lower()
    if role == ROLE_BG or role == ROLE_MAIN or role == ROLE_FG:
        return role
    var name := layer_name.strip_edges().to_lower()
    if name.contains("foreground") or name == "fg":
        return ROLE_FG
    if name.contains("background") or name == "bg":
        return ROLE_BG
    return ROLE_MAIN


static func _normalize_runtime_tile_layer_entry(layer_data: Dictionary) -> Dictionary:
    var layer_name := str(layer_data.get("name", "Layer"))
    var role := _normalize_layer_role(str(layer_data.get("role", ROLE_MAIN)), layer_name)
    var scroll := _normalized_scroll_for_role(
        role,
        float(layer_data.get("scroll_speed_x", 1.0)),
        float(layer_data.get("scroll_speed_y", 1.0)))
    var normalized := layer_data.duplicate(true)
    normalized["name"] = layer_name
    normalized["role"] = role
    normalized["scroll_speed_x"] = scroll.x
    normalized["scroll_speed_y"] = scroll.y
    return normalized


static func _blank_matching(template: Array) -> Array:
    var result: Array = []
    for row in template.size():
        var line: Array = template[row]
        var inner: Array = []
        inner.resize(line.size())
        inner.fill(0)
        result.append(inner)
    return result


static func _parse_2d(v) -> Array:
    if typeof(v) != TYPE_ARRAY:
        return []
    var result: Array = []
    for row in v:
        var inner: Array = []
        if typeof(row) == TYPE_ARRAY:
            for col in row:
                inner.append(int(col))
        result.append(inner)
    return result


func reload_rooms() -> void:
    var pack := MvPackLoader.current_pack
    if pack == null:
        return
    _rooms.clear()
    _load_room_data(pack.rooms_path())


func load_room(addr: String) -> void:
    if not _rooms.has(addr):
        push_error("MvRoomManager: unknown room '%s'" % addr)
        return

    _reset_active_crumbles(true)

    var info: Dictionary = _rooms[addr]

    # Free any existing TileMapLayer nodes from the previous room.
    if _tile_animator != null:
        _tile_animator.queue_free()
        _tile_animator = null
    for entry in _tile_layers:
        var node: TileMapLayer = entry.get("node")
        if node != null:
            node.queue_free()
    _tile_layers.clear()
    _clear_backdrop()

    var full := _tileset_mgr.get_tile_set(info["tileset"])
    var width_blocks: int = info["width_blocks"]
    var height_blocks: int = info["height_blocks"]
    var tile_layers: Array = info.get("tile_layers", [])

    _apply_backdrop(info)

    # Build TileMapLayer nodes in array order. bg/main go under self; fg
    # goes under _fg_host (so it draws in front of the player). Array
    # order determines z-order within a role.
    for i in tile_layers.size():
        var layer_data: Dictionary = _normalize_runtime_tile_layer_entry(tile_layers[i])
        tile_layers[i] = layer_data
        var layer_name := str(layer_data.get("name", "Layer"))
        var role := str(layer_data.get("role", ROLE_MAIN))
        var tiles: Array = layer_data.get("tiles", [])
        if tiles.is_empty():
            continue

        var node := TileMapLayer.new()
        node.name = "TileLayer_%02d_%s" % [i, layer_name]
        node.tile_set = full
        if role == ROLE_FG and _fg_host != null:
            _fg_host.add_child(node)
        else:
            add_child(node)
        MvRoomRenderer.build_layer(node, tiles, width_blocks, height_blocks)

        _tile_layers.append({
            "node": node,
            "name": layer_name,
            "role": role,
            "scroll_speed": _normalized_scroll_for_role(
                role,
                float(layer_data.get("scroll_speed_x", 1.0)),
                float(layer_data.get("scroll_speed_y", 1.0))),
        })

    # Set up tile animation runner. Pairs each TileMapLayer node with the
    # animations dict from its layer data so the renderer can cycle frames.
    _tile_animator = MvRoomRenderer.new()
    _tile_animator.name = "TileAnimator"
    add_child(_tile_animator)
    var anim_pairs: Array = []
    for i in tile_layers.size():
        var layer_data: Dictionary = tile_layers[i]
        var anims: Dictionary = layer_data.get("animations", {})
        if anims.is_empty():
            continue
        # Find the matching TileMapLayer node. _tile_layers indices track
        # non-empty layers; match by name suffix.
        for entry in _tile_layers:
            var node: TileMapLayer = entry.get("node")
            if node == null:
                continue
            var expected_name := "TileLayer_%02d_%s" % [i, str(layer_data.get("name", "Layer"))]
            if node.name == expected_name:
                anim_pairs.append({"node": node, "animations": anims})
                break
    _tile_animator.load_animations(anim_pairs)

    _current_room_addr = addr
    _build_collision(info)
    _spawn_entities(info)
    MvTriggerEngine.set_room_triggers(info.get("raw_triggers", []))
    MvMapScreen.mark_visited(addr)

    print("[MvRoomManager] entered '%s' (%s) %dx%dpx, blocks %dx%d, tileset %d, tile_layers %d, slopes %d, doors %d, entities %d" % [
        info["name"], addr, info["width_px"], info["height_px"],
        info["width_blocks"], info["height_blocks"], info["tileset"],
        _tile_layers.size(),
        info["slopes"].size(), info["doors"].size(), info["entities"].size()
    ])


func load_start_room() -> void:
    # Packs authored without a start_room (fresh pack, or the entry was
    # deleted) leave _start_room empty, which would orphan the player in
    # an unloaded scene. Fall back to the first authored room so the pack
    # is at least playable, and log loudly so the author sees they need
    # to set a real entry_room.
    if _start_room.is_empty() or not _rooms.has(_start_room):
        if _rooms.is_empty():
            push_error("MvRoomManager: pack has zero rooms — cannot start")
            return
        var fallback: String = _rooms.keys()[0] as String
        push_warning("MvRoomManager: start_room '%s' missing/empty, falling back to '%s'. Set 'start_room' in Pack.json." % [_start_room, fallback])
        _start_room = fallback
    load_room(_start_room)


func rebuild_collision_from_current() -> void:
    if _rooms.has(_current_room_addr):
        _build_collision(_rooms[_current_room_addr])


# Break a destructible block at the given world position. Used by beam
# impacts so a shot that lands on a BT_SHOOT_SOLID cell clears the tile
# and rebuilds collision. Returns true if a block was broken.
func break_block_at_world_pos(world_pos: Vector2) -> bool:
    var info: Dictionary = current_room()
    if info.is_empty() or info["collision"].size() == 0:
        return false

    var col := int(world_pos.x / BLOCK_SIZE)
    var row := int(world_pos.y / BLOCK_SIZE)
    if row < 0 or row >= info["collision"].size():
        return false
    if col < 0 or col >= info["collision"][row].size():
        return false

    var block: int = info["collision"][row][col]
    if not _is_destructible(block):
        return false

    info["collision"][row][col] = BT_AIR
    if info["bts"].size() > 0 and row < info["bts"].size() and col < info["bts"][row].size():
        info["bts"][row][col] = 0

    _clear_tile_cell_on_main_layers(info, Vector2i(col, row))
    _build_collision(info)
    return true


static func _is_destructible(block: int) -> bool:
    # Power-beam-breakable tiles. BT_BOMB_SOLID is intentionally excluded —
    # once weapons matter, its BTS byte will name a specific weapon. Grapple
    # blocks are never damage targets.
    return block == BT_SHOOT_SOLID


# Bomb-breakable tiles. Bombs cover Destructible + Weapon Block placeholders.
func break_bomb_target_at_world_pos(world_pos: Vector2) -> bool:
    var info: Dictionary = current_room()
    if info.is_empty() or info["collision"].size() == 0:
        return false

    var col := int(world_pos.x / BLOCK_SIZE)
    var row := int(world_pos.y / BLOCK_SIZE)
    if row < 0 or row >= info["collision"].size():
        return false
    if col < 0 or col >= info["collision"][row].size():
        return false

    var block: int = info["collision"][row][col]
    if block != BT_SHOOT_SOLID and block != BT_BOMB_SOLID:
        return false

    info["collision"][row][col] = BT_AIR
    if info["bts"].size() > 0 and row < info["bts"].size() and col < info["bts"][row].size():
        info["bts"][row][col] = 0

    _clear_tile_cell_on_main_layers(info, Vector2i(col, row))
    _build_collision(info)
    return true


# Clears the cell at `cell` on every main/fg tile layer so breaking a wall
# also wipes its visual. bg layers are parallax decoration — not cleared.
# Mirrors the change into the parsed info.tile_layers so the in-memory
# view stays consistent with what's rendered.
func _clear_tile_cell_on_main_layers(info: Dictionary, cell: Vector2i) -> void:
    for entry in _tile_layers:
        var role := str(entry.get("role", ROLE_MAIN))
        if role == ROLE_BG:
            continue
        var node: TileMapLayer = entry.get("node")
        if node != null:
            node.set_cell(cell, -1)
    var data_layers_v: Variant = info.get("tile_layers", [])
    if typeof(data_layers_v) != TYPE_ARRAY:
        return
    for layer_entry_v in data_layers_v:
        if typeof(layer_entry_v) != TYPE_DICTIONARY:
            continue
        var layer_entry: Dictionary = _normalize_runtime_tile_layer_entry(layer_entry_v)
        if str(layer_entry.get("role", ROLE_MAIN)) == ROLE_BG:
            continue
        var tiles_v: Variant = layer_entry.get("tiles", [])
        if typeof(tiles_v) != TYPE_ARRAY:
            continue
        var tiles: Array = tiles_v
        if cell.y < 0 or cell.y >= tiles.size():
            continue
        var row_v: Variant = tiles[cell.y]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row_arr: Array = row_v
        if cell.x >= 0 and cell.x < row_arr.size():
            row_arr[cell.x] = 0


func _build_collision(info: Dictionary) -> void:
    for child in _collision_container.get_children():
        child.queue_free()

    var collision: Array = info["collision"]
    if collision.size() == 0:
        return

    var rows: int = collision.size()
    var cols: int = collision[0].size()

    # Greedy-merge contiguous mergeable cells into rectangles. Each merged
    # rect becomes a single StaticBody2D + RectangleShape2D. Slopes get per
    # cell convex polygon colliders further down.
    var visited: Array = []
    for _r in rows:
        var line: Array = []
        line.resize(cols)
        line.fill(false)
        visited.append(line)

    for r in rows:
        for c in cols:
            if visited[r][c]:
                continue
            if not _is_rect_mergeable(collision[r][c]):
                continue

            var end_c := c
            while end_c + 1 < cols and not visited[r][end_c + 1] \
                    and _is_rect_mergeable(collision[r][end_c + 1]):
                end_c += 1

            var end_r := r
            while end_r + 1 < rows:
                var full_row := true
                for cc in range(c, end_c + 1):
                    if visited[end_r + 1][cc] or not _is_rect_mergeable(collision[end_r + 1][cc]):
                        full_row = false
                        break
                if not full_row:
                    break
                end_r += 1

            for rr in range(r, end_r + 1):
                for cc in range(c, end_c + 1):
                    visited[rr][cc] = true

            var w := (end_c - c + 1) * BLOCK_SIZE
            var h := (end_r - r + 1) * BLOCK_SIZE
            var cx: float = c * BLOCK_SIZE + w / 2.0
            var cy: float = r * BLOCK_SIZE + h / 2.0

            var body := StaticBody2D.new()
            var shape_node := CollisionShape2D.new()
            var rect := RectangleShape2D.new()
            rect.size = Vector2(w, h)
            shape_node.shape = rect
            body.position = Vector2(cx, cy)
            body.add_child(shape_node)
            _collision_container.add_child(body)

    # Build the slope lookup grid for runtime try_get_slope_floor queries.
    # Two sources: explicit SlopeCell entries from rooms.json "slopes", and
    # any BT_SLOPE cells painted into the collision grid by the editor. The
    # editor doesn't maintain the Slopes list — it writes BT_SLOPE + a BTS
    # byte — so without synthesizing from the grid, slope blocks would
    # produce zero collision.
    #
    # BTS byte layout for BT_SLOPE: bits 0-5 shape index, bit 6 HFlip, bit 7
    # VFlip. bts==0 defaults to shape 1 (45 up-ramp) so the common "paint a
    # slope block" case just works.
    var shape_count: int = _slope_shapes.size()
    var slope_grid: Array = []
    for _r in rows:
        var line: Array = []
        line.resize(cols)
        line.fill(null)
        slope_grid.append(line)
    for s in info["slopes"]:
        var sr: int = s["row"]
        var sc: int = s["col"]
        if sr >= 0 and sr < rows and sc >= 0 and sc < cols:
            slope_grid[sr][sc] = s
    for r in rows:
        for c in cols:
            if collision[r][c] != BT_SLOPE:
                continue
            if slope_grid[r][c] != null:
                continue
            var bts_val := 0
            var bts: Array = info["bts"]
            if bts.size() > 0 and r < bts.size() and c < bts[r].size():
                bts_val = bts[r][c]
            var shape_idx := bts_val & 0x3F
            if shape_idx == 0 or shape_idx >= shape_count:
                shape_idx = 1 if shape_count > 1 else 0
            slope_grid[r][c] = {
                "row":   r,
                "col":   c,
                "shape": shape_idx,
                "hflip": (bts_val & 0x40) != 0,
                "vflip": (bts_val & 0x80) != 0,
            }
    info["slope_grid"] = slope_grid

    # Spawn a physical collider for every slope cell so the player has
    # something solid to walk onto — TryGetSlopeFloor sampling alone can't
    # catch a player approaching horizontally (she'd fall through before her
    # feet reach the sample row). A ConvexPolygonShape2D built from the
    # slope shape gives Godot's collision engine real geometry to resolve
    # against; the existing Y snap in Player still handles sub-pixel smoothing.
    for r in rows:
        for c in cols:
            var sc_dict = slope_grid[r][c]
            if sc_dict == null:
                continue
            var poly := _build_slope_polygon(sc_dict)
            if poly == null:
                continue
            var body := StaticBody2D.new()
            var shape_node := CollisionShape2D.new()
            shape_node.shape = poly
            body.add_child(shape_node)
            body.position = Vector2(c * BLOCK_SIZE, r * BLOCK_SIZE)
            _collision_container.add_child(body)


# Walks the room's entity layer and spawns runtime nodes for every
# authored entry. Dispatches by category from entities.json:
#   enemy → MvEnemy, boss → MvBoss, interactable → MvInteractable,
#   pickup → MvPickup, logic → MvTriggerVolume.
#
# Called from load_room after collision is rebuilt. Previous room's
# entities are freed by clearing _entities_container children.
func _spawn_entities(info: Dictionary) -> void:
    for child in _entities_container.get_children():
        child.queue_free()

    var pack := MvPackLoader.current_pack
    if pack == null:
        return

    var arr_v: Variant = info.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return

    var entity_defs := _load_entity_defs(pack.pack_id)
    var room_id: String = str(info.get("id", ""))

    for e_v in arr_v:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var type_id := str(e.get("type", ""))
        if type_id == "":
            continue
        if type_id == "player_spawn":
            continue

        var entity_tags: Array = e.get("tags", [])
        var entity_props: Dictionary = e.get("properties", {})
        var instance_id: String = str(e.get("instance_id", _fallback_entity_instance_id(type_id, e.get("position", Vector2.ZERO)))).strip_edges()
        var category := str(entity_defs.get(type_id, {}).get("category", "enemy"))

        var node: Node2D = null
        match category:
            "interactable":
                var npc := _MvInteractable.new()
                npc.configure(pack.pack_id, type_id, entity_tags, entity_props)
                npc.instance_id = instance_id
                node = npc
            "pickup":
                var pickup := _MvPickup.new()
                pickup.configure(pack.pack_id, type_id, entity_tags, entity_props)
                pickup.room_id = room_id
                pickup.instance_id = instance_id
                node = pickup
            "logic":
                var vol := _MvTriggerVolume.new()
                vol.configure(pack.pack_id, type_id, entity_tags, entity_props)
                vol.room_id = room_id
                vol.instance_id = instance_id
                node = vol
            "boss":
                var boss := _MvBoss.new()
                boss.configure(pack.pack_id, type_id)
                boss.instance_id = instance_id
                node = boss
            _:
                var enemy := MvEnemy.new()
                enemy.configure(pack.pack_id, type_id)
                enemy.instance_id = instance_id
                node = enemy

        var pos_v: Variant = e.get("position", Vector2.ZERO)
        if pos_v is Vector2:
            node.position = pos_v
        _entities_container.add_child(node)

        if category == "enemy" or category == "boss":
            MvTriggerEngine.fire_event("enemy_spawn", {
                "entity_id": type_id,
                "room_id": room_id,
                "position": node.position,
                "tags": entity_tags,
            })


func spawn_entity_dynamic(type_id: String, pos: Vector2, entity_tags: Array = [], entity_props: Dictionary = {}) -> Node2D:
    if type_id.is_empty() or _entities_container == null:
        return null
    var pack := MvPackLoader.current_pack
    if pack == null:
        return null
    var entity_defs := _load_entity_defs(pack.pack_id)
    var category := str(entity_defs.get(type_id, {}).get("category", "enemy"))
    var room_id := _current_room_addr
    var uid := str(entity_props.get("instance_id", "")).strip_edges()
    if uid.is_empty():
        uid = "%s_dyn_%d" % [type_id, Time.get_ticks_msec()]
    var node: Node2D = null
    match category:
        "interactable":
            var npc := _MvInteractable.new()
            npc.configure(pack.pack_id, type_id, entity_tags, entity_props)
            npc.instance_id = uid
            node = npc
        "pickup":
            var pickup := _MvPickup.new()
            pickup.configure(pack.pack_id, type_id, entity_tags, entity_props)
            pickup.room_id = room_id
            pickup.instance_id = uid
            node = pickup
        "logic":
            var vol := _MvTriggerVolume.new()
            vol.configure(pack.pack_id, type_id, entity_tags, entity_props)
            vol.room_id = room_id
            vol.instance_id = uid
            node = vol
        "boss":
            var boss := _MvBoss.new()
            boss.configure(pack.pack_id, type_id)
            boss.instance_id = uid
            node = boss
        _:
            var enemy := MvEnemy.new()
            enemy.configure(pack.pack_id, type_id)
            enemy.instance_id = uid
            node = enemy
    node.position = pos
    _entities_container.add_child(node)
    return node


func spawn_entity_at_zone(type_id: String, zone_id: String, data: Dictionary = {}) -> Node2D:
    var pos := resolve_zone_position(zone_id)
    if pos.x < 0.0 or pos.y < 0.0:
        push_warning("MvRoomManager: spawn_entity_at_zone could not find zone '%s'" % zone_id)
        return null
    var entity_tags: Array = []
    var tags_v: Variant = data.get("tags", [])
    if typeof(tags_v) == TYPE_ARRAY:
        entity_tags = tags_v
    var entity_props: Dictionary = {}
    var props_v: Variant = data.get("properties", {})
    if typeof(props_v) == TYPE_DICTIONARY:
        entity_props = props_v
    return spawn_entity_dynamic(type_id, pos, entity_tags, entity_props)


func despawn_entity_by_id(entity_id_or_name: String) -> bool:
    if _entities_container == null or entity_id_or_name.is_empty():
        return false
    for child in _entities_container.get_children():
        var matched := false
        if "instance_id" in child and str(child.get("instance_id")) == entity_id_or_name:
            matched = true
        elif "entity_id" in child and str(child.get("entity_id")) == entity_id_or_name:
            matched = true
        elif child.name == entity_id_or_name:
            matched = true
        if matched:
            child.queue_free()
            return true
    return false


func find_entity_node(entity_ref: String) -> Node2D:
    if _entities_container == null or entity_ref.is_empty():
        return null
    for child in _entities_container.get_children():
        var node := child as Node2D
        if node == null:
            continue
        var instance_id := _node_instance_id(node)
        if not instance_id.is_empty() and instance_id == entity_ref:
            return node
        if "entity_id" in node and str(node.get("entity_id")) == entity_ref:
            return node
        if node.name == entity_ref:
            return node
    return null


func resolve_zone_position(zone_id: String) -> Vector2:
    var trimmed := zone_id.strip_edges()
    if trimmed.is_empty():
        return Vector2(-1, -1)
    if _entities_container != null:
        for child in _entities_container.get_children():
            var node := child as Node2D
            if node == null:
                continue
            if _node_zone_id(node) == trimmed:
                return node.position
    var info: Dictionary = current_room()
    var entities_v: Variant = info.get("entities", [])
    if typeof(entities_v) != TYPE_ARRAY:
        return Vector2(-1, -1)
    for e_v in entities_v:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var props_v: Variant = e.get("properties", {})
        if typeof(props_v) != TYPE_DICTIONARY:
            continue
        if str((props_v as Dictionary).get("zone_id", "")).strip_edges() == trimmed:
            var pos_v: Variant = e.get("position", Vector2(-1, -1))
            if pos_v is Vector2:
                return pos_v
    return Vector2(-1, -1)


func move_entity_to_zone(entity_ref: String, zone_id: String, speed: float = 64.0) -> bool:
    var node := find_entity_node(entity_ref)
    if node == null:
        push_warning("MvRoomManager: move_entity_to_zone could not find entity '%s'" % entity_ref)
        return false
    var pos := resolve_zone_position(zone_id)
    if pos.x < 0.0 or pos.y < 0.0:
        push_warning("MvRoomManager: move_entity_to_zone could not find zone '%s'" % zone_id)
        return false
    if node.has_method("begin_scripted_move"):
        node.call("begin_scripted_move", pos, speed)
    else:
        node.position = pos
    return true


func play_entity_animation(entity_ref: String, anim_name: String, loop: bool = true, speed_scale: float = 1.0) -> bool:
    var node := find_entity_node(entity_ref)
    if node == null:
        push_warning("MvRoomManager: play_entity_animation could not find entity '%s'" % entity_ref)
        return false
    if node.has_method("play_scripted_animation"):
        node.call("play_scripted_animation", anim_name, loop, speed_scale)
        return true
    return false


func _node_instance_id(node: Node) -> String:
    if "instance_id" in node:
        return str(node.get("instance_id")).strip_edges()
    if node.has_meta("instance_id"):
        return str(node.get_meta("instance_id", "")).strip_edges()
    return ""


func _node_zone_id(node: Node) -> String:
    if "properties" in node:
        var props_v: Variant = node.get("properties")
        if typeof(props_v) == TYPE_DICTIONARY:
            var props: Dictionary = {}
            props = props_v
            var zone_id := str(props.get("zone_id", "")).strip_edges()
            if not zone_id.is_empty():
                return zone_id
    var instance_id := _node_instance_id(node)
    if instance_id.begins_with("zone_"):
        return instance_id
    return ""


func _fallback_entity_instance_id(type_id: String, pos: Vector2) -> String:
    var col := maxi(0, floori(pos.x / float(BLOCK_SIZE)))
    var row := maxi(0, floori(pos.y / float(BLOCK_SIZE)))
    if type_id == "trigger_volume":
        return "zone_%d_%d" % [col, row]
    return "%s_%d_%d" % [type_id, col, row]


static func _load_entity_defs(pack_id: String) -> Dictionary:
    const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")
    var data := EntIO.load_or_init(pack_id)
    var out: Dictionary = {}
    var list_v: Variant = data.get("entities", [])
    if typeof(list_v) != TYPE_ARRAY:
        return out
    for row_v in list_v:
        if typeof(row_v) != TYPE_DICTIONARY:
            continue
        var eid := str(row_v.get("id", ""))
        if not eid.is_empty():
            out[eid] = row_v
    return out


func _build_slope_polygon(sc: Dictionary) -> ConvexPolygonShape2D:
    if _slope_shapes.is_empty():
        return null
    var sh_idx: int = sc["shape"]
    if sh_idx < 0 or sh_idx >= _slope_shapes.size():
        return null
    var shape: Array = _slope_shapes[sh_idx]

    # Evaluate the surface at each column, applying H/V flips the same way
    # try_get_slope_floor does so the collider matches the sample math.
    # Completely empty shapes (all 16s) produce no collider.
    var points: PackedVector2Array = PackedVector2Array()
    var any_solid := false
    for x in shape.size():
        var src_x: int = (shape.size() - 1 - x) if sc["hflip"] else x
        var surface_y: int = shape[src_x]
        if sc["vflip"]:
            if surface_y >= 16:
                continue
            surface_y = 16 - surface_y
        elif surface_y >= 16:
            continue
        any_solid = true
        points.append(Vector2(x, surface_y))
    if not any_solid or points.size() < 2:
        return null

    # Extend the surface to the right edge of the cell so the polygon
    # reaches x=16 instead of stopping at the last shape column. Avoids a
    # 1px gap where the next cell's collider starts.
    var last := points[points.size() - 1]
    points.append(Vector2(BLOCK_SIZE, last.y))

    # V-flipped slopes are ceilings — close along the top of the cell (y=0)
    # instead of the bottom. Non-flipped slopes close along y=16 (bottom).
    if sc["vflip"]:
        points.append(Vector2(BLOCK_SIZE, 0))
        points.append(Vector2(0, 0))
    else:
        points.append(Vector2(BLOCK_SIZE, BLOCK_SIZE))
        points.append(Vector2(0, BLOCK_SIZE))

    var poly := ConvexPolygonShape2D.new()
    poly.points = points
    return poly


# Sample the slope surface Y under a world position. Returns a dict:
#   { "hit": bool, "floor_y": float }
# hit=true means (world_x, world_y) is inside a slope cell with a solid
# surface at this column; floor_y is the world-Y where the player's feet
# should rest.
func try_get_slope_floor(world_x: float, world_y: float) -> Dictionary:
    var result := { "hit": false, "floor_y": 0.0 }
    var info: Dictionary = current_room()
    if info.is_empty() or info["slope_grid"].size() == 0 or _slope_shapes.is_empty():
        return result

    var col := int(world_x / BLOCK_SIZE)
    var row := int(world_y / BLOCK_SIZE)
    if row < 0 or row >= info["slope_grid"].size():
        return result
    if col < 0 or col >= info["slope_grid"][row].size():
        return result

    var sc = info["slope_grid"][row][col]
    if sc == null:
        return result
    var sh_idx: int = sc["shape"]
    if sh_idx < 0 or sh_idx >= _slope_shapes.size():
        return result

    var shape: Array = _slope_shapes[sh_idx]
    var x_in_cell: int = int(floor(world_x)) - col * BLOCK_SIZE
    if x_in_cell < 0:
        x_in_cell = 0
    if x_in_cell > 15:
        x_in_cell = 15
    if sc["hflip"]:
        x_in_cell = 15 - x_in_cell

    var surface_y: int = shape[x_in_cell]
    if sc["vflip"]:
        # V-flipped slope: $10 columns are no-contact; others reflect
        # around the cell midpoint.
        if surface_y >= 16:
            return result
        surface_y = 16 - surface_y
    else:
        if surface_y >= 16:
            return result

    result["hit"] = true
    result["floor_y"] = float(row * BLOCK_SIZE + surface_y)
    return result


static func _is_rect_mergeable(block_type: int) -> bool:
    return block_type == BT_SOLID \
        or block_type == BT_SHOOT_SOLID \
        or block_type == BT_BOMB_SOLID \
        or block_type == BT_GRAPPLE_BLOCK \
        or block_type == BT_SPIKE \
        or block_type == BT_CRUMBLE


func find_door(direction: String) -> Dictionary:
    var info: Dictionary = current_room()
    if info.is_empty():
        return {}
    for door in info["doors"]:
        if door["direction"] == direction:
            return door
    return {}


func find_door_for_points(points: Array, preferred_direction: String = "") -> Dictionary:
    var info: Dictionary = current_room()
    if info.is_empty():
        return {}
    var dir_filter := preferred_direction.strip_edges()
    for door_v in info["doors"]:
        if typeof(door_v) != TYPE_DICTIONARY:
            continue
        var door: Dictionary = door_v
        var door_dir := str(door.get("direction", "")).strip_edges()
        if not dir_filter.is_empty() and door_dir != dir_filter:
            continue
        var rect := _door_world_rect(door)
        if rect.size.x <= 0.0 or rect.size.y <= 0.0:
            continue
        var probe := rect.grow(2.0)
        for point_v in points:
            if typeof(point_v) != TYPE_VECTOR2:
                continue
            if probe.has_point(point_v):
                return door
    return {}


func _door_world_rect(door: Dictionary) -> Rect2:
    var block_x := int(door.get("cap_block_x", -1))
    var block_y := int(door.get("cap_block_y", -1))
    if block_x < 0 or block_y < 0:
        return Rect2()
    var local_pos := Vector2(float(block_x * BLOCK_SIZE), float(block_y * BLOCK_SIZE))
    return Rect2(to_global(local_pos), Vector2(float(BLOCK_SIZE), float(BLOCK_SIZE)))


func get_room(addr: String) -> Dictionary:
    return _rooms.get(addr, {})


func _clear_backdrop() -> void:
    _backdrop_layers.clear()
    if _backdrop_root == null:
        return
    for child in _backdrop_root.get_children():
        child.queue_free()


func _apply_backdrop(info: Dictionary) -> void:
    if _backdrop_root == null:
        return
    var layers_v: Variant = info.get("parallax_layers", [])
    if typeof(layers_v) == TYPE_ARRAY:
        for layer_v in layers_v:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            _apply_backdrop_layer(info, layer_v)
    elif not str(info.get("backdrop_image", "")).is_empty():
        _apply_backdrop_layer(info, {
            "name": "mid",
            "image": str(info.get("backdrop_image", "")),
            "scroll_speed_x": float(info.get("backdrop_scroll_speed_x", 0.94)),
            "scroll_speed_y": float(info.get("backdrop_scroll_speed_y", 0.97)),
        })


func _apply_backdrop_layer(info: Dictionary, layer: Dictionary) -> void:
    var rel_path := str(layer.get("image", ""))
    if rel_path.is_empty():
        return
    var tex_path := _resolve_pack_asset_path(rel_path)
    var tex := _load_backdrop_texture(tex_path)
    if not (tex is Texture2D):
        push_warning("MvRoomManager: failed to load backdrop '%s' for room '%s'" % [tex_path, info.get("addr", "")])
        return

    var spr := Sprite2D.new()
    spr.name = "Backdrop_%s" % str(layer.get("name", "layer"))
    spr.centered = false
    spr.texture = tex as Texture2D
    spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _backdrop_root.add_child(spr)

    var tex_size: Vector2 = (spr.texture as Texture2D).get_size()
    var room_size := Vector2(
        maxf(1.0, float(info.get("width_px", tex_size.x))),
        maxf(1.0, float(info.get("height_px", tex_size.y))))

    _backdrop_layers.append({
        "node": spr,
        "room_size": room_size,
        "texture_size": tex_size,
        "scroll_speed": Vector2(
            float(layer.get("scroll_speed_x", 1.0)),
            float(layer.get("scroll_speed_y", 1.0))),
    })
    var cam := get_viewport().get_camera_2d()
    if cam != null:
        _update_backdrop_layer_transform(_backdrop_layers[_backdrop_layers.size() - 1], cam, cam.get_screen_center_position())


func _resolve_pack_asset_path(rel_path: String) -> String:
    if rel_path.begins_with("res://") or rel_path.begins_with("user://"):
        return rel_path
    if _pack != null:
        return _pack.resolve_read(rel_path)
    return "res://Content/demo/%s" % rel_path


func _load_backdrop_texture(path: String) -> Texture2D:
    if FileAccess.file_exists(path):
        var f := FileAccess.open(path, FileAccess.READ)
        if f != null:
            var bytes := f.get_buffer(f.get_length())
            f.close()
            var img := Image.new()
            if img.load_png_from_buffer(bytes) == OK:
                return ImageTexture.create_from_image(img)
    var tex := load(path)
    if tex is Texture2D:
        return tex
    return null


func _update_backdrop_layer_transform(entry: Dictionary, cam: Camera2D, cam_pos: Vector2) -> void:
    var node: Sprite2D = entry.get("node") as Sprite2D
    if node == null or node.texture == null:
        return
    var room_size: Vector2 = entry.get("room_size", Vector2.ONE)
    var tex_size: Vector2 = entry.get("texture_size", node.texture.get_size())
    var speed: Vector2 = entry.get("scroll_speed", Vector2.ONE)
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return

    var view_size := _camera_view_world_size(cam)
    var center_min := view_size * 0.5
    var center_max := room_size - view_size * 0.5
    var progress := Vector2(
        _axis_camera_progress(cam_pos.x, center_min.x, center_max.x),
        _axis_camera_progress(cam_pos.y, center_min.y, center_max.y)
    )

    var target_size := Vector2(
        _backdrop_axis_target_size(room_size.x, view_size.x, speed.x),
        _backdrop_axis_target_size(room_size.y, view_size.y, speed.y)
    )
    node.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)

    var slack := Vector2(
        maxf(0.0, target_size.x - room_size.x),
        maxf(0.0, target_size.y - room_size.y)
    )
    node.position = Vector2(
        _backdrop_axis_position(progress.x, slack.x, speed.x),
        _backdrop_axis_position(progress.y, slack.y, speed.y)
    )


func _camera_view_world_size(cam: Camera2D) -> Vector2:
    var viewport_size: Vector2 = cam.get_viewport_rect().size
    return Vector2(
        maxf(1.0, viewport_size.x * cam.zoom.x),
        maxf(1.0, viewport_size.y * cam.zoom.y)
    )


func _axis_camera_progress(cam_pos: float, center_min: float, center_max: float) -> float:
    if center_max <= center_min:
        return 0.0
    return clampf((cam_pos - center_min) / (center_max - center_min), 0.0, 1.0)


func _backdrop_axis_target_size(room_span: float, view_span: float, speed: float) -> float:
    var strength := absf(1.0 - speed)
    var overscan := maxf(0.0, room_span - view_span) * strength
    return maxf(1.0, room_span + overscan)


func _backdrop_axis_position(progress: float, slack: float, speed: float) -> float:
    if slack <= 0.0:
        return 0.0
    var dir := -1.0 if speed <= 1.0 else 1.0
    return progress * slack * dir


func current_room() -> Dictionary:
    return _rooms.get(_current_room_addr, {})


func current_room_addr() -> String:
    return _current_room_addr


func has_room(addr: String) -> bool:
    return _rooms.has(addr)


func resolve_room_addr(addr: String, from_room_addr: String = "") -> String:
    var trimmed := addr.strip_edges()
    if trimmed.is_empty():
        return ""
    if _rooms.has(trimmed):
        return trimmed

    var realm_id := ""
    var region_id := ""
    var source_addr := from_room_addr.strip_edges()
    if source_addr.is_empty():
        source_addr = _current_room_addr
    var source_parts := source_addr.split("/", false)
    if source_parts.size() >= 3:
        realm_id = str(source_parts[0]).strip_edges()
        region_id = str(source_parts[1]).strip_edges()
    elif source_parts.size() == 2:
        region_id = str(source_parts[0]).strip_edges()
    if not realm_id.is_empty() and trimmed.count("/") == 1:
        var realm_prefixed := "%s/%s" % [realm_id, trimmed]
        if _rooms.has(realm_prefixed):
            return realm_prefixed
    if not region_id.is_empty() and not trimmed.contains("/"):
        var regional := "%s/%s/%s" % [realm_id, region_id, trimmed] if not realm_id.is_empty() else "%s/%s" % [region_id, trimmed]
        if _rooms.has(regional):
            return regional

    var regional_name_match := ""
    var realm_name_match := ""
    for key_v in _rooms.keys():
        var key := str(key_v)
        var room_v: Variant = _rooms[key]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        if str(room.get("name", "")).strip_edges() != trimmed:
            continue
        if not realm_id.is_empty() and not region_id.is_empty() and key.begins_with("%s/%s/" % [realm_id, region_id]):
            return key
        if not realm_id.is_empty() and key.begins_with(realm_id + "/"):
            if realm_name_match.is_empty():
                realm_name_match = key
            continue
        if not region_id.is_empty() and key.begins_with(region_id + "/"):
            return key
        if regional_name_match.is_empty():
            regional_name_match = key
    if not realm_name_match.is_empty():
        return realm_name_match
    return regional_name_match


func start_room() -> String:
    return _start_room


func rooms() -> Dictionary:
    return _rooms


func tileset_mgr() -> MvTilesetManager:
    return _tileset_mgr
