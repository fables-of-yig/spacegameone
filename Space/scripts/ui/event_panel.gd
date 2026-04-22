extends Control


signal event_finished(effects: Array)
signal closed

var events_data: Dictionary = {}
var current_event: Dictionary = {}
var current_event_id: String = ""
var current_node_id: String = ""
var current_node: Dictionary = {}
var hovered_choice: int = -1
var collected_effects: Array = []

var _skip_close_frame: bool = false
var bg_art = null

# Dialogue box textures
var _box_tex: Texture2D = null
var _choice_tex: Texture2D = null
const BOX_W: float = 796.0
const BOX_H: float = 256.0

# Portrait area – covers the green square in dialogue_box.png
const PORTRAIT_RECT := Rect2(20, 19, 220, 218)
var _portrait_tex: Texture2D = null
## Maps speaker name → res:// path to portrait texture.
## Populate from outside:  event_panel.portrait_map["Captain"] = "res://Space/art/portraits/captain.png"
var portrait_map: Dictionary = {}

# Typewriter
var _full_text: String = ""
var _revealed_chars: int = 0
var _typewriter_speed: float = 40.0   # characters per second
var _typewriter_timer: float = 0.0
var _typewriter_done: bool = false

# Text layout inside the dialogue box (right of portrait)
const TEXT_LEFT: float = 260.0
const TEXT_RIGHT: float = 780.0
const TEXT_TOP: float = 33.0
const LINE_H: float = 22.0

const CHOICE_H_MIN: float = 44.0
const CHOICE_TEXT_W: float = BOX_W - 90.0   # usable text width inside a choice box
const CHOICE_LINE_H: float = 18.0           # line spacing for wrapped choice text
const CHOICE_PAD_TOP: float = 14.0          # top padding before first line
const CHOICE_PAD_BOT: float = 12.0          # bottom padding after last line

# VHS / static effect state
var _vhs_time: float = 0.0
var _vhs_roll_offset: float = 0.0       # current vertical roll displacement
var _vhs_roll_target: float = 0.0       # where the roll is heading
var _vhs_next_glitch: float = 0.0       # countdown to next roll glitch
var _vhs_noise_seed: int = 0            # changes each frame for noise
var _vhs_h_tear: float = -1.0           # y-position of horizontal tear (-1 = none)
## Speakers that get full static instead of a portrait (no portrait available).
var static_speakers: Dictionary = {}    # e.g. {"HARLEN": true}

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	_box_tex = load("res://Space/art/ui/dialogue_box.png")
	_choice_tex = load("res://Space/art/ui/dialogue_choicebox.png")


func open_event(all_events: Dictionary, event_id: String):
	events_data = all_events
	if not events_data.has(event_id):
		push_warning("Event not found: " + event_id)
		return
	current_event_id = event_id
	current_event = events_data[event_id]
	collected_effects.clear()
	_go_to_node("start")
	visible = true
	_skip_close_frame = true

	if bg_art and DataManager.encounter_art.has(event_id):
		var art_data = DataManager.encounter_art[event_id]
		bg_art.start_art(art_data.get("bg_art", ""), art_data.get("params", {}))


func _go_to_node(node_id: String):
	var nodes: Dictionary = current_event.get("nodes", {})
	if not nodes.has(node_id):
		_close()
		return
	current_node_id = node_id
	current_node = nodes[node_id]
	hovered_choice = -1

	# Reset typewriter
	_full_text = GameManager.substitute_tags(current_node.get("text", ""))
	_revealed_chars = 0
	_typewriter_timer = 0.0
	_typewriter_done = false

	# Load portrait for this speaker
	var speaker: String = current_node.get("speaker", "")
	_portrait_tex = null
	if portrait_map.has(speaker):
		var path = portrait_map[speaker]
		if ResourceLoader.exists(path):
			_portrait_tex = load(path)

	var effects: Array = current_node.get("effects", [])
	for eff in effects:
		collected_effects.append(eff)

	queue_redraw()


func _close():
	if bg_art and bg_art.active:
		bg_art.stop_art()
	visible = false
	event_finished.emit(collected_effects)
	closed.emit()


func _process(delta: float):
	if not visible:
		return
	if _skip_close_frame:
		_skip_close_frame = false
		return

	# Advance typewriter
	if not _typewriter_done:
		_typewriter_timer += delta
		var new_chars := int(_typewriter_timer * _typewriter_speed)
		if new_chars > _full_text.length():
			new_chars = _full_text.length()
		if new_chars != _revealed_chars:
			_revealed_chars = new_chars
			if _revealed_chars >= _full_text.length():
				_typewriter_done = true

	# VHS effect timers
	_vhs_time += delta
	_vhs_noise_seed = randi()
	# Roll glitch: occasionally kick the image vertically (values are 0-1 ratio of portrait height)
	_vhs_next_glitch -= delta
	if _vhs_next_glitch <= 0:
		_vhs_next_glitch = randf_range(2.0, 6.0)
		# Most rolls are subtle, but occasionally go big (up to 50% of the portrait)
		var intensity := randf()
		if intensity > 0.85:
			_vhs_roll_target = randf_range(0.3, 0.55) * (1.0 if randf() > 0.5 else -1.0)
		else:
			_vhs_roll_target = randf_range(0.05, 0.2) * (1.0 if randf() > 0.5 else -1.0)
		_vhs_h_tear = randf_range(0.1, 0.9)
	# Decay roll back to 0
	if absf(_vhs_roll_target) > 0.01:
		_vhs_roll_offset = lerpf(_vhs_roll_offset, _vhs_roll_target, 10.0 * delta)
		_vhs_roll_target = lerpf(_vhs_roll_target, 0.0, 3.0 * delta)
	else:
		_vhs_roll_offset = lerpf(_vhs_roll_offset, 0.0, 6.0 * delta)
		_vhs_roll_target = 0.0
	# Horizontal tear decay
	if _vhs_h_tear >= 0:
		_vhs_h_tear -= delta * 3.0

	queue_redraw()


func _gui_input(event: InputEvent):
	if not visible:
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_click()

	if event is InputEventJoypadButton and event.pressed:
		var choices: Array = current_node.get("choices", [])
		var choice_count: int = 1 if choices.is_empty() else choices.size()

		if event.button_index == JOY_BUTTON_DPAD_UP:
			if hovered_choice <= 0:
				hovered_choice = choice_count - 1
			else:
				hovered_choice -= 1
			accept_event()

		elif event.button_index == JOY_BUTTON_DPAD_DOWN:
			if hovered_choice < 0:
				hovered_choice = 0
			elif hovered_choice >= choice_count - 1:
				hovered_choice = 0
			else:
				hovered_choice += 1
			accept_event()

		elif event.button_index == JOY_BUTTON_A:
			if hovered_choice < 0:
				hovered_choice = 0
			_on_click()
			accept_event()


func _on_click():
	# First click while typewriter is running → skip to end
	if not _typewriter_done:
		_revealed_chars = _full_text.length()
		_typewriter_done = true
		return

	var choices: Array = current_node.get("choices", [])
	if choices.is_empty():
		_close()
		return

	if hovered_choice >= 0 and hovered_choice < choices.size():
		var choice = choices[hovered_choice]
		var choice_effects: Array = choice.get("effects", [])
		for eff in choice_effects:
			collected_effects.append(eff)
		var next_id: String = choice.get("next", "")
		if next_id == "":
			_close()
		else:
			_go_to_node(next_id)


func _update_hover(mouse_pos: Vector2):
	if not _typewriter_done:
		hovered_choice = -1
		return

	hovered_choice = -1
	var box_pos := _box_origin()
	var choices_y := box_pos.y + BOX_H + 4.0

	var choices: Array = current_node.get("choices", [])
	if choices.is_empty():
		var btn_rect = Rect2(box_pos.x, choices_y, BOX_W, CHOICE_H_MIN)
		if btn_rect.has_point(mouse_pos):
			hovered_choice = 0
		return

	var cy := choices_y
	for i in choices.size():
		var label: String = GameManager.substitute_tags(choices[i].get("label", "..."))
		var ch := _choice_height(label)
		var choice_rect = Rect2(box_pos.x, cy, BOX_W, ch)
		if choice_rect.has_point(mouse_pos):
			hovered_choice = i
			return
		cy += ch + 2


func _box_origin() -> Vector2:
	return Vector2((size.x - BOX_W) / 2.0, (size.y - BOX_H) / 2.0)


func _draw():
	if not visible or current_node.is_empty():
		return

	var font = ThemeDB.fallback_font

	# Dim background
	var dim_alpha = 0.3 if (bg_art and bg_art.active) else 0.7
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dim_alpha))

	var box_pos := _box_origin()

	# Draw dialogue box image
	if _box_tex:
		draw_texture(_box_tex, box_pos)

	# Draw speaker portrait / static in the green square
	var port_x := box_pos.x + PORTRAIT_RECT.position.x
	var port_y := box_pos.y + PORTRAIT_RECT.position.y
	var port_w := PORTRAIT_RECT.size.x
	var port_h := PORTRAIT_RECT.size.y
	var port_rect := Rect2(port_x, port_y, port_w, port_h)
	var speaker_name: String = current_node.get("speaker", "")
	var is_static_speaker := static_speakers.has(speaker_name) and _portrait_tex == null

	if is_static_speaker:
		_draw_full_static(port_rect)
	elif _portrait_tex:
		_draw_portrait_vhs(port_rect)
	else:
		# No portrait, no static — just leave the green square
		pass

	# Speaker name
	var speaker: String = current_node.get("speaker", "")
	var text_y := box_pos.y + TEXT_TOP
	if speaker != "":
		draw_string(font, Vector2(box_pos.x + TEXT_LEFT, text_y), speaker + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.75, 1.0))
		text_y += 24

	# Typewriter text – wrap only the revealed portion
	var visible_text := _full_text.substr(0, _revealed_chars)
	var text_w := TEXT_RIGHT - TEXT_LEFT
	var lines := _wrap_text(visible_text, text_w)
	for line in lines:
		draw_string(font, Vector2(box_pos.x + TEXT_LEFT, text_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.82, 0.88))
		text_y += LINE_H

	# Choices appear only after typewriter finishes
	if not _typewriter_done:
		return

	var choices: Array = current_node.get("choices", [])
	var choices_y := box_pos.y + BOX_H + 4.0

	if choices.is_empty():
		var btn_rect = Rect2(box_pos.x, choices_y, BOX_W, CHOICE_H_MIN)
		if _choice_tex:
			var mod_col = Color.WHITE if hovered_choice != 0 else Color(1.2, 1.2, 1.4)
			draw_texture_rect(_choice_tex, btn_rect, false, mod_col)
		draw_string(font, Vector2(btn_rect.position.x + BOX_W / 2 - 30, btn_rect.position.y + 28), "Continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.85))
	else:
		var cy := choices_y
		for i in choices.size():
			var choice = choices[i]
			var label: String = GameManager.substitute_tags(choice.get("label", "..."))
			var ch := _choice_height(label)
			var choice_rect = Rect2(box_pos.x, cy, BOX_W, ch)

			var is_hovered = (i == hovered_choice)
			if _choice_tex:
				var mod_col = Color.WHITE if not is_hovered else Color(1.2, 1.2, 1.4)
				draw_texture_rect(_choice_tex, choice_rect, false, mod_col)

			var num_text = "%d." % (i + 1)
			draw_string(font, Vector2(choice_rect.position.x + 30, cy + CHOICE_PAD_TOP + CHOICE_LINE_H), num_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.5, 0.65))

			var label_col = Color(0.7, 0.72, 0.8) if not is_hovered else Color(0.85, 0.88, 1.0)
			var choice_lines := _wrap_text(label, CHOICE_TEXT_W)
			for li in choice_lines.size():
				var ly := cy + CHOICE_PAD_TOP + (li + 1) * CHOICE_LINE_H
				draw_string(font, Vector2(choice_rect.position.x + 55, ly), choice_lines[li], HORIZONTAL_ALIGNMENT_LEFT, int(CHOICE_TEXT_W), 13, label_col)

			cy += ch + 2


func _choice_height(label: String) -> float:
	var lines := _wrap_text(label, CHOICE_TEXT_W)
	var h := CHOICE_PAD_TOP + lines.size() * CHOICE_LINE_H + CHOICE_PAD_BOT
	return maxf(h, CHOICE_H_MIN)


func _wrap_text(text: String, max_width: float) -> Array:
	var lines: Array = []
	var words = text.split(" ")
	var line = ""
	var char_w = 7.5
	for word in words:
		var test = line + (" " if line != "" else "") + word
		if test.length() * char_w > max_width and line != "":
			lines.append(line)
			line = word
		else:
			line = test
	if line != "":
		lines.append(line)
	return lines


# --- VHS / static drawing helpers ---

## Cheap deterministic hash for pseudo-random per-pixel noise.
func _noise(x: int, y: int, seed_val: int) -> float:
	var h = (x * 374761393 + y * 668265263 + seed_val * 1274126177) & 0x7FFFFFFF
	h = ((h >> 13) ^ h) * 1103515245
	return float((h >> 16) & 0xFF) / 255.0

func _draw_portrait_vhs(rect: Rect2):
	# Draw portrait with proper VHS wrapping roll.
	# _vhs_roll_offset is -1..1 ratio of the portrait height.
	var tex := _portrait_tex
	var tex_h := float(tex.get_height())
	var tex_w := float(tex.get_width())
	var roll_px := fmod(_vhs_roll_offset * rect.size.y, rect.size.y)
	# Wrap to positive
	if roll_px < 0:
		roll_px += rect.size.y

	if absf(roll_px) < 0.5:
		# No meaningful roll — draw normally
		draw_texture_rect(tex, rect, false)
	else:
		# Split into two halves that wrap around
		# Top portion: the part of the image that's been pushed down
		var src_top_h := tex_h * (1.0 - roll_px / rect.size.y)
		var dst_top_h := rect.size.y - roll_px
		# Bottom portion: the part that wraps around to the top
		var src_bot_h := tex_h - src_top_h

		# Draw bottom of source image at the top of the rect
		var src_bottom := Rect2(0, src_top_h, tex_w, src_bot_h)
		var dst_top := Rect2(rect.position.x, rect.position.y, rect.size.x, roll_px)
		draw_texture_rect_region(tex, dst_top, src_bottom)

		# Draw top of source image at the bottom of the rect
		var src_top := Rect2(0, 0, tex_w, src_top_h)
		var dst_bottom := Rect2(rect.position.x, rect.position.y + roll_px, rect.size.x, dst_top_h)
		draw_texture_rect_region(tex, dst_bottom, src_top)

		# Seam line where the roll splits — bright tear
		var seam_y := rect.position.y + roll_px
		draw_rect(Rect2(rect.position.x, seam_y - 1.0, rect.size.x, 2.0), Color(0.8, 0.85, 1.0, 0.4))

	# VHS overlay effects
	_draw_vhs_overlay(rect)

func _draw_full_static(rect: Rect2):
	# Full VHS static — broken rolling signal, no image
	var block := 6.0
	var cols := int(rect.size.x / block)
	var rows := int(rect.size.y / block)
	var roll := fmod(_vhs_time * 80.0, rect.size.y)

	for row_i in rows:
		for col_i in cols:
			var lum := _noise(col_i, row_i, _vhs_noise_seed)
			var world_y := float(row_i) * block + roll
			var band := sin(world_y * 0.15) * 0.3 + sin(world_y * 0.4) * 0.15
			lum = clampf(lum + band, 0.0, 1.0)
			var r := lum
			var g := lum
			var b := lum
			if _noise(col_i + 100, row_i, _vhs_noise_seed) > 0.92:
				r = clampf(lum + 0.3, 0.0, 1.0)
				b = clampf(lum - 0.2, 0.0, 1.0)
			var px := Rect2(rect.position.x + col_i * block, rect.position.y + row_i * block, block, block)
			draw_rect(px, Color(r, g, b, 1.0))

	# Horizontal tear
	if _vhs_h_tear >= 0:
		var tear_y := rect.position.y + _vhs_h_tear * rect.size.y
		draw_rect(Rect2(rect.position.x, tear_y, rect.size.x, randf_range(2.0, 5.0)), Color(0.9, 0.9, 0.95, 0.7))

	_draw_scanlines(rect, 0.35)

func _draw_vhs_overlay(rect: Rect2):
	# Grain — noisy pixels scattered over the portrait
	var grain_block := 3.0
	var cols := int(rect.size.x / grain_block)
	var rows := int(rect.size.y / grain_block)
	for row_i in rows:
		for col_i in cols:
			var n := _noise(col_i, row_i, _vhs_noise_seed)
			if n > 0.82:
				var lum := n * 0.6
				var px := Rect2(
					rect.position.x + col_i * grain_block,
					rect.position.y + row_i * grain_block,
					grain_block, grain_block
				)
				draw_rect(px, Color(lum, lum, lum, 0.2))

	# Scan lines
	_draw_scanlines(rect, 0.12)

	# Horizontal tear during glitch
	if _vhs_h_tear >= 0:
		var tear_y := rect.position.y + _vhs_h_tear * rect.size.y
		draw_rect(Rect2(rect.position.x - 3.0, tear_y, rect.size.x + 6.0, 2.5), Color(0.7, 0.85, 1.0, 0.35))

	# Color fringe band during roll
	if absf(_vhs_roll_offset) > 0.02:
		var band_y := rect.position.y + rect.size.y * 0.5 + _vhs_roll_offset * rect.size.y * 0.5
		var band_h := clampf(absf(_vhs_roll_offset) * rect.size.y * 0.15, 2.0, 14.0)
		draw_rect(Rect2(rect.position.x, band_y, rect.size.x, band_h), Color(0.4, 0.6, 1.0, 0.18))

func _draw_scanlines(rect: Rect2, alpha: float):
	var y := rect.position.y
	while y < rect.position.y + rect.size.y:
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 1.0), Color(0.0, 0.0, 0.0, alpha))
		y += 3.0
