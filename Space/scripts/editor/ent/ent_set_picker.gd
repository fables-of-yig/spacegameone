extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EntIO = preload("res://Space/scripts/editor/ent/ent_io.gd")

# Full-screen modal that lists every sprite-set folder available in the
# current pack (user layer + shipped layer, de-duped) and lets the user
# click one to assign it to the active entity. Fires `picked(rel_path)`
# on selection; `cancelled` on Esc or click-outside.
#
# The picker also exposes a "(none)" row so users can clear the field,
# and a "custom…" row that re-routes through the shared text modal for
# folders that don't exist on disk yet.

signal picked(sprite_set_rel: String)
signal cancelled
signal import_requested

const BOX_W: float = 560.0
const BOX_H: float = 480.0
const ROW_H: float = 30.0

var editor: Node = null

var _title: String = "Pick sprite set"
var _current_set: String = ""
var _sets: Array = []
var _rows: Array = []  # [{rel, rect}]
var _none_rect: Rect2 = Rect2()
var _import_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()
var _scroll: float = 0.0
var _viewport_h: float = 0.0
var _content_h: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)


func _process(_delta):
    if visible:
        queue_redraw()


func open(pack_id: String, current_set: String = "") -> void:
    _sets = EntIO.list_sprite_sets(pack_id)
    _current_set = current_set
    _scroll = 0.0
    visible = true
    queue_redraw()


func close() -> void:
    visible = false


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 36.0, max(0.0, _content_h - _viewport_h))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 36.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _cancel_rect.has_point(mb.position):
                _do_cancel()
                accept_event()
                return
            if _import_rect.has_point(mb.position):
                visible = false
                import_requested.emit()
                accept_event()
                return
            if _none_rect.has_point(mb.position):
                _do_pick("")
                accept_event()
                return
            for row in _rows:
                if (row["rect"] as Rect2).has_point(mb.position):
                    _do_pick(str(row["rel"]))
                    accept_event()
                    return
            var box := _box_rect()
            if not box.has_point(mb.position):
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


func _do_pick(rel: String) -> void:
    visible = false
    picked.emit(rel)


func _do_cancel() -> void:
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
    draw_string(font, box.position + Vector2(24, 58),
        "Scans Sprites/ in both the user pack and shipped pack.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    var list_x: float = box.position.x + 20
    var list_y: float = box.position.y + 78
    var list_w: float = box.size.x - 40
    var list_h: float = box.size.y - 78 - 60
    var list_rect := Rect2(list_x, list_y, list_w, list_h)
    draw_rect(list_rect, Color(0.05, 0.08, 0.12, 0.92))
    draw_rect(list_rect, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    _viewport_h = list_h
    var total_rows: int = _sets.size() + 1  # +1 for the "(none)" row
    _content_h = float(total_rows) * ROW_H + 6.0
    if _scroll > max(0.0, _content_h - _viewport_h):
        _scroll = max(0.0, _content_h - _viewport_h)

    _rows.clear()

    var row_y: float = list_y + 4.0 - _scroll
    _none_rect = Rect2(list_x + 4, row_y, list_w - 8, ROW_H - 2)
    var none_selected := _current_set == ""
    var none_hover := _none_rect.has_point(mouse_pos)
    var none_bg: Color
    if none_selected:
        none_bg = Color(0.3, 0.5, 0.8, 0.9)
    elif none_hover:
        none_bg = Color(0.2, 0.3, 0.45, 0.85)
    else:
        none_bg = Color(0.1, 0.14, 0.2, 0.4)
    if _none_rect.position.y + _none_rect.size.y >= list_y and _none_rect.position.y <= list_y + list_h:
        draw_rect(_none_rect, none_bg)
        draw_string(font, _none_rect.position + Vector2(10, 18),
            "— none —", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.95, 0.95, 0.7, 1) if none_selected else Color(0.78, 0.88, 0.98, 1))
        if none_hover:
            EditorTooltip.show_text("Clear the sprite set field. The entity will have no sprites — useful for invisible triggers or entities whose visuals come from their scene.")

    for i in _sets.size():
        var rel := str(_sets[i])
        var r_y: float = list_y + 4.0 - _scroll + float(i + 1) * ROW_H
        var rect := Rect2(list_x + 4, r_y, list_w - 8, ROW_H - 2)

        _rows.append({
            "rel": rel,
            "rect": rect,
        })

        if rect.position.y + rect.size.y < list_y:
            continue
        if rect.position.y > list_y + list_h:
            continue

        var is_sel := rel == _current_set
        var hover := rect.has_point(mouse_pos)
        var bg: Color
        if is_sel:
            bg = Color(0.3, 0.5, 0.8, 0.9)
        elif hover:
            bg = Color(0.2, 0.3, 0.45, 0.85)
        else:
            bg = Color(0.1, 0.14, 0.2, 0.4)
        draw_rect(rect, bg)

        var text_col: Color
        if is_sel:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.78, 0.88, 0.98, 1)
        draw_string(font, rect.position + Vector2(10, 18),
            rel, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
        if hover:
            EditorTooltip.show_text("Sprite set \"%s\". Click to assign it to the active entity. Each PNG inside this folder becomes a named pose." % rel)

    if _sets.is_empty():
        draw_string(font, Vector2(list_x + 12, list_y + 40 + ROW_H),
            "No sprite sets found under Sprites/.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.68, 0.85, 1))
        draw_string(font, Vector2(list_x + 12, list_y + 58 + ROW_H),
            "Create a folder with a .png inside either",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.62, 0.78, 1))
        draw_string(font, Vector2(list_x + 12, list_y + 74 + ROW_H),
            "  res://Content/<pack>/Sprites/  or",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.62, 0.78, 1))
        draw_string(font, Vector2(list_x + 12, list_y + 90 + ROW_H),
            "  user://Packs/<pack>/Sprites/",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.62, 0.78, 1))

    # Import + Cancel buttons (bottom-right of the box)
    var btn_w: float = 140.0
    var btn_h: float = 32.0
    _cancel_rect = Rect2(box.position.x + box.size.x - btn_w - 20,
        box.position.y + box.size.y - btn_h - 16, btn_w, btn_h)
    _import_rect = Rect2(_cancel_rect.position.x - btn_w - 10,
        _cancel_rect.position.y, btn_w, btn_h)

    var import_hover := _import_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _import_rect, import_hover,
        Color(0.55, 0.85, 1.0, 1.0))
    var import_label := "IMPORT PNG…"
    var import_w := float(import_label.length()) * 6.0
    draw_string(font, Vector2(_import_rect.position.x + (btn_w - import_w) * 0.5,
        _import_rect.position.y + 21),
        import_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 1, 1) if import_hover else Color(0.7, 0.85, 0.98, 1))
    if import_hover:
        EditorTooltip.show_text("Open a file picker to copy one or more PNGs from anywhere on your computer into a new or existing sprite set inside this pack. After copying, the new set is preselected here.")

    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover,
        Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 21),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Close the picker without changing the entity's sprite set. Esc or clicking outside the box does the same thing.")

    draw_string(font, Vector2(box.position.x + 24,
        box.position.y + box.size.y - 12),
        "Click a row to assign.  Esc: cancel",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.85, 1))
