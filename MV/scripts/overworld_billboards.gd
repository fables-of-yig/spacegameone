extends Node2D

const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")
const BLOCK_SIZE: int = 16
const STRUCTURE_SCALE_MULT: float = 12.0
const SKY_SCALE_MULT: float = 4.0
const SKY_ELEVATION: float = 200.0
const MAX_VISIBLE: int = 256

var _structure_entries: Array = []
var _sky_entries: Array = []
var _sprite_pool: Array = []
var _tex_cache: Dictionary = {}
var _realm_width_px: float = 0.0
var _realm_height_px: float = 0.0
var _animated_entries: Array = []  # entries that have animation metadata
var _anim_clock: float = 0.0


func load_billboards(pack_id: String, realm_data: Dictionary) -> void:
    _structure_entries.clear()
    _sky_entries.clear()
    _tex_cache.clear()
    _animated_entries.clear()
    _anim_clock = 0.0
    _realm_width_px = float(int(realm_data.get("realm_grid_cells_x", 32))) * BLOCK_SIZE
    _realm_height_px = float(int(realm_data.get("realm_grid_cells_y", 32))) * BLOCK_SIZE

    var layers_v: Variant = realm_data.get("realm_tile_layers", [])
    if typeof(layers_v) != TYPE_ARRAY:
        return
    var layers: Array = layers_v

    if layers.size() > 1:
        _load_layer_entries(pack_id, layers[1], _structure_entries, STRUCTURE_SCALE_MULT, 0.0)
    if layers.size() > 2:
        _load_layer_entries(pack_id, layers[2], _sky_entries, SKY_SCALE_MULT, SKY_ELEVATION)


func _load_layer_entries(pack_id: String, layer_v: Variant, out: Array,
        scale_mult: float, elevation: float) -> void:
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    var layer_dict: Dictionary = layer_v as Dictionary
    var tiles: Array = layer_dict.get("tiles", [])
    var animations: Dictionary = layer_dict.get("animations", {})
    var grouped: Dictionary = {}
    for entry_v in tiles:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var col: int = int(entry.get("col", 0))
        var row: int = int(entry.get("row", 0))
        var tileset_name: String = str(entry.get("tileset", ""))
        var atlas_x: int = int(entry.get("atlas_x", 0))
        var atlas_y: int = int(entry.get("atlas_y", 0))
        var anchor_col: int = int(entry.get("anchor_col", col))
        var anchor_row: int = int(entry.get("anchor_row", row))
        var anchor_atlas_x: int = int(entry.get("anchor_atlas_x", atlas_x))
        var anchor_atlas_y: int = int(entry.get("anchor_atlas_y", atlas_y))
        var placement_w: int = maxi(int(entry.get("placement_w", 1)), 1)
        var placement_h: int = maxi(int(entry.get("placement_h", 1)), 1)
        var group_key := "%s|%d|%d|%d|%d|%d|%d" % [
            tileset_name, anchor_col, anchor_row, anchor_atlas_x, anchor_atlas_y, placement_w, placement_h]
        if grouped.has(group_key):
            continue

        var tex: Texture2D = _resolve_texture(pack_id, tileset_name)
        if tex == null:
            continue
        var src_rect := Rect2(
            float(anchor_atlas_x) * BLOCK_SIZE, float(anchor_atlas_y) * BLOCK_SIZE,
            float(placement_w) * BLOCK_SIZE, float(placement_h) * BLOCK_SIZE)
        var world_x: float = (float(anchor_col) + float(placement_w) * 0.5) * BLOCK_SIZE
        var world_y: float = (float(anchor_row) + float(placement_h)) * BLOCK_SIZE
        var billboard := {
            "world_x": world_x,
            "world_y": world_y,
            "tex": tex,
            "src_rect": src_rect,
            "anchor_col": anchor_col,
            "anchor_row": anchor_row,
            "scale_mult": scale_mult,
            "elevation": elevation,
        }
        grouped[group_key] = true

        var tile_key := "%d,%d" % [anchor_col, anchor_row]
        if placement_w == 1 and placement_h == 1 and animations.has(tile_key):
            var anim_data: Dictionary = animations[tile_key]
            @warning_ignore("integer_division")
            var sheet_cols: int = maxi(int(tex.get_width()) / BLOCK_SIZE, 1)
            var frames: Array = anim_data.get("frames", [])
            var fps: float = float(anim_data.get("fps", 8))
            var loop: bool = bool(anim_data.get("loop", true))
            var frame_rects: Array = []
            for frame_idx in frames:
                var fi: int = int(frame_idx)
                var ax: int = fi % sheet_cols
                @warning_ignore("integer_division")
                var ay: int = fi / sheet_cols
                frame_rects.append(Rect2(
                    float(ax) * BLOCK_SIZE, float(ay) * BLOCK_SIZE,
                    BLOCK_SIZE, BLOCK_SIZE))
            if not frame_rects.is_empty():
                billboard["anim_frames"] = frame_rects
                billboard["anim_fps"] = fps
                billboard["anim_loop"] = loop
                billboard["anim_frame_count"] = frame_rects.size()
                _animated_entries.append(billboard)

        out.append(billboard)


func _resolve_texture(pack_id: String, tileset_name: String) -> Texture2D:
    if _tex_cache.has(tileset_name):
        return _tex_cache[tileset_name]
    var indices := EnvIO.list_tileset_indices(pack_id)
    for idx in indices:
        var i := int(idx)
        if str(EnvIO.load_tileset_name(pack_id, i)) == tileset_name:
            var tex := EnvIO.load_tileset_texture(pack_id, i)
            _tex_cache[tileset_name] = tex
            return tex
    if tileset_name.is_valid_int():
        var tex := EnvIO.load_tileset_texture(pack_id, int(tileset_name))
        _tex_cache[tileset_name] = tex
        return tex
    _tex_cache[tileset_name] = null
    return null


func update_billboards(cam_pos: Vector2, cam_angle: float, cam_height: float,
        horizon: float, fov_scale: float, screen_size: Vector2,
        delta: float = 0.0) -> void:
    _advance_animations(delta)
    var structure_projections: Array = []
    var sky_projections: Array = []

    for entry in _structure_entries:
        _project_wrapped(entry, cam_pos, cam_angle, cam_height,
            horizon, fov_scale, screen_size, structure_projections)

    for entry in _sky_entries:
        _project_wrapped(entry, cam_pos, cam_angle, cam_height,
            horizon, fov_scale, screen_size, sky_projections)

    structure_projections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["depth"]) > float(b["depth"]))
    sky_projections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["depth"]) > float(b["depth"]))

    if structure_projections.size() > MAX_VISIBLE:
        structure_projections.resize(MAX_VISIBLE)
    if sky_projections.size() > MAX_VISIBLE:
        sky_projections.resize(MAX_VISIBLE)

    var projections: Array = []
    projections.append_array(structure_projections)
    projections.append_array(sky_projections)

    _ensure_pool(projections.size())

    var structure_count: int = structure_projections.size()
    for i in projections.size():
        var p: Dictionary = projections[i]
        var spr: Sprite2D = _sprite_pool[i]
        spr.visible = true
        spr.texture = p["tex"]
        spr.region_enabled = true
        spr.region_rect = p["src_rect"]
        var s: float = float(p["scale_factor"])
        spr.scale = Vector2(s, s)
        var src_rect: Rect2 = p["src_rect"]
        spr.position = Vector2(
            float(p["screen_x"]) - src_rect.size.x * s * 0.5,
            float(p["screen_y"]) - src_rect.size.y * s)
        if i < structure_count:
            # Structure billboards sort by depth: farther first, nearer on top.
            spr.z_index = i
        else:
            # Sky billboards always render over structures from the player's POV.
            spr.z_index = structure_count + (i - structure_count)

    for i in range(projections.size(), _sprite_pool.size()):
        (_sprite_pool[i] as Sprite2D).visible = false


func _advance_animations(delta: float) -> void:
    if _animated_entries.is_empty():
        return
    _anim_clock += delta
    for entry in _animated_entries:
        var fps: float = float(entry["anim_fps"])
        var frame_count: int = int(entry["anim_frame_count"])
        var loop: bool = bool(entry["anim_loop"])
        var total_frames: float = _anim_clock * fps
        var frame_idx: int = int(total_frames) % frame_count
        if not loop and int(total_frames) >= frame_count:
            frame_idx = frame_count - 1
        var frame_rects: Array = entry["anim_frames"]
        entry["src_rect"] = frame_rects[frame_idx]


# Project the billboard at its original position plus up to 8 wrapped copies
# so billboards near realm edges remain visible when the camera wraps around.
func _project_wrapped(entry: Dictionary, cam_pos: Vector2, cam_angle: float,
        cam_height: float, horizon_norm: float, fov_scale: float,
        screen_size: Vector2, out: Array) -> void:
    var wx: float = float(entry["world_x"])
    var wy: float = float(entry["world_y"])
    var rw := _realm_width_px
    var rh := _realm_height_px
    # Try the 9 copies (original + 8 wraps). Most will cull in _project.
    for ox in [-rw, 0.0, rw]:
        for oy in [-rh, 0.0, rh]:
            var wrapped := entry.duplicate()
            wrapped["world_x"] = wx + ox
            wrapped["world_y"] = wy + oy
            var proj: Variant = _project(wrapped, cam_pos, cam_angle, cam_height,
                horizon_norm, fov_scale, screen_size)
            if proj != null:
                out.append(proj)


func _project(entry: Dictionary, cam_pos: Vector2, cam_angle: float,
        cam_height: float, horizon_norm: float, fov_scale: float,
        screen_size: Vector2) -> Variant:
    var dx: float = float(entry["world_x"]) - cam_pos.x
    var dy: float = float(entry["world_y"]) - cam_pos.y
    var rcos := cos(cam_angle)
    var rsin := sin(cam_angle)
    var depth: float = dx * rsin + dy * rcos
    if depth <= 1.0:
        return null
    var lateral: float = dx * rcos - dy * rsin
    var screen_x_norm: float = 0.5 + lateral / (depth * fov_scale)
    if screen_x_norm < -0.2 or screen_x_norm > 1.2:
        return null
    var screen_y_norm: float = horizon_norm + cam_height / depth
    var scale_factor: float = (cam_height / depth) * float(entry.get("scale_mult", 1.0))
    var elev_offset: float = float(entry.get("elevation", 0.0)) * (cam_height / depth)
    return {
        "screen_x": screen_x_norm * screen_size.x,
        "screen_y": screen_y_norm * screen_size.y - elev_offset,
        "scale_factor": scale_factor,
        "depth": depth,
        "tex": entry["tex"],
        "src_rect": entry["src_rect"],
    }


func _ensure_pool(needed: int) -> void:
    while _sprite_pool.size() < needed:
        var spr := Sprite2D.new()
        spr.centered = false
        spr.visible = false
        add_child(spr)
        _sprite_pool.append(spr)
