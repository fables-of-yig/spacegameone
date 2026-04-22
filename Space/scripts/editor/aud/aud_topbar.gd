extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Top bar for the audio editor. Campaign label on the left, IMPORT OGG
# in the middle, SAVE + CLOSE on the right. Clips only exist via the
# import → trim → save-clip flow, so there is no "add empty clip"
# button — importing is the only way to create one.

var editor: Node = null

var _import_rect: Rect2 = Rect2()
var _manifest_rect: Rect2 = Rect2()
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
        if _import_rect.has_point(event.position):
            editor.request_import_ogg()
            accept_event()
            return
        if _manifest_rect.has_point(event.position):
            editor.request_open_manifest()
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
    var label := "CAMPAIGN  %s   —   AUDIO" % editor.pack_id
    draw_string(font, Vector2(pad, 34),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

    _tooltips_rect = Rect2(pad + label_w + 18.0, 16, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    var btn_w: float = 110.0
    var btn_h: float = 32.0

    var import_btn_w: float = 160.0
    var manifest_btn_w: float = 130.0
    var mid_total := import_btn_w + 8.0 + manifest_btn_w
    var mid_x := (size.x - mid_total) * 0.5
    _import_rect = Rect2(mid_x, 16, import_btn_w, btn_h)
    var import_hover := _import_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _import_rect, import_hover,
        Color(0.55, 0.85, 1.0, 1))
    var import_label := "+ IMPORT OGG"
    var import_w := float(import_label.length()) * 6.0
    draw_string(font, Vector2(_import_rect.position.x + (import_btn_w - import_w) * 0.5,
        _import_rect.position.y + 21),
        import_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 1, 1) if import_hover else Color(0.88, 0.92, 1.0, 1))
    if import_hover:
        EditorTooltip.show_text("Pick one or more .ogg files from your computer and copy them into a pack folder. Each imported file drops you into a trim session — set the trim marks, rename, then SAVE CLIP to commit the entry.")

    _manifest_rect = Rect2(mid_x + import_btn_w + 8.0, 16, manifest_btn_w, btn_h)
    var manifest_hover := _manifest_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _manifest_rect, manifest_hover,
        Color(0.7, 0.7, 1.0, 1))
    var manifest_label := "MANIFEST"
    var manifest_w := float(manifest_label.length()) * 6.0
    draw_string(font, Vector2(_manifest_rect.position.x + (manifest_btn_w - manifest_w) * 0.5,
        _manifest_rect.position.y + 21),
        manifest_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 1, 1) if manifest_hover else Color(0.85, 0.88, 1.0, 1))
    if manifest_hover:
        EditorTooltip.show_text("Edit Audio/manifest.json — the SFX/ambience/music name→path lookup. The game calls AudioManager.play_sfx(\"laser_fire\") and the manifest tells it which file to play. Saves hot-reload live.")

    _close_rect = Rect2(size.x - pad - btn_w, 16, btn_w, btn_h)
    var close_hover := _close_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _close_rect, close_hover,
        Color(0.95, 0.45, 0.4, 1))
    if close_hover:
        EditorTooltip.show_text("Close the audio editor and return to the main menu. Unsaved changes will prompt you to save first.")
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
        EditorTooltip.show_text("Save the clips registry to disk. SAVE* means there are unsaved edits. Imported .ogg files are already on disk — SAVE only persists clip metadata.")
    var save_w := float(save_label.length()) * 6.0
    var save_col: Color
    if save_hover:
        save_col = Color(1, 1, 0.95, 1)
    else:
        save_col = Color(0.75, 0.95, 0.75, 1)
    draw_string(font, Vector2(_save_rect.position.x + (btn_w - save_w) * 0.5,
        _save_rect.position.y + 21),
        save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, save_col)
