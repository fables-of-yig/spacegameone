class_name MvRoomManager
extends Node2D

const _MvInteractable := preload("res://MV/scripts/interactable.gd")
const _MvPickup := preload("res://MV/scripts/pickup.gd")
const _MvTriggerVolume := preload("res://MV/scripts/trigger_volume.gd")
const _MvBoss := preload("res://MV/scripts/boss.gd")
const _MvWeatherOverlay := preload("res://MV/scripts/weather_overlay.gd")
const RegIO := preload("res://Space/scripts/shared/reg/reg_io.gd")

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
var _shader_fx_root: Node2D = null
var _crumble_fx_root: Node2D = null

var _collision_container: Node2D
var _entities_container: Node2D
var _tileset_mgr: MvTilesetManager
var _pack: MvPackRef = null
# _current_room_addr is the CANONICAL addr the rest of the game tracks —
# what doors target, what the map screen records, what save snapshots
# store. _loaded_room_addr is the actual key into _rooms whose data was
# instantiated this frame. The two differ when a room_variants.json rule
# fired and the player is standing inside an alternate. current_room()
# returns the loaded data; current_room_addr() returns the canonical id
# so external state stays stable across variant swaps.
var _current_room_addr: String = ""
var _loaded_room_addr: String = ""
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
const _BG_SHADER_CODE: String = "shader_type canvas_item;\nuniform int effect_mode = 0;\nuniform vec4 tint : source_color = vec4(1.0);\nuniform float strength = 0.6;\nuniform float speed = 1.0;\nvoid fragment() {\n\tvec2 uv = UV;\n\tif (effect_mode == 2 || effect_mode == 3) {\n\t\tfloat off = sin((uv.y * 24.0 + TIME * speed * 4.0)) * strength * 0.02;\n\t\tuv.x += off;\n\t}\n\tvec4 tex = texture(TEXTURE, uv);\n\tif (effect_mode == 1) {\n\t\tfloat flick = 1.0 - strength * 0.35 + sin(TIME * (6.0 * speed) + uv.y * 12.0) * strength * 0.2;\n\t\ttex.rgb *= flick;\n\t} else if (effect_mode == 3) {\n\t\tfloat shimmer = sin((uv.y * 32.0) - TIME * speed * 5.0) * strength * 0.15;\n\t\ttex.rgb += tint.rgb * max(shimmer, 0.0) * 0.5;\n\t}\n\ttex.rgb *= mix(vec3(1.0), tint.rgb, clamp(strength, 0.0, 1.0));\n\ttex.a *= tint.a;\n\tCOLOR = tex;\n}\n"
const _ROOM_FX_SHADER_CODE: String = "shader_type canvas_item;\nrender_mode unshaded, blend_mix;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;\nuniform int effect_mode = 1;\nuniform vec4 tint : source_color = vec4(1.0);\nuniform float strength = 0.6;\nuniform float speed = 1.0;\nvoid fragment() {\n\tvec2 uv = SCREEN_UV;\n\tvec2 offset = vec2(0.0);\n\tif (effect_mode == 2 || effect_mode == 3) {\n\t\tfloat wave = sin((UV.y * 32.0 + TIME * speed * 4.0)) * 0.006 * strength;\n\t\toffset.x += wave;\n\t}\n\tvec4 src = textureLod(screen_tex, uv + offset, 0.0);\n\tif (effect_mode == 1) {\n\t\tfloat flick = 1.0 - strength * 0.22 + sin(TIME * (7.0 * speed) + UV.y * 12.0) * strength * 0.18;\n\t\tsrc.rgb *= flick;\n\t} else if (effect_mode == 3) {\n\t\tfloat shimmer = sin((UV.y * 42.0) - TIME * speed * 6.0) * strength * 0.18;\n\t\tsrc.rgb += tint.rgb * max(shimmer, 0.0) * 0.5;\n\t}\n\tsrc.rgb = mix(src.rgb, src.rgb * tint.rgb, clamp(strength * 0.6, 0.0, 1.0));\n\tsrc.a = 1.0;\n\tCOLOR = src;\n}\n"

var _backdrop_shader: Shader = null
var _room_fx_shader: Shader = null
var _weather_canvas: CanvasLayer = null
var _weather_overlay: Control = null


func _ready() -> void:
    _backdrop_root = Node2D.new()
    _backdrop_root.name = "Backdrop"
    _backdrop_root.z_index = -100
    add_child(_backdrop_root)

    _shader_fx_root = Node2D.new()
    _shader_fx_root.name = "ShaderFx"
    _shader_fx_root.z_index = 80
    add_child(_shader_fx_root)

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

    _weather_canvas = CanvasLayer.new()
    _weather_canvas.name = "WeatherCanvas"
    add_child(_weather_canvas)
    _weather_overlay = _MvWeatherOverlay.new()
    _weather_canvas.add_child(_weather_overlay)

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
        _update_backdrop_layer_animation(entry, _delta)
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
    @warning_ignore("integer_division")
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
            @warning_ignore("integer_division")
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
    var room_list: Dictionary = raw.get("rooms", {})
    for key in room_list.keys():
        var addr := str(key)
        var info := _parse_room_info(addr, room_list[key])
        _rooms[addr] = info

    print("[MvRoomManager] loaded %d room(s), start=%s" % [_rooms.size(), _start_room])


func _parse_room_info(addr: String, r: Dictionary) -> Dictionary:
    var info: Dictionary = {
        "addr": addr,
        "name": str(r.get("friendly_name", addr)),
        "parallax_enabled": bool(r.get("parallax_enabled", true)),
        "backdrop_image": str(r.get("backdrop_image", "")),
        "backdrop_scroll_speed_x": float(r.get("backdrop_scroll_speed_x", 0.94)),
        "backdrop_scroll_speed_y": float(r.get("backdrop_scroll_speed_y", 0.97)),
        "parallax_layers": _parse_parallax_layers(r),
        "background_images": _parse_background_images(r),
        "background_image": _parse_background_image(r),
        "shader_regions": _parse_shader_regions(r),
        "weather": _parse_weather(r),
        "width_screens":  int(r.get("width_screens", 0)),
        "height_screens": int(r.get("height_screens", 0)),
        "width_blocks":   int(r.get("width_blocks", 0)),
        "height_blocks":  int(r.get("height_blocks", 0)),
        "width_px":       int(r.get("width_px", 0)),
        "height_px":      int(r.get("height_px", 0)),
        "tileset":        int(r.get("tileset", 0)),
        "zones":          [],
        "doors":          [],
        "tile_layers":    [],
        "collision":      [],
        "bts":            [],
        "slopes":         [],
        "slope_grid":     [],
        "entities":       [],
        "raw_triggers":   [],
    }

    info["zones"] = _parse_room_zones(r)
    info["doors"] = _parse_room_doors(r, info["zones"])

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
        @warning_ignore("incompatible_ternary")
        info["raw_triggers"] = (r["triggers"] as Array).duplicate(true) if typeof(r["triggers"]) == TYPE_ARRAY else (r["triggers"] as Dictionary).duplicate(true)

    return info


func _parse_room_zones(r: Dictionary) -> Array:
    var out: Array = []
    var zones_v: Variant = r.get("zones", [])
    if typeof(zones_v) != TYPE_ARRAY:
        return out
    for zone_v in zones_v:
        if typeof(zone_v) != TYPE_DICTIONARY:
            continue
        out.append((zone_v as Dictionary).duplicate(true))
    return out


func _parse_room_doors(r: Dictionary, zones: Array) -> Array:
    var out: Array = []
    var seen_ids: Dictionary = {}
    for zone_v in zones:
        if typeof(zone_v) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zone_v
        if str(zone.get("kind", "")).strip_edges().to_lower() != "door":
            continue
        var door := _parse_door_from_zone(zone)
        var door_id := str(door.get("id", "")).strip_edges()
        if door_id.is_empty():
            continue
        seen_ids[door_id] = true
        out.append(door)
    if not out.is_empty():
        return out

    var doors_v: Variant = r.get("doors", [])
    if typeof(doors_v) != TYPE_ARRAY:
        return out
    for d_v in doors_v:
        if typeof(d_v) != TYPE_DICTIONARY:
            continue
        var door := _parse_legacy_door(d_v as Dictionary)
        var door_id := str(door.get("id", "")).strip_edges()
        if door_id.is_empty() or seen_ids.has(door_id):
            continue
        out.append(door)
    return out


func _parse_door_from_zone(zone: Dictionary) -> Dictionary:
    var tags: Array = []
    var tags_v: Variant = zone.get("tags", [])
    if typeof(tags_v) == TYPE_ARRAY:
        for tag_v in tags_v:
            tags.append(str(tag_v))
    return {
        "id": str(zone.get("id", "")),
        "target_door_id": str(zone.get("target_door_id", zone.get("target_room", ""))).strip_edges(),
        "target": str(zone.get("target_room", "")).strip_edges(),
        "direction": str(zone.get("direction", "right")).strip_edges().to_lower(),
        "launch_to_space": bool(zone.get("launch_to_space", false)),
        "enabled": bool(zone.get("enabled", true)),
        "locked": bool(zone.get("locked", false)),
        "required_item_id": str(zone.get("required_item_id", "")).strip_edges(),
        "required_item_count": maxi(1, int(zone.get("required_item_count", 1))),
        "required_var_name": str(zone.get("required_var_name", "")).strip_edges(),
        "required_var_value": zone.get("required_var_value", 1),
        "required_global_tag": str(zone.get("required_global_tag", "")).strip_edges(),
        "blocked_event_name": str(zone.get("blocked_event_name", "")).strip_edges(),
        "success_event_name": str(zone.get("success_event_name", "")).strip_edges(),
        "arrive_event_name": str(zone.get("arrive_event_name", "")).strip_edges(),
        "x_blocks": float(zone.get("x_blocks", zone.get("x", 0.0))),
        "y_blocks": float(zone.get("y_blocks", zone.get("y", 0.0))),
        "width_blocks": maxf(1.0, float(zone.get("width_blocks", zone.get("w", 1.0)))),
        "height_blocks": maxf(1.0, float(zone.get("height_blocks", zone.get("h", 1.0)))),
        "zone": zone.duplicate(true),
        "tags": tags,
        "destinations": [],
    }


func _parse_legacy_door(door: Dictionary) -> Dictionary:
    var tags: Array = []
    var tags_v: Variant = door.get("tags", [])
    if typeof(tags_v) == TYPE_ARRAY:
        for tag_v in tags_v:
            tags.append(str(tag_v))
    var destinations: Array = []
    var dests_v: Variant = door.get("destinations", [])
    if typeof(dests_v) == TYPE_ARRAY:
        destinations = (dests_v as Array).duplicate(true)
    return {
        "id": str(door.get("door_id", door.get("id", ""))).strip_edges(),
        "target_door_id": str(door.get("target_door_id", "")).strip_edges(),
        "target": str(door.get("target_room", door.get("target", ""))).strip_edges(),
        "direction": str(door.get("direction", "right")).strip_edges().to_lower(),
        "launch_to_space": bool(door.get("launch_to_space", false)),
        "enabled": bool(door.get("enabled", true)),
        "locked": bool(door.get("locked", false)),
        "required_item_id": str(door.get("required_item_id", "")).strip_edges(),
        "required_item_count": maxi(1, int(door.get("required_item_count", 1))),
        "required_var_name": str(door.get("required_var_name", "")).strip_edges(),
        "required_var_value": door.get("required_var_value", 1),
        "required_global_tag": str(door.get("required_global_tag", "")).strip_edges(),
        "blocked_event_name": str(door.get("blocked_event_name", "")).strip_edges(),
        "success_event_name": str(door.get("success_event_name", "")).strip_edges(),
        "arrive_event_name": str(door.get("arrive_event_name", "")).strip_edges(),
        "cap_block_x": int(door.get("cap_x", 0)),
        "cap_block_y": int(door.get("cap_y", 0)),
        "dest_pixel_x": int(door.get("dest_x", 0)),
        "dest_pixel_y": int(door.get("dest_y", 0)),
        "x_blocks": float(int(door.get("cap_x", 0))),
        "y_blocks": float(int(door.get("cap_y", 0))),
        "width_blocks": maxf(1.0, float(door.get("width_blocks", 1.0))),
        "height_blocks": maxf(1.0, float(door.get("height_blocks", 1.0))),
        "tags": tags,
        "destinations": destinations,
    }


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


func _parse_background_image(r: Dictionary) -> Dictionary:
    var defaults := {
        "image": "",
        "x_blocks": 0.0,
        "y_blocks": 0.0,
        "width_blocks": float(maxi(1, int(r.get("width_blocks", 1)))),
        "height_blocks": float(maxi(1, int(r.get("height_blocks", 1)))),
        "scroll_speed_x": 1.0,
        "scroll_speed_y": 1.0,
        "shader_preset": "none",
        "shader_tint": Color.WHITE,
        "shader_strength": 0.6,
        "shader_speed": 1.0,
    }
    var raw_v: Variant = r.get("background_image", {})
    if typeof(raw_v) != TYPE_DICTIONARY:
        return defaults
    var raw: Dictionary = raw_v
    defaults["image"] = str(raw.get("image", raw.get("path", defaults["image"]))).strip_edges()
    defaults["x_blocks"] = float(raw.get("x_blocks", raw.get("x", defaults["x_blocks"])))
    defaults["y_blocks"] = float(raw.get("y_blocks", raw.get("y", defaults["y_blocks"])))
    defaults["width_blocks"] = maxf(0.0, float(raw.get("width_blocks", raw.get("w", defaults["width_blocks"]))))
    defaults["height_blocks"] = maxf(0.0, float(raw.get("height_blocks", raw.get("h", defaults["height_blocks"]))))
    defaults["scroll_speed_x"] = clampf(float(raw.get("scroll_speed_x", defaults["scroll_speed_x"])), 0.0, 2.0)
    defaults["scroll_speed_y"] = clampf(float(raw.get("scroll_speed_y", defaults["scroll_speed_y"])), 0.0, 2.0)
    var shader_preset := str(raw.get("shader_preset", defaults["shader_preset"])).strip_edges().to_lower()
    if shader_preset != "flicker" and shader_preset != "wave" and shader_preset != "heat":
        shader_preset = "none"
    defaults["shader_preset"] = shader_preset
    defaults["shader_tint"] = Color.from_string(str(raw.get("shader_tint", "ffffff")), Color.WHITE)
    defaults["shader_strength"] = clampf(float(raw.get("shader_strength", defaults["shader_strength"])), 0.0, 2.0)
    defaults["shader_speed"] = clampf(float(raw.get("shader_speed", defaults["shader_speed"])), 0.0, 4.0)
    return defaults


func _parse_background_images(r: Dictionary) -> Array:
    var out: Array = []
    var raw_v: Variant = r.get("background_images", [])
    if typeof(raw_v) == TYPE_ARRAY:
        var raw_arr: Array = raw_v
        for i in raw_arr.size():
            var entry_v: Variant = raw_arr[i]
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = _parse_background_image({
                "width_blocks": r.get("width_blocks", 1),
                "height_blocks": r.get("height_blocks", 1),
                "background_image": entry_v,
            })
            entry["id"] = str((entry_v as Dictionary).get("id", "bg_%d" % (i + 1))).strip_edges()
            entry["anim_frames"] = maxi(1, int((entry_v as Dictionary).get("anim_frames", (entry_v as Dictionary).get("frames", 1))))
            entry["anim_fps"] = maxf(0.0, float((entry_v as Dictionary).get("anim_fps", (entry_v as Dictionary).get("fps", 0.0))))
            entry["anim_loop"] = bool((entry_v as Dictionary).get("anim_loop", (entry_v as Dictionary).get("loop", true)))
            out.append(entry)
    if out.is_empty():
        var legacy := _parse_background_image(r)
        if not str(legacy.get("image", "")).is_empty():
            legacy["id"] = "bg_1"
            legacy["anim_frames"] = 1
            legacy["anim_fps"] = 0.0
            legacy["anim_loop"] = true
            out.append(legacy)
    return out


func _parse_shader_regions(r: Dictionary) -> Array:
    var out: Array = []
    var raw_v: Variant = r.get("shader_regions", [])
    if typeof(raw_v) != TYPE_ARRAY:
        return out
    var raw_arr: Array = raw_v
    for i in raw_arr.size():
        var entry_v: Variant = raw_arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var raw: Dictionary = entry_v
        var preset := str(raw.get("shader_preset", "flicker")).strip_edges().to_lower()
        if preset != "flicker" and preset != "wave" and preset != "heat":
            preset = "flicker"
        out.append({
            "id": str(raw.get("id", "shader_%d" % (i + 1))).strip_edges(),
            "x_blocks": float(raw.get("x_blocks", raw.get("x", 0.0))),
            "y_blocks": float(raw.get("y_blocks", raw.get("y", 0.0))),
            "width_blocks": maxf(0.0, float(raw.get("width_blocks", raw.get("w", 0.0)))),
            "height_blocks": maxf(0.0, float(raw.get("height_blocks", raw.get("h", 0.0)))),
            "shader_preset": preset,
            "shader_tint": Color.from_string(str(raw.get("shader_tint", "ffffff")), Color.WHITE),
            "shader_strength": clampf(float(raw.get("shader_strength", 0.6)), 0.0, 2.0),
            "shader_speed": clampf(float(raw.get("shader_speed", 1.0)), 0.0, 4.0),
        })
    return out


func _parse_weather(r: Dictionary) -> Dictionary:
    var out := {
        "preset": "none",
        "color": Color(0.81, 0.91, 1.0, 1.0),
        "intensity": 0.7,
        "speed": 1.0,
    }
    var raw_v: Variant = r.get("weather", {})
    if typeof(raw_v) != TYPE_DICTIONARY:
        return out
    var raw: Dictionary = raw_v
    var preset := str(raw.get("preset", "none")).strip_edges().to_lower()
    if preset != "rain" and preset != "snow":
        preset = "none"
    out["preset"] = preset
    out["color"] = Color.from_string(str(raw.get("color", "cfe8ffff")), Color(0.81, 0.91, 1.0, 1.0))
    out["intensity"] = clampf(float(raw.get("intensity", 0.7)), 0.0, 2.0)
    out["speed"] = clampf(float(raw.get("speed", 1.0)), 0.0, 4.0)
    return out


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

static func _normalized_scroll_for_role(_role: String, _sx: float, _sy: float) -> Vector2:
    return Vector2.ONE


static func _normalize_layer_role(raw_role: String, layer_name: String = "") -> String:
    var role := raw_role.strip_edges().to_lower()
    if role == ROLE_BG or role == ROLE_MAIN or role == ROLE_FG:
        return role
    var normalized_name := layer_name.strip_edges().to_lower()
    if normalized_name.contains("foreground") or normalized_name == "fg":
        return ROLE_FG
    if normalized_name.contains("background") or normalized_name == "bg":
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


# Variant resolution: takes a fully-qualified canonical addr like
# "forest/town_square" and returns either the same addr (no variant fired)
# or the qualified addr of an alternate (e.g. "forest/town_square_burned").
#
# Walks Regions/<region_id>/room_variants.json's rule list for the canonical
# bare room id, evaluates each rule's `when` clause against the live
# PlanetaryInterface flag state, and returns the first matching `use`.
# Empty or missing variants file -> canonical unchanged.
#
# Resolution is recomputed on every load_room call so updated flag state
# is honored on each room entry. Slice 3 adds live re-resolve while the
# player is already inside the room.
func resolve_room_variant(canonical_addr: String) -> String:
    var parsed: Dictionary = RegIO.parse_room_addr(canonical_addr)
    var region_id: String = str(parsed.get("region_id", "")).strip_edges()
    var bare_room: String = str(parsed.get("room_addr", "")).strip_edges()
    if region_id.is_empty() or bare_room.is_empty():
        return canonical_addr
    if _pack == null:
        return canonical_addr

    var variants_path: String = _pack.room_variants_path(region_id)
    if not FileAccess.file_exists(variants_path):
        return canonical_addr
    var file := FileAccess.open(variants_path, FileAccess.READ)
    if file == null:
        return canonical_addr
    var parsed_v: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed_v) != TYPE_DICTIONARY:
        return canonical_addr

    var root: Dictionary = parsed_v
    var variants_v: Variant = root.get("variants", {})
    if typeof(variants_v) != TYPE_DICTIONARY:
        return canonical_addr
    var rules_v: Variant = (variants_v as Dictionary).get(bare_room, [])
    if typeof(rules_v) != TYPE_ARRAY:
        return canonical_addr

    for rule_v in (rules_v as Array):
        if typeof(rule_v) != TYPE_DICTIONARY:
            continue
        var rule: Dictionary = rule_v
        if not _variant_when_matches(rule.get("when", null)):
            continue
        var use_room: String = str(rule.get("use", "")).strip_edges()
        if use_room.is_empty():
            continue
        return RegIO.runtime_room_addr(region_id, use_room)

    return canonical_addr


# Evaluates a single variant `when` clause against PlanetaryInterface
# flag state. Returns true iff the named flag (scope-qualified) currently
# equals the authored `equals` value. `equals: null` matches an unset flag.
# Bad/missing PlanetaryInterface returns false so the canonical wins.
func _variant_when_matches(when_v: Variant) -> bool:
    if typeof(when_v) != TYPE_DICTIONARY:
        return false
    var when_dict: Dictionary = when_v
    var scope: String = str(when_dict.get("scope", "")).strip_edges().to_lower()
    var flag_name: String = str(when_dict.get("flag", "")).strip_edges()
    if flag_name.is_empty():
        return false
    if not when_dict.has("equals"):
        return false
    var pi: Node = get_node_or_null("/root/PlanetaryInterface")
    if pi == null:
        return false
    var actual: Variant = null
    if scope == "planet":
        actual = pi.call("get_planet_flag", flag_name, null)
    elif scope == "global":
        actual = pi.call("get_global_flag", flag_name, null)
    else:
        return false
    var expected: Variant = when_dict.get("equals", null)
    if expected == null:
        return actual == null
    if actual == null:
        return false
    return typeof(actual) == typeof(expected) and actual == expected


func load_room(addr: String) -> void:
    if not _rooms.has(addr):
        push_error("MvRoomManager: unknown room '%s'" % addr)
        return

    _reset_active_crumbles(true)

    # Variant resolution: if room_variants.json gates this canonical addr
    # behind a planet/global flag and the flag matches, load the alternate
    # room data instead. Falls back to canonical when no variants fire or
    # when the resolved alternate is missing from _rooms.
    var resolved_addr: String = resolve_room_variant(addr)
    if not _rooms.has(resolved_addr):
        push_warning("MvRoomManager: variant resolved '%s' -> '%s' which is missing — using canonical" % [addr, resolved_addr])
        resolved_addr = addr
    var info: Dictionary = _rooms[resolved_addr]

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
    _loaded_room_addr = resolved_addr
    _build_collision(info)
    _spawn_entities(info)
    MvTriggerEngine.set_room_triggers(info.get("raw_triggers", []))
    MvMapScreen.mark_visited(addr)

    var variant_suffix: String = "" if resolved_addr == addr else " [variant '%s']" % resolved_addr
    print("[MvRoomManager] entered '%s' (%s)%s %dx%dpx, blocks %dx%d, tileset %d, tile_layers %d, slopes %d, doors %d, entities %d" % [
        info["name"], addr, variant_suffix, info["width_px"], info["height_px"],
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


# ── In-game tile editing (slice 2) ────────────────────────────────────────
# Public API for the in-game edit mode. Mutates the live room's main-role tile
# layer + collision array, re-renders the affected cell, and (optionally)
# rebuilds the room's colliders. Cells index [row = y][col = x]; pixel<->cell
# uses BLOCK_SIZE, matching block_type_at_world_pos.

func world_to_cell(world_pos: Vector2) -> Vector2i:
    return Vector2i(int(world_pos.x / BLOCK_SIZE), int(world_pos.y / BLOCK_SIZE))


func cell_in_bounds(cell: Vector2i) -> bool:
    var info := current_room()
    if info.is_empty():
        return false
    return cell.x >= 0 and cell.y >= 0 \
        and cell.x < int(info.get("width_blocks", 0)) \
        and cell.y < int(info.get("height_blocks", 0))


# Paint `metatile_idx` (from the room's primary tileset) onto the main layer at
# `cell`. `solid` marks BT_SOLID (player can stand on it) vs BT_AIR (deco).
# When `rebuild_collision` is false the collider rebuild is skipped so a paint
# stroke can defer the (whole-room) rebuild to mouse-release.
func paint_cell(cell: Vector2i, metatile_idx: int, solid: bool, rebuild_collision: bool = true) -> bool:
    var info := current_room()
    if info.is_empty() or not cell_in_bounds(cell):
        return false
    var data_idx := _main_layer_data_index(info)
    if data_idx < 0:
        return false
    var packed := MvTileValue.pack(metatile_idx, false, false, int(info.get("tileset", 0)))
    if not _set_layer_tile_value(info, data_idx, cell, packed):
        return false
    var node := _tile_node_for_data_index(data_idx)
    if node != null:
        MvRoomRenderer.update_cell(node, cell.x, cell.y, packed)
    _set_collision_cell(info, cell, BT_SOLID if solid else BT_AIR)
    _set_bts_value(info, cell.y, cell.x, 0)
    if rebuild_collision:
        _build_collision(info)
    return true


# Clear the main-layer tile at `cell` and mark it BT_AIR (non-colliding).
func erase_cell(cell: Vector2i, rebuild_collision: bool = true) -> bool:
    var info := current_room()
    if info.is_empty() or not cell_in_bounds(cell):
        return false
    var data_idx := _main_layer_data_index(info)
    if data_idx < 0:
        return false
    if not _set_layer_tile_value(info, data_idx, cell, 0):
        return false
    var node := _tile_node_for_data_index(data_idx)
    if node != null:
        MvRoomRenderer.update_cell(node, cell.x, cell.y, 0)
    _set_collision_cell(info, cell, BT_AIR)
    _set_bts_value(info, cell.y, cell.x, 0)
    if rebuild_collision:
        _build_collision(info)
    return true


func _main_layer_data_index(info: Dictionary) -> int:
    var layers: Array = info.get("tile_layers", [])
    for i in layers.size():
        if str((layers[i] as Dictionary).get("role", ROLE_MAIN)) == ROLE_MAIN:
            return i
    return 0 if not layers.is_empty() else -1


func _tile_node_for_data_index(data_idx: int) -> TileMapLayer:
    # load_room names nodes "TileLayer_%02d_<name>" where %02d is the data idx.
    var prefix := "TileLayer_%02d_" % data_idx
    for entry in _tile_layers:
        var node: TileMapLayer = entry.get("node")
        if node != null and str(node.name).begins_with(prefix):
            return node
    return null


func _set_layer_tile_value(info: Dictionary, data_idx: int, cell: Vector2i, packed: int) -> bool:
    var layers: Array = info.get("tile_layers", [])
    if data_idx < 0 or data_idx >= layers.size():
        return false
    var tiles: Array = (layers[data_idx] as Dictionary).get("tiles", [])
    if cell.y < 0 or cell.y >= tiles.size():
        return false
    var row_arr: Array = tiles[cell.y]
    if cell.x < 0 or cell.x >= row_arr.size():
        return false
    row_arr[cell.x] = packed
    return true


func _set_collision_cell(info: Dictionary, cell: Vector2i, bt: int) -> void:
    var coll: Array = info.get("collision", [])
    if cell.y >= 0 and cell.y < coll.size():
        var row_arr: Array = coll[cell.y]
        if cell.x >= 0 and cell.x < row_arr.size():
            row_arr[cell.x] = bt


# ── In-game entity placement (slice 3) ─────────────────────────────────────
# Sorted list of entity type ids the active pack defines (the edit-mode picker
# cycles these).
func entity_type_ids() -> Array:
    var pack := MvPackLoader.current_pack
    if pack == null:
        return []
    var ids: Array = _load_entity_defs(pack.pack_id).keys()
    ids.sort()
    return ids


# Place an entity for editing: spawn the live node AND record it in the room's
# entities[] so it survives a save + respawns on reload. Returns the instance id
# (empty on failure).
func place_entity(type_id: String, world_pos: Vector2) -> String:
    var info := current_room()
    if info.is_empty() or type_id.strip_edges().is_empty():
        return ""
    var uid := "%s_ed_%d" % [type_id, Time.get_ticks_msec()]
    var node := spawn_entity_dynamic(type_id, world_pos, [], {"instance_id": uid})
    if node == null:
        return ""
    var entities: Array = info.get("entities", [])
    entities.append({
        "type": type_id,
        "position": world_pos,
        "instance_id": uid,
        "tags": [],
        "properties": {"instance_id": uid},
    })
    info["entities"] = entities
    return uid


# Delete the live entity nearest world_pos (within `radius` px) and drop its
# entities[] record (matched by instance_id). Returns true if one was removed.
func remove_entity_near(world_pos: Vector2, radius: float = 12.0) -> Dictionary:
    if _entities_container == null:
        return {}
    var best: Node2D = null
    var best_d := radius
    for child in _entities_container.get_children():
        var n := child as Node2D
        if n == null:
            continue
        var d := n.global_position.distance_to(world_pos)
        if d <= best_d:
            best_d = d
            best = n
    if best == null:
        return {}
    var uid_v: Variant = best.get("instance_id")
    var uid := str(uid_v) if uid_v != null else ""
    var removed: Dictionary = {}
    var info := current_room()
    if not info.is_empty() and not uid.is_empty():
        var entities: Array = info.get("entities", [])
        for i in range(entities.size() - 1, -1, -1):
            if str((entities[i] as Dictionary).get("instance_id", "")) == uid:
                removed = (entities[i] as Dictionary).duplicate(true)
                entities.remove_at(i)
                break
        info["entities"] = entities
    best.queue_free()
    return removed


# Re-place an entity from a saved record (edit-mode undo of a delete): spawns the
# live node reusing the record's instance_id/pos/tags/props and restores the
# entities[] record verbatim.
func place_entity_record(record: Dictionary) -> bool:
    var info := current_room()
    if info.is_empty():
        return false
    var type_id := str(record.get("type", "")).strip_edges()
    if type_id.is_empty():
        return false
    var pos_v: Variant = record.get("position", Vector2.ZERO)
    var pos: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
    var tags_v: Variant = record.get("tags", [])
    var tags: Array = tags_v if typeof(tags_v) == TYPE_ARRAY else []
    var props_v: Variant = record.get("properties", {})
    var props: Dictionary = (props_v as Dictionary).duplicate(true) if typeof(props_v) == TYPE_DICTIONARY else {}
    var uid := str(record.get("instance_id", "")).strip_edges()
    if not uid.is_empty() and not props.has("instance_id"):
        props["instance_id"] = uid
    if spawn_entity_dynamic(type_id, pos, tags, props) == null:
        return false
    var entities: Array = info.get("entities", [])
    entities.append(record.duplicate(true))
    info["entities"] = entities
    return true


# Remove a placed entity by its instance id (used by edit-mode undo of a place).
func remove_entity_by_id(uid: String) -> bool:
    if _entities_container == null or uid.strip_edges().is_empty():
        return false
    var removed := false
    for child in _entities_container.get_children():
        var v: Variant = child.get("instance_id")
        if v != null and str(v) == uid:
            child.queue_free()
            removed = true
            break
    if not removed:
        return false
    var info := current_room()
    if not info.is_empty():
        var entities: Array = info.get("entities", [])
        for i in range(entities.size() - 1, -1, -1):
            if str((entities[i] as Dictionary).get("instance_id", "")) == uid:
                entities.remove_at(i)
                break
        info["entities"] = entities
    return true


# Read a cell's full main-layer state (packed tile + collision + bts) so the
# edit-mode undo stack can restore it later.
func cell_state(cell: Vector2i) -> Dictionary:
    var info := current_room()
    if info.is_empty():
        return {"packed": 0, "collision": BT_AIR, "bts": 0}
    var packed := 0
    var data_idx := _main_layer_data_index(info)
    if data_idx >= 0:
        var tiles: Array = (info.get("tile_layers", [])[data_idx] as Dictionary).get("tiles", [])
        if cell.y >= 0 and cell.y < tiles.size():
            var row_arr: Array = tiles[cell.y]
            if cell.x >= 0 and cell.x < row_arr.size():
                packed = int(row_arr[cell.x])
    var coll := BT_AIR
    var coll_arr: Array = info.get("collision", [])
    if cell.y >= 0 and cell.y < coll_arr.size():
        var crow: Array = coll_arr[cell.y]
        if cell.x >= 0 and cell.x < crow.size():
            coll = int(crow[cell.x])
    return {"packed": packed, "collision": coll, "bts": _get_bts_value(info, cell.y, cell.x)}


# Set a cell's tile + collision + bts to explicit values (undo restore path).
func set_cell_full(cell: Vector2i, packed: int, collision_bt: int, bts_val: int, rebuild_collision: bool = true) -> bool:
    var info := current_room()
    if info.is_empty() or not cell_in_bounds(cell):
        return false
    var data_idx := _main_layer_data_index(info)
    if data_idx < 0:
        return false
    if not _set_layer_tile_value(info, data_idx, cell, packed):
        return false
    var node := _tile_node_for_data_index(data_idx)
    if node != null:
        MvRoomRenderer.update_cell(node, cell.x, cell.y, packed)
    _set_collision_cell(info, cell, collision_bt)
    _set_bts_value(info, cell.y, cell.x, bts_val)
    if rebuild_collision:
        _build_collision(info)
    return true


# The room's primary tileset atlas for the edit-mode palette: the texture plus
# its column/row count and tile size (empty if the room has no atlas source).
func current_tileset_atlas() -> Dictionary:
    var info := current_room()
    if info.is_empty():
        return {}
    var ts := _tileset_mgr.get_tile_set(int(info.get("tileset", 0)))
    if ts == null or ts.get_source_count() == 0:
        return {}
    var want := int(info.get("tileset", 0))
    var src: TileSetAtlasSource = null
    for i in ts.get_source_count():
        var sid := ts.get_source_id(i)
        var s := ts.get_source(sid)
        if s is TileSetAtlasSource and (s as TileSetAtlasSource).texture != null:
            if sid == want:
                src = s as TileSetAtlasSource
                break
            if src == null:
                src = s as TileSetAtlasSource
    if src == null or src.texture == null:
        return {}
    var tsz: int = src.texture_region_size.x
    if tsz < 1:
        tsz = BLOCK_SIZE
    @warning_ignore("integer_division")
    var cols := maxi(1, src.texture.get_width() / tsz)
    @warning_ignore("integer_division")
    var rows := maxi(1, src.texture.get_height() / tsz)
    return {"texture": src.texture, "cols": cols, "rows": rows, "tile_size": tsz}


func block_type_at_world_pos(world_pos: Vector2) -> int:
    var info: Dictionary = current_room()
    if info.is_empty() or info["collision"].size() == 0:
        return BT_AIR

    var col := int(world_pos.x / BLOCK_SIZE)
    var row := int(world_pos.y / BLOCK_SIZE)
    if row < 0 or row >= info["collision"].size():
        return BT_AIR
    if col < 0 or col >= info["collision"][row].size():
        return BT_AIR
    return int(info["collision"][row][col])


func is_solid_at_world_pos(world_pos: Vector2) -> bool:
    var block := block_type_at_world_pos(world_pos)
    if block == BT_SLOPE:
        var slope_hit := try_get_slope_floor(world_pos.x, world_pos.y)
        return bool(slope_hit.get("hit", false))
    return _is_rect_mergeable(block)


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
        _apply_room_entity_overrides(node, entity_props)
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
    _apply_room_entity_overrides(node, entity_props)
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
    if typeof(entities_v) == TYPE_ARRAY:
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
    var zones_v: Variant = info.get("zones", [])
    if typeof(zones_v) == TYPE_ARRAY:
        for zone_v in zones_v:
            if typeof(zone_v) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zone_v
            if str(zone.get("id", "")).strip_edges() == trimmed:
                return _room_zone_center(zone)
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


func _room_zone_center(zone: Dictionary) -> Vector2:
    var x_blocks: float = float(zone.get("x_blocks", 0.0))
    var y_blocks: float = float(zone.get("y_blocks", 0.0))
    var width_blocks: float = maxf(1.0, float(zone.get("width_blocks", 1.0)))
    var height_blocks: float = maxf(1.0, float(zone.get("height_blocks", 1.0)))
    return Vector2(
        (x_blocks + width_blocks * 0.5) * float(BLOCK_SIZE),
        (y_blocks + height_blocks * 0.5) * float(BLOCK_SIZE)
    )


func _apply_room_entity_overrides(node: Node, entity_props: Dictionary) -> void:
    if node == null or entity_props.is_empty():
        return
    var behavior_override := str(entity_props.get("behavior", "")).strip_edges()
    if behavior_override.is_empty():
        return
    node.set_meta("behavior_override", behavior_override)
    if "behavior_id" in node:
        node.set("behavior_id", behavior_override)
        return
    if "behavior" in node:
        node.set("behavior", behavior_override)
        return
    if node.has_method("set_behavior_override"):
        node.call("set_behavior_override", behavior_override)


func _fallback_entity_instance_id(type_id: String, pos: Vector2) -> String:
    var col := maxi(0, floori(pos.x / float(BLOCK_SIZE)))
    var row := maxi(0, floori(pos.y / float(BLOCK_SIZE)))
    if type_id == "trigger_volume":
        return "zone_%d_%d" % [col, row]
    return "%s_%d_%d" % [type_id, col, row]


static func _load_entity_defs(pack_id: String) -> Dictionary:
    const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")
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

    # Build a smooth ramp from the first and last solid columns instead of a
    # 16-step staircase. CharacterBody2D resolves continuous faces much more
    # reliably than dense micro-steps on slopes.
    var first_x: int = -1
    var last_x: int = -1
    var first_y: float = 0.0
    var last_y: float = 0.0
    for x in shape.size():
        var src_x: int = (shape.size() - 1 - x) if sc["hflip"] else x
        var surface_y: int = shape[src_x]
        if sc["vflip"]:
            if surface_y >= 16:
                continue
            surface_y = 16 - surface_y
        elif surface_y >= 16:
            continue
        if first_x < 0:
            first_x = x
            first_y = float(surface_y)
        last_x = x
        last_y = float(surface_y)
    if first_x < 0 or last_x < 0:
        return null

    var left_x := float(first_x)
    var right_x := float(last_x + 1)
    if right_x <= left_x:
        right_x = left_x + 1.0
    if left_x <= 0.0:
        left_x = 0.0
    if right_x >= float(BLOCK_SIZE):
        right_x = float(BLOCK_SIZE)

    var points: PackedVector2Array = PackedVector2Array()
    points.append(Vector2(left_x, first_y))
    points.append(Vector2(right_x, last_y))
    if sc["vflip"]:
        points.append(Vector2(right_x, 0))
        points.append(Vector2(left_x, 0))
    else:
        points.append(Vector2(right_x, BLOCK_SIZE))
        points.append(Vector2(left_x, BLOCK_SIZE))

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


func find_door_by_id(door_id: String, room_addr: String = "") -> Dictionary:
    var trimmed := door_id.strip_edges()
    if trimmed.is_empty():
        return {}
    var room := current_room() if room_addr.strip_edges().is_empty() else get_room(room_addr)
    if room.is_empty():
        return {}
    var doors_v: Variant = room.get("doors", [])
    if typeof(doors_v) != TYPE_ARRAY:
        return {}
    for door_v in doors_v:
        if typeof(door_v) != TYPE_DICTIONARY:
            continue
        var door: Dictionary = door_v
        if str(door.get("id", "")).strip_edges() == trimmed:
            return door
    return {}


func find_door_link(door_id: String) -> Dictionary:
    var trimmed := door_id.strip_edges()
    if trimmed.is_empty():
        return {}
    for room_addr_v in _rooms.keys():
        var room_addr := str(room_addr_v)
        var room: Dictionary = _rooms.get(room_addr, {})
        if room.is_empty():
            continue
        var door := find_door_by_id(trimmed, room_addr)
        if door.is_empty():
            continue
        return {
            "room_addr": room_addr,
            "room": room,
            "door": door,
        }
    return {}


func door_spawn_position(door: Dictionary, room: Dictionary = {}) -> Vector2:
    if door.is_empty():
        return Vector2(-1, -1)
    var target_room: Dictionary = room if not room.is_empty() else current_room()
    if target_room.is_empty():
        return Vector2(-1, -1)
    var rect := _door_local_rect(door)
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return Vector2(-1, -1)
    var width_px := maxi(BLOCK_SIZE, int(target_room.get("width_blocks", 1)) * BLOCK_SIZE)
    var height_px := maxi(BLOCK_SIZE, int(target_room.get("height_blocks", 1)) * BLOCK_SIZE)
    var left_px := int(round(rect.position.x))
    var top_px := int(round(rect.position.y))
    var right_px := int(round(rect.end.x))
    var bottom_px := int(round(rect.end.y))
    var center_x := int(round(rect.position.x + rect.size.x * 0.5))
    var center_y := int(round(rect.position.y + rect.size.y * 0.5))
    var spawn_x := center_x
    var spawn_y := center_y
    match str(door.get("direction", "right")).strip_edges():
        "left":
            spawn_x = right_px + 8
        "right":
            spawn_x = left_px - 8
        "up":
            spawn_y = bottom_px + 8
        "down":
            spawn_y = top_px - 8
    spawn_x = clampi(spawn_x, 24, maxi(24, width_px - 24))
    spawn_y = clampi(spawn_y, 24, maxi(24, height_px - 24))
    return Vector2(spawn_x, spawn_y)


func _door_world_rect(door: Dictionary) -> Rect2:
    var local_rect := _door_local_rect(door)
    if local_rect.size.x <= 0.0 or local_rect.size.y <= 0.0:
        return Rect2()
    return Rect2(to_global(local_rect.position), local_rect.size)


func _door_local_rect(door: Dictionary) -> Rect2:
    var width_blocks := maxf(1.0, float(door.get("width_blocks", 1.0)))
    var height_blocks := maxf(1.0, float(door.get("height_blocks", 1.0)))
    if door.has("x_blocks") and door.has("y_blocks"):
        return Rect2(
            Vector2(float(door.get("x_blocks", 0.0)) * BLOCK_SIZE, float(door.get("y_blocks", 0.0)) * BLOCK_SIZE),
            Vector2(width_blocks * BLOCK_SIZE, height_blocks * BLOCK_SIZE)
        )
    var block_x := int(door.get("cap_block_x", -1))
    var block_y := int(door.get("cap_block_y", -1))
    if block_x < 0 or block_y < 0:
        return Rect2()
    return Rect2(
        Vector2(float(block_x * BLOCK_SIZE), float(block_y * BLOCK_SIZE)),
        Vector2(width_blocks * BLOCK_SIZE, height_blocks * BLOCK_SIZE)
    )


func get_room(addr: String) -> Dictionary:
    return _rooms.get(addr, {})


func _clear_backdrop() -> void:
    _backdrop_layers.clear()
    if _weather_overlay != null and _weather_overlay.has_method("clear_weather"):
        _weather_overlay.call("clear_weather")
    if _backdrop_root == null:
        return
    for child in _backdrop_root.get_children():
        child.queue_free()
    if _shader_fx_root != null:
        for child in _shader_fx_root.get_children():
            child.queue_free()


func _apply_backdrop(info: Dictionary) -> void:
    if _backdrop_root == null:
        return
    if bool(info.get("parallax_enabled", true)):
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
    var bg_arr_v: Variant = info.get("background_images", [])
    if typeof(bg_arr_v) == TYPE_ARRAY and not (bg_arr_v as Array).is_empty():
        for bg_v in bg_arr_v:
            if typeof(bg_v) != TYPE_DICTIONARY:
                continue
            _apply_placed_background_image(bg_v)
    else:
        var bg_v: Variant = info.get("background_image", {})
        if typeof(bg_v) == TYPE_DICTIONARY:
            _apply_placed_background_image(bg_v)
    var shader_regions_v: Variant = info.get("shader_regions", [])
    if typeof(shader_regions_v) == TYPE_ARRAY:
        for region_v in shader_regions_v:
            if typeof(region_v) != TYPE_DICTIONARY:
                continue
            _apply_shader_region(region_v)
    _apply_weather(info.get("weather", {}))


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


func _apply_placed_background_image(bg: Dictionary) -> void:
    var rel_path := str(bg.get("image", "")).strip_edges()
    if rel_path.is_empty() or _backdrop_root == null:
        return
    var tex_path := _resolve_pack_asset_path(rel_path)
    var tex := _load_backdrop_texture(tex_path)
    if not (tex is Texture2D):
        push_warning("MvRoomManager: failed to load placed background '%s'" % tex_path)
        return
    var spr := Sprite2D.new()
    spr.name = "PlacedBackground_%s" % str(bg.get("id", "bg"))
    spr.centered = false
    spr.texture = tex as Texture2D
    spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var shader_mat: Variant = _make_background_shader_material(bg)
    if shader_mat != null:
        spr.material = shader_mat
    var anim_frames := maxi(1, int(bg.get("anim_frames", 1)))
    spr.hframes = anim_frames
    spr.frame = 0
    _backdrop_root.add_child(spr)
    var tex_size_full: Vector2 = (spr.texture as Texture2D).get_size()
    var tex_size := Vector2(tex_size_full.x / float(anim_frames), tex_size_full.y)
    var size_px := Vector2(
        maxf(1.0, float(bg.get("width_blocks", 0.0)) * BLOCK_SIZE),
        maxf(1.0, float(bg.get("height_blocks", 0.0)) * BLOCK_SIZE))
    var base_position := Vector2(
        float(bg.get("x_blocks", 0.0)) * BLOCK_SIZE,
        float(bg.get("y_blocks", 0.0)) * BLOCK_SIZE)
    _backdrop_layers.append({
        "node": spr,
        "type": "placed",
        "texture_size": tex_size,
        "target_size": size_px,
        "base_position": base_position,
        "scroll_speed": Vector2(
            float(bg.get("scroll_speed_x", 1.0)),
            float(bg.get("scroll_speed_y", 1.0))),
        "anim_frames": anim_frames,
        "anim_fps": maxf(0.0, float(bg.get("anim_fps", 0.0))),
        "anim_loop": bool(bg.get("anim_loop", true)),
        "anim_time": 0.0,
    })
    var cam := get_viewport().get_camera_2d()
    if cam != null:
        _update_backdrop_layer_transform(_backdrop_layers[_backdrop_layers.size() - 1], cam, cam.get_screen_center_position())


func _make_background_shader_material(bg: Dictionary) -> Variant:
    var preset := str(bg.get("shader_preset", "none")).strip_edges().to_lower()
    if preset == "none":
        return null
    if _backdrop_shader == null:
        _backdrop_shader = Shader.new()
        _backdrop_shader.code = _BG_SHADER_CODE
    var mode := 0
    match preset:
        "flicker":
            mode = 1
        "wave":
            mode = 2
        "heat":
            mode = 3
    if mode == 0:
        return null
    var bg_material := ShaderMaterial.new()
    bg_material.shader = _backdrop_shader
    bg_material.set_shader_parameter("effect_mode", mode)
    bg_material.set_shader_parameter("tint", bg.get("shader_tint", Color.WHITE))
    bg_material.set_shader_parameter("strength", clampf(float(bg.get("shader_strength", 0.6)), 0.0, 2.0))
    bg_material.set_shader_parameter("speed", clampf(float(bg.get("shader_speed", 1.0)), 0.0, 4.0))
    return bg_material


func _apply_shader_region(region: Dictionary) -> void:
    if _shader_fx_root == null:
        return
    var size_px := Vector2(
        maxf(1.0, float(region.get("width_blocks", 0.0)) * BLOCK_SIZE),
        maxf(1.0, float(region.get("height_blocks", 0.0)) * BLOCK_SIZE))
    if size_px.x <= 0.0 or size_px.y <= 0.0:
        return
    var poly := Polygon2D.new()
    poly.name = "ShaderRegion_%s" % str(region.get("id", "shader"))
    poly.polygon = PackedVector2Array([
        Vector2.ZERO,
        Vector2(size_px.x, 0.0),
        Vector2(size_px.x, size_px.y),
        Vector2(0.0, size_px.y),
    ])
    poly.color = Color.WHITE
    poly.position = Vector2(
        float(region.get("x_blocks", 0.0)) * BLOCK_SIZE,
        float(region.get("y_blocks", 0.0)) * BLOCK_SIZE)
    var region_material: Variant = _make_room_fx_material(region)
    if region_material != null:
        poly.material = region_material
    _shader_fx_root.add_child(poly)


func _make_room_fx_material(region: Dictionary) -> Variant:
    var preset := str(region.get("shader_preset", "flicker")).strip_edges().to_lower()
    var mode := 0
    match preset:
        "flicker":
            mode = 1
        "wave":
            mode = 2
        "heat":
            mode = 3
    if mode == 0:
        return null
    if _room_fx_shader == null:
        _room_fx_shader = Shader.new()
        _room_fx_shader.code = _ROOM_FX_SHADER_CODE
    var fx_material := ShaderMaterial.new()
    fx_material.shader = _room_fx_shader
    fx_material.set_shader_parameter("effect_mode", mode)
    fx_material.set_shader_parameter("tint", region.get("shader_tint", Color.WHITE))
    fx_material.set_shader_parameter("strength", clampf(float(region.get("shader_strength", 0.6)), 0.0, 2.0))
    fx_material.set_shader_parameter("speed", clampf(float(region.get("shader_speed", 1.0)), 0.0, 4.0))
    return fx_material


func _apply_weather(weather_v: Variant) -> void:
    if _weather_overlay == null:
        return
    if typeof(weather_v) == TYPE_DICTIONARY and _weather_overlay.has_method("configure"):
        _weather_overlay.call("configure", weather_v as Dictionary)
    elif _weather_overlay.has_method("clear_weather"):
        _weather_overlay.call("clear_weather")


func set_room_weather(room_addr: String, weather: Dictionary) -> void:
    var target_room := room_addr.strip_edges()
    if target_room.is_empty():
        target_room = _current_room_addr
    if target_room.is_empty() or not _rooms.has(target_room):
        return
    var target_v: Variant = _rooms.get(target_room, {})
    if typeof(target_v) != TYPE_DICTIONARY:
        return
    var target: Dictionary = target_v
    var normalized := _parse_weather({"weather": weather})
    target["weather"] = normalized
    _rooms[target_room] = target
    if target_room == _current_room_addr:
        _apply_weather(normalized)


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


func _update_backdrop_layer_animation(entry: Dictionary, delta: float) -> void:
    var node: Sprite2D = entry.get("node") as Sprite2D
    if node == null:
        return
    var anim_frames := maxi(1, int(entry.get("anim_frames", 1)))
    var anim_fps := maxf(0.0, float(entry.get("anim_fps", 0.0)))
    if anim_frames <= 1 or anim_fps <= 0.0:
        node.frame = 0
        return
    var anim_time := float(entry.get("anim_time", 0.0)) + delta
    entry["anim_time"] = anim_time
    var frame_idx := int(floor(anim_time * anim_fps))
    if bool(entry.get("anim_loop", true)):
        frame_idx %= anim_frames
    else:
        frame_idx = mini(frame_idx, anim_frames - 1)
    node.frame = frame_idx


func _update_backdrop_layer_transform(entry: Dictionary, cam: Camera2D, cam_pos: Vector2) -> void:
    var node: Sprite2D = entry.get("node") as Sprite2D
    if node == null or node.texture == null:
        return
    var entry_type := str(entry.get("type", "fullscreen"))
    if entry_type == "placed":
        var tex_size_placed: Vector2 = entry.get("texture_size", node.texture.get_size())
        var placed_target_size: Vector2 = entry.get("target_size", tex_size_placed)
        var speed_placed: Vector2 = entry.get("scroll_speed", Vector2.ONE)
        var base_position: Vector2 = entry.get("base_position", Vector2.ZERO)
        if tex_size_placed.x <= 0.0 or tex_size_placed.y <= 0.0:
            return
        node.scale = Vector2(placed_target_size.x / tex_size_placed.x, placed_target_size.y / tex_size_placed.y)
        node.position = base_position + Vector2(
            cam_pos.x * (1.0 - speed_placed.x),
            cam_pos.y * (1.0 - speed_placed.y))
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
    # Visible world span = viewport / zoom (Godot Camera2D: zoom > 1 magnifies,
    # showing less world). Native viewport (1920) at zoom 4 = 480 world px.
    var viewport_size: Vector2 = cam.get_viewport_rect().size
    var zx := cam.zoom.x if cam.zoom.x > 0.0 else 1.0
    var zy := cam.zoom.y if cam.zoom.y > 0.0 else 1.0
    return Vector2(
        maxf(1.0, viewport_size.x / zx),
        maxf(1.0, viewport_size.y / zy)
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
    # Returns the actually-loaded room data — when a variant rule fired,
    # this is the alternate's data, not the canonical's. External code
    # that needs the stable identity should use current_room_addr().
    var key: String = _loaded_room_addr if not _loaded_room_addr.is_empty() else _current_room_addr
    return _rooms.get(key, {})


func current_room_addr() -> String:
    # Returns the CANONICAL addr regardless of which variant is loaded so
    # doors, map state, and save snapshots stay stable across hot-swaps.
    return _current_room_addr


# Internal accessor for callers that genuinely need the loaded key (e.g.
# the live re-resolve subscriber in slice 3 comparing what was loaded vs.
# what would resolve now). Kept off the public surface to discourage
# accidental coupling to variant identity.
func _current_loaded_room_addr() -> String:
    return _loaded_room_addr if not _loaded_room_addr.is_empty() else _current_room_addr


# Next free tileset index for an uploaded atlas (in-game tileset authoring).
func next_tileset_index() -> int:
    return _tileset_mgr.next_index()


# Reassign the current room's tileset index and re-render its tile layers live.
# Rebuilds the TileSet from disk (picking up a freshly-uploaded atlas). Does not
# move the player or reset entities. Persist the change via the editor's save.
func set_current_room_tileset(idx: int) -> void:
    var key := _current_loaded_room_addr()
    if key.is_empty() or not _rooms.has(key):
        return
    _rooms[key]["tileset"] = idx
    _tileset_mgr.clear_cache()
    load_room(current_room_addr())


# Set the current room's screen-space shader regions and re-render so they apply
# live (load_room -> _apply_backdrop clears + re-adds the shader fx). Pass raw
# region dicts (hex tint ok); they're normalized via _parse_shader_regions.
func set_current_room_shader_regions(regions: Array) -> void:
    var key := _current_loaded_room_addr()
    if key.is_empty() or not _rooms.has(key):
        return
    _rooms[key]["shader_regions"] = _parse_shader_regions({"shader_regions": regions})
    load_room(current_room_addr())


func has_room(addr: String) -> bool:
    return _rooms.has(addr)


func resolve_room_addr(addr: String, from_room_addr: String = "") -> String:
    var trimmed := addr.strip_edges()
    if trimmed.is_empty():
        return ""
    if _rooms.has(trimmed):
        return trimmed
    if trimmed.count("/") > 1:
        push_warning("resolve_room_addr: '%s' uses the removed 3-slot realm/region/room form; expected '<region>/<room>' or '<room>'" % trimmed)
        return ""

    # Figure out the source region — explicit from_room_addr first, then
    # the active room, then MvMain's region resolver (which falls back to
    # pending_region_id / the pack's default region for bare boot states).
    var region_id := ""
    var source_addr := from_room_addr.strip_edges()
    if source_addr.is_empty():
        source_addr = _current_room_addr
    var source_parsed: Dictionary = RegIO.parse_room_addr(source_addr)
    region_id = str(source_parsed.get("region_id", "")).strip_edges()
    if region_id.is_empty() and MvGame.main != null and MvGame.main.has_method("_resolve_current_region_id"):
        var resolved_v: Variant = MvGame.main.call("_resolve_current_region_id")
        region_id = str(resolved_v).strip_edges()

    # Bare addresses (no slash) resolve under the active region.
    if not region_id.is_empty() and not trimmed.contains("/"):
        var qualified := RegIO.runtime_room_addr(region_id, trimmed)
        if _rooms.has(qualified):
            return qualified

    # Friendly-name lookup as a fallback: prefer matches under the active
    # region, but accept any region as a last resort so cross-region links
    # using a room's display name keep resolving.
    var name_match := ""
    var name_match_count := 0
    for key_v in _rooms.keys():
        var key := str(key_v)
        var room_v: Variant = _rooms[key]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        if str(room.get("name", "")).strip_edges() != trimmed:
            continue
        if not region_id.is_empty() and key.begins_with(region_id + "/"):
            return key
        if name_match.is_empty():
            name_match = key
        name_match_count += 1
    if name_match_count > 1:
        push_warning("resolve_room_addr: '%s' matches %d rooms by display name across regions; using '%s'. Qualify as '<region>/<room>' to disambiguate." % [trimmed, name_match_count, name_match])
    return name_match


func start_room() -> String:
    return _start_room


func rooms() -> Dictionary:
    return _rooms


func tileset_mgr() -> MvTilesetManager:
    return _tileset_mgr
