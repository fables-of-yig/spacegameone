class_name AIDesignPanel
extends Control
## Full-page AI Design panel accessible from the Creative Builder.
## Contains: Train AI, Fight AI, and recording editing tools.

signal train_ai_requested()
signal fight_ai_requested(template_name: String, recording_path: String)
signal back_requested()

# --- Recording list ---
var _recordings: Array = []  # [{name, template, path, frames, quality_pct, rec: CombatRecording}]
var _templates: Array = []   # [{name, recordings: [idx into _recordings]}]
var _expanded_template: int = -1
var _selected_recording: int = -1  # index into _recordings
var _list_scroll: float = 0.0
var _list_rects: Array = []  # [{rect, type, idx}]

# --- UI rects ---
var _btn_back: Rect2 = Rect2()
var _btn_train: Rect2 = Rect2()
var _btn_fight: Rect2 = Rect2()
var _btn_trim: Rect2 = Rect2()
var _btn_merge: Rect2 = Rect2()
var _btn_purge: Rect2 = Rect2()
var _btn_delete: Rect2 = Rect2()
var _slider_threshold: Rect2 = Rect2()
var _slider_aggression: Rect2 = Rect2()
var _dragging_threshold: bool = false
var _dragging_aggression: bool = false

# --- Merge mode ---
var _merge_mode: bool = false
var _merge_target: int = -1  # recording index to merge INTO

# --- Trim prompt ---
var _trim_active: bool = false
var _trim_start: int = 60
var _trim_end: int = 60

# --- Confirm prompt ---
var _confirm_action: String = ""  # "purge" or "delete"
var _confirm_rect_yes: Rect2 = Rect2()
var _confirm_rect_no: Rect2 = Rect2()

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    focus_mode = FOCUS_ALL
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func show_panel():
    visible = true
    _refresh_recordings()
    _selected_recording = -1
    _merge_mode = false
    _trim_active = false
    _confirm_action = ""
    grab_focus()
    queue_redraw()

func _refresh_recordings():
    _recordings.clear()
    _templates.clear()
    _list_rects.clear()
    _expanded_template = -1
    var by_template: Dictionary = {}
    var paths = CombatRecording.list_recordings()
    for path in paths:
        var rec = CombatRecording.new()
        if rec.load_from_file(path):
            var stats = rec.get_stats()
            var idx = _recordings.size()
            _recordings.append({
                name = rec.recording_name,
                template = rec.template_name if rec.template_name != "" else rec.recording_name,
                path = path,
                frames = rec.get_frame_count(),
                quality_pct = stats.quality_pct,
                rec = rec,
            })
            var tname = _recordings[idx].template
            if not by_template.has(tname):
                by_template[tname] = []
            by_template[tname].append(idx)
    for tname in by_template:
        _templates.append({name = tname, recordings = by_template[tname]})

func _draw():
    var vp = size
    var font = ThemeDB.fallback_font
    var mouse = get_local_mouse_position()

    # Background
    draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.025, 0.04))

    # --- Header ---
    draw_rect(Rect2(0, 0, vp.x, 50), Color(0.04, 0.05, 0.08))
    draw_string(font, Vector2(20, 34), "AI DESIGN", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.8, 1.0))

    # Back button
    _btn_back = Rect2(vp.x - 110, 10, 90, 30)
    var back_hov = _btn_back.has_point(mouse)
    draw_rect(_btn_back, Color(0.08, 0.06, 0.06) if not back_hov else Color(0.14, 0.1, 0.1))
    draw_rect(_btn_back, Color(0.5, 0.35, 0.35) if not back_hov else Color(0.8, 0.5, 0.5), false, 1.0)
    draw_string(font, Vector2(_btn_back.position.x + 16, _btn_back.position.y + 20), "< Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.55, 0.55) if not back_hov else Color(1.0, 0.7, 0.7))

    # --- Layout: left panel (recordings), right panel (tools) ---
    var left_w: float = 340.0
    var right_x: float = left_w + 20
    var panel_y: float = 60.0
    var panel_h: float = vp.y - 70.0

    # Left panel background
    draw_rect(Rect2(10, panel_y, left_w, panel_h), Color(0.03, 0.035, 0.06, 0.95))
    draw_rect(Rect2(10, panel_y, left_w, panel_h), Color(0.15, 0.2, 0.35, 0.5), false, 1.0)
    draw_string(font, Vector2(20, panel_y + 22), "RECORDINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.55, 0.7))

    _draw_recording_list(font, mouse, Rect2(10, panel_y + 30, left_w, panel_h - 30))

    # Right panel background
    var right_w = vp.x - right_x - 10
    draw_rect(Rect2(right_x, panel_y, right_w, panel_h), Color(0.03, 0.035, 0.06, 0.95))
    draw_rect(Rect2(right_x, panel_y, right_w, panel_h), Color(0.15, 0.2, 0.35, 0.5), false, 1.0)

    _draw_tools_panel(font, mouse, Rect2(right_x, panel_y, right_w, panel_h))

    # Overlay prompts
    if _trim_active:
        _draw_trim_prompt(font, mouse)
    if _confirm_action != "":
        _draw_confirm_prompt(font, mouse)

func _draw_recording_list(font: Font, mouse: Vector2, area: Rect2):
    _list_rects.clear()
    var row_h: float = 28.0
    var y = area.position.y + 4.0 - _list_scroll
    var clip_top = area.position.y
    var clip_bottom = area.position.y + area.size.y

    if _templates.is_empty():
        draw_string(font, Vector2(area.position.x + 16, area.position.y + 40), "No recordings found.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))
        draw_string(font, Vector2(area.position.x + 16, area.position.y + 60), "Use Train AI to create one.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.35, 0.4))
        return

    for ti in _templates.size():
        var tmpl = _templates[ti]
        if y + row_h > clip_top and y < clip_bottom:
            var row_rect = Rect2(area.position.x + 6, y, area.size.x - 12, row_h - 2)
            _list_rects.append({rect = row_rect, type = "template", idx = ti})
            var is_hov = row_rect.has_point(mouse)
            var is_exp = (_expanded_template == ti)
            draw_rect(row_rect, Color(0.08, 0.1, 0.16) if is_exp else (Color(0.06, 0.08, 0.12) if is_hov else Color(0.04, 0.045, 0.07)))
            draw_rect(row_rect, Color(0.25, 0.4, 0.6) if is_exp else Color(0.12, 0.15, 0.2), false, 1.0)
            var arrow = "v " if is_exp else "> "
            draw_string(font, Vector2(row_rect.position.x + 8, y + 19), arrow + tmpl.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.8, 0.95) if is_exp else Color(0.5, 0.6, 0.7))
            var cnt_text = "%d rec" % tmpl.recordings.size()
            draw_string(font, Vector2(row_rect.position.x + row_rect.size.x - 50, y + 19), cnt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.4, 0.45))
        y += row_h

        if _expanded_template == ti:
            for ri_idx in tmpl.recordings.size():
                var rec_i = tmpl.recordings[ri_idx]
                var rec_data = _recordings[rec_i]
                if y + row_h > clip_top and y < clip_bottom:
                    var rec_rect = Rect2(area.position.x + 20, y, area.size.x - 26, row_h - 2)
                    _list_rects.append({rect = rec_rect, type = "recording", idx = rec_i})
                    var is_sel = (_selected_recording == rec_i)
                    var r_hov = rec_rect.has_point(mouse)
                    var bg_col: Color
                    if _merge_mode and rec_i != _merge_target:
                        bg_col = Color(0.1, 0.08, 0.14) if r_hov else Color(0.06, 0.04, 0.08)
                    elif is_sel:
                        bg_col = Color(0.1, 0.15, 0.2)
                    else:
                        bg_col = Color(0.06, 0.08, 0.1) if r_hov else Color(0.035, 0.04, 0.055)
                    draw_rect(rec_rect, bg_col)
                    var bdr_col = Color(0.4, 0.7, 0.9) if is_sel else (Color(0.25, 0.35, 0.5) if r_hov else Color(0.1, 0.12, 0.16))
                    if _merge_mode and rec_i != _merge_target:
                        bdr_col = Color(0.5, 0.3, 0.7) if r_hov else Color(0.2, 0.15, 0.3)
                    draw_rect(rec_rect, bdr_col, false, 1.0)
                    var name_col = Color(0.7, 0.9, 1.0) if is_sel else (Color(0.55, 0.65, 0.75) if r_hov else Color(0.45, 0.5, 0.58))
                    draw_string(font, Vector2(rec_rect.position.x + 10, y + 18), rec_data.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_col)
                    var info = "%d fr" % rec_data.frames
                    if rec_data.quality_pct > 0:
                        info += "  %d%% q" % int(rec_data.quality_pct)
                    draw_string(font, Vector2(rec_rect.position.x + rec_rect.size.x - 90, y + 18), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.4, 0.45))
                y += row_h

func _draw_tools_panel(font: Font, mouse: Vector2, area: Rect2):
    var x = area.position.x + 20
    var y = area.position.y + 16
    var btn_w: float = 140.0
    var btn_h: float = 32.0
    var gap: float = 12.0

    # --- Action buttons row ---
    draw_string(font, Vector2(x, y + 14), "ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.55, 0.7))
    y += 28

    # Train AI
    _btn_train = Rect2(x, y, btn_w, btn_h)
    _draw_button(font, mouse, _btn_train, "Train AI", Color(0.65, 0.25, 0.25), Color(0.85, 0.4, 0.4))

    # Fight AI (needs selected recording)
    _btn_fight = Rect2(x + btn_w + gap, y, btn_w, btn_h)
    var fight_enabled = _selected_recording >= 0
    if fight_enabled:
        _draw_button(font, mouse, _btn_fight, "Fight AI", Color(0.25, 0.55, 0.65), Color(0.4, 0.7, 0.85))
    else:
        _draw_button_disabled(font, _btn_fight, "Fight AI")
    y += btn_h + 24

    # --- Selected recording info ---
    draw_string(font, Vector2(x, y + 14), "SELECTED RECORDING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.55, 0.7))
    y += 28

    if _selected_recording < 0:
        draw_string(font, Vector2(x, y + 14), "Select a recording from the list to edit it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.38, 0.45))
        # Clear tool button rects when nothing selected
        _btn_trim = Rect2()
        _btn_merge = Rect2()
        _btn_purge = Rect2()
        _btn_delete = Rect2()
        _slider_threshold = Rect2()
        _slider_aggression = Rect2()
        return

    var rec_data = _recordings[_selected_recording]
    var rec: CombatRecording = rec_data.rec

    # Name and template
    draw_string(font, Vector2(x, y + 14), rec_data.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.9, 1.0))
    draw_string(font, Vector2(x, y + 32), "Template: " + rec_data.template, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.55))
    y += 46

    # Stats
    var stats = rec.get_stats()
    var stat_col = Color(0.5, 0.55, 0.65)
    draw_string(font, Vector2(x, y + 14), "Frames: %d" % stats.total_frames, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, stat_col)
    draw_string(font, Vector2(x + 160, y + 14), "Quality: %d%% (%d frames)" % [int(stats.quality_pct), stats.quality_frames], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, stat_col)
    y += 20
    draw_string(font, Vector2(x, y + 14), "Avg Dist: %d" % int(stats.avg_dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, stat_col)
    draw_string(font, Vector2(x + 160, y + 14), "Fire Rate: %d%%" % int(stats.fire_rate_pct), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, stat_col)
    draw_string(font, Vector2(x + 320, y + 14), "Range: %d - %d" % [int(stats.min_dist), int(stats.max_dist)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, stat_col)
    y += 32

    # --- Sliders ---
    draw_string(font, Vector2(x, y + 14), "TUNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.55, 0.7))
    y += 28

    # Quality Threshold slider (0.0 - 1.0)
    y = _draw_slider(font, mouse, x, y, "Quality Threshold", rec.quality_threshold, 0.0, 1.0, "slider_threshold")
    y += 8

    # Aggression Bias slider (0.0 - 5.0)
    y = _draw_slider(font, mouse, x, y, "Aggression Bias", rec.aggression_bias, 0.0, 5.0, "slider_aggression")
    y += 24

    # --- Edit tools ---
    draw_string(font, Vector2(x, y + 14), "EDIT TOOLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.55, 0.7))
    y += 28

    _btn_trim = Rect2(x, y, btn_w, btn_h)
    _draw_button(font, mouse, _btn_trim, "Trim Frames", Color(0.5, 0.45, 0.2), Color(0.75, 0.65, 0.35))

    _btn_merge = Rect2(x + btn_w + gap, y, btn_w, btn_h)
    if not _merge_mode:
        _draw_button(font, mouse, _btn_merge, "Merge Into", Color(0.3, 0.45, 0.55), Color(0.5, 0.7, 0.8))
    else:
        _draw_button(font, mouse, _btn_merge, "Cancel Merge", Color(0.55, 0.3, 0.3), Color(0.8, 0.45, 0.45))
    y += btn_h + gap

    _btn_purge = Rect2(x, y, btn_w, btn_h)
    _draw_button(font, mouse, _btn_purge, "Purge Low-Q", Color(0.55, 0.35, 0.2), Color(0.8, 0.55, 0.3))

    _btn_delete = Rect2(x + btn_w + gap, y, btn_w, btn_h)
    _draw_button(font, mouse, _btn_delete, "Delete", Color(0.6, 0.15, 0.15), Color(0.85, 0.3, 0.3))

    if _merge_mode:
        y += btn_h + 16
        draw_string(font, Vector2(x, y + 14), "Click another recording to merge its frames into this one.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.4, 0.8))

func _draw_slider(font: Font, mouse: Vector2, x: float, y: float, label: String, value: float, min_val: float, max_val: float, slider_id: String) -> float:
    draw_string(font, Vector2(x, y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65))
    var val_text = "%.2f" % value
    draw_string(font, Vector2(x + 160, y + 14), val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.95))
    y += 20

    var track_x = x
    var track_w: float = 300.0
    var track_h: float = 8.0
    var track_rect = Rect2(track_x, y, track_w, track_h)

    # Store slider rect
    if slider_id == "slider_threshold":
        _slider_threshold = track_rect
    elif slider_id == "slider_aggression":
        _slider_aggression = track_rect

    # Track
    draw_rect(track_rect, Color(0.08, 0.09, 0.14))
    draw_rect(track_rect, Color(0.2, 0.25, 0.35), false, 1.0)

    # Fill
    var fill_frac = clampf((value - min_val) / maxf(max_val - min_val, 0.001), 0.0, 1.0)
    draw_rect(Rect2(track_x, y, track_w * fill_frac, track_h), Color(0.25, 0.5, 0.7, 0.6))

    # Handle
    var handle_x = track_x + track_w * fill_frac
    var handle_rect = Rect2(handle_x - 5, y - 3, 10, track_h + 6)
    var hov = handle_rect.grow(4).has_point(mouse) or track_rect.has_point(mouse)
    draw_rect(handle_rect, Color(0.5, 0.75, 1.0) if hov else Color(0.35, 0.55, 0.8))

    return y + track_h + 4

func _draw_button(_font: Font, mouse: Vector2, rect: Rect2, label: String, border_col: Color, text_col: Color):
    var hov = rect.has_point(mouse)
    draw_rect(rect, Color(0.06, 0.07, 0.1) if not hov else Color(0.1, 0.12, 0.18))
    draw_rect(rect, border_col if not hov else border_col.lightened(0.3), false, 1.0)
    draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 12, rect.position.y + 21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col if not hov else text_col.lightened(0.2))

func _draw_button_disabled(font: Font, rect: Rect2, label: String):
    draw_rect(rect, Color(0.04, 0.045, 0.06))
    draw_rect(rect, Color(0.12, 0.14, 0.18), false, 1.0)
    draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.28, 0.32))

func _draw_trim_prompt(font: Font, mouse: Vector2):
    var vp = size
    # Dim background
    draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))
    var pw: float = 340.0
    var ph: float = 160.0
    var px = vp.x * 0.5 - pw * 0.5
    var py = vp.y * 0.5 - ph * 0.5
    draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.05, 0.08, 0.98))
    draw_rect(Rect2(px, py, pw, ph), Color(0.4, 0.5, 0.7), false, 2.0)

    draw_string(font, Vector2(px + 20, py + 28), "TRIM FRAMES", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.75, 0.95))

    var total = 0
    if _selected_recording >= 0:
        total = _recordings[_selected_recording].frames
    draw_string(font, Vector2(px + 20, py + 52), "Total frames: %d" % total, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.5, 0.6))

    draw_string(font, Vector2(px + 20, py + 76), "Trim start: %d frames (~%.1fs)" % [_trim_start, _trim_start / 60.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.7))
    draw_string(font, Vector2(px + 20, py + 96), "Trim end:   %d frames (~%.1fs)" % [_trim_end, _trim_end / 60.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.7))
    var remaining = maxi(total - _trim_start - _trim_end, 0)
    draw_string(font, Vector2(px + 20, py + 116), "Remaining: %d frames" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.8, 0.5))

    _confirm_rect_yes = Rect2(px + 20, py + ph - 38, 80, 28)
    _confirm_rect_no = Rect2(px + 112, py + ph - 38, 80, 28)
    _draw_button(font, mouse, _confirm_rect_yes, "Trim", Color(0.5, 0.45, 0.2), Color(0.75, 0.65, 0.35))
    _draw_button(font, mouse, _confirm_rect_no, "Cancel", Color(0.4, 0.3, 0.3), Color(0.65, 0.5, 0.5))

    draw_string(font, Vector2(px + 210, py + ph - 20), "Up/Down: start  Shift+Up/Down: end", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.38, 0.45))

func _draw_confirm_prompt(font: Font, mouse: Vector2):
    var vp = size
    draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))
    var pw: float = 320.0
    var ph: float = 100.0
    var px = vp.x * 0.5 - pw * 0.5
    var py = vp.y * 0.5 - ph * 0.5
    draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.05, 0.08, 0.98))
    draw_rect(Rect2(px, py, pw, ph), Color(0.6, 0.3, 0.3), false, 2.0)

    var msg = ""
    if _confirm_action == "purge":
        msg = "Purge all low-quality frames? This cannot be undone."
    elif _confirm_action == "delete":
        msg = "Delete this recording? This cannot be undone."
    draw_string(font, Vector2(px + 20, py + 34), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.6, 0.6))

    _confirm_rect_yes = Rect2(px + 20, py + ph - 38, 80, 28)
    _confirm_rect_no = Rect2(px + 112, py + ph - 38, 80, 28)
    _draw_button(font, mouse, _confirm_rect_yes, "Yes", Color(0.6, 0.2, 0.2), Color(0.85, 0.4, 0.4))
    _draw_button(font, mouse, _confirm_rect_no, "Cancel", Color(0.3, 0.3, 0.4), Color(0.55, 0.55, 0.65))

# --- Input handling ---

func _gui_input(event: InputEvent):
    if not visible:
        return
    if event is InputEventMouseButton and event.pressed:
        var mouse = event.position
        if event.button_index == MOUSE_BUTTON_LEFT:
            _handle_click(mouse)
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _list_scroll = maxf(_list_scroll - 40, 0)
            queue_redraw()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _list_scroll += 40
            queue_redraw()

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if not event.pressed:
            _dragging_threshold = false
            _dragging_aggression = false

    if event is InputEventMouseMotion:
        if _dragging_threshold and _selected_recording >= 0:
            _update_slider_drag(event.position, _slider_threshold, "threshold")
        elif _dragging_aggression and _selected_recording >= 0:
            _update_slider_drag(event.position, _slider_aggression, "aggression")
        queue_redraw()

    if event is InputEventKey and event.pressed and not event.echo:
        if _trim_active:
            _handle_trim_key(event)
            return
        if event.keycode == KEY_ESCAPE:
            if _confirm_action != "":
                _confirm_action = ""
                queue_redraw()
            elif _merge_mode:
                _merge_mode = false
                queue_redraw()
            elif _trim_active:
                _trim_active = false
                queue_redraw()
            else:
                back_requested.emit()

func _handle_click(mouse: Vector2):
    # Confirm prompt takes priority
    if _confirm_action != "" or _trim_active:
        if _confirm_rect_yes.has_point(mouse):
            if _trim_active:
                _do_trim()
            elif _confirm_action == "purge":
                _do_purge()
            elif _confirm_action == "delete":
                _do_delete()
        elif _confirm_rect_no.has_point(mouse):
            _confirm_action = ""
            _trim_active = false
        queue_redraw()
        return

    # Back button
    if _btn_back.has_point(mouse):
        back_requested.emit()
        return

    # Train AI
    if _btn_train.has_point(mouse):
        train_ai_requested.emit()
        return

    # Fight AI
    if _btn_fight.size.x > 0 and _btn_fight.has_point(mouse) and _selected_recording >= 0:
        var rec_data = _recordings[_selected_recording]
        fight_ai_requested.emit(rec_data.template, rec_data.path)
        return

    # Sliders
    if _slider_threshold.size.x > 0 and _slider_threshold.grow(6).has_point(mouse):
        _dragging_threshold = true
        _update_slider_drag(mouse, _slider_threshold, "threshold")
        queue_redraw()
        return
    if _slider_aggression.size.x > 0 and _slider_aggression.grow(6).has_point(mouse):
        _dragging_aggression = true
        _update_slider_drag(mouse, _slider_aggression, "aggression")
        queue_redraw()
        return

    # Tool buttons
    if _btn_trim.size.x > 0 and _btn_trim.has_point(mouse) and _selected_recording >= 0:
        _trim_active = true
        _trim_start = 60
        _trim_end = 60
        queue_redraw()
        return
    if _btn_merge.size.x > 0 and _btn_merge.has_point(mouse) and _selected_recording >= 0:
        _merge_mode = not _merge_mode
        if _merge_mode:
            _merge_target = _selected_recording
        queue_redraw()
        return
    if _btn_purge.size.x > 0 and _btn_purge.has_point(mouse) and _selected_recording >= 0:
        _confirm_action = "purge"
        queue_redraw()
        return
    if _btn_delete.size.x > 0 and _btn_delete.has_point(mouse) and _selected_recording >= 0:
        _confirm_action = "delete"
        queue_redraw()
        return

    # Recording list
    for entry in _list_rects:
        if entry.rect.has_point(mouse):
            if entry.type == "template":
                _expanded_template = entry.idx if _expanded_template != entry.idx else -1
                queue_redraw()
                return
            elif entry.type == "recording":
                if _merge_mode and entry.idx != _merge_target:
                    _do_merge(entry.idx)
                    return
                _selected_recording = entry.idx
                queue_redraw()
                return

func _update_slider_drag(mouse: Vector2, slider_rect: Rect2, which: String):
    if slider_rect.size.x <= 0 or _selected_recording < 0:
        return
    var frac = clampf((mouse.x - slider_rect.position.x) / slider_rect.size.x, 0.0, 1.0)
    var rec: CombatRecording = _recordings[_selected_recording].rec
    if which == "threshold":
        rec.quality_threshold = frac * 1.0  # range 0-1
        _save_recording_metadata(_selected_recording)
    elif which == "aggression":
        rec.aggression_bias = frac * 5.0  # range 0-5
        _save_recording_metadata(_selected_recording)
    queue_redraw()

func _handle_trim_key(event: InputEventKey):
    if event.keycode == KEY_UP:
        if event.shift_pressed:
            _trim_end = maxi(_trim_end + 60, 0)
        else:
            _trim_start = maxi(_trim_start + 60, 0)
        queue_redraw()
    elif event.keycode == KEY_DOWN:
        if event.shift_pressed:
            _trim_end = maxi(_trim_end - 60, 0)
        else:
            _trim_start = maxi(_trim_start - 60, 0)
        queue_redraw()
    elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
        _do_trim()
    elif event.keycode == KEY_ESCAPE:
        _trim_active = false
        queue_redraw()

# --- Actions ---

func _save_recording_metadata(rec_idx: int):
    if rec_idx < 0 or rec_idx >= _recordings.size():
        return
    var rec_data = _recordings[rec_idx]
    var rec: CombatRecording = rec_data.rec
    rec.save_to_file(rec_data.path)

func _do_trim():
    if _selected_recording < 0:
        return
    var rec: CombatRecording = _recordings[_selected_recording].rec
    var path = _recordings[_selected_recording].path
    rec.trim_frames(_trim_start, _trim_end)
    rec.save_to_file(path)
    _trim_active = false
    _refresh_recordings()
    _reselect_by_path(path)
    queue_redraw()

func _do_merge(source_idx: int):
    if _merge_target < 0 or _merge_target >= _recordings.size():
        return
    if source_idx < 0 or source_idx >= _recordings.size():
        return
    var target_rec: CombatRecording = _recordings[_merge_target].rec
    var source_rec: CombatRecording = _recordings[source_idx].rec
    target_rec.merge_from(source_rec)
    target_rec.save_to_file(_recordings[_merge_target].path)
    _merge_mode = false
    var target_path = _recordings[_merge_target].path
    _refresh_recordings()
    _reselect_by_path(target_path)
    queue_redraw()

func _do_purge():
    if _selected_recording < 0:
        return
    var rec: CombatRecording = _recordings[_selected_recording].rec
    var path = _recordings[_selected_recording].path
    rec.purge_low_quality(rec.quality_threshold)
    rec.save_to_file(path)
    _confirm_action = ""
    _refresh_recordings()
    _reselect_by_path(path)
    queue_redraw()

func _do_delete():
    if _selected_recording < 0:
        return
    var path = _recordings[_selected_recording].path
    DirAccess.remove_absolute(path)
    _confirm_action = ""
    _selected_recording = -1
    _refresh_recordings()
    queue_redraw()

func _reselect_by_path(path: String):
    _selected_recording = -1
    for i in _recordings.size():
        if _recordings[i].path == path:
            _selected_recording = i
            # Also expand the right template
            for ti in _templates.size():
                if _recordings[i].template == _templates[ti].name:
                    _expanded_template = ti
            break

func _process(_delta: float):
    if visible:
        queue_redraw()
