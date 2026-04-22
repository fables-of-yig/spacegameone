extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Full-screen color picker modal. Shows a hex input (real LineEdit child),
# a live swatch preview, and a quick palette of common UI colors that
# the user can one-click to apply. Submits the current hex on OK.

signal submitted(hex: String)
signal cancelled

var editor: Node = null

const BOX_W: float = 480.0
const BOX_H: float = 400.0

var _title: String = ""
var _hex: String = "#ffffff"
var _line_edit: LineEdit = null

var _swatch_rects: Array = []   # [{rect, hex}]
var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()

# Palette: rows of (label, hex) tuples laid out as a 6×N grid.
const PALETTE: Array = [
    "#ffffff", "#000000", "#ffeb40", "#c7b82d", "#ff9d3b", "#ff7070",
    "#70ff70", "#5ad9ff", "#9b8cff", "#ff80c0", "#202830", "#3a4654",
    "#6699ee", "#88e0a0", "#a04060", "#404060", "#1a1a22", "#0e1418",
]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)
    _line_edit = LineEdit.new()
    _line_edit.placeholder_text = "#rrggbb or #rrggbbaa"
    _line_edit.text_changed.connect(_on_text_changed)
    _line_edit.text_submitted.connect(_on_text_submitted)
    add_child(_line_edit)
    _layout_line_edit()


func _process(_delta):
    if visible:
        queue_redraw()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_line_edit()


func open(title: String, current_hex: String) -> void:
    _title = title
    _hex = current_hex
    visible = true
    if _line_edit != null:
        _line_edit.text = current_hex
        _line_edit.grab_focus.call_deferred()
        _line_edit.select_all.call_deferred()
    _layout_line_edit()
    queue_redraw()


func close() -> void:
    visible = false


func _layout_line_edit() -> void:
    if _line_edit == null:
        return
    var box_x := (size.x - BOX_W) * 0.5
    var box_y := (size.y - BOX_H) * 0.5
    _line_edit.position = Vector2(box_x + 24, box_y + 80)
    _line_edit.size = Vector2(BOX_W - 200, 30)


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
            for s in _swatch_rects:
                if (s["rect"] as Rect2).has_point(mb.position):
                    _hex = str(s["hex"])
                    if _line_edit != null:
                        _line_edit.text = _hex
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


func _on_text_changed(new_text: String) -> void:
    _hex = new_text


func _on_text_submitted(_text: String) -> void:
    _confirm()


func _confirm() -> void:
    visible = false
    submitted.emit(_normalized_hex(_hex))


func _cancel() -> void:
    visible = false
    cancelled.emit()


func _normalized_hex(hex: String) -> String:
    var s := hex.strip_edges()
    if s == "":
        return "#ffffff"
    if not s.begins_with("#"):
        s = "#" + s
    return s


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
    draw_string(font, box.position + Vector2(24, 60),
        "Hex code:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    # Live swatch preview to the right of the LineEdit.
    var preview := Rect2(box.position.x + BOX_W - 160, box.position.y + 78, 130, 36)
    var col := UIPanels._hex_to_color(_hex)
    draw_rect(preview, col)
    draw_rect(preview, Color(0, 0, 0, 0.7), false, 1.0)
    draw_string(font, preview.position + Vector2(8, 22),
        UIPanels.color_to_hex(col), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(1, 1, 1, 1) if col.get_luminance() < 0.5 else Color(0, 0, 0, 1))
    if preview.has_point(mouse_pos):
        EditorTooltip.show_text("Live preview of the current hex value. Updates as you type or click a swatch below.")
    if _line_edit != null and Rect2(_line_edit.position, _line_edit.size).has_point(mouse_pos):
        EditorTooltip.show_text("Hex color input. Format: #rrggbb or #rrggbbaa (with alpha). The leading # is optional. Press Enter to submit.")

    # Palette grid
    draw_string(font, box.position + Vector2(24, 138),
        "Quick palette:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    _swatch_rects.clear()
    var sw_size: float = 50.0
    var sw_gap: float = 8.0
    var cols: int = 6
    for i in PALETTE.size():
        var c_i: int = i % cols
        var r_i: int = i / cols
        var x: float = box.position.x + 24 + float(c_i) * (sw_size + sw_gap)
        var y: float = box.position.y + 152 + float(r_i) * (sw_size + sw_gap)
        var sw_rect := Rect2(x, y, sw_size, sw_size)
        var sw_hex := str(PALETTE[i])
        var sw_color := UIPanels._hex_to_color(sw_hex)
        draw_rect(sw_rect, sw_color)
        var border := Color(0, 0, 0, 0.7)
        if sw_rect.has_point(mouse_pos):
            border = Color(1, 1, 1, 0.9)
            EditorTooltip.show_text("Quick palette swatch %s. Click to copy this hex into the input above. You can still edit it before pressing OK." % sw_hex)
        draw_rect(sw_rect, border, false, 1.5)
        _swatch_rects.append({"rect": sw_rect, "hex": sw_hex})

    # OK + Cancel buttons
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
        EditorTooltip.show_text("Apply the current hex color and close. Pressing Enter inside the hex input does the same thing.")

    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover, Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 20),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Discard color changes and close. Esc or clicking outside the box does the same thing.")

    draw_string(font, box.position + Vector2(24, box.size.y - 12),
        "Enter: OK   Esc: Cancel   Click swatch: apply",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
