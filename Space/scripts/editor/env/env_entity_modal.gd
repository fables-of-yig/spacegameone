extends Control

signal submitted(data: Dictionary)
signal cancelled

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

const BOX_W: float = 560.0
const BOX_H: float = 360.0

var _entity_type: String = ""
var _entity_pos: Vector2 = Vector2.ZERO
var _instance_edit: LineEdit = null
var _zone_id_edit: LineEdit = null
var _width_edit: LineEdit = null
var _height_edit: LineEdit = null
var _event_edit: LineEdit = null
var _once_check: CheckBox = null
var _error_text: String = ""

var _ok_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_process(true)
	_instance_edit = _make_line_edit("instance id")
	_zone_id_edit = _make_line_edit("zone id")
	_width_edit = _make_line_edit("width")
	_height_edit = _make_line_edit("height")
	_event_edit = _make_line_edit("event name")
	_once_check = CheckBox.new()
	_once_check.text = "Trigger once"
	for node in [_instance_edit, _zone_id_edit, _width_edit, _height_edit, _event_edit, _once_check]:
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


func open(entity_type: String, entity_x: float, entity_y: float, properties: Dictionary) -> void:
	_entity_type = entity_type
	_entity_pos = Vector2(entity_x, entity_y)
	_error_text = ""
	_instance_edit.text = str(properties.get("instance_id", ""))
	_zone_id_edit.text = str(properties.get("zone_id", ""))
	_width_edit.text = str(int(properties.get("width", 16)))
	_height_edit.text = str(int(properties.get("height", 16)))
	_event_edit.text = str(properties.get("event_name", "zone_enter"))
	_once_check.button_pressed = bool(properties.get("once", false))
	visible = true
	_apply_visibility()
	_layout_fields()
	_instance_edit.grab_focus.call_deferred()
	_instance_edit.select_all.call_deferred()


func close() -> void:
	visible = false


func _is_zone() -> bool:
	return _entity_type == "trigger_volume"


func _apply_visibility() -> void:
	var show_zone := _is_zone()
	_instance_edit.visible = true
	_zone_id_edit.visible = show_zone
	_width_edit.visible = show_zone
	_height_edit.visible = show_zone
	_event_edit.visible = show_zone
	_once_check.visible = show_zone


func _layout_fields() -> void:
	if _instance_edit == null:
		return
	var box := _box_rect()
	var label_x := box.position.x + 24.0
	var field_x := box.position.x + 180.0
	var field_w := box.size.x - 204.0
	var row_h := 36.0
	var y := box.position.y + 92.0
	_instance_edit.position = Vector2(field_x, y)
	_instance_edit.size = Vector2(field_w, 28.0)
	y += row_h
	if _is_zone():
		_zone_id_edit.position = Vector2(field_x, y)
		_zone_id_edit.size = Vector2(field_w, 28.0)
		y += row_h
		_width_edit.position = Vector2(field_x, y)
		_width_edit.size = Vector2(96.0, 28.0)
		_height_edit.position = Vector2(field_x + 112.0, y)
		_height_edit.size = Vector2(96.0, 28.0)
		y += row_h
		_event_edit.position = Vector2(field_x, y)
		_event_edit.size = Vector2(field_w, 28.0)
		y += row_h
		_once_check.position = Vector2(field_x, y - 4.0)
		_once_check.size = Vector2(field_w, 28.0)


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
	var out: Dictionary = {
		"instance_id": _instance_edit.text.strip_edges(),
	}
	if _entity_type != "player_spawn" and out["instance_id"].is_empty():
		_error_text = "Instance id is required."
		queue_redraw()
		return
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
	visible = false
	submitted.emit(out)


func _cancel() -> void:
	visible = false
	cancelled.emit()


func _box_rect() -> Rect2:
	return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw() -> void:
	if not visible:
		return
	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
	var box := _box_rect()
	UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)
	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()
	draw_string(font, box.position + Vector2(24, 34),
		"ENTITY PROPERTIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
	draw_string(font, box.position + Vector2(24, 56),
		"%s at (%d, %d)" % [_entity_type, int(_entity_pos.x), int(_entity_pos.y)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)

	var label_x := box.position.x + 24.0
	var y := box.position.y + 112.0
	draw_string(font, Vector2(label_x, y), "Instance Id", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
	y += 36.0
	if _is_zone():
		draw_string(font, Vector2(label_x, y), "Zone Id", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
		y += 36.0
		draw_string(font, Vector2(label_x, y), "Bounds", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
		y += 36.0
		draw_string(font, Vector2(label_x, y), "Enter Event", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)

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
	if not _error_text.is_empty():
		draw_string(font, Vector2(box.position.x + 24.0, box.end.y - 20.0),
			_error_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.55, 1.0))
