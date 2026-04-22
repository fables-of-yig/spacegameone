extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo     = preload("res://Space/scripts/editor/ui/ui_io.gd")

# Full-screen 9-slice texture picker for the theme editor. Lists every
# PNG found under the active pack's Assets/UI folder + the global
# res://Assets/UI + res://Space/art/ui as a scrollable thumbnail grid.
# The currently-selected texture is highlighted. Clicking a thumb fires
# `picked(path)`; Esc / outside click fires `cancelled`.

signal picked(path: String)
signal cancelled

var editor: Node = null
var _pack_id: String = ""

const BOX_W: float = 760.0
const BOX_H: float = 560.0
const THUMB_W: float = 96.0
const THUMB_H: float = 96.0
const THUMB_GAP: float = 12.0

var _items: Array = []          # [{path, label, name}]
var _item_rects: Array = []     # parallel index → Rect2
var _texture_cache: Dictionary = {}
var _current_path: String = ""
var _scroll: float = 0.0
var _content_h: float = 0.0
var _cancel_rect: Rect2 = Rect2()
var _import_rect: Rect2 = Rect2()
var _file_dialog: FileDialog = null


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)
    _file_dialog = FileDialog.new()
    _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _file_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
    _enable_native_file_dialog(_file_dialog)
    _file_dialog.file_selected.connect(_on_file_selected)
    add_child(_file_dialog)


func _process(_delta):
    if visible:
        queue_redraw()


func open(pack_id: String, current_path: String = "") -> void:
    _pack_id = pack_id
    _current_path = current_path
    _scroll = 0.0
    _items = UIIo.list_available_textures(pack_id)
    _texture_cache.clear()
    visible = true
    queue_redraw()


func close() -> void:
    visible = false


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 48.0, max(0.0, _content_h - _grid_rect().size.y))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 48.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _cancel_rect.has_point(mb.position):
                _do_cancel()
                accept_event()
                return
            if _import_rect.has_point(mb.position):
                _open_import_dialog()
                accept_event()
                return
            for i in _item_rects.size():
                if (_item_rects[i] as Rect2).has_point(mb.position):
                    if i < _items.size():
                        _do_pick(str((_items[i] as Dictionary)["path"]))
                    accept_event()
                    return
            var box := _box_rect()
            if not box.has_point(mb.position):
                _do_cancel()
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _do_cancel()
            get_viewport().set_input_as_handled()


func _do_pick(path: String) -> void:
    visible = false
    picked.emit(path)


func _do_cancel() -> void:
    visible = false
    cancelled.emit()


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _grid_rect() -> Rect2:
    var box := _box_rect()
    return Rect2(box.position.x + 20, box.position.y + 70,
        box.size.x - 40, box.size.y - 130)


func _draw():
    if not visible:
        return

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.65)
    var box := _box_rect()
    UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, box.position + Vector2(24, 36),
        "Pick texture", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    var hint := "%d available  —  Esc to cancel" % _items.size()
    draw_string(font, box.position + Vector2(24, 56),
        hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

    var grid := _grid_rect()
    draw_rect(grid, Color(0.04, 0.06, 0.04, 0.85))

    _item_rects.clear()
    var cols: int = max(1, int((grid.size.x + THUMB_GAP) / (THUMB_W + THUMB_GAP)))
    var col_w: float = THUMB_W
    var col_h: float = THUMB_H + 28.0
    var row_h: float = col_h + THUMB_GAP

    for i in _items.size():
        var item: Dictionary = _items[i]
        var col_i: int = i % cols
        var row_i: int = i / cols
        var x: float = grid.position.x + 4 + float(col_i) * (col_w + THUMB_GAP)
        var y: float = grid.position.y + 8 + float(row_i) * row_h - _scroll
        var thumb_rect := Rect2(x, y, col_w, col_h)
        _item_rects.append(thumb_rect)

        if y + col_h < grid.position.y or y > grid.position.y + grid.size.y:
            continue

        var hover := thumb_rect.has_point(mouse_pos)
        var is_sel := str(item["path"]) == _current_path
        var bg: Color
        if is_sel:
            bg = Color(0.3, 0.55, 0.42, 0.95)
        elif hover:
            bg = Color(0.18, 0.3, 0.22, 0.85)
        else:
            bg = Color(0.08, 0.16, 0.1, 0.85)
        draw_rect(thumb_rect, bg)
        draw_rect(thumb_rect, Color(0.4, 0.7, 0.5, 0.85), false, 1.0)

        var tex := _get_texture(str(item["path"]))
        if tex != null:
            var tex_size: Vector2 = tex.get_size()
            var fit_w: float = min(THUMB_W - 12.0, tex_size.x * 2.0)
            var fit_h: float = min(THUMB_H - 12.0, tex_size.y * 2.0)
            if tex_size.x > 0 and tex_size.y > 0:
                var fit_scale := minf((THUMB_W - 12.0) / tex_size.x,
                    (THUMB_H - 12.0) / tex_size.y)
                fit_w = tex_size.x * fit_scale
                fit_h = tex_size.y * fit_scale
            var tex_rect := Rect2(
                thumb_rect.position + Vector2((col_w - fit_w) * 0.5, 6),
                Vector2(fit_w, fit_h))
            draw_texture_rect(tex, tex_rect, false)
        else:
            draw_string(font, thumb_rect.position + Vector2(8, 50),
                "(load fail)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(0.85, 0.4, 0.4, 1))

        var name := str(item["name"])
        if name.length() > 14:
            name = name.substr(0, 12) + "…"
        draw_string(font, thumb_rect.position + Vector2(6, THUMB_H + 14),
            name, HORIZONTAL_ALIGNMENT_LEFT, int(col_w - 12), 10,
            Color(0.85, 0.98, 0.92, 1))
        if hover:
            EditorTooltip.show_text("Texture \"%s\". Click to assign it to the field that opened this picker. Path: %s" % [str(item["name"]), str(item["path"])])

    var rows_count: int = int(ceil(float(_items.size()) / float(max(1, cols))))
    _content_h = float(rows_count) * row_h + 16.0

    if _items.is_empty():
        draw_string(font, grid.position + Vector2(20, 30),
            "No PNGs found in pack/global UI folders.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 0.75, 1))

    var btn_w: float = 110.0
    var btn_h: float = 32.0
    _cancel_rect = Rect2(box.position.x + box.size.x - btn_w - 20,
        box.position.y + box.size.y - btn_h - 16, btn_w, btn_h)
    _import_rect = Rect2(_cancel_rect.position.x - btn_w - 10.0,
        _cancel_rect.position.y, btn_w, btn_h)
    var import_hover := _import_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _import_rect, import_hover,
        Color(0.38, 0.72, 0.48, 1.0))
    draw_string(font, Vector2(_import_rect.position.x + 24.0, _import_rect.position.y + 21.0),
        "IMPORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(0.95, 1.0, 0.95, 1.0) if import_hover else Color(0.86, 0.98, 0.9, 1.0))
    if import_hover:
        EditorTooltip.show_text("Import a PNG into this pack's Assets/UI folder, then assign it.")
    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover,
        Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 21),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Close the picker without changing the texture. Esc or clicking outside the box does the same thing.")


func _get_texture(path: String) -> Texture2D:
    if _texture_cache.has(path):
        return _texture_cache[path]
    var tex := UIIo.load_texture(path)
    _texture_cache[path] = tex
    return tex


func _open_import_dialog() -> void:
    if _file_dialog == null or _pack_id.is_empty():
        return
    _file_dialog.popup_centered_ratio(0.8)


func _on_file_selected(path: String) -> void:
    var imported := UIIo.import_texture_to_pack(_pack_id, path)
    if imported.is_empty():
        return
    open(_pack_id, imported)


func _enable_native_file_dialog(dialog: FileDialog) -> void:
    for prop_v in dialog.get_property_list():
        if typeof(prop_v) != TYPE_DICTIONARY:
            continue
        var prop: Dictionary = prop_v
        if str(prop.get("name", "")) == "use_native_dialog":
            dialog.set("use_native_dialog", true)
            return
