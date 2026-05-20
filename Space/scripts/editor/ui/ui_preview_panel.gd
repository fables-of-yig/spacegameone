extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UITypes  = preload("res://Space/scripts/shared/ui/ui_types.gd")

# Right pane for the theme editor. Renders a live preview of the active
# theme:
#   - Three panel variants (main / alt / dark) side by side
#   - Three button states (normal / hover / pressed)
#   - Every text role with a sample string in its current color/size
#   - A sample "modal" dim layer + popup so the modal_dim_alpha is visible
#
# The preview reads UIPanels (which already holds the live theme), so
# every edit on the field panel updates here on the next frame.

var editor: Node = null

const PAD: float = 16.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    clip_contents = true
    set_process(true)


func _process(_delta):
    queue_redraw()


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)
    if editor == null:
        return

    var font := ThemeDB.fallback_font
    var inner := Rect2(PAD, PAD, size.x - PAD * 2.0, size.y - PAD * 2.0)

    var y: float = inner.position.y
    y = _draw_section_label(font, inner.position.x, y, "PREVIEW — PANEL VARIANTS")
    y = _draw_panel_row(font, inner.position.x, y, inner.size.x)
    y += 12

    y = _draw_section_label(font, inner.position.x, y, "BUTTON STATES")
    y = _draw_button_row(font, inner.position.x, y, inner.size.x)
    y += 12

    y = _draw_section_label(font, inner.position.x, y, "TEXT ROLES")
    y = _draw_text_roles(font, inner.position.x, y, inner.size.x)
    y += 12

    y = _draw_section_label(font, inner.position.x, y, "MODAL OVERLAY")
    _draw_modal_sample(font, inner.position.x, y, inner.size.x, inner.position.y + inner.size.y - y)


func _draw_section_label(font: Font, x: float, y: float, label: String) -> float:
    var col: Color = UIPanels.text_color("title")
    draw_string(font, Vector2(x + 4, y + 16),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
    draw_line(Vector2(x, y + 24), Vector2(x + size.x - PAD * 2.0, y + 24),
        Color(0.4, 0.7, 0.5, 0.7), 1.0)
    return y + 30


func _draw_panel_row(font: Font, x: float, y: float, w: float) -> float:
    var box_h: float = 120.0
    var gap: float = 10.0
    var box_w := (w - gap * 2.0) / 3.0
    var variants := [
        {"key": "main", "label": "MAIN", "variant": UIPanels.PanelVariant.MAIN},
        {"key": "alt",  "label": "ALT",  "variant": UIPanels.PanelVariant.ALT},
        {"key": "dark", "label": "DARK", "variant": UIPanels.PanelVariant.DARK},
    ]
    for i in variants.size():
        var v: Dictionary = variants[i]
        var rect := Rect2(x + float(i) * (box_w + gap), y, box_w, box_h)
        UIPanels.draw_panel(self, rect, Color.WHITE, int(v["variant"]))
        var margin := _panel_margin(str(v["key"]))
        var pad_x := float(margin.x)
        var pad_y := float(margin.y)
        var inner_w := maxf(10.0, rect.size.x - pad_x * 2.0)
        var title_sz := UIPanels.font_size("title_size")
        var body_sz := UIPanels.font_size("body_size")
        var hint_sz := UIPanels.font_size("hint_size")
        var ty := rect.position.y + pad_y + float(title_sz)
        draw_multiline_string(font,
            Vector2(rect.position.x + pad_x, ty),
            str(v["label"]), HORIZONTAL_ALIGNMENT_LEFT, inner_w,
            title_sz, 1, UIPanels.text_color("title"))
        ty += float(title_sz) + 6.0
        draw_multiline_string(font,
            Vector2(rect.position.x + pad_x, ty),
            "Sample body text", HORIZONTAL_ALIGNMENT_LEFT, inner_w,
            body_sz, 2, UIPanels.text_color("body"))
        ty += float(body_sz) + 6.0
        draw_multiline_string(font,
            Vector2(rect.position.x + pad_x, ty),
            "dim hint line", HORIZONTAL_ALIGNMENT_LEFT, inner_w,
            hint_sz, 1, UIPanels.text_color("dim"))
    return y + box_h


func _panel_margin(key: String) -> Vector2i:
    var entry_v: Variant = UIPanels.panels.get(key, null)
    if typeof(entry_v) != TYPE_DICTIONARY:
        return Vector2i(12, 12)
    var m_v: Variant = (entry_v as Dictionary).get("margin", Vector2i(12, 12))
    if typeof(m_v) == TYPE_VECTOR2I:
        return m_v
    if typeof(m_v) == TYPE_ARRAY and (m_v as Array).size() >= 2:
        return Vector2i(int((m_v as Array)[0]), int((m_v as Array)[1]))
    return Vector2i(12, 12)


func _draw_button_row(font: Font, x: float, y: float, w: float) -> float:
    var btn_h: float = 38.0
    var gap: float = 10.0
    var btn_w := (w - gap * 2.0) / 3.0
    var states := [
        {"label": "NORMAL",  "hovered": false, "pressed": false},
        {"label": "HOVER",   "hovered": true,  "pressed": false},
        {"label": "PRESSED", "hovered": false, "pressed": true},
    ]
    for i in states.size():
        var s: Dictionary = states[i]
        var rect := Rect2(x + float(i) * (btn_w + gap), y, btn_w, btn_h)
        UIPanels.draw_button_bg(self, rect, bool(s["hovered"]),
            Color(0.55, 0.85, 1.0, 1.0), bool(s["pressed"]))
        var text_col: Color
        if bool(s["hovered"]):
            text_col = UIPanels.text_color("button_hover")
        else:
            text_col = UIPanels.text_color("button")
        var lbl := str(s["label"])
        var lbl_w := float(lbl.length()) * 6.0
        draw_string(font, Vector2(rect.position.x + (rect.size.x - lbl_w) * 0.5,
            rect.position.y + 24),
            lbl, HORIZONTAL_ALIGNMENT_LEFT, -1,
            UIPanels.font_size("button_size"), text_col)
    return y + btn_h


func _draw_text_roles(font: Font, x: float, y: float, w: float) -> float:
    var margin := _panel_margin("dark")
    var pad_x := float(margin.x)
    var pad_y := float(margin.y)
    var inner_w := maxf(40.0, w - pad_x * 2.0 - 8.0)
    var row_gap: float = 6.0

    var row_heights: Array = []
    var total_h: float = pad_y * 2.0
    for role_v in UITypes.TEXT_ROLES:
        var role := str(role_v)
        var sz := UIPanels.font_size(_size_role_for_text(role))
        var sample := "%s — The quick brown fox jumps over the lazy dog" % UITypes.text_label(role)
        var lines := _wrap_line_count(font, sample, sz, inner_w)
        var h := float(sz + 4) * float(lines)
        row_heights.append(h)
        total_h += h + row_gap
    total_h -= row_gap

    var rect := Rect2(x, y, w, maxf(40.0, total_h))
    UIPanels.draw_panel(self, rect, Color.WHITE, UIPanels.PanelVariant.DARK)

    var ry := rect.position.y + pad_y
    for i in UITypes.TEXT_ROLES.size():
        var role2 := str(UITypes.TEXT_ROLES[i])
        var col := UIPanels.text_color(role2)
        var sz2 := UIPanels.font_size(_size_role_for_text(role2))
        var sample2 := "%s — The quick brown fox jumps over the lazy dog" % UITypes.text_label(role2)
        draw_multiline_string(font,
            Vector2(rect.position.x + pad_x, ry + float(sz2)),
            sample2, HORIZONTAL_ALIGNMENT_LEFT, inner_w,
            sz2, -1, col)
        ry += float(row_heights[i]) + row_gap
    return rect.position.y + rect.size.y


func _wrap_line_count(font: Font, text: String, font_sz: int, width: float) -> int:
    if text == "":
        return 1
    var sizes := font.get_multiline_string_size(text,
        HORIZONTAL_ALIGNMENT_LEFT, width, font_sz)
    if sizes.y <= 0.0:
        return 1
    var line_h := float(font.get_height(font_sz))
    if line_h <= 0.0:
        return 1
    var n: int = int(round(sizes.y / line_h))
    return max(1, n)


func _size_role_for_text(role: String) -> String:
    match role:
        "title": return "title_size"
        "dim":   return "hint_size"
        "button", "button_hover": return "button_size"
        _: return "body_size"


func _draw_modal_sample(font: Font, x: float, y: float, w: float, h: float) -> void:
    var rect := Rect2(x, y, w, max(80.0, h - 4.0))
    UIPanels.draw_panel(self, rect, Color.WHITE, UIPanels.PanelVariant.MAIN)
    UIPanels.draw_dim(self, rect)

    var modal_w: float = min(rect.size.x - 40.0, 320.0)
    var modal_h: float = min(rect.size.y - 30.0, 90.0)
    var modal_rect := Rect2(rect.position.x + (rect.size.x - modal_w) * 0.5,
        rect.position.y + (rect.size.y - modal_h) * 0.5,
        modal_w, modal_h)
    UIPanels.draw_panel(self, modal_rect, Color.WHITE, UIPanels.PanelVariant.MAIN)
    draw_string(font, modal_rect.position + Vector2(20, 30),
        "Sample modal", HORIZONTAL_ALIGNMENT_LEFT, -1,
        UIPanels.font_size("title_size"), UIPanels.text_color("title"))
    draw_string(font, modal_rect.position + Vector2(20, 56),
        "Backdrop alpha = %.2f" % float(editor.theme_data.get("modal_dim_alpha", 0.55)),
        HORIZONTAL_ALIGNMENT_LEFT, -1,
        UIPanels.font_size("body_size"), UIPanels.text_color("body"))
