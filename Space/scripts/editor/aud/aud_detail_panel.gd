extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Right pane for the audio editor. Shows the selected clip's text
# fields (id / file / tags) plus a timeline block with the real clip
# duration and two draggable trim markers (start / end). A playback
# cursor sweeps across while the preview is running.
#
# Trim is non-destructive: the underlying .ogg is never re-encoded.
# end_sec = -1 is the "play to natural end" sentinel and is mapped to
# the full duration for display/drag purposes.

var editor: Node = null

const FIELD_H: float = 44.0
const FIELD_PAD_X: float = 18.0
const HEADER_H: float = 52.0
const PLAY_H: float = 44.0
const TIMELINE_H: float = 102.0
const MARKER_HIT_W: float = 16.0
const BAR_INSET_X: float = 10.0
const COMMIT_H: float = 44.0

var _field_rects: Array = []  # [{field, rect}]
var _play_rect: Rect2 = Rect2()
var _stop_rect: Rect2 = Rect2()
var _bar_rect: Rect2 = Rect2()
var _start_marker_hit: Rect2 = Rect2()
var _end_marker_hit: Rect2 = Rect2()
var _save_clip_rect: Rect2 = Rect2()
var _discard_rect: Rect2 = Rect2()

var _drag_kind: String = ""  # "", "start", "end"
var _drag_duration: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()
    if _drag_kind != "":
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            _drag_kind = ""
        else:
            _apply_drag(get_local_mouse_position())


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _save_clip_rect.size.x > 0.0 and _save_clip_rect.has_point(event.position):
            editor.save_pending_clip()
            accept_event()
            return
        if _discard_rect.size.x > 0.0 and _discard_rect.has_point(event.position):
            editor.discard_pending_clip()
            accept_event()
            return
        if _play_rect.has_point(event.position):
            editor.play_selected_clip()
            accept_event()
            return
        if _stop_rect.has_point(event.position):
            editor.stop_preview()
            accept_event()
            return
        if _bar_rect.size.x > 0.0 and _drag_duration > 0.0:
            if _start_marker_hit.has_point(event.position):
                _drag_kind = "start"
                _apply_drag(event.position)
                accept_event()
                return
            if _end_marker_hit.has_point(event.position):
                _drag_kind = "end"
                _apply_drag(event.position)
                accept_event()
                return
        for row in _field_rects:
            if (row["rect"] as Rect2).has_point(event.position):
                var field := str(row["field"])
                var title := "Edit %s" % field
                var prompt := _prompt_for(field)
                editor.request_edit_clip_field(field, title, prompt)
                accept_event()
                return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    _field_rects.clear()
    _play_rect = Rect2()
    _stop_rect = Rect2()
    _bar_rect = Rect2()
    _start_marker_hit = Rect2()
    _end_marker_hit = Rect2()
    _save_clip_rect = Rect2()
    _discard_rect = Rect2()

    var c: Dictionary = editor.get_selected_clip()
    if c.is_empty():
        draw_string(font, Vector2(FIELD_PAD_X + 6, 40),
            "No clip selected.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            UIPanels.TEXT_PANEL)
        draw_string(font, Vector2(FIELD_PAD_X + 6, 62),
            "Select one on the left, or click + IMPORT OGG.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL_DIM)
        return

    var pending: bool = editor.is_pending()
    var header: String
    if pending:
        var remaining: int = editor.get_pending_queue_remaining()
        if remaining > 0:
            header = "NEW CLIP  %s   (+%d more queued)" % [str(c.get("id", "")), remaining]
        else:
            header = "NEW CLIP  %s" % str(c.get("id", ""))
    else:
        header = "CLIP  %s" % str(c.get("id", ""))
    var header_col := Color(1.0, 0.85, 0.5, 1) if pending else UIPanels.TEXT_PANEL
    draw_string(font, Vector2(FIELD_PAD_X + 4, 34),
        header, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, header_col)

    var y: float = HEADER_H + 8.0
    y = _draw_field(font, mouse_pos, c, "id", "ID", y)
    y = _draw_field(font, mouse_pos, c, "file", "File (relative)", y)

    var file_rel := str(c.get("file", ""))
    var dur: float = editor.get_clip_duration(file_rel) if file_rel != "" else 0.0
    _drag_duration = dur
    y = _draw_timeline(font, mouse_pos, c, dur, y)

    y = _draw_field(font, mouse_pos, c, "tags", "Tags (comma separated)", y)

    y += 12.0
    if pending:
        _draw_commit_row(font, mouse_pos, y)
        y += COMMIT_H + 8.0
    _draw_play_strip(font, mouse_pos, y)
    y += PLAY_H + 8.0

    var hint: String
    if pending:
        hint = "Trim the clip, then SAVE CLIP to commit it to the registry."
    else:
        hint = "Drag the green/red markers to trim. PLAY respects trim marks."
    draw_string(font, Vector2(FIELD_PAD_X + 4, y + 12),
        hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)


func _draw_field(font: Font, mouse_pos: Vector2, c: Dictionary,
        field: String, label: String, y: float) -> float:
    var rect := Rect2(FIELD_PAD_X, y, size.x - FIELD_PAD_X * 2.0, FIELD_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.32, 0.48, 0.9)
    else:
        bg = Color(0.12, 0.17, 0.24, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    draw_string(font, rect.position + Vector2(12, 16),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.6, 0.72, 0.88, 1))

    var value := _display_value(c, field)
    var value_col := Color(0.95, 0.97, 1.0, 1) if hover else Color(0.82, 0.9, 1.0, 1)
    if value == "":
        value = "(empty)"
        value_col = Color(0.5, 0.6, 0.78, 1)

    var max_chars: int = int((rect.size.x - 24.0) / 6.0)
    if value.length() > max_chars and max_chars > 3:
        value = value.substr(0, max_chars - 3) + "..."
    draw_string(font, rect.position + Vector2(12, 36),
        value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, value_col)

    _field_rects.append({
        "field": field,
        "rect": rect,
    })

    if hover:
        EditorTooltip.show_text(_tooltip_for(field))

    return y + FIELD_H + 6.0


func _draw_timeline(font: Font, mouse_pos: Vector2, c: Dictionary,
        dur: float, y: float) -> float:
    var block := Rect2(FIELD_PAD_X, y, size.x - FIELD_PAD_X * 2.0, TIMELINE_H)
    draw_rect(block, Color(0.08, 0.12, 0.18, 0.9))
    draw_rect(block, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    var start_sec := float(c.get("start_sec", 0.0))
    var end_sec := float(c.get("end_sec", -1.0))
    var end_for_display := end_sec if end_sec > 0.0 else dur

    var dur_label: String
    if dur > 0.0:
        dur_label = "Duration  %s    Trim  %s → %s" % [
            _fmt_time(dur), _fmt_time(start_sec), _fmt_time(end_for_display)]
    elif str(c.get("file", "")) == "":
        dur_label = "No file. Edit the File field or use IMPORT OGG."
    else:
        dur_label = "Duration  (failed to load)"
    draw_string(font, Vector2(block.position.x + 12, block.position.y + 20),
        dur_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(0.7, 0.82, 0.95, 1))

    var bar_y: float = block.position.y + 34.0
    var bar_h: float = 44.0
    var bar_x: float = block.position.x + BAR_INSET_X
    var bar_w: float = block.size.x - BAR_INSET_X * 2.0
    _bar_rect = Rect2(bar_x, bar_y, bar_w, bar_h)

    draw_rect(_bar_rect, Color(0.14, 0.2, 0.28, 1.0))
    draw_rect(_bar_rect, Color(0.3, 0.45, 0.65, 0.85), false, 1.0)

    if dur <= 0.0:
        var hint := "Waiting for file…" if str(c.get("file", "")) != "" else "Import an OGG to see the waveform strip."
        draw_string(font, Vector2(bar_x + 10, bar_y + bar_h * 0.5 + 4),
            hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.5, 0.6, 0.75, 1))
        return y + TIMELINE_H + 6.0

    var start_clamped: float = clamp(start_sec, 0.0, dur)
    var end_clamped: float = clamp(end_for_display, start_clamped, dur)
    var start_x: float = bar_x + (start_clamped / dur) * bar_w
    var end_x: float = bar_x + (end_clamped / dur) * bar_w

    # Selected-region fill highlights the audible part of the clip.
    if end_x > start_x:
        var fill := Rect2(start_x, bar_y + 3, end_x - start_x, bar_h - 6)
        draw_rect(fill, Color(0.2, 0.55, 0.85, 0.45))

    # Simulated tick marks (roughly every second) so the eye can gauge
    # scale. Not a real waveform — the underlying OGG stream doesn't
    # expose samples, so this is a pseudo-grid instead.
    var tick_count: int = min(30, max(2, int(round(dur))))
    var tc: Color = Color(0.35, 0.5, 0.7, 0.35)
    for i in range(1, tick_count):
        var tx: float = bar_x + (float(i) / float(tick_count)) * bar_w
        draw_line(Vector2(tx, bar_y + 6), Vector2(tx, bar_y + bar_h - 6), tc, 1.0)

    # Playback cursor while preview is running.
    var pos: float = editor.get_preview_position()
    if pos >= 0.0:
        var px: float = bar_x + clamp(pos / dur, 0.0, 1.0) * bar_w
        draw_line(Vector2(px, bar_y + 1), Vector2(px, bar_y + bar_h - 1),
            Color(0.4, 0.95, 1.0, 0.95), 2.0)

    # Start/end markers. Thick line plus a grabber handle above the bar.
    var start_col := Color(0.45, 0.95, 0.55, 1.0)
    var end_col := Color(1.0, 0.4, 0.4, 1.0)
    draw_line(Vector2(start_x, bar_y), Vector2(start_x, bar_y + bar_h),
        start_col, 2.0)
    draw_line(Vector2(end_x, bar_y), Vector2(end_x, bar_y + bar_h),
        end_col, 2.0)

    var handle_h: float = 10.0
    var start_handle := Rect2(start_x - 5.0, bar_y - handle_h, 10.0, handle_h)
    var end_handle := Rect2(end_x - 5.0, bar_y + bar_h, 10.0, handle_h)
    draw_rect(start_handle, start_col)
    draw_rect(end_handle, end_col)

    _start_marker_hit = Rect2(start_x - MARKER_HIT_W * 0.5,
        bar_y - handle_h, MARKER_HIT_W, bar_h + handle_h)
    _end_marker_hit = Rect2(end_x - MARKER_HIT_W * 0.5,
        bar_y, MARKER_HIT_W, bar_h + handle_h)

    var axis_y: float = bar_y + bar_h + 12.0
    draw_string(font, Vector2(bar_x, axis_y),
        "0.00s", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.55, 0.68, 0.85, 1))
    var right_label := _fmt_time(dur)
    var right_w: float = float(right_label.length()) * 5.4
    draw_string(font, Vector2(bar_x + bar_w - right_w, axis_y),
        right_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.55, 0.68, 0.85, 1))

    if _bar_rect.has_point(mouse_pos) or _start_marker_hit.has_point(mouse_pos) \
            or _end_marker_hit.has_point(mouse_pos):
        EditorTooltip.show_text("Drag the green marker to set trim start, the red marker to set trim end. Markers store seconds into the underlying .ogg — the file is never re-encoded.")

    return y + TIMELINE_H + 6.0


func _apply_drag(mouse_pos: Vector2) -> void:
    if _drag_duration <= 0.0 or _bar_rect.size.x <= 0.0:
        return
    var c: Dictionary = editor.get_selected_clip()
    if c.is_empty():
        return
    var local_x: float = clamp(mouse_pos.x - _bar_rect.position.x, 0.0, _bar_rect.size.x)
    var sec: float = (local_x / _bar_rect.size.x) * _drag_duration
    var start_sec := float(c.get("start_sec", 0.0))
    var end_sec := float(c.get("end_sec", -1.0))
    var end_effective := end_sec if end_sec > 0.0 else _drag_duration
    if _drag_kind == "start":
        sec = clamp(sec, 0.0, max(0.0, end_effective - 0.01))
        editor.set_clip_trim("start_sec", snapped(sec, 0.01))
    elif _drag_kind == "end":
        sec = clamp(sec, start_sec + 0.01, _drag_duration)
        if sec >= _drag_duration - 0.005:
            editor.set_clip_trim("end_sec", -1.0)
        else:
            editor.set_clip_trim("end_sec", snapped(sec, 0.01))


func _draw_commit_row(font: Font, mouse_pos: Vector2, y: float) -> void:
    var strip := Rect2(FIELD_PAD_X, y, size.x - FIELD_PAD_X * 2.0, COMMIT_H)
    draw_rect(strip, Color(0.14, 0.1, 0.06, 0.9))
    draw_rect(strip, Color(0.95, 0.7, 0.3, 0.85), false, 1.0)

    var save_w: float = (strip.size.x - 18.0) * 0.62
    var discard_w: float = strip.size.x - save_w - 18.0
    var btn_y: float = strip.position.y + 6.0
    var btn_h: float = strip.size.y - 12.0

    _save_clip_rect = Rect2(strip.position.x + 6.0, btn_y, save_w, btn_h)
    var save_hover := _save_clip_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _save_clip_rect, save_hover,
        Color(0.95, 0.75, 0.3, 1))
    var save_label := "✓ SAVE CLIP"
    var save_w_text := float(save_label.length()) * 6.0
    draw_string(font, Vector2(_save_clip_rect.position.x + (save_w - save_w_text) * 0.5,
        _save_clip_rect.position.y + 21),
        save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 0.95, 1) if save_hover else Color(1.0, 0.95, 0.82, 1))
    if save_hover:
        EditorTooltip.show_text("Commit this clip to the registry with its current id, file, trim marks, and tags. Then the next queued import (if any) takes its place.")

    _discard_rect = Rect2(_save_clip_rect.position.x + save_w + 6.0, btn_y, discard_w, btn_h)
    var discard_hover := _discard_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _discard_rect, discard_hover,
        Color(0.85, 0.45, 0.45, 1))
    var discard_label := "DISCARD"
    var discard_w_text := float(discard_label.length()) * 6.0
    draw_string(font, Vector2(_discard_rect.position.x + (discard_w - discard_w_text) * 0.5,
        _discard_rect.position.y + 21),
        discard_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if discard_hover else Color(0.95, 0.82, 0.82, 1))
    if discard_hover:
        EditorTooltip.show_text("Skip this clip — don't add it to the registry. The underlying .ogg stays on disk so you can re-import later.")


func _draw_play_strip(font: Font, mouse_pos: Vector2, y: float) -> void:
    var strip := Rect2(FIELD_PAD_X, y, size.x - FIELD_PAD_X * 2.0, PLAY_H)
    draw_rect(strip, Color(0.1, 0.16, 0.22, 0.85))
    draw_rect(strip, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    var btn_w: float = (strip.size.x - 18.0) * 0.5
    var btn_y: float = strip.position.y + 6.0
    var btn_h: float = strip.size.y - 12.0

    _play_rect = Rect2(strip.position.x + 6.0, btn_y, btn_w, btn_h)
    var play_hover := _play_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _play_rect, play_hover,
        Color(0.55, 0.9, 0.55, 1))
    var play_label := "▶ PLAY"
    var play_w := float(play_label.length()) * 6.0
    draw_string(font, Vector2(_play_rect.position.x + (btn_w - play_w) * 0.5,
        _play_rect.position.y + 21),
        play_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 0.95, 1) if play_hover else Color(0.85, 0.95, 0.85, 1))
    if play_hover:
        EditorTooltip.show_text("Preview this clip. Respects trim start/end. The playback cursor sweeps the timeline bar while playing.")

    _stop_rect = Rect2(_play_rect.position.x + btn_w + 6.0, btn_y, btn_w, btn_h)
    var stop_hover := _stop_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _stop_rect, stop_hover,
        Color(0.9, 0.45, 0.45, 1))
    var stop_label := "■ STOP"
    var stop_w := float(stop_label.length()) * 6.0
    draw_string(font, Vector2(_stop_rect.position.x + (btn_w - stop_w) * 0.5,
        _stop_rect.position.y + 21),
        stop_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if stop_hover else Color(0.95, 0.85, 0.85, 1))
    if stop_hover:
        EditorTooltip.show_text("Stop the currently-playing preview.")


func _display_value(c: Dictionary, field: String) -> String:
    var v: Variant = c.get(field, null)
    if v == null:
        return ""
    if field == "tags":
        if typeof(v) == TYPE_ARRAY:
            var parts: Array = []
            for t in v:
                parts.append(str(t))
            return ", ".join(parts)
        return str(v)
    return str(v)


func _fmt_time(sec: float) -> String:
    if sec <= 0.0:
        return "0.00s"
    if sec < 60.0:
        return "%.2fs" % sec
    var m := int(sec / 60.0)
    var s := sec - float(m) * 60.0
    return "%d:%05.2f" % [m, s]


func _prompt_for(field: String) -> String:
    if field == "id":
        return "Unique id (snake_case)."
    if field == "file":
        return "Pack-relative path to the .ogg, e.g. Audio/footsteps/step1.ogg"
    if field == "tags":
        return "Comma-separated tags, e.g. footstep, metal, loud"
    return ""


func _tooltip_for(field: String) -> String:
    if field == "id":
        return "Unique id for this clip (snake_case). Entities and triggers reference clips by id, so pick something descriptive."
    if field == "file":
        return "Pack-relative path to the underlying .ogg file (e.g. Audio/footsteps/step1.ogg). Usually set automatically by IMPORT OGG, but you can type a path manually to alias an existing file."
    if field == "tags":
        return "Free-form comma-separated tags. Useful for grouping clips (e.g. 'footstep, metal') so you can pick a random one at runtime without hardcoding ids."
    return "Click to edit this field."
