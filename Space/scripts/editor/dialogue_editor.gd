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

var _undo: RefCounted = null

var _file_list: ItemList = null
var _line_list: ItemList = null
var _empty_warning: Label = null
var _speaker_edit: LineEdit = null
var _speaker_pick: OptionButton = null
var _text_edit: TextEdit = null
var _cond_form: DlgConditionForm = null
var _action_form: DlgActionsForm = null
var _choices_box: VBoxContainer = null
var _choice_rows: Array = []  # [{"row": HBoxContainer, "text": LineEdit, "cond": ConditionForm, "actions": ActionsForm, "expanded": bool, "detail": VBoxContainer}]


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
    back_btn.pressed.connect(request_close)
    file_btns.add_child(back_btn)
    var save_btn := Button.new()
    save_btn.text = "Save"
    save_btn.pressed.connect(save)
    file_btns.add_child(save_btn)
    var new_btn := Button.new()
    new_btn.text = "+ New"
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
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    file_btns.add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    _tutorial_overlay.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_tutorial_overlay)

    _file_list = ItemList.new()
    _file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
    add_line.pressed.connect(_on_add_line)
    line_btns.add_child(add_line)
    var del_line := Button.new()
    del_line.text = "Delete"
    del_line.pressed.connect(_on_delete_line)
    line_btns.add_child(del_line)

    _line_list = ItemList.new()
    _line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

    _add_label(detail, "Speaker")
    var speaker_row := HBoxContainer.new()
    detail.add_child(speaker_row)
    _speaker_edit = LineEdit.new()
    _speaker_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _speaker_edit.text_changed.connect(func(t):
        _sync_speaker_pick(t)
        _mark_dirty()
    )
    speaker_row.add_child(_speaker_edit)
    _speaker_pick = OptionButton.new()
    _speaker_pick.custom_minimum_size = Vector2(180, 0)
    _speaker_pick.item_selected.connect(_on_speaker_pick_selected)
    speaker_row.add_child(_speaker_pick)

    _add_label(detail, "Text")
    _text_edit = TextEdit.new()
    _text_edit.custom_minimum_size = Vector2(0, 60)
    _text_edit.text_changed.connect(func(): _mark_dirty())
    detail.add_child(_text_edit)

    _add_label(detail, "Condition (gates whether this line shows)")
    _cond_form = DlgConditionForm.new()
    _cond_form.changed.connect(_mark_dirty)
    detail.add_child(_cond_form)

    _add_label(detail, "Actions (fire when line displays)")
    _action_form = DlgActionsForm.new()
    _action_form.changed.connect(_mark_dirty)
    detail.add_child(_action_form)

    _add_label(detail, "Choices (if present, line waits for pick)")
    var choices_btns := HBoxContainer.new()
    detail.add_child(choices_btns)
    var add_choice_btn := Button.new()
    add_choice_btn.text = "+ Choice"
    add_choice_btn.pressed.connect(_on_add_choice)
    choices_btns.add_child(add_choice_btn)
    _choices_box = VBoxContainer.new()
    _choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_child(_choices_box)


func _add_label(parent: VBoxContainer, text: String) -> void:
    var lbl := Label.new()
    lbl.text = text
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
    if _undo != null:
        _undo.clear()


func _rebuild_line_list() -> void:
    _line_list.clear()
    for i in _lines.size():
        var line: Dictionary = _lines[i]
        var preview := "%s: %s" % [str(line.get("speaker", "")), str(line.get("text", "")).substr(0, 30)]
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
            _empty_warning.text = "Dialogue '%s' has no lines. Interacting with an NPC using this dialogue silently fails at runtime. Add at least one line." % _current_id


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
    _speaker_pick.add_item("Portrait Id...")
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
    text_lbl.text = "Text:"
    header.add_child(text_lbl)
    var text_edit := LineEdit.new()
    text_edit.text = str(seed_data.get("text", ""))
    text_edit.custom_minimum_size = Vector2(260, 0)
    text_edit.text_changed.connect(func(_t): _mark_dirty())
    header.add_child(text_edit)
    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.pressed.connect(_on_delete_choice.bind(row))
    header.add_child(del_btn)

    var cond_lbl := Label.new()
    cond_lbl.text = "  Condition:"
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
    act_lbl.text = "  Actions:"
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
    _lines.append({ "speaker": "", "text": "..." })
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
        status_changed.emit("Created dialogue '%s'" % new_id)
    else:
        status_changed.emit("Could not create dialogue '%s'" % new_id)


func _mark_dirty() -> void:
    if _suppress:
        return
    _dirty = true


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
