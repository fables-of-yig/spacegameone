extends Object

# Shared draw helpers used by the weapon-readout widgets. Each readout
# (pulse / gauss / torpedo / shield-parry) renders the same hotkey badge,
# weapon name, and status sublabel chrome; only the central readout body
# differs per weapon.
#
# Static-only — instantiate nothing; just call the methods.

# Hotkey badge in the top-left of a readout panel. Draws a tight
# [KEY]-style label in the accent color.
static func draw_hotkey_badge(c: CanvasItem, pos: Vector2, key_label: String) -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var sz := Tokens.font_size("label_lg")
    var text := "[%s]" % key_label.to_upper()
    var color: Color = Tokens.hud_color
    c.draw_string(font, pos + Vector2(0.0, float(sz)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, color)


# Weapon name banner — uppercase, right-justified within `right_x`,
# anchored to the same baseline as draw_hotkey_badge.
static func draw_weapon_name(c: CanvasItem, baseline_y: float, right_x: float, name: String) -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var sz := Tokens.font_size("label_md")
    var text := name.to_upper()
    var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
    var pos := Vector2(right_x - text_size.x, baseline_y)
    c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Tokens.hud_dim)


# Status sublabel along the bottom of a readout panel. `color` picks
# the line color (use Tokens.ok / warn / danger / hud_color depending
# on state). `value` is an optional right-aligned number/string.
static func draw_status_line(c: CanvasItem, bottom_left: Vector2, panel_w: float, status: String, color: Color, value: String = "") -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var sz := Tokens.font_size("sublabel")
    var baseline := Vector2(bottom_left.x, bottom_left.y)
    c.draw_string(font, baseline, status.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, color)
    if not value.is_empty():
        var val_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
        c.draw_string(font, Vector2(bottom_left.x + panel_w - val_size.x, bottom_left.y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Tokens.hud_dim)


# Skewed parallelogram from the bars helper, replicated here for
# inline-drawn heat strips inside a readout.
static func skew_rect(x: float, y: float, w: float, h: float, deg: float) -> PackedVector2Array:
    var dx := h * tan(deg_to_rad(deg))
    return PackedVector2Array([
        Vector2(x + dx, y),
        Vector2(x + w + dx, y),
        Vector2(x + w, y + h),
        Vector2(x, y + h),
    ])


# Quick state-color helper for heat-style bars.
static func heat_state_color(heat_pct: float, lockout: float) -> Color:
    if heat_pct >= lockout:
        return Tokens.danger
    if heat_pct >= 0.7:
        return Tokens.warn
    return Tokens.hud_color
