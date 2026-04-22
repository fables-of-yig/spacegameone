extends Control

const PedIO = preload("res://Space/scripts/editor/ped/ped_io.gd")
const PedUtil = preload("res://Space/scripts/editor/ped/ped_util.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")

# Player editor — Items tab. List + detail editor for items.json. Items are
# referenced by id from pickups, shops, and trigger actions. Each entry has
# id, display name, description, max_stack, price, category, and optional
# machine-readable use-effect fields.

var pack_id: String = ""
var dirty: bool = false

var _items: Array = []          # Array[Dictionary] — the full list
var _selected_idx: int = -1

# Left column widgets
var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null

# Detail panel widgets
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _stack_edit: LineEdit = null
var _price_edit: LineEdit = null
var _category_edit: LineEdit = null
var _use_effect_edit: LineEdit = null
var _use_amount_edit: LineEdit = null
var _use_arg_edit: LineEdit = null

# Sprite
var _sprite_header: Label = null
var _sheet_edit: LineEdit = null
var _fw_edit: LineEdit = null
var _fh_edit: LineEdit = null
var _findex_edit: LineEdit = null
var _label_sheet: Label = null
var _label_fw: Label = null
var _label_fh: Label = null
var _label_findex: Label = null
var _sprite_preview: Control = null

# Headers/labels
var _list_header: Label = null
var _detail_header: Label = null
var _label_id: Label = null
var _label_name: Label = null
var _label_desc: Label = null
var _label_stack: Label = null
var _label_price: Label = null
var _label_category: Label = null
var _label_use_effect: Label = null
var _label_use_amount: Label = null
var _label_use_arg: Label = null

# Suppress field-change handlers while we programmatically set widget text
# on selection changes, so _on_field_edited doesn't wipe out the data we
# just wrote in.
var _suppress_events: bool = false

var _undo: RefCounted = null

const LEFT_W: float = 220.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "items": _items.duplicate(true),
        "selected_idx": _selected_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var i_v: Variant = snap.get("items", null)
    if typeof(i_v) == TYPE_ARRAY:
        _items = i_v
    _selected_idx = int(snap.get("selected_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_list()
    if _selected_idx >= 0 and _selected_idx < _items.size() and _list != null:
        _list.select(_selected_idx)
    _apply_to_inputs()


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _has_text_focus():
            return
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()


func _has_text_focus() -> bool:
    var focused := get_viewport().gui_get_focus_owner()
    if focused == null:
        return false
    return focused is LineEdit or focused is TextEdit


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _process(_delta: float) -> void:
    if not is_visible_in_tree():
        return
    _update_tooltips()


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    if _stack_edit != null and Rect2(_stack_edit.position, _stack_edit.size).has_point(mp):
        EditorTooltip.show_text("Maximum number of this item the player can carry in one inventory slot. 1 = unique, higher = stackable consumable.")
    elif _price_edit != null and Rect2(_price_edit.position, _price_edit.size).has_point(mp):
        EditorTooltip.show_text("Base shop price. The shopkeep multiplier scales this at runtime. 0 = not purchasable.")
    elif _category_edit != null and Rect2(_category_edit.position, _category_edit.size).has_point(mp):
        EditorTooltip.show_text("Category for inventory sorting and shop filtering: currency, consumable, key, upgrade, material, or quest.")
    elif _use_effect_edit != null and Rect2(_use_effect_edit.position, _use_effect_edit.size).has_point(mp):
        EditorTooltip.show_text("Machine-readable effect applied by the Use action. Leave blank for non-usable items.")
    elif _use_amount_edit != null and Rect2(_use_amount_edit.position, _use_amount_edit.size).has_point(mp):
        EditorTooltip.show_text("Numeric strength of the use effect. Examples: HP restored, max HP gained, or var delta.")
    elif _use_arg_edit != null and Rect2(_use_arg_edit.position, _use_arg_edit.size).has_point(mp):
        EditorTooltip.show_text("Optional string payload for the use effect, such as an ability id, game var key, or weapon name.")
    elif _desc_edit != null and Rect2(_desc_edit.position, _desc_edit.size).has_point(mp):
        EditorTooltip.show_text("In-game description shown when the player inspects this item in the inventory or shop.")


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_data()
    _populate_list()
    if _items.size() > 0:
        _list.select(0)
        _on_list_selected(0)
    else:
        _apply_to_inputs()
    if _undo != null:
        _undo.clear()


func save() -> bool:
    var out := {"items": _items.duplicate(true)}
    if not PedIO.save_items(pack_id, out):
        return false
    dirty = false
    return true


func is_dirty() -> bool:
    return dirty


# ─── Layout ──────────────────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.09, 0.1, 0.13, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _list_header = Label.new()
    _list_header.text = "ITEMS"
    _list_header.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
    add_child(_list_header)

    _list = ItemList.new()
    _list.item_selected.connect(_on_list_selected)
    add_child(_list)

    _add_btn = Button.new()
    _add_btn.text = "+ ITEM"
    _add_btn.pressed.connect(_on_add_pressed)
    add_child(_add_btn)

    _del_btn = Button.new()
    _del_btn.text = "- ITEM"
    _del_btn.pressed.connect(_on_del_pressed)
    add_child(_del_btn)

    _detail_header = Label.new()
    _detail_header.text = "DETAIL"
    _detail_header.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
    add_child(_detail_header)

    _label_id = _make_label("ID")
    _id_edit = LineEdit.new()
    _id_edit.text_changed.connect(func(t): _on_field_edited("id", t))
    add_child(_id_edit)

    _label_name = _make_label("Name")
    _name_edit = LineEdit.new()
    _name_edit.text_changed.connect(func(t): _on_field_edited("name", t))
    add_child(_name_edit)

    _label_desc = _make_label("Description")
    _desc_edit = TextEdit.new()
    _desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _desc_edit.text_changed.connect(_on_desc_changed)
    add_child(_desc_edit)

    _label_stack = _make_label("Max stack")
    _stack_edit = LineEdit.new()
    _stack_edit.text_changed.connect(func(t): _on_field_edited("max_stack", t))
    add_child(_stack_edit)

    _label_price = _make_label("Price")
    _price_edit = LineEdit.new()
    _price_edit.text_changed.connect(func(t): _on_field_edited("price", t))
    add_child(_price_edit)

    _label_category = _make_label("Category")
    _category_edit = LineEdit.new()
    _category_edit.placeholder_text = "currency|consumable|key|upgrade|material|quest"
    _category_edit.text_changed.connect(func(t): _on_field_edited("category", t))
    add_child(_category_edit)

    _label_use_effect = _make_label("Use effect")
    _use_effect_edit = LineEdit.new()
    _use_effect_edit.placeholder_text = "heal_hp|max_hp_up|grant_ability|add_var|set_weapon"
    _use_effect_edit.text_changed.connect(func(t): _on_field_edited("use_effect", t))
    add_child(_use_effect_edit)

    _label_use_amount = _make_label("Use amount")
    _use_amount_edit = LineEdit.new()
    _use_amount_edit.text_changed.connect(func(t): _on_field_edited("use_amount", t))
    add_child(_use_amount_edit)

    _label_use_arg = _make_label("Use arg")
    _use_arg_edit = LineEdit.new()
    _use_arg_edit.placeholder_text = "ability id, game var key, or weapon name"
    _use_arg_edit.text_changed.connect(func(t): _on_field_edited("use_arg", t))
    add_child(_use_arg_edit)

    _sprite_header = Label.new()
    _sprite_header.text = "SPRITE (inventory icon)"
    _sprite_header.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
    add_child(_sprite_header)

    _label_sheet = _make_label("Sheet")
    _sheet_edit = LineEdit.new()
    _sheet_edit.placeholder_text = "items_sheet.png"
    _sheet_edit.text_changed.connect(func(t): _on_sprite_field_edited("sprite_sheet", "str", t))
    add_child(_sheet_edit)

    _label_fw = _make_label("Frame W")
    _fw_edit = LineEdit.new()
    _fw_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_width", "int", t))
    add_child(_fw_edit)

    _label_fh = _make_label("Frame H")
    _fh_edit = LineEdit.new()
    _fh_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_height", "int", t))
    add_child(_fh_edit)

    _label_findex = _make_label("Frame index")
    _findex_edit = LineEdit.new()
    _findex_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_index", "int", t))
    add_child(_findex_edit)

    _sprite_preview = Control.new()
    _sprite_preview.set_script(preload("res://Space/scripts/editor/ped/ped_sprite_preview.gd"))
    add_child(_sprite_preview)

    _layout_children()


func _make_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
    add_child(l)
    return l


func _layout_children() -> void:
    if _list == null:
        return
    var vw := size.x
    var vh := size.y

    # Left column
    _list_header.position = Vector2(12, 12)
    _list_header.size = Vector2(LEFT_W - 24, 20)
    _list.position = Vector2(12, 40)
    _list.size = Vector2(LEFT_W - 24, vh - 40 - 48)
    _add_btn.position = Vector2(12, vh - 40)
    _add_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)
    _del_btn.position = Vector2(12 + (LEFT_W - 32) * 0.5 + 8, vh - 40)
    _del_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)

    # Detail panel right of the list
    var right_x: float = LEFT_W + 8
    var right_w: float = vw - right_x - 12
    var label_w: float = 110.0
    var field_x: float = right_x + label_w
    var field_w: float = right_w - label_w - 8
    var row_y: float = 12.0
    var row_h: float = 30.0
    var field_h: float = 24.0

    _detail_header.position = Vector2(right_x, row_y)
    _detail_header.size = Vector2(right_w, 20)
    row_y += 32.0

    _label_id.position = Vector2(right_x, row_y + 3)
    _label_id.size = Vector2(label_w, row_h)
    _id_edit.position = Vector2(field_x, row_y)
    _id_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_name.position = Vector2(right_x, row_y + 3)
    _label_name.size = Vector2(label_w, row_h)
    _name_edit.position = Vector2(field_x, row_y)
    _name_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_desc.position = Vector2(right_x, row_y + 3)
    _label_desc.size = Vector2(label_w, row_h)
    _desc_edit.position = Vector2(field_x, row_y)
    _desc_edit.size = Vector2(field_w, 80)
    row_y += 88

    _label_stack.position = Vector2(right_x, row_y + 3)
    _label_stack.size = Vector2(label_w, row_h)
    _stack_edit.position = Vector2(field_x, row_y)
    _stack_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_price.position = Vector2(right_x, row_y + 3)
    _label_price.size = Vector2(label_w, row_h)
    _price_edit.position = Vector2(field_x, row_y)
    _price_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_category.position = Vector2(right_x, row_y + 3)
    _label_category.size = Vector2(label_w, row_h)
    _category_edit.position = Vector2(field_x, row_y)
    _category_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_use_effect.position = Vector2(right_x, row_y + 3)
    _label_use_effect.size = Vector2(label_w, row_h)
    _use_effect_edit.position = Vector2(field_x, row_y)
    _use_effect_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_use_amount.position = Vector2(right_x, row_y + 3)
    _label_use_amount.size = Vector2(label_w, row_h)
    _use_amount_edit.position = Vector2(field_x, row_y)
    _use_amount_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_use_arg.position = Vector2(right_x, row_y + 3)
    _label_use_arg.size = Vector2(label_w, row_h)
    _use_arg_edit.position = Vector2(field_x, row_y)
    _use_arg_edit.size = Vector2(field_w, field_h)
    row_y += row_h + 10

    # Sprite section
    _sprite_header.position = Vector2(right_x, row_y)
    _sprite_header.size = Vector2(right_w, 20)
    row_y += 24

    _label_sheet.position = Vector2(right_x, row_y + 3)
    _label_sheet.size = Vector2(label_w, row_h)
    _sheet_edit.position = Vector2(field_x, row_y)
    _sheet_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_fw.position = Vector2(right_x, row_y + 3)
    _label_fw.size = Vector2(label_w, row_h)
    _fw_edit.position = Vector2(field_x, row_y)
    _fw_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_fh.position = Vector2(right_x, row_y + 3)
    _label_fh.size = Vector2(label_w, row_h)
    _fh_edit.position = Vector2(field_x, row_y)
    _fh_edit.size = Vector2(field_w, field_h)
    row_y += row_h

    _label_findex.position = Vector2(right_x, row_y + 3)
    _label_findex.size = Vector2(label_w, row_h)
    _findex_edit.position = Vector2(field_x, row_y)
    _findex_edit.size = Vector2(field_w, field_h)
    row_y += row_h + 4

    if _sprite_preview != null:
        var preview_h: float = minf(110.0, vh - row_y - 12)
        if preview_h < 40.0:
            preview_h = 40.0
        _sprite_preview.position = Vector2(right_x, row_y)
        _sprite_preview.size = Vector2(right_w, preview_h)


# ─── Data ────────────────────────────────────────────────────────────────

func _load_data() -> void:
    var data := PedIO.load_items(pack_id)
    var raw = data.get("items", [])
    _items.clear()
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                _items.append(_normalize_item(entry))
    _selected_idx = -1
    dirty = false


static func _normalize_item(src: Dictionary) -> Dictionary:
    return {
        "id":           str(src.get("id", "")),
        "name":         str(src.get("name", "")),
        "description":  str(src.get("description", "")),
        "max_stack":    int(src.get("max_stack", 1)),
        "price":        int(src.get("price", 0)),
        "category":     str(src.get("category", "")),
        "use_effect":   str(src.get("use_effect", "")),
        "use_amount":   int(src.get("use_amount", 0)),
        "use_arg":      str(src.get("use_arg", "")),
        "sprite_sheet": str(src.get("sprite_sheet", "")),
        "frame_width":  int(src.get("frame_width", 16)),
        "frame_height": int(src.get("frame_height", 16)),
        "frame_index":  int(src.get("frame_index", 0)),
    }


func _populate_list() -> void:
    _list.clear()
    for item in _items:
        var label: String = "%s — %s" % [item.get("id", "?"), item.get("name", "?")]
        _list.add_item(label)


func _on_list_selected(idx: int) -> void:
    if idx < 0 or idx >= _items.size():
        _selected_idx = -1
        _apply_to_inputs()
        return
    _selected_idx = idx
    _apply_to_inputs()


func _on_add_pressed() -> void:
    if _undo != null: _undo.begin()
    var new_id := "item_%d" % (_items.size() + 1)
    while _id_taken(new_id):
        new_id += "_"
    var new_item := {
        "id": new_id,
        "name": "New Item",
        "description": "",
        "max_stack": 1,
        "price": 0,
        "category": "",
        "use_effect": "",
        "use_amount": 0,
        "use_arg": "",
        "sprite_sheet": "",
        "frame_width": 16,
        "frame_height": 16,
        "frame_index": 0,
    }
    _items.append(new_item)
    dirty = true
    _populate_list()
    var new_idx := _items.size() - 1
    _list.select(new_idx)
    _on_list_selected(new_idx)
    if _undo != null: _undo.commit("add item")


func _id_taken(id: String) -> bool:
    for item in _items:
        if str(item.get("id", "")) == id:
            return true
    return false


func _on_del_pressed() -> void:
    if _selected_idx < 0 or _selected_idx >= _items.size():
        return
    if _undo != null: _undo.begin()
    _items.remove_at(_selected_idx)
    dirty = true
    _populate_list()
    if _items.is_empty():
        _selected_idx = -1
        _apply_to_inputs()
        if _undo != null: _undo.commit("delete item")
        return
    var next_idx: int = mini(_selected_idx, _items.size() - 1)
    _list.select(next_idx)
    _on_list_selected(next_idx)
    if _undo != null: _undo.commit("delete item")


func _apply_to_inputs() -> void:
    if _id_edit == null:
        return
    _suppress_events = true
    var have: bool = _selected_idx >= 0 and _selected_idx < _items.size()
    _id_edit.editable = have
    _name_edit.editable = have
    _desc_edit.editable = have
    _stack_edit.editable = have
    _price_edit.editable = have
    _category_edit.editable = have
    _use_effect_edit.editable = have
    _use_amount_edit.editable = have
    _use_arg_edit.editable = have
    _sheet_edit.editable = have
    _fw_edit.editable = have
    _fh_edit.editable = have
    _findex_edit.editable = have

    if not have:
        _id_edit.text = ""
        _name_edit.text = ""
        _desc_edit.text = ""
        _stack_edit.text = ""
        _price_edit.text = ""
        _category_edit.text = ""
        _use_effect_edit.text = ""
        _use_amount_edit.text = ""
        _use_arg_edit.text = ""
        _sheet_edit.text = ""
        _fw_edit.text = ""
        _fh_edit.text = ""
        _findex_edit.text = ""
        _suppress_events = false
        return

    var item: Dictionary = _items[_selected_idx]
    _id_edit.text = str(item.get("id", ""))
    _name_edit.text = str(item.get("name", ""))
    _desc_edit.text = str(item.get("description", ""))
    _stack_edit.text = str(int(item.get("max_stack", 1)))
    _price_edit.text = str(int(item.get("price", 0)))
    _category_edit.text = str(item.get("category", ""))
    _use_effect_edit.text = str(item.get("use_effect", ""))
    _use_amount_edit.text = str(int(item.get("use_amount", 0)))
    _use_arg_edit.text = str(item.get("use_arg", ""))
    _sheet_edit.text = str(item.get("sprite_sheet", ""))
    _fw_edit.text = str(int(item.get("frame_width", 16)))
    _fh_edit.text = str(int(item.get("frame_height", 16)))
    _findex_edit.text = str(int(item.get("frame_index", 0)))

    if _sprite_preview != null:
        _sprite_preview.pack_id = pack_id
        _sprite_preview.sheet_name = str(item.get("sprite_sheet", ""))
        _sprite_preview.frame_width = int(item.get("frame_width", 16))
        _sprite_preview.frame_height = int(item.get("frame_height", 16))
        _sprite_preview.frame_start = int(item.get("frame_index", 0))
        _sprite_preview.frame_count = 1
        _sprite_preview.frame_tick = 0
        _sprite_preview.reload_texture()
    _suppress_events = false


func _on_field_edited(field: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _items.size():
        return
    var item: Dictionary = _items[_selected_idx]
    if field == "max_stack" or field == "price" or field == "use_amount":
        item[field] = PedUtil.to_int(text, int(item.get(field, 0)))
    else:
        item[field] = text
    _items[_selected_idx] = item
    dirty = true
    if field == "id" or field == "name":
        _refresh_list_row(_selected_idx)


func _on_desc_changed() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _items.size():
        return
    var item: Dictionary = _items[_selected_idx]
    item["description"] = _desc_edit.text
    _items[_selected_idx] = item
    dirty = true


func _on_sprite_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _items.size():
        return
    var item: Dictionary = _items[_selected_idx]
    if kind == "int":
        item[field] = PedUtil.to_int(text, int(item.get(field, 0)))
    else:
        item[field] = text
    _items[_selected_idx] = item
    dirty = true

    if _sprite_preview != null:
        _sprite_preview.pack_id = pack_id
        _sprite_preview.sheet_name = str(item.get("sprite_sheet", ""))
        _sprite_preview.frame_width = maxi(1, int(item.get("frame_width", 16)))
        _sprite_preview.frame_height = maxi(1, int(item.get("frame_height", 16)))
        _sprite_preview.frame_start = int(item.get("frame_index", 0))
        _sprite_preview.frame_count = 1
        _sprite_preview.frame_tick = 0
        if field == "sprite_sheet":
            _sprite_preview.reload_texture()
        else:
            _sprite_preview._recalc_grid()


func _refresh_list_row(idx: int) -> void:
    if idx < 0 or idx >= _items.size():
        return
    var item: Dictionary = _items[idx]
    _list.set_item_text(idx, "%s — %s" % [item.get("id", "?"), item.get("name", "?")])
