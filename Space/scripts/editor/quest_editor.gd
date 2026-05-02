extends Control

const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")
const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")

const OBJECTIVE_TYPES := [
    "collect_item",
    "have_item",
    "kill_entity",
    "visit_room",
    "talk_dialogue",
    "open_shop",
    "trigger_event",
    "set_flag",
    "reach_var",
]

signal closed
signal status_changed(text: String)

var _pack_id: String = ""
var _quests: Array = []
var _selected_quest: int = -1
var _selected_stage: int = -1
var _selected_objective: int = -1
var _dirty: bool = false
var _suppress: bool = false

var _quest_list: ItemList = null
var _stage_list: ItemList = null
var _objective_list: ItemList = null
var _quest_id: LineEdit = null
var _quest_title: LineEdit = null
var _quest_desc: TextEdit = null
var _repeatable: CheckBox = null
var _stage_id: LineEdit = null
var _stage_title: LineEdit = null
var _objective_id: LineEdit = null
var _objective_type: OptionButton = null
var _objective_target: LineEdit = null
var _objective_count: SpinBox = null
var _reward_items: LineEdit = null
var _reward_abilities: LineEdit = null
var _reward_events: LineEdit = null
var _validation_label: Label = null


func request_close() -> void:
    visible = false
    closed.emit()


func open_editor(pack_id: String) -> void:
    _pack_id = pack_id
    _load()
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func is_dirty() -> bool:
    return _dirty


func save() -> bool:
    _flush_all()
    if not QuestIO.save(_pack_id, {"quests": _quests}):
        _set_status("Quest save failed")
        return false
    _dirty = false
    var errors := _quest_validation_errors()
    if errors.is_empty():
        _set_status("Quests saved; validation clean")
        return true
    _set_status("Quests saved; %d validation issue(s)" % errors.size())
    return true


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _build_ui()


func _build_ui() -> void:
    var split := HSplitContainer.new()
    split.anchor_right = 1.0
    split.anchor_bottom = 1.0
    split.split_offset = 220
    add_child(split)

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(left)

    var top_buttons := HBoxContainer.new()
    left.add_child(top_buttons)
    _add_button(top_buttons, "Back", request_close)
    _add_button(top_buttons, "Save", save)
    _add_button(top_buttons, "+ Quest", _on_add_quest)
    _add_button(top_buttons, "Delete", _on_delete_quest)

    _quest_list = ItemList.new()
    _quest_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _quest_list.tooltip_text = "Quest files in this pack. A quest contains stages, objectives, and stage rewards."
    _quest_list.item_selected.connect(_on_quest_selected)
    left.add_child(_quest_list)

    _validation_label = Label.new()
    _validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _validation_label.custom_minimum_size = Vector2(0, 48)
    _validation_label.add_theme_font_size_override("font_size", 11)
    _validation_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.95))
    left.add_child(_validation_label)

    var main_split := HSplitContainer.new()
    main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_split.split_offset = 260
    split.add_child(main_split)

    var middle := VBoxContainer.new()
    middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_split.add_child(middle)

    middle.add_child(_section_label("Quest"))
    _quest_id = _line_edit("quest id", _on_quest_field_changed.bind("id"))
    middle.add_child(_quest_id)
    _quest_title = _line_edit("quest title", _on_quest_field_changed.bind("title"))
    middle.add_child(_quest_title)
    _repeatable = CheckBox.new()
    _repeatable.text = "Repeatable"
    _repeatable.toggled.connect(_on_repeatable_changed)
    middle.add_child(_repeatable)
    _quest_desc = TextEdit.new()
    _quest_desc.custom_minimum_size = Vector2(0, 74)
    _quest_desc.placeholder_text = "Quest summary for journal-facing context."
    _quest_desc.text_changed.connect(_on_quest_description_changed)
    middle.add_child(_quest_desc)

    var stage_buttons := HBoxContainer.new()
    stage_buttons.add_child(_section_label("Stages"))
    _add_button(stage_buttons, "+ Stage", _on_add_stage)
    _add_button(stage_buttons, "Delete", _on_delete_stage)
    middle.add_child(stage_buttons)
    _stage_list = ItemList.new()
    _stage_list.custom_minimum_size = Vector2(0, 130)
    _stage_list.item_selected.connect(_on_stage_selected)
    middle.add_child(_stage_list)
    _stage_id = _line_edit("stage id", _on_stage_field_changed.bind("id"))
    middle.add_child(_stage_id)
    _stage_title = _line_edit("stage title", _on_stage_field_changed.bind("title"))
    middle.add_child(_stage_title)

    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_split.add_child(right)

    var objective_buttons := HBoxContainer.new()
    objective_buttons.add_child(_section_label("Objectives"))
    _add_button(objective_buttons, "+ Objective", _on_add_objective)
    _add_button(objective_buttons, "Delete", _on_delete_objective)
    right.add_child(objective_buttons)
    _objective_list = ItemList.new()
    _objective_list.custom_minimum_size = Vector2(0, 150)
    _objective_list.item_selected.connect(_on_objective_selected)
    right.add_child(_objective_list)
    _objective_id = _line_edit("objective id", _on_objective_field_changed.bind("id"))
    right.add_child(_objective_id)
    _objective_type = OptionButton.new()
    for type_v in OBJECTIVE_TYPES:
        _objective_type.add_item(str(type_v))
    _objective_type.item_selected.connect(_on_objective_type_selected)
    right.add_child(_objective_type)
    _objective_target = _line_edit("target id or room path", _on_objective_target_changed)
    right.add_child(_objective_target)
    _objective_count = SpinBox.new()
    _objective_count.min_value = 1
    _objective_count.max_value = 9999
    _objective_count.step = 1
    _objective_count.value_changed.connect(_on_objective_count_changed)
    right.add_child(_objective_count)

    right.add_child(_section_label("Stage Rewards"))
    _reward_items = _line_edit("items: id or id:count, comma separated", _on_rewards_changed)
    right.add_child(_reward_items)
    _reward_abilities = _line_edit("abilities, comma separated", _on_rewards_changed)
    right.add_child(_reward_abilities)
    _reward_events = _line_edit("events to fire, comma separated", _on_rewards_changed)
    right.add_child(_reward_events)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.pressed.connect(callback)
    parent.add_child(button)
    return button


func _section_label(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 12)
    label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    return label


func _line_edit(placeholder: String, callback: Callable) -> LineEdit:
    var edit := LineEdit.new()
    edit.placeholder_text = placeholder
    edit.text_changed.connect(callback)
    return edit


func _load() -> void:
    var root := QuestIO.load_or_init(_pack_id)
    _quests = _as_array(root.get("quests", [])).duplicate(true)
    _selected_quest = 0 if not _quests.is_empty() else -1
    _selected_stage = 0 if _selected_quest >= 0 and not _stages().is_empty() else -1
    _selected_objective = 0 if _selected_stage >= 0 and not _objectives().is_empty() else -1
    _dirty = false
    _rebuild_all()
    _set_status("Loaded %d quest(s)" % _quests.size())


func _rebuild_all() -> void:
    _suppress = true
    _rebuild_quest_list()
    _rebuild_stage_list()
    _rebuild_objective_list()
    _refresh_fields()
    _suppress = false


func _rebuild_quest_list() -> void:
    _quest_list.clear()
    for i in range(_quests.size()):
        var quest: Dictionary = _quests[i]
        _quest_list.add_item("%s - %s" % [
            str(quest.get("id", "quest")),
            str(quest.get("title", "")),
        ])
    if _selected_quest >= 0 and _selected_quest < _quest_list.item_count:
        _quest_list.select(_selected_quest)


func _rebuild_stage_list() -> void:
    _stage_list.clear()
    for i in range(_stages().size()):
        var stage: Dictionary = _stages()[i]
        _stage_list.add_item("%s - %s" % [
            str(stage.get("id", "stage")),
            str(stage.get("title", "")),
        ])
    if _selected_stage >= 0 and _selected_stage < _stage_list.item_count:
        _stage_list.select(_selected_stage)


func _rebuild_objective_list() -> void:
    _objective_list.clear()
    for i in range(_objectives().size()):
        var objective: Dictionary = _objectives()[i]
        _objective_list.add_item("%s: %s" % [
            str(objective.get("type", "")),
            _objective_target_for_display(objective),
        ])
    if _selected_objective >= 0 and _selected_objective < _objective_list.item_count:
        _objective_list.select(_selected_objective)


func _refresh_fields() -> void:
    var quest := _quest()
    var stage := _stage()
    var objective := _objective()
    _quest_id.text = str(quest.get("id", ""))
    _quest_title.text = str(quest.get("title", ""))
    _quest_desc.text = str(quest.get("description", ""))
    _repeatable.button_pressed = bool(quest.get("repeatable", false))
    _stage_id.text = str(stage.get("id", ""))
    _stage_title.text = str(stage.get("title", ""))
    _objective_id.text = str(objective.get("id", ""))
    _select_objective_type(str(objective.get("type", "collect_item")))
    _objective_target.text = _objective_target_for_display(objective)
    _objective_count.value = float(maxi(1, int(objective.get("count", objective.get("target_count", 1)))))
    var rewards := _rewards()
    _reward_items.text = _join_reward_items(_as_array(rewards.get("items", [])))
    _reward_abilities.text = _join_values(_as_array(rewards.get("abilities", [])))
    _reward_events.text = _join_values(_as_array(rewards.get("events", [])))


func _quest() -> Dictionary:
    if _selected_quest >= 0 and _selected_quest < _quests.size() and typeof(_quests[_selected_quest]) == TYPE_DICTIONARY:
        return _quests[_selected_quest]
    return {}


func _stage() -> Dictionary:
    var stages := _stages()
    if _selected_stage >= 0 and _selected_stage < stages.size() and typeof(stages[_selected_stage]) == TYPE_DICTIONARY:
        return stages[_selected_stage]
    return {}


func _objective() -> Dictionary:
    var objectives := _objectives()
    if _selected_objective >= 0 and _selected_objective < objectives.size() and typeof(objectives[_selected_objective]) == TYPE_DICTIONARY:
        return objectives[_selected_objective]
    return {}


func _stages() -> Array:
    var quest := _quest()
    return _as_array(quest.get("stages", []))


func _objectives() -> Array:
    var stage := _stage()
    return _as_array(stage.get("objectives", []))


func _rewards() -> Dictionary:
    var stage := _stage()
    var rewards_v: Variant = stage.get("rewards", {})
    if typeof(rewards_v) == TYPE_DICTIONARY:
        return rewards_v
    return {}


func _on_add_quest() -> void:
    _flush_all()
    var id := _unique_id("quest", _quest_ids())
    _quests.append(QuestIO.starter_quest(id))
    _selected_quest = _quests.size() - 1
    _selected_stage = 0
    _selected_objective = -1
    _mark_dirty()
    _rebuild_all()


func _on_delete_quest() -> void:
    if _selected_quest < 0 or _selected_quest >= _quests.size():
        return
    _quests.remove_at(_selected_quest)
    _selected_quest = mini(_selected_quest, _quests.size() - 1)
    _selected_stage = 0 if _selected_quest >= 0 and not _stages().is_empty() else -1
    _selected_objective = 0 if _selected_stage >= 0 and not _objectives().is_empty() else -1
    _mark_dirty()
    _rebuild_all()


func _on_add_stage() -> void:
    var quest := _quest()
    if quest.is_empty():
        return
    var stages := _stages()
    var id := _unique_id("stage", _stage_ids())
    stages.append({"id": id, "title": id.capitalize(), "objectives": [], "rewards": {"items": [], "abilities": [], "events": []}})
    quest["stages"] = stages
    _selected_stage = stages.size() - 1
    _selected_objective = -1
    _mark_dirty()
    _rebuild_all()


func _on_delete_stage() -> void:
    var quest := _quest()
    var stages := _stages()
    if quest.is_empty() or _selected_stage < 0 or _selected_stage >= stages.size():
        return
    stages.remove_at(_selected_stage)
    quest["stages"] = stages
    _selected_stage = mini(_selected_stage, stages.size() - 1)
    _selected_objective = 0 if _selected_stage >= 0 and not _objectives().is_empty() else -1
    _mark_dirty()
    _rebuild_all()


func _on_add_objective() -> void:
    var stage := _stage()
    if stage.is_empty():
        return
    var objectives := _objectives()
    var id := _unique_id("objective", _objective_ids())
    objectives.append({"id": id, "type": "collect_item", "item_id": "", "count": 1})
    stage["objectives"] = objectives
    _selected_objective = objectives.size() - 1
    _mark_dirty()
    _rebuild_all()


func _on_delete_objective() -> void:
    var stage := _stage()
    var objectives := _objectives()
    if stage.is_empty() or _selected_objective < 0 or _selected_objective >= objectives.size():
        return
    objectives.remove_at(_selected_objective)
    stage["objectives"] = objectives
    _selected_objective = mini(_selected_objective, objectives.size() - 1)
    _mark_dirty()
    _rebuild_all()


func _on_quest_selected(index: int) -> void:
    if _suppress:
        return
    _flush_all()
    _selected_quest = index
    _selected_stage = 0 if not _stages().is_empty() else -1
    _selected_objective = 0 if _selected_stage >= 0 and not _objectives().is_empty() else -1
    _rebuild_all()


func _on_stage_selected(index: int) -> void:
    if _suppress:
        return
    _flush_all()
    _selected_stage = index
    _selected_objective = 0 if not _objectives().is_empty() else -1
    _rebuild_all()


func _on_objective_selected(index: int) -> void:
    if _suppress:
        return
    _flush_all()
    _selected_objective = index
    _rebuild_all()


func _on_quest_field_changed(text: String, key: String) -> void:
    if _suppress:
        return
    var quest := _quest()
    if quest.is_empty():
        return
    quest[key] = text.strip_edges() if key == "id" else text
    _mark_dirty()
    _rebuild_quest_list()


func _on_quest_description_changed() -> void:
    if _suppress:
        return
    var quest := _quest()
    if quest.is_empty():
        return
    quest["description"] = _quest_desc.text
    _mark_dirty()


func _on_repeatable_changed(on: bool) -> void:
    if _suppress:
        return
    var quest := _quest()
    if quest.is_empty():
        return
    quest["repeatable"] = on
    _mark_dirty()


func _on_stage_field_changed(text: String, key: String) -> void:
    if _suppress:
        return
    var stage := _stage()
    if stage.is_empty():
        return
    stage[key] = text.strip_edges() if key == "id" else text
    _mark_dirty()
    _rebuild_stage_list()


func _on_objective_field_changed(text: String, key: String) -> void:
    if _suppress:
        return
    var objective := _objective()
    if objective.is_empty():
        return
    objective[key] = text.strip_edges()
    _mark_dirty()
    _rebuild_objective_list()


func _on_objective_type_selected(index: int) -> void:
    if _suppress:
        return
    var objective := _objective()
    if objective.is_empty() or index < 0 or index >= OBJECTIVE_TYPES.size():
        return
    objective["type"] = OBJECTIVE_TYPES[index]
    _set_objective_target(objective, _objective_target.text.strip_edges())
    _mark_dirty()
    _rebuild_objective_list()


func _on_objective_target_changed(text: String) -> void:
    if _suppress:
        return
    var objective := _objective()
    if objective.is_empty():
        return
    _set_objective_target(objective, text.strip_edges())
    _mark_dirty()
    _rebuild_objective_list()


func _on_objective_count_changed(value: float) -> void:
    if _suppress:
        return
    var objective := _objective()
    if objective.is_empty():
        return
    objective["count"] = maxi(1, int(value))
    _mark_dirty()


func _on_rewards_changed(_text: String = "") -> void:
    if _suppress:
        return
    var stage := _stage()
    if stage.is_empty():
        return
    stage["rewards"] = {
        "items": _parse_reward_items(_reward_items.text),
        "abilities": _parse_list(_reward_abilities.text),
        "events": _parse_list(_reward_events.text),
    }
    _mark_dirty()


func _flush_all() -> void:
    _on_rewards_changed()


func _set_objective_target(objective: Dictionary, target: String) -> void:
    for key_v in ["item_id", "entity_id", "room", "dialogue_id", "shop_id", "event", "flag", "var"]:
        objective.erase(str(key_v))
    match str(objective.get("type", "")).strip_edges():
        "collect_item", "have_item":
            objective["item_id"] = target
        "kill_entity":
            objective["entity_id"] = target
        "visit_room":
            objective["room"] = target
        "talk_dialogue":
            objective["dialogue_id"] = target
        "open_shop":
            objective["shop_id"] = target
        "trigger_event":
            objective["event"] = target
        "set_flag":
            objective["flag"] = target
        "reach_var":
            objective["var"] = target


func _objective_target_for_display(objective: Dictionary) -> String:
    for key_v in ["item_id", "entity_id", "room", "room_id", "room_addr", "dialogue_id", "shop_id", "event", "event_id", "flag", "name", "var"]:
        var value := str(objective.get(str(key_v), "")).strip_edges()
        if not value.is_empty():
            return value
    return ""


func _select_objective_type(type_name: String) -> void:
    var idx := OBJECTIVE_TYPES.find(type_name)
    if idx < 0:
        idx = 0
    _objective_type.select(idx)


func _mark_dirty() -> void:
    _dirty = true
    _set_status("Unsaved quest changes")


func _set_status(text: String) -> void:
    if _validation_label != null:
        _validation_label.text = text
    status_changed.emit(text)


func _quest_validation_errors() -> Array:
    var out: Array = []
    for issue_v in ContentValidator.validate(_pack_id):
        if issue_v != null and issue_v.severity == "error" and str(issue_v.source).begins_with("Quest"):
            out.append(issue_v)
    return out


func _quest_ids() -> Dictionary:
    var ids: Dictionary = {}
    for quest_v in _quests:
        if typeof(quest_v) == TYPE_DICTIONARY:
            var id := str((quest_v as Dictionary).get("id", "")).strip_edges()
            if not id.is_empty():
                ids[id] = true
    return ids


func _stage_ids() -> Dictionary:
    var ids: Dictionary = {}
    for stage_v in _stages():
        if typeof(stage_v) == TYPE_DICTIONARY:
            var id := str((stage_v as Dictionary).get("id", "")).strip_edges()
            if not id.is_empty():
                ids[id] = true
    return ids


func _objective_ids() -> Dictionary:
    var ids: Dictionary = {}
    for objective_v in _objectives():
        if typeof(objective_v) == TYPE_DICTIONARY:
            var id := str((objective_v as Dictionary).get("id", "")).strip_edges()
            if not id.is_empty():
                ids[id] = true
    return ids


func _unique_id(prefix: String, ids: Dictionary) -> String:
    var idx := 1
    var candidate := "%s_%d" % [prefix, idx]
    while ids.has(candidate):
        idx += 1
        candidate = "%s_%d" % [prefix, idx]
    return candidate


func _parse_list(text: String) -> Array:
    var out: Array = []
    for part in text.split(",", false):
        var value := str(part).strip_edges()
        if not value.is_empty():
            out.append(value)
    return out


func _parse_reward_items(text: String) -> Array:
    var out: Array = []
    for part in text.split(",", false):
        var value := str(part).strip_edges()
        if value.is_empty():
            continue
        if value.contains(":"):
            var pieces := value.split(":", false, 1)
            out.append({"id": str(pieces[0]).strip_edges(), "count": maxi(1, int(str(pieces[1]).strip_edges()))})
        else:
            out.append({"id": value, "count": 1})
    return out


func _join_values(values: Array) -> String:
    var parts: Array = []
    for value_v in values:
        if typeof(value_v) == TYPE_DICTIONARY:
            parts.append(str((value_v as Dictionary).get("id", (value_v as Dictionary).get("ability_id", ""))).strip_edges())
        else:
            parts.append(str(value_v).strip_edges())
    return ", ".join(parts)


func _join_reward_items(values: Array) -> String:
    var parts: Array = []
    for value_v in values:
        if typeof(value_v) == TYPE_DICTIONARY:
            var item: Dictionary = value_v
            var id := str(item.get("id", item.get("item_id", ""))).strip_edges()
            if not id.is_empty():
                parts.append("%s:%d" % [id, maxi(1, int(item.get("count", 1)))])
        else:
            var id := str(value_v).strip_edges()
            if not id.is_empty():
                parts.append(id)
    return ", ".join(parts)


func _as_array(value: Variant) -> Array:
    if typeof(value) == TYPE_ARRAY:
        return value
    return []
