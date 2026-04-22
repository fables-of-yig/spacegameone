extends Control

var _selected: int = -1
var _fade_in: float = 0.0
var _death_message: String = ""

signal retry_pressed
signal menu_pressed

const TAUNTS_COLLISION = [
	"Every action has an equal and opposite reaction.",
]

const TAUNTS_COMBAT = [
	"Your hull integrity disagreed with their firepower.",
	"Shields down. Hull down. Ego down.",
	"They shot first. They also shot last.",
]

const TAUNTS_DEFAULT = [
	"Space is unforgiving.",
	"You have been returned to the void.",
]

func _ready():
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS

func show_death(cause: String = ""):
	visible = true
	_selected = -1
	_fade_in = 0.0
	match cause:
		"collision":
			_death_message = TAUNTS_COLLISION[randi() % TAUNTS_COLLISION.size()]
		"combat":
			_death_message = TAUNTS_COMBAT[randi() % TAUNTS_COMBAT.size()]
		_:
			_death_message = TAUNTS_DEFAULT[randi() % TAUNTS_DEFAULT.size()]

func _process(delta):
	if not visible:
		return
	if _fade_in < 1.0:
		_fade_in = minf(_fade_in + delta * 0.8, 1.0)
	queue_redraw()

func _input(event):
	if not visible or _fade_in < 0.95:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _selected >= 0:
				_activate_selected()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_UP or event.button_index == JOY_BUTTON_DPAD_DOWN:
			_selected = 1 - maxi(_selected, 0)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_A:
			if _selected < 0:
				_selected = 0
			else:
				_activate_selected()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		if is_inside_tree(): get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		if is_inside_tree(): get_viewport().set_input_as_handled()

func _update_hover(pos: Vector2):
	_selected = -1
	var buttons = _get_button_rects()
	for i in buttons.size():
		if buttons[i].has_point(pos):
			_selected = i

func _handle_click(pos: Vector2):
	var buttons = _get_button_rects()
	for i in buttons.size():
		if buttons[i].has_point(pos):
			match i:
				0: _do_retry()
				1: _do_menu()

func _activate_selected():
	match _selected:
		0: _do_retry()
		1: _do_menu()

func _do_retry():
	visible = false
	retry_pressed.emit()

func _do_menu():
	visible = false
	menu_pressed.emit()

func _get_button_rects() -> Array:
	var cx = size.x * 0.5
	var ph = 340.0
	var py = (size.y - ph) * 0.5 - 20
	var btn_w = 260.0
	var btn_h = 40.0
	var gap = 12.0
	var base_y = py + ph - 20.0 - 2.0 * (btn_h + gap)
	var rects: Array = []
	for i in 2:
		var bx = cx - btn_w * 0.5
		var by = base_y + float(i) * (btn_h + gap)
		rects.append(Rect2(bx, by, btn_w, btn_h))
	return rects

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font
	var alpha = _fade_in

	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.9 * alpha)

	var pw = 480.0
	var ph = 340.0
	var px = (size.x - pw) * 0.5
	var py = (size.y - ph) * 0.5 - 20
	var panel = Rect2(px, py, pw, ph)
	UIPanels.draw_panel(self, panel, Color(0.95, 0.4, 0.32, alpha), UIPanels.PanelVariant.DARK)

	# Title
	var title = "DESTROYED"
	var title_w = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(font, Vector2(size.x * 0.5 - title_w * 0.5, py + 35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.2, 0.15, alpha))
	draw_line(Vector2(px + 20, py + 45), Vector2(px + pw - 20, py + 45), Color(0.4, 0.1, 0.1, 0.5 * alpha), 1.0)

	# Death message
	if _death_message != "":
		var msg_max_w = pw - 60
		var msg_y = py + 80
		var char_w = 7.0
		var chars_per_line = int(msg_max_w / char_w)
		var words = _death_message.split(" ")
		var lines: Array = []
		var current_line = ""
		for word in words:
			if current_line == "":
				current_line = word
			elif (current_line + " " + word).length() <= chars_per_line:
				current_line += " " + word
			else:
				lines.append(current_line)
				current_line = word
		if current_line != "":
			lines.append(current_line)
		for i in lines.size():
			var line_w = font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(size.x * 0.5 - line_w * 0.5, msg_y + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.55, 0.5, alpha))

	# Buttons
	if alpha >= 0.95:
		var labels = ["RETRY", "MAIN MENU"]
		var buttons = _get_button_rects()
		for i in buttons.size():
			var rect = buttons[i]
			var label = labels[i]
			var is_hovered = _selected == i
			var tint = Color(0.95, 0.45, 0.35, 1.0)
			UIPanels.draw_button_bg(self, rect, is_hovered, tint)
			var lw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			if is_hovered:
				draw_string(font, Vector2(rect.position.x + rect.size.x * 0.5 - lw * 0.5, rect.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.92, 0.88))
				draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 26), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.5, 0.4))
			else:
				draw_string(font, Vector2(rect.position.x + rect.size.x * 0.5 - lw * 0.5, rect.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.55, 0.5))

		var hint_text = "[A] Select" if GameManager.using_controller else ""
		if hint_text != "":
			draw_string(font, Vector2(size.x * 0.5 - 30, py + ph - 10), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.33, 0.4, 0.6))
