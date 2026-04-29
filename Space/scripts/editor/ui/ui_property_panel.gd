extends Control

# Right-side property panel for the UI screen editor. Shows editable
# properties for the currently selected element: type, id, rect, anchor,
# and type-specific properties (bindings, actions, colors, etc.).

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes = preload("res://Space/scripts/editor/ui/ui_types.gd")

signal property_changed(element_id: String, key: String, value: Variant)

var editor: Node = null
var _element: Dictionary = {}  # Currently displayed element
var _field_edits: Dictionary = {}  # key -> Control
var _field_buttons: Dictionary = {}  # key -> Button
var _scroll_y: float = 0.0
var _rebuild_scheduled: bool = false
const _FIELD_X: float = 144.0
const _FIELD_W_PAD: float = 8.0
const _PICKER_W: float = 28.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    _update_edit_layout()
    queue_redraw()


func show_element(element: Dictionary) -> void:
    _element = element
    _scroll_y = 0.0
    _schedule_rebuild()
    queue_redraw()


func clear() -> void:
    _element = {}
    _schedule_rebuild()
    queue_redraw()


func _schedule_rebuild() -> void:
    if _rebuild_scheduled:
        return
    _rebuild_scheduled = true
    _rebuild_edits_deferred.call_deferred()


func _rebuild_edits_deferred() -> void:
    _rebuild_scheduled = false
    _clear_edits()
    _build_edits()


func _clear_edits() -> void:
    for key in _field_edits.keys():
        var ctrl: Control = _field_edits[key]
        if ctrl != null and is_instance_valid(ctrl):
            ctrl.queue_free()
    for key in _field_buttons.keys():
        var btn: Button = _field_buttons[key]
        if btn != null and is_instance_valid(btn):
            btn.queue_free()
    _field_edits.clear()
    _field_buttons.clear()


func _build_edits() -> void:
    if _element.is_empty():
        return
    # Create line edits for core fields
    var fields: Array = ["id"]
    var rect_d: Variant = _element.get("rect", {})
    if typeof(rect_d) == TYPE_DICTIONARY:
        for k in ["x", "y", "w", "h"]:
            fields.append("rect." + k)

    # Type-specific property fields
    var props: Variant = _element.get("properties", {})
    if typeof(props) == TYPE_DICTIONARY:
        for key in (props as Dictionary).keys():
            fields.append("prop." + str(key))

    var y := 80.0
    for field in fields:
        var val: Variant = _get_field_value(field)
        if _is_enum_field(field):
            var option := OptionButton.new()
            option.size = Vector2(_field_edit_width(field), 22)
            option.position = Vector2(_FIELD_X, y)
            for item in _enum_values(field):
                option.add_item(str(item))
            var selected_idx := _enum_values(field).find(str(val))
            if selected_idx < 0:
                selected_idx = 0
            option.select(selected_idx)
            option.item_selected.connect(_on_enum_selected.bind(field))
            add_child(option)
            _field_edits[field] = option
        else:
            var le := LineEdit.new()
            le.size = Vector2(_field_edit_width(field), 22)
            le.position = Vector2(_FIELD_X, y)
            le.text = str(val)
            le.text_submitted.connect(_on_field_submitted.bind(field))
            le.focus_exited.connect(_on_field_focus_exited.bind(field))
            add_child(le)
            _field_edits[field] = le
        if _is_texture_field(field) or _is_color_field(field):
            var pick_btn := Button.new()
            if _is_texture_field(field):
                pick_btn.text = "..."
                pick_btn.tooltip_text = "Import a PNG for this sprite field."
                pick_btn.pressed.connect(_on_pick_texture_pressed.bind(field))
            else:
                pick_btn.text = "#"
                pick_btn.tooltip_text = "Open the color picker for this color field."
                pick_btn.pressed.connect(_on_pick_color_pressed.bind(field))
            add_child(pick_btn)
            _field_buttons[field] = pick_btn
        y += 28.0
    _update_edit_layout()


func _update_edit_layout() -> void:
    if _field_edits.is_empty():
        return
    var y := 80.0 - _scroll_y
    var fields: Array = ["id"]
    var rect_d: Variant = _element.get("rect", {})
    if typeof(rect_d) == TYPE_DICTIONARY:
        for k in ["x", "y", "w", "h"]:
            fields.append("rect." + k)
    var props: Variant = _element.get("properties", {})
    if typeof(props) == TYPE_DICTIONARY:
        for key in (props as Dictionary).keys():
            fields.append("prop." + str(key))
    for field in fields:
        if not _field_edits.has(field):
            continue
        var ctrl: Control = _field_edits[field]
        if ctrl == null or not is_instance_valid(ctrl):
            continue
        var width := _field_edit_width(field)
        ctrl.size = Vector2(width, 22)
        ctrl.position = Vector2(_FIELD_X, y)
        ctrl.visible = y + ctrl.size.y >= 0.0 and y <= size.y
        if _field_buttons.has(field):
            var btn: Button = _field_buttons[field]
            if btn != null and is_instance_valid(btn):
                btn.size = Vector2(_PICKER_W, 22)
                btn.position = Vector2(_FIELD_X + width + 4.0, y)
                btn.visible = ctrl.visible
        y += 28.0


func _get_field_value(field: String) -> Variant:
    if field == "id":
        return _element.get("id", "")
    if field.begins_with("rect."):
        var k := field.substr(5)
        var rect_d: Variant = _element.get("rect", {})
        if typeof(rect_d) == TYPE_DICTIONARY:
            return (rect_d as Dictionary).get(k, 0)
        return 0
    if field.begins_with("prop."):
        var k := field.substr(5)
        var props: Variant = _element.get("properties", {})
        if typeof(props) == TYPE_DICTIONARY:
            return (props as Dictionary).get(k, "")
        return ""
    return ""


func _on_field_submitted(text: String, field: String) -> void:
    var eid: String = str(_element.get("id", ""))
    if eid.is_empty():
        return
    if field == "id":
        property_changed.emit(eid, "id", text)
    elif field.begins_with("rect."):
        var k := field.substr(5)
        var rect_d: Variant = _element.get("rect", {})
        if typeof(rect_d) != TYPE_DICTIONARY:
            rect_d = {}
            _element["rect"] = rect_d
        if text.is_valid_int():
            (rect_d as Dictionary)[k] = int(text)
        elif text.is_valid_float():
            (rect_d as Dictionary)[k] = float(text)
        else:
            var le_rect: LineEdit = _field_edits.get(field)
            if le_rect != null and is_instance_valid(le_rect):
                le_rect.text = str((rect_d as Dictionary).get(k, 0))
            return
        property_changed.emit(eid, "rect", rect_d)
    elif field.begins_with("prop."):
        var k := field.substr(5)
        var props: Variant = _element.get("properties", {})
        if typeof(props) != TYPE_DICTIONARY:
            props = {}
            _element["properties"] = props
        # Try to preserve the original type
        var old_val: Variant = (props as Dictionary).get(k, "")
        if typeof(old_val) == TYPE_BOOL:
            (props as Dictionary)[k] = text.to_lower() == "true"
        elif typeof(old_val) == TYPE_INT:
            if not text.is_valid_int():
                var le_prop: LineEdit = _field_edits.get(field)
                if le_prop != null and is_instance_valid(le_prop):
                    le_prop.text = str(old_val)
                return
            (props as Dictionary)[k] = int(text)
        elif typeof(old_val) == TYPE_FLOAT:
            if not text.is_valid_float():
                var le_prop_float: LineEdit = _field_edits.get(field)
                if le_prop_float != null and is_instance_valid(le_prop_float):
                    le_prop_float.text = str(old_val)
                return
            (props as Dictionary)[k] = float(text)
        else:
            (props as Dictionary)[k] = text
        property_changed.emit(eid, "properties", props)


func commit_pending_edits() -> void:
    if _element.is_empty():
        return
    for field_v in _field_edits.keys():
        var field: String = str(field_v)
        var ctrl: Variant = _field_edits.get(field)
        if not (ctrl is LineEdit):
            continue
        var le: LineEdit = ctrl
        if le == null or not is_instance_valid(le):
            continue
        _on_field_submitted(le.text, field)


func _on_field_focus_exited(field: String) -> void:
    var le: LineEdit = _field_edits.get(field)
    if le == null or not is_instance_valid(le):
        return
    _on_field_submitted(le.text, field)


func _gui_input(event):
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _scroll_y = maxf(_scroll_y - 28.0, 0.0)
            _update_edit_layout()
            accept_event()
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _scroll_y += 28.0
            _update_edit_layout()
            accept_event()


func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.2, 1.0))
    var font := ThemeDB.fallback_font

    if _element.is_empty():
        draw_string(font, Vector2(12, 30), "No element selected",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL_DIM)
        return

    var etype: String = str(_element.get("type", "?"))
    var _eid: String = str(_element.get("id", "?"))
    var anchor: String = str(_element.get("anchor", "top_left"))

    draw_string(font, Vector2(12, 22), "PROPERTIES",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(12, 42), "Type: %s" % etype,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(12, 58), "Anchor: %s" % anchor,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    # Field labels
    var y := 80.0 - _scroll_y
    var fields: Array = ["id"]
    var rect_d: Variant = _element.get("rect", {})
    if typeof(rect_d) == TYPE_DICTIONARY:
        for k in ["x", "y", "w", "h"]:
            fields.append("rect." + k)
    var props: Variant = _element.get("properties", {})
    if typeof(props) == TYPE_DICTIONARY:
        for key in (props as Dictionary).keys():
            fields.append("prop." + str(key))

    var has_binding_field := false
    for field in fields:
        var label: String = str(field)
        if field.begins_with("prop."):
            label = field.substr(5)
        if label.begins_with("bind_"):
            has_binding_field = true
        if y + 20.0 >= 0.0 and y <= size.y:
            draw_string(font, Vector2(12, y + 15), label,
                HORIZONTAL_ALIGNMENT_LEFT, int(_FIELD_X - 20.0), 10, UIPanels.TEXT_PANEL_DIM)
        y += 28.0

    if has_binding_field:
        _draw_binding_reference(font, y + 6.0)


func _draw_binding_reference(font: Font, y: float) -> void:
    # Reference panel listing valid binding names. The property panel
    # uses text fields (no dropdown), so the author needs a visible list
    # of what resolves at runtime — anything not here will render blank.
    draw_string(font, Vector2(12, y + 14),
        "VALID BINDINGS (paste into bind_* field):",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)
    y += 22.0
    var col := Color(0.7, 0.9, 0.7, 1)
    for src in UiContract.binding_sources():
        if y + 12.0 > size.y - 8.0:
            draw_string(font, Vector2(12, y + 11),
                "... more in ui_contract.gd", HORIZONTAL_ALIGNMENT_LEFT,
                -1, 10, UIPanels.TEXT_PANEL_DIM)
            return
        draw_string(font, Vector2(12, y + 11), str(src),
            HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 16), 10, col)
        y += 13.0
    draw_string(font, Vector2(12, y + 13),
        "RATIOS (0..1, good for progress bars):",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL)
    y += 22.0
    var ratio_col := Color(0.75, 0.8, 1.0, 1)
    for src2 in UiContract.binding_ratios():
        if y + 12.0 > size.y - 8.0:
            return
        draw_string(font, Vector2(12, y + 11), str(src2),
            HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 16), 10, ratio_col)
        y += 13.0


func _field_edit_width(field: String) -> float:
    var width := maxf(size.x - _FIELD_X - _FIELD_W_PAD, 120.0)
    if _is_texture_field(field) or _is_color_field(field):
        width = maxf(width - _PICKER_W - 4.0, 92.0)
    return width


func _is_enum_field(field: String) -> bool:
    if not field.begins_with("prop."):
        return false
    var key := field.substr(5)
    return key in ["sprite_mode"]


func _enum_values(field: String) -> Array:
    if not field.begins_with("prop."):
        return []
    var key := field.substr(5)
    match key:
        "sprite_mode":
            return ["9slice", "stretch"]
    return []


func _is_texture_field(field: String) -> bool:
    if not field.begins_with("prop."):
        return false
    var key := field.substr(5)
    return key in ["sprite_source", "sprite_normal", "sprite_hover", "sprite_pressed"]


func _is_color_field(field: String) -> bool:
    if not field.begins_with("prop."):
        return false
    var key := field.substr(5)
    return key in ["sprite_tint", "tint", "fill_color", "bg_color"]


func _on_pick_texture_pressed(field: String) -> void:
    if editor == null or _element.is_empty() or not field.begins_with("prop."):
        return
    var key := field.substr(5)
    if editor.has_method("request_import_screen_texture"):
        editor.request_import_screen_texture(str(_element.get("id", "")), key)


func _on_pick_color_pressed(field: String) -> void:
    if editor == null or _element.is_empty() or not field.begins_with("prop."):
        return
    var key := field.substr(5)
    var current := str(_get_field_value(field))
    if editor.has_method("request_edit_screen_color"):
        editor.request_edit_screen_color(str(_element.get("id", "")), key, current)


func _on_enum_selected(index: int, field: String) -> void:
    var values := _enum_values(field)
    if index < 0 or index >= values.size():
        return
    _on_field_submitted(str(values[index]), field)
