extends Control

# Element hierarchy tree view for the UI screen editor. Shows the
# parent-child nesting of elements in the current screen layout.
# Clicking an entry selects that element; drag to reparent (deferred).

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes = preload("res://Space/scripts/editor/ui/ui_types.gd")

signal element_selected(element_id: String)
signal element_delete_requested(element_id: String)

var editor: Node = null
var screen_data: Dictionary = {}
var selected_id: String = ""

const PAD: float = 8.0
const ROW_H: float = 22.0
const INDENT: float = 16.0

var _row_rects: Array = []  # [{id, rect, depth}]
var _delete_rects: Array = []
var _scroll_y: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for entry in _delete_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    element_delete_requested.emit(str(entry["id"]))
                    accept_event()
                    return
            for entry in _row_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    selected_id = str(entry["id"])
                    element_selected.emit(selected_id)
                    accept_event()
                    return
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _scroll_y = maxf(_scroll_y - ROW_H, 0.0)
            accept_event()
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _scroll_y += ROW_H
            accept_event()


func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.18, 1.0))
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, Vector2(PAD, 16), "HIERARCHY",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)

    _row_rects.clear()
    _delete_rects.clear()
    var y := 24.0 - _scroll_y
    _draw_tree(screen_data, 0, y, font, mouse_pos)


func _draw_tree(element: Dictionary, depth: int, y: float, font: Font, mouse_pos: Vector2) -> float:
    if element.is_empty():
        return y
    var eid: String = str(element.get("id", "?"))
    var etype: String = str(element.get("type", "?"))
    var indent := PAD + depth * INDENT
    var row_rect := Rect2(indent, y, size.x - indent - PAD, ROW_H)

    if y + ROW_H >= 0 and y < size.y:
        _row_rects.append({"id": eid, "rect": row_rect})

        var is_selected := eid == selected_id
        var is_hovered := row_rect.has_point(mouse_pos)
        var bg: Color
        if is_selected:
            bg = Color(0.3, 0.55, 0.85, 0.7)
        elif is_hovered:
            bg = Color(0.25, 0.3, 0.45, 0.4)
        else:
            bg = Color(0.15, 0.17, 0.25, 0.3)
        draw_rect(row_rect, bg)

        # Type indicator dot
        var dot_col: Color = UITypes.ELEMENT_COLORS.get(etype, Color(0.5, 0.5, 0.5))
        draw_circle(Vector2(indent + 6, y + ROW_H * 0.5), 4, dot_col)

        # Label
        var label := "%s (%s)" % [eid, etype]
        var text_col := Color(1, 1, 1, 1) if is_selected else Color(0.8, 0.85, 0.9, 1)
        draw_string(font, Vector2(indent + 14, y + 15), label,
            HORIZONTAL_ALIGNMENT_LEFT, int(row_rect.size.x - 30), 10, text_col)

        # Delete button (small x)
        var del_rect := Rect2(row_rect.position.x + row_rect.size.x - 16, y + 3, 14, 14)
        _delete_rects.append({"id": eid, "rect": del_rect})
        var del_hover := del_rect.has_point(mouse_pos)
        draw_rect(del_rect, Color(0.8, 0.25, 0.25, 0.7 if del_hover else 0.3))
        draw_string(font, del_rect.position + Vector2(3, 11), "x",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(1, 1, 1, 1) if del_hover else Color(0.7, 0.7, 0.7, 0.8))

    y += ROW_H + 2

    # Recurse into children
    var children_v: Variant = element.get("children", [])
    if typeof(children_v) == TYPE_ARRAY:
        for child_v in (children_v as Array):
            if typeof(child_v) == TYPE_DICTIONARY:
                y = _draw_tree(child_v, depth + 1, y, font, mouse_pos)

    return y
