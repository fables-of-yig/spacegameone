extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Numeric input modal for the theme editor. Three modes:
#   open_int(title, value, prompt)      → emits {"int": int}
#   open_float(title, value, prompt)    → emits {"float": float}
#   open_int_pair(title, x, y, prompt)  → emits {"x": int, "y": int}
#
# Always emits a Dictionary (so the editor controller has one consistent
# callback signature regardless of mode).

signal submitted(payload: Dictionary)
signal cancelled

var editor: Node = null

const BOX_W: float = 460.0
const BOX_H: float = 220.0

enum Mode { INT, FLOAT, INT_PAIR }

var _title: String = ""
var _prompt: String = ""
var _mode: int = Mode.INT
var _line_edit_a: LineEdit = null
var _line_edit_b: LineEdit = null  # only used for INT_PAIR
var _error_text: String = ""

var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)

    _line_edit_a = LineEdit.new()
    _line_edit_a.text_submitted.connect(_on_text_submitted)
    add_child(_line_edit_a)

    _line_edit_b = LineEdit.new()
    _line_edit_b.text_submitted.connect(_on_text_submitted)
    _line_edit_b.visible = false
    add_child(_line_edit_b)

    _layout_inputs()


func _process(_delta):
    if visible:
        queue_redraw()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_inputs()


func open_int(title: String, value: int, prompt: String = "") -> void:
    _title = title
    _prompt = prompt
    _mode = Mode.INT
    _error_text = ""
    visible = true
    _line_edit_b.visible = false
    _line_edit_a.text = str(value)
    _line_edit_a.grab_focus.call_deferred()
    _line_edit_a.select_all.call_deferred()
    _layout_inputs()
    queue_redraw()


func open_float(title: String, value: float, prompt: String = "") -> void:
    _title = title
    _prompt = prompt
    _mode = Mode.FLOAT
    _error_text = ""
    visible = true
    _line_edit_b.visible = false
    _line_edit_a.text = "%.3f" % value
    _line_edit_a.grab_focus.call_deferred()
    _line_edit_a.select_all.call_deferred()
    _layout_inputs()
    queue_redraw()


func open_int_pair(title: String, x: int, y: int, prompt: String = "") -> void:
    _title = title
    _prompt = prompt
    _mode = Mode.INT_PAIR
    _error_text = ""
    visible = true
    _line_edit_b.visible = true
    _line_edit_a.text = str(x)
    _line_edit_b.text = str(y)
    _line_edit_a.grab_focus.call_deferred()
    _line_edit_a.select_all.call_deferred()
    _layout_inputs()
    queue_redraw()


func close() -> void:
    visible = false


func _layout_inputs() -> void:
    if _line_edit_a == null:
        return
    var box_x := (size.x - BOX_W) * 0.5
    var box_y := (size.y - BOX_H) * 0.5
    if _mode == Mode.INT_PAIR:
        _line_edit_a.position = Vector2(box_x + 24, box_y + 100)
        _line_edit_a.size = Vector2(180, 30)
        _line_edit_b.position = Vector2(box_x + 220, box_y + 100)
        _line_edit_b.size = Vector2(180, 30)
    else:
        _line_edit_a.position = Vector2(box_x + 24, box_y + 100)
        _line_edit_a.size = Vector2(BOX_W - 48, 30)


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _ok_rect.has_point(mb.position):
                _confirm()
                accept_event()
                return
            if _cancel_rect.has_point(mb.position):
                _cancel()
                accept_event()
                return
            var box := _box_rect()
            if not box.has_point(mb.position):
                _cancel()
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _cancel()
            get_viewport().set_input_as_handled()


func _on_text_submitted(_text: String) -> void:
    _confirm()


func _confirm() -> void:
    var payload: Dictionary = {}
    match _mode:
        Mode.INT:
            if not _line_edit_a.text.strip_edges().is_valid_int():
                _error_text = "Value must be a whole number."
                queue_redraw()
                return
            payload = {"int": int(_line_edit_a.text)}
        Mode.FLOAT:
            if not _line_edit_a.text.strip_edges().is_valid_float():
                _error_text = "Value must be a number."
                queue_redraw()
                return
            payload = {"float": float(_line_edit_a.text)}
        Mode.INT_PAIR:
            if not _line_edit_a.text.strip_edges().is_valid_int():
                _error_text = "X must be a whole number."
                queue_redraw()
                return
            if not _line_edit_b.text.strip_edges().is_valid_int():
                _error_text = "Y must be a whole number."
                queue_redraw()
                return
            payload = {
                "x": int(_line_edit_a.text),
                "y": int(_line_edit_b.text),
            }
    _error_text = ""
    visible = false
    submitted.emit(payload)


func _cancel() -> void:
    visible = false
    cancelled.emit()


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw():
    if not visible:
        return
    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)

    var box := _box_rect()
    UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, box.position + Vector2(24, 36),
        _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    if _prompt != "":
        draw_string(font, box.position + Vector2(24, 60),
            _prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    if _error_text != "":
        draw_string(font, box.position + Vector2(24, 82),
            _error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.4, 1.0))

    if _mode == Mode.INT_PAIR:
        draw_string(font, box.position + Vector2(24, 90),
            "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
        draw_string(font, box.position + Vector2(220, 90),
            "Y", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    if _line_edit_a != null and Rect2(_line_edit_a.position, _line_edit_a.size).has_point(mouse_pos):
        EditorTooltip.show_text(_input_tooltip(true))
    elif _mode == Mode.INT_PAIR and _line_edit_b != null \
            and Rect2(_line_edit_b.position, _line_edit_b.size).has_point(mouse_pos):
        EditorTooltip.show_text(_input_tooltip(false))

    var btn_w: float = 96.0
    var btn_h: float = 30.0
    var btn_y: float = box.position.y + box.size.y - btn_h - 16.0
    _ok_rect = Rect2(box.position.x + box.size.x - btn_w - 16.0, btn_y, btn_w, btn_h)
    _cancel_rect = Rect2(_ok_rect.position.x - btn_w - 10.0, btn_y, btn_w, btn_h)

    var ok_hover := _ok_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _ok_rect, ok_hover, Color(0.4, 0.9, 0.55, 1.0))
    var ok_label := "OK"
    var ok_w := float(ok_label.length()) * 6.0
    draw_string(font, Vector2(_ok_rect.position.x + (btn_w - ok_w) * 0.5,
        _ok_rect.position.y + 20),
        ok_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 0.95, 1) if ok_hover else Color(0.75, 0.95, 0.75, 1))
    if ok_hover:
        EditorTooltip.show_text("Apply this value and close. Pressing Enter inside the input does the same thing.")

    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover, Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 20),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Discard the input and close. Esc or clicking outside the box does the same thing.")

    draw_string(font, box.position + Vector2(24, box.size.y - 12),
        "Enter: OK   Esc: Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)


func _input_tooltip(is_first: bool) -> String:
    match _mode:
        Mode.INT:
            return "Integer input. Type a whole number and press Enter or click OK."
        Mode.FLOAT:
            return "Decimal input. Type a number (e.g. 0.55) and press Enter or click OK."
        Mode.INT_PAIR:
            if is_first:
                return "X value (integer). Tab or click into the next field to edit Y."
            return "Y value (integer). Press Enter or click OK to submit both."
    return "Numeric input."
