extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const PsgIO = preload("res://Space/scripts/editor/psg/psg_io.gd")
const PsgPreview = preload("res://Space/scripts/editor/psg/psg_preview.gd")

# Full-screen modal that lets the author browse PixelPlanets body types,
# scrub seed + common shader params, optionally randomize colors, then
# bake a rotation strip PNG into the active content pack. Emits
# `applied(sprite_path, anim_frames, anim_fps, sidecar_path)` on a
# successful bake or `cancelled` if the user closes without baking.
#
# Open via `open(initial_type, initial_seed, target_dir, file_stem,
# sidecar_path)`. If `sidecar_path` exists, the panel restores type +
# seed + params + colors from it so re-edits don't lose tuning. The
# parent (system_editor) is responsible for converting `applied`'s
# arguments into the right POI or system-star data fields and for
# locating the right write directory based on whether the target is a
# planet/star POI or the system's central star.

signal cancelled
signal applied(sprite_path: String, anim_frames: int, anim_fps: float, sidecar_path: String)

const BOX_W: float = 820.0
const BOX_H: float = 680.0
const HEADER_H: float = 60.0
const FOOTER_H: float = 64.0
const LIST_W: float = 220.0
const ROW_H: float = 32.0
const PAD: float = 16.0

const SLIDER_W: float = 220.0
const SLIDER_H: float = 22.0
const SLIDER_ROW_H: float = 30.0
const SWATCH_H: float = 24.0
const SWATCH_GAP: float = 4.0

# Bake parameters are fixed for Phase 2 — Phase 3 can add controls.
const FRAME_COUNT: int = 32
const FPS: float = 12.0

var _selected_type: String = ""
var _current_seed: int = 0
var _row_rects: Array = []  # [{type_id, rect}]
var _close_rect: Rect2 = Rect2()
var _reroll_rect: Rect2 = Rect2()
var _randomize_rect: Rect2 = Rect2()
var _bake_rect: Rect2 = Rect2()
var _scroll: float = 0.0
var _list_viewport_h: float = 0.0
var _list_content_h: float = 0.0
var _baking: bool = false
var _bake_status: String = ""

# Bake target — set by caller via open(). Empty means "preview-only";
# the bake button is disabled in that case.
var _target_dir: String = ""
var _file_stem: String = ""
var _sidecar_path: String = ""

var _preview: Control = null

var _size_slider: HSlider = null
var _octaves_slider: HSlider = null
var _time_speed_slider: HSlider = null
var _light_angle_slider: HSlider = null

# Clickable swatch rects rebuilt every redraw, plus the popup that lets
# the user override a single color manually instead of having to keep
# Randomize-rolling. Indices map into the body's full color list as
# returned by get_colors().
var _palette_rects: Array = []  # [{ index: int, rect: Rect2 }]
var _color_picker_popup: PopupPanel = null
var _color_picker: ColorPicker = null
var _editing_color_index: int = -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_process(true)

	_preview = Control.new()
	_preview.set_script(PsgPreview)
	add_child(_preview)

	_color_picker_popup = PopupPanel.new()
	_color_picker_popup.exclusive = false
	_color_picker = ColorPicker.new()
	_color_picker.edit_alpha = false
	_color_picker.color_changed.connect(_on_color_picker_changed)
	_color_picker_popup.add_child(_color_picker)
	_color_picker_popup.popup_hide.connect(_on_color_picker_closed)
	add_child(_color_picker_popup)

	_size_slider = _make_slider(1.0, 50.0, 0.5, 9.0, "size")
	_octaves_slider = _make_slider(0.0, 20.0, 1.0, 5.0, "OCTAVES")
	# Anim speed multiplier: 0 = paused, 1 = native rate, 3 = sped up.
	# The slider is not bound to the shader's `time_speed` uniform —
	# psg_preview drives the body's update_time() at this rate instead,
	# because Planet.gd's get_multiplier cancels the shader uniform out.
	_time_speed_slider = _make_slider(0.0, 3.0, 0.05, 1.0, "anim_speed")
	_light_angle_slider = _make_slider(0.0, 360.0, 1.0, 45.0, "light_angle")

	_size_slider.value_changed.connect(_on_size_changed)
	_octaves_slider.value_changed.connect(_on_octaves_changed)
	_time_speed_slider.value_changed.connect(_on_time_speed_changed)
	_light_angle_slider.value_changed.connect(_on_light_angle_changed)


func _make_slider(min_v: float, max_v: float, step: float, default_v: float, slider_name: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = default_v
	s.name = slider_name
	add_child(s)
	return s


func open(initial_type: String = "GasPlanet", initial_seed: int = 0,
		target_dir: String = "", file_stem: String = "",
		sidecar_path: String = "") -> void:
	if not PsgIO.is_known_type(initial_type):
		initial_type = "GasPlanet"
	_selected_type = initial_type
	_current_seed = initial_seed
	_target_dir = target_dir.strip_edges().trim_suffix("/")
	_file_stem = file_stem.strip_edges()
	_sidecar_path = sidecar_path.strip_edges()
	_scroll = 0.0
	_baking = false
	_bake_status = ""
	visible = true
	_apply_selection_to_preview()
	_load_sidecar_if_any()
	_refresh_sliders_from_body()
	queue_redraw()


func close() -> void:
	_hide_color_picker()
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	var vp_size := get_viewport_rect().size
	if size != vp_size:
		size = vp_size
	_layout_controls()
	queue_redraw()


func _layout_controls() -> void:
	var box := _box_rect()
	if _preview != null:
		var preview_size: float = 320.0
		var preview_x: float = box.position.x + LIST_W + PAD * 2.0
		var preview_y: float = box.position.y + HEADER_H + PAD
		_preview.position = Vector2(preview_x, preview_y)
		_preview.size = Vector2(preview_size, preview_size)

	var slider_x: float = box.position.x + LIST_W + PAD * 3.0 + 320.0
	var slider_y: float = box.position.y + HEADER_H + PAD + 6.0
	for s in [_size_slider, _octaves_slider, _time_speed_slider, _light_angle_slider]:
		if s == null:
			continue
		s.position = Vector2(slider_x, slider_y + 14.0)
		s.size = Vector2(SLIDER_W, SLIDER_H)
		slider_y += SLIDER_ROW_H + 10.0


func _apply_selection_to_preview() -> void:
	if _preview == null:
		return
	if _preview.has_method("set_body_type"):
		_preview.set_body_type(_selected_type)
	if _preview.has_method("set_seed"):
		_preview.set_seed(_current_seed)
	if _preview.has_method("set_light_angle_deg") and _light_angle_slider != null:
		_preview.set_light_angle_deg(_light_angle_slider.value)
	if _preview.has_method("set_anim_speed") and _time_speed_slider != null:
		_preview.set_anim_speed(_time_speed_slider.value)


func _refresh_sliders_from_body() -> void:
	if _preview == null:
		return
	# Mirror the freshly-instantiated body's per-body shader defaults
	# (size, OCTAVES) into the sliders without re-triggering the
	# value_changed handlers — otherwise we'd immediately push the
	# panel's init-defaults back onto the body and lose its tuned
	# values. The time_speed slider is intentionally NOT refreshed here:
	# it controls our anim_speed multiplier, which lives on the preview
	# and is independent of whichever body is currently loaded.
	var size_v: Variant = _preview.get_shader_param("size", null)
	var oct_v: Variant = _preview.get_shader_param("OCTAVES", null)
	if _size_slider != null and size_v != null:
		_size_slider.set_block_signals(true)
		_size_slider.value = float(size_v)
		_size_slider.set_block_signals(false)
	if _octaves_slider != null and oct_v != null:
		_octaves_slider.set_block_signals(true)
		_octaves_slider.value = float(oct_v)
		_octaves_slider.set_block_signals(false)


func _load_sidecar_if_any() -> void:
	if _sidecar_path.is_empty():
		return
	var data: Dictionary = PsgIO.read_sidecar(_sidecar_path)
	if data.is_empty():
		return
	var saved_type: String = str(data.get("type", ""))
	if PsgIO.is_known_type(saved_type):
		_selected_type = saved_type
	_current_seed = int(data.get("seed", _current_seed))
	if _preview != null:
		_preview.set_body_type(_selected_type)
		_preview.set_seed(_current_seed)
	var params_v: Variant = data.get("params", null)
	if typeof(params_v) == TYPE_DICTIONARY:
		var params: Dictionary = params_v
		if params.has("size") and _size_slider != null:
			_size_slider.set_block_signals(true)
			_size_slider.value = float(params["size"])
			_size_slider.set_block_signals(false)
			_preview.apply_shader_param("size", float(params["size"]))
		if params.has("OCTAVES") and _octaves_slider != null:
			_octaves_slider.set_block_signals(true)
			_octaves_slider.value = float(int(params["OCTAVES"]))
			_octaves_slider.set_block_signals(false)
			_preview.apply_shader_param("OCTAVES", int(params["OCTAVES"]))
		if params.has("time_speed") and _time_speed_slider != null:
			# Saved as the panel's anim_speed multiplier (post-fix); old
			# sidecars stored the cancelled-out shader uniform value (0..1)
			# which is still inside the new slider range, so clamping is
			# enough — no migration shim needed.
			var saved_speed: float = clampf(float(params["time_speed"]),
				_time_speed_slider.min_value,
				_time_speed_slider.max_value)
			_time_speed_slider.set_block_signals(true)
			_time_speed_slider.value = saved_speed
			_time_speed_slider.set_block_signals(false)
			_preview.set_anim_speed(saved_speed)
		if params.has("light_angle") and _light_angle_slider != null:
			_light_angle_slider.set_block_signals(true)
			_light_angle_slider.value = float(params["light_angle"])
			_light_angle_slider.set_block_signals(false)
			_preview.set_light_angle_deg(float(params["light_angle"]))
	var colors_v: Variant = data.get("colors", null)
	if colors_v != null:
		var pca := PsgIO.colors_from_json(colors_v)
		if pca.size() > 0:
			_preview.set_colors(pca)


func _on_size_changed(v: float) -> void:
	if _preview != null:
		_preview.apply_shader_param("size", v)


func _on_octaves_changed(v: float) -> void:
	if _preview != null:
		_preview.apply_shader_param("OCTAVES", int(v))


func _on_time_speed_changed(v: float) -> void:
	if _preview != null:
		_preview.set_anim_speed(v)


func _on_light_angle_changed(v: float) -> void:
	if _preview != null:
		_preview.set_light_angle_deg(v)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = min(_scroll + 36.0, max(0.0, _list_content_h - _list_viewport_h))
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = max(_scroll - 36.0, 0.0)
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _close_rect.has_point(mb.position):
				_do_cancel()
				accept_event()
				return
			if _reroll_rect.has_point(mb.position):
				_reroll_seed()
				accept_event()
				return
			if _randomize_rect.has_point(mb.position):
				_randomize_colors()
				accept_event()
				return
			if _bake_rect.has_point(mb.position):
				_do_bake()
				accept_event()
				return
			for swatch in _palette_rects:
				if (swatch["rect"] as Rect2).has_point(mb.position):
					_open_color_picker_for(int(swatch["index"]),
						(swatch["rect"] as Rect2))
					accept_event()
					return
			for row in _row_rects:
				if (row["rect"] as Rect2).has_point(mb.position):
					_select_type(str(row["type_id"]))
					accept_event()
					return
			if not _box_rect().has_point(mb.position) and not _baking:
				_do_cancel()
				accept_event()
				return


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE and not _baking:
			_do_cancel()
			get_viewport().set_input_as_handled()


func _select_type(type_id: String) -> void:
	if not PsgIO.is_known_type(type_id):
		return
	if type_id == _selected_type:
		return
	# The color-picker is editing an index in the OLD body's palette;
	# new bodies have different palette sizes (e.g. Rivers=10, Asteroid=3)
	# so reusing the open picker would splice into the wrong slot.
	_hide_color_picker()
	_selected_type = type_id
	_apply_selection_to_preview()
	_refresh_sliders_from_body()


func _reroll_seed() -> void:
	_current_seed = randi() % 10000
	if _preview != null and _preview.has_method("set_seed"):
		_preview.set_seed(_current_seed)


func _randomize_colors() -> void:
	if _preview != null and _preview.has_method("randomize_colors"):
		_preview.randomize_colors()


func _open_color_picker_for(index: int, swatch_rect: Rect2) -> void:
	if _preview == null or not _preview.has_method("get_colors"):
		return
	if _color_picker_popup == null or _color_picker == null:
		return
	var colors: Array = _preview.get_colors()
	if index < 0 or index >= colors.size():
		return
	var current_v: Variant = colors[index]
	var current: Color = current_v if current_v is Color else Color.MAGENTA

	_editing_color_index = index
	_color_picker.set_block_signals(true)
	_color_picker.color = current
	_color_picker.set_block_signals(false)

	# Anchor the popup directly under the clicked swatch in screen
	# coordinates. get_screen_position() bakes in any window-chrome
	# offset so the popup lines up correctly when the game runs windowed.
	# Sized for ColorPicker's full layout (hue ring + sliders + hex).
	var pop_size := Vector2i(320, 420)
	var screen_origin: Vector2 = get_screen_position()
	var anchor: Vector2 = screen_origin + swatch_rect.position \
		+ Vector2(0, swatch_rect.size.y + 4.0)
	# Keep the popup on-screen if the swatch is near a right/bottom edge.
	var screen_size: Vector2 = get_viewport_rect().size
	var clamped_x: float = clampf(anchor.x,
		screen_origin.x,
		screen_origin.x + max(0.0, screen_size.x - float(pop_size.x)))
	var clamped_y: float = clampf(anchor.y,
		screen_origin.y,
		screen_origin.y + max(0.0, screen_size.y - float(pop_size.y)))
	_color_picker_popup.popup(Rect2i(
		Vector2i(int(clamped_x), int(clamped_y)),
		pop_size))


func _on_color_picker_changed(c: Color) -> void:
	if _preview == null or not _preview.has_method("get_colors"):
		return
	if _editing_color_index < 0:
		return
	var colors: Array = _preview.get_colors()
	if _editing_color_index >= colors.size():
		return
	var updated := PackedColorArray()
	for i in colors.size():
		var col_v: Variant = colors[i]
		var col: Color = col_v if col_v is Color else Color.MAGENTA
		if i == _editing_color_index:
			# Preserve the body's authored alpha — the picker has
			# edit_alpha disabled, so `c.a` is always 1.0 even when the
			# original swatch was partially transparent.
			updated.append(Color(c.r, c.g, c.b, col.a))
		else:
			updated.append(col)
	if _preview.has_method("set_colors"):
		_preview.set_colors(updated)
	queue_redraw()


func _on_color_picker_closed() -> void:
	_editing_color_index = -1


func _do_bake() -> void:
	if _baking:
		return
	if _target_dir.is_empty() or _file_stem.is_empty():
		_bake_status = "No target dir set — cannot bake."
		queue_redraw()
		return
	if _preview == null or not _preview.has_method("bake_strip_frames"):
		_bake_status = "Preview not ready."
		queue_redraw()
		return

	_baking = true
	_bake_status = "Baking %d frames..." % FRAME_COUNT
	queue_redraw()

	PsgIO.ensure_dir(_target_dir)
	var frames: Array = await _preview.bake_strip_frames(FRAME_COUNT)
	if frames.size() != FRAME_COUNT:
		_baking = false
		_bake_status = "Bake captured %d/%d frames; aborting." % [frames.size(), FRAME_COUNT]
		queue_redraw()
		return

	var sprite_path: String = "%s/%s.png" % [_target_dir, _file_stem]
	if not PsgIO.write_strip_png(frames, sprite_path):
		_baking = false
		_bake_status = "PNG write failed."
		queue_redraw()
		return

	var sidecar_path: String = PsgIO.sidecar_path_for(sprite_path)
	PsgIO.write_sidecar(sidecar_path, _serialize_state())

	_baking = false
	_bake_status = ""
	_hide_color_picker()
	visible = false
	applied.emit(sprite_path, FRAME_COUNT, FPS, sidecar_path)


func _serialize_state() -> Dictionary:
	var data: Dictionary = {
		"type": _selected_type,
		"seed": _current_seed,
		"params": {
			"size": _size_slider.value if _size_slider != null else 0.0,
			"OCTAVES": int(_octaves_slider.value) if _octaves_slider != null else 0,
			"time_speed": _time_speed_slider.value if _time_speed_slider != null else 0.0,
			"light_angle": _light_angle_slider.value if _light_angle_slider != null else 0.0,
		},
		"anim": {
			"frames": FRAME_COUNT,
			"fps": FPS,
		},
	}
	if _preview != null and _preview.has_method("get_colors"):
		data["colors"] = PsgIO.colors_to_json(_preview.get_colors())
	return data


func _do_cancel() -> void:
	_hide_color_picker()
	visible = false
	cancelled.emit()


func _hide_color_picker() -> void:
	if _color_picker_popup != null and _color_picker_popup.visible:
		_color_picker_popup.hide()
	_editing_color_index = -1


func _box_rect() -> Rect2:
	return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw() -> void:
	if not visible:
		return
	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
	var box := _box_rect()
	UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()

	draw_string(font, box.position + Vector2(24, 36),
		"PLANET GENERATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		UIPanels.TEXT_PANEL)
	var sub: String = "Pick a body, scrub seed + params, Randomize Colors, then Bake & Apply."
	if _target_dir.is_empty() or _file_stem.is_empty():
		sub = "Preview only — no bake target provided. Reopen from a planet/star field."
	draw_string(font, box.position + Vector2(24, 56),
		sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

	_draw_type_list(box, font, mouse_pos)
	_draw_preview_frame(box, font)
	_draw_slider_labels(box, font)
	_draw_palette(box, font, mouse_pos)
	_draw_footer(box, font, mouse_pos)


func _draw_type_list(box: Rect2, font: Font, mouse_pos: Vector2) -> void:
	var list_x: float = box.position.x + PAD
	var list_y: float = box.position.y + HEADER_H + PAD
	var list_w: float = LIST_W
	var list_h: float = box.size.y - HEADER_H - FOOTER_H - PAD * 2.0
	var list_rect := Rect2(list_x, list_y, list_w, list_h)

	draw_rect(list_rect, Color(0.05, 0.08, 0.14, 0.92))
	draw_rect(list_rect, Color(0.35, 0.55, 0.78, 0.9), false, 1.0)

	_list_viewport_h = list_h
	_list_content_h = float(PsgIO.TYPE_ORDER.size()) * ROW_H + 8.0
	if _scroll > max(0.0, _list_content_h - _list_viewport_h):
		_scroll = max(0.0, _list_content_h - _list_viewport_h)

	_row_rects.clear()
	for i in PsgIO.TYPE_ORDER.size():
		var type_id: String = str(PsgIO.TYPE_ORDER[i])
		var r_y: float = list_y + 4.0 - _scroll + float(i) * ROW_H
		var rect := Rect2(list_x + 4, r_y, list_w - 8, ROW_H - 2)
		_row_rects.append({"type_id": type_id, "rect": rect})

		if rect.position.y + rect.size.y < list_y:
			continue
		if rect.position.y > list_y + list_h:
			continue

		var is_sel := type_id == _selected_type
		var hover := rect.has_point(mouse_pos)
		var bg: Color
		if is_sel:
			bg = Color(0.28, 0.5, 0.78, 0.95)
		elif hover:
			bg = Color(0.18, 0.28, 0.42, 0.85)
		else:
			bg = Color(0.1, 0.14, 0.22, 0.55)
		draw_rect(rect, bg)

		var label: String = PsgIO.type_label(type_id)
		var text_col: Color
		if is_sel:
			text_col = Color(1, 1, 1, 1)
		else:
			text_col = Color(0.84, 0.92, 1.0, 1)
		draw_string(font, rect.position + Vector2(12, 20),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)


func _draw_preview_frame(box: Rect2, font: Font) -> void:
	var frame_x: float = box.position.x + LIST_W + PAD * 2.0
	var frame_y: float = box.position.y + HEADER_H + PAD
	var frame_size: float = 320.0
	var frame_rect := Rect2(frame_x, frame_y, frame_size, frame_size)

	draw_rect(frame_rect, Color(0.02, 0.02, 0.04, 1.0))
	draw_rect(frame_rect, Color(0.3, 0.6, 0.85, 0.9), false, 1.0)

	var label: String = "%s   |   seed %d" % [PsgIO.type_label(_selected_type), _current_seed]
	draw_string(font, Vector2(frame_x + 8, frame_y + frame_size + 18),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)


func _draw_slider_labels(box: Rect2, font: Font) -> void:
	var label_x: float = box.position.x + LIST_W + PAD * 3.0 + 320.0
	var label_y: float = box.position.y + HEADER_H + PAD + 6.0
	var labels: Array = [
		["Noise size", _size_slider.value if _size_slider != null else 0.0, "%.1f"],
		["Octaves", _octaves_slider.value if _octaves_slider != null else 0.0, "%d"],
		["Time speed", _time_speed_slider.value if _time_speed_slider != null else 0.0, "%.2f"],
		["Light angle", _light_angle_slider.value if _light_angle_slider != null else 0.0, "%.0f°"],
	]
	for entry_v in labels:
		var entry: Array = entry_v
		var lbl: String = str(entry[0])
		var v: float = float(entry[1])
		var fmt: String = str(entry[2])
		var value_text: String = (fmt % int(v)) if fmt == "%d" else (fmt % v)
		draw_string(font, Vector2(label_x, label_y),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
		draw_string(font, Vector2(label_x + SLIDER_W - 60, label_y),
			value_text, HORIZONTAL_ALIGNMENT_RIGHT, 60, 11, UIPanels.TEXT_PANEL)
		label_y += SLIDER_ROW_H + 10.0


func _draw_palette(box: Rect2, _font: Font, mouse_pos: Vector2) -> void:
	_palette_rects.clear()
	if _preview == null or not _preview.has_method("get_colors"):
		return
	var palette_x: float = box.position.x + LIST_W + PAD * 2.0
	var palette_y: float = box.position.y + HEADER_H + PAD + 320.0 + 32.0
	var palette_w: float = box.size.x - LIST_W - PAD * 3.0
	var colors: Array = _preview.get_colors()
	if colors.is_empty():
		return
	var swatch_w: float = max(8.0, (palette_w - SWATCH_GAP * float(colors.size() - 1)) / float(colors.size()))
	for i in colors.size():
		var col_v: Variant = colors[i]
		var col: Color = col_v if col_v is Color else Color.MAGENTA
		var rect := Rect2(palette_x + float(i) * (swatch_w + SWATCH_GAP),
			palette_y, swatch_w, SWATCH_H)
		draw_rect(rect, col)
		var border_col: Color = Color(1, 1, 1, 0.9) if rect.has_point(mouse_pos) \
			else Color(0, 0, 0, 0.6)
		draw_rect(rect, border_col, false, 1.0)
		_palette_rects.append({ "index": i, "rect": rect })


func _draw_footer(box: Rect2, font: Font, mouse_pos: Vector2) -> void:
	var btn_h: float = 32.0
	var footer_y: float = box.position.y + box.size.y - btn_h - 16.0

	var btn_w: float = 130.0
	var btn_x: float = box.position.x + LIST_W + PAD * 2.0

	_reroll_rect = Rect2(btn_x, footer_y, btn_w, btn_h)
	var reroll_hover := _reroll_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _reroll_rect, reroll_hover,
		Color(0.45, 0.65, 0.95, 1.0))
	draw_string(font, _reroll_rect.position + Vector2(20, 21),
		"RE-ROLL SEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.98, 1.0, 0.95, 1) if reroll_hover else Color(0.85, 0.95, 1.0, 1))

	btn_x += btn_w + 8.0
	_randomize_rect = Rect2(btn_x, footer_y, btn_w + 10, btn_h)
	var rand_hover := _randomize_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _randomize_rect, rand_hover,
		Color(0.7, 0.5, 0.9, 1.0))
	draw_string(font, _randomize_rect.position + Vector2(8, 21),
		"RANDOMIZE COLORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 0.97, 1, 1) if rand_hover else Color(0.9, 0.82, 1.0, 1))

	btn_x += btn_w + 18.0
	_bake_rect = Rect2(btn_x, footer_y, btn_w + 20, btn_h)
	var can_bake: bool = (not _baking) and (not _target_dir.is_empty()) and (not _file_stem.is_empty())
	var bake_hover := _bake_rect.has_point(mouse_pos) and can_bake
	var bake_bg: Color = Color(0.4, 0.85, 0.5, 1.0) if can_bake else Color(0.3, 0.35, 0.3, 1.0)
	UIPanels.draw_button_bg(self, _bake_rect, bake_hover, bake_bg)
	var bake_label: String = "BAKING..." if _baking else "BAKE & APPLY"
	var bake_text_col: Color = Color(1, 1, 1, 1) if can_bake else Color(0.6, 0.65, 0.6, 1)
	draw_string(font, _bake_rect.position + Vector2(16, 21),
		bake_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, bake_text_col)

	var close_w: float = 100.0
	_close_rect = Rect2(box.position.x + box.size.x - close_w - 20,
		footer_y, close_w, btn_h)
	var close_hover := _close_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _close_rect, close_hover,
		Color(0.9, 0.45, 0.4, 1.0))
	draw_string(font, _close_rect.position + Vector2(24, 21),
		"CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 0.95, 0.95, 1) if close_hover else Color(0.85, 0.6, 0.6, 1))

	var footer_text: String = "Bake writes a %d-frame strip @ %.0f fps to %s.png. Esc closes." \
		% [FRAME_COUNT, FPS, _file_stem if not _file_stem.is_empty() else "<stem>"]
	if not _bake_status.is_empty():
		footer_text = _bake_status
	draw_string(font, Vector2(box.position.x + 24,
		box.position.y + box.size.y - 12),
		footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.55, 0.78, 0.85, 1))
