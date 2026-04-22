extends Control

# Loads a screen JSON element tree and renders it using UIPanels draw calls.
# Resolves anchors to absolute positions and updates bindings each frame so
# bound labels (e.g. "player.hp") always show the latest value.
#
# Element tree shape (recursive):
#   {
#     "type": "panel" | "label" | "button" | "progress_bar" | "icon"
#             | "separator" | "tab_bar" | "list" | "grid" | "conditional",
#     "id": "optional_id",
#     "anchor": "top_left" | "top_right" | "bottom_left" | "bottom_right"
#               | "center" | "top_center" | "bottom_center",
#     "rect": {"x": 10, "y": 10, "w": 200, "h": 30},
#     "binding": "player.hp",
#     "static_text": "Hello",
#     "children": [ ... ],
#     ... (type-specific keys)
#   }

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UiBindingResolver := preload("res://MV/scripts/ui_binding_resolver.gd")

var screen_data: Dictionary = {}

# Hit-test tracking for interactive elements (buttons).
var _element_rects: Array = []   # [{id, rect, element}]
var _hovered_id: String = ""
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func load_screen(data: Dictionary) -> void:
	screen_data = data
	_element_rects.clear()
	_hovered_id = ""
	queue_redraw()


func _process(_delta: float) -> void:
	# Bindings may change every frame (hp ticks down, etc.), so redraw.
	if not screen_data.is_empty():
		queue_redraw()


func _draw() -> void:
	if screen_data.is_empty():
		return
	_element_rects.clear()
	var viewport_size := get_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = Vector2(480, 270)
	_draw_element(screen_data, Rect2(Vector2.ZERO, viewport_size))


# ---- Recursive element renderer -----------------------------------------

func _draw_element(el: Dictionary, parent_rect: Rect2) -> void:
	var el_type: String = str(el.get("type", "panel"))
	var abs_rect := _resolve_rect(el, parent_rect)

	match el_type:
		"panel":
			_draw_panel(el, abs_rect)
		"label":
			_draw_label(el, abs_rect)
		"button":
			_draw_button(el, abs_rect)
		"progress_bar":
			_draw_progress_bar(el, abs_rect)
		"icon":
			_draw_icon(el, abs_rect)
		"separator":
			_draw_separator(el, abs_rect)
		"tab_bar":
			_draw_tab_bar(el, abs_rect)
		"list":
			_draw_placeholder(el, abs_rect, "list", Color(0.2, 0.3, 0.5, 0.4))
		"grid":
			_draw_placeholder(el, abs_rect, "grid", Color(0.3, 0.2, 0.5, 0.4))
		"conditional":
			_draw_conditional(el, abs_rect)
		_:
			_draw_placeholder(el, abs_rect, el_type, Color(0.4, 0.4, 0.4, 0.3))

	# Draw children within this element's rect.
	var children: Array = el.get("children", [])
	for child in children:
		if typeof(child) == TYPE_DICTIONARY:
			_draw_element(child, abs_rect)


# ---- Type-specific draw methods ------------------------------------------

func _draw_panel(el: Dictionary, rect: Rect2) -> void:
	var variant_str: String = str(el.get("variant", "main"))
	var variant: int = UIPanels.PanelVariant.MAIN
	match variant_str:
		"alt":
			variant = UIPanels.PanelVariant.ALT
		"dark":
			variant = UIPanels.PanelVariant.DARK
	var tint := _parse_color(el.get("tint", ""), Color.WHITE)
	UIPanels.draw_panel(self, rect, tint, variant)


func _draw_label(el: Dictionary, rect: Rect2) -> void:
	var text := _resolve_text(el)
	if text.is_empty():
		return
	var role: String = str(el.get("text_role", "body"))
	var color := UIPanels.text_color(role)
	var custom_color: String = str(el.get("color", ""))
	if not custom_color.is_empty():
		color = _parse_color(custom_color, color)
	var size_role: String = str(el.get("font_size_role", "body_size"))
	var fsize: int = UIPanels.font_size(size_role)
	var custom_size: int = int(el.get("font_size", 0))
	if custom_size > 0:
		fsize = custom_size
	if _font != null:
		var text_y := rect.position.y + rect.size.y * 0.5 + float(fsize) * 0.35
		draw_string(_font, Vector2(rect.position.x, text_y), text,
			HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x), fsize, color)


func _draw_button(el: Dictionary, rect: Rect2) -> void:
	var el_id: String = str(el.get("id", ""))
	var hovered := el_id != "" and el_id == _hovered_id
	var label_text := _resolve_text(el)
	var tint := _parse_color(el.get("tint", ""), Color.WHITE)
	if _font != null:
		UIPanels.draw_button(self, rect, label_text, _font, hovered, tint)
	else:
		UIPanels.draw_button_bg(self, rect, hovered, tint)
	# Register for hit testing.
	if not el_id.is_empty():
		_element_rects.append({"id": el_id, "rect": rect, "element": el})


func _draw_progress_bar(el: Dictionary, rect: Rect2) -> void:
	var binding: String = str(el.get("binding", ""))
	var max_binding: String = str(el.get("max_binding", ""))
	var value: float = 0.0
	var max_value: float = 1.0

	if not binding.is_empty():
		value = float(UiBindingResolver.resolve(binding))
	else:
		value = float(el.get("value", 0))

	if not max_binding.is_empty():
		max_value = float(UiBindingResolver.resolve(max_binding))
	else:
		max_value = float(el.get("max_value", 1.0))

	var ratio := value / maxf(max_value, 0.001)
	var fill_color := _parse_color(el.get("fill_color", ""), Color(0.3, 0.85, 0.4))
	var bg_color := _parse_color(el.get("bg_color", ""), Color(0.15, 0.15, 0.2))
	var direction: String = str(el.get("direction", "left_to_right"))
	var label_text: String = str(el.get("label", ""))
	UIPanels.draw_progress_bar(self, rect, ratio, fill_color, bg_color,
		direction, label_text, _font)


func _draw_icon(el: Dictionary, rect: Rect2) -> void:
	var tex_path: String = str(el.get("texture", ""))
	var tex: Texture2D = null
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		tex = load(tex_path) as Texture2D
	var tint := _parse_color(el.get("tint", ""), Color.WHITE)
	UIPanels.draw_icon(self, rect, tex, Rect2(), tint)


func _draw_separator(el: Dictionary, rect: Rect2) -> void:
	var color := _parse_color(el.get("color", ""), Color(0.5, 0.5, 0.5, 0.8))
	var thickness: float = float(el.get("thickness", 1.0))
	var orientation: String = str(el.get("orientation", "horizontal"))
	UIPanels.draw_separator(self, rect, color, thickness, orientation)


func _draw_tab_bar(el: Dictionary, rect: Rect2) -> void:
	var tabs: Array = el.get("tabs", [])
	var active_idx: int = int(el.get("active_tab", 0))
	var active_color := _parse_color(el.get("active_color", ""), Color(0.4, 0.85, 1.0))
	var inactive_color := _parse_color(el.get("inactive_color", ""), Color(0.6, 0.65, 0.7))
	if _font != null:
		UIPanels.draw_tab_bar(self, rect, tabs, active_idx, _font,
			active_color, inactive_color)


func _draw_conditional(el: Dictionary, rect: Rect2) -> void:
	# Evaluate the binding as a boolean. If truthy, draw children; if
	# not, draw else_children (if present). For now, draw a tinted rect
	# to indicate conditional regions during authoring.
	var binding: String = str(el.get("binding", ""))
	var value: Variant = null
	if not binding.is_empty():
		value = UiBindingResolver.resolve(binding)
	var truthy := _is_truthy(value)

	var bg_color := Color(0.2, 0.4, 0.2, 0.25) if truthy else Color(0.4, 0.2, 0.2, 0.15)
	draw_rect(rect, bg_color)

	var branch_key := "children" if truthy else "else_children"
	var branch: Array = el.get(branch_key, [])
	for child in branch:
		if typeof(child) == TYPE_DICTIONARY:
			_draw_element(child, rect)


func _draw_placeholder(_el: Dictionary, rect: Rect2, type_name: String,
		bg: Color) -> void:
	draw_rect(rect, bg)
	draw_rect(rect, Color(0.6, 0.6, 0.6, 0.4), false, 1.0)
	if _font != null:
		var label := "[%s]" % type_name
		var label_y := rect.position.y + rect.size.y * 0.5 + 5
		draw_string(_font, Vector2(rect.position.x + 4, label_y), label,
			HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 8), 10,
			Color(0.8, 0.8, 0.8, 0.7))


# ---- Anchor + rect resolution -------------------------------------------

func _resolve_rect(el: Dictionary, parent_rect: Rect2) -> Rect2:
	var r: Dictionary = el.get("rect", {})
	var x: float = float(r.get("x", 0))
	var y: float = float(r.get("y", 0))
	var w: float = float(r.get("w", parent_rect.size.x))
	var h: float = float(r.get("h", parent_rect.size.y))

	var anchor: String = str(el.get("anchor", "top_left"))
	var origin := _anchor_origin(anchor, parent_rect, Vector2(w, h))
	return Rect2(origin + Vector2(x, y), Vector2(w, h))


static func _anchor_origin(anchor: String, parent: Rect2,
		el_size: Vector2) -> Vector2:
	var pp := parent.position
	var ps := parent.size
	match anchor:
		"top_left":
			return pp
		"top_right":
			return Vector2(pp.x + ps.x - el_size.x, pp.y)
		"top_center":
			return Vector2(pp.x + (ps.x - el_size.x) * 0.5, pp.y)
		"bottom_left":
			return Vector2(pp.x, pp.y + ps.y - el_size.y)
		"bottom_right":
			return Vector2(pp.x + ps.x - el_size.x, pp.y + ps.y - el_size.y)
		"bottom_center":
			return Vector2(pp.x + (ps.x - el_size.x) * 0.5, pp.y + ps.y - el_size.y)
		"center":
			return Vector2(pp.x + (ps.x - el_size.x) * 0.5,
				pp.y + (ps.y - el_size.y) * 0.5)
		"center_left":
			return Vector2(pp.x, pp.y + (ps.y - el_size.y) * 0.5)
		"center_right":
			return Vector2(pp.x + ps.x - el_size.x,
				pp.y + (ps.y - el_size.y) * 0.5)
	return pp


# ---- Text + binding resolution ------------------------------------------

func _resolve_text(el: Dictionary) -> String:
	var binding: String = str(el.get("binding", ""))
	if not binding.is_empty():
		var value: Variant = UiBindingResolver.resolve(binding)
		if value == null:
			return str(el.get("static_text", ""))
		return str(value)
	return str(el.get("static_text", ""))


static func _parse_color(val: Variant, fallback: Color) -> Color:
	if typeof(val) == TYPE_COLOR:
		return val
	var s := str(val).strip_edges()
	if s.is_empty():
		return fallback
	if s.begins_with("#"):
		s = s.substr(1)
	if s.length() == 6 or s.length() == 8:
		return Color.html(s)
	return fallback


static func _is_truthy(value: Variant) -> bool:
	if value == null:
		return false
	match typeof(value):
		TYPE_BOOL:
			return value as bool
		TYPE_INT:
			return (value as int) != 0
		TYPE_FLOAT:
			return (value as float) != 0.0
		TYPE_STRING:
			return not (value as String).is_empty()
		TYPE_ARRAY:
			return not (value as Array).is_empty()
		TYPE_DICTIONARY:
			return not (value as Dictionary).is_empty()
	return true


# ---- Input: hover tracking for buttons ----------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		_update_hover(pos)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)


func _update_hover(pos: Vector2) -> void:
	var old := _hovered_id
	_hovered_id = ""
	for entry in _element_rects:
		var r: Rect2 = entry["rect"]
		if r.has_point(pos):
			_hovered_id = str(entry["id"])
			break
	if _hovered_id != old:
		queue_redraw()


func _handle_click(pos: Vector2) -> void:
	for entry in _element_rects:
		var r: Rect2 = entry["rect"]
		if r.has_point(pos):
			var el: Dictionary = entry["element"]
			var action: String = str(el.get("action", ""))
			if not action.is_empty():
				_dispatch_action(action, el)
			break


func _dispatch_action(action: String, el: Dictionary) -> void:
	# Future: route to a signal or callback registry. For now, print for
	# debugging so authors can verify click targets work.
	print("UIScreenRenderer: action '%s' from element '%s'" % [
		action, str(el.get("id", "?"))])
