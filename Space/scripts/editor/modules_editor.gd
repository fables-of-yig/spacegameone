extends Control

const ModuleVisuals = preload("res://Space/scripts/autoload/module_visuals.gd")

signal closed

const DATA_PATH: String = "res://Space/data/modules/starter_modules.json"
const ART_DIR: String = "res://Space/art/modules"
const PREVIEW_HEX_SIZE: float = 38.0

class FootprintCanvas:
    extends Control

    var editor: Control = null

    func _draw() -> void:
        if editor != null:
            editor._draw_visual_canvas(self)

    func _gui_input(event: InputEvent) -> void:
        if editor != null:
            editor._visual_canvas_input(event)


var pack_id: String = ""
var data: Dictionary = {}
var selected_id: String = ""
var _sprite_names: Array = []
var _sprite_cache: Dictionary = {}
var _updating_controls: bool = false
var _dirty: bool = false
var _status_text: String = ""
var _status_timer: float = 0.0
var _dragging_sprite: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_offset: Vector2 = Vector2.ZERO
var _last_sprite_rect: Rect2 = Rect2()

var _list: ItemList = null
var _search: LineEdit = null
var _canvas: FootprintCanvas = null
var _mode_select: OptionButton = null
var _name_edit: LineEdit = null
var _type_edit: LineEdit = null
var _sprite_edit: LineEdit = null
var _sprite_select: OptionButton = null
var _hex_size_spin: SpinBox = null
var _sprite_cell_spin: SpinBox = null
var _sprite_scale_spin: SpinBox = null
var _sprite_rot_spin: SpinBox = null
var _offset_x_spin: SpinBox = null
var _offset_y_spin: SpinBox = null
var _raw_json: TextEdit = null
var _status_label: Label = null


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_anchors_preset(PRESET_FULL_RECT)
    set_process(true)
    _build_ui()


func open_editor(p_pack_id: String = "") -> void:
    pack_id = p_pack_id
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    _load_sprite_names()
    _load_data()
    _refresh_module_list()
    if selected_id == "" and not data.is_empty():
        var ids := data.keys()
        ids.sort()
        _select_module(str(ids[0]))
    else:
        _sync_controls()
    grab_focus()


func request_close() -> void:
    visible = false
    if _raw_json != null:
        _raw_json.release_focus()
    closed.emit()


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            get_viewport().set_input_as_handled()
            request_close()


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        request_close()


func _process(delta: float) -> void:
    if not visible:
        return
    if _status_timer > 0.0:
        _status_timer -= delta
        if _status_timer <= 0.0:
            _status_text = ""
            _update_status()
    if _canvas != null:
        _canvas.queue_redraw()


func _build_ui() -> void:
    var root := VBoxContainer.new()
    root.set_anchors_preset(PRESET_FULL_RECT)
    root.offset_left = 14.0
    root.offset_top = 14.0
    root.offset_right = -14.0
    root.offset_bottom = -14.0
    add_child(root)

    var header := HBoxContainer.new()
    root.add_child(header)

    var exit_btn := Button.new()
    exit_btn.text = "Exit to Campaign"
    exit_btn.pressed.connect(request_close)
    header.add_child(exit_btn)

    var title := Label.new()
    title.text = "Module Editor"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    header.add_child(title)

    var add_btn := Button.new()
    add_btn.text = "+ New"
    add_btn.pressed.connect(_add_module)
    header.add_child(add_btn)

    var dup_btn := Button.new()
    dup_btn.text = "Duplicate"
    dup_btn.pressed.connect(_duplicate_module)
    header.add_child(dup_btn)

    var del_btn := Button.new()
    del_btn.text = "Delete"
    del_btn.pressed.connect(_delete_module)
    header.add_child(del_btn)

    var inv_btn := Button.new()
    inv_btn.text = "+ Inventory"
    inv_btn.pressed.connect(_add_to_inventory)
    header.add_child(inv_btn)

    var save_btn := Button.new()
    save_btn.text = "Save"
    save_btn.pressed.connect(_save_data)
    header.add_child(save_btn)

    _status_label = Label.new()
    _status_label.custom_minimum_size.x = 160.0
    header.add_child(_status_label)

    var body := HBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    var left := VBoxContainer.new()
    left.custom_minimum_size.x = 250.0
    body.add_child(left)

    _search = LineEdit.new()
    _search.placeholder_text = "Search modules"
    _search.text_changed.connect(func(_t: String): _refresh_module_list())
    left.add_child(_search)

    _list = ItemList.new()
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.item_selected.connect(_on_list_selected)
    left.add_child(_list)

    var center := VBoxContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(center)

    var mode_row := HBoxContainer.new()
    center.add_child(mode_row)

    _mode_select = OptionButton.new()
    _mode_select.add_item("Cells", 0)
    _mode_select.add_item("Sprite Offset", 1)
    mode_row.add_child(_mode_select)

    var fit_btn := Button.new()
    fit_btn.text = "Fit Count"
    fit_btn.pressed.connect(_fit_hex_size_to_shape)
    mode_row.add_child(fit_btn)

    var rot_left_btn := Button.new()
    rot_left_btn.text = "Rotate Cells -60"
    rot_left_btn.pressed.connect(_rotate_footprint.bind(-1))
    mode_row.add_child(rot_left_btn)

    var rot_right_btn := Button.new()
    rot_right_btn.text = "Rotate Cells +60"
    rot_right_btn.pressed.connect(_rotate_footprint.bind(1))
    mode_row.add_child(rot_right_btn)

    var reset_btn := Button.new()
    reset_btn.text = "Reset Footprint"
    reset_btn.pressed.connect(_reset_footprint)
    mode_row.add_child(reset_btn)

    _canvas = FootprintCanvas.new()
    _canvas.editor = self
    _canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _canvas.custom_minimum_size = Vector2(420, 420)
    center.add_child(_canvas)

    var right_scroll := ScrollContainer.new()
    right_scroll.custom_minimum_size.x = 390.0
    right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(right_scroll)

    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.add_child(right)

    _name_edit = _make_line(right, "Name", _on_name_submitted)
    _type_edit = _make_line(right, "Type", _on_type_submitted)
    _sprite_edit = _make_line(right, "Sprite", _on_sprite_submitted)

    _sprite_select = OptionButton.new()
    _sprite_select.item_selected.connect(_on_sprite_selected)
    right.add_child(_labeled_control("Sprite Picker", _sprite_select))

    _hex_size_spin = _make_spin(right, "Cell Count", 1.0, 64.0, 1.0, _on_hex_size_changed)
    _sprite_cell_spin = _make_spin(right, "Sprite Cell Px", 1.0, 256.0, 1.0, _on_sprite_cell_changed)
    _sprite_scale_spin = _make_spin(right, "Sprite Scale", 0.05, 8.0, 0.05, _on_sprite_scale_changed)
    _sprite_rot_spin = _make_spin(right, "Rotation", -360.0, 360.0, 1.0, _on_sprite_rot_changed)
    _offset_x_spin = _make_spin(right, "Offset X", -512.0, 512.0, 1.0, _on_offset_x_changed)
    _offset_y_spin = _make_spin(right, "Offset Y", -512.0, 512.0, 1.0, _on_offset_y_changed)

    var rotate_row := HBoxContainer.new()
    right.add_child(rotate_row)
    for pair in [["-60", -60.0], ["-15", -15.0], ["0", 0.0], ["+15", 15.0], ["+60", 60.0]]:
        var b := Button.new()
        b.text = str(pair[0])
        b.pressed.connect(_adjust_sprite_rotation.bind(float(pair[1])))
        rotate_row.add_child(b)

    var raw_label := Label.new()
    raw_label.text = "Raw Module JSON"
    raw_label.add_theme_font_size_override("font_size", 13)
    right.add_child(raw_label)

    _raw_json = TextEdit.new()
    _raw_json.custom_minimum_size = Vector2(340, 240)
    _raw_json.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.add_child(_raw_json)

    var raw_apply := Button.new()
    raw_apply.text = "Apply Raw JSON"
    raw_apply.pressed.connect(_apply_raw_json)
    right.add_child(raw_apply)


func _labeled_control(label: String, control: Control) -> Control:
    var box := VBoxContainer.new()
    var l := Label.new()
    l.text = label
    box.add_child(l)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(control)
    return box


func _make_line(parent: VBoxContainer, label: String, submitted: Callable) -> LineEdit:
    var line := LineEdit.new()
    line.text_submitted.connect(submitted)
    line.focus_exited.connect(func(): submitted.call(line.text))
    parent.add_child(_labeled_control(label, line))
    return line


func _make_spin(parent: VBoxContainer, label: String, min_v: float, max_v: float, step_v: float, changed: Callable) -> SpinBox:
    var spin := SpinBox.new()
    spin.min_value = min_v
    spin.max_value = max_v
    spin.step = step_v
    spin.allow_greater = true
    spin.allow_lesser = true
    spin.value_changed.connect(changed)
    parent.add_child(_labeled_control(label, spin))
    return spin


func _load_data() -> void:
    data.clear()
    for id in DataManager.modules:
        data[str(id)] = DataManager.modules[id].duplicate(true)


func _load_sprite_names() -> void:
    _sprite_names.clear()
    _sprite_cache.clear()
    var dir := DirAccess.open(ART_DIR)
    if dir == null:
        return
    dir.list_dir_begin()
    var filename := dir.get_next()
    while filename != "":
        if not dir.current_is_dir() and filename.to_lower().ends_with(".png"):
            _sprite_names.append(filename.get_basename())
        filename = dir.get_next()
    dir.list_dir_end()
    _sprite_names.sort()


func _refresh_module_list() -> void:
    if _list == null:
        return
    var filter := _search.text.strip_edges().to_lower() if _search != null else ""
    _list.clear()
    var ids := data.keys()
    ids.sort()
    for id_v in ids:
        var id := str(id_v)
        var entry: Dictionary = data[id]
        var label := "%s  [%s]" % [str(entry.get("name", id)), id]
        if filter != "" and not label.to_lower().contains(filter):
            continue
        _list.add_item(label)
        var idx: int = _list.item_count - 1
        _list.set_item_metadata(idx, id)
        if id == selected_id:
            _list.select(idx)


func _on_list_selected(index: int) -> void:
    _select_module(str(_list.get_item_metadata(index)))


func _select_module(id: String) -> void:
    if not data.has(id):
        return
    selected_id = id
    _sync_controls()
    _refresh_module_list()
    _redraw_preview()


func _sync_controls() -> void:
    _updating_controls = true
    var entry: Dictionary = _current_entry()
    if entry.is_empty():
        _updating_controls = false
        return
    _name_edit.text = str(entry.get("name", selected_id))
    _type_edit.text = str(entry.get("type", ""))
    _sprite_edit.text = str(entry.get("sprite", ""))
    _hex_size_spin.value = float(entry.get("hex_size", _shape_array(entry).size()))
    _sprite_cell_spin.value = ModuleVisuals.get_sprite_cell_size(entry)
    _sprite_scale_spin.value = float(entry.get("sprite_scale", 1.0))
    _sprite_rot_spin.value = float(entry.get("sprite_rotation_deg", 0.0))
    var off := _entry_sprite_offset(entry)
    _offset_x_spin.value = off.x
    _offset_y_spin.value = off.y
    _refresh_sprite_select(str(entry.get("sprite", "")))
    _raw_json.text = JSON.stringify(entry, "\t")
    _updating_controls = false


func _refresh_sprite_select(current_sprite: String) -> void:
    _sprite_select.clear()
    _sprite_select.add_item("(none)")
    var selected_idx := 0
    for name_v in _sprite_names:
        var name := str(name_v)
        _sprite_select.add_item(name)
        var idx: int = _sprite_select.item_count - 1
        if name == current_sprite:
            selected_idx = idx
    _sprite_select.select(selected_idx)


func _current_entry() -> Dictionary:
    if selected_id == "" or not data.has(selected_id):
        return {}
    return data[selected_id]


func _shape_array(entry: Dictionary) -> Array:
    var shape: Array = entry.get("hex_shape", [])
    if shape.is_empty():
        shape = HexUtil.default_shape(int(entry.get("hex_size", 1)))
    return shape


func _entry_sprite_offset(entry: Dictionary) -> Vector2:
    var raw: Variant = entry.get("sprite_offset", [0.0, 0.0])
    if raw is Array and raw.size() >= 2:
        return Vector2(float(raw[0]), float(raw[1]))
    if raw is Dictionary:
        return Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
    return Vector2.ZERO


func _set_entry_sprite_offset(offset: Vector2) -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    entry["sprite_offset"] = [snappedf(offset.x, 0.1), snappedf(offset.y, 0.1)]
    _mark_dirty()
    _sync_offset_spins(offset)
    _sync_raw_json()
    _redraw_preview()


func _sync_offset_spins(offset: Vector2) -> void:
    _updating_controls = true
    _offset_x_spin.value = offset.x
    _offset_y_spin.value = offset.y
    _updating_controls = false


func _mark_dirty() -> void:
    _dirty = true
    _update_status()


func _set_status(text: String, seconds: float = 2.0) -> void:
    _status_text = text
    _status_timer = seconds
    _update_status()


func _update_status() -> void:
    if _status_label == null:
        return
    if _status_text != "":
        _status_label.text = _status_text
    elif _dirty:
        _status_label.text = "Unsaved"
    else:
        _status_label.text = ""


func _sync_raw_json() -> void:
    if _raw_json == null or _raw_json.has_focus():
        return
    var entry := _current_entry()
    if not entry.is_empty():
        _raw_json.text = JSON.stringify(entry, "\t")


func _on_name_submitted(text: String) -> void:
    _set_field("name", text)
    _refresh_module_list()


func _on_type_submitted(text: String) -> void:
    _set_field("type", text)


func _on_sprite_submitted(text: String) -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    var sprite := text.strip_edges()
    if sprite == "":
        entry.erase("sprite")
    else:
        entry["sprite"] = sprite
    _mark_dirty()
    _refresh_sprite_select(sprite)
    _sync_raw_json()
    _redraw_preview()


func _set_field(key: String, value: Variant) -> void:
    if _updating_controls:
        return
    var entry := _current_entry()
    if entry.is_empty():
        return
    entry[key] = value
    _mark_dirty()
    _sync_raw_json()
    _redraw_preview()


func _on_sprite_selected(index: int) -> void:
    if _updating_controls:
        return
    var sprite := ""
    if index > 0:
        sprite = _sprite_select.get_item_text(index)
    _sprite_edit.text = sprite
    _on_sprite_submitted(sprite)


func _on_hex_size_changed(value: float) -> void:
    if _updating_controls:
        return
    var entry := _current_entry()
    if entry.is_empty():
        return
    var new_size: int = maxi(1, int(round(value)))
    entry["hex_size"] = new_size
    if not entry.has("hex_shape") or entry.get("hex_shape", []).is_empty():
        entry["hex_shape"] = HexUtil.default_shape(new_size)
    _mark_dirty()
    _sync_raw_json()
    _redraw_preview()


func _on_sprite_cell_changed(value: float) -> void:
    _set_field("sprite_cell_size", maxf(value, 1.0))


func _on_sprite_scale_changed(value: float) -> void:
    _set_field("sprite_scale", maxf(value, 0.01))


func _on_sprite_rot_changed(value: float) -> void:
    _set_field("sprite_rotation_deg", value)


func _on_offset_x_changed(value: float) -> void:
    if _updating_controls:
        return
    var offset := _entry_sprite_offset(_current_entry())
    offset.x = value
    _set_entry_sprite_offset(offset)


func _on_offset_y_changed(value: float) -> void:
    if _updating_controls:
        return
    var offset := _entry_sprite_offset(_current_entry())
    offset.y = value
    _set_entry_sprite_offset(offset)


func _adjust_sprite_rotation(delta: float) -> void:
    if selected_id == "":
        return
    if absf(delta) < 0.001:
        _sprite_rot_spin.value = 0.0
    else:
        _sprite_rot_spin.value = float(_sprite_rot_spin.value) + delta


func _fit_hex_size_to_shape() -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    entry["hex_size"] = maxi(1, _shape_array(entry).size())
    _mark_dirty()
    _sync_controls()
    _redraw_preview()


func _reset_footprint() -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    var size_count: int = maxi(1, int(entry.get("hex_size", 1)))
    entry["hex_shape"] = HexUtil.default_shape(size_count)
    _mark_dirty()
    _sync_raw_json()
    _redraw_preview()


func _rotate_footprint(direction: int) -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    var shape := _shape_array(entry)
    if shape.is_empty():
        return
    var rotated := shape.duplicate(true)
    if direction < 0:
        rotated = HexUtil.rotate_shape_ccw(rotated)
    else:
        rotated = HexUtil.rotate_shape_cw(rotated)
    entry["hex_shape"] = _sort_shape(rotated)
    entry["hex_size"] = entry["hex_shape"].size()
    _mark_dirty()
    _sync_controls()
    _redraw_preview()


func _apply_raw_json() -> void:
    if selected_id == "":
        return
    var parsed: Variant = JSON.parse_string(_raw_json.text)
    if not (parsed is Dictionary):
        _set_status("Raw JSON error", 3.0)
        return
    data[selected_id] = parsed
    _mark_dirty()
    _sync_controls()
    _refresh_module_list()
    _set_status("Applied raw JSON", 2.0)


func _add_module() -> void:
    var base := "new_module"
    var idx := 1
    while data.has("%s_%d" % [base, idx]):
        idx += 1
    var id := "%s_%d" % [base, idx]
    data[id] = {
        "name": "New Module",
        "type": "weapon",
        "subtype": "energy",
        "tier": "standard",
        "hex_size": 1,
        "hex_shape": [[0, 0]],
        "sprite_cell_size": 50,
        "sprite_scale": 1.0,
        "sprite_rotation_deg": 0.0,
        "sprite_offset": [0, 0],
        "stats": {"power_draw": 1},
        "description": "A new module."
    }
    _mark_dirty()
    _refresh_module_list()
    _select_module(id)


func _duplicate_module() -> void:
    if selected_id == "" or not data.has(selected_id):
        return
    var base := selected_id + "_copy"
    var id := base
    var idx := 2
    while data.has(id):
        id = "%s_%d" % [base, idx]
        idx += 1
    data[id] = data[selected_id].duplicate(true)
    data[id]["name"] = str(data[id].get("name", selected_id)) + " Copy"
    _mark_dirty()
    _refresh_module_list()
    _select_module(id)


func _delete_module() -> void:
    if selected_id == "" or not data.has(selected_id):
        return
    data.erase(selected_id)
    selected_id = ""
    _mark_dirty()
    _refresh_module_list()
    if _list.item_count > 0:
        _select_module(str(_list.get_item_metadata(0)))
    else:
        _sync_controls()


func _add_to_inventory() -> void:
    if selected_id == "" or not data.has(selected_id):
        return
    GameManager.add_module(selected_id, 1)
    _set_status("Added to inventory", 2.0)


func _save_data() -> void:
    DataManager.modules = data.duplicate(true)
    GameManager.invalidate_module_sprites()
    var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
    if file == null:
        _set_status("Save failed", 3.0)
        return
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
    _dirty = false
    _set_status("Saved", 2.0)


func _redraw_preview() -> void:
    if _canvas != null:
        _canvas.queue_redraw()


func _canvas_origin(canvas: Control) -> Vector2:
    return canvas.size * 0.5


func _draw_visual_canvas(canvas: Control) -> void:
    var entry := _current_entry()
    var rect := Rect2(Vector2.ZERO, canvas.size)
    canvas.draw_rect(rect, Color(0.045, 0.05, 0.072))
    canvas.draw_rect(rect, Color(0.16, 0.19, 0.24), false, 1.0)
    if entry.is_empty():
        return

    var origin := _canvas_origin(canvas)
    var shape := _shape_array(entry)
    var occupied := {}
    for cell_v in shape:
        var cell: Array = cell_v
        occupied[Vector2i(int(cell[0]), int(cell[1]))] = true

    for q in range(-5, 6):
        for r in range(-5, 6):
            var cell := Vector2i(q, r)
            if HexUtil.hex_distance(Vector2i.ZERO, cell) > 5:
                continue
            var center := origin + HexUtil.hex_to_pixel(cell, PREVIEW_HEX_SIZE)
            var corners := HexUtil.hex_corners(center, PREVIEW_HEX_SIZE - 2.0)
            var is_on := occupied.has(cell)
            var fill := Color(0.08, 0.095, 0.125)
            if is_on:
                fill = Color(0.22, 0.52, 0.68, 0.78)
            if cell == Vector2i.ZERO:
                fill = fill.lerp(Color(0.8, 0.65, 0.25), 0.18)
            canvas.draw_colored_polygon(corners, fill)
            canvas.draw_polyline(_closed_poly(corners), Color(0.34, 0.42, 0.52, 0.75), 1.0)

    _draw_preview_sprite(canvas, entry, origin)

    var font := ThemeDB.fallback_font
    var mode_label := _mode_select.get_item_text(_mode_select.selected) if _mode_select != null else "Cells"
    canvas.draw_string(font, Vector2(12, 22), "%s: %s" % [selected_id, mode_label], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.82, 0.88, 0.94))


func _closed_poly(points: PackedVector2Array) -> PackedVector2Array:
    var closed := PackedVector2Array(points)
    if closed.size() > 0:
        closed.append(closed[0])
    return closed


func _draw_preview_sprite(canvas: Control, entry: Dictionary, origin: Vector2) -> void:
    _last_sprite_rect = Rect2()
    var sprite_name := str(entry.get("sprite", ""))
    if sprite_name == "":
        return
    var tex := _load_sprite(sprite_name)
    if tex == null:
        return
    var center := origin + ModuleVisuals.get_canonical_sprite_center(entry, PREVIEW_HEX_SIZE)
    var scale_v := ModuleVisuals.get_sprite_scale(entry, PREVIEW_HEX_SIZE)
    var rot := ModuleVisuals.get_sprite_rotation_rad(entry)
    var half := Vector2(tex.get_width(), tex.get_height()) * scale_v * 0.5
    _last_sprite_rect = Rect2(center - half, half * 2.0).grow(10.0)
    canvas.draw_set_transform(center, rot, Vector2(scale_v, scale_v))
    canvas.draw_texture(tex, Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.5))
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    canvas.draw_circle(center, 3.0, Color(1.0, 0.9, 0.35, 0.9))


func _load_sprite(sprite_name: String) -> Texture2D:
    if _sprite_cache.has(sprite_name):
        return _sprite_cache[sprite_name]
    var tex: Texture2D = GameManager.get_module_sprite(sprite_name)
    _sprite_cache[sprite_name] = tex
    return tex


func _visual_canvas_input(event: InputEvent) -> void:
    if selected_id == "":
        return
    var entry := _current_entry()
    if entry.is_empty():
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                if _edit_mode_is_sprite():
                    _dragging_sprite = true
                    _drag_start_mouse = mb.position
                    _drag_start_offset = _entry_sprite_offset(entry)
                    _canvas.accept_event()
                    return
                _toggle_cell_at(mb.position)
                _canvas.accept_event()
            else:
                _dragging_sprite = false
                _canvas.accept_event()
        elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            _toggle_cell_at(mb.position)
            _canvas.accept_event()
    elif event is InputEventMouseMotion and _dragging_sprite:
        var mm := event as InputEventMouseMotion
        var delta := mm.position - _drag_start_mouse
        var source_scale := ModuleVisuals.get_sprite_cell_size(entry) / PREVIEW_HEX_SIZE
        var canonical_delta := delta * source_scale
        _set_entry_sprite_offset(_drag_start_offset + canonical_delta)
        _canvas.accept_event()


func _edit_mode_is_sprite() -> bool:
    return _mode_select != null and _mode_select.selected == 1


func _toggle_cell_at(pos: Vector2) -> void:
    var entry := _current_entry()
    if entry.is_empty():
        return
    var cell := _preview_pixel_to_hex(pos - _canvas_origin(_canvas))
    if HexUtil.hex_distance(Vector2i.ZERO, cell) > 5:
        return
    var shape := _shape_array(entry)
    var found := -1
    for i in shape.size():
        var c: Array = shape[i]
        if int(c[0]) == cell.x and int(c[1]) == cell.y:
            found = i
            break
    if found >= 0:
        if shape.size() <= 1:
            return
        shape.remove_at(found)
    else:
        shape.append([cell.x, cell.y])
    entry["hex_shape"] = _sort_shape(shape)
    entry["hex_size"] = entry["hex_shape"].size()
    _mark_dirty()
    _sync_controls()
    _redraw_preview()


func _sort_shape(shape: Array) -> Array:
    var out := shape.duplicate(true)
    out.sort_custom(func(a: Array, b: Array) -> bool:
        if int(a[1]) == int(b[1]):
            return int(a[0]) < int(b[0])
        return int(a[1]) < int(b[1])
    )
    return out


func _preview_pixel_to_hex(pixel: Vector2) -> Vector2i:
    return HexUtil.pixel_to_hex(pixel, PREVIEW_HEX_SIZE)
