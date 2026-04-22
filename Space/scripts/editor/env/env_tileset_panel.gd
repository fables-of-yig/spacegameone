extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EnvTypes = preload("res://Space/scripts/editor/env/env_types.gd")
const BLOCK_SIZE: int = 16

# Right-side panel. Display mode switches on the editor's active_mode:
#   • MODE_COLLISION → 4×4 grid of collision-nibble swatches with labels.
#   • MODE_ENTITIES  → entity type picker column.
#   • MODE_DOORS     → direction picker + scrollable target-room list.
#   • MODE_TILE      → tileset dropdown + import button + scrollable
#                      metatile atlas grid. Each dropdown row has inline
#                      rename/append buttons; right-clicking a tileset
#                      name in the dropdown also triggers append.
# Click dispatching lives in `_gui_input` with branches into the matching
# hit-test array.

var editor: Node = null

var _scroll_y: float = 0.0
var _content_h: float = 0.0
var _import_tab_rect: Rect2 = Rect2()
var _tile_rect_for_cell: Dictionary = {}  # atlas idx -> Rect2
var _tile_drag_selecting: bool = false
var _tile_drag_start_idx: int = -1
var _tile_drag_current_idx: int = -1
# Dropdown selector replacing the numeric tab strip. When _dropdown_open
# is true we draw an overlay list of [{idx, rect, rename_rect, append_rect}]
# on top of the metatile grid.
var _dropdown_button_rect: Rect2 = Rect2()
var _dropdown_open: bool = false
var _dropdown_row_rects: Array = []
var _nibble_rects: Array = []  # [{nibble: int, rect: Rect2}, ...]
var _entity_rects: Array = []  # [{type: String, rect: Rect2}, ...]
var _door_dir_rects: Array = []  # [{dir: String, rect: Rect2}, ...]
var _door_target_rects: Array = []  # [{addr: String, rect: Rect2}, ...]
var _door_overworld_toggle_rect: Rect2 = Rect2()
var _door_target_scroll: float = 0.0
var _door_target_viewport: Rect2 = Rect2()
var _door_target_content_h: float = 0.0


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

    var is_collision: bool = editor.active_mode == EnvTypes.MODE_COLLISION
    var is_entities: bool = editor.active_mode == EnvTypes.MODE_ENTITIES
    var is_doors: bool = editor.active_mode == EnvTypes.MODE_DOORS

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            if is_doors and _door_target_viewport.has_point(mb.position):
                _door_target_scroll = maxf(_door_target_scroll - 24.0, 0.0)
            else:
                _scroll_y = maxf(_scroll_y - 32.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if is_doors and _door_target_viewport.has_point(mb.position):
                var max_t := maxf(_door_target_content_h - _door_target_viewport.size.y, 0.0)
                _door_target_scroll = minf(_door_target_scroll + 24.0, max_t)
            else:
                var max_scroll := maxf(_content_h - size.y + 48.0, 0.0)
                _scroll_y = minf(_scroll_y + 32.0, max_scroll)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
            # Right-click a dropdown row → append PNGs to that tileset
            # (fast path, skips hitting the append button).
            if not is_collision and not is_entities and not is_doors and _dropdown_open:
                for entry in _dropdown_row_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.request_append_to_tileset(int(entry["idx"]))
                        _dropdown_open = false
                        accept_event()
                        return
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if is_doors:
                if _door_overworld_toggle_rect.has_point(mb.position):
                    editor.set_selected_door_send_to_overworld(
                        not bool(editor.selected_door_send_to_overworld))
                    accept_event()
                    return
                for entry in _door_dir_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_door_direction(str(entry["dir"]))
                        accept_event()
                        return
                if _door_target_viewport.has_point(mb.position):
                    if bool(editor.selected_door_send_to_overworld):
                        accept_event()
                        return
                    for entry in _door_target_rects:
                        if (entry["rect"] as Rect2).has_point(mb.position):
                            editor.set_selected_door_target_room(str(entry["addr"]))
                            accept_event()
                            return
                return
            if is_collision:
                for entry in _nibble_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_collision_nibble(int(entry["nibble"]))
                        accept_event()
                        return
                return
            if is_entities:
                for entry in _entity_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_entity_type(str(entry["type"]))
                        accept_event()
                        return
                return
            # Tile mode. Dropdown takes priority when open so its rows
            # can shadow whatever metatile cells sit underneath.
            if _dropdown_open:
                for entry in _dropdown_row_rects:
                    var rename_r: Rect2 = entry["rename_rect"]
                    if rename_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_rename_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var append_r: Rect2 = entry["append_rect"]
                    if append_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_append_to_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var delete_r: Rect2 = entry["delete_rect"]
                    if delete_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_delete_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var row_r: Rect2 = entry["rect"]
                    if row_r.has_point(mb.position):
                        editor.set_selected_tileset(int(entry["idx"]))
                        _dropdown_open = false
                        accept_event()
                        return
                # Click on the dropdown button while open → toggle closed.
                if _dropdown_button_rect.has_point(mb.position):
                    _dropdown_open = false
                    accept_event()
                    return
                # Click anywhere else → close without selecting.
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
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size), Color.WHITE, UIPanels.PanelVariant.DARK)

    var font := ThemeDB.fallback_font
    if editor == null:
        draw_string(font, Vector2(16, 32), "(no editor)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65, 1))
        return

    if editor.active_mode == EnvTypes.MODE_COLLISION:
        _draw_collision_palette(font)
    elif editor.active_mode == EnvTypes.MODE_ENTITIES:
        _draw_entity_palette(font)
    elif editor.active_mode == EnvTypes.MODE_DOORS:
        _draw_door_palette(font)
    else:
        _draw_tile_palette(font)
        # Dropdown overlay is drawn AFTER the picker grid so it sits on
        # top of any metatile cells that would otherwise occlude it.
        if _dropdown_open:
            _draw_tileset_dropdown(font)


func _draw_tile_palette(font: Font) -> void:
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
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

    var current_idx: int = int(editor.selected_tileset_id)
    var current_label: String = "(no tilesets)"
    if not indices.is_empty():
        var name_str := str(editor.get_tileset_name(current_idx))
        current_label = "%s  (%02d)" % [name_str, current_idx]
    draw_string(font, Vector2(dropdown_x + 10, row_y + 17), current_label,
        HORIZONTAL_ALIGNMENT_LEFT, dropdown_w - 28, 12, Color(1, 1, 1, 1))
    # Caret on the right edge.
    var caret_x: float = dropdown_x + dropdown_w - 14.0
    var caret_y: float = row_y + row_h * 0.5
    var caret_pts := PackedVector2Array([
        Vector2(caret_x - 4, caret_y - 2),
        Vector2(caret_x + 4, caret_y - 2),
        Vector2(caret_x, caret_y + 3),
    ])
    draw_colored_polygon(caret_pts, Color(1, 1, 1, 0.92))
    if dd_hover:
        EditorTooltip.show_text("Active tileset. Click to open the dropdown — select another tileset, rename it, or append more tiles to it. The numeric ID in parentheses is the disambiguator when multiple tilesets share a name.")

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
        EditorTooltip.show_text("Create a new tileset from one or more PNGs. Shift/Ctrl-click in the file picker to select a batch — they'll all get stitched into one atlas. Each source's width and height must be multiples of 16. To add MORE tiles to an EXISTING tileset, use the dropdown's \"append\" button.")

    var grid_top: float = row_y + row_h + 14.0

    _tile_rect_for_cell.clear()
    _content_h = 0.0

    var tex: Texture2D = editor.get_tileset_texture(editor.selected_tileset_id)
    if tex == null:
        draw_string(font, Vector2(16, grid_top + 14),
            "(no tileset texture for id %d)" % editor.selected_tileset_id,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.55, 0.55, 1))
        return

    var atlas_w := tex.get_width()
    var atlas_h := tex.get_height()
    if atlas_w <= 0 or atlas_h <= 0:
        return
    # Storage is always 16-px cells; the grid_cols/grid_rows here are the
    # 16-px sub-tile dimensions (which also match MvTileValue's linearized
    # idx layout). A "logical tile" is an N×N sub-tile chunk where
    # N = tile_size / BLOCK_SIZE.
    @warning_ignore("integer_division")
    var grid_cols := atlas_w / BLOCK_SIZE
    @warning_ignore("integer_division")
    var grid_rows := atlas_h / BLOCK_SIZE
    if grid_cols <= 0 or grid_rows <= 0:
        return
    var tile_px: int = int(editor.get_tileset_tile_size(editor.selected_tileset_id))
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

    var panel_inner_x: float = 16.0
    var panel_inner_w: float = size.x - 32.0
    var display_cols: int = maxi(int(panel_inner_w / 32.0), 4)
    display_cols = mini(display_cols, logical_cols)
    var cell_px: float = floorf(panel_inner_w / float(display_cols))
    var cols_per_row: int = display_cols
    var total_logical: int = logical_cols * logical_rows
    var total_rows: int = int(ceilf(float(total_logical) / float(cols_per_row)))
    _content_h = float(total_rows) * cell_px + 60.0

    var max_scroll := maxf(_content_h - (size.y - grid_top - 20.0), 0.0)
    _scroll_y = clampf(_scroll_y, 0.0, max_scroll)

    var panel_rect := Rect2(Vector2(0, grid_top - 2), Vector2(size.x, size.y - grid_top - 4))
    draw_rect(panel_rect, Color(0.04, 0.05, 0.08, 0.85))

    for logical_idx in total_logical:
        @warning_ignore("integer_division")
        var pr := logical_idx / cols_per_row
        var pc := logical_idx % cols_per_row
        var px := panel_inner_x + float(pc) * cell_px
        var py := grid_top + float(pr) * cell_px - _scroll_y
        if py + cell_px < grid_top or py > size.y:
            continue
        var dst := Rect2(Vector2(px, py), Vector2(cell_px, cell_px))
        var l_col := logical_idx % logical_cols
        @warning_ignore("integer_division")
        var l_row := logical_idx / logical_cols
        var src := Rect2(
            Vector2(l_col * tile_px, l_row * tile_px),
            Vector2(tile_px, tile_px))
        draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 1))
        # Key = top-left 16-px sub-tile idx of this logical tile. That's
        # what the editor stores in selected_metatile_idx, so both click
        # dispatch and the selection highlight can match on it directly.
        var top_left_sub_idx: int = (l_row * n_subs) * grid_cols + (l_col * n_subs)
        _tile_rect_for_cell[top_left_sub_idx] = dst

        var mouse_pos2 := get_local_mouse_position()
        var sel_rect := _current_selection_rect(logical_cols, n_subs, grid_cols)
        var selected_start := sel_rect.position
        var selected_size := sel_rect.size
        if l_col >= selected_start.x and l_col < selected_start.x + selected_size.x and l_row >= selected_start.y and l_row < selected_start.y + selected_size.y:
            draw_rect(dst, Color(1, 0.9, 0.3, 1), false, 2.0)
            draw_rect(dst.grow(2), Color(1, 0.95, 0.55, 0.55), false, 1.0)
        elif dst.has_point(mouse_pos2):
            draw_rect(dst, Color(0.5, 0.75, 1.0, 0.85), false, 1.5)
            if n_subs == 1:
                EditorTooltip.show_text("Tile #%d from tileset %d. Click to select it, or drag across multiple tiles to build a larger paint brush." % [top_left_sub_idx, int(editor.selected_tileset_id)])
            else:
                EditorTooltip.show_text("Logical tile at atlas (%d,%d) from tileset %d — %d×%d px, paints as a %d×%d metatile. Drag across multiple logical tiles to build a larger brush." % [int(l_col), int(l_row), int(editor.selected_tileset_id), tile_px, tile_px, n_subs, n_subs])

    var footer_size := _current_selection_rect(logical_cols, n_subs, grid_cols).size
    var footer := "brush: %dx%d logical  (%d×%d px each)" % [footer_size.x, footer_size.y, tile_px, tile_px]
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.65, 0.8, 1))


func _commit_drag_selection() -> void:
    if editor == null or _tile_drag_start_idx < 0:
        return
    var tex: Texture2D = editor.get_tileset_texture(editor.selected_tileset_id)
    if tex == null:
        editor.set_selected_metatile(_tile_drag_start_idx)
        _tile_drag_start_idx = -1
        _tile_drag_current_idx = -1
        return
    var tile_px: int = int(editor.get_tileset_tile_size(editor.selected_tileset_id))
    if tile_px < BLOCK_SIZE:
        tile_px = BLOCK_SIZE
    var n_subs: int = maxi(tile_px / BLOCK_SIZE, 1)
    var grid_cols: int = maxi(tex.get_width() / BLOCK_SIZE, 1)
    var logical_cols: int = maxi(grid_cols / n_subs, 1)
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


func _current_selection_rect(logical_cols: int, n_subs: int, grid_cols: int) -> Rect2i:
    if _tile_drag_selecting and _tile_drag_start_idx >= 0:
        var a := _logical_coord_for_idx(_tile_drag_start_idx, n_subs, grid_cols)
        var b := _logical_coord_for_idx(_tile_drag_current_idx if _tile_drag_current_idx >= 0 else _tile_drag_start_idx, n_subs, grid_cols)
        var min_x := mini(a.x, b.x)
        var min_y := mini(a.y, b.y)
        var max_x := mini(maxi(a.x, b.x), logical_cols - 1)
        var max_y := maxi(a.y, b.y)
        return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))
    var start_idx := int(editor.selected_metatile_idx)
    var start := _logical_coord_for_idx(start_idx, n_subs, grid_cols)
    var span: Vector2i = editor.get_selected_metatile_span()
    return Rect2i(start, Vector2i(maxi(span.x, 1), maxi(span.y, 1)))


func _draw_collision_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _content_h = 0.0
    _scroll_y = 0.0

    var title_y: float = 32.0
    draw_string(font, Vector2(16, title_y), "COLLISION",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(16, title_y + 16), "click to select nibble",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.78, 0.9, 1))

    var mouse_pos := get_local_mouse_position()
    var grid_top: float = title_y + 36.0
    var cols: int = 2
    var pad: float = 16.0
    var gap: float = 6.0
    var cell_w: float = (size.x - pad * 2.0 - gap * float(cols - 1)) / float(cols)
    var cell_h: float = 38.0

    for nibble in range(16):
        var col_i := nibble % cols
        @warning_ignore("integer_division")
        var row_i := nibble / cols
        var x := pad + float(col_i) * (cell_w + gap)
        var y := grid_top + float(row_i) * (cell_h + gap)
        var rect := Rect2(x, y, cell_w, cell_h)
        _nibble_rects.append({"nibble": nibble, "rect": rect})

        var is_active := int(editor.selected_collision_nibble) == nibble
        var is_hover := rect.has_point(mouse_pos)

        var bt_col := EnvTypes.block_type_color(nibble)
        bt_col.a = 1.0
        UIPanels.draw_button_bg(self, rect, is_hover, bt_col.lerp(Color(1, 1, 1, 1), 0.15) if is_active else bt_col)

        var swatch := Rect2(rect.position + Vector2(8, 6), Vector2(cell_h - 12, cell_h - 12))
        draw_rect(swatch, EnvTypes.block_type_color(nibble))
        draw_rect(swatch, Color(0, 0, 0, 0.75), false, 1.0)
        var hex_lbl := "%X" % nibble
        draw_string(font, swatch.position + Vector2(7, cell_h - 18),
            hex_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.1, 1))

        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.9, 0.92, 1.0, 0.9)
        var lbl := EnvTypes.block_type_label(nibble)
        draw_string(font, rect.position + Vector2(swatch.size.x + 16, cell_h * 0.5 + 5),
            lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_col)

        if is_active:
            draw_rect(rect, Color(1, 0.95, 0.35, 1), false, 2.0)

        if is_hover:
            EditorTooltip.show_text("Collision type 0x%X — %s. Click to select, then PAINT this collision nibble onto canvas cells. 0 = empty, 1 = solid block." % [nibble, EnvTypes.block_type_label(nibble)])

    var sel: int = editor.selected_collision_nibble
    var footer := "nibble: 0x%X  %s" % [sel, EnvTypes.block_type_label(sel)]
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.75, 0.75, 1))


func _draw_entity_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _content_h = 0.0
    _scroll_y = 0.0

    var title_y: float = 32.0
    draw_string(font, Vector2(16, title_y), "ENTITIES",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(16, title_y + 16), "click to select type",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.78, 0.9, 1))

    var mouse_pos := get_local_mouse_position()
    var list_top: float = title_y + 36.0
    var pad: float = 16.0
    var row_h: float = 34.0
    var gap: float = 6.0
    var row_w: float = size.x - pad * 2.0

    var types: Array = EnvTypes.ENTITY_TYPES
    for i in types.size():
        var t := str(types[i])
        var y := list_top + float(i) * (row_h + gap)
        var rect := Rect2(pad, y, row_w, row_h)
        _entity_rects.append({"type": t, "rect": rect})

        var is_active := str(editor.selected_entity_type) == t
        var is_hover := rect.has_point(mouse_pos)

        var base := EnvTypes.entity_color(t)
        base.a = 1.0
        var tint: Color
        if is_active:
            tint = base.lerp(Color(1, 1, 1, 1), 0.2)
        else:
            tint = Color(base.r * 0.55, base.g * 0.55, base.b * 0.55, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hover, tint)

        var swatch_r: float = 10.0
        var swatch_center := rect.position + Vector2(20, row_h * 0.5)
        draw_circle(swatch_center, swatch_r, EnvTypes.entity_color(t))
        draw_arc(swatch_center, swatch_r, 0, TAU, 18, Color(0, 0, 0, 0.75), 1.5)

        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.85, 0.9, 1.0, 0.9)
        draw_string(font, rect.position + Vector2(40, row_h * 0.5 + 5),
            EnvTypes.entity_label(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)

        if is_active:
            draw_rect(rect, Color(1, 0.95, 0.35, 1), false, 2.0)

        if is_hover:
            EditorTooltip.show_text("%s Click to select, then click in the canvas to place instances. Room-placed entities now get stable instance IDs so triggers can target them." % EnvTypes.entity_help(t))

    var footer := "type: %s" % EnvTypes.entity_label(str(editor.selected_entity_type))
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.82, 0.95, 1))


func _draw_door_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
    _content_h = 0.0
    _scroll_y = 0.0

    var mouse_pos := get_local_mouse_position()
    var pad: float = 16.0

    draw_string(font, Vector2(pad, 32), "DOORS",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(pad, 48), "click a cell to place",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.85, 0.78, 1))

    draw_string(font, Vector2(pad, 74), "DIRECTION",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var dir_row_y: float = 82.0
    var dir_btn_w: float = (size.x - pad * 2.0 - 12.0) * 0.25
    var dir_btn_h: float = 32.0
    var dirs := [
        {"dir": "up", "glyph": "↑"},
        {"dir": "down", "glyph": "↓"},
        {"dir": "left", "glyph": "←"},
        {"dir": "right", "glyph": "→"},
    ]
    for i in dirs.size():
        var def: Dictionary = dirs[i]
        var rect := Rect2(pad + float(i) * (dir_btn_w + 4.0), dir_row_y, dir_btn_w, dir_btn_h)
        _door_dir_rects.append({"dir": def["dir"], "rect": rect})
        var is_active := str(editor.selected_door_direction) == str(def["dir"])
        var is_hover := rect.has_point(mouse_pos)
        var tint: Color
        if is_active:
            tint = Color(0.4, 0.9, 0.55, 1.0)
        else:
            tint = Color(0.25, 0.45, 0.32, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hover, tint)
        var label_col := Color(1, 1, 1, 1) if is_active else Color(0.75, 0.9, 0.82, 1)
        draw_string(font, rect.position + Vector2(dir_btn_w * 0.5 - 5, dir_btn_h * 0.5 + 7),
            str(def["glyph"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, label_col)
        if is_hover:
            EditorTooltip.show_text("Door exit direction: %s. When the player enters this door, they'll be ejected in this direction in the target room." % str(def["dir"]).to_upper())

    var target_title_y: float = dir_row_y + dir_btn_h + 18.0
    draw_string(font, Vector2(pad, target_title_y), "TARGET ROOM",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var send_to_overworld: bool = bool(editor.selected_door_send_to_overworld)
    var toggle_label := "send to overworld"
    var toggle_font_size := 11
    var toggle_box_size: float = 16.0
    var toggle_gap: float = 6.0
    var toggle_label_w: float = font.get_string_size(toggle_label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, toggle_font_size).x
    var toggle_w: float = toggle_box_size + toggle_gap + toggle_label_w
    var toggle_x: float = maxf(pad + 108.0, size.x - pad - toggle_w)
    var toggle_y: float = target_title_y - 12.0
    _door_overworld_toggle_rect = Rect2(toggle_x, toggle_y, toggle_w, 20.0)
    var toggle_box := Rect2(toggle_x, toggle_y + 2.0, toggle_box_size, toggle_box_size)
    var toggle_hover := _door_overworld_toggle_rect.has_point(mouse_pos)
    draw_rect(toggle_box, Color(0.08, 0.12, 0.16, 0.95))
    draw_rect(toggle_box,
        Color(0.42, 0.86, 1.0, 1.0) if send_to_overworld else Color(0.32, 0.42, 0.5, 0.95),
        false, 2.0)
    if send_to_overworld:
        draw_line(toggle_box.position + Vector2(3.0, 9.0),
            toggle_box.position + Vector2(7.0, 13.0), Color(0.85, 1.0, 1.0, 1.0), 2.0)
        draw_line(toggle_box.position + Vector2(7.0, 13.0),
            toggle_box.position + Vector2(13.0, 4.0), Color(0.85, 1.0, 1.0, 1.0), 2.0)
    draw_string(font, Vector2(toggle_x + toggle_box_size + toggle_gap, target_title_y + 1.0),
        toggle_label, HORIZONTAL_ALIGNMENT_LEFT, -1, toggle_font_size,
        Color(0.86, 0.96, 1.0, 1.0) if send_to_overworld else Color(0.72, 0.82, 0.9, 1.0))
    if toggle_hover:
        EditorTooltip.show_text("When enabled, newly placed doors ignore the room target list and return the player to the overworld.")

    var viewport_top: float = target_title_y + 10.0
    var viewport_bot: float = size.y - 24.0
    _door_target_viewport = Rect2(pad, viewport_top, size.x - pad * 2.0, viewport_bot - viewport_top)
    draw_rect(_door_target_viewport,
        Color(0.04, 0.05, 0.08, 0.5) if send_to_overworld else Color(0.04, 0.05, 0.08, 0.85))

    var addrs: Array = editor.get_room_addrs()
    var options: Array = [""]  # "" = no target
    options.append_array(addrs)

    var row_h: float = 26.0
    var row_gap: float = 4.0
    _door_target_content_h = float(options.size()) * (row_h + row_gap)
    var max_scroll := maxf(_door_target_content_h - _door_target_viewport.size.y, 0.0)
    _door_target_scroll = clampf(_door_target_scroll, 0.0, max_scroll)

    var base_y: float = viewport_top + 4.0 - _door_target_scroll
    for i in options.size():
        var addr := str(options[i])
        var rect := Rect2(pad + 4.0, base_y + float(i) * (row_h + row_gap),
            _door_target_viewport.size.x - 8.0, row_h)
        _door_target_rects.append({"addr": addr, "rect": rect})
        if rect.position.y + row_h < viewport_top or rect.position.y > viewport_bot:
            continue

        var is_active := (not send_to_overworld) and str(editor.selected_door_target_room) == addr
        var is_hover := (not send_to_overworld) and rect.has_point(mouse_pos) and _door_target_viewport.has_point(mouse_pos)

        var bg: Color
        if send_to_overworld:
            bg = Color(0.08, 0.1, 0.12, 0.45)
        elif is_active:
            bg = Color(0.25, 0.5, 0.35, 0.9)
        elif is_hover:
            bg = Color(0.15, 0.22, 0.18, 0.9)
        else:
            bg = Color(0.08, 0.12, 0.12, 0.9)
        draw_rect(rect, bg)

        var text_col: Color
        if send_to_overworld:
            text_col = Color(0.46, 0.54, 0.58, 1.0)
        elif is_active:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.75, 0.88, 0.8, 1)
        var label := "— none —" if addr.is_empty() else addr
        draw_string(font, rect.position + Vector2(8, row_h - 7),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_col)
        if send_to_overworld and _door_target_viewport.has_point(mouse_pos):
            EditorTooltip.show_text("Disable send to overworld to pick a room destination for doors.")
        elif is_hover:
            if addr.is_empty():
                EditorTooltip.show_text("No target. Doors without a target room do nothing — useful for placeholder placement.")
            else:
                EditorTooltip.show_text("Target room %s. Doors placed after selecting this room will take the player there on contact." % addr)

    var sel := str(editor.selected_door_target_room)
    if send_to_overworld:
        sel = "OVERWORLD"
    var footer := "dir: %s  target: %s" % [str(editor.selected_door_direction), "—" if sel.is_empty() else sel]
    draw_string(font, Vector2(pad, size.y - 10),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.92, 0.82, 1))


# Overlay list that appears below the dropdown button. Each row has an
# inline "rename" and "append" button on the right; clicking the row
# anywhere else selects that tileset. Populates _dropdown_row_rects so
# _gui_input can dispatch clicks back.
func _draw_tileset_dropdown(font: Font) -> void:
    _dropdown_row_rects.clear()
    var indices: Array = editor.get_tileset_indices()
    if indices.is_empty():
        return

    var list_x: float = _dropdown_button_rect.position.x
    var list_w: float = _dropdown_button_rect.size.x
    var list_top: float = _dropdown_button_rect.position.y + _dropdown_button_rect.size.y + 2.0
    var row_h: float = 28.0
    var btn_pad: float = 4.0
    var btn_w: float = 52.0
    var delete_btn_w: float = 26.0
    var list_h: float = float(indices.size()) * row_h + btn_pad * 2.0
    var list_rect := Rect2(list_x, list_top, list_w, list_h)

    # Opaque backdrop so whatever sits underneath (metatile grid) can't
    # bleed through and confuse the hit test.
    draw_rect(list_rect, Color(0.07, 0.09, 0.14, 0.98))
    draw_rect(list_rect, Color(0.5, 0.65, 0.9, 0.9), false, 1.0)

    var mouse_pos := get_local_mouse_position()
    for i in indices.size():
        var idx: int = int(indices[i])
        var row_y: float = list_top + btn_pad + float(i) * row_h
        var row_rect := Rect2(list_x + btn_pad, row_y, list_w - btn_pad * 2.0, row_h - 2.0)
        # Button strip on the right edge: [rename] [append] [X].
        var delete_rect := Rect2(row_rect.position.x + row_rect.size.x - delete_btn_w,
            row_rect.position.y + 3.0, delete_btn_w, row_rect.size.y - 6.0)
        var append_rect := Rect2(delete_rect.position.x - btn_w - 4.0,
            row_rect.position.y + 3.0, btn_w, row_rect.size.y - 6.0)
        var rename_rect := Rect2(append_rect.position.x - btn_w - 4.0,
            row_rect.position.y + 3.0, btn_w, row_rect.size.y - 6.0)

        _dropdown_row_rects.append({
            "idx": idx,
            "rect": row_rect,
            "rename_rect": rename_rect,
            "append_rect": append_rect,
            "delete_rect": delete_rect,
        })

        var is_active: bool = (idx == int(editor.selected_tileset_id))
        var row_hover := row_rect.has_point(mouse_pos) \
                and not rename_rect.has_point(mouse_pos) \
                and not append_rect.has_point(mouse_pos) \
                and not delete_rect.has_point(mouse_pos)
        var row_bg: Color
        if is_active:
            row_bg = Color(0.2, 0.35, 0.55, 0.95)
        elif row_hover:
            row_bg = Color(0.15, 0.22, 0.32, 0.95)
        else:
            row_bg = Color(0.09, 0.12, 0.18, 0.95)
        draw_rect(row_rect, row_bg)

        var name_str: String = str(editor.get_tileset_name(idx))
        var label := "%s  (%02d)" % [name_str, idx]
        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.85, 0.92, 1.0, 1)
        var label_w: float = rename_rect.position.x - row_rect.position.x - 12.0
        draw_string(font, row_rect.position + Vector2(10, 18), label,
            HORIZONTAL_ALIGNMENT_LEFT, label_w, 12, label_col)

        var rename_hover := rename_rect.has_point(mouse_pos)
        var rename_tint: Color
        if rename_hover:
            rename_tint = Color(0.55, 0.7, 0.95, 1.0)
        else:
            rename_tint = Color(0.28, 0.38, 0.55, 1.0)
        UIPanels.draw_button_bg(self, rename_rect, rename_hover, rename_tint)
        draw_string(font, rename_rect.position + Vector2(6, 16), "rename",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1))
        if rename_hover:
            EditorTooltip.show_text("Rename tileset %02d. Only the display label changes — the numeric ID and every tile painted against it stay stable." % idx)

        var append_hover := append_rect.has_point(mouse_pos)
        var append_tint: Color
        if append_hover:
            append_tint = Color(0.55, 0.95, 0.65, 1.0)
        else:
            append_tint = Color(0.3, 0.6, 0.4, 1.0)
        UIPanels.draw_button_bg(self, append_rect, append_hover, append_tint)
        draw_string(font, append_rect.position + Vector2(8, 16), "append",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1))
        if append_hover:
            EditorTooltip.show_text("Append PNG(s) to tileset %02d. Uses this tileset's existing tile size — the file picker opens to grab more source art. Existing tile indices stay stable so your painted rooms don't shift." % idx)

        var delete_hover := delete_rect.has_point(mouse_pos)
        var delete_tint: Color
        if delete_hover:
            delete_tint = Color(1.0, 0.45, 0.4, 1.0)
        else:
            delete_tint = Color(0.72, 0.18, 0.16, 1.0)
        UIPanels.draw_button_bg(self, delete_rect, delete_hover, delete_tint)
        # Draw a centered X glyph out of two lines so the button reads as
        # a destructive action at a glance.
        var x_center := delete_rect.position + delete_rect.size * 0.5
        var x_arm: float = 5.0
        var x_col := Color(1, 1, 1, 1)
        draw_line(x_center + Vector2(-x_arm, -x_arm),
            x_center + Vector2(x_arm, x_arm), x_col, 2.0)
        draw_line(x_center + Vector2(-x_arm, x_arm),
            x_center + Vector2(x_arm, -x_arm), x_col, 2.0)
        if delete_hover:
            EditorTooltip.show_text("Delete tileset %02d. You'll get a confirmation prompt first. Any rooms that painted cells from this tileset will render those cells as empty until you repaint them — the tile data isn't rewritten." % idx)
