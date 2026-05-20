extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const BehIO = preload("res://Space/scripts/shared/beh/beh_io.gd")
const BehTypes = preload("res://Space/scripts/shared/beh/beh_types.gd")

# Middle pane that shows the selected behavior's tree as an indented
# flat list. Each row is one node; depth drives the x-offset and a
# color swatch conveys the category (composite / decorator / leaf).
# Clicking a row selects that node (updating the props panel). Toolbar
# at the top holds + ADD CHILD / ↑ / ↓ / × buttons that operate on the
# current selection.

var editor: Node = null

const HEADER_H: float = 44.0
const ROW_H: float = 30.0
const INDENT_PX: float = 22.0
const PAD: float = 12.0

var _rows: Array = []  # [{node, path, depth, rect}]
var _scroll: float = 0.0
var _viewport_h: float = 0.0
var _content_h: float = 0.0

var _add_child_rect: Rect2 = Rect2()
var _del_rect: Rect2 = Rect2()
var _up_rect: Rect2 = Rect2()
var _down_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    clip_contents = true
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
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
            if _add_child_rect.has_point(mb.position):
                editor.add_child_node(_current_selection_path())
                accept_event()
                return
            if _del_rect.has_point(mb.position):
                editor.delete_node(_current_selection_path())
                accept_event()
                return
            if _up_rect.has_point(mb.position):
                editor.move_node(_current_selection_path(), -1)
                accept_event()
                return
            if _down_rect.has_point(mb.position):
                editor.move_node(_current_selection_path(), 1)
                accept_event()
                return
            for row in _rows:
                if (row["rect"] as Rect2).has_point(mb.position):
                    var path_v: Variant = row["path"]
                    if typeof(path_v) == TYPE_ARRAY:
                        editor.select_node(path_v)
                    accept_event()
                    return


func _current_selection_path() -> Array:
    var p_v: Variant = editor.selected_node_path
    if typeof(p_v) != TYPE_ARRAY:
        return []
    return p_v


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var b: Dictionary = editor.get_selected_behavior()
    if b.is_empty():
        _rows.clear()
        _reset_toolbar_rects()
        draw_string(font, Vector2(PAD + 6, 40),
            "No behavior selected.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            UIPanels.TEXT_PANEL)
        draw_string(font, Vector2(PAD + 6, 62),
            "Select one on the left, or click + ADD BEHAVIOR.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL_DIM)
        return

    var header_label := "TREE  %s" % str(b.get("id", ""))
    draw_string(font, Vector2(PAD + 4, 22),
        header_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)

    _draw_toolbar(font, mouse_pos)

    var root_v: Variant = b.get("root", {})
    if typeof(root_v) != TYPE_DICTIONARY:
        _rows.clear()
        return
    var root: Dictionary = root_v

    var flat: Array = BehIO.flatten(root)
    var list_y0: float = HEADER_H + 40
    _viewport_h = size.y - list_y0 - PAD
    _content_h = float(flat.size()) * ROW_H
    if _scroll > max(0.0, _content_h - _viewport_h):
        _scroll = max(0.0, _content_h - _viewport_h)

    _rows.clear()
    var sel_path: Array = _current_selection_path()
    for i in flat.size():
        var entry_v: Variant = flat[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var node_v: Variant = entry.get("node", {})
        if typeof(node_v) != TYPE_DICTIONARY:
            continue
        var node: Dictionary = node_v
        var path_v: Variant = entry.get("path", [])
        var path: Array = path_v if typeof(path_v) == TYPE_ARRAY else []
        var depth: int = int(entry.get("depth", 0))

        var row_y: float = list_y0 + float(i) * ROW_H - _scroll
        var row_rect := Rect2(PAD, row_y, size.x - PAD * 2.0, ROW_H - 4.0)
        _rows.append({
            "node": node,
            "path": path,
            "depth": depth,
            "rect": row_rect,
        })

        if row_rect.position.y + row_rect.size.y < list_y0:
            continue
        if row_rect.position.y > size.y:
            continue

        _draw_tree_row(font, row_rect, node, depth,
            _paths_equal(sel_path, path), mouse_pos)

    if flat.is_empty():
        draw_string(font, Vector2(PAD + 6, list_y0 + 24),
            "Empty tree.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.55, 0.78, 0.65, 1))


func _draw_toolbar(font: Font, mouse_pos: Vector2) -> void:
    var y: float = HEADER_H
    var x: float = PAD
    var btn_h: float = 28.0

    var add_w: float = 120.0
    _add_child_rect = Rect2(x, y, add_w, btn_h)
    _draw_tool_btn(font, _add_child_rect, "+ ADD CHILD",
        _add_child_rect.has_point(mouse_pos),
        Color(0.4, 0.85, 0.6, 1.0))
    if _add_child_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Add a new child node to the currently selected node. Opens a picker — composites hold multiple children, decorators hold one, leaves hold none.")
    x += add_w + 6

    var icon_w: float = 38.0
    _up_rect = Rect2(x, y, icon_w, btn_h)
    _draw_tool_btn(font, _up_rect, "↑",
        _up_rect.has_point(mouse_pos),
        Color(0.45, 0.75, 0.95, 1.0))
    if _up_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Move the selected node one position up among its siblings. Order matters for sequence/selector — they evaluate children left-to-right.")
    x += icon_w + 4
    _down_rect = Rect2(x, y, icon_w, btn_h)
    _draw_tool_btn(font, _down_rect, "↓",
        _down_rect.has_point(mouse_pos),
        Color(0.45, 0.75, 0.95, 1.0))
    if _down_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Move the selected node one position down among its siblings. Order matters for sequence/selector — they evaluate children left-to-right.")
    x += icon_w + 10

    var del_w: float = 70.0
    _del_rect = Rect2(x, y, del_w, btn_h)
    _draw_tool_btn(font, _del_rect, "× DEL",
        _del_rect.has_point(mouse_pos),
        Color(0.95, 0.45, 0.4, 1.0))
    if _del_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Delete the selected node and all of its children. Cannot delete the root node. There is no undo.")


func _draw_tool_btn(font: Font, rect: Rect2, label: String,
        hover: bool, accent: Color) -> void:
    var bg: Color
    if hover:
        bg = Color(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6, 0.95)
    else:
        bg = Color(0.12, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, accent, false, 1.0)
    var label_w := float(label.length()) * 6.0
    draw_string(font, Vector2(rect.position.x + (rect.size.x - label_w) * 0.5,
        rect.position.y + 19),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1, 1, 1, 1) if hover else Color(0.9, 0.95, 0.92, 1))


func _reset_toolbar_rects() -> void:
    _add_child_rect = Rect2()
    _del_rect = Rect2()
    _up_rect = Rect2()
    _down_rect = Rect2()


func _draw_tree_row(font: Font, rect: Rect2, node: Dictionary, depth: int,
        selected: bool, mouse_pos: Vector2) -> void:
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if selected:
        bg = Color(0.3, 0.55, 0.42, 0.95)
    elif hover:
        bg = Color(0.18, 0.3, 0.22, 0.85)
    else:
        bg = Color(0.08, 0.16, 0.1, 0.85)
    draw_rect(rect, bg)

    # Indent line
    var indent_offset: float = float(depth) * INDENT_PX
    for d in depth:
        var line_x: float = rect.position.x + 10.0 + float(d) * INDENT_PX + 6.0
        draw_line(Vector2(line_x, rect.position.y),
            Vector2(line_x, rect.position.y + rect.size.y),
            Color(0.35, 0.55, 0.45, 0.6), 1.0)

    var type_str := str(node.get("type", ""))
    var cat := BehTypes.category_of(type_str)
    var swatch_x: float = rect.position.x + 10.0 + indent_offset
    var swatch_rect := Rect2(swatch_x, rect.position.y + 8.0, 12.0, 12.0)
    draw_rect(swatch_rect, BehTypes.category_color(cat))

    var label_x: float = swatch_x + 18.0
    var display_name := str(node.get("name", BehTypes.type_label(type_str)))
    var label := "%s" % display_name
    if display_name != type_str:
        label = "%s  (%s)" % [display_name, BehTypes.type_label(type_str)]
    var unregistered: bool = false
    var leaf_name: String = ""
    if cat == BehTypes.CAT_LEAF:
        if type_str == "action":
            leaf_name = str(node.get("action", ""))
            label += "  →  %s" % leaf_name
            if BehLeafSchema.find_schema("action", leaf_name).is_empty():
                unregistered = true
        elif type_str == "condition":
            leaf_name = str(node.get("condition", ""))
            label += "  ?  %s" % leaf_name
            if BehLeafSchema.find_schema("condition", leaf_name).is_empty():
                unregistered = true
    if not leaf_name.is_empty() and not unregistered:
        var leaf_schema := BehLeafSchema.find_schema(type_str, leaf_name)
        if not leaf_schema.is_empty():
            var joiner := " -> " if type_str == "action" else " ? "
            label = "%s (%s)%s%s" % [
                display_name,
                BehTypes.type_label(type_str),
                joiner,
                str(leaf_schema.get("label", leaf_name)),
            ]
    if unregistered:
        label += "  [!] unregistered"

    var text_col: Color
    if unregistered and not selected:
        text_col = Color(1.0, 0.55, 0.35, 1)
    elif selected:
        text_col = Color(1, 1, 1, 1)
    else:
        text_col = Color(0.85, 0.98, 0.9, 1)
    draw_string(font, Vector2(label_x, rect.position.y + 18),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

    if BehTypes.accepts_children(type_str):
        var kids_count := 0
        if node.has("children") and typeof(node["children"]) == TYPE_ARRAY:
            kids_count = (node["children"] as Array).size()
        var count_str := "[%d]" % kids_count
        draw_string(font, Vector2(rect.position.x + rect.size.x - 36.0,
            rect.position.y + 18),
            count_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.6, 0.82, 0.7, 1))

    if hover and not selected:
        if unregistered:
            var fallback: String = "idle" if type_str == "action" else "always"
            EditorTooltip.show_text("[!] Leaf name \"%s\" is not registered in the runtime. At runtime this node silently falls back to '%s' and emits a push_warning. Edit the node and pick a registered %s." % [leaf_name, fallback, type_str])
        else:
            EditorTooltip.show_text("%s Click to select and edit details on the right. Internal type: %s." % [BehTypes.type_help(type_str), type_str])


func _paths_equal(a: Array, b: Array) -> bool:
    if a.size() != b.size():
        return false
    for i in a.size():
        if int(a[i]) != int(b[i]):
            return false
    return true
