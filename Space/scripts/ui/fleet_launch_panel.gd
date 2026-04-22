extends Control

## Fleet launch panel — shown after building a fleet ship.
## Player names the ship, selects crew to transfer, then launches.
## All rendering via _draw(), input via _input().

signal launched(ship_name: String, crew_ids: Array)
signal cancelled

var _skip_close_frame: bool = true
var fleet_core_id: String = ""
var fleet_modules: Array = []
var ship_name: String = ""
var naming_active: bool = true   # Start with naming focused
var selected_crew: Array = []    # crew IDs to transfer
var hovered_crew_idx: int = -1
var scroll_offset: float = 0.0

const CARD_H: float = 48.0
const CARD_GAP: float = 3.0

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)

func open_panel(core_id: String, modules: Array):
	fleet_core_id = core_id
	fleet_modules = modules
	# Auto-generate a ship name
	var names = ["Pathfinder", "Prospector", "Surveyor", "Pioneer", "Wanderer", "Venture", "Pilgrim", "Outrider", "Herald", "Seeker", "Drifter", "Ranger"]
	ship_name = names.pick_random() + " " + str(randi_range(1, 99))
	naming_active = true
	selected_crew = []
	hovered_crew_idx = -1
	scroll_offset = 0.0
	visible = true
	_skip_close_frame = true
	queue_redraw()

func _process(_delta: float):
	if not visible:
		return
	if _skip_close_frame:
		_skip_close_frame = false
		return
	queue_redraw()

func _input(event: InputEvent):
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if naming_active:
			# Text input for ship name
			match event.keycode:
				KEY_ENTER:
					naming_active = false
					get_viewport().set_input_as_handled()
				KEY_BACKSPACE:
					if ship_name.length() > 0:
						ship_name = ship_name.left(ship_name.length() - 1)
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_cancel()
					get_viewport().set_input_as_handled()
				_:
					var u = event.unicode
					if u > 31 and u < 127 and ship_name.length() < 24:
						ship_name += char(u)
					get_viewport().set_input_as_handled()
		else:
			match event.keycode:
				KEY_ESCAPE:
					_cancel()
					get_viewport().set_input_as_handled()
				KEY_ENTER:
					_launch()
					get_viewport().set_input_as_handled()
				KEY_A:
					if event.ctrl_pressed:
						# Select all available crew
						selected_crew = []
						for c in GameManager.ship_crew:
							if c.get("status") == "active" and not c.get("permanent", false):
								selected_crew.append(c.get("id", ""))
						get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed:
		if naming_active:
			match event.button_index:
				JOY_BUTTON_A:
					naming_active = false
					get_viewport().set_input_as_handled()
				JOY_BUTTON_B:
					_cancel()
					get_viewport().set_input_as_handled()
		else:
			var crew = _get_eligible_crew()
			match event.button_index:
				JOY_BUTTON_DPAD_DOWN:
					if crew.size() > 0:
						hovered_crew_idx = clampi(hovered_crew_idx + 1, 0, crew.size() - 1)
						# Auto-scroll to keep selection visible
						var list_rect = _get_crew_list_rect()
						var card_y = float(hovered_crew_idx) * (CARD_H + CARD_GAP)
						if card_y - scroll_offset + CARD_H > list_rect.size.y:
							scroll_offset = card_y + CARD_H - list_rect.size.y
					get_viewport().set_input_as_handled()
				JOY_BUTTON_DPAD_UP:
					if crew.size() > 0:
						hovered_crew_idx = maxi(hovered_crew_idx - 1, 0)
						var card_y = float(hovered_crew_idx) * (CARD_H + CARD_GAP)
						if card_y < scroll_offset:
							scroll_offset = card_y
					get_viewport().set_input_as_handled()
				JOY_BUTTON_A:
					# Toggle crew selection at hovered index
					if hovered_crew_idx >= 0 and hovered_crew_idx < crew.size():
						var cid = crew[hovered_crew_idx].get("id", "")
						if cid in selected_crew:
							selected_crew.erase(cid)
						else:
							selected_crew.append(cid)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_B:
					_cancel()
					get_viewport().set_input_as_handled()
				JOY_BUTTON_START:
					_launch()
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_offset = maxf(scroll_offset - 30, 0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var crew = _get_eligible_crew()
			var max_scroll = maxf(crew.size() * (CARD_H + CARD_GAP) - 300, 0)
			scroll_offset = minf(scroll_offset + 30, max_scroll)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_hover(event.position)

func _cancel():
	# Return modules to inventory (they were already consumed by builder close)
	for pm in fleet_modules:
		var mid = pm.get("id", "")
		if mid != "":
			GameManager.module_inventory[mid] = GameManager.module_inventory.get(mid, 0) + 1
	# Return core to inventory
	if fleet_core_id != "":
		GameManager.module_inventory[fleet_core_id] = GameManager.module_inventory.get(fleet_core_id, 0) + 1
	visible = false
	cancelled.emit()

func _launch():
	if ship_name.strip_edges() == "":
		ship_name = "Fleet Ship"
	visible = false
	launched.emit(ship_name.strip_edges(), selected_crew)

func _get_eligible_crew() -> Array:
	## Get crew that can be transferred (active, not the captain/permanent).
	var result: Array = []
	for c in GameManager.ship_crew:
		if c.get("status") == "active":
			result.append(c)
	return result

func _handle_click(pos: Vector2):
	# Name field click
	var name_rect = _get_name_rect()
	if name_rect.has_point(pos):
		naming_active = true
		return
	naming_active = false

	# Launch button
	if _get_launch_rect().has_point(pos):
		_launch()
		return

	# Cancel button
	if _get_cancel_rect().has_point(pos):
		_cancel()
		return

	# Crew list
	var list_rect = _get_crew_list_rect()
	if list_rect.has_point(pos):
		var crew = _get_eligible_crew()
		var local_y = pos.y - list_rect.position.y + scroll_offset
		var idx = int(local_y / (CARD_H + CARD_GAP))
		if idx >= 0 and idx < crew.size():
			var cid = crew[idx].get("id", "")
			if cid in selected_crew:
				selected_crew.erase(cid)
			else:
				selected_crew.append(cid)

func _update_hover(pos: Vector2):
	hovered_crew_idx = -1
	var list_rect = _get_crew_list_rect()
	if list_rect.has_point(pos):
		var crew = _get_eligible_crew()
		var local_y = pos.y - list_rect.position.y + scroll_offset
		var idx = int(local_y / (CARD_H + CARD_GAP))
		if idx >= 0 and idx < crew.size():
			hovered_crew_idx = idx

func _get_name_rect() -> Rect2:
	var cx = size.x * 0.5 - 200
	return Rect2(cx, 130, 400, 36)

func _get_crew_list_rect() -> Rect2:
	var cx = size.x * 0.5 - 200
	return Rect2(cx, 230, 400, size.y - 340)

func _get_launch_rect() -> Rect2:
	return Rect2(size.x * 0.5 + 60, size.y - 80, 140, 36)

func _get_cancel_rect() -> Rect2:
	return Rect2(size.x * 0.5 - 200, size.y - 80, 120, 36)

# --- Drawing ---

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.94))

	var cx = size.x * 0.5 - 200

	# Title
	draw_string(font, Vector2(cx, 50), "LAUNCH FLEET SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.7, 0.55, 0.9))

	# Hull info
	var core_data = DataManager.modules.get(fleet_core_id, {})
	var hull_name = core_data.get("name", "Unknown Hull")
	var mod_count = fleet_modules.size()
	draw_string(font, Vector2(cx, 80), "%s  |  %d modules" % [hull_name, mod_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65))

	# Ship name field
	draw_string(font, Vector2(cx, 118), "SHIP NAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.5, 0.6))
	var name_r = _get_name_rect()
	var name_bg = Color(0.08, 0.1, 0.14) if not naming_active else Color(0.1, 0.12, 0.18)
	draw_rect(name_r, name_bg)
	var name_border = Color(0.3, 0.4, 0.55) if not naming_active else Color(0.5, 0.6, 0.9)
	draw_rect(name_r, name_border, false, 1.0)
	var display_name = ship_name
	if naming_active:
		# Blink cursor
		@warning_ignore("integer_division")
		if int(Time.get_ticks_msec() / 500) % 2 == 0:
			display_name += "|"
	draw_string(font, Vector2(name_r.position.x + 10, name_r.position.y + 24), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.95))

	# Crew selection header
	var crew = _get_eligible_crew()
	draw_string(font, Vector2(cx, 210), "ASSIGN CREW (%d selected)" % selected_crew.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.5, 0.6))
	draw_string(font, Vector2(cx + 250, 210), "[Ctrl+A] Select all", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.4, 0.5))

	# Crew list
	var list_r = _get_crew_list_rect()
	draw_rect(list_r, Color(0.04, 0.05, 0.07, 0.6))
	draw_rect(list_r, Color(0.2, 0.25, 0.35, 0.3), false, 1.0)

	if crew.is_empty():
		draw_string(font, Vector2(list_r.position.x + 10, list_r.position.y + 30), "No crew available", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.4, 0.45))
	else:
		for i in crew.size():
			var c = crew[i]
			var cy = list_r.position.y + i * (CARD_H + CARD_GAP) - scroll_offset
			if cy + CARD_H < list_r.position.y or cy > list_r.position.y + list_r.size.y:
				continue

			var cid = c.get("id", "")
			var is_sel = cid in selected_crew
			var is_hov = (i == hovered_crew_idx)

			# Card background
			var bg = Color(0.06, 0.07, 0.1, 0.8)
			if is_sel:
				bg = Color(0.1, 0.12, 0.22, 0.9)
			if is_hov:
				bg = bg.lightened(0.06)
			draw_rect(Rect2(list_r.position.x, cy, list_r.size.x, CARD_H), bg)

			# Selection check
			if is_sel:
				draw_rect(Rect2(list_r.position.x, cy, 3, CARD_H), Color(0.4, 0.7, 0.95))
				# Checkmark
				draw_string(font, Vector2(list_r.position.x + 8, cy + 28), "[x]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.8, 0.5))
			else:
				draw_string(font, Vector2(list_r.position.x + 8, cy + 28), "[ ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.5))

			# Crew info
			var cname = c.get("name", "?")
			var role = c.get("role", "?").capitalize()
			var best = GameManager.get_best_skill(c)
			var best_val = GameManager.get_crew_skill(c, best)
			var name_col = Color(0.8, 0.85, 0.95) if is_sel else Color(0.65, 0.7, 0.8)
			draw_string(font, Vector2(list_r.position.x + 36, cy + 20), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
			draw_string(font, Vector2(list_r.position.x + 36, cy + 36), "%s — %s %d" % [role, best.capitalize(), best_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.6))

			# Health
			var hp = c.get("health", 100)
			var hp_col = Color(0.3, 0.8, 0.4) if hp > 60 else Color(0.85, 0.5, 0.2)
			draw_string(font, Vector2(list_r.position.x + list_r.size.x - 60, cy + 20), "%d HP" % int(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hp_col)

			# Permanent flag
			if c.get("permanent", false):
				draw_string(font, Vector2(list_r.position.x + list_r.size.x - 70, cy + 36), "CAPTAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.7, 0.3))

	# Buttons
	# Launch
	var launch_r = _get_launch_rect()
	var can_launch = not ship_name.strip_edges().is_empty()
	var launch_bg = Color(0.1, 0.15, 0.25, 0.9) if can_launch else Color(0.06, 0.07, 0.1, 0.6)
	draw_rect(launch_r, launch_bg)
	var launch_col = Color(0.4, 0.8, 0.5) if can_launch else Color(0.3, 0.35, 0.4)
	draw_rect(launch_r, launch_col, false, 1.0)
	draw_string(font, Vector2(launch_r.position.x + 20, launch_r.position.y + 24), "LAUNCH SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, launch_col)

	# Cancel
	var cancel_r = _get_cancel_rect()
	draw_rect(cancel_r, Color(0.08, 0.05, 0.05, 0.8))
	draw_rect(cancel_r, Color(0.7, 0.3, 0.25, 0.5), false, 1.0)
	draw_string(font, Vector2(cancel_r.position.x + 20, cancel_r.position.y + 24), "CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.4, 0.3))

	# Hint
	var hint_text: String
	if GameManager.using_controller:
		hint_text = "[Start] Launch  [B] Cancel  |  D-pad + [A] to select/deselect crew"
	else:
		hint_text = "[Enter] Launch  [Esc] Cancel  |  Click crew to select/deselect"
	draw_string(font, Vector2(cx, size.y - 30), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.4, 0.5, 0.6))
