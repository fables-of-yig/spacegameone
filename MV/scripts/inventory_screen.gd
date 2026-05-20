extends CanvasLayer

# Full-screen pause overlay. Shows collected items, equipment slots, and
# ability descriptions. Opens on the menu button and pauses the game.

const MARGIN: int = 24
const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")

var _panel: Control = null
var _item_list: VBoxContainer = null
var _ability_list: VBoxContainer = null
var _equip_list: VBoxContainer = null
var _active: bool = false
var _authored_screen: Control = null
var _authored_pack_id: String = ""

static var _singleton = null


static func instance():
	return _singleton


func _ready() -> void:
	_singleton = self
	layer = 95
	_build_ui()
	visible = false
	_authored_screen = Control.new()
	_authored_screen.set_script(AuthoredScreenRuntime)
	_authored_screen.visible = false
	add_child(_authored_screen)
	_authored_screen.action_requested.connect(_on_authored_action)


func _process(_delta: float) -> void:
	if not _mv_runtime_available():
		if _active:
			close()
		return
	if MvDialogueRunner != null and MvDialogueRunner.has_method("is_active") and MvDialogueRunner.is_active():
		return
	if Input.is_action_just_pressed("ui_cancel"):
		if _active:
			close()
		else:
			open()


func open() -> void:
	if not _mv_runtime_available():
		return
	if _active:
		return
	_active = true
	visible = true
	MvGame.simulation_paused = true
	_refresh_authored_screen()
	_refresh()


func close() -> void:
	_active = false
	visible = false
	MvGame.simulation_paused = false


func _refresh() -> void:
	_clear_children(_item_list)
	_clear_children(_ability_list)
	_clear_children(_equip_list)

	_add_header(_item_list, "Items")
	var snap := PlayerInventory.snapshot()
	var items: Dictionary = snap.get("items", {})
	if items.is_empty():
		_add_line(_item_list, "(none)", UIPanels.text_color("body"))
	else:
		for item_id in items:
			_add_line(_item_list, "%s  x%d" % [item_id, items[item_id]], UIPanels.text_color("body"))

	_add_header(_ability_list, "Abilities")
	var abilities: Dictionary = snap.get("abilities", {})
	if abilities.is_empty():
		_add_line(_ability_list, "(none)", UIPanels.text_color("success"))
	else:
		for ability_id in abilities:
			_add_line(_ability_list, ability_id, UIPanels.text_color("success"))

	_add_header(_equip_list, "Equipment")
	var equip: Dictionary = snap.get("equipment", {})
	if equip.is_empty():
		_add_line(_equip_list, "(none)", UIPanels.text_color("body"))
	else:
		for slot in equip:
			var item_id: String = equip[slot]
			_add_line(_equip_list, "%s: %s" % [slot, item_id if not item_id.is_empty() else "(empty)"], UIPanels.text_color("body"))


func _build_ui() -> void:
	_panel = Control.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_bottom = -MARGIN
	_panel.draw.connect(_draw_bg)

	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 16
	hbox.offset_right = -16
	hbox.offset_top = 12
	hbox.offset_bottom = -12
	hbox.add_theme_constant_override("separation", 24)
	_panel.add_child(hbox)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_item_list)

	_equip_list = VBoxContainer.new()
	_equip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_equip_list)

	_ability_list = VBoxContainer.new()
	_ability_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_ability_list)

	add_child(_panel)


func _draw_bg() -> void:
	if _has_authored_screen():
		UIPanels.draw_dim(_panel, Rect2(Vector2.ZERO, _panel.size))
		return
	UIPanels.draw_panel(_panel, Rect2(Vector2.ZERO, _panel.size))


func _add_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIPanels.font_size("title_size"))
	lbl.add_theme_color_override("font_color", UIPanels.text_color("title"))
	parent.add_child(lbl)


func _add_line(parent: VBoxContainer, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)


func _clear_children(container: VBoxContainer) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func _has_authored_screen() -> bool:
	return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
	if _authored_screen == null:
		return
	var pack_id := _current_pack_id()
	if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "inventory"):
		_authored_pack_id = ""
		_authored_screen.call("clear_screen")
		_panel.visible = true
		return
	if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
		_authored_pack_id = pack_id
		var data: Dictionary = UIIo.load_screen(pack_id, "inventory")
		_authored_screen.call("load_screen", "inventory", data, HudDataSource.new(null, null))
	_authored_screen.visible = true
	_panel.visible = false


func _on_authored_action(action_id: String, action_args: String, _element_id: String) -> void:
	_emit_ui_button_event(action_id, action_args, _element_id)
	match action_id:
		"close_screen", "resume":
			close()
		"open_screen":
			_open_authored_screen(action_args)
		"fire_event":
			UiHostActions.fire_authored_event("inventory", "inventory_screen", action_args, _element_id)
		"equip_item":
			_equip_from_action(action_args)
		"unequip":
			if not action_args.is_empty():
				PlayerInventory.unequip(action_args)
				_refresh()
		"use_item":
			_use_item_from_action(action_args)
		"play_sfx":
			UiHostActions.play_authored_sfx(action_args)
		_:
			UiHostActions.warn_unhandled_action("inventory_screen", action_id)


func _open_authored_screen(target: String) -> void:
	match target:
		"", "inventory":
			return
		"boss_intro", "cinematic":
			UiHostActions.open_cinematic(_current_pack_id(), "inventory_screen", target)
		"map":
			close()
			MvMapScreen.open()
		_:
			push_warning("MvInventoryScreen: open_screen target '%s' is not supported here" % target)


func _equip_from_action(action_args: String) -> void:
	var item_id := action_args.strip_edges()
	if item_id.is_empty():
		push_warning("MvInventoryScreen: equip_item expects action_args 'item_id'")
		return
	if not PlayerInventory.equip_item_by_id(item_id):
		push_warning("MvInventoryScreen: equipment '%s' was not found in the current pack" % item_id)
	_refresh()


func _use_item_from_action(action_args: String) -> void:
	if action_args.is_empty():
		push_warning("MvInventoryScreen: use_item expects action_args 'item_id[:count]'")
		return
	var parts := action_args.split(":", false, 1)
	var item_id := str(parts[0]).strip_edges()
	var count := int(parts[1]) if parts.size() > 1 and str(parts[1]).is_valid_int() else 1
	if item_id.is_empty():
		push_warning("MvInventoryScreen: use_item needs an item_id")
		return
	if not PlayerInventory.has_item(item_id, count):
		push_warning("MvInventoryScreen: player does not have %d x '%s'" % [count, item_id])
		return
	if not PlayerInventory.use_item_definition(item_id, count):
		push_warning("MvInventoryScreen: item '%s' has no runtime use effect" % item_id)
		return
	MvTriggerEngine.fire_event("item_use", { "item_id": item_id, "count": count })
	_refresh()


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
	UiHostActions.emit_ui_button_event("inventory", "inventory_screen", action_id, action_args, element_id)


func _mv_runtime_available() -> bool:
	return PlanetaryInterface.hosted or MvGame.main != null
