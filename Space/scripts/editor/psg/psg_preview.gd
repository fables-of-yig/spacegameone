extends Control

const PsgIO = preload("res://Space/scripts/editor/psg/psg_io.gd")

# Live SubViewport-based preview of a PixelPlanets body type. The body
# scene is instantiated inside a 200² SubViewport and displayed via a
# TextureRect with STRETCH_KEEP_ASPECT_CENTERED + TEXTURE_FILTER_NEAREST,
# so the texture scales up to fill the preview frame while staying
# centered and pixel-crisp.
#
# The body scenes extend `res://Space/vendor/pixel_planets/Planet.gd`,
# which defines a common interface: set_pixels(amount), set_seed(sd),
# set_light(pos), set_rotates(r). Their internal `_process` advances
# `time` for animated effects (clouds, plasma, etc.) so the preview
# animates on its own once instantiated.

const VIEWPORT_RES: int = 200  # pixels — matches the size we drive into set_pixels()

var _viewport: SubViewport = null
var _texture_rect: TextureRect = null
var _body: Node = null

var _current_type: String = ""
var _current_seed: int = 0
var _current_light: Vector2 = Vector2(0.3, 0.3)

# Animation rate multiplier driven by the panel's "Time speed" slider.
# Planet.gd's get_multiplier divides by the shader's `time_speed`, and
# every shader then multiplies by `time_speed`, so scrubbing that
# uniform alone cancels out. We disable the body's own _process and
# drive `update_time(_local_time)` from this script instead, so the
# slider becomes a real animation-rate knob.
var _anim_speed: float = 1.0
var _local_time: float = 1000.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	clip_contents = true
	_ensure_viewport()
	set_process(true)


func _ensure_viewport() -> void:
	if _viewport != null:
		return
	# Render the planet offscreen at VIEWPORT_RES² in the SubViewport, then
	# display it via a TextureRect with KEEP_ASPECT_CENTERED so the texture
	# scales to fill the preview frame and stays centered. A
	# SubViewportContainer with stretch=false would have drawn the
	# 200² texture at the top-left of the larger preview frame instead of
	# centering or scaling it.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEWPORT_RES, VIEWPORT_RES)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	add_child(_viewport)

	_texture_rect = TextureRect.new()
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_texture_rect)


func set_body_type(type_id: String) -> bool:
	_ensure_viewport()
	if type_id == _current_type and _body != null:
		return true
	var scene_path: String = PsgIO.scene_path_for(type_id)
	if scene_path.is_empty():
		push_warning("psg_preview: unknown body type '%s'" % type_id)
		return false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("psg_preview: failed to load scene '%s'" % scene_path)
		return false
	var instance: Node = packed.instantiate()
	if instance == null:
		push_warning("psg_preview: failed to instantiate '%s'" % scene_path)
		return false

	if _body != null:
		_body.queue_free()
		_body = null
	_viewport.add_child(instance)
	_body = instance
	_current_type = type_id

	# Vendored PixelPlanets scenes ship with root-Control anchors tuned
	# for the much larger upstream demo (PRESET_FULL_RECT + offset_right
	# ~ -412). In our 200² SubViewport those resolve to a negative-size
	# rect that shifts every inner ColorRect ~100 px left of x=0, so the
	# planet renders as a half-circle clipped on the right. Pin the root
	# to fill the viewport so the ColorRects render where their offsets
	# expect (parent origin = viewport origin).
	if _body is Control:
		var root_ctrl: Control = _body
		root_ctrl.set_anchors_preset(PRESET_FULL_RECT)
		root_ctrl.offset_left = 0
		root_ctrl.offset_top = 0
		root_ctrl.offset_right = 0
		root_ctrl.offset_bottom = 0

	# Suppress Planet.gd's _process so our anim_speed-driven update_time
	# call is the only thing advancing the shader's `time` uniform.
	_body.set_process(false)
	_local_time = 1000.0

	_apply_seed(_current_seed)
	_apply_light(_current_light)
	if _body.has_method("set_pixels"):
		_body.set_pixels(VIEWPORT_RES)
	return true


func set_anim_speed(speed: float) -> void:
	_anim_speed = max(0.0, speed)


func _process(delta: float) -> void:
	if _body == null:
		return
	# Bake takes exclusive control of `time` via set_custom_time; skip
	# our update so we don't fight it.
	if bool(_body.get("override_time")):
		return
	if _anim_speed <= 0.0:
		return
	_local_time += delta * _anim_speed
	if _body.has_method("update_time"):
		_body.update_time(_local_time)


func set_seed(seed_value: int) -> void:
	_current_seed = seed_value
	_apply_seed(seed_value)


func set_light(pos: Vector2) -> void:
	_current_light = pos
	_apply_light(pos)


func get_current_type() -> String:
	return _current_type


func get_current_seed() -> int:
	return _current_seed


func get_body() -> Node:
	return _body


func get_viewport_resolution() -> int:
	return VIEWPORT_RES


# Light position parameter is in [0,1]^2 UV space. Mapping a 0..2π angle
# onto a unit circle centered at (0.5, 0.5) keeps the light direction
# intuitive ("0° = 3 o'clock"), with a radius of 0.25 that matches the
# upstream demo's default light_origin (around (0.39, 0.39)).
func set_light_angle_deg(angle_deg: float) -> void:
	var theta: float = deg_to_rad(angle_deg)
	var r: float = 0.25
	set_light(Vector2(0.5 + cos(theta) * r, 0.5 + sin(theta) * r))


func set_rotates(angle_rad: float) -> void:
	if _body != null and _body.has_method("set_rotates"):
		_body.set_rotates(angle_rad)


func set_custom_time(t: float) -> void:
	if _body != null and _body.has_method("set_custom_time"):
		_body.set_custom_time(t)


# Toggles the body's `override_time` flag (defined on the upstream base
# Planet.gd). When true, `_process` stops calling `update_time` so the
# shader stays at whatever time was last set via `set_custom_time` —
# required for deterministic frame capture during baking.
func set_override_time(enabled: bool) -> void:
	if _body != null:
		_body.set("override_time", enabled)


func apply_shader_param(uniform_name: String, value: Variant) -> void:
	if _body == null:
		return
	for child in _body.get_children():
		var mat_v: Variant = child.get("material")
		if mat_v is ShaderMaterial:
			(mat_v as ShaderMaterial).set_shader_parameter(uniform_name, value)


func get_shader_param(uniform_name: String, default_value: Variant = null) -> Variant:
	if _body == null:
		return default_value
	for child in _body.get_children():
		var mat_v: Variant = child.get("material")
		if mat_v is ShaderMaterial:
			var v: Variant = (mat_v as ShaderMaterial).get_shader_parameter(uniform_name)
			if v != null:
				return v
	return default_value


func randomize_colors() -> void:
	if _body != null and _body.has_method("randomize_colors"):
		_body.randomize_colors()


func get_colors() -> Array:
	if _body == null or not _body.has_method("get_colors"):
		return []
	var v: Variant = _body.get_colors()
	var out: Array = []
	if typeof(v) == TYPE_PACKED_COLOR_ARRAY:
		for c in (v as PackedColorArray):
			out.append(c)
	elif typeof(v) == TYPE_ARRAY:
		for c_v in (v as Array):
			if c_v is Color:
				out.append(c_v)
	return out


func set_colors(colors: PackedColorArray) -> void:
	if _body != null and _body.has_method("set_colors"):
		_body.set_colors(colors)


# Captures `frame_count` frames of one full rotation+animation cycle and
# returns them as an Array of Image. Suspends the body's automatic time
# update so each frame corresponds to a deterministic shader state.
# Caller awaits this coroutine.
func bake_strip_frames(frame_count: int) -> Array:
	var frames: Array = []
	_ensure_viewport()
	if _body == null or _viewport == null or frame_count <= 0:
		return frames

	var previous_update_mode: SubViewport.UpdateMode = _viewport.render_target_update_mode
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_override_time(true)

	for i in frame_count:
		var t: float = float(i) / float(frame_count)
		set_custom_time(t)
		set_rotates(t * TAU)
		await RenderingServer.frame_post_draw
		var tex: ViewportTexture = _viewport.get_texture()
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		frames.append(img)

	set_override_time(false)
	_viewport.render_target_update_mode = previous_update_mode
	return frames


func _apply_seed(seed_value: int) -> void:
	if _body != null and _body.has_method("set_seed"):
		_body.set_seed(seed_value)


func _apply_light(pos: Vector2) -> void:
	if _body != null and _body.has_method("set_light"):
		_body.set_light(pos)
