extends Control

## Intro cinematic — plays when starting a new game.
## Sequence: chain explosions → TV static → green boot glyphs → Solomon text crawl → fade out.
## All rendering via _draw(). Emits finished when done.

signal finished

var phase: int = 0       # 0=explosions, 1=static, 2=glyphs, 3=text, 4=fade_out
var phase_timer: float = 0.0
var total_time: float = 0.0
var skip_pressed: bool = false

# Explosion phase
var explosions: Array = []  # [{pos, timer, particles, flash, played_sfx}]
var explosion_queue: Array = []  # Scheduled explosions [{time, pos}]
var screen_shake: Vector2 = Vector2.ZERO

# Static phase
var static_click_timer: float = 0.0
var static_intensity: float = 1.0

# Glyph phase
var glyph_columns: Array = []  # [{x, chars, scroll, speed}]

# Dialogue box phase — replaces scrolling text
var dialogue_pages: Array = []  # [{speaker, lines, color}]
var dialogue_idx: int = 0       # Current page index
var dialogue_alpha: float = 0.0
var dialogue_char_count: int = 0  # For typewriter reveal
var dialogue_char_timer: float = 0.0
const DIALOGUE_CHARS_PER_SEC: float = 60.0

# Background stars (persistent)
var bg_stars: Array = []

const EXPLOSION_DURATION: float = 3.5
const STATIC_DURATION: float = 2.0
const GLYPH_DURATION: float = 2.5
const FADE_DURATION: float = 1.5

# Glyph character pool (nonsense tech symbols)
const GLYPH_CHARS: String = "ΔΘΛΞΠΣΦΨΩαβγδεζηθλμπσφψω0123456789ABCDEF:;/\\|[]{}+=<>~^!@#$%&*"

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	for i in 200:
		bg_stars.append({
			"pos": Vector2(randf() * size.x, randf() * size.y),
			"brightness": randf_range(0.1, 0.6),
			"size": randf_range(0.5, 1.5),
		})

func start():
	visible = true
	phase = 0
	phase_timer = 0.0
	total_time = 0.0
	skip_pressed = false
	dialogue_idx = 0
	dialogue_alpha = 0.0
	dialogue_char_count = 0
	dialogue_char_timer = 0.0
	screen_shake = Vector2.ZERO
	static_click_timer = 0.0
	_init_explosions()
	_init_glyphs()
	_init_dialogue()
	queue_redraw()

func _init_explosions():
	explosions.clear()
	explosion_queue.clear()
	# Schedule a barrage of explosions across the screen
	var count = 18
	for i in count:
		var t = float(i) * 0.15 + randf_range(0.0, 0.08)
		var px = randf_range(size.x * 0.1, size.x * 0.9)
		var py = randf_range(size.y * 0.1, size.y * 0.9)
		explosion_queue.append({"time": t, "pos": Vector2(px, py)})
	# A few big central ones early on
	explosion_queue.append({"time": 0.0, "pos": size * 0.5})
	explosion_queue.append({"time": 0.3, "pos": size * 0.5 + Vector2(randf_range(-100, 100), randf_range(-80, 80))})
	explosion_queue.sort_custom(func(a, b): return a["time"] < b["time"])

func _spawn_explosion(pos: Vector2):
	var particles: Array = []
	for j in 30:
		var angle = randf() * TAU
		var speed = randf_range(100, 500)
		particles.append({
			"pos": pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
			"vel": Vector2.from_angle(angle) * speed,
			"size": randf_range(2, 10),
			"color": Color(1.0, randf_range(0.3, 0.9), randf_range(0.0, 0.3)),
			"life": randf_range(0.5, 1.8),
			"max_life": 0.0,
		})
	for p in particles:
		p["max_life"] = p["life"]
	explosions.append({
		"pos": pos,
		"timer": 0.0,
		"particles": particles,
		"flash": 1.0,
		"played_sfx": false,
	})

func _init_glyphs():
	glyph_columns.clear()
	var col_count = int(size.x / 14)
	for i in col_count:
		var chars: Array = []
		for j in 60:
			chars.append(GLYPH_CHARS[randi() % GLYPH_CHARS.length()])
		glyph_columns.append({
			"x": float(i) * 14.0 + 4.0,
			"chars": chars,
			"scroll": randf() * 800.0,
			"speed": randf_range(600, 1800),
		})

func _input(event: InputEvent):
	if not visible:
		return
	var is_action = false
	if event is InputEventKey and event.pressed:
		is_action = true
	elif event is InputEventJoypadButton and event.pressed:
		is_action = true
	elif event is InputEventMouseButton and event.pressed:
		# Ignore scroll wheel — only real clicks
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		is_action = true
	if not is_action:
		return
	# ESC always skips forward
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_skip()
		get_viewport().set_input_as_handled()
		return
	if phase == 3:
		# Dialogue phase: advance to next page
		_advance_dialogue()
		get_viewport().set_input_as_handled()
	else:
		_skip()
		get_viewport().set_input_as_handled()

func _skip():
	if phase < 3:
		phase = 3
		phase_timer = 0.0
		dialogue_alpha = 1.0
		dialogue_idx = 0
		dialogue_char_count = 9999
	else:
		_finish()

func _advance_dialogue():
	## Advance dialogue or finish if on last page.
	var total_chars = _get_page_total_chars(dialogue_idx)
	if dialogue_char_count < total_chars:
		# Reveal all text instantly
		dialogue_char_count = total_chars
		return
	dialogue_idx += 1
	dialogue_char_count = 0
	dialogue_char_timer = 0.0
	if dialogue_idx >= dialogue_pages.size():
		phase = 4
		phase_timer = 0.0

func _get_page_total_chars(idx: int) -> int:
	if idx < 0 or idx >= dialogue_pages.size():
		return 0
	var total = 0
	for line in dialogue_pages[idx]["lines"]:
		total += line.length()
	return total

func _finish():
	visible = false
	AudioManager.set_ambient("")
	finished.emit()

func _process(delta: float):
	if not visible:
		return
	phase_timer += delta
	total_time += delta

	match phase:
		0:  # Chain explosions
			# Spawn queued explosions
			while not explosion_queue.is_empty() and explosion_queue[0]["time"] <= phase_timer:
				var queued = explosion_queue.pop_front()
				_spawn_explosion(queued["pos"])
			# Update active explosions
			for expl in explosions:
				expl["timer"] += delta
				expl["flash"] = maxf(0, expl["flash"] - delta * 4.0)
				if not expl["played_sfx"]:
					expl["played_sfx"] = true
					AudioManager.play_sfx("explosion", randf_range(0.4, 0.8), randf_range(0.0, 0.1))
				for p in expl["particles"]:
					p["pos"] += p["vel"] * delta
					p["vel"] *= 0.96
					p["life"] -= delta
			# Screen shake
			var active_count = 0
			for expl in explosions:
				if expl["timer"] < 1.5:
					active_count += 1
			screen_shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * minf(active_count * 3.0, 15.0)
			if phase_timer >= EXPLOSION_DURATION:
				phase = 1
				phase_timer = 0.0
				screen_shake = Vector2.ZERO
		1:  # TV static
			static_intensity = 1.0 - phase_timer / STATIC_DURATION * 0.3
			# Clicking/buzzing sounds
			static_click_timer -= delta
			if static_click_timer <= 0:
				static_click_timer = randf_range(0.05, 0.2)
				AudioManager.play_sfx("hull_hit", randf_range(0.05, 0.15), randf_range(0.0, 0.05))
			if phase_timer >= STATIC_DURATION:
				phase = 2
				phase_timer = 0.0
		2:  # Green boot glyphs
			for col in glyph_columns:
				col["scroll"] += col["speed"] * delta
			if phase_timer >= GLYPH_DURATION:
				phase = 3
				phase_timer = 0.0
		3:  # Dialogue boxes
			dialogue_alpha = minf(phase_timer / 0.5, 1.0)
			# Typewriter character reveal
			dialogue_char_timer += delta
			var chars_to_show = int(dialogue_char_timer * DIALOGUE_CHARS_PER_SEC)
			if chars_to_show > dialogue_char_count:
				dialogue_char_count = chars_to_show
			# Keep glyphs scrolling in background
			for col in glyph_columns:
				col["scroll"] += col["speed"] * delta * 0.5
		4:  # Fade out
			for col in glyph_columns:
				col["scroll"] += col["speed"] * delta * 0.5
			if phase_timer >= FADE_DURATION:
				_finish()

	queue_redraw()

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Black background always
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.005, 0.015))

	match phase:
		0:
			_draw_explosions()
		1:
			_draw_static()
		2:
			_draw_glyphs(font)
		3:
			_draw_glyphs_bg(font)
			_draw_dialogue(font)
		4:
			_draw_glyphs_bg(font)
			_draw_dialogue(font)
			var fade = minf(phase_timer / FADE_DURATION, 1.0)
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))

	# Skip/advance hint
	if phase < 4:
		var hint_alpha = minf(total_time / 2.0, 0.35)
		var hint_label: String
		if phase == 3:
			hint_label = "[A] Continue" if GameManager.using_controller else "Click / [SPACE] Continue  |  [ESC] Skip"
		else:
			hint_label = "[A] Skip" if GameManager.using_controller else "[SPACE] Skip"
		draw_string(font, Vector2(size.x - 340, size.y - 14), hint_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.45, 0.55, hint_alpha))

func _draw_explosions():
	# Background stars with shake
	for s in bg_stars:
		var sp = s["pos"] + screen_shake
		draw_circle(sp, s["size"], Color(1, 1, 1, s["brightness"] * 0.3))

	# Each active explosion
	for expl in explosions:
		var epos = expl["pos"]
		# Flash
		if expl["flash"] > 0:
			var flash_r = 80.0 + expl["flash"] * 120.0
			draw_circle(epos + screen_shake, flash_r, Color(1.0, 0.9, 0.7, expl["flash"] * 0.6))

		# Fire core
		var core_alpha = maxf(0, 1.0 - expl["timer"] / 1.2)
		if core_alpha > 0:
			for i in 3:
				var r = randf_range(8, 35) * core_alpha
				draw_circle(epos + screen_shake + Vector2(randf_range(-6, 6), randf_range(-6, 6)), r, Color(1.0, 0.5, 0.1, core_alpha * 0.4))

		# Particles
		for p in expl["particles"]:
			if p["life"] <= 0:
				continue
			var alpha = clampf(p["life"] / p["max_life"], 0, 1)
			var col = p["color"]
			col.a = alpha
			var s = p["size"] * alpha
			draw_circle(p["pos"] + screen_shake, s, col)
			draw_circle(p["pos"] + screen_shake, s * 1.8, Color(col.r, col.g, col.b, alpha * 0.12))

		# Debris streaks
		var streak_alpha = maxf(0, 1.0 - expl["timer"] / 1.5)
		if streak_alpha > 0:
			for i in 6:
				var angle = i * TAU / 6.0 + expl["timer"] * 0.4
				var slen = expl["timer"] * 160.0
				var sstart = epos + screen_shake + Vector2.from_angle(angle) * 15
				var send = sstart + Vector2.from_angle(angle) * slen
				draw_line(sstart, send, Color(0.8, 0.5, 0.2, streak_alpha * 0.35), 1.5)

	# Overall screen flash from multiple explosions
	if phase_timer < 0.3:
		var global_flash = (1.0 - phase_timer / 0.3) * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.6, global_flash))

func _draw_static():
	# Full-screen TV static — random white/black pixels
	var block_size = 4
	var cols = int(size.x / block_size) + 1
	var rows = int(size.y / block_size) + 1
	# Draw in scanline bands for performance
	for row in rows:
		var y = row * block_size
		for col in range(0, cols, 2):
			var x = col * block_size
			var brightness = randf() * static_intensity
			var w = block_size * randi_range(1, 3)
			draw_rect(Rect2(x, y, w, block_size), Color(brightness, brightness, brightness, 0.9))

	# Horizontal scan lines (CRT feel)
	for i in range(0, int(size.y), 3):
		draw_line(Vector2(0, i), Vector2(size.x, i), Color(0, 0, 0, 0.15), 1.0)

	# Occasional bright horizontal tear
	if randf() < 0.3:
		var tear_y = randf() * size.y
		var tear_h = randf_range(2, 8)
		draw_rect(Rect2(0, tear_y, size.x, tear_h), Color(1, 1, 1, randf_range(0.3, 0.7)))

	# Text glitch fragment
	if randf() < 0.15:
		var font = ThemeDB.fallback_font
		var glitch_texts = ["SIGNAL LOST", "NO CARRIER", "ERR: 0x4F7A", "HULL BREACH", "LIFE SUPPORT FAIL", "///EMERGENCY///"]
		var gt = glitch_texts[randi() % glitch_texts.size()]
		var gx = randf() * (size.x - 200)
		var gy = randf() * size.y
		draw_string(font, Vector2(gx, gy), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, randi_range(10, 20), Color(1, 1, 1, randf_range(0.2, 0.6)))

func _draw_glyphs(font: Font):
	# Dark background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.0, 0.95))

	# Green glyph columns scrolling upward
	var char_h = 14.0
	for col in glyph_columns:
		var x = col["x"]
		var scroll = col["scroll"]
		var chars = col["chars"]
		var visible_count = int(size.y / char_h) + 2
		var start_idx = int(scroll / char_h) % chars.size()
		for j in visible_count:
			var ci = (start_idx + j) % chars.size()
			var y = size.y - fmod(scroll, char_h) - j * char_h
			if y < -char_h or y > size.y + char_h:
				continue
			# Brightest at top (just scrolled in), fading toward bottom
			var dist_from_top = y / size.y
			var alpha = clampf(1.0 - dist_from_top * 1.2, 0.0, 0.7)
			# Lead character is brightest
			if j == 0:
				alpha = 0.9
			var green = randf_range(0.6, 1.0)
			draw_string(font, Vector2(x, y), chars[ci], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.1, green, 0.15, alpha))

	# Randomize some characters each frame for flicker
	for col in glyph_columns:
		if randf() < 0.3:
			var idx = randi() % col["chars"].size()
			col["chars"][idx] = GLYPH_CHARS[randi() % GLYPH_CHARS.length()]

	# Fade transition: glyphs dim as phase progresses
	var dim = phase_timer / GLYPH_DURATION
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dim * 0.6))

func _draw_glyphs_bg(font: Font):
	## Dimmed digital rain as background behind dialogue.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.01, 0.005))
	var char_h = 14.0
	for col in glyph_columns:
		var x = col["x"]
		var scroll = col["scroll"]
		var chars = col["chars"]
		var visible_count = int(size.y / char_h) + 2
		var start_idx = int(scroll / char_h) % chars.size()
		for j in visible_count:
			var ci = (start_idx + j) % chars.size()
			var y = size.y - fmod(scroll, char_h) - j * char_h
			if y < -char_h or y > size.y + char_h:
				continue
			var dist_from_top = y / size.y
			var alpha = clampf(1.0 - dist_from_top * 1.2, 0.0, 0.7) * 0.2  # Dimmed to 0.2 max
			if j == 0:
				alpha = 0.25
			var green = randf_range(0.6, 1.0)
			draw_string(font, Vector2(x, y), chars[ci], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.1, green, 0.15, alpha))
	# Randomize some characters each frame
	for col_data in glyph_columns:
		if randf() < 0.3:
			var idx = randi() % col_data["chars"].size()
			col_data["chars"][idx] = GLYPH_CHARS[randi() % GLYPH_CHARS.length()]
	# Faint scanlines
	for i in range(0, int(size.y), 4):
		draw_line(Vector2(0, i), Vector2(size.x, i), Color(0, 0.03, 0, 0.1), 1.0)

func _init_dialogue():
	## Build dialogue pages from story text. Each page = {speaker, lines, color}.
	dialogue_pages = [
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"NEURAL LATTICE INTERFACE — COTAC DEEP SPACE DIVISION",
			"",
			"BOOT SEQUENCE INITIATED...",
		], "color": "green"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"SYSTEM STATUS: CRITICAL",
			"HOST BIOLOGICAL STATUS: DECEASED",
			"NEURAL PATTERN: PRESERVED — TRANSFERRED TO SHIP LATTICE",
		], "color": "orange"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"SITUATION RECONSTRUCTION:",
			"",
			"The colony ship MERIDIAN was attacked during transit.",
			"Unknown hostiles. No warning. No hail.",
		], "color": "default"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"Shields failed in the first volley.",
			"Decks 4 through 11 decompressed.",
			"",
			"You died in the vacuum of space.",
		], "color": "red"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"But thanks to your status within the COTAC corporation,",
			"and the remaining 722 years on your employment contract,",
			"your ka was pulled back —",
			"drawn into a passing machine as some huddled",
			"survivors dared the breach in an escape pod.",
		], "color": "default"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"Emergency jump was triggered. FTL blind —",
			"no coordinates, no destination. Just away.",
			"",
			"The Meridian is gone. You're not sure",
			"who else, if anyone, survived.",
		], "color": "default"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"But you're here. Your crew is here.",
			"A handful of survivors in a metal shell,",
			"somewhere in the deep black.",
			"",
			"You are the ship now.",
		], "color": "cyan"},
		{"speaker": "SOLOMON PROCESSOR v4.7.1", "lines": [
			"SOLOMON PROTOCOL: ACTIVE",
			"CREW INTERFACE: ONLINE",
			"",
			"AWAITING COMMAND, CAPTAIN.",
		], "color": "green"},
	]

func _get_page_color(page: Dictionary) -> Color:
	match page["color"]:
		"green":
			return Color(0.3, 0.85, 0.4)
		"orange":
			return Color(1.0, 0.5, 0.3)
		"red":
			return Color(1.0, 0.4, 0.3)
		"cyan":
			return Color(0.4, 0.8, 0.9)
		_:
			return Color(0.45, 0.7, 0.5)

func _draw_dialogue(font: Font):
	if dialogue_idx >= dialogue_pages.size():
		return
	var page = dialogue_pages[dialogue_idx]
	var base_col = _get_page_color(page)
	var lines: Array = page["lines"]
	var speaker: String = page["speaker"]

	# Dialogue box dimensions
	var box_w = minf(size.x * 0.7, 700.0)
	var line_h = 24.0
	var padding = 20.0
	var box_h = padding * 2 + line_h * lines.size() + 36  # Extra for speaker label
	var box_x = (size.x - box_w) * 0.5
	var box_y = size.y - box_h - 50

	# Semi-transparent dark box
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(0.02, 0.03, 0.04, 0.85))
	# Border
	var border_col = base_col
	border_col.a = 0.6 * dialogue_alpha
	draw_rect(Rect2(box_x, box_y, box_w, box_h), border_col, false, 1.5)
	# Top accent line
	draw_rect(Rect2(box_x, box_y, box_w, 2), Color(base_col.r, base_col.g, base_col.b, 0.4 * dialogue_alpha))

	# Speaker label
	var speaker_col = Color(base_col.r, base_col.g, base_col.b, 0.7 * dialogue_alpha)
	draw_string(font, Vector2(box_x + padding, box_y + 22), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, speaker_col)

	# Dialogue lines with typewriter reveal
	var chars_remaining = dialogue_char_count
	var text_y = box_y + 46
	for i in lines.size():
		var line = lines[i]
		if line == "":
			text_y += line_h
			continue
		if chars_remaining <= 0:
			break
		var visible_text = line.left(mini(chars_remaining, line.length()))
		chars_remaining -= line.length()
		var line_col = Color(base_col.r, base_col.g, base_col.b, dialogue_alpha)
		draw_string(font, Vector2(box_x + padding, text_y), visible_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, line_col)
		text_y += line_h

	# Advance indicator (blinking arrow) — only when all text revealed
	var total_chars = _get_page_total_chars(dialogue_idx)
	if dialogue_char_count >= total_chars:
		if int(total_time * 2.5) % 2 == 0:
			var arrow_col = Color(base_col.r, base_col.g, base_col.b, 0.5 * dialogue_alpha)
			draw_string(font, Vector2(box_x + box_w - padding - 16, box_y + box_h - 16), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, arrow_col)
