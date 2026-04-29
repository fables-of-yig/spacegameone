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
var _rows: Array = []  # each: {"box": VBoxContainer, "type": String, "fields": {key -> Control}}
var _last_errors: Array = []


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    _rows_box = VBoxContainer.new()
    add_child(_rows_box)

    var add_row := HBoxContainer.new()
    add_child(add_row)
    var lbl := Label.new()
    lbl.text = "Add effect:"
    lbl.tooltip_text = "Add something that should happen automatically. Effects run from top to bottom."
    add_row.add_child(lbl)
    _add_option = OptionButton.new()
    _add_option.add_item("(pick type)")
    for label in EcaSchemaLib.action_labels():
        _add_option.add_item(str(label))
    _add_option.tooltip_text = "Choose what kind of effect to add."
    add_row.add_child(_add_option)
    var add_btn := Button.new()
    add_btn.text = "+ Add"
    add_btn.tooltip_text = "Add the selected effect to the bottom of the list."
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
    var row_box := VBoxContainer.new()
    row_box.add_theme_constant_override("separation", 3)
    _rows_box.add_child(row_box)

    var box := HBoxContainer.new()
    row_box.add_child(box)

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
        var control := _make_field(kind, seed_data.get(key, null), type_name, key)
        control.tooltip_text = field_tip
        fields_box.add_child(control)
        field_controls[key] = control

    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.tooltip_text = "Delete this action row."
    del_btn.pressed.connect(_on_delete_row.bind(row_box))
    box.add_child(del_btn)

    var help_lbl := Label.new()
    help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help_lbl.add_theme_font_size_override("font_size", 10)
    help_lbl.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84))
    help_lbl.text = _action_summary_text(type_name)
    row_box.add_child(help_lbl)

    var sep := HSeparator.new()
    row_box.add_child(sep)

    _rows.append({"box": row_box, "type": type_name, "fields": field_controls})


func _on_delete_row(row_box: VBoxContainer) -> void:
    for i in _rows.size():
        if (_rows[i] as Dictionary).get("box") == row_box:
            _rows.remove_at(i)
            break
    row_box.queue_free()
    _emit_changed()


func _make_field(kind: String, initial: Variant, action_type: String = "", field_key: String = "") -> Control:
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
            le.placeholder_text = _field_placeholder(action_type, field_key, kind)
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


func _action_summary_text(action_type: String) -> String:
    var help_text: String = EcaSchemaLib.action_help(action_type)
    var example_text: String = _action_example(action_type)
    if help_text.is_empty():
        return example_text
    if example_text.is_empty():
        return help_text
    return "%s Example: %s" % [help_text, example_text]


func _action_example(action_type: String) -> String:
    match action_type:
        "start_dialogue":
            return "id = shopkeep_intro"
        "set_trigger_enabled":
            return "id = boss_gate_intro, enabled = false"
        "set_door_enabled":
            return "id = startingregion_startingsceneleftdoor, enabled = false"
        "set_door_locked":
            return "id = startingregion_startingsceneleftdoor, locked = true"
        "fire_event":
            return "event = cutscene_done"
        "wait_for_event":
            return "event = bridge_lowered, timeout = 3"
        "wait_for_dialogue":
            return "timeout = 3, result_local = dialogue_finished"
        "spawn_player":
            return "room = town/plaza, zone_id = front_gate, facing = right"
        "spawn_entity":
            return "id = drone_guard, x = 320, y = 96"
        "spawn_entity_at_zone":
            return "id = drone_guard, zone_id = ambush_spawn"
        "move_entity_to_zone":
            return "entity = player, zone_id = exit_left, speed = 80"
        "play_entity_anim":
            return "entity = guard_01, anim = wave"
        "set_entity_facing":
            return "entity = player, direction = toward_zone, zone_id = mayor_desk"
        "camera_focus":
            return "mode = zone, target = boss_arena, speed = 160"
        "teleport_player":
            return "room = town/plaza, x = 128, y = 96"
        "set_flag":
            return "name = met_mayor, value = true"
        "set_var":
            return "name = gold, value = 100"
        "add_var":
            return "name = gold, delta = 25"
        "give_item":
            return "id = medkit_small, count = 1"
        "give_ability":
            return "id = double_jump"
        "play_sfx":
            return "name = ui_confirm"
        "log":
            return "message = reached_intro_gate"
        _:
            return ""


func _field_placeholder(action_type: String, field_key: String, kind: String) -> String:
    if kind == "opt_string":
        match field_key:
            "key":
                return "entity_id"
            "value":
                return "mayor_npc"
            "result_local":
                return "wait_succeeded"
            "anim":
                return "wave"
            "room":
                return "town/plaza"
            "zone_id":
                return "front_gate" if action_type == "spawn_player" else "entrance_zone"
            "entry_direction":
                return "left / right / up / down"
            "facing":
                return "left / right / up / down"
            "region_id":
                return "capital"
            "x":
                return "leave blank to reuse current"
            "y":
                return "leave blank to reuse current"
            _:
                return ""
    match field_key:
        "id":
            match action_type:
                "start_dialogue":
                    return "shopkeep_intro"
                "set_trigger_enabled":
                    return "boss_gate_intro"
                "set_door_enabled", "set_door_locked":
                    return "startingregion_startingsceneleftdoor"
                "spawn_entity", "spawn_entity_at_zone", "despawn_entity":
                    return "drone_guard"
                "give_item", "take_item":
                    return "medkit_small"
                "give_ability", "revoke_ability":
                    return "double_jump"
                "start_shop":
                    return "armorer_shop"
                _:
                    return "snake_case_id"
        "event":
            return "cutscene_done"
        "entity":
            return "player or guard_01"
        "mode":
            return "player / entity / zone / position"
        "target":
            return "player, guard_01, or boss_arena"
        "speed":
            if action_type == "camera_focus":
                return "160"
            if action_type == "move_entity_to_zone":
                return "80"
            if action_type == "play_entity_anim":
                return "1.0"
            return ""
        "direction":
            return "left / right / toward_zone / away_from_zone"
        "enabled":
            return "true / false"
        "locked":
            return "true / false"
        "anchor":
            return "player / world / system"
        "room":
            return "town/plaza"
        "name":
            if action_type == "play_sfx":
                return "ui_confirm"
            if action_type == "set_flag":
                return "met_mayor"
            if action_type == "set_var" or action_type == "add_var":
                return "gold"
            if action_type == "set_local_var" or action_type == "add_local_var":
                return "intro_step"
            return "name"
        "message":
            return "Reached intro gate"
        "tag":
            return "met_shopkeep"
        "key":
            return "entity_id"
        "value":
            return "mayor_npc"
        "class":
            return "pirate_raider"
        "anim":
            return "wave"
        "result_local":
            return "wait_succeeded"
        _:
            return ""
