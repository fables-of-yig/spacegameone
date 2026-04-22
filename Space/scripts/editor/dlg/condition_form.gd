class_name DlgConditionForm
extends VBoxContainer

# Form builder for a single condition dict. Attach as a VBoxContainer,
# call open(current_value) to populate, get_value() to read back. Emits
# `changed` when any input changes so hosts can mark dirty.
#
# Supports both flat single-clause editing and raw JSON editing for
# composite conditions like and/or/not.

signal changed

const EcaSchemaLib := preload("res://Space/scripts/editor/dlg/eca_schema.gd")

var _type_option: OptionButton = null
var _raw_toggle: CheckBox = null
var _fields_box: VBoxContainer = null
var _raw_box: VBoxContainer = null
var _raw_edit: TextEdit = null
var _field_controls: Dictionary = {}
var _current_type: String = ""
var _suppress_emit: bool = false
var _last_error: String = ""


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    var header := HBoxContainer.new()
    add_child(header)
    var lbl := Label.new()
    lbl.text = "Type:"
    lbl.tooltip_text = "Choose the condition clause type."
    header.add_child(lbl)
    _type_option = OptionButton.new()
    _type_option.add_item("(none)")
    for label in EcaSchemaLib.condition_labels():
        _type_option.add_item(str(label))
    _type_option.tooltip_text = "Choose the condition clause type."
    _type_option.item_selected.connect(_on_type_changed)
    header.add_child(_type_option)

    _raw_toggle = CheckBox.new()
    _raw_toggle.text = "Raw JSON"
    _raw_toggle.tooltip_text = "Switch to raw JSON mode for compound logic such as and/or/not trees."
    _raw_toggle.toggled.connect(_on_raw_toggled)
    header.add_child(_raw_toggle)

    _fields_box = VBoxContainer.new()
    add_child(_fields_box)

    _raw_box = VBoxContainer.new()
    _raw_box.visible = false
    add_child(_raw_box)
    var raw_lbl := Label.new()
    raw_lbl.text = "Condition JSON"
    raw_lbl.tooltip_text = "Author a full condition object manually when simple row editing is not enough."
    _raw_box.add_child(raw_lbl)
    _raw_edit = TextEdit.new()
    _raw_edit.custom_minimum_size = Vector2(0, 96)
    _raw_edit.placeholder_text = "{\"type\":\"and\",\"children\":[...]}"
    _raw_edit.tooltip_text = "Full condition JSON object. Use this for nested and/or/not logic."
    _raw_edit.text_changed.connect(func(): _emit_changed(null))
    _raw_box.add_child(_raw_edit)


func open(value: Dictionary) -> void:
    _suppress_emit = true
    if _supports_simple_mode(value):
        _raw_toggle.button_pressed = false
        _current_type = str(value.get("type", ""))
        var idx := EcaSchemaLib.condition_type_names().find(_current_type)
        _type_option.select(idx + 1 if idx >= 0 else 0)
        _type_option.tooltip_text = EcaSchemaLib.condition_help(_current_type)
        _rebuild_fields(value)
        _raw_edit.text = ""
    else:
        _raw_toggle.button_pressed = true
        _current_type = ""
        _type_option.select(0)
        _type_option.tooltip_text = ""
        _rebuild_fields({})
        _raw_edit.text = JSON.stringify(value, "  ") if not value.is_empty() else ""
    _sync_mode_visibility()
    _suppress_emit = false


func get_value() -> Dictionary:
    _last_error = ""
    if _is_raw_mode():
        var trimmed := _raw_edit.text.strip_edges()
        if trimmed.is_empty():
            return {}
        var parsed := _parse_raw_value()
        return parsed if not parsed.is_empty() else {}
    if _current_type.is_empty():
        return {}
    var out: Dictionary = {"type": _current_type}
    var schema := EcaSchemaLib.find_condition_schema(_current_type)
    var fields: Array = schema.get("fields", [])
    for field_def in fields:
        var key: String = field_def[0]
        var label: String = field_def[1]
        var kind: String = field_def[2]
        var control: Control = _field_controls.get(key)
        if control == null:
            continue
        var parse := _read_field(control, kind)
        if not bool(parse.get("ok", false)):
            _last_error = "%s must be %s." % [label, _kind_label(kind)]
            return {}
        out[key] = parse.get("value")
    return out


func has_error() -> bool:
    if _is_raw_mode():
        var trimmed := _raw_edit.text.strip_edges()
        if trimmed.is_empty():
            return false
        return _parse_raw_value().is_empty()
    get_value()
    return not _last_error.is_empty()


func error_text() -> String:
    if _is_raw_mode():
        var trimmed := _raw_edit.text.strip_edges()
        if trimmed.is_empty():
            return ""
        var parser := JSON.new()
        var err := parser.parse(trimmed)
        if err != OK:
            return "Condition JSON is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
        if typeof(parser.data) != TYPE_DICTIONARY:
            return "Condition JSON must be a single JSON object"
        return ""
    get_value()
    return _last_error


func _on_type_changed(option_idx: int) -> void:
    if _is_raw_mode():
        return
    if option_idx == 0:
        _current_type = ""
    else:
        var names := EcaSchemaLib.condition_type_names()
        var real_idx := option_idx - 1
        if real_idx >= 0 and real_idx < names.size():
            _current_type = str(names[real_idx])
    _type_option.tooltip_text = EcaSchemaLib.condition_help(_current_type)
    _rebuild_fields({})
    if not _suppress_emit:
        changed.emit()


func _on_raw_toggled(enabled: bool) -> void:
    if enabled:
        var current_value := _build_simple_value()
        _raw_edit.text = JSON.stringify(current_value, "  ") if not current_value.is_empty() else ""
    else:
        var parsed := _parse_raw_value()
        if _supports_simple_mode(parsed):
            _current_type = str(parsed.get("type", ""))
            var idx := EcaSchemaLib.condition_type_names().find(_current_type)
            _type_option.select(idx + 1 if idx >= 0 else 0)
            _type_option.tooltip_text = EcaSchemaLib.condition_help(_current_type)
            _rebuild_fields(parsed)
        else:
            _current_type = ""
            _type_option.select(0)
            _type_option.tooltip_text = ""
            _rebuild_fields({})
    _sync_mode_visibility()
    if not _suppress_emit:
        changed.emit()


func _rebuild_fields(seed: Dictionary) -> void:
    for child in _fields_box.get_children():
        child.queue_free()
    _field_controls.clear()
    if _current_type.is_empty():
        return
    var schema := EcaSchemaLib.find_condition_schema(_current_type)
    var fields: Array = schema.get("fields", [])
    var condition_label: String = str(schema.get("label", _current_type))
    var condition_help: String = EcaSchemaLib.condition_help(_current_type)
    for field_def in fields:
        var key: String = field_def[0]
        var label: String = field_def[1]
        var kind: String = field_def[2]
        var row := HBoxContainer.new()
        var lbl := Label.new()
        lbl.text = label
        lbl.custom_minimum_size = Vector2(110, 0)
        var field_tip := _field_tooltip(condition_label, condition_help, label, kind)
        lbl.tooltip_text = field_tip
        row.add_child(lbl)
        var control := _make_field(kind, seed.get(key, null))
        control.tooltip_text = field_tip
        row.add_child(control)
        _fields_box.add_child(row)
        _field_controls[key] = control


func _sync_mode_visibility() -> void:
    var raw := _is_raw_mode()
    if _type_option != null:
        _type_option.disabled = raw
    if _fields_box != null:
        _fields_box.visible = not raw
    if _raw_box != null:
        _raw_box.visible = raw


func _make_field(kind: String, initial: Variant) -> Control:
    match kind:
        "bool":
            var cb := CheckBox.new()
            cb.button_pressed = bool(initial) if initial != null else false
            cb.toggled.connect(_emit_changed)
            return cb
        _:
            var le := LineEdit.new()
            le.custom_minimum_size = Vector2(160, 0)
            if initial != null:
                if kind == "int":
                    le.text = str(int(initial))
                elif kind == "float":
                    le.text = "%f" % float(initial)
                else:
                    le.text = str(initial)
            le.text_changed.connect(func(_t): _emit_changed(null))
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
        "float":
            if control is LineEdit:
                var text := (control as LineEdit).text.strip_edges()
                if _is_valid_float_string(text):
                    return {"ok": true, "value": float(text)}
            return {"ok": false, "value": 0.0}
        _:
            return {"ok": true, "value": (control as LineEdit).text.strip_edges() if control is LineEdit else ""}


func _emit_changed(_arg) -> void:
    if not _suppress_emit:
        changed.emit()


func _is_raw_mode() -> bool:
    return _raw_toggle != null and _raw_toggle.button_pressed


func _build_simple_value() -> Dictionary:
    if _current_type.is_empty():
        return {}
    var out: Dictionary = {"type": _current_type}
    var schema := EcaSchema.find_condition_schema(_current_type)
    var fields: Array = schema.get("fields", [])
    for field_def in fields:
        var key: String = field_def[0]
        var kind: String = field_def[2]
        var control: Control = _field_controls.get(key)
        if control == null:
            continue
        var parse := _read_field(control, kind)
        if not bool(parse.get("ok", false)):
            return {}
        out[key] = parse.get("value")
    return out


func _supports_simple_mode(value: Dictionary) -> bool:
    if value.is_empty():
        return true
    var type_name := str(value.get("type", "")).strip_edges()
    if type_name.is_empty():
        return false
    return not EcaSchema.find_condition_schema(type_name).is_empty()


func _parse_raw_value() -> Dictionary:
    var trimmed := _raw_edit.text.strip_edges()
    if trimmed.is_empty():
        return {}
    var parser := JSON.new()
    var err := parser.parse(trimmed)
    if err != OK:
        return {}
    if typeof(parser.data) != TYPE_DICTIONARY:
        return {}
    return parser.data


func _kind_label(kind: String) -> String:
    match kind:
        "int":
            return "a whole number"
        "float":
            return "a number"
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


func _field_tooltip(condition_label: String, condition_help: String, field_label: String, kind: String) -> String:
    var tip := "%s for %s." % [field_label.capitalize(), condition_label]
    if not condition_help.is_empty():
        tip += " " + condition_help
    match kind:
        "int":
            tip += " Enter a whole number."
        "float":
            tip += " Enter a number; decimals are allowed."
        "bool":
            tip += " Toggle on or off."
        _:
            tip += " Enter text."
    return tip
