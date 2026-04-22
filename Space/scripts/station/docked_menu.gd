extends Control

## Docked station menu — overlay shown while docked at a station.
## Provides access to Shop, Missions, Repairs, Ship Builder, Crew, and Undock.
## All rendering via _draw(), input via _input().

signal open_shop
signal open_missions
signal open_builder
signal open_crew
signal open_fleet
signal open_colony_panel
signal undock_requested

var station_name: String = "Station"
var hovered_idx: int = -1
var anim_time: float = 0.0
var is_colony: bool = false
var colony_id: String = ""

const MENU_ITEMS: Array = [
	{"label": "SHOP", "desc": "Buy and sell goods", "icon": "S", "action": "shop"},
	{"label": "MISSIONS", "desc": "Check the job board", "icon": "M", "action": "missions"},
	{"label": "REPAIRS", "desc": "Fix damaged modules", "icon": "R", "action": "repairs"},
	{"label": "SHIP BUILDER", "desc": "Modify your ship", "icon": "B", "action": "builder"},
	{"label": "FLEET", "desc": "Manage fleet ships", "icon": "G", "action": "fleet"},
	{"label": "CREW", "desc": "Manage your crew", "icon": "C", "action": "crew"},
	{"label": "UNDOCK", "desc": "Recall crew and depart", "icon": "U", "action": "undock"},
]

const COLONY_MENU_ITEMS: Array = [
	{"label": "COLONY", "desc": "Manage this colony", "icon": "H", "action": "colony_panel"},
	{"label": "COLLECT", "desc": "Gather colony resources", "icon": "L", "action": "collect"},
	{"label": "SUPPLY", "desc": "Send food to colony", "icon": "S", "action": "supply"},
	{"label": "REPAIRS", "desc": "Fix damaged modules", "icon": "R", "action": "repairs"},
	{"label": "SHIP BUILDER", "desc": "Modify your ship", "icon": "B", "action": "builder"},
	{"label": "FLEET", "desc": "Manage fleet ships", "icon": "G", "action": "fleet"},
	{"label": "CREW", "desc": "Manage your crew", "icon": "C", "action": "crew"},
	{"label": "DEPART", "desc": "Recall crew and leave", "icon": "U", "action": "undock"},
]

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)

func _get_items() -> Array:
	return COLONY_MENU_ITEMS if is_colony else MENU_ITEMS

func open_menu(sname: String = "Station", colony_mode: bool = false, col_id: String = ""):
	station_name = sname
	is_colony = colony_mode
	colony_id = col_id
	visible = true
	hovered_idx = -1
	anim_time = 0.0
	queue_redraw()

func close_menu():
	visible = false

func _process(delta: float):
	if not visible:
		return
	anim_time += delta
	queue_redraw()

func _input(event: InputEvent):
	if not visible:
		return
	var items = _get_items()
	if event is InputEventMouseMotion:
		hovered_idx = _get_item_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = _get_item_at(event.position)
		if idx >= 0 and idx < items.size():
			AudioManager.play_sfx("ui_click", 0.5)
			_activate(idx)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				close_menu()
				undock_requested.emit()
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				if hovered_idx < 0:
					hovered_idx = 0
				else:
					hovered_idx = wrapi(hovered_idx - 1, 0, items.size())
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_DOWN:
				if hovered_idx < 0:
					hovered_idx = 0
				else:
					hovered_idx = wrapi(hovered_idx + 1, 0, items.size())
				get_viewport().set_input_as_handled()
			JOY_BUTTON_A:
				if hovered_idx < 0:
					hovered_idx = 0
				elif hovered_idx < items.size():
					AudioManager.play_sfx("ui_click", 0.5)
					_activate(hovered_idx)
				get_viewport().set_input_as_handled()

func _activate(idx: int):
	var items = _get_items()
	var action = items[idx]["action"]
	match action:
		"shop":
			close_menu()
			open_shop.emit()
		"missions":
			close_menu()
			open_missions.emit()
		"repairs":
			close_menu()
			_do_repairs()
		"builder":
			close_menu()
			open_builder.emit()
		"fleet":
			close_menu()
			open_fleet.emit()
		"crew":
			close_menu()
			open_crew.emit()
		"colony_panel":
			close_menu()
			open_colony_panel.emit()
		"collect":
			_do_colony_collect()
		"supply":
			_do_colony_supply()
		"undock":
			close_menu()
			undock_requested.emit()

func _do_repairs():
	## Instant repair of all damaged modules (costs credits).
	var damaged = GameManager.get_damaged_modules()
	if damaged.is_empty():
		open_menu(station_name, is_colony, colony_id)
		return
	var total_cost: int = 0
	for mod in damaged:
		# Cost scales with damage severity — more damaged = more expensive
		var hp_pct = mod.get("hp", 0) / maxf(mod.get("max_hp", 1.0), 1.0)
		total_cost += int(25 + (1.0 - hp_pct) * 50)
	if GameManager.credits >= total_cost:
		GameManager.credits -= total_cost
		for mod in damaged:
			GameManager.repair_module(mod)
		AudioManager.play_sfx("repair", 0.7)
	open_menu(station_name, is_colony, colony_id)

func _do_colony_collect():
	## Collect resources from the docked colony.
	if colony_id == "":
		return
	var result = GameManager.collect_from_colony(colony_id)
	if not result.is_empty():
		AudioManager.play_sfx("ui_click", 0.6)
	open_menu(station_name, is_colony, colony_id)

func _do_colony_supply():
	## Send food from player cargo to the colony.
	if colony_id == "":
		return
	var supplied = GameManager.supply_colony(colony_id, GameManager.food_supply)
	if supplied > 0:
		AudioManager.play_sfx("ui_click", 0.6)
	open_menu(station_name, is_colony, colony_id)

func _get_item_at(mouse_pos: Vector2) -> int:
	var items = _get_items()
	var panel_w: float = 320.0
	var item_h: float = 52.0
	var gap: float = 6.0
	var total_h = items.size() * (item_h + gap) - gap
	var panel_x = 24.0
	var panel_y = size.y * 0.5 - total_h * 0.5 + 30
	for i in items.size():
		var iy = panel_y + i * (item_h + gap)
		var rect = Rect2(panel_x, iy, panel_w, item_h)
		if rect.has_point(mouse_pos):
			return i
	return -1

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font
	var items = _get_items()
	var panel_w: float = 320.0
	var item_h: float = 52.0
	var gap: float = 6.0
	var total_h = items.size() * (item_h + gap) - gap
	var panel_x = 24.0
	var header_y = size.y * 0.5 - total_h * 0.5 - 40
	var panel_y = size.y * 0.5 - total_h * 0.5 + 30

	# Sidebar background
	draw_rect(Rect2(0, 0, panel_x + panel_w + 20, size.y), Color(0.0, 0.0, 0.02, 0.55))
	draw_line(Vector2(panel_x + panel_w + 20, 0), Vector2(panel_x + panel_w + 20, size.y), Color(0.3, 0.4, 0.55, 0.3), 1.0)

	# Header
	draw_string(font, Vector2(panel_x, header_y), station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.72, 0.88))
	var subtitle = "COLONY" if is_colony else "DOCKED"
	var sub_col = Color(0.4, 0.85, 0.3, 0.8) if is_colony else Color(0.3, 0.8, 0.5, 0.8)
	draw_string(font, Vector2(panel_x, header_y + 22), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, sub_col)
	draw_line(Vector2(panel_x, header_y + 30), Vector2(panel_x + panel_w, header_y + 30), Color(0.3, 0.4, 0.55, 0.4), 1.0)

	# Menu items
	for i in items.size():
		var item = items[i]
		var iy = panel_y + i * (item_h + gap)
		var rect = Rect2(panel_x, iy, panel_w, item_h)
		var is_hovered = (i == hovered_idx)

		# Background
		var bg_col = Color(0.06, 0.07, 0.1, 0.85)
		if is_hovered:
			bg_col = Color(0.1, 0.12, 0.18, 0.92)
		if item["action"] == "undock":
			bg_col = Color(0.12, 0.06, 0.04, 0.85) if not is_hovered else Color(0.18, 0.08, 0.05, 0.92)
		draw_rect(rect, bg_col)

		# Border
		var border_col = Color(0.25, 0.3, 0.4, 0.5)
		if is_hovered:
			border_col = Color(0.4, 0.55, 0.75, 0.8)
		if item["action"] == "undock" and is_hovered:
			border_col = Color(0.8, 0.4, 0.2, 0.8)
		draw_rect(rect, border_col, false, 1.0)

		# Left accent
		var accent_col = Color(0.3, 0.6, 0.9)
		if item["action"] == "undock":
			accent_col = Color(0.9, 0.4, 0.2)
		elif item["action"] == "repairs":
			accent_col = Color(0.4, 0.8, 0.4)
		elif item["action"] == "fleet":
			accent_col = Color(0.7, 0.5, 0.9)
		elif item["action"] == "colony_panel":
			accent_col = Color(0.3, 0.85, 0.4)
		elif item["action"] == "collect":
			accent_col = Color(0.85, 0.75, 0.3)
		elif item["action"] == "supply":
			accent_col = Color(0.4, 0.7, 0.95)
		draw_rect(Rect2(panel_x, iy, 3, item_h), accent_col)

		# Icon circle
		var icon_x = panel_x + 24
		var icon_y = iy + item_h * 0.5
		draw_circle(Vector2(icon_x, icon_y), 14, Color(accent_col, 0.15))
		draw_arc(Vector2(icon_x, icon_y), 14, 0, TAU, 16, Color(accent_col, 0.4), 1.0)
		draw_string(font, Vector2(icon_x - 4, icon_y + 5), item["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent_col)

		# Label
		var label_col = Color(0.82, 0.85, 0.92) if not is_hovered else Color(0.95, 0.97, 1.0)
		draw_string(font, Vector2(panel_x + 48, iy + 22), item["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, label_col)

		# Description
		draw_string(font, Vector2(panel_x + 48, iy + 38), item["desc"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.5, 0.6))

		# Repairs: show damage count and cost
		if item["action"] == "repairs":
			var damaged = GameManager.get_damaged_modules()
			var dmg_text = ""
			if damaged.is_empty():
				dmg_text = "No damage"
			else:
				var cost: int = 0
				for dmod in damaged:
					var hp_pct = dmod.get("hp", 0) / maxf(dmod.get("max_hp", 1.0), 1.0)
					cost += int(25 + (1.0 - hp_pct) * 50)
				dmg_text = "%d modules — %d CR" % [damaged.size(), cost]
			draw_string(font, Vector2(panel_x + panel_w - 120, iy + 30), dmg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.55, 0.4))

		# Fleet: show ship count
		if item["action"] == "fleet":
			var fc = GameManager.fleet_ships.size()
			var fleet_text = "%d ship%s" % [fc, "" if fc == 1 else "s"] if fc > 0 else "No ships"
			draw_string(font, Vector2(panel_x + panel_w - 120, iy + 30), fleet_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.45, 0.65))

		# Colony collect: show resource summary
		if item["action"] == "collect" and colony_id != "":
			var col = GameManager.get_colony(colony_id)
			var res = col.get("resource_stockpile", {})
			var total: int = 0
			for v in res.values():
				total += int(v)
			var ct = "%d resources" % total if total > 0 else "Empty"
			draw_string(font, Vector2(panel_x + panel_w - 120, iy + 30), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.6, 0.3))

		# Colony supply: show food status
		if item["action"] == "supply" and colony_id != "":
			var col = GameManager.get_colony(colony_id)
			var food = col.get("food_stockpile", 0.0)
			var cap = col.get("food_capacity", 50.0)
			var ft = "Food: %d/%d" % [int(food), int(cap)]
			draw_string(font, Vector2(panel_x + panel_w - 120, iy + 30), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.6, 0.8))

	# Bottom hint
	var hint_y = panel_y + total_h + 20
	var hint_text = "[ESC] Depart" if is_colony else "[ESC] Undock"
	draw_string(font, Vector2(panel_x, hint_y), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.45, 0.55, 0.6))

	# Crew shore leave status (top right)
	_draw_shore_status(font)

func _draw_shore_status(font: Font):
	var crew = GameManager.ship_crew
	if crew.is_empty():
		return
	var sx = size.x - 200
	var sy = 60.0
	draw_string(font, Vector2(sx, sy), "CREW SHORE LEAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.65))
	sy += 16
	var count = 0
	for c in crew:
		if count >= 6:
			draw_string(font, Vector2(sx, sy), "+%d more" % (crew.size() - 6), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.5))
			break
		if c.get("status") != "active":
			continue
		var cname = c.get("name", "?").split(" ")[0]
		var needs = c.get("needs", {})
		var morale = int(needs.get("morale", 100))
		var col = Color(0.3, 0.8, 0.5) if morale > 50 else Color(0.85, 0.6, 0.2)
		draw_circle(Vector2(sx + 5, sy + 4), 3, col)
		draw_string(font, Vector2(sx + 14, sy + 8), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.65, 0.75))
		sy += 14
		count += 1
