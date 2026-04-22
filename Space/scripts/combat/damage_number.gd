extends Node2D



var text: String = ""
var color: Color = Color(1.0, 1.0, 1.0)
var velocity: Vector2 = Vector2(0, -40)
var lifetime: float = 1.0
var age: float = 0.0
var font_size: int = 12

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE

func setup(dmg: float, col: Color = Color(1.0, 1.0, 1.0), size: int = 12):
    text = str(int(dmg))
    color = col
    font_size = size

    velocity = Vector2(randf_range(-15, 15), randf_range(-50, -30))

func _process(delta: float):
    age += delta
    position += velocity * delta
    velocity.y -= 20.0 * delta
    if age >= lifetime:
        queue_free()
    queue_redraw()

func _draw():
    var alpha = clampf(1.0 - age / lifetime, 0.0, 1.0)

    var scale_t = 1.0 + 0.3 * (1.0 - minf(age * 8.0, 1.0))
    var font = ThemeDB.fallback_font
    var sz = int(float(font_size) * scale_t)

    draw_string(font, Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, Color(0, 0, 0, alpha * 0.5))

    draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, Color(color, alpha))
