extends Control

# Dialogue editor tab. Left panel: dialogue file list. Right panel:
# line list + line detail (speaker, text, choices, conditions, actions).

const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")

const PackAssetIndex = preload("res://Space/scripts/editor/pack_asset_index.gd")
signal status_changed(text: String)

var _pack_id: String = ""
var _dialogue_ids: Array = []
var _current_id: String = ""
var _lines: Array = []
var _selected_line: int = -1
var _dirty: bool = false
var _suppress: bool = false

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null
var _import_dialogue_dialog: FileDialog = null

var _undo: RefCounted = null

var _file_list: ItemList = null
var _line_list: ItemList = null
var _empty_warning: Label = null
var _speaker_edit: LineEdit = null
var _speaker_pick: OptionButton = null
var _text_edit: TextEdit = null
var _link_help: Label = null
var _cond_form: DlgConditionForm = null
var _action_form: DlgActionsForm = null
var _choices_box: VBoxContainer = null
var _choice_rows: Array = []  # [{"row": VBoxContainer, "text": LineEdit, "next": OptionButton, "cond": ConditionForm, "actions": ActionsForm}]


signal closed


func request_close() -> void:
    visible = false
    closed.emit()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    _refresh_speaker_picker()
    _load_file_list()


func open_editor(pack_id: String) -> void:
    open(pack_id)
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func save() -> bool:
    if not _flush_line():
        return false
    if _current_id.is_empty():
        return false
    if PedIO.save_dialogue(_pack_id, _current_id, { "id": _current_id, "lines": _lines }):
        _dirty = false
        status_changed.emit("Dialogue '%s' saved" % _current_id)
        return true
    else:
        status_changed.emit("Dialogue '%s' failed validation; save aborted" % _current_id)
        return false


func is_dirty() -> bool:
    return _dirty


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_ui()


func _capture_state() -> Dictionary:
    return {
        "lines": _lines.duplicate(true),
        "selected_line": _selected_line,
        "dirty": _dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var lines_v: Variant = snap.get("lines", null)
    if typeof(lines_v) == TYPE_ARRAY:
        _lines = lines_v
    _selected_line = int(snap.get("selected_line", -1))
    _dirty = bool(snap.get("dirty", false))
    _rebuild_line_list()


func _build_ui() -> void:
    var split := HSplitContainer.new()
    split.anchor_right = 1.0
    split.anchor_bottom = 1.0
    split.split_offset = 160
    add_child(split)

    # Left: file list
    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(left)

    var file_btns := HBoxContainer.new()
    left.add_child(file_btns)
    var back_btn := Button.new()
    back_btn.text = "Back"
    back_btn.tooltip_text = "Close the dialogue editor and return to the previous screen."
    back_btn.pressed.connect(request_close)
    file_btns.add_child(back_btn)
    var save_btn := Button.new()
    save_btn.text = "Save"
    save_btn.tooltip_text = "Save the currently selected conversation."
    save_btn.pressed.connect(save)
    file_btns.add_child(save_btn)
    var import_btn := Button.new()
    import_btn.text = "Import JSON"
    import_btn.tooltip_text = "Import a compatible dialogue JSON file or exported dialogue bundle into this pack."
    import_btn.pressed.connect(_on_import_dialogue_pressed)
    file_btns.add_child(import_btn)
    var new_btn := Button.new()
    new_btn.text = "+ New"
    new_btn.tooltip_text = "Create a new empty conversation file in this pack."
    new_btn.pressed.connect(_on_new_dialogue)
    file_btns.add_child(new_btn)

    var _tooltip_toggle := CheckButton.new()
    _tooltip_toggle.text = "Tooltips"
    _tooltip_toggle.button_pressed = EditorTooltip.enabled
    _tooltip_toggle.toggled.connect(func(on: bool): EditorTooltip.set_enabled(on))
    _tooltip_toggle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
    _tooltip_toggle.add_theme_font_size_override("font_size", 11)
    file_btns.add_child(_tooltip_toggle)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.tooltip_text = "Open a plain-language walkthrough for building conversations."
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    file_btns.add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    _tutorial_overlay.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_tutorial_overlay)

    _import_dialogue_dialog = FileDialog.new()
    _import_dialogue_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _import_dialogue_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _import_dialogue_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
    _import_dialogue_dialog.file_selected.connect(_on_import_dialogue_file_selected)
    add_child(_import_dialogue_dialog)

    _file_list = ItemList.new()
    _file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _file_list.tooltip_text = "List of conversation files in this pack. Select one to edit its lines."
    _file_list.item_selected.connect(_on_file_select)
    left.add_child(_file_list)

    # Right: line list + detail
    var right_split := HSplitContainer.new()
    right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.split_offset = 180
    split.add_child(right_split)

    var mid := VBoxContainer.new()
    mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.add_child(mid)

    var line_btns := HBoxContainer.new()
    mid.add_child(line_btns)
    var add_line := Button.new()
    add_line.text = "+ Line"
    add_line.tooltip_text = "Add a new line to the current conversation."
    add_line.pressed.connect(_on_add_line)
    line_btns.add_child(add_line)
    var del_line := Button.new()
    del_line.text = "Delete"
    del_line.tooltip_text = "Delete the currently selected line."
    del_line.pressed.connect(_on_delete_line)
    line_btns.add_child(del_line)

    _line_list = ItemList.new()
    _line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _line_list.tooltip_text = "Lines in this conversation. Select a line to edit who says it, what it says, and what happens next."
    _line_list.item_selected.connect(_on_line_select)
    mid.add_child(_line_list)

    _empty_warning = Label.new()
    _empty_warning.add_theme_font_size_override("font_size", 11)
    _empty_warning.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
    _empty_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _empty_warning.custom_minimum_size = Vector2(0, 32)
    _empty_warning.visible = false
    mid.add_child(_empty_warning)

    # Detail
    var detail_scroll := ScrollContainer.new()
    detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.add_child(detail_scroll)

    var detail := VBoxContainer.new()
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_scroll.add_child(detail)

    _link_help = Label.new()
    _link_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _link_help.add_theme_font_size_override("font_size", 10)
    _link_help.add_theme_color_override("font_color", Color(0.65, 0.78, 0.9))
    detail.add_child(_link_help)
    _refresh_link_help()

    _add_label(detail, "Who is speaking?", "Name or portrait id shown for this line. Leave blank for narration or system text.")
    var speaker_row := HBoxContainer.new()
    detail.add_child(speaker_row)
    _speaker_edit = LineEdit.new()
    _speaker_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _speaker_edit.placeholder_text = "Example: Captain Mira"
    _speaker_edit.tooltip_text = "Type the speaker name exactly how you want it shown in the dialogue box."
    _speaker_edit.text_changed.connect(func(t):
        _sync_speaker_pick(t)
        _mark_dirty()
    )
    speaker_row.add_child(_speaker_edit)
    _speaker_pick = OptionButton.new()
    _speaker_pick.custom_minimum_size = Vector2(180, 0)
    _speaker_pick.tooltip_text = "Quick-pick from portrait ids already authored in this pack."
    _speaker_pick.item_selected.connect(_on_speaker_pick_selected)
    speaker_row.add_child(_speaker_pick)

    _add_label(detail, "What does this line say?", "The actual dialogue text shown to the player for this line.")
    _text_edit = TextEdit.new()
    _text_edit.custom_minimum_size = Vector2(0, 60)
    _text_edit.placeholder_text = "Type the line the player will read here."
    _text_edit.tooltip_text = "Write the text for this line. If the line has choices, this text appears before the player picks one."
    _text_edit.text_changed.connect(func(): _mark_dirty())
    detail.add_child(_text_edit)

    _add_label(detail, "When should this line be allowed?", "Optional requirement. Leave this empty if the line should always play.")
    _cond_form = DlgConditionForm.new()
    _cond_form.changed.connect(_mark_dirty)
    detail.add_child(_cond_form)

    _add_label(detail, "What happens as soon as this line appears?", "Optional side effects such as setting a flag, giving an item, or playing a sound.")
    _action_form = DlgActionsForm.new()
    _action_form.changed.connect(_mark_dirty)
    detail.add_child(_action_form)

    _add_label(detail, "Player choices", "If you add choices here, the conversation pauses on this line and waits for the player to pick one.")
    var choices_btns := HBoxContainer.new()
    detail.add_child(choices_btns)
    var add_choice_btn := Button.new()
    add_choice_btn.text = "+ Choice"
    add_choice_btn.tooltip_text = "Add a player response option under this line."
    add_choice_btn.pressed.connect(_on_add_choice)
    choices_btns.add_child(add_choice_btn)
    _choices_box = VBoxContainer.new()
    _choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_child(_choices_box)


func _add_label(parent: VBoxContainer, text: String, tip: String = "") -> void:
    var lbl := Label.new()
    lbl.text = text
    lbl.tooltip_text = tip
    lbl.add_theme_font_size_override("font_size", 11)
    parent.add_child(lbl)


func _load_file_list() -> void:
    _dialogue_ids = PedIO.list_dialogues(_pack_id)
    _file_list.clear()
    for i in _dialogue_ids.size():
        var id: String = str(_dialogue_ids[i])
        var data: Dictionary = PedIO.load_dialogue(_pack_id, id)
        var lines_v: Variant = data.get("lines", [])
        var count: int = (lines_v as Array).size() if typeof(lines_v) == TYPE_ARRAY else 0
        var label: String = id if count > 0 else "%s   [!] empty" % id
        _file_list.add_item(label)
        if count == 0:
            _file_list.set_item_custom_fg_color(i, Color(1.0, 0.55, 0.35))


func _on_file_select(idx: int) -> void:
    if _dirty:
        if not save():
            if _file_list != null:
                var current_idx := _dialogue_ids.find(_current_id)
                if current_idx >= 0:
                    _file_list.select(current_idx)
            return
    _current_id = _dialogue_ids[idx]
    var data := PedIO.load_dialogue(_pack_id, _current_id)
    var raw: Variant = data.get("lines", [])
    _lines = raw if typeof(raw) == TYPE_ARRAY else []
    _selected_line = -1
    _rebuild_line_list()
    _dirty = false
    _refresh_link_help()
    if _undo != null:
        _undo.clear()


func _rebuild_line_list() -> void:
    _line_list.clear()
    for i in _lines.size():
        var line: Dictionary = _lines[i]
        var preview := "#%d  %s: %s" % [i, str(line.get("speaker", "")), str(line.get("text", "")).substr(0, 30)]
        _line_list.add_item(preview)
    if _selected_line >= 0 and _selected_line < _lines.size():
        _line_list.select(_selected_line)
        _show_line_detail(_selected_line)
    if _empty_warning != null:
        if _current_id.is_empty() or not _lines.is_empty():
            _empty_warning.visible = false
            _empty_warning.text = ""
        else:
            _empty_warning.visible = true
            _empty_warning.text = "This conversation is empty right now. If something tries to play it in-game, the player will see nothing. Add at least one line before using it."


func _on_line_select(idx: int) -> void:
    if not _flush_line():
        if _selected_line >= 0 and _selected_line < _lines.size():
            _line_list.select(_selected_line)
        return
    _selected_line = idx
    _show_line_detail(idx)


func _show_line_detail(idx: int) -> void:
    if idx < 0 or idx >= _lines.size():
        return
    _suppress = true
    var line: Dictionary = _lines[idx]
    _speaker_edit.text = str(line.get("speaker", ""))
    _sync_speaker_pick(_speaker_edit.text)
    _text_edit.text = str(line.get("text", ""))

    var cond_v: Variant = line.get("condition", {})
    _cond_form.open(cond_v if typeof(cond_v) == TYPE_DICTIONARY else {})

    var act_v: Variant = line.get("actions", [])
    _action_form.open(act_v if typeof(act_v) == TYPE_ARRAY else [])

    var choices_v: Variant = line.get("choices", [])
    _rebuild_choice_rows(choices_v if typeof(choices_v) == TYPE_ARRAY else [])
    _suppress = false


func _flush_line() -> bool:
    if _selected_line < 0 or _selected_line >= _lines.size():
        return true
    var line: Dictionary = _lines[_selected_line]
    line["speaker"] = _speaker_edit.text.strip_edges()
    line["text"] = _text_edit.text

    if _cond_form != null and _cond_form.has_error():
        status_changed.emit(_cond_form.error_text())
        return false
    if _action_form != null and _action_form.has_error():
        status_changed.emit(_action_form.error_text())
        return false
    var cond_val: Dictionary = _cond_form.get_value()
    if cond_val.is_empty():
        line.erase("condition")
    else:
        line["condition"] = cond_val

    var act_val: Array = _action_form.get_value()
    if act_val.is_empty():
        line.erase("actions")
    else:
        line["actions"] = act_val
    line.erase("next_line")

    var choices_out: Array = []
    for row_v in _choice_rows:
        var row: Dictionary = row_v
        var entry: Dictionary = {
            "text": (row.get("text") as LineEdit).text,
        }
        var cond_node: DlgConditionForm = row.get("cond")
        if cond_node != null and cond_node.has_error():
            status_changed.emit(cond_node.error_text())
            return false
        var c_cond: Dictionary = cond_node.get_value() if cond_node != null else {}
        if not c_cond.is_empty():
            entry["condition"] = c_cond
        var acts_node: DlgActionsForm = row.get("actions")
        if acts_node != null and acts_node.has_error():
            status_changed.emit(acts_node.error_text())
            return false
        var c_acts: Array = acts_node.get_value() if acts_node != null else []
        if not c_acts.is_empty():
            entry["actions"] = c_acts
        if not _apply_next_line_option(entry, row.get("next"), "Choice"):
            return false
        choices_out.append(entry)
    if choices_out.is_empty():
        line.erase("choices")
    else:
        line["choices"] = choices_out
    return true


func _refresh_speaker_picker() -> void:
    if _speaker_pick == null:
        return
    _speaker_pick.clear()
    _speaker_pick.add_item("Pick portrait id...")
    _speaker_pick.set_item_disabled(0, true)
    for portrait_id_v in PackAssetIndex.list_portrait_ids(_pack_id):
        _speaker_pick.add_item(str(portrait_id_v))
    _speaker_pick.select(0)


func _sync_speaker_pick(current_speaker: String) -> void:
    if _speaker_pick == null:
        return
    var clean: String = current_speaker.strip_edges()
    if clean.is_empty():
        _speaker_pick.select(0)
        return
    for idx in range(1, _speaker_pick.item_count):
        if _speaker_pick.get_item_text(idx) == clean:
            _speaker_pick.select(idx)
            return
    _speaker_pick.select(0)


func _on_speaker_pick_selected(idx: int) -> void:
    if _speaker_pick == null or idx <= 0:
        return
    if _speaker_edit != null:
        _speaker_edit.text = _speaker_pick.get_item_text(idx)
    _mark_dirty()


func _rebuild_choice_rows(choices: Array) -> void:
    for row_v in _choice_rows:
        (row_v as Dictionary).get("row").queue_free()
    _choice_rows.clear()
    for choice_v in choices:
        if typeof(choice_v) != TYPE_DICTIONARY:
            continue
        _append_choice_row(choice_v)


func _append_choice_row(seed_data: Dictionary) -> void:
    var row := VBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    _choices_box.add_child(row)

    var header := HBoxContainer.new()
    row.add_child(header)

    var text_lbl := Label.new()
    text_lbl.text = "Choice text:"
    text_lbl.tooltip_text = "What the player sees as this response option."
    header.add_child(text_lbl)
    var text_edit := LineEdit.new()
    text_edit.text = str(seed_data.get("text", ""))
    text_edit.custom_minimum_size = Vector2(260, 0)
    text_edit.placeholder_text = "Example: Tell me more."
    text_edit.tooltip_text = "Write the player-facing text for this response option."
    text_edit.text_changed.connect(func(_t): _mark_dirty())
    header.add_child(text_edit)
    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.tooltip_text = "Delete this response option."
    del_btn.pressed.connect(_on_delete_choice.bind(row))
    header.add_child(del_btn)

    var next_row := HBoxContainer.new()
    row.add_child(next_row)
    var next_lbl := Label.new()
    next_lbl.text = "  After this choice:"
    next_lbl.tooltip_text = "Choose where the conversation goes after this response is picked."
    next_lbl.add_theme_font_size_override("font_size", 10)
    next_row.add_child(next_lbl)
    var next_edit := OptionButton.new()
    next_edit.custom_minimum_size = Vector2(260, 0)
    next_edit.tooltip_text = "Choose a line to jump to, continue normally, or end the conversation."
    _populate_next_option(next_edit, seed_data.get("next_line", null))
    next_edit.item_selected.connect(func(_idx): _mark_dirty())
    next_row.add_child(next_edit)

    var cond_lbl := Label.new()
    cond_lbl.text = "  Show this choice only if:"
    cond_lbl.tooltip_text = "Optional requirement for whether this response should be visible."
    cond_lbl.add_theme_font_size_override("font_size", 10)
    row.add_child(cond_lbl)
    var cond_form := DlgConditionForm.new()
    cond_form.changed.connect(_mark_dirty)
    row.add_child(cond_form)
    var seed_cond: Variant = seed_data.get("condition", {})
    if typeof(seed_cond) == TYPE_DICTIONARY:
        cond_form.open(seed_cond)
    else:
        cond_form.open({})

    var act_lbl := Label.new()
    act_lbl.text = "  When this choice is picked:"
    act_lbl.tooltip_text = "Optional effects that fire after the player chooses this response."
    act_lbl.add_theme_font_size_override("font_size", 10)
    row.add_child(act_lbl)
    var act_form := DlgActionsForm.new()
    act_form.changed.connect(_mark_dirty)
    row.add_child(act_form)
    var seed_acts: Variant = seed_data.get("actions", [])
    if typeof(seed_acts) == TYPE_ARRAY:
        act_form.open(seed_acts)
    else:
        act_form.open([])

    var sep := HSeparator.new()
    row.add_child(sep)

    _choice_rows.append({
        "row": row,
        "text": text_edit,
        "next": next_edit,
        "cond": cond_form,
        "actions": act_form,
    })


func _on_add_choice() -> void:
    _append_choice_row({"text": ""})
    _mark_dirty()


func _on_delete_choice(row: VBoxContainer) -> void:
    for i in _choice_rows.size():
        if (_choice_rows[i] as Dictionary).get("row") == row:
            _choice_rows.remove_at(i)
            break
    row.queue_free()
    _mark_dirty()


func _on_add_line() -> void:
    if not _flush_line():
        return
    if _undo != null:
        _undo.begin()
    _lines.append({ "speaker": "", "text": "New line..." })
    _selected_line = _lines.size() - 1
    _rebuild_line_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("add dialogue line")


func _on_delete_line() -> void:
    if _selected_line < 0 or _selected_line >= _lines.size():
        return
    if _undo != null:
        _undo.begin()
    _lines.remove_at(_selected_line)
    _selected_line = mini(_selected_line, _lines.size() - 1)
    _rebuild_line_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("delete dialogue line")


func _on_new_dialogue() -> void:
    var new_id := "new_dialogue_%d" % _dialogue_ids.size()
    if PedIO.save_dialogue(_pack_id, new_id, { "id": new_id, "lines": [] }):
        _load_file_list()
        _refresh_link_help()
        status_changed.emit("Created new conversation '%s'" % new_id)
    else:
        status_changed.emit("Could not create conversation '%s'" % new_id)


func _on_import_dialogue_pressed() -> void:
    if _import_dialogue_dialog == null:
        return
    _import_dialogue_dialog.popup_centered_ratio(0.75)


func _on_import_dialogue_file_selected(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        status_changed.emit("Could not open import file")
        return
    var text := file.get_as_text()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        status_changed.emit("Imported file must contain a JSON object")
        return
    var payload: Dictionary = parsed
    var imported_ids := _import_dialogue_payload(payload)
    if imported_ids.is_empty():
        return
    _load_file_list()
    var first_id := str(imported_ids[0])
    var first_idx := _dialogue_ids.find(first_id)
    if first_idx >= 0:
        _file_list.select(first_idx)
        _on_file_select(first_idx)
    status_changed.emit("Imported %d conversation file(s)" % imported_ids.size())


func _import_dialogue_payload(payload: Dictionary) -> Array:
    var imported_ids: Array = []
    if payload.has("dialogues"):
        var dialogues_v: Variant = payload.get("dialogues", [])
        if typeof(dialogues_v) != TYPE_ARRAY:
            status_changed.emit("Dialogue bundle must contain a 'dialogues' array")
            return []
        for entry_v in dialogues_v:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_v.duplicate(true)
            var dialogue_id := str(entry.get("id", "")).strip_edges()
            if dialogue_id.is_empty():
                continue
            if PedIO.save_dialogue(_pack_id, dialogue_id, entry):
                imported_ids.append(dialogue_id)
        if imported_ids.is_empty():
            status_changed.emit("No valid dialogue files were imported from the bundle")
        return imported_ids

    var dialogue_id := str(payload.get("id", "")).strip_edges()
    if dialogue_id.is_empty():
        status_changed.emit("Imported dialogue JSON is missing an 'id'")
        return []
    var single: Dictionary = payload.duplicate(true)
    if not PedIO.save_dialogue(_pack_id, dialogue_id, single):
        status_changed.emit("Imported dialogue '%s' failed validation" % dialogue_id)
        return []
    imported_ids.append(dialogue_id)
    return imported_ids


func _mark_dirty() -> void:
    if _suppress:
        return
    _dirty = true


func _populate_next_option(option: OptionButton, value: Variant) -> void:
    if option == null:
        return
    option.clear()
    option.add_item("Continue to the next line")
    option.set_item_metadata(0, "__continue__")
    option.add_item("End the conversation")
    option.set_item_metadata(1, "__end__")
    for i in range(_lines.size()):
        var line: Dictionary = _lines[i] if typeof(_lines[i]) == TYPE_DICTIONARY else {}
        var preview := str(line.get("text", "")).strip_edges()
        if preview.is_empty():
            preview = "(blank line)"
        if preview.length() > 42:
            preview = preview.substr(0, 39) + "..."
        option.add_item("Jump to #%d: %s" % [i, preview])
        option.set_item_metadata(option.item_count - 1, i)
    option.select(_next_option_index(option, value))


func _next_option_index(option: OptionButton, value: Variant) -> int:
    if value == null:
        return 0
    if typeof(value) == TYPE_STRING:
        var lower := str(value).strip_edges().to_lower()
        if lower == "end" or lower == "stop" or lower == "close":
            return 1
        if lower.begins_with("#"):
            var trimmed := lower.substr(1).strip_edges()
            if trimmed.is_valid_int():
                value = int(trimmed)
        elif lower.is_valid_int():
            value = int(lower)
    if typeof(value) == TYPE_FLOAT:
        value = int(value)
    if typeof(value) == TYPE_INT:
        var wanted := int(value)
        for idx in range(option.item_count):
            var meta: Variant = option.get_item_metadata(idx)
            if typeof(meta) == TYPE_INT and int(meta) == wanted:
                return idx
    return 0


func _apply_next_line_option(target: Dictionary, option: OptionButton, label: String) -> bool:
    if option == null:
        target.erase("next_line")
        return true
    var idx := option.get_selected()
    if idx < 0 or idx >= option.item_count:
        target.erase("next_line")
        return true
    var meta: Variant = option.get_item_metadata(idx)
    if typeof(meta) == TYPE_STRING:
        var value := str(meta)
        if value == "__continue__":
            target.erase("next_line")
            return true
        if value == "__end__":
            target["next_line"] = "end"
            return true
    if typeof(meta) == TYPE_INT:
        target["next_line"] = int(meta)
        return true
    status_changed.emit("%s branch target is invalid" % label)
    return false


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _has_text_focus():
            return
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _has_text_focus() -> bool:
    var focused := get_viewport().gui_get_focus_owner()
    if focused == null:
        return false
    return focused is LineEdit or focused is TextEdit


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("dialogue")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


func _refresh_link_help() -> void:
    if _link_help == null:
        return
    var dialogue_ref: String = _current_id if not _current_id.is_empty() else "shopkeep_intro"
    _link_help.text = "How this conversation connects: the simplest NPC path is an interactable entity whose dialogue_id is %s, which opens automatically when the player talks to it. If you need extra logic, use a trigger action named Start Dialogue with id %s. Lines without choices continue in order. Choices can now pick a target from the branch dropdown, end the conversation, or continue normally. Dialogue choices also fire the event 'When the player picks a dialogue choice' so triggers can react to specific answers." % [dialogue_ref, dialogue_ref]
