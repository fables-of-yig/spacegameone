extends Control

## Mission board UI -- shown at stations. Lists available and active missions.
## Drawn entirely with _draw() vector graphics.

var available_missions: Array = []  # [{id, template}, ...]
var active_missions: Array = []     # GameManager.active_missions
var selected_idx: int = -1
var scroll_offset: int = 0
var viewing_tab: int = 0  # 0 = available, 1 = active
var hovered_idx: int = -1
var accept_btn_rect: Rect2 = Rect2()
var tab_available_rect: Rect2 = Rect2()
var tab_active_rect: Rect2 = Rect2()
var close_btn_rect: Rect2 = Rect2()

signal mission_accepted(mission_id: String)
signal closed

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_STOP
	var vp = get_viewport_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1920, 1080)
	size = vp
	set_anchors_preset(PRESET_FULL_RECT)

func open_board(system_id: String):
	visible = true
	selected_idx = -1
	scroll_offset = 0
	viewing_tab = 0
	_refresh_missions(system_id)

func _refresh_missions(system_id: String):
	available_missions.clear()
	var ids = DataManager.get_available_missions(system_id)
	for mid in ids:
		if mid in GameManager.completed_missions:
			continue
		var already_active = false
		for am in GameManager.active_missions:
			if am.get("id") == mid:
				already_active = true
				break
		if already_active:
			continue
		var template = DataManager.missions.get(mid, {})
		available_missions.append({"id": mid, "template": template})
	active_missions = GameManager.active_missions

func _process(_delta: float):
	if not visible:
		return
	_update_hover()
	queue_redraw()

func _update_hover():
	var mouse = get_local_mouse_position()
	hovered_idx = -1
	var panel = _get_panel_rect()
	var list_y = panel.position.y + 80
	var items = available_missions if viewing_tab == 0 else active_missions
	for i in items.size():
		var iy = list_y + i * 65 - scroll_offset * 65
		if iy < list_y or iy > panel.position.y + panel.size.y - 100:
			continue
		var item_r = Rect2(panel.position.x + 16, iy, panel.size.x - 32, 60)
		if item_r.has_point(mouse):
			hovered_idx = i

func _gui_input(event: InputEvent):
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_click()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_offset = maxi(scroll_offset - 1, 0)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_offset += 1
			accept_event()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_B:
			_close()
			accept_event()
	if event is InputEventJoypadButton and event.pressed:
		var items = available_missions if viewing_tab == 0 else active_missions
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				if items.size() > 0:
					if hovered_idx <= 0:
						hovered_idx = items.size() - 1
					else:
						hovered_idx -= 1
					selected_idx = hovered_idx
					# Scroll to keep selection visible
					if hovered_idx < scroll_offset:
						scroll_offset = hovered_idx
				accept_event()
			JOY_BUTTON_DPAD_DOWN:
				if items.size() > 0:
					if hovered_idx < items.size() - 1:
						hovered_idx += 1
					else:
						hovered_idx = 0
					selected_idx = hovered_idx
					var panel = _get_panel_rect()
					var visible_count = int((panel.size.y - 180) / 65)
					if hovered_idx >= scroll_offset + visible_count:
						scroll_offset = hovered_idx - visible_count + 1
				accept_event()
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				viewing_tab = 1 - viewing_tab
				selected_idx = -1
				hovered_idx = -1
				accept_event()
			JOY_BUTTON_A:
				if viewing_tab == 0 and selected_idx >= 0 and selected_idx < available_missions.size():
					var mid = available_missions[selected_idx].get("id", "")
					if GameManager.accept_mission(mid):
						AudioManager.play_sfx("mission_accept", 0.7)
						mission_accepted.emit(mid)
						available_missions.remove_at(selected_idx)
						active_missions = GameManager.active_missions
						selected_idx = -1
						hovered_idx = -1
				accept_event()
			JOY_BUTTON_B:
				_close()
				accept_event()

func _on_click():
	var mouse = get_local_mouse_position()
	# Tab clicks
	if tab_available_rect.has_point(mouse):
		viewing_tab = 0
		selected_idx = -1
		return
	if tab_active_rect.has_point(mouse):
		viewing_tab = 1
		selected_idx = -1
		return
	# Close button
	if close_btn_rect.has_point(mouse):
		_close()
		return
	# Accept button
	if accept_btn_rect.has_point(mouse) and viewing_tab == 0 and selected_idx >= 0:
		if selected_idx < available_missions.size():
			var mid = available_missions[selected_idx].get("id", "")
			if GameManager.accept_mission(mid):
				AudioManager.play_sfx("mission_accept", 0.7)
				mission_accepted.emit(mid)
				# Refresh
				available_missions.remove_at(selected_idx)
				active_missions = GameManager.active_missions
				selected_idx = -1
		return
	# List item click
	if hovered_idx >= 0:
		selected_idx = hovered_idx

func _close():
	visible = false
	closed.emit()

func _get_panel_rect() -> Rect2:
	var pw: float = 700.0
	var ph: float = 650.0
	return Rect2((size.x - pw) / 2, (size.y - ph) / 2, pw, ph)

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Dim background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))

	var panel = _get_panel_rect()
	var px = panel.position.x
	var py = panel.position.y
	var pw = panel.size.x
	var ph = panel.size.y

	# Panel background
	draw_rect(panel, Color(0.02, 0.025, 0.06))
	draw_rect(panel, Color(0.25, 0.3, 0.5), false, 2.0)
	# Inner glow line
	draw_rect(panel.grow(-2), Color(0.15, 0.2, 0.35, 0.3), false, 1.0)

	# Title
	draw_string(font, Vector2(px + 20, py + 30), "MISSION BOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.8, 0.95))

	# Close button
	close_btn_rect = Rect2(px + pw - 50, py + 8, 40, 28)
	draw_rect(close_btn_rect, Color(0.5, 0.2, 0.15, 0.5))
	draw_string(font, Vector2(px + pw - 42, py + 28), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.4, 0.3))

	# Tabs
	var tab_y = py + 48
	tab_available_rect = Rect2(px + 16, tab_y, 140, 26)
	tab_active_rect = Rect2(px + 164, tab_y, 140, 26)

	var avail_col = Color(0.15, 0.2, 0.35) if viewing_tab == 0 else Color(0.06, 0.07, 0.1)
	var active_col = Color(0.15, 0.2, 0.35) if viewing_tab == 1 else Color(0.06, 0.07, 0.1)
	draw_rect(tab_available_rect, avail_col)
	draw_rect(tab_available_rect, Color(0.3, 0.35, 0.5), false, 1.0)
	draw_string(font, Vector2(px + 26, tab_y + 19), "AVAILABLE (%d)" % available_missions.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))
	draw_rect(tab_active_rect, active_col)
	draw_rect(tab_active_rect, Color(0.3, 0.35, 0.5), false, 1.0)
	draw_string(font, Vector2(px + 174, tab_y + 19), "ACTIVE (%d)" % active_missions.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))

	# Cargo capacity display
	var cargo_text = "Cargo: %d/%d" % [GameManager.cargo_hold.size(), GameManager.cargo_capacity]
	var cargo_col = Color(0.5, 0.55, 0.6) if GameManager.cargo_hold.size() < GameManager.cargo_capacity else Color(0.9, 0.4, 0.2)
	draw_string(font, Vector2(px + pw - 130, tab_y + 19), cargo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cargo_col)

	# List area
	var list_y = py + 80
	var _list_h = ph - 180
	var items = available_missions if viewing_tab == 0 else active_missions

	if items.is_empty():
		var empty_msg = "No missions available here." if viewing_tab == 0 else "No active missions."
		draw_string(font, Vector2(px + pw / 2 - 80, list_y + 40), empty_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45))
	else:
		for i in items.size():
			var iy = list_y + i * 65 - scroll_offset * 65
			if iy < list_y - 10 or iy > py + ph - 110:
				continue
			_draw_mission_item(font, px + 16, iy, pw - 32, items[i], i)

	# Detail area / Accept button (available tab only)
	if viewing_tab == 0 and selected_idx >= 0 and selected_idx < available_missions.size():
		var detail_y = py + ph - 90
		var template = available_missions[selected_idx].get("template", {})
		# Description
		var desc = template.get("description", "")
		draw_string(font, Vector2(px + 20, detail_y + 16), desc, HORIZONTAL_ALIGNMENT_LEFT, int(pw - 200), 12, Color(0.6, 0.65, 0.7))
		# Reward
		var reward = template.get("reward_text", "")
		draw_string(font, Vector2(px + 20, detail_y + 36), "Reward: " + reward, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.75, 0.3))
		# Cargo requirement
		var mtype = template.get("type", "")
		if mtype == "cargo_haul":
			var cargo_needed = template.get("cargo_size", 1)
			var can_fit = GameManager.get_cargo_space_free() >= cargo_needed
			var cargo_label = "Requires %d cargo space" % cargo_needed
			var cc = Color(0.3, 0.8, 0.4) if can_fit else Color(0.9, 0.3, 0.2)
			draw_string(font, Vector2(px + 20, detail_y + 54), cargo_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, cc)
			if not can_fit:
				draw_string(font, Vector2(px + 20, detail_y + 68), "Install a Cargo Bay module!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.4, 0.2))

		# Accept button
		accept_btn_rect = Rect2(px + pw - 160, detail_y + 10, 140, 35)
		var can_accept = true
		if mtype == "cargo_haul" and GameManager.get_cargo_space_free() < template.get("cargo_size", 1):
			can_accept = false
		var btn_col = Color(0.15, 0.4, 0.25) if can_accept else Color(0.2, 0.2, 0.2)
		draw_rect(accept_btn_rect, btn_col)
		draw_rect(accept_btn_rect, Color(0.3, 0.7, 0.4) if can_accept else Color(0.3, 0.3, 0.3), false, 1.5)
		var btn_text_col = Color(0.3, 0.9, 0.5) if can_accept else Color(0.4, 0.4, 0.4)
		draw_string(font, Vector2(accept_btn_rect.position.x + 30, accept_btn_rect.position.y + 24), "ACCEPT", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, btn_text_col)
	else:
		accept_btn_rect = Rect2()

	# Active mission detail
	if viewing_tab == 1 and selected_idx >= 0 and selected_idx < active_missions.size():
		var detail_y = py + ph - 70
		var m = active_missions[selected_idx]
		var template = DataManager.missions.get(m.get("id", ""), {})
		var desc = template.get("description", "")
		draw_string(font, Vector2(px + 20, detail_y + 16), desc, HORIZONTAL_ALIGNMENT_LEFT, int(pw - 40), 12, Color(0.6, 0.65, 0.7))
		var reward = template.get("reward_text", "")
		draw_string(font, Vector2(px + 20, detail_y + 36), "Reward: " + reward, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.75, 0.3))

func _draw_mission_item(font: Font, x: float, y: float, w: float, item: Dictionary, idx: int):
	var is_active_tab = viewing_tab == 1
	var template: Dictionary
	var mission_data: Dictionary = {}
	if is_active_tab:
		mission_data = item
		template = DataManager.missions.get(item.get("id", ""), {})
	else:
		template = item.get("template", {})

	var item_r = Rect2(x, y, w, 58)
	var is_sel = idx == selected_idx
	var is_hov = idx == hovered_idx

	# Background
	if is_sel:
		draw_rect(item_r, Color(0.1, 0.15, 0.3))
		draw_rect(item_r, Color(0.35, 0.5, 0.85), false, 1.5)
	elif is_hov:
		draw_rect(item_r, Color(0.06, 0.08, 0.15))
	else:
		draw_rect(item_r, Color(0.03, 0.035, 0.06))

	# Type icon
	var mtype = template.get("type", "")
	var type_col = Color(0.5, 0.5, 0.5)
	var type_icon = "?"
	match mtype:
		"cargo_haul":
			type_col = Color(0.85, 0.65, 0.2)
			type_icon = "C"
		"bounty":
			type_col = Color(0.9, 0.3, 0.25)
			type_icon = "B"
		"salvage":
			type_col = Color(0.3, 0.7, 0.9)
			type_icon = "S"
		"gather":
			type_col = Color(0.4, 0.8, 0.5)
			type_icon = "G"

	# Type badge
	draw_rect(Rect2(x + 8, y + 8, 30, 30), type_col * 0.5)
	draw_rect(Rect2(x + 8, y + 8, 30, 30), type_col, false, 1.0)
	draw_string(font, Vector2(x + 17, y + 30), type_icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, type_col)

	# Title
	var title = template.get("title", "Unknown Mission")
	draw_string(font, Vector2(x + 48, y + 22), title, HORIZONTAL_ALIGNMENT_LEFT, int(w - 200), 14, Color(0.85, 0.87, 0.92))

	# Subtitle -- type + destination/target
	var subtitle = mtype.replace("_", " ").capitalize()
	match mtype:
		"cargo_haul":
			var dest = template.get("destination_system", "")
			var dest_name = DataManager.systems.get(dest, {}).get("name", dest)
			subtitle = "Deliver to " + dest_name
		"bounty":
			var target_sys = template.get("target_system", "")
			var target_name = DataManager.systems.get(target_sys, {}).get("name", target_sys)
			subtitle = "Hunt in " + target_name
		"salvage":
			var poi = template.get("target_poi", "")
			subtitle = "Find: " + poi
		"gather":
			var res_type = template.get("gather_resource", "")
			var res_name = GameManager.RESOURCE_TYPES.get(res_type, {}).get("name", res_type)
			subtitle = "Collect " + res_name
	draw_string(font, Vector2(x + 48, y + 40), subtitle, HORIZONTAL_ALIGNMENT_LEFT, int(w - 200), 11, Color(0.5, 0.55, 0.6))

	# Giver
	var giver = template.get("giver", "")
	draw_string(font, Vector2(x + 48, y + 53), "From: " + giver, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.42, 0.48))

	# Progress (active tab)
	if is_active_tab:
		var progress_text = ""
		match mtype:
			"cargo_haul":
				progress_text = "In transit..."
			"bounty":
				var target = template.get("kill_target", 5)
				var prog = mission_data.get("progress", 0)
				progress_text = "%d/%d kills" % [prog, target]
			"salvage":
				var prog = mission_data.get("progress", 0)
				progress_text = "Complete!" if prog >= 1 else "Searching..."
			"gather":
				var target = template.get("gather_target", 10)
				var prog = mission_data.get("progress", 0)
				progress_text = "%d/%d gathered" % [prog, target]
		var prog_col = Color(0.3, 0.8, 0.4) if progress_text == "Complete!" or progress_text == "In transit..." else Color(0.7, 0.65, 0.4)
		draw_string(font, Vector2(x + w - 110, y + 30), progress_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, prog_col)

	# Reward preview
	var reward_text = template.get("reward_text", "")
	if reward_text != "":
		draw_string(font, Vector2(x + w - 200, y + 53), reward_text, HORIZONTAL_ALIGNMENT_LEFT, 190, 9, Color(0.65, 0.55, 0.25))
