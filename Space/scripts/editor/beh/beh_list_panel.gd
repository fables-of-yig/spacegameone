extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Left sidebar for the behavior editor. Scrollable list of behaviors;
# each row shows id + name with per-row ✎/× icon buttons. Clicking the
# row body selects the behavior and resets the node selection to root.

var editor: Node = null

const ROW_H: float = 36.0
const HEADER_H: float = 38.0
const PAD: float = 10.0
const ICON_SIZE: float = 22.0

var _scroll: float = 0.0
var _viewport_h: float = 0.0
var _content_h: float = 0.0
var _rows: Array = []  # [{id, row_rect, rename_rect, delete_rect}]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)
    clip_contents = true


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 40.0, max(0.0, _content_h - _viewport_h))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 40.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for row in _rows:
                if (row["rename_rect"] as Rect2).has_point(mb.position):
                    editor.request_rename_behavior(str(row["id"]))
                    accept_event()
                    return
                if (row["delete_rect"] as Rect2).has_point(mb.position):
                    editor.delete_behavior(str(row["id"]))
                    accept_event()
                    return
                if (row["row_rect"] as Rect2).has_point(mb.position):
                    editor.select_behavior(str(row["id"]))
                    accept_event()
                    return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.ALT)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var header_label := "BEHAVIORS"
    draw_string(font, Vector2(PAD + 4, 24),
        header_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        UIPanels.TEXT_PANEL)

    var behaviors: Array = editor.get_behaviors()
    var count := behaviors.size()
    draw_string(font, Vector2(size.x - PAD - 40, 24),
        "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        UIPanels.TEXT_PANEL_DIM)

    var list_y0: float = HEADER_H
    _viewport_h = size.y - list_y0 - PAD
    _content_h = float(count) * ROW_H
    if _scroll > max(0.0, _content_h - _viewport_h):
        _scroll = max(0.0, _content_h - _viewport_h)

    _rows.clear()
    for i in count:
        var b_v: Variant = behaviors[i]
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var b: Dictionary = b_v
        var id := str(b.get("id", ""))
        var name_str := str(b.get("name", ""))

        var row_top: float = list_y0 + float(i) * ROW_H - _scroll
        var row_rect := Rect2(PAD, row_top, size.x - PAD * 2.0, ROW_H - 4.0)

        var ix: float = row_rect.position.x + row_rect.size.x - ICON_SIZE - 4.0
        var iy: float = row_rect.position.y + (row_rect.size.y - ICON_SIZE) * 0.5
        var delete_rect := Rect2(ix, iy, ICON_SIZE, ICON_SIZE)
        ix -= ICON_SIZE + 4.0
        var rename_rect := Rect2(ix, iy, ICON_SIZE, ICON_SIZE)

        _rows.append({
            "id": id,
            "row_rect": row_rect,
            "rename_rect": rename_rect,
            "delete_rect": delete_rect,
        })

        if row_rect.position.y + row_rect.size.y < list_y0:
            continue
        if row_rect.position.y > size.y:
            continue

        var is_selected: bool = id == editor.selected_behavior_id
        var row_hover := row_rect.has_point(mouse_pos) \
            and not rename_rect.has_point(mouse_pos) \
            and not delete_rect.has_point(mouse_pos)

        var bg: Color
        if is_selected:
            bg = Color(0.3, 0.6, 0.45, 0.95)
        elif row_hover:
            bg = Color(0.18, 0.32, 0.24, 0.85)
        else:
            bg = Color(0.08, 0.18, 0.12, 0.85)
        draw_rect(row_rect, bg)

        var has_unregistered: bool = false
        if editor.has_method("behavior_has_unregistered"):
            has_unregistered = bool(editor.behavior_has_unregistered(id))

        var text_col: Color
        if is_selected:
            text_col = Color(1, 1, 1, 1)
        elif has_unregistered:
            text_col = Color(1.0, 0.78, 0.5, 1)
        else:
            text_col = Color(0.8, 0.95, 0.85, 1)
        var id_label := id
        if has_unregistered:
            id_label = "[!] %s" % id
        draw_string(font, Vector2(row_rect.position.x + 10.0,
            row_rect.position.y + 14),
            id_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
        if name_str != "" and name_str != id:
            draw_string(font, Vector2(row_rect.position.x + 10.0,
                row_rect.position.y + 28),
                name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(0.6, 0.85, 0.72, 1))
        elif has_unregistered:
            draw_string(font, Vector2(row_rect.position.x + 10.0,
                row_rect.position.y + 28),
                "has unregistered leaves", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(1.0, 0.65, 0.4, 1))

        _draw_row_icon(font, rename_rect, "✎",
            rename_rect.has_point(mouse_pos),
            Color(0.55, 0.95, 0.85, 1), Color(0.3, 0.6, 0.45, 1))
        _draw_row_icon(font, delete_rect, "×",
            delete_rect.has_point(mouse_pos),
            Color(1, 0.5, 0.45, 1), Color(0.55, 0.3, 0.3, 1))

        if rename_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Rename behavior \"%s\". Entities reference behaviors by ID — renaming updates all referring entity definitions automatically." % id)
        elif delete_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Delete behavior \"%s\". Entities referencing this behavior will fall back to no behavior. There is no undo." % id)
        elif row_hover:
            if has_unregistered:
                EditorTooltip.show_text("Behavior \"%s\" contains one or more leaves whose action/condition name is not registered in the runtime. At runtime those nodes silently fall back to idle/always. Click to open and fix." % id)
            else:
                EditorTooltip.show_text("Behavior \"%s\". Click to edit its tree on the right. The tree is executed every frame for each entity using this behavior." % id)

    if count == 0:
        draw_string(font, Vector2(PAD + 6, list_y0 + 24),
            "No behaviors yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.55, 0.78, 0.65, 1))
        draw_string(font, Vector2(PAD + 6, list_y0 + 42),
            "Use + ADD BEHAVIOR above.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.45, 0.7, 0.55, 1))


func _draw_row_icon(font: Font, rect: Rect2, glyph: String,
        hover: bool, active_col: Color, rest_col: Color) -> void:
    var bg_col: Color
    if hover:
        bg_col = Color(0.25, 0.4, 0.3, 0.95)
    else:
        bg_col = Color(0.1, 0.18, 0.14, 0.7)
    draw_rect(rect, bg_col)
    draw_rect(rect, Color(0.3, 0.55, 0.4, 0.9), false, 1.0)
    var text_col := active_col if hover else rest_col
    draw_string(font, rect.position + Vector2(7, 16),
        glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)
