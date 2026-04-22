extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes  = preload("res://Space/scripts/editor/ui/ui_types.gd")

# Left pane for the theme editor. Renders a scrollable list of every
# editable field grouped into sections:
#   PANEL ART      — frame + margin per panel variant
#   BUTTON ART     — frame + margin per button state
#   TEXT COLORS    — hex color per text role
#   FONT SIZES     — int per font role
#   MISC           — modal_dim_alpha + frame_stroke
#
# Each row is clickable and dispatches the matching request_* on the
# editor controller, which opens the appropriate modal.

var editor: Node = null

const HEADER_H: float = 30.0
const ROW_H: float    = 38.0
const ROW_GAP: float  = 4.0
const PAD: float      = 14.0

var _rows: Array = []  # [{"target": String, "key": String, "rect": Rect2}]
var _scroll: float = 0.0
var _content_h: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    clip_contents = true
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 36.0, max(0.0, _content_h - size.y))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 36.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for row in _rows:
                if (row["rect"] as Rect2).has_point(mb.position):
                    _dispatch(row)
                    accept_event()
                    return


func _dispatch(row: Dictionary) -> void:
    var t := str(row["target"])
    var k := str(row.get("key", ""))
    match t:
        "panel_frame":   editor.request_pick_panel_frame(k)
        "panel_margin":  editor.request_edit_panel_margin(k)
        "button_frame":  editor.request_pick_button_frame(k)
        "button_margin": editor.request_edit_button_margin(k)
        "text_color":    editor.request_edit_text_color(k)
        "font_size":     editor.request_edit_font_size(k)
        "modal_dim":     editor.request_edit_modal_dim()
        "frame_stroke":  editor.request_edit_frame_stroke()


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)
    if editor == null:
        return

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()
    _rows.clear()

    var theme_dict: Dictionary = editor.theme_data
    var y: float = PAD - _scroll

    y = _draw_section(font, mouse_pos, y, UITypes.SECTION_PANELS)
    for k_v in UITypes.PANEL_KEYS:
        var k := str(k_v)
        var entry := UITypes.get_panel_entry(theme_dict, k)
        var frame := str(entry.get("frame", ""))
        var margin_v: Variant = entry.get("margin", [12, 12])
        y = _draw_field_row(font, mouse_pos, y, "panel_frame", k,
            UITypes.panel_label(k), _short_path(frame))
        y = _draw_field_row(font, mouse_pos, y, "panel_margin", k,
            "  margin", _margin_str(margin_v))

    y += 6
    y = _draw_section(font, mouse_pos, y, UITypes.SECTION_BUTTONS)
    for k_v in UITypes.BUTTON_KEYS:
        var k := str(k_v)
        var entry := UITypes.get_button_entry(theme_dict, k)
        var frame := str(entry.get("frame", ""))
        var margin_v: Variant = entry.get("margin", [14, 14])
        y = _draw_field_row(font, mouse_pos, y, "button_frame", k,
            UITypes.button_label(k), _short_path(frame))
        y = _draw_field_row(font, mouse_pos, y, "button_margin", k,
            "  margin", _margin_str(margin_v))

    y += 6
    y = _draw_section(font, mouse_pos, y, UITypes.SECTION_TEXT)
    for role_v in UITypes.TEXT_ROLES:
        var role := str(role_v)
        var hex := UITypes.get_text_hex(theme_dict, role)
        y = _draw_color_row(font, mouse_pos, y, "text_color", role,
            UITypes.text_label(role), hex)

    y += 6
    y = _draw_section(font, mouse_pos, y, UITypes.SECTION_FONTS)
    for role_v in UITypes.FONT_ROLES:
        var role := str(role_v)
        var sz := UITypes.get_font_size(theme_dict, role)
        y = _draw_field_row(font, mouse_pos, y, "font_size", role,
            UITypes.font_label(role), "%d px" % sz)

    y += 6
    y = _draw_section(font, mouse_pos, y, UITypes.SECTION_MISC)
    var dim_a := float(theme_dict.get("modal_dim_alpha", 0.55))
    y = _draw_field_row(font, mouse_pos, y, "modal_dim", "",
        "Modal dim alpha", "%.2f" % dim_a)
    var stroke_hex := str(theme_dict.get("frame_stroke", "#6699ee99"))
    y = _draw_color_row(font, mouse_pos, y, "frame_stroke", "",
        "Frame stroke", stroke_hex)

    _content_h = y + _scroll + PAD


func _draw_section(font: Font, _mouse: Vector2, y: float, label: String) -> float:
    draw_string(font, Vector2(PAD + 4, y + 18),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.55, 0.88, 0.7, 1))
    draw_line(Vector2(PAD, y + 26), Vector2(size.x - PAD, y + 26),
        Color(0.35, 0.6, 0.45, 0.85), 1.0)
    return y + HEADER_H


func _draw_field_row(font: Font, mouse_pos: Vector2, y: float, target: String,
        key: String, label: String, value: String) -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0, ROW_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.4, 0.3, 0.95)
    else:
        bg = Color(0.1, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.35, 0.6, 0.45, 0.85), false, 1.0)

    draw_string(font, rect.position + Vector2(10, 14),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.72, 1))

    var shown := value
    if shown == "":
        shown = "(empty)"
    var max_chars: int = int((rect.size.x - 20.0) / 6.0)
    if shown.length() > max_chars and max_chars > 3:
        shown = shown.substr(0, max_chars - 3) + "..."
    var vcol := Color(1, 1, 1, 1) if hover else Color(0.85, 0.98, 0.92, 1)
    draw_string(font, rect.position + Vector2(10, 30),
        shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vcol)

    _rows.append({
        "target": target,
        "key":    key,
        "rect":   rect,
    })
    if hover:
        EditorTooltip.show_text(_tooltip_for(target, key, label, value))
    return y + ROW_H + ROW_GAP


func _draw_color_row(font: Font, mouse_pos: Vector2, y: float, target: String,
        key: String, label: String, hex: String) -> float:
    var rect := Rect2(PAD, y, size.x - PAD * 2.0, ROW_H)
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.4, 0.3, 0.95)
    else:
        bg = Color(0.1, 0.18, 0.14, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.35, 0.6, 0.45, 0.85), false, 1.0)

    draw_string(font, rect.position + Vector2(10, 14),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        Color(0.6, 0.85, 0.72, 1))

    var col := UIPanels._hex_to_color(hex)
    var swatch := Rect2(rect.position.x + 10, rect.position.y + 18, 18, 14)
    draw_rect(swatch, col)
    draw_rect(swatch, Color(0, 0, 0, 0.6), false, 1.0)

    var hcol := Color(1, 1, 1, 1) if hover else Color(0.85, 0.98, 0.92, 1)
    draw_string(font, Vector2(swatch.position.x + swatch.size.x + 8,
        rect.position.y + 30),
        hex, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hcol)

    _rows.append({
        "target": target,
        "key":    key,
        "rect":   rect,
    })
    if hover:
        EditorTooltip.show_text(_tooltip_for(target, key, label, hex))
    return y + ROW_H + ROW_GAP


func _short_path(path: String) -> String:
    if path == "":
        return "(none)"
    var parts := path.split("/")
    if parts.size() <= 2:
        return path
    return ".../" + parts[parts.size() - 2] + "/" + parts[parts.size() - 1]


func _margin_str(m_v: Variant) -> String:
    if typeof(m_v) == TYPE_VECTOR2I:
        return "%d, %d" % [(m_v as Vector2i).x, (m_v as Vector2i).y]
    if typeof(m_v) == TYPE_ARRAY and (m_v as Array).size() >= 2:
        return "%d, %d" % [int((m_v as Array)[0]), int((m_v as Array)[1])]
    return "12, 12"


func _tooltip_for(target: String, key: String, label: String, value: String) -> String:
    match target:
        "panel_frame":
            return "Pick the 9-slice frame texture for the \"%s\" panel variant. Opens a texture picker that lists every PNG under res://Space/UI/. Currently: %s" % [key, value]
        "panel_margin":
            return "Edit the inner margin (x, y) for the \"%s\" panel variant in pixels. Controls how far panel content is inset from the frame edges. Currently: %s" % [key, value]
        "button_frame":
            return "Pick the 9-slice frame texture for the \"%s\" button state. Opens a texture picker. Currently: %s" % [key, value]
        "button_margin":
            return "Edit the inner margin (x, y) for the \"%s\" button state in pixels. Controls how far the button label is inset from the frame edges. Currently: %s" % [key, value]
        "text_color":
            return "Edit the color used for \"%s\" text. Opens a color picker modal. Hex with optional alpha (e.g. #aabbccff). Currently: %s" % [key, value]
        "font_size":
            return "Edit the font size in pixels for the \"%s\" role. Currently: %s" % [key, value]
        "modal_dim":
            return "Edit the alpha (0–1) of the dim overlay drawn behind every modal dialog. Higher = darker backdrop. Currently: %s" % value
        "frame_stroke":
            return "Edit the color used for the 1px stroke drawn around panels and buttons. Hex with alpha. Currently: %s" % value
    return "Click to edit \"%s\". Currently: %s" % [label, value]
