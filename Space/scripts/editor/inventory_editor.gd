extends Control

const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")


var scroll_inv: float = 0.0
var scroll_catalog: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0
var selected_mod: String = ""
var view_mode: String = "inventory"

var _undo: RefCounted = null

const LIST_W: float = 280.0

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    return {
        "credits": GameManager.credits,
        "inventory": GameManager.module_inventory.duplicate(true),
    }


func _apply_state(snap: Dictionary) -> void:
    GameManager.credits = int(snap.get("credits", 0))
    var inv_v: Variant = snap.get("inventory", null)
    if typeof(inv_v) == TYPE_DICTIONARY:
        GameManager.module_inventory = inv_v


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()


func refresh():
    scroll_inv = 0.0
    scroll_catalog = 0.0
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
            var tip := _inventory_tip(str(btn.get("id", "")))
            if tip != "":
                EditorTooltip.show_text(tip)
            return


func _inventory_tip(bid: String) -> String:
    if bid == "credits_+100":
        return "Add 100 credits to the player wallet."
    if bid == "credits_-100":
        return "Remove 100 credits from the wallet (floors at 0)."
    if bid == "credits_+1k":
        return "Add 1000 credits."
    if bid == "save_game":
        return "Save the current game state to the active save slot."
    if bid.begins_with("inv_add_"):
        return "Add one more %s to the player's inventory." % _mod_name(bid.substr(8))
    if bid.begins_with("inv_rem_"):
        return "Remove one %s from the player's inventory." % _mod_name(bid.substr(8))
    if bid.begins_with("cat_add_"):
        return "Add %s to the player's inventory (creates the entry if missing)." % _mod_name(bid.substr(8))
    return ""

func _draw():
    var font = ThemeDB.fallback_font
    var pw = size.x
    var ph = size.y


    draw_rect(Rect2(0, 0, LIST_W, ph), Color(0.06, 0.06, 0.08))
    draw_string(font, Vector2(10, 18), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.75))


    var cy = 30.0
    draw_string(font, Vector2(10, cy + 14), "Credits:", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.65))
    draw_string(font, Vector2(80, cy + 14), str(GameManager.credits), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.82, 0.2))


    var btn_rects: Array = []
    var bx = 150.0
    for label in ["+100", "-100", "+1k"]:
        var br = Rect2(bx, cy, 42, 18)
        draw_rect(br, Color(0.12, 0.15, 0.2))
        draw_rect(br, Color(0.25, 0.3, 0.4), false, 1.0)
        draw_string(font, Vector2(bx + 4, cy + 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.8, 0.9))
        btn_rects.append({"id": "credits_" + label, "rect": br})
        bx += 44

    cy += 26
    draw_line(Vector2(4, cy), Vector2(LIST_W - 4, cy), Color(0.15, 0.18, 0.22), 1.0)
    cy += 4


    var iy = cy - scroll_inv
    var inv = GameManager.module_inventory
    if inv.is_empty():
        draw_string(font, Vector2(10, iy + 14), "(empty)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))
    else:
        for mod_id in inv:
            if iy > -30 and iy < ph:
                var count: int = inv[mod_id]
                var mod_data = DataManager.modules.get(mod_id, {})
                var mod_name = mod_data.get("name", mod_id)
                var mod_type = mod_data.get("type", "")
                var _sell_price = int(mod_data.get("sell_price", 0))

                var r = Rect2(4, iy, LIST_W - 8, 28)
                var sel = (mod_id == selected_mod and view_mode == "inventory")
                if sel:
                    draw_rect(r, Color(0.15, 0.2, 0.3))


                var tc = _type_color(mod_type)
                draw_rect(Rect2(8, iy + 8, 6, 12), tc)

                draw_string(font, Vector2(18, iy + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(LIST_W - 120), 12, 
                    Color(0.85, 0.85, 0.9) if sel else Color(0.6, 0.6, 0.65))
                draw_string(font, Vector2(LIST_W - 100, iy + 18), "x" + str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.8))


                var plus_r = Rect2(LIST_W - 60, iy + 4, 22, 20)
                var minus_r = Rect2(LIST_W - 34, iy + 4, 22, 20)
                draw_rect(plus_r, Color(0.1, 0.18, 0.1))
                draw_string(font, Vector2(LIST_W - 55, iy + 18), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.5))
                draw_rect(minus_r, Color(0.18, 0.1, 0.1))
                draw_string(font, Vector2(LIST_W - 29, iy + 18), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.4, 0.4))
                btn_rects.append({"id": "inv_add_" + mod_id, "rect": plus_r})
                btn_rects.append({"id": "inv_rem_" + mod_id, "rect": minus_r})

            iy += 30


    var rx = LIST_W
    var rw = pw - LIST_W
    draw_rect(Rect2(rx, 0, rw, ph), Color(0.05, 0.05, 0.07))
    draw_line(Vector2(rx, 0), Vector2(rx, ph), Color(0.15, 0.18, 0.22), 1.0)
    draw_string(font, Vector2(rx + 10, 18), "ALL MODULES (click to add)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.75))

    var my = 28.0 - scroll_catalog
    var all_mods = DataManager.modules
    for mod_id in all_mods:
        var mod_data = all_mods[mod_id]
        if my > -30 and my < ph:
            var mod_name = mod_data.get("name", mod_id)
            var mod_type = mod_data.get("type", "")
            var tier = mod_data.get("tier", "standard")
            var buy_price = int(mod_data.get("buy_price", 0))
            var sell_price = int(mod_data.get("sell_price", 0))

            var r = Rect2(rx + 4, my, rw - 8, 26)
            btn_rects.append({"id": "cat_add_" + mod_id, "rect": r})

            var tc = _type_color(mod_type)
            draw_rect(Rect2(rx + 8, my + 6, 6, 14), tc)

            var tier_col = Color(0.5, 0.5, 0.55) if tier == "standard" else Color(0.4, 0.65, 1.0)
            draw_string(font, Vector2(rx + 18, my + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(rw * 0.45), 12, tier_col)
            draw_string(font, Vector2(rx + rw * 0.5, my + 18), mod_type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.4, 0.45))
            draw_string(font, Vector2(rx + rw * 0.7, my + 18), "Buy:" + str(buy_price), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.3))
            draw_string(font, Vector2(rx + rw * 0.85, my + 18), "Sell:" + str(sell_price), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.6, 0.4))

        my += 28


    if status_text != "":
        draw_rect(Rect2(0, ph - 28, pw, 28), Color(0.05, 0.08, 0.05))
        draw_string(font, Vector2(10, ph - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.4))

    var save_r = Rect2(pw - 130, ph - 26, 120, 22)
    draw_rect(save_r, Color(0.12, 0.18, 0.25))
    draw_rect(save_r, Color(0.3, 0.4, 0.5), false, 1.0)
    draw_string(font, Vector2(pw - 118, ph - 9), "Save Game", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.9))
    btn_rects.append({"id": "save_game", "rect": save_r})

    set_meta("btn_rects", btn_rects)

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
                if event.position.x < LIST_W:
                    scroll_inv = maxf(scroll_inv - 30, 0)
                else:
                    scroll_catalog = maxf(scroll_catalog - 30, 0)
                accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                if event.position.x < LIST_W:
                    scroll_inv += 30
                else:
                    scroll_catalog += 30
                accept_event()

func _handle_click(pos: Vector2):
    var btn_rects: Array = get_meta("btn_rects", [])
    for btn in btn_rects:
        if btn.rect.has_point(pos):
            _handle_button(btn.id)
            return

func _handle_button(btn_id: String):
    if btn_id == "credits_+100":
        if _undo != null:
            _undo.begin()
        GameManager.credits += 100
        _status("Added 100 credits")
        if _undo != null:
            _undo.commit("+100 credits")
    elif btn_id == "credits_-100":
        if _undo != null:
            _undo.begin()
        GameManager.credits = maxi(GameManager.credits - 100, 0)
        _status("Removed 100 credits")
        if _undo != null:
            _undo.commit("-100 credits")
    elif btn_id == "credits_+1k":
        if _undo != null:
            _undo.begin()
        GameManager.credits += 1000
        _status("Added 1000 credits")
        if _undo != null:
            _undo.commit("+1000 credits")
    elif btn_id.begins_with("inv_add_"):
        var mod_id = btn_id.replace("inv_add_", "")
        if _undo != null:
            _undo.begin()
        GameManager.add_module(mod_id)
        _status("Added " + _mod_name(mod_id))
        if _undo != null:
            _undo.commit("add module")
    elif btn_id.begins_with("inv_rem_"):
        var mod_id = btn_id.replace("inv_rem_", "")
        if _undo != null:
            _undo.begin()
        if GameManager.remove_module(mod_id):
            _status("Removed " + _mod_name(mod_id))
            if _undo != null:
                _undo.commit("remove module")
        else:
            _status("Cannot remove (none left)")
            if _undo != null:
                _undo.discard()
    elif btn_id.begins_with("cat_add_"):
        var mod_id = btn_id.replace("cat_add_", "")
        if _undo != null:
            _undo.begin()
        GameManager.add_module(mod_id)
        _status("Added " + _mod_name(mod_id) + " to inventory")
        if _undo != null:
            _undo.commit("add module from catalog")
    elif btn_id == "save_game":
        if GameManager.save_game():
            _status("Game saved! (slot %d)" % GameManager.current_save_slot)
        else:
            _status("ERROR: Save failed!")

func _mod_name(mod_id: String) -> String:
    return DataManager.modules.get(mod_id, {}).get("name", mod_id)

func _status(text: String):
    status_text = text
    status_timer = 2.5
