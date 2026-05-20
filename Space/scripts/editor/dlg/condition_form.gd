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
var _help_label: Label = null
var _field_controls: Dictionary = {}
var _current_type: String = ""
var _suppress_emit: bool = false
var _last_error: String = ""
var _pack_id: String = ""
var _rule_event: String = ""


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    var header := HBoxContainer.new()
    add_child(header)
    var lbl := Label.new()
    lbl.text = "Only if:"
    lbl.tooltip_text = "Choose the requirement that must be true before this can happen."
    header.add_child(lbl)
    _type_option = OptionButton.new()
    _type_option.add_item("(always allowed)")
    for label in EcaSchemaLib.condition_labels():
        _type_option.add_item(str(label))
    _type_option.tooltip_text = "Choose the requirement that must be true before this can happen."
    _type_option.item_selected.connect(_on_type_changed)
    header.add_child(_type_option)

    _raw_toggle = CheckBox.new()
    _raw_toggle.text = "Advanced"
    _raw_toggle.tooltip_text = "Advanced mode for nested AND / OR / NOT logic. Most rules should use the normal picker."
    _raw_toggle.toggled.connect(_on_raw_toggled)
    header.add_child(_raw_toggle)

    _help_label = Label.new()
    _help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _help_label.add_theme_font_size_override("font_size", 10)
    _help_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84))
    add_child(_help_label)

    _fields_box = VBoxContainer.new()
    add_child(_fields_box)

    _raw_box = VBoxContainer.new()
    _raw_box.visible = false
    add_child(_raw_box)
    var raw_lbl := Label.new()
    raw_lbl.text = "Advanced requirement text"
    raw_lbl.tooltip_text = "Use this only when you need nested AND / OR / NOT logic that the simple picker cannot express."
    _raw_box.add_child(raw_lbl)
    _raw_edit = TextEdit.new()
    _raw_edit.custom_minimum_size = Vector2(0, 96)
    _raw_edit.placeholder_text = "{\"type\":\"and\",\"children\":[...]}"
    _raw_edit.tooltip_text = "Full condition object for advanced branching logic."
    _raw_edit.text_changed.connect(func(): _emit_changed(null))
    _raw_box.add_child(_raw_edit)


func set_pack_id(pack_id: String) -> void:
    _pack_id = pack_id.strip_edges()


func set_rule_event(event_name: String) -> void:
    var trimmed := event_name.strip_edges()
    if _rule_event == trimmed:
        return
    _rule_event = trimmed
    # payload_eq's key picker is event-aware: when the rule's event changes,
    # the dropdown contents must refresh. Other condition types are unaffected.
    if _current_type == "payload_eq":
        var snapshot := _build_simple_value()
        _rebuild_fields(snapshot)


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
    _update_help_label()
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
            return "The advanced condition text is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
        if typeof(parser.data) != TYPE_DICTIONARY:
            return "The advanced condition must be one JSON object"
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
    _update_help_label()
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
    _update_help_label()
    if not _suppress_emit:
        changed.emit()


func _rebuild_fields(rng_seed: Dictionary) -> void:
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
        var control := _make_field(kind, rng_seed.get(key, null), _current_type, key)
        control.tooltip_text = field_tip
        row.add_child(control)
        _fields_box.add_child(row)
        _field_controls[key] = control
        EditorTooltipWrap.wrap_tree(row)


func _sync_mode_visibility() -> void:
    var raw := _is_raw_mode()
    if _type_option != null:
        _type_option.disabled = raw
    if _fields_box != null:
        _fields_box.visible = not raw
    if _raw_box != null:
        _raw_box.visible = raw


func _make_field(kind: String, initial: Variant, condition_type: String = "", field_key: String = "") -> Control:
    if _should_use_quest_picker(condition_type, field_key, kind):
        return _make_quest_picker(field_key, initial)
    if _should_use_payload_key_picker(condition_type, field_key, kind):
        return _make_payload_key_picker(initial)
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
            le.placeholder_text = _field_placeholder(condition_type, field_key, kind)
            le.text_changed.connect(func(_t): _emit_changed(null))
            return le


func _read_field(control: Control, kind: String) -> Dictionary:
    if control.has_meta("payload_key_picker"):
        return _read_payload_key_picker(control)
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
            if control is OptionButton:
                var opt_value := _option_selected_value(control as OptionButton)
                return {"ok": not opt_value.is_empty(), "value": opt_value}
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


func _update_help_label() -> void:
    if _help_label == null:
        return
    if _is_raw_mode():
        _help_label.text = "Advanced mode is only for nested logic like AND / OR / NOT groups."
        return
    if _current_type.is_empty():
        _help_label.text = "Leave this empty if the line, choice, or trigger should always be allowed."
        return
    var help_text: String = EcaSchemaLib.condition_help(_current_type)
    var natural_text: String = EcaSchemaLib.condition_summary(_build_simple_value())
    var example_text: String = _condition_example(_current_type)
    var parts: Array = []
    if not natural_text.is_empty():
        parts.append("Reads as: %s." % natural_text)
    if not help_text.is_empty():
        parts.append(help_text)
    if not example_text.is_empty():
        parts.append("Example: %s" % example_text)
    _help_label.text = " ".join(parts)


func _condition_example(condition_type: String) -> String:
    match condition_type:
        "has_item":
            return "id = medkit_small, min_count = 1"
        "has_ability":
            return "id = double_jump"
        "has_tag":
            return "tag = boss_room"
        "has_global_tag":
            return "tag = met_shopkeep"
        "has_flag":
            return "name = met_mayor, value = true"
        "var_eq":
            return "name = gold, value = 100"
        "var_gte":
            return "name = story_step, value = 3"
        "chance_roll":
            return "percent = 25"
        "local_var_eq":
            return "name = intro_step, value = complete"
        "local_var_gte":
            return "name = phase, value = 2"
        "payload_eq":
            return "key = entity_id, value = mayor_npc"
        "quest_status":
            return "quest_id = first_steps, status = active"
        "quest_stage":
            return "quest_id = first_steps, stage_id = start"
        "quest_objective_done":
            return "quest_id = first_steps, stage_id = start, objective_id = get_key"
        _:
            return ""


func _field_placeholder(condition_type: String, field_key: String, _kind: String) -> String:
    if condition_type.begins_with("quest_"):
        match field_key:
            "quest_id":
                return "choose a quest"
            "stage_id":
                return "choose a quest stage"
            "objective_id":
                return "choose a quest objective"
            "status":
                return "inactive / active / complete"
    match field_key:
        "id":
            match condition_type:
                "has_item":
                    return "medkit_small"
                "has_ability":
                    return "double_jump"
                _:
                    return "snake_case_id"
        "tag":
            return "boss_room"
        "name":
            match condition_type:
                "has_flag":
                    return "met_mayor"
                "var_eq", "var_gte":
                    return "story_step"
                "local_var_eq", "local_var_gte":
                    return "intro_step"
                _:
                    return "name"
        "key":
            return "entity_id"
        "value":
            if condition_type == "payload_eq":
                return "mayor_npc"
            if condition_type == "local_var_eq":
                return "complete"
            return ""
        _:
            return ""


func _should_use_quest_picker(condition_type: String, field_key: String, kind: String) -> bool:
    if not condition_type.begins_with("quest_"):
        return false
    if kind != "string":
        return false
    return ["quest_id", "stage_id", "objective_id"].has(field_key)


func _should_use_payload_key_picker(condition_type: String, field_key: String, kind: String) -> bool:
    return condition_type == "payload_eq" and field_key == "key" and kind == "string"


# Composite control: OptionButton with documented payload keys for the
# current rule's event, plus a "Custom…" sentinel that reveals an inline
# LineEdit for typing a non-listed key. The HBoxContainer is tagged with
# the "payload_key_picker" meta flag so _read_field knows to peel it apart
# instead of treating it as a normal control.
func _make_payload_key_picker(initial: Variant) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    row.set_meta("payload_key_picker", true)

    var picker := OptionButton.new()
    picker.custom_minimum_size = Vector2(160, 0)
    picker.tooltip_text = "Pick the payload key to compare. Use 'Custom…' if the rule's event publishes something outside the documented list."
    var keys := EcaSchemaLib.event_payload_keys(_rule_event)
    for key in keys:
        var key_str := str(key)
        var idx := picker.item_count
        picker.add_item(key_str)
        picker.set_item_metadata(idx, key_str)
    var custom_idx := picker.item_count
    picker.add_item("Custom…")
    picker.set_item_metadata(custom_idx, "__custom__")
    row.add_child(picker)

    var edit := LineEdit.new()
    edit.placeholder_text = "type custom key"
    edit.custom_minimum_size = Vector2(140, 0)
    edit.visible = false
    edit.tooltip_text = "Custom payload key for events that publish data outside the documented schema (e.g. entity properties merged into pickup/interact payloads)."
    row.add_child(edit)

    var initial_value := str(initial).strip_edges() if initial != null else ""
    var matched_idx := -1
    for i in range(keys.size()):
        if str(keys[i]) == initial_value:
            matched_idx = i
            break
    if matched_idx >= 0:
        picker.select(matched_idx)
    elif not initial_value.is_empty():
        picker.select(custom_idx)
        edit.text = initial_value
        edit.visible = true
    elif keys.is_empty():
        # Event has no documented payload keys yet — fall straight into
        # custom-input mode so the author isn't stuck on a one-option dropdown.
        picker.select(custom_idx)
        edit.visible = true
    else:
        picker.select(0)

    picker.item_selected.connect(func(idx: int):
        var meta_v: Variant = picker.get_item_metadata(idx)
        var is_custom: bool = str(meta_v) == "__custom__"
        edit.visible = is_custom
        if is_custom:
            edit.grab_focus()
        _emit_changed(null))
    edit.text_changed.connect(func(_t: String): _emit_changed(null))
    return row


func _read_payload_key_picker(control: Control) -> Dictionary:
    var picker: OptionButton = control.get_child(0)
    var edit: LineEdit = control.get_child(1)
    if picker == null:
        return {"ok": true, "value": ""}
    var selected_idx := picker.get_selected()
    if selected_idx < 0:
        return {"ok": true, "value": ""}
    var meta_v: Variant = picker.get_item_metadata(selected_idx)
    if str(meta_v) == "__custom__":
        var custom_text: String = edit.text.strip_edges() if edit != null else ""
        return {"ok": true, "value": custom_text}
    return {"ok": true, "value": str(meta_v)}


func _make_quest_picker(field_key: String, initial: Variant) -> Control:
    var picker := OptionButton.new()
    picker.custom_minimum_size = Vector2(190, 0)
    var initial_value := str(initial).strip_edges() if initial != null else ""
    var options := _quest_picker_options(field_key)
    for option_v in options:
        var option: Dictionary = option_v
        var label := str(option.get("label", ""))
        var value := str(option.get("value", ""))
        if value.is_empty():
            continue
        var idx := picker.item_count
        picker.add_item(label)
        picker.set_item_metadata(idx, value)
    if picker.item_count == 0:
        picker.add_item("(create a quest first)")
        picker.set_item_metadata(0, "")
    if not initial_value.is_empty():
        _select_option_value(picker, initial_value)
    elif picker.item_count > 0:
        picker.select(0)
    picker.item_selected.connect(func(_idx): _emit_changed(null))
    return picker


func _option_selected_value(picker: OptionButton) -> String:
    var idx := picker.get_selected()
    if idx < 0:
        return ""
    var meta: Variant = picker.get_item_metadata(idx)
    if meta != null:
        return str(meta).strip_edges()
    return picker.get_item_text(idx).strip_edges()


func _select_option_value(picker: OptionButton, value: String) -> void:
    for i in range(picker.item_count):
        if str(picker.get_item_metadata(i)).strip_edges() == value:
            picker.select(i)
            return
    var idx := picker.item_count
    picker.add_item("%s (missing)" % value)
    picker.set_item_metadata(idx, value)
    picker.select(idx)


func _quest_picker_options(field_key: String) -> Array:
    if _pack_id.is_empty():
        return []
    var quests_v: Variant = QuestIO.load_or_init(_pack_id).get("quests", [])
    if typeof(quests_v) != TYPE_ARRAY:
        return []
    var out: Array = []
    for quest_v in quests_v:
        if typeof(quest_v) != TYPE_DICTIONARY:
            continue
        var quest: Dictionary = quest_v
        var quest_id := str(quest.get("id", "")).strip_edges()
        if quest_id.is_empty():
            continue
        var quest_title := str(quest.get("title", quest_id)).strip_edges()
        if field_key == "quest_id":
            out.append({"value": quest_id, "label": "%s (%s)" % [quest_title, quest_id]})
            continue
        var stages_v: Variant = quest.get("stages", [])
        if typeof(stages_v) != TYPE_ARRAY:
            continue
        for stage_v in stages_v:
            if typeof(stage_v) != TYPE_DICTIONARY:
                continue
            var stage: Dictionary = stage_v
            var stage_id := str(stage.get("id", "")).strip_edges()
            if stage_id.is_empty():
                continue
            var stage_title := str(stage.get("title", stage_id)).strip_edges()
            if field_key == "stage_id":
                out.append({"value": stage_id, "label": "%s / %s (%s)" % [quest_title, stage_title, stage_id]})
                continue
            var objectives_v: Variant = stage.get("objectives", [])
            if typeof(objectives_v) != TYPE_ARRAY:
                continue
            for objective_v in objectives_v:
                if typeof(objective_v) != TYPE_DICTIONARY:
                    continue
                var objective: Dictionary = objective_v
                var objective_id := str(objective.get("id", "")).strip_edges()
                if objective_id.is_empty():
                    continue
                var objective_title := str(objective.get("title", objective_id)).strip_edges()
                out.append({"value": objective_id, "label": "%s / %s / %s (%s)" % [quest_title, stage_title, objective_title, objective_id]})
    return out
