extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes = preload("res://Space/scripts/shared/ui/ui_types.gd")

var editor: Node = null

var _save_rect: Rect2 = Rect2()
var _mode_rect: Rect2 = Rect2()
var _set_default_rect: Rect2 = Rect2()
var _load_default_rect: Rect2 = Rect2()
var _reset_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _tooltips_rect: Rect2 = Rect2()
var _screen_rects: Dictionary = {}


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _tooltips_rect.has_point(event.position):
            EditorTooltip.toggle()
            accept_event()
            return
        if _save_rect.has_point(event.position):
            editor.save_to_pack()
            accept_event()
            return
        if _mode_rect.has_point(event.position):
            editor.toggle_editor_mode()
            accept_event()
            return
        for screen_id in _screen_rects.keys():
            var rect: Rect2 = _screen_rects[screen_id]
            if rect.has_point(event.position):
                editor.set_active_screen(str(screen_id))
                accept_event()
                return
        if _set_default_rect.has_point(event.position):
            editor.save_as_default()
            accept_event()
            return
        if _load_default_rect.has_point(event.position):
            editor.load_from_default()
            accept_event()
            return
        if _reset_rect.has_point(event.position):
            editor.reset_to_fallback()
            accept_event()
            return
        if _close_rect.has_point(event.position):
            editor.request_close()
            accept_event()
            return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size), Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font: Font = ThemeDB.fallback_font
    var mouse_pos: Vector2 = get_local_mouse_position()
    var in_screen_mode: bool = editor.get_editor_mode() == 1

    var pad: float = 18.0
    var label: String = "CAMPAIGN  %s   -   %s" % [editor.pack_id, "SCREEN UI" if in_screen_mode else "THEME"]
    if editor.pack_id == "":
        label = "GLOBAL DEFAULT   -   %s" % ("SCREEN UI" if in_screen_mode else "THEME")
    draw_string(font, Vector2(pad, 30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

    _tooltips_rect = Rect2(pad + label_w + 18.0, 12, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)
    _screen_rects.clear()

    var btn_h: float = 32.0
    var x_right: float = size.x - pad

    var close_w: float = 90.0
    _close_rect = Rect2(x_right - close_w, 12, close_w, btn_h)
    _draw_btn(font, _close_rect, "CLOSE", Color(0.95, 0.45, 0.4, 1.0), Color(0.8, 0.55, 0.55, 1.0), Color(1, 0.95, 0.95, 1.0), mouse_pos)
    if _close_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Close the editor and return to the menu.")
    x_right -= close_w + 8.0

    var reset_w: float = 90.0
    _reset_rect = Rect2(x_right - reset_w, 12, reset_w, btn_h)
    _draw_btn(font, _reset_rect, "RESET", Color(0.85, 0.6, 0.3, 1.0), Color(0.78, 0.62, 0.4, 1.0), Color(1, 0.92, 0.78, 1.0), mouse_pos)
    if _reset_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Reset the current editor surface to fallback values without saving.")
    x_right -= reset_w + 8.0

    var load_w: float = 130.0
    _load_default_rect = Rect2(x_right - load_w, 12, load_w, btn_h)
    _draw_btn(font, _load_default_rect, "LOAD DEFAULT", Color(0.55, 0.7, 0.95, 1.0), Color(0.7, 0.82, 0.95, 1.0), Color(0.95, 0.98, 1.0, 1.0), mouse_pos)
    if _load_default_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Load the global default theme into the editor.")
    x_right -= load_w + 8.0

    var set_w: float = 130.0
    _set_default_rect = Rect2(x_right - set_w, 12, set_w, btn_h)
    _draw_btn(font, _set_default_rect, "SET DEFAULT", Color(0.55, 0.85, 0.95, 1.0), Color(0.7, 0.92, 0.98, 1.0), Color(0.95, 1.0, 1.0, 1.0), mouse_pos)
    if _set_default_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Save the current theme as the global default.")
    x_right -= set_w + 8.0

    var save_w: float = 100.0
    _save_rect = Rect2(x_right - save_w, 12, save_w, btn_h)
    var save_dirty: bool = editor._screen_dirty if in_screen_mode else editor.dirty
    var save_label: String = "SAVE*" if save_dirty else "SAVE"
    _draw_btn(font, _save_rect, save_label, Color(0.4, 0.9, 0.55, 1.0), Color(0.75, 0.95, 0.75, 1.0), Color(1, 1, 0.95, 1.0), mouse_pos)
    if _save_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Save the current %s to this pack." % ("screen" if in_screen_mode else "theme"))
    x_right -= save_w + 8.0

    var mode_w: float = 126.0
    _mode_rect = Rect2(x_right - mode_w, 12, mode_w, btn_h)
    _draw_btn(font, _mode_rect, "SCREEN MODE" if in_screen_mode else "THEME MODE", Color(0.55, 0.78, 0.96, 1.0), Color(0.88, 0.95, 1.0, 1.0), Color(1, 1, 1, 1), mouse_pos)
    if _mode_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Toggle between theme styling and authored screen editing.")

    if in_screen_mode:
        var chip_x: float = pad
        var chip_y: float = 44.0
        var chip_h: float = 16.0
        for screen_id in UITypes.SCREEN_IDS:
            var chip_label: String = str(screen_id).replace("_", " ").to_upper()
            var chip_w: float = maxf(72.0, font.get_string_size(chip_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 18.0)
            if chip_x + chip_w > size.x - pad:
                chip_x = pad
                chip_y += chip_h + 4.0
            var chip_rect: Rect2 = Rect2(chip_x, chip_y, chip_w, chip_h)
            _screen_rects[str(screen_id)] = chip_rect
            var active: bool = str(screen_id) == editor.get_active_screen_id()
            var accent: Color = Color(0.35, 0.7, 0.95, 1.0) if active else Color(0.24, 0.3, 0.42, 1.0)
            _draw_btn(font, chip_rect, chip_label, accent, Color(0.82, 0.9, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0), mouse_pos, 10)
            if chip_rect.has_point(mouse_pos):
                EditorTooltip.show_text(str(UITypes.SCREEN_LABELS.get(screen_id, screen_id)))
            chip_x += chip_w + 6.0


func _draw_btn(font: Font, rect: Rect2, label: String, accent: Color, text_col: Color, hover_text: Color, mouse_pos: Vector2, font_size: int = 13) -> void:
    var hover: bool = rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, rect, hover, accent)
    var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    draw_string(font, Vector2(rect.position.x + (rect.size.x - text_w) * 0.5, rect.position.y + rect.size.y * 0.5 + float(font_size) * 0.33), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, hover_text if hover else text_col)
