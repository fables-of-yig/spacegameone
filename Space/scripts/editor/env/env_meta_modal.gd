extends Control

# Full-screen modal for editing a room's metadata: width, height, tileset,
# plus authored far/mid/near parallax image paths and per-layer scroll
# speeds. Fires `submitted(meta)` with the updated dict on OK.

signal submitted(meta: Dictionary)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")
const PackAssetIndex = preload("res://Space/scripts/editor/pack_asset_index.gd")

const BOX_W: float = 860.0
const BOX_H: float = 620.0

const PARALLAX_ROWS := [
    {"name": "far", "label": "Far"},
    {"name": "mid", "label": "Mid"},
    {"name": "near", "label": "Near"},
]
const PARALLAX_SPEED_PRESETS := [
    {
        "id": "gentle",
        "label": "GENTLE",
        "rows": [
            {"x": 0.04, "y": 0.02},
            {"x": 0.10, "y": 0.05},
            {"x": 0.20, "y": 0.08},
        ],
    },
    {
        "id": "balanced",
        "label": "BALANCED",
        "rows": [
            {"x": 0.10, "y": 0.05},
            {"x": 0.24, "y": 0.10},
            {"x": 0.42, "y": 0.16},
        ],
    },
    {
        "id": "locked",
        "label": "ROOM-LOCKED",
        "rows": [
            {"x": 1.00, "y": 1.00},
            {"x": 1.00, "y": 1.00},
            {"x": 1.00, "y": 1.00},
        ],
    },
]

var _title: String = ""
var _pack_id: String = "demo"
var _width_edit: LineEdit = null
var _height_edit: LineEdit = null
var _selected_tileset: int = 0
var _available_tilesets: Array = []
var _available_backdrops: Array = []
var _error_text: String = ""
var _parallax_rows: Array = []
var _parallax_preset_rects: Array = []
var _import_parallax_btn: Button = null
var _import_parallax_dialog: FileDialog = null

var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()
var _tileset_rects: Array = []


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)

    _width_edit = _make_line_edit("30")
    _height_edit = _make_line_edit("17")
    add_child(_width_edit)
    add_child(_height_edit)

    _import_parallax_btn = Button.new()
    _import_parallax_btn.text = "IMPORT PARALLAX"
    _import_parallax_btn.pressed.connect(_on_import_parallax_pressed)
    add_child(_import_parallax_btn)

    _import_parallax_dialog = FileDialog.new()
    _import_parallax_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _import_parallax_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    _import_parallax_dialog.filters = PackedStringArray(["*.png ; PNG images"])
    _import_parallax_dialog.title = "Choose 1-3 parallax PNGs"
    _import_parallax_dialog.files_selected.connect(_on_import_parallax_files_selected)
    add_child(_import_parallax_dialog)

    for row_v in PARALLAX_ROWS:
        var row: Dictionary = row_v
        var path_edit := _make_line_edit("Backdrops/Parallax/example.png")
        var picker := OptionButton.new()
        picker.custom_minimum_size = Vector2(170, 0)
        picker.item_selected.connect(_on_backdrop_picked.bind(str(row.get("name", ""))))
        var sx_edit := _make_line_edit("0.50")
        var sy_edit := _make_line_edit("0.18")
        sx_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
        sy_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
        add_child(path_edit)
        add_child(picker)
        add_child(sx_edit)
        add_child(sy_edit)
        _parallax_rows.append({
            "name": str(row.get("name", "")),
            "label": str(row.get("label", "")),
            "path_edit": path_edit,
            "picker": picker,
            "sx_edit": sx_edit,
            "sy_edit": sy_edit,
        })
    _layout_fields()


func _make_line_edit(placeholder: String) -> LineEdit:
    var le := LineEdit.new()
    le.placeholder_text = placeholder
    le.text_submitted.connect(_on_any_text_submitted)
    return le


func _process(_delta):
    if visible:
        queue_redraw()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_fields()


func open(room_addr: String, meta: Dictionary, available_tilesets: Array, pack_id: String = "demo") -> void:
    _title = "Room settings - %s" % room_addr
    _pack_id = pack_id.strip_edges()
    if _pack_id.is_empty():
        _pack_id = "demo"
    _error_text = ""
    _available_tilesets = available_tilesets.duplicate()
    _available_backdrops = PackAssetIndex.list_pack_pngs(_pack_id, "Backdrops/Parallax")
    _selected_tileset = int(meta.get("tileset", 0))
    visible = true

    if _width_edit != null:
        _width_edit.text = str(int(meta.get("width_blocks", 30)))
        _width_edit.grab_focus.call_deferred()
        _width_edit.select_all.call_deferred()
    if _height_edit != null:
        _height_edit.text = str(int(meta.get("height_blocks", 17)))

    var defaults := EnvIO.default_parallax_layers()
    var layers_v: Variant = meta.get("parallax_layers", defaults)
    var layers: Array = defaults
    if typeof(layers_v) == TYPE_ARRAY:
        layers = (layers_v as Array).duplicate(true)
    for i in range(_parallax_rows.size()):
        var row: Dictionary = _parallax_rows[i]
        var fallback: Dictionary = defaults[i]
        var src: Dictionary = fallback
        if i < layers.size() and typeof(layers[i]) == TYPE_DICTIONARY:
            src = layers[i]
        var image_path: String = str(src.get("image", ""))
        (row["path_edit"] as LineEdit).text = image_path
        (row["sx_edit"] as LineEdit).text = "%.2f" % float(src.get("scroll_speed_x", fallback.get("scroll_speed_x", 1.0)))
        (row["sy_edit"] as LineEdit).text = "%.2f" % float(src.get("scroll_speed_y", fallback.get("scroll_speed_y", 1.0)))
        _refresh_backdrop_picker(row, image_path)

    _layout_fields()
    queue_redraw()


func close() -> void:
    visible = false


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _layout_fields() -> void:
    if _width_edit == null:
        return
    var box := _box_rect()
    var field_w: float = 120.0
    var field_h: float = 28.0
    _width_edit.position = Vector2(box.position.x + 160, box.position.y + 70)
    _width_edit.size = Vector2(field_w, field_h)
    _height_edit.position = Vector2(box.position.x + 160, box.position.y + 110)
    _height_edit.size = Vector2(field_w, field_h)
    if _import_parallax_btn != null:
        _import_parallax_btn.position = Vector2(box.position.x + box.size.x - 172.0, box.position.y + 150.0)
        _import_parallax_btn.size = Vector2(148.0, 30.0)

    var start_y := box.position.y + 294.0
    for i in range(_parallax_rows.size()):
        var row: Dictionary = _parallax_rows[i]
        var y := start_y + float(i) * 74.0
        var path_edit := row["path_edit"] as LineEdit
        var picker := row["picker"] as OptionButton
        var sx_edit := row["sx_edit"] as LineEdit
        var sy_edit := row["sy_edit"] as LineEdit
        path_edit.position = Vector2(box.position.x + 160.0, y)
        path_edit.size = Vector2(290.0, field_h)
        picker.position = Vector2(box.position.x + 456.0, y)
        picker.size = Vector2(174.0, field_h)
        sx_edit.position = Vector2(box.position.x + 666.0, y)
        sx_edit.size = Vector2(74.0, field_h)
        sy_edit.position = Vector2(box.position.x + 754.0, y)
        sy_edit.size = Vector2(74.0, field_h)


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _ok_rect.has_point(mb.position):
                _confirm()
                accept_event()
                return
            if _cancel_rect.has_point(mb.position):
                _cancel()
                accept_event()
                return
            for preset_v in _parallax_preset_rects:
                var preset: Dictionary = preset_v
                var preset_rect: Rect2 = preset.get("rect", Rect2())
                if preset_rect.has_point(mb.position):
                    _apply_parallax_speed_preset(str(preset.get("id", "")))
                    accept_event()
                    return
            for entry in _tileset_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    _selected_tileset = int(entry["idx"])
                    accept_event()
                    return
            var box := _box_rect()
            if not box.has_point(mb.position):
                _cancel()
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _cancel()
            get_viewport().set_input_as_handled()


func _on_import_parallax_pressed() -> void:
    if _import_parallax_dialog == null:
        return
    _error_text = ""
    _import_parallax_dialog.popup_centered_ratio(0.72)


func _on_import_parallax_files_selected(paths: PackedStringArray) -> void:
    if paths.is_empty():
        return
    if paths.size() > 3:
        _error_text = "Choose up to 3 PNGs for Far, Mid, and Near."
        queue_redraw()
        return
    var assignments: Array = _parallax_import_assignments(paths)
    var ordered_paths: PackedStringArray = PackedStringArray()
    for entry_v in assignments:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        ordered_paths.append(str((entry_v as Dictionary).get("path", "")))
    var imported: Array = EnvIO.import_backdrops(_pack_id, ordered_paths)
    if imported.is_empty():
        _error_text = "Parallax import failed."
        queue_redraw()
        return
    _available_backdrops = PackAssetIndex.list_pack_pngs(_pack_id, "Backdrops/Parallax")
    for i in range(mini(imported.size(), assignments.size())):
        var entry: Dictionary = assignments[i]
        var row_idx: int = int(entry.get("slot", i))
        if row_idx < 0 or row_idx >= _parallax_rows.size():
            continue
        var row: Dictionary = _parallax_rows[row_idx]
        var rel_path: String = str(imported[i]).strip_edges()
        var path_edit: LineEdit = row.get("path_edit")
        if path_edit != null:
            path_edit.text = rel_path
        _refresh_backdrop_picker(row, rel_path)
    _error_text = ""
    queue_redraw()


func _on_any_text_submitted(_t: String) -> void:
    _confirm()


func _parallax_import_assignments(paths: PackedStringArray) -> Array:
    var slots: Array = [null, null, null]
    var overflow: Array = []
    for path_v in paths:
        var path: String = str(path_v)
        var slot: int = _parallax_slot_for_path(path)
        if slot >= 0 and slots[slot] == null:
            slots[slot] = path
        else:
            overflow.append(path)
    var out: Array = []
    var overflow_idx: int = 0
    for i in range(slots.size()):
        if slots[i] == null and overflow_idx < overflow.size():
            slots[i] = overflow[overflow_idx]
            overflow_idx += 1
        if slots[i] != null:
            out.append({
                "slot": i,
                "path": str(slots[i]),
            })
    return out


func _parallax_slot_for_path(path: String) -> int:
    var file_name: String = path.get_file().get_basename().to_lower()
    if file_name.contains("far") or file_name.contains("back"):
        return 0
    if file_name.contains("mid") or file_name.contains("middle"):
        return 1
    if file_name.contains("near") or file_name.contains("front") or file_name.contains("fg"):
        return 2
    if file_name.contains("bg1"):
        return 0
    if file_name.contains("bg2"):
        return 1
    if file_name.contains("bg3"):
        return 2
    return -1


func _confirm() -> void:
    var w_str: String = _width_edit.text if _width_edit != null else "30"
    var h_str: String = _height_edit.text if _height_edit != null else "17"
    if not w_str.is_valid_int():
        _error_text = "Width must be a whole number."
        queue_redraw()
        return
    if not h_str.is_valid_int():
        _error_text = "Height must be a whole number."
        queue_redraw()
        return
    var w := clampi(int(w_str), 4, 256)
    var h := clampi(int(h_str), 4, 256)

    var layers: Array = []
    for row in _parallax_rows:
        var path_edit := row["path_edit"] as LineEdit
        var sx_edit := row["sx_edit"] as LineEdit
        var sy_edit := row["sy_edit"] as LineEdit
        var sx_str := sx_edit.text.strip_edges()
        var sy_str := sy_edit.text.strip_edges()
        if not sx_str.is_valid_float():
            _error_text = "%s X speed must be a number." % str(row["label"])
            queue_redraw()
            return
        if not sy_str.is_valid_float():
            _error_text = "%s Y speed must be a number." % str(row["label"])
            queue_redraw()
            return
        layers.append({
            "name": str(row["name"]),
            "image": path_edit.text.strip_edges(),
            "scroll_speed_x": clampf(float(sx_str), 0.0, 2.0),
            "scroll_speed_y": clampf(float(sy_str), 0.0, 2.0),
        })

    _error_text = ""
    var meta := {
        "width_blocks": w,
        "height_blocks": h,
        "tileset": _selected_tileset,
        "parallax_layers": layers,
    }
    visible = false
    submitted.emit(meta)


func _cancel() -> void:
    visible = false
    cancelled.emit()


func _draw():
    if not visible:
        return

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)

    var box := _box_rect()
    UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, box.position + Vector2(24, 36),
        _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    draw_string(font, box.position + Vector2(24, 56),
        "Leave image paths blank to disable a layer. Relative paths resolve inside the pack folder.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    draw_string(font, box.position + Vector2(24, 90),
        "Width (blocks)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    draw_string(font, box.position + Vector2(24, 130),
        "Height (blocks)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)

    if _width_edit != null and Rect2(_width_edit.position, _width_edit.size).has_point(mouse_pos):
        EditorTooltip.show_text("Room width in 16px blocks (4-256). Resizing preserves cells inside the new bounds.")
    if _height_edit != null and Rect2(_height_edit.position, _height_edit.size).has_point(mouse_pos):
        EditorTooltip.show_text("Room height in 16px blocks (4-256). Resizing preserves cells inside the new bounds.")
    if _import_parallax_btn != null and Rect2(_import_parallax_btn.position, _import_parallax_btn.size).has_point(mouse_pos):
        EditorTooltip.show_text("Import up to 3 PNGs into this pack's Backdrops/Parallax folder and auto-fill Far, Mid, and Near.")

    draw_string(font, box.position + Vector2(24, 170),
        "Tileset", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    _tileset_rects.clear()
    var tab_x: float = box.position.x + 160
    var tab_y: float = box.position.y + 158
    var tab_w: float = 40.0
    var tab_h: float = 28.0
    var tab_gap: float = 4.0
    for idx in _available_tilesets:
        var rect := Rect2(tab_x, tab_y, tab_w, tab_h)
        _tileset_rects.append({"idx": idx, "rect": rect})
        var is_active := int(idx) == _selected_tileset
        var is_hover := rect.has_point(mouse_pos)
        var tint := Color(0.4, 0.85, 1.0, 1.0) if is_active else Color(0.35, 0.45, 0.6, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hover, tint)
        draw_string(font, rect.position + Vector2(8, 18),
            "%02d" % int(idx), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(1, 1, 1, 1) if is_active else Color(0.75, 0.85, 0.95, 1))
        if is_hover:
            EditorTooltip.show_text("Default room tileset. Tile gaps remain transparent, so authored parallax can show through behind the room art.")
        tab_x += tab_w + tab_gap

    if _available_tilesets.is_empty():
        draw_string(font, box.position + Vector2(160, 178),
            "(none)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.55, 0.55, 1))

    var panel_rect := Rect2(box.position.x + 16.0, box.position.y + 218.0, box.size.x - 32.0, 322.0)
    draw_rect(panel_rect, Color(0.08, 0.1, 0.15, 0.92))
    draw_rect(panel_rect, Color(0.36, 0.48, 0.62, 0.9), false, 1.5)
    draw_string(font, Vector2(panel_rect.position.x + 12.0, panel_rect.position.y + 22.0),
        "Parallax Layers", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPanels.TEXT_PANEL)
    _parallax_preset_rects.clear()
    var preset_btn_w: float = 88.0
    var preset_btn_h: float = 24.0
    var preset_gap: float = 8.0
    var preset_x: float = panel_rect.position.x + panel_rect.size.x - 12.0 - (preset_btn_w * 3.0 + preset_gap * 2.0)
    var preset_y: float = panel_rect.position.y + 34.0
    for i in range(PARALLAX_SPEED_PRESETS.size()):
        var preset: Dictionary = PARALLAX_SPEED_PRESETS[i]
        var preset_rect := Rect2(
            preset_x + float(i) * (preset_btn_w + preset_gap),
            preset_y,
            preset_btn_w,
            preset_btn_h
        )
        var preset_hover := preset_rect.has_point(mouse_pos)
        UIPanels.draw_button_bg(self, preset_rect, preset_hover, Color(0.32, 0.44, 0.64, 1.0))
        draw_string(font, preset_rect.position + Vector2(10.0, 16.0),
            str(preset.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.95, 0.98, 1.0, 1.0))
        _parallax_preset_rects.append({
            "id": str(preset.get("id", "")),
            "rect": preset_rect,
        })
        if preset_hover:
            match str(preset.get("id", "")):
                "gentle":
                    EditorTooltip.show_text("Apply a much slower parallax stack. Best when the current backdrop motion feels too aggressive.")
                "balanced":
                    EditorTooltip.show_text("Apply a calmer default parallax stack with readable depth but less eye strain.")
                "locked":
                    EditorTooltip.show_text("Lock all parallax layers to room movement. Useful when you want static backdrops.")
    draw_string(font, Vector2(panel_rect.position.x + 145.0, panel_rect.position.y + 70.0),
        "Image Path", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(panel_rect.position.x + 651.0, panel_rect.position.y + 70.0),
        "X SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(panel_rect.position.x + 739.0, panel_rect.position.y + 70.0),
        "Y SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    for i in range(_parallax_rows.size()):
        var row: Dictionary = _parallax_rows[i]
        var y := panel_rect.position.y + 94.0 + float(i) * 74.0
        var row_rect := Rect2(panel_rect.position.x + 8.0, y - 10.0, panel_rect.size.x - 16.0, 54.0)
        draw_rect(row_rect, Color(0.14, 0.17, 0.24, 0.88))
        draw_string(font, Vector2(panel_rect.position.x + 18.0, y + 10.0),
            str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPanels.TEXT_PANEL)
        draw_string(font, Vector2(panel_rect.position.x + 18.0, y + 28.0),
            "Layer / Motion", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

        var path_edit := row["path_edit"] as LineEdit
        var picker := row["picker"] as OptionButton
        var sx_edit := row["sx_edit"] as LineEdit
        var sy_edit := row["sy_edit"] as LineEdit
        if Rect2(path_edit.position, path_edit.size).has_point(mouse_pos):
            EditorTooltip.show_text("%s image path. Example: Backdrops/Parallax/desert_ocean_far.png or an absolute res:// / user:// path." % str(row["label"]))
        elif Rect2(picker.position, picker.size).has_point(mouse_pos):
            EditorTooltip.show_text("Pick one of the imported parallax images already inside this pack.")
        elif Rect2(sx_edit.position, sx_edit.size).has_point(mouse_pos):
            EditorTooltip.show_text("%s X parallax speed. Lower = slower camera response, so the layer feels farther back." % str(row["label"]))
        elif Rect2(sy_edit.position, sy_edit.size).has_point(mouse_pos):
            EditorTooltip.show_text("%s Y parallax speed. Use values below 1.0 for depth; 1.0 locks to the room." % str(row["label"]))

    if not _error_text.is_empty():
        draw_string(font, box.position + Vector2(24, box.size.y - 54),
            _error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.4, 1.0))

    var btn_w: float = 96.0
    var btn_h: float = 30.0
    var btn_y: float = box.position.y + box.size.y - btn_h - 16.0
    _ok_rect = Rect2(box.position.x + box.size.x - btn_w - 16.0, btn_y, btn_w, btn_h)
    _cancel_rect = Rect2(_ok_rect.position.x - btn_w - 10.0, btn_y, btn_w, btn_h)

    var ok_hover := _ok_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _ok_rect, ok_hover, Color(0.4, 0.9, 0.55, 1.0))
    draw_string(font, Vector2(_ok_rect.position.x + 34.0, _ok_rect.position.y + 20.0),
        "OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 1, 0.95, 1) if ok_hover else Color(0.75, 0.95, 0.75, 1))

    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover, Color(0.9, 0.45, 0.4, 1.0))
    draw_string(font, Vector2(_cancel_rect.position.x + 17.0, _cancel_rect.position.y + 20.0),
        "CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))

    draw_string(font, box.position + Vector2(24, box.size.y - 12),
        "Transparent cells stay transparent. Any visible room gaps will reveal the authored parallax stack behind them.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)


func _refresh_backdrop_picker(row: Dictionary, selected_path: String) -> void:
    var picker: OptionButton = row.get("picker")
    if picker == null:
        return
    picker.clear()
    picker.add_item("Imported...")
    picker.set_item_disabled(0, true)
    var selected_idx: int = 0
    for rel_path_v in _available_backdrops:
        var rel_path: String = str(rel_path_v)
        picker.add_item(rel_path)
        var item_idx: int = picker.get_item_count() - 1
        picker.set_item_metadata(item_idx, rel_path)
        if rel_path == selected_path:
            selected_idx = item_idx
    picker.select(selected_idx)


func _on_backdrop_picked(idx: int, row_name: String) -> void:
    if idx <= 0:
        return
    for row_v in _parallax_rows:
        var row: Dictionary = row_v
        if str(row.get("name", "")) != row_name:
            continue
        var picker: OptionButton = row.get("picker")
        var path_edit: LineEdit = row.get("path_edit")
        if picker == null or path_edit == null:
            return
        path_edit.text = str(picker.get_item_metadata(idx))
        return


func _apply_parallax_speed_preset(preset_id: String) -> void:
    for preset_v in PARALLAX_SPEED_PRESETS:
        var preset: Dictionary = preset_v
        if str(preset.get("id", "")) != preset_id:
            continue
        var rows_v: Variant = preset.get("rows", [])
        if typeof(rows_v) != TYPE_ARRAY:
            return
        var rows: Array = rows_v
        for i in range(mini(rows.size(), _parallax_rows.size())):
            if typeof(rows[i]) != TYPE_DICTIONARY:
                continue
            var values: Dictionary = rows[i]
            var row: Dictionary = _parallax_rows[i]
            var sx_edit: LineEdit = row.get("sx_edit")
            var sy_edit: LineEdit = row.get("sy_edit")
            if sx_edit != null:
                sx_edit.text = "%.2f" % float(values.get("x", 1.0))
            if sy_edit != null:
                sy_edit.text = "%.2f" % float(values.get("y", 1.0))
        _error_text = ""
        queue_redraw()
        return
