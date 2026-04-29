extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const BehTypes = preload("res://Space/scripts/editor/beh/beh_types.gd")

# Right pane for the behavior editor. Shows the fields of the currently
# selected tree node: type (clickable → type picker), name, optional
# action/condition name (for leaves), and a key/value params editor
# backed by the shared text modal. Also exposes top-level behavior
# metadata (name, description) when the root is selected.

var editor: Node = null

const HEADER_H: float = 42.0
const FIELD_H: float = 38.0
const PAD: float = 14.0

var _field_rects: Array = []  # [{field, rect, kind, [param_key]}]
var _type_btn_rect: Rect2 = Rect2()
var _add_param_rect: Rect2 = Rect2()

var _scroll: float = 0.0
var _content_h: float = 0.0


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
            _scroll = min(_scroll + 40.0, max(0.0, _content_h - size.y))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 40.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _type_btn_rect.has_point(mb.position):
                editor.request_pick_node_type(editor.selected_node_path)
                accept_event()
                return
            if _add_param_rect.has_point(mb.position):
                editor.request_add_node_param()
                accept_event()
                return
            for row in _field_rects:
                if (row["rect"] as Rect2).has_point(mb.position):
                    _dispatch_field(row)
                    accept_event()
                    return


func _dispatch_field(row: Dictionary) -> void:
    var kind := str(row["kind"])
    var field := str(row["field"])
    if kind == "behavior_field":
        var title := "Edit %s" % field
        editor.request_edit_behavior_field(field, title, _prompt_for_behavior_field(field))
    elif kind == "node_field":
        var title := "Edit %s" % field
        editor.request_edit_node_field(field, title, _prompt_for_node_field(field))
    elif kind == "param":
        var key := str(row["param_key"])
        editor.request_edit_node_param(key)
    elif kind == "param_delete":
        var key := str(row["param_key"])
        editor.delete_node_param(key)


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    _field_rects.clear()
    _type_btn_rect = Rect2()
    _add_param_rect = Rect2()

    var b: Dictionary = editor.get_selected_behavior()
    if b.is_empty():
        draw_string(font, Vector2(PAD + 4, 36),
            "No behavior selected.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPanels.TEXT_PANEL)
        return

    var node: Dictionary = editor.get_selected_node()
    var path_v: Variant = editor.selected_node_path
    var path_is_root: bool = typeof(path_v) == TYPE_ARRAY and (path_v as Array).is_empty()

    var y: float = PAD - _scroll
    y = _draw_section_header(font, y, "BEHAVIOR")
    y = _draw_row(font, mouse_pos, y, "name", "Name",
        str(b.get("name", "")), "behavior_field")
    y = _draw_row(font, mouse_pos, y, "description", "Description",
        str(b.get("description", "")), "behavior_field")
    y += 6

    y = _draw_section_header(font, y, "NODE" + ("  (root)" if path_is_root else ""))

    if node.is_empty():
        draw_string(font, Vector2(PAD + 4, y + 22),
            "No node selected.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.78, 0.65, 1))
        _content_h = y + 60
        return

    var type_str := str(node.get("type", ""))
    y = _draw_type_row(font, mouse_pos, y, type_str)
    y = _draw_row(font, mouse_pos, y, "name", "Name",
        str(node.get("name", "")), "node_field")

    if type_str == "action":
        var a_name := str(node.get("action", ""))
        var a_schema := BehLeafSchema.find_schema("action", a_name)
        var a_val := a_name
        var a_unregistered := a_schema.is_empty() and not a_name.is_empty()
        if not a_schema.is_empty():
            a_val = "%s (%s)" % [str(a_schema.get("label", "")), a_name]
        elif a_unregistered:
            a_val = "%s  [!] unregistered" % a_name
        y = _draw_row(font, mouse_pos, y, "action", "Action",
            a_val, "node_field")
        if a_unregistered:
            y = _draw_unregistered_warning(font, y, a_name, "action", "idle")
    elif type_str == "condition":
        var c_name := str(node.get("condition", ""))
        var c_schema := BehLeafSchema.find_schema("condition", c_name)
        var c_val := c_name
        var c_unregistered := c_schema.is_empty() and not c_name.is_empty()
        if not c_schema.is_empty():
            c_val = "%s (%s)" % [str(c_schema.get("label", "")), c_name]
        elif c_unregistered:
            c_val = "%s  [!] unregistered" % c_name
        y = _draw_row(font, mouse_pos, y, "condition", "Condition",
            c_val, "node_field")
        if c_unregistered:
            y = _draw_unregistered_warning(font, y, c_name, "condition", "always")

    y += 6
    y = _draw_section_header(font, y, "PARAMS")

    var params_v: Variant = node.get("params", {})
    if typeof(params_v) != TYPE_DICTIONARY:
        params_v = {}
    var params: Dictionary = params_v
    var schema := BehLeafSchema.find_schema(type_str, str(node.get(type_str, "")))
    if params.is_empty() and schema.is_empty():
        draw_string(font, Vector2(PAD + 4, y + 18),
            "(none)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.5, 0.72, 0.6, 1))
        y += 28
    else:
        var drawn_keys: Dictionary = {}
        if not schema.is_empty():
            for f_v in schema.get("fields", []):
                var f: Array = f_v
                var sk: String = str(f[0])
                var label: String = str(f[1])
                var kind_str: String = str(f[2])
                var val_s: String = ""
                if params.has(sk):
                    val_s = str(params[sk])
                else:
                    val_s = "(default: %s)" % str(f[3])
                y = _draw_param_row(font, mouse_pos, y, sk, val_s, label, kind_str)
                drawn_keys[sk] = true
        var keys := params.keys()
        keys.sort()
        for k_v in keys:
            var k := str(k_v)
            if drawn_keys.has(k):
                continue
            var v_str := str(params[k])
            y = _draw_param_row(font, mouse_pos, y, k, v_str, "", "")

    y += 6
    _add_param_rect = Rect2(PAD, y, size.x - PAD * 2.0, 30.0)
    var add_hover := _add_param_rect.has_point(mouse_pos)
    var add_bg: Color
    if add_hover:
        add_bg = Color(0.22, 0.4, 0.28, 0.95)
    else:
        add_bg = Color(0.1, 0.18, 0.12, 0.85)
    draw_rect(_add_param_rect, add_bg)
    draw_rect(_add_param_rect, Color(0.4, 0.8, 0.55, 0.9), false, 1.0)
    draw_string(font, Vector2(_add_param_rect.position.x + 8,
        _add_param_rect.position.y + 19),
        "+ ADD PARAM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(0.85, 1.0, 0.92, 1))
    if add_hover:
        EditorTooltip.show_text("Add a new key/value parameter to this node. Params are passed to the action/condition handler at runtime, e.g. speed=80, range=4.")

    y += 40
    _content_h = y + _scroll


func _draw_unregistered_warning(font: Font, y: float, leaf_name: String,
        leaf_kind: String, fallback_name: String) -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0, 34.0)
    draw_rect(rect, Color(0.32, 0.14, 0.08, 0.85))
    draw_rect(rect, Color(1.0, 0.55, 0.35, 0.95), false, 1.0)
    var msg := "[!] '%s' is not a registered %s — runtime falls back to '%s'." % [
        leaf_name, leaf_kind, fallback_name]
    draw_string(font, rect.position + Vector2(10, 14),
        msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(1.0, 0.78, 0.5, 1))
    var hint := "Click the row above and pick a registered %s name." % leaf_kind
    draw_string(font, rect.position + Vector2(10, 28),
        hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(1.0, 0.7, 0.45, 1))
    return y + rect.size.y + 4


func _draw_section_header(font: Font, y: float, label: String) -> float:
    draw_string(font, Vector2(PAD + 4, y + 18),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.55, 0.88, 0.7, 1))
    draw_line(Vector2(PAD, y + 26), Vector2(size.x - PAD, y + 26),
        Color(0.35, 0.6, 0.45, 0.8), 1.0)
    return y + 30


func _draw_row(font: Font, mouse_pos: Vector2, y: float, field: String,
        label: String, value: String, kind: String) -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0, FIELD_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.4, 0.3, 0.95)
    else:
        bg = Color(0.1, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.35, 0.6, 0.45, 0.85), false, 1.0)

    draw_string(font, rect.position + Vector2(10, 14),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.72, 1))

    var shown := value
    var vcol := Color(0.85, 0.98, 0.92, 1) if not hover else Color(1, 1, 1, 1)
    if shown == "":
        shown = "(empty)"
        vcol = Color(0.5, 0.72, 0.6, 1)

    var max_chars: int = int((rect.size.x - 20.0) / 6.0)
    if shown.length() > max_chars and max_chars > 3:
        shown = shown.substr(0, max_chars - 3) + "..."
    draw_string(font, rect.position + Vector2(10, 30),
        shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vcol)

    _field_rects.append({
        "field": field,
        "rect": rect,
        "kind": kind,
    })
    if hover:
        EditorTooltip.show_text("Click to edit \"%s\". %s" % [label, _tooltip_for_field(field, kind)])
    return y + FIELD_H + 4


func _draw_type_row(font: Font, mouse_pos: Vector2, y: float,
        type_str: String) -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0, FIELD_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.4, 0.3, 0.95)
    else:
        bg = Color(0.1, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.35, 0.6, 0.45, 0.85), false, 1.0)

    draw_string(font, rect.position + Vector2(10, 14),
        "Type", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.72, 1))

    var swatch := Rect2(rect.position.x + 10, rect.position.y + 22, 12, 12)
    draw_rect(swatch, BehTypes.type_color(type_str))
    draw_string(font, rect.position + Vector2(28, 34),
        type_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 1, 1) if hover else Color(0.85, 0.98, 0.92, 1))
    draw_string(font, Vector2(rect.position.x + rect.size.x - 64,
        rect.position.y + 30),
        "▾ pick", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.7, 1))

    _type_btn_rect = rect
    if hover:
        EditorTooltip.show_text("Click to change the node's type. Composites hold many children, decorators wrap one child, leaves are actions or conditions. Changing type may invalidate children.")
    return y + FIELD_H + 4


func _draw_param_row(font: Font, mouse_pos: Vector2, y: float,
        key: String, value: String, schema_label: String = "",
        schema_kind: String = "") -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0 - 30.0, FIELD_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.4, 0.3, 0.95)
    else:
        bg = Color(0.1, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.35, 0.6, 0.45, 0.85), false, 1.0)

    var header_text: String = key
    if not schema_label.is_empty():
        header_text = "%s  (%s)" % [key, schema_kind]
    draw_string(font, rect.position + Vector2(10, 14),
        header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.72, 1))
    var shown := value
    var max_chars: int = int((rect.size.x - 20.0) / 6.0)
    if shown.length() > max_chars and max_chars > 3:
        shown = shown.substr(0, max_chars - 3) + "..."
    var is_default := shown.begins_with("(default")
    var text_col: Color
    if is_default:
        text_col = Color(0.55, 0.75, 0.65, 1)
    elif hover:
        text_col = Color(1, 1, 1, 1)
    else:
        text_col = Color(0.85, 0.98, 0.92, 1)
    draw_string(font, rect.position + Vector2(10, 30),
        shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

    _field_rects.append({
        "field": "param",
        "rect": rect,
        "kind": "param",
        "param_key": key,
    })
    if hover:
        var tip: String
        if schema_label.is_empty():
            tip = "Param \"%s\" = %s. Click to edit." % [key, value]
        else:
            tip = "%s (%s) — %s. Click to edit; enums and bools open a picker." % [schema_label, schema_kind, value]
        EditorTooltip.show_text(tip)

    var del_rect := Rect2(rect.position.x + rect.size.x + 4.0,
        rect.position.y + (FIELD_H - 26) * 0.5, 26, 26)
    var del_hover := del_rect.has_point(mouse_pos)
    var del_bg: Color
    if del_hover:
        del_bg = Color(0.55, 0.25, 0.25, 0.95)
    else:
        del_bg = Color(0.14, 0.2, 0.16, 0.85)
    draw_rect(del_rect, del_bg)
    draw_rect(del_rect, Color(0.95, 0.45, 0.4, 0.9), false, 1.0)
    draw_string(font, del_rect.position + Vector2(9, 18),
        "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
        Color(1, 0.95, 0.95, 1))
    _field_rects.append({
        "field": "param",
        "rect": del_rect,
        "kind": "param_delete",
        "param_key": key,
    })
    if del_hover:
        EditorTooltip.show_text("Delete param \"%s\". The runtime handler will fall back to its default value (or fail if the param is required)." % key)

    return y + FIELD_H + 4


func _prompt_for_behavior_field(field: String) -> String:
    if field == "name":
        return "Human-readable label for this behavior."
    if field == "description":
        return "Short description. Optional."
    return ""


func _prompt_for_node_field(field: String) -> String:
    if field == "name":
        return "Display label for this node. Shown in the tree view."
    if field == "action":
        return "Action name — maps to a runtime action. e.g. walk_left"
    if field == "condition":
        return "Condition name — maps to a runtime condition. e.g. wall_ahead"
    return ""


func _tooltip_for_field(field: String, kind: String) -> String:
    if kind == "behavior_field":
        if field == "name":
            return "Human-readable label for the whole behavior. Used in pickers; the id is what entities reference."
        if field == "description":
            return "Free-form description of what this behavior does. Optional, for your own reference."
    elif kind == "node_field":
        if field == "name":
            return "Display label for this node in the tree view. Purely cosmetic — does not affect behavior."
        if field == "action":
            return "Name of the runtime action handler to invoke (e.g. walk_left, attack). Must match a registered action in the runtime."
        if field == "condition":
            return "Name of the runtime condition handler to query (e.g. wall_ahead, see_player). Must match a registered condition in the runtime."
    return "Opens a text input modal."
