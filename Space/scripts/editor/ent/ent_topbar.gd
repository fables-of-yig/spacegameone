extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Top bar for the entity editor. Campaign label on the left, ADD ENTITY
# button in the middle, SAVE + CLOSE on the right. Much simpler than the
# environment editor's topbar because there's no room switching to do
# here — the entity registry is flat per pack.

var editor: Node = null

var _add_rect: Rect2 = Rect2()
var _save_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _tooltips_rect: Rect2 = Rect2()


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
        if _add_rect.has_point(event.position):
            editor.request_add_entity()
            accept_event()
            return
        if _save_rect.has_point(event.position):
            editor.save_all()
            accept_event()
            return
        if _close_rect.has_point(event.position):
            editor.request_close()
            accept_event()
            return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var pad: float = 18.0
    var label := "CAMPAIGN  %s   —   ENTITIES" % editor.pack_id
    draw_string(font, Vector2(pad, 34),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

    _tooltips_rect = Rect2(pad + label_w + 18.0, 16, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    var btn_w: float = 110.0
    var btn_h: float = 32.0

    var add_btn_w: float = 140.0
    _add_rect = Rect2((size.x - add_btn_w) * 0.5, 16, add_btn_w, btn_h)
    var add_hover := _add_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _add_rect, add_hover,
        Color(0.55, 0.8, 1.0, 1))
    var add_label := "+ ADD ENTITY"
    var add_w := float(add_label.length()) * 6.0
    draw_string(font, Vector2(_add_rect.position.x + (add_btn_w - add_w) * 0.5,
        _add_rect.position.y + 21),
        add_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 1, 1) if add_hover else Color(0.88, 0.92, 1.0, 1))
    if add_hover:
        EditorTooltip.show_text("Create a new entity definition. You'll be prompted for an ID — rooms place entities by ID, so pick something descriptive.")

    _close_rect = Rect2(size.x - pad - btn_w, 16, btn_w, btn_h)
    var close_hover := _close_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _close_rect, close_hover,
        Color(0.95, 0.45, 0.4, 1))
    if close_hover:
        EditorTooltip.show_text("Close the entity editor and return to the main menu. Unsaved changes will prompt you to save first.")
    var close_label := "CLOSE"
    var close_w := float(close_label.length()) * 6.0
    var close_col: Color
    if close_hover:
        close_col = Color(1, 0.95, 0.95, 1)
    else:
        close_col = Color(0.8, 0.55, 0.55, 1)
    draw_string(font, Vector2(_close_rect.position.x + (btn_w - close_w) * 0.5,
        _close_rect.position.y + 21),
        close_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, close_col)

    _save_rect = Rect2(_close_rect.position.x - btn_w - 8, 16, btn_w, btn_h)
    var save_hover := _save_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _save_rect, save_hover,
        Color(0.4, 0.9, 0.55, 1))
    var save_label := "SAVE"
    if editor.dirty:
        save_label = "SAVE*"
    if save_hover:
        EditorTooltip.show_text("Save all entity definitions to disk. SAVE* means there are unsaved edits.")
    var save_w := float(save_label.length()) * 6.0
    var save_col: Color
    if save_hover:
        save_col = Color(1, 1, 0.95, 1)
    else:
        save_col = Color(0.75, 0.95, 0.75, 1)
    draw_string(font, Vector2(_save_rect.position.x + (btn_w - save_w) * 0.5,
        _save_rect.position.y + 21),
        save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, save_col)
