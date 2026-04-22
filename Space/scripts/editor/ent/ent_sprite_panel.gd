extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EntIO = preload("res://Space/scripts/editor/ent/ent_io.gd")

# Center/right pane that browses the selected entity's sprite set.
# Shows a large preview of the currently-selected PNG on top, with a
# scrollable list of PNG filenames beneath it. A header row displays the
# active sprite_set and opens the set picker on click.
#
# Textures are cached keyed by "<sprite_set>/<filename>" so we don't
# reload PNGs every frame. The cache is invalidated whenever the active
# sprite_set changes.

var editor: Node = null

var _current_entity_id: String = ""
var _current_set: String = ""
var _pngs: Array = []
var _selected_png: String = ""
var _tex_cache: Dictionary = {}
var _png_rects: Array = []  # [{filename, rect}]

var _header_rect: Rect2 = Rect2()
var _scroll: float = 0.0
var _list_y0: float = 0.0
var _list_h: float = 0.0
var _content_h: float = 0.0

# Playback state. _frame_index steps forward based on the active pose's
# fps; reset whenever the selected PNG changes.
var _frame_index: int = 0
var _frame_time: float = 0.0
var _playing: bool = true
var _play_rect: Rect2 = Rect2()

var _pose_field_rects: Array = []  # [{field, rect}]

const HEADER_H: float = 44.0
const PREVIEW_H: float = 230.0
const POSE_ROW_H: float = 56.0
const ROW_H: float = 22.0
const PAD: float = 12.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    clip_contents = true
    set_process(true)


func _process(delta):
    if _playing and _selected_png != "":
        _advance_animation(delta)
    queue_redraw()


func _advance_animation(delta: float) -> void:
    if editor == null:
        return
    var frames := _frame_count_for_selected()
    if frames <= 1:
        _frame_index = 0
        _frame_time = 0.0
        return
    var pose: Dictionary = editor.get_pose_for(_current_set, _selected_png)
    var fps: float = 8.0
    if pose.has("fps"):
        fps = float(pose["fps"])
    if fps <= 0.0:
        fps = 8.0
    var frame_dur := 1.0 / fps
    _frame_time += delta
    while _frame_time >= frame_dur:
        _frame_time -= frame_dur
        _frame_index += 1
        if _frame_index >= frames:
            var loop_from: int = 0
            if pose.has("loop_from"):
                loop_from = int(pose["loop_from"])
            loop_from = clamp(loop_from, 0, frames - 1)
            _frame_index = loop_from


func _frame_count_for_selected() -> int:
    if editor == null or _selected_png == "" or _current_set == "":
        return 1
    var pose: Dictionary = editor.get_pose_for(_current_set, _selected_png)
    if pose.has("frames"):
        return max(1, int(pose["frames"]))
    var tex := _tex_for(_selected_png)
    return EntIO.autodetect_frame_count(tex)


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 32.0, max(0.0, _content_h - _list_h))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 32.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _header_rect.has_point(mb.position):
                editor.request_pick_sprite_set()
                accept_event()
                return
            if _play_rect.has_point(mb.position):
                _playing = not _playing
                accept_event()
                return
            for f_row in _pose_field_rects:
                if (f_row["rect"] as Rect2).has_point(mb.position):
                    _open_pose_field_editor(str(f_row["field"]))
                    accept_event()
                    return
            for row in _png_rects:
                if (row["rect"] as Rect2).has_point(mb.position):
                    _selected_png = str(row["filename"])
                    _frame_index = 0
                    _frame_time = 0.0
                    accept_event()
                    return


func _refresh_for_entity(e: Dictionary) -> void:
    var eid := str(e.get("id", ""))
    var set_rel := str(e.get("sprite_set", ""))
    if eid != _current_entity_id or set_rel != _current_set:
        _current_entity_id = eid
        if set_rel != _current_set:
            _tex_cache.clear()
            _scroll = 0.0
            _frame_index = 0
            _frame_time = 0.0
        _current_set = set_rel
        if set_rel == "":
            _pngs = []
            _selected_png = ""
        else:
            _pngs = EntIO.list_sprite_pngs(editor.pack_id, set_rel)
            if _selected_png == "" or not _pngs.has(_selected_png):
                _selected_png = str(_pngs[0]) if not _pngs.is_empty() else ""
                _frame_index = 0
                _frame_time = 0.0


func _open_pose_field_editor(field: String) -> void:
    if editor == null or _current_set == "" or _selected_png == "":
        return
    var title := "Edit %s" % field
    var prompt := _prompt_for_pose_field(field)
    editor.request_edit_pose_field(_current_set, _selected_png, field, title, prompt)


func _prompt_for_pose_field(field: String) -> String:
    if field == "frames":
        return "Override auto-detected frame count. Positive integer."
    if field == "fps":
        return "Playback frame rate (frames per second). e.g. 8"
    if field == "loop_from":
        return "Frame index to loop back to when the animation ends."
    if field == "y_offset":
        return "Vertical draw offset in pixels (for foot alignment)."
    return ""


func _tex_for(filename: String) -> Texture2D:
    if filename == "" or _current_set == "":
        return null
    var key := _current_set + "/" + filename
    if _tex_cache.has(key):
        return _tex_cache[key]
    var tex := EntIO.load_sprite_png(editor.pack_id, _current_set, filename)
    if tex != null:
        _tex_cache[key] = tex
    return tex


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var e: Dictionary = editor.get_selected_entity()
    if e.is_empty():
        _png_rects.clear()
        draw_string(font, Vector2(PAD + 6, 36),
            "No entity selected.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            UIPanels.TEXT_PANEL)
        return

    _refresh_for_entity(e)

    _header_rect = Rect2(PAD, 10, size.x - PAD * 2.0, HEADER_H - 4.0)
    var header_hover := _header_rect.has_point(mouse_pos)
    var header_bg: Color
    if header_hover:
        header_bg = Color(0.22, 0.32, 0.48, 0.9)
    else:
        header_bg = Color(0.12, 0.17, 0.24, 0.85)
    draw_rect(_header_rect, header_bg)
    draw_rect(_header_rect, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    draw_string(font, _header_rect.position + Vector2(12, 14),
        "SPRITE SET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.72, 0.88, 1))
    var set_label := _current_set if _current_set != "" else "(none — click to pick)"
    var label_col := Color(1, 1, 1, 1) if header_hover else Color(0.85, 0.92, 1.0, 1)
    draw_string(font, _header_rect.position + Vector2(12, 32),
        set_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)
    draw_string(font, Vector2(_header_rect.position.x + _header_rect.size.x - 22,
        _header_rect.position.y + 26),
        "▾", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
        Color(0.9, 0.95, 1, 1))
    if header_hover:
        EditorTooltip.show_text("Click to change this entity's sprite set. Opens a picker that scans Sprites/ in both the user pack and the shipped pack.")

    var preview_rect := Rect2(PAD, HEADER_H + 16, size.x - PAD * 2.0, PREVIEW_H)
    draw_rect(preview_rect, Color(0.05, 0.08, 0.12, 0.95))
    draw_rect(preview_rect, Color(0.25, 0.4, 0.6, 0.9), false, 1.0)

    if _selected_png == "":
        _play_rect = Rect2()
        var hint := "No PNG selected."
        if _current_set == "":
            hint = "Pick a sprite set above to browse PNGs."
        elif _pngs.is_empty():
            hint = "No PNGs found in sprite set."
        draw_string(font, preview_rect.position + Vector2(12, 22),
            hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.6, 0.72, 0.88, 1))
    else:
        var tex := _tex_for(_selected_png)
        if tex != null:
            var frames := _frame_count_for_selected()
            _draw_preview_texture(preview_rect, tex, frames, _frame_index)
            draw_string(font, Vector2(preview_rect.position.x + 8,
                preview_rect.position.y + preview_rect.size.y - 8),
                "%s   %dx%d   frame %d/%d" % [_selected_png,
                    tex.get_width(), tex.get_height(),
                    _frame_index + 1, max(1, frames)],
                HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(0.7, 0.82, 0.95, 1))

            # Play / pause toggle in the top-right of the preview.
            var play_w: float = 70.0
            var play_h: float = 22.0
            _play_rect = Rect2(preview_rect.position.x + preview_rect.size.x - play_w - 8,
                preview_rect.position.y + 6, play_w, play_h)
            var play_hover := _play_rect.has_point(mouse_pos)
            var play_bg: Color
            if play_hover:
                play_bg = Color(0.25, 0.45, 0.75, 0.9)
            else:
                play_bg = Color(0.14, 0.22, 0.34, 0.8)
            draw_rect(_play_rect, play_bg)
            draw_rect(_play_rect, Color(0.4, 0.6, 0.85, 0.9), false, 1.0)
            var play_label := "▶ PLAY" if not _playing else "❚❚ PAUSE"
            draw_string(font, _play_rect.position + Vector2(8, 16),
                play_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
                Color(0.95, 0.98, 1.0, 1))
            if play_hover:
                EditorTooltip.show_text("Toggle animation playback. Frame rate is taken from the pose's FPS field below — adjust it to preview at different speeds.")
        else:
            _play_rect = Rect2()
            draw_string(font, preview_rect.position + Vector2(12, 22),
                "Failed to load %s" % _selected_png, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
                Color(1, 0.5, 0.5, 1))

    var pose_row_y: float = HEADER_H + 16 + PREVIEW_H + 10
    _draw_pose_field_row(font, mouse_pos, pose_row_y)

    _list_y0 = pose_row_y + POSE_ROW_H + 10
    _list_h = size.y - _list_y0 - PAD
    if _list_h < 30.0:
        _list_h = 30.0

    var list_rect := Rect2(PAD, _list_y0, size.x - PAD * 2.0, _list_h)
    draw_rect(list_rect, Color(0.08, 0.12, 0.18, 0.9))
    draw_rect(list_rect, Color(0.25, 0.4, 0.6, 0.8), false, 1.0)

    _png_rects.clear()
    _content_h = float(_pngs.size()) * ROW_H + 8.0
    if _scroll > max(0.0, _content_h - _list_h):
        _scroll = max(0.0, _content_h - _list_h)

    var row_y0: float = _list_y0 + 4.0 - _scroll
    for i in _pngs.size():
        var fn := str(_pngs[i])
        var row_rect := Rect2(list_rect.position.x + 4.0,
            row_y0 + float(i) * ROW_H,
            list_rect.size.x - 8.0, ROW_H - 2.0)

        _png_rects.append({
            "filename": fn,
            "rect": row_rect,
        })

        if row_rect.position.y + row_rect.size.y < _list_y0:
            continue
        if row_rect.position.y > _list_y0 + _list_h:
            continue

        var is_sel := fn == _selected_png
        var row_hover := row_rect.has_point(mouse_pos)
        var bg: Color
        if is_sel:
            bg = Color(0.3, 0.5, 0.8, 0.9)
        elif row_hover:
            bg = Color(0.2, 0.3, 0.45, 0.85)
        else:
            bg = Color(0.12, 0.16, 0.22, 0.0)
        draw_rect(row_rect, bg)

        var text_col: Color
        if is_sel:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.78, 0.88, 0.98, 1)
        draw_string(font, row_rect.position + Vector2(8, 14),
            fn, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_col)
        if row_hover:
            EditorTooltip.show_text("Sprite \"%s\". Click to load it into the preview above and edit its pose metadata. Each PNG is one named pose (e.g. idle, walk, attack)." % fn)

    if _pngs.is_empty():
        draw_string(font, list_rect.position + Vector2(10, 20),
            "No PNGs in this sprite set.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.55, 0.68, 0.85, 1))


func _draw_preview_texture(rect: Rect2, tex: Texture2D, frames: int, frame_idx: int) -> void:
    var tw_total := float(tex.get_width())
    var th := float(tex.get_height())
    if tw_total <= 0.0 or th <= 0.0:
        return
    var frame_count: float = float(max(1, frames))
    var fw := tw_total / frame_count
    var idx: int = clamp(frame_idx, 0, max(0, frames - 1))
    var src_rect := Rect2(float(idx) * fw, 0.0, fw, th)

    var inset: float = 10.0
    var max_w: float = rect.size.x - inset * 2.0
    var max_h: float = rect.size.y - inset * 2.0 - 14.0
    var scale_fit: float = min(max_w / fw, max_h / th)
    # Snap to integer scale >=1 so pixel art stays crisp.
    if scale_fit > 1.0:
        scale_fit = min(scale_fit, 6.0)
        scale_fit = floor(scale_fit)
        if scale_fit < 1.0:
            scale_fit = 1.0
    var dw: float = fw * scale_fit
    var dh: float = th * scale_fit
    var dx: float = rect.position.x + (rect.size.x - dw) * 0.5
    var dy: float = rect.position.y + (rect.size.y - dh - 14.0) * 0.5 + 2.0
    var dst := Rect2(dx, dy, dw, dh)
    draw_texture_rect_region(tex, dst, src_rect)
    draw_rect(dst, Color(0.45, 0.65, 0.9, 0.7), false, 1.0)


func _draw_pose_field_row(font: Font, mouse_pos: Vector2, y: float) -> void:
    _pose_field_rects.clear()
    var row_rect := Rect2(PAD, y, size.x - PAD * 2.0, POSE_ROW_H)
    draw_rect(row_rect, Color(0.08, 0.12, 0.18, 0.85))
    draw_rect(row_rect, Color(0.3, 0.45, 0.65, 0.8), false, 1.0)

    var label_col := Color(0.6, 0.72, 0.88, 1)
    draw_string(font, row_rect.position + Vector2(8, 14),
        "POSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)

    if _selected_png == "" or _current_set == "":
        draw_string(font, row_rect.position + Vector2(8, 36),
            "Select a PNG to edit its pose.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.5, 0.62, 0.78, 1))
        return

    var pose: Dictionary = editor.get_pose_for(_current_set, _selected_png)
    var tex := _tex_for(_selected_png)
    var auto_frames: int = EntIO.autodetect_frame_count(tex)

    var fields := [
        {"id": "frames", "label": "FRAMES"},
        {"id": "fps", "label": "FPS"},
        {"id": "loop_from", "label": "LOOP"},
        {"id": "y_offset", "label": "Y OFF"},
    ]

    var inner_x: float = row_rect.position.x + 50.0
    var inner_w: float = row_rect.size.x - 60.0
    var field_w: float = inner_w / float(fields.size())
    for i in fields.size():
        var f: Dictionary = fields[i]
        var field_id := str(f["id"])
        var flabel := str(f["label"])
        var rect := Rect2(inner_x + float(i) * field_w + 4.0,
            row_rect.position.y + 6.0,
            field_w - 8.0, POSE_ROW_H - 12.0)

        var hover := rect.has_point(mouse_pos)
        var bg: Color
        if hover:
            bg = Color(0.22, 0.32, 0.48, 0.92)
        else:
            bg = Color(0.12, 0.17, 0.24, 0.85)
        draw_rect(rect, bg)
        draw_rect(rect, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

        draw_string(font, rect.position + Vector2(8, 14),
            flabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)

        var value_str: String
        var is_auto: bool = false
        if pose.has(field_id):
            value_str = str(pose[field_id])
        else:
            if field_id == "frames":
                value_str = "%d (auto)" % auto_frames
                is_auto = true
            elif field_id == "fps":
                value_str = "8 (default)"
                is_auto = true
            elif field_id == "loop_from":
                value_str = "0 (default)"
                is_auto = true
            elif field_id == "y_offset":
                value_str = "0 (default)"
                is_auto = true
            else:
                value_str = "—"
        var vcol: Color
        if is_auto:
            vcol = Color(0.55, 0.68, 0.85, 1)
        elif hover:
            vcol = Color(1, 1, 1, 1)
        else:
            vcol = Color(0.85, 0.92, 1.0, 1)
        draw_string(font, rect.position + Vector2(8, 34),
            value_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vcol)

        _pose_field_rects.append({
            "field": field_id,
            "rect": rect,
        })
        if hover:
            EditorTooltip.show_text(_tooltip_for_pose_field(field_id, auto_frames))


func _tooltip_for_pose_field(field_id: String, auto_frames: int) -> String:
    if field_id == "frames":
        return "Number of horizontal frames in this PNG. Auto-detected as %d (assumes square frames). Click to override if the autodetect is wrong." % auto_frames
    if field_id == "fps":
        return "Animation playback frame rate (frames per second). Default is 8. Used both by the editor preview and the runtime."
    if field_id == "loop_from":
        return "When the animation reaches the end, it jumps back to this frame index. 0 = restart from the beginning. Useful for animations with a one-shot intro followed by a looping cycle."
    if field_id == "y_offset":
        return "Vertical draw offset in pixels. Use this to align the sprite's feet to the entity's collision origin without re-cropping the PNG."
    return "Pose field. Click to edit."
