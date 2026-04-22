extends Control

# Full-screen text-input modal for the environment editor. Fires signal
# `submitted(text)` on Enter/OK, `cancelled` on Esc/Cancel. Owns a real
# LineEdit child so we get IME + selection + clipboard for free; the
# surrounding dialog box is drawn via the shared 9-slice UI panel art.
#
# Usage (from environment_editor):
#   text_modal.open("Rename room", "start")
#   text_modal.submitted.connect(_on_name_submitted)
#
# The caller is expected to disconnect the signal (or route through the
# editor's reusable _modal_callback helper) after receiving the result.

signal submitted(text: String)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

const BOX_W: float = 420.0
const BOX_H: float = 170.0

var _title: String = ""
var _prompt: String = ""
var _line_edit: LineEdit = null

var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)
    _line_edit = LineEdit.new()
    _line_edit.placeholder_text = ""
    _line_edit.text_submitted.connect(_on_text_submitted)
    add_child(_line_edit)
    _layout_line_edit()


func _process(_delta):
    if visible:
        queue_redraw()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_line_edit()


func open(title: String, default_text: String = "", prompt: String = "") -> void:
    _title = title
    _prompt = prompt
    visible = true
    if _line_edit != null:
        _line_edit.text = default_text
        _line_edit.grab_focus.call_deferred()
        _line_edit.select_all.call_deferred()
    _layout_line_edit()
    queue_redraw()


func close() -> void:
    visible = false


func _layout_line_edit() -> void:
    if _line_edit == null:
        return
    var box_x: float = (size.x - BOX_W) * 0.5
    var box_y: float = (size.y - BOX_H) * 0.5
    _line_edit.position = Vector2(box_x + 24, box_y + 74)
    _line_edit.size = Vector2(BOX_W - 48, 30)


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
            # Click outside dialog box also cancels.
            var box_rect := _box_rect()
            if not box_rect.has_point(mb.position):
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


func _confirm() -> void:
    var text := _line_edit.text if _line_edit != null else ""
    visible = false
    submitted.emit(text)


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
        draw_string(font, box.position + Vector2(24, 58),
            _prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

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
        EditorTooltip.show_text("Accept the entered value. Enter in the text field does the same thing.")

    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover, Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 20),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Discard input and close. Esc or clicking outside the box does the same thing.")

    if _line_edit != null and Rect2(_line_edit.position, _line_edit.size).has_point(mouse_pos):
        EditorTooltip.show_text("Text field. Type your value and press Enter to submit, or click OK.")

    draw_string(font, box.position + Vector2(24, box.size.y - 12),
        "Enter: OK   Esc: Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)


func _on_text_submitted(_text: String) -> void:
    _confirm()
