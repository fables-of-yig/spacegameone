extends Control

# Per-cell animation configuration modal. Opened when the user clicks a
# painted tile cell with the ANIMATE tool. Lets them define a frame sequence
# from the cell's tileset, set FPS, loop mode, and phase offset.
#
# On submit, fires `submitted(anim_data)` where anim_data is a dict:
#   { "frames": [int...], "fps": float, "loop": bool, "ping_pong": bool, "phase_offset": int }
# Or an empty dict if the user clears the animation (reverts to static).

signal submitted(anim_data: Dictionary)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
# MvTileValue is a class_name — access it directly, no preload needed.

const BOX_W: float = 760.0
const BOX_H: float = 640.0
const TILE_DRAW_SIZE: float = 32.0  # display size for each tile in the picker

var _tileset_tex: Texture2D = null
var _tileset_id: int = 0
var _grid_cols: int = 0  # atlas width in 16px columns
var _total_tiles: int = 0
var _base_idx: int = 0   # metatile idx of the cell being edited

var _selected_frames: Array = []  # metatile indices in sequence order
var _fps: float = 8.0
var _loop: bool = true
var _ping_pong: bool = false
var _phase_offset: int = 0

# UI elements
var _fps_edit: LineEdit = null
var _phase_edit: LineEdit = null
var _error_text: String = ""

# Hit rects
var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()
var _clear_rect: Rect2 = Rect2()
var _loop_rect: Rect2 = Rect2()
var _pingpong_rect: Rect2 = Rect2()
var _tile_rects: Array = []  # [{idx, rect}]
var _picker_rect: Rect2 = Rect2()
var _scroll_row: int = 0

# Animation preview
var _preview_timer: float = 0.0
var _preview_frame: int = 0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)
    _fps_edit = LineEdit.new()
    _fps_edit.placeholder_text = "FPS"
    _fps_edit.visible = false
    add_child(_fps_edit)
    _phase_edit = LineEdit.new()
    _phase_edit.placeholder_text = "Phase offset"
    _phase_edit.visible = false
    add_child(_phase_edit)


func _process(delta):
    if visible:
        # Advance preview animation
        if _selected_frames.size() > 1 and _fps > 0.0:
            _preview_timer += delta
            var frame_dur := 1.0 / _fps
            if _preview_timer >= frame_dur:
                _preview_timer -= frame_dur
                _preview_frame = (_preview_frame + 1) % _selected_frames.size()
        queue_redraw()


func open(tileset_tex: Texture2D, tileset_id: int, grid_cols: int, base_metatile_idx: int, existing_anim: Dictionary) -> void:
    _tileset_tex = tileset_tex
    _tileset_id = tileset_id
    _grid_cols = grid_cols
    _base_idx = base_metatile_idx

    if grid_cols > 0 and tileset_tex != null:
        @warning_ignore("integer_division")
        var rows := tileset_tex.get_height() / 16
        _total_tiles = grid_cols * rows
    else:
        _total_tiles = 0

    # Load existing animation data or default to just the base tile
    if not existing_anim.is_empty():
        var frames_v: Variant = existing_anim.get("frames", [])
        _selected_frames = []
        if typeof(frames_v) == TYPE_ARRAY:
            for f in frames_v:
                _selected_frames.append(int(f))
        _fps = float(existing_anim.get("fps", 8.0))
        _loop = bool(existing_anim.get("loop", true))
        _ping_pong = bool(existing_anim.get("ping_pong", false))
        _phase_offset = int(existing_anim.get("phase_offset", 0))
    else:
        _selected_frames = [base_metatile_idx]
        _fps = 8.0
        _loop = true
        _ping_pong = false
        _phase_offset = 0

    _preview_frame = 0
    _preview_timer = 0.0
    _error_text = ""
    @warning_ignore("integer_division")
    _scroll_row = maxi(0, int(_base_idx / maxi(1, _grid_cols)) - 2)

    _fps_edit.text = "%.1f" % _fps
    _phase_edit.text = str(_phase_offset)
    _fps_edit.visible = true
    _phase_edit.visible = true
    visible = true
    _layout_fields()
    queue_redraw()


func close() -> void:
    visible = false
    _fps_edit.visible = false
    _phase_edit.visible = false


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _layout_fields() -> void:
    var box := _box_rect()
    _fps_edit.position = Vector2(box.position.x + 72, box.position.y + BOX_H - 108)
    _fps_edit.size = Vector2(60, 24)
    _phase_edit.position = Vector2(box.position.x + 240, box.position.y + BOX_H - 108)
    _phase_edit.size = Vector2(60, 24)


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_fields()


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP and _picker_rect.has_point(mb.position):
            _scroll_picker(-1)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _picker_rect.has_point(mb.position):
            _scroll_picker(1)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            var pos := mb.position
            if _ok_rect.has_point(pos):
                _confirm()
                accept_event()
                return
            if _cancel_rect.has_point(pos):
                _do_cancel()
                accept_event()
                return
            if _clear_rect.has_point(pos):
                _selected_frames.clear()
                _preview_frame = 0
                accept_event()
                return
            if _loop_rect.has_point(pos):
                _loop = not _loop
                accept_event()
                return
            if _pingpong_rect.has_point(pos):
                _ping_pong = not _ping_pong
                accept_event()
                return
            # Tile clicks — toggle frame in/out of sequence
            for entry in _tile_rects:
                if (entry["rect"] as Rect2).has_point(pos):
                    var idx: int = int(entry["idx"])
                    var found := _selected_frames.find(idx)
                    if found >= 0:
                        _selected_frames.remove_at(found)
                    else:
                        _selected_frames.append(idx)
                    _preview_frame = 0
                    accept_event()
                    return
            # Click outside box = cancel
            if not _box_rect().has_point(pos):
                _do_cancel()
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _do_cancel()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_PAGEUP:
            _scroll_picker(-4)
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_PAGEDOWN:
            _scroll_picker(4)
            get_viewport().set_input_as_handled()


func _scroll_picker(delta_rows: int) -> void:
    var metrics := _picker_metrics()
    var max_scroll: int = int(metrics.get("max_scroll_rows", 0))
    _scroll_row = clampi(_scroll_row + delta_rows, 0, max_scroll)


func _picker_metrics() -> Dictionary:
    var picker_w := BOX_W - 32.0
    var picker_h := 344.0
    var draw_size := TILE_DRAW_SIZE
    if _grid_cols > 0:
        draw_size = floor((picker_w - 8.0) / float(_grid_cols))
    draw_size = clampf(draw_size, 16.0, TILE_DRAW_SIZE)
    @warning_ignore("integer_division")
    var total_rows := (_total_tiles + maxi(1, _grid_cols) - 1) / maxi(1, _grid_cols)
    var visible_rows := maxi(1, int(floor(picker_h / draw_size)))
    var max_scroll_rows := maxi(0, total_rows - visible_rows)
    return {
        "picker_w": picker_w,
        "picker_h": picker_h,
        "draw_size": draw_size,
        "total_rows": total_rows,
        "visible_rows": visible_rows,
        "max_scroll_rows": max_scroll_rows,
    }


func _confirm() -> void:
    if not _fps_edit.text.strip_edges().is_valid_float():
        _error_text = "FPS must be a number."
        queue_redraw()
        return
    if not _phase_edit.text.strip_edges().is_valid_int():
        _error_text = "Phase offset must be a whole number."
        queue_redraw()
        return
    _fps = float(_fps_edit.text)
    _fps = clampf(_fps, 0.5, 30.0)
    _phase_offset = int(_phase_edit.text)
    _error_text = ""

    var result: Dictionary = {}
    if _selected_frames.size() >= 2:
        result = {
            "frames": _selected_frames.duplicate(),
            "fps": _fps,
            "loop": _loop,
            "ping_pong": _ping_pong,
            "phase_offset": _phase_offset,
        }
    # Empty dict = clear animation (revert to static)
    close()
    submitted.emit(result)


func _do_cancel() -> void:
    close()
    cancelled.emit()


func _draw():
    if not visible:
        return

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
    var box := _box_rect()
    UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()
    var bx := box.position.x
    var by := box.position.y

    # Title
    draw_string(font, Vector2(bx + 24, by + 28),
        "Tile Animation", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(bx + 24, by + 46),
        "Click tiles to add/remove frames. Order = click order.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if not _error_text.is_empty():
        draw_string(font, Vector2(bx + 24, by + BOX_H - 54),
            _error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.4, 1.0))

    # Tile picker grid (scrollable region showing the tileset)
    _tile_rects.clear()
    var picker_x := bx + 16.0
    var picker_y := by + 58.0
    var metrics := _picker_metrics()
    var picker_w: float = metrics["picker_w"]
    var picker_h: float = metrics["picker_h"]
    var draw_size: float = metrics["draw_size"]
    var total_rows: int = metrics["total_rows"]
    var row_count: int = metrics["visible_rows"]
    var max_scroll_rows: int = metrics["max_scroll_rows"]
    _scroll_row = clampi(_scroll_row, 0, max_scroll_rows)
    _picker_rect = Rect2(picker_x, picker_y, picker_w, picker_h)
    draw_rect(Rect2(picker_x, picker_y, picker_w, picker_h), Color(0.15, 0.18, 0.25, 1.0))
    draw_rect(_picker_rect, Color(0.32, 0.42, 0.56, 0.9), false, 1.5)

    if _tileset_tex != null and _grid_cols > 0:
        for tile_r in row_count:
            var atlas_row := _scroll_row + tile_r
            if atlas_row >= total_rows:
                break
            for tc in _grid_cols:
                var idx := atlas_row * _grid_cols + tc
                if idx >= _total_tiles:
                    break
                var dx := picker_x + tc * draw_size
                var dy := picker_y + tile_r * draw_size
                var dst_rect := Rect2(dx, dy, draw_size, draw_size)
                var src_x := (idx % _grid_cols) * 16
                @warning_ignore("integer_division")
                var src_y := (idx / _grid_cols) * 16
                var src_rect := Rect2(src_x, src_y, 16, 16)
                draw_texture_rect_region(_tileset_tex, dst_rect, src_rect)

                _tile_rects.append({"idx": idx, "rect": dst_rect})

                # Highlight if in selected frames
                var frame_pos := _selected_frames.find(idx)
                if frame_pos >= 0:
                    draw_rect(dst_rect, Color(0.2, 0.8, 1.0, 0.35))
                    draw_rect(dst_rect, Color(0.3, 0.9, 1.0, 0.9), false, 2.0)
                    # Frame number
                    draw_string(font, Vector2(dx + 2, dy + 12),
                        str(frame_pos + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                        Color(1, 1, 0.3, 1))

                # Highlight base tile
                if idx == _base_idx:
                    draw_rect(Rect2(dx + 1, dy + 1, draw_size - 2, draw_size - 2),
                        Color(1, 0.8, 0.2, 0.6), false, 1.5)

        if total_rows > row_count:
            var track_rect := Rect2(picker_x + picker_w - 10.0, picker_y + 2.0, 8.0, picker_h - 4.0)
            draw_rect(track_rect, Color(0.08, 0.1, 0.14, 0.95))
            var thumb_h := maxf(18.0, track_rect.size.y * (float(row_count) / float(total_rows)))
            var travel := maxf(1.0, track_rect.size.y - thumb_h)
            var thumb_y := track_rect.position.y + travel * (float(_scroll_row) / float(maxi(1, max_scroll_rows)))
            draw_rect(Rect2(track_rect.position.x + 1.0, thumb_y, track_rect.size.x - 2.0, thumb_h),
                Color(0.38, 0.62, 0.88, 0.95))
        draw_string(font, Vector2(picker_x + 8.0, picker_y + picker_h + 16.0),
            "Mouse wheel / PgUp / PgDn scrolls the tileset. Atlas rows %d-%d of %d." % [
                _scroll_row + 1,
                mini(total_rows, _scroll_row + row_count),
                total_rows],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    # Animation preview
    var prev_x := bx + 16.0
    var prev_y := by + picker_h + 76.0
    draw_string(font, Vector2(prev_x, prev_y),
        "Preview:", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    if _selected_frames.size() > 0 and _tileset_tex != null and _grid_cols > 0:
        var frame_idx: int = _selected_frames[clampi(_preview_frame, 0, _selected_frames.size() - 1)]
        var prev_dst := Rect2(prev_x + 60, prev_y - 14, 48, 48)
        var psrc_x := (frame_idx % _grid_cols) * 16
        @warning_ignore("integer_division")
        var psrc_y := (frame_idx / _grid_cols) * 16
        draw_texture_rect_region(_tileset_tex, prev_dst, Rect2(psrc_x, psrc_y, 16, 16))

    # Frame sequence display
    var seq_str := ""
    for i in _selected_frames.size():
        if i > 0:
            seq_str += " > "
        seq_str += str(_selected_frames[i])
    if seq_str.is_empty():
        seq_str = "(no frames — will clear animation)"
    draw_string(font, Vector2(prev_x + 120, prev_y + 4),
        seq_str, HORIZONTAL_ALIGNMENT_LEFT, int(BOX_W - 160), 10, UIPanels.TEXT_PANEL_DIM)

    # Controls row
    var ctrl_y := by + BOX_H - 114
    draw_string(font, Vector2(bx + 16, ctrl_y + 16), "FPS:",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(bx + 160, ctrl_y + 16), "Phase offset:",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)

    # Loop toggle
    _loop_rect = Rect2(bx + 300, ctrl_y, 60, 22)
    var loop_col := Color(0.3, 0.75, 0.45, 0.9) if _loop else Color(0.4, 0.4, 0.5, 0.5)
    draw_rect(_loop_rect, loop_col)
    draw_string(font, _loop_rect.position + Vector2(8, 15),
        "LOOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(1, 1, 1, 1) if _loop else Color(0.7, 0.7, 0.7, 1))

    # Ping-pong toggle
    _pingpong_rect = Rect2(bx + 370, ctrl_y, 80, 22)
    var pp_col := Color(0.3, 0.55, 0.75, 0.9) if _ping_pong else Color(0.4, 0.4, 0.5, 0.5)
    draw_rect(_pingpong_rect, pp_col)
    draw_string(font, _pingpong_rect.position + Vector2(4, 15),
        "PINGPONG", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(1, 1, 1, 1) if _ping_pong else Color(0.7, 0.7, 0.7, 1))

    # Buttons
    var btn_h: float = 28.0
    var btn_y := by + BOX_H - btn_h - 16.0

    _ok_rect = Rect2(bx + BOX_W - 88, btn_y, 72, btn_h)
    UIPanels.draw_button_bg(self, _ok_rect, _ok_rect.has_point(mouse_pos), Color(0.4, 0.9, 0.55, 1.0))
    draw_string(font, _ok_rect.position + Vector2(24, 18), "OK",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.95, 1))

    _cancel_rect = Rect2(_ok_rect.position.x - 88, btn_y, 80, btn_h)
    UIPanels.draw_button_bg(self, _cancel_rect, _cancel_rect.has_point(mouse_pos), Color(0.9, 0.45, 0.4, 1.0))
    draw_string(font, _cancel_rect.position + Vector2(12, 18), "CANCEL",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.95, 1))

    _clear_rect = Rect2(bx + 16, btn_y, 90, btn_h)
    UIPanels.draw_button_bg(self, _clear_rect, _clear_rect.has_point(mouse_pos), Color(0.7, 0.5, 0.3, 1.0))
    draw_string(font, _clear_rect.position + Vector2(4, 18), "CLEAR ANIM",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 1))
