extends Control



var editor_mode: String = "enemies"
var data: Dictionary = {}
var selected_id: String = ""
var scroll_list: float = 0.0
var scroll_props: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0

var edit_line: LineEdit = null
var editing_key: String = ""
var field_rects: Array = []
var button_rects: Array = []

var _undo: RefCounted = null

const LIST_W: float = 240.0

const _FIELD_TIPS: Dictionary = {
    "name": "Display name shown in the UI and in event text.",
    "description": "Flavor text. Shown in hover cards and event prompts.",
    "max_health": "Ship HP pool. Enemy dies when it hits 0.",
    "max_speed": "Top velocity in pixels/second.",
    "acceleration": "How fast the ship reaches max_speed.",
    "fire_rate": "Shots per second while engaged.",
    "damage": "Damage per projectile.",
    "proj_speed": "Projectile velocity in pixels/second.",
    "ship_size": "Visual + collision radius in pixels.",
    "orbit_distance": "Preferred engagement distance from the player.",
    "color_base": "RGB triplet 0.0–1.0 for the ship's hull color. Format: r, g, b.",
    "shape": "Procedural silhouette: chevron, hex, diamond, ring, arrow.",
    "behavior": "AI archetype: orbit (circle-strafe), ram (charge), sniper (hold distance), skirmish (dodge+shoot).",
    "weapon_type": "Projectile visual: laser, beam, missile, plasma.",
    "min_threat": "Minimum system threat_level at which this enemy can spawn.",
    "weight": "Relative spawn weight in encounter rolls. Higher = more common.",
    "type": "Module category: weapon, shield, engine, reactor, armor, sensor, conduit, cargo, core.",
    "subtype": "Sub-category within the type (e.g. energy/kinetic/missile for weapons).",
    "tier": "Rarity tier: standard, advanced. Advanced paints the name blue in lists.",
    "hex_size": "Number of hex cells this module occupies on the ship grid.",
    "buy_price": "Shop purchase price in credits.",
    "sell_price": "Vendor sell-back price in credits.",
    "stats.power_draw": "Reactor power consumed per tick while active.",
    "stats.damage": "Per-shot damage dealt by this weapon module.",
    "stats.fire_rate": "Shots per second.",
    "stats.range": "Maximum effective range in pixels.",
    "stats.projectile_speed": "Projectile velocity.",
    "stats.thrust": "Linear thrust added to the ship's engines (for engine modules).",
    "stats.shield_hp": "Shield HP pool added (for shield modules).",
    "stats.shield_regen": "Shield HP regenerated per second.",
    "stats.cargo_bonus": "Extra cargo slots provided.",
    "stats.reactor_output": "Power generated per tick (for reactor modules).",
}

const _BUTTON_TIPS: Dictionary = {
    "add": "Create a new entry with default stats. The ID auto-increments.",
    "delete": "Delete the currently selected entry.",
    "save": "Save all edits to disk. Enemies → enemy_classes.json; Modules → starter_modules.json.",
    "add_inv": "Add one of the selected module to the player's live inventory for playtesting.",
    "sel": "Click to select this entry for editing in the property panel on the right.",
}

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _load_data()
    _undo = EditorUndo.new(_capture_state, _apply_state)
    edit_line = LineEdit.new()
    edit_line.visible = false
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.1, 0.1, 0.14)
    sb.border_color = Color(0.4, 0.6, 1.0)
    sb.set_border_width_all(1)
    sb.set_content_margin_all(3)
    edit_line.add_theme_stylebox_override("normal", sb)
    edit_line.add_theme_stylebox_override("focus", sb)
    edit_line.add_theme_color_override("font_color", Color(1, 1, 0.9))
    edit_line.add_theme_font_size_override("font_size", 13)
    add_child(edit_line)
    edit_line.text_submitted.connect(_on_field_submitted)

func refresh():
    _load_data()
    selected_id = ""
    if _undo != null:
        _undo.clear()
    queue_redraw()


func _capture_state() -> Dictionary:
    return {
        "data": data.duplicate(true),
        "selected_id": selected_id,
    }


func _apply_state(snap: Dictionary) -> void:
    var d_v: Variant = snap.get("data", null)
    if typeof(d_v) == TYPE_DICTIONARY:
        data = d_v
    selected_id = str(snap.get("selected_id", ""))

func _load_data():
    var source = DataManager.enemy_classes if editor_mode == "enemies" else DataManager.modules
    data = {}
    for k in source:
        data[k] = source[k].duplicate(true)

func _data_path() -> String:
    if editor_mode == "enemies":
        return "res://Space/data/enemies/enemy_classes.json"
    return "res://Space/data/modules/starter_modules.json"

func _process(delta: float):
    if status_timer > 0:
        status_timer -= delta
        if status_timer <= 0:
            status_text = ""
    if is_visible_in_tree():
        _update_tooltips()
    queue_redraw()


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    for entry in field_rects:
        var r: Rect2 = entry.get("rect", Rect2())
        if r.has_point(mp):
            var key: String = str(entry.get("key", ""))
            var tip: String = str(_FIELD_TIPS.get(key, ""))
            if tip != "":
                EditorTooltip.show_text(tip)
            return
    for entry in button_rects:
        var r: Rect2 = entry.get("rect", Rect2())
        if r.has_point(mp):
            var bid: String = str(entry.get("id", ""))
            var tip: String = str(_BUTTON_TIPS.get(bid, ""))
            if tip == "" and bid.begins_with("sel_"):
                tip = str(_BUTTON_TIPS.get("sel", ""))
            if tip != "":
                EditorTooltip.show_text(tip)
            return

func _draw():
    var font = ThemeDB.fallback_font
    field_rects.clear()
    button_rects.clear()

    var mode_label = "ENEMIES" if editor_mode == "enemies" else "MODULES"


    draw_rect(Rect2(0, 0, LIST_W, size.y), Color(0.06, 0.06, 0.08))
    draw_string(font, Vector2(10, 18), mode_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.75))

    var ey = 28.0 - scroll_list
    for did in data:
        var entry = data[did]
        var r = Rect2(4, ey, LIST_W - 8, 26)
        var sel = (did == selected_id)
        if sel:
            draw_rect(r, Color(0.15, 0.2, 0.3))
        var label = entry.get("name", did)
        draw_string(font, Vector2(10, ey + 18), label, HORIZONTAL_ALIGNMENT_LEFT, int(LIST_W - 20), 12, 
            Color(0.85, 0.85, 0.9) if sel else Color(0.55, 0.55, 0.6))
        button_rects.append({"id": "sel_" + did, "rect": r})
        ey += 28


    var btn_y = size.y - 34
    var ar = Rect2(4, btn_y, 90, 24)
    var dr = Rect2(100, btn_y, 90, 24)

    draw_rect(Rect2(0, btn_y - 4, LIST_W, size.y - btn_y + 4), Color(0.06, 0.06, 0.08))
    draw_rect(ar, Color(0.12, 0.18, 0.12))
    draw_rect(ar, Color(0.3, 0.5, 0.3), false, 1.0)
    draw_string(font, Vector2(14, btn_y + 17), "+ Add", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.85, 0.5))
    button_rects.insert(0, {"id": "add", "rect": ar})
    draw_rect(dr, Color(0.18, 0.1, 0.1))
    draw_rect(dr, Color(0.5, 0.3, 0.3), false, 1.0)
    draw_string(font, Vector2(110, btn_y + 17), "- Delete", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.4, 0.4))
    button_rects.insert(1, {"id": "delete", "rect": dr})


    var px = LIST_W
    var pw = size.x - LIST_W
    draw_rect(Rect2(px, 0, pw, size.y), Color(0.05, 0.05, 0.07))
    draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.15, 0.18, 0.22), 1.0)

    if selected_id == "" or not data.has(selected_id):
        draw_string(font, Vector2(px + 16, 30), "Select an entry", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45))
    else:
        _draw_props(px + 12, font)


    var sr = Rect2(px + 12, size.y - 34, 110, 24)
    draw_rect(sr, Color(0.12, 0.18, 0.25))
    draw_rect(sr, Color(0.3, 0.4, 0.5), false, 1.0)
    draw_string(font, Vector2(px + 22, size.y - 14), "Save to Disk", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.9))
    button_rects.append({"id": "save", "rect": sr})


    if editor_mode == "modules" and selected_id != "" and data.has(selected_id):
        var ir = Rect2(px + 136, size.y - 34, 140, 24)
        draw_rect(ir, Color(0.12, 0.2, 0.12))
        draw_rect(ir, Color(0.3, 0.5, 0.3), false, 1.0)
        draw_string(font, Vector2(px + 146, size.y - 14), "+ To Inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.9, 0.5))
        button_rects.append({"id": "add_inv", "rect": ir})

    if status_text != "":
        draw_string(font, Vector2(px + 16, size.y - 50), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.4))

func _draw_props(x: float, font: Font):
    var entry = data[selected_id]
    var pw = size.x - LIST_W - 24
    var y = 8.0 - scroll_props


    draw_line(Vector2(x, y + 6), Vector2(x + pw, y + 6), Color(0.2, 0.25, 0.3), 1.0)
    draw_string(font, Vector2(x + 4, y + 20), "ID: " + selected_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 1.0))
    y += 28


    for key in entry:
        var val = entry[key]
        if val is Dictionary:

            y += 4
            draw_line(Vector2(x, y + 6), Vector2(x + pw, y + 6), Color(0.18, 0.2, 0.25), 1.0)
            draw_string(font, Vector2(x + 4, y + 20), key.to_upper() + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
            y += 26
            for skey in val:
                y = _draw_field(key + "." + skey, skey, _val_to_str(val[skey]), x, y, font, pw)
        elif val is Array:
            y = _draw_field(key, key, _val_to_str(val), x, y, font, pw)
        else:
            y = _draw_field(key, key, _val_to_str(val), x, y, font, pw)

func _draw_field(key: String, label: String, value: String, x: float, y: float, font: Font, pw: float) -> float:
    var label_w: float = 110.0
    var val_x = x + label_w
    var val_w = pw - label_w - 16
    draw_string(font, Vector2(x + 4, y + 15), label + ":", HORIZONTAL_ALIGNMENT_LEFT, int(label_w - 8), 12, Color(0.5, 0.5, 0.55))
    var vr = Rect2(val_x, y + 1, val_w, 18)
    if not (editing_key == key and edit_line.visible):
        draw_rect(vr, Color(0.1, 0.1, 0.13))
        var display = value
        if display.length() > 50:
            display = display.substr(0, 47) + "..."
        draw_string(font, Vector2(val_x + 4, y + 15), display, HORIZONTAL_ALIGNMENT_LEFT, int(val_w - 8), 12, Color(0.85, 0.85, 0.9))
    field_rects.append({"key": key, "rect": vr, "value": value})
    return y + 22

func _val_to_str(val) -> String:
    if val is float:
        if val == int(val):
            return str(int(val))
        return "%.2f" % val
    if val is Array:
        var parts: Array = []
        for v in val:
            parts.append(_val_to_str(v))
        return ", ".join(parts)
    return str(val)

func _str_to_val(text: String, original):

    if original is int:
        return int(text)
    if original is float:
        return float(text)
    if original is bool:
        return text.to_lower() == "true"
    if original is Array:

        var parts = text.split(",")
        var result: Array = []
        for i in parts.size():
            var p = parts[i].strip_edges()
            if i < original.size():
                result.append(_str_to_val(p, original[i]))
            elif p.is_valid_float():
                result.append(float(p))
            elif p.is_valid_int():
                result.append(int(p))
            else:
                result.append(p)
        return result
    return text



func _input(event):
    if not visible:
        return
    if edit_line != null and edit_line.has_focus():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()


func _gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _handle_click(event.position)
            MOUSE_BUTTON_WHEEL_UP:
                if event.position.x < LIST_W:
                    scroll_list = maxf(scroll_list - 30, 0)
                else:
                    scroll_props = maxf(scroll_props - 30, 0)
                queue_redraw()
                accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                if event.position.x < LIST_W:
                    scroll_list += 30
                else:
                    scroll_props += 30
                queue_redraw()
                accept_event()

func _handle_click(pos: Vector2):
    if edit_line.visible:
        _on_field_submitted(edit_line.text)

    for btn in button_rects:
        if btn.rect.has_point(pos):
            _handle_button(btn.id)
            accept_event()
            return

    for fr in field_rects:
        if fr.rect.has_point(pos):
            editing_key = fr.key
            edit_line.text = fr.value
            edit_line.position = fr.rect.position
            edit_line.size = fr.rect.size
            edit_line.visible = true
            edit_line.grab_focus()
            edit_line.select_all()
            accept_event()
            return

func _handle_button(btn_id: String):
    if btn_id.begins_with("sel_"):
        selected_id = btn_id.replace("sel_", "")
        scroll_props = 0
    elif btn_id == "add":
        _add_entry()
    elif btn_id == "delete":
        _delete_entry()
    elif btn_id == "save":
        _save_data()
    elif btn_id == "add_inv":
        _add_to_inventory()
    queue_redraw()

func _on_field_submitted(text: String):
    if editing_key == "" or selected_id == "" or not data.has(selected_id):
        edit_line.visible = false
        editing_key = ""
        return

    var entry = data[selected_id]
    var key = editing_key
    edit_line.visible = false
    editing_key = ""

    if _undo != null:
        _undo.begin()
    if key.contains("."):

        var parts = key.split(".")
        if entry.has(parts[0]) and entry[parts[0]] is Dictionary:
            var sub = entry[parts[0]]
            if sub.has(parts[1]):
                sub[parts[1]] = _str_to_val(text, sub[parts[1]])
    elif entry.has(key):
        entry[key] = _str_to_val(text, entry[key])
    if _undo != null:
        _undo.commit("edit " + key)

    queue_redraw()



func _add_entry():
    var base = "new_" + editor_mode.rstrip("s")
    var idx = 1
    while data.has(base + "_" + str(idx)):
        idx += 1
    var eid = base + "_" + str(idx)
    if _undo != null:
        _undo.begin()
    if editor_mode == "enemies":
        data[eid] = {
            "name": "New Enemy", 
            "max_health": 40, 
            "max_speed": 200, 
            "acceleration": 400, 
            "fire_rate": 1.0, 
            "damage": 8, 
            "proj_speed": 500, 
            "ship_size": 16, 
            "orbit_distance": 250, 
            "color_base": [1.0, 0.5, 0.3], 
            "shape": "chevron", 
            "behavior": "orbit", 
            "weapon_type": "laser", 
            "min_threat": 1, 
            "weight": 3, 
            "description": "New enemy class."
        }
    else:
        data[eid] = {
            "name": "New Module",
            "type": "weapon",
            "subtype": "energy",
            "tier": "standard",
            "hex_size": 1,
            "stats": {"power_draw": 5},
            "description": "A new module."
        }
    selected_id = eid
    if _undo != null:
        _undo.commit("add " + editor_mode.rstrip("s"))

func _delete_entry():
    if selected_id != "" and data.has(selected_id):
        if _undo != null:
            _undo.begin()
        data.erase(selected_id)
        selected_id = ""
        if _undo != null:
            _undo.commit("delete " + editor_mode.rstrip("s"))

func _add_to_inventory():
    if selected_id == "" or not data.has(selected_id):
        return
    GameManager.add_module(selected_id, 1)
    status_text = "Added " + data[selected_id].get("name", selected_id) + " to inventory"
    status_timer = 2.0

func _save_data():
    if editor_mode == "enemies":
        DataManager.enemy_classes = data.duplicate(true)
    else:
        DataManager.modules = data.duplicate(true)
    var file = FileAccess.open(_data_path(), FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()
        status_text = "Saved!"
        status_timer = 3.0
    else:
        status_text = "ERROR: Could not write!"
        status_timer = 3.0
