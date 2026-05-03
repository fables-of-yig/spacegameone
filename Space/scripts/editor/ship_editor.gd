extends Control

const LegacyShipBuilder = preload("res://Space/scripts/ship_builder/ship_builder.gd")
const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")

signal closed
signal test_fly_requested(placed: Array, core_id: String)
signal record_ai_requested(placed: Array, core_id: String, template_name: String)
signal fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String)

const _MANIFEST_DEFAULTS := {
    "pack_id": "",
    "name": "",
    "version": "0.1.0",
    "author": "",
    "description": "",
    "entry_room": "",
    "start_realm": "",
    "start_system": "",
    "start_ship_template": "",
}

var _pack_id: String = ""
var _templates: Array = []
var _selected_idx: int = -1

var _shell: Control = null
var _template_list: ItemList = null
var _starter_value: Label = null
var _details_value: RichTextLabel = null
var _status_label: Label = null
var _edit_btn: Button = null
var _set_start_btn: Button = null
var _clear_start_btn: Button = null
var _builder: Control = null


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_anchors_preset(PRESET_FULL_RECT)
    _build_ui()
    _ensure_builder()


func open_editor(pack_id: String = "") -> void:
    _pack_id = pack_id
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    _show_shell()
    _refresh_templates()
    _refresh_manifest_state()
    grab_focus()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED and _builder != null and _builder.visible:
        call_deferred("_sync_builder_layout")


func request_close() -> void:
    if _builder != null and _builder.visible:
        return
    visible = false
    closed.emit()


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _builder != null and _builder.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        request_close()


func _build_ui() -> void:
    _shell = Control.new()
    _shell.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_shell)

    var root := VBoxContainer.new()
    root.set_anchors_preset(PRESET_FULL_RECT)
    root.offset_left = 18.0
    root.offset_top = 18.0
    root.offset_right = -18.0
    root.offset_bottom = -18.0
    _shell.add_child(root)

    var header := HBoxContainer.new()
    root.add_child(header)

    var back_btn := Button.new()
    back_btn.text = "Back"
    back_btn.pressed.connect(request_close)
    header.add_child(back_btn)

    var new_btn := Button.new()
    new_btn.text = "New Ship"
    new_btn.pressed.connect(_on_new_ship_pressed)
    header.add_child(new_btn)

    _edit_btn = Button.new()
    _edit_btn.text = "Edit Selected"
    _edit_btn.disabled = true
    _edit_btn.pressed.connect(_on_edit_selected_pressed)
    header.add_child(_edit_btn)

    _set_start_btn = Button.new()
    _set_start_btn.text = "Set Starting Ship"
    _set_start_btn.disabled = true
    _set_start_btn.pressed.connect(_on_set_start_pressed)
    header.add_child(_set_start_btn)

    _clear_start_btn = Button.new()
    _clear_start_btn.text = "Clear Starter"
    _clear_start_btn.pressed.connect(_on_clear_start_pressed)
    header.add_child(_clear_start_btn)

    var refresh_btn := Button.new()
    refresh_btn.text = "Refresh"
    refresh_btn.pressed.connect(_refresh_templates)
    header.add_child(refresh_btn)

    var title := Label.new()
    title.text = "Ship Templates"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    title.add_theme_font_size_override("font_size", 20)
    header.add_child(title)

    var info := Label.new()
    info.text = "Open the legacy creative ship builder, then press T in-builder to save templates."
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_theme_font_size_override("font_size", 12)
    info.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    root.add_child(info)

    var split := HSplitContainer.new()
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = 360
    root.add_child(split)

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_child(left)

    var list_label := Label.new()
    list_label.text = "Saved Templates"
    list_label.add_theme_font_size_override("font_size", 14)
    left.add_child(list_label)

    _template_list = ItemList.new()
    _template_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _template_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _template_list.item_selected.connect(_on_template_selected)
    left.add_child(_template_list)

    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_child(right)

    var starter_title := Label.new()
    starter_title.text = "Current Starting Ship"
    starter_title.add_theme_font_size_override("font_size", 14)
    right.add_child(starter_title)

    _starter_value = Label.new()
    _starter_value.text = "(none)"
    _starter_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _starter_value.add_theme_color_override("font_color", Color(0.84, 0.9, 1.0))
    right.add_child(_starter_value)

    var details_title := Label.new()
    details_title.text = "Selected Template"
    details_title.add_theme_font_size_override("font_size", 14)
    right.add_child(details_title)

    _details_value = RichTextLabel.new()
    _details_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _details_value.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _details_value.bbcode_enabled = false
    _details_value.fit_content = false
    _details_value.scroll_active = true
    right.add_child(_details_value)

    _status_label = Label.new()
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.add_theme_color_override("font_color", Color(0.58, 0.88, 0.64))
    root.add_child(_status_label)


func _ensure_builder() -> void:
    if _builder != null:
        return
    _builder = Control.new()
    _builder.set_script(LegacyShipBuilder)
    _builder.visible = false
    _builder.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_builder)
    _builder.closed.connect(_on_builder_closed)
    _builder.test_fly_requested.connect(_on_builder_test_fly_requested)
    _builder.record_ai_requested.connect(_on_builder_record_ai_requested)
    _builder.fight_ai_requested.connect(_on_builder_fight_ai_requested)


func _refresh_templates() -> void:
    GameManager.reload_npc_templates()
    var current_id := _selected_template_id()
    _templates.clear()
    for entry_v in GameManager.get_template_list():
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var filename := str(entry.get("filename", "")).strip_edges()
        var path := str(entry.get("path", "")).strip_edges()
        var template_id := filename.get_basename()
        if template_id.is_empty() and not path.is_empty():
            template_id = path.get_file().get_basename()
        if template_id.is_empty():
            continue
        var source := "User" if path.begins_with("user://") else "Bundled"
        var decorated := entry.duplicate(true)
        decorated["template_id"] = template_id
        decorated["source"] = source
        _templates.append(decorated)
    _templates.sort_custom(func(a, b):
        return str(a.get("name", a.get("template_id", ""))).to_lower() < str(b.get("name", b.get("template_id", ""))).to_lower()
    )
    _rebuild_template_list(current_id)
    _refresh_manifest_state()
    _set_status("Ship template list refreshed.")


func _rebuild_template_list(selected_id: String = "") -> void:
    if _template_list == null:
        return
    _template_list.clear()
    _selected_idx = -1
    var starter_id := _current_start_ship_id()
    for i in range(_templates.size()):
        var entry: Dictionary = _templates[i]
        var display_name := str(entry.get("name", entry.get("template_id", ""))).strip_edges()
        var template_id := str(entry.get("template_id", "")).strip_edges()
        var label := "%s [%s]" % [display_name if not display_name.is_empty() else template_id, str(entry.get("source", ""))]
        if not starter_id.is_empty() and starter_id == template_id:
            label = "* " + label
        _template_list.add_item(label)
        if not selected_id.is_empty() and template_id == selected_id:
            _selected_idx = i
    if _selected_idx == -1 and not _templates.is_empty():
        _selected_idx = 0
    if _selected_idx >= 0 and _selected_idx < _templates.size():
        _template_list.select(_selected_idx)
    _refresh_selection_state()


func _refresh_selection_state() -> void:
    var has_selection := _selected_idx >= 0 and _selected_idx < _templates.size()
    if _edit_btn != null:
        _edit_btn.disabled = not has_selection
    if _set_start_btn != null:
        _set_start_btn.disabled = not has_selection or _pack_id.is_empty()
    if _clear_start_btn != null:
        _clear_start_btn.disabled = _pack_id.is_empty()
    if _details_value == null:
        return
    _details_value.clear()
    if not has_selection:
        _details_value.append_text("Select a saved template to inspect or edit it.\n")
        return
    var entry: Dictionary = _templates[_selected_idx]
    var template_id := str(entry.get("template_id", ""))
    var core_id := str(entry.get("core_id", ""))
    var core_name := str(DataManager.modules.get(core_id, {}).get("name", core_id))
    var module_count := int(entry.get("module_count", 0))
    var path := str(entry.get("path", ""))
    var lines := [
        "ID: %s" % template_id,
        "Name: %s" % str(entry.get("name", template_id)),
        "Source: %s" % str(entry.get("source", "")),
        "Core: %s" % (core_name if not core_name.is_empty() else core_id),
        "Modules: %d" % module_count,
        "Path: %s" % path,
        "",
        "Use New Ship for a fresh hull, or Edit Selected to load this template into the builder.",
        "Inside the builder, press T to save, L to browse templates, and Esc to return here.",
    ]
    _details_value.append_text("\n".join(lines))


func _refresh_manifest_state() -> void:
    if _starter_value == null:
        return
    var current_id := _current_start_ship_id()
    _starter_value.text = current_id if not current_id.is_empty() else "(none)"
    _rebuild_template_list(_selected_template_id())


func _current_start_ship_id() -> String:
    if _pack_id.is_empty():
        return ""
    var manifest := _load_manifest()
    return _normalize_template_id(str(manifest.get("start_ship_template", "")))


func _manifest_path() -> String:
    return PackPaths.writable_pack_file(_pack_id, "Pack.json")


func _load_manifest() -> Dictionary:
    var manifest := _MANIFEST_DEFAULTS.duplicate(true)
    manifest["pack_id"] = _pack_id
    manifest["name"] = _pack_id
    var path := _manifest_path()
    if FileAccess.file_exists(path):
        var file := FileAccess.open(path, FileAccess.READ)
        if file != null:
            var parsed: Variant = JSON.parse_string(file.get_as_text())
            file.close()
            if typeof(parsed) == TYPE_DICTIONARY:
                for key in (parsed as Dictionary).keys():
                    manifest[str(key)] = (parsed as Dictionary)[key]
    return manifest


func _save_manifest(manifest: Dictionary) -> void:
    if _pack_id.is_empty():
        return
    var path := _manifest_path()
    var dir_path := path.get_base_dir()
    DirAccess.make_dir_recursive_absolute(dir_path)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _set_status("Failed to write Pack.json for '%s'." % _pack_id)
        return
    file.store_string(JSON.stringify(manifest, "\t"))
    file.close()


func _selected_template_id() -> String:
    if _selected_idx < 0 or _selected_idx >= _templates.size():
        return ""
    return str(_templates[_selected_idx].get("template_id", ""))


func _selected_template_data() -> Dictionary:
    if _selected_idx < 0 or _selected_idx >= _templates.size():
        return {}
    var path := str(_templates[_selected_idx].get("path", "")).strip_edges()
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _show_shell() -> void:
    if _shell != null:
        _shell.visible = true
    if _builder != null:
        _builder.visible = false


func _show_builder() -> void:
    _ensure_builder()
    if _shell != null:
        _shell.visible = false
    _builder.visible = true


func resume_builder_state(placed: Array, core_id: String) -> void:
    _show_builder()
    _builder.open_creative_builder(core_id if not core_id.strip_edges().is_empty() else "core_cruiser")
    _builder.placed_modules = placed.duplicate(true)
    if _builder.has_method("compute_power_routing"):
        _builder.compute_power_routing()
    _builder.queue_redraw()
    call_deferred("_sync_builder_layout")


func _sync_builder_layout() -> void:
    if _builder == null:
        return
    _builder.position = Vector2.ZERO
    _builder.size = get_viewport_rect().size
    _builder.set_anchors_preset(PRESET_FULL_RECT)
    if _builder.has_method("refresh_layout"):
        _builder.refresh_layout()
    if _builder.has_method("grab_focus"):
        _builder.grab_focus()


func _on_template_selected(index: int) -> void:
    _selected_idx = index
    _refresh_selection_state()


func _on_new_ship_pressed() -> void:
    _show_builder()
    _builder.open_creative_builder()
    call_deferred("_sync_builder_layout")


func _on_edit_selected_pressed() -> void:
    var data := _selected_template_data()
    if data.is_empty():
        _set_status("Selected ship template could not be loaded.")
        return
    _show_builder()
    _builder.open_creative_template(data, str(data.get("name", _selected_template_id())))
    call_deferred("_sync_builder_layout")


func _on_set_start_pressed() -> void:
    var template_id := _selected_template_id()
    if template_id.is_empty() or _pack_id.is_empty():
        return
    var manifest := _load_manifest()
    manifest["start_ship_template"] = template_id
    _save_manifest(manifest)
    _refresh_manifest_state()
    _set_status("Starting ship set to '%s'." % template_id)


func _on_clear_start_pressed() -> void:
    if _pack_id.is_empty():
        return
    var manifest := _load_manifest()
    manifest["start_ship_template"] = ""
    _save_manifest(manifest)
    _refresh_manifest_state()
    _set_status("Starting ship cleared.")


func _on_builder_closed(_placed: Array) -> void:
    _show_shell()
    _refresh_templates()
    grab_focus()


func _on_builder_test_fly_requested(placed: Array, core_id: String) -> void:
    visible = false
    test_fly_requested.emit(placed, core_id)


func _on_builder_record_ai_requested(placed: Array, core_id: String, template_name: String) -> void:
    visible = false
    record_ai_requested.emit(placed, core_id, template_name)


func _on_builder_fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String) -> void:
    visible = false
    fight_ai_requested.emit(placed, core_id, template_name, recording_path)


func _normalize_template_id(value: String) -> String:
    var trimmed := value.strip_edges()
    if trimmed.is_empty():
        return ""
    if trimmed.contains("/"):
        trimmed = trimmed.get_file()
    if trimmed.ends_with(".json"):
        trimmed = trimmed.get_basename()
    return trimmed


func _set_status(text: String) -> void:
    if _status_label != null:
        _status_label.text = text
