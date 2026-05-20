extends Control

# WYSIWYG editor canvas for the UI Builder system. Renders a simulated game
# viewport (480x272 at configurable zoom) and lets the user place, move, and
# resize UI elements. Reads/writes a screen data dict (a tree of element dicts).
#
# Element dict shape:
#   { "type": "label", "id": "hp_label",
#     "rect": {"x": 10, "y": 10, "w": 100, "h": 20},
#     "anchor": "top_left", "properties": {...}, "children": [...] }

const UITypes = preload("res://Space/scripts/shared/ui/ui_types.gd")
const UIIo = preload("res://Space/scripts/shared/ui/ui_io.gd")
const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

signal element_selected(element_id: String)
signal element_moved(element_id: String)
signal element_resized(element_id: String)
signal context_menu_requested(element_id: String, pos: Vector2)

# Set by the parent editor after instantiation.
var editor: Node = null

# Root element tree for the current screen. Typically a panel with children.
var screen_data: Dictionary = {}

# Currently selected element id.
var selected_element_id: String = ""

# ─── Viewport constants ────────────────────────────────────────────────
const VIEWPORT_W: int = 480
const VIEWPORT_H: int = 272

# ─── Camera / zoom state ───────────────────────────────────────────────
var zoom: float = 2.0
var cam_offset: Vector2 = Vector2(32, 32)

# ─── Selection handle constants ────────────────────────────────────────
const HANDLE_SIZE: float = 6.0
const HANDLE_HALF: float = 3.0

enum _HandleCorner { NONE = -1, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

# ─── Interaction state ─────────────────────────────────────────────────
var _dragging: bool = false
var _resizing: bool = false
var _resize_corner: int = _HandleCorner.NONE
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_rect: Dictionary = {}  # snapshot of rect at drag start
var _hovered_element_id: String = ""
var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO

# Flat cache rebuilt each frame — maps element id to its world Rect2.
var _element_rects: Dictionary = {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)


func _process(_delta: float) -> void:
	# Update hover before redraw.
	var mouse_pos := get_local_mouse_position()
	if Rect2(Vector2.ZERO, size).has_point(mouse_pos):
		_hovered_element_id = _hit_test(mouse_pos)
	else:
		_hovered_element_id = ""
	queue_redraw()


# ─── Input ──────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	# Middle-click panning
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mb.pressed
		_pan_last = mb.position
		accept_event()
		return

	# Zoom
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_at(mb.position, 1.15)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_at(mb.position, 1.0 / 1.15)
		accept_event()
		return

	# Right-click context menu
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var hit := _hit_test(mb.position)
		if hit != "":
			context_menu_requested.emit(hit, mb.global_position)
		accept_event()
		return

	# Left-click: select, start drag or resize
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_on_left_press(mb.position)
		else:
			_on_left_release()
		accept_event()
		return


func _on_left_press(pos: Vector2) -> void:
	# Check if clicking a resize handle of the already-selected element.
	if selected_element_id != "" and _element_rects.has(selected_element_id):
		var corner := _hit_handle(pos, _element_rects[selected_element_id])
		if corner != _HandleCorner.NONE:
			_resizing = true
			_resize_corner = corner
			_drag_start_mouse = pos
			_drag_start_rect = _get_element_rect_dict(selected_element_id)
			return

	# Hit-test for element selection.
	var hit := _hit_test(pos)
	if hit != selected_element_id:
		selected_element_id = hit
		element_selected.emit(hit)

	# Begin dragging the selected element.
	if selected_element_id != "":
		_dragging = true
		_drag_start_mouse = pos
		_drag_start_rect = _get_element_rect_dict(selected_element_id)


func _on_left_release() -> void:
	if _dragging:
		_dragging = false
		if selected_element_id != "":
			element_moved.emit(selected_element_id)
	if _resizing:
		_resizing = false
		_resize_corner = _HandleCorner.NONE
		if selected_element_id != "":
			element_resized.emit(selected_element_id)


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if _panning:
		cam_offset += mm.position - _pan_last
		_pan_last = mm.position
		accept_event()
		return

	if _dragging and selected_element_id != "":
		var delta := (mm.position - _drag_start_mouse) / zoom
		_apply_move(selected_element_id, delta)
		accept_event()
		return

	if _resizing and selected_element_id != "":
		var delta := (mm.position - _drag_start_mouse) / zoom
		_apply_resize(selected_element_id, delta)
		accept_event()
		return


# ─── Zoom ───────────────────────────────────────────────────────────────

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world_before := (screen_pos - cam_offset) / zoom
	zoom = clampf(zoom * factor, 0.5, 6.0)
	var world_after := (screen_pos - cam_offset) / zoom
	cam_offset += (world_after - world_before) * zoom


# ─── Coordinate helpers ────────────────────────────────────────────────

func _world_to_screen(world: Vector2) -> Vector2:
	return cam_offset + world * zoom


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - cam_offset) / zoom


func _resolved_screen_rect(elem: Dictionary, parent_origin: Vector2) -> Rect2:
	var wr := _resolved_world_rect(elem, parent_origin)
	return Rect2(_world_to_screen(wr.position), wr.size * zoom)


func _resolved_world_rect(elem: Dictionary, parent_origin: Vector2) -> Rect2:
	var r: Dictionary = elem.get("rect", {})
	var pos := Vector2(float(r.get("x", 0)), float(r.get("y", 0)))
	var rect := Rect2(pos, Vector2(float(r.get("w", 50)), float(r.get("h", 20))))
	if _is_root_element(elem):
		return rect
	if parent_origin != Vector2.ZERO:
		rect.position += parent_origin
		return rect
	var offs_v: Variant = elem.get("anchor_offset", {})
	var anchor_offset := Vector2.ZERO
	if typeof(offs_v) == TYPE_DICTIONARY:
		var offs: Dictionary = offs_v
		anchor_offset = Vector2(float(offs.get("x", 0)), float(offs.get("y", 0)))
	rect.position += _anchor_origin(str(elem.get("anchor", "top_left"))) + anchor_offset
	return rect


# ─── Hit testing ───────────────────────────────────────────────────────

# Returns the id of the topmost (last-drawn) element under `screen_pos`,
# or "" if nothing is hit. Walks the tree depth-first so children are
# tested after (and override) parents.
func _hit_test(screen_pos: Vector2) -> String:
	if screen_data.is_empty():
		return ""
	_rebuild_element_rects()
	var result := ""
	_hit_test_recursive(screen_data, screen_pos, result)
	return result


func _hit_test_recursive(elem: Dictionary, screen_pos: Vector2, result: String) -> String:
	var eid := str(elem.get("id", ""))
	var sr: Rect2 = _element_rects.get(eid, Rect2())
	if sr.has_point(screen_pos) and eid != "":
		result = eid
	var children_v: Variant = elem.get("children", [])
	if typeof(children_v) == TYPE_ARRAY:
		for child_v in (children_v as Array):
			if typeof(child_v) == TYPE_DICTIONARY:
				result = _hit_test_recursive(child_v as Dictionary, screen_pos, result)
	return result


func _hit_handle(screen_pos: Vector2, sr: Rect2) -> int:
	var corners: Array[Rect2] = _handle_rects(sr)
	for i in corners.size():
		if corners[i].has_point(screen_pos):
			return i
	return _HandleCorner.NONE


func _handle_rects(sr: Rect2) -> Array[Rect2]:
	var hs := HANDLE_SIZE
	var hh := HANDLE_HALF
	return [
		Rect2(sr.position.x - hh, sr.position.y - hh, hs, hs),
		Rect2(sr.end.x - hh, sr.position.y - hh, hs, hs),
		Rect2(sr.position.x - hh, sr.end.y - hh, hs, hs),
		Rect2(sr.end.x - hh, sr.end.y - hh, hs, hs),
	]


# ─── Move / resize ────────────────────────────────────────────────────

func _get_element_rect_dict(eid: String) -> Dictionary:
	var elem := _find_element(screen_data, eid)
	if elem.is_empty():
		return {}
	var r: Dictionary = elem.get("rect", {})
	return {"x": float(r.get("x", 0)), "y": float(r.get("y", 0)),
			"w": float(r.get("w", 50)), "h": float(r.get("h", 20))}


func _apply_move(eid: String, delta: Vector2) -> void:
	var elem := _find_element(screen_data, eid)
	if elem.is_empty() or _drag_start_rect.is_empty():
		return
	var r: Dictionary = elem.get("rect", {}).duplicate()
	r["x"] = snapped(_drag_start_rect["x"] + delta.x, 1.0)
	r["y"] = snapped(_drag_start_rect["y"] + delta.y, 1.0)
	elem["rect"] = r


func _apply_resize(eid: String, delta: Vector2) -> void:
	var elem := _find_element(screen_data, eid)
	if elem.is_empty() or _drag_start_rect.is_empty():
		return
	var r: Dictionary = elem.get("rect", {}).duplicate()
	var sx: float = _drag_start_rect["x"]
	var sy: float = _drag_start_rect["y"]
	var sw: float = _drag_start_rect["w"]
	var sh: float = _drag_start_rect["h"]
	var min_dim := 8.0

	match _resize_corner:
		_HandleCorner.BOTTOM_RIGHT:
			r["w"] = maxf(min_dim, snapped(sw + delta.x, 1.0))
			r["h"] = maxf(min_dim, snapped(sh + delta.y, 1.0))
		_HandleCorner.TOP_LEFT:
			var new_w := maxf(min_dim, snapped(sw - delta.x, 1.0))
			var new_h := maxf(min_dim, snapped(sh - delta.y, 1.0))
			r["x"] = snapped(sx + sw - new_w, 1.0)
			r["y"] = snapped(sy + sh - new_h, 1.0)
			r["w"] = new_w
			r["h"] = new_h
		_HandleCorner.TOP_RIGHT:
			var new_h := maxf(min_dim, snapped(sh - delta.y, 1.0))
			r["w"] = maxf(min_dim, snapped(sw + delta.x, 1.0))
			r["y"] = snapped(sy + sh - new_h, 1.0)
			r["h"] = new_h
		_HandleCorner.BOTTOM_LEFT:
			var new_w := maxf(min_dim, snapped(sw - delta.x, 1.0))
			r["x"] = snapped(sx + sw - new_w, 1.0)
			r["w"] = new_w
			r["h"] = maxf(min_dim, snapped(sh + delta.y, 1.0))
	elem["rect"] = r


# ─── Element tree search ──────────────────────────────────────────────

func _find_element(root: Dictionary, eid: String) -> Dictionary:
	if str(root.get("id", "")) == eid:
		return root
	var children_v: Variant = root.get("children", [])
	if typeof(children_v) == TYPE_ARRAY:
		for child_v in (children_v as Array):
			if typeof(child_v) != TYPE_DICTIONARY:
				continue
			var found := _find_element(child_v as Dictionary, eid)
			if not found.is_empty():
				return found
	return {}


# ─── Draw ──────────────────────────────────────────────────────────────

func _draw() -> void:
	# Canvas background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.10, 1.0))

	# Simulated viewport background
	var vp_screen := Rect2(
		_world_to_screen(Vector2.ZERO),
		Vector2(float(VIEWPORT_W), float(VIEWPORT_H)) * zoom)
	draw_rect(vp_screen, Color(0.02, 0.025, 0.05, 1.0))
	draw_rect(vp_screen, Color(0.3, 0.45, 0.7, 0.6), false, 1.0)

	if screen_data.is_empty():
		_draw_empty_hint()
		return

	# Rebuild the flat rect cache, then draw elements.
	_rebuild_element_rects()
	_draw_element_recursive(screen_data)

	# Hover outline (below selection handles so handles stay on top)
	if _hovered_element_id != "" and _hovered_element_id != selected_element_id:
		if _element_rects.has(_hovered_element_id):
			var hr: Rect2 = _element_rects[_hovered_element_id]
			draw_rect(hr, Color(0.3, 0.65, 1.0, 0.7), false, 1.5)

	# Selection handles
	if selected_element_id != "" and _element_rects.has(selected_element_id):
		var sr: Rect2 = _element_rects[selected_element_id]
		draw_rect(sr, Color(1.0, 0.85, 0.2, 0.85), false, 2.0)
		var corners := _handle_rects(sr)
		for corner_rect in corners:
			draw_rect(corner_rect, Color(1.0, 1.0, 1.0, 0.95))
			draw_rect(corner_rect, Color(0.2, 0.2, 0.2, 1.0), false, 1.0)

	# Viewport size label
	var font := ThemeDB.fallback_font
	var label_text := "%dx%d  zoom %.0f%%" % [VIEWPORT_W, VIEWPORT_H, zoom * 100.0]
	draw_string(font, vp_screen.position + Vector2(4, -4),
		label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.5, 0.6, 0.7, 0.7))


func _draw_empty_hint() -> void:
	var font := ThemeDB.fallback_font
	var msg := "(no screen loaded)"
	var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5),
		msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.5, 0.6, 1.0))


func _draw_element_recursive(elem: Dictionary) -> void:
	var eid := str(elem.get("id", ""))
	var etype := str(elem.get("type", ""))
	var sr: Rect2 = _element_rects.get(eid, Rect2())
	var props: Dictionary = elem.get("properties", {})
	var opacity := clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)

	var fill_color: Color = UITypes.ELEMENT_COLORS.get(etype, Color(0.5, 0.5, 0.5, 0.5))
	if etype == UITypes.ELEM_PANEL:
		var sprite_path := str(props.get("sprite_source", "")).strip_edges()
		var drew_panel_art := false
		if not sprite_path.is_empty():
			var tex := UIIo.load_texture(sprite_path)
			if tex != null:
				var tint := Color.from_string(str(props.get("sprite_tint", "#ffffff")), Color.WHITE)
				tint.a *= opacity
				UIPanels.draw_authored_panel_sprite(self, sr, tex, props, tint, zoom)
				drew_panel_art = true
		if not drew_panel_art:
			var variant_key := str(props.get("variant", "main")).strip_edges()
			if not variant_key.is_empty() and variant_key != "none":
				var variant := UIPanels.PanelVariant.MAIN
				if variant_key == "alt":
					variant = UIPanels.PanelVariant.ALT
				elif variant_key == "dark":
					variant = UIPanels.PanelVariant.DARK
				UIPanels.draw_panel(self, sr, Color(1.0, 1.0, 1.0, opacity), variant)
				drew_panel_art = true
		if not drew_panel_art:
			fill_color.a *= opacity
			draw_rect(sr, fill_color)
	elif etype == UITypes.ELEM_ICON:
		var source := str(props.get("sprite_source", "")).strip_edges()
		var tex := UIIo.load_texture(source)
		if tex != null:
			var tint := Color.from_string(str(props.get("tint", "#ffffff")), Color.WHITE)
			tint.a *= opacity
			UIPanels.draw_icon(self, sr, tex, Rect2(), tint)
		else:
			fill_color.a *= opacity
			draw_rect(sr, fill_color)
	else:
		fill_color.a *= opacity
		draw_rect(sr, fill_color)

	# Thin border so overlapping elements are distinguishable.
	var border_color := fill_color
	border_color.a = minf(1.0, fill_color.a + 0.3)
	draw_rect(sr, border_color, false, 1.0)

	# Type + id label inside the rectangle.
	var font := ThemeDB.fallback_font
	var type_label: String = UITypes.element_label(etype) if etype != "" else "?"
	var display_label := type_label
	if eid != "":
		display_label += "  #" + eid
	var font_sz := clampi(int(sr.size.y * 0.45), 7, 12)
	var max_text_w := int(sr.size.x - 4)
	if max_text_w > 10 and sr.size.y > 10:
		draw_string(font, sr.position + Vector2(3, font_sz + 2.0),
			display_label, HORIZONTAL_ALIGNMENT_LEFT, max_text_w, font_sz,
			Color(1, 1, 1, 0.9))

	# Recurse into children.
	var children_v: Variant = elem.get("children", [])
	if typeof(children_v) == TYPE_ARRAY:
		for child_v in (children_v as Array):
			if typeof(child_v) == TYPE_DICTIONARY:
				_draw_element_recursive(child_v as Dictionary)


func _rebuild_element_rects() -> void:
	_element_rects.clear()
	if screen_data.is_empty():
		return
	_cache_element_rects_recursive(screen_data, Vector2.ZERO)


func _cache_element_rects_recursive(elem: Dictionary, parent_origin: Vector2) -> void:
	var world_rect := _resolved_world_rect(elem, parent_origin)
	var rect := Rect2(_world_to_screen(world_rect.position), world_rect.size * zoom)
	var eid := str(elem.get("id", ""))
	if eid != "":
		_element_rects[eid] = rect
	var children_v: Variant = elem.get("children", [])
	if typeof(children_v) != TYPE_ARRAY:
		return
	for child_v in (children_v as Array):
		if typeof(child_v) == TYPE_DICTIONARY:
			_cache_element_rects_recursive(child_v as Dictionary, world_rect.position)


func _is_root_element(elem: Dictionary) -> bool:
	return elem == screen_data


func _anchor_origin(anchor: String) -> Vector2:
	match anchor:
		"top_left":
			return Vector2.ZERO
		"top_center":
			return Vector2(VIEWPORT_W * 0.5, 0.0)
		"top_right":
			return Vector2(VIEWPORT_W, 0.0)
		"center_left":
			return Vector2(0.0, VIEWPORT_H * 0.5)
		"center":
			return Vector2(VIEWPORT_W * 0.5, VIEWPORT_H * 0.5)
		"center_right":
			return Vector2(VIEWPORT_W, VIEWPORT_H * 0.5)
		"bottom_left":
			return Vector2(0.0, VIEWPORT_H)
		"bottom_center":
			return Vector2(VIEWPORT_W * 0.5, VIEWPORT_H)
		"bottom_right":
			return Vector2(VIEWPORT_W, VIEWPORT_H)
	return Vector2.ZERO
