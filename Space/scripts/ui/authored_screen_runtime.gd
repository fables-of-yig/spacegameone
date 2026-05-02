extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")

signal action_requested(action_id: String, action_args: String, element_id: String)

var data_source: RefCounted = null
var screen_id: String = ""
var screen_data: Dictionary = {}

var _interactive: Array = []
var _hovered_element_id: String = ""
var _pressed_element_id: String = ""
var _tab_state: Dictionary = {}
var _binding_issues_reported: Dictionary = {}
var _layout_scale: float = 1.0
var _layout_offset: Vector2 = Vector2.ZERO
var _design_size: Vector2 = Vector2(480.0, 272.0)
const DESIGN_VIEWPORT_SIZE := Vector2(480.0, 272.0)


func _ready() -> void:
    _apply_mouse_filter()
    _sync_host_rect()
    set_process(true)


func load_screen(id: String, data: Dictionary, source: RefCounted) -> void:
    _sync_host_rect()
    screen_id = id
    screen_data = data.duplicate(true)
    data_source = source
    _interactive.clear()
    _hovered_element_id = ""
    _pressed_element_id = ""
    _tab_state.clear()
    _binding_issues_reported.clear()
    _seed_tab_state(screen_data)
    _apply_mouse_filter()
    visible = not screen_data.is_empty()
    queue_redraw()


func clear_screen() -> void:
    screen_id = ""
    screen_data = {}
    _interactive.clear()
    _hovered_element_id = ""
    _pressed_element_id = ""
    _tab_state.clear()
    _binding_issues_reported.clear()
    visible = false
    queue_redraw()


func has_screen() -> bool:
    return not screen_data.is_empty()


func _apply_mouse_filter() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE if _is_display_only_hud() else MOUSE_FILTER_STOP


func _is_display_only_hud() -> bool:
    return screen_id == "hud_mv" or screen_id == "hud_space" or screen_id == "hud"


func _process(_delta: float) -> void:
    _sync_host_rect()
    if visible and not screen_data.is_empty():
        queue_redraw()


func _draw() -> void:
    if screen_data.is_empty() or not is_visible_in_tree():
        return
    _sync_host_rect()
    _refresh_layout_metrics()
    _interactive.clear()
    _draw_element(screen_data, Vector2.ZERO)
    _draw_hover_tooltip()


func _gui_input(event: InputEvent) -> void:
    if screen_data.is_empty() or not visible:
        return
    if event is InputEventMouseMotion:
        _update_hover((event as InputEventMouseMotion).position)
    elif event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
            _update_pressed(mb.position)
            if _handle_click(mb.position):
                accept_event()
        elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
            _pressed_element_id = ""
            queue_redraw()


func _update_hover(pos: Vector2) -> void:
    var old := _hovered_element_id
    _hovered_element_id = ""
    for i in range(_interactive.size() - 1, -1, -1):
        var entry: Dictionary = _interactive[i]
        if (entry.get("rect", Rect2()) as Rect2).has_point(pos):
            _hovered_element_id = str(entry.get("id", ""))
            break
    if old != _hovered_element_id:
        queue_redraw()


func _handle_click(pos: Vector2) -> bool:
    for i in range(_interactive.size() - 1, -1, -1):
        var entry: Dictionary = _interactive[i]
        var rect: Rect2 = entry.get("rect", Rect2())
        if not rect.has_point(pos):
            continue
        if not bool(entry.get("enabled", true)):
            return true
        var action_id := str(entry.get("action_id", ""))
        if action_id == "__tab_select__":
            var group := str(entry.get("tab_group", "default"))
            _tab_state[group] = str(entry.get("tab_key", ""))
            queue_redraw()
            return true
        action_requested.emit(
            action_id,
            str(entry.get("action_args", "")),
            str(entry.get("id", "")))
        return true
    return false


func _update_pressed(pos: Vector2) -> void:
    _pressed_element_id = ""
    for i in range(_interactive.size() - 1, -1, -1):
        var entry: Dictionary = _interactive[i]
        var rect: Rect2 = entry.get("rect", Rect2())
        if rect.has_point(pos):
            _pressed_element_id = str(entry.get("id", ""))
            break
    queue_redraw()


func _draw_element(elem: Dictionary, parent_origin: Vector2) -> void:
    var etype := str(elem.get("type", ""))
    var props := _props(elem)
    if not _is_tab_visible(props):
        return

    if etype == "conditional":
        if not _eval_condition(props):
            return
        var conditional_origin := _resolve_origin(elem, parent_origin)
        for child in _children(elem):
            _draw_element(child, conditional_origin)
        return

    var rect := _resolve_rect(elem, parent_origin)
    match etype:
        "panel":
            _draw_panel(rect, props)
        "label":
            _draw_label(rect, props)
        "button":
            _draw_button(rect, elem, props)
        "progress_bar":
            _draw_progress_bar(rect, elem, props)
        "icon":
            _draw_icon(rect, props)
        "separator":
            _draw_separator(rect, props)
        "list":
            _draw_list(rect, props)
        "grid":
            _draw_grid(rect, props)
        "tab_bar":
            _draw_tab_bar(rect, elem, props)
        _:
            draw_rect(rect, Color(0.5, 0.2, 0.2, 0.18))
            draw_rect(rect, Color(0.85, 0.45, 0.45, 0.65), false, 1.0)

    for child in _children(elem):
        _draw_element(child, rect.position)


func _draw_panel(rect: Rect2, props: Dictionary) -> void:
    var opacity := clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
    var sprite_path := str(props.get("sprite_source", "")).strip_edges()
    var sprite_tint := _hex(str(props.get("sprite_tint", "#ffffff")))
    sprite_tint.a *= opacity
    var drew_panel_art := false
    if not sprite_path.is_empty():
        var tex := UIIo.load_texture(sprite_path)
        if tex != null:
            UIPanels.draw_authored_panel_sprite(self, rect, tex, props, sprite_tint, _layout_scale)
            drew_panel_art = true
    if not drew_panel_art:
        var variant_key := str(props.get("variant", "main")).strip_edges()
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
    if text.is_empty():
        return
    var align := HORIZONTAL_ALIGNMENT_LEFT
    var align_raw := str(props.get("alignment", "left"))
    if align_raw == "center":
        align = HORIZONTAL_ALIGNMENT_CENTER
    elif align_raw == "right":
        align = HORIZONTAL_ALIGNMENT_RIGHT
    var role := str(props.get("text_role", "body"))
    var col := UIPanels.text_color(role)
    col.a *= clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
    var size_role := "body_size"
    if role == "title":
        size_role = "title_size"
    elif role == "dim":
        size_role = "hint_size"
    var font_size := int(props.get("font_size", 0))
    if font_size <= 0:
        font_size = UIPanels.font_size(size_role)
    font_size = _scaled_font_size(font_size)
    var padding_x := _scaled_value(4.0)
    var wrap := bool(props.get("wrap", false))
    if wrap:
        var lines := _wrap_text_lines(text, maxf(rect.size.x - padding_x * 2.0, 1.0), font_size, font)
        var line_h := font_size + int(round(_scaled_value(4.0)))
        var baseline := rect.position.y + _scaled_value(6.0) + float(font_size)
        for line in lines:
            if baseline > rect.end.y:
                break
            draw_string(font,
                Vector2(rect.position.x + padding_x, baseline),
                line, align, int(rect.size.x - padding_x * 2.0), font_size, col)
            baseline += float(line_h)
        return
    draw_string(font,
        Vector2(rect.position.x + padding_x, rect.position.y + rect.size.y * 0.5 + font_size * 0.35),
        text, align, int(rect.size.x - padding_x * 2.0), font_size, col)


func _draw_button(rect: Rect2, elem: Dictionary, props: Dictionary) -> void:
    var hovered := str(elem.get("id", "")) == _hovered_element_id
    var pressed := str(elem.get("id", "")) == _pressed_element_id
    var enabled := _button_enabled(props)
    var tex := _button_texture(props, hovered and enabled, pressed and enabled)
    var tint := _hex(str(props.get("sprite_tint", "#ffffff")))
    if tex != null:
        draw_texture_rect(tex, rect, false, tint if enabled else Color(0.5, 0.5, 0.55, 0.75))
        draw_rect(rect, Color(0.0, 0.0, 0.0, 0.25), false, 1.0)
    else:
        var bg_tint := Color(0.45, 0.6, 0.9, 1.0) if enabled else Color(0.3, 0.34, 0.42, 0.7)
        UIPanels.draw_button_bg(self, rect, (hovered or pressed) and enabled, bg_tint)
    var font := ThemeDB.fallback_font
    var label := str(props.get("label", "Button"))
    var text_col := UIPanels.text_color("button_hover") if (hovered or pressed) and enabled else UIPanels.text_color("button")
    if not enabled:
        text_col = Color(0.55, 0.58, 0.64, 0.9)
    if bool(props.get("show_label", true)):
        var font_size: int = _scaled_font_size(13)
        draw_string(font,
            Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + _scaled_value(5.0)),
            label, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), font_size, text_col)
    _interactive.append({
        "id": str(elem.get("id", "")),
        "rect": rect,
        "enabled": enabled,
        "action_id": str(props.get("action_id", "")),
        "action_args": str(props.get("action_args", "")),
    })


func _button_texture(props: Dictionary, hovered: bool, pressed: bool) -> Texture2D:
    var paths: Array = []
    if pressed:
        paths.append(str(props.get("sprite_pressed", "")))
        paths.append(str(props.get("sprite_hover", "")))
    elif hovered:
        paths.append(str(props.get("sprite_hover", "")))
    paths.append(str(props.get("sprite_normal", "")))
    for path_v in paths:
        var path := str(path_v).strip_edges()
        if path.is_empty():
            continue
        var tex := UIIo.load_texture(path)
        if tex != null:
            return tex
    return null


func _draw_progress_bar(rect: Rect2, elem: Dictionary, props: Dictionary) -> void:
    var bg := _hex(str(props.get("bg_color", "#222222")))
    var fg := _hex(str(props.get("fill_color", "#ff4444")))
    var ratio := 0.0
    var current_bind := str(props.get("bind_current", ""))
    var max_bind := str(props.get("bind_max", ""))
    var issue_text := ""
    if data_source != null:
        ratio = data_source.resolve_bar(
            current_bind,
            max_bind)
    if data_source == null or (not current_bind.is_empty() and not _binding_is_resolved(current_bind)) or (not max_bind.is_empty() and not _binding_is_resolved(max_bind)):
        issue_text = "MISSING"
        if not current_bind.is_empty():
            _report_binding_issue(current_bind, "%s.progress_bar.current" % str(elem.get("id", "")))
        if not max_bind.is_empty():
            _report_binding_issue(max_bind, "%s.progress_bar.max" % str(elem.get("id", "")))
    ratio = clampf(ratio, 0.0, 1.0)
    draw_rect(rect, bg)
    var fill := rect
    var direction := str(props.get("direction", "left_to_right"))
    match direction:
        "right_to_left":
            fill.position.x = rect.position.x + rect.size.x * (1.0 - ratio)
            fill.size.x = rect.size.x * ratio
        "bottom_to_top":
            fill.position.y = rect.position.y + rect.size.y * (1.0 - ratio)
            fill.size.y = rect.size.y * ratio
        "top_to_bottom":
            fill.size.y = rect.size.y * ratio
        _:
            fill.size.x = rect.size.x * ratio
    draw_rect(fill, fg)
    draw_rect(rect, Color(0, 0, 0, 0.35), false, maxf(_scaled_value(1.0), 1.0))
    if not issue_text.is_empty():
        draw_rect(rect, Color(1.0, 0.65, 0.2, 0.9), false, maxf(_scaled_value(2.0), 1.0))
    if bool(props.get("show_label", false)) or not issue_text.is_empty():
        var font := ThemeDB.fallback_font
        var label_text := issue_text if not issue_text.is_empty() else "%d%%" % int(round(ratio * 100.0))
        var font_size: int = _scaled_font_size(11)
        draw_string(font,
            Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + _scaled_value(5.0)),
            label_text, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), font_size,
            Color(1.0, 0.9, 0.6, 0.96) if not issue_text.is_empty() else Color(1, 1, 1, 0.92))


func _draw_icon(rect: Rect2, props: Dictionary) -> void:
    var tex: Texture2D = null
    var bind_sprite := str(props.get("bind_sprite", ""))
    if bind_sprite != "" and data_source != null:
        var bound: Variant = data_source.resolve(bind_sprite)
        if bound != null:
            tex = UIIo.load_texture(str(bound))
        else:
            _report_binding_issue(bind_sprite, "%s.icon" % screen_id)
    if tex == null:
        var source := str(props.get("sprite_source", ""))
        if source != "":
            tex = UIIo.load_texture(source)
    if tex == null:
        draw_rect(rect, Color(0.2, 0.2, 0.25, 0.5))
        var stroke := Color(1.0, 0.65, 0.2, 0.9) if not bind_sprite.is_empty() else Color(0.6, 0.5, 0.9, 0.8)
        draw_rect(rect, stroke, false, 1.0)
        return
    draw_texture_rect(tex, rect, false, _hex(str(props.get("tint", "#ffffff"))))


func _draw_separator(rect: Rect2, props: Dictionary) -> void:
    var col := _hex(str(props.get("color", "#666666")))
    var thickness := maxf(_scaled_value(float(props.get("thickness", 1.0))), 1.0)
    if str(props.get("orientation", "horizontal")) == "vertical":
        draw_rect(Rect2(rect.position.x, rect.position.y, thickness, rect.size.y), col)
    else:
        draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, thickness), col)


func _draw_list(rect: Rect2, props: Dictionary) -> void:
    UIPanels.draw_panel(self, rect, Color(0.92, 0.98, 1.0, 0.8), UIPanels.PanelVariant.DARK)
    var bind_array := str(props.get("bind_array", ""))
    var array_result := _array_binding_result(bind_array, "list")
    var items: Array = array_result.get("items", [])
    var issue_text := str(array_result.get("issue", ""))
    var spacing := maxf(_scaled_value(float(props.get("spacing", 4.0))), 0.0)
    var max_visible := maxi(int(props.get("max_visible", 10)), 1)
    var y := rect.position.y + _scaled_value(8.0)
    var font := ThemeDB.fallback_font
    var font_size: int = _scaled_font_size(11)
    var item_action_id := str(props.get("item_action_id", ""))
    var item_wrap := bool(props.get("item_wrap", false))
    var item_min_height := maxf(_scaled_value(float(props.get("item_min_height", 18.0))), _scaled_value(18.0))
    var text_width := maxf(rect.size.x - _scaled_value(16.0), 1.0)
    var line_h := float(font_size) + _scaled_value(4.0)
    for i in range(min(items.size(), max_visible)):
        var item_text := _item_text(items[i])
        var item_lines := [item_text]
        if item_wrap:
            item_lines = _wrap_text_lines(item_text, text_width, font_size, font)
        var item_h := maxf(item_min_height, _scaled_value(4.0) + float(item_lines.size()) * line_h + _scaled_value(4.0))
        if y + item_h > rect.end.y:
            break
        var line_rect := Rect2(rect.position.x + _scaled_value(4.0), y - _scaled_value(1.0), rect.size.x - _scaled_value(8.0), item_h)
        var hovered := _hovered_element_id == "%s::item::%d" % [str(props.get("bind_array", "")), i]
        if hovered and not item_action_id.is_empty():
            draw_rect(line_rect, Color(0.22, 0.32, 0.48, 0.45))
        var baseline := y + float(font_size)
        for line in item_lines:
            if baseline > line_rect.end.y:
                break
            draw_string(font, Vector2(rect.position.x + _scaled_value(8.0), baseline),
                line, HORIZONTAL_ALIGNMENT_LEFT, int(text_width), font_size,
                UIPanels.text_color("body"))
            baseline += line_h
        if not item_action_id.is_empty():
            var enabled := _item_enabled(items[i], props)
            _interactive.append({
                "id": "%s::item::%d" % [str(props.get("bind_array", "")), i],
                "rect": line_rect,
                "enabled": enabled,
                "action_id": item_action_id,
                "action_args": _item_action_arg(items[i], i, props),
                "tooltip": _item_tooltip(items[i], props),
            })
        y += item_h + spacing
    if items.is_empty():
        draw_string(font, Vector2(rect.position.x + _scaled_value(8.0), rect.position.y + _scaled_value(20.0)),
            issue_text if not issue_text.is_empty() else "(empty)",
            HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - _scaled_value(16.0)), font_size,
            Color(1.0, 0.9, 0.6, 0.96) if not issue_text.is_empty() else UIPanels.text_color("dim"))
        if not issue_text.is_empty():
            draw_rect(rect, Color(1.0, 0.65, 0.2, 0.9), false, maxf(_scaled_value(2.0), 1.0))


func _draw_grid(rect: Rect2, props: Dictionary) -> void:
    UIPanels.draw_panel(self, rect, Color(0.92, 0.98, 1.0, 0.8), UIPanels.PanelVariant.DARK)
    var bind_array := str(props.get("bind_array", ""))
    var array_result := _array_binding_result(bind_array, "grid")
    var items: Array = array_result.get("items", [])
    var issue_text := str(array_result.get("issue", ""))
    var columns := maxi(int(props.get("columns", 4)), 1)
    var slot_size := maxf(_scaled_value(float(props.get("slot_size", 32.0))), _scaled_value(16.0))
    var gap := _scaled_value(6.0)
    var font := ThemeDB.fallback_font
    var font_size: int = _scaled_font_size(10)
    var idx := 0
    var rows := maxi(int(ceil(float(max(items.size(), columns)) / float(columns))), 1)
    var item_action_id := str(props.get("item_action_id", ""))
    for row in range(rows):
        for col in range(columns):
            var x := rect.position.x + _scaled_value(8.0) + float(col) * (slot_size + gap)
            var y := rect.position.y + _scaled_value(8.0) + float(row) * (slot_size + gap)
            var cell := Rect2(x, y, slot_size, slot_size)
            if cell.end.x > rect.end.x or cell.end.y > rect.end.y:
                continue
            var occupied := idx < items.size()
            var enabled := occupied and _item_enabled(items[idx], props)
            draw_rect(cell, Color(0.16, 0.18, 0.24, 1.0) if occupied and enabled else (Color(0.15, 0.13, 0.13, 0.9) if occupied else Color(0.1, 0.11, 0.15, 0.7)))
            draw_rect(cell, Color(0.35, 0.45, 0.65, 0.8), false, maxf(_scaled_value(1.0), 1.0))
            if occupied:
                draw_string(font, Vector2(cell.position.x + _scaled_value(4.0), cell.position.y + cell.size.y * 0.5 + _scaled_value(4.0)),
                    _grid_text(items[idx]), HORIZONTAL_ALIGNMENT_LEFT, int(cell.size.x - _scaled_value(8.0)), font_size,
                    UIPanels.text_color("body") if enabled else UIPanels.text_color("dim"))
                if not item_action_id.is_empty():
                    _interactive.append({
                        "id": "%s::cell::%d" % [str(props.get("bind_array", "")), idx],
                        "rect": cell,
                        "enabled": enabled,
                        "action_id": item_action_id,
                        "action_args": _item_action_arg(items[idx], idx, props),
                        "tooltip": _item_tooltip(items[idx], props),
                    })
            idx += 1
    if not issue_text.is_empty():
        draw_rect(rect, Color(1.0, 0.65, 0.2, 0.9), false, maxf(_scaled_value(2.0), 1.0))
        draw_string(font, Vector2(rect.position.x + _scaled_value(8.0), rect.position.y + _scaled_value(20.0)),
            issue_text, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - _scaled_value(16.0)), _scaled_font_size(11),
            Color(1.0, 0.9, 0.6, 0.96))


func _draw_tab_bar(rect: Rect2, elem: Dictionary, props: Dictionary) -> void:
    var tabs_v: Variant = props.get("tabs", [])
    var tabs: Array = []
    if typeof(tabs_v) == TYPE_ARRAY:
        tabs = tabs_v
    if tabs.is_empty():
        tabs = ["Tab A", "Tab B"]
    var group: String = str(props.get("tab_group", "default"))
    if not _tab_state.has(group):
        var initial: int = clampi(int(props.get("active_tab", 0)), 0, tabs.size() - 1)
        _tab_state[group] = str(tabs[initial])
    var active_key: String = str(_tab_state.get(group, str(tabs[0])))
    var count: int = max(tabs.size(), 1)
    var tab_w: float = rect.size.x / float(count)
    var font: Font = ThemeDB.fallback_font
    var font_size: int = _scaled_font_size(11)
    for i in range(count):
        var tab_rect: Rect2 = Rect2(rect.position.x + tab_w * i, rect.position.y, tab_w, rect.size.y)
        var tab_key: String = str(tabs[i])
        var active_tab: bool = tab_key == active_key
        var tint: Color = Color(0.35, 0.55, 0.9, 1.0) if active_tab else Color(0.2, 0.24, 0.32, 1.0)
        UIPanels.draw_button_bg(self, tab_rect, false, tint)
        draw_string(font,
            Vector2(tab_rect.position.x, tab_rect.position.y + tab_rect.size.y * 0.5 + _scaled_value(5.0)),
            tab_key, HORIZONTAL_ALIGNMENT_CENTER, int(tab_rect.size.x), font_size,
            UIPanels.text_color("button") if active_tab else UIPanels.text_color("dim"))
        _interactive.append({
            "id": "%s::tab::%d" % [str(elem.get("id", "")), i],
            "rect": tab_rect,
            "enabled": true,
            "action_id": "__tab_select__",
            "action_args": tab_key,
            "tab_group": group,
            "tab_key": tab_key,
        })


func _label_text(props: Dictionary) -> String:
    var bind := str(props.get("bind_var", ""))
    var fmt := str(props.get("format", "{value}"))
    if bind == "" or data_source == null:
        if bind != "" and data_source == null:
            _report_binding_issue(bind, "%s.label" % screen_id)
            return "[missing %s]" % bind
        return str(props.get("static_text", ""))
    var v: Variant = data_source.resolve(bind)
    if v == null:
        _report_binding_issue(bind, "%s.label" % screen_id)
        return "[missing %s]" % bind
    var text := str(v)
    if typeof(v) == TYPE_FLOAT:
        text = String.num(float(v), int(props.get("decimal_places", 0)))
    return fmt.replace("{value}", text) if fmt != "" else text


func _button_enabled(props: Dictionary) -> bool:
    var cond := str(props.get("enabled_condition", ""))
    if cond == "":
        return true
    if data_source == null:
        _report_binding_issue(cond, "%s.enabled_condition" % screen_id)
        return false
    var resolved: Variant = data_source.resolve(cond)
    if resolved == null:
        _report_binding_issue(cond, "%s.enabled_condition" % screen_id)
    return _is_truthy(resolved)


func _eval_condition(props: Dictionary) -> bool:
    var cond_type := str(props.get("condition_type", "has_flag"))
    var cond_val := str(props.get("condition_value", ""))
    match cond_type:
        "has_flag":
            if data_source != null and data_source.game_manager != null and data_source.game_manager.has_method("has_flag"):
                return bool(data_source.game_manager.has_flag(cond_val))
            return false
        "binding_truthy":
            if data_source == null:
                _report_binding_issue(str(props.get("condition", "")), "%s.conditional" % screen_id)
                return false
            var binding := str(props.get("condition", ""))
            var resolved: Variant = data_source.resolve(binding)
            if resolved == null:
                _report_binding_issue(binding, "%s.conditional" % screen_id)
            return _is_truthy(resolved)
    return true


func _array_like_value(binding: String) -> Array:
    if binding == "" or data_source == null:
        return []
    var v: Variant = data_source.resolve(binding)
    if typeof(v) == TYPE_ARRAY:
        return v
    if typeof(v) == TYPE_DICTIONARY:
        var out: Array = []
        for key in (v as Dictionary).keys():
            out.append({"key": key, "value": (v as Dictionary)[key]})
        return out
    return []


func _array_binding_result(binding: String, context: String) -> Dictionary:
    if binding.is_empty():
        return {"items": [], "issue": ""}
    if data_source == null:
        _report_binding_issue(binding, "%s.%s" % [screen_id, context])
        return {"items": [], "issue": "[missing %s]" % binding}
    var resolved: Variant = data_source.resolve(binding)
    if resolved == null:
        _report_binding_issue(binding, "%s.%s" % [screen_id, context])
        return {"items": [], "issue": "[missing %s]" % binding}
    return {"items": _array_like_value(binding), "issue": ""}


func _draw_hover_tooltip() -> void:
    if _hovered_element_id.is_empty():
        return
    var tooltip := ""
    var hovered_rect := Rect2()
    for entry_v in _interactive:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        if str(entry.get("id", "")) != _hovered_element_id:
            continue
        tooltip = str(entry.get("tooltip", "")).strip_edges()
        hovered_rect = entry.get("rect", Rect2())
        break
    if tooltip.is_empty():
        return
    var font := ThemeDB.fallback_font
    var font_size := _scaled_font_size(11)
    var lines := tooltip.split("\n", false)
    var max_w := 0.0
    for line_v in lines:
        max_w = maxf(max_w, font.get_string_size(str(line_v), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    var pad := _scaled_value(8.0)
    var line_h := float(font_size) + _scaled_value(4.0)
    var box_size := Vector2(max_w + pad * 2.0, float(lines.size()) * line_h + pad * 2.0)
    var pos := hovered_rect.position + Vector2(0.0, hovered_rect.size.y + _scaled_value(6.0))
    if pos.x + box_size.x > size.x:
        pos.x = maxf(_scaled_value(4.0), size.x - box_size.x - _scaled_value(4.0))
    if pos.y + box_size.y > size.y:
        pos.y = maxf(_scaled_value(4.0), hovered_rect.position.y - box_size.y - _scaled_value(6.0))
    var box := Rect2(pos, box_size)
    UIPanels.draw_panel(self, box, Color(1.0, 1.0, 1.0, 0.98), UIPanels.PanelVariant.DARK)
    var baseline := box.position.y + pad + float(font_size)
    for line_v in lines:
        draw_string(font, Vector2(box.position.x + pad, baseline), str(line_v),
            HORIZONTAL_ALIGNMENT_LEFT, int(box.size.x - pad * 2.0), font_size, UIPanels.text_color("body"))
        baseline += line_h


func _binding_is_resolved(binding: String) -> bool:
    if binding.is_empty() or data_source == null:
        return false
    return data_source.resolve(binding) != null


func _report_binding_issue(binding: String, context: String) -> void:
    var trimmed := binding.strip_edges()
    if trimmed.is_empty() or _binding_issues_reported.has(trimmed):
        return
    _binding_issues_reported[trimmed] = true
    push_warning("AuthoredScreenRuntime[%s]: unresolved binding '%s' at %s" % [screen_id, trimmed, context])


func _item_text(item: Variant) -> String:
    if typeof(item) == TYPE_DICTIONARY:
        var d: Dictionary = item
        if d.has("key") and d.has("value"):
            return "%s: %s" % [str(d["key"]), str(d["value"])]
        if d.has("label"):
            return str(d.get("label", ""))
        if d.has("text"):
            return str(d.get("text", ""))
        if d.has("name"):
            var name := str(d.get("name", ""))
            if d.has("price"):
                var count_suffix := (" x%d" % int(d.get("count", 1))) if int(d.get("count", 1)) > 1 else ""
                return "%s%s - %d gold" % [name, count_suffix, int(d.get("price", 0))]
            return name
        return JSON.stringify(d)
    return str(item)


func _grid_text(item: Variant) -> String:
    var text := _item_text(item)
    return text.substr(0, 8) if text.length() > 8 else text


func _item_action_arg(item: Variant, index: int, props: Dictionary) -> String:
    var key := str(props.get("item_action_arg_key", "")).strip_edges()
    if key == "__index__":
        return str(index)
    if typeof(item) == TYPE_DICTIONARY:
        var d: Dictionary = item
        if not key.is_empty() and d.has(key):
            return str(d.get(key, ""))
        if d.has("id"):
            return str(d.get("id", ""))
        if d.has("key"):
            return str(d.get("key", ""))
    return _item_text(item)


func _item_enabled(item: Variant, props: Dictionary) -> bool:
    if str(props.get("item_action_id", "")) != "buy_item":
        return true
    if typeof(item) != TYPE_DICTIONARY:
        return true
    var d: Dictionary = item
    var price := int(d.get("price", 0))
    if price <= 0:
        return true
    if data_source == null:
        return false
    var gold_v: Variant = data_source.resolve("game_var.gold")
    if gold_v == null:
        return false
    return int(gold_v) >= price


func _item_tooltip(item: Variant, props: Dictionary) -> String:
    var action_id := str(props.get("item_action_id", ""))
    if typeof(item) != TYPE_DICTIONARY:
        return str(item)
    var d: Dictionary = item
    var lines: Array = []
    var name := str(d.get("name", d.get("id", d.get("key", "Item"))))
    lines.append(name)
    if d.has("price"):
        lines.append("%d gold" % int(d.get("price", 0)))
    var desc := str(d.get("description", "")).strip_edges()
    if not desc.is_empty():
        lines.append(desc)
    if action_id == "buy_item":
        if _item_enabled(item, props):
            lines.append("Click to buy.")
        else:
            var gold := int(data_source.resolve("game_var.gold")) if data_source != null and data_source.resolve("game_var.gold") != null else 0
            lines.append("Need %d more gold." % maxi(int(d.get("price", 0)) - gold, 0))
    elif action_id == "sell_item":
        lines.append("Click to sell.")
    return "\n".join(lines)


func _is_tab_visible(props: Dictionary) -> bool:
    var tab_id := str(props.get("tab_id", ""))
    if tab_id.is_empty():
        return true
    var group := str(props.get("tab_group", "default"))
    return str(_tab_state.get(group, "")) == tab_id


func _seed_tab_state(elem: Dictionary) -> void:
    var etype := str(elem.get("type", ""))
    var props := _props(elem)
    if etype == "tab_bar":
        var tabs_v: Variant = props.get("tabs", [])
        var tabs: Array = []
        if typeof(tabs_v) == TYPE_ARRAY:
            tabs = tabs_v
        if not tabs.is_empty():
            var group := str(props.get("tab_group", "default"))
            var initial := clampi(int(props.get("active_tab", 0)), 0, tabs.size() - 1)
            if not _tab_state.has(group):
                _tab_state[group] = str(tabs[initial])
    for child in _children(elem):
        _seed_tab_state(child)


func _resolve_rect(elem: Dictionary, parent_origin: Vector2) -> Rect2:
    var r := _rect_dict(elem)
    var x := float(r.get("x", 0))
    var y := float(r.get("y", 0))
    var w := float(r.get("w", 100))
    var h := float(r.get("h", 30))
    var scaled_pos: Vector2 = Vector2(x, y) * _layout_scale
    var scaled_size: Vector2 = Vector2(w, h) * _layout_scale
    if _is_root_element(elem):
        var root_anchor := str(elem.get("anchor", "top_left"))
        return Rect2(_anchor_origin(root_anchor) - _anchor_pivot(root_anchor, scaled_size) + scaled_pos, scaled_size)
    var origin := _anchor_origin(str(elem.get("anchor", "top_left")))
    var offs: Dictionary = {}
    var offs_v: Variant = elem.get("anchor_offset", null)
    if typeof(offs_v) == TYPE_DICTIONARY:
        offs = offs_v
    origin += Vector2(float(offs.get("x", 0)), float(offs.get("y", 0))) * _layout_scale
    if parent_origin != Vector2.ZERO:
        return Rect2(parent_origin + scaled_pos, scaled_size)
    return Rect2(origin + scaled_pos, scaled_size)


func _resolve_origin(elem: Dictionary, parent_origin: Vector2) -> Vector2:
    return _resolve_rect(elem, parent_origin).position


func _anchor_origin(anchor: String) -> Vector2:
    var rect := Rect2(_layout_offset, _design_size * _layout_scale)
    var pos := rect.position
    var s := rect.size
    match anchor:
        "top_left":      return pos
        "top_center":    return pos + Vector2(s.x * 0.5, 0.0)
        "top_right":     return pos + Vector2(s.x, 0.0)
        "center_left":   return pos + Vector2(0.0, s.y * 0.5)
        "center":        return pos + s * 0.5
        "center_right":  return pos + Vector2(s.x, s.y * 0.5)
        "bottom_left":   return pos + Vector2(0.0, s.y)
        "bottom_center": return pos + Vector2(s.x * 0.5, s.y)
        "bottom_right":  return pos + s
    return pos


func _anchor_pivot(anchor: String, rect_size: Vector2) -> Vector2:
    match anchor:
        "top_left":      return Vector2.ZERO
        "top_center":    return Vector2(rect_size.x * 0.5, 0.0)
        "top_right":     return Vector2(rect_size.x, 0.0)
        "center_left":   return Vector2(0.0, rect_size.y * 0.5)
        "center":        return rect_size * 0.5
        "center_right":  return Vector2(rect_size.x, rect_size.y * 0.5)
        "bottom_left":   return Vector2(0.0, rect_size.y)
        "bottom_center": return Vector2(rect_size.x * 0.5, rect_size.y)
        "bottom_right":  return rect_size
    return Vector2.ZERO


func _sync_host_rect() -> void:
    if not is_inside_tree():
        return
    var parent_control := get_parent() as Control
    if parent_control != null:
        set_anchors_preset(PRESET_FULL_RECT)
        offset_left = 0.0
        offset_top = 0.0
        offset_right = 0.0
        offset_bottom = 0.0
        position = Vector2.ZERO
        return
    var viewport_size := get_viewport_rect().size
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        return
    set_anchors_preset(PRESET_TOP_LEFT)
    position = Vector2.ZERO
    size = viewport_size


func _refresh_layout_metrics() -> void:
    _layout_scale = 1.0
    _layout_offset = Vector2.ZERO
    _design_size = DESIGN_VIEWPORT_SIZE
    if screen_data.is_empty():
        return
    var root_rect: Dictionary = _rect_dict(screen_data)
    var design_w: float = maxf(DESIGN_VIEWPORT_SIZE.x,
        float(root_rect.get("x", 0)) + float(root_rect.get("w", DESIGN_VIEWPORT_SIZE.x)))
    var design_h: float = maxf(DESIGN_VIEWPORT_SIZE.y,
        float(root_rect.get("y", 0)) + float(root_rect.get("h", DESIGN_VIEWPORT_SIZE.y)))
    if design_w <= 0.0 or design_h <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
        return
    _design_size = Vector2(design_w, design_h)
    _layout_scale = minf(size.x / design_w, size.y / design_h)
    if _layout_scale <= 0.0:
        _layout_scale = 1.0
    _layout_offset = (size - _design_size * _layout_scale) * 0.5


func _scaled_value(value: float) -> float:
    return value * _layout_scale


func _scaled_font_size(font_size: int) -> int:
    return maxi(int(round(float(font_size) * _layout_scale)), 1)


func _is_root_element(elem: Dictionary) -> bool:
    return str(elem.get("id", "")) == str(screen_data.get("id", ""))


func _props(elem: Dictionary) -> Dictionary:
    var v: Variant = elem.get("properties", {})
    return v if typeof(v) == TYPE_DICTIONARY else {}


func _children(elem: Dictionary) -> Array:
    var v: Variant = elem.get("children", [])
    return v if typeof(v) == TYPE_ARRAY else []


func _rect_dict(elem: Dictionary) -> Dictionary:
    var v: Variant = elem.get("rect", {})
    return v if typeof(v) == TYPE_DICTIONARY else {}


func _hex(s: String) -> Color:
    if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
        return Color(s)
    return Color(1, 1, 1, 1)


func _is_truthy(v: Variant) -> bool:
    if v == null:
        return false
    match typeof(v):
        TYPE_BOOL:
            return v
        TYPE_INT, TYPE_FLOAT:
            return float(v) != 0.0
        TYPE_STRING:
            return str(v) != ""
        TYPE_ARRAY:
            return not (v as Array).is_empty()
        TYPE_DICTIONARY:
            return not (v as Dictionary).is_empty()
    return true


func _wrap_text_lines(text: String, max_width: float, font_size: int, font: Font) -> Array:
    var out: Array = []
    var safe_width := maxf(max_width, 1.0)
    var hard_lines := text.split("\n", false)
    if hard_lines.is_empty():
        hard_lines = [text]
    for hard_v in hard_lines:
        var hard := str(hard_v)
        if hard.is_empty():
            out.append("")
            continue
        var words := hard.split(" ", false)
        var current := ""
        for word_v in words:
            var word := str(word_v)
            var test := word if current.is_empty() else current + " " + word
            if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= safe_width:
                current = test
                continue
            if not current.is_empty():
                out.append(current)
                current = ""
            if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= safe_width:
                current = word
                continue
            var fragments := _wrap_long_word(word, safe_width, font_size, font)
            for fragment_i in range(fragments.size()):
                var fragment := str(fragments[fragment_i])
                if fragment_i == fragments.size() - 1:
                    current = fragment
                else:
                    out.append(fragment)
        if not current.is_empty():
            out.append(current)
    return out


func _wrap_long_word(word: String, max_width: float, font_size: int, font: Font) -> Array:
    var out: Array = []
    var current := ""
    for i in range(word.length()):
        var letter := word.substr(i, 1)
        var test := current + letter
        if not current.is_empty() and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
            out.append(current)
            current = letter
        else:
            current = test
    if not current.is_empty():
        out.append(current)
    return out
