extends Control

# Full-screen modal for editing Audio/manifest.json. The manifest maps
# logical sound names (e.g. "laser_fire") to pack-relative file paths
# used by AudioManager.play_sfx when the name isn't already in sfx_cache.
#
# Three sections: sfx, ambience, music. Each is a {name: path} dict.
# Save writes back to the pack's manifest.json and calls
# AudioManager.reload_manifest() so changes apply live.

signal closed

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")

var pack_id: String = ""
var _manifest: Dictionary = {}
var _active_section: String = "sfx"

var _root_box: VBoxContainer = null
var _section_buttons: HBoxContainer = null
var _entry_list: VBoxContainer = null
var _add_row: HBoxContainer = null
var _add_name_edit: LineEdit = null
var _add_path_edit: LineEdit = null
var _bottom_bar: HBoxContainer = null
var _dirty: bool = false


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    _build_ui()


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _manifest = _load_manifest()
    _active_section = "sfx"
    _dirty = false
    visible = true
    _layout_root.call_deferred()
    _refresh_entries.call_deferred()


func close() -> void:
    visible = false
    closed.emit()


func _notification(what) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_root()


# ─── UI construction ─────────────────────────────────────────────────────

func _build_ui() -> void:
    _root_box = VBoxContainer.new()
    _root_box.add_theme_constant_override("separation", 8)
    add_child(_root_box)

    var title := Label.new()
    title.text = "AUDIO MANIFEST"
    title.add_theme_font_size_override("font_size", 18)
    _root_box.add_child(title)

    _section_buttons = HBoxContainer.new()
    _root_box.add_child(_section_buttons)
    for sect in ["sfx", "ambience", "music"]:
        var btn := Button.new()
        btn.text = sect.to_upper()
        btn.pressed.connect(_on_section_pressed.bind(sect))
        _section_buttons.add_child(btn)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _root_box.add_child(scroll)

    _entry_list = VBoxContainer.new()
    _entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_entry_list)

    _add_row = HBoxContainer.new()
    _root_box.add_child(_add_row)
    var add_lbl := Label.new()
    add_lbl.text = "New entry:"
    _add_row.add_child(add_lbl)
    _add_name_edit = LineEdit.new()
    _add_name_edit.placeholder_text = "name (e.g. laser_fire)"
    _add_name_edit.custom_minimum_size = Vector2(200, 0)
    _add_row.add_child(_add_name_edit)
    _add_path_edit = LineEdit.new()
    _add_path_edit.placeholder_text = "pack-relative path (e.g. Audio/Sfx/laser.ogg)"
    _add_path_edit.custom_minimum_size = Vector2(360, 0)
    _add_row.add_child(_add_path_edit)
    var add_btn := Button.new()
    add_btn.text = "+ ADD"
    add_btn.pressed.connect(_on_add_pressed)
    _add_row.add_child(add_btn)

    _bottom_bar = HBoxContainer.new()
    _bottom_bar.alignment = BoxContainer.ALIGNMENT_END
    _root_box.add_child(_bottom_bar)
    var save_btn := Button.new()
    save_btn.text = "SAVE"
    save_btn.pressed.connect(_on_save_pressed)
    _bottom_bar.add_child(save_btn)
    var close_btn := Button.new()
    close_btn.text = "CLOSE"
    close_btn.pressed.connect(close)
    _bottom_bar.add_child(close_btn)


func _layout_root() -> void:
    if _root_box == null:
        return
    var inset: float = 40.0
    _root_box.position = Vector2(inset, inset)
    _root_box.size = Vector2(size.x - inset * 2.0, size.y - inset * 2.0)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.6))
    UIPanels.draw_panel(self, Rect2(Vector2(20, 20), Vector2(size.x - 40, size.y - 40)),
        Color.WHITE, UIPanels.PanelVariant.MAIN)


# ─── Section switching + entry refresh ───────────────────────────────────

func _on_section_pressed(sect: String) -> void:
    _active_section = sect
    _refresh_entries()


func _refresh_entries() -> void:
    if _entry_list == null:
        return
    for child in _entry_list.get_children():
        child.queue_free()
    var section: Dictionary = _get_section_dict()
    var keys: Array = section.keys()
    keys.sort()
    var invalid_count: int = 0
    for k in keys:
        var row := HBoxContainer.new()
        var name_lbl := Label.new()
        name_lbl.text = str(k)
        name_lbl.custom_minimum_size = Vector2(200, 0)
        row.add_child(name_lbl)
        var path_edit := LineEdit.new()
        var path_val: String = str(section[k])
        path_edit.text = path_val
        path_edit.custom_minimum_size = Vector2(420, 0)
        path_edit.text_changed.connect(_on_path_edited.bind(str(k)))
        if not _is_valid_audio_path(path_val):
            path_edit.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
            invalid_count += 1
        row.add_child(path_edit)
        var status_lbl := Label.new()
        if not _is_valid_audio_path(path_val):
            status_lbl.text = "  [!] not on disk"
            status_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
            status_lbl.add_theme_font_size_override("font_size", 11)
        row.add_child(status_lbl)
        var del_btn := Button.new()
        del_btn.text = "X"
        del_btn.pressed.connect(_on_delete_pressed.bind(str(k)))
        row.add_child(del_btn)
        _entry_list.add_child(row)

    var header := Label.new()
    var header_text: String = "%s (%d entries" % [_active_section.to_upper(), keys.size()]
    if invalid_count > 0:
        header_text += ", %d unresolved" % invalid_count
    header_text += ")"
    header.text = header_text
    var header_col: Color = Color(1.0, 0.7, 0.3) if invalid_count > 0 else Color(0.8, 0.9, 1.0)
    header.add_theme_color_override("font_color", header_col)
    _entry_list.add_child(header)
    _entry_list.move_child(header, 0)


func _is_valid_audio_path(path: String) -> bool:
    var clean: String = path.strip_edges()
    if clean.is_empty():
        return false
    # Accept absolute Godot resource paths as-is.
    if clean.begins_with("res://") or clean.begins_with("user://"):
        return ResourceLoader.exists(clean) or FileAccess.file_exists(clean)
    # Otherwise treat as pack-relative: try user override then shipped.
    var user_path: String = PackPaths.writable_pack_file(pack_id, clean)
    if FileAccess.file_exists(user_path):
        return true
    var shipped_path: String = "res://Content/%s/%s" % [pack_id, clean]
    return ResourceLoader.exists(shipped_path) or FileAccess.file_exists(shipped_path)


func _get_section_dict() -> Dictionary:
    var v: Variant = _manifest.get(_active_section, {})
    if typeof(v) != TYPE_DICTIONARY:
        _manifest[_active_section] = {}
        return _manifest[_active_section]
    return v


# ─── Edit handlers ───────────────────────────────────────────────────────

func _on_path_edited(new_text: String, key: String) -> void:
    var section := _get_section_dict()
    section[key] = new_text
    _dirty = true


func _on_add_pressed() -> void:
    if _add_name_edit == null or _add_path_edit == null:
        return
    var name_val := _add_name_edit.text.strip_edges()
    var path_val := _add_path_edit.text.strip_edges()
    if name_val.is_empty() or path_val.is_empty():
        return
    var section := _get_section_dict()
    section[name_val] = path_val
    _add_name_edit.text = ""
    _add_path_edit.text = ""
    _dirty = true
    _refresh_entries()


func _on_delete_pressed(key: String) -> void:
    var section := _get_section_dict()
    if section.has(key):
        section.erase(key)
        _dirty = true
        _refresh_entries()


# ─── IO ──────────────────────────────────────────────────────────────────

func _load_manifest() -> Dictionary:
    var user_path := PackPaths.writable_pack_file(pack_id, "Audio/manifest.json")
    var shipped_path := "res://Content/%s/Audio/manifest.json" % pack_id
    var path := user_path if FileAccess.file_exists(user_path) else shipped_path
    if not FileAccess.file_exists(path):
        return {"sfx": {}, "ambience": {}, "music": {}}
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {"sfx": {}, "ambience": {}, "music": {}}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {"sfx": {}, "ambience": {}, "music": {}}
    for k in ["sfx", "ambience", "music"]:
        if not (raw as Dictionary).has(k) or typeof(raw[k]) != TYPE_DICTIONARY:
            raw[k] = {}
    return raw


func _on_save_pressed() -> void:
    # Lint before writing: still save so the author's in-progress work
    # isn't lost, but surface a summary of unresolved paths so broken
    # entries don't quietly slip into the shipped manifest.
    var invalid: Array = []
    for section_name in ["sfx", "ambience", "music"]:
        var section_v: Variant = _manifest.get(section_name, {})
        if typeof(section_v) != TYPE_DICTIONARY:
            continue
        for k_v in (section_v as Dictionary).keys():
            var path_val: String = str((section_v as Dictionary)[k_v])
            if not _is_valid_audio_path(path_val):
                invalid.append("%s.%s -> %s" % [section_name, str(k_v), path_val])
    var dir_path := PackPaths.writable_pack_dir(pack_id) + "Audio"
    DirAccess.make_dir_recursive_absolute(dir_path)
    var out_path := dir_path + "/manifest.json"
    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("[AudManifest] cannot open %s for write" % out_path)
        return
    f.store_string(JSON.stringify(_manifest, "\t"))
    f.close()
    _dirty = false
    if Engine.has_singleton("AudioManager") or has_node("/root/AudioManager"):
        var am = get_node_or_null("/root/AudioManager")
        if am != null and am.has_method("reload_manifest"):
            am.reload_manifest()
    if not invalid.is_empty():
        push_warning("[AudManifest] saved with %d unresolved path(s):\n - %s" %
            [invalid.size(), "\n - ".join(invalid)])
    print("[AudManifest] saved for pack '%s'" % pack_id)


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            close()
            get_viewport().set_input_as_handled()
