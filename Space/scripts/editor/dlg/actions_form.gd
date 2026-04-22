class_name DlgActionsForm
extends VBoxContainer

# Form builder for a list of action dicts. Each action is rendered as
# its own row with a type dropdown + per-type fields + delete button.
# A footer Add Action bar appends new rows. Emits `changed` on any edit.

signal changed

const EcaSchemaLib := preload("res://Space/scripts/editor/dlg/eca_schema.gd")

var _rows_box: VBoxContainer = null
var _add_option: OptionButton = null
var _suppress_emit: bool = false
var _rows: Array = []  # each: {"box": HBoxContainer, "type": String, "fields": {key -> Control}}
var _last_errors: Array = []


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    _rows_box = VBoxContainer.new()
    add_child(_rows_box)

    var add_row := HBoxContainer.new()
    add_child(add_row)
    var lbl := Label.new()
    lbl.text = "Add action:"
    lbl.tooltip_text = "Append a new action to the selected rule. Actions run top-to-bottom."
    add_row.add_child(lbl)
    _add_option = OptionButton.new()
    _add_option.add_item("(pick type)")
    for label in EcaSchemaLib.action_labels():
        _add_option.add_item(str(label))
    _add_option.tooltip_text = "Choose which action type to append to this rule."
    add_row.add_child(_add_option)
    var add_btn := Button.new()
    add_btn.text = "+ Add"
    add_btn.tooltip_text = "Add the selected action type to the bottom of the action list."
    add_btn.pressed.connect(_on_add_pressed)
    add_row.add_child(add_btn)


func open(actions: Array) -> void:
    _suppress_emit = true
    for row in _rows:
        (row as Dictionary).get("box").queue_free()
    _rows.clear()
    for action_v in actions:
        if typeof(action_v) != TYPE_DICTIONARY:
            continue
        _append_row(action_v)
    _suppress_emit = false


func get_value() -> Array:
    _last_errors.clear()
    var out: Array = []
    for row_v in _rows:
        var row: Dictionary = row_v
        var type_name: String = str(row.get("type", ""))
        if type_name.is_empty():
            continue
        var schema := EcaSchemaLib.find_action_schema(type_name)
        var label := str(schema.get("label", type_name))
        var entry: Dictionary = {"type": type_name}
        var fields: Dictionary = row.get("fields", {})
        var field_specs: Array = schema.get("fields", [])
        for spec in field_specs:
            var key: String = spec[0]
            var field_label: String = spec[1]
            var kind: String = spec[2]
            var control: Control = fields.get(key)
            if control != null:
                var parse := _read_field(control, kind)
                if not bool(parse.get("ok", false)):
                    _last_errors.append("%s: %s must be %s." % [label, field_label, _kind_label(kind)])
                else:
                    entry[key] = parse.get("value")
        out.append(entry)
    return out


func has_error() -> bool:
    get_value()
    return not _last_errors.is_empty()


func error_text() -> String:
    get_value()
    if _last_errors.is_empty():
        return ""
    return str(_last_errors[0])


func _on_add_pressed() -> void:
    var idx := _add_option.get_selected()
    if idx <= 0:
        return
    var names := EcaSchemaLib.action_type_names()
    var real_idx := idx - 1
    if real_idx < 0 or real_idx >= names.size():
        return
    var type_name: String = str(names[real_idx])
    _append_row({"type": type_name})
    _add_option.select(0)
    _emit_changed()


func _append_row(seed_data: Dictionary) -> void:
    var type_name: String = str(seed_data.get("type", ""))
    var box := HBoxContainer.new()
    _rows_box.add_child(box)

    var type_lbl := Label.new()
    var schema := EcaSchemaLib.find_action_schema(type_name)
    var action_label: String = str(schema.get("label", type_name))
    var action_help: String = EcaSchemaLib.action_help(type_name)
    type_lbl.text = action_label
    type_lbl.custom_minimum_size = Vector2(140, 0)
    type_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
    type_lbl.tooltip_text = action_help
    type_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
    box.add_child(type_lbl)

    var fields_box := HBoxContainer.new()
    box.add_child(fields_box)
    var field_controls: Dictionary = {}
    var field_specs: Array = schema.get("fields", [])
    for spec in field_specs:
        var key: String = spec[0]
        var label: String = spec[1]
        var kind: String = spec[2]
        var sub_lbl := Label.new()
        sub_lbl.text = label + ":"
        var field_tip := _field_tooltip(action_label, action_help, label, kind)
        sub_lbl.tooltip_text = field_tip
        fields_box.add_child(sub_lbl)
        var control := _make_field(kind, seed_data.get(key, null))
        control.tooltip_text = field_tip
        fields_box.add_child(control)
        field_controls[key] = control

    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.tooltip_text = "Delete this action row."
    del_btn.pressed.connect(_on_delete_row.bind(box))
    box.add_child(del_btn)

    _rows.append({"box": box, "type": type_name, "fields": field_controls})


func _on_delete_row(row_box: HBoxContainer) -> void:
    for i in _rows.size():
        if (_rows[i] as Dictionary).get("box") == row_box:
            _rows.remove_at(i)
            break
    row_box.queue_free()
    _emit_changed()


func _make_field(kind: String, initial: Variant) -> Control:
    match kind:
        "bool":
            var cb := CheckBox.new()
            cb.button_pressed = bool(initial) if initial != null else false
            cb.toggled.connect(_emit_changed_arg)
            return cb
        _:
            var le := LineEdit.new()
            le.custom_minimum_size = Vector2(120, 0)
            if initial != null:
                if kind == "int" or kind == "opt_int":
                    le.text = str(int(initial))
                elif kind == "float" or kind == "opt_float":
                    le.text = "%f" % float(initial)
                else:
                    le.text = str(initial)
            le.text_changed.connect(func(_t): _emit_changed())
            return le


func _read_field(control: Control, kind: String) -> Dictionary:
    match kind:
        "bool":
            return {"ok": true, "value": (control as CheckBox).button_pressed if control is CheckBox else false}
        "int":
            if control is LineEdit:
                var text := (control as LineEdit).text.strip_edges()
                if _is_valid_int_string(text):
                    return {"ok": true, "value": int(text)}
            return {"ok": false, "value": 0}
        "opt_int":
            if control is LineEdit:
                var text := (control as LineEdit).text.strip_edges()
                if text.is_empty():
                    return {"ok": true, "value": 0}
                if _is_valid_int_string(text):
                    return {"ok": true, "value": int(text)}
            return {"ok": false, "value": 0}
        "float":
            if control is LineEdit:
                var text := (control as LineEdit).text.strip_edges()
                if _is_valid_float_string(text):
                    return {"ok": true, "value": float(text)}
            return {"ok": false, "value": 0.0}
        "opt_float":
            if control is LineEdit:
                var text := (control as LineEdit).text.strip_edges()
                if text.is_empty():
                    return {"ok": true, "value": 0.0}
                if _is_valid_float_string(text):
                    return {"ok": true, "value": float(text)}
            return {"ok": false, "value": 0.0}
        "opt_string":
            return {"ok": true, "value": (control as LineEdit).text.strip_edges() if control is LineEdit else ""}
        _:
            return {"ok": true, "value": (control as LineEdit).text.strip_edges() if control is LineEdit else ""}


func _emit_changed_arg(_arg) -> void:
    _emit_changed()


func _emit_changed() -> void:
    if not _suppress_emit:
        changed.emit()


func _kind_label(kind: String) -> String:
    match kind:
        "int":
            return "a whole number"
        "float":
            return "a number"
        "opt_int":
            return "a whole number or blank"
        "opt_float":
            return "a number or blank"
        "opt_string":
            return "text"
        _:
            return kind


func _is_valid_int_string(text: String) -> bool:
    if text.is_empty():
        return false
    var start := 0
    if text.begins_with("-"):
        if text.length() == 1:
            return false
        start = 1
    for i in range(start, text.length()):
        var ch := text.unicode_at(i)
        if ch < 48 or ch > 57:
            return false
    return true


func _is_valid_float_string(text: String) -> bool:
    if text.is_empty():
        return false
    var start := 0
    var saw_dot := false
    var saw_digit := false
    if text.begins_with("-"):
        if text.length() == 1:
            return false
        start = 1
    for i in range(start, text.length()):
        var ch := text.unicode_at(i)
        if ch == 46:
            if saw_dot:
                return false
            saw_dot = true
            continue
        if ch < 48 or ch > 57:
            return false
        saw_digit = true
    return saw_digit


func _field_tooltip(action_label: String, action_help: String, field_label: String, kind: String) -> String:
    var tip := "%s for %s." % [field_label.capitalize(), action_label]
    if not action_help.is_empty():
        tip += " " + action_help
    match kind:
        "int":
            tip += " Enter a whole number."
        "float":
            tip += " Enter a number; decimals are allowed."
        "opt_int":
            tip += " Enter a whole number or leave blank."
        "opt_float":
            tip += " Enter a number or leave blank."
        "bool":
            tip += " Toggle on or off."
        "opt_string":
            tip += " Optional text field."
        _:
            tip += " Enter text."
    return tip
