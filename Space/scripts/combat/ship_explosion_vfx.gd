extends Node2D

signal finished

static var _tex: Texture2D

const FRAME_W: int = 64
const FRAME_H: int = 64
const GRID_COLS: int = 4
const FRAME_COUNT: int = 24
const FPS: float = 18.0

var frame: int = 0
var timer: float = 0.0
var draw_scale: float = 1.0
var _rotation_offset: float = 0.0

func _ready():
	process_mode = PROCESS_MODE_PAUSABLE
	if _tex == null:
		_tex = load("res://Space/art/vfx/shipexplosion.png")
	_rotation_offset = randf() * TAU

func setup(ship_size: float):
	if _tex == null:
		_tex = load("res://Space/art/vfx/shipexplosion.png")
	var sprite_size = maxf(FRAME_W, FRAME_H)
	draw_scale = (ship_size * 2.6) / sprite_size
	z_index = 10

func _process(delta: float):
	timer += delta
	var new_frame = int(timer * FPS)
	if new_frame >= FRAME_COUNT:
		finished.emit()
		queue_free()
		return
	if new_frame != frame:
		frame = new_frame
		queue_redraw()

func _draw():
	if _tex == null:
		return
	@warning_ignore("integer_division")
	var col = frame % GRID_COLS
	@warning_ignore("integer_division")
	var row = frame / GRID_COLS
	var src = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
	var target_w = FRAME_W * draw_scale
	var target_h = FRAME_H * draw_scale
	var dst = Rect2(-target_w * 0.5, -target_h * 0.5, target_w, target_h)
	draw_set_transform(Vector2.ZERO, _rotation_offset)
	draw_texture_rect_region(_tex, dst, src)
	draw_set_transform(Vector2.ZERO, 0.0)
