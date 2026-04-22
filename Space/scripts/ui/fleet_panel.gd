extends Control

## Fleet management panel — list fleet ships, multi-select, issue group orders.
## All rendering via _draw(), input via _input().

signal closed
signal build_requested(core_id: String)
signal command_requested(ship_id: String)  # Player wants to take command of a fleet ship
signal return_to_flagship()                # Player wants to return to main ship

var _skip_close_frame: bool = true
var scroll_offset: float = 0.0
var selected_ships: Array = []    # Array of ship IDs (strings)
var build_menu_open: bool = false  # Showing hull picker for new fleet ship
var hovered_idx: int = -1
var gamepad_idx: int = -1         # Gamepad-driven selection index
var detail_ship_id: String = ""   # Ship shown in detail pane (last single-clicked)
var order_hovered: int = -1       # Hovered order button index
var confirm_scuttle: bool = false # Two-click scuttle confirmation
var collect_flash: float = 0.0   # Flash feedback on collect
var route_picker_open: bool = false  # Transport route colony picker
var route_stops: Array = []          # Selected colony IDs for transport route
var route_hovered_idx: int = -1      # Hovered colony in route picker
var crew_picker_open: bool = false   # Crew transfer picker overlay
var crew_picker_scroll: float = 0.0  # Scroll offset for crew picker
var crew_picker_selected: Array = [] # Selected crew IDs to transfer

const CARD_H: float = 64.0
const CARD_GAP: float = 4.0
const LIST_X: float = 24.0
const LIST_W: float = 340.0
const DETAIL_PAD: float = 380.0

const ORDER_NAMES: Array = ["HOLD", "ORBIT", "PATROL", "ESCORT", "MINE", "SCOOP", "TRANSPORT"]
const ORDER_DESCS: Array = [
	"Stay in place",
	"Orbit current target",
	"Patrol the system",
	"Escort the flagship",
	"Mine asteroid field",
	"Scoop fuel from star",
	"Run transport route",
]
const ORDER_COLORS: Array = [
	[0.5, 0.5, 0.6],   # HOLD — grey
	[0.3, 0.7, 0.9],   # ORBIT — blue
	[0.4, 0.8, 0.5],   # PATROL — green
	[0.6, 0.7, 0.9],   # ESCORT — light blue
	[0.8, 0.6, 0.3],   # MINE — orange
	[0.9, 0.7, 0.2],   # SCOOP — gold
	[0.7, 0.5, 0.8],   # TRANSPORT — purple
]

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)

func open_panel():
	visible = true
	_skip_close_frame = true
	scroll_offset = 0.0
	hovered_idx = -1
	order_hovered = -1
	confirm_scuttle = false
	build_menu_open = false
	route_picker_open = false
	crew_picker_open = false
	crew_picker_selected = []
	gamepad_idx = -1
	# Keep selection if ships still exist, prune dead refs
	var valid: Array = []
	for sid in selected_ships:
		if not GameManager.get_fleet_ship(sid).is_empty():
			valid.append(sid)
	selected_ships = valid
	if selected_ships.size() == 1:
		detail_ship_id = selected_ships[0]
	queue_redraw()

func _process(delta: float):
	if not visible:
		return
	if _skip_close_frame:
		_skip_close_frame = false
		return
	if collect_flash > 0:
		collect_flash -= delta * 2.0
	queue_redraw()

func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_G:
				if crew_picker_open:
					crew_picker_open = false
					crew_picker_selected = []
				elif route_picker_open:
					route_picker_open = false
				elif build_menu_open:
					build_menu_open = false
				else:
					_close()
				get_viewport().set_input_as_handled()
			KEY_A:
				if event.ctrl_pressed:
					# Select all
					selected_ships = []
					for fs in GameManager.fleet_ships:
						selected_ships.append(fs.get("id", ""))
					if selected_ships.size() == 1:
						detail_ship_id = selected_ships[0]
					get_viewport().set_input_as_handled()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				var count = GameManager.fleet_ships.size()
				if count > 0:
					gamepad_idx = maxi(gamepad_idx - 1, 0)
					hovered_idx = gamepad_idx
					var sid = GameManager.fleet_ships[gamepad_idx].get("id", "")
					selected_ships = [sid]
					detail_ship_id = sid
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_DOWN:
				var count = GameManager.fleet_ships.size()
				if count > 0:
					gamepad_idx = mini(gamepad_idx + 1, count - 1)
					hovered_idx = gamepad_idx
					var sid = GameManager.fleet_ships[gamepad_idx].get("id", "")
					selected_ships = [sid]
					detail_ship_id = sid
				get_viewport().set_input_as_handled()
			JOY_BUTTON_A:
				if detail_ship_id != "":
					command_requested.emit(detail_ship_id)
					_close()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_B:
				if crew_picker_open:
					crew_picker_open = false
					crew_picker_selected = []
				elif route_picker_open:
					route_picker_open = false
				elif build_menu_open:
					build_menu_open = false
				else:
					_close()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if crew_picker_open:
				crew_picker_scroll = maxf(crew_picker_scroll - 28, 0)
			else:
				scroll_offset = maxf(scroll_offset - 40, 0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if crew_picker_open:
				var max_cs = maxf(GameManager.ship_crew.size() * 28.0 - (_get_crew_picker_rect().size.y - 100), 0)
				crew_picker_scroll = minf(crew_picker_scroll + 28, max_cs)
			else:
				var max_scroll = maxf(GameManager.fleet_ships.size() * (CARD_H + CARD_GAP) - (size.y - 180), 0)
				scroll_offset = minf(scroll_offset + 40, max_scroll)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_hover(event.position)

func _close():
	visible = false
	closed.emit()

func _refresh_player_ship():
	## Reapply loadout on the player ship after link/detach changes modules.
	var main_scene = get_tree().current_scene
	if main_scene and "player" in main_scene and main_scene.player and is_instance_valid(main_scene.player):
		main_scene.player.apply_loadout(GameManager.ship_modules)

func _handle_click(pos: Vector2):
	confirm_scuttle = false
	# Crew transfer picker
	if crew_picker_open:
		var crew_idx = _get_crew_picker_crew_at(pos)
		if crew_idx >= 0 and crew_idx < GameManager.ship_crew.size():
			var cid = GameManager.ship_crew[crew_idx].get("id", "")
			if cid in crew_picker_selected:
				crew_picker_selected.erase(cid)
			else:
				crew_picker_selected.append(cid)
			AudioManager.play_sfx("ui_click", 0.5)
			return
		if not crew_picker_selected.is_empty() and _get_crew_picker_confirm_rect().has_point(pos):
			GameManager.transfer_crew_to_fleet(detail_ship_id, crew_picker_selected)
			crew_picker_open = false
			crew_picker_selected = []
			AudioManager.play_sfx("ui_click", 0.6)
			return
		if _get_crew_picker_cancel_rect().has_point(pos):
			crew_picker_open = false
			crew_picker_selected = []
			return
		return
	# Route picker (transport route colony selection)
	if route_picker_open:
		var colony_idx = _get_route_colony_at(pos)
		if colony_idx >= 0:
			var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
			if colony_idx < colonies.size():
				var cid = colonies[colony_idx].get("id", "")
				if cid in route_stops:
					route_stops.erase(cid)
				else:
					route_stops.append(cid)
				AudioManager.play_sfx("ui_click", 0.5)
			return
		# Check confirm route button
		if route_stops.size() >= 2 and _get_route_confirm_rect().has_point(pos):
			for sid in selected_ships:
				GameManager.set_transport_route(sid, route_stops.duplicate())
			route_picker_open = false
			AudioManager.play_sfx("ui_click", 0.6)
			return
		# Check cancel
		if _get_route_cancel_rect().has_point(pos):
			route_picker_open = false
			return
		return
	# Hull picker (build menu)
	if build_menu_open:
		var picked = _get_hull_pick_at(pos)
		if picked != "":
			build_menu_open = false
			_close()
			build_requested.emit(picked)
			return
		# Click outside hull picker closes it
		build_menu_open = false
		return
	# Build button — works with ship's construction hangar OR when docked at station
	if _get_build_rect().has_point(pos):
		if GameManager.has_construction_hangar() or GameManager.docked_at_station:
			build_menu_open = true
			AudioManager.play_sfx("ui_click", 0.5)
		return
	# Check order buttons
	var order_idx = _get_order_at(pos)
	if order_idx >= 0 and not selected_ships.is_empty():
		_issue_order(order_idx)
		return
	# Check scuttle button
	if _get_scuttle_rect().has_point(pos) and detail_ship_id != "":
		if not confirm_scuttle:
			confirm_scuttle = true
		else:
			_scuttle_ship(detail_ship_id)
			confirm_scuttle = false
		return
	# Check recall crew button
	if _get_recall_rect().has_point(pos) and detail_ship_id != "":
		_recall_crew(detail_ship_id)
		return
	# Check assign crew button
	if _get_assign_crew_rect().has_point(pos) and detail_ship_id != "":
		var ship = GameManager.get_fleet_ship(detail_ship_id)
		if not ship.is_empty() and ship.get("system", "") == GameManager.current_system:
			if not GameManager.ship_crew.is_empty():
				crew_picker_open = true
				crew_picker_scroll = 0.0
				crew_picker_selected = []
				AudioManager.play_sfx("ui_click", 0.5)
		return
	# Check collect button
	if _get_collect_rect().has_point(pos) and detail_ship_id != "":
		var ship = GameManager.get_fleet_ship(detail_ship_id)
		if not ship.is_empty() and ship.get("system", "") == GameManager.current_system:
			_collect_from_ship(detail_ship_id)
			return
	# Check flagship button — promote fleet ship to flagship
	if _get_flagship_rect().has_point(pos) and detail_ship_id != "":
		var ship = GameManager.get_fleet_ship(detail_ship_id)
		if not ship.is_empty() and ship.get("system", "") == GameManager.current_system:
			if not ship.get("deployed_as_colony", false):
				# Store player position before swap
				var main_scene = get_tree().current_scene
				var player_pos = Vector2.ZERO
				if main_scene and "player" in main_scene and main_scene.player and is_instance_valid(main_scene.player):
					player_pos = main_scene.player.global_position
				var success = GameManager.promote_to_flagship(detail_ship_id)
				if success:
					# Set old player ship fleet entity position
					var old_ship = GameManager.fleet_ships.back()
					old_ship["world_pos"] = [player_pos.x, player_pos.y]
					# Spawn old player ship as fleet entity immediately
					if main_scene and main_scene.has_method("_spawn_single_fleet_ship"):
						main_scene._spawn_single_fleet_ship(old_ship)
					detail_ship_id = ""
					AudioManager.play_sfx("ui_click", 0.8)
					_refresh_player_ship()
					if main_scene and "hud_control" in main_scene and main_scene.hud_control:
						main_scene.hud_control.show_bark("FLEET", "New flagship designated!", Color(0.9, 0.8, 0.3), 3.0)
				return
	# Check link button — merge fleet ship into flagship
	if _get_link_rect().has_point(pos) and detail_ship_id != "":
		var ship = GameManager.get_fleet_ship(detail_ship_id)
		if not ship.is_empty() and ship.get("system", "") == GameManager.current_system:
			if GameManager.has_docking_collar():
				var success = GameManager.link_fleet_ship(detail_ship_id)
				if success:
					detail_ship_id = ""
					AudioManager.play_sfx("ui_click", 0.7)
					_refresh_player_ship()
					var main_scene = get_tree().current_scene
					if main_scene and "hud_control" in main_scene and main_scene.hud_control:
						main_scene.hud_control.show_bark("FLEET", "Ship linked to flagship", Color(0.6, 0.45, 0.9), 3.0)
				return
	# Check detach buttons — detach linked sections
	for si in GameManager.linked_sections.size():
		if _get_detach_rect(si).has_point(pos):
			var success = GameManager.detach_section(si)
			if success:
				AudioManager.play_sfx("ui_click", 0.6)
				_refresh_player_ship()
				var main_scene = get_tree().current_scene
				if main_scene and "hud_control" in main_scene and main_scene.hud_control:
					main_scene.hud_control.show_bark("FLEET", "Section detached", Color(0.7, 0.5, 0.3), 3.0)
			return
	# Check command button (take command / return to flagship)
	if _get_command_rect().has_point(pos):
		if GameManager.is_controlling_fleet_ship():
			# Return to player ship
			return_to_flagship.emit()
			_close()
			return
		elif detail_ship_id != "":
			# Take command of this fleet ship
			var ship = GameManager.get_fleet_ship(detail_ship_id)
			if not ship.is_empty() and ship.get("system", "") == GameManager.current_system:
				command_requested.emit(detail_ship_id)
				_close()
				return
	# Check ship list
	var list_top = 100.0
	var list_bottom = size.y - 100.0
	if pos.x >= LIST_X and pos.x <= LIST_X + LIST_W and pos.y >= list_top and pos.y <= list_bottom:
		var local_y = pos.y - list_top + scroll_offset
		var idx = int(local_y / (CARD_H + CARD_GAP))
		if idx >= 0 and idx < GameManager.fleet_ships.size():
			var ship = GameManager.fleet_ships[idx]
			var sid = ship.get("id", "")
			if Input.is_key_pressed(KEY_CTRL):
				# Toggle in multi-select
				if sid in selected_ships:
					selected_ships.erase(sid)
				else:
					selected_ships.append(sid)
			elif Input.is_key_pressed(KEY_SHIFT) and not selected_ships.is_empty():
				# Range select
				var last_sid = selected_ships[-1]
				var start_idx = -1
				var end_idx = idx
				for i in GameManager.fleet_ships.size():
					if GameManager.fleet_ships[i].get("id") == last_sid:
						start_idx = i
						break
				if start_idx >= 0:
					var from = mini(start_idx, end_idx)
					var to = maxi(start_idx, end_idx)
					for i in range(from, to + 1):
						var s = GameManager.fleet_ships[i].get("id", "")
						if s not in selected_ships:
							selected_ships.append(s)
			else:
				# Single select
				selected_ships = [sid]
			detail_ship_id = sid
		return

func _update_hover(pos: Vector2):
	hovered_idx = -1
	order_hovered = -1
	var list_top = 100.0
	var list_bottom = size.y - 100.0
	if pos.x >= LIST_X and pos.x <= LIST_X + LIST_W and pos.y >= list_top and pos.y <= list_bottom:
		var local_y = pos.y - list_top + scroll_offset
		var idx = int(local_y / (CARD_H + CARD_GAP))
		if idx >= 0 and idx < GameManager.fleet_ships.size():
			hovered_idx = idx
	order_hovered = _get_order_at(pos)

func _issue_order(order_idx: int):
	if order_idx == 6:  # TRANSPORT — open route picker
		var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
		if colonies.size() < 2:
			AudioManager.play_sfx("ui_click", 0.3)
			return  # Need at least 2 colonies for a route
		route_picker_open = true
		route_stops = []
		route_hovered_idx = -1
		AudioManager.play_sfx("ui_click", 0.5)
		return
	for sid in selected_ships:
		GameManager.set_fleet_order(sid, order_idx)
	AudioManager.play_sfx("ui_click", 0.5)

func _scuttle_ship(ship_id: String):
	# Return crew to player ship first
	_recall_crew(ship_id)
	GameManager.remove_fleet_ship(ship_id)
	selected_ships.erase(ship_id)
	if detail_ship_id == ship_id:
		detail_ship_id = ""
	AudioManager.play_sfx("power_down", 0.7)

func _recall_crew(ship_id: String):
	var ship = GameManager.get_fleet_ship(ship_id)
	if ship.is_empty():
		return
	var crew: Array = ship.get("crew", [])
	var ids: Array = []
	for c in crew:
		ids.append(c.get("id", ""))
	GameManager.transfer_crew_from_fleet(ship_id, ids)

func _collect_from_ship(ship_id: String):
	var result = GameManager.collect_from_fleet_ship(ship_id)
	if result.is_empty():
		return
	collect_flash = 1.0
	# Build bark message
	var parts: Array = []
	var res_dict: Dictionary = result.get("resources", {})
	for rk in res_dict:
		var info = GameManager.RESOURCE_TYPES.get(rk, {})
		parts.append("%d %s" % [res_dict[rk], info.get("name", rk)])
	if result.get("fuel", 0) > 0.5:
		parts.append("%.0f fuel" % result["fuel"])
	if result.get("food", 0) > 0.5:
		parts.append("%.0f food" % result["food"])
	if not parts.is_empty():
		var main_scene = get_tree().current_scene
		if main_scene and "hud_control" in main_scene and main_scene.hud_control:
			main_scene.hud_control.show_bark("FLEET", "Collected: " + ", ".join(parts), Color(0.3, 0.8, 0.5), 3.0)

func _get_build_rect() -> Rect2:
	return Rect2(LIST_X, size.y - 90, LIST_W, 34)

func _get_available_cores() -> Array:
	## Returns core IDs player owns in inventory.
	var result: Array = []
	for mid in GameManager.module_inventory:
		if GameManager.module_inventory[mid] > 0:
			var mdata = DataManager.modules.get(mid, {})
			if mdata.get("type", "") == "core":
				result.append(mid)
	return result

func _get_hull_pick_at(pos: Vector2) -> String:
	var cores = _get_available_cores()
	if cores.is_empty():
		return ""
	var pick_x = LIST_X + 20
	var pick_y = size.y - 130 - cores.size() * 44
	for i in cores.size():
		var ry = pick_y + i * 44
		if Rect2(pick_x, ry, LIST_W - 40, 40).has_point(pos):
			return cores[i]
	return ""

func _get_order_at(pos: Vector2) -> int:
	var btn_w: float = 90.0
	var btn_h: float = 32.0
	var btn_gap: float = 6.0
	var start_x: float = DETAIL_PAD
	var start_y: float = size.y - 80.0
	var cols = maxi(int((size.x - 20 - start_x) / (btn_w + btn_gap)), 1)
	for i in ORDER_NAMES.size():
		@warning_ignore("integer_division")
		var row = i / cols
		var col = i % cols
		var bx = start_x + col * (btn_w + btn_gap)
		var by = start_y + row * (btn_h + btn_gap)
		if Rect2(bx, by, btn_w, btn_h).has_point(pos):
			return i
	return -1

func _get_command_rect() -> Rect2:
	return Rect2(size.x - 400, size.y - 50, 130, 30)

func _get_scuttle_rect() -> Rect2:
	return Rect2(size.x - 130, size.y - 50, 110, 30)

func _get_recall_rect() -> Rect2:
	return Rect2(size.x - 260, size.y - 50, 120, 30)

func _get_collect_rect() -> Rect2:
	return Rect2(size.x - 540, size.y - 50, 120, 30)

func _get_assign_crew_rect() -> Rect2:
	return Rect2(size.x - 680, size.y - 50, 120, 30)

func _get_flagship_rect() -> Rect2:
	return Rect2(size.x - 960, size.y - 50, 120, 30)

func _get_link_rect() -> Rect2:
	return Rect2(size.x - 820, size.y - 50, 120, 30)

func _get_detach_rect(idx: int) -> Rect2:
	## Rect for the detach button of a linked section in the linked sections list.
	var sec_x = size.x - 260
	var base_y: float = _get_linked_sections_y()
	return Rect2(sec_x + 160, base_y + 22 + idx * 24, 70, 20)

func _get_linked_sections_y() -> float:
	## Y position where linked sections list starts in the detail pane.
	return 110.0  # Upper-right area of detail pane

func _get_crew_picker_rect() -> Rect2:
	var pw: float = 320.0
	var ph: float = minf(GameManager.ship_crew.size() * 28.0 + 90, size.y * 0.6)
	return Rect2(size.x * 0.5 - pw * 0.5, size.y * 0.5 - ph * 0.5, pw, ph)

func _get_crew_picker_crew_at(pos: Vector2) -> int:
	var pr = _get_crew_picker_rect()
	var list_top = pr.position.y + 50
	var list_bottom = pr.position.y + pr.size.y - 50
	if pos.x < pr.position.x + 10 or pos.x > pr.position.x + pr.size.x - 10:
		return -1
	if pos.y < list_top or pos.y > list_bottom:
		return -1
	var local_y = pos.y - list_top + crew_picker_scroll
	var idx = int(local_y / 28.0)
	if idx >= 0 and idx < GameManager.ship_crew.size():
		return idx
	return -1

func _get_crew_picker_confirm_rect() -> Rect2:
	var pr = _get_crew_picker_rect()
	return Rect2(pr.position.x + 10, pr.position.y + pr.size.y - 40, 120, 30)

func _get_crew_picker_cancel_rect() -> Rect2:
	var pr = _get_crew_picker_rect()
	return Rect2(pr.position.x + 150, pr.position.y + pr.size.y - 40, 120, 30)

func _get_route_colony_at(pos: Vector2) -> int:
	var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
	var picker_x = size.x * 0.5 - 140
	var picker_y = size.y * 0.5 - colonies.size() * 20
	for i in colonies.size():
		var ry = picker_y + 40 + i * 36
		if Rect2(picker_x + 10, ry, 260, 30).has_point(pos):
			return i
	return -1

func _get_route_confirm_rect() -> Rect2:
	var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
	var picker_x = size.x * 0.5 - 140
	var picker_y = size.y * 0.5 - colonies.size() * 20
	var bottom = picker_y + 50 + colonies.size() * 36
	return Rect2(picker_x + 10, bottom, 120, 30)

func _get_route_cancel_rect() -> Rect2:
	var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
	var picker_x = size.x * 0.5 - 140
	var picker_y = size.y * 0.5 - colonies.size() * 20
	var bottom = picker_y + 50 + colonies.size() * 36
	return Rect2(picker_x + 150, bottom, 120, 30)

# --- Drawing ---

func _draw():
	if not visible:
		return
	var font = ThemeDB.fallback_font

	# Full background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.92))

	# Title
	draw_string(font, Vector2(LIST_X, 40), "FLEET COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.7, 0.8, 0.95))
	var ship_count = GameManager.fleet_ships.size()
	var sel_count = selected_ships.size()
	var subtitle = "%d ship%s" % [ship_count, "" if ship_count == 1 else "s"]
	if sel_count > 0:
		subtitle += "  |  %d selected" % sel_count
	var linked_count = GameManager.linked_sections.size()
	if linked_count > 0:
		subtitle += "  |  %d linked" % linked_count
	draw_string(font, Vector2(LIST_X, 60), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.5, 0.6))

	# Divider under title
	draw_line(Vector2(LIST_X, 70), Vector2(size.x - 20, 70), Color(0.2, 0.3, 0.4, 0.5), 1.0)

	# Ship list
	_draw_ship_list(font)

	# Detail pane
	if detail_ship_id != "":
		_draw_detail(font)

	# Linked sections (always shown, independent of selected ship)
	_draw_linked_sections(font, DETAIL_PAD, size.x - DETAIL_PAD - 20)

	# Order buttons
	_draw_orders(font)

	# Build ship button (below ship list)
	_draw_build_button(font)

	# Hull picker overlay
	if build_menu_open:
		_draw_hull_picker(font)

	# Route picker overlay
	if route_picker_open:
		_draw_route_picker(font)

	# Crew transfer picker overlay
	if crew_picker_open:
		_draw_crew_picker(font)

	# Controls hint
	draw_string(font, Vector2(LIST_X, size.y - 10), "[G/ESC] Close  [Ctrl+Click] Multi-select  [Shift+Click] Range  [Ctrl+A] Select All", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.4, 0.5, 0.6))

	# Empty state
	if ship_count == 0 and not build_menu_open:
		draw_string(font, Vector2(size.x * 0.5 - 120, size.y * 0.5), "No fleet ships yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.45, 0.55))
		draw_string(font, Vector2(size.x * 0.5 - 160, size.y * 0.5 + 24), "Build ships from a Construction Hangar to grow your fleet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.4, 0.5))

func _draw_ship_list(font: Font):
	var list_top: float = 100.0
	var list_bottom: float = size.y - 100.0
	var clip = Rect2(LIST_X - 2, list_top - 2, LIST_W + 4, list_bottom - list_top + 4)

	# List background
	draw_rect(clip, Color(0.04, 0.05, 0.07, 0.6))
	draw_rect(clip, Color(0.2, 0.25, 0.35, 0.3), false, 1.0)

	# Column header
	draw_string(font, Vector2(LIST_X + 8, list_top - 6), "SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	draw_string(font, Vector2(LIST_X + LIST_W - 80, list_top - 6), "ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))

	for i in GameManager.fleet_ships.size():
		var ship = GameManager.fleet_ships[i]
		var cy = list_top + i * (CARD_H + CARD_GAP) - scroll_offset
		if cy + CARD_H < list_top or cy > list_bottom:
			continue  # Off screen

		var sid = ship.get("id", "")
		var is_selected = sid in selected_ships
		var is_hovered = (i == hovered_idx)
		var is_commanded = (sid == GameManager.active_ship_id)

		var card_rect = Rect2(LIST_X, cy, LIST_W, CARD_H)

		# Card background
		var bg = Color(0.06, 0.07, 0.1, 0.8)
		if is_commanded:
			bg = Color(0.08, 0.15, 0.1, 0.9)
		elif is_selected:
			bg = Color(0.1, 0.15, 0.25, 0.9)
		if is_hovered:
			bg = bg.lightened(0.08)
		draw_rect(card_rect, bg)

		# Selection / command indicator
		if is_commanded:
			draw_rect(Rect2(LIST_X, cy, 3, CARD_H), Color(0.3, 0.95, 0.4))
		elif is_selected:
			draw_rect(Rect2(LIST_X, cy, 3, CARD_H), Color(0.3, 0.7, 0.95))
		# Border
		var border_col = Color(0.2, 0.25, 0.35, 0.4)
		if is_selected:
			border_col = Color(0.3, 0.5, 0.7, 0.6)
		if is_hovered:
			border_col = border_col.lightened(0.1)
		draw_rect(card_rect, border_col, false, 1.0)

		# Ship name
		var sname = ship.get("name", "Unknown")
		var name_col = Color(0.8, 0.85, 0.95) if is_selected else Color(0.65, 0.7, 0.8)
		draw_string(font, Vector2(LIST_X + 10, cy + 20), sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)

		# Hull type
		var core_id = ship.get("core_id", "core_pod")
		var core_data = DataManager.modules.get(core_id, {})
		var hull_name = core_data.get("name", "Pod")
		draw_string(font, Vector2(LIST_X + 10, cy + 36), hull_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))

		# Crew count
		var crew_count = ship.get("crew", []).size()
		draw_string(font, Vector2(LIST_X + 10, cy + 50), "%d crew" % crew_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.55))

		# Health bar
		var hp_pct = ship.get("health", 100) / maxf(ship.get("max_health", 100), 1)
		var bar_x = LIST_X + 140
		var bar_y = cy + 42
		var bar_w = 60.0
		var bar_h = 6.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15))
		var hp_col = Color(0.3, 0.8, 0.4) if hp_pct > 0.5 else Color(0.85, 0.5, 0.2) if hp_pct > 0.25 else Color(0.9, 0.25, 0.2)
		draw_rect(Rect2(bar_x, bar_y, bar_w * hp_pct, bar_h), hp_col)

		# Current order
		var order_val = int(ship.get("order", 0))
		if order_val >= 0 and order_val < ORDER_NAMES.size():
			var oc = ORDER_COLORS[order_val]
			var order_col = Color(oc[0], oc[1], oc[2])
			draw_string(font, Vector2(LIST_X + LIST_W - 80, cy + 20), ORDER_NAMES[order_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, order_col)

		# System location
		var sys_id = ship.get("system", "")
		var sys_data = DataManager.systems.get(sys_id, {})
		var sys_name = sys_data.get("name", "Unknown")
		draw_string(font, Vector2(LIST_X + LIST_W - 80, cy + 36), sys_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.55))

func _draw_detail(font: Font):
	var ship = GameManager.get_fleet_ship(detail_ship_id)
	if ship.is_empty():
		detail_ship_id = ""
		return

	var dx: float = DETAIL_PAD
	var dy: float = 100.0
	var dw: float = size.x - DETAIL_PAD - 20

	# Detail background
	draw_rect(Rect2(dx, dy, dw, size.y - dy - 100), Color(0.04, 0.05, 0.07, 0.5))
	draw_rect(Rect2(dx, dy, dw, size.y - dy - 100), Color(0.2, 0.25, 0.35, 0.25), false, 1.0)

	# Ship name header
	var sname = ship.get("name", "Unknown")
	draw_string(font, Vector2(dx + 16, dy + 28), sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.85, 0.95))

	# Hull class
	var core_id = ship.get("core_id", "core_pod")
	var core_data = DataManager.modules.get(core_id, {})
	draw_string(font, Vector2(dx + 16, dy + 46), core_data.get("name", "Unknown Hull"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))

	# Stats columns
	var col1_x = dx + 16
	var _col2_x = dx + 200
	var sy = dy + 74

	# Health
	_draw_stat_bar(font, col1_x, sy, "HULL", ship.get("health", 100), ship.get("max_health", 100), Color(0.3, 0.8, 0.4))
	sy += 28

	# Shield
	if ship.get("max_shield", 0) > 0:
		_draw_stat_bar(font, col1_x, sy, "SHIELD", ship.get("shield", 0), ship.get("max_shield", 0), Color(0.3, 0.6, 0.95))
		sy += 28

	# Fuel
	_draw_stat_bar(font, col1_x, sy, "FUEL", ship.get("fuel", 0), ship.get("fuel_capacity", 50), Color(0.9, 0.7, 0.2))
	sy += 28

	# Food
	_draw_stat_bar(font, col1_x, sy, "FOOD", ship.get("food", 0), ship.get("food_capacity", 50), Color(0.5, 0.8, 0.4))
	sy += 28

	# Power
	var pw_out = ship.get("power_output", 0)
	var pw_draw = ship.get("power_draw", 0)
	var pw_col = Color(0.3, 0.8, 0.5) if pw_out >= pw_draw else Color(0.9, 0.3, 0.2)
	draw_string(font, Vector2(col1_x, sy), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	draw_string(font, Vector2(col1_x + 60, sy), "%d / %d" % [int(pw_draw), int(pw_out)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pw_col)
	sy += 22

	# Speed
	draw_string(font, Vector2(col1_x, sy), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	draw_string(font, Vector2(col1_x + 60, sy), "%d" % int(ship.get("max_speed", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.8))
	sy += 22

	# Production rates and active status
	var scoop = ship.get("scoop_rate", 0)
	var mine = ship.get("mine_rate", 0)
	var food_gen = ship.get("food_generation", 0)
	var order_val = int(ship.get("order", 0))
	if scoop > 0:
		var active_scoop = (order_val == 5)
		var scoop_label = "SCOOPING" if active_scoop else "SCOOP"
		var scoop_col = Color(1.0, 0.85, 0.3) if active_scoop else Color(0.9, 0.7, 0.3)
		draw_string(font, Vector2(col1_x, sy), scoop_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
		draw_string(font, Vector2(col1_x + 70, sy), "%.1f/s" % scoop, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, scoop_col)
		sy += 22
	if mine > 0:
		var active_mine = (order_val == 4)
		var mine_label = "MINING" if active_mine else "MINE"
		var mine_col = Color(1.0, 0.8, 0.3) if active_mine else Color(0.8, 0.6, 0.3)
		draw_string(font, Vector2(col1_x, sy), mine_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
		draw_string(font, Vector2(col1_x + 70, sy), "%.1f/s" % mine, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mine_col)
		if active_mine:
			var mrt = ship.get("mine_resource_type", "ore")
			var mri = GameManager.RESOURCE_TYPES.get(mrt, {})
			var mrn = mri.get("name", mrt.capitalize())
			draw_string(font, Vector2(col1_x + 120, sy), mrn, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.55, 0.5))
		sy += 22
	if food_gen > 0:
		draw_string(font, Vector2(col1_x, sy), "HYDRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
		draw_string(font, Vector2(col1_x + 70, sy), "%.1f/s" % food_gen, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.8, 0.4))
		sy += 22

	# Special modules
	if ship.get("has_colony_spear", false):
		draw_string(font, Vector2(col1_x, sy), "COLONY SPEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.8, 0.4))
		sy += 18
	if ship.get("has_fleet_comm", false):
		draw_string(font, Vector2(col1_x, sy), "FLEET COMM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.7, 0.9))
		sy += 18
	if ship.get("has_construction_hangar", false):
		draw_string(font, Vector2(col1_x, sy), "CONSTRUCTION HANGAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.6, 0.4))
		sy += 18

	# Current order
	sy += 10
	draw_string(font, Vector2(col1_x, sy), "CURRENT ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	if order_val >= 0 and order_val < ORDER_NAMES.size():
		var oc = ORDER_COLORS[order_val]
		draw_string(font, Vector2(col1_x + 100, sy), ORDER_NAMES[order_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(oc[0], oc[1], oc[2]))
	# Transport route display
	if order_val == 6:
		sy += 16
		var route: Array = ship.get("transport_route", [])
		if route.is_empty():
			draw_string(font, Vector2(col1_x + 10, sy), "No route set", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.4, 0.4))
		else:
			var tstate = ship.get("transport_state", "moving")
			var tidx = int(ship.get("transport_waypoint_idx", 0))
			for ri in route.size():
				var stop_name = GameManager.get_transport_stop_name(route[ri])
				var is_current = (ri == tidx)
				var stop_col = Color(0.7, 0.55, 0.85) if is_current else Color(0.45, 0.5, 0.6)
				var prefix = "> " if is_current else "  "
				var suffix = " [%s]" % tstate if is_current else ""
				draw_string(font, Vector2(col1_x + 10, sy), "%s%d. %s%s" % [prefix, ri + 1, stop_name, suffix], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, stop_col)
				sy += 14

	# Crew roster
	sy += 28
	draw_string(font, Vector2(col1_x, sy), "CREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	sy += 16
	var crew: Array = ship.get("crew", [])
	if crew.is_empty():
		draw_string(font, Vector2(col1_x, sy), "No crew assigned", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.4, 0.4))
	else:
		var shown = 0
		for c in crew:
			if shown >= 8:
				draw_string(font, Vector2(col1_x, sy), "+%d more" % (crew.size() - 8), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.5))
				break
			var cname = c.get("name", "?")
			var best = GameManager.get_best_skill(c)
			var skill_val = GameManager.get_crew_skill(c, best)
			var _role_label = c.get("role", "?").capitalize()
			draw_string(font, Vector2(col1_x, sy), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.65, 0.75))
			draw_string(font, Vector2(col1_x + 160, sy), "%s %d" % [best.capitalize(), skill_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.55, 0.65))
			sy += 16
			shown += 1

	# Resources
	var res: Dictionary = ship.get("resources", {})
	if not res.is_empty():
		sy += 12
		draw_string(font, Vector2(col1_x, sy), "CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
		sy += 16
		var total_cargo: int = 0
		for rk in res:
			var rv = int(res[rk])
			if rv > 0:
				total_cargo += rv
				var res_info = GameManager.RESOURCE_TYPES.get(rk, {})
				var rname = res_info.get("name", rk.capitalize())
				var rc = res_info.get("color", [0.55, 0.6, 0.7])
				draw_string(font, Vector2(col1_x, sy), "%s: %d" % [rname, rv], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(rc[0], rc[1], rc[2]))
				sy += 14
		var cap = int(ship.get("resource_capacity", 10))
		draw_string(font, Vector2(col1_x, sy), "%d / %d capacity" % [total_cargo, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.5))
		sy += 14

	# Command / Scuttle / Recall buttons
	var cmd_r = _get_command_rect()
	var is_controlling = GameManager.is_controlling_fleet_ship()
	var is_same_system = ship.get("system", "") == GameManager.current_system
	if is_controlling:
		# Show "RETURN TO FLAGSHIP" regardless of detail_ship_id
		draw_rect(cmd_r, Color(0.08, 0.12, 0.06, 0.8))
		draw_rect(cmd_r, Color(0.4, 0.8, 0.3, 0.7), false, 1.0)
		draw_string(font, Vector2(cmd_r.position.x + 6, cmd_r.position.y + 20), "RETURN TO FLAGSHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.9, 0.4))
	elif is_same_system:
		draw_rect(cmd_r, Color(0.06, 0.08, 0.14, 0.8))
		draw_rect(cmd_r, Color(0.3, 0.6, 0.95, 0.7), false, 1.0)
		draw_string(font, Vector2(cmd_r.position.x + 8, cmd_r.position.y + 20), "TAKE COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.7, 1.0))
	else:
		draw_rect(cmd_r, Color(0.05, 0.05, 0.07, 0.5))
		draw_rect(cmd_r, Color(0.25, 0.25, 0.3, 0.3), false, 1.0)
		draw_string(font, Vector2(cmd_r.position.x + 8, cmd_r.position.y + 20), "TAKE COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.35))

	var scuttle_r = _get_scuttle_rect()
	var scuttle_col = Color(0.7, 0.2, 0.15) if not confirm_scuttle else Color(0.95, 0.3, 0.2)
	draw_rect(scuttle_r, Color(0.15, 0.05, 0.03, 0.8))
	draw_rect(scuttle_r, scuttle_col, false, 1.0)
	var scuttle_text = "SCUTTLE" if not confirm_scuttle else "CONFIRM?"
	draw_string(font, Vector2(scuttle_r.position.x + 10, scuttle_r.position.y + 20), scuttle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, scuttle_col)

	var recall_r = _get_recall_rect()
	draw_rect(recall_r, Color(0.05, 0.08, 0.12, 0.8))
	draw_rect(recall_r, Color(0.4, 0.6, 0.8, 0.5), false, 1.0)
	draw_string(font, Vector2(recall_r.position.x + 10, recall_r.position.y + 20), "RECALL CREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 0.9))

	# Collect button — transfer cargo/fuel/food from fleet ship to player
	var collect_r = _get_collect_rect()
	var has_cargo = false
	var fleet_res: Dictionary = ship.get("resources", {})
	for rk in fleet_res:
		if int(fleet_res[rk]) > 0:
			has_cargo = true
			break
	if not has_cargo:
		has_cargo = ship.get("fuel", 0) > ship.get("fuel_capacity", 50) * 0.1 + 0.5
	if not has_cargo:
		has_cargo = ship.get("food", 0) > ship.get("food_capacity", 50) * 0.1 + 0.5
	if is_same_system and has_cargo:
		var cflash = clampf(collect_flash, 0, 1)
		var bg_col = Color(0.06, 0.12, 0.06, 0.8).lerp(Color(0.2, 0.5, 0.2, 0.9), cflash)
		draw_rect(collect_r, bg_col)
		draw_rect(collect_r, Color(0.3, 0.8, 0.4, 0.7), false, 1.0)
		draw_string(font, Vector2(collect_r.position.x + 16, collect_r.position.y + 20), "COLLECT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.9, 0.5))
	elif is_same_system:
		draw_rect(collect_r, Color(0.05, 0.05, 0.07, 0.5))
		draw_rect(collect_r, Color(0.25, 0.3, 0.25, 0.3), false, 1.0)
		draw_string(font, Vector2(collect_r.position.x + 16, collect_r.position.y + 20), "COLLECT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.35, 0.3))

	# Assign crew button — transfer crew from player ship to fleet ship
	var assign_r = _get_assign_crew_rect()
	var has_crew = not GameManager.ship_crew.is_empty()
	if is_same_system and has_crew:
		draw_rect(assign_r, Color(0.06, 0.08, 0.14, 0.8))
		draw_rect(assign_r, Color(0.4, 0.6, 0.9, 0.6), false, 1.0)
		draw_string(font, Vector2(assign_r.position.x + 10, assign_r.position.y + 20), "ASSIGN CREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0))
	elif is_same_system:
		draw_rect(assign_r, Color(0.05, 0.05, 0.07, 0.5))
		draw_rect(assign_r, Color(0.25, 0.25, 0.3, 0.3), false, 1.0)
		draw_string(font, Vector2(assign_r.position.x + 10, assign_r.position.y + 20), "ASSIGN CREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.35))

	# Flagship button — promote fleet ship to new flagship
	var flagship_r = _get_flagship_rect()
	var is_colony = ship.get("deployed_as_colony", false)
	if is_same_system and not is_colony:
		draw_rect(flagship_r, Color(0.12, 0.1, 0.04, 0.8))
		draw_rect(flagship_r, Color(0.9, 0.75, 0.2, 0.7), false, 1.0)
		draw_string(font, Vector2(flagship_r.position.x + 8, flagship_r.position.y + 20), "SET FLAGSHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.85, 0.3))
	elif is_same_system:
		draw_rect(flagship_r, Color(0.05, 0.05, 0.05, 0.5))
		draw_rect(flagship_r, Color(0.3, 0.3, 0.25, 0.3), false, 1.0)
		draw_string(font, Vector2(flagship_r.position.x + 8, flagship_r.position.y + 20), "SET FLAGSHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.25))

	# Link button — merge fleet ship into flagship as linked section
	var link_r = _get_link_rect()
	var has_collar = GameManager.has_docking_collar()
	if is_same_system and has_collar:
		draw_rect(link_r, Color(0.08, 0.06, 0.14, 0.8))
		draw_rect(link_r, Color(0.6, 0.45, 0.9, 0.7), false, 1.0)
		draw_string(font, Vector2(link_r.position.x + 16, link_r.position.y + 20), "LINK SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.55, 1.0))
	elif is_same_system:
		draw_rect(link_r, Color(0.05, 0.05, 0.07, 0.5))
		draw_rect(link_r, Color(0.3, 0.25, 0.35, 0.3), false, 1.0)
		draw_string(font, Vector2(link_r.position.x + 16, link_r.position.y + 20), "LINK SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.25, 0.35))
		draw_string(font, Vector2(link_r.position.x, link_r.position.y - 4), "Need docking collar", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.3, 0.35))

func _draw_linked_sections(font: Font, _dx: float, _dw: float):
	var sections = GameManager.linked_sections
	if sections.is_empty():
		return
	var sec_x = size.x - 260
	var sec_y = _get_linked_sections_y()
	draw_string(font, Vector2(sec_x, sec_y), "LINKED SECTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.45, 0.8))
	draw_line(Vector2(sec_x, sec_y + 6), Vector2(sec_x + 220, sec_y + 6), Color(0.4, 0.3, 0.55, 0.4), 1.0)
	for i in sections.size():
		var sec = sections[i]
		var sy = sec_y + 22 + i * 24
		var src_id = sec.get("source_id", "?")
		var mod_count = sec.get("modules", []).size()
		var label = "%s (%d mods)" % [src_id, mod_count]
		draw_string(font, Vector2(sec_x, sy + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.5, 0.7))
		# Detach button
		var det_r = _get_detach_rect(i)
		var mouse = get_local_mouse_position()
		var is_hov = det_r.has_point(mouse)
		var bg = Color(0.12, 0.06, 0.04, 0.8) if is_hov else Color(0.08, 0.05, 0.04, 0.7)
		draw_rect(det_r, bg)
		draw_rect(det_r, Color(0.7, 0.35, 0.2, 0.7) if is_hov else Color(0.5, 0.3, 0.2, 0.4), false, 1.0)
		draw_string(font, Vector2(det_r.position.x + 8, det_r.position.y + 14), "DETACH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.4, 0.25) if is_hov else Color(0.6, 0.35, 0.25))

func _draw_stat_bar(font: Font, x: float, y: float, label: String, current: float, max_val: float, col: Color):
	draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
	var bar_x = x + 60
	var bar_w = 100.0
	var bar_h = 8.0
	var bar_y = y - 8
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.12))
	var pct = clampf(current / maxf(max_val, 1), 0, 1)
	draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), col)
	draw_string(font, Vector2(bar_x + bar_w + 6, y), "%d/%d" % [int(current), int(max_val)], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.55, 0.65))

func _draw_orders(font: Font):
	if selected_ships.is_empty():
		return
	var btn_w: float = 90.0
	var btn_h: float = 32.0
	var btn_gap: float = 6.0
	var start_x: float = DETAIL_PAD
	var start_y: float = size.y - 80.0

	draw_string(font, Vector2(start_x, start_y - 14), "ORDERS — %d ship%s selected" % [selected_ships.size(), "" if selected_ships.size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))

	# Calculate layout (wrap if needed)
	var cols = maxi(int((size.x - 20 - start_x) / (btn_w + btn_gap)), 1)
	for i in ORDER_NAMES.size():
		@warning_ignore("integer_division")
		var row = i / cols
		var col = i % cols
		var bx = start_x + col * (btn_w + btn_gap)
		var by = start_y + row * (btn_h + btn_gap)
		var oc = ORDER_COLORS[i]
		var base_col = Color(oc[0], oc[1], oc[2])
		var is_hov = (i == order_hovered)

		# Button background
		var bg = Color(0.06, 0.07, 0.1, 0.85) if not is_hov else Color(0.1, 0.12, 0.18, 0.92)
		draw_rect(Rect2(bx, by, btn_w, btn_h), bg)
		draw_rect(Rect2(bx, by, btn_w, btn_h), base_col if is_hov else Color(base_col, 0.4), false, 1.0)

		# Label
		var tcol = base_col if is_hov else Color(base_col, 0.7)
		draw_string(font, Vector2(bx + 8, by + 14), ORDER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tcol)
		# Short desc on hover
		if is_hov:
			draw_string(font, Vector2(bx + 8, by + 26), ORDER_DESCS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.5, 0.6))

func _draw_build_button(font: Font):
	var br = _get_build_rect()
	var can_build = GameManager.has_construction_hangar() or GameManager.docked_at_station
	var bg = Color(0.08, 0.1, 0.18, 0.9) if can_build else Color(0.06, 0.06, 0.08, 0.5)
	draw_rect(br, bg)
	var bcol = Color(0.5, 0.7, 0.9) if can_build else Color(0.3, 0.3, 0.35)
	draw_rect(br, bcol, false, 1.0)
	var label = "+ BUILD NEW SHIP"
	if GameManager.docked_at_station and not GameManager.has_construction_hangar():
		label = "+ BUILD NEW SHIP (Station)"
	draw_string(font, Vector2(br.position.x + 10, br.position.y + 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, bcol)
	if not can_build:
		draw_string(font, Vector2(br.position.x + 180, br.position.y + 22), "(need Construction Hangar or Station)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.35, 0.3))

func _draw_hull_picker(font: Font):
	var cores = _get_available_cores()
	# Backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.4))
	var pick_x = LIST_X + 20
	var pick_h = cores.size() * 44 + 50
	var pick_y = size.y - 130 - cores.size() * 44
	var panel_r = Rect2(pick_x - 10, pick_y - 40, LIST_W - 20, pick_h + 40)
	draw_rect(panel_r, Color(0.04, 0.05, 0.08, 0.95))
	draw_rect(panel_r, Color(0.3, 0.4, 0.6, 0.5), false, 1.0)
	draw_string(font, Vector2(pick_x, pick_y - 16), "SELECT HULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.7, 0.85))
	if cores.is_empty():
		draw_string(font, Vector2(pick_x, pick_y + 20), "No hull frames in inventory.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.4, 0.4))
		draw_string(font, Vector2(pick_x, pick_y + 38), "Buy or craft a core module first.", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.45))
	else:
		for i in cores.size():
			var cid = cores[i]
			var cdata = DataManager.modules.get(cid, {})
			var ry = pick_y + i * 44
			var item_r = Rect2(pick_x, ry, LIST_W - 40, 40)
			# Hover detection
			var mouse = get_local_mouse_position()
			var is_hov = item_r.has_point(mouse)
			var ibg = Color(0.08, 0.1, 0.15, 0.8) if not is_hov else Color(0.12, 0.15, 0.22, 0.9)
			draw_rect(item_r, ibg)
			draw_rect(item_r, Color(0.3, 0.4, 0.55, 0.4) if not is_hov else Color(0.4, 0.55, 0.75, 0.7), false, 1.0)
			# Hull name
			draw_string(font, Vector2(pick_x + 10, ry + 18), cdata.get("name", cid), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.9) if is_hov else Color(0.6, 0.65, 0.75))
			# Decks / description
			var decks = int(cdata.get("deck_count", 1))
			var desc = "%d deck%s" % [decks, "" if decks == 1 else "s"]
			draw_string(font, Vector2(pick_x + 10, ry + 34), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))
			# Count in inventory
			var count = GameManager.module_inventory.get(cid, 0)
			draw_string(font, Vector2(pick_x + LIST_W - 100, ry + 18), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))

func _draw_route_picker(font: Font):
	var colonies = GameManager.get_colonies_in_system(GameManager.current_system)
	# Backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
	var picker_w: float = 280.0
	var picker_x = size.x * 0.5 - picker_w * 0.5
	var picker_y = size.y * 0.5 - colonies.size() * 20
	var picker_h = 90.0 + colonies.size() * 36.0
	var panel_r = Rect2(picker_x, picker_y - 10, picker_w, picker_h)
	draw_rect(panel_r, Color(0.04, 0.05, 0.08, 0.95))
	draw_rect(panel_r, Color(0.5, 0.4, 0.7, 0.5), false, 1.0)
	draw_string(font, Vector2(picker_x + 10, picker_y + 16), "SELECT TRANSPORT ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.55, 0.85))
	draw_string(font, Vector2(picker_x + 10, picker_y + 32), "Click colonies in order (min 2)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.6))
	# Colony list
	var mouse = get_local_mouse_position()
	for i in colonies.size():
		var col = colonies[i]
		var cid = col.get("id", "")
		var ry = picker_y + 40 + i * 36
		var item_r = Rect2(picker_x + 10, ry, 260, 30)
		var is_selected = cid in route_stops
		var is_hov = item_r.has_point(mouse)
		var ibg = Color(0.08, 0.1, 0.15, 0.8)
		if is_selected:
			ibg = Color(0.1, 0.07, 0.18, 0.9)
		if is_hov:
			ibg = ibg.lightened(0.08)
		draw_rect(item_r, ibg)
		var bcol = Color(0.5, 0.4, 0.7, 0.6) if is_selected else Color(0.3, 0.35, 0.45, 0.4)
		if is_hov:
			bcol = bcol.lightened(0.15)
		draw_rect(item_r, bcol, false, 1.0)
		# Checkbox
		var check_col = Color(0.4, 0.85, 0.4) if is_selected else Color(0.3, 0.35, 0.4)
		draw_rect(Rect2(picker_x + 16, ry + 8, 14, 14), check_col, false, 1.0)
		if is_selected:
			var idx_in_route = route_stops.find(cid) + 1
			draw_string(font, Vector2(picker_x + 18, ry + 20), str(idx_in_route), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.85, 0.4))
		# Colony name
		var tier_name = GameManager.get_colony_tier_name(col.get("tier", 1))
		var cname = col.get("name", "Colony")
		draw_string(font, Vector2(picker_x + 38, ry + 15), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.8, 0.9))
		draw_string(font, Vector2(picker_x + 38, ry + 27), tier_name + " — Pop: %d" % col.get("population", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.45, 0.5, 0.6))
	# Confirm / Cancel buttons
	var btn_y = picker_y + 50 + colonies.size() * 36
	var confirm_r = _get_route_confirm_rect()
	var cancel_r = _get_route_cancel_rect()
	var can_confirm = route_stops.size() >= 2
	var confirm_bg = Color(0.08, 0.15, 0.08) if can_confirm else Color(0.06, 0.06, 0.06)
	var confirm_border = Color(0.3, 0.7, 0.3) if can_confirm else Color(0.25, 0.25, 0.25)
	draw_rect(confirm_r, confirm_bg)
	draw_rect(confirm_r, confirm_border, false, 1.0)
	draw_string(font, Vector2(confirm_r.position.x + 20, btn_y + 20), "CONFIRM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.85, 0.4) if can_confirm else Color(0.35, 0.35, 0.35))
	draw_rect(cancel_r, Color(0.1, 0.06, 0.04))
	draw_rect(cancel_r, Color(0.6, 0.3, 0.2), false, 1.0)
	draw_string(font, Vector2(cancel_r.position.x + 25, btn_y + 20), "CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.4, 0.3))

func _draw_crew_picker(font: Font):
	# Backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
	var pr = _get_crew_picker_rect()
	draw_rect(pr, Color(0.04, 0.05, 0.08, 0.95))
	draw_rect(pr, Color(0.4, 0.5, 0.8, 0.5), false, 1.0)

	# Title
	var ship = GameManager.get_fleet_ship(detail_ship_id)
	var target_name = ship.get("name", "Fleet Ship") if not ship.is_empty() else "Fleet Ship"
	draw_string(font, Vector2(pr.position.x + 10, pr.position.y + 20), "ASSIGN CREW TO: %s" % target_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.7, 0.9))
	draw_string(font, Vector2(pr.position.x + 10, pr.position.y + 36), "Click to select, then confirm", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.5, 0.6))

	# Crew list
	var list_top = pr.position.y + 50
	var list_bottom = pr.position.y + pr.size.y - 50
	var mouse = get_local_mouse_position()

	for i in GameManager.ship_crew.size():
		var c = GameManager.ship_crew[i]
		var cy = list_top + i * 28.0 - crew_picker_scroll
		if cy + 28 < list_top or cy > list_bottom:
			continue
		var cid = c.get("id", "")
		var is_selected = cid in crew_picker_selected
		var item_r = Rect2(pr.position.x + 10, cy, pr.size.x - 20, 26)
		var is_hov = item_r.has_point(mouse)

		var ibg = Color(0.06, 0.07, 0.1, 0.8)
		if is_selected:
			ibg = Color(0.1, 0.12, 0.2, 0.9)
		if is_hov:
			ibg = ibg.lightened(0.06)
		draw_rect(item_r, ibg)

		var bcol = Color(0.4, 0.5, 0.8, 0.5) if is_selected else Color(0.2, 0.25, 0.35, 0.4)
		if is_hov:
			bcol = bcol.lightened(0.1)
		draw_rect(item_r, bcol, false, 1.0)

		# Checkbox
		var check_col = Color(0.4, 0.7, 1.0) if is_selected else Color(0.3, 0.35, 0.4)
		draw_rect(Rect2(pr.position.x + 16, cy + 6, 14, 14), check_col, false, 1.0)
		if is_selected:
			draw_string(font, Vector2(pr.position.x + 19, cy + 18), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, check_col)

		# Crew name and best skill
		var cname = c.get("name", "Unknown")
		var best = GameManager.get_best_skill(c)
		var skill_val = GameManager.get_crew_skill(c, best)
		draw_string(font, Vector2(pr.position.x + 36, cy + 18), cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.75, 0.85))
		draw_string(font, Vector2(pr.position.x + pr.size.x - 110, cy + 18), "%s %d" % [best.capitalize(), skill_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.55, 0.65))

	# Confirm / Cancel buttons
	var confirm_r = _get_crew_picker_confirm_rect()
	var cancel_r = _get_crew_picker_cancel_rect()
	var can_confirm = not crew_picker_selected.is_empty()
	var confirm_bg = Color(0.08, 0.12, 0.18) if can_confirm else Color(0.06, 0.06, 0.06)
	var confirm_border = Color(0.4, 0.6, 0.9) if can_confirm else Color(0.25, 0.25, 0.25)
	draw_rect(confirm_r, confirm_bg)
	draw_rect(confirm_r, confirm_border, false, 1.0)
	var sel_label = "ASSIGN (%d)" % crew_picker_selected.size() if can_confirm else "ASSIGN"
	draw_string(font, Vector2(confirm_r.position.x + 12, confirm_r.position.y + 20), sel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 1.0) if can_confirm else Color(0.35, 0.35, 0.35))
	draw_rect(cancel_r, Color(0.1, 0.06, 0.04))
	draw_rect(cancel_r, Color(0.6, 0.3, 0.2), false, 1.0)
	draw_string(font, Vector2(cancel_r.position.x + 25, cancel_r.position.y + 20), "CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.4, 0.3))
