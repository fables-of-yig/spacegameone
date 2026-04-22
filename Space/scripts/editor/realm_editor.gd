extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const RegIO = preload("res://Space/scripts/editor/reg/reg_io.gd")
const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")
const RlmTypes = preload("res://Space/scripts/editor/rlm/rlm_types.gd")
const RlmCanvas = preload("res://Space/scripts/editor/rlm/rlm_canvas.gd")
const RlmToolPalette = preload("res://Space/scripts/editor/rlm/rlm_tool_palette.gd")
const RlmTilesetPanel = preload("res://Space/scripts/editor/rlm/rlm_tileset_panel.gd")
const EditorUndo = preload("res://Space/scripts/editor/editor_undo.gd")

signal closed
signal region_chosen(realm_id: String, region_id: String)

var pack_id: String = ""
var realm_id: String = ""
var realm_list: Array = []
var realm_data: Dictionary = {}
var regions_meta: Dictionary = {}

var active_tool: int = RlmTypes.TOOL_PAINT
var active_realm_layer: int = RlmTypes.LAYER_GROUND
var selected_realm_tileset: int = 0
var selected_realm_tile: int = 1
var selected_realm_tile_span: Vector2i = Vector2i.ONE

var _tileset_textures: Dictionary = {}
var _tileset_indices: Array = []
var _tileset_sizes: Dictionary = {}
var _tileset_names: Dictionary = {}

var _rlm_canvas: Control = null
var _rlm_tool_palette: Control = null
var _rlm_tileset_panel: Control = null
var _text_modal: Control = null

var _modal_callback: Callable = Callable()
var _pending_import_paths: PackedStringArray = PackedStringArray()

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _skip_close_frame: bool = false
var _realm_row_rects: Array = []
var _region_row_rects: Array = []
var _new_realm_rect: Rect2 = Rect2()
var _new_region_rect: Rect2 = Rect2()
var _back_rect: Rect2 = Rect2()
var _tooltips_rect: Rect2 = Rect2()

var _undo: RefCounted = null
var _realm_clipboard: Dictionary = {}
var _realm_paste_preview_active: bool = false


const TOPBAR_H: float = 64.0
const LIST_W: float = 300.0
const PALETTE_W: float = 180.0
const TILESET_PANEL_W: float = 220.0
const PAD: float = 12.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    set_process(true)
    visible = false
    _build_panels()
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    return {
        "realm_id": realm_id,
        "realm_data": realm_data.duplicate(true),
        "regions_meta": regions_meta.duplicate(true),
    }


func _apply_state(snap: Dictionary) -> void:
    realm_id = str(snap.get("realm_id", realm_id))
    var rd_v: Variant = snap.get("realm_data", null)
    if typeof(rd_v) == TYPE_DICTIONARY:
        realm_data = rd_v
    var rm_v: Variant = snap.get("regions_meta", null)
    if typeof(rm_v) == TYPE_DICTIONARY:
        regions_meta = rm_v
    RegIO.save_realm(pack_id, realm_id, realm_data)
    for region_id in regions_meta.keys():
        var meta_v: Variant = regions_meta[region_id]
        if typeof(meta_v) == TYPE_DICTIONARY:
            RegIO.save_region_meta(pack_id, realm_id, str(region_id), meta_v)
    queue_redraw()


func _process(_delta):
    if visible:
        queue_redraw()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_panels()


func open_editor(p_pack_id: String = "", p_realm_id: String = "") -> void:
    pack_id = p_pack_id
    realm_id = p_realm_id
    _skip_close_frame = true
    visible = true
    _reload()
    _refresh_tileset_cache()
    selected_realm_tile = _snap_to_realm_logical_tile(selected_realm_tile, selected_realm_tileset)
    selected_realm_tile_span = Vector2i.ONE
    _realm_paste_preview_active = false
    _layout_panels()
    queue_redraw()


func _reload() -> void:
    var all := RegIO.load_all_realms(pack_id)
    realm_list = all.get("realm_list", [])
    if realm_id.strip_edges().is_empty():
        realm_id = RegIO.default_realm_id(pack_id)
    var realms: Dictionary = all.get("realms", {})
    var bundle: Dictionary = realms.get(realm_id, RegIO.load_or_init(pack_id, realm_id))
    realm_data = bundle.get("realm", {})
    realm_id = str(bundle.get("realm_id", realm_id))
    regions_meta = bundle.get("regions", {})
    if _undo != null:
        _undo.clear()


func _input(event):
    if not visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()
            return
        if event.keycode == KEY_C and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
            if _rlm_canvas != null and _rlm_canvas.has_method("copy_selection_to_clipboard"):
                if bool(_rlm_canvas.call("copy_selection_to_clipboard")):
                    get_viewport().set_input_as_handled()
                    return
        if event.keycode == KEY_V and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
            if start_realm_paste_preview():
                get_viewport().set_input_as_handled()
                return
        if event.keycode == KEY_ESCAPE:
            if cancel_realm_paste_preview():
                get_viewport().set_input_as_handled()
                return
            if _skip_close_frame:
                return
            _request_close()
            get_viewport().set_input_as_handled()


func _gui_input(event):
    _skip_close_frame = false
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var p: Vector2 = event.position
        if _tooltips_rect.has_point(p):
            EditorTooltip.toggle()
            accept_event()
            return
        if _back_rect.has_point(p):
            _request_close()
            accept_event()
            return
        if _new_region_rect.has_point(p):
            _create_new_region()
            accept_event()
            return
        if _new_realm_rect.has_point(p):
            _create_new_realm()
            accept_event()
            return
        for entry in _realm_row_rects:
            if (entry["rect"] as Rect2).has_point(p):
                realm_id = str(entry["id"])
                _reload()
                _refresh_tileset_cache()
                queue_redraw()
                accept_event()
                return
        for entry in _region_row_rects:
            if (entry["rect"] as Rect2).has_point(p):
                region_chosen.emit(realm_id, str(entry["id"]))
                accept_event()
                return


func _request_close() -> void:
    visible = false
    if _rlm_canvas != null:
        _rlm_canvas.visible = false
    if _rlm_tool_palette != null:
        _rlm_tool_palette.visible = false
    if _rlm_tileset_panel != null:
        _rlm_tileset_panel.visible = false
    closed.emit()


func _create_new_region() -> void:
    if _undo != null:
        _undo.begin()
    var regions: Array = realm_data.get("regions", [])
    var used_ids: Dictionary = {}
    for entry_v in regions:
        if typeof(entry_v) == TYPE_DICTIONARY:
            used_ids[str((entry_v as Dictionary).get("id", ""))] = true
    var idx: int = 1
    while used_ids.has("region_%02d" % idx):
        idx += 1
    var new_id := "region_%02d" % idx
    var new_name := "Region %d" % idx
    var new_entry := {
        "id": new_id,
        "name": new_name,
        "col": 0,
        "row": 0,
    }
    regions.append(new_entry)
    realm_data["regions"] = regions
    RegIO.save_realm(pack_id, realm_id, realm_data)
    var region_meta := RegIO.default_region(new_id, new_name)
    RegIO.save_region_meta(pack_id, realm_id, new_id, region_meta)
    regions_meta[new_id] = region_meta
    queue_redraw()
    if _undo != null:
        _undo.commit("create region")


func _create_new_realm() -> void:
    if _undo != null:
        _undo.begin()
    var used: Dictionary = {}
    for entry_v in realm_list:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        used[str((entry_v as Dictionary).get("id", ""))] = true
    var idx: int = 1
    while used.has("realm_%02d" % idx):
        idx += 1
    var new_realm_id := "realm_%02d" % idx
    var new_realm_name := "Realm %d" % idx
    RegIO.create_realm(pack_id, new_realm_id, new_realm_name)
    realm_id = new_realm_id
    _reload()
    _refresh_tileset_cache()
    queue_redraw()
    if _undo != null:
        _undo.commit("create realm")


func _draw():
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.10, 1))

    var topbar_h: float = 64.0
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, Vector2(size.x, topbar_h)),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    var title := "REALM  %s" % str(realm_data.get("realm_name", "(unknown)"))
    draw_string(font, Vector2(24, 36),
        title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)

    var pack_label := "CAMPAIGN  %s     ID  %s" % [pack_id, realm_id]
    draw_string(font, Vector2(24, 54),
        pack_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    var back_w: float = 110.0
    var btn_h: float = 32.0
    _back_rect = Rect2(size.x - 16.0 - back_w, 16.0, back_w, btn_h)
    var back_hover := _back_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _back_rect, back_hover, Color(0.95, 0.45, 0.4, 1))
    var back_label := "< BACK"
    var back_w_text := float(back_label.length()) * 6.0
    var back_text_col: Color
    if back_hover:
        back_text_col = Color(1, 1, 1, 1)
    else:
        back_text_col = Color(0.85, 0.6, 0.6, 1)
    draw_string(font, Vector2(_back_rect.position.x + (back_w - back_w_text) * 0.5,
            _back_rect.position.y + 21),
        back_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, back_text_col)
    if back_hover:
        EditorTooltip.show_text("Close the realm editor and return to the main menu.")

    _tooltips_rect = Rect2(_back_rect.position.x - EditorTooltip.TOGGLE_WIDTH - 12.0, 16.0, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    var body_y: float = topbar_h + PAD
    var body_h: float = size.y - topbar_h - PAD * 2.0
    var list_rect := Rect2(PAD, body_y, LIST_W, body_h)
    draw_rect(list_rect, Color(0.08, 0.11, 0.18, 1))
    draw_rect(list_rect, Color(0.35, 0.55, 0.8, 1), false, 2.0)

    draw_string(font, list_rect.position + Vector2(16, 24),
        "REALMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 0.95, 1))

    _realm_row_rects.clear()
    _region_row_rects.clear()
    var row_h: float = 34.0
    var row_gap: float = 6.0
    var row_y: float = list_rect.position.y + 40.0
    for realm_entry_v in realm_list:
        if typeof(realm_entry_v) != TYPE_DICTIONARY:
            continue
        var realm_entry: Dictionary = realm_entry_v
        var rid := str(realm_entry.get("id", ""))
        if rid.is_empty():
            continue
        var rname := str(realm_entry.get("name", rid))
        var row_rect := Rect2(list_rect.position.x + 12.0, row_y, list_rect.size.x - 24.0, row_h)
        var active := rid == realm_id
        var hover := row_rect.has_point(mouse_pos)
        var bg_col := Color(0.12, 0.17, 0.26, 1)
        if active:
            bg_col = Color(0.2, 0.33, 0.54, 1)
        elif hover:
            bg_col = Color(0.16, 0.22, 0.33, 1)
        draw_rect(row_rect, bg_col)
        draw_rect(row_rect, Color(0.34, 0.5, 0.76, 1), false, 1.0)
        draw_string(font, row_rect.position + Vector2(10, 21),
            rname, HORIZONTAL_ALIGNMENT_LEFT, int(row_rect.size.x - 20.0), 13,
            Color(1, 1, 1, 1) if active else Color(0.86, 0.9, 1, 1))
        if hover:
            EditorTooltip.show_text("Switch the active realm. Regions listed below belong to this realm only.")
        _realm_row_rects.append({"id": rid, "rect": row_rect})
        row_y += row_h + row_gap

    _new_realm_rect = Rect2(list_rect.position.x + 12.0, row_y, list_rect.size.x - 24.0, 32.0)
    var new_realm_hover := _new_realm_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _new_realm_rect, new_realm_hover, Color(0.45, 0.78, 0.98, 1))
    draw_string(font, _new_realm_rect.position + Vector2(10, 22),
        "+ NEW REALM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1, 1, 1, 1) if new_realm_hover else Color(0.86, 0.94, 1, 1))
    if new_realm_hover:
        EditorTooltip.show_text("Create a new overworld realm inside this campaign pack.")

    var divider_y: float = _new_realm_rect.end.y + 18.0
    draw_line(Vector2(list_rect.position.x + 12.0, divider_y),
        Vector2(list_rect.end.x - 12.0, divider_y),
        Color(0.22, 0.3, 0.42, 1), 1.0)
    draw_string(font, Vector2(list_rect.position.x + 16.0, divider_y + 22.0),
        "REGIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 0.95, 1))

    row_y = divider_y + 34.0
    row_h = 44.0
    var regions: Array = realm_data.get("regions", [])
    for entry_v in regions:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var rid := str(entry.get("id", ""))
        var rname := str(entry.get("name", rid))
        var row_rect := Rect2(list_rect.position.x + 12, row_y,
            list_rect.size.x - 24, row_h)
        var hover := row_rect.has_point(mouse_pos)
        var bg_col: Color
        if hover:
            bg_col = Color(0.2, 0.3, 0.48, 1)
        else:
            bg_col = Color(0.12, 0.17, 0.26, 1)
        draw_rect(row_rect, bg_col)
        draw_rect(row_rect, Color(0.3, 0.45, 0.7, 1), false, 1.0)
        var name_col: Color
        if hover:
            name_col = Color(1, 1, 1, 1)
        else:
            name_col = Color(0.85, 0.9, 1, 1)
        draw_string(font, row_rect.position + Vector2(12, 22),
            rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_col)
        draw_string(font, row_rect.position + Vector2(12, 38),
            rid, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.65, 0.75, 0.9, 1))
        if hover:
            EditorTooltip.show_text("Click to open region \"%s\" (id: %s) in the region editor, where you paint room layouts on its grid." % [rname, rid])
        _region_row_rects.append({"id": rid, "rect": row_rect})
        row_y += row_h + row_gap

    var new_btn_w: float = LIST_W - 24.0
    var new_btn_h: float = 36.0
    _new_region_rect = Rect2(list_rect.position.x + 12,
        list_rect.position.y + list_rect.size.y - new_btn_h - 12,
        new_btn_w, new_btn_h)
    var new_hover := _new_region_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _new_region_rect, new_hover,
        Color(0.4, 0.85, 0.6, 1))
    var new_label := "+ NEW REGION"
    var new_w_t := float(new_label.length()) * 6.5
    var new_text_col: Color
    if new_hover:
        new_text_col = Color(1, 1, 1, 1)
    else:
        new_text_col = Color(0.85, 0.95, 0.85, 1)
    draw_string(font, Vector2(_new_region_rect.position.x + (new_btn_w - new_w_t) * 0.5,
            _new_region_rect.position.y + 24),
        new_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, new_text_col)
    if new_hover:
        EditorTooltip.show_text("Create a new empty region on this realm. A blank region entry is added to the list — click it to open and paint room layouts on its grid.")

    # Child panels are positioned via _layout_panels(); their own _draw()
    # handles tile canvas, tool palette, and tileset picker rendering.


func _build_panels() -> void:
    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    _rlm_tool_palette = RlmToolPalette.new()
    _rlm_tool_palette.editor = self
    _rlm_tool_palette.visible = false
    add_child(_rlm_tool_palette)

    _rlm_canvas = RlmCanvas.new()
    _rlm_canvas.editor = self
    _rlm_canvas.visible = false
    add_child(_rlm_canvas)

    _rlm_tileset_panel = RlmTilesetPanel.new()
    _rlm_tileset_panel.editor = self
    _rlm_tileset_panel.visible = false
    add_child(_rlm_tileset_panel)

    _text_modal = Control.new()
    _text_modal.set_script(preload("res://Space/scripts/editor/env/env_text_modal.gd"))
    _text_modal.visible = false
    add_child(_text_modal)
    _text_modal.submitted.connect(_on_modal_submit)
    _text_modal.cancelled.connect(_on_modal_cancel)


func _layout_panels() -> void:
    var vw := size.x
    var vh := size.y
    if _tutorial_btn != null:
        _tutorial_btn.position = Vector2(vw - 360, 16)
        _tutorial_btn.size = Vector2(100, 32)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)

    var body_y: float = TOPBAR_H + PAD
    var body_h: float = size.y - TOPBAR_H - PAD * 2.0

    var palette_x: float = PAD + LIST_W + PAD
    if _rlm_tool_palette != null:
        _rlm_tool_palette.position = Vector2(palette_x, body_y)
        _rlm_tool_palette.size = Vector2(PALETTE_W, body_h)
        _rlm_tool_palette.visible = visible

    var canvas_x: float = palette_x + PALETTE_W + PAD
    var canvas_w: float = size.x - canvas_x - TILESET_PANEL_W - PAD * 2.0
    if _rlm_canvas != null:
        _rlm_canvas.position = Vector2(canvas_x, body_y)
        _rlm_canvas.size = Vector2(canvas_w, body_h)
        _rlm_canvas.visible = visible

    var ts_x: float = canvas_x + canvas_w + PAD
    if _rlm_tileset_panel != null:
        _rlm_tileset_panel.position = Vector2(ts_x, body_y)
        _rlm_tileset_panel.size = Vector2(TILESET_PANEL_W, body_h)
        _rlm_tileset_panel.visible = visible


func _refresh_tileset_cache() -> void:
    _tileset_indices = EnvIO.list_tileset_indices(pack_id)
    _tileset_textures.clear()
    _tileset_sizes.clear()
    _tileset_names.clear()
    for idx in _tileset_indices:
        var i := int(idx)
        var tex := EnvIO.load_tileset_texture(pack_id, i)
        if tex != null:
            _tileset_textures[i] = tex
        _tileset_sizes[i] = EnvIO.load_tileset_size(pack_id, i)
        _tileset_names[i] = EnvIO.load_tileset_name(pack_id, i)
    if not _tileset_indices.is_empty():
        selected_realm_tileset = int(_tileset_indices[0])
        selected_realm_tile = _snap_to_realm_logical_tile(selected_realm_tile, selected_realm_tileset)


func realm_grid_w() -> int:
    return int(realm_data.get("realm_grid_cells_x", RegIO.DEFAULT_REALM_GRID_X))


func realm_grid_h() -> int:
    return int(realm_data.get("realm_grid_cells_y", RegIO.DEFAULT_REALM_GRID_Y))


func get_realm_tile_layers() -> Array:
    var layers_v: Variant = realm_data.get("realm_tile_layers", [])
    if typeof(layers_v) == TYPE_ARRAY:
        return layers_v
    return []


func get_realm_regions() -> Array:
    var regions_v: Variant = realm_data.get("regions", [])
    if typeof(regions_v) == TYPE_ARRAY:
        return regions_v
    return []


func get_tileset_indices() -> Array:
    return _tileset_indices


func get_tileset_texture(idx: int) -> Texture2D:
    if _tileset_textures.has(idx):
        return _tileset_textures[idx]
    return null


func get_tileset_index_by_name(tileset_name: String) -> int:
    for idx in _tileset_indices:
        var i := int(idx)
        if str(_tileset_names.get(i, "")) == tileset_name:
            return i
    if tileset_name.is_valid_int():
        return int(tileset_name)
    return -1


func get_tileset_texture_by_name(tileset_name: String) -> Texture2D:
    var idx := get_tileset_index_by_name(tileset_name)
    if idx >= 0:
        return get_tileset_texture(idx)
    return null


func get_tileset_name(idx: int) -> String:
    if _tileset_names.has(idx):
        return str(_tileset_names[idx])
    return "Tileset %02d" % idx


func get_tileset_tile_size(idx: int) -> int:
    if _tileset_sizes.has(idx):
        return int(_tileset_sizes[idx])
    return EnvIO.BLOCK_SIZE


func get_tileset_tile_size_by_name(tileset_name: String) -> int:
    var idx := get_tileset_index_by_name(tileset_name)
    if idx >= 0:
        return get_tileset_tile_size(idx)
    return EnvIO.BLOCK_SIZE


func set_selected_tileset(idx: int) -> void:
    selected_realm_tileset = idx
    selected_realm_tile = _snap_to_realm_logical_tile(selected_realm_tile, idx)
    selected_realm_tile_span = Vector2i.ONE
    _realm_paste_preview_active = false


func set_selected_metatile(idx: int) -> void:
    selected_realm_tile = _snap_to_realm_logical_tile(idx, selected_realm_tileset)
    selected_realm_tile_span = Vector2i.ONE
    _realm_paste_preview_active = false


func set_selected_metatile_block(idx: int, logical_w: int, logical_h: int) -> void:
    selected_realm_tile = _snap_to_realm_logical_tile(idx, selected_realm_tileset)
    selected_realm_tile_span = Vector2i(maxi(logical_w, 1), maxi(logical_h, 1))
    _realm_paste_preview_active = false


func get_selected_realm_tile_span() -> Vector2i:
    return selected_realm_tile_span


func _get_tileset_subtile_span(tileset_idx: int) -> int:
    return maxi(get_tileset_tile_size(tileset_idx) / EnvIO.BLOCK_SIZE, 1)


func _is_billboard_realm_layer(layer_idx: int) -> bool:
    return layer_idx == RlmTypes.LAYER_STRUCTURE or layer_idx == RlmTypes.LAYER_SKY


func _snap_to_realm_logical_tile(idx: int, tileset_idx: int) -> int:
    var tex: Texture2D = get_tileset_texture(tileset_idx)
    if tex == null:
        return maxi(idx, 0)
    var tile_px := maxi(get_tileset_tile_size(tileset_idx), EnvIO.BLOCK_SIZE)
    @warning_ignore("integer_division")
    var n_subs := maxi(tile_px / EnvIO.BLOCK_SIZE, 1)
    @warning_ignore("integer_division")
    var grid_cols := maxi(tex.get_width() / EnvIO.BLOCK_SIZE, 1)
    @warning_ignore("integer_division")
    var grid_rows := maxi(tex.get_height() / EnvIO.BLOCK_SIZE, 1)
    var clamped_idx := clampi(idx, 0, grid_cols * grid_rows - 1)
    var sub_col := clamped_idx % grid_cols
    @warning_ignore("integer_division")
    var sub_row := clamped_idx / grid_cols
    @warning_ignore("integer_division")
    var logical_col := sub_col / n_subs
    @warning_ignore("integer_division")
    var logical_row := sub_row / n_subs
    return (logical_row * n_subs) * grid_cols + (logical_col * n_subs)


# ─── Tileset import (shares pool with environment editor) ───────────────

func request_import_tileset() -> void:
    var dlg := FileDialog.new()
    dlg.use_native_dialog = true
    dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    dlg.access = FileDialog.ACCESS_FILESYSTEM
    dlg.filters = PackedStringArray(["*.png ; PNG images"])
    dlg.title = "Import PNG(s) as new tileset"
    dlg.files_selected.connect(_on_tileset_files_selected)
    dlg.canceled.connect(_on_tileset_dialog_closed.bind(dlg))
    dlg.visibility_changed.connect(_on_tileset_dialog_visibility_changed.bind(dlg))
    add_child(dlg)
    dlg.popup_centered_ratio(0.7)


func _on_tileset_dialog_visibility_changed(dlg: FileDialog) -> void:
    if not dlg.visible:
        dlg.queue_free()


func _on_tileset_dialog_closed(dlg: FileDialog) -> void:
    dlg.queue_free()


func _on_tileset_files_selected(paths: PackedStringArray) -> void:
    if paths.is_empty():
        return
    _pending_import_paths = paths
    var prompt := "Pixel size of each logical tile (multiple of %d, ≥ %d). 16 is a plain 16×16 tileset; 32/48/64/… for bigger art. Storage stays 16-px under the hood — large tiles paint as N×N brushes." % [EnvIO.BLOCK_SIZE, EnvIO.BLOCK_SIZE]
    show_text_modal("Tile size",
        "%d" % EnvIO.BLOCK_SIZE,
        prompt,
        Callable(self, "_finish_tileset_import"))


func _finish_tileset_import(tile_size_str: String) -> void:
    var paths := _pending_import_paths
    _pending_import_paths = PackedStringArray()
    if paths.is_empty():
        return
    var tile_size: int = EnvIO.BLOCK_SIZE
    var parsed := int(tile_size_str.strip_edges())
    if parsed >= EnvIO.BLOCK_SIZE and parsed % EnvIO.BLOCK_SIZE == 0:
        tile_size = parsed
    else:
        push_warning("[RealmEditor] tile size '%s' invalid — falling back to %d" % [tile_size_str, EnvIO.BLOCK_SIZE])
    var new_idx := EnvIO.import_tileset(pack_id, paths, tile_size)
    if new_idx < 0:
        return
    var default_name := str(paths[0]).get_file().get_basename()
    if not default_name.is_empty():
        EnvIO.save_tileset_name(pack_id, new_idx, default_name)
    _refresh_tileset_cache()
    selected_realm_tileset = new_idx
    selected_realm_tile = 0
    selected_realm_tile_span = Vector2i.ONE


func show_text_modal(title: String, default_text: String, prompt: String, cb: Callable) -> void:
    _modal_callback = cb
    if _text_modal != null:
        _text_modal.open(title, default_text, prompt)


func _on_modal_submit(text: String) -> void:
    var cb := _modal_callback
    _modal_callback = Callable()
    if cb.is_valid():
        cb.call(text)


func _on_modal_cancel() -> void:
    _modal_callback = Callable()


func copy_realm_region(rect: Rect2i) -> bool:
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size() or rect.size.x <= 0 or rect.size.y <= 0:
        return false
    var clipped := Rect2i(
        Vector2i(
            clampi(rect.position.x, 0, realm_grid_w() - 1),
            clampi(rect.position.y, 0, realm_grid_h() - 1)),
        Vector2i.ZERO)
    var max_x := clampi(rect.end.x, clipped.position.x + 1, realm_grid_w())
    var max_y := clampi(rect.end.y, clipped.position.y + 1, realm_grid_h())
    clipped.size = Vector2i(max_x - clipped.position.x, max_y - clipped.position.y)
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])
    var cells: Array = []
    for y in clipped.size.y:
        var out_row: Array = []
        for x in clipped.size.x:
            out_row.append(null)
        cells.append(out_row)
    for entry_v in tiles:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var col := int(entry.get("col", -1))
        var row := int(entry.get("row", -1))
        if col < clipped.position.x or col >= clipped.end.x or row < clipped.position.y or row >= clipped.end.y:
            continue
        var rel_x := col - clipped.position.x
        var rel_y := row - clipped.position.y
        var copied_entry := entry.duplicate(true)
        if copied_entry.has("anchor_col"):
            var anchor_col := int(copied_entry.get("anchor_col", col))
            var anchor_row := int(copied_entry.get("anchor_row", row))
            var placement_w := maxi(int(copied_entry.get("placement_w", 1)), 1)
            var placement_h := maxi(int(copied_entry.get("placement_h", 1)), 1)
            var clip_left := maxi(anchor_col, clipped.position.x)
            var clip_top := maxi(anchor_row, clipped.position.y)
            var clip_right := mini(anchor_col + placement_w, clipped.end.x)
            var clip_bottom := mini(anchor_row + placement_h, clipped.end.y)
            if clip_right > clip_left and clip_bottom > clip_top:
                var atlas_anchor_x := int(copied_entry.get("anchor_atlas_x", int(copied_entry.get("atlas_x", 0))))
                var atlas_anchor_y := int(copied_entry.get("anchor_atlas_y", int(copied_entry.get("atlas_y", 0))))
                copied_entry["anchor_col"] = clip_left - clipped.position.x
                copied_entry["anchor_row"] = clip_top - clipped.position.y
                copied_entry["anchor_atlas_x"] = atlas_anchor_x + (clip_left - anchor_col)
                copied_entry["anchor_atlas_y"] = atlas_anchor_y + (clip_top - anchor_row)
                copied_entry["placement_w"] = clip_right - clip_left
                copied_entry["placement_h"] = clip_bottom - clip_top
            else:
                copied_entry.erase("anchor_col")
                copied_entry.erase("anchor_row")
                copied_entry.erase("anchor_atlas_x")
                copied_entry.erase("anchor_atlas_y")
                copied_entry.erase("placement_w")
                copied_entry.erase("placement_h")
        cells[rel_y][rel_x] = copied_entry
    _realm_clipboard = {
        "kind": "realm_tiles",
        "width": clipped.size.x,
        "height": clipped.size.y,
        "cells": cells,
    }
    _realm_paste_preview_active = false
    return true


func has_realm_clipboard() -> bool:
    return str(_realm_clipboard.get("kind", "")) == "realm_tiles"


func get_realm_clipboard_size() -> Vector2i:
    if not has_realm_clipboard():
        return Vector2i.ZERO
    return Vector2i(int(_realm_clipboard.get("width", 0)), int(_realm_clipboard.get("height", 0)))


func start_realm_paste_preview() -> bool:
    if not has_realm_clipboard():
        return false
    _realm_paste_preview_active = true
    return true


func cancel_realm_paste_preview() -> bool:
    if not _realm_paste_preview_active:
        return false
    _realm_paste_preview_active = false
    return true


func has_realm_paste_preview() -> bool:
    return _realm_paste_preview_active and has_realm_clipboard()


func paste_realm_clipboard(start_col: int, start_row: int) -> void:
    if not has_realm_paste_preview():
        return
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size():
        return
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])
    var width := int(_realm_clipboard.get("width", 0))
    var height := int(_realm_clipboard.get("height", 0))
    var cells: Array = _realm_clipboard.get("cells", [])
    var changed := false
    for y in height:
        if y >= cells.size():
            continue
        var row_v: Variant = cells[y]
        if typeof(row_v) != TYPE_ARRAY:
            continue
        var row_cells: Array = row_v
        for x in width:
            if x >= row_cells.size():
                continue
            var dst_col := start_col + x
            var dst_row := start_row + y
            if dst_col < 0 or dst_col >= realm_grid_w() or dst_row < 0 or dst_row >= realm_grid_h():
                continue
            var cell_v: Variant = row_cells[x]
            var entry: Dictionary = {}
            if typeof(cell_v) == TYPE_DICTIONARY:
                entry = (cell_v as Dictionary).duplicate(true)
                if entry.has("anchor_col"):
                    entry["anchor_col"] = int(entry.get("anchor_col", 0)) + start_col
                if entry.has("anchor_row"):
                    entry["anchor_row"] = int(entry.get("anchor_row", 0)) + start_row
                if entry.has("anchor_col") and entry.has("anchor_row"):
                    var anchor_col := int(entry.get("anchor_col", dst_col))
                    var anchor_row := int(entry.get("anchor_row", dst_row))
                    var placement_w := maxi(int(entry.get("placement_w", 1)), 1)
                    var placement_h := maxi(int(entry.get("placement_h", 1)), 1)
                    var clip_left := maxi(anchor_col, 0)
                    var clip_top := maxi(anchor_row, 0)
                    var clip_right := mini(anchor_col + placement_w, realm_grid_w())
                    var clip_bottom := mini(anchor_row + placement_h, realm_grid_h())
                    if clip_right > clip_left and clip_bottom > clip_top:
                        entry["anchor_atlas_x"] = int(entry.get("anchor_atlas_x", int(entry.get("atlas_x", 0)))) + (clip_left - anchor_col)
                        entry["anchor_atlas_y"] = int(entry.get("anchor_atlas_y", int(entry.get("atlas_y", 0)))) + (clip_top - anchor_row)
                        entry["anchor_col"] = clip_left
                        entry["anchor_row"] = clip_top
                        entry["placement_w"] = clip_right - clip_left
                        entry["placement_h"] = clip_bottom - clip_top
            if _set_realm_tile_entry(tiles, dst_col, dst_row, entry):
                changed = true
    if changed:
        layer["tiles"] = tiles


func begin_stroke() -> void:
    if _undo != null:
        _undo.begin()


func end_stroke() -> void:
    RegIO.save_realm(pack_id, realm_id, realm_data)
    if _undo != null:
        _undo.commit("paint realm")


func paint_realm_cell(col: int, row: int) -> void:
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size():
        return
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])

    var tileset_name := get_tileset_name(selected_realm_tileset)
    var tex: Texture2D = get_tileset_texture(selected_realm_tileset)
    var atlas_sub_x: int = 0
    var atlas_sub_y: int = 0
    var n_subs: int = _get_tileset_subtile_span(selected_realm_tileset)
    if tex != null:
        @warning_ignore("integer_division")
        var grid_cols: int = maxi(tex.get_width() / EnvIO.BLOCK_SIZE, 1)
        var sub_idx := selected_realm_tile
        atlas_sub_x = sub_idx % grid_cols
        @warning_ignore("integer_division")
        atlas_sub_y = sub_idx / grid_cols

    var span := selected_realm_tile_span
    var changed := false
    var grid_w := realm_grid_w()
    var grid_h := realm_grid_h()
    var logical_w := maxi(span.x, 1)
    var logical_h := maxi(span.y, 1)
    var footprint_w := logical_w * n_subs
    var footprint_h := logical_h * n_subs
    var clipped_w := mini(footprint_w, maxi(grid_w - col, 0))
    var clipped_h := mini(footprint_h, maxi(grid_h - row, 0))
    if clipped_w <= 0 or clipped_h <= 0:
        return
    var billboard_layer := _is_billboard_realm_layer(active_realm_layer)
    for logical_y in logical_h:
        for logical_x in logical_w:
            var world_origin_col := col + logical_x * n_subs
            var world_origin_row := row + logical_y * n_subs
            var atlas_origin_x := atlas_sub_x + logical_x * n_subs
            var atlas_origin_y := atlas_sub_y + logical_y * n_subs
            for sub_y in n_subs:
                for sub_x in n_subs:
                    var dst_col := world_origin_col + sub_x
                    var dst_row := world_origin_row + sub_y
                    if dst_col < 0 or dst_col >= grid_w or dst_row < 0 or dst_row >= grid_h:
                        continue
                    var entry := {
                        "col": dst_col,
                        "row": dst_row,
                        "tileset": tileset_name,
                        "atlas_x": atlas_origin_x + sub_x,
                        "atlas_y": atlas_origin_y + sub_y,
                    }
                    if billboard_layer:
                        entry["anchor_col"] = col
                        entry["anchor_row"] = row
                        entry["anchor_atlas_x"] = atlas_sub_x
                        entry["anchor_atlas_y"] = atlas_sub_y
                        entry["placement_w"] = clipped_w
                        entry["placement_h"] = clipped_h
                    if _set_realm_tile_entry(tiles, dst_col, dst_row, entry):
                        changed = true
    if changed:
        layer["tiles"] = tiles


func erase_realm_cell(col: int, row: int) -> void:
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size():
        return
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])
    var changed := false
    var grid_w := realm_grid_w()
    var grid_h := realm_grid_h()
    if _is_billboard_realm_layer(active_realm_layer):
        var erase_keys: Dictionary = {}
        var fallback_cells: Array = []
        var n_subs_billboard := _get_tileset_subtile_span(selected_realm_tileset)
        var brush_w_billboard := maxi(selected_realm_tile_span.x, 1) * n_subs_billboard
        var brush_h_billboard := maxi(selected_realm_tile_span.y, 1) * n_subs_billboard
        for dy in brush_h_billboard:
            for dx in brush_w_billboard:
                var probe_col := col + dx
                var probe_row := row + dy
                if probe_col < 0 or probe_col >= grid_w or probe_row < 0 or probe_row >= grid_h:
                    continue
                var hit := _find_realm_tile_entry(tiles, probe_col, probe_row)
                if hit.is_empty():
                    fallback_cells.append(Vector2i(probe_col, probe_row))
                    continue
                if hit.has("anchor_col") and hit.has("anchor_row"):
                    var anchor_col := int(hit.get("anchor_col", probe_col))
                    var anchor_row := int(hit.get("anchor_row", probe_row))
                    var placement_w := maxi(int(hit.get("placement_w", 1)), 1)
                    var placement_h := maxi(int(hit.get("placement_h", 1)), 1)
                    erase_keys["%d,%d,%d,%d" % [anchor_col, anchor_row, placement_w, placement_h]] = {
                        "anchor_col": anchor_col,
                        "anchor_row": anchor_row,
                        "placement_w": placement_w,
                        "placement_h": placement_h,
                    }
                else:
                    fallback_cells.append(Vector2i(probe_col, probe_row))
        for data_v in erase_keys.values():
            var data: Dictionary = data_v
            var anchor_col := int(data.get("anchor_col", 0))
            var anchor_row := int(data.get("anchor_row", 0))
            var placement_w := maxi(int(data.get("placement_w", 1)), 1)
            var placement_h := maxi(int(data.get("placement_h", 1)), 1)
            for dy in placement_h:
                for dx in placement_w:
                    var dst_col := anchor_col + dx
                    var dst_row := anchor_row + dy
                    if dst_col < 0 or dst_col >= grid_w or dst_row < 0 or dst_row >= grid_h:
                        continue
                    if _set_realm_tile_entry(tiles, dst_col, dst_row, {}):
                        changed = true
        for cell in fallback_cells:
            if _set_realm_tile_entry(tiles, cell.x, cell.y, {}):
                changed = true
        if changed:
            layer["tiles"] = tiles
        return
    var n_subs := _get_tileset_subtile_span(selected_realm_tileset)
    var brush_w := maxi(selected_realm_tile_span.x, 1) * n_subs
    var brush_h := maxi(selected_realm_tile_span.y, 1) * n_subs
    for dy in brush_h:
        for dx in brush_w:
            if col + dx < 0 or col + dx >= grid_w or row + dy < 0 or row + dy >= grid_h:
                continue
            if _set_realm_tile_entry(tiles, col + dx, row + dy, {}):
                changed = true
    if changed:
        layer["tiles"] = tiles


func _set_realm_tile_entry(tiles: Array, col: int, row: int, entry: Dictionary) -> bool:
    var remove_entry := entry.is_empty()
    var normalized: Dictionary = {}
    if not remove_entry:
        normalized = entry.duplicate(true)
        normalized["col"] = col
        normalized["row"] = row
    for i in range(tiles.size() - 1, -1, -1):
        var entry_v: Variant = tiles[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var existing: Dictionary = entry_v
        if int(existing.get("col", -1)) != col or int(existing.get("row", -1)) != row:
            continue
        if remove_entry:
            tiles.remove_at(i)
            return true
        var changed := false
        for key_v in normalized.keys():
            var key := str(key_v)
            if existing.get(key, null) != normalized[key_v]:
                existing[key] = normalized[key_v]
                changed = true
        return changed
    if remove_entry:
        return false
    tiles.append(normalized)
    return true


func _find_realm_tile_entry(tiles: Array, col: int, row: int) -> Dictionary:
    for i in range(tiles.size() - 1, -1, -1):
        var entry_v: Variant = tiles[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var existing: Dictionary = entry_v
        if int(existing.get("col", -1)) == col and int(existing.get("row", -1)) == row:
            return existing
    return {}


func pick_realm_cell(col: int, row: int) -> void:
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size():
        return
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])
    for entry_v in tiles:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        if int(entry.get("col", -1)) == col and int(entry.get("row", -1)) == row:
            var ts_name := str(entry.get("tileset", ""))
            var resolved_idx := get_tileset_index_by_name(ts_name)
            if resolved_idx >= 0:
                selected_realm_tileset = resolved_idx
            var tex: Texture2D = get_tileset_texture(selected_realm_tileset)
            if tex != null:
                var n_subs := _get_tileset_subtile_span(selected_realm_tileset)
                @warning_ignore("integer_division")
                var grid_cols := maxi(tex.get_width() / EnvIO.BLOCK_SIZE, 1)
                var sub_idx := int(entry.get("atlas_y", 0)) * grid_cols + int(entry.get("atlas_x", 0))
                selected_realm_tile = _snap_to_realm_logical_tile(sub_idx, selected_realm_tileset)
                selected_realm_tile_span = Vector2i.ONE
            active_tool = RlmTypes.TOOL_PAINT
            return


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("realm")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


func fill_realm_cells(start_col: int, start_row: int) -> void:
    var layers := get_realm_tile_layers()
    if active_realm_layer < 0 or active_realm_layer >= layers.size():
        return
    if _undo != null:
        _undo.begin()
    var grid_w := realm_grid_w()
    var grid_h := realm_grid_h()
    var layer: Dictionary = layers[active_realm_layer]
    var tiles: Array = layer.get("tiles", [])

    var existing: Dictionary = {}
    for entry_v in tiles:
        if typeof(entry_v) == TYPE_DICTIONARY:
            var entry: Dictionary = entry_v
            existing["%d,%d" % [int(entry.get("col", 0)), int(entry.get("row", 0))]] = true

    var target_key := "%d,%d" % [start_col, start_row]
    var target_filled: bool = existing.has(target_key)

    var visited: Dictionary = {}
    var queue: Array = [Vector2i(start_col, start_row)]
    visited[target_key] = true
    var fill_cells: Array = []

    while not queue.is_empty():
        var cell: Vector2i = queue.pop_front()
        var key := "%d,%d" % [cell.x, cell.y]
        var is_filled: bool = existing.has(key)
        if is_filled != target_filled:
            continue
        fill_cells.append(cell)
        for dir_offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var nb: Vector2i = cell + dir_offset
            if nb.x < 0 or nb.x >= grid_w or nb.y < 0 or nb.y >= grid_h:
                continue
            var nb_key := "%d,%d" % [nb.x, nb.y]
            if visited.has(nb_key):
                continue
            visited[nb_key] = true
            queue.append(nb)
        if fill_cells.size() > 2048:
            break

    var saved_span := selected_realm_tile_span
    selected_realm_tile_span = Vector2i.ONE
    for cell in fill_cells:
        paint_realm_cell(cell.x, cell.y)
    selected_realm_tile_span = saved_span
    RegIO.save_realm(pack_id, realm_id, realm_data)
    if _undo != null:
        _undo.commit("fill realm")
