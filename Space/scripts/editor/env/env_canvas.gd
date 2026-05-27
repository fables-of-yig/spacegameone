extends Control

# Tilemap canvas for the environment editor. Owns the pan/zoom camera,
# draws the selected room's tile layers + collision overlay + entity/door/
# slope markers, and dispatches paint/erase operations back to the parent
# editor via its public paint_cell / erase_cell API.
#
# Rendering uses draw_texture_rect_region on cached tileset textures — no
# TileMapLayer / TileSet resource involved. The editor is a flat immediate-
# mode renderer so we don't have to spin up the runtime's multi-source
# TileSet machinery during authoring.

const EnvTypes = preload("res://Space/scripts/editor/env/env_types.gd")

# Keyed by editor.active_mode — describes what LMB does on the canvas right
# now, used by the tooltip overlay when the user hovers the canvas.
const MODE_HELP := {
    EnvTypes.MODE_TILE: "TILE mode: LMB paints the selected tile brush onto the active tile layer. Drag in the tileset palette to build a multi-tile brush. Ctrl-drag copies a region from the canvas; Ctrl-V pastes it.",
    EnvTypes.MODE_COLLISION: "COLLISION mode: LMB paints the selected collision brush on this cell. Ctrl-drag copies a collision region; Ctrl-V pastes it. Use the left palette to author supported runtime blocks only: solid, slope, crumble, shot/bomb break, grapple, spikes, and air.",
    EnvTypes.MODE_ENTITIES: "ENTITIES mode: LMB places the selected entity type at the cursor. Use trigger volumes as named zones for zone_enter triggers, scripted NPC movement targets, and spawn targets. RMB or ERASE removes them.",
    EnvTypes.MODE_DOORS: "DOORS mode: LMB places a door cell. Doors link rooms — click a placed door with the PICK tool to edit its target room/direction.",
    EnvTypes.MODE_BG_IMAGES: "BG IMAGES mode: PAINT drags out stretched PNG rects using the selected background asset. PICK selects an existing placement. ERASE deletes the top-most placement under the cursor. Drag the selected image or its corner handles to move and resize it.",
    EnvTypes.MODE_SHADERS: "SHADERS mode: PAINT drags out animated shader zones over the room. PICK selects one, ERASE deletes one, and dragging the selected rect or its corner handles moves and resizes it.",
}

var editor: Node = null  # EnvironmentEditor — set by parent after instantiation.

func _mode_help_text(mode: int) -> String:
    if mode == EnvTypes.MODE_ENTITIES:
        return "ENTITIES mode: LMB places the selected entity type at the cursor. Use this for actors and pickups; room logic zones now live in ZONES mode. RMB or ERASE removes them."
    if mode == EnvTypes.MODE_ZONES or mode == EnvTypes.MODE_DOORS or mode == EnvTypes.MODE_SHADERS:
        return "ZONES mode: PAINT drags out room zones for doors, shaders, interact prompts, and triggers. PICK selects one, ERASE deletes one, and dragging the selected rect or its corner handles moves and resizes it."
    return MODE_HELP.get(mode, "")


const BLOCK_SIZE: int = 16

# Camera state
var cam_offset: Vector2 = Vector2(32, 32)  # world-pos of the top-left of the canvas
var zoom: float = 2.0

# Interaction state
var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO
var _painting: bool = false
var _erasing: bool = false
var _copy_selecting: bool = false
var _copy_start_cell: Vector2i = Vector2i(-1, -1)
var _copy_end_cell: Vector2i = Vector2i(-1, -1)
var _copied_rect: Rect2i = Rect2i()
var _last_painted_cell: Vector2i = Vector2i(-1, -1)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _bg_drag_mode: String = ""
var _bg_drag_active: bool = false
var _bg_drag_start_blocks: Vector2 = Vector2.ZERO
var _bg_drag_last_blocks: Vector2 = Vector2.ZERO
var _bg_drag_origin_rect: Rect2 = Rect2()
var _bg_preview_rect: Rect2 = Rect2()
var _shader_drag_mode: String = ""
var _shader_drag_active: bool = false
var _shader_drag_start_blocks: Vector2 = Vector2.ZERO
var _shader_drag_last_blocks: Vector2 = Vector2.ZERO
var _shader_drag_origin_rect: Rect2 = Rect2()
var _shader_preview_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    clip_contents = true
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = mb.pressed
            _pan_last = mb.position
            accept_event()
            return
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _zoom_at(mb.position, 1.15)
            accept_event()
            return
        if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _zoom_at(mb.position, 1.0 / 1.15)
            accept_event()
            return
        if editor.active_mode == EnvTypes.MODE_BG_IMAGES:
            if mb.button_index == MOUSE_BUTTON_LEFT:
                if mb.pressed:
                    _begin_bg_image_interaction(mb.position, false)
                else:
                    _finish_bg_image_interaction()
                accept_event()
                return
            if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
                _begin_bg_image_interaction(mb.position, true)
                accept_event()
                return
        if editor.active_mode == EnvTypes.MODE_ZONES:
            if mb.button_index == MOUSE_BUTTON_LEFT:
                if mb.pressed:
                    _begin_shader_interaction(mb.position, false)
                else:
                    _finish_shader_interaction()
                accept_event()
                return
            if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
                _begin_shader_interaction(mb.position, true)
                accept_event()
                return
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                if mb.ctrl_pressed and editor.active_mode in [EnvTypes.MODE_TILE, EnvTypes.MODE_COLLISION]:
                    _copy_selecting = true
                    _copy_start_cell = _screen_to_cell(mb.position)
                    _copy_end_cell = _copy_start_cell
                    accept_event()
                    return
                _painting = true
                _last_painted_cell = Vector2i(-1, -1)
                if editor != null:
                    editor.begin_stroke()
                _apply_tool_at(mb.position, false)
            else:
                if _copy_selecting:
                    _copy_selecting = false
                    _copy_end_cell = _screen_to_cell(mb.position)
                    _copied_rect = _normalized_cell_rect(_copy_start_cell, _copy_end_cell)
                    if editor != null:
                        editor.copy_active_region(_copied_rect)
                    accept_event()
                    return
                _painting = false
                if editor != null:
                    editor.end_stroke()
            accept_event()
            return
        if mb.button_index == MOUSE_BUTTON_RIGHT:
            if mb.pressed:
                _erasing = true
                _last_painted_cell = Vector2i(-1, -1)
                if editor != null:
                    editor.begin_stroke()
                _apply_tool_at(mb.position, true)
            else:
                _erasing = false
                if editor != null:
                    editor.end_stroke()
            accept_event()
            return

    if event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if _panning:
            cam_offset += mm.position - _pan_last
            _pan_last = mm.position
            accept_event()
            return
        if editor.active_mode == EnvTypes.MODE_BG_IMAGES and _bg_drag_active:
            _update_bg_image_interaction(mm.position)
            accept_event()
            return
        if editor.active_mode == EnvTypes.MODE_ZONES and _shader_drag_active:
            _update_shader_interaction(mm.position)
            accept_event()
            return
        _hover_cell = _screen_to_cell(mm.position)
        if _copy_selecting:
            _copy_end_cell = _hover_cell
        elif _painting:
            _apply_tool_at(mm.position, false)
        elif _erasing:
            _apply_tool_at(mm.position, true)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
    var world_before := (screen_pos - cam_offset) / zoom
    zoom = clampf(zoom * factor, 0.5, 8.0)
    var world_after := (screen_pos - cam_offset) / zoom
    cam_offset += (world_after - world_before) * zoom


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
    var world := (screen_pos - cam_offset) / zoom
    return Vector2i(floori(world.x / float(BLOCK_SIZE)), floori(world.y / float(BLOCK_SIZE)))


func _screen_to_world_px(screen_pos: Vector2) -> Vector2:
    return (screen_pos - cam_offset) / zoom


func _cell_to_screen(col: int, row: int) -> Vector2:
    return cam_offset + Vector2(float(col * BLOCK_SIZE), float(row * BLOCK_SIZE)) * zoom


func _world_to_screen(world: Vector2) -> Vector2:
    return cam_offset + world * zoom


func _screen_to_block_pos(screen_pos: Vector2) -> Vector2:
    var world := _screen_to_world_px(screen_pos)
    return world / float(BLOCK_SIZE)


func _normalized_rect_from_points(a: Vector2, b: Vector2) -> Rect2:
    var min_x := minf(a.x, b.x)
    var min_y := minf(a.y, b.y)
    var max_x := maxf(a.x, b.x)
    var max_y := maxf(a.y, b.y)
    return Rect2(Vector2(min_x, min_y), Vector2(maxf(0.0, max_x - min_x), maxf(0.0, max_y - min_y)))


func _bg_screen_rect(entry: Dictionary) -> Rect2:
    return _background_image_screen_rect(entry)


func _bg_handle_rects(screen_rect: Rect2) -> Dictionary:
    var handle_size := maxf(8.0, 10.0 * zoom)
    var half := handle_size * 0.5
    return {
        "tl": Rect2(screen_rect.position - Vector2(half, half), Vector2(handle_size, handle_size)),
        "tr": Rect2(Vector2(screen_rect.end.x - half, screen_rect.position.y - half), Vector2(handle_size, handle_size)),
        "bl": Rect2(Vector2(screen_rect.position.x - half, screen_rect.end.y - half), Vector2(handle_size, handle_size)),
        "br": Rect2(screen_rect.end - Vector2(half, half), Vector2(handle_size, handle_size)),
    }


func _begin_bg_image_interaction(screen_pos: Vector2, erase: bool) -> void:
    if editor == null:
        return
    var world := _screen_to_world_px(screen_pos)
    if erase or editor.active_tool == EnvTypes.TOOL_ERASE:
        editor.begin_stroke()
        editor.delete_background_image_at(world.x, world.y)
        editor.end_stroke()
        return
    if editor.active_tool == EnvTypes.TOOL_PICK:
        editor.pick_background_image_at(world.x, world.y)
        return
    var selected: Dictionary = editor.get_selected_background_image() if editor.has_method("get_selected_background_image") else {}
    if not selected.is_empty():
        var screen_rect := _bg_screen_rect(selected)
        var handles := _bg_handle_rects(screen_rect)
        for key_v in handles.keys():
            var key := str(key_v)
            if (handles[key] as Rect2).has_point(screen_pos):
                _bg_drag_active = true
                _bg_drag_mode = "resize_%s" % key
                _bg_drag_origin_rect = Rect2(
                    Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                    Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
                _bg_drag_start_blocks = _screen_to_block_pos(screen_pos)
                _bg_drag_last_blocks = _bg_drag_start_blocks
                editor.begin_stroke()
                return
        if screen_rect.has_point(screen_pos):
            _bg_drag_active = true
            _bg_drag_mode = "move"
            _bg_drag_origin_rect = Rect2(
                Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
            _bg_drag_start_blocks = _screen_to_block_pos(screen_pos)
            _bg_drag_last_blocks = _bg_drag_start_blocks
            editor.begin_stroke()
            return
    if editor.has_method("find_background_image_hit"):
        var hit: Dictionary = editor.find_background_image_hit(world.x, world.y)
        if not hit.is_empty():
            editor.pick_background_image_at(world.x, world.y)
            selected = editor.get_selected_background_image() if editor.has_method("get_selected_background_image") else {}
            if not selected.is_empty():
                _bg_drag_active = true
                _bg_drag_mode = "move"
                _bg_drag_origin_rect = Rect2(
                    Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                    Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
                _bg_drag_start_blocks = _screen_to_block_pos(screen_pos)
                _bg_drag_last_blocks = _bg_drag_start_blocks
                editor.begin_stroke()
                return
    _bg_drag_active = true
    _bg_drag_mode = "create"
    _bg_drag_start_blocks = _screen_to_block_pos(screen_pos)
    _bg_drag_last_blocks = _bg_drag_start_blocks
    _bg_preview_rect = Rect2(_bg_drag_start_blocks, Vector2.ZERO)


func _update_bg_image_interaction(screen_pos: Vector2) -> void:
    if not _bg_drag_active or editor == null:
        return
    var blocks := _screen_to_block_pos(screen_pos)
    _bg_drag_last_blocks = blocks
    if _bg_drag_mode == "create":
        _bg_preview_rect = _normalized_rect_from_points(_bg_drag_start_blocks, blocks)
        return
    if _bg_drag_mode == "move":
        var delta := blocks - _bg_drag_start_blocks
        editor.set_selected_background_image_rect(Rect2(_bg_drag_origin_rect.position + delta, _bg_drag_origin_rect.size))
        return
    if _bg_drag_mode.begins_with("resize_"):
        var rect := _bg_drag_origin_rect
        var tl := rect.position
        var br := rect.end
        var handle := _bg_drag_mode.trim_prefix("resize_")
        if handle == "tl":
            tl = blocks
        elif handle == "tr":
            tl.y = blocks.y
            br.x = blocks.x
        elif handle == "bl":
            tl.x = blocks.x
            br.y = blocks.y
        elif handle == "br":
            br = blocks
        editor.set_selected_background_image_rect(_normalized_rect_from_points(tl, br))


func _finish_bg_image_interaction() -> void:
    if not _bg_drag_active or editor == null:
        return
    if _bg_drag_mode == "create":
        var rect := _normalized_rect_from_points(_bg_drag_start_blocks, _bg_drag_last_blocks)
        if rect.size.x > 0.01 and rect.size.y > 0.01:
            editor.begin_stroke()
            editor.create_background_image(rect)
            editor.end_stroke()
    elif _bg_drag_mode == "move" or _bg_drag_mode.begins_with("resize_"):
        editor.end_stroke()
    _bg_drag_active = false
    _bg_drag_mode = ""
    _bg_preview_rect = Rect2()


func _shader_screen_rect(entry: Dictionary) -> Rect2:
    return _background_image_screen_rect(entry)


func _begin_shader_interaction(screen_pos: Vector2, erase: bool) -> void:
    if editor == null:
        return
    var world := _screen_to_world_px(screen_pos)
    if erase or editor.active_tool == EnvTypes.TOOL_ERASE:
        editor.begin_stroke()
        editor.delete_zone_at(world.x, world.y)
        editor.end_stroke()
        return
    if editor.active_tool == EnvTypes.TOOL_PICK:
        editor.pick_zone_at(world.x, world.y)
        return
    var selected: Dictionary = editor.get_selected_zone() if editor.has_method("get_selected_zone") else {}
    if not selected.is_empty():
        var screen_rect := _shader_screen_rect(selected)
        var handles := _bg_handle_rects(screen_rect)
        for key_v in handles.keys():
            var key := str(key_v)
            if (handles[key] as Rect2).has_point(screen_pos):
                _shader_drag_active = true
                _shader_drag_mode = "resize_%s" % key
                _shader_drag_origin_rect = Rect2(
                    Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                    Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
                _shader_drag_start_blocks = _screen_to_block_pos(screen_pos)
                _shader_drag_last_blocks = _shader_drag_start_blocks
                editor.begin_stroke()
                return
        if screen_rect.has_point(screen_pos):
            _shader_drag_active = true
            _shader_drag_mode = "move"
            _shader_drag_origin_rect = Rect2(
                Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
            _shader_drag_start_blocks = _screen_to_block_pos(screen_pos)
            _shader_drag_last_blocks = _shader_drag_start_blocks
            editor.begin_stroke()
            return
    if editor.has_method("find_zone_hit"):
        var hit: Dictionary = editor.find_zone_hit(world.x, world.y)
        if not hit.is_empty():
            editor.pick_zone_at(world.x, world.y)
            selected = editor.get_selected_zone() if editor.has_method("get_selected_zone") else {}
            if not selected.is_empty():
                _shader_drag_active = true
                _shader_drag_mode = "move"
                _shader_drag_origin_rect = Rect2(
                    Vector2(float(selected.get("x_blocks", 0.0)), float(selected.get("y_blocks", 0.0))),
                    Vector2(float(selected.get("width_blocks", 0.0)), float(selected.get("height_blocks", 0.0))))
                _shader_drag_start_blocks = _screen_to_block_pos(screen_pos)
                _shader_drag_last_blocks = _shader_drag_start_blocks
                editor.begin_stroke()
                return
    _shader_drag_active = true
    _shader_drag_mode = "create"
    _shader_drag_start_blocks = _screen_to_block_pos(screen_pos)
    _shader_drag_last_blocks = _shader_drag_start_blocks
    _shader_preview_rect = Rect2(_shader_drag_start_blocks, Vector2.ZERO)


func _update_shader_interaction(screen_pos: Vector2) -> void:
    if not _shader_drag_active or editor == null:
        return
    var blocks := _screen_to_block_pos(screen_pos)
    _shader_drag_last_blocks = blocks
    if _shader_drag_mode == "create":
        _shader_preview_rect = _normalized_rect_from_points(_shader_drag_start_blocks, blocks)
        return
    if _shader_drag_mode == "move":
        var delta := blocks - _shader_drag_start_blocks
        editor.set_selected_zone_rect(Rect2(_shader_drag_origin_rect.position + delta, _shader_drag_origin_rect.size))
        return
    if _shader_drag_mode.begins_with("resize_"):
        var rect := _shader_drag_origin_rect
        var tl := rect.position
        var br := rect.end
        var handle := _shader_drag_mode.trim_prefix("resize_")
        if handle == "tl":
            tl = blocks
        elif handle == "tr":
            tl.y = blocks.y
            br.x = blocks.x
        elif handle == "bl":
            tl.x = blocks.x
            br.y = blocks.y
        elif handle == "br":
            br = blocks
        editor.set_selected_zone_rect(_normalized_rect_from_points(tl, br))


func _finish_shader_interaction() -> void:
    if not _shader_drag_active or editor == null:
        return
    if _shader_drag_mode == "create":
        var rect := _normalized_rect_from_points(_shader_drag_start_blocks, _shader_drag_last_blocks)
        if rect.size.x > 0.01 and rect.size.y > 0.01:
            editor.begin_stroke()
            editor.create_zone(rect)
            editor.end_stroke()
    elif _shader_drag_mode == "move" or _shader_drag_mode.begins_with("resize_"):
        editor.end_stroke()
    _shader_drag_active = false
    _shader_drag_mode = ""
    _shader_preview_rect = Rect2()


func _apply_tool_at(screen_pos: Vector2, erase: bool) -> void:
    if editor == null:
        return
    if not erase and editor.has_method("has_grid_paste_preview") and editor.has_grid_paste_preview():
        var paste_cell := _screen_to_cell(screen_pos)
        editor.paste_grid_clipboard(paste_cell.y, paste_cell.x)
        return
    var room: Dictionary = editor.get_current_room()
    if room.is_empty():
        return

    if editor.active_mode == EnvTypes.MODE_ENTITIES:
        # Entities live in pixel space; drag-paint would spam duplicates, so
        # only fire on the initial press (press handler resets this to
        # Vector2i(-1,-1)) and flip a sentinel to swallow subsequent motion.
        if _last_painted_cell != Vector2i(-1, -1):
            return
        _last_painted_cell = Vector2i(-2, -2)
        var world := _screen_to_world_px(screen_pos)
        if editor.active_tool == EnvTypes.TOOL_ERASE or erase:
            editor.delete_entity_near(world.x, world.y)
        elif editor.active_tool == EnvTypes.TOOL_PICK:
            editor.pick_entity_at(world.x, world.y)
        else:
            editor.place_entity_at(world.x, world.y)
        return

    var cell := _screen_to_cell(screen_pos)
    if cell == _last_painted_cell:
        return
    _last_painted_cell = cell
    var rows := int(room.get("height_blocks", 0))
    var cols := int(room.get("width_blocks", 0))
    if cell.y < 0 or cell.y >= rows or cell.x < 0 or cell.x >= cols:
        return

    if editor.active_mode == EnvTypes.MODE_ZONES:
        var world := _screen_to_world_px(screen_pos)
        if editor.active_tool == EnvTypes.TOOL_ERASE or erase:
            editor.delete_zone_at(world.x, world.y)
        elif editor.active_tool == EnvTypes.TOOL_PICK:
            editor.pick_zone_at(world.x, world.y)
        return

    if erase:
        editor.erase_cell(cell.y, cell.x)
    else:
        editor.paint_cell(cell.y, cell.x)


# ─── Draw ────────────────────────────────────────────────────────────────

func _draw():
    # Backdrop
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.12, 1.0))

    if editor == null:
        return
    var room: Dictionary = editor.get_current_room()
    if room.is_empty():
        _draw_empty_hint()
        return

    var rows := int(room.get("height_blocks", 0))
    var cols := int(room.get("width_blocks", 0))
    if rows <= 0 or cols <= 0:
        _draw_empty_hint()
        return

    _draw_room_background(room, rows, cols)

    var active_mode: int = editor.active_mode
    var active_idx: int = editor.active_tile_layer_idx
    var editing_tile: bool = active_mode == EnvTypes.MODE_TILE
    var editing_collision: bool = active_mode == EnvTypes.MODE_COLLISION
    var _editing_entities: bool = active_mode == EnvTypes.MODE_ENTITIES
    var editing_bg_images: bool = active_mode == EnvTypes.MODE_BG_IMAGES
    var editing_zones: bool = active_mode == EnvTypes.MODE_ZONES

    # tile_layers is already in draw order (bg → main → fg). Iterate and
    # draw each in place. When editing a tile layer, the active layer draws
    # opaque and siblings dim based on distance from active. When editing
    # a non-tile mode, all tile layers dim uniformly so the overlay reads.
    var tile_layers_v: Variant = room.get("tile_layers", [])
    if typeof(tile_layers_v) == TYPE_ARRAY:
        var tile_layers: Array = tile_layers_v
        for i in tile_layers.size():
            var layer_v: Variant = tile_layers[i]
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = layer_v
            var tiles_v: Variant = layer.get("tiles")
            if typeof(tiles_v) != TYPE_ARRAY:
                continue
            var alpha: float
            if editing_tile:
                if i == active_idx:
                    alpha = 1.0
                else:
                    alpha = 0.35
            else:
                alpha = 0.5
            var anims_v: Variant = layer.get("animations", {})
            var layer_anims: Dictionary = anims_v if typeof(anims_v) == TYPE_DICTIONARY else {}
            _draw_tile_layer(tiles_v, alpha, layer_anims)

        # Draw animated cell indicators on the active tile layer.
        if editing_tile and editor.has_method("get_tile_layer_animations"):
            var anims: Dictionary = editor.get_tile_layer_animations(active_idx)
            if not anims.is_empty():
                _draw_anim_indicators(anims)

    if editing_collision:
        _draw_collision_overlay(room, rows, cols, 1.0)
    elif editor.show_collision:
        _draw_collision_overlay(room, rows, cols, 0.7)

    _draw_entities(room)
    _draw_trigger_camera_preview()
    _draw_zones(editing_zones)
    _draw_background_image_handles(editing_bg_images)
    _draw_zone_handles(editing_zones)
    _draw_grid(rows, cols)
    _draw_copy_selection(rows, cols)
    _draw_paste_preview(rows, cols)
    _draw_hover_marker(rows, cols)

    if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
        var help: String = _mode_help_text(active_mode)
        if help != "":
            var controls := "\nMMB drag to pan, wheel to zoom. LMB uses the active tool, RMB always erases."
            if _hover_cell.x >= 0 and _hover_cell.x < cols and _hover_cell.y >= 0 and _hover_cell.y < rows:
                controls += "\nCell (%d, %d)" % [_hover_cell.x, _hover_cell.y]
                if active_mode == EnvTypes.MODE_COLLISION and editor.has_method("get_slope_info_at"):
                    var slope_info: Dictionary = editor.get_slope_info_at(_hover_cell.y, _hover_cell.x)
                    if not slope_info.is_empty() and bool(slope_info.get("valid", false)):
                        controls += "\n%s" % str(slope_info.get("label", "Slope"))
                        var grade := str(slope_info.get("grade_label", ""))
                        if not grade.is_empty():
                            controls += "\n%s" % grade
            EditorTooltip.show_text(help + controls)


func copy_selection_to_clipboard() -> bool:
    if editor == null or _copied_rect.size.x <= 0 or _copied_rect.size.y <= 0:
        return false
    return editor.copy_active_region(_copied_rect)


func _normalized_cell_rect(a: Vector2i, b: Vector2i) -> Rect2i:
    var min_x := mini(a.x, b.x)
    var min_y := mini(a.y, b.y)
    var max_x := maxi(a.x, b.x)
    var max_y := maxi(a.y, b.y)
    return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _draw_copy_selection(rows: int, cols: int) -> void:
    var rect := Rect2i()
    if _copy_selecting:
        rect = _normalized_cell_rect(_copy_start_cell, _copy_end_cell)
    elif _copied_rect.size.x > 0 and _copied_rect.size.y > 0:
        rect = _copied_rect
    else:
        return
    _draw_cell_rect_outline(rect, rows, cols, Color(0.45, 0.9, 1.0, 0.95), Color(0.45, 0.9, 1.0, 0.15))


func _draw_paste_preview(rows: int, cols: int) -> void:
    if editor == null or not editor.has_method("has_grid_paste_preview") or not editor.has_grid_paste_preview():
        return
    if _hover_cell.x < 0 or _hover_cell.y < 0:
        return
    var size_cells: Vector2i = editor.get_grid_clipboard_size()
    if size_cells.x <= 0 or size_cells.y <= 0:
        return
    var rect := Rect2i(_hover_cell, size_cells)
    _draw_cell_rect_outline(rect, rows, cols, Color(0.55, 1.0, 0.45, 0.95), Color(0.55, 1.0, 0.45, 0.14))


func _draw_cell_rect_outline(rect: Rect2i, rows: int, cols: int, stroke: Color, fill: Color) -> void:
    var clipped := Rect2i(
        Vector2i(clampi(rect.position.x, 0, cols), clampi(rect.position.y, 0, rows)),
        Vector2i(clampi(rect.end.x, 0, cols), clampi(rect.end.y, 0, rows)) - Vector2i(clampi(rect.position.x, 0, cols), clampi(rect.position.y, 0, rows)))
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return
    var top_left := _cell_to_screen(clipped.position.x, clipped.position.y)
    var bottom_right := _cell_to_screen(clipped.end.x, clipped.end.y)
    var screen_rect := Rect2(top_left, bottom_right - top_left)
    draw_rect(screen_rect, fill)
    draw_rect(screen_rect, stroke, false, 2.0)


func _draw_empty_hint() -> void:
    var font := ThemeDB.fallback_font
    var msg := "(no room loaded)"
    var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
    draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5),
        msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.5, 0.6, 1.0))


func _draw_room_background(room: Dictionary, rows: int, cols: int) -> void:
    var top_left := _cell_to_screen(0, 0)
    var bot_right := _cell_to_screen(cols, rows)
    var room_rect := Rect2(top_left, bot_right - top_left)
    var has_parallax := _draw_room_parallax(room, room_rect)
    if not has_parallax:
        draw_rect(room_rect, Color(0.02, 0.03, 0.06, 1.0))
    _draw_room_background_images()
    draw_rect(room_rect, Color(0.35, 0.5, 0.75, 0.8), false, 2.0)


func _draw_room_parallax(_room: Dictionary, room_rect: Rect2) -> bool:
    if editor == null or not editor.has_method("get_room_parallax_layers"):
        return false
    var layers: Array = editor.get_room_parallax_layers()
    var any_drawn := false
    for layer_v in layers:
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = layer_v
        var rel_path := str(layer.get("image", ""))
        if rel_path.is_empty():
            continue
        var tex: Texture2D = null
        if editor.has_method("load_backdrop_texture"):
            tex = editor.load_backdrop_texture(rel_path)
        if tex == null:
            continue
        draw_texture_rect(tex, room_rect, false)
        any_drawn = true
    return any_drawn


func _draw_room_background_images() -> void:
    if editor == null \
            or not editor.has_method("get_room_background_images") \
            or not editor.has_method("load_backdrop_texture"):
        return
    var bg_images: Array = editor.get_room_background_images()
    for bg_v in bg_images:
        if typeof(bg_v) != TYPE_DICTIONARY:
            continue
        var bg: Dictionary = bg_v
        var rel_path := str(bg.get("image", "")).strip_edges()
        if rel_path.is_empty():
            continue
        var tex: Texture2D = editor.load_backdrop_texture(rel_path)
        if tex == null:
            continue
        var screen_rect := _background_image_screen_rect(bg)
        if screen_rect.size.x <= 0.0 or screen_rect.size.y <= 0.0:
            continue
        var frame_count := maxi(1, int(bg.get("anim_frames", 1)))
        var fps := maxf(0.0, float(bg.get("anim_fps", 0.0)))
        var tint := Color.from_string(str(bg.get("shader_tint", "ffffff")), Color.WHITE)
        if frame_count > 1 and fps > 0.0:
            var frame_w := float(tex.get_width()) / float(frame_count)
            var frame_idx := int(floor(Time.get_ticks_msec() * 0.001 * fps)) % frame_count
            var src_rect := Rect2(frame_w * float(frame_idx), 0.0, frame_w, float(tex.get_height()))
            draw_texture_rect_region(tex, screen_rect, src_rect, tint)
        else:
            draw_texture_rect(tex, screen_rect, false, tint)


func _background_image_screen_rect(bg: Dictionary) -> Rect2:
    var x_blocks := float(bg.get("x_blocks", 0.0))
    var y_blocks := float(bg.get("y_blocks", 0.0))
    var w_blocks := float(bg.get("width_blocks", 0.0))
    var h_blocks := float(bg.get("height_blocks", 0.0))
    if w_blocks <= 0.0 or h_blocks <= 0.0:
        return Rect2()
    var world_pos := Vector2(x_blocks * BLOCK_SIZE, y_blocks * BLOCK_SIZE)
    var screen_pos := _world_to_screen(world_pos)
    return Rect2(screen_pos, Vector2(w_blocks * BLOCK_SIZE * zoom, h_blocks * BLOCK_SIZE * zoom))


func _draw_background_image_handles(editing_bg_images: bool) -> void:
    if editor == null or not editor.has_method("get_selected_background_image"):
        return
    var selected: Dictionary = editor.get_selected_background_image()
    if selected.is_empty():
        if _bg_drag_mode == "create" and _bg_preview_rect.size.x > 0.0 and _bg_preview_rect.size.y > 0.0:
            var preview := _bg_screen_rect({
                "x_blocks": _bg_preview_rect.position.x,
                "y_blocks": _bg_preview_rect.position.y,
                "width_blocks": _bg_preview_rect.size.x,
                "height_blocks": _bg_preview_rect.size.y,
            })
            draw_rect(preview, Color(1.0, 0.86, 0.45, 0.14))
            draw_rect(preview, Color(1.0, 0.86, 0.45, 0.95), false, 2.0)
        return
    var screen_rect := _bg_screen_rect(selected)
    var stroke := Color(1.0, 0.86, 0.45, 0.95) if editing_bg_images else Color(0.9, 0.8, 0.55, 0.75)
    draw_rect(screen_rect, Color(stroke.r, stroke.g, stroke.b, 0.10))
    draw_rect(screen_rect, stroke, false, 2.0)
    if editing_bg_images:
        var handles := _bg_handle_rects(screen_rect)
        for key_v in handles.keys():
            var rect: Rect2 = handles[key_v]
            draw_rect(rect, Color(0.05, 0.06, 0.08, 0.95))
            draw_rect(rect, stroke, false, 1.5)
    if _bg_drag_mode == "create" and _bg_preview_rect.size.x > 0.0 and _bg_preview_rect.size.y > 0.0:
        var preview := _bg_screen_rect({
            "x_blocks": _bg_preview_rect.position.x,
            "y_blocks": _bg_preview_rect.position.y,
            "width_blocks": _bg_preview_rect.size.x,
            "height_blocks": _bg_preview_rect.size.y,
        })
        draw_rect(preview, Color(1.0, 0.86, 0.45, 0.14))
        draw_rect(preview, Color(1.0, 0.86, 0.45, 0.95), false, 2.0)


func _zone_palette_colors(zone: Dictionary, editing_zones: bool) -> Dictionary:
    var kind := str(zone.get("kind", "shader")).strip_edges().to_lower()
    var stroke := Color(0.8, 0.88, 1.0, 0.9)
    var fill := Color(0.6, 0.72, 1.0, 0.16)
    if kind == "door":
        stroke = Color(0.45, 0.95, 0.6, 0.94)
        fill = Color(0.14, 0.62, 0.34, 0.16)
    elif kind == "interact":
        stroke = Color(1.0, 0.86, 0.35, 0.94)
        fill = Color(0.92, 0.66, 0.12, 0.16)
    elif kind == "trigger":
        stroke = Color(1.0, 0.52, 0.34, 0.94)
        fill = Color(0.78, 0.26, 0.18, 0.16)
    else:
        var preset := str(zone.get("shader_preset", "flicker")).strip_edges().to_lower()
        match preset:
            "wave":
                stroke = Color(0.45, 0.95, 1.0, 0.92)
                fill = Color(0.2, 0.7, 1.0, 0.16)
            "heat":
                stroke = Color(1.0, 0.68, 0.35, 0.94)
                fill = Color(1.0, 0.42, 0.16, 0.15)
            _:
                stroke = Color(0.88, 0.84, 1.0, 0.92)
                fill = Color(0.72, 0.62, 1.0, 0.14)
    if not editing_zones:
        stroke.a *= 0.7
        fill.a *= 0.8
    return {"stroke": stroke, "fill": fill}


func _draw_zones(editing_zones: bool) -> void:
    if editor == null or not editor.has_method("get_room_zones"):
        return
    var zones: Array = editor.get_room_zones()
    var time_s := Time.get_ticks_msec() * 0.001
    for zone_v in zones:
        if typeof(zone_v) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zone_v
        var screen_rect := _shader_screen_rect(zone)
        if screen_rect.size.x <= 0.0 or screen_rect.size.y <= 0.0:
            continue
        var palette: Dictionary = _zone_palette_colors(zone, editing_zones)
        var stroke: Color = palette.get("stroke", Color(1, 1, 1, 0.9))
        var fill: Color = palette.get("fill", Color(1, 1, 1, 0.14))
        var pulse := 1.0
        if str(zone.get("kind", "shader")) == "shader":
            pulse = 0.86 + sin(time_s * maxf(0.5, float(zone.get("shader_speed", 1.0))) * 3.2) * 0.14
        draw_rect(screen_rect, Color(fill.r, fill.g, fill.b, fill.a * pulse))
        draw_rect(screen_rect, stroke, false, 2.0)
        var label := str(zone.get("kind", "shader")).to_upper()
        if label == "SHADER":
            label = str(zone.get("shader_preset", "flicker")).to_upper()
        var font := ThemeDB.fallback_font
        draw_string(font, screen_rect.position + Vector2(6.0, 14.0),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(stroke.r, stroke.g, stroke.b, 0.95))
    if _shader_drag_mode == "create" and _shader_preview_rect.size.x > 0.0 and _shader_preview_rect.size.y > 0.0:
        var preview := _shader_screen_rect({
            "x_blocks": _shader_preview_rect.position.x,
            "y_blocks": _shader_preview_rect.position.y,
            "width_blocks": _shader_preview_rect.size.x,
            "height_blocks": _shader_preview_rect.size.y,
        })
        draw_rect(preview, Color(0.75, 0.84, 1.0, 0.14))
        draw_rect(preview, Color(0.75, 0.84, 1.0, 0.96), false, 2.0)


func _draw_zone_handles(editing_zones: bool) -> void:
    if editor == null or not editor.has_method("get_selected_zone"):
        return
    var selected: Dictionary = editor.get_selected_zone()
    if selected.is_empty():
        return
    var screen_rect := _shader_screen_rect(selected)
    var palette := _zone_palette_colors(selected, editing_zones)
    var stroke: Color = palette.get("stroke", Color(0.82, 0.9, 1.0, 0.98))
    draw_rect(screen_rect, Color(stroke.r, stroke.g, stroke.b, 0.08))
    draw_rect(screen_rect, stroke, false, 2.0)
    if editing_zones:
        var handles := _bg_handle_rects(screen_rect)
        for key_v in handles.keys():
            var rect: Rect2 = handles[key_v]
            draw_rect(rect, Color(0.05, 0.06, 0.08, 0.95))
            draw_rect(rect, stroke, false, 1.5)


func _draw_shader_regions(editing_shaders: bool) -> void:
    _draw_zones(editing_shaders)


func _draw_shader_region_handles(editing_shaders: bool) -> void:
    _draw_zone_handles(editing_shaders)


func _draw_tile_layer(tiles: Array, alpha: float, animations: Dictionary = {}) -> void:
    var rows := tiles.size()
    if rows == 0:
        return
    var cell_size := float(BLOCK_SIZE) * zoom
    var now_sec := Time.get_ticks_msec() / 1000.0
    for r in rows:
        var row_v: Variant = tiles[r]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row: Array = row_v
        for c in row.size():
            var packed := int(row[c])
            if packed == 0:
                continue
            var info := MvTileValue.unpack_full(packed)
            var idx: int = info["idx"]
            var tileset_id: int = info["tileset"]
            var hflip: bool = info["hflip"]
            var vflip: bool = info["vflip"]
            # Swap idx for the current animation frame when this cell has
            # a multi-frame anim configured. Matches the runtime algorithm
            # in MV/scripts/room_renderer.gd so editor preview = gameplay.
            if not animations.is_empty():
                var anim_idx := _resolve_anim_frame_idx(animations, c, r, now_sec)
                if anim_idx >= 0:
                    idx = anim_idx
            var tex: Texture2D = editor.get_tileset_texture(tileset_id)
            if tex == null:
                continue
            @warning_ignore("integer_division")
            var grid_cols := tex.get_width() / BLOCK_SIZE
            if grid_cols <= 0:
                continue
            var src_col := idx % grid_cols
            @warning_ignore("integer_division")
            var src_row := idx / grid_cols
            var src_rect := Rect2(
                Vector2(src_col * BLOCK_SIZE, src_row * BLOCK_SIZE),
                Vector2(BLOCK_SIZE, BLOCK_SIZE))
            var dst_pos := _cell_to_screen(c, r)
            var dst_rect := Rect2(dst_pos, Vector2(cell_size, cell_size))
            _draw_tile_quad(tex, dst_rect, src_rect, alpha, hflip, vflip)


# Returns the metatile idx for the current frame of the animation at
# (col, row), or -1 if no animation is configured. `now_sec` is the
# shared timebase so every cell stays in lockstep within a redraw.
func _resolve_anim_frame_idx(animations: Dictionary, col: int, row: int, now_sec: float) -> int:
    var key := "%d,%d" % [col, row]
    if not animations.has(key):
        return -1
    var cfg_v: Variant = animations[key]
    if typeof(cfg_v) != TYPE_DICTIONARY:
        return -1
    var cfg: Dictionary = cfg_v
    var frames_v: Variant = cfg.get("frames", [])
    if typeof(frames_v) != TYPE_ARRAY:
        return -1
    var frames: Array = frames_v
    var frame_count: int = frames.size()
    if frame_count < 2:
        return -1
    var fps := float(cfg.get("fps", 8.0))
    if fps <= 0.0:
        fps = 8.0
    var phase := float(cfg.get("phase_offset", 0.0))
    var elapsed_frames := int(floor((now_sec + phase) * fps))
    if elapsed_frames < 0:
        elapsed_frames = 0
    var new_idx: int = 0
    if bool(cfg.get("ping_pong", false)):
        var cycle: int = maxi(1, (frame_count - 1) * 2)
        var pos: int = elapsed_frames % cycle
        if pos < frame_count:
            new_idx = pos
        else:
            new_idx = cycle - pos
        new_idx = clampi(new_idx, 0, frame_count - 1)
    elif bool(cfg.get("loop", true)):
        new_idx = elapsed_frames % frame_count
    else:
        new_idx = mini(elapsed_frames, frame_count - 1)
    return int(frames[new_idx])


func _draw_tile_quad(tex: Texture2D, dst: Rect2, src: Rect2, alpha: float, hflip: bool, vflip: bool) -> void:
    if hflip:
        src.position.x += src.size.x
        src.size.x = -src.size.x
    if vflip:
        src.position.y += src.size.y
        src.size.y = -src.size.y
    draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, alpha))


func _draw_collision_overlay(room: Dictionary, rows: int, cols: int, alpha_mul: float) -> void:
    var col_arr_v: Variant = room.get("collision")
    if typeof(col_arr_v) != TYPE_ARRAY:
        return
    var col_arr: Array = col_arr_v
    var cell_size := float(BLOCK_SIZE) * zoom
    for r in rows:
        if r >= col_arr.size():
            break
        var row_v: Variant = col_arr[r]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row: Array = row_v
        for c in cols:
            if c >= row.size():
                break
            var v := int(row[c])
            if v == 0:
                continue
            var tint := EnvTypes.block_type_color(v)
            tint.a *= alpha_mul
            var pos := _cell_to_screen(c, r)
            var cell_rect := Rect2(pos, Vector2(cell_size, cell_size))
            draw_rect(cell_rect, tint)
            if (v & 0xF) == EnvTypes.BT_SLOPE and editor != null and editor.has_method("get_slope_info_at"):
                var slope_info: Dictionary = editor.get_slope_info_at(r, c)
                _draw_slope_marker(cell_rect, slope_info, alpha_mul)

    # Draw spike profile labels on BT_SPIKE cells with non-default profiles.
    if editor != null and alpha_mul > 0.5:
        var bts_v: Variant = room.get("bts", [])
        if typeof(bts_v) == TYPE_ARRAY:
            var bts: Array = bts_v
            var font := ThemeDB.fallback_font
            for r in rows:
                if r >= col_arr.size() or r >= bts.size():
                    break
                var crow_v: Variant = col_arr[r]
                var brow_v: Variant = bts[r]
                if typeof(crow_v) != TYPE_ARRAY or typeof(brow_v) != TYPE_ARRAY:
                    continue
                var crow: Array = crow_v
                var brow: Array = brow_v
                for c in cols:
                    if c >= crow.size() or c >= brow.size():
                        break
                    if (int(crow[c]) & 0xF) != EnvTypes.BT_SPIKE:
                        continue
                    var bts_val := int(brow[c])
                    if bts_val == 0:
                        continue
                    var pos := _cell_to_screen(c, r)
                    var pname: String = str(editor.get_spike_profile_name(bts_val))
                    if pname.is_empty():
                        pname = "#%d" % bts_val
                    # Small label at bottom of cell
                    var label_pos := pos + Vector2(1, cell_size - 2)
                    draw_string(font, label_pos, pname,
                        HORIZONTAL_ALIGNMENT_LEFT, int(cell_size - 2),
                        clampi(int(cell_size * 0.45), 6, 11),
                        Color(1, 0.85, 0.3, 0.95 * alpha_mul))


func _draw_slope_marker(cell_rect: Rect2, slope_info: Dictionary, alpha_mul: float) -> void:
    if not bool(slope_info.get("valid", false)):
        return
    var left_y := float(int(slope_info.get("left_y", 16)))
    var right_y := float(int(slope_info.get("right_y", 16)))
    var pad := maxf(2.0, cell_rect.size.x * 0.12)
    var x0 := cell_rect.position.x + pad
    var x1 := cell_rect.end.x - pad
    var y0 := lerpf(cell_rect.position.y + pad, cell_rect.end.y - pad, clampf(left_y / 16.0, 0.0, 1.0))
    var y1 := lerpf(cell_rect.position.y + pad, cell_rect.end.y - pad, clampf(right_y / 16.0, 0.0, 1.0))
    var p0 := Vector2(x0, y0)
    var p1 := Vector2(x1, y1)
    var is_ceiling := bool(slope_info.get("vflip", false))
    var fill_poly := PackedVector2Array([p0, p1, Vector2(x1, cell_rect.position.y if is_ceiling else cell_rect.end.y), Vector2(x0, cell_rect.position.y if is_ceiling else cell_rect.end.y)])
    draw_colored_polygon(fill_poly, Color(0.6, 0.9, 1.0, 0.12 * alpha_mul))
    draw_line(p0, p1, Color(0.92, 0.98, 1.0, 0.95 * alpha_mul), maxf(1.5, zoom * 0.7))
    if zoom >= 2.5:
        var font := ThemeDB.fallback_font
        draw_string(font, cell_rect.position + Vector2(2.0, 10.0),
            "%d°" % int(slope_info.get("angle_deg", 0)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, clampi(int(cell_rect.size.y * 0.28), 7, 10),
            Color(0.92, 0.98, 1.0, 0.95 * alpha_mul))


func _draw_entities(room: Dictionary) -> void:
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    var font := ThemeDB.fallback_font
    var editing_entities: bool = editor.active_mode == EnvTypes.MODE_ENTITIES
    var alpha_mul: float = 1.0 if editing_entities else 0.85
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var x := float(e.get("x", 0)) * zoom
        var y := float(e.get("y", 0)) * zoom
        var type_id := str(e.get("type", "?"))
        var props_v: Variant = e.get("properties", {})
        var props: Dictionary = {}
        if typeof(props_v) == TYPE_DICTIONARY:
            props = props_v
        var center := cam_offset + Vector2(x, y)
        var col := EnvTypes.entity_color(type_id)
        col.a *= alpha_mul
        var label_col := Color(0.9, 0.95, 1.0, 0.9 * alpha_mul)
        var instance_id := str(props.get("instance_id", "")).strip_edges()
        if type_id == "trigger_volume":
            var zone_w := maxf(16.0, float(props.get("width", 16.0))) * zoom
            var zone_h := maxf(16.0, float(props.get("height", 16.0))) * zoom
            var rect := Rect2(center - Vector2(zone_w, zone_h) * 0.5, Vector2(zone_w, zone_h))
            draw_rect(rect, Color(col.r, col.g, col.b, 0.18 * alpha_mul))
            draw_rect(rect, col, false, maxf(1.5, zoom * 0.65))
            draw_line(rect.position, rect.end, Color(1, 1, 1, 0.35 * alpha_mul), 1.0)
            draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y),
                Color(1, 1, 1, 0.35 * alpha_mul), 1.0)
            var zone_fallback := instance_id if not instance_id.is_empty() else "zone"
            var zone_id := str(props.get("zone_id", zone_fallback)).strip_edges()
            draw_string(font, rect.position + Vector2(4, -4),
                zone_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
            if editing_entities and not instance_id.is_empty() and instance_id != zone_id:
                draw_string(font, rect.position + Vector2(4, rect.size.y + 12),
                    instance_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.86, 0.98, 0.82 * alpha_mul))
            continue
        var preview_tex: Texture2D = null
        if editor.has_method("get_entity_preview_texture"):
            preview_tex = editor.get_entity_preview_texture(type_id)
        var label_pos := center + Vector2(12.0, 4.0)
        if preview_tex != null:
            var preview_rect := _entity_preview_rect(center, preview_tex)
            draw_texture_rect(preview_tex, preview_rect, false, Color(1, 1, 1, alpha_mul))
            draw_rect(preview_rect.grow(1.0), Color(0, 0, 0, 0.55 * alpha_mul), false, 1.0)
            label_pos = Vector2(preview_rect.end.x + 4.0, preview_rect.position.y + 12.0)
        else:
            var radius := 6.0 * zoom * 0.5 + 4.0
            draw_circle(center, radius, col)
            draw_arc(center, radius, 0, TAU, 24, Color(1, 1, 1, 0.9 * alpha_mul), 1.5)
            label_pos = center + Vector2(radius + 4.0, 4.0)
        var label := EnvTypes.entity_label(type_id)
        if editor.has_method("get_entity_preview_label"):
            label = str(editor.get_entity_preview_label(type_id))
        draw_string(font, label_pos,
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
        if editing_entities and not instance_id.is_empty():
            draw_string(font, label_pos + Vector2(0.0, 11.0),
                instance_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.86, 0.98, 0.82 * alpha_mul))


func _entity_preview_rect(center: Vector2, tex: Texture2D) -> Rect2:
    var tex_size := tex.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return Rect2(center - Vector2(8.0, 16.0), Vector2(16.0, 16.0))
    var max_draw := maxf(24.0, 48.0 * zoom)
    var preview_scale := minf(max_draw / tex_size.x, max_draw / tex_size.y)
    preview_scale = minf(preview_scale, maxf(zoom, 1.0))
    var draw_size := tex_size * maxf(preview_scale, 0.01)
    return Rect2(Vector2(center.x - draw_size.x * 0.5, center.y - draw_size.y), draw_size)


func _draw_doors(room: Dictionary, rows: int, cols: int) -> void:
    var arr_v: Variant = room.get("doors", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var cell_size := float(BLOCK_SIZE) * zoom
    var font := ThemeDB.fallback_font
    var editing_doors: bool = editor.active_mode == EnvTypes.MODE_DOORS
    var fill_a: float = 0.55 if editing_doors else 0.35
    var stroke_a: float = 1.0 if editing_doors else 0.9
    # Build a set of known rooms so we can mark unresolved door targets
    # in-canvas rather than burying the warning in the console.
    var known_rooms: Dictionary = {}
    var addrs: Array = editor.get_room_addrs() if editor.has_method("get_room_addrs") else []
    for a in addrs:
        known_rooms[str(a)] = true
    for d_v in arr_v:
        if typeof(d_v) != TYPE_DICTIONARY:
            continue
        var d: Dictionary = d_v
        var cap_x := int(d.get("cap_x", 0))
        var cap_y := int(d.get("cap_y", 0))
        var direction := str(d.get("direction", "right"))
        var target := str(d.get("target_room", ""))
        var launches_to_space := bool(d.get("launch_to_space", false))
        if cap_x < 0 or cap_x >= cols or cap_y < 0 or cap_y >= rows:
            continue
        var target_valid: bool = launches_to_space or (not target.is_empty() and known_rooms.has(target))
        var fill_col: Color = Color(0.2, 0.85, 0.4, fill_a)
        var stroke_col: Color = Color(0.3, 1.0, 0.55, stroke_a)
        if launches_to_space:
            fill_col = Color(0.22, 0.62, 0.95, fill_a)
            stroke_col = Color(0.46, 0.82, 1.0, stroke_a)
        elif not target_valid:
            fill_col = Color(0.95, 0.35, 0.25, fill_a)
            stroke_col = Color(1.0, 0.5, 0.35, stroke_a)
        var pos := _cell_to_screen(cap_x, cap_y)
        var rect := Rect2(pos, Vector2(cell_size, cell_size))
        draw_rect(rect, fill_col)
        draw_rect(rect, stroke_col, false, 2.0)
        var tag := "→" if direction == "right" else ("←" if direction == "left" else ("↑" if direction == "up" else "↓"))
        var tag_color: Color = Color(0.2, 1, 0.5, 1)
        if launches_to_space:
            tag_color = Color(0.88, 0.96, 1.0, 1.0)
        elif not target_valid:
            tag_color = Color(1, 0.85, 0.75, 1)
        draw_string(font, pos + Vector2(4, cell_size * 0.5 + 4),
            tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tag_color)
        if editing_doors:
            var label: String = "LAUNCH TO SPACE" if launches_to_space else (target if not target.is_empty() else "(no target)")
            if not launches_to_space and not target_valid:
                label += "  [!]"
            var col: Color = Color(0.7, 1, 0.8, 0.95)
            if launches_to_space:
                col = Color(0.72, 0.9, 1.0, 0.95)
            elif not target_valid:
                col = Color(1.0, 0.75, 0.7, 0.95)
            draw_string(font, pos + Vector2(4, cell_size + 10),
                label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


func _draw_trigger_camera_preview() -> void:
    if editor == null or not editor.has_method("get_trigger_camera_preview"):
        return
    var preview: Array = editor.get_trigger_camera_preview()
    if preview.is_empty():
        return
    var font := ThemeDB.fallback_font
    for i in range(preview.size()):
        var item_v: Variant = preview[i]
        if typeof(item_v) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_v
        var world := Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
        var center := _world_to_screen(world)
        if item.has("from_x") and item.has("from_y"):
            var from_world := Vector2(float(item.get("from_x", 0.0)), float(item.get("from_y", 0.0)))
            draw_line(_world_to_screen(from_world), center, Color(0.4, 0.95, 1.0, 0.95), maxf(2.0, zoom * 0.9))
        var radius := maxf(6.0, zoom * 4.5)
        draw_circle(center, radius + 2.0, Color(0.08, 0.15, 0.18, 0.85))
        draw_circle(center, radius, Color(0.35, 0.95, 1.0, 0.92))
        draw_arc(center, radius + 7.0, 0.0, TAU, 36, Color(0.8, 1.0, 1.0, 0.55), 1.5)
        if str(item.get("mode", "")) == "zone":
            var zone_w := maxf(16.0, float(item.get("w", 16.0))) * zoom
            var zone_h := maxf(16.0, float(item.get("h", 16.0))) * zoom
            var rect := Rect2(center - Vector2(zone_w, zone_h) * 0.5, Vector2(zone_w, zone_h))
            draw_rect(rect, Color(0.25, 0.92, 1.0, 0.10))
            draw_rect(rect, Color(0.25, 0.92, 1.0, 0.85), false, maxf(1.5, zoom * 0.65))
        var label := "%d. %s" % [i + 1, str(item.get("label", item.get("mode", "camera")))]
        draw_string(font, center + Vector2(radius + 6.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.88, 0.98, 1.0, 0.95))


func _draw_grid(rows: int, cols: int) -> void:
    if zoom < 1.0:
        return
    var col_alpha := clampf((zoom - 1.0) * 0.2 + 0.08, 0.06, 0.22)
    var col := Color(0.35, 0.45, 0.6, col_alpha)
    for c in range(cols + 1):
        var x := cam_offset.x + float(c * BLOCK_SIZE) * zoom
        draw_line(Vector2(x, cam_offset.y), Vector2(x, cam_offset.y + float(rows * BLOCK_SIZE) * zoom), col, 1.0)
    for r in range(rows + 1):
        var y := cam_offset.y + float(r * BLOCK_SIZE) * zoom
        draw_line(Vector2(cam_offset.x, y), Vector2(cam_offset.x + float(cols * BLOCK_SIZE) * zoom, y), col, 1.0)


func _draw_anim_indicators(anims: Dictionary) -> void:
    # Draw a small film-strip icon on cells that have animation data.
    var cell_size := float(BLOCK_SIZE) * zoom
    var font := ThemeDB.fallback_font
    for key in anims.keys():
        var parts: PackedStringArray = str(key).split(",")
        if parts.size() < 2:
            continue
        var c := int(parts[0])
        var r := int(parts[1])
        var pos := _cell_to_screen(c, r)
        # Small teal triangle in top-right corner as animation indicator
        var tri_size := minf(cell_size * 0.35, 10.0)
        var p1 := pos + Vector2(cell_size - tri_size, 0)
        var p2 := pos + Vector2(cell_size, 0)
        var p3 := pos + Vector2(cell_size, tri_size)
        draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.2, 0.9, 0.9, 0.85))
        # Frame count label
        var anim_v: Variant = anims[key]
        if typeof(anim_v) == TYPE_DICTIONARY:
            var frames_v: Variant = (anim_v as Dictionary).get("frames", [])
            if typeof(frames_v) == TYPE_ARRAY:
                var fc := (frames_v as Array).size()
                if fc > 0:
                    draw_string(font, pos + Vector2(1, cell_size - 2),
                        "%df" % fc, HORIZONTAL_ALIGNMENT_LEFT,
                        int(cell_size - 2), clampi(int(cell_size * 0.4), 6, 10),
                        Color(0.2, 0.9, 0.9, 0.8))


func _draw_hover_marker(rows: int, cols: int) -> void:
    if _hover_cell.y < 0 or _hover_cell.y >= rows or _hover_cell.x < 0 or _hover_cell.x >= cols:
        return
    var pos := _cell_to_screen(_hover_cell.x, _hover_cell.y)
    var cell_size := float(BLOCK_SIZE) * zoom
    var rect := Rect2(pos, Vector2(cell_size, cell_size))
    draw_rect(rect, Color(1, 1, 1, 0.15))
    draw_rect(rect, Color(0.95, 0.95, 1.0, 0.85), false, 1.5)
