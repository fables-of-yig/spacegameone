extends Node2D

signal finished

static var _tex: Texture2D

const TOTAL_FRAMES: int = 69
const FRAME_W: int = 512
const FRAME_H: int = 512
const GRID_COLS: int = 8
const INTRO_END: int = 64       # frames 0-63 = intro
const LOOP_START: int = 64      # frames 64-68 = loop
const LOOP_END: int = 69        # exclusive
const INTRO_FPS: float = 24.0
const LOOP_FPS: float = 16.0
const LOOP_DURATION: float = 4.5
const SHIP_APPEAR_TIME: float = 1.8
const CONTROL_DELAY: float = 0.2

enum Phase { INTRO, LOOP, REVERSE }

var phase: int = Phase.INTRO
var frame: int = 0
var timer: float = 0.0
var loop_timer: float = 0.0
var draw_scale: float = 1.0
var _ship_spawned: bool = false
var _control_granted: bool = false
var _target_ship: Node2D = null
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_timer: float = 0.0
var _rotation_offset: float = 0.0

func _ready():
	_rotation_offset = randf() * TAU
	process_mode = PROCESS_MODE_PAUSABLE
	if _tex == null:
		_tex = load("res://Space/art/vfx/warpportal.png")

func setup(scale_size: float, ship: Node2D = null):
	if _tex == null:
		_tex = load("res://Space/art/vfx/warpportal.png")
	var sprite_size = maxf(FRAME_W, FRAME_H)
	draw_scale = (scale_size * 7.0) / sprite_size
	z_index = -1
	_target_ship = ship
	if _target_ship and is_instance_valid(_target_ship):
		_target_ship.visible = false
		_target_ship.set_process(false)
		_target_ship.set_physics_process(false)
		if _target_ship is Area2D:
			_target_ship.monitorable = false
			_target_ship.monitoring = false

func _update_shake(delta: float, intensity: float):
	_shake_timer += delta * 45.0
	var jx = sin(_shake_timer * 3.7) * cos(_shake_timer * 5.3) + sin(_shake_timer * 11.1) * 0.4
	var jy = cos(_shake_timer * 4.1) * sin(_shake_timer * 6.7) + cos(_shake_timer * 9.3) * 0.4
	_shake_offset = Vector2(jx, jy) * intensity

func _process(delta: float):
	match phase:
		Phase.INTRO:
			timer += delta
			var progress = timer * INTRO_FPS / float(INTRO_END)
			var shake_str = lerpf(1.0, 3.0, progress) * draw_scale * 2.0
			_update_shake(delta, shake_str)
			var new_frame = int(timer * INTRO_FPS)
			if new_frame >= INTRO_END:
				phase = Phase.LOOP
				frame = LOOP_START
				timer = 0.0
				loop_timer = 0.0
				_shake_offset = Vector2.ZERO
				queue_redraw()
				return
			if new_frame != frame:
				frame = new_frame
			queue_redraw()

		Phase.LOOP:
			loop_timer += delta
			timer += delta
			var loop_frames = LOOP_END - LOOP_START
			var loop_frame = int(timer * LOOP_FPS) % loop_frames
			var new_frame = LOOP_START + loop_frame
			# Show the ship partway through the loop
			if not _ship_spawned and loop_timer >= SHIP_APPEAR_TIME:
				_ship_spawned = true
				if _target_ship and is_instance_valid(_target_ship):
					_target_ship.visible = true
					if _target_ship is Area2D:
						_target_ship.monitorable = true
						_target_ship.monitoring = true
			# Grant control shortly after ship appears
			if _ship_spawned and not _control_granted and loop_timer >= SHIP_APPEAR_TIME + CONTROL_DELAY:
				_control_granted = true
				if _target_ship and is_instance_valid(_target_ship):
					_target_ship.set_process(true)
					_target_ship.set_physics_process(true)
			if loop_timer >= LOOP_DURATION:
				phase = Phase.REVERSE
				frame = INTRO_END - 1
				timer = 0.0
				# Ensure control is granted if it wasn't already
				if not _control_granted and _target_ship and is_instance_valid(_target_ship):
					_target_ship.visible = true
					_target_ship.set_process(true)
					_target_ship.set_physics_process(true)
					if _target_ship is Area2D:
						_target_ship.monitorable = true
						_target_ship.monitoring = true
				queue_redraw()
				return
			if new_frame != frame:
				frame = new_frame
				queue_redraw()

		Phase.REVERSE:
			timer += delta
			# Frames 71->40 at 24fps, then pause 3 frames, then 2, 1, 0
			var reverse_frames_fast = INTRO_END - 1 - 35  # 63 down to 35 = 28 frames
			var fast_duration = float(reverse_frames_fast) / INTRO_FPS
			var pause_duration = 3.0 / INTRO_FPS
			var tail_duration = 3.0 / INTRO_FPS  # frames 2, 1, 0
			var new_frame: int
			if timer <= fast_duration:
				# 71 -> 40
				new_frame = (INTRO_END - 1) - int(timer * INTRO_FPS)
				new_frame = maxi(new_frame, 35)
			elif timer <= fast_duration + pause_duration:
				# hold blank for 3 frames worth of time
				new_frame = -2  # signal blank
			elif timer <= fast_duration + pause_duration + tail_duration:
				# frames 2, 1, 0
				var tail_time = timer - fast_duration - pause_duration
				var tail_idx = int(tail_time * INTRO_FPS)
				new_frame = 2 - mini(tail_idx, 2)
			else:
				finished.emit()
				queue_free()
				return
			var progress = timer / (fast_duration + pause_duration + tail_duration)
			var shake_str = lerpf(3.0, 0.5, progress) * draw_scale * 2.0
			_update_shake(delta, shake_str)
			if new_frame != frame:
				frame = new_frame
			queue_redraw()

func _draw():
	if _tex == null or frame < 0:
		return
	@warning_ignore("integer_division")
	var col = frame % GRID_COLS
	@warning_ignore("integer_division")
	var row = frame / GRID_COLS
	var src = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
	var target_w = FRAME_W * draw_scale
	var target_h = FRAME_H * draw_scale
	var dst = Rect2(-target_w * 0.5 + _shake_offset.x, -target_h * 0.5 + _shake_offset.y, target_w, target_h)
	# Random rotation on intro/reverse frames, but keep the loop unrotated
	var use_rotation = phase != Phase.LOOP
	if use_rotation:
		draw_set_transform(Vector2.ZERO, _rotation_offset)
	draw_texture_rect_region(_tex, dst, src)
	if use_rotation:
		draw_set_transform(Vector2.ZERO, 0.0)
