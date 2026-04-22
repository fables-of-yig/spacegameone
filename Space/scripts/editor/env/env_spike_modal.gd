extends Control

# Modal for editing spike cell properties. When the user clicks a BT_SPIKE
# cell with the PICK tool in collision mode, this modal opens to let them
# assign a spike profile (damage, effect, knockback) via the BTS byte.
#
# The modal shows a list of existing spike profiles (from spike_profiles.json)
# and lets the user pick one or create a new one. On submit, fires
# `submitted(bts_value)` where bts_value is the profile id to write into
# the BTS grid at that cell.

signal submitted(bts_value: int)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")

const BOX_W: float = 560.0
const BOX_H: float = 480.0

const EFFECT_OPTIONS: Array = ["none", "burn", "poison", "slow"]
const KNOCKBACK_OPTIONS: Array = ["push_away", "launch_up", "pull_in", "none"]

var _pack_id: String = ""
var _profiles: Array = []
var _selected_idx: int = 0  # index into _profiles array (not profile id)
var _editing: bool = false   # true when the detail panel is open for editing

# Detail editing fields
var _edit_name: LineEdit = null
var _edit_damage: LineEdit = null
var _edit_duration: LineEdit = null
var _edit_tick_dmg: LineEdit = null
var _edit_tick_interval: LineEdit = null
var _edit_speed_mult: LineEdit = null
var _effect_idx: int = 0
var _knockback_idx: int = 0
var _error_text: String = ""

# Hit rects
var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()
var _new_rect: Rect2 = Rect2()
var _edit_rect: Rect2 = Rect2()
var _delete_rect: Rect2 = Rect2()
var _profile_rects: Array = []
var _effect_rects: Array = []
var _knockback_rects: Array = []


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)
    _build_edit_fields()


func _build_edit_fields() -> void:
    _edit_name = _make_line_edit("Profile name")
    _edit_damage = _make_line_edit("Damage")
    _edit_duration = _make_line_edit("Duration (s)")
    _edit_tick_dmg = _make_line_edit("Tick damage")
    _edit_tick_interval = _make_line_edit("Tick interval (s)")
    _edit_speed_mult = _make_line_edit("Speed mult")
    for le in [_edit_name, _edit_damage, _edit_duration, _edit_tick_dmg, _edit_tick_interval, _edit_speed_mult]:
        le.visible = false
        add_child(le)


func _make_line_edit(placeholder: String) -> LineEdit:
    var le := LineEdit.new()
    le.placeholder_text = placeholder
    return le


func _process(_delta):
    if visible:
        queue_redraw()


func open(pack_id: String, current_bts: int) -> void:
    _pack_id = pack_id
    _profiles = EnvIO.load_spike_profiles(pack_id)
    _editing = false
    _error_text = ""
    # Select the profile matching the current BTS value.
    _selected_idx = 0
    for i in _profiles.size():
        if typeof(_profiles[i]) == TYPE_DICTIONARY:
            if int((_profiles[i] as Dictionary).get("id", -1)) == current_bts:
                _selected_idx = i
                break
    visible = true
    _hide_edit_fields()
    queue_redraw()


func close() -> void:
    visible = false
    _editing = false
    _hide_edit_fields()


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _selected_profile() -> Dictionary:
    if _selected_idx >= 0 and _selected_idx < _profiles.size():
        var p = _profiles[_selected_idx]
        if typeof(p) == TYPE_DICTIONARY:
            return p
    return EnvIO.default_spike_profile()


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
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
            if _new_rect.size.x > 0 and _new_rect.has_point(pos):
                _create_new_profile()
                accept_event()
                return
            if _edit_rect.size.x > 0 and _edit_rect.has_point(pos):
                _toggle_edit()
                accept_event()
                return
            if _delete_rect.size.x > 0 and _delete_rect.has_point(pos):
                _delete_selected()
                accept_event()
                return
            for entry in _profile_rects:
                if (entry["rect"] as Rect2).has_point(pos):
                    _selected_idx = int(entry["idx"])
                    if _editing:
                        _populate_edit_fields()
                    accept_event()
                    return
            for entry in _effect_rects:
                if (entry["rect"] as Rect2).has_point(pos):
                    _effect_idx = int(entry["idx"])
                    accept_event()
                    return
            for entry in _knockback_rects:
                if (entry["rect"] as Rect2).has_point(pos):
                    _knockback_idx = int(entry["idx"])
                    accept_event()
                    return
            # Click outside box = cancel
            var box := _box_rect()
            if not box.has_point(pos):
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


func _confirm() -> void:
    if _editing:
        _save_edit_fields()
        if not _error_text.is_empty():
            return
    var profile := _selected_profile()
    var bts_val := int(profile.get("id", 0))
    visible = false
    _editing = false
    _hide_edit_fields()
    submitted.emit(bts_val)


func _do_cancel() -> void:
    visible = false
    _editing = false
    _hide_edit_fields()
    cancelled.emit()


func _create_new_profile() -> void:
    var new_p := EnvIO.default_spike_profile().duplicate()
    new_p["name"] = "spike_%d" % _profiles.size()
    var new_id := EnvIO.add_spike_profile(_pack_id, new_p)
    if new_id < 0:
        return
    _profiles = EnvIO.load_spike_profiles(_pack_id)
    for i in _profiles.size():
        if typeof(_profiles[i]) == TYPE_DICTIONARY and int((_profiles[i] as Dictionary).get("id", -1)) == new_id:
            _selected_idx = i
            break
    _editing = true
    _populate_edit_fields()
    _show_edit_fields()


func _toggle_edit() -> void:
    if _editing:
        _save_edit_fields()
        _editing = false
        _hide_edit_fields()
    else:
        _editing = true
        _populate_edit_fields()
        _show_edit_fields()


func _delete_selected() -> void:
    var profile := _selected_profile()
    var pid := int(profile.get("id", 0))
    if pid == 0:
        return  # Can't delete default
    EnvIO.delete_spike_profile(_pack_id, pid)
    _profiles = EnvIO.load_spike_profiles(_pack_id)
    _selected_idx = clampi(_selected_idx, 0, _profiles.size() - 1)
    if _editing:
        _populate_edit_fields()


func _populate_edit_fields() -> void:
    var p := _selected_profile()
    _edit_name.text = str(p.get("name", ""))
    _edit_damage.text = str(int(p.get("damage", 10)))
    _edit_duration.text = "%.1f" % float(p.get("effect_duration", 0.0))
    _edit_tick_dmg.text = str(int(p.get("effect_tick_damage", 0)))
    _edit_tick_interval.text = "%.2f" % float(p.get("effect_tick_interval", 0.5))
    _edit_speed_mult.text = "%.2f" % float(p.get("effect_speed_mult", 1.0))
    var eff := str(p.get("effect", "none"))
    _effect_idx = EFFECT_OPTIONS.find(eff)
    if _effect_idx < 0:
        _effect_idx = 0
    var kb := str(p.get("knockback", "push_away"))
    _knockback_idx = KNOCKBACK_OPTIONS.find(kb)
    if _knockback_idx < 0:
        _knockback_idx = 0


func _save_edit_fields() -> void:
    var profile := _selected_profile()
    var pid := int(profile.get("id", 0))
    if not _edit_damage.text.strip_edges().is_valid_int():
        _error_text = "Damage must be a whole number."
        queue_redraw()
        return
    if not _edit_duration.text.strip_edges().is_valid_float():
        _error_text = "Duration must be a number."
        queue_redraw()
        return
    if not _edit_tick_dmg.text.strip_edges().is_valid_int():
        _error_text = "Tick damage must be a whole number."
        queue_redraw()
        return
    if not _edit_tick_interval.text.strip_edges().is_valid_float():
        _error_text = "Tick interval must be a number."
        queue_redraw()
        return
    if not _edit_speed_mult.text.strip_edges().is_valid_float():
        _error_text = "Speed multiplier must be a number."
        queue_redraw()
        return
    var updates := {
        "name": _edit_name.text.strip_edges(),
        "damage": int(_edit_damage.text),
        "effect": EFFECT_OPTIONS[_effect_idx],
        "effect_duration": float(_edit_duration.text),
        "effect_tick_damage": int(_edit_tick_dmg.text),
        "effect_tick_interval": float(_edit_tick_interval.text),
        "effect_speed_mult": float(_edit_speed_mult.text),
        "knockback": KNOCKBACK_OPTIONS[_knockback_idx],
    }
    _error_text = ""
    EnvIO.update_spike_profile(_pack_id, pid, updates)
    _profiles = EnvIO.load_spike_profiles(_pack_id)
    queue_redraw()


func _show_edit_fields() -> void:
    for le in [_edit_name, _edit_damage, _edit_duration, _edit_tick_dmg, _edit_tick_interval, _edit_speed_mult]:
        le.visible = true
    _layout_edit_fields()


func _hide_edit_fields() -> void:
    for le in [_edit_name, _edit_damage, _edit_duration, _edit_tick_dmg, _edit_tick_interval, _edit_speed_mult]:
        le.visible = false


func _layout_edit_fields() -> void:
    var box := _box_rect()
    var field_x: float = box.position.x + 280.0
    var field_y: float = box.position.y + 80.0
    var field_w: float = 160.0
    var field_h: float = 24.0
    var gap: float = 30.0
    var fields := [_edit_name, _edit_damage, _edit_duration, _edit_tick_dmg, _edit_tick_interval, _edit_speed_mult]
    for i in fields.size():
        var le: LineEdit = fields[i]
        le.position = Vector2(field_x, field_y + i * gap)
        le.size = Vector2(field_w, field_h)


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        if _editing:
            _layout_edit_fields()


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
    draw_string(font, Vector2(bx + 24, by + 32),
        "Spike Profile", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    if not _error_text.is_empty():
        draw_string(font, Vector2(bx + 24, by + BOX_H - 54),
            _error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.4, 1.0))

    # Profile list (left side)
    _profile_rects.clear()
    var list_x := bx + 16.0
    var list_y := by + 56.0
    var item_h := 28.0
    var list_w := 240.0

    for i in _profiles.size():
        var p = _profiles[i]
        if typeof(p) != TYPE_DICTIONARY:
            continue
        var pd: Dictionary = p
        var rect := Rect2(list_x, list_y + i * item_h, list_w, item_h - 2)
        _profile_rects.append({"idx": i, "rect": rect})

        var is_selected := i == _selected_idx
        var is_hover := rect.has_point(mouse_pos)
        var bg_color: Color
        if is_selected:
            bg_color = Color(0.3, 0.6, 0.9, 0.8)
        elif is_hover:
            bg_color = Color(0.35, 0.45, 0.6, 0.5)
        else:
            bg_color = Color(0.25, 0.3, 0.4, 0.3)
        draw_rect(rect, bg_color)

        var pid := int(pd.get("id", 0))
        var pname := str(pd.get("name", ""))
        var pdmg := int(pd.get("damage", 0))
        var peff := str(pd.get("effect", "none"))
        var pkb := str(pd.get("knockback", "push_away"))
        var label := "[%d] %s  dmg:%d %s %s" % [pid, pname, pdmg, peff, pkb]
        var label_color := Color(1, 1, 1, 1) if is_selected else Color(0.8, 0.85, 0.9, 1)
        draw_string(font, rect.position + Vector2(8, 18), label,
            HORIZONTAL_ALIGNMENT_LEFT, int(list_w - 12), 11, label_color)

    # Selected profile detail (right side, when not editing)
    var detail_x := bx + 270.0
    var detail_y := by + 56.0
    var profile := _selected_profile()

    if not _editing:
        var lines := [
            "Name: %s" % str(profile.get("name", "")),
            "Damage: %d" % int(profile.get("damage", 0)),
            "Effect: %s" % str(profile.get("effect", "none")),
            "Duration: %.1fs" % float(profile.get("effect_duration", 0.0)),
            "Tick Dmg: %d" % int(profile.get("effect_tick_damage", 0)),
            "Tick Interval: %.2fs" % float(profile.get("effect_tick_interval", 0.5)),
            "Speed Mult: %.2f" % float(profile.get("effect_speed_mult", 1.0)),
            "Knockback: %s" % str(profile.get("knockback", "push_away")),
        ]
        for i in lines.size():
            draw_string(font, Vector2(detail_x, detail_y + i * 22 + 14),
                lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    else:
        # Draw field labels next to the LineEdits
        var field_labels := ["Name:", "Damage:", "Duration (s):", "Tick Damage:", "Tick Interval (s):", "Speed Mult:"]
        for i in field_labels.size():
            draw_string(font, Vector2(detail_x, detail_y + i * 30 + 14),
                field_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)

        # Effect picker
        var eff_y := detail_y + 6 * 30 + 6
        draw_string(font, Vector2(detail_x, eff_y + 14),
            "Effect:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)
        _effect_rects.clear()
        var eff_btn_x := detail_x + 60.0
        for i in EFFECT_OPTIONS.size():
            var r := Rect2(eff_btn_x + i * 60, eff_y, 56, 20)
            _effect_rects.append({"idx": i, "rect": r})
            var active := i == _effect_idx
            var col := Color(0.3, 0.7, 0.4, 0.9) if active else Color(0.3, 0.35, 0.45, 0.6)
            draw_rect(r, col)
            draw_string(font, r.position + Vector2(4, 14),
                EFFECT_OPTIONS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(1, 1, 1, 1) if active else Color(0.7, 0.75, 0.8, 1))

        # Knockback picker
        var kb_y := eff_y + 28
        draw_string(font, Vector2(detail_x, kb_y + 14),
            "Knockback:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)
        _knockback_rects.clear()
        var kb_btn_x := detail_x + 80.0
        for i in KNOCKBACK_OPTIONS.size():
            var r := Rect2(kb_btn_x + i * 68, kb_y, 64, 20)
            _knockback_rects.append({"idx": i, "rect": r})
            var active := i == _knockback_idx
            var col := Color(0.3, 0.7, 0.4, 0.9) if active else Color(0.3, 0.35, 0.45, 0.6)
            draw_rect(r, col)
            draw_string(font, r.position + Vector2(4, 14),
                KNOCKBACK_OPTIONS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(1, 1, 1, 1) if active else Color(0.7, 0.75, 0.8, 1))

    # Action buttons along bottom
    var btn_h: float = 28.0
    var btn_y: float = by + BOX_H - btn_h - 16.0
    var btn_gap: float = 8.0

    # OK / Cancel on the right
    var ok_w: float = 80.0
    _ok_rect = Rect2(bx + BOX_W - ok_w - 16.0, btn_y, ok_w, btn_h)
    _cancel_rect = Rect2(_ok_rect.position.x - ok_w - btn_gap, btn_y, ok_w, btn_h)

    UIPanels.draw_button_bg(self, _ok_rect, _ok_rect.has_point(mouse_pos), Color(0.4, 0.9, 0.55, 1.0))
    draw_string(font, _ok_rect.position + Vector2(28, 18), "OK",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.95, 1))

    UIPanels.draw_button_bg(self, _cancel_rect, _cancel_rect.has_point(mouse_pos), Color(0.9, 0.45, 0.4, 1.0))
    draw_string(font, _cancel_rect.position + Vector2(16, 18), "CANCEL",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.95, 1))

    # New / Edit / Delete on the left
    var action_x := bx + 16.0
    var action_w: float = 64.0
    _new_rect = Rect2(action_x, btn_y, action_w, btn_h)
    _edit_rect = Rect2(action_x + action_w + btn_gap, btn_y, action_w, btn_h)
    _delete_rect = Rect2(action_x + 2 * (action_w + btn_gap), btn_y, action_w, btn_h)

    UIPanels.draw_button_bg(self, _new_rect, _new_rect.has_point(mouse_pos), Color(0.4, 0.65, 0.9, 1.0))
    draw_string(font, _new_rect.position + Vector2(14, 18), "NEW",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 1))

    var edit_label := "DONE" if _editing else "EDIT"
    UIPanels.draw_button_bg(self, _edit_rect, _edit_rect.has_point(mouse_pos), Color(0.7, 0.65, 0.3, 1.0))
    draw_string(font, _edit_rect.position + Vector2(12, 18), edit_label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 1))

    var can_delete := int(profile.get("id", 0)) != 0
    var del_color := Color(0.85, 0.3, 0.3, 1.0) if can_delete else Color(0.5, 0.4, 0.4, 0.5)
    UIPanels.draw_button_bg(self, _delete_rect, _delete_rect.has_point(mouse_pos) and can_delete, del_color)
    draw_string(font, _delete_rect.position + Vector2(8, 18), "DELETE",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1, 1, 1, 1) if can_delete else Color(0.6, 0.55, 0.55, 0.7))
