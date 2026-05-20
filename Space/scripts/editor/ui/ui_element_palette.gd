extends Control

# Left-side element palette for the UI screen editor. Shows available
# element types that can be dragged or clicked to add to the current screen.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes = preload("res://Space/scripts/shared/ui/ui_types.gd")

signal element_add_requested(element_type: String)

var editor: Node = null

const PAD: float = 12.0
const ITEM_H: float = 32.0
const GAP: float = 4.0

var _item_rects: Array = []  # [{type, rect}]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for entry in _item_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    element_add_requested.emit(str(entry["type"]))
                    accept_event()
                    return


func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.2, 1.0))

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, Vector2(PAD, 22), "ELEMENTS",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)

    _item_rects.clear()
    var y := 34.0

    for type_str in UITypes.ELEMENT_TYPES:
        var type: String = str(type_str)
        var rect := Rect2(PAD, y, size.x - PAD * 2, ITEM_H)
        _item_rects.append({"type": type, "rect": rect})

        var hovered := rect.has_point(mouse_pos)
        var col: Color = UITypes.ELEMENT_COLORS.get(type, Color(0.5, 0.5, 0.5, 0.5))
        if hovered:
            col.a = 0.9
        else:
            col.a = 0.5
        draw_rect(rect, col)

        var label: String = UITypes.element_label(type)
        draw_string(font, rect.position + Vector2(8, 20), label,
            HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 16), 12,
            Color(1, 1, 1, 1) if hovered else Color(0.85, 0.9, 0.95, 1))

        y += ITEM_H + GAP

    # Screen selector section
    y += GAP * 2
    draw_string(font, Vector2(PAD, y + 14), "SCREENS",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    y += 22

    for sid in UITypes.SCREEN_IDS:
        var _label: String = str(UITypes.SCREEN_LABELS.get(sid, sid))
        var rect := Rect2(PAD, y, size.x - PAD * 2, 24)
        var hovered := rect.has_point(mouse_pos)
        var is_active: bool = editor != null and editor.has_method("get_active_screen_id") and str(editor.get_active_screen_id()) == sid
        var bg := Color(0.3, 0.55, 0.8, 0.8) if is_active else (Color(0.25, 0.3, 0.45, 0.5) if hovered else Color(0.18, 0.2, 0.28, 0.3))
        draw_rect(rect, bg)
        draw_string(font, rect.position + Vector2(6, 16), sid,
            HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 12), 11,
            Color(1, 1, 1, 1) if is_active else Color(0.7, 0.75, 0.85, 1))
        y += 28
