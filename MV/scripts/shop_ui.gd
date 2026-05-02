extends CanvasLayer

# Item buy/sell overlay. Opens via the "start_shop" trigger action.
# Reads shop inventory from a shops.json entry or entity properties.
# Uses PlayerInventory game_vars["gold"] as currency.


const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo := preload("res://Space/scripts/editor/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")

var _panel: Control = null
var _item_container: VBoxContainer = null
var _gold_label: Label = null
var _close_btn: Button = null
var _active: bool = false
var _shop_items: Array = []
var _shop_id: String = ""
var _authored_screen: Control = null
var _authored_pack_id: String = ""
var _last_message: String = ""
static var _singleton = null


static func instance():
	return _singleton

func _ready() -> void:
	_singleton = self
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_build_ui()
	visible = false
	_authored_screen = Control.new()
	_authored_screen.set_script(AuthoredScreenRuntime)
	_authored_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	_authored_screen.visible = false
	add_child(_authored_screen)
	_authored_screen.action_requested.connect(_on_authored_action)


func open_shop(shop_id: String) -> void:
	_shop_id = shop_id
	_last_message = ""
	_shop_items = _load_shop(shop_id)
	_normalize_shop_items()
	if _shop_items.is_empty():
		return
	_active = true
	visible = true
	MvGame.simulation_paused = true
	_refresh_authored_screen()
	_refresh()


func close_shop() -> void:
	_active = false
	visible = false
	MvGame.simulation_paused = false
	_shop_id = ""
	_last_message = ""
	_clear_items()


func _refresh() -> void:
	_clear_items()
	var gold := int(PlayerInventory.get_var("gold", 0))
	_gold_label.text = "Gold: %d%s" % [gold, ("  -  %s" % _last_message) if not _last_message.is_empty() else ""]

	for i in _shop_items.size():
		var item: Dictionary = _shop_items[i]
		var item_id: String = str(item.get("id", ""))
		var price: int = int(item.get("price", 0))
		var item_name: String = str(item.get("name", item_id))
		var count: int = int(item.get("count", 1))
		var can_afford := gold >= price

		var row := HBoxContainer.new()
		var lbl := Label.new()
		var count_suffix := (" x%d" % count) if count > 1 else ""
		lbl.text = "%s%s - %d gold" % [item_name, count_suffix, price]
		lbl.tooltip_text = _item_tooltip(item, can_afford)
		lbl.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
		lbl.add_theme_color_override("font_color", UIPanels.text_color("success") if can_afford else UIPanels.text_color("dim"))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.disabled = not can_afford
		buy_btn.tooltip_text = _item_tooltip(item, can_afford)
		buy_btn.pressed.connect(_on_buy.bind(i))
		row.add_child(buy_btn)
		_item_container.add_child(row)


func _on_buy(index: int) -> void:
	if index < 0 or index >= _shop_items.size():
		return
	var item: Dictionary = _shop_items[index]
	var price: int = int(item.get("price", 0))
	var gold := int(PlayerInventory.get_var("gold", 0))
	if gold < price:
		_last_message = "Need %d more gold for %s." % [price - gold, str(item.get("name", item.get("id", "")))]
		_refresh()
		return
	PlayerInventory.add_var("gold", -price)
	var item_id := str(item.get("id", ""))
	var count := maxi(1, int(item.get("count", 1)))
	var applied_shop_effect := false
	if str(item.get("use_effect", "")).strip_edges() != "" and bool(item.get("auto_use_on_gain", true)):
		var def := PlayerInventory.get_item_definition(item_id)
		def["id"] = item_id
		def["stock_id"] = str(item.get("stock_id", ""))
		def["use_effect"] = str(item.get("use_effect", ""))
		def["use_amount"] = int(item.get("use_amount", 0))
		def["use_arg"] = str(item.get("use_arg", ""))
		applied_shop_effect = PlayerInventory.apply_item_effect_definition(def, count)
	if not applied_shop_effect:
		PlayerInventory.add_item(item_id, count)
	MvTriggerEngine.fire_event("item_gain", {
		"item_id": item_id,
		"stock_id": str(item.get("stock_id", "")),
		"shop_id": _shop_id,
		"count": count,
	})
	_last_message = "Bought %s." % str(item.get("name", item_id))
	_consume_stock(index)
	_refresh()
	if _authored_screen != null:
		_authored_screen.queue_redraw()


func _clear_items() -> void:
	if _item_container == null:
		return
	for child in _item_container.get_children():
		child.queue_free()


func _load_shop(shop_id: String) -> Array:
	var path := MvPackLoader.resolve_read_cascade(
		_current_pack_id(), "Shops", shop_id + ".json")
	var raw := MvPackLoader.read_json_dict(path)
	var items_v: Variant = raw.get("items", [])
	return items_v if typeof(items_v) == TYPE_ARRAY else []


func _normalize_shop_items() -> void:
	var used: Dictionary = {}
	for i in range(_shop_items.size()):
		if typeof(_shop_items[i]) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = _shop_items[i]
		var stock_id := str(item.get("stock_id", "")).strip_edges()
		if stock_id.is_empty():
			stock_id = _sanitize_stock_id(str(item.get("id", "stock_item")))
		var base := stock_id
		var suffix := 1
		while used.has(stock_id):
			stock_id = "%s_%d" % [base, suffix]
			suffix += 1
		item["stock_id"] = stock_id
		used[stock_id] = true


func _sanitize_stock_id(value: String) -> String:
	var out := value.strip_edges().to_lower().replace(" ", "_")
	return out if not out.is_empty() else "stock_item"


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func current_items() -> Array:
	var out: Array = []
	for item_v in _shop_items:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = (item_v as Dictionary).duplicate(true)
		var item_id := str(item.get("id", ""))
		var def := PlayerInventory.get_item_definition(item_id)
		if not def.is_empty():
			if not item.has("description") or str(item.get("description", "")).strip_edges().is_empty():
				item["description"] = str(def.get("description", ""))
			if not item.has("name") or str(item.get("name", "")).strip_edges().is_empty():
				item["name"] = str(def.get("name", item_id))
		out.append(item)
	return out


func status_message() -> String:
	return _last_message


func _consume_stock(index: int) -> void:
	if index < 0 or index >= _shop_items.size():
		return
	var item: Dictionary = _shop_items[index]
	var count := maxi(1, int(item.get("count", 1)))
	if count > 1:
		item["count"] = count - 1
		_shop_items[index] = item
	else:
		_shop_items.remove_at(index)


func _item_tooltip(item: Dictionary, can_afford: bool) -> String:
	var item_id := str(item.get("id", ""))
	var item_name := str(item.get("name", item_id))
	var price := int(item.get("price", 0))
	var desc := str(PlayerInventory.get_item_definition(item_id).get("description", "")).strip_edges()
	var lines: Array = [item_name, "%d gold" % price]
	if not desc.is_empty():
		lines.append(desc)
	if can_afford:
		lines.append("Click Buy to purchase.")
	else:
		var gold := int(PlayerInventory.get_var("gold", 0))
		lines.append("Need %d more gold." % maxi(price - gold, 0))
	return "\n".join(lines)


func _build_ui() -> void:
	_panel = Control.new()
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	_panel.draw.connect(_draw_bg)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 12
	vbox.offset_bottom = -12
	_panel.add_child(vbox)

	var header := Label.new()
	header.text = "SHOP"
	header.add_theme_font_size_override("font_size", UIPanels.font_size("title_size"))
	header.add_theme_color_override("font_color", UIPanels.text_color("title"))
	vbox.add_child(header)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", UIPanels.font_size("body_size"))
	_gold_label.add_theme_color_override("font_color", UIPanels.text_color("title"))
	vbox.add_child(_gold_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_item_container = VBoxContainer.new()
	_item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_container)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(close_shop)
	vbox.add_child(_close_btn)

	add_child(_panel)


func _draw_bg() -> void:
	if _has_authored_screen():
		UIPanels.draw_panel(_panel, Rect2(Vector2.ZERO, _panel.size))
		return
	UIPanels.draw_panel(_panel, Rect2(Vector2.ZERO, _panel.size))


func _buy_item_by_id(item_id: String) -> bool:
	for i in range(_shop_items.size()):
		var item: Dictionary = _shop_items[i]
		if str(item.get("stock_id", "")) == item_id or str(item.get("id", "")) == item_id:
			_on_buy(i)
			return true
	return false


func _has_authored_screen() -> bool:
	return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
	if _authored_screen == null:
		return
	var pack_id := _current_pack_id()
	if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "shop"):
		_authored_pack_id = ""
		_authored_screen.call("clear_screen")
		_panel.visible = true
		return
	if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
		_authored_pack_id = pack_id
		var data: Dictionary = UIIo.load_screen(pack_id, "shop")
		_authored_screen.call("load_screen", "shop", data, HudDataSource.new(null, null))
	_authored_screen.visible = true
	_panel.visible = false


func _on_authored_action(action_id: String, action_args: String, _element_id: String) -> void:
	_emit_ui_button_event(action_id, action_args, _element_id)
	match action_id:
		"close_screen", "resume":
			close_shop()
		"open_screen":
			_open_authored_screen(action_args)
		"fire_event":
			UiHostActions.fire_authored_event("shop", "shop_ui", action_args, _element_id, {
				"shop_id": _shop_id,
			})
		"buy_item":
			if action_args.is_empty():
				push_warning("MvShopUI: buy_item authored action requires action_args = offer id or item id")
				return
			if not _buy_item_by_id(action_args):
				push_warning("MvShopUI: shop '%s' has no offer or item '%s'" % [_shop_id, action_args])
		"sell_item":
			_sell_item_from_action(action_args)
		"play_sfx":
			UiHostActions.play_authored_sfx(action_args)
		_:
			UiHostActions.warn_unhandled_action("shop_ui", action_id)


func _open_authored_screen(target: String) -> void:
	match target:
		"", "shop":
			return
		"boss_intro", "cinematic":
			UiHostActions.open_cinematic(_current_pack_id(), "shop_ui", target)
		"inventory":
			close_shop()
			MvInventoryScreen.open()
		"map":
			close_shop()
			MvMapScreen.open()
		_:
			push_warning("MvShopUI: open_screen target '%s' is not supported here" % target)


func _sell_item_from_action(action_args: String) -> void:
	if action_args.is_empty():
		push_warning("MvShopUI: sell_item expects action_args 'item_id[:price]'")
		return
	var parts := action_args.split(":", false, 1)
	var item_id := str(parts[0]).strip_edges()
	var explicit_price := int(parts[1]) if parts.size() > 1 and str(parts[1]).is_valid_int() else -1
	if item_id.is_empty():
		push_warning("MvShopUI: sell_item needs an item_id")
		return
	if not PlayerInventory.has_item(item_id):
		push_warning("MvShopUI: player does not have '%s' to sell" % item_id)
		return
	var price := explicit_price
	if price < 0:
		for item_v in _shop_items:
			if typeof(item_v) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = item_v
			if str(item.get("id", "")) == item_id:
				price = maxi(int(round(float(item.get("price", 0)) * 0.5)), 0)
				break
	if price < 0:
		price = 0
	PlayerInventory.remove_item(item_id, 1)
	PlayerInventory.add_var("gold", price)
	MvTriggerEngine.fire_event("item_sell", { "item_id": item_id, "price": price })
	_refresh()


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
	UiHostActions.emit_ui_button_event("shop", "shop_ui", action_id, action_args, element_id, {
		"shop_id": _shop_id,
	})
