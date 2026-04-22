extends Control

const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")


var scroll_y: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0
var selected_threat: String = "1"
var view_mode: String = "loot"
var selected_system: String = ""

var _undo: RefCounted = null

const TAB_H: float = 32.0
const LIST_W: float = 180.0

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    return {"loot_data": DataManager.loot_data.duplicate(true)}


func _apply_state(snap: Dictionary) -> void:
    var ld_v: Variant = snap.get("loot_data", null)
    if typeof(ld_v) == TYPE_DICTIONARY:
        DataManager.loot_data = ld_v


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()

func refresh():
    scroll_y = 0.0
    if _undo != null:
        _undo.clear()
    queue_redraw()

func _process(delta: float):
    if status_timer > 0:
        status_timer -= delta
        if status_timer <= 0:
            status_text = ""
    if is_visible_in_tree():
        _update_tooltips()
    queue_redraw()


func _update_tooltips() -> void:
    var rects: Array = get_meta("btn_rects", [])
    var mp := get_local_mouse_position()
    for btn in rects:
        var r: Rect2 = btn.get("rect", Rect2())
        if r.has_point(mp):
            var tip := _loot_tip(str(btn.get("id", "")))
            if tip != "":
                EditorTooltip.show_text(tip)
            return


func _loot_tip(bid: String) -> String:
    if bid == "tab_loot":
        return "Loot tables — what modules drop from enemies at each threat level."
    if bid == "tab_shops":
        return "Shop stock — which modules each system's shop carries and at what price."
    if bid == "save":
        return "Save loot tables and shop stock to disk."
    if bid.begins_with("threat_"):
        return "Edit the drop table for threat level %s. Higher threats use this tier's weights." % bid.substr(7)
    if bid.begins_with("sys_"):
        return "Edit the shop stock for this system."
    if bid.begins_with("wt_up_"):
        return "Increase this entry's drop weight (more likely to roll from the table)."
    if bid.begins_with("wt_dn_"):
        return "Decrease this entry's drop weight (minimum 1)."
    if bid.begins_with("del_"):
        return "Remove this entry from the current threat table."
    if bid.begins_with("add_"):
        return "Add this module to the current threat table with weight 1."
    if bid.begins_with("shop_del_"):
        return "Remove this module from the system's shop stock."
    if bid.begins_with("shop_add_"):
        return "Add this module to the system's shop stock."
    return ""

func _draw():
    var font = ThemeDB.fallback_font
    var pw = size.x
    var ph = size.y
    var btn_rects: Array = []


    var loot_r = Rect2(4, 4, 120, 24)
    var shop_r = Rect2(128, 4, 120, 24)
    draw_rect(loot_r, Color(0.18, 0.22, 0.3) if view_mode == "loot" else Color(0.08, 0.08, 0.1))
    draw_string(font, Vector2(14, 22), "Loot Tables", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 
        Color(0.9, 0.9, 0.95) if view_mode == "loot" else Color(0.45, 0.45, 0.5))
    btn_rects.append({"id": "tab_loot", "rect": loot_r})
    draw_rect(shop_r, Color(0.18, 0.22, 0.3) if view_mode == "shops" else Color(0.08, 0.08, 0.1))
    draw_string(font, Vector2(138, 22), "Shop Stock", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 
        Color(0.9, 0.9, 0.95) if view_mode == "shops" else Color(0.45, 0.45, 0.5))
    btn_rects.append({"id": "tab_shops", "rect": shop_r})

    var top_y = TAB_H + 4

    if view_mode == "loot":
        _draw_loot_tables(top_y, font, btn_rects)
    else:
        _draw_shop_stock(top_y, font, btn_rects)


    var sr = Rect2(pw - 130, ph - 34, 120, 24)
    draw_rect(sr, Color(0.12, 0.18, 0.25))
    draw_rect(sr, Color(0.3, 0.4, 0.5), false, 1.0)
    draw_string(font, Vector2(pw - 120, ph - 14), "Save to Disk", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.9))
    btn_rects.append({"id": "save", "rect": sr})

    if status_text != "":
        draw_string(font, Vector2(10, ph - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.4))

    set_meta("btn_rects", btn_rects)

func _draw_loot_tables(top_y: float, font: Font, btn_rects: Array):
    var pw = size.x
    var ph = size.y
    var loot = DataManager.loot_data


    draw_rect(Rect2(0, top_y, LIST_W, ph - top_y), Color(0.06, 0.06, 0.08))
    draw_string(font, Vector2(10, top_y + 16), "THREAT LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))


    var dcy = top_y + 24
    var base = loot.get("drop_chance_base", 0.25)
    var per = loot.get("drop_chance_per_threat", 0.05)
    draw_string(font, Vector2(10, dcy + 14), "Base: %.0f%%" % (base * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))
    draw_string(font, Vector2(90, dcy + 14), "+%.0f%%/lvl" % (per * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))
    dcy += 22

    for i in 5:
        var key = str(i + 1)
        var r = Rect2(4, dcy, LIST_W - 8, 26)
        var sel = (key == selected_threat)
        if sel:
            draw_rect(r, Color(0.15, 0.2, 0.3))
        @warning_ignore("confusable_local_declaration")
        var table = loot.get("tables", {}).get(key, [])
        draw_string(font, Vector2(10, dcy + 18), "Threat " + key + " (" + str(table.size()) + " items)", 
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9) if sel else Color(0.55, 0.55, 0.6))
        btn_rects.append({"id": "threat_" + key, "rect": r})
        dcy += 28


    var rx = LIST_W
    var rw = pw - LIST_W
    draw_rect(Rect2(rx, top_y, rw, ph - top_y), Color(0.05, 0.05, 0.07))
    draw_line(Vector2(rx, top_y), Vector2(rx, ph), Color(0.15, 0.18, 0.22), 1.0)

    var tables = loot.get("tables", {})
    var table: Array = tables.get(selected_threat, [])
    draw_string(font, Vector2(rx + 10, top_y + 16), "THREAT " + selected_threat + " DROPS", 
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))

    var ey = top_y + 26.0 - scroll_y
    for idx in table.size():
        var entry = table[idx]
        var mod_id: String = entry.get("id", "")
        var weight = entry.get("weight", 1)
        var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
        var mod_type = DataManager.modules.get(mod_id, {}).get("type", "")

        if ey > top_y - 30 and ey < ph:
            var tc = _type_color(mod_type)
            draw_rect(Rect2(rx + 8, ey + 6, 6, 14), tc)
            draw_string(font, Vector2(rx + 18, ey + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(rw * 0.5), 12, Color(0.7, 0.7, 0.75))
            if not DataManager.modules.has(mod_id):
                _draw_warning(rx + rw * 0.42, ey + 18, font)
            draw_string(font, Vector2(rx + rw * 0.55, ey + 18), "W:" + str(weight), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.3))


            var wp = Rect2(rx + rw * 0.7, ey + 2, 22, 20)
            var wm = Rect2(rx + rw * 0.7 + 24, ey + 2, 22, 20)
            draw_rect(wp, Color(0.1, 0.18, 0.1))
            draw_string(font, Vector2(rx + rw * 0.7 + 5, ey + 16), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.5))
            draw_rect(wm, Color(0.18, 0.1, 0.1))
            draw_string(font, Vector2(rx + rw * 0.7 + 29, ey + 16), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.4, 0.4))
            btn_rects.append({"id": "wt_up_%s_%d" % [selected_threat, idx], "rect": wp})
            btn_rects.append({"id": "wt_dn_%s_%d" % [selected_threat, idx], "rect": wm})


            var del_r = Rect2(rx + rw - 56, ey + 2, 44, 20)
            draw_rect(del_r, Color(0.18, 0.08, 0.08))
            draw_string(font, Vector2(rx + rw - 50, ey + 16), "DEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.3, 0.3))
            btn_rects.append({"id": "del_%s_%d" % [selected_threat, idx], "rect": del_r})

        ey += 28


    ey += 8
    draw_line(Vector2(rx + 4, ey), Vector2(rx + rw - 4, ey), Color(0.2, 0.22, 0.28), 1.0)
    ey += 4
    draw_string(font, Vector2(rx + 10, ey + 14), "Add module:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
    ey += 20

    var existing_ids: Array = []
    for e in table:
        existing_ids.append(e.get("id", ""))

    for mod_id in DataManager.modules:
        if mod_id in existing_ids:
            continue
        var mod_data = DataManager.modules[mod_id]
        if mod_data.get("type", "") == "core":
            continue
        if ey > top_y - 30 and ey < ph:
            var r = Rect2(rx + 4, ey, rw - 8, 22)
            var mod_name = mod_data.get("name", mod_id)
            draw_string(font, Vector2(rx + 18, ey + 15), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(rw * 0.6), 11, Color(0.45, 0.5, 0.55))
            btn_rects.append({"id": "add_%s_%s" % [selected_threat, mod_id], "rect": r})
        ey += 24

func _draw_shop_stock(top_y: float, font: Font, btn_rects: Array):
    var pw = size.x
    var ph = size.y
    var shop_stock = DataManager.loot_data.get("shop_stock", {})


    draw_rect(Rect2(0, top_y, LIST_W, ph - top_y), Color(0.06, 0.06, 0.08))
    draw_string(font, Vector2(10, top_y + 16), "SYSTEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))

    var sy = top_y + 24.0
    for sys_id in DataManager.systems:
        var sys_data = DataManager.systems[sys_id]
        @warning_ignore("confusable_local_declaration")
        var sys_name = sys_data.get("name", sys_id)
        var r = Rect2(4, sy, LIST_W - 8, 26)
        var sel = (sys_id == selected_system)
        if sel:
            draw_rect(r, Color(0.15, 0.2, 0.3))
        @warning_ignore("confusable_local_declaration")
        var stock: Array = shop_stock.get(sys_id, [])
        draw_string(font, Vector2(10, sy + 18), sys_name + " (" + str(stock.size()) + ")", 
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9) if sel else Color(0.55, 0.55, 0.6))
        btn_rects.append({"id": "sys_" + sys_id, "rect": r})
        sy += 28


    var rx = LIST_W
    var rw = pw - LIST_W
    draw_rect(Rect2(rx, top_y, rw, ph - top_y), Color(0.05, 0.05, 0.07))
    draw_line(Vector2(rx, top_y), Vector2(rx, ph), Color(0.15, 0.18, 0.22), 1.0)

    if selected_system == "":
        draw_string(font, Vector2(rx + 16, top_y + 30), "Select a system", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45))
        return

    var stock: Array = shop_stock.get(selected_system, [])
    var sys_name = DataManager.systems.get(selected_system, {}).get("name", selected_system)
    draw_string(font, Vector2(rx + 10, top_y + 16), sys_name + " SHOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))

    var ey = top_y + 26.0 - scroll_y
    for idx in stock.size():
        var mod_id: String = stock[idx]
        var mod_data = DataManager.modules.get(mod_id, {})
        var mod_name = mod_data.get("name", mod_id)
        var buy_price = int(mod_data.get("buy_price", 0))

        if ey > top_y - 30 and ey < ph:
            var tc = _type_color(mod_data.get("type", ""))
            draw_rect(Rect2(rx + 8, ey + 6, 6, 14), tc)
            draw_string(font, Vector2(rx + 18, ey + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(rw * 0.5), 12, Color(0.7, 0.7, 0.75))
            if not DataManager.modules.has(mod_id):
                _draw_warning(rx + rw * 0.42, ey + 18, font)
            draw_string(font, Vector2(rx + rw * 0.55, ey + 18), str(buy_price) + "cr", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.3))

            var del_r = Rect2(rx + rw - 56, ey + 2, 44, 20)
            draw_rect(del_r, Color(0.18, 0.08, 0.08))
            draw_string(font, Vector2(rx + rw - 50, ey + 16), "DEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.3, 0.3))
            btn_rects.append({"id": "shop_del_%s_%d" % [selected_system, idx], "rect": del_r})

        ey += 28


    ey += 8
    draw_line(Vector2(rx + 4, ey), Vector2(rx + rw - 4, ey), Color(0.2, 0.22, 0.28), 1.0)
    ey += 4
    draw_string(font, Vector2(rx + 10, ey + 14), "Add to shop:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
    ey += 20

    for mod_id in DataManager.modules:
        if mod_id in stock:
            continue
        var mod_data = DataManager.modules[mod_id]
        if mod_data.get("type", "") == "core":
            continue
        if ey > top_y - 30 and ey < ph:
            var r = Rect2(rx + 4, ey, rw - 8, 22)
            var mod_name = mod_data.get("name", mod_id)
            var buy_price = int(mod_data.get("buy_price", 0))
            draw_string(font, Vector2(rx + 18, ey + 15), mod_name + " (" + str(buy_price) + "cr)", 
                HORIZONTAL_ALIGNMENT_LEFT, int(rw * 0.7), 11, Color(0.45, 0.5, 0.55))
            btn_rects.append({"id": "shop_add_%s_%s" % [selected_system, mod_id], "rect": r})
        ey += 24

func _type_color(t: String) -> Color:
    match t:
        "weapon": return Color(0.9, 0.3, 0.25)
        "shield": return Color(0.3, 0.5, 1.0)
        "engine": return Color(1.0, 0.6, 0.2)
        "reactor": return Color(0.95, 0.82, 0.2)
        "armor": return Color(0.5, 0.55, 0.6)
        "sensor": return Color(0.25, 0.85, 0.45)
        "conduit": return Color(0.6, 0.5, 0.2)
        "cargo": return Color(0.6, 0.45, 0.3)
    return Color(0.4, 0.4, 0.4)

func _gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _handle_click(event.position)
                accept_event()
            MOUSE_BUTTON_WHEEL_UP:
                scroll_y = maxf(scroll_y - 30, 0)
                accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                scroll_y += 30
                accept_event()

func _handle_click(pos: Vector2):
    var btn_rects: Array = get_meta("btn_rects", [])
    for btn in btn_rects:
        if btn.rect.has_point(pos):
            _handle_button(btn.id)
            return

func _handle_button(btn_id: String):
    var loot = DataManager.loot_data
    var tables = loot.get("tables", {})
    var shop_stock = loot.get("shop_stock", {})

    if btn_id == "tab_loot":
        view_mode = "loot"
        scroll_y = 0
    elif btn_id == "tab_shops":
        view_mode = "shops"
        scroll_y = 0
    elif btn_id.begins_with("threat_"):
        selected_threat = btn_id.replace("threat_", "")
        scroll_y = 0
    elif btn_id.begins_with("sys_"):
        selected_system = btn_id.replace("sys_", "")
        scroll_y = 0
    elif btn_id.begins_with("wt_up_"):
        var parts = btn_id.replace("wt_up_", "").split("_")
        var t = parts[0]
        var idx = int(parts[1])
        if tables.has(t) and idx < tables[t].size():
            if _undo != null:
                _undo.begin()
            tables[t][idx]["weight"] = int(tables[t][idx].get("weight", 1)) + 1
            if _undo != null:
                _undo.commit("weight +1")
    elif btn_id.begins_with("wt_dn_"):
        var parts = btn_id.replace("wt_dn_", "").split("_")
        var t = parts[0]
        var idx = int(parts[1])
        if tables.has(t) and idx < tables[t].size():
            if _undo != null:
                _undo.begin()
            tables[t][idx]["weight"] = maxi(int(tables[t][idx].get("weight", 1)) - 1, 1)
            if _undo != null:
                _undo.commit("weight -1")
    elif btn_id.begins_with("del_"):
        var parts = btn_id.replace("del_", "").split("_")
        var t = parts[0]
        var idx = int(parts[1])
        if tables.has(t) and idx < tables[t].size():
            if _undo != null:
                _undo.begin()
            tables[t].remove_at(idx)
            _status("Removed entry")
            if _undo != null:
                _undo.commit("remove loot entry")
    elif btn_id.begins_with("add_"):
        var rest = btn_id.substr(4)
        var sep = rest.find("_")
        var t = rest.substr(0, sep)
        var mod_id = rest.substr(sep + 1)
        if _undo != null:
            _undo.begin()
        if not tables.has(t):
            tables[t] = []
        tables[t].append({"id": mod_id, "weight": 1})
        _status("Added " + _mod_name(mod_id))
        if _undo != null:
            _undo.commit("add loot entry")
    elif btn_id.begins_with("shop_del_"):
        var rest = btn_id.replace("shop_del_", "")
        var last_sep = rest.rfind("_")
        var sys_id = rest.substr(0, last_sep)
        var idx = int(rest.substr(last_sep + 1))
        if shop_stock.has(sys_id) and idx < shop_stock[sys_id].size():
            if _undo != null:
                _undo.begin()
            shop_stock[sys_id].remove_at(idx)
            _status("Removed from shop")
            if _undo != null:
                _undo.commit("remove shop entry")
    elif btn_id.begins_with("shop_add_"):
        var rest = btn_id.replace("shop_add_", "")
        var sep = rest.find("_")
        var sys_id = rest.substr(0, sep)
        var mod_id = rest.substr(sep + 1)
        if _undo != null:
            _undo.begin()
        if not shop_stock.has(sys_id):
            shop_stock[sys_id] = []
        shop_stock[sys_id].append(mod_id)
        _status("Added " + _mod_name(mod_id) + " to shop")
        if _undo != null:
            _undo.commit("add shop entry")
    elif btn_id == "save":
        _save_data()

func _save_data():
    var file = FileAccess.open("res://Space/data/loot/loot_tables.json", FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(DataManager.loot_data, "\t"))
        file.close()
        _status("Saved!")
    else:
        _status("ERROR: Could not write!")

func _mod_name(mod_id: String) -> String:
    return DataManager.modules.get(mod_id, {}).get("name", mod_id)

func _draw_warning(x: float, y: float, font: Font):
    draw_string(font, Vector2(x, y), "!MISSING", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.3, 0.2))

func _status(text: String):
    status_text = text
    status_timer = 2.5
