extends Control

# Generic full-screen modal that lists string options and emits the
# chosen value. Used for enum-kind params (e.g. shoot.aim = facing|player)
# and for the "pick a schema key to add" flow. Fires `picked(value)` /
# `cancelled`.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

signal picked(value: String)
signal cancelled

const BOX_W: float = 420.0
const ROW_H: float = 34.0
const PAD: float = 20.0

var _title: String = "Pick"
var _options: Array = []  # [{value, label?, help?}]
var _current: String = ""
var _rows: Array = []  # [{value, rect}]
var _cancel_rect: Rect2 = Rect2()


func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_process(true)


func _process(_delta):
	if visible:
		queue_redraw()


func open(title: String, options: Array, current: String = "") -> void:
	_title = title
	_options = options
	_current = current
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _gui_input(event):
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cancel_rect.has_point(mb.position):
				_do_cancel()
				accept_event()
				return
			for row in _rows:
				if (row["rect"] as Rect2).has_point(mb.position):
					visible = false
					picked.emit(str(row["value"]))
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
	var h: float = 90.0 + float(_options.size()) * ROW_H + 60.0
	h = clampf(h, 180.0, 600.0)
	return Rect2((size.x - BOX_W) * 0.5, (size.y - h) * 0.5, BOX_W, h)


func _draw():
	if not visible:
		return
	UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
	var box := _box_rect()
	UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()
	draw_string(font, box.position + Vector2(PAD + 4, 36),
		_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)

	_rows.clear()
	var list_x: float = box.position.x + PAD
	var list_y: float = box.position.y + 56
	var list_w: float = box.size.x - PAD * 2.0

	var y: float = list_y
	for opt_v in _options:
		var opt: Dictionary = opt_v if typeof(opt_v) == TYPE_DICTIONARY else {"value": str(opt_v)}
		var val: String = str(opt.get("value", ""))
		var label: String = str(opt.get("label", val))
		var help: String = str(opt.get("help", ""))
		var rect := Rect2(list_x, y, list_w, ROW_H - 4)
		var is_sel := val == _current
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
		draw_string(font, rect.position + Vector2(10, 20),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.95, 1, 0.96, 1) if (hover or is_sel) else Color(0.78, 0.92, 0.84, 1))
		_rows.append({"value": val, "rect": rect})
		if hover and not help.is_empty():
			EditorTooltip.show_text(help)
		y += ROW_H

	var btn_w: float = 110.0
	var btn_h: float = 30.0
	_cancel_rect = Rect2(box.position.x + box.size.x - btn_w - PAD,
		box.position.y + box.size.y - btn_h - 16, btn_w, btn_h)
	var cancel_hover := _cancel_rect.has_point(mouse_pos)
	UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover,
		Color(0.9, 0.45, 0.4, 1.0))
	draw_string(font, _cancel_rect.position + Vector2(32, 20),
		"CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
