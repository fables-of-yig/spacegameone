extends Control

# Full-screen scanline overlay matching tokens.animations.scan_lines:
# `repeating-linear-gradient(0deg, rgba(92,242,255,0.025) 0 1px,
#  transparent 1px 3px)`. Drawn as 1px horizontal tinted lines every 3px.

const STEP := 3.0
const LINE_ALPHA := 0.025


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 4096  # sit above panel chrome


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var col := Tokens.hud_color
    col.a = LINE_ALPHA
    var y := 0.0
    while y < size.y:
        draw_line(Vector2(0.0, y), Vector2(size.x, y), col, 1.0)
        y += STEP
