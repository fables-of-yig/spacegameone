extends Control

signal submitted(data: Dictionary)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EntIO = preload("res://Space/scripts/editor/ent/ent_io.gd")
const BehIO = preload("res://Space/scripts/editor/beh/beh_io.gd")

const BOX_W: float = 860.0
const BOX_H: float = 468.0
const ROW_H: float = 36.0
const LABEL_X: float = 24.0
const FIELD_X: float = 208.0
const FIELD_W: float = 320.0

var _pack_id: String = ""
var _entity_type: String = ""
var _placement_kind: String = ""
var _entity_pos: Vector2 = Vector2.ZERO
var _entity_defs: Array = []
var _behavior_defs: Array = []

var _instance_edit: LineEdit = null
var _entity_picker: OptionButton = null
var _behavior_picker: OptionButton = null
var _dialogue_edit: LineEdit = null
var _item_id_edit: LineEdit = null
var _count_edit: LineEdit = null
var _zone_id_edit: LineEdit = null
var _width_edit: LineEdit = null
var _height_edit: LineEdit = null
var _event_edit: LineEdit = null
var _spawn_facing_picker: OptionButton = null
var _once_check: CheckBox = null
var _error_text: String = ""
var _preview_texture: Texture2D = null
var _preview_label: String = ""
var _preview_filename: String = ""

var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_process(true)

	_instance_edit = _make_line_edit("instance id")
	_entity_picker = OptionButton.new()
	_entity_picker.item_selected.connect(_on_entity_picker_selected)
	_behavior_picker = OptionButton.new()
	_dialogue_edit = _make_line_edit("dialogue id")
	_item_id_edit = _make_line_edit("item id")
	_count_edit = _make_line_edit("count")
	_zone_id_edit = _make_line_edit("zone id")
	_width_edit = _make_line_edit("width")
	_height_edit = _make_line_edit("height")
	_event_edit = _make_line_edit("event name")
	_spawn_facing_picker = OptionButton.new()
	_spawn_facing_picker.add_item("Right")
	_spawn_facing_picker.set_item_metadata(0, "right")
	_spawn_facing_picker.add_item("Left")
	_spawn_facing_picker.set_item_metadata(1, "left")
	_once_check = CheckBox.new()
	_once_check.text = "Trigger once"

	for node in [
		_instance_edit,
		_entity_picker,
		_behavior_picker,
		_dialogue_edit,
		_item_id_edit,
		_count_edit,
		_zone_id_edit,
		_width_edit,
		_height_edit,
		_event_edit,
		_spawn_facing_picker,
		_once_check,
	]:
		node.visible = false
		add_child(node)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_fields()


func _make_line_edit(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	return le


func open(pack_id: String, entity_type: String, entity_x: float, entity_y: float, properties: Dictionary) -> void:
	_pack_id = pack_id
	_entity_type = entity_type
	_entity_pos = Vector2(entity_x, entity_y)
	_entity_defs = _load_entity_defs()
	_behavior_defs = _load_behavior_defs()
	_placement_kind = _resolve_placement_kind(entity_type)
	_error_text = ""

	_populate_entity_picker()
	_populate_behavior_picker()

	_instance_edit.text = str(properties.get("instance_id", ""))
	_zone_id_edit.text = str(properties.get("zone_id", ""))
	_width_edit.text = str(int(properties.get("width", 16)))
	_height_edit.text = str(int(properties.get("height", 16)))
	_event_edit.text = str(properties.get("event_name", "zone_enter"))
	_once_check.button_pressed = bool(properties.get("once", false))
	_dialogue_edit.text = str(properties.get("dialogue_id", ""))
	_item_id_edit.text = str(properties.get("item_id", ""))
	_count_edit.text = str(int(properties.get("count", 1)))
	_select_spawn_facing_value(str(properties.get("facing", "right")))

	_select_entity_picker_value(entity_type)
	var behavior_id := str(properties.get("behavior", "")).strip_edges()
	if behavior_id.is_empty():
		behavior_id = _selected_entity_default_behavior()
	_select_behavior_picker_value(behavior_id)
	_refresh_entity_preview()

	visible = true
	_apply_visibility()
	_layout_fields()
	_focus_default_field()


func close() -> void:
	visible = false


func _focus_default_field() -> void:
	if _supports_authored_entity_picker() and _entity_picker.visible:
		_entity_picker.grab_focus.call_deferred()
		return
	if _instance_edit != null:
		_instance_edit.grab_focus.call_deferred()
		_instance_edit.select_all.call_deferred()


func _load_entity_defs() -> Array:
	var data: Dictionary = EntIO.load_or_init(_pack_id)
	var arr_v: Variant = data.get("entities", [])
	if typeof(arr_v) == TYPE_ARRAY:
		return arr_v
	return []


func _load_behavior_defs() -> Array:
	var data: Dictionary = BehIO.load_or_init(_pack_id)
	var arr_v: Variant = data.get("behaviors", [])
	if typeof(arr_v) == TYPE_ARRAY:
		return arr_v
	return []


func _resolve_placement_kind(entity_type: String) -> String:
	var trimmed := entity_type.strip_edges()
	if trimmed == "player_spawn" or trimmed == "trigger_volume":
		return trimmed
	if trimmed == "npc" or trimmed == "sign":
		return trimmed
	if trimmed == "pickup":
		return "pickup"
	if trimmed == "enemy" or trimmed == "patroller":
		return trimmed
	for entity_v in _entity_defs:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if str(entity.get("id", "")).strip_edges() != trimmed:
			continue
		var category := str(entity.get("category", "")).strip_edges().to_lower()
		if category == "interactable":
			return "npc"
		if category == "pickup":
			return "pickup"
		if category == "enemy" or category == "boss":
			return "enemy"
		if category == "logic":
			return "trigger_volume"
	return trimmed


func _supports_authored_entity_picker() -> bool:
	return _placement_kind == "npc" or _placement_kind == "sign" \
		or _placement_kind == "pickup" or _placement_kind == "enemy" \
		or _placement_kind == "patroller"


func _is_zone() -> bool:
	return _placement_kind == "trigger_volume"


func _is_player_spawn() -> bool:
	return _placement_kind == "player_spawn"


func _is_enemy_like() -> bool:
	return _placement_kind == "enemy" or _placement_kind == "patroller"


func _is_interactable_like() -> bool:
	return _placement_kind == "npc" or _placement_kind == "sign"


func _is_pickup_like() -> bool:
	return _placement_kind == "pickup"


func _picker_entity_ids() -> Array:
	var out: Array = []
	for entity_v in _entity_defs:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		var category := str(entity.get("category", "")).strip_edges().to_lower()
		if _is_interactable_like() and category != "interactable":
			continue
		if _is_pickup_like() and category != "pickup":
			continue
		if _is_enemy_like() and category != "enemy" and category != "boss":
			continue
		out.append(entity)
	out.sort_custom(Callable(self, "_sort_entity_picker_rows"))
	return out


func _sort_entity_picker_rows(a: Dictionary, b: Dictionary) -> bool:
	var folder_a := str(a.get("placement_folder", "")).strip_edges().to_lower()
	var folder_b := str(b.get("placement_folder", "")).strip_edges().to_lower()
	if folder_a != folder_b:
		return folder_a < folder_b
	var name_a := str(a.get("name", a.get("id", ""))).strip_edges().to_lower()
	var name_b := str(b.get("name", b.get("id", ""))).strip_edges().to_lower()
	if name_a != name_b:
		return name_a < name_b
	return str(a.get("id", "")).strip_edges().to_lower() < str(b.get("id", "")).strip_edges().to_lower()


func _populate_entity_picker() -> void:
	_entity_picker.clear()
	if not _supports_authored_entity_picker():
		return
	var candidates := _picker_entity_ids()
	for entity_v in candidates:
		var entity: Dictionary = entity_v
		var entity_id := str(entity.get("id", "")).strip_edges()
		if entity_id.is_empty():
			continue
		var label := entity_id
		var display_name := str(entity.get("name", "")).strip_edges()
		if not display_name.is_empty() and display_name != entity_id:
			label = "%s  (%s)" % [display_name, entity_id]
		var folder := str(entity.get("placement_folder", "")).strip_edges()
		if not folder.is_empty():
			label = "%s / %s" % [folder, label]
		_entity_picker.add_item(label)
		_entity_picker.set_item_metadata(_entity_picker.item_count - 1, entity_id)


func _populate_behavior_picker() -> void:
	_behavior_picker.clear()
	_behavior_picker.add_item("(Entity Default)")
	_behavior_picker.set_item_metadata(0, "")
	for behavior_v in _behavior_defs:
		if typeof(behavior_v) != TYPE_DICTIONARY:
			continue
		var behavior: Dictionary = behavior_v
		var behavior_id := str(behavior.get("id", "")).strip_edges()
		if behavior_id.is_empty():
			continue
		var label := behavior_id
		var display_name := str(behavior.get("name", "")).strip_edges()
		if not display_name.is_empty() and display_name != behavior_id:
			label = "%s  (%s)" % [display_name, behavior_id]
		_behavior_picker.add_item(label)
		_behavior_picker.set_item_metadata(_behavior_picker.item_count - 1, behavior_id)


func _select_entity_picker_value(type_id: String) -> void:
	if not _supports_authored_entity_picker():
		return
	var trimmed := type_id.strip_edges()
	for i in _entity_picker.item_count:
		if str(_entity_picker.get_item_metadata(i)).strip_edges() == trimmed:
			_entity_picker.select(i)
			return
	if _entity_picker.item_count > 0:
		_entity_picker.select(0)


func _select_behavior_picker_value(behavior_id: String) -> void:
	var trimmed := behavior_id.strip_edges()
	for i in _behavior_picker.item_count:
		if str(_behavior_picker.get_item_metadata(i)).strip_edges() == trimmed:
			_behavior_picker.select(i)
			return
	_behavior_picker.select(0)


func _selected_entity_id() -> String:
	if not _supports_authored_entity_picker() or _entity_picker.item_count <= 0:
		return _entity_type
	var idx := _entity_picker.selected
	if idx < 0 or idx >= _entity_picker.item_count:
		return ""
	return str(_entity_picker.get_item_metadata(idx)).strip_edges()


func _selected_entity_default_behavior() -> String:
	var entity_id := _selected_entity_id()
	if entity_id.is_empty():
		return ""
	for entity_v in _entity_defs:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if str(entity.get("id", "")).strip_edges() == entity_id:
			return str(entity.get("behavior", "")).strip_edges()
	return ""


func _selected_behavior_override() -> String:
	var idx := _behavior_picker.selected
	if idx < 0 or idx >= _behavior_picker.item_count:
		return ""
	return str(_behavior_picker.get_item_metadata(idx)).strip_edges()


func _select_spawn_facing_value(facing: String) -> void:
	var trimmed: String = facing.strip_edges().to_lower()
	for i in _spawn_facing_picker.item_count:
		if str(_spawn_facing_picker.get_item_metadata(i)).strip_edges() == trimmed:
			_spawn_facing_picker.select(i)
			return
	_spawn_facing_picker.select(0)


func _selected_spawn_facing() -> String:
	var idx: int = _spawn_facing_picker.selected
	if idx < 0 or idx >= _spawn_facing_picker.item_count:
		return "right"
	return str(_spawn_facing_picker.get_item_metadata(idx)).strip_edges()


func _selected_entity_def() -> Dictionary:
	var entity_id := _selected_entity_id()
	if entity_id.is_empty():
		return {}
	for entity_v in _entity_defs:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if str(entity.get("id", "")).strip_edges() == entity_id:
			return entity
	return {}


func _refresh_entity_preview() -> void:
	_preview_texture = null
	_preview_label = ""
	_preview_filename = ""
	if not _supports_authored_entity_picker():
		return
	var entity := _selected_entity_def()
	if entity.is_empty():
		return
	_preview_label = str(entity.get("name", _selected_entity_id())).strip_edges()
	if _preview_label.is_empty():
		_preview_label = _selected_entity_id()
	var sprite_set_rel := str(entity.get("sprite_set", "")).strip_edges()
	if sprite_set_rel.is_empty():
		return
	var pngs := EntIO.list_sprite_pngs(_pack_id, sprite_set_rel)
	if pngs.is_empty():
		return
	var chosen := _pick_preview_png(pngs)
	_preview_filename = chosen
	_preview_texture = EntIO.load_sprite_png(_pack_id, sprite_set_rel, chosen)


func _pick_preview_png(pngs: Array) -> String:
	if pngs.is_empty():
		return ""
	for name_v in pngs:
		var name := str(name_v).to_lower()
		if name.contains("idle"):
			return str(name_v)
	for name_v in pngs:
		var name := str(name_v).to_lower()
		if name.contains("walk"):
			return str(name_v)
	for name_v in pngs:
		var name := str(name_v).to_lower()
		if name.contains("default"):
			return str(name_v)
	return str(pngs[0])


func _apply_visibility() -> void:
	var show_zone := _is_zone()
	var show_picker := _supports_authored_entity_picker()
	_instance_edit.visible = true
	_entity_picker.visible = show_picker
	_behavior_picker.visible = _is_enemy_like()
	_dialogue_edit.visible = _is_interactable_like()
	_item_id_edit.visible = _is_pickup_like()
	_count_edit.visible = _is_pickup_like()
	_zone_id_edit.visible = show_zone
	_width_edit.visible = show_zone
	_height_edit.visible = show_zone
	_event_edit.visible = show_zone
	_spawn_facing_picker.visible = _is_player_spawn()
	_once_check.visible = show_zone


func _layout_fields() -> void:
	if _instance_edit == null:
		return
	var box := _box_rect()
	var field_x := box.position.x + FIELD_X
	var field_w := FIELD_W
	var y := box.position.y + 92.0

	_instance_edit.position = Vector2(field_x, y)
	_instance_edit.size = Vector2(field_w, 28.0)
	y += ROW_H

	if _supports_authored_entity_picker():
		_entity_picker.position = Vector2(field_x, y)
		_entity_picker.size = Vector2(field_w, 28.0)
		y += ROW_H
	if _is_enemy_like():
		_behavior_picker.position = Vector2(field_x, y)
		_behavior_picker.size = Vector2(field_w, 28.0)
		y += ROW_H
	if _is_interactable_like():
		_dialogue_edit.position = Vector2(field_x, y)
		_dialogue_edit.size = Vector2(field_w, 28.0)
		y += ROW_H
	if _is_pickup_like():
		_item_id_edit.position = Vector2(field_x, y)
		_item_id_edit.size = Vector2(field_w, 28.0)
		y += ROW_H
		_count_edit.position = Vector2(field_x, y)
		_count_edit.size = Vector2(120.0, 28.0)
		y += ROW_H
	if _is_zone():
		_zone_id_edit.position = Vector2(field_x, y)
		_zone_id_edit.size = Vector2(field_w, 28.0)
		y += ROW_H
		_width_edit.position = Vector2(field_x, y)
		_width_edit.size = Vector2(96.0, 28.0)
		_height_edit.position = Vector2(field_x + 112.0, y)
		_height_edit.size = Vector2(96.0, 28.0)
		y += ROW_H
		_event_edit.position = Vector2(field_x, y)
		_event_edit.size = Vector2(field_w, 28.0)
		y += ROW_H
		_once_check.position = Vector2(field_x, y - 4.0)
		_once_check.size = Vector2(field_w, 28.0)
	if _is_player_spawn():
		_spawn_facing_picker.position = Vector2(field_x, y)
		_spawn_facing_picker.size = Vector2(140.0, 28.0)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _ok_rect.has_point(mb.position):
				_confirm()
				accept_event()
				return
			if _cancel_rect.has_point(mb.position):
				_cancel()
				accept_event()
				return
			if not _box_rect().has_point(mb.position):
				_cancel()
				accept_event()
				return


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	var out: Dictionary = {}
	var clear_keys: Array = []
	var instance_id := _instance_edit.text.strip_edges()
	if _entity_type != "player_spawn" and instance_id.is_empty():
		_error_text = "Instance id is required."
		queue_redraw()
		return
	if not instance_id.is_empty():
		out["instance_id"] = instance_id

	if _supports_authored_entity_picker():
		var type_id := _selected_entity_id()
		if type_id.is_empty():
			_error_text = "Pick an authored entity definition."
			queue_redraw()
			return
		out["type_id"] = type_id

	if _is_enemy_like():
		var behavior_id := _selected_behavior_override()
		if behavior_id.is_empty():
			clear_keys.append("behavior")
		else:
			out["behavior"] = behavior_id

	if _is_interactable_like():
		var dialogue_id := _dialogue_edit.text.strip_edges()
		if dialogue_id.is_empty():
			clear_keys.append("dialogue_id")
		else:
			out["dialogue_id"] = dialogue_id

	if _is_pickup_like():
		var item_id := _item_id_edit.text.strip_edges()
		if item_id.is_empty():
			clear_keys.append("item_id")
			clear_keys.append("count")
		else:
			out["item_id"] = item_id
			if not _count_edit.text.strip_edges().is_valid_int() or int(_count_edit.text) < 1:
				_error_text = "Pickup count must be a positive whole number."
				queue_redraw()
				return
			out["count"] = int(_count_edit.text)

	if _is_zone():
		if not _width_edit.text.strip_edges().is_valid_int() or int(_width_edit.text) < 1:
			_error_text = "Zone width must be a positive whole number."
			queue_redraw()
			return
		if not _height_edit.text.strip_edges().is_valid_int() or int(_height_edit.text) < 1:
			_error_text = "Zone height must be a positive whole number."
			queue_redraw()
			return
		var zone_id := _zone_id_edit.text.strip_edges()
		if zone_id.is_empty():
			_error_text = "Zone id is required."
			queue_redraw()
			return
		out["zone_id"] = zone_id
		out["width"] = int(_width_edit.text)
		out["height"] = int(_height_edit.text)
		out["event_name"] = _event_edit.text.strip_edges() if not _event_edit.text.strip_edges().is_empty() else "zone_enter"
		out["once"] = _once_check.button_pressed
	if _is_player_spawn():
		out["facing"] = _selected_spawn_facing()

	if not clear_keys.is_empty():
		out["clear_keys"] = clear_keys

	visible = false
	submitted.emit(out)


func _cancel() -> void:
	visible = false
	cancelled.emit()


func _box_rect() -> Rect2:
	return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw_label(font: Font, box: Rect2, row_index: int, text: String) -> void:
	var y := box.position.y + 112.0 + float(row_index) * ROW_H
	draw_string(font, Vector2(box.position.x + LABEL_X, y),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)


func _draw() -> void:
	if not visible:
		return
	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
	var box := _box_rect()
	UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)
	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()
	draw_string(font, box.position + Vector2(24, 34),
		"ENTITY PLACEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
	draw_string(font, box.position + Vector2(24, 56),
		"%s at (%d, %d)" % [_entity_type, int(_entity_pos.x), int(_entity_pos.y)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

	var row := 0
	_draw_label(font, box, row, "Instance Id")
	row += 1
	if _supports_authored_entity_picker():
		_draw_label(font, box, row, "Entity Definition")
		row += 1
	if _is_enemy_like():
		_draw_label(font, box, row, "Behavior Override")
		row += 1
	if _is_interactable_like():
		_draw_label(font, box, row, "Dialogue Id")
		row += 1
	if _is_pickup_like():
		_draw_label(font, box, row, "Item Id")
		row += 1
		_draw_label(font, box, row, "Count")
		row += 1
	if _is_zone():
		_draw_label(font, box, row, "Zone Id")
		row += 1
		_draw_label(font, box, row, "Bounds")
		row += 1
		_draw_label(font, box, row, "Enter Event")
		row += 1
	if _is_player_spawn():
		_draw_label(font, box, row, "Facing")

	var btn_w := 96.0
	var btn_h := 30.0
	var btn_y := box.end.y - btn_h - 16.0
	_ok_rect = Rect2(box.end.x - btn_w - 16.0, btn_y, btn_w, btn_h)
	_cancel_rect = Rect2(_ok_rect.position.x - btn_w - 10.0, btn_y, btn_w, btn_h)
	var ok_hover := _ok_rect.has_point(mouse_pos)
	var cancel_hover := _cancel_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _ok_rect, ok_hover, Color(0.4, 0.9, 0.55, 1.0))
	UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover, Color(0.9, 0.45, 0.4, 1.0))
	draw_string(font, _ok_rect.position + Vector2(32.0, 20.0), "OK",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 1))
	draw_string(font, _cancel_rect.position + Vector2(18.0, 20.0), "CANCEL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 1))

	var helper := ""
	if _supports_authored_entity_picker():
		helper = "Pick the authored entity to spawn here. Instance Id is the per-room ref triggers use."
	elif _is_zone():
		helper = "Zones are trigger targets and event volumes. Use zone_id in trigger actions."
	elif _is_player_spawn():
		helper = "Player spawns can author facing. Runtime startup and room-entry spawns will use it when no explicit facing override is supplied."
	else:
		helper = "Edit the placed entity's room-level properties."
	draw_string(font, Vector2(box.position.x + 24.0, box.end.y - 44.0),
		helper, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 48.0, 10, UIPanels.TEXT_PANEL_DIM)

	if not _error_text.is_empty():
		draw_string(font, Vector2(box.position.x + 24.0, box.end.y - 20.0),
			_error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.55, 1.0))

	if _supports_authored_entity_picker():
		var preview_rect := Rect2(box.end.x - 248.0, box.position.y + 86.0, 212.0, 212.0)
		UIPanels.draw_panel(self, preview_rect, Color(0.18, 0.21, 0.28, 1.0), UIPanels.PanelVariant.DARK)
		draw_string(font, preview_rect.position + Vector2(12.0, 18.0),
			"PREVIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.9, 1.0, 0.95))
		var inner := preview_rect.grow(-14.0)
		inner.position.y += 14.0
		inner.size.y -= 42.0
		if _preview_texture != null:
			var tex_size := _preview_texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				var scale := minf(inner.size.x / tex_size.x, inner.size.y / tex_size.y)
				var draw_size := tex_size * maxf(scale, 0.01)
				var draw_rect := Rect2(inner.position + (inner.size - draw_size) * 0.5, draw_size)
				draw_texture_rect(_preview_texture, draw_rect, false)
		else:
			draw_string(font, inner.position + Vector2(0.0, inner.size.y * 0.5),
				"No sprite preview", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 11, UIPanels.TEXT_PANEL_DIM)
		var preview_name := _preview_label if not _preview_label.is_empty() else _selected_entity_id()
		draw_string(font, Vector2(preview_rect.position.x + 12.0, preview_rect.end.y - 28.0),
			preview_name, HORIZONTAL_ALIGNMENT_LEFT, preview_rect.size.x - 24.0, 10, Color(0.95, 0.97, 1.0, 0.95))
		if not _preview_filename.is_empty():
			draw_string(font, Vector2(preview_rect.position.x + 12.0, preview_rect.end.y - 12.0),
				_preview_filename, HORIZONTAL_ALIGNMENT_LEFT, preview_rect.size.x - 24.0, 9, UIPanels.TEXT_PANEL_DIM)


func _on_entity_picker_selected(_index: int) -> void:
	_refresh_entity_preview()
	if not _is_enemy_like():
		return
	if _selected_behavior_override().is_empty():
		_select_behavior_picker_value(_selected_entity_default_behavior())
