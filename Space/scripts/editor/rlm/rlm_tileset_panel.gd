extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const BLOCK_SIZE: int = 16

var editor: Node = null

var _scroll_y: float = 0.0
var _content_h: float = 0.0
var _dropdown_button_rect: Rect2 = Rect2()
var _import_tab_rect: Rect2 = Rect2()
var _dropdown_open: bool = false
var _dropdown_row_rects: Array = []
var _tile_rect_for_cell: Dictionary = {}
var _tile_drag_selecting: bool = false
var _tile_drag_start_idx: int = -1
var _tile_drag_current_idx: int = -1


func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)


func _process(_delta):
	queue_redraw()


func close_dropdown_if_open() -> bool:
	if _dropdown_open:
		_dropdown_open = false
		return true
	return false


func _gui_input(event):
	if editor == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_y = maxf(_scroll_y - 32.0, 0.0)
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var max_scroll := maxf(_content_h - size.y + 48.0, 0.0)
			_scroll_y = minf(_scroll_y + 32.0, max_scroll)
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _dropdown_open:
				for entry in _dropdown_row_rects:
					var row_r: Rect2 = entry["rect"]
					if row_r.has_point(mb.position):
						editor.set_selected_tileset(int(entry["idx"]))
						_dropdown_open = false
						accept_event()
						return
				if _dropdown_button_rect.has_point(mb.position):
					_dropdown_open = false
					accept_event()
					return
				_dropdown_open = false
				accept_event()
				return
			if _dropdown_button_rect.has_point(mb.position):
				_dropdown_open = true
				accept_event()
				return
			if _import_tab_rect.has_point(mb.position):
				editor.request_import_tileset()
				accept_event()
				return
			for idx in _tile_rect_for_cell.keys():
				var r: Rect2 = _tile_rect_for_cell[idx]
				if r.has_point(mb.position):
					_tile_drag_selecting = true
					_tile_drag_start_idx = int(idx)
					_tile_drag_current_idx = int(idx)
					accept_event()
					return
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _tile_drag_selecting:
			_tile_drag_selecting = false
			_commit_drag_selection()
			accept_event()
			return
	elif event is InputEventMouseMotion and _tile_drag_selecting:
		var mm := event as InputEventMouseMotion
		for idx in _tile_rect_for_cell.keys():
			var r: Rect2 = _tile_rect_for_cell[idx]
			if r.has_point(mm.position):
				_tile_drag_current_idx = int(idx)
				break
		accept_event()
		return


func _draw():
	UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
		Color.WHITE, UIPanels.PanelVariant.DARK)

	var font := ThemeDB.fallback_font
	if editor == null:
		draw_string(font, Vector2(16, 32), "(no editor)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65, 1))
		return

	_draw_tile_palette(font)
	if _dropdown_open:
		_draw_tileset_dropdown(font)


func _draw_tile_palette(font: Font) -> void:
	_dropdown_row_rects.clear()

	var title_y: float = 32.0
	draw_string(font, Vector2(16, title_y), "TILESET",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)

	var indices: Array = editor.get_tileset_indices()
	var row_y: float = title_y + 12.0
	var row_h: float = 26.0
	var btn_gap: float = 6.0
	var import_btn_w: float = 30.0
	var dropdown_x: float = 16.0
	var dropdown_w: float = size.x - 32.0 - import_btn_w - btn_gap
	_dropdown_button_rect = Rect2(dropdown_x, row_y, dropdown_w, row_h)
	var mouse_pos := get_local_mouse_position()
	var dd_hover := _dropdown_button_rect.has_point(mouse_pos)
	var dd_tint: Color
	if _dropdown_open:
		dd_tint = Color(0.45, 0.88, 1.0, 1.0)
	elif dd_hover:
		dd_tint = Color(0.5, 0.65, 0.9, 1.0)
	else:
		dd_tint = Color(0.32, 0.42, 0.58, 1.0)
	UIPanels.draw_button_bg(self, _dropdown_button_rect, dd_hover, dd_tint)

	var current_idx: int = editor.selected_realm_tileset
	var current_label: String = "(no tilesets)"
	if not indices.is_empty():
		var name_str := str(editor.get_tileset_name(current_idx))
		current_label = "%s  (%02d)" % [name_str, current_idx]
	draw_string(font, Vector2(dropdown_x + 10, row_y + 17), current_label,
		HORIZONTAL_ALIGNMENT_LEFT, dropdown_w - 28, 12, Color(1, 1, 1, 1))

	var caret_x: float = dropdown_x + dropdown_w - 14.0
	var caret_y: float = row_y + row_h * 0.5
	var caret_pts := PackedVector2Array([
		Vector2(caret_x - 4, caret_y - 2),
		Vector2(caret_x + 4, caret_y - 2),
		Vector2(caret_x, caret_y + 3),
	])
	draw_colored_polygon(caret_pts, Color(1, 1, 1, 0.92))

	if dd_hover:
		EditorTooltip.show_text("Active tileset for the realm canvas. Click to pick a different tileset — the tile grid below updates to show its cells.")

	_import_tab_rect = Rect2(dropdown_x + dropdown_w + btn_gap, row_y, import_btn_w, row_h)
	var import_hover := _import_tab_rect.has_point(mouse_pos)
	var import_tint: Color
	if import_hover:
		import_tint = Color(0.55, 0.95, 0.65, 1.0)
	else:
		import_tint = Color(0.3, 0.6, 0.4, 1.0)
	UIPanels.draw_button_bg(self, _import_tab_rect, import_hover, import_tint)
	draw_string(font, _import_tab_rect.position + Vector2(11, 18), "+",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 1))
	if import_hover:
		EditorTooltip.show_text("Import PNG(s) as a new tileset. Shift/Ctrl-click in the file picker to select a batch — they get stitched into one atlas. Width and height must be multiples of 16. The realm editor shares tilesets with the environment editor, so imports show up in both.")

	var grid_top: float = row_y + row_h + 14.0

	_tile_rect_for_cell.clear()
	_content_h = 0.0

	var tex: Texture2D = editor.get_tileset_texture(current_idx)
	if tex == null:
		draw_string(font, Vector2(16, grid_top + 14),
			"(no tileset)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.7, 0.55, 0.55, 1))
		return

	var atlas_w := tex.get_width()
	var atlas_h := tex.get_height()
	if atlas_w <= 0 or atlas_h <= 0:
		return

	@warning_ignore("integer_division")
	var grid_cols := atlas_w / BLOCK_SIZE
	@warning_ignore("integer_division")
	var grid_rows := atlas_h / BLOCK_SIZE
	if grid_cols <= 0 or grid_rows <= 0:
		return

	var tile_px: int = int(editor.get_tileset_tile_size(current_idx))
	if tile_px < BLOCK_SIZE:
		tile_px = BLOCK_SIZE
	@warning_ignore("integer_division")
	var n_subs: int = tile_px / BLOCK_SIZE
	if n_subs <= 0:
		n_subs = 1
	@warning_ignore("integer_division")
	var logical_cols := grid_cols / n_subs
	@warning_ignore("integer_division")
	var logical_rows := grid_rows / n_subs
	if logical_cols <= 0 or logical_rows <= 0:
		return

	var avail_w: float = size.x - 32.0
	var cell_draw_size := floorf(avail_w / float(logical_cols))
	cell_draw_size = clampf(cell_draw_size, 8.0, 48.0)
	var max_scroll := maxf(grid_top + float(logical_rows) * cell_draw_size + 16.0 - size.y, 0.0)
	_scroll_y = clampf(_scroll_y, 0.0, max_scroll)

	var selection_rect := _current_selection_rect(n_subs, grid_cols)
	for gy in logical_rows:
		for gx in logical_cols:
			var linear_idx: int = (gy * n_subs) * grid_cols + (gx * n_subs)
			var draw_x: float = 16.0 + float(gx) * cell_draw_size
			var draw_y: float = grid_top + float(gy) * cell_draw_size - _scroll_y
			if draw_y + cell_draw_size < grid_top or draw_y > size.y:
				continue
			var src_rect := Rect2(
				float(gx * n_subs) * BLOCK_SIZE,
				float(gy * n_subs) * BLOCK_SIZE,
				float(n_subs) * BLOCK_SIZE,
				float(n_subs) * BLOCK_SIZE)
			var dst_rect := Rect2(Vector2(draw_x, draw_y), Vector2(cell_draw_size, cell_draw_size))
			draw_texture_rect_region(tex, dst_rect, src_rect)
			_tile_rect_for_cell[linear_idx] = dst_rect
			var is_selected := gx >= selection_rect.position.x and gx < selection_rect.position.x + selection_rect.size.x and gy >= selection_rect.position.y and gy < selection_rect.position.y + selection_rect.size.y
			if is_selected:
				draw_rect(dst_rect, Color(1, 1, 0.3, 0.8), false, 2.0)
				draw_rect(dst_rect.grow(2), Color(1, 0.95, 0.55, 0.45), false, 1.0)
			elif dst_rect.has_point(mouse_pos):
				draw_rect(dst_rect, Color(0.5, 0.75, 1.0, 0.85), false, 1.5)
			if dst_rect.has_point(mouse_pos):
				EditorTooltip.show_text("Tile #%d from the active tileset. Click to select it, or drag across multiple tiles to build a larger realm brush." % linear_idx)

	_content_h = grid_top + float(logical_rows) * cell_draw_size + 16.0
	var footer := "brush: %dx%d logical" % [selection_rect.size.x, selection_rect.size.y]
	draw_string(font, Vector2(16, size.y - 12),
		footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.65, 0.8, 1))


func _commit_drag_selection() -> void:
	if editor == null or _tile_drag_start_idx < 0:
		return
	var tex: Texture2D = editor.get_tileset_texture(editor.selected_realm_tileset)
	if tex == null:
		editor.set_selected_metatile(_tile_drag_start_idx)
		_tile_drag_start_idx = -1
		_tile_drag_current_idx = -1
		return
	var tile_px: int = int(editor.get_tileset_tile_size(editor.selected_realm_tileset))
	if tile_px < BLOCK_SIZE:
		tile_px = BLOCK_SIZE
	var n_subs: int = maxi(tile_px / BLOCK_SIZE, 1)
	var grid_cols: int = maxi(tex.get_width() / BLOCK_SIZE, 1)
	var a := _logical_coord_for_idx(_tile_drag_start_idx, n_subs, grid_cols)
	var b := _logical_coord_for_idx(_tile_drag_current_idx if _tile_drag_current_idx >= 0 else _tile_drag_start_idx, n_subs, grid_cols)
	var min_x := mini(a.x, b.x)
	var min_y := mini(a.y, b.y)
	var max_x := maxi(a.x, b.x)
	var max_y := maxi(a.y, b.y)
	var anchor_idx := (min_y * n_subs) * grid_cols + (min_x * n_subs)
	editor.set_selected_metatile_block(anchor_idx, max_x - min_x + 1, max_y - min_y + 1)
	_tile_drag_start_idx = -1
	_tile_drag_current_idx = -1


func _logical_coord_for_idx(idx: int, n_subs: int, grid_cols: int) -> Vector2i:
	var sub_col := idx % grid_cols
	var sub_row := idx / grid_cols
	return Vector2i(sub_col / n_subs, sub_row / n_subs)


func _current_selection_rect(n_subs: int, grid_cols: int) -> Rect2i:
	if _tile_drag_selecting and _tile_drag_start_idx >= 0:
		var a := _logical_coord_for_idx(_tile_drag_start_idx, n_subs, grid_cols)
		var b := _logical_coord_for_idx(_tile_drag_current_idx if _tile_drag_current_idx >= 0 else _tile_drag_start_idx, n_subs, grid_cols)
		return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(abs(a.x - b.x) + 1, abs(a.y - b.y) + 1))
	var start := _logical_coord_for_idx(int(editor.selected_realm_tile), n_subs, grid_cols)
	var span: Vector2i = editor.get_selected_realm_tile_span()
	return Rect2i(start, Vector2i(maxi(span.x, 1), maxi(span.y, 1)))


func _draw_tileset_dropdown(font: Font) -> void:
	_dropdown_row_rects.clear()
	var indices: Array = editor.get_tileset_indices()
	if indices.is_empty():
		return
	var dd_x: float = _dropdown_button_rect.position.x
	var dd_w: float = _dropdown_button_rect.size.x
	var row_h: float = 26.0
	var y: float = _dropdown_button_rect.position.y + _dropdown_button_rect.size.y
	var bg_h: float = float(indices.size()) * row_h + 4.0
	draw_rect(Rect2(dd_x, y, dd_w, bg_h), Color(0.08, 0.1, 0.16, 0.97))
	draw_rect(Rect2(dd_x, y, dd_w, bg_h), Color(0.4, 0.55, 0.85, 1), false, 1.0)
	var mouse_pos := get_local_mouse_position()
	for idx in indices:
		var i := int(idx)
		var row_rect := Rect2(dd_x + 2, y + 2, dd_w - 4, row_h - 4)
		_dropdown_row_rects.append({"idx": i, "rect": row_rect})
		var hover := row_rect.has_point(mouse_pos)
		var bg_col: Color
		if i == editor.selected_realm_tileset:
			bg_col = Color(0.25, 0.4, 0.65, 1)
		elif hover:
			bg_col = Color(0.18, 0.25, 0.4, 1)
		else:
			bg_col = Color(0.1, 0.13, 0.2, 1)
		draw_rect(row_rect, bg_col)
		var name_str := str(editor.get_tileset_name(i))
		var label := "%s  (%02d)" % [name_str, i]
		draw_string(font, Vector2(row_rect.position.x + 10, row_rect.position.y + 16),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 1, 1))
		if hover:
			EditorTooltip.show_text("Select tileset \"%s\" (#%02d) for the realm canvas." % [name_str, i])
		y += row_h
