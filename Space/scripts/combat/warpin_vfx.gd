extends Node2D

static var _tex: Texture2D

var frame: int = 0
var frame_count: int = 20
var fps: float = 18.0
var timer: float = 0.0
var draw_scale: float = 1.0

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    if _tex == null:
        _tex = load("res://Space/art/vfx/warpin.png")

func setup(ship_size: float):
    if _tex == null:
        _tex = load("res://Space/art/vfx/warpin.png")
    @warning_ignore("integer_division")
    var frame_w = _tex.get_width() / frame_count
    var frame_h = _tex.get_height()
    var sprite_size = maxf(frame_w, frame_h)
    draw_scale = (ship_size * 2.6) / sprite_size
    z_index = 5

func _process(delta: float):
    timer += delta
    var new_frame = int(timer * fps)
    if new_frame >= frame_count:
        queue_free()
        return
    if new_frame != frame:
        frame = new_frame
        queue_redraw()

func _draw():
    if _tex == null:
        return
    var tex_w = _tex.get_width()
    var tex_h = _tex.get_height()
    @warning_ignore("integer_division")
    var fw = tex_w / frame_count
    var fh = tex_h
    var src = Rect2(frame * fw, 0, fw, fh)
    var target_w = fw * draw_scale
    var target_h = fh * draw_scale
    var dst = Rect2(-target_w * 0.5, -target_h * 0.5, target_w, target_h)
    draw_texture_rect_region(_tex, dst, src)
