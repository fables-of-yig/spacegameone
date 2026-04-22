extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")

# Flag inspector tab for the SSB content editor. Reads the unified flag bridge
# (PlanetaryInterface autoload) so it sees state set by either MVMania
# triggers or SSB GDScript code. Two columns: planet-scoped flags (wiped on
# planet entry, snapshotted per planet) and global flags (cross-system,
# never wiped).
#
# Click a flag to toggle/cycle its value:
#   bool   → flips
#   int    → +1 (right-click to -1)
#   string → no-op (use a trigger to mutate)
# Click [×] next to a flag to delete it.
# Click [Clear] in the column header to wipe the whole namespace.

var status_text: String = ""
var status_timer: float = 0.0
var _row_rects: Array = []
var _del_rects: Array = []
var _clear_planet_rect: Rect2 = Rect2()
var _clear_global_rect: Rect2 = Rect2()
var _scroll_planet: float = 0.0
var _scroll_global: float = 0.0

var _undo: RefCounted = null

const ROW_H: float = 22.0
const HEADER_H: float = 32.0

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    var iface = _get_iface()
    var planet: Dictionary = {}
    var global: Dictionary = {}
    if iface != null:
        if iface.has_method("snapshot_planet_flags"):
            planet = iface.snapshot_planet_flags()
        if "_global_flags" in iface and typeof(iface._global_flags) == TYPE_DICTIONARY:
            global = (iface._global_flags as Dictionary).duplicate(true)
    return {"planet": planet, "global": global}


func _apply_state(snap: Dictionary) -> void:
    var iface = _get_iface()
    if iface == null:
        return
    var p_v: Variant = snap.get("planet", null)
    if typeof(p_v) == TYPE_DICTIONARY and iface.has_method("restore_planet_flags"):
        iface.restore_planet_flags(p_v)
    var g_v: Variant = snap.get("global", null)
    if typeof(g_v) == TYPE_DICTIONARY and "_global_flags" in iface:
        iface._global_flags = g_v


func refresh():
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
    var mp := get_local_mouse_position()
    if _clear_planet_rect.has_point(mp):
        EditorTooltip.show_text("Wipe every flag in the planet namespace (the current visit's snapshot).")
        return
    if _clear_global_rect.has_point(mp):
        EditorTooltip.show_text("Wipe every flag in the global, cross-system, persistent namespace.")
        return
    for d in _del_rects:
        if (d["rect"] as Rect2).has_point(mp):
            EditorTooltip.show_text("Delete this flag from the %s namespace." % str(d.get("scope", "")))
            return
    for r in _row_rects:
        if (r["rect"] as Rect2).has_point(mp):
            EditorTooltip.show_text("Left-click cycles this flag (bool toggles, int/float +1). Right-click -1. String flags are read-only here — mutate them with a trigger.")
            return

func _get_iface() -> Node:
    return get_node_or_null("/root/PlanetaryInterface")

func _draw():
    var font = ThemeDB.fallback_font
    draw_rect(Rect2(0, 0, size.x, size.y), Color(0.05, 0.05, 0.07))

    var iface = _get_iface()
    if iface == null:
        draw_string(font, Vector2(size.x * 0.5 - 200, size.y * 0.5),
            "PlanetaryInterface autoload missing — flag bridge offline",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.4, 0.4))
        return

    _row_rects.clear()
    _del_rects.clear()

    var col_w = (size.x - 24) * 0.5
    _draw_column(font, iface, "planet", "PLANET FLAGS  (per-visit, snapshotted)",
        Rect2(8, 8, col_w, size.y - 16), _scroll_planet)
    _draw_column(font, iface, "global", "GLOBAL FLAGS  (cross-system, persistent)",
        Rect2(16 + col_w, 8, col_w, size.y - 16), _scroll_global)

    if status_text != "":
        var sw: float = float(status_text.length()) * 6.0 + 32
        var sr := Rect2(size.x * 0.5 - sw * 0.5, size.y - 42, sw, 28)
        UIPanels.draw_panel(self, sr, Color.WHITE)
        draw_string(font, Vector2(sr.position.x + 16, sr.position.y + 19),
            status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)

func _draw_column(font: Font, iface: Node, scope: String, title: String, rect: Rect2, scroll: float):
    UIPanels.draw_panel(self, rect, Color.WHITE, UIPanels.PanelVariant.DARK)

    # Header text — drawn on top of the panel art
    draw_string(font, Vector2(rect.position.x + 14, rect.position.y + 22),
        title, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 90), 13, UIPanels.TEXT_PANEL)

    var clear_r := Rect2(rect.position.x + rect.size.x - 78, rect.position.y + 8, 64, 22)
    UIPanels.draw_button_bg(self, clear_r, false, Color(0.95, 0.4, 0.32, 1.0))
    draw_string(font, Vector2(clear_r.position.x + 14, clear_r.position.y + 16),
        "CLEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.65))
    if scope == "planet":
        _clear_planet_rect = clear_r
    else:
        _clear_global_rect = clear_r

    # Flag list
    var names: Array
    if scope == "planet":
        names = iface.list_planet_flag_names() if iface.has_method("list_planet_flag_names") else []
    else:
        names = iface.list_global_flag_names() if iface.has_method("list_global_flag_names") else []

    var content_top := rect.position.y + HEADER_H + 4
    var content_bottom := rect.position.y + rect.size.y - 4
    var y := content_top - scroll

    if names.size() == 0:
        draw_string(font, Vector2(rect.position.x + 14, content_top + 18),
            "(no flags set)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))
        return

    for i in names.size():
        var flag_name: String = names[i]
        if y + ROW_H < content_top or y > content_bottom:
            y += ROW_H
            continue
        var value
        if scope == "planet":
            value = iface.get_planet_flag(flag_name, null)
        else:
            value = iface.get_global_flag(flag_name, null)
        var row_r := Rect2(rect.position.x + 4, y, rect.size.x - 8, ROW_H - 2)
        draw_rect(row_r, Color(0.04, 0.06, 0.09) if i % 2 == 0 else Color(0.06, 0.08, 0.11))

        var name_col := Color(0.7, 0.78, 0.88)
        var value_col := Color(0.55, 0.85, 0.95)
        var type_str := _type_label(value)

        draw_string(font, Vector2(row_r.position.x + 8, row_r.position.y + 15),
            flag_name, HORIZONTAL_ALIGNMENT_LEFT, int(row_r.size.x - 200), 12, name_col)

        var value_str: String = "%s" % [value] if value != null else "<null>"
        if value_str.length() > 24:
            value_str = value_str.substr(0, 22) + "…"
        draw_string(font, Vector2(row_r.position.x + row_r.size.x - 180, row_r.position.y + 15),
            value_str, HORIZONTAL_ALIGNMENT_LEFT, 110, 12, value_col)

        draw_string(font, Vector2(row_r.position.x + row_r.size.x - 60, row_r.position.y + 15),
            type_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.5, 0.6))

        # Delete button
        var del_r := Rect2(row_r.position.x + row_r.size.x - 22, row_r.position.y + 3, 16, 14)
        draw_rect(del_r, Color(0.15, 0.05, 0.05))
        draw_rect(del_r, Color(0.6, 0.2, 0.2, 0.7), false, 1.0)
        draw_string(font, Vector2(del_r.position.x + 5, del_r.position.y + 11),
            "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.4, 0.4))

        _row_rects.append({"scope": scope, "name": flag_name, "rect": row_r})
        _del_rects.append({"scope": scope, "name": flag_name, "rect": del_r})

        y += ROW_H

func _type_label(v) -> String:
    match typeof(v):
        TYPE_BOOL: return "bool"
        TYPE_INT: return "int"
        TYPE_FLOAT: return "float"
        TYPE_STRING: return "string"
        TYPE_VECTOR2: return "vec2"
        TYPE_NIL: return "nil"
        _: return "var"

func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()
            return
    if event is InputEventMouseButton and event.pressed:
        var pos = event.position
        if event.button_index == MOUSE_BUTTON_LEFT:
            _handle_left_click(pos)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _handle_right_click(pos)
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _handle_scroll(pos, -16.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _handle_scroll(pos, 16.0)

func _handle_scroll(pos: Vector2, delta: float):
    if pos.x < size.x * 0.5:
        _scroll_planet = maxf(0.0, _scroll_planet + delta)
    else:
        _scroll_global = maxf(0.0, _scroll_global + delta)

func _handle_left_click(pos: Vector2):
    var iface = _get_iface()
    if iface == null:
        return

    if _clear_planet_rect.has_point(pos):
        if _undo != null:
            _undo.begin()
        iface.clear_planet_flags()
        _flash("Cleared planet flags")
        if _undo != null:
            _undo.commit("clear planet flags")
        return
    if _clear_global_rect.has_point(pos):
        if _undo != null:
            _undo.begin()
        iface.clear_global_flags()
        _flash("Cleared global flags")
        if _undo != null:
            _undo.commit("clear global flags")
        return

    for item in _del_rects:
        if (item["rect"] as Rect2).has_point(pos):
            _delete_flag(iface, item["scope"], item["name"])
            return

    for item in _row_rects:
        if (item["rect"] as Rect2).has_point(pos):
            _cycle_flag(iface, item["scope"], item["name"], +1)
            return

func _handle_right_click(pos: Vector2):
    var iface = _get_iface()
    if iface == null:
        return
    for item in _row_rects:
        if (item["rect"] as Rect2).has_point(pos):
            _cycle_flag(iface, item["scope"], item["name"], -1)
            return

func _delete_flag(iface: Node, scope: String, flag_name: String):
    if _undo != null:
        _undo.begin()
    var did: bool = false
    if scope == "planet":
        var snap = iface.snapshot_planet_flags()
        if snap.has(flag_name):
            snap.erase(flag_name)
            iface.restore_planet_flags(snap)
            _flash("Deleted planet flag '%s'" % flag_name)
            did = true
    else:
        if "_global_flags" in iface:
            var d = iface._global_flags
            if d.has(flag_name):
                d.erase(flag_name)
                _flash("Deleted global flag '%s'" % flag_name)
                did = true
    if _undo != null:
        if did:
            _undo.commit("delete flag")
        else:
            _undo.discard()

func _cycle_flag(iface: Node, scope: String, flag_name: String, delta: int):
    var value
    if scope == "planet":
        value = iface.get_planet_flag(flag_name, null)
    else:
        value = iface.get_global_flag(flag_name, null)
    var new_value = value
    match typeof(value):
        TYPE_BOOL:
            new_value = not value
        TYPE_INT:
            new_value = value + delta
        TYPE_FLOAT:
            new_value = value + float(delta)
        _:
            return # nothing to cycle for strings / nil
    if _undo != null:
        _undo.begin()
    if scope == "planet":
        iface.set_planet_flag(flag_name, new_value)
    else:
        iface.set_global_flag(flag_name, new_value)
    _flash("%s/%s: %s → %s" % [scope, flag_name, str(value), str(new_value)])
    if _undo != null:
        _undo.commit("cycle flag")

func _flash(msg: String):
    status_text = msg
    status_timer = 2.5
