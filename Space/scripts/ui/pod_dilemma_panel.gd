extends Control

## Quick dilemma panel for enemy escape pods.
## Pauses game, shows 2-3 choices: Leave, Destroy, Capture (if brig).

signal choice_made(action: String)  # "leave", "destroy", "capture"

var crew_data: Dictionary = {}
var hovered_choice: int = -1
var _choices: Array = []  # [{label, action, color, desc}]

const PANEL_W: float = 420.0
const CHOICE_H: float = 38.0
const CHOICE_GAP: float = 4.0

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)

func open(pod_crew_data: Dictionary):
	crew_data = pod_crew_data
	hovered_choice = -1

	# Build choices
	_choices.clear()
	_choices.append({
		"label": "Leave them",
		"action": "leave",
		"color": Color(0.5, 0.55, 0.6),
		"desc": "Drift on. Not your problem.",
	})
	_choices.append({
		"label": "Destroy the pod",
		"action": "destroy",
		"color": Color(0.9, 0.3, 0.2),
		"desc": "No survivors. No witnesses.",
	})
	if GameManager.has_brig_space():
		var cap = GameManager.prisoners.size()
		var max_cap = GameManager.prisoner_capacity
		_choices.append({
			"label": "Take them captive  [%d/%d]" % [cap + 1, max_cap],
			"action": "capture",
			"color": Color(0.85, 0.65, 0.2),
			"desc": "Lock them in the brig. Could be useful.",
		})
	elif GameManager.prisoner_capacity > 0:
		_choices.append({
			"label": "Brig full",
			"action": "",
			"color": Color(0.35, 0.35, 0.4),
			"desc": "No room for more prisoners.",
		})

	visible = true
	queue_redraw()

func _gui_input(event: InputEvent):
	if not visible:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered_choice >= 0 and hovered_choice < _choices.size():
			var action = _choices[hovered_choice].get("action", "")
			if action != "":
				visible = false
				choice_made.emit(action)
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				if _choices.size() > 0:
					if hovered_choice <= 0:
						hovered_choice = _choices.size() - 1
					else:
						hovered_choice -= 1
					# Skip disabled choices
					if _choices[hovered_choice].get("action", "") == "" and _choices.size() > 1:
						hovered_choice = maxi(hovered_choice - 1, 0)
					queue_redraw()
				accept_event()
			JOY_BUTTON_DPAD_DOWN:
				if _choices.size() > 0:
					if hovered_choice < _choices.size() - 1:
						hovered_choice += 1
					else:
						hovered_choice = 0
					# Skip disabled choices
					if _choices[hovered_choice].get("action", "") == "" and _choices.size() > 1:
						hovered_choice = mini(hovered_choice + 1, _choices.size() - 1)
					queue_redraw()
				accept_event()
			JOY_BUTTON_A:
				if hovered_choice >= 0 and hovered_choice < _choices.size():
					var action = _choices[hovered_choice].get("action", "")
					if action != "":
						visible = false
						choice_made.emit(action)
				accept_event()
			JOY_BUTTON_B:
				visible = false
				choice_made.emit("leave")
				accept_event()

func _update_hover(mouse_pos: Vector2):
	hovered_choice = -1
	var panel_h = _calc_panel_h()
	var px = (size.x - PANEL_W) / 2.0
	var py = (size.y - panel_h) / 2.0
	var choices_y = py + 90
	for i in _choices.size():
		var cy = choices_y + i * (CHOICE_H + CHOICE_GAP)
		var rect = Rect2(px + 20, cy, PANEL_W - 40, CHOICE_H)
		if rect.has_point(mouse_pos):
			hovered_choice = i
			return

func _calc_panel_h() -> float:
	return 100.0 + _choices.size() * (CHOICE_H + CHOICE_GAP) + 20.0

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font
	var panel_h = _calc_panel_h()
	var px = (size.x - PANEL_W) / 2.0
	var py = (size.y - panel_h) / 2.0

	# Dim background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))

	# Panel
	draw_rect(Rect2(px, py, PANEL_W, panel_h), Color(0.03, 0.035, 0.06, 0.97))
	draw_rect(Rect2(px, py, PANEL_W, panel_h), Color(0.4, 0.35, 0.25, 0.5), false, 1.5)
	# Top accent
	draw_line(Vector2(px, py), Vector2(px + PANEL_W, py), Color(0.9, 0.5, 0.15, 0.6), 2.0)

	# Title
	draw_string(font, Vector2(px + 20, py + 26), "ENEMY ESCAPE POD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.6, 0.2))

	# Crew info
	var cname = crew_data.get("name", "Unknown")
	var crole = crew_data.get("role", "spacer")
	draw_string(font, Vector2(px + 20, py + 50), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.78, 0.85))
	draw_string(font, Vector2(px + 20, py + 68), crole.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.6))
	# Skills summary
	var skills = crew_data.get("skills", {})
	var skill_text = ""
	for sk in skills:
		if skill_text != "":
			skill_text += "  "
		skill_text += "%s:%d" % [sk.substr(0, 3).to_upper(), int(skills[sk])]
	draw_string(font, Vector2(px + 120, py + 68), skill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.5, 0.55))

	# Separator
	draw_line(Vector2(px + 15, py + 80), Vector2(px + PANEL_W - 15, py + 80), Color(0.2, 0.22, 0.28), 1.0)

	# Choices
	var choices_y = py + 90
	for i in _choices.size():
		var choice = _choices[i]
		var cy = choices_y + i * (CHOICE_H + CHOICE_GAP)
		var rect = Rect2(px + 20, cy, PANEL_W - 40, CHOICE_H)
		var is_hovered = i == hovered_choice
		var is_disabled = choice.get("action", "") == ""

		# Choice background
		var bg_col = Color(0.08, 0.08, 0.1) if not is_hovered else Color(0.12, 0.12, 0.16)
		if is_disabled:
			bg_col = Color(0.05, 0.05, 0.06)
		draw_rect(rect, bg_col)

		# Left color pip
		var pip_col: Color = choice.get("color", Color(0.5, 0.5, 0.5))
		if is_disabled:
			pip_col *= 0.4
		draw_rect(Rect2(rect.position.x, cy, 3, CHOICE_H), pip_col)

		# Hover highlight border
		if is_hovered and not is_disabled:
			draw_rect(rect, Color(pip_col, 0.3), false, 1.0)

		# Label
		var label_col = Color(0.8, 0.82, 0.88) if not is_disabled else Color(0.35, 0.38, 0.42)
		if is_hovered and not is_disabled:
			label_col = Color(0.95, 0.95, 1.0)
		draw_string(font, Vector2(rect.position.x + 12, cy + 16), choice.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)

		# Description
		var desc_col = Color(0.45, 0.48, 0.55) if not is_disabled else Color(0.25, 0.28, 0.3)
		draw_string(font, Vector2(rect.position.x + 12, cy + 31), choice.get("desc", ""), HORIZONTAL_ALIGNMENT_LEFT, int(PANEL_W - 70), 10, desc_col)
