extends Control

# Full-screen modal that lists all registered action or condition leaves
# pulled from BehLeafSchema. Fires `picked(name, is_custom)` on selection:
# when is_custom == true the name is empty and the host should fall back
# to a free-form text prompt. `cancelled` on Esc or outside click.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const BehLeafSchema = preload("res://Space/scripts/editor/beh/beh_leaf_schema.gd")

signal picked(leaf_name: String, is_custom: bool)
signal cancelled

const BOX_W: float = 560.0
const BOX_H: float = 560.0
const ROW_H: float = 40.0

var _kind: String = "action"
var _current: String = ""
var _rows: Array = []  # [{name, rect}]
var _custom_rect: Rect2 = Rect2()
var _cancel_rect: Rect2 = Rect2()
var _scroll: float = 0.0
var _content_h: float = 0.0


func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_process(true)


func _process(_delta):
	if visible:
		queue_redraw()


func open(kind: String, current_name: String = "") -> void:
	_kind = kind if kind == "action" or kind == "condition" else "action"
	_current = current_name
	_scroll = 0.0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _gui_input(event):
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = min(_scroll + 40.0, max(0.0, _content_h - BOX_H + 100.0))
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = max(_scroll - 40.0, 0.0)
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cancel_rect.has_point(mb.position):
				_do_cancel()
				accept_event()
				return
			if _custom_rect.has_point(mb.position):
				visible = false
				picked.emit("", true)
				accept_event()
				return
			for row in _rows:
				if (row["rect"] as Rect2).has_point(mb.position):
					visible = false
					picked.emit(str(row["name"]), false)
					accept_event()
					return
			var box := _box_rect()
			if not box.has_point(mb.position):
				_do_cancel()
				accept_event()
				return


func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_do_cancel()
			get_viewport().set_input_as_handled()


func _do_cancel() -> void:
	visible = false
	cancelled.emit()


func _box_rect() -> Rect2:
	return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw():
	if not visible:
		return
	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
	var box := _box_rect()
	UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()

	var title := "Pick %s" % ("action" if _kind == "action" else "condition")
	draw_string(font, box.position + Vector2(24, 36),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)

	_rows.clear()
	var list_x: float = box.position.x + 20
	var list_y: float = box.position.y + 60
	var list_w: float = box.size.x - 40

	var schemas: Array = BehLeafSchema.ACTIONS if _kind == "action" else BehLeafSchema.CONDITIONS
	var y: float = list_y - _scroll
	for entry_v in schemas:
		var entry: Dictionary = entry_v
		var name: String = str(entry.get("name", ""))
		var label: String = str(entry.get("label", name))
		var help: String = str(entry.get("help", ""))
		var rect := Rect2(list_x, y, list_w, ROW_H - 2)
		var is_sel := name == _current
		var hover := rect.has_point(mouse_pos)
		var bg: Color
		if is_sel:
			bg = Color(0.3, 0.55, 0.42, 0.95)
		elif hover:
			bg = Color(0.18, 0.3, 0.22, 0.9)
		else:
			bg = Color(0.08, 0.16, 0.1, 0.8)
		draw_rect(rect, bg)
		draw_rect(rect, Color(0.5, 0.85, 0.62, 0.85), false, 1.0)
		draw_string(font, rect.position + Vector2(12, 16),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.95, 1, 0.96, 1) if (hover or is_sel) else Color(0.78, 0.92, 0.84, 1))
		draw_string(font, rect.position + Vector2(12, 32),
			name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.55, 0.85, 0.7, 1))
		_rows.append({"name": name, "rect": rect})
		if hover and not help.is_empty():
			EditorTooltip.show_text(help)
		y += ROW_H

	_content_h = (y + _scroll) - list_y

	# Custom-name row.
	_custom_rect = Rect2(list_x, box.position.y + box.size.y - 96.0,
		list_w * 0.55, 32.0)
	var custom_hover := _custom_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _custom_rect, custom_hover, Color(0.7, 0.75, 1.0, 1.0))
	draw_string(font, _custom_rect.position + Vector2(10, 21),
		"(custom name...)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.95, 0.95, 1, 1) if custom_hover else Color(0.75, 0.8, 0.95, 1))
	if custom_hover:
		EditorTooltip.show_text("Open a text input for a custom leaf name not in the registered list. The runtime will warn and fall back to idle/always if the name isn't registered.")

	var btn_w: float = 110.0
	var btn_h: float = 32.0
	_cancel_rect = Rect2(box.position.x + box.size.x - btn_w - 20,
		box.position.y + box.size.y - btn_h - 16, btn_w, btn_h)
	var cancel_hover := _cancel_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover,
		Color(0.9, 0.45, 0.4, 1.0))
	draw_string(font, _cancel_rect.position + Vector2(32, 21),
		"CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
	if cancel_hover:
		EditorTooltip.show_text("Close this picker without changing the leaf name.")

	draw_string(font, box.position + Vector2(24, box.size.y - 12),
		"Click a name to apply.  Esc: cancel",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
