extends Control

# Region editor. Draws a grid of cells, lets the user build rooms with
# rectangle-drag (LMB adds cells, RMB subtracts). A pending selection can
# accumulate multiple rects before the user commits with the confirm panel.
#
# Mouse vocabulary on the grid canvas:
#   LMB drag on empty cells → add rectangle to pending selection
#   RMB drag on any cells   → subtract rectangle from pending selection
#   LMB click on a room     → select (shows detail in sidebar)
#   LMB double-click a room → open that room in the env editor
#   ESC                     → cancel pending, or back to the POI panel
#
# No pan / zoom — the region grid scales to fit the canvas rect.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const RegIO = preload("res://Space/scripts/editor/reg/reg_io.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")
const ContentReferenceRefactor = preload("res://Space/scripts/editor/content_reference_refactor.gd")


@warning_ignore("unused_signal")
signal closed
signal back_to_pack
signal room_chosen(region_id: String, room_addr: String)

enum Mode { IDLE, DRAWING_ADD, DRAWING_SUB, PENDING }

const TOPBAR_H: float = 64.0
const SIDEBAR_W: float = 300.0
const CONFIRM_H: float = 72.0
const DOUBLE_CLICK_DELAY: float = 0.35

var pack_id: String = ""
var region_id: String = ""
var region_meta: Dictionary = {}
var rooms_data: Dictionary = {}

var _mode: int = Mode.IDLE
var _drag_start: Vector2i = Vector2i.ZERO
var _drag_current: Vector2i = Vector2i.ZERO
var _pending_cells: Dictionary = {}
var _cell_to_room: Dictionary = {}
var _selected_room: String = ""
var _last_click_time: float = 0.0
var _last_click_room: String = ""
var _skip_close_frame: bool = false

var _canvas_rect: Rect2 = Rect2()
var _cell_px: Vector2 = Vector2.ZERO
var _grid_origin: Vector2 = Vector2.ZERO

var _back_rect: Rect2 = Rect2()
var _save_rect: Rect2 = Rect2()
var _tooltips_rect: Rect2 = Rect2()
var _confirm_yes_rect: Rect2 = Rect2()
var _confirm_no_rect: Rect2 = Rect2()

var _name_edit: LineEdit = null
var _region_edits: Dictionary = {}
var _undo: RefCounted = null

const REGION_FIELDS: Array = [
    {"key": "music_id", "label": "Music ID", "kind": "string", "hint": "audio pack id, e.g. 'cave_theme'"},
    {"key": "encounter_id", "label": "Encounter ID", "kind": "string", "hint": "optional encounter to queue on landing"},
    {"key": "visual_theme", "label": "Visual Theme", "kind": "string", "hint": "e.g. 'neon', 'ruin'"},
    {"key": "hazard_type", "label": "Hazard", "kind": "string", "hint": "e.g. 'lava', 'toxic'"},
    {"key": "gravity_mult", "label": "Gravity Mult", "kind": "float", "hint": "1.0 = normal"},
]


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    set_process(true)
    visible = false

    _name_edit = LineEdit.new()
    _name_edit.visible = false
    _name_edit.placeholder_text = "room name"
    _name_edit.text_submitted.connect(_on_name_submitted)
    _name_edit.focus_exited.connect(_on_name_focus_exited)
    add_child(_name_edit)

    for field in REGION_FIELDS:
        var key := str(field.get("key", ""))
        var edit := LineEdit.new()
        edit.visible = false
        edit.placeholder_text = str(field.get("hint", ""))
        edit.text_submitted.connect(_on_region_field_submitted.bind(key))
        edit.focus_exited.connect(_on_region_field_focus_exited.bind(key))
        add_child(edit)
        _region_edits[key] = edit

    _undo = EditorUndo.new(_capture_state, _apply_state)


func _process(_delta):
    if visible:
        queue_redraw()


func open_editor(p_pack_id: String, p_region_id: String) -> void:
    pack_id = p_pack_id
    region_id = p_region_id
    _skip_close_frame = true
    visible = true
    _selected_room = ""
    _reload()
    _reset_selection()
    if _name_edit != null:
        _name_edit.visible = false
    queue_redraw()


func _reload() -> void:
    region_meta = RegIO.load_region(pack_id, region_id)
    rooms_data = RegIO.load_region_rooms(pack_id, region_id)
    _rebuild_cell_index()
    if _undo != null:
        _undo.clear()


func _capture_state() -> Dictionary:
    return {
        "region_meta": region_meta.duplicate(true),
        "rooms_data": rooms_data.duplicate(true),
    }


func _apply_state(snap: Dictionary) -> void:
    var rm_v: Variant = snap.get("region_meta", null)
    if typeof(rm_v) == TYPE_DICTIONARY:
        region_meta = rm_v
    var rd_v: Variant = snap.get("rooms_data", null)
    if typeof(rd_v) == TYPE_DICTIONARY:
        rooms_data = rd_v
    _rebuild_cell_index()
    _save_all()
    queue_redraw()


func _rebuild_cell_index() -> void:
    _cell_to_room.clear()
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return
    for key in (rooms_v as Dictionary).keys():
        var room_v: Variant = (rooms_v as Dictionary)[key]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var origin := Vector2i(
            int(room.get("region_col", 0)),
            int(room.get("region_row", 0)))
        var mask_v: Variant = room.get("mask", [])
        if typeof(mask_v) != TYPE_ARRAY:
            continue
        for cell_v in mask_v:
            if typeof(cell_v) != TYPE_ARRAY or (cell_v as Array).size() < 2:
                continue
            var cell := Vector2i(
                int((cell_v as Array)[0]) + origin.x,
                int((cell_v as Array)[1]) + origin.y)
            _cell_to_room[cell] = str(key)


func _reset_selection() -> void:
    _mode = Mode.IDLE
    _pending_cells.clear()


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()
            return
        if event.keycode == KEY_ESCAPE:
            if _skip_close_frame:
                return
            if _name_edit != null and _name_edit.has_focus():
                _name_edit.release_focus()
                get_viewport().set_input_as_handled()
                return
            for key in _region_edits.keys():
                var redit: LineEdit = _region_edits[key]
                if redit != null and redit.has_focus():
                    redit.release_focus()
                    get_viewport().set_input_as_handled()
                    return
            if _mode != Mode.IDLE or not _pending_cells.is_empty():
                _reset_selection()
                queue_redraw()
                get_viewport().set_input_as_handled()
                return
            _emit_back()
            get_viewport().set_input_as_handled()


func _gui_input(event):
    _skip_close_frame = false

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed:
            _handle_press(mb)
        else:
            _handle_release(mb)
        return

    if event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if _mode == Mode.DRAWING_ADD or _mode == Mode.DRAWING_SUB:
            if _canvas_rect.has_point(mm.position):
                var cell := _cell_at(mm.position)
                if cell.x >= 0:
                    _drag_current = cell


func _handle_press(mb: InputEventMouseButton) -> void:
    var p: Vector2 = mb.position
    if mb.button_index == MOUSE_BUTTON_LEFT:
        if _tooltips_rect.has_point(p):
            EditorTooltip.toggle()
            accept_event()
            return
        if _back_rect.has_point(p):
            _emit_back()
            accept_event()
            return
        if _save_rect.has_point(p):
            _save_all()
            accept_event()
            return
        if _mode == Mode.PENDING:
            if _confirm_yes_rect.has_point(p):
                _confirm_pending()
                accept_event()
                return
            if _confirm_no_rect.has_point(p):
                _reset_selection()
                queue_redraw()
                accept_event()
                return
        if _canvas_rect.has_point(p):
            var cell := _cell_at(p)
            if cell.x < 0:
                return
            if _cell_to_room.has(cell):
                _handle_room_click(str(_cell_to_room[cell]))
                accept_event()
                return
            _mode = Mode.DRAWING_ADD
            _drag_start = cell
            _drag_current = cell
            accept_event()
            return
    elif mb.button_index == MOUSE_BUTTON_RIGHT:
        if _canvas_rect.has_point(p):
            var cell := _cell_at(p)
            if cell.x < 0:
                return
            _mode = Mode.DRAWING_SUB
            _drag_start = cell
            _drag_current = cell
            accept_event()
            return


func _handle_release(mb: InputEventMouseButton) -> void:
    if mb.button_index == MOUSE_BUTTON_LEFT and _mode == Mode.DRAWING_ADD:
        _commit_drag_add()
        accept_event()
        return
    if mb.button_index == MOUSE_BUTTON_RIGHT and _mode == Mode.DRAWING_SUB:
        _commit_drag_sub()
        accept_event()
        return


func _handle_room_click(addr: String) -> void:
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    if addr == _last_click_room and (now - _last_click_time) < DOUBLE_CLICK_DELAY:
        _last_click_time = 0.0
        _last_click_room = ""
        room_chosen.emit(region_id, addr)
        return
    _selected_room = addr
    _last_click_time = now
    _last_click_room = addr
    queue_redraw()


func _commit_drag_add() -> void:
    var lo := Vector2i(
        mini(_drag_start.x, _drag_current.x),
        mini(_drag_start.y, _drag_current.y))
    var hi := Vector2i(
        maxi(_drag_start.x, _drag_current.x),
        maxi(_drag_start.y, _drag_current.y))
    for y in range(lo.y, hi.y + 1):
        for x in range(lo.x, hi.x + 1):
            var cell := Vector2i(x, y)
            if _cell_to_room.has(cell):
                continue
            _pending_cells[cell] = true
    if _pending_cells.is_empty():
        _mode = Mode.IDLE
    else:
        _mode = Mode.PENDING
    queue_redraw()


func _commit_drag_sub() -> void:
    var lo := Vector2i(
        mini(_drag_start.x, _drag_current.x),
        mini(_drag_start.y, _drag_current.y))
    var hi := Vector2i(
        maxi(_drag_start.x, _drag_current.x),
        maxi(_drag_start.y, _drag_current.y))
    for y in range(lo.y, hi.y + 1):
        for x in range(lo.x, hi.x + 1):
            _pending_cells.erase(Vector2i(x, y))
    if _pending_cells.is_empty():
        _mode = Mode.IDLE
    else:
        _mode = Mode.PENDING
    queue_redraw()


func _confirm_pending() -> void:
    if _pending_cells.is_empty():
        _reset_selection()
        return

    if _undo != null: _undo.begin()
    var min_x: int = 0x7FFFFFFF
    var min_y: int = 0x7FFFFFFF
    for cell_key in _pending_cells.keys():
        var c: Vector2i = cell_key
        min_x = mini(min_x, c.x)
        min_y = mini(min_y, c.y)
    var mask: Array = []
    for cell_key in _pending_cells.keys():
        var c: Vector2i = cell_key
        mask.append([c.x - min_x, c.y - min_y])

    var room_identity := _next_room_identity()
    var addr := str(room_identity.get("id", "room"))
    var room_name := str(room_identity.get("name", addr))
    var cell_bx := int(region_meta.get("cell_blocks_x", RegIO.DEFAULT_CELL_BLOCKS_X))
    var cell_by := int(region_meta.get("cell_blocks_y", RegIO.DEFAULT_CELL_BLOCKS_Y))
    var room := RegIO.make_room_from_mask(addr, room_name, mask, min_x, min_y,
        cell_bx, cell_by, 0)
    (rooms_data["rooms"] as Dictionary)[addr] = room
    if str(rooms_data.get("start_room", "")) == "":
        rooms_data["start_room"] = addr
    _rebuild_cell_index()
    _save_all()
    _reset_selection()
    _selected_room = addr
    if _undo != null: _undo.commit("create room %s" % addr)
    queue_redraw()


func _next_room_identity() -> Dictionary:
    var rooms_v: Variant = rooms_data.get("rooms", {})
    var used: Dictionary = {}
    if typeof(rooms_v) == TYPE_DICTIONARY:
        for key in (rooms_v as Dictionary).keys():
            used[str(key)] = true
    var idx: int = 1
    var name := "Room %d" % idx
    var room_id := RegIO.unique_content_id(name, used, "room")
    while used.has(room_id):
        idx += 1
        name = "Room %d" % idx
        room_id = RegIO.unique_content_id(name, used, "room")
    return {
        "id": room_id,
        "name": name,
    }


func _save_all() -> void:
    RegIO.save_region_rooms(pack_id, region_id, rooms_data)
    RegIO.save_region_meta(pack_id, region_id, region_meta)


func _emit_back() -> void:
    visible = false
    back_to_pack.emit()


func _cell_at(pos: Vector2) -> Vector2i:
    if _cell_px.x <= 0 or _cell_px.y <= 0:
        return Vector2i(-1, -1)
    var local := pos - _grid_origin
    if local.x < 0 or local.y < 0:
        return Vector2i(-1, -1)
    var cx := int(local.x / _cell_px.x)
    var cy := int(local.y / _cell_px.y)
    var grid_w := int(region_meta.get("grid_cells_x", RegIO.DEFAULT_REGION_GRID_X))
    var grid_h := int(region_meta.get("grid_cells_y", RegIO.DEFAULT_REGION_GRID_Y))
    if cx < 0 or cy < 0 or cx >= grid_w or cy >= grid_h:
        return Vector2i(-1, -1)
    return Vector2i(cx, cy)


func _cell_rect(cell: Vector2i) -> Rect2:
    return Rect2(
        _grid_origin + Vector2(float(cell.x) * _cell_px.x, float(cell.y) * _cell_px.y),
        _cell_px)


func _draw():
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.10, 1))

    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, Vector2(size.x, TOPBAR_H)),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    var title := "REGION  %s" % str(region_meta.get("name", region_id))
    draw_string(font, Vector2(24, 36),
        title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)
    var sub := "CAMPAIGN  %s     ID  %s" % [pack_id, region_id]
    draw_string(font, Vector2(24, 54),
        sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    var btn_w: float = 110.0
    var btn_h: float = 32.0
    _back_rect = Rect2(size.x - 16.0 - btn_w, 16.0, btn_w, btn_h)
    var back_hover := _back_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _back_rect, back_hover, Color(0.95, 0.45, 0.4, 1))
    var back_label := "< PACK"
    var back_lw := float(back_label.length()) * 6.0
    var back_col: Color
    if back_hover:
        back_col = Color(1, 1, 1, 1)
    else:
        back_col = Color(0.85, 0.6, 0.6, 1)
    draw_string(font, Vector2(_back_rect.position.x + (btn_w - back_lw) * 0.5,
        _back_rect.position.y + 21),
        back_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, back_col)
    if back_hover:
        EditorTooltip.show_text("Return to the previous editor surface. Unsaved changes stay in memory — use SAVE first if you want them on disk.")

    _save_rect = Rect2(_back_rect.position.x - btn_w - 8, 16.0, btn_w, btn_h)
    var save_hover := _save_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _save_rect, save_hover, Color(0.4, 0.9, 0.55, 1))
    var save_label := "SAVE"
    var save_lw := float(save_label.length()) * 6.0
    var save_col: Color
    if save_hover:
        save_col = Color(1, 1, 0.95, 1)
    else:
        save_col = Color(0.75, 0.95, 0.75, 1)
    draw_string(font, Vector2(_save_rect.position.x + (btn_w - save_lw) * 0.5,
        _save_rect.position.y + 21),
        save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, save_col)
    if save_hover:
        EditorTooltip.show_text("Save this region's metadata and room layouts to disk.")

    _tooltips_rect = Rect2(_save_rect.position.x - EditorTooltip.TOGGLE_WIDTH - 12.0, 16.0, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    var pad: float = 16.0
    var canvas_x := pad
    var canvas_y := TOPBAR_H + pad
    var canvas_w := size.x - SIDEBAR_W - pad * 3.0
    var canvas_h := size.y - TOPBAR_H - pad * 2.0
    if _mode == Mode.PENDING:
        canvas_h -= CONFIRM_H + pad
    _canvas_rect = Rect2(canvas_x, canvas_y, canvas_w, canvas_h)
    draw_rect(_canvas_rect, Color(0.06, 0.08, 0.13, 1))
    draw_rect(_canvas_rect, Color(0.25, 0.35, 0.5, 1), false, 2.0)
    if _canvas_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Region grid. LMB-drag empty cells to mark a pending rectangle. RMB-drag cells to subtract from the pending rectangle. Click a placed room to select. Double-click a room to open it in the environment editor. ESC cancels pending or goes back to the POI panel.")

    var grid_w := int(region_meta.get("grid_cells_x", RegIO.DEFAULT_REGION_GRID_X))
    var grid_h := int(region_meta.get("grid_cells_y", RegIO.DEFAULT_REGION_GRID_Y))
    if grid_w > 0 and grid_h > 0:
        # Cells are square — 1 region cell = 1 room block — so pick the
        # largest square that keeps the whole grid on-canvas.
        var max_cell_w := canvas_w / float(grid_w)
        var max_cell_h := canvas_h / float(grid_h)
        var cell_sz := minf(max_cell_w, max_cell_h)
        _cell_px = Vector2(cell_sz, cell_sz)
        var cell_w := cell_sz
        var cell_h := cell_sz
        var grid_total_w := cell_w * float(grid_w)
        var grid_total_h := cell_h * float(grid_h)
        _grid_origin = Vector2(
            _canvas_rect.position.x + (canvas_w - grid_total_w) * 0.5,
            _canvas_rect.position.y + (canvas_h - grid_total_h) * 0.5)

        for gy in grid_h + 1:
            var y := _grid_origin.y + float(gy) * cell_h
            draw_line(Vector2(_grid_origin.x, y),
                Vector2(_grid_origin.x + grid_total_w, y),
                Color(0.15, 0.2, 0.3, 1), 1.0)
        for gx in grid_w + 1:
            var x := _grid_origin.x + float(gx) * cell_w
            draw_line(Vector2(x, _grid_origin.y),
                Vector2(x, _grid_origin.y + grid_total_h),
                Color(0.15, 0.2, 0.3, 1), 1.0)

        var rooms_v: Variant = rooms_data.get("rooms", {})
        if typeof(rooms_v) == TYPE_DICTIONARY:
            for key in (rooms_v as Dictionary).keys():
                var room_v = (rooms_v as Dictionary)[key]
                if typeof(room_v) == TYPE_DICTIONARY:
                    _draw_room(font, str(key), room_v)

        for cell_key in _pending_cells.keys():
            var cc: Vector2i = cell_key
            var cr := _cell_rect(cc)
            draw_rect(cr, Color(0.3, 0.85, 0.6, 0.55))
            draw_rect(cr, Color(0.45, 1.0, 0.7, 1), false, 2.0)

        if _mode == Mode.DRAWING_ADD or _mode == Mode.DRAWING_SUB:
            var lo := Vector2i(
                mini(_drag_start.x, _drag_current.x),
                mini(_drag_start.y, _drag_current.y))
            var hi := Vector2i(
                maxi(_drag_start.x, _drag_current.x),
                maxi(_drag_start.y, _drag_current.y))
            var preview_col: Color
            if _mode == Mode.DRAWING_ADD:
                preview_col = Color(0.45, 1.0, 0.7, 0.9)
            else:
                preview_col = Color(1.0, 0.5, 0.4, 0.9)
            var drag_rect := Rect2(
                _grid_origin + Vector2(float(lo.x) * cell_w, float(lo.y) * cell_h),
                Vector2(float(hi.x - lo.x + 1) * cell_w,
                    float(hi.y - lo.y + 1) * cell_h))
            draw_rect(drag_rect, preview_col, false, 2.0)

    var detail_rect := Rect2(
        _canvas_rect.position.x + _canvas_rect.size.x + pad,
        _canvas_rect.position.y,
        SIDEBAR_W, _canvas_rect.size.y)
    draw_rect(detail_rect, Color(0.08, 0.11, 0.18, 1))
    draw_rect(detail_rect, Color(0.3, 0.45, 0.65, 1), false, 2.0)
    _draw_detail(font, detail_rect)

    if _mode == Mode.PENDING:
        var conf_rect := Rect2(_canvas_rect.position.x,
            _canvas_rect.position.y + _canvas_rect.size.y + pad,
            _canvas_rect.size.x, CONFIRM_H)
        draw_rect(conf_rect, Color(0.1, 0.14, 0.22, 1))
        draw_rect(conf_rect, Color(0.4, 0.6, 0.85, 1), false, 2.0)
        draw_string(font, conf_rect.position + Vector2(16, 28),
            "Create room from %d cell(s)?" % _pending_cells.size(),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.95, 1, 1))
        draw_string(font, conf_rect.position + Vector2(16, 50),
            "LMB to add more, RMB to subtract, or click YES / NO.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.9, 1))
        var yes_w: float = 90.0
        var yes_h: float = 36.0
        _confirm_yes_rect = Rect2(
            conf_rect.position.x + conf_rect.size.x - yes_w * 2.0 - 24.0,
            conf_rect.position.y + (conf_rect.size.y - yes_h) * 0.5,
            yes_w, yes_h)
        _confirm_no_rect = Rect2(
            conf_rect.position.x + conf_rect.size.x - yes_w - 12.0,
            conf_rect.position.y + (conf_rect.size.y - yes_h) * 0.5,
            yes_w, yes_h)
        var yes_hover := _confirm_yes_rect.has_point(mouse_pos)
        var no_hover := _confirm_no_rect.has_point(mouse_pos)
        UIPanels.draw_button_bg(self, _confirm_yes_rect, yes_hover,
            Color(0.4, 0.9, 0.55, 1))
        UIPanels.draw_button_bg(self, _confirm_no_rect, no_hover,
            Color(0.95, 0.45, 0.4, 1))
        var yes_col: Color
        if yes_hover:
            yes_col = Color(1, 1, 0.95, 1)
        else:
            yes_col = Color(0.85, 0.95, 0.85, 1)
        var no_col: Color
        if no_hover:
            no_col = Color(1, 1, 0.95, 1)
        else:
            no_col = Color(0.95, 0.85, 0.85, 1)
        draw_string(font, _confirm_yes_rect.position + Vector2(28, 24),
            "YES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, yes_col)
        draw_string(font, _confirm_no_rect.position + Vector2(32, 24),
            "NO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, no_col)
        if yes_hover:
            EditorTooltip.show_text("Commit the pending cells as a new room in this region. A new room address is generated automatically.")
        if no_hover:
            EditorTooltip.show_text("Discard the pending selection and return to idle mode. Nothing is saved.")


func _draw_room(font: Font, addr: String, room: Dictionary) -> void:
    var origin := Vector2i(
        int(room.get("region_col", 0)),
        int(room.get("region_row", 0)))
    var mask_v: Variant = room.get("mask", [])
    if typeof(mask_v) != TYPE_ARRAY:
        return
    var is_selected := addr == _selected_room
    var bg_col: Color
    if is_selected:
        bg_col = Color(0.35, 0.55, 0.85, 0.85)
    else:
        bg_col = Color(0.25, 0.35, 0.55, 0.75)
    var border_col: Color
    if is_selected:
        border_col = Color(0.6, 0.85, 1.0, 1)
    else:
        border_col = Color(0.45, 0.6, 0.85, 1)
    for cell_v in mask_v:
        if typeof(cell_v) != TYPE_ARRAY or (cell_v as Array).size() < 2:
            continue
        var cell := Vector2i(
            int((cell_v as Array)[0]) + origin.x,
            int((cell_v as Array)[1]) + origin.y)
        var r := _cell_rect(cell)
        draw_rect(r, bg_col)
        draw_rect(r, border_col, false, 1.5)
    var label_pos := _grid_origin + Vector2(
        float(origin.x) * _cell_px.x + 6.0,
        float(origin.y) * _cell_px.y + 14.0)
    var label_col: Color
    if is_selected:
        label_col = Color(1, 1, 1, 1)
    else:
        label_col = Color(0.85, 0.9, 1, 1)
    draw_string(font, label_pos, addr,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_col)


func _draw_detail(font: Font, rect: Rect2) -> void:
    if _selected_room == "":
        _hide_room_edit()
        _draw_region_props(font, rect)
        return
    _hide_region_edits()
    draw_string(font, rect.position + Vector2(16, 24),
        "ROOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(0.75, 0.85, 0.95, 1))
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return
    var rooms: Dictionary = rooms_v
    if not rooms.has(_selected_room):
        if _name_edit != null:
            _name_edit.visible = false
        return
    var room: Dictionary = rooms[_selected_room]
    var mask_arr: Array = room.get("mask", [])

    draw_string(font, rect.position + Vector2(16, 52),
        "Address:  %s" % _selected_room,
        HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 11,
        Color(0.85, 0.9, 1, 1))
    draw_string(font, rect.position + Vector2(16, 74),
        "Name", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.7, 0.8, 0.95, 1))

    var edit_h: float = 26.0
    var edit_rect := Rect2(
        rect.position.x + 16.0, rect.position.y + 82.0,
        rect.size.x - 32.0, edit_h)
    _name_edit.position = edit_rect.position
    _name_edit.size = edit_rect.size
    _name_edit.visible = true
    var current_name := str(room.get("friendly_name", _selected_room))
    if not _name_edit.has_focus() and _name_edit.text != current_name:
        _name_edit.text = current_name

    var rest_y: float = edit_rect.position.y + edit_h + 14.0 - rect.position.y
    var lines: Array = [
        "Size:     %d × %d blocks" % [
            int(room.get("width_blocks", 0)),
            int(room.get("height_blocks", 0))],
        "Origin:   (%d, %d)" % [
            int(room.get("region_col", 0)),
            int(room.get("region_row", 0))],
        "Cells:    %d" % mask_arr.size(),
        "",
        "Double-click the room to edit",
        "its tiles, entities, and doors.",
    ]
    var ly: float = rest_y
    for line in lines:
        draw_string(font, rect.position + Vector2(16, ly),
            str(line), HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 11,
            Color(0.85, 0.9, 1, 1))
        ly += 18.0


func _on_name_submitted(new_name: String) -> void:
    _apply_name_edit(new_name)
    _name_edit.release_focus()


func _on_name_focus_exited() -> void:
    if _selected_room == "" or _name_edit == null or not _name_edit.visible:
        return
    _apply_name_edit(_name_edit.text)


func _apply_name_edit(new_name: String) -> void:
    if _selected_room == "":
        return
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return
    var rooms: Dictionary = rooms_v
    if not rooms.has(_selected_room):
        return
    var room: Dictionary = rooms[_selected_room]
    var trimmed := new_name.strip_edges()
    if trimmed == "":
        return
    var new_addr := RegIO.unique_content_id(trimmed, rooms, "room", _selected_room)
    var current_name := str(room.get("friendly_name", _selected_room)).strip_edges()
    if trimmed == current_name and new_addr == _selected_room:
        return
    var old_addr := _selected_room
    if not RegIO.rename_room(pack_id, region_id, _selected_room, new_addr, trimmed):
        return
    _update_room_rename_references(old_addr, new_addr)
    rooms_data = RegIO.load_region_rooms(pack_id, region_id)
    _selected_room = new_addr
    _rebuild_cell_index()
    queue_redraw()


func _update_room_rename_references(old_addr: String, new_addr: String) -> void:
    var refactor := ContentReferenceRefactor.rename_room_references(
        pack_id,
        region_id,
        old_addr,
        region_id,
        new_addr
    )
    if not bool(refactor.get("ok", false)):
        push_warning("[RegionEditor] room renamed, but reference update failed: %s" % str(refactor.get("errors", [])))
        return
    if int(refactor.get("changed_refs", 0)) > 0:
        RegIO.flatten_to_runtime(pack_id)


func _hide_room_edit() -> void:
    if _name_edit != null:
        _name_edit.visible = false


func _hide_region_edits() -> void:
    for key in _region_edits.keys():
        var edit: LineEdit = _region_edits[key]
        edit.visible = false


func _draw_region_props(font: Font, rect: Rect2) -> void:
    draw_string(font, rect.position + Vector2(16, 24),
        "REGION PROPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(0.75, 0.85, 0.95, 1))
    draw_string(font, rect.position + Vector2(16, 44),
        "Applied when the player lands here.",
        HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 10,
        Color(0.55, 0.65, 0.8, 1))

    var y: float = 64.0
    var edit_h: float = 24.0
    for field in REGION_FIELDS:
        var key := str(field.get("key", ""))
        var label := str(field.get("label", key))
        var kind := str(field.get("kind", "string"))
        var edit: LineEdit = _region_edits.get(key, null)
        if edit == null:
            continue
        draw_string(font, rect.position + Vector2(16, y + 12),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.7, 0.8, 0.95, 1))
        var edit_rect := Rect2(
            rect.position.x + 16.0, rect.position.y + y + 16.0,
            rect.size.x - 32.0, edit_h)
        edit.position = edit_rect.position
        edit.size = edit_rect.size
        edit.visible = true
        var current := _region_field_text(key, kind)
        if not edit.has_focus() and edit.text != current:
            edit.text = current
        y += 46.0

    var hint_y: float = rect.size.y - 60.0
    draw_string(font, rect.position + Vector2(16, hint_y),
        "Click a room to edit rooms.",
        HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 10,
        Color(0.5, 0.6, 0.75, 1))
    draw_string(font, rect.position + Vector2(16, hint_y + 16),
        "Drag LMB on empty cells to create one.",
        HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 10,
        Color(0.5, 0.6, 0.75, 1))
    draw_string(font, rect.position + Vector2(16, hint_y + 32),
        "Double-click a room to open its tiles.",
        HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 32), 10,
        Color(0.5, 0.6, 0.75, 1))


func _region_field_text(key: String, kind: String) -> String:
    var v: Variant = region_meta.get(key, "")
    if kind == "float":
        return str(float(v))
    return str(v)


func _on_region_field_submitted(text: String, key: String) -> void:
    _apply_region_field(key, text)
    var edit: LineEdit = _region_edits.get(key, null)
    if edit != null:
        edit.release_focus()


func _on_region_field_focus_exited(key: String) -> void:
    var edit: LineEdit = _region_edits.get(key, null)
    if edit == null or not edit.visible:
        return
    _apply_region_field(key, edit.text)


func _apply_region_field(key: String, text: String) -> void:
    var kind: String = ""
    for field in REGION_FIELDS:
        if str(field.get("key", "")) == key:
            kind = str(field.get("kind", "string"))
            break
    if kind == "":
        return
    var new_val: Variant
    if kind == "float":
        var trimmed := text.strip_edges()
        # Empty or invalid input → revert the edit to the current stored
        # value rather than clobbering to 0 (which would silently zero
        # gravity, cam_height, etc. on an accidental empty field).
        if trimmed == "" or not trimmed.is_valid_float():
            var edit: LineEdit = _region_edits.get(key, null)
            if edit != null:
                edit.text = _region_field_text(key, kind)
            return
        new_val = trimmed.to_float()
    else:
        new_val = text.strip_edges()
    var current: Variant = region_meta.get(key, null)
    if typeof(current) == typeof(new_val) and current == new_val:
        return
    if _undo != null: _undo.begin()
    region_meta[key] = new_val
    _save_all()
    if _undo != null: _undo.commit("edit %s" % key)
    queue_redraw()
