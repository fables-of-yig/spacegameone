extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Shared three-way confirm modal used by editors that copy files into
# pack folders. Shown when one or more destination filenames already
# exist inside the target folder. The user picks a single resolution
# for the whole batch: OVERWRITE, SKIP, or CANCEL.
#
# Used by:
#   - entity_editor.gd  (sprite PNG import into a Sprites/<set>/ folder)
#   - audio_editor.gd   (audio file import into an Audio/<folder>/)
#
# Emits `chose(action)` where action is "overwrite" | "skip" | "cancel".

signal chose(action: String)

const BOX_W: float = 520.0
const BOX_H: float = 340.0
const MAX_SHOWN: int = 6

var _folder_label: String = ""
var _conflict_names: Array = []

var _overwrite_rect: Rect2 = Rect2()
var _skip_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)


func _process(_delta):
    if visible:
        queue_redraw()


func open(folder_label: String, conflict_names: Array) -> void:
    _folder_label = folder_label
    _conflict_names = conflict_names
    visible = true
    queue_redraw()


func close() -> void:
    visible = false


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _overwrite_rect.has_point(mb.position):
                _emit_and_close("overwrite")
                accept_event()
                return
            if _skip_rect.has_point(mb.position):
                _emit_and_close("skip")
                accept_event()
                return
            if _cancel_rect.has_point(mb.position):
                _emit_and_close("cancel")
                accept_event()
                return
            if not _box_rect().has_point(mb.position):
                _emit_and_close("cancel")
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _emit_and_close("cancel")
            get_viewport().set_input_as_handled()


func _emit_and_close(action: String) -> void:
    visible = false
    chose.emit(action)


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
        "Import conflicts", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)

    var plural := "" if _conflict_names.size() == 1 else "s"
    var sub := "%d file%s already exist in \"%s\":" % [
        _conflict_names.size(), plural, _folder_label]
    draw_string(font, box.position + Vector2(24, 58),
        sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    var list_x := box.position.x + 40
    var list_y := box.position.y + 82
    var shown: int = mini(_conflict_names.size(), MAX_SHOWN)
    for i in shown:
        draw_string(font, Vector2(list_x, list_y + float(i) * 18 + 12),
            str(_conflict_names[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.9, 0.95, 1.0, 1))
    if _conflict_names.size() > MAX_SHOWN:
        var rest := "… and %d more" % (_conflict_names.size() - MAX_SHOWN)
        draw_string(font, Vector2(list_x, list_y + float(shown) * 18 + 12),
            rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.6, 0.72, 0.88, 1))

    var btn_w: float = 140.0
    var btn_h: float = 32.0
    var btn_y: float = box.position.y + box.size.y - btn_h - 16
    _cancel_rect = Rect2(box.position.x + box.size.x - btn_w - 16, btn_y, btn_w, btn_h)
    _skip_rect = Rect2(_cancel_rect.position.x - btn_w - 8, btn_y, btn_w, btn_h)
    _overwrite_rect = Rect2(_skip_rect.position.x - btn_w - 8, btn_y, btn_w, btn_h)

    _draw_btn(font, mouse_pos, _overwrite_rect, "OVERWRITE",
        Color(0.95, 0.6, 0.4, 1.0), Color(1, 0.92, 0.82, 1),
        "Replace all listed files with the new imports. The old bytes are discarded.")
    _draw_btn(font, mouse_pos, _skip_rect, "SKIP",
        Color(0.55, 0.85, 1.0, 1.0), Color(0.85, 0.95, 1, 1),
        "Keep the existing files. Only the non-conflicting files from your selection are imported.")
    _draw_btn(font, mouse_pos, _cancel_rect, "CANCEL",
        Color(0.9, 0.45, 0.4, 1.0), Color(1, 0.92, 0.92, 1),
        "Abort the import. No files will be copied.")


func _draw_btn(font: Font, mouse_pos: Vector2, rect: Rect2, label: String,
        tint: Color, text_col: Color, tooltip: String) -> void:
    var hover := rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, rect, hover, tint)
    var lbl_w := float(label.length()) * 6.0
    draw_string(font,
        Vector2(rect.position.x + (rect.size.x - lbl_w) * 0.5, rect.position.y + 21),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        text_col if hover else text_col * Color(0.75, 0.75, 0.75, 1))
    if hover:
        EditorTooltip.show_text(tooltip)
