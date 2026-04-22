extends Control

# Shop editor. Authors user://Packs/<pack>/Shops/<shop_id>.json — the
# buyable-stock lists that MvShopUI.open_shop(shop_id) reads.
#
# Left: shop file list + Back/Save/+New buttons. Right: stock item list
# + per-item fields (id, name, price, count). Item ids are expected to
# resolve against the pack's Items registry; that cross-reference is
# validated by ContentValidator, not here.

const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")

signal status_changed(text: String)
signal closed

var _pack_id: String = ""
var _shop_ids: Array = []
var _current_id: String = ""
var _items: Array = []
var _selected_item: int = -1
var _dirty: bool = false
var _suppress: bool = false
var _known_item_ids: Dictionary = {}  # id string -> true

var _undo: RefCounted = null

var _file_list: ItemList = null
var _item_list: ItemList = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _price_edit: LineEdit = null
var _count_edit: LineEdit = null
var _validation_label: Label = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null


func request_close() -> void:
    visible = false
    closed.emit()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    _refresh_known_item_ids()
    _load_file_list()


func _refresh_known_item_ids() -> void:
    _known_item_ids.clear()
    var data: Dictionary = PedIO.load_items(_pack_id)
    var items_v: Variant = data.get("items", [])
    if typeof(items_v) != TYPE_ARRAY:
        return
    for entry_v in items_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var id_str: String = str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not id_str.is_empty():
            _known_item_ids[id_str] = true


func open_editor(pack_id: String) -> void:
    open(pack_id)
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func save() -> bool:
    if not _flush_item():
        return false
    if _current_id.is_empty():
        return false
    if PedIO.save_shop(_pack_id, _current_id, { "id": _current_id, "items": _items }):
        _dirty = false
        status_changed.emit("Shop '%s' saved" % _current_id)
        return true
    else:
        status_changed.emit("Shop '%s' failed validation; save aborted" % _current_id)
        return false


func is_dirty() -> bool:
    return _dirty


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_ui()


func _capture_state() -> Dictionary:
    return {
        "items": _items.duplicate(true),
        "selected_item": _selected_item,
        "dirty": _dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var items_v: Variant = snap.get("items", null)
    if typeof(items_v) == TYPE_ARRAY:
        _items = items_v
    _selected_item = int(snap.get("selected_item", -1))
    _dirty = bool(snap.get("dirty", false))
    _rebuild_item_list()


func _build_ui() -> void:
    var split := HSplitContainer.new()
    split.anchor_right = 1.0
    split.anchor_bottom = 1.0
    split.split_offset = 200
    add_child(split)

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
    new_btn.pressed.connect(_on_new_shop)
    file_btns.add_child(new_btn)

    var tooltip_toggle := CheckButton.new()
    tooltip_toggle.text = "Tooltips"
    tooltip_toggle.button_pressed = EditorTooltip.enabled
    tooltip_toggle.toggled.connect(func(on: bool): EditorTooltip.set_enabled(on))
    tooltip_toggle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
    tooltip_toggle.add_theme_font_size_override("font_size", 11)
    file_btns.add_child(tooltip_toggle)

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

    var right_split := HSplitContainer.new()
    right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.split_offset = 220
    split.add_child(right_split)

    var mid := VBoxContainer.new()
    mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.add_child(mid)

    var item_btns := HBoxContainer.new()
    mid.add_child(item_btns)
    var add_btn := Button.new()
    add_btn.text = "+ Item"
    add_btn.pressed.connect(_on_add_item)
    item_btns.add_child(add_btn)
    var del_btn := Button.new()
    del_btn.text = "Delete"
    del_btn.pressed.connect(_on_delete_item)
    item_btns.add_child(del_btn)

    _item_list = ItemList.new()
    _item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _item_list.item_selected.connect(_on_item_select)
    mid.add_child(_item_list)

    var detail_scroll := ScrollContainer.new()
    detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.add_child(detail_scroll)

    var detail := VBoxContainer.new()
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_scroll.add_child(detail)

    _add_label(detail, "Item ID (must match an Items registry entry)")
    _id_edit = LineEdit.new()
    _id_edit.text_changed.connect(func(_t): _mark_dirty())
    detail.add_child(_id_edit)

    _add_label(detail, "Display Name (optional override)")
    _name_edit = LineEdit.new()
    _name_edit.text_changed.connect(func(_t): _mark_dirty())
    detail.add_child(_name_edit)

    _add_label(detail, "Price (gold)")
    _price_edit = LineEdit.new()
    _price_edit.text_changed.connect(func(_t): _mark_dirty())
    _price_edit.text_changed.connect(func(_t): _refresh_validation())
    detail.add_child(_price_edit)

    _add_label(detail, "Count per purchase")
    _count_edit = LineEdit.new()
    _count_edit.text_changed.connect(func(_t): _mark_dirty())
    _count_edit.text_changed.connect(func(_t): _refresh_validation())
    detail.add_child(_count_edit)

    _validation_label = Label.new()
    _validation_label.add_theme_font_size_override("font_size", 11)
    _validation_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
    _validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _validation_label.custom_minimum_size = Vector2(0, 40)
    detail.add_child(_validation_label)
    _id_edit.text_changed.connect(func(_t): _refresh_validation())


func _add_label(parent: VBoxContainer, text: String) -> void:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 11)
    parent.add_child(lbl)


func _load_file_list() -> void:
    _shop_ids = PedIO.list_shops(_pack_id)
    _file_list.clear()
    for id in _shop_ids:
        _file_list.add_item(id)


func _on_file_select(idx: int) -> void:
    if _dirty:
        if not save():
            if _file_list != null:
                var current_idx := _shop_ids.find(_current_id)
                if current_idx >= 0:
                    _file_list.select(current_idx)
            return
    _current_id = _shop_ids[idx]
    var data := PedIO.load_shop(_pack_id, _current_id)
    var raw: Variant = data.get("items", [])
    _items = raw if typeof(raw) == TYPE_ARRAY else []
    _selected_item = -1
    _rebuild_item_list()
    _dirty = false
    if _undo != null:
        _undo.clear()


func _rebuild_item_list() -> void:
    _item_list.clear()
    var seen_ids: Dictionary = {}
    for i in _items.size():
        var item: Dictionary = _items[i]
        var id_str: String = str(item.get("id", "")).strip_edges()
        var preview: String = "%s — %d gold" % [
            id_str if not id_str.is_empty() else "(no id)",
            int(item.get("price", 0)),
        ]
        var warn := ""
        if id_str.is_empty():
            warn = "  [!] empty id"
        elif not _known_item_ids.has(id_str):
            warn = "  [!] unknown item id"
        elif seen_ids.has(id_str):
            warn = "  [!] duplicate id"
        seen_ids[id_str] = true
        _item_list.add_item(preview + warn)
        if not warn.is_empty():
            _item_list.set_item_custom_fg_color(i, Color(1.0, 0.55, 0.35))
    if _selected_item >= 0 and _selected_item < _items.size():
        _item_list.select(_selected_item)
        _show_item_detail(_selected_item)
    _refresh_validation()


func _on_item_select(idx: int) -> void:
    if not _flush_item():
        if _item_list != null and _selected_item >= 0 and _selected_item < _items.size():
            _item_list.select(_selected_item)
        return
    _selected_item = idx
    _show_item_detail(idx)


func _show_item_detail(idx: int) -> void:
    if idx < 0 or idx >= _items.size():
        return
    _suppress = true
    var item: Dictionary = _items[idx]
    _id_edit.text = str(item.get("id", ""))
    _name_edit.text = str(item.get("name", ""))
    _price_edit.text = str(int(item.get("price", 0)))
    _count_edit.text = str(int(item.get("count", 1)))
    _suppress = false
    _refresh_validation()


func _refresh_validation() -> void:
    if _validation_label == null:
        return
    var id_str: String = _id_edit.text.strip_edges() if _id_edit != null else ""
    var msgs: Array = []
    if id_str.is_empty():
        msgs.append("Item id is empty.")
    elif not _known_item_ids.has(id_str):
        msgs.append("'%s' is not in this pack's Items registry — open the Items editor to add it." % id_str)
    var dup_count := 0
    for i in _items.size():
        if i == _selected_item:
            continue
        if str((_items[i] as Dictionary).get("id", "")).strip_edges() == id_str and not id_str.is_empty():
            dup_count += 1
    if dup_count > 0:
        msgs.append("Duplicate id — %d other stock row(s) share this id." % dup_count)
    if _price_edit != null and not _is_valid_int_string(_price_edit.text):
        msgs.append("Price must be a whole number.")
    if _count_edit != null and not _is_valid_int_string(_count_edit.text):
        msgs.append("Count must be a whole number.")
    _validation_label.text = "  ".join(msgs)


func _flush_item() -> bool:
    if _selected_item < 0 or _selected_item >= _items.size():
        return true
    if not _is_valid_int_string(_price_edit.text):
        var bad_price := _price_edit.text.strip_edges()
        _validation_label.text = "Price must be a whole number, got '%s'." % bad_price
        status_changed.emit("Shop item price is invalid; fix it before saving or switching rows")
        return false
    if not _is_valid_int_string(_count_edit.text):
        var bad_count := _count_edit.text.strip_edges()
        _validation_label.text = "Count must be a whole number, got '%s'." % bad_count
        status_changed.emit("Shop item count is invalid; fix it before saving or switching rows")
        return false
    var item: Dictionary = _items[_selected_item]
    item["id"] = _id_edit.text.strip_edges()
    var name_val := _name_edit.text.strip_edges()
    if name_val.is_empty():
        item.erase("name")
    else:
        item["name"] = name_val
    item["price"] = max(0, int(_price_edit.text))
    item["count"] = max(1, int(_count_edit.text))
    _rebuild_item_list()
    return true


func _on_add_item() -> void:
    if not _flush_item():
        return
    if _undo != null:
        _undo.begin()
    _items.append({"id": "", "price": 0, "count": 1})
    _selected_item = _items.size() - 1
    _rebuild_item_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("add shop item")


func _on_delete_item() -> void:
    if _selected_item < 0 or _selected_item >= _items.size():
        return
    if _undo != null:
        _undo.begin()
    _items.remove_at(_selected_item)
    _selected_item = mini(_selected_item, _items.size() - 1)
    _rebuild_item_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("delete shop item")


func _on_new_shop() -> void:
    var new_id := "new_shop_%d" % _shop_ids.size()
    if PedIO.save_shop(_pack_id, new_id, { "id": new_id, "items": [] }):
        _load_file_list()
        status_changed.emit("Created shop '%s'" % new_id)
    else:
        status_changed.emit("Could not create shop '%s'" % new_id)


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
    var tut: Dictionary = EditorTutorial.get_tutorial("shop")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


func _is_valid_int_string(text: String) -> bool:
    var trimmed := text.strip_edges()
    if trimmed.is_empty():
        return false
    var start := 0
    if trimmed.begins_with("-"):
        if trimmed.length() == 1:
            return false
        start = 1
    for i in range(start, trimmed.length()):
        var ch := trimmed.unicode_at(i)
        if ch < 48 or ch > 57:
            return false
    return true
