extends Control

const PedIO = preload("res://Space/scripts/shared/ped/ped_io.gd")

# Player editor — Equipment tab. List + detail editor for equipment.json.
# Each piece has a slot (SOTN 7-slot layout), grants_abilities (set), and
# stat_mods (string→float dict). Equipment that carries a weapon sets the
# optional `weapon` field which the runtime reads to pick the active attack.

var pack_id: String = ""
var dirty: bool = false

var _equipment: Array = []       # Array[Dictionary]
var _abilities_pool: Array = []  # Array[String] — id list from abilities.json
var _selected_idx: int = -1

# Left column
var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null
var _list_header: Label = null

# Detail
var _detail_header: Label = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _slot_option: OptionButton = null
var _weapon_edit: LineEdit = null
var _secondary_attack_edit: LineEdit = null
var _secondary_ammo_key_edit: LineEdit = null
var _secondary_ammo_cost_edit: LineEdit = null

# Abilities multi-select (left = pool, populated from abilities.json)
var _abilities_header: Label = null
var _abilities_list: ItemList = null

# Stat mods as a LineEdit in "key=value, key=value" format. Simple to author,
# round-trips through the _stat_mods_to_text / _text_to_stat_mods helpers.
var _stat_mods_header: Label = null
var _stat_mods_edit: LineEdit = null

# Labels for the field rows
var _label_id: Label = null
var _label_name: Label = null
var _label_slot: Label = null
var _label_weapon: Label = null
var _label_secondary_attack: Label = null
var _label_secondary_ammo_key: Label = null
var _label_secondary_ammo_cost: Label = null
var _label_desc: Label = null

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
        "equipment": _equipment.duplicate(true),
        "selected_idx": _selected_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var e_v: Variant = snap.get("equipment", null)
    if typeof(e_v) == TYPE_ARRAY:
        _equipment = e_v
    _selected_idx = int(snap.get("selected_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_list()
    if _selected_idx >= 0 and _selected_idx < _equipment.size() and _list != null:
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
    if _slot_option != null and Rect2(_slot_option.position, _slot_option.size).has_point(mp):
        EditorTooltip.show_text("Equipment slot (SOTN 7-slot layout). Only one piece can occupy each slot at a time.")
    elif _weapon_edit != null and Rect2(_weapon_edit.position, _weapon_edit.size).has_point(mp):
        EditorTooltip.show_text("Attack selector. Use an authored attack id for pack-driven combat, or beam / grenade_launcher for legacy fallback behavior.")
    elif _secondary_attack_edit != null and Rect2(_secondary_attack_edit.position, _secondary_attack_edit.size).has_point(mp):
        EditorTooltip.show_text("Authored attack id fired by the Secondary Fire input while this equipment is worn.")
    elif _secondary_ammo_key_edit != null and Rect2(_secondary_ammo_key_edit.position, _secondary_ammo_key_edit.size).has_point(mp):
        EditorTooltip.show_text("Ammo pool name consumed by secondary fire. 'missile' reads ammo_missile and max_ammo_missile.")
    elif _secondary_ammo_cost_edit != null and Rect2(_secondary_ammo_cost_edit.position, _secondary_ammo_cost_edit.size).has_point(mp):
        EditorTooltip.show_text("Amount of the secondary ammo pool spent per shot. Use 0 for no ammo cost.")
    elif _abilities_list != null and Rect2(_abilities_list.position, _abilities_list.size).has_point(mp):
        EditorTooltip.show_text("Abilities granted while this equipment is worn. Multi-select from the pool defined in the Abilities tab. These act as binary unlocks via has_ability().")
    elif _stat_mods_edit != null and Rect2(_stat_mods_edit.position, _stat_mods_edit.size).has_point(mp):
        EditorTooltip.show_text("Stat modifiers applied while equipped, as key=value pairs. e.g. damage_reduction=0.5 halves incoming damage. Stacks additively with other equipment.")
    elif _desc_edit != null and Rect2(_desc_edit.position, _desc_edit.size).has_point(mp):
        EditorTooltip.show_text("In-game description shown when the player inspects this equipment in the inventory or shop.")


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_data()
    _load_abilities_pool()
    _populate_list()
    _populate_abilities_pool_ui()
    if _equipment.size() > 0:
        _list.select(0)
        _on_list_selected(0)
    else:
        _apply_to_inputs()
    if _undo != null:
        _undo.clear()


func save() -> bool:
    var out := {"equipment": _equipment.duplicate(true)}
    if not PedIO.save_equipment(pack_id, out):
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

    _list_header = _make_header("EQUIPMENT")
    _list = ItemList.new()
    _list.item_selected.connect(_on_list_selected)
    add_child(_list)
    _add_btn = _make_button("+ EQUIP", _on_add_pressed)
    _del_btn = _make_button("- EQUIP", _on_del_pressed)

    _detail_header = _make_header("DETAIL")

    _label_id = _make_label("ID")
    _id_edit = LineEdit.new()
    _id_edit.text_changed.connect(func(t): _on_field_edited("id", t))
    add_child(_id_edit)

    _label_name = _make_label("Name")
    _name_edit = LineEdit.new()
    _name_edit.text_changed.connect(func(t): _on_field_edited("name", t))
    add_child(_name_edit)

    _label_slot = _make_label("Slot")
    _slot_option = OptionButton.new()
    for s in PedIO.equipment_slots():
        _slot_option.add_item(str(s))
    _slot_option.item_selected.connect(func(_i): _on_slot_selected())
    add_child(_slot_option)

    _label_weapon = _make_label("Weapon Mode")
    _weapon_edit = LineEdit.new()
    _weapon_edit.placeholder_text = "beam_shot | beam | grenade_launcher | blank"
    _weapon_edit.text_changed.connect(func(t): _on_field_edited("weapon", t))
    add_child(_weapon_edit)

    _label_secondary_attack = _make_label("Secondary")
    _secondary_attack_edit = LineEdit.new()
    _secondary_attack_edit.placeholder_text = "missile_shot | blank"
    _secondary_attack_edit.text_changed.connect(func(t): _on_field_edited("secondary_attack", t))
    add_child(_secondary_attack_edit)

    _label_secondary_ammo_key = _make_label("Ammo key")
    _secondary_ammo_key_edit = LineEdit.new()
    _secondary_ammo_key_edit.placeholder_text = "missile"
    _secondary_ammo_key_edit.text_changed.connect(func(t): _on_field_edited("secondary_ammo_key", t))
    add_child(_secondary_ammo_key_edit)

    _label_secondary_ammo_cost = _make_label("Ammo cost")
    _secondary_ammo_cost_edit = LineEdit.new()
    _secondary_ammo_cost_edit.placeholder_text = "1"
    _secondary_ammo_cost_edit.text_changed.connect(func(t): _on_int_field_edited("secondary_ammo_cost", t))
    add_child(_secondary_ammo_cost_edit)

    _label_desc = _make_label("Description")
    _desc_edit = TextEdit.new()
    _desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _desc_edit.text_changed.connect(_on_desc_changed)
    add_child(_desc_edit)

    _abilities_header = _make_header("GRANTS ABILITIES (multi-select)")
    _abilities_list = ItemList.new()
    _abilities_list.select_mode = ItemList.SELECT_MULTI
    _abilities_list.multi_selected.connect(_on_abilities_multi_selected)
    add_child(_abilities_list)

    _stat_mods_header = _make_header("STAT MODS (key=value, comma-separated)")
    _stat_mods_edit = LineEdit.new()
    _stat_mods_edit.placeholder_text = "damage_reduction=0.5, fire_resist=0.25"
    _stat_mods_edit.text_changed.connect(func(t): _on_stat_mods_text_changed(t))
    add_child(_stat_mods_edit)

    _sprite_header = _make_header("SPRITE (inventory icon)")
    _label_sheet = _make_label("Sheet")
    _sheet_edit = LineEdit.new()
    _sheet_edit.placeholder_text = "equipment_sheet.png"
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


func _make_header(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
    add_child(l)
    return l


func _make_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
    add_child(l)
    return l


func _make_button(text: String, cb: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.pressed.connect(cb)
    add_child(b)
    return b


func _layout_children() -> void:
    if _list == null:
        return
    var vw := size.x
    var vh := size.y

    _list_header.position = Vector2(12, 12)
    _list_header.size = Vector2(LEFT_W - 24, 20)
    _list.position = Vector2(12, 40)
    _list.size = Vector2(LEFT_W - 24, vh - 40 - 48)
    _add_btn.position = Vector2(12, vh - 40)
    _add_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)
    _del_btn.position = Vector2(12 + (LEFT_W - 32) * 0.5 + 8, vh - 40)
    _del_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)

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

    _place_row(_label_id, _id_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_name, _name_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_slot, _slot_option, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_weapon, _weapon_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_secondary_attack, _secondary_attack_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_secondary_ammo_key, _secondary_ammo_key_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_secondary_ammo_cost, _secondary_ammo_cost_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    _label_desc.position = Vector2(right_x, row_y + 3)
    _label_desc.size = Vector2(label_w, row_h)
    _desc_edit.position = Vector2(field_x, row_y)
    _desc_edit.size = Vector2(field_w, 70)
    row_y += 78

    _abilities_header.position = Vector2(right_x, row_y)
    _abilities_header.size = Vector2(right_w, 20)
    row_y += 24
    # Reserve room below abilities list for stat_mods (~60) + sprite section (~260).
    var abl_h: float = maxf(80.0, vh - row_y - 340.0)
    _abilities_list.position = Vector2(right_x, row_y)
    _abilities_list.size = Vector2(right_w, abl_h)
    row_y += abl_h + 8

    _stat_mods_header.position = Vector2(right_x, row_y)
    _stat_mods_header.size = Vector2(right_w, 20)
    row_y += 22
    _stat_mods_edit.position = Vector2(right_x, row_y)
    _stat_mods_edit.size = Vector2(right_w, field_h)
    row_y += field_h + 10

    _sprite_header.position = Vector2(right_x, row_y)
    _sprite_header.size = Vector2(right_w, 20)
    row_y += 24
    _label_sheet.position = Vector2(right_x, row_y + 3); _label_sheet.size = Vector2(label_w, row_h)
    _sheet_edit.position = Vector2(field_x, row_y); _sheet_edit.size = Vector2(field_w, field_h)
    row_y += row_h
    _label_fw.position = Vector2(right_x, row_y + 3); _label_fw.size = Vector2(label_w, row_h)
    _fw_edit.position = Vector2(field_x, row_y); _fw_edit.size = Vector2(field_w, field_h)
    row_y += row_h
    _label_fh.position = Vector2(right_x, row_y + 3); _label_fh.size = Vector2(label_w, row_h)
    _fh_edit.position = Vector2(field_x, row_y); _fh_edit.size = Vector2(field_w, field_h)
    row_y += row_h
    _label_findex.position = Vector2(right_x, row_y + 3); _label_findex.size = Vector2(label_w, row_h)
    _findex_edit.position = Vector2(field_x, row_y); _findex_edit.size = Vector2(field_w, field_h)
    row_y += row_h + 4

    if _sprite_preview != null:
        var preview_h: float = minf(110.0, vh - row_y - 8)
        if preview_h < 40.0:
            preview_h = 40.0
        _sprite_preview.position = Vector2(right_x, row_y)
        _sprite_preview.size = Vector2(right_w, preview_h)


func _place_row(lbl: Label, widget: Control,
                left_x: float, field_x: float, y: float,
                label_w: float, field_w: float,
                row_h: float, field_h: float) -> void:
    lbl.position = Vector2(left_x, y + 3)
    lbl.size = Vector2(label_w, row_h)
    widget.position = Vector2(field_x, y)
    widget.size = Vector2(field_w, field_h)


# ─── Data load / apply ───────────────────────────────────────────────────

func _load_data() -> void:
    var data := PedIO.load_equipment(pack_id)
    var raw = data.get("equipment", [])
    _equipment.clear()
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                _equipment.append(_normalize_entry(entry))
    _selected_idx = -1
    dirty = false


static func _normalize_entry(src: Dictionary) -> Dictionary:
    var slot_str: String = str(src.get("slot", "Body"))
    if not PedIO.equipment_slots().has(slot_str):
        slot_str = "Body"
    var grants_raw = src.get("grants_abilities", [])
    var grants: Array = []
    if typeof(grants_raw) == TYPE_ARRAY:
        for a in grants_raw:
            grants.append(str(a))
    var mods_raw = src.get("stat_mods", {})
    var mods: Dictionary = {}
    if typeof(mods_raw) == TYPE_DICTIONARY:
        for k in mods_raw.keys():
            mods[str(k)] = float(mods_raw[k])
    return {
        "id":               str(src.get("id", "")),
        "name":             str(src.get("name", "")),
        "description":      str(src.get("description", "")),
        "slot":             slot_str,
        "grants_abilities": grants,
        "stat_mods":        mods,
        "weapon":           str(src.get("weapon", "")),
        "secondary_attack": str(src.get("secondary_attack", "")),
        "secondary_ammo_key": str(src.get("secondary_ammo_key", "")),
        "secondary_ammo_cost": int(src.get("secondary_ammo_cost", 1)),
        "sprite_sheet":     str(src.get("sprite_sheet", "")),
        "frame_width":      int(src.get("frame_width", 16)),
        "frame_height":     int(src.get("frame_height", 16)),
        "frame_index":      int(src.get("frame_index", 0)),
    }


func _load_abilities_pool() -> void:
    var data := PedIO.load_abilities(pack_id)
    _abilities_pool.clear()
    var raw = data.get("abilities", [])
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                var id_str := str(entry.get("id", ""))
                if not id_str.is_empty():
                    _abilities_pool.append(id_str)


func _populate_list() -> void:
    _list.clear()
    for e in _equipment:
        _list.add_item("%s — %s (%s)" % [e.get("id", "?"), e.get("name", "?"), e.get("slot", "?")])


func _populate_abilities_pool_ui() -> void:
    _abilities_list.clear()
    for a in _abilities_pool:
        _abilities_list.add_item(str(a))


func _on_list_selected(idx: int) -> void:
    if idx < 0 or idx >= _equipment.size():
        _selected_idx = -1
        _apply_to_inputs()
        return
    _selected_idx = idx
    _apply_to_inputs()


func _on_add_pressed() -> void:
    if _undo != null: _undo.begin()
    var new_id := "equip_%d" % (_equipment.size() + 1)
    while _id_taken(new_id):
        new_id += "_"
    var new_entry := {
        "id": new_id,
        "name": "New Equipment",
        "description": "",
        "slot": "Body",
        "grants_abilities": [],
        "stat_mods": {},
        "weapon": "",
        "secondary_attack": "",
        "secondary_ammo_key": "",
        "secondary_ammo_cost": 1,
        "sprite_sheet": "",
        "frame_width": 16,
        "frame_height": 16,
        "frame_index": 0,
    }
    _equipment.append(new_entry)
    dirty = true
    _populate_list()
    var new_idx := _equipment.size() - 1
    _list.select(new_idx)
    _on_list_selected(new_idx)
    if _undo != null: _undo.commit("add equipment")


func _id_taken(id: String) -> bool:
    for e in _equipment:
        if str(e.get("id", "")) == id:
            return true
    return false


func _on_del_pressed() -> void:
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    if _undo != null: _undo.begin()
    _equipment.remove_at(_selected_idx)
    dirty = true
    _populate_list()
    if _equipment.is_empty():
        _selected_idx = -1
        _apply_to_inputs()
        if _undo != null: _undo.commit("delete equipment")
        return
    var next_idx: int = mini(_selected_idx, _equipment.size() - 1)
    _list.select(next_idx)
    _on_list_selected(next_idx)
    if _undo != null: _undo.commit("delete equipment")


func _apply_to_inputs() -> void:
    if _id_edit == null:
        return
    _suppress_events = true
    var have: bool = _selected_idx >= 0 and _selected_idx < _equipment.size()
    _id_edit.editable = have
    _name_edit.editable = have
    _desc_edit.editable = have
    _slot_option.disabled = not have
    _weapon_edit.editable = have
    _secondary_attack_edit.editable = have
    _secondary_ammo_key_edit.editable = have
    _secondary_ammo_cost_edit.editable = have
    _stat_mods_edit.editable = have
    _sheet_edit.editable = have
    _fw_edit.editable = have
    _fh_edit.editable = have
    _findex_edit.editable = have

    # Reset ability selection state regardless
    _clear_abilities_list_selection()

    if not have:
        _id_edit.text = ""
        _name_edit.text = ""
        _desc_edit.text = ""
        _weapon_edit.text = ""
        _secondary_attack_edit.text = ""
        _secondary_ammo_key_edit.text = ""
        _secondary_ammo_cost_edit.text = ""
        _stat_mods_edit.text = ""
        _sheet_edit.text = ""
        _fw_edit.text = ""
        _fh_edit.text = ""
        _findex_edit.text = ""
        _slot_option.select(0)
        _suppress_events = false
        return

    var e: Dictionary = _equipment[_selected_idx]
    _id_edit.text = str(e.get("id", ""))
    _name_edit.text = str(e.get("name", ""))
    _desc_edit.text = str(e.get("description", ""))
    _weapon_edit.text = str(e.get("weapon", ""))
    _secondary_attack_edit.text = str(e.get("secondary_attack", ""))
    _secondary_ammo_key_edit.text = str(e.get("secondary_ammo_key", ""))
    _secondary_ammo_cost_edit.text = str(int(e.get("secondary_ammo_cost", 1)))
    _stat_mods_edit.text = _stat_mods_to_text(e.get("stat_mods", {}))
    _sheet_edit.text = str(e.get("sprite_sheet", ""))
    _fw_edit.text = str(int(e.get("frame_width", 16)))
    _fh_edit.text = str(int(e.get("frame_height", 16)))
    _findex_edit.text = str(int(e.get("frame_index", 0)))

    var slot_str: String = str(e.get("slot", "Body"))
    var slots: Array = PedIO.equipment_slots()
    var slot_idx: int = slots.find(slot_str)
    _slot_option.select(maxi(0, slot_idx))

    var granted: Array = e.get("grants_abilities", [])
    for i in _abilities_list.item_count:
        var id_str := _abilities_list.get_item_text(i)
        if granted.has(id_str):
            _abilities_list.select(i, false)

    if _sprite_preview != null:
        _sprite_preview.pack_id = pack_id
        _sprite_preview.sheet_name = str(e.get("sprite_sheet", ""))
        _sprite_preview.frame_width = maxi(1, int(e.get("frame_width", 16)))
        _sprite_preview.frame_height = maxi(1, int(e.get("frame_height", 16)))
        _sprite_preview.frame_start = int(e.get("frame_index", 0))
        _sprite_preview.frame_count = 1
        _sprite_preview.frame_tick = 0
        _sprite_preview.reload_texture()
    _suppress_events = false


func _clear_abilities_list_selection() -> void:
    for i in _abilities_list.item_count:
        _abilities_list.deselect(i)


func _on_field_edited(field: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    e[field] = text
    _equipment[_selected_idx] = e
    dirty = true
    if field == "id" or field == "name":
        _refresh_list_row(_selected_idx)


func _on_int_field_edited(field: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    var t := text.strip_edges()
    if t.is_empty() or t == "-" or t == "+":
        e[field] = int(e.get(field, 0))
    else:
        e[field] = t.to_int()
    _equipment[_selected_idx] = e
    dirty = true


func _on_desc_changed() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    e["description"] = _desc_edit.text
    _equipment[_selected_idx] = e
    dirty = true


func _on_slot_selected() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var slots: Array = PedIO.equipment_slots()
    var idx := _slot_option.selected
    if idx < 0 or idx >= slots.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    e["slot"] = str(slots[idx])
    _equipment[_selected_idx] = e
    dirty = true
    _refresh_list_row(_selected_idx)


func _on_abilities_multi_selected(index: int, selected: bool) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var id_str := _abilities_list.get_item_text(index)
    var e: Dictionary = _equipment[_selected_idx]
    var granted: Array = (e.get("grants_abilities", []) as Array).duplicate()
    if selected:
        if not granted.has(id_str):
            granted.append(id_str)
    else:
        granted.erase(id_str)
    e["grants_abilities"] = granted
    _equipment[_selected_idx] = e
    dirty = true


func _on_stat_mods_text_changed(text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    e["stat_mods"] = _text_to_stat_mods(text)
    _equipment[_selected_idx] = e
    dirty = true


func _on_sprite_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[_selected_idx]
    if kind == "int":
        var t := text.strip_edges()
        if t.is_empty() or t == "-" or t == "+":
            e[field] = int(e.get(field, 0))
        else:
            e[field] = t.to_int()
    else:
        e[field] = text
    _equipment[_selected_idx] = e
    dirty = true

    if _sprite_preview != null:
        _sprite_preview.pack_id = pack_id
        _sprite_preview.sheet_name = str(e.get("sprite_sheet", ""))
        _sprite_preview.frame_width = maxi(1, int(e.get("frame_width", 16)))
        _sprite_preview.frame_height = maxi(1, int(e.get("frame_height", 16)))
        _sprite_preview.frame_start = int(e.get("frame_index", 0))
        _sprite_preview.frame_count = 1
        _sprite_preview.frame_tick = 0
        if field == "sprite_sheet":
            _sprite_preview.reload_texture()
        else:
            _sprite_preview._recalc_grid()


func _refresh_list_row(idx: int) -> void:
    if idx < 0 or idx >= _equipment.size():
        return
    var e: Dictionary = _equipment[idx]
    _list.set_item_text(idx, "%s — %s (%s)" % [e.get("id", "?"), e.get("name", "?"), e.get("slot", "?")])


# ─── Stat mods text <-> dict ─────────────────────────────────────────────

static func _stat_mods_to_text(mods: Dictionary) -> String:
    var parts: Array = []
    var keys := mods.keys()
    keys.sort()
    for k in keys:
        parts.append("%s=%s" % [str(k), _trim_float_text(float(mods[k]))])
    return ", ".join(parts)


static func _trim_float_text(v: float) -> String:
    # Show ints without trailing .0, floats with up to 3 decimals and
    # trailing zero trimming.
    if abs(v - round(v)) < 0.0001:
        return str(int(round(v)))
    var s := "%.3f" % v
    while s.ends_with("0"):
        s = s.substr(0, s.length() - 1)
    if s.ends_with("."):
        s = s.substr(0, s.length() - 1)
    return s


static func _text_to_stat_mods(text: String) -> Dictionary:
    var out: Dictionary = {}
    var raw := text.strip_edges()
    if raw.is_empty():
        return out
    var parts := raw.split(",", false)
    for p in parts:
        var kv := (p as String).strip_edges().split("=", false, 1)
        if kv.size() != 2:
            continue
        var key := kv[0].strip_edges()
        var val_str := kv[1].strip_edges()
        if key.is_empty() or val_str.is_empty():
            continue
        out[key] = val_str.to_float()
    return out
