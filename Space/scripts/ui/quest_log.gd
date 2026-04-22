extends Control

## Quest Log panel -- shows active and completed missions with full details.
## Opened with J key. All rendering via _draw().

var _skip_close_frame: bool = true

# Layout
var panel_rect: Rect2 = Rect2()
var scroll: float = 0.0
var selected_mission: String = ""
var hovered_mission: String = ""
var gamepad_idx: int = -1  # Index into mission_rects for gamepad navigation
var tab: int = 0  # 0 = active, 1 = completed

const TAB_ACTIVE: int = 0
const TAB_COMPLETED: int = 1

const TYPE_COLORS: Dictionary = {
	"cargo_haul": Color(0.85, 0.65, 0.2),
	"bounty": Color(0.9, 0.3, 0.25),
	"salvage": Color(0.3, 0.7, 0.9),
	"gather": Color(0.4, 0.8, 0.5),
}
const TYPE_LABELS: Dictionary = {
	"cargo_haul": "CARGO",
	"bounty": "BOUNTY",
	"salvage": "SALVAGE",
	"gather": "GATHER",
}

signal closed

func _ready():
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS

func open_panel():
	visible = true
	_skip_close_frame = true
	selected_mission = ""
	hovered_mission = ""
	gamepad_idx = -1
	scroll = 0.0
	tab = TAB_ACTIVE

func _process(_delta):
	if not visible:
		return
	if _skip_close_frame:
		_skip_close_frame = false
		return
	if Input.is_action_just_pressed("toggle_quest_log"):
		visible = false
		closed.emit()
		return
	queue_redraw()

func _input(event):
	if not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		var rects = get_meta("mission_rects", [])
		match event.button_index:
			JOY_BUTTON_DPAD_DOWN:
				if rects.size() > 0:
					gamepad_idx = clampi(gamepad_idx + 1, 0, rects.size() - 1)
					var mid = rects[gamepad_idx].get("id", "")
					hovered_mission = mid
					selected_mission = mid
			JOY_BUTTON_DPAD_UP:
				if rects.size() > 0:
					gamepad_idx = maxi(gamepad_idx - 1, 0)
					var mid = rects[gamepad_idx].get("id", "")
					hovered_mission = mid
					selected_mission = mid
			JOY_BUTTON_A:
				# Toggle selection / expand
				if selected_mission != "":
					pass  # Already selected and detail shown
				elif rects.size() > 0 and gamepad_idx >= 0:
					var mid = rects[gamepad_idx].get("id", "")
					selected_mission = mid
			JOY_BUTTON_B:
				visible = false
				closed.emit()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if panel_rect.has_point(event.position):
				scroll = maxf(scroll - 35, 0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if panel_rect.has_point(event.position):
				scroll += 35
	elif event is InputEventMouseMotion:
		_update_hover(event.position)

func _update_hover(pos: Vector2):
	hovered_mission = ""
	var rects = get_meta("mission_rects", [])
	for entry in rects:
		if entry.get("rect", Rect2()).has_point(pos):
			hovered_mission = entry.get("id", "")
			return

func _handle_click(pos: Vector2):
	# Tab buttons
	var tab_rects = get_meta("tab_rects", [])
	for i in tab_rects.size():
		if tab_rects[i].has_point(pos):
			tab = i
			scroll = 0.0
			selected_mission = ""
			return

	# Abandon button
	var abandon_rect = get_meta("abandon_btn_rect", Rect2())
	if abandon_rect.size.x > 0 and abandon_rect.has_point(pos) and tab == TAB_ACTIVE:
		if selected_mission != "":
			_abandon_mission(selected_mission)
			selected_mission = ""
		return

	# Mission row click
	var rects = get_meta("mission_rects", [])
	for entry in rects:
		if entry.get("rect", Rect2()).has_point(pos):
			var mid: String = entry.get("id", "")
			selected_mission = mid if selected_mission != mid else ""
			return

func _abandon_mission(mission_id: String):
	var idx = -1
	for i in GameManager.active_missions.size():
		if GameManager.active_missions[i].get("id", "") == mission_id:
			idx = i
			break
	if idx >= 0:
		# Remove cargo if it's a cargo haul
		var m = GameManager.active_missions[idx]
		if m.get("type", "") == "cargo_haul":
			var _cargo_id = m.get("cargo_id", "")
			var new_hold: Array = []
			for c in GameManager.cargo_hold:
				if c.get("mission_id", "") != mission_id:
					new_hold.append(c)
			GameManager.cargo_hold = new_hold
		GameManager.active_missions.remove_at(idx)

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Dim background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.97))

	# Panel frame
	var pw = minf(700, size.x - 60)
	var ph = minf(550, size.y - 60)
	var px = (size.x - pw) * 0.5
	var py = (size.y - ph) * 0.5
	panel_rect = Rect2(px, py, pw, ph)
	draw_rect(panel_rect, Color(0.04, 0.04, 0.06))
	draw_rect(panel_rect, Color(0.45, 0.55, 0.7, 0.6), false, 1.5)

	# Title
	draw_string(font, Vector2(px + 16, py + 24), "QUEST LOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.8, 0.9))
	draw_string(font, Vector2(px + pw - 130, py + 24), "[J] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.5, 0.6))

	# Tabs
	var tab_y = py + 38
	var tab_rects: Array = []
	var tab_names = ["ACTIVE (%d)" % GameManager.active_missions.size(), "COMPLETED (%d)" % GameManager.completed_missions.size()]
	var tab_x = px + 16
	for i in tab_names.size():
		var tw = font.get_string_size(tab_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20
		var tab_rect = Rect2(tab_x, tab_y, tw, 22)
		tab_rects.append(tab_rect)
		if i == tab:
			draw_rect(tab_rect, Color(0.1, 0.14, 0.2))
			draw_rect(tab_rect, Color(0.4, 0.55, 0.7, 0.7), false, 1.0)
			draw_string(font, Vector2(tab_x + 10, tab_y + 16), tab_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))
		else:
			draw_rect(tab_rect, Color(0.06, 0.06, 0.08))
			draw_string(font, Vector2(tab_x + 10, tab_y + 16), tab_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.5, 0.55))
		tab_x += tw + 8
	set_meta("tab_rects", tab_rects)

	# Separator
	var sep_y = tab_y + 28
	draw_line(Vector2(px + 10, sep_y), Vector2(px + pw - 10, sep_y), Color(0.15, 0.2, 0.28), 1.0)

	# Content area
	var list_y = sep_y + 6
	var detail_h = 110.0
	var list_h = ph - (list_y - py) - detail_h - 10

	if tab == TAB_ACTIVE:
		_draw_active_tab(font, px, list_y, pw, list_h)
	else:
		_draw_completed_tab(font, px, list_y, pw, list_h)

	# Detail area
	var detail_y = list_y + list_h + 8
	draw_line(Vector2(px + 10, detail_y), Vector2(px + pw - 10, detail_y), Color(0.15, 0.2, 0.28), 1.0)
	detail_y += 6
	_draw_detail(font, px, detail_y, pw, detail_h - 14)

func _draw_active_tab(font: Font, px: float, list_y: float, pw: float, list_h: float):
	var missions = GameManager.active_missions
	var mission_rects: Array = []

	if missions.is_empty():
		draw_string(font, Vector2(px + pw * 0.5 - 80, list_y + list_h * 0.4), "No active missions.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 0.38, 0.45))
		draw_string(font, Vector2(px + pw * 0.5 - 110, list_y + list_h * 0.4 + 20), "Visit a station to pick up contracts.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.32, 0.38))
		set_meta("mission_rects", mission_rects)
		return

	var ey = list_y - scroll
	for i in missions.size():
		var mission = missions[i]
		var mid = mission.get("id", "")
		var template = DataManager.missions.get(mid, {})
		var row_h = 52.0
		if ey + row_h > list_y and ey < list_y + list_h:
			var mrect = Rect2(px + 12, ey + 2, pw - 24, row_h - 4)
			mission_rects.append({"id": mid, "rect": mrect})
			_draw_mission_row(font, px, ey, pw, mid, mission, template, mrect, false)
		ey += row_h

	set_meta("mission_rects", mission_rects)

func _draw_completed_tab(font: Font, px: float, list_y: float, pw: float, list_h: float):
	var completed = GameManager.completed_missions
	var mission_rects: Array = []

	if completed.is_empty():
		draw_string(font, Vector2(px + pw * 0.5 - 80, list_y + list_h * 0.4), "No completed missions yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 0.38, 0.45))
		set_meta("mission_rects", mission_rects)
		return

	var ey = list_y - scroll
	for i in completed.size():
		var mid = completed[i]
		var template = DataManager.missions.get(mid, {})
		var row_h = 42.0
		if ey + row_h > list_y and ey < list_y + list_h:
			var mrect = Rect2(px + 12, ey + 2, pw - 24, row_h - 4)
			mission_rects.append({"id": mid, "rect": mrect})
			_draw_mission_row(font, px, ey, pw, mid, {}, template, mrect, true)
		ey += row_h

	set_meta("mission_rects", mission_rects)

func _draw_mission_row(font: Font, px: float, ey: float, pw: float, mid: String, mission: Dictionary, template: Dictionary, mrect: Rect2, is_completed: bool):
	var mtype = template.get("type", mission.get("type", ""))
	var is_selected = mid == selected_mission
	var is_hovered = mid == hovered_mission
	var tc = TYPE_COLORS.get(mtype, Color(0.5, 0.5, 0.5))
	var type_label = TYPE_LABELS.get(mtype, "???")

	# Background
	if is_selected:
		draw_rect(mrect, Color(0.08, 0.12, 0.18))
		draw_rect(mrect, Color(0.35, 0.5, 0.7, 0.6), false, 1.0)
	elif is_hovered:
		draw_rect(mrect, Color(0.06, 0.08, 0.12))

	# Type badge
	var badge_x = px + 18
	var badge_y = ey + 6
	draw_rect(Rect2(badge_x, badge_y, 50, 16), Color(tc, 0.15))
	draw_rect(Rect2(badge_x, badge_y, 50, 16), Color(tc, 0.5), false, 1.0)
	draw_string(font, Vector2(badge_x + 4, badge_y + 12), type_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tc)

	# Title
	var title = template.get("title", mid)
	var title_col = Color(0.5, 0.6, 0.55) if is_completed else Color(0.8, 0.82, 0.88)
	draw_string(font, Vector2(badge_x + 58, badge_y + 12), title, HORIZONTAL_ALIGNMENT_LEFT, int(pw - 120), 13, title_col)

	# Giver
	var giver = template.get("giver", "")
	if giver != "":
		draw_string(font, Vector2(px + pw - 160, badge_y + 12), giver, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.45, 0.5))

	if is_completed:
		# Checkmark
		draw_string(font, Vector2(px + pw - 40, badge_y + 12), "[OK]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.75, 0.4))
		return

	# Progress line
	var prog_y = badge_y + 20
	var prog_text = ""
	match mtype:
		"cargo_haul":
			var dest = template.get("destination_system", "")
			var dest_name = DataManager.systems.get(dest, {}).get("name", dest)
			prog_text = "Deliver to " + dest_name
			if GameManager.current_system == dest:
				prog_text += " [ARRIVED]"
		"bounty":
			var target = template.get("kill_target", 5)
			var prog = mission.get("progress", 0)
			var target_sys = template.get("target_system", "")
			var sys_name = DataManager.systems.get(target_sys, {}).get("name", target_sys)
			prog_text = "Kills: %d/%d in %s" % [prog, target, sys_name]
		"salvage":
			var prog = mission.get("progress", 0)
			var target_poi = template.get("target_poi", "")
			prog_text = "Find: " + target_poi
			if prog >= 1:
				prog_text += " [FOUND]"
		"gather":
			var prog = mission.get("progress", 0)
			var target_amt = template.get("gather_target", 10)
			var res_name = template.get("gather_resource", "resources")
			prog_text = "Gather %s: %d/%d" % [res_name, prog, target_amt]
	draw_string(font, Vector2(badge_x, prog_y + 10), prog_text, HORIZONTAL_ALIGNMENT_LEFT, int(pw - 60), 10, Color(0.5, 0.55, 0.6))

	# Progress bar
	var bar_x = badge_x
	var bar_y = prog_y + 16
	var bar_w = pw - 60
	var bar_h = 4.0
	var pct = 0.0
	match mtype:
		"cargo_haul":
			pct = 1.0 if GameManager.current_system == template.get("destination_system", "") else 0.3
		"bounty":
			var target = maxf(template.get("kill_target", 5), 1)
			pct = clampf(float(mission.get("progress", 0)) / target, 0, 1)
		"salvage":
			pct = 1.0 if mission.get("progress", 0) >= 1 else 0.0
		"gather":
			var target = maxf(template.get("gather_target", 10), 1)
			pct = clampf(float(mission.get("progress", 0)) / target, 0, 1)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.06, 0.06, 0.08))
	if pct > 0.01:
		draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), Color(tc, 0.7))
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.18, 0.22), false, 0.5)

func _draw_detail(font: Font, px: float, dy: float, pw: float, dh: float):
	var abandon_rect = Rect2()

	if selected_mission == "":
		draw_string(font, Vector2(px + 16, dy + 14), "Select a mission to view details.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.42, 0.48))
		set_meta("abandon_btn_rect", abandon_rect)
		return

	var template = DataManager.missions.get(selected_mission, {})
	var title = template.get("title", selected_mission)
	var desc = template.get("description", "No description available.")
	var reward_text = template.get("reward_text", "")
	var reward_credits = template.get("reward_credits", 0)
	var is_completed = selected_mission in GameManager.completed_missions

	# Title
	draw_string(font, Vector2(px + 16, dy + 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))

	# Description (word-wrapped)
	var desc_lines = _wrap_text(desc, pw - 40, 11, font)
	var ly = dy + 30
	for line in desc_lines:
		draw_string(font, Vector2(px + 16, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.58, 0.65))
		ly += 14

	# Rewards
	ly += 4
	if reward_credits > 0:
		draw_string(font, Vector2(px + 16, ly), "Reward: %d credits" % reward_credits, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.75, 0.3))
		ly += 14
	if reward_text != "":
		draw_string(font, Vector2(px + 16, ly), reward_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.5))

	# Abandon button (active tab only)
	if tab == TAB_ACTIVE and not is_completed:
		var btn_w = 90.0
		var btn_h = 24.0
		var btn_x = px + pw - btn_w - 16
		var btn_y = dy + dh - btn_h - 2
		abandon_rect = Rect2(btn_x, btn_y, btn_w, btn_h)
		draw_rect(abandon_rect, Color(0.12, 0.05, 0.05))
		draw_rect(abandon_rect, Color(0.6, 0.2, 0.2, 0.7), false, 1.0)
		draw_string(font, Vector2(btn_x + 10, btn_y + 17), "ABANDON", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.3, 0.25))
	elif is_completed:
		draw_string(font, Vector2(px + pw - 120, dy + dh - 14), "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.75, 0.4))

	set_meta("abandon_btn_rect", abandon_rect)

func _wrap_text(text: String, max_width: float, font_size: int, font: Font) -> Array:
	var lines: Array = []
	var words = text.split(" ")
	var line = ""
	for word in words:
		var test = line + (" " if line != "" else "") + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width and line != "":
			lines.append(line)
			line = word
		else:
			line = test
	if line != "":
		lines.append(line)
	return lines
