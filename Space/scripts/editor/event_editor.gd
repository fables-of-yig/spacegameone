extends Control

const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")
const PackAssetIndex = preload("res://Space/scripts/editor/pack_asset_index.gd")


var events: Dictionary = {}
var selected_event: String = ""
var selected_node: String = ""
var selected_choice: int = -1
var scroll_left: float = 0.0
var scroll_center: float = 0.0
var scroll_right: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0

var edit_line: LineEdit = null
var editing_key: String = ""
var field_rects: Array = []
var button_rects: Array = []

var selected_effect: int = -1
var effect_context: String = ""
var type_picker_open: bool = false
var type_picker_scroll: float = 0.0
var speaker_picker_open: bool = false
var speaker_picker_scroll: float = 0.0
var _speaker_ids: Array = []

var _undo: RefCounted = null

const LIST_W: float = 220.0
const PANEL_W: float = 380.0
const TOOLBAR_H: float = 32.0

const _FIELD_TIPS: Dictionary = {
    "node_speaker": "Speaker name shown above the dialogue text. Use one of the portrait ids from Portraits/manifest.json or pick from the imported portrait list.",
    "node_text": "Dialogue text displayed when the player arrives at this node. Supports multi-line — use \\n for breaks.",
    "choice_label": "Button label shown to the player for this choice.",
    "choice_next": "Target node id jumped to when this choice is picked. Leave empty to end the event after this choice's effects fire.",
}

const _EFF_FIELD_TIPS: Dictionary = {
    "type": "Effect type. Click to open the type picker. Each type has its own parameter schema.",
    "amount": "Numeric amount for this effect (credits, hull damage, resource count, etc. depending on type).",
    "module_id": "Module ID from the Modules tab. Red ! warning = module doesn't exist.",
    "count": "Quantity to grant.",
    "resource": "Resource name (e.g. iron, scrap, nanites).",
    "event_id": "Event ID to queue or reference. Red ! warning = event doesn't exist in this pack.",
    "min": "Range minimum.",
    "max": "Range maximum.",
    "delay_min": "Minimum delay in seconds before the queued event fires.",
    "delay_max": "Maximum delay in seconds before the queued event fires. Actual delay is random in [min, max].",
    "tag": "Tag/flag name to set.",
    "value": "Value to assign. Booleans accept true/false; integers are parsed as ints.",
    "flag": "Encounter flag name (scoped to the current encounter).",
    "distance": "Spawn distance from the player ship in pixels.",
    "angle": "Spawn angle in degrees relative to the player (0 = east, 90 = south).",
    "name": "NPC display name.",
    "faction": "Faction id from galaxy_data.json. Drives color and default hostility.",
    "npc_type": "NPC archetype: patrol, guard, trader, wanderer.",
    "hostile": "true = attacks on sight; false = passive.",
    "role": "Crew role (e.g. medic, engineer, pilot).",
    "price": "Cost in credits.",
    "min_dist": "Minimum spawn distance from the player.",
    "max_dist": "Maximum spawn distance from the player.",
}

const _BUTTON_TIPS: Dictionary = {
    "add_event": "Create a new event graph.",
    "del_event": "Delete the selected event.",
    "sel_event": "Click to select this event for editing.",
    "save": "Save all events to disk.",
    "add_node": "Add a new dialogue node to this event graph.",
    "del_node": "Delete the selected node.",
    "sel_node": "Click to select this node; shows its speaker/text and choices in the center panel.",
    "add_choice": "Add a new choice to the selected node.",
    "del_choice": "Delete the selected choice.",
    "sel_choice": "Click to select this choice; shows its label/target and effect list on the right.",
    "add_eff": "Add an effect to this context (on-enter, on-choose, etc.). Opens the effect type picker.",
    "sel_eff": "Click to select this effect for editing.",
    "del_eff": "Remove this effect from the context.",
    "pick_type": "Select this effect type. Applies to the effect being created/edited.",
}

const EFFECT_SCHEMA: Dictionary = {
    "repair": [{"key": "amount", "type": "float", "default": 50}],
    "give_credits": [{"key": "amount", "type": "int", "default": 100}],
    "give_fuel": [{"key": "amount", "type": "float", "default": 10}],
    "damage_hull": [{"key": "amount", "type": "float", "default": 20}],
    "take_credits": [{"key": "amount", "type": "int", "default": 50}],
    "take_fuel": [{"key": "amount", "type": "float", "default": 10}],
    "give_module": [{"key": "module_id", "type": "string", "default": ""}, {"key": "count", "type": "int", "default": 1}],
    "give_resource": [{"key": "resource", "type": "string", "default": ""}, {"key": "amount", "type": "int", "default": 5}],
    "take_resource": [{"key": "resource", "type": "string", "default": ""}, {"key": "amount", "type": "int", "default": 5}],
    "give_resource_random": [{"key": "min", "type": "int", "default": 3}, {"key": "max", "type": "int", "default": 8}],
    "spawn_enemies": [{"key": "count", "type": "int", "default": 3}, {"key": "min_dist", "type": "float", "default": 200}, {"key": "max_dist", "type": "float", "default": 400}],
    "spawn_encounter_ship": [{"key": "distance", "type": "float", "default": 400}, {"key": "angle", "type": "float", "default": 0}, {"key": "name", "type": "string", "default": ""}, {"key": "faction", "type": "string", "default": ""}, {"key": "npc_type", "type": "string", "default": "patrol"}, {"key": "hostile", "type": "bool", "default": true}],
    "set_tag": [{"key": "tag", "type": "string", "default": ""}, {"key": "value", "type": "bool", "default": true}],
    "encounter_flag": [{"key": "flag", "type": "string", "default": ""}],
    "clear_encounter_flag": [{"key": "flag", "type": "string", "default": ""}],
    "queue_event": [{"key": "event_id", "type": "string", "default": ""}, {"key": "delay_min", "type": "float", "default": 60}, {"key": "delay_max", "type": "float", "default": 180}],
    "buy_npc_cargo": [{"key": "price", "type": "int", "default": 100}],
    "reputation_change": [{"key": "faction", "type": "string", "default": ""}, {"key": "amount", "type": "float", "default": 10}],
    "dock_station": [],
    "fire_triggers": [],
    "open_shop": [],
    "open_missions": [],
    "enter_station": [],
    "give_crew": [{"key": "role", "type": "string", "default": ""}],
}

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _load_events()
    _refresh_speaker_ids()
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
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    return {
        "events": events.duplicate(true),
        "selected_event": selected_event,
        "selected_node": selected_node,
        "selected_choice": selected_choice,
        "selected_effect": selected_effect,
        "effect_context": effect_context,
    }


func _apply_state(snap: Dictionary) -> void:
    var e_v: Variant = snap.get("events", null)
    if typeof(e_v) == TYPE_DICTIONARY:
        events = e_v
    selected_event = str(snap.get("selected_event", ""))
    selected_node = str(snap.get("selected_node", ""))
    selected_choice = int(snap.get("selected_choice", -1))
    selected_effect = int(snap.get("selected_effect", -1))
    effect_context = str(snap.get("effect_context", ""))


func _input(event):
    if not visible:
        return
    if edit_line != null and edit_line.has_focus():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()


func refresh():
    _load_events()
    selected_event = ""
    selected_node = ""
    if _undo != null:
        _undo.clear()
    queue_redraw()

func _load_events():
    events = {}
    for eid in DataManager.events:
        events[eid] = DataManager.events[eid].duplicate(true)

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
            var tip := _event_field_tip(str(entry.get("key", "")))
            if tip != "":
                EditorTooltip.show_text(tip)
            return
    for entry in button_rects:
        var r: Rect2 = entry.get("rect", Rect2())
        if r.has_point(mp):
            var tip := _event_button_tip(str(entry.get("id", "")))
            if tip != "":
                EditorTooltip.show_text(tip)
            return


func _event_field_tip(key: String) -> String:
    if _FIELD_TIPS.has(key):
        return str(_FIELD_TIPS[key])
    # Effect param keys have the form "eff_<context>_<param>" where <param>
    # may be multi-token (e.g. "module_id", "min_dist"). Match by trying the
    # last token, then the last two tokens.
    if key.begins_with("eff_"):
        var parts := key.split("_")
        if parts.size() >= 3:
            var last1: String = str(parts[parts.size() - 1])
            if parts.size() >= 4:
                var last2: String = str(parts[parts.size() - 2]) + "_" + last1
                if _EFF_FIELD_TIPS.has(last2):
                    return str(_EFF_FIELD_TIPS[last2])
            if _EFF_FIELD_TIPS.has(last1):
                return str(_EFF_FIELD_TIPS[last1])
    return ""


func _event_button_tip(bid: String) -> String:
    if _BUTTON_TIPS.has(bid):
        return str(_BUTTON_TIPS[bid])
    # Longest-prefix match for dynamic ids like sel_event_<id>, sel_eff_<ctx>_<idx>.
    var best := ""
    for k in _BUTTON_TIPS.keys():
        var ks := str(k)
        if bid.begins_with(ks + "_") and ks.length() > best.length():
            best = ks
    if best != "":
        return str(_BUTTON_TIPS[best])
    return ""

func _draw():
    var font = ThemeDB.fallback_font
    field_rects.clear()
    button_rects.clear()


    draw_rect(Rect2(0, 0, LIST_W, size.y), Color(0.06, 0.06, 0.08))


    draw_rect(Rect2(0, 0, LIST_W, TOOLBAR_H), Color(0.08, 0.09, 0.12))
    draw_string(font, Vector2(8, 20), "EVENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.75))

    var add_r = Rect2(LIST_W - 100, 4, 46, TOOLBAR_H - 8)
    draw_rect(add_r, Color(0.15, 0.22, 0.15))
    draw_rect(add_r, Color(0.3, 0.5, 0.3), false, 1.0)
    draw_string(font, Vector2(LIST_W - 92, 21), "+ Add", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.9, 0.5))
    button_rects.append({"id": "add_event", "rect": add_r})

    var del_r = Rect2(LIST_W - 50, 4, 46, TOOLBAR_H - 8)
    draw_rect(del_r, Color(0.22, 0.12, 0.12))
    draw_rect(del_r, Color(0.5, 0.3, 0.3), false, 1.0)
    draw_string(font, Vector2(LIST_W - 44, 21), "- Del", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.4, 0.4))
    button_rects.append({"id": "del_event", "rect": del_r})


    var ey = TOOLBAR_H + 4.0 - scroll_left
    for eid in events:
        var r = Rect2(4, ey, LIST_W - 8, 24)
        if ey + 24 > TOOLBAR_H and ey < size.y:
            var sel = (eid == selected_event)
            if sel:
                draw_rect(r, Color(0.15, 0.2, 0.3))
            draw_string(font, Vector2(10, ey + 17), events[eid].get("title", eid), HORIZONTAL_ALIGNMENT_LEFT, int(LIST_W - 20), 12, 
                Color(0.85, 0.85, 0.9) if sel else Color(0.55, 0.55, 0.6))
        button_rects.append({"id": "sel_event_" + eid, "rect": r})
        ey += 26


    var cx = LIST_W
    var cw = size.x - LIST_W - PANEL_W
    draw_rect(Rect2(cx, 0, cw, size.y), Color(0.04, 0.04, 0.06))
    draw_line(Vector2(cx, 0), Vector2(cx, size.y), Color(0.15, 0.18, 0.22), 1.0)

    if selected_event != "" and events.has(selected_event):
        _draw_node_flow(cx, cw, font)


    var px = size.x - PANEL_W
    draw_rect(Rect2(px, 0, PANEL_W, size.y), Color(0.07, 0.07, 0.09))
    draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.2, 0.25, 0.3), 1.0)

    if selected_node != "" and selected_event != "":
        _draw_node_props(px, font)
    else:
        draw_string(font, Vector2(px + 12, 30), "Select a node", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45))


    var save_r = Rect2(px + 12, size.y - 34, 100, 24)
    draw_rect(save_r, Color(0.12, 0.18, 0.25))
    draw_rect(save_r, Color(0.3, 0.4, 0.5), false, 1.0)
    draw_string(font, Vector2(px + 22, size.y - 14), "Save to Disk", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.9))
    button_rects.append({"id": "save", "rect": save_r})

    if type_picker_open:
        _draw_type_picker(px, font)
    if speaker_picker_open:
        _draw_speaker_picker(px, font)

    if status_text != "":
        draw_string(font, Vector2(cx + 10, size.y - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.4))

func _draw_node_flow(cx: float, cw: float, font: Font):
    var evt = events[selected_event]
    var nodes: Dictionary = evt.get("nodes", {})
    if nodes.is_empty():
        draw_string(font, Vector2(cx + 20, 40), "(no nodes — click + Add Node)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))


    var ordered: Array = []
    if nodes.has("start"):
        ordered.append("start")
    for nid in nodes:
        if nid != "start":
            ordered.append(nid)

    var ny = 20.0 - scroll_center
    var nw = cw - 40
    for nid in ordered:
        var node = nodes[nid]
        var text_preview = str(node.get("text", "")).substr(0, 50)
        if text_preview.length() >= 50:
            text_preview += "..."
        var nh = 50.0 + node.get("choices", []).size() * 16.0
        var nr = Rect2(cx + 20, ny, nw, nh)
        var sel = (nid == selected_node)

        if ny + nh > 0 and ny < size.y:

            draw_rect(nr, Color(0.1, 0.12, 0.16) if sel else Color(0.07, 0.08, 0.1))
            if sel:
                draw_rect(nr, Color(0.4, 0.6, 1.0), false, 2.0)
            else:
                draw_rect(nr, Color(0.2, 0.25, 0.3), false, 1.0)


            draw_string(font, Vector2(cx + 28, ny + 16), nid, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 1.0))

            var speaker = node.get("speaker", "")
            if speaker != "":
                draw_string(font, Vector2(cx + 28, ny + 30), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.6, 0.4))

            draw_string(font, Vector2(cx + 28, ny + 44), text_preview, HORIZONTAL_ALIGNMENT_LEFT, int(nw - 20), 11, Color(0.6, 0.6, 0.65))


            var cy = ny + 54
            for choice in node.get("choices", []):
                var clabel = choice.get("label", "")
                if clabel.length() > 40:
                    clabel = clabel.substr(0, 37) + "..."
                draw_string(font, Vector2(cx + 36, cy), "> " + clabel + " -> " + choice.get("next", ""), HORIZONTAL_ALIGNMENT_LEFT, int(nw - 30), 10, Color(0.45, 0.55, 0.5))
                cy += 16

        button_rects.append({"id": "sel_node_" + nid, "rect": nr})
        ny += nh + 12


    var anr = Rect2(cx + 20, ny + 4, 100, 22)
    draw_rect(anr, Color(0.12, 0.18, 0.12))
    draw_rect(anr, Color(0.3, 0.5, 0.3), false, 1.0)
    draw_string(font, Vector2(cx + 30, ny + 20), "+ Add Node", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.85, 0.5))
    button_rects.append({"id": "add_node", "rect": anr})
    var dnr = Rect2(cx + 130, ny + 4, 100, 22)
    draw_rect(dnr, Color(0.18, 0.1, 0.1))
    draw_rect(dnr, Color(0.5, 0.3, 0.3), false, 1.0)
    draw_string(font, Vector2(cx + 140, ny + 20), "- Del Node", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.4, 0.4))
    button_rects.append({"id": "del_node", "rect": dnr})

func _draw_node_props(px: float, font: Font):
    var evt = events[selected_event]
    var nodes: Dictionary = evt.get("nodes", {})
    if not nodes.has(selected_node):
        return
    var node = nodes[selected_node]

    var x = px + 12.0
    var y = 8.0 - scroll_right


    draw_line(Vector2(x, y + 6), Vector2(x + PANEL_W - 30, y + 6), Color(0.2, 0.25, 0.3), 1.0)
    draw_string(font, Vector2(x + 4, y + 20), "NODE: " + selected_node, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0))
    y += 28

    y = _draw_field("node_speaker", "Speaker", str(node.get("speaker", "")), x, y, font, PANEL_W)
    y = _draw_field("node_text", "Text", str(node.get("text", "")), x, y, font, PANEL_W)


    y += 8
    draw_string(font, Vector2(x + 4, y + 14), "CHOICES:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
    y += 20
    var choices: Array = node.get("choices", [])
    for i in choices.size():
        var c = choices[i]
        var sel = (i == selected_choice)
        var cr = Rect2(x + 2, y, PANEL_W - 38, 36)
        draw_rect(cr, Color(0.12, 0.15, 0.2) if sel else Color(0.07, 0.07, 0.09))
        if sel:
            draw_rect(cr, Color(0.4, 0.5, 0.7), false, 1.0)
        draw_string(font, Vector2(x + 8, y + 14), c.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, int(PANEL_W - 50), 11, 
            Color(0.8, 0.8, 0.85) if sel else Color(0.5, 0.5, 0.55))
        draw_string(font, Vector2(x + 8, y + 30), "-> " + c.get("next", "(end)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.55, 0.5))
        button_rects.append({"id": "sel_choice_%d" % i, "rect": cr})
        y += 40


    var acr = Rect2(x + 2, y + 2, 80, 20)
    draw_rect(acr, Color(0.12, 0.18, 0.12))
    draw_string(font, Vector2(x + 10, y + 17), "+ Choice", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.85, 0.5))
    button_rects.append({"id": "add_choice", "rect": acr})
    var rcr = Rect2(x + 90, y + 2, 80, 20)
    draw_rect(rcr, Color(0.18, 0.1, 0.1))
    draw_string(font, Vector2(x + 98, y + 17), "- Choice", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.4, 0.4))
    button_rects.append({"id": "del_choice", "rect": rcr})
    y += 28


    if selected_choice >= 0 and selected_choice < choices.size():
        var c = choices[selected_choice]
        y += 4
        draw_string(font, Vector2(x + 4, y + 14), "CHOICE DETAILS:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
        y += 20
        y = _draw_field("choice_label", "Label", str(c.get("label", "")), x, y, font, PANEL_W)
        y = _draw_field("choice_next", "Next Node", str(c.get("next", "")), x, y, font, PANEL_W)
        var _next_id = c.get("next", "")
        if _next_id != "" and not evt.get("nodes", {}).has(_next_id):
            _draw_warning(field_rects.back().rect, font)

        y += 8
        var choice_effects: Array = c.get("effects", [])
        if not c.has("effects"):
            c["effects"] = choice_effects
        y = _draw_effects_section("CHOICE EFFECTS", choice_effects, "choice", x, y, font, evt)

    y += 8
    var node_effects: Array = node.get("effects", [])
    if not node.has("effects"):
        node["effects"] = node_effects
    y = _draw_effects_section("NODE EFFECTS", node_effects, "node", x, y, font, evt)

func _draw_field(key: String, label: String, value: String, x: float, y: float, font: Font, panel_w: float = PANEL_W) -> float:
    var label_w: float = 72.0
    var val_x = x + label_w
    var val_w = panel_w - label_w - 36
    draw_string(font, Vector2(x + 4, y + 15), label + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))
    var vr = Rect2(val_x, y + 1, val_w, 18)
    var is_editing = (editing_key == key and edit_line.visible)
    if not is_editing:
        draw_rect(vr, Color(0.1, 0.1, 0.13))
        var display = value
        if display.length() > 40:
            display = display.substr(0, 37) + "..."
        draw_string(font, Vector2(val_x + 4, y + 15), display, HORIZONTAL_ALIGNMENT_LEFT, int(val_w - 8), 12, Color(0.85, 0.85, 0.9))
    field_rects.append({"key": key, "rect": vr, "value": value})
    return y + 22



func _gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _handle_click(event.position)
            MOUSE_BUTTON_WHEEL_UP:
                if speaker_picker_open:
                    speaker_picker_scroll = maxf(speaker_picker_scroll - 30, 0)
                elif type_picker_open:
                    type_picker_scroll = maxf(type_picker_scroll - 30, 0)
                elif event.position.x < LIST_W:
                    scroll_left = maxf(scroll_left - 30, 0)
                elif event.position.x > size.x - PANEL_W:
                    scroll_right = maxf(scroll_right - 30, 0)
                else:
                    scroll_center = maxf(scroll_center - 30, 0)
                queue_redraw()
                accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                if speaker_picker_open:
                    speaker_picker_scroll += 30
                elif type_picker_open:
                    type_picker_scroll += 30
                elif event.position.x < LIST_W:
                    scroll_left += 30
                elif event.position.x > size.x - PANEL_W:
                    scroll_right += 30
                else:
                    scroll_center += 30
                queue_redraw()
                accept_event()

func _handle_click(pos: Vector2):
    if edit_line.visible:
        _on_field_submitted(edit_line.text)

    if speaker_picker_open:
        for btn in button_rects:
            if btn.id.begins_with("pick_speaker_") and btn.rect.has_point(pos):
                _handle_button(btn.id)
                accept_event()
                return
        speaker_picker_open = false
        queue_redraw()
        accept_event()
        return

    if type_picker_open:
        for btn in button_rects:
            if btn.id.begins_with("pick_type_") and btn.rect.has_point(pos):
                _handle_button(btn.id)
                accept_event()
                return
        type_picker_open = false
        queue_redraw()
        accept_event()
        return

    for btn in button_rects:
        if btn.rect.has_point(pos):
            _handle_button(btn.id)
            accept_event()
            return

    for fr in field_rects:
        if fr.rect.has_point(pos):
            if fr.key == "node_speaker":
                speaker_picker_open = true
                speaker_picker_scroll = 0.0
                _refresh_speaker_ids()
                queue_redraw()
                accept_event()
                return
            if fr.key.begins_with("eff_") and fr.key.ends_with("_type"):
                type_picker_open = true
                type_picker_scroll = 0.0
                queue_redraw()
                accept_event()
                return
            _start_editing(fr.key, fr.value, fr.rect)
            accept_event()
            return

func _handle_button(btn_id: String):
    if btn_id.begins_with("sel_event_"):
        selected_event = btn_id.replace("sel_event_", "")
        selected_node = ""
        selected_choice = -1
        selected_effect = -1
        effect_context = ""
        type_picker_open = false
        speaker_picker_open = false
        scroll_right = 0
        scroll_center = 0
    elif btn_id.begins_with("sel_node_"):
        selected_node = btn_id.replace("sel_node_", "")
        selected_choice = -1
        selected_effect = -1
        effect_context = ""
        type_picker_open = false
        speaker_picker_open = false
        scroll_right = 0
    elif btn_id.begins_with("sel_choice_"):
        selected_choice = int(btn_id.replace("sel_choice_", ""))
        selected_effect = -1
        effect_context = ""
        type_picker_open = false
        speaker_picker_open = false
    elif btn_id == "add_event":
        _add_event()
    elif btn_id == "del_event":
        _del_event()
    elif btn_id == "add_node":
        _add_node()
    elif btn_id == "del_node":
        _del_node()
    elif btn_id == "add_choice":
        _add_choice()
    elif btn_id == "del_choice":
        _del_choice()
    elif btn_id.begins_with("sel_eff_"):
        var rest = btn_id.replace("sel_eff_", "")
        var sep = rest.rfind("_")
        var ctx = rest.substr(0, sep)
        var idx = int(rest.substr(sep + 1))
        if ctx == effect_context and idx == selected_effect:
            selected_effect = -1
            effect_context = ""
        else:
            effect_context = ctx
            selected_effect = idx
        type_picker_open = false
        speaker_picker_open = false
    elif btn_id.begins_with("del_eff_"):
        var rest = btn_id.replace("del_eff_", "")
        var sep = rest.rfind("_")
        var ctx = rest.substr(0, sep)
        var idx = int(rest.substr(sep + 1))
        var arr = _get_effects_array(ctx)
        if arr != null and idx < arr.size():
            if _undo != null:
                _undo.begin()
            arr.remove_at(idx)
            if ctx == effect_context:
                if selected_effect >= arr.size():
                    selected_effect = arr.size() - 1
                if arr.is_empty():
                    selected_effect = -1
                    effect_context = ""
            if _undo != null:
                _undo.commit("remove effect")
        type_picker_open = false
        speaker_picker_open = false
    elif btn_id.begins_with("add_eff_"):
        var ctx = btn_id.replace("add_eff_", "")
        var arr = _get_effects_array(ctx)
        if arr != null:
            if _undo != null:
                _undo.begin()
            arr.append({"type": "give_credits", "amount": 100})
            effect_context = ctx
            selected_effect = arr.size() - 1
            if _undo != null:
                _undo.commit("add effect")
        type_picker_open = false
        speaker_picker_open = false
    elif btn_id.begins_with("pick_type_"):
        var new_type = btn_id.replace("pick_type_", "")
        var arr = _get_effects_array(effect_context)
        if arr != null and selected_effect >= 0 and selected_effect < arr.size():
            if _undo != null:
                _undo.begin()
            var eff = arr[selected_effect]
            var old_type = eff.get("type", "")
            if new_type != old_type:
                var old_keys: Array = []
                for k in eff:
                    if k != "type":
                        old_keys.append(k)
                for k in old_keys:
                    eff.erase(k)
                eff["type"] = new_type
                if EFFECT_SCHEMA.has(new_type):
                    for p in EFFECT_SCHEMA[new_type]:
                        eff[p.key] = p.default
            else:
                eff["type"] = new_type
            if _undo != null:
                _undo.commit("change effect type")
        type_picker_open = false
        speaker_picker_open = false
    elif btn_id.begins_with("pick_speaker_"):
        if btn_id == "pick_speaker_manual":
            speaker_picker_open = false
            _begin_manual_speaker_edit()
            queue_redraw()
            return
        var speaker_name: String = btn_id.replace("pick_speaker_", "")
        if selected_event != "" and events.has(selected_event):
            var evt: Dictionary = events[selected_event]
            var nodes: Dictionary = evt.get("nodes", {})
            if nodes.has(selected_node):
                if _undo != null:
                    _undo.begin()
                nodes[selected_node]["speaker"] = speaker_name
                if _undo != null:
                    _undo.commit("pick speaker")
        speaker_picker_open = false
    elif btn_id == "save":
        _save_events()
    queue_redraw()

func _start_editing(key: String, value: String, rect: Rect2):
    editing_key = key
    edit_line.text = value
    edit_line.position = rect.position
    edit_line.size = rect.size
    edit_line.visible = true
    edit_line.grab_focus()
    edit_line.select_all()

func _on_field_submitted(text: String):
    if editing_key == "" or selected_event == "" or not events.has(selected_event):
        edit_line.visible = false
        editing_key = ""
        return

    var evt = events[selected_event]
    var nodes: Dictionary = evt.get("nodes", {})
    var key = editing_key
    edit_line.visible = false
    editing_key = ""

    if _undo != null:
        _undo.begin()
    if key == "node_speaker" and nodes.has(selected_node):
        nodes[selected_node]["speaker"] = text
    elif key == "node_text" and nodes.has(selected_node):
        nodes[selected_node]["text"] = text
    elif key == "choice_label":
        if selected_choice >= 0 and nodes.has(selected_node):
            var choices: Array = nodes[selected_node].get("choices", [])
            if selected_choice < choices.size():
                choices[selected_choice]["label"] = text
    elif key == "choice_next":
        if selected_choice >= 0 and nodes.has(selected_node):
            var choices: Array = nodes[selected_node].get("choices", [])
            if selected_choice < choices.size():
                choices[selected_choice]["next"] = text
    elif key.begins_with("eff_"):
        _apply_effect_field(key, text)
    if _undo != null:
        _undo.commit("edit " + key)
    queue_redraw()



func _add_event():
    if _undo != null:
        _undo.begin()
    var base = "new_event"
    var idx = 1
    while events.has(base + "_" + str(idx)):
        idx += 1
    var eid = base + "_" + str(idx)
    events[eid] = {
        "title": "New Event",
        "nodes": {
            "start": {
                "speaker": "",
                "text": "Event text here.",
                "choices": [
                    {"label": "OK", "next": "leave"}
                ]
            },
            "leave": {
                "speaker": "",
                "text": "You move on.",
                "choices": []
            }
        }
    }
    selected_event = eid
    selected_node = ""
    status_text = "Created: " + eid
    status_timer = 3.0
    if _undo != null:
        _undo.commit("add event")

func _del_event():
    if selected_event != "" and events.has(selected_event):
        if _undo != null:
            _undo.begin()
        var event_name = selected_event
        events.erase(selected_event)
        selected_event = ""
        selected_node = ""
        status_text = "Deleted: " + event_name
        status_timer = 3.0
        if _undo != null:
            _undo.commit("delete event")

func _add_node():
    if selected_event == "" or not events.has(selected_event):
        return
    if _undo != null:
        _undo.begin()
    var nodes: Dictionary = events[selected_event].get("nodes", {})
    var idx = nodes.size()
    var nid = "node_%d" % idx
    while nodes.has(nid):
        idx += 1
        nid = "node_%d" % idx
    nodes[nid] = {"speaker": "", "text": "New node text.", "choices": []}
    selected_node = nid
    if _undo != null:
        _undo.commit("add node")

func _del_node():
    if selected_event == "" or selected_node == "":
        return
    var nodes: Dictionary = events[selected_event].get("nodes", {})
    if nodes.has(selected_node):
        if _undo != null:
            _undo.begin()
        nodes.erase(selected_node)
        selected_node = ""
        selected_choice = -1
        if _undo != null:
            _undo.commit("delete node")

func _add_choice():
    if selected_event == "" or selected_node == "":
        return
    var nodes: Dictionary = events[selected_event].get("nodes", {})
    if nodes.has(selected_node):
        if _undo != null:
            _undo.begin()
        var choices: Array = nodes[selected_node].get("choices", [])
        choices.append({"label": "New choice", "next": "leave"})
        nodes[selected_node]["choices"] = choices
        selected_choice = choices.size() - 1
        if _undo != null:
            _undo.commit("add choice")

func _del_choice():
    if selected_event == "" or selected_node == "" or selected_choice < 0:
        return
    var nodes: Dictionary = events[selected_event].get("nodes", {})
    if nodes.has(selected_node):
        var choices: Array = nodes[selected_node].get("choices", [])
        if selected_choice < choices.size():
            if _undo != null:
                _undo.begin()
            choices.remove_at(selected_choice)
            selected_choice = mini(selected_choice, choices.size() - 1)
            if _undo != null:
                _undo.commit("delete choice")


func _draw_effects_section(title: String, effects: Array, context: String, x: float, y: float, font: Font, evt: Dictionary) -> float:
    draw_string(font, Vector2(x + 4, y + 14), title + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
    y += 20

    for ei in effects.size():
        var eff = effects[ei]
        var is_sel = (ei == selected_effect and context == effect_context)

        var row_r = Rect2(x + 2, y, PANEL_W - 58, 22)
        draw_rect(row_r, Color(0.12, 0.14, 0.2) if is_sel else Color(0.07, 0.07, 0.09))
        if is_sel:
            draw_rect(row_r, Color(0.4, 0.5, 0.7), false, 1.0)

        var summary = _effect_summary(eff)
        if summary.length() > 42:
            summary = summary.substr(0, 39) + "..."
        draw_string(font, Vector2(x + 8, y + 15), summary, HORIZONTAL_ALIGNMENT_LEFT, int(PANEL_W - 80), 10, Color(0.8, 0.75, 0.5) if is_sel else Color(0.6, 0.55, 0.4))
        button_rects.append({"id": "sel_eff_%s_%d" % [context, ei], "rect": row_r})

        var del_r = Rect2(x + PANEL_W - 52, y + 1, 20, 20)
        draw_rect(del_r, Color(0.18, 0.08, 0.08))
        draw_string(font, Vector2(x + PANEL_W - 47, y + 15), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.35, 0.35))
        button_rects.append({"id": "del_eff_%s_%d" % [context, ei], "rect": del_r})

        y += 24

        if is_sel:
            y = _draw_effect_detail(eff, context, x, y, font, evt)

    var add_r = Rect2(x + 2, y, 100, 20)
    draw_rect(add_r, Color(0.12, 0.15, 0.1))
    draw_string(font, Vector2(x + 10, y + 15), "+ Add Effect", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.85, 0.5))
    button_rects.append({"id": "add_eff_" + context, "rect": add_r})
    y += 26

    return y

func _draw_effect_detail(eff: Dictionary, context: String, x: float, y: float, font: Font, _evt: Dictionary) -> float:
    draw_rect(Rect2(x + 6, y - 2, PANEL_W - 44, 2), Color(0.3, 0.35, 0.45))

    var etype = eff.get("type", "")
    y = _draw_field("eff_%s_type" % context, "Type", etype, x + 8, y, font, PANEL_W - 16)

    if EFFECT_SCHEMA.has(etype):
        for param in EFFECT_SCHEMA[etype]:
            var field_key = "eff_%s_%s" % [context, param.key]
            var val = str(eff.get(param.key, param.default))
            y = _draw_field(field_key, param.key.capitalize(), val, x + 8, y, font, PANEL_W - 16)

            if param.key == "module_id":
                var mid = eff.get("module_id", "")
                if mid != "" and not DataManager.modules.has(mid):
                    _draw_warning(field_rects.back().rect, font)
            elif param.key == "event_id":
                var qeid = eff.get("event_id", "")
                if qeid != "" and not DataManager.events.has(qeid):
                    _draw_warning(field_rects.back().rect, font)

    draw_rect(Rect2(x + 6, y, PANEL_W - 44, 2), Color(0.3, 0.35, 0.45))
    y += 6
    return y

func _effect_summary(eff: Dictionary) -> String:
    var etype = eff.get("type", "?")
    if not EFFECT_SCHEMA.has(etype):
        return etype
    var params = EFFECT_SCHEMA[etype]
    if params.is_empty():
        return etype
    var parts: Array = [etype + ":"]
    for p in params:
        var val = eff.get(p.key, p.default)
        parts.append("%s=%s" % [p.key, str(val)])
    return " ".join(parts)

func _apply_effect_field(key: String, text: String):
    var arr = _get_effects_array(effect_context)
    if arr == null or selected_effect < 0 or selected_effect >= arr.size():
        return
    var eff = arr[selected_effect]

    var prefix = "eff_%s_" % effect_context
    var field = key.replace(prefix, "")

    if field == "type":
        return

    var etype = eff.get("type", "")
    if EFFECT_SCHEMA.has(etype):
        for param in EFFECT_SCHEMA[etype]:
            if param.key == field:
                match param.type:
                    "int": eff[field] = int(text)
                    "float": eff[field] = float(text)
                    "bool": eff[field] = (text.to_lower() == "true" or text == "1")
                    _: eff[field] = text
                return

func _get_effects_array(context: String) -> Variant:
    if selected_event == "" or selected_node == "":
        return null
    var nodes: Dictionary = events[selected_event].get("nodes", {})
    if not nodes.has(selected_node):
        return null
    var node = nodes[selected_node]
    if context == "choice" and selected_choice >= 0:
        var choices: Array = node.get("choices", [])
        if selected_choice < choices.size():
            if not choices[selected_choice].has("effects"):
                choices[selected_choice]["effects"] = []
            return choices[selected_choice]["effects"]
    elif context == "node":
        if not node.has("effects"):
            node["effects"] = []
        return node["effects"]
    return null

func _draw_type_picker(px: float, font: Font):
    var picker_x = px + 20
    var picker_y = 40.0
    var picker_w = PANEL_W - 40
    var row_h = 22.0
    var types = EFFECT_SCHEMA.keys()
    var picker_h = minf(types.size() * row_h + 8, size.y - 100)

    draw_rect(Rect2(picker_x - 2, picker_y - 2, picker_w + 4, picker_h + 4), Color(0.0, 0.0, 0.0, 0.8))
    draw_rect(Rect2(picker_x, picker_y, picker_w, picker_h), Color(0.08, 0.09, 0.12))
    draw_rect(Rect2(picker_x, picker_y, picker_w, picker_h), Color(0.4, 0.5, 0.7), false, 1.0)

    draw_string(font, Vector2(picker_x + 6, picker_y + 16), "SELECT TYPE:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.6, 0.75))
    var ty = picker_y + 22.0 - type_picker_scroll

    for type_name in types:
        if ty > picker_y and ty + row_h < picker_y + picker_h:
            var params = EFFECT_SCHEMA[type_name]
            var param_hint = ""
            if not params.is_empty():
                var pnames: Array = []
                for p in params:
                    pnames.append(p.key)
                param_hint = " (" + ", ".join(pnames) + ")"

            var row_r = Rect2(picker_x + 4, ty, picker_w - 8, row_h - 2)
            draw_rect(row_r, Color(0.1, 0.1, 0.14))
            draw_string(font, Vector2(picker_x + 10, ty + 15), type_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.8, 0.5))
            draw_string(font, Vector2(picker_x + 10 + type_name.length() * 7, ty + 15), param_hint, HORIZONTAL_ALIGNMENT_LEFT, int(picker_w - type_name.length() * 7 - 20), 9, Color(0.45, 0.45, 0.5))
            button_rects.append({"id": "pick_type_" + type_name, "rect": row_r})
        ty += row_h


func _draw_speaker_picker(px: float, font: Font) -> void:
    var picker_x: float = px + 20.0
    var picker_y: float = 40.0
    var picker_w: float = PANEL_W - 40.0
    var row_h: float = 22.0
    var picker_h: float = minf(float(_speaker_ids.size() + 1) * row_h + 8.0, size.y - 100.0)

    draw_rect(Rect2(picker_x - 2.0, picker_y - 2.0, picker_w + 4.0, picker_h + 4.0), Color(0.0, 0.0, 0.0, 0.8))
    draw_rect(Rect2(picker_x, picker_y, picker_w, picker_h), Color(0.08, 0.09, 0.12))
    draw_rect(Rect2(picker_x, picker_y, picker_w, picker_h), Color(0.6, 0.45, 0.75), false, 1.0)
    draw_string(font, Vector2(picker_x + 6.0, picker_y + 16.0), "SELECT SPEAKER:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.65, 0.95))

    var ty: float = picker_y + 22.0 - speaker_picker_scroll
    if ty > picker_y and ty + row_h < picker_y + picker_h:
        var manual_r := Rect2(picker_x + 4.0, ty, picker_w - 8.0, row_h - 2.0)
        draw_rect(manual_r, Color(0.14, 0.11, 0.18))
        draw_string(font, Vector2(picker_x + 10.0, ty + 15.0), "Edit manually...", HORIZONTAL_ALIGNMENT_LEFT, int(picker_w - 20.0), 11, Color(1.0, 0.9, 1.0))
        button_rects.append({"id": "pick_speaker_manual", "rect": manual_r})
    ty += row_h
    for speaker_v in _speaker_ids:
        var speaker_name: String = str(speaker_v)
        if ty > picker_y and ty + row_h < picker_y + picker_h:
            var row_r := Rect2(picker_x + 4.0, ty, picker_w - 8.0, row_h - 2.0)
            draw_rect(row_r, Color(0.1, 0.1, 0.14))
            draw_string(font, Vector2(picker_x + 10.0, ty + 15.0), speaker_name, HORIZONTAL_ALIGNMENT_LEFT, int(picker_w - 20.0), 11, Color(0.92, 0.85, 1.0))
            button_rects.append({"id": "pick_speaker_" + speaker_name, "rect": row_r})
        ty += row_h


func _current_pack_id() -> String:
    var pack_id := "demo"
    if MvPackLoader.current_pack != null:
        pack_id = str(MvPackLoader.current_pack.pack_id).strip_edges()
    if pack_id.is_empty():
        pack_id = "demo"
    return pack_id


func _refresh_speaker_ids() -> void:
    _speaker_ids = PackAssetIndex.list_portrait_ids(_current_pack_id())


func _begin_manual_speaker_edit() -> void:
    if selected_event == "" or not events.has(selected_event):
        return
    var evt: Dictionary = events[selected_event]
    var nodes: Dictionary = evt.get("nodes", {})
    if not nodes.has(selected_node):
        return
    for field_v in field_rects:
        var field: Dictionary = field_v
        if str(field.get("key", "")) == "node_speaker":
            _start_editing("node_speaker", str(nodes[selected_node].get("speaker", "")), field.get("rect", Rect2()))
            return

func _draw_warning(rect: Rect2, font: Font):
    draw_rect(rect, Color(0.9, 0.2, 0.1, 0.25), false, 1.0)
    draw_string(font, Vector2(rect.position.x + rect.size.x - 14, rect.position.y + 14), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.3, 0.2))

func _save_events():
    DataManager.events = events.duplicate(true)
    var file = FileAccess.open("res://Space/data/events/starter_events.json", FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(events, "\t"))
        file.close()
        status_text = "Saved starter_events.json!"
        status_timer = 3.0
    else:
        status_text = "ERROR: Could not write file!"
        status_timer = 3.0
