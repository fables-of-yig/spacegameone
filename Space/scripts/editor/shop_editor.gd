extends Control

# Shop editor. Authors Content/<pack>/Shops/<shop_id>.json — the
# buyable-stock lists that MvShopUI.open_shop(shop_id) reads.
#
# Left: shop file list + Back/Save/+New buttons. Right: stock item list
# + per-item fields (id, name, price, count). Item ids are expected to
# resolve against the pack's Items registry; that cross-reference is
# validated by ContentValidator, not here.

const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const ContentReferenceIndex := preload("res://Space/scripts/editor/content_reference_index.gd")
const ContentReferenceRefactor := preload("res://Space/scripts/editor/content_reference_refactor.gd")

const ITEM_EFFECTS := [
    "",
    "heal_hp",
    "max_hp_up",
    "add_gold",
    "add_ammo",
    "max_ammo_up",
    "damage_up",
    "melee_damage_up",
    "projectile_damage_up",
    "inventory_slots_up",
    "grant_ability",
    "add_var",
    "set_flag",
    "add_tag",
    "fire_event",
    "set_weapon",
    "equip_item",
]
const EFFECTS_REQUIRING_ARG := [
    "grant_ability",
    "add_var",
    "set_flag",
    "add_tag",
    "fire_event",
    "set_weapon",
    "equip_item",
    "add_ammo",
    "max_ammo_up",
]


signal status_changed(text: String)
signal closed

var _pack_id: String = ""
var _shop_ids: Array = []
var _current_id: String = ""
var _items: Array = []
var _selected_item: int = -1
var _registry_items: Array = []
var _selected_registry_item: int = -1
var _dirty: bool = false
var _items_dirty: bool = false
var _suppress: bool = false
var _known_item_ids: Dictionary = {}  # id string -> true

var _undo: RefCounted = null

var _file_list: ItemList = null
var _item_list: ItemList = null
var _stock_id_edit: LineEdit = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _price_edit: LineEdit = null
var _count_edit: LineEdit = null
var _stock_effect: OptionButton = null
var _stock_amount_edit: LineEdit = null
var _stock_arg_edit: LineEdit = null
var _stock_auto_check: CheckBox = null
var _validation_label: Label = null
var _registry_list: ItemList = null
var _reg_id_edit: LineEdit = null
var _reg_name_edit: LineEdit = null
var _reg_desc_edit: TextEdit = null
var _reg_category: OptionButton = null
var _reg_stack_edit: LineEdit = null
var _reg_price_edit: LineEdit = null
var _reg_effect: OptionButton = null
var _reg_amount_edit: LineEdit = null
var _reg_arg_edit: LineEdit = null
var _reg_auto_check: CheckBox = null
var _reg_validation_label: Label = null
var _delete_registry_confirm: ConfirmationDialog = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null
var _pending_delete_registry_item_id: String = ""


func request_close() -> void:
    visible = false
    closed.emit()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    _load_registry_items()
    _load_file_list()


func _refresh_known_item_ids() -> void:
    _known_item_ids.clear()
    for entry_v in _registry_items:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var id_str: String = str((entry_v as Dictionary).get("id", "")).strip_edges()
        if not id_str.is_empty():
            _known_item_ids[id_str] = true


func _load_registry_items() -> void:
    var data: Dictionary = PedIO.load_items(_pack_id)
    var items_v: Variant = data.get("items", [])
    _registry_items = (items_v as Array).duplicate(true) if typeof(items_v) == TYPE_ARRAY else []
    _selected_registry_item = -1
    _refresh_known_item_ids()
    _rebuild_registry_list()


func open_editor(pack_id: String) -> void:
    open(pack_id)
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func save() -> bool:
    if not _flush_item():
        return false
    if not _flush_registry_item():
        return false
    if _items_dirty:
        if not PedIO.save_items(_pack_id, {"items": _registry_items}):
            status_changed.emit("Items registry failed validation; save aborted")
            return false
        _items_dirty = false
        _refresh_known_item_ids()
        _rebuild_item_list()
    if _current_id.is_empty():
        status_changed.emit("Items saved")
        return true
    if PedIO.save_shop(_pack_id, _current_id, { "id": _current_id, "items": _items }):
        _dirty = false
        status_changed.emit("Shop '%s' saved" % _current_id)
        return true
    else:
        status_changed.emit("Shop '%s' failed validation; save aborted" % _current_id)
        return false


func is_dirty() -> bool:
    return _dirty or _items_dirty


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_ui()
    _build_delete_registry_confirm()


func _build_delete_registry_confirm() -> void:
    _delete_registry_confirm = ConfirmationDialog.new()
    _delete_registry_confirm.title = "Delete Item"
    _delete_registry_confirm.confirmed.connect(_on_delete_registry_item_confirmed)
    add_child(_delete_registry_confirm)


func _capture_state() -> Dictionary:
    return {
        "items": _items.duplicate(true),
        "selected_item": _selected_item,
        "registry_items": _registry_items.duplicate(true),
        "selected_registry_item": _selected_registry_item,
        "dirty": _dirty,
        "items_dirty": _items_dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var items_v: Variant = snap.get("items", null)
    if typeof(items_v) == TYPE_ARRAY:
        _items = items_v
    var registry_v: Variant = snap.get("registry_items", null)
    if typeof(registry_v) == TYPE_ARRAY:
        _registry_items = registry_v
    _selected_item = int(snap.get("selected_item", -1))
    _selected_registry_item = int(snap.get("selected_registry_item", -1))
    _dirty = bool(snap.get("dirty", false))
    _items_dirty = bool(snap.get("items_dirty", false))
    _refresh_known_item_ids()
    _rebuild_item_list()
    _rebuild_registry_list()


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
    add_btn.text = "+ Offer"
    add_btn.pressed.connect(_on_add_item)
    item_btns.add_child(add_btn)
    var del_btn := Button.new()
    del_btn.text = "Remove Offer"
    del_btn.pressed.connect(_on_delete_item)
    item_btns.add_child(del_btn)

    _item_list = ItemList.new()
    _item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _item_list.item_selected.connect(_on_item_select)
    mid.add_child(_item_list)

    var registry := VBoxContainer.new()
    registry.custom_minimum_size.x = 310.0
    right_split.add_child(registry)

    var reg_header := Label.new()
    reg_header.text = "Global Item Registry"
    reg_header.add_theme_font_size_override("font_size", 14)
    registry.add_child(reg_header)

    var template_row := HBoxContainer.new()
    registry.add_child(template_row)
    for template in [
        ["Health", "health"],
        ["Money", "money"],
        ["Ammo", "ammo"],
        ["Max Ammo Up", "max_ammo_up"],
        ["HP Up", "hp_up"],
        ["Damage Up", "damage_up"],
        ["Inventory Up", "inventory_up"],
        ["Ability", "ability"],
        ["Tag", "tag"],
        ["Event", "event"],
    ]:
        var tb := Button.new()
        tb.text = str(template[0])
        tb.pressed.connect(_on_add_registry_template.bind(str(template[1])))
        template_row.add_child(tb)

    var reg_btns := HBoxContainer.new()
    registry.add_child(reg_btns)
    var add_reg_btn := Button.new()
    add_reg_btn.text = "+ Blank"
    add_reg_btn.pressed.connect(_on_add_registry_item)
    reg_btns.add_child(add_reg_btn)
    var del_reg_btn := Button.new()
    del_reg_btn.text = "Delete"
    del_reg_btn.pressed.connect(_on_delete_registry_item)
    reg_btns.add_child(del_reg_btn)
    var add_to_stock_btn := Button.new()
    add_to_stock_btn.text = "Add Selected to Shop"
    add_to_stock_btn.pressed.connect(_on_add_selected_registry_to_shop)
    reg_btns.add_child(add_to_stock_btn)

    _registry_list = ItemList.new()
    _registry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _registry_list.item_selected.connect(_on_registry_select)
    registry.add_child(_registry_list)

    var detail_scroll := ScrollContainer.new()
    detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_split.add_child(detail_scroll)

    var detail := VBoxContainer.new()
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_scroll.add_child(detail)

    _add_label(detail, "Offer ID (unique in this shop)")
    _stock_id_edit = LineEdit.new()
    _stock_id_edit.placeholder_text = "missile_upgrade_1"
    _stock_id_edit.text_changed.connect(func(_t): _mark_dirty())
    _stock_id_edit.text_changed.connect(func(_t): _refresh_validation())
    detail.add_child(_stock_id_edit)

    _add_label(detail, "Base Item ID (from the Items registry)")
    _id_edit = LineEdit.new()
    _id_edit.text_changed.connect(func(_t): _mark_dirty())
    detail.add_child(_id_edit)

    _add_label(detail, "Offer Name (optional override)")
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

    _add_label(detail, "What this offer does instead")
    _stock_effect = OptionButton.new()
    _populate_effect_option(_stock_effect)
    _stock_effect.item_selected.connect(func(_idx):
        _mark_dirty()
        if _selected_effect_from(_stock_effect) != "" and _stock_auto_check != null:
            _stock_auto_check.button_pressed = true
        _refresh_validation()
    )
    detail.add_child(_stock_effect)

    _add_label(detail, "Effect amount")
    _stock_amount_edit = LineEdit.new()
    _stock_amount_edit.text_changed.connect(func(_t): _mark_dirty())
    _stock_amount_edit.text_changed.connect(func(_t): _refresh_validation())
    detail.add_child(_stock_amount_edit)

    _add_label(detail, "Effect target (ammo type, tag, event, variable, ability, or weapon)")
    _stock_arg_edit = LineEdit.new()
    _stock_arg_edit.text_changed.connect(func(_t): _mark_dirty())
    _stock_arg_edit.text_changed.connect(func(_t): _refresh_validation())
    detail.add_child(_stock_arg_edit)

    _stock_auto_check = CheckBox.new()
    _stock_auto_check.text = "Apply this offer's effect immediately when bought"
    _stock_auto_check.toggled.connect(func(_on): _mark_dirty())
    detail.add_child(_stock_auto_check)

    _validation_label = Label.new()
    _validation_label.add_theme_font_size_override("font_size", 11)
    _validation_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
    _validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _validation_label.custom_minimum_size = Vector2(0, 40)
    detail.add_child(_validation_label)
    _id_edit.text_changed.connect(func(_t): _refresh_validation())

    _add_label(detail, "Registry Item ID")
    _reg_id_edit = LineEdit.new()
    _reg_id_edit.text_changed.connect(func(_t): _mark_items_dirty())
    _reg_id_edit.text_changed.connect(func(_t): _refresh_registry_validation())
    detail.add_child(_reg_id_edit)

    _add_label(detail, "Registry Name")
    _reg_name_edit = LineEdit.new()
    _reg_name_edit.text_changed.connect(func(_t): _mark_items_dirty())
    detail.add_child(_reg_name_edit)

    _add_label(detail, "Registry Description")
    _reg_desc_edit = TextEdit.new()
    _reg_desc_edit.custom_minimum_size = Vector2(0, 70)
    _reg_desc_edit.text_changed.connect(func(): _mark_items_dirty())
    detail.add_child(_reg_desc_edit)

    _add_label(detail, "Category")
    _reg_category = OptionButton.new()
    for cat in ["currency", "consumable", "ammo", "upgrade", "key", "tag", "misc"]:
        _reg_category.add_item(cat)
    _reg_category.item_selected.connect(func(_idx): _mark_items_dirty())
    detail.add_child(_reg_category)

    _add_label(detail, "Max Stack")
    _reg_stack_edit = LineEdit.new()
    _reg_stack_edit.text_changed.connect(func(_t): _mark_items_dirty())
    _reg_stack_edit.text_changed.connect(func(_t): _refresh_registry_validation())
    detail.add_child(_reg_stack_edit)

    _add_label(detail, "Default Price")
    _reg_price_edit = LineEdit.new()
    _reg_price_edit.text_changed.connect(func(_t): _mark_items_dirty())
    _reg_price_edit.text_changed.connect(func(_t): _refresh_registry_validation())
    detail.add_child(_reg_price_edit)

    _add_label(detail, "Effect")
    _reg_effect = OptionButton.new()
    _populate_effect_option(_reg_effect)
    _reg_effect.item_selected.connect(func(_idx): _mark_items_dirty())
    _reg_effect.item_selected.connect(func(_idx): _refresh_registry_validation())
    detail.add_child(_reg_effect)

    _add_label(detail, "Effect Amount")
    _reg_amount_edit = LineEdit.new()
    _reg_amount_edit.text_changed.connect(func(_t): _mark_items_dirty())
    _reg_amount_edit.text_changed.connect(func(_t): _refresh_registry_validation())
    detail.add_child(_reg_amount_edit)

    _add_label(detail, "Effect target (ammo type, tag, event, variable, ability, or weapon)")
    _reg_arg_edit = LineEdit.new()
    _reg_arg_edit.text_changed.connect(func(_t): _mark_items_dirty())
    _reg_arg_edit.text_changed.connect(func(_t): _refresh_registry_validation())
    detail.add_child(_reg_arg_edit)

    _reg_auto_check = CheckBox.new()
    _reg_auto_check.text = "Auto-use on pickup / purchase"
    _reg_auto_check.toggled.connect(func(_on): _mark_items_dirty())
    detail.add_child(_reg_auto_check)

    _reg_validation_label = Label.new()
    _reg_validation_label.add_theme_font_size_override("font_size", 11)
    _reg_validation_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
    _reg_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _reg_validation_label.custom_minimum_size = Vector2(0, 40)
    detail.add_child(_reg_validation_label)


func _add_label(parent: VBoxContainer, text: String) -> void:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 11)
    parent.add_child(lbl)


func _populate_effect_option(option: OptionButton) -> void:
    if option == null:
        return
    option.clear()
    for effect in ITEM_EFFECTS:
        option.add_item(effect if effect != "" else "(none)")
        option.set_item_metadata(option.item_count - 1, effect)


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
    _normalize_stock_ids()
    _selected_item = -1
    _rebuild_item_list()
    _dirty = false
    if _undo != null:
        _undo.clear()


func _rebuild_item_list() -> void:
    _item_list.clear()
    var seen_stock_ids: Dictionary = {}
    for i in _items.size():
        var item: Dictionary = _items[i]
        var id_str: String = str(item.get("id", "")).strip_edges()
        var stock_id := str(item.get("stock_id", "")).strip_edges()
        var name_str := str(item.get("name", id_str)).strip_edges()
        var preview: String = "%s — %d gold" % [
            name_str if not name_str.is_empty() else "(unnamed)",
            int(item.get("price", 0)),
        ]
        if not stock_id.is_empty():
            preview += "  [%s]" % stock_id
        var effect_str := str(item.get("use_effect", "")).strip_edges()
        if not effect_str.is_empty():
            preview += "  " + effect_str
        var warn := ""
        if stock_id.is_empty():
            warn = "  [!] empty entry id"
        elif seen_stock_ids.has(stock_id):
            warn = "  [!] duplicate entry id"
        elif id_str.is_empty():
            warn = "  [!] empty id"
        elif not _known_item_ids.has(id_str):
            warn = "  [!] unknown item id"
        seen_stock_ids[stock_id] = true
        _item_list.add_item(preview + warn)
        if not warn.is_empty():
            _item_list.set_item_custom_fg_color(i, Color(1.0, 0.55, 0.35))
    if _selected_item >= 0 and _selected_item < _items.size():
        _item_list.select(_selected_item)
        _show_item_detail(_selected_item)
    _refresh_validation()


func _rebuild_registry_list() -> void:
    if _registry_list == null:
        return
    _registry_list.clear()
    var seen: Dictionary = {}
    for i in _registry_items.size():
        var item: Dictionary = _registry_items[i]
        var id_str := str(item.get("id", "")).strip_edges()
        var name_str := str(item.get("name", id_str)).strip_edges()
        var effect_str := str(item.get("use_effect", "")).strip_edges()
        var label := "%s  [%s]" % [name_str if not name_str.is_empty() else "(unnamed)", id_str if not id_str.is_empty() else "no id"]
        if not effect_str.is_empty():
            label += "  " + effect_str
        var warn := ""
        if id_str.is_empty():
            warn = "  [!] empty id"
        elif seen.has(id_str):
            warn = "  [!] duplicate"
        seen[id_str] = true
        _registry_list.add_item(label + warn)
        if not warn.is_empty():
            _registry_list.set_item_custom_fg_color(i, Color(1.0, 0.55, 0.35))
    if _selected_registry_item >= 0 and _selected_registry_item < _registry_items.size():
        _registry_list.select(_selected_registry_item)
        _show_registry_detail(_selected_registry_item)
    _refresh_registry_validation()


func _on_registry_select(idx: int) -> void:
    if not _flush_registry_item():
        if _registry_list != null and _selected_registry_item >= 0 and _selected_registry_item < _registry_items.size():
            _registry_list.select(_selected_registry_item)
        return
    _selected_registry_item = idx
    _show_registry_detail(idx)


func _show_registry_detail(idx: int) -> void:
    if idx < 0 or idx >= _registry_items.size():
        return
    _suppress = true
    var item: Dictionary = _registry_items[idx]
    _reg_id_edit.text = str(item.get("id", ""))
    _reg_name_edit.text = str(item.get("name", ""))
    _reg_desc_edit.text = str(item.get("description", ""))
    _select_option_text(_reg_category, str(item.get("category", "misc")))
    _reg_stack_edit.text = str(int(item.get("max_stack", 1)))
    _reg_price_edit.text = str(int(item.get("price", 0)))
    _select_effect(str(item.get("use_effect", "")))
    _reg_amount_edit.text = str(int(item.get("use_amount", 0)))
    _reg_arg_edit.text = str(item.get("use_arg", ""))
    _reg_auto_check.button_pressed = bool(item.get("auto_use_on_gain", false))
    _suppress = false
    _refresh_registry_validation()


func _select_option_text(option: OptionButton, value: String) -> void:
    if option == null:
        return
    for i in option.item_count:
        if option.get_item_text(i) == value:
            option.select(i)
            return
    option.select(0)


func _select_effect(effect: String) -> void:
    _select_effect_option(_reg_effect, effect)


func _select_stock_effect(effect: String) -> void:
    _select_effect_option(_stock_effect, effect)


func _select_effect_option(option: OptionButton, effect: String) -> void:
    if option == null:
        return
    for i in option.item_count:
        if str(option.get_item_metadata(i)) == effect:
            option.select(i)
            return
    option.select(0)


func _selected_effect() -> String:
    return _selected_effect_from(_reg_effect)


func _selected_stock_effect() -> String:
    return _selected_effect_from(_stock_effect)


func _selected_effect_from(option: OptionButton) -> String:
    if option == null or option.selected < 0:
        return ""
    return str(option.get_item_metadata(option.selected))


func _refresh_registry_validation() -> void:
    if _reg_validation_label == null:
        return
    var msgs: Array = []
    var id_str := _reg_id_edit.text.strip_edges() if _reg_id_edit != null else ""
    if id_str.is_empty():
        msgs.append("Registry item id is empty.")
    var dup_count := 0
    for i in _registry_items.size():
        if i == _selected_registry_item:
            continue
        if str((_registry_items[i] as Dictionary).get("id", "")).strip_edges() == id_str and not id_str.is_empty():
            dup_count += 1
    if dup_count > 0:
        msgs.append("Duplicate registry id.")
    if _reg_stack_edit != null and not _is_valid_int_string(_reg_stack_edit.text):
        msgs.append("Max stack must be a whole number.")
    if _reg_price_edit != null and not _is_valid_int_string(_reg_price_edit.text):
        msgs.append("Default price must be a whole number.")
    if _reg_amount_edit != null and not _is_valid_int_string(_reg_amount_edit.text):
        msgs.append("Effect amount must be a whole number.")
    var effect := _selected_effect()
    var arg := _reg_arg_edit.text.strip_edges() if _reg_arg_edit != null else ""
    if effect in EFFECTS_REQUIRING_ARG and arg.is_empty():
        msgs.append("This effect needs an arg.")
    _reg_validation_label.text = "  ".join(msgs)


func _flush_registry_item() -> bool:
    if _selected_registry_item < 0 or _selected_registry_item >= _registry_items.size():
        return true
    if not _is_valid_int_string(_reg_stack_edit.text) or not _is_valid_int_string(_reg_price_edit.text) or not _is_valid_int_string(_reg_amount_edit.text):
        _refresh_registry_validation()
        status_changed.emit("Registry item has invalid number fields")
        return false
    var item: Dictionary = _registry_items[_selected_registry_item]
    var old_id := str(item.get("id", "")).strip_edges()
    var new_id := _reg_id_edit.text.strip_edges()
    item["id"] = new_id
    item["name"] = _reg_name_edit.text.strip_edges()
    item["description"] = _reg_desc_edit.text.strip_edges()
    item["category"] = _reg_category.get_item_text(_reg_category.selected) if _reg_category.selected >= 0 else "misc"
    item["max_stack"] = maxi(1, int(_reg_stack_edit.text))
    item["price"] = maxi(0, int(_reg_price_edit.text))
    var effect := _selected_effect()
    if effect.is_empty():
        item.erase("use_effect")
        item.erase("use_amount")
        item.erase("use_arg")
    else:
        item["use_effect"] = effect
        item["use_amount"] = maxi(0, int(_reg_amount_edit.text))
        item["use_arg"] = _reg_arg_edit.text.strip_edges()
    if _reg_auto_check.button_pressed:
        item["auto_use_on_gain"] = true
    else:
        item.erase("auto_use_on_gain")
    if not old_id.is_empty() and not new_id.is_empty() and old_id != new_id:
        _rename_item_references(old_id, new_id)
    _refresh_known_item_ids()
    _rebuild_registry_list()
    return true


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
    _stock_id_edit.text = str(item.get("stock_id", _unique_stock_id(str(item.get("id", "stock_item")))))
    _id_edit.text = str(item.get("id", ""))
    _name_edit.text = str(item.get("name", ""))
    _price_edit.text = str(int(item.get("price", 0)))
    _count_edit.text = str(int(item.get("count", 1)))
    _select_stock_effect(str(item.get("use_effect", "")))
    _stock_amount_edit.text = str(int(item.get("use_amount", 0)))
    _stock_arg_edit.text = str(item.get("use_arg", ""))
    _stock_auto_check.button_pressed = bool(item.get("auto_use_on_gain", not str(item.get("use_effect", "")).strip_edges().is_empty()))
    _suppress = false
    _refresh_validation()


func _refresh_validation() -> void:
    if _validation_label == null:
        return
    var stock_id := _stock_id_edit.text.strip_edges() if _stock_id_edit != null else ""
    var id_str: String = _id_edit.text.strip_edges() if _id_edit != null else ""
    var msgs: Array = []
    if stock_id.is_empty():
        msgs.append("Offer id is empty.")
    var dup_stock_count := 0
    for i in _items.size():
        if i == _selected_item:
            continue
        if str((_items[i] as Dictionary).get("stock_id", "")).strip_edges() == stock_id and not stock_id.is_empty():
            dup_stock_count += 1
    if dup_stock_count > 0:
        msgs.append("Offer id must be unique in this shop.")
    if id_str.is_empty():
        msgs.append("Item id is empty.")
    elif not _known_item_ids.has(id_str):
        msgs.append("'%s' is not in this pack's Items registry — open the Items editor to add it." % id_str)
    if _price_edit != null and not _is_valid_int_string(_price_edit.text):
        msgs.append("Price must be a whole number.")
    if _count_edit != null and not _is_valid_int_string(_count_edit.text):
        msgs.append("Count must be a whole number.")
    if _stock_amount_edit != null and not _is_valid_int_string(_stock_amount_edit.text):
        msgs.append("Effect amount must be a whole number.")
    var effect := _selected_stock_effect()
    var arg := _stock_arg_edit.text.strip_edges() if _stock_arg_edit != null else ""
    if effect in EFFECTS_REQUIRING_ARG and arg.is_empty():
        msgs.append("This offer effect needs a target.")
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
    if not _is_valid_int_string(_stock_amount_edit.text):
        var bad_amount := _stock_amount_edit.text.strip_edges()
        _validation_label.text = "Effect amount must be a whole number, got '%s'." % bad_amount
        status_changed.emit("Offer effect amount is invalid; fix it before saving or switching rows")
        return false
    var item: Dictionary = _items[_selected_item]
    item["stock_id"] = _stock_id_edit.text.strip_edges()
    item["id"] = _id_edit.text.strip_edges()
    var name_val := _name_edit.text.strip_edges()
    if name_val.is_empty():
        item.erase("name")
    else:
        item["name"] = name_val
    item["price"] = max(0, int(_price_edit.text))
    item["count"] = max(1, int(_count_edit.text))
    var effect := _selected_stock_effect()
    if effect.is_empty():
        item.erase("use_effect")
        item.erase("use_amount")
        item.erase("use_arg")
        item.erase("auto_use_on_gain")
    else:
        item["use_effect"] = effect
        item["use_amount"] = max(0, int(_stock_amount_edit.text))
        item["use_arg"] = _stock_arg_edit.text.strip_edges()
        item["auto_use_on_gain"] = _stock_auto_check.button_pressed
    _rebuild_item_list()
    return true


func _on_add_item() -> void:
    if not _flush_item():
        return
    if _undo != null:
        _undo.begin()
    _items.append({"stock_id": _unique_stock_id("stock_item"), "id": "", "price": 0, "count": 1})
    _selected_item = _items.size() - 1
    _rebuild_item_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("add shop item")


func _on_add_selected_registry_to_shop() -> void:
    if _selected_registry_item < 0 or _selected_registry_item >= _registry_items.size():
        return
    if not _flush_item() or not _flush_registry_item():
        return
    var reg: Dictionary = _registry_items[_selected_registry_item]
    var item_id := str(reg.get("id", "")).strip_edges()
    if item_id.is_empty():
        return
    if _undo != null:
        _undo.begin()
    _items.append({
        "stock_id": _unique_stock_id(item_id),
        "id": item_id,
        "name": str(reg.get("name", item_id)),
        "price": int(reg.get("price", 0)),
        "count": 1,
    })
    _selected_item = _items.size() - 1
    _rebuild_item_list()
    _mark_dirty()
    if _undo != null:
        _undo.commit("add registry item to shop")


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


func _on_add_registry_item() -> void:
    _add_registry_item(_template_item("blank"))


func _on_add_registry_template(template_id: String) -> void:
    _add_registry_item(_template_item(template_id))


func _add_registry_item(item: Dictionary) -> void:
    if not _flush_registry_item():
        return
    if _undo != null:
        _undo.begin()
    var base_id := str(item.get("id", "item")).strip_edges()
    item["id"] = _unique_registry_id(base_id)
    _registry_items.append(item)
    _selected_registry_item = _registry_items.size() - 1
    _mark_items_dirty()
    _rebuild_registry_list()
    if _undo != null:
        _undo.commit("add registry item")


func _on_delete_registry_item() -> void:
    if _selected_registry_item < 0 or _selected_registry_item >= _registry_items.size():
        return
    var item_id := str((_registry_items[_selected_registry_item] as Dictionary).get("id", "")).strip_edges()
    var refs := ContentReferenceIndex.find_references(_pack_id, "item", item_id)
    if not refs.is_empty() and _delete_registry_confirm != null:
        _pending_delete_registry_item_id = item_id
        _delete_registry_confirm.dialog_text = _reference_warning_text(
            refs,
            "Delete \"%s\"? These references will break unless you update them." % item_id
        )
        _delete_registry_confirm.popup_centered(Vector2i(560, 280))
        return
    _delete_registry_item_now(item_id)


func _delete_registry_item_now(item_id: String) -> void:
    var idx := _selected_registry_item
    if not item_id.is_empty():
        idx = _registry_index_for_id(item_id)
    if idx < 0 or idx >= _registry_items.size():
        return
    if _undo != null:
        _undo.begin()
    _registry_items.remove_at(idx)
    _selected_registry_item = mini(idx, _registry_items.size() - 1)
    _mark_items_dirty()
    _refresh_known_item_ids()
    _rebuild_registry_list()
    _rebuild_item_list()
    if _undo != null:
        _undo.commit("delete registry item")


func _on_delete_registry_item_confirmed() -> void:
    var item_id := _pending_delete_registry_item_id
    _pending_delete_registry_item_id = ""
    _delete_registry_item_now(item_id)


func _rename_item_references(old_id: String, new_id: String) -> void:
    _rename_item_refs_in_current_shop(old_id, new_id)
    var refactor := ContentReferenceRefactor.rename_references(_pack_id, "item", old_id, new_id)
    if not bool(refactor.get("ok", false)):
        status_changed.emit("Item renamed, but reference update failed: %s" % _lines_to_text(refactor.get("errors", [])))
        return
    var changed := int(refactor.get("changed_refs", 0))
    if changed > 0:
        _dirty = true
        status_changed.emit("Renamed item id and updated %d reference(s)" % changed)


func _rename_item_refs_in_current_shop(old_id: String, new_id: String) -> void:
    for item_v in _items:
        if typeof(item_v) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_v
        if str(item.get("id", "")).strip_edges() == old_id:
            item["id"] = new_id
    _rebuild_item_list()


func _registry_index_for_id(item_id: String) -> int:
    for i in range(_registry_items.size()):
        var item_v: Variant = _registry_items[i]
        if typeof(item_v) == TYPE_DICTIONARY and str((item_v as Dictionary).get("id", "")).strip_edges() == item_id:
            return i
    return -1


func _reference_warning_text(refs: Array, intro: String) -> String:
    var lines := PackedStringArray()
    lines.append(intro)
    lines.append("")
    lines.append("%d reference(s) found:" % refs.size())
    var limit := mini(refs.size(), 8)
    for i in range(limit):
        var ref_v: Variant = refs[i]
        if typeof(ref_v) != TYPE_DICTIONARY:
            continue
        var ref: Dictionary = ref_v
        lines.append("- %s %s (%s)" % [
            str(ref.get("source", "")),
            str(ref.get("field", "")),
            str(ref.get("role", "")),
        ])
    if refs.size() > limit:
        lines.append("- ...and %d more." % (refs.size() - limit))
    return "\n".join(lines)


func _lines_to_text(value: Variant) -> String:
    var lines := PackedStringArray()
    for line_v in _as_array(value):
        lines.append(str(line_v))
    return "\n".join(lines)


func _as_array(value: Variant) -> Array:
    if typeof(value) == TYPE_ARRAY:
        return value
    return []


func _unique_registry_id(base_id: String) -> String:
    var base := base_id.strip_edges().to_lower().replace(" ", "_")
    if base.is_empty():
        base = "item"
    var used: Dictionary = {}
    for item_v in _registry_items:
        if typeof(item_v) == TYPE_DICTIONARY:
            used[str((item_v as Dictionary).get("id", ""))] = true
    var candidate := base
    var idx := 1
    while used.has(candidate):
        candidate = "%s_%d" % [base, idx]
        idx += 1
    return candidate


func _normalize_stock_ids() -> void:
    var used: Dictionary = {}
    for item_v in _items:
        if typeof(item_v) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_v
        var base := str(item.get("stock_id", "")).strip_edges()
        if base.is_empty():
            base = str(item.get("id", "stock_item")).strip_edges()
        var candidate := _sanitize_id(base, "stock_item")
        var idx := 1
        var final_id := candidate
        while used.has(final_id):
            final_id = "%s_%d" % [candidate, idx]
            idx += 1
        item["stock_id"] = final_id
        used[final_id] = true


func _unique_stock_id(base_id: String) -> String:
    var base := _sanitize_id(base_id, "stock_item")
    var used: Dictionary = {}
    for item_v in _items:
        if typeof(item_v) == TYPE_DICTIONARY:
            used[str((item_v as Dictionary).get("stock_id", ""))] = true
    var candidate := base
    var idx := 1
    while used.has(candidate):
        candidate = "%s_%d" % [base, idx]
        idx += 1
    return candidate


func _sanitize_id(value: String, fallback: String) -> String:
    var out := value.strip_edges().to_lower().replace(" ", "_")
    if out.is_empty():
        out = fallback
    return out


func _template_item(template_id: String) -> Dictionary:
    match template_id:
        "health":
            return {
                "id": "health_pickup",
                "name": "Health Pickup",
                "description": "Restores 25 HP immediately.",
                "category": "consumable",
                "max_stack": 1,
                "price": 10,
                "use_effect": "heal_hp",
                "use_amount": 25,
                "use_arg": "",
                "auto_use_on_gain": true,
            }
        "money":
            return {
                "id": "credit_pickup",
                "name": "Credit Pickup",
                "description": "Adds 5 gold immediately.",
                "category": "currency",
                "max_stack": 9999,
                "price": 0,
                "use_effect": "add_gold",
                "use_amount": 5,
                "use_arg": "",
                "auto_use_on_gain": true,
            }
        "ammo":
            return {
                "id": "missile_ammo_pickup",
                "name": "Missile Ammo",
                "description": "Adds 5 missile ammo.",
                "category": "ammo",
                "max_stack": 99,
                "price": 8,
                "use_effect": "add_ammo",
                "use_amount": 5,
                "use_arg": "missile",
                "auto_use_on_gain": true,
            }
        "max_ammo_up":
            return {
                "id": "missile_expansion",
                "name": "Missile Expansion",
                "description": "Permanently increases max missile ammo.",
                "category": "upgrade",
                "max_stack": 99,
                "price": 75,
                "use_effect": "max_ammo_up",
                "use_amount": 5,
                "use_arg": "missile",
                "auto_use_on_gain": true,
            }
        "hp_up":
            return {
                "id": "health_container",
                "name": "Health Container",
                "description": "Permanently increases max HP.",
                "category": "upgrade",
                "max_stack": 99,
                "price": 75,
                "use_effect": "max_hp_up",
                "use_amount": 25,
                "use_arg": "",
                "auto_use_on_gain": true,
            }
        "damage_up":
            return {
                "id": "damage_upgrade",
                "name": "Damage Upgrade",
                "description": "Permanently adds 2 damage to melee and projectile attacks.",
                "category": "upgrade",
                "max_stack": 99,
                "price": 100,
                "use_effect": "damage_up",
                "use_amount": 2,
                "use_arg": "",
                "auto_use_on_gain": true,
            }
        "inventory_up":
            return {
                "id": "inventory_upgrade",
                "name": "Inventory Upgrade",
                "description": "Permanently increases inventory capacity.",
                "category": "upgrade",
                "max_stack": 99,
                "price": 60,
                "use_effect": "inventory_slots_up",
                "use_amount": 5,
                "use_arg": "",
                "auto_use_on_gain": true,
            }
        "ability":
            return {
                "id": "ability_unlock",
                "name": "Ability Unlock",
                "description": "Grants an ability immediately.",
                "category": "upgrade",
                "max_stack": 1,
                "price": 100,
                "use_effect": "grant_ability",
                "use_amount": 1,
                "use_arg": "double_jump",
                "auto_use_on_gain": true,
            }
        "tag":
            return {
                "id": "trigger_tag",
                "name": "Trigger Tag",
                "description": "Adds a world tag for triggers and doors.",
                "category": "tag",
                "max_stack": 1,
                "price": 25,
                "use_effect": "add_tag",
                "use_amount": 1,
                "use_arg": "met_shopkeeper",
                "auto_use_on_gain": true,
            }
        "event":
            return {
                "id": "trigger_event",
                "name": "Trigger Event",
                "description": "Fires a trigger event immediately.",
                "category": "misc",
                "max_stack": 1,
                "price": 25,
                "use_effect": "fire_event",
                "use_amount": 1,
                "use_arg": "item_purchased",
                "auto_use_on_gain": true,
            }
    return {
        "id": "new_item",
        "name": "New Item",
        "description": "",
        "category": "misc",
        "max_stack": 1,
        "price": 0,
    }


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


func _mark_items_dirty() -> void:
    if _suppress:
        return
    _items_dirty = true


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
