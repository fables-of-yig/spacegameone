extends Control

const RlmTypes = preload("res://Space/scripts/editor/rlm/rlm_types.gd")
const BLOCK_SIZE: int = 16

var editor: Node = null

var cam_offset: Vector2 = Vector2(32, 32)
var zoom: float = 2.0

var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO
var _painting: bool = false
var _erasing: bool = false
var _copy_selecting: bool = false
var _copy_start_cell: Vector2i = Vector2i(-1, -1)
var _copy_end_cell: Vector2i = Vector2i(-1, -1)
var _copied_rect: Rect2i = Rect2i()
var _last_painted_cell: Vector2i = Vector2i(-1, -1)
var _hover_cell: Vector2i = Vector2i(-1, -1)


func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)


func _process(_delta):
	queue_redraw()


func _gui_input(event):
	if editor == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_last = mb.position
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.ctrl_pressed:
					_copy_selecting = true
					_copy_start_cell = _screen_to_cell(mb.position)
					_copy_end_cell = _copy_start_cell
					accept_event()
					return
				_painting = true
				_last_painted_cell = Vector2i(-1, -1)
				editor.begin_stroke()
				_apply_tool_at(mb.position, false)
			else:
				if _copy_selecting:
					_copy_selecting = false
					_copy_end_cell = _screen_to_cell(mb.position)
					_copied_rect = _normalized_cell_rect(_copy_start_cell, _copy_end_cell)
					editor.copy_realm_region(_copied_rect)
					accept_event()
					return
				_painting = false
				editor.end_stroke()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_erasing = true
				_last_painted_cell = Vector2i(-1, -1)
				editor.begin_stroke()
				_apply_tool_at(mb.position, true)
			else:
				_erasing = false
				editor.end_stroke()
			accept_event()
			return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			cam_offset += mm.position - _pan_last
			_pan_last = mm.position
			accept_event()
			return
		_hover_cell = _screen_to_cell(mm.position)
		if _copy_selecting:
			_copy_end_cell = _hover_cell
		elif _painting:
			_apply_tool_at(mm.position, false)
		elif _erasing:
			_apply_tool_at(mm.position, true)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world_before := (screen_pos - cam_offset) / zoom
	zoom = clampf(zoom * factor, 0.5, 8.0)
	var world_after := (screen_pos - cam_offset) / zoom
	cam_offset += (world_after - world_before) * zoom


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var world := (screen_pos - cam_offset) / zoom
	return Vector2i(floori(world.x / float(BLOCK_SIZE)), floori(world.y / float(BLOCK_SIZE)))


func _cell_to_screen(col: int, row: int) -> Vector2:
	return cam_offset + Vector2(float(col * BLOCK_SIZE), float(row * BLOCK_SIZE)) * zoom


func _apply_tool_at(screen_pos: Vector2, erase: bool) -> void:
	if editor == null:
		return
	if not erase and editor.has_method("has_realm_paste_preview") and editor.has_realm_paste_preview():
		var paste_cell := _screen_to_cell(screen_pos)
		editor.paste_realm_clipboard(paste_cell.x, paste_cell.y)
		return
	var cell := _screen_to_cell(screen_pos)
	if cell == _last_painted_cell:
		return
	_last_painted_cell = cell
	var grid_w: int = editor.realm_grid_w()
	var grid_h: int = editor.realm_grid_h()
	if cell.x < 0 or cell.x >= grid_w or cell.y < 0 or cell.y >= grid_h:
		return
	if erase:
		editor.erase_realm_cell(cell.x, cell.y)
	elif editor.active_tool == RlmTypes.TOOL_PICK:
		editor.pick_realm_cell(cell.x, cell.y)
	elif editor.active_tool == RlmTypes.TOOL_FILL:
		editor.fill_realm_cells(cell.x, cell.y)
	else:
		editor.paint_realm_cell(cell.x, cell.y)


func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.12, 1.0))

	if editor == null:
		return

	var grid_w: int = editor.realm_grid_w()
	var grid_h: int = editor.realm_grid_h()
	if grid_w <= 0 or grid_h <= 0:
		return

	_draw_grid_background(grid_w, grid_h)

	var layers: Array = editor.get_realm_tile_layers()
	var active_layer: int = editor.active_realm_layer
	for i in layers.size():
		if i >= 3:
			break
		var layer_v: Variant = layers[i]
		if typeof(layer_v) != TYPE_DICTIONARY:
			continue
		var tiles: Array = (layer_v as Dictionary).get("tiles", [])
		var alpha: float
		if i == active_layer:
			alpha = 1.0
		elif i < active_layer:
			alpha = 0.35
		else:
			alpha = RlmTypes.layer_alpha(i) * 0.5
		_draw_realm_tile_layer(tiles, alpha)

	_draw_region_overlays()
	_draw_grid_lines(grid_w, grid_h)
	_draw_copy_selection(grid_w, grid_h)
	_draw_paste_preview(grid_w, grid_h)
	_draw_hover_marker(grid_w, grid_h)

	if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		var info := "Layer: %s | " % RlmTypes.layer_name(active_layer)
		if _hover_cell.x >= 0 and _hover_cell.x < grid_w and _hover_cell.y >= 0 and _hover_cell.y < grid_h:
			info += "Cell (%d, %d)" % [_hover_cell.x, _hover_cell.y]
		EditorTooltip.show_text(info + "\nMMB drag to pan, wheel to zoom. Drag in the palette to build a larger brush. LMB paints, RMB erases. Ctrl-drag copies a region; Ctrl-V pastes it.")


func copy_selection_to_clipboard() -> bool:
	if editor == null or _copied_rect.size.x <= 0 or _copied_rect.size.y <= 0:
		return false
	return editor.copy_realm_region(_copied_rect)


func _normalized_cell_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var min_x := mini(a.x, b.x)
	var min_y := mini(a.y, b.y)
	var max_x := maxi(a.x, b.x)
	var max_y := maxi(a.y, b.y)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _draw_copy_selection(grid_w: int, grid_h: int) -> void:
	var rect := Rect2i()
	if _copy_selecting:
		rect = _normalized_cell_rect(_copy_start_cell, _copy_end_cell)
	elif _copied_rect.size.x > 0 and _copied_rect.size.y > 0:
		rect = _copied_rect
	else:
		return
	_draw_cell_rect_outline(rect, grid_w, grid_h, Color(0.45, 0.9, 1.0, 0.95), Color(0.45, 0.9, 1.0, 0.15))


func _draw_paste_preview(grid_w: int, grid_h: int) -> void:
	if editor == null or not editor.has_method("has_realm_paste_preview") or not editor.has_realm_paste_preview():
		return
	if _hover_cell.x < 0 or _hover_cell.y < 0:
		return
	var size_cells: Vector2i = editor.get_realm_clipboard_size()
	if size_cells.x <= 0 or size_cells.y <= 0:
		return
	var rect := Rect2i(_hover_cell, size_cells)
	_draw_cell_rect_outline(rect, grid_w, grid_h, Color(0.55, 1.0, 0.45, 0.95), Color(0.55, 1.0, 0.45, 0.14))


func _draw_cell_rect_outline(rect: Rect2i, grid_w: int, grid_h: int, stroke: Color, fill: Color) -> void:
	var clamped_pos := Vector2i(clampi(rect.position.x, 0, grid_w), clampi(rect.position.y, 0, grid_h))
	var clamped_end := Vector2i(clampi(rect.end.x, 0, grid_w), clampi(rect.end.y, 0, grid_h))
	var clipped := Rect2i(clamped_pos, clamped_end - clamped_pos)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	var top_left := _cell_to_screen(clipped.position.x, clipped.position.y)
	var bot_right := _cell_to_screen(clipped.end.x, clipped.end.y)
	var draw_rect2 := Rect2(top_left, bot_right - top_left)
	draw_rect(draw_rect2, fill)
	draw_rect(draw_rect2, stroke, false, 2.0)


func _draw_grid_background(grid_w: int, grid_h: int) -> void:
	var top_left := _cell_to_screen(0, 0)
	var bot_right := _cell_to_screen(grid_w, grid_h)
	var grid_rect := Rect2(top_left, bot_right - top_left)
	draw_rect(grid_rect, Color(0.03, 0.04, 0.07, 1.0))
	draw_rect(grid_rect, Color(0.35, 0.5, 0.75, 0.8), false, 2.0)


func _draw_realm_tile_layer(tiles: Array, alpha: float) -> void:
	if tiles.is_empty():
		return
	var cell_size := float(BLOCK_SIZE) * zoom
	for entry_v in tiles:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var col: int = int(entry.get("col", 0))
		var row: int = int(entry.get("row", 0))
		var tileset_id: String = str(entry.get("tileset", ""))
		var atlas_x: int = int(entry.get("atlas_x", 0))
		var atlas_y: int = int(entry.get("atlas_y", 0))
		var tex: Texture2D = editor.get_tileset_texture_by_name(tileset_id)
		if tex == null:
			var fallback_col := Color(0.4, 0.3, 0.5, alpha)
			draw_rect(Rect2(_cell_to_screen(col, row), Vector2(cell_size, cell_size)), fallback_col)
			continue
		var src_rect := Rect2(
			Vector2(float(atlas_x * BLOCK_SIZE), float(atlas_y * BLOCK_SIZE)),
			Vector2(float(BLOCK_SIZE), float(BLOCK_SIZE)))
		var dst_pos := _cell_to_screen(col, row)
		var dst_rect := Rect2(dst_pos, Vector2(cell_size, cell_size))
		draw_texture_rect_region(tex, dst_rect, src_rect, Color(1, 1, 1, alpha))


func _draw_region_overlays() -> void:
	var cell_size := float(BLOCK_SIZE) * zoom
	var regions: Array = editor.get_realm_regions()
	var font := ThemeDB.fallback_font
	for entry_v in regions:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var col: int = int(entry.get("col", 0))
		var row: int = int(entry.get("row", 0))
		var rname := str(entry.get("name", str(entry.get("id", "?"))))
		var pos := _cell_to_screen(col, row)
		var rect := Rect2(pos, Vector2(cell_size, cell_size))
		draw_rect(rect, Color(0.3, 0.85, 0.5, 0.25))
		draw_rect(rect, Color(0.3, 0.85, 0.5, 0.7), false, 2.0)
		if zoom >= 1.5:
			var label_size: int = clampi(int(8.0 * zoom), 8, 14)
			draw_string(font, pos + Vector2(3, float(label_size) + 2),
				rname, HORIZONTAL_ALIGNMENT_LEFT, cell_size - 4, label_size,
				Color(0.9, 1.0, 0.9, 0.9))


func _draw_grid_lines(grid_w: int, grid_h: int) -> void:
	if zoom < 1.0:
		return
	var line_col := Color(0.2, 0.25, 0.35, 0.3)
	var cell_size := float(BLOCK_SIZE) * zoom
	var tl := _cell_to_screen(0, 0)
	var br := _cell_to_screen(grid_w, grid_h)
	for c in grid_w + 1:
		var x := tl.x + float(c) * cell_size
		draw_line(Vector2(x, tl.y), Vector2(x, br.y), line_col, 1.0)
	for r in grid_h + 1:
		var y := tl.y + float(r) * cell_size
		draw_line(Vector2(tl.x, y), Vector2(br.x, y), line_col, 1.0)


func _draw_hover_marker(grid_w: int, grid_h: int) -> void:
	if _hover_cell.x < 0 or _hover_cell.x >= grid_w:
		return
	if _hover_cell.y < 0 or _hover_cell.y >= grid_h:
		return
	var cell_size := float(BLOCK_SIZE) * zoom
	var pos := _cell_to_screen(_hover_cell.x, _hover_cell.y)
	draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color(1, 1, 1, 0.2))
	draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color(1, 1, 1, 0.6), false, 1.0)
