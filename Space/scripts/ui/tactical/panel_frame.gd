extends Control

# Tactical-HUD panel chrome. Draws the 14px corner-cut polygon with
# the design's panel fill + accent border in its own coordinate space.
# Optionally renders an uppercase title strip across the top edge.
#
# Token references: panels.corner_cut, panels.background, panels.border_color
# and typography.scales.label_md.

@export var title: String = "":
    set(value):
        title = value
        queue_redraw()

@export var corner_cut: float = 14.0
@export var border_alpha: float = 0.75
@export var fill_alpha: float = 1.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return

    var w := size.x
    var h := size.y
    var c := corner_cut
    # 8-vertex corner-cut polygon, clockwise from top-left.
    var pts := PackedVector2Array([
        Vector2(c, 0.0),
        Vector2(w - c, 0.0),
        Vector2(w, c),
        Vector2(w, h - c),
        Vector2(w - c, h),
        Vector2(c, h),
        Vector2(0.0, h - c),
        Vector2(0.0, c),
    ])

    var fill: Color = Tokens.panel_fill
    fill.a = clampf(Tokens.panel_fill.a * fill_alpha, 0.0, 1.0)
    draw_colored_polygon(pts, fill)

    # Border — close polygon by repeating the first vertex.
    var border_pts := pts.duplicate()
    border_pts.append(pts[0])
    var border_col: Color = Tokens.hud_dim
    border_col.a = clampf(border_alpha, 0.0, 1.0)
    draw_polyline(border_pts, border_col, 1.5, true)

    # Inner glow line, just inside the border.
    var inner := Tokens.hud_color
    inner.a = 0.10
    draw_polyline(border_pts, inner, 1.0, true)

    if not title.is_empty():
        _draw_title_strip()


func _draw_title_strip() -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var label := title.to_upper()
    var label_size := Tokens.font_size("sublabel")
    # Tucked into the top-left of the panel, just inside the corner cut.
    var pos := Vector2(corner_cut + 6.0, corner_cut + 4.0 + float(label_size))
    draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Tokens.hud_dim)
