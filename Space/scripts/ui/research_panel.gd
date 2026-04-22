extends Control

## Research panel -- shows available research projects grouped by category.
## Opened with R key. All rendering via _draw().

var _skip_close_frame: bool = true

# Layout
var panel_rect: Rect2 = Rect2()
var scroll: float = 0.0
var selected_project: String = ""
var hovered_project: String = ""
var gamepad_idx: int = -1  # Index into project_rects for gamepad navigation

# Category display order
const CATEGORIES: Array = ["weapons", "defense", "engines", "crew", "ship"]
const CATEGORY_COLORS: Dictionary = {
	"weapons": Color(0.9, 0.3, 0.25),
	"defense": Color(0.3, 0.5, 1.0),
	"engines": Color(1.0, 0.6, 0.2),
	"crew": Color(0.3, 0.8, 0.4),
	"ship": Color(0.6, 0.5, 0.8),
}

signal closed

func _ready():
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS

func open_panel():
	visible = true
	_skip_close_frame = true
	selected_project = ""
	hovered_project = ""
	gamepad_idx = -1
	scroll = 0.0

func _process(_delta):
	if not visible:
		return
	if _skip_close_frame:
		_skip_close_frame = false
		return
	if Input.is_action_just_pressed("toggle_research"):
		visible = false
		closed.emit()
		return
	queue_redraw()

func _input(event):
	if not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		var rects = get_meta("project_rects", [])
		match event.button_index:
			JOY_BUTTON_DPAD_DOWN:
				if rects.size() > 0:
					gamepad_idx = clampi(gamepad_idx + 1, 0, rects.size() - 1)
					var pid = rects[gamepad_idx].get("id", "")
					hovered_project = pid
					selected_project = pid if pid not in GameManager.completed_research else ""
			JOY_BUTTON_DPAD_UP:
				if rects.size() > 0:
					gamepad_idx = maxi(gamepad_idx - 1, 0)
					var pid = rects[gamepad_idx].get("id", "")
					hovered_project = pid
					selected_project = pid if pid not in GameManager.completed_research else ""
			JOY_BUTTON_A:
				if selected_project != "" and GameManager.can_research(selected_project):
					GameManager.start_research(selected_project)
					selected_project = ""
			JOY_BUTTON_B:
				visible = false
				closed.emit()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if panel_rect.has_point(event.position):
				scroll = maxf(scroll - 30, 0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if panel_rect.has_point(event.position):
				scroll += 30
	elif event is InputEventMouseMotion:
		_update_hover(event.position)

func _update_hover(pos: Vector2):
	hovered_project = ""
	if not panel_rect.has_point(pos):
		return
	# We'll determine hover in _draw via stored rects
	var rects = get_meta("project_rects", [])
	for entry in rects:
		if entry.get("rect", Rect2()).has_point(pos):
			hovered_project = entry.get("id", "")
			return

func _handle_click(pos: Vector2):
	# Check start button
	var start_rect = get_meta("start_btn_rect", Rect2())
	if start_rect.size.x > 0 and start_rect.has_point(pos):
		if selected_project != "" and GameManager.can_research(selected_project):
			GameManager.start_research(selected_project)
			selected_project = ""
		return

	# Check project rects
	var rects = get_meta("project_rects", [])
	for entry in rects:
		if entry.get("rect", Rect2()).has_point(pos):
			var pid: String = entry.get("id", "")
			if pid in GameManager.completed_research:
				selected_project = ""
			else:
				selected_project = pid if selected_project != pid else ""
			return

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Dim background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.97))

	# Panel frame
	var pw = minf(620, size.x - 60)
	var ph = minf(520, size.y - 60)
	var px = (size.x - pw) * 0.5
	var py = (size.y - ph) * 0.5
	panel_rect = Rect2(px, py, pw, ph)
	draw_rect(panel_rect, Color(0.04, 0.04, 0.06))
	draw_rect(panel_rect, Color(0.3, 0.5, 0.7, 0.6), false, 1.5)

	# Title
	draw_string(font, Vector2(px + 16, py + 24), "RESEARCH LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.8, 0.9))
	draw_string(font, Vector2(px + pw - 150, py + 24), "[R] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.5, 0.6))

	# Active research progress bar
	var bar_y = py + 34
	if GameManager.active_research != "":
		var proj = GameManager.RESEARCH_PROJECTS.get(GameManager.active_research, {})
		var rname = proj.get("name", GameManager.active_research)
		var rdur = proj.get("duration", 120.0)
		var rpct = clampf(GameManager.research_progress / maxf(rdur, 1), 0, 1)
		draw_string(font, Vector2(px + 16, bar_y + 12), "ACTIVE: " + rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.7, 0.95))
		draw_string(font, Vector2(px + pw - 60, bar_y + 12), "%d%%" % int(rpct * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.7, 0.95))
		var bar_x = px + 16
		var bar_w = pw - 32
		var bar_h = 8.0
		bar_y += 16
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.06, 0.06, 0.08))
		if rpct > 0.01:
			draw_rect(Rect2(bar_x, bar_y, bar_w * rpct, bar_h), Color(0.3, 0.6, 0.9) * 0.7)
			draw_rect(Rect2(bar_x, bar_y, bar_w * rpct, bar_h * 0.4), Color(0.3, 0.6, 0.9, 0.3))
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.25, 0.3, 0.4), false, 1.0)
		bar_y += bar_h + 4
		# Staffing info
		var staff = GameManager.count_crew_for_type("research_lab")
		var staff_col = Color(0.3, 0.8, 0.4) if staff > 0 else Color(0.9, 0.3, 0.2)
		var speed = 1.0 + (float(maxi(staff, 1)) - 1.0) * 0.3
		draw_string(font, Vector2(px + 16, bar_y + 10), "Staff: %d (%.1fx speed)" % [staff, speed if staff > 0 else 0.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, staff_col)
		if staff <= 0:
			draw_string(font, Vector2(px + pw * 0.5, bar_y + 10), "PAUSED - assign crew to lab!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.5, 0.15))
		bar_y += 16
	else:
		bar_y += 6

	# Completed count
	var comp_count = GameManager.completed_research.size()
	var total_count = GameManager.RESEARCH_PROJECTS.size()
	draw_string(font, Vector2(px + pw - 120, py + 24), "%d/%d" % [comp_count, total_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))

	# Project list area
	var list_y = bar_y + 4
	var list_h = ph - (list_y - py) - 80  # Leave room for detail area at bottom
	var project_rects: Array = []

	# Clip drawing to list area (manual via y checks)
	var ey = list_y - scroll

	for cat in CATEGORIES:
		# Category header
		if ey >= list_y - 20 and ey < list_y + list_h:
			var cat_col = CATEGORY_COLORS.get(cat, Color(0.5, 0.5, 0.5))
			draw_rect(Rect2(px + 10, ey + 2, 6, 12), cat_col)
			draw_string(font, Vector2(px + 22, ey + 13), cat.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cat_col)
		ey += 20

		# Projects in this category
		for pid in GameManager.RESEARCH_PROJECTS:
			var proj = GameManager.RESEARCH_PROJECTS[pid]
			if proj.get("category", "") != cat:
				continue
			if ey >= list_y - 28 and ey < list_y + list_h:
				var prect = Rect2(px + 14, ey, pw - 28, 24)
				project_rects.append({"id": pid, "rect": prect})
				_draw_project_row(font, px, ey, pw, pid, proj, prect)
			ey += 26
		ey += 6  # Gap between categories

	set_meta("project_rects", project_rects)

	# Detail area at bottom
	var detail_y = list_y + list_h + 8
	draw_line(Vector2(px + 10, detail_y), Vector2(px + pw - 10, detail_y), Color(0.2, 0.25, 0.35), 1.0)
	detail_y += 6
	_draw_detail(font, px, detail_y, pw, ph - (detail_y - py) - 10)

func _draw_project_row(font: Font, px: float, ey: float, pw: float, pid: String, proj: Dictionary, prect: Rect2):
	var is_completed = pid in GameManager.completed_research
	var is_active = pid == GameManager.active_research
	var is_selected = pid == selected_project
	var is_hovered = pid == hovered_project

	# Check if prereqs are met
	var prereqs: Array = proj.get("prereqs", [])
	var prereqs_met = true
	for p in prereqs:
		if p not in GameManager.completed_research:
			prereqs_met = false
			break

	# Background
	if is_selected:
		draw_rect(prect, Color(0.1, 0.15, 0.25))
		draw_rect(prect, Color(0.3, 0.5, 0.7, 0.7), false, 1.5)
	elif is_hovered and not is_completed:
		draw_rect(prect, Color(0.07, 0.09, 0.14))
	elif is_active:
		draw_rect(prect, Color(0.08, 0.12, 0.18))

	var name_str = proj.get("name", pid)
	var desc_str = proj.get("desc", "")

	if is_completed:
		# Checkmark
		draw_string(font, Vector2(px + 18, ey + 16), "[OK]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 0.4))
		draw_string(font, Vector2(px + 52, ey + 16), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.55, 0.5))
		draw_string(font, Vector2(px + pw * 0.55, ey + 16), desc_str, HORIZONTAL_ALIGNMENT_LEFT, int(pw * 0.4), 10, Color(0.35, 0.45, 0.4))
	elif is_active:
		var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.2 + 0.8
		draw_string(font, Vector2(px + 18, ey + 16), "[..]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.6, 0.9, pulse))
		draw_string(font, Vector2(px + 52, ey + 16), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 0.9))
		draw_string(font, Vector2(px + pw * 0.55, ey + 16), desc_str, HORIZONTAL_ALIGNMENT_LEFT, int(pw * 0.4), 10, Color(0.4, 0.55, 0.7))
	elif not prereqs_met:
		# Locked
		draw_string(font, Vector2(px + 18, ey + 16), "[--]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.3, 0.3))
		draw_string(font, Vector2(px + 52, ey + 16), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.35, 0.38))
		draw_string(font, Vector2(px + pw * 0.55, ey + 16), desc_str, HORIZONTAL_ALIGNMENT_LEFT, int(pw * 0.4), 10, Color(0.3, 0.3, 0.32))
	else:
		# Available
		draw_string(font, Vector2(px + 18, ey + 16), "[  ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))
		draw_string(font, Vector2(px + 52, ey + 16), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.85))
		draw_string(font, Vector2(px + pw * 0.55, ey + 16), desc_str, HORIZONTAL_ALIGNMENT_LEFT, int(pw * 0.4), 10, Color(0.5, 0.55, 0.6))

func _draw_detail(font: Font, px: float, dy: float, pw: float, dh: float):
	var start_rect = Rect2()

	if selected_project == "" or not GameManager.RESEARCH_PROJECTS.has(selected_project):
		draw_string(font, Vector2(px + 16, dy + 14), "Select a project to view details.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.42, 0.48))
		if not GameManager._has_research_lab():
			draw_string(font, Vector2(px + 16, dy + 30), "You need a Research Lab module to begin research.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.5, 0.2))
		set_meta("start_btn_rect", start_rect)
		return

	var proj = GameManager.RESEARCH_PROJECTS[selected_project]
	var name_str = proj.get("name", selected_project)
	var desc_str = proj.get("desc", "")
	var cost: Dictionary = proj.get("cost", {})
	var prereqs: Array = proj.get("prereqs", [])
	var duration: float = proj.get("duration", 120.0)
	var is_completed = selected_project in GameManager.completed_research
	var is_active = selected_project == GameManager.active_research

	# Name and description
	draw_string(font, Vector2(px + 16, dy + 14), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	draw_string(font, Vector2(px + 16, dy + 30), desc_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.7))

	# Duration
	var dur_text = "Time: %ds" % int(duration)
	draw_string(font, Vector2(px + pw - 120, dy + 14), dur_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.6))

	# Cost
	var cost_x = px + 16
	var cost_y = dy + 46
	draw_string(font, Vector2(cost_x, cost_y), "Cost:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
	cost_x += 35
	for res_type in cost:
		var needed = int(cost[res_type])
		var have = GameManager.resources.get(res_type, 0)
		var enough = have >= needed
		var info = GameManager.RESOURCE_TYPES.get(res_type, {})
		var rc_arr = info.get("color", [0.5, 0.5, 0.5])
		var rc = Color(rc_arr[0], rc_arr[1], rc_arr[2])
		draw_rect(Rect2(cost_x, cost_y - 8, 5, 5), rc)
		var cost_label = "%s:%d" % [res_type.substr(0, 3), needed]
		var cost_col = Color(0.5, 0.8, 0.4) if enough else Color(0.8, 0.3, 0.25)
		draw_string(font, Vector2(cost_x + 7, cost_y), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cost_col)
		cost_x += font.get_string_size(cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 16

	# Prerequisites
	if not prereqs.is_empty():
		var preq_x = px + 16
		var preq_y = cost_y + 16
		draw_string(font, Vector2(preq_x, preq_y), "Requires:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
		preq_x += 60
		for p in prereqs:
			var pdata = GameManager.RESEARCH_PROJECTS.get(p, {})
			var pname = pdata.get("name", p)
			var pmet = p in GameManager.completed_research
			var pcol = Color(0.4, 0.8, 0.4) if pmet else Color(0.8, 0.35, 0.25)
			draw_string(font, Vector2(preq_x, preq_y), pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, pcol)
			preq_x += font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12

	# Start button
	if not is_completed and not is_active:
		var can_do = GameManager.can_research(selected_project)
		var btn_w = 80.0
		var btn_h = 24.0
		var btn_x = px + pw - btn_w - 16
		var btn_y = dy + dh - btn_h - 4
		start_rect = Rect2(btn_x, btn_y, btn_w, btn_h)
		if can_do:
			draw_rect(start_rect, Color(0.08, 0.18, 0.12))
			draw_rect(start_rect, Color(0.3, 0.6, 0.4), false, 1.5)
			draw_string(font, Vector2(btn_x + 14, btn_y + 17), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.9, 0.5))
		else:
			draw_rect(start_rect, Color(0.06, 0.06, 0.06))
			draw_rect(start_rect, Color(0.2, 0.2, 0.2), false, 1.0)
			draw_string(font, Vector2(btn_x + 14, btn_y + 17), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.3, 0.3))
	elif is_completed:
		draw_string(font, Vector2(px + pw - 120, dy + dh - 16), "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.8, 0.4))
	elif is_active:
		var rpct = int(GameManager.research_progress / maxf(duration, 1) * 100)
		draw_string(font, Vector2(px + pw - 140, dy + dh - 16), "IN PROGRESS %d%%" % rpct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.6, 0.9))

	set_meta("start_btn_rect", start_rect)
