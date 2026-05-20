extends Control

const PedIO = preload("res://Space/scripts/shared/ped/ped_io.gd")

# Player editor — Abilities tab. List + detail editor for abilities.json. Each
# ability has id/name/description/category plus a `params` dict of arbitrary
# numeric values that the runtime reads via AbilityDef.ParamFloat / ParamInt.

var pack_id: String = ""
var dirty: bool = false

var _abilities: Array = []         # Array[Dictionary]
var _selected_idx: int = -1

var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null
var _list_header: Label = null

var _detail_header: Label = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _category_edit: LineEdit = null
var _params_edit: LineEdit = null

var _label_id: Label = null
var _label_name: Label = null
var _label_desc: Label = null
var _label_category: Label = null
var _params_header: Label = null
var _add_param_btn: Button = null
var _known_params_header: Label = null
var _explain_label: Label = null
var _known_param_rects: Array = []  # [{key, default_value, rect}]

var _suppress_events: bool = false

var _undo: RefCounted = null

# Common ability params that users can click to auto-add.
const KNOWN_PARAMS: Array = [
    {"key": "jump_multiplier", "default": 1.4, "desc": "Multiplies jump speed (double_jump, high_jump)"},
    {"key": "extra_air_jumps", "default": 1, "desc": "Number of extra mid-air jumps granted"},
    {"key": "wall_jump_x_speed", "default": 200.0, "desc": "Horizontal speed on wall kick"},
    {"key": "wall_jump_y_speed", "default": 280.0, "desc": "Vertical speed on wall kick"},
    {"key": "boost_speed_multiplier", "default": 1.6, "desc": "Run speed multiplier (speed_booster)"},
    {"key": "charge_seconds", "default": 1.0, "desc": "Charge-up duration in seconds"},
    {"key": "stash_seconds", "default": 5.0, "desc": "Stash timer duration (shinespark)"},
    {"key": "gravity_multiplier", "default": 0.5, "desc": "Gravity scale factor (space_jump)"},
    {"key": "damage_multiplier", "default": 2.0, "desc": "Damage multiplier for ability attacks"},
    {"key": "range", "default": 120.0, "desc": "Effective range in pixels"},
]

const LEFT_W: float = 220.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "abilities": _abilities.duplicate(true),
        "selected_idx": _selected_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var a_v: Variant = snap.get("abilities", null)
    if typeof(a_v) == TYPE_ARRAY:
        _abilities = a_v
    _selected_idx = int(snap.get("selected_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_list()
    if _selected_idx >= 0 and _selected_idx < _abilities.size() and _list != null:
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
    queue_redraw()


func _draw() -> void:
    # Draw known params as clickable chips below the params input.
    if _known_params_header == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()
    var base_x: float = _known_params_header.position.x
    var y: float = _known_params_header.position.y + 22.0
    var chip_h: float = 22.0
    var chip_gap: float = 6.0
    var max_w: float = size.x - base_x - 20.0

    _known_param_rects.clear()
    var x: float = base_x
    for entry in KNOWN_PARAMS:
        var key: String = str(entry["key"])
        var desc: String = str(entry["desc"])
        var chip_w: float = float(key.length()) * 7.0 + 16.0
        if x + chip_w > base_x + max_w:
            x = base_x
            y += chip_h + chip_gap
        var rect := Rect2(x, y, chip_w, chip_h)
        _known_param_rects.append({"key": key, "default_value": entry["default"], "rect": rect})

        var hovered := rect.has_point(mouse_pos)
        var col := Color(0.3, 0.55, 0.75, 0.8) if hovered else Color(0.2, 0.3, 0.45, 0.6)
        draw_rect(rect, col)
        draw_string(font, rect.position + Vector2(8, 15), key,
            HORIZONTAL_ALIGNMENT_LEFT, int(chip_w - 16), 10,
            Color(0.85, 0.95, 1.0) if hovered else Color(0.65, 0.75, 0.85))

        if hovered:
            EditorTooltip.show_text("%s — default: %s" % [desc, str(entry["default"])])

        x += chip_w + chip_gap


func _gui_input(event) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for entry in _known_param_rects:
            if (entry["rect"] as Rect2).has_point(event.position):
                _add_known_param(str(entry["key"]), entry["default_value"])
                accept_event()
                return


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    if _id_edit != null and Rect2(_id_edit.position, _id_edit.size).has_point(mp):
        EditorTooltip.show_text("Unique string ID for this ability. The runtime checks has_ability(id) as a binary unlock gate -- if the player has it, the ability is active.")
    elif _category_edit != null and Rect2(_category_edit.position, _category_edit.size).has_point(mp):
        EditorTooltip.show_text("Category tag for UI grouping: movement, weapon, passive, or utility. The inventory screen sorts abilities by this.")
    elif _params_edit != null and Rect2(_params_edit.position, _params_edit.size).has_point(mp):
        EditorTooltip.show_text("Arbitrary key=value pairs read at runtime via AbilityDef.ParamFloat / ParamInt. e.g. jump_multiplier=1.4 makes double-jump scale the jump speed.")
    elif _desc_edit != null and Rect2(_desc_edit.position, _desc_edit.size).has_point(mp):
        EditorTooltip.show_text("In-game description shown to the player in the inventory/pause screen when they inspect this ability.")


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_data()
    _populate_list()
    if _abilities.size() > 0:
        _list.select(0)
        _on_list_selected(0)
    else:
        _apply_to_inputs()
    if _undo != null:
        _undo.clear()


func save() -> bool:
    var out := {"abilities": _abilities.duplicate(true)}
    if not PedIO.save_abilities(pack_id, out):
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

    _list_header = _make_header("ABILITIES")
    _list = ItemList.new()
    _list.item_selected.connect(_on_list_selected)
    add_child(_list)
    _add_btn = _make_button("+ ABILITY", _on_add_pressed)
    _del_btn = _make_button("- ABILITY", _on_del_pressed)

    _detail_header = _make_header("DETAIL")

    _label_id = _make_label("ID")
    _id_edit = LineEdit.new()
    _id_edit.text_changed.connect(func(t): _on_field_edited("id", t))
    add_child(_id_edit)

    _label_name = _make_label("Name")
    _name_edit = LineEdit.new()
    _name_edit.text_changed.connect(func(t): _on_field_edited("name", t))
    add_child(_name_edit)

    _label_category = _make_label("Category")
    _category_edit = LineEdit.new()
    _category_edit.placeholder_text = "movement|weapon|passive|utility"
    _category_edit.text_changed.connect(func(t): _on_field_edited("category", t))
    add_child(_category_edit)

    _label_desc = _make_label("Description")
    _desc_edit = TextEdit.new()
    _desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _desc_edit.text_changed.connect(_on_desc_changed)
    add_child(_desc_edit)

    _params_header = _make_header("PARAMS")
    _params_edit = LineEdit.new()
    _params_edit.placeholder_text = "key=value, key=value ..."
    _params_edit.text_changed.connect(_on_params_text_changed)
    add_child(_params_edit)

    _add_param_btn = _make_button("+ PARAM", _on_add_param)
    _known_params_header = _make_header("KNOWN PARAMS (click to add)")

    _explain_label = Label.new()
    _explain_label.text = "Abilities are binary unlocks — has_ability(\"id\") returns true/false.\nParams fine-tune behavior: e.g. double_jump's jump_multiplier=1.4."
    _explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _explain_label.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))
    _explain_label.add_theme_font_size_override("font_size", 11)
    add_child(_explain_label)

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
    _place_row(_label_category, _category_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    _label_desc.position = Vector2(right_x, row_y + 3)
    _label_desc.size = Vector2(label_w, row_h)
    var desc_h: float = 90.0
    _desc_edit.position = Vector2(field_x, row_y)
    _desc_edit.size = Vector2(field_w, desc_h)
    row_y += desc_h + 8

    # Explanation
    if _explain_label != null:
        _explain_label.position = Vector2(right_x, row_y)
        _explain_label.size = Vector2(right_w, 36)
        row_y += 40

    _params_header.position = Vector2(right_x, row_y)
    _params_header.size = Vector2(right_w, 20)
    row_y += 22
    _params_edit.position = Vector2(right_x, row_y)
    _params_edit.size = Vector2(right_w - 100, field_h)
    if _add_param_btn != null:
        _add_param_btn.position = Vector2(right_x + right_w - 90, row_y)
        _add_param_btn.size = Vector2(90, field_h)
    row_y += field_h + 12

    # Known params section
    if _known_params_header != null:
        _known_params_header.position = Vector2(right_x, row_y)
        _known_params_header.size = Vector2(right_w, 20)
        row_y += 22


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
    var data := PedIO.load_abilities(pack_id)
    var raw = data.get("abilities", [])
    _abilities.clear()
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                _abilities.append(_normalize_entry(entry))
    _selected_idx = -1
    dirty = false


static func _normalize_entry(src: Dictionary) -> Dictionary:
    var params_raw = src.get("params", {})
    var params: Dictionary = {}
    if typeof(params_raw) == TYPE_DICTIONARY:
        for k in params_raw.keys():
            params[str(k)] = params_raw[k]
    return {
        "id":          str(src.get("id", "")),
        "name":        str(src.get("name", "")),
        "description": str(src.get("description", "")),
        "category":    str(src.get("category", "")),
        "params":      params,
    }


func _populate_list() -> void:
    _list.clear()
    for a in _abilities:
        _list.add_item("%s — %s" % [a.get("id", "?"), a.get("name", "?")])


func _on_list_selected(idx: int) -> void:
    if idx < 0 or idx >= _abilities.size():
        _selected_idx = -1
        _apply_to_inputs()
        return
    _selected_idx = idx
    _apply_to_inputs()


func _on_add_pressed() -> void:
    if _undo != null: _undo.begin()
    var new_id := "ability_%d" % (_abilities.size() + 1)
    while _id_taken(new_id):
        new_id += "_"
    var new_entry := {
        "id": new_id,
        "name": "New Ability",
        "description": "",
        "category": "",
        "params": {},
    }
    _abilities.append(new_entry)
    dirty = true
    _populate_list()
    var new_idx := _abilities.size() - 1
    _list.select(new_idx)
    _on_list_selected(new_idx)
    if _undo != null: _undo.commit("add ability")


func _id_taken(id: String) -> bool:
    for a in _abilities:
        if str(a.get("id", "")) == id:
            return true
    return false


func _id_taken_except(id: String, except_idx: int) -> bool:
    for i in range(_abilities.size()):
        if i == except_idx:
            continue
        var a: Dictionary = _abilities[i]
        if str(a.get("id", "")).strip_edges() == id:
            return true
    return false


func _on_del_pressed() -> void:
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    if _undo != null: _undo.begin()
    _abilities.remove_at(_selected_idx)
    dirty = true
    _populate_list()
    if _abilities.is_empty():
        _selected_idx = -1
        _apply_to_inputs()
        if _undo != null: _undo.commit("delete ability")
        return
    var next_idx: int = mini(_selected_idx, _abilities.size() - 1)
    _list.select(next_idx)
    _on_list_selected(next_idx)
    if _undo != null: _undo.commit("delete ability")


func _apply_to_inputs() -> void:
    if _id_edit == null:
        return
    _suppress_events = true
    var have: bool = _selected_idx >= 0 and _selected_idx < _abilities.size()
    _id_edit.editable = have
    _name_edit.editable = have
    _desc_edit.editable = have
    _category_edit.editable = have
    _params_edit.editable = have

    if not have:
        _id_edit.text = ""
        _name_edit.text = ""
        _desc_edit.text = ""
        _category_edit.text = ""
        _params_edit.text = ""
        _suppress_events = false
        return

    var a: Dictionary = _abilities[_selected_idx]
    _id_edit.text = str(a.get("id", ""))
    _name_edit.text = str(a.get("name", ""))
    _desc_edit.text = str(a.get("description", ""))
    _category_edit.text = str(a.get("category", ""))
    _params_edit.text = _params_to_text(a.get("params", {}))
    _suppress_events = false


func _on_field_edited(field: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    var a: Dictionary = _abilities[_selected_idx]
    if field == "id":
        var old_id := str(a.get("id", "")).strip_edges()
        var new_id := text.strip_edges()
        if not old_id.is_empty() and not new_id.is_empty() and old_id != new_id and not _id_taken_except(new_id, _selected_idx):
            _rename_ability_references(old_id, new_id)
    a[field] = text
    _abilities[_selected_idx] = a
    dirty = true
    if field == "id" or field == "name":
        _refresh_list_row(_selected_idx)


func _on_desc_changed() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    var a: Dictionary = _abilities[_selected_idx]
    a["description"] = _desc_edit.text
    _abilities[_selected_idx] = a
    dirty = true


func _on_add_param() -> void:
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    if _undo != null: _undo.begin()
    var a: Dictionary = _abilities[_selected_idx]
    var params: Dictionary = a.get("params", {})
    var n := params.size()
    var key := "param_%d" % (n + 1)
    params[key] = 0
    a["params"] = params
    _params_edit.text = _params_to_text(params)
    dirty = true
    if _undo != null: _undo.commit("add ability param")


func _add_known_param(key: String, default_value: Variant) -> void:
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    var a: Dictionary = _abilities[_selected_idx]
    var params: Dictionary = a.get("params", {})
    if not params.has(key):
        params[key] = default_value
        a["params"] = params
        _params_edit.text = _params_to_text(params)
        dirty = true


func _on_params_text_changed(text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _abilities.size():
        return
    var a: Dictionary = _abilities[_selected_idx]
    a["params"] = _text_to_params(text)
    _abilities[_selected_idx] = a
    dirty = true


func _refresh_list_row(idx: int) -> void:
    if idx < 0 or idx >= _abilities.size():
        return
    var a: Dictionary = _abilities[idx]
    _list.set_item_text(idx, "%s — %s" % [a.get("id", "?"), a.get("name", "?")])


# ─── Params text <-> dict ────────────────────────────────────────────────
# Preserve int vs float typing so the JSON round-trips cleanly: values without
# a decimal point stay ints, values with one become floats.

func _rename_ability_references(old_id: String, new_id: String) -> void:
    var refactor := ContentReferenceRefactor.rename_references(pack_id, "ability", old_id, new_id)
    if not bool(refactor.get("ok", false)):
        push_warning("[AbilitiesTab] ability renamed, but reference update failed: %s" % str(refactor.get("errors", [])))


static func _params_to_text(params: Dictionary) -> String:
    var parts: Array = []
    var keys := params.keys()
    keys.sort()
    for k in keys:
        var v = params[k]
        var s: String
        if typeof(v) == TYPE_INT:
            s = str(int(v))
        elif typeof(v) == TYPE_FLOAT:
            s = _trim_float_text(float(v))
        else:
            s = str(v)
        parts.append("%s=%s" % [str(k), s])
    return ", ".join(parts)


static func _trim_float_text(v: float) -> String:
    if abs(v - round(v)) < 0.0001:
        return "%.1f" % v
    var s := "%.3f" % v
    while s.ends_with("0"):
        s = s.substr(0, s.length() - 1)
    if s.ends_with("."):
        s = s.substr(0, s.length() - 1)
    return s


static func _text_to_params(text: String) -> Dictionary:
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
        if val_str.contains("."):
            out[key] = val_str.to_float()
        else:
            out[key] = val_str.to_int()
    return out
