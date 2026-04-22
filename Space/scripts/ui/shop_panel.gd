extends Control

## Shop panel — buy/sell modules and purchase supplies at stations.
## Three tabs: BUY (modules), SELL (modules), SUPPLIES (fuel, repair).

signal closed

var shop_stock: Array = []  # Module IDs available for purchase
var scroll_buy: float = 0.0
var scroll_sell: float = 0.0
var scroll_supply: float = 0.0
var scroll_craft: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0
var view_mode: String = "buy"  # "buy", "sell", "supply", or "craft"
var hovered_item_rects: Array = []  # [{rect, mod_id}] for tooltip tracking
var gamepad_idx: int = -1  # Currently highlighted button index for gamepad nav

# Supply pricing — per unit costs (can vary by system later)
const FUEL_UNIT: float = 10.0    # Fuel per purchase
const FUEL_PRICE: int = 8        # Credits per fuel unit purchase
const REPAIR_PRICE: int = 2      # Credits per HP repaired

func _ready():
	size = get_viewport_rect().size
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

func open_shop(system_id: String, _station_key: String = ""):
	shop_stock = DataManager.get_shop_stock(system_id)
	scroll_buy = 0.0
	scroll_sell = 0.0
	scroll_supply = 0.0
	scroll_craft = 0.0
	view_mode = "buy"
	gamepad_idx = -1
	visible = true
	queue_redraw()

func _process(delta: float):
	if not visible:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		_close()
		return
	if status_timer > 0:
		status_timer -= delta
		if status_timer <= 0:
			status_text = ""
	queue_redraw()

func _close():
	visible = false
	closed.emit()

func _draw():
	var font = ThemeDB.fallback_font
	var pw = size.x
	var ph = size.y
	var btn_rects: Array = []
	hovered_item_rects.clear()

	# Dim background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))

	# Panel frame
	var panel_w = minf(720, pw - 80)
	var panel_h = minf(520, ph - 80)
	var px = (pw - panel_w) * 0.5
	var py = (ph - panel_h) * 0.5
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.04, 0.04, 0.06))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.3, 0.5, 0.7, 0.6), false, 1.5)

	# Title
	draw_string(font, Vector2(px + 16, py + 24), "STATION SHOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.8, 0.9))
	# Credits
	draw_string(font, Vector2(px + panel_w - 180, py + 24), "Credits: " + str(GameManager.credits),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.82, 0.2))

	# Tabs: BUY / SELL / SUPPLY
	var tab_y = py + 36
	var tabs = [
		{"id": "tab_buy", "label": "BUY", "mode": "buy", "x": px + 10, "w": 60},
		{"id": "tab_sell", "label": "SELL", "mode": "sell", "x": px + 74, "w": 60},
		{"id": "tab_craft", "label": "CRAFT", "mode": "craft", "x": px + 138, "w": 70},
		{"id": "tab_supply", "label": "SUPPLY", "mode": "supply", "x": px + 212, "w": 80},
	]
	for tab in tabs:
		var tab_rect = Rect2(tab.x, tab_y, tab.w, 24)
		var active = view_mode == tab.mode
		draw_rect(tab_rect, Color(0.15, 0.2, 0.28) if active else Color(0.06, 0.06, 0.08))
		draw_string(font, Vector2(tab.x + 10, tab_y + 17), tab.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.9, 0.9, 0.95) if active else Color(0.45, 0.45, 0.5))
		btn_rects.append({"id": tab.id, "rect": tab_rect})

	# Close button
	var close_r = Rect2(px + panel_w - 70, tab_y, 60, 24)
	draw_rect(close_r, Color(0.15, 0.1, 0.1))
	draw_string(font, Vector2(px + panel_w - 58, tab_y + 17), "Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.5, 0.5))
	btn_rects.append({"id": "close", "rect": close_r})

	var list_y = tab_y + 32
	var list_h = panel_h - (list_y - py) - 36

	match view_mode:
		"buy":
			draw_string(font, Vector2(px + 16, list_y + 14), "Module", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			draw_string(font, Vector2(px + panel_w * 0.45, list_y + 14), "Type", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			draw_string(font, Vector2(px + panel_w * 0.6, list_y + 14), "Price", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			list_y += 20
			_draw_buy_list(px, list_y, panel_w, list_h, font, btn_rects)
		"sell":
			draw_string(font, Vector2(px + 16, list_y + 14), "Module", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			draw_string(font, Vector2(px + panel_w * 0.45, list_y + 14), "Type", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			draw_string(font, Vector2(px + panel_w * 0.6, list_y + 14), "Price", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			list_y += 20
			_draw_sell_list(px, list_y, panel_w, list_h, font, btn_rects)
		"craft":
			# Resource summary bar
			var res_x = px + 16
			for rt in GameManager.RESOURCE_TYPES:
				var amt = GameManager.resources.get(rt, 0)
				var info = GameManager.RESOURCE_TYPES[rt]
				var rc = Color(info.color[0], info.color[1], info.color[2])
				draw_rect(Rect2(res_x, list_y + 4, 6, 6), rc)
				var label = "%s:%d" % [rt.substr(0, 3), amt]
				draw_string(font, Vector2(res_x + 8, list_y + 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.55, 0.6))
				res_x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 16
			list_y += 18
			draw_string(font, Vector2(px + 16, list_y + 14), "Module", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			draw_string(font, Vector2(px + panel_w * 0.35, list_y + 14), "Cost", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))
			list_y += 20
			_draw_craft_list(px, list_y, panel_w, list_h, font, btn_rects)
		"supply":
			_draw_supply_tab(px, list_y, panel_w, list_h, font, btn_rects)

	# Status
	if status_text != "":
		draw_string(font, Vector2(px + 16, py + panel_h - 12), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.4))

	# Tooltip for hovered item
	_draw_shop_tooltip(font, px, py, panel_w, panel_h)

	set_meta("btn_rects", btn_rects)

	# Gamepad highlight
	if gamepad_idx >= 0 and gamepad_idx < btn_rects.size():
		var hr: Rect2 = btn_rects[gamepad_idx].rect
		draw_rect(hr, Color(0.4, 0.7, 1.0, 0.25))
		draw_rect(hr, Color(0.4, 0.7, 1.0, 0.7), false, 2.0)

func _draw_buy_list(px: float, list_y: float, panel_w: float, list_h: float, font: Font, btn_rects: Array):
	var ey = list_y - scroll_buy
	for mod_id in shop_stock:
		var mod_data = DataManager.modules.get(mod_id, {})
		if mod_data.is_empty():
			continue
		if ey >= list_y - 30 and ey < list_y + list_h:
			var mod_name = mod_data.get("name", mod_id)
			var mod_type = mod_data.get("type", "")
			var price = int(mod_data.get("buy_price", 0) * GameManager.get_station_price_mult())
			var can_afford = GameManager.credits >= price
			var desc = mod_data.get("description", "")

			var tc = _type_color(mod_type)
			draw_rect(Rect2(px + 10, ey + 6, 6, 14), tc)
			draw_string(font, Vector2(px + 20, ey + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w * 0.4), 12,
				Color(0.8, 0.8, 0.85) if can_afford else Color(0.4, 0.4, 0.42))
			draw_string(font, Vector2(px + panel_w * 0.45, ey + 18), mod_type, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.55))
			draw_string(font, Vector2(px + panel_w * 0.6, ey + 18), str(price) + " cr", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(0.95, 0.82, 0.2) if can_afford else Color(0.5, 0.35, 0.15))
			# Description line
			if desc != "":
				draw_string(font, Vector2(px + 20, ey + 30), desc, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w * 0.55), 9, Color(0.4, 0.42, 0.48))

			# Buy button
			var buy_r = Rect2(px + panel_w - 80, ey + 2, 60, 22)
			if can_afford:
				draw_rect(buy_r, Color(0.1, 0.18, 0.12))
				draw_rect(buy_r, Color(0.3, 0.5, 0.3), false, 1.0)
				draw_string(font, Vector2(px + panel_w - 68, ey + 17), "BUY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.9, 0.5))
			else:
				draw_rect(buy_r, Color(0.08, 0.08, 0.08))
				draw_string(font, Vector2(px + panel_w - 68, ey + 17), "BUY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.3))
			btn_rects.append({"id": "buy_" + mod_id, "rect": buy_r})
			# Track for tooltip
			hovered_item_rects.append({"rect": Rect2(px + 10, ey, panel_w - 90, 36), "mod_id": mod_id})

		ey += 36

func _draw_sell_list(px: float, list_y: float, panel_w: float, list_h: float, font: Font, btn_rects: Array):
	var inv = GameManager.module_inventory
	if inv.is_empty():
		draw_string(font, Vector2(px + 16, list_y + 18), "No modules in inventory to sell.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))
		return

	var ey = list_y - scroll_sell
	for mod_id in inv:
		var count: int = inv[mod_id]
		if count <= 0:
			continue
		var mod_data = DataManager.modules.get(mod_id, {})
		if ey >= list_y - 30 and ey < list_y + list_h:
			var mod_name = mod_data.get("name", mod_id)
			var mod_type = mod_data.get("type", "")
			var price = int(mod_data.get("sell_price", 0))
			var desc = mod_data.get("description", "")

			var tc = _type_color(mod_type)
			draw_rect(Rect2(px + 10, ey + 6, 6, 14), tc)
			draw_string(font, Vector2(px + 20, ey + 18), mod_name + " x" + str(count), HORIZONTAL_ALIGNMENT_LEFT, int(panel_w * 0.4), 12, Color(0.8, 0.8, 0.85))
			draw_string(font, Vector2(px + panel_w * 0.45, ey + 18), mod_type, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.55))
			draw_string(font, Vector2(px + panel_w * 0.6, ey + 18), str(price) + " cr", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.8, 0.4))
			if desc != "":
				draw_string(font, Vector2(px + 20, ey + 30), desc, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w * 0.55), 9, Color(0.4, 0.42, 0.48))

			# Sell button
			var sell_r = Rect2(px + panel_w - 80, ey + 2, 60, 22)
			draw_rect(sell_r, Color(0.18, 0.12, 0.08))
			draw_rect(sell_r, Color(0.5, 0.4, 0.2), false, 1.0)
			draw_string(font, Vector2(px + panel_w - 68, ey + 17), "SELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.75, 0.3))
			btn_rects.append({"id": "sell_" + mod_id, "rect": sell_r})
			hovered_item_rects.append({"rect": Rect2(px + 10, ey, panel_w - 90, 36), "mod_id": mod_id})

		ey += 36

func _draw_craft_list(px: float, list_y: float, panel_w: float, list_h: float, font: Font, btn_rects: Array):
	var recipes = GameManager.CRAFTING_RECIPES
	if recipes.is_empty():
		draw_string(font, Vector2(px + 16, list_y + 18), "No recipes known.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))
		return

	var ey = list_y - scroll_craft
	for mod_id in recipes:
		var recipe = recipes[mod_id]
		var mod_data = DataManager.modules.get(mod_id, {})
		if mod_data.is_empty():
			continue
		if ey >= list_y - 30 and ey < list_y + list_h:
			var mod_name = mod_data.get("name", mod_id)
			var mod_type = mod_data.get("type", "")
			var can_do = GameManager.can_craft(mod_id)

			var tc = _type_color(mod_type)
			draw_rect(Rect2(px + 10, ey + 6, 6, 14), tc)
			draw_string(font, Vector2(px + 20, ey + 18), mod_name, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w * 0.3), 12,
				Color(0.8, 0.8, 0.85) if can_do else Color(0.4, 0.4, 0.42))

			# Resource cost inline
			var cost_x = px + panel_w * 0.35
			for res_type in recipe:
				var needed = int(recipe[res_type])
				var have = GameManager.resources.get(res_type, 0)
				var enough = have >= needed
				var info = GameManager.RESOURCE_TYPES.get(res_type, {})
				var rc = Color(info.get("color", [0.5, 0.5, 0.5])[0], info.get("color", [0.5, 0.5, 0.5])[1], info.get("color", [0.5, 0.5, 0.5])[2])
				draw_rect(Rect2(cost_x, ey + 9, 5, 5), rc)
				var cost_label = "%d" % needed
				var cost_col = Color(0.5, 0.8, 0.4) if enough else Color(0.8, 0.3, 0.25)
				draw_string(font, Vector2(cost_x + 7, ey + 17), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cost_col)
				cost_x += font.get_string_size(cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14

			# Craft button
			var craft_r = Rect2(px + panel_w - 86, ey + 2, 68, 22)
			if can_do:
				draw_rect(craft_r, Color(0.08, 0.15, 0.18))
				draw_rect(craft_r, Color(0.2, 0.5, 0.6), false, 1.0)
				draw_string(font, Vector2(px + panel_w - 76, ey + 17), "CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.9, 0.85))
			else:
				draw_rect(craft_r, Color(0.06, 0.06, 0.06))
				draw_string(font, Vector2(px + panel_w - 76, ey + 17), "CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.25, 0.25, 0.25))
			btn_rects.append({"id": "craft_" + mod_id, "rect": craft_r})
			hovered_item_rects.append({"rect": Rect2(px + 10, ey, panel_w - 96, 28), "mod_id": mod_id})

		ey += 28

func _draw_supply_tab(px: float, list_y: float, panel_w: float, list_h: float, font: Font, btn_rects: Array):
	# Apply scroll offset — all content shifts up by scroll_supply
	var ey = list_y + 4 - scroll_supply
	var clip_top = list_y
	var clip_bot = list_y + list_h

	# --- FUEL ---
	var fuel_pct = GameManager.fuel / maxf(GameManager.fuel_capacity, 1)
	var fuel_full = GameManager.fuel >= GameManager.fuel_capacity - 0.1
	if ey + 50 > clip_top and ey < clip_bot:
		_draw_supply_row(px, ey, panel_w, font, btn_rects,
			"FUEL", Color(0.4, 0.6, 0.9),
			GameManager.fuel, GameManager.fuel_capacity, fuel_pct,
			"+%d units" % int(FUEL_UNIT), FUEL_PRICE, fuel_full, "sup_fuel")
	ey += 52

	# --- REPAIR (hull) ---
	var hull_dmg: float = 0.0
	var player = get_tree().get_first_node_in_group("player")
	if player:
		hull_dmg = player.max_health - player.health
	var repair_cost = int(ceilf(hull_dmg)) * REPAIR_PRICE
	var hull_full = hull_dmg < 1.0
	if ey + 50 > clip_top and ey < clip_bot:
		_draw_supply_row(px, ey, panel_w, font, btn_rects,
			"HULL REPAIR", Color(0.3, 0.8, 0.35),
			player.health if player else 0, player.max_health if player else 100,
			player.health / player.max_health if player else 1.0,
			"Full repair", repair_cost, hull_full, "sup_repair")
	ey += 52

	# Separator
	if ey > clip_top and ey < clip_bot:
		draw_line(Vector2(px + 16, ey), Vector2(px + panel_w - 16, ey), Color(0.2, 0.25, 0.35), 1.0)
	ey += 8

	# --- SELL RESOURCES ---
	var res = GameManager.resources
	if not res.is_empty():
		ey += 8
		if ey > clip_top and ey < clip_bot:
			draw_line(Vector2(px + 16, ey), Vector2(px + panel_w - 16, ey), Color(0.2, 0.25, 0.35), 1.0)
		ey += 8
		if ey + 20 > clip_top and ey < clip_bot:
			draw_string(font, Vector2(px + 16, ey + 14), "SELL RESOURCES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.7, 0.8))
			var total_value: int = 0
			for rt in res:
				var info = GameManager.RESOURCE_TYPES.get(rt, {})
				total_value += int(info.get("sell_price", 1)) * int(res[rt])
			var sell_all_r = Rect2(px + panel_w - 120, ey + 2, 104, 20)
			draw_rect(sell_all_r, Color(0.18, 0.14, 0.08))
			draw_rect(sell_all_r, Color(0.6, 0.45, 0.2), false, 1.0)
			draw_string(font, Vector2(sell_all_r.position.x + 6, ey + 15), "SELL ALL +%d cr" % total_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.75, 0.3))
			btn_rects.append({"id": "sup_sell_all_res", "rect": sell_all_r})
		ey += 24
		for rt in res:
			if ey > clip_bot:
				break
			var amount = int(res[rt])
			if amount <= 0:
				continue
			if ey + 20 > clip_top:
				var info = GameManager.RESOURCE_TYPES.get(rt, {})
				var rname = info.get("name", rt)
				var rprice = int(info.get("sell_price", 1))
				var rc_arr = info.get("color", [0.5, 0.5, 0.5])
				var rc = Color(rc_arr[0], rc_arr[1], rc_arr[2])
				draw_rect(Rect2(px + 16, ey + 4, 8, 8), rc)
				draw_string(font, Vector2(px + 30, ey + 12), "%s x%d" % [rname, amount], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.78))
				draw_string(font, Vector2(px + panel_w * 0.42, ey + 12), "%d cr/u" % rprice, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.55, 0.35))
				var s1_r = Rect2(px + panel_w - 190, ey, 36, 18)
				draw_rect(s1_r, Color(0.14, 0.1, 0.06))
				draw_rect(s1_r, Color(0.45, 0.35, 0.15), false, 1.0)
				draw_string(font, Vector2(s1_r.position.x + 6, ey + 13), "x1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.7, 0.3))
				btn_rects.append({"id": "sell_res_1_" + rt, "rect": s1_r})
				var s5_r = Rect2(px + panel_w - 148, ey, 36, 18)
				draw_rect(s5_r, Color(0.14, 0.1, 0.06))
				draw_rect(s5_r, Color(0.45, 0.35, 0.15), false, 1.0)
				draw_string(font, Vector2(s5_r.position.x + 6, ey + 13), "x5", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.7, 0.3) if amount >= 5 else Color(0.4, 0.35, 0.25))
				btn_rects.append({"id": "sell_res_5_" + rt, "rect": s5_r})
				var sa_r = Rect2(px + panel_w - 106, ey, 90, 18)
				draw_rect(sa_r, Color(0.16, 0.12, 0.06))
				draw_rect(sa_r, Color(0.5, 0.4, 0.15), false, 1.0)
				draw_string(font, Vector2(sa_r.position.x + 4, ey + 13), "ALL +%d" % (rprice * amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.75, 0.3))
				btn_rects.append({"id": "sell_res_all_" + rt, "rect": sa_r})
			ey += 22

	# --- TURN IN PRISONERS ---
	if not GameManager.prisoners.is_empty():
		ey += 8
		if ey > clip_top and ey < clip_bot:
			draw_line(Vector2(px + 16, ey), Vector2(px + panel_w - 16, ey), Color(0.2, 0.25, 0.35), 1.0)
		ey += 8
		if ey + 20 > clip_top and ey < clip_bot:
			draw_string(font, Vector2(px + 16, ey + 14), "TURN IN PRISONERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.7, 0.8))
		ey += 24
		for pi in GameManager.prisoners.size():
			if ey > clip_bot:
				break
			if ey + 20 > clip_top:
				var pris = GameManager.prisoners[pi]
				var pname = pris.get("name", "Unknown")
				var prole = pris.get("role", "spacer")
				var bounty = 50 + int(pris.get("skills", {}).get("combat", 3)) * 10
				draw_rect(Rect2(px + 16, ey + 3, 8, 8), Color(0.9, 0.5, 0.2))
				draw_string(font, Vector2(px + 30, ey + 12), "%s (%s)" % [pname, prole], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.78))
				var turn_r = Rect2(px + panel_w - 130, ey, 114, 18)
				draw_rect(turn_r, Color(0.16, 0.12, 0.06))
				draw_rect(turn_r, Color(0.6, 0.45, 0.15), false, 1.0)
				draw_string(font, Vector2(turn_r.position.x + 6, ey + 13), "TURN IN +%d cr" % bounty, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.75, 0.3))
				btn_rects.append({"id": "turn_in_%d" % pi, "rect": turn_r})
			ey += 22

	# Scrollbar indicator
	var content_h = ey - (list_y + 4 - scroll_supply)
	if content_h > list_h:
		var sb_x = px + panel_w - 8
		var sb_h = list_h
		var thumb_h = maxf(sb_h * list_h / content_h, 20.0)
		var thumb_y = clip_top + (scroll_supply / (content_h - list_h)) * (sb_h - thumb_h)
		draw_rect(Rect2(sb_x, clip_top, 4, sb_h), Color(0.1, 0.1, 0.12))
		draw_rect(Rect2(sb_x, thumb_y, 4, thumb_h), Color(0.3, 0.35, 0.45, 0.6))

	# Clamp scroll to valid range
	var max_scroll = maxf(content_h - list_h, 0)
	scroll_supply = clampf(scroll_supply, 0, max_scroll)

func _draw_supply_row(px: float, ey: float, panel_w: float, font: Font, btn_rects: Array,
		label: String, color: Color, current: float, capacity: float, pct: float,
		btn_label: String, price: int, is_full: bool, btn_id: String):
	# Label
	draw_string(font, Vector2(px + 16, ey + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	# Current / Max
	var val_text = "%d / %d" % [int(current), int(capacity)]
	draw_string(font, Vector2(px + 140, ey + 14), val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.68, 0.75))

	# Bar
	var bar_x = px + 16
	var bar_y = ey + 20
	var bar_w = panel_w - 130
	var bar_h = 14
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.06, 0.06, 0.08))
	var fill_w = bar_w * clampf(pct, 0, 1)
	if fill_w > 1:
		draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), color * 0.6)
		draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h * 0.4), Color(color, 0.3) * 1.3)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.25, 0.28, 0.35), false, 1.0)
	# Pct text
	draw_string(font, Vector2(bar_x + bar_w * 0.5 - 15, bar_y + 11), "%d%%" % int(pct * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.9))

	# Buy button
	var can_afford = GameManager.credits >= price and not is_full
	var buy_r = Rect2(px + panel_w - 100, ey + 4, 84, 30)
	if can_afford:
		draw_rect(buy_r, Color(0.1, 0.16, 0.12))
		draw_rect(buy_r, Color(0.3, 0.5, 0.3), false, 1.0)
		draw_string(font, Vector2(buy_r.position.x + 6, ey + 15), btn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.9, 0.5))
		draw_string(font, Vector2(buy_r.position.x + 6, ey + 28), str(price) + " cr", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.8, 0.3))
	else:
		draw_rect(buy_r, Color(0.06, 0.06, 0.06))
		var txt = "FULL" if is_full else btn_label
		draw_string(font, Vector2(buy_r.position.x + 6, ey + 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.3, 0.3))
	btn_rects.append({"id": btn_id, "rect": buy_r})

func _type_color(t: String) -> Color:
	match t:
		"weapon": return Color(0.9, 0.3, 0.25)
		"shield": return Color(0.3, 0.5, 1.0)
		"engine": return Color(1.0, 0.6, 0.2)
		"reactor": return Color(0.95, 0.82, 0.2)
		"armor": return Color(0.5, 0.55, 0.6)
		"sensor": return Color(0.25, 0.85, 0.45)
		"conduit": return Color(0.6, 0.5, 0.2)
		"hallway": return Color(0.45, 0.45, 0.5)
		"airlock": return Color(0.7, 0.5, 0.2)
		"structural": return Color(0.5, 0.5, 0.55)
		"cargo": return Color(0.6, 0.45, 0.3)
		"quarters": return Color(0.75, 0.55, 0.3)
		"mess": return Color(0.8, 0.5, 0.2)
		"medbay": return Color(0.3, 0.8, 0.4)
		"construction_hangar": return Color(0.55, 0.55, 0.6)
		"basic_workshop", "farmers_workshop": return Color(0.6, 0.5, 0.35)
		"solar_field": return Color(0.85, 0.75, 0.3)
		"life_support": return Color(0.3, 0.7, 0.7)
		"brig": return Color(0.45, 0.4, 0.4)
		"hangar": return Color(0.4, 0.5, 0.7)
		"hydroponics": return Color(0.3, 0.75, 0.3)
		"armory": return Color(0.8, 0.4, 0.15)
		"rec_room": return Color(0.6, 0.5, 0.8)
		"bridge": return Color(0.5, 0.6, 0.9)
		"fuel_scoop": return Color(0.9, 0.7, 0.2)
		"mining": return Color(0.7, 0.5, 0.3)
		"research_lab": return Color(0.3, 0.6, 0.9)
	return Color(0.4, 0.4, 0.4)

func _gui_input(event: InputEvent):
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_click(event.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				match view_mode:
					"buy": scroll_buy = maxf(scroll_buy - 30, 0)
					"sell": scroll_sell = maxf(scroll_sell - 30, 0)
					"craft": scroll_craft = maxf(scroll_craft - 30, 0)
					"supply": scroll_supply = maxf(scroll_supply - 30, 0)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				match view_mode:
					"buy": scroll_buy += 30
					"sell": scroll_sell += 30
					"craft": scroll_craft += 30
					"supply": scroll_supply += 30
				accept_event()
	if event is InputEventMouseMotion:
		gamepad_idx = -1  # Clear gamepad highlight when mouse moves
	if event is InputEventJoypadButton and event.pressed:
		var btn_rects: Array = get_meta("btn_rects", [])
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				if btn_rects.size() > 0:
					if gamepad_idx <= 0:
						gamepad_idx = btn_rects.size() - 1
					else:
						gamepad_idx -= 1
				accept_event()
			JOY_BUTTON_DPAD_DOWN:
				if btn_rects.size() > 0:
					if gamepad_idx < btn_rects.size() - 1:
						gamepad_idx += 1
					else:
						gamepad_idx = 0
				accept_event()
			JOY_BUTTON_A:
				if gamepad_idx >= 0 and gamepad_idx < btn_rects.size():
					_handle_button(btn_rects[gamepad_idx].id)
				accept_event()
			JOY_BUTTON_B:
				_close()
				accept_event()

func _handle_click(pos: Vector2):
	var btn_rects: Array = get_meta("btn_rects", [])
	for btn in btn_rects:
		if btn.rect.has_point(pos):
			_handle_button(btn.id)
			return

func _handle_button(btn_id: String):
	match btn_id:
		"tab_buy": view_mode = "buy"
		"tab_sell": view_mode = "sell"
		"tab_craft": view_mode = "craft"
		"tab_supply": view_mode = "supply"
		"close": _close()
		"sup_fuel":
			if GameManager.buy_fuel(FUEL_UNIT, FUEL_PRICE):
				_status("Refueled +%d" % int(FUEL_UNIT))
			else:
				_status("Can't afford fuel" if GameManager.credits < FUEL_PRICE else "Tank full")
		"sup_sell_all_res":
			var earned = GameManager.sell_all_resources()
			if earned > 0:
				_status("Sold all resources +%d cr" % earned)
			else:
				_status("No resources to sell")
		"sup_repair":
			var player = get_tree().get_first_node_in_group("player")
			if player:
				var dmg = player.max_health - player.health
				if dmg < 1.0:
					_status("Hull intact")
					return
				var cost = int(ceilf(dmg)) * REPAIR_PRICE
				if GameManager.credits >= cost:
					GameManager.credits -= cost
					player.health = player.max_health
					player.shields = player.max_shields
					if player.has_signal("health_changed"):
						player.health_changed.emit(player.health, player.max_health, player.shields, player.max_shields)
					_status("Hull repaired! -%d cr" % cost)
				else:
					_status("Can't afford repairs")
		_:
			if btn_id.begins_with("buy_"):
				var mod_id = btn_id.substr(4)
				if GameManager.buy_module(mod_id):
					var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
					_status("Bought " + mod_name)
				else:
					_status("Can't afford that")
			elif btn_id.begins_with("sell_res_"):
				var parts = btn_id.split("_", false)
				# sell_res_1_<type>, sell_res_5_<type>, sell_res_all_<type>
				if parts.size() >= 4:
					var qty_str = parts[2]
					var res_type = parts[3]
					var held = int(GameManager.resources.get(res_type, 0))
					if held <= 0:
						_status("No %s to sell" % res_type)
					else:
						var sell_amount: int
						if qty_str == "all":
							sell_amount = held
						else:
							sell_amount = mini(int(qty_str), held)
						if GameManager.sell_resource(res_type, sell_amount):
							var info = GameManager.RESOURCE_TYPES.get(res_type, {})
							var price_per = int(info.get("sell_price", 1))
							_status("Sold %d %s (+%d cr)" % [sell_amount, res_type, sell_amount * price_per])
						else:
							_status("Failed to sell")
			elif btn_id.begins_with("sell_"):
				var mod_id = btn_id.substr(5)
				if GameManager.sell_module(mod_id):
					var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
					_status("Sold " + mod_name)
				else:
					_status("Nothing to sell")
			elif btn_id.begins_with("craft_"):
				var mod_id = btn_id.substr(6)
				if GameManager.craft_module(mod_id):
					var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
					_status("Crafted " + mod_name)
				else:
					_status("Not enough resources")
			elif btn_id.begins_with("turn_in_"):
				var idx = int(btn_id.substr(8))
				if idx >= 0 and idx < GameManager.prisoners.size():
					var pris = GameManager.prisoners[idx]
					var pname = pris.get("name", "Unknown")
					var bounty = 50 + int(pris.get("skills", {}).get("combat", 3)) * 10
					GameManager.credits += bounty
					GameManager.prisoners.remove_at(idx)
					_status("Turned in %s (+%d cr)" % [pname, bounty])

func _status(text: String):
	status_text = text
	status_timer = 2.5

const STAT_LABELS: Dictionary = {
	"damage": "Damage", "fire_rate": "Fire Rate", "range": "Range",
	"projectile_speed": "Proj Speed", "shield_capacity": "Shields",
	"recharge_rate": "Shield Regen",
	"thrust": "Thrust", "power_output": "Power Output",
	"power_draw": "Power Draw", "hull_bonus": "Hull",
	"cargo_capacity": "Cargo", "crew_capacity": "Crew Cap",
	"crew_supported": "Life Support", "scan_range": "Scan Range",
	"scan_speed": "Scan Speed", "feed_capacity": "Feed Cap",
	"food_generation": "Food/sec", "damage_resist": "Dmg Resist",
	"scoop_rate": "Scoop Rate", "mining_rate": "Mining Rate",
	"mining_range": "Mining Range", "boarding_power": "Boarding",
	"heat_per_shot": "Heat/Shot", "heat_decay": "Heat Decay",
}

func _draw_shop_tooltip(font: Font, panel_x: float, _panel_y: float, panel_w: float, _panel_h: float):
	var mouse = get_local_mouse_position()
	var hovered_id: String = ""
	for item in hovered_item_rects:
		if item["rect"].has_point(mouse):
			hovered_id = item["mod_id"]
			break
	if hovered_id == "":
		return

	var mod_data = DataManager.modules.get(hovered_id, {})
	if mod_data.is_empty():
		return

	var stats: Dictionary = mod_data.get("stats", {})
	if stats.is_empty():
		return  # No stats to show

	# Build stat lines
	var lines: Array = []
	for sk in stats:
		var label = STAT_LABELS.get(sk, sk.capitalize())
		var val = stats[sk]
		var val_str = str(val)
		if val is float:
			val_str = "%.1f" % val
		if float(val) > 0:
			val_str = "+" + val_str
		var scol = Color(0.5, 0.8, 0.5) if float(val) > 0 else Color(0.8, 0.4, 0.3)
		lines.append({"text": "%s: %s" % [label, val_str], "color": scol})

	if lines.is_empty():
		return

	var padding = Vector2(10, 6)
	var line_h = 15.0
	var max_w: float = 140.0
	for ln in lines:
		var tw = font.get_string_size(ln["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + padding.x * 2
		max_w = maxf(max_w, tw)
	var total_h = padding.y * 2 + lines.size() * line_h

	# Position to right of panel
	var tx = panel_x + panel_w + 8
	var ty = mouse.y - total_h * 0.5
	if tx + max_w > size.x - 10:
		tx = panel_x - max_w - 8
	ty = clampf(ty, 10, size.y - total_h - 10)

	draw_rect(Rect2(tx, ty, max_w, total_h), Color(0.03, 0.04, 0.07, 0.95))
	draw_rect(Rect2(tx, ty, max_w, total_h), Color(0.3, 0.35, 0.5, 0.7), false, 1.0)

	var ly = ty + padding.y + 11
	for ln in lines:
		draw_string(font, Vector2(tx + padding.x, ly), ln["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ln["color"])
		ly += line_h

