extends Control

# Renders a screen JSON built by the theme editor's Screen Layout Builder
# with live bindings resolved every frame via HudDataSource.
#
# Usage:
#   var r := preload("res://Space/scripts/ui/hud_screen_renderer.gd").new()
#   r.data_source = HudDataSource.new(player, GameManager)
#   r.screen_data = UIIo.load_screen(pack_id, "hud")
#   add_child(r)
#
# The screen data shape (one element):
#   {
#     "type": "panel"|"label"|"button"|"progress_bar"|"icon"|...,
#     "id": "...",
#     "rect": {"x": 10, "y": 10, "w": 100, "h": 30},
#     "anchor": "top_left"|"bottom_right"|...,
#     "properties": { type-specific dict },
#     "children": [ nested elements ],
#   }

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
const UIIo = preload("res://Space/scripts/shared/ui/ui_io.gd")

var data_source: RefCounted = null
var screen_data: Dictionary = {}

# Smoothed bar fills keyed by element id. Advances toward the live
# resolved ratio at a fixed rate per second — this is what gives the
# editor's "animate_fill" property a visible effect.
var _bar_smooth: Dictionary = {}
var _pulse_phase: float = 0.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    set_process(true)


func _process(delta: float) -> void:
    _pulse_phase = fmod(_pulse_phase + delta * 4.0, TAU)
    _advance_smoothing(delta)
    queue_redraw()


func _advance_smoothing(delta: float) -> void:
    # Only walk the tree when we have data — avoids allocations in the
    # pre-load frames right after scene load.
    if screen_data.is_empty():
        return
    _walk_for_smoothing(_elements(screen_data), delta)


func _walk_for_smoothing(elems: Array, delta: float) -> void:
    for e_v in elems:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("type", "")) == "progress_bar":
            var eid: String = str(e.get("id", ""))
            var props: Dictionary = _props(e)
            if bool(props.get("animate_fill", true)) and data_source != null:
                var target: float = data_source.resolve_bar(
                    str(props.get("bind_current", "")),
                    str(props.get("bind_max", "")))
                var cur: float = float(_bar_smooth.get(eid, target))
                var speed: float = 2.5  # fills smoothly over ~0.4s
                if target > cur:
                    cur = minf(cur + speed * delta, target)
                else:
                    cur = maxf(cur - speed * delta, target)
                _bar_smooth[eid] = cur
        var kids_v: Variant = e.get("children", [])
        if typeof(kids_v) == TYPE_ARRAY:
            _walk_for_smoothing(kids_v, delta)


func _draw() -> void:
    if screen_data.is_empty():
        return
    _draw_elements(_elements(screen_data), Vector2.ZERO)


func _draw_elements(elems: Array, parent_origin: Vector2) -> void:
    for e_v in elems:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        _draw_element(e_v, parent_origin)


func _draw_element(e: Dictionary, parent_origin: Vector2) -> void:
    # Conditional elements gate rendering of themselves AND their children.
    var etype: String = str(e.get("type", ""))
    var props: Dictionary = _props(e)

    if etype == "conditional":
        if not _eval_condition(props):
            return
        # Conditional acts as a transparent group.
        var origin := _resolve_origin(e, parent_origin)
        var kids: Array = _children(e)
        _draw_elements(kids, origin)
        return

    var rect := _resolve_rect(e, parent_origin)
    match etype:
        "panel":
            _draw_panel(rect, props)
        "label":
            _draw_label(rect, props)
        "button":
            _draw_button(rect, props)
        "progress_bar":
            _draw_progress_bar(rect, props, str(e.get("id", "")))
        "icon":
            _draw_icon(rect, props)
        "separator":
            _draw_separator(rect, props)
        _:
            # List/grid/tab_bar: stubbed — just frame the area so authors see something.
            draw_rect(rect, Color(0.5, 0.5, 0.5, 0.15))
            draw_rect(rect, Color(0.5, 0.5, 0.5, 0.5), false, 1.0)

    var children: Array = _children(e)
    if not children.is_empty():
        _draw_elements(children, rect.position)


func _draw_panel(rect: Rect2, props: Dictionary) -> void:
    var opacity := clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
    var sprite_path: String = str(props.get("sprite_source", "")).strip_edges()
    var drew_panel_art := false
    if not sprite_path.is_empty():
        var tex: Texture2D = UIIo.load_texture(sprite_path)
        if tex != null:
            var tint := UIPanels._hex_to_color(str(props.get("sprite_tint", "#ffffff")))
            tint.a *= opacity
            UIPanels.draw_authored_panel_sprite(self, rect, tex, props,
                tint)
            drew_panel_art = true
    if not drew_panel_art:
        var variant_key: String = str(props.get("variant", "main")).strip_edges()
        if not variant_key.is_empty() and variant_key != "none":
            var variant := UIPanels.PanelVariant.MAIN
            if variant_key == "alt":
                variant = UIPanels.PanelVariant.ALT
            elif variant_key == "dark":
                variant = UIPanels.PanelVariant.DARK
            UIPanels.draw_panel(self, rect, Color(1.0, 1.0, 1.0, opacity), variant)


func _draw_label(rect: Rect2, props: Dictionary) -> void:
    var font := ThemeDB.fallback_font
    var text := _label_text(props)
    var align_raw: String = str(props.get("alignment", "left"))
    var align := HORIZONTAL_ALIGNMENT_LEFT
    if align_raw == "center":
        align = HORIZONTAL_ALIGNMENT_CENTER
    elif align_raw == "right":
        align = HORIZONTAL_ALIGNMENT_RIGHT
    var col := Color(1, 1, 1, 1)
    var role: String = str(props.get("text_role", "body"))
    if role == "dim":
        col = Color(0.7, 0.75, 0.85, 1)
    elif role == "title":
        col = Color(1, 0.95, 0.8, 1)
    elif role == "error":
        col = Color(1, 0.45, 0.4, 1)
    elif role == "success":
        col = Color(0.55, 1, 0.55, 1)
    col.a *= clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
    # Vertical center within rect.
    draw_string(font,
        Vector2(rect.position.x + 4, rect.position.y + rect.size.y * 0.5 + 5.0),
        text, align, int(rect.size.x - 8), 13, col)


func _label_text(props: Dictionary) -> String:
    var bind: String = str(props.get("bind_var", ""))
    var fmt: String = str(props.get("format", "{value}"))
    if bind.is_empty() or data_source == null:
        return str(props.get("static_text", ""))
    var v: Variant = data_source.resolve(bind)
    if v == null:
        return str(props.get("static_text", ""))
    var text: String
    if typeof(v) == TYPE_FLOAT:
        var dp: int = int(props.get("decimal_places", 0))
        text = String.num(float(v), dp)
    else:
        text = str(v)
    if fmt.is_empty():
        return text
    return fmt.replace("{value}", text)


func _draw_button(rect: Rect2, props: Dictionary) -> void:
    UIPanels.draw_button_bg(self, rect, false, Color(0.45, 0.6, 0.9, 1.0))
    var font := ThemeDB.fallback_font
    var label: String = str(props.get("label", "Button"))
    draw_string(font,
        Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 5.0),
        label, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), 13,
        Color(1, 1, 1, 1))


func _draw_progress_bar(rect: Rect2, props: Dictionary, eid: String) -> void:
    var bg := _hex(str(props.get("bg_color", "#222222")))
    var fg := _hex(str(props.get("fill_color", "#ff4444")))

    var target: float = 0.0
    if data_source != null:
        target = data_source.resolve_bar(
            str(props.get("bind_current", "")),
            str(props.get("bind_max", "")))
    var ratio: float
    if bool(props.get("animate_fill", true)):
        ratio = float(_bar_smooth.get(eid, target))
    else:
        ratio = target

    # Pulse on low: slightly modulates alpha when ratio under threshold.
    if bool(props.get("pulse_on_low", false)):
        var threshold: float = float(props.get("pulse_threshold", 0.25))
        if target <= threshold:
            var pulse := 0.6 + 0.4 * sin(_pulse_phase)
            fg.a *= pulse

    draw_rect(rect, bg)
    var direction: String = str(props.get("direction", "left_to_right"))
    var fill := rect
    match direction:
        "left_to_right":
            fill.size.x = rect.size.x * ratio
        "right_to_left":
            fill.position.x = rect.position.x + rect.size.x * (1.0 - ratio)
            fill.size.x = rect.size.x * ratio
        "bottom_to_top":
            fill.position.y = rect.position.y + rect.size.y * (1.0 - ratio)
            fill.size.y = rect.size.y * ratio
        "top_to_bottom":
            fill.size.y = rect.size.y * ratio
    draw_rect(fill, fg)
    draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.0)

    if bool(props.get("show_label", false)):
        var font := ThemeDB.fallback_font
        var label_text := "%d%%" % int(round(target * 100.0))
        draw_string(font,
            Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 5.0),
            label_text, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), 11,
            Color(1, 1, 1, 0.92))


func _draw_icon(rect: Rect2, props: Dictionary) -> void:
    var source: String = str(props.get("sprite_source", ""))
    var tex: Texture2D = null
    if source != "":
        tex = load(source) as Texture2D
    if tex == null:
        # Placeholder so authors see something where the icon would go.
        draw_rect(rect, Color(0.2, 0.2, 0.25, 0.5))
        draw_rect(rect, Color(0.6, 0.5, 0.9, 0.8), false, 1.0)
        return
    var tint := _hex(str(props.get("tint", "#ffffff")))
    draw_texture_rect(tex, rect, false, tint)


func _draw_separator(rect: Rect2, props: Dictionary) -> void:
    var col := _hex(str(props.get("color", "#666666")))
    var thickness: float = float(props.get("thickness", 1))
    if str(props.get("orientation", "horizontal")) == "vertical":
        draw_rect(Rect2(rect.position.x, rect.position.y, thickness, rect.size.y), col)
    else:
        draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, thickness), col)


func _eval_condition(props: Dictionary) -> bool:
    var cond_type: String = str(props.get("condition_type", "has_flag"))
    var cond_val: String = str(props.get("condition_value", ""))
    match cond_type:
        "has_flag":
            if data_source != null and data_source.game_manager != null \
                    and data_source.game_manager.has_method("has_flag"):
                return bool(data_source.game_manager.has_flag(cond_val))
            return false
        "binding_truthy":
            if data_source == null:
                return false
            var v: Variant = data_source.resolve(str(props.get("condition", "")))
            if v == null:
                return false
            if typeof(v) == TYPE_BOOL:
                return v
            if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
                return float(v) != 0.0
            if typeof(v) == TYPE_STRING:
                return str(v) != ""
            if typeof(v) == TYPE_ARRAY:
                return not (v as Array).is_empty()
            return true
    return true


# ─── Layout helpers ─────────────────────────────────────────────────────

func _resolve_rect(e: Dictionary, parent_origin: Vector2) -> Rect2:
    var r: Dictionary = _rect_dict(e)
    var x: float = float(r.get("x", 0))
    var y: float = float(r.get("y", 0))
    var w: float = float(r.get("w", 100))
    var h: float = float(r.get("h", 30))
    var origin := _anchor_origin(str(e.get("anchor", "top_left")))
    var offs: Dictionary = e.get("anchor_offset", {}) if typeof(e.get("anchor_offset", null)) == TYPE_DICTIONARY else {}
    origin += Vector2(float(offs.get("x", 0)), float(offs.get("y", 0)))
    # If this element is nested (parent_origin != zero), anchor is always
    # relative to the parent's origin — treat rect as offset from parent.
    if parent_origin != Vector2.ZERO:
        return Rect2(parent_origin + Vector2(x, y), Vector2(w, h))
    return Rect2(origin + Vector2(x, y), Vector2(w, h))


func _resolve_origin(e: Dictionary, parent_origin: Vector2) -> Vector2:
    return _resolve_rect(e, parent_origin).position


func _anchor_origin(anchor: String) -> Vector2:
    var s := size
    match anchor:
        "top_left":      return Vector2.ZERO
        "top_center":    return Vector2(s.x * 0.5, 0)
        "top_right":     return Vector2(s.x, 0)
        "center_left":   return Vector2(0, s.y * 0.5)
        "center":        return s * 0.5
        "center_right":  return Vector2(s.x, s.y * 0.5)
        "bottom_left":   return Vector2(0, s.y)
        "bottom_center": return Vector2(s.x * 0.5, s.y)
        "bottom_right":  return s
    return Vector2.ZERO


func _hex(s: String) -> Color:
    if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
        return Color(s)
    return Color(1, 1, 1, 1)


func _elements(screen: Dictionary) -> Array:
    var elems_v: Variant = screen.get("elements", [])
    if typeof(elems_v) == TYPE_ARRAY:
        return elems_v
    return []


func _children(e: Dictionary) -> Array:
    var kids_v: Variant = e.get("children", [])
    if typeof(kids_v) == TYPE_ARRAY:
        return kids_v
    return []


func _props(e: Dictionary) -> Dictionary:
    var p_v: Variant = e.get("properties", {})
    if typeof(p_v) == TYPE_DICTIONARY:
        return p_v
    return {}


func _rect_dict(e: Dictionary) -> Dictionary:
    var r_v: Variant = e.get("rect", {})
    if typeof(r_v) == TYPE_DICTIONARY:
        return r_v
    return {}
