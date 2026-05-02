class_name DlgActionsForm
extends VBoxContainer

# Form builder for a list of action dicts. Each action is rendered as
# its own row with a type dropdown + per-type fields + delete button.
# A footer Add Action bar appends new rows. Emits `changed` on any edit.

signal changed

const EcaSchemaLib := preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")

var _rows_box: VBoxContainer = null
var _add_option: OptionButton = null
var _suppress_emit: bool = false
var _rows: Array = []  # each: {"box": VBoxContainer, "type": String, "fields": {key -> Control}}
var _last_errors: Array = []
var _pack_id: String = ""


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    _rows_box = VBoxContainer.new()
    add_child(_rows_box)

    var add_row := HBoxContainer.new()
    add_child(add_row)
    var lbl := Label.new()
    lbl.text = "Add action:"
    lbl.tooltip_text = "Add something the game should do. Actions run from top to bottom."
    add_row.add_child(lbl)
    _add_option = OptionButton.new()
    _add_option.add_item("(choose what happens)")
    for label in EcaSchemaLib.action_labels():
        _add_option.add_item(str(label))
    _add_option.tooltip_text = "Choose what the game should do next."
    add_row.add_child(_add_option)
    var add_btn := Button.new()
    add_btn.text = "+ Add"
    add_btn.tooltip_text = "Add the selected action to the bottom of the list."
    add_btn.pressed.connect(_on_add_pressed)
    add_row.add_child(add_btn)


func set_pack_id(pack_id: String) -> void:
    _pack_id = pack_id.strip_edges()


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
    help_lbl.text = _action_summary_text(type_name, seed_data)
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
    if _should_use_quest_picker(action_type, field_key, kind):
        return _make_quest_picker(field_key, initial, kind == "opt_string")
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
            if control is OptionButton:
                return {"ok": true, "value": _option_selected_value(control as OptionButton)}
            return {"ok": true, "value": (control as LineEdit).text.strip_edges() if control is LineEdit else ""}
        _:
            if control is OptionButton:
                var opt_value := _option_selected_value(control as OptionButton)
                return {"ok": not opt_value.is_empty(), "value": opt_value}
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


func _action_summary_text(action_type: String, action_data: Dictionary = {}) -> String:
    var natural := EcaSchemaLib.action_summary(action_data if not action_data.is_empty() else {"type": action_type})
    var help_text: String = EcaSchemaLib.action_help(action_type)
    var example_text: String = _action_example(action_type)
    var parts: Array = []
    if not natural.is_empty():
        parts.append("Reads as: %s." % natural)
    if not help_text.is_empty():
        parts.append(help_text)
    if not example_text.is_empty():
        parts.append("Example: %s" % example_text)
    return " ".join(parts)


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
        "quest_start":
            return "quest_id = first_steps, stage_id = start"
        "quest_set_stage":
            return "quest_id = first_steps, stage_id = clear_boss"
        "quest_complete_objective":
            return "quest_id = first_steps, stage_id = start, objective_id = get_key"
        "quest_complete_stage":
            return "quest_id = first_steps, stage_id = start"
        "quest_complete":
            return "quest_id = first_steps"
        _:
            return ""


func _field_placeholder(action_type: String, field_key: String, kind: String) -> String:
    if action_type.begins_with("quest_"):
        match field_key:
            "quest_id":
                return "choose a quest"
            "stage_id":
                return "choose a quest stage"
            "objective_id":
                return "choose a quest objective"
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


func _should_use_quest_picker(action_type: String, field_key: String, kind: String) -> bool:
    if not action_type.begins_with("quest_"):
        return false
    if kind != "string" and kind != "opt_string":
        return false
    return ["quest_id", "stage_id", "objective_id"].has(field_key)


func _make_quest_picker(field_key: String, initial: Variant, optional: bool) -> Control:
    var picker := OptionButton.new()
    picker.custom_minimum_size = Vector2(170, 0)
    var initial_value := str(initial).strip_edges() if initial != null else ""
    if optional:
        picker.add_item("(leave unchanged)")
        picker.set_item_metadata(0, "")
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
    if not initial_value.is_empty() and _select_option_value(picker, initial_value):
        pass
    elif not optional and picker.item_count > 0:
        picker.select(0)
    picker.item_selected.connect(func(_idx): _emit_changed())
    return picker


func _option_selected_value(picker: OptionButton) -> String:
    var idx := picker.get_selected()
    if idx < 0:
        return ""
    var meta: Variant = picker.get_item_metadata(idx)
    if meta != null:
        return str(meta).strip_edges()
    return picker.get_item_text(idx).strip_edges()


func _select_option_value(picker: OptionButton, value: String) -> bool:
    for i in range(picker.item_count):
        if str(picker.get_item_metadata(i)).strip_edges() == value:
            picker.select(i)
            return true
    var idx := picker.item_count
    picker.add_item("%s (missing)" % value)
    picker.set_item_metadata(idx, value)
    picker.select(idx)
    return true


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
