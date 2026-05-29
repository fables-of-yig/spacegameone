extends Control

const EnvIO = preload("res://Space/scripts/shared/env/env_io.gd")
const EnvTypes = preload("res://Space/scripts/editor/env/env_types.gd")
const PackAssetIndex = preload("res://Space/scripts/shared/pack_asset_index.gd")
const RegIO = preload("res://Space/scripts/shared/reg/reg_io.gd")
const EntIO = preload("res://Space/scripts/shared/ent/ent_io.gd")
const _ContentValidator = preload("res://Space/scripts/editor/content_validator.gd")
const _UndoManager = preload("res://Space/scripts/editor/undo_manager.gd")

# Environment (room) editor main controller. Holds the full rooms.json
# tree for the active pack, the active tool / layer / tileset / metatile
# selection, and the cached tileset textures. Owns five child Controls
# (topbar, tool palette, canvas, tileset panel) laid out in a fixed split.
#
# Module layout under Space/scripts/editor/env/:
#   env_io.gd             — rooms.json + tileset IO (static)
#   env_canvas.gd         — tilemap canvas (pan/zoom/paint)
#   env_tool_palette.gd   — left sidebar tool/layer buttons
#   env_tileset_panel.gd  — right sidebar metatile picker
#   env_topbar.gd         — top bar room selector + save/close
#
# Tile packed-value encoding comes from MvTileValue (bit layout defined in
# MV/scripts/tile_value.gd). Saves preserve unknown room fields verbatim.

signal closed

var pack_id: String = ""
var region_id: String = ""
var rooms_data: Dictionary = {}
var current_room_addr: String = ""
var active_tool: int = EnvTypes.TOOL_PAINT
# Active sidebar mode (MODE_TILE / MODE_COLLISION / MODE_ENTITIES / MODE_DOORS).
# When MODE_TILE, active_tile_layer_idx points at the layer being painted.
var active_mode: int = EnvTypes.MODE_TILE
var active_tile_layer_idx: int = 0
var selected_tileset_id: int = 0
var selected_metatile_idx: int = 1
var selected_metatile_span: Vector2i = Vector2i.ONE
var selected_collision_nibble: int = EnvTypes.BT_SOLID
var selected_slope_shape: int = 1
var selected_slope_hflip: bool = false
var selected_slope_vflip: bool = false
var selected_crumble_reload_only: bool = false
var selected_entity_type: String = "npc"
var selected_door_direction: String = "right"
var selected_door_target_room: String = ""
var selected_door_launch_to_space: bool = false
var selected_door_enabled: bool = true
var selected_door_locked: bool = false
var selected_door_required_item_id: String = ""
var selected_door_required_item_count: int = 1
var selected_door_required_var_name: String = ""
var selected_door_required_var_value: Variant = 1
var selected_door_required_global_tag: String = ""
var selected_door_blocked_event_name: String = ""
var selected_door_success_event_name: String = ""
var selected_door_arrive_event_name: String = ""
var selected_zone_kind: String = "shader"
var selected_background_asset: String = ""
var selected_background_image_id: String = ""
var selected_zone_id: String = ""
var selected_shader_region_id: String = ""
var show_collision: bool = false
var dirty: bool = false

# Cached tileset textures, logical tile sizes, and display names keyed
# by tileset index. _tileset_sizes stores the authoring tile size in
# pixels (a multiple of EnvIO.BLOCK_SIZE). Tilesets without a sidecar
# fall back to BLOCK_SIZE for size and "Tileset NN" for name.
var _tileset_textures: Dictionary = {}
var _tileset_indices: Array = []
var _tileset_sizes: Dictionary = {}
var _tileset_names: Dictionary = {}
var _backdrop_textures: Dictionary = {}
var _entity_preview_textures: Dictionary = {}
var _entity_defs_by_id: Dictionary = {}

# Child panels
var topbar: Control = null
var tool_palette: Control = null
var canvas: Control = null
var tileset_panel: Control = null
var text_modal: Control = null
var meta_modal: Control = null
var spike_modal: Control = null
var anim_modal: Control = null
var entity_modal: Control = null
var room_trigger_modal: Control = null
var variants_modal: Control = null
var _trigger_camera_preview: Array = []
var _spike_profiles: Array = []
var _slope_shapes: Array = []
var _anim_pending_layer_idx: int = -1
var _anim_pending_row: int = -1
var _anim_pending_col: int = -1

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _skip_close_frame: bool = true
var _modal_callback: Callable = Callable()
var undo_mgr: RefCounted = null
var _stroke_snapshot: Dictionary = {}
# Staged import state. We don't use Callable.bind for the PackedStringArray
# path list because binding non-Object Variants through the text-modal
# callback chain is fiddly; an instance var is simpler.
var _pending_import_paths: PackedStringArray = PackedStringArray()
# Same reasoning as _pending_import_paths — keep rename target on the
# instance instead of binding through the text-modal callback chain.
var _pending_rename_idx: int = -1
# Last directory used in the tileset import/append picker, so the OS
# dialog reopens where the user was last working instead of snapping
# back to the project root every time.
var _last_tileset_import_dir: String = ""
var _grid_clipboard: Dictionary = {}
var _grid_paste_preview_active: bool = false

const TOPBAR_H: float = 64.0
const SIDEBAR_W: float = 220.0
const RIGHT_PANEL_W: float = 280.0
const RIGHT_PANEL_W_BG_IMAGES: float = 420.0
const RIGHT_PANEL_W_SHADERS: float = 520.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    undo_mgr = _UndoManager.new()
    _build_layout.call_deferred()


func _build_layout() -> void:
    # NOTE on child order: topbar is added AFTER the three main panels so
    # its room-list dropdown can overflow past the 64px strip and still
    # draw on top of the canvas. Modals are added last so they cover the
    # topbar when open. When the topbar's dropdown is open it expands its
    # own rect to full-screen so clicks still route to it — see
    # env_topbar._open_room_list.
    tool_palette = Control.new()
    tool_palette.set_script(preload("res://Space/scripts/editor/env/env_tool_palette.gd"))
    tool_palette.editor = self
    add_child(tool_palette)

    canvas = Control.new()
    canvas.set_script(preload("res://Space/scripts/editor/env/env_canvas.gd"))
    canvas.editor = self
    add_child(canvas)

    tileset_panel = Control.new()
    tileset_panel.set_script(preload("res://Space/scripts/editor/env/env_tileset_panel.gd"))
    tileset_panel.editor = self
    add_child(tileset_panel)

    topbar = Control.new()
    topbar.set_script(preload("res://Space/scripts/editor/env/env_topbar.gd"))
    topbar.editor = self
    add_child(topbar)

    text_modal = Control.new()
    text_modal.set_script(preload("res://Space/scripts/editor/env/env_text_modal.gd"))
    text_modal.visible = false
    add_child(text_modal)
    text_modal.submitted.connect(_on_modal_submit)
    text_modal.cancelled.connect(_on_modal_cancel)

    meta_modal = Control.new()
    meta_modal.set_script(preload("res://Space/scripts/editor/env/env_meta_modal.gd"))
    meta_modal.visible = false
    add_child(meta_modal)
    meta_modal.submitted.connect(_on_meta_modal_submit)
    meta_modal.cancelled.connect(_on_meta_modal_cancel)

    spike_modal = Control.new()
    spike_modal.set_script(preload("res://Space/scripts/editor/env/env_spike_modal.gd"))
    spike_modal.visible = false
    add_child(spike_modal)
    spike_modal.submitted.connect(_on_spike_modal_submit)
    spike_modal.cancelled.connect(_on_spike_modal_cancel)

    anim_modal = Control.new()
    anim_modal.set_script(preload("res://Space/scripts/editor/env/env_anim_modal.gd"))
    anim_modal.visible = false
    add_child(anim_modal)
    anim_modal.submitted.connect(_on_anim_modal_submit)
    anim_modal.cancelled.connect(_on_anim_modal_cancel)

    entity_modal = Control.new()
    entity_modal.set_script(preload("res://Space/scripts/editor/env/env_entity_modal.gd"))
    entity_modal.visible = false
    add_child(entity_modal)
    entity_modal.submitted.connect(_on_entity_modal_submit)
    entity_modal.cancelled.connect(_on_entity_modal_cancel)

    room_trigger_modal = Control.new()
    room_trigger_modal.set_script(preload("res://Space/scripts/editor/trigger_editor.gd"))
    room_trigger_modal.visible = false
    add_child(room_trigger_modal)
    room_trigger_modal.closed.connect(_on_room_trigger_modal_closed)
    room_trigger_modal.status_changed.connect(_on_room_trigger_status_changed)
    room_trigger_modal.camera_preview_changed.connect(_on_room_trigger_camera_preview_changed)
    room_trigger_modal.camera_preview_cleared.connect(_on_room_trigger_camera_preview_cleared)

    variants_modal = Control.new()
    variants_modal.set_script(preload("res://Space/scripts/editor/env/env_variants_modal.gd"))
    variants_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    variants_modal.visible = false
    add_child(variants_modal)
    variants_modal.submitted.connect(_on_variants_modal_submit)
    variants_modal.cancelled.connect(_on_variants_modal_cancel)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    _layout_children()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _layout_children() -> void:
    if topbar == null:
        return
    var vw := size.x
    var vh := size.y
    var right_panel_w := _current_right_panel_width()
    topbar.position = Vector2.ZERO
    topbar.size = Vector2(vw, TOPBAR_H)
    tool_palette.position = Vector2(0, TOPBAR_H)
    tool_palette.size = Vector2(SIDEBAR_W, vh - TOPBAR_H)
    tileset_panel.position = Vector2(vw - right_panel_w, TOPBAR_H)
    tileset_panel.size = Vector2(right_panel_w, vh - TOPBAR_H)
    canvas.position = Vector2(SIDEBAR_W, TOPBAR_H)
    canvas.size = Vector2(vw - SIDEBAR_W - right_panel_w, vh - TOPBAR_H)
    if text_modal != null:
        text_modal.position = Vector2.ZERO
        text_modal.size = Vector2(vw, vh)
    if meta_modal != null:
        meta_modal.position = Vector2.ZERO
        meta_modal.size = Vector2(vw, vh)
    if spike_modal != null:
        spike_modal.position = Vector2.ZERO
        spike_modal.size = Vector2(vw, vh)
    if anim_modal != null:
        anim_modal.position = Vector2.ZERO
        anim_modal.size = Vector2(vw, vh)
    if entity_modal != null:
        entity_modal.position = Vector2.ZERO
        entity_modal.size = Vector2(vw, vh)
    if room_trigger_modal != null:
        room_trigger_modal.position = Vector2.ZERO
        room_trigger_modal.size = Vector2(vw, vh)
    if _tutorial_btn != null:
        # Keep the tutorial affordance on the top strip, but leave it well
        # clear of the PLAY/CHECK/META/SAVE/CLOSE cluster on the right.
        _tutorial_btn.position = Vector2(maxf(16.0, vw - 644.0), 16)
        _tutorial_btn.size = Vector2(100, 32)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)


func _current_right_panel_width() -> float:
    if active_mode == EnvTypes.MODE_BG_IMAGES:
        return RIGHT_PANEL_W_BG_IMAGES
    if active_mode == EnvTypes.MODE_ZONES:
        return RIGHT_PANEL_W_SHADERS
    return RIGHT_PANEL_W


func open_editor(p_pack_id: String = "", p_region_id: String = "", p_room_addr: String = ""):
    pack_id = p_pack_id
    region_id = p_region_id
    visible = true
    _skip_close_frame = true
    _backdrop_textures.clear()
    _entity_preview_textures.clear()
    _entity_defs_by_id.clear()

    # Ensure the pack has at least a default tileset seeded on disk.
    EnvIO.load_or_init(pack_id)
    if region_id != "":
        rooms_data = RegIO.load_region_rooms(pack_id, region_id)
    else:
        rooms_data = EnvIO.load_or_init(pack_id)
    _refresh_tileset_cache()

    if not _tileset_indices.is_empty():
        selected_tileset_id = int(_tileset_indices[0])
    else:
        selected_tileset_id = 0

    var rooms: Dictionary = rooms_data.get("rooms", {})
    if p_room_addr != "" and rooms.has(p_room_addr):
        current_room_addr = p_room_addr
    else:
        var start := str(rooms_data.get("start_room", ""))
        if start.is_empty() or not rooms.has(start):
            var keys := rooms.keys()
            if keys.is_empty():
                current_room_addr = ""
            else:
                current_room_addr = str(keys[0])
        else:
            current_room_addr = start

    _spike_profiles = EnvIO.load_spike_profiles(pack_id)
    _slope_shapes = EnvIO.load_slope_shapes(pack_id)
    if _slope_shapes.size() <= 1:
        selected_slope_shape = 0
    else:
        selected_slope_shape = clampi(selected_slope_shape, 1, _slope_shapes.size() - 1)

    active_tool = EnvTypes.TOOL_PAINT
    active_mode = EnvTypes.MODE_TILE
    active_tile_layer_idx = _default_active_tile_layer_idx()
    selected_metatile_idx = _snap_to_metatile(1, selected_tileset_id)
    selected_metatile_span = Vector2i.ONE
    selected_background_image_id = ""
    selected_zone_id = ""
    selected_shader_region_id = ""
    _grid_paste_preview_active = false
    dirty = false

    if is_inside_tree():
        _layout_children()


func _process(_delta):
    if _skip_close_frame:
        _skip_close_frame = false
        return


func _input(event):
    if not visible:
        return
    if _skip_close_frame:
        return
    if room_trigger_modal != null and room_trigger_modal.visible:
        return
    if text_modal != null and text_modal.visible:
        return
    if meta_modal != null and meta_modal.visible:
        return
    if spike_modal != null and spike_modal.visible:
        return
    if anim_modal != null and anim_modal.visible:
        return
    if entity_modal != null and entity_modal.visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var ke: InputEventKey = event
        if ke.keycode == KEY_9 and ke.ctrl_pressed and not ke.shift_pressed and not ke.alt_pressed:
            get_viewport().set_input_as_handled()
            request_playtest()
            return
        if ke.keycode == KEY_Z and ke.ctrl_pressed and not ke.alt_pressed:
            if ke.shift_pressed:
                if undo_mgr != null and undo_mgr.can_redo():
                    var desc: String = undo_mgr.redo()
                    print("[EnvEditor] redo: %s" % desc)
            else:
                if undo_mgr != null and undo_mgr.can_undo():
                    var desc: String = undo_mgr.undo()
                    print("[EnvEditor] undo: %s" % desc)
            get_viewport().set_input_as_handled()
            return
        if ke.keycode == KEY_Y and ke.ctrl_pressed and not ke.shift_pressed and not ke.alt_pressed:
            if undo_mgr != null and undo_mgr.can_redo():
                var desc: String = undo_mgr.redo()
                print("[EnvEditor] redo: %s" % desc)
            get_viewport().set_input_as_handled()
            return
        if ke.keycode == KEY_C and ke.ctrl_pressed and not ke.shift_pressed and not ke.alt_pressed:
            if canvas != null and canvas.has_method("copy_selection_to_clipboard"):
                if bool(canvas.call("copy_selection_to_clipboard")):
                    get_viewport().set_input_as_handled()
                    return
        if ke.keycode == KEY_V and ke.ctrl_pressed and not ke.shift_pressed and not ke.alt_pressed:
            if start_grid_paste_preview():
                get_viewport().set_input_as_handled()
                return
        if ke.keycode == KEY_ESCAPE:
            if cancel_grid_paste_preview():
                get_viewport().set_input_as_handled()
                return
            # Close the tileset dropdown first if it's open — ESC should
            # dismiss transient UI before leaving the editor entirely.
            if tileset_panel != null and tileset_panel.has_method("close_dropdown_if_open"):
                if bool(tileset_panel.call("close_dropdown_if_open")):
                    get_viewport().set_input_as_handled()
                    return
            request_close()
            get_viewport().set_input_as_handled()


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("environment")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


# ─── Tool/state setters called by child panels ───────────────────────────

func set_active_tool(t: int) -> void:
    active_tool = t

func set_active_mode(m: int) -> void:
    if m == EnvTypes.MODE_DOORS:
        selected_zone_kind = "door"
        m = EnvTypes.MODE_ZONES
    elif m == EnvTypes.MODE_SHADERS:
        selected_zone_kind = "shader"
        m = EnvTypes.MODE_ZONES
    active_mode = m
    if active_mode == EnvTypes.MODE_BG_IMAGES and selected_background_asset.is_empty():
        var backdrops := get_available_backdrop_images()
        if not backdrops.is_empty():
            selected_background_asset = str(backdrops[0])
    if is_inside_tree():
        _layout_children()

func set_active_tile_layer(idx: int) -> void:
    var layers := _get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return
    active_mode = EnvTypes.MODE_TILE
    active_tile_layer_idx = idx

func _default_active_tile_layer_idx() -> int:
    # Prefer the first MAIN-role layer; otherwise first layer; otherwise 0.
    var layers := _get_tile_layers()
    for i in layers.size():
        var layer_v: Variant = layers[i]
        if typeof(layer_v) == TYPE_DICTIONARY and str((layer_v as Dictionary).get("role", "")) == EnvTypes.ROLE_MAIN:
            return i
    if layers.size() > 0:
        return 0
    return 0

func set_selected_tileset(idx: int) -> void:
    selected_tileset_id = idx
    # Keep the brush aligned to the new tileset's metatile grid — otherwise
    # the picker highlight doesn't show up on anything when the old idx
    # isn't a valid top-left for the new tile_size.
    selected_metatile_idx = _snap_to_metatile(selected_metatile_idx, idx)
    selected_metatile_span = Vector2i.ONE
    _grid_paste_preview_active = false

func set_selected_metatile(idx: int) -> void:
    selected_metatile_idx = _snap_to_metatile(idx, selected_tileset_id)
    selected_metatile_span = Vector2i.ONE
    _grid_paste_preview_active = false


func set_selected_metatile_block(idx: int, logical_w: int, logical_h: int) -> void:
    selected_metatile_idx = _snap_to_metatile(idx, selected_tileset_id)
    selected_metatile_span = Vector2i(maxi(logical_w, 1), maxi(logical_h, 1))
    _grid_paste_preview_active = false


func get_selected_metatile_span() -> Vector2i:
    return selected_metatile_span

func set_selected_collision_nibble(n: int) -> void:
    selected_collision_nibble = n & 0xF

func set_selected_slope_shape(shape_idx: int) -> void:
    if _slope_shapes.size() <= 1:
        selected_slope_shape = 0
        return
    selected_slope_shape = clampi(shape_idx, 1, _slope_shapes.size() - 1)

func set_selected_slope_hflip(enabled: bool) -> void:
    selected_slope_hflip = enabled

func set_selected_slope_vflip(enabled: bool) -> void:
    selected_slope_vflip = enabled

func toggle_selected_slope_hflip() -> void:
    selected_slope_hflip = not selected_slope_hflip

func toggle_selected_slope_vflip() -> void:
    selected_slope_vflip = not selected_slope_vflip

func set_selected_crumble_reload_only(enabled: bool) -> void:
    selected_crumble_reload_only = enabled

func toggle_selected_crumble_reload_only() -> void:
    selected_crumble_reload_only = not selected_crumble_reload_only

func set_selected_entity_type(t: String) -> void:
    selected_entity_type = t

func set_selected_door_direction(d: String) -> void:
    selected_door_direction = d
    _apply_selected_door_fields_to_zone()

func set_selected_door_target_room(addr: String) -> void:
    selected_door_target_room = addr
    selected_door_launch_to_space = false
    _apply_selected_door_fields_to_zone()

func set_selected_door_launch_to_space(enabled: bool) -> void:
    selected_door_launch_to_space = enabled
    _apply_selected_door_fields_to_zone()


func _apply_selected_door_fields_to_zone() -> void:
    if get_selected_zone_kind() != "door":
        return
    update_selected_zone({
        "direction": selected_door_direction,
        "target_door_id": selected_door_target_room,
        "target_room": "",
        "launch_to_space": selected_door_launch_to_space,
        "enabled": selected_door_enabled,
        "locked": selected_door_locked,
        "required_item_id": selected_door_required_item_id,
        "required_item_count": selected_door_required_item_count,
        "required_var_name": selected_door_required_var_name,
        "required_var_value": selected_door_required_var_value,
        "required_global_tag": selected_door_required_global_tag,
        "blocked_event_name": selected_door_blocked_event_name,
        "success_event_name": selected_door_success_event_name,
        "arrive_event_name": selected_door_arrive_event_name,
    })


func _sync_selected_door_fields(entry: Dictionary) -> void:
    selected_door_direction = str(entry.get("direction", selected_door_direction))
    selected_door_target_room = str(entry.get("target_door_id", entry.get("target_room", selected_door_target_room)))
    selected_door_launch_to_space = bool(entry.get("launch_to_space", selected_door_launch_to_space))
    selected_door_enabled = bool(entry.get("enabled", selected_door_enabled))
    selected_door_locked = bool(entry.get("locked", selected_door_locked))
    selected_door_required_item_id = str(entry.get("required_item_id", selected_door_required_item_id)).strip_edges()
    selected_door_required_item_count = maxi(1, int(entry.get("required_item_count", selected_door_required_item_count)))
    selected_door_required_var_name = str(entry.get("required_var_name", selected_door_required_var_name)).strip_edges()
    selected_door_required_var_value = entry.get("required_var_value", selected_door_required_var_value)
    selected_door_required_global_tag = str(entry.get("required_global_tag", selected_door_required_global_tag)).strip_edges()
    selected_door_blocked_event_name = str(entry.get("blocked_event_name", selected_door_blocked_event_name)).strip_edges()
    selected_door_success_event_name = str(entry.get("success_event_name", selected_door_success_event_name)).strip_edges()
    selected_door_arrive_event_name = str(entry.get("arrive_event_name", selected_door_arrive_event_name)).strip_edges()


func set_selected_zone_kind(kind: String) -> void:
    selected_zone_kind = _normalize_zone_kind(kind)

func switch_to_room(addr: String) -> void:
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if rooms.has(addr):
        current_room_addr = addr
        selected_background_image_id = ""
        selected_zone_id = ""
        selected_shader_region_id = ""


# ─── Queries used by child panels ────────────────────────────────────────

func get_current_room() -> Dictionary:
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return {}
    var rooms: Dictionary = rooms_v
    var room_v: Variant = rooms.get(current_room_addr, {})
    if typeof(room_v) != TYPE_DICTIONARY:
        return {}
    var room: Dictionary = room_v
    EnvIO.normalize_parallax_layers(room)
    EnvIO.normalize_background_images(room)
    EnvIO.normalize_background_image(room)
    EnvIO.normalize_shader_regions(room)
    EnvIO.normalize_zones(room)
    EnvIO.normalize_weather(room)
    return room

func get_room_addrs() -> Array:
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return []
    var rooms: Dictionary = rooms_v
    var keys := rooms.keys()
    keys.sort()
    return keys

func get_tileset_texture(idx: int) -> Texture2D:
    if _tileset_textures.has(idx):
        return _tileset_textures[idx]
    return null

func get_tileset_indices() -> Array:
    return _tileset_indices

# Logical tile size (in px) for the given tileset. Multiple of BLOCK_SIZE.
# Tilesets without a sidecar fall back to BLOCK_SIZE.
func get_tileset_tile_size(idx: int) -> int:
    if _tileset_sizes.has(idx):
        return int(_tileset_sizes[idx])
    return EnvIO.BLOCK_SIZE

# Display name for a tileset. Falls back to "Tileset NN" via EnvIO when
# the cache doesn't have an entry for this idx yet.
func get_tileset_name(idx: int) -> String:
    if _tileset_names.has(idx):
        return str(_tileset_names[idx])
    return "Tileset %02d" % idx

# Atlas width in 16-px sub-tile columns. Used by metatile brushes to
# linearize (row, col) → sub-tile idx in the same way MvTileValue does.
# Returns 0 when the texture isn't loaded (caller should fall back).
func get_tileset_grid_cols(idx: int) -> int:
    var tex := get_tileset_texture(idx)
    if tex == null:
        return 0
    var w := int(tex.get_width())
    if w <= 0:
        return 0
    @warning_ignore("integer_division")
    var cols := w / EnvIO.BLOCK_SIZE
    return cols


func get_slope_shapes() -> Array:
    return _slope_shapes


func get_selected_slope_info() -> Dictionary:
    return get_slope_info(selected_slope_shape, selected_slope_hflip, selected_slope_vflip)


func get_selected_crumble_info() -> Dictionary:
    return {
        "reload_only": selected_crumble_reload_only,
        "label": "Reload-only" if selected_crumble_reload_only else "Respawn",
        "desc": "Stays gone until you leave/re-enter the room." if selected_crumble_reload_only else "Fades out, stays gone 4s, then returns.",
    }


func get_slope_info(shape_idx: int, hflip: bool, vflip: bool) -> Dictionary:
    var info := {
        "valid": false,
        "shape": shape_idx,
        "hflip": hflip,
        "vflip": vflip,
        "label": "No slope",
        "grade_label": "",
        "left_y": 16,
        "right_y": 16,
        "angle_deg": 0,
        "solid_samples": 0,
    }
    if shape_idx < 0 or shape_idx >= _slope_shapes.size():
        return info
    var shape_v: Variant = _slope_shapes[shape_idx]
    if typeof(shape_v) != TYPE_ARRAY:
        return info
    var shape: Array = shape_v
    if shape.is_empty():
        return info
    var first_x := -1
    var last_x := -1
    for x in shape.size():
        var sample := int(shape[x])
        if sample >= 16:
            continue
        if first_x < 0:
            first_x = x
        last_x = x
    if first_x < 0 or last_x < 0:
        info["label"] = "Empty slope"
        return info
    var left_y := _slope_surface_y(shape, 0, hflip, vflip)
    var right_y := _slope_surface_y(shape, shape.size() - 1, hflip, vflip)
    var dy := right_y - left_y
    var run := maxi(last_x - first_x, 1)
    var angle := int(round(rad_to_deg(atan(float(abs(dy)) / float(run)))))
    var direction := "flat"
    if dy < 0:
        direction = "up-right"
    elif dy > 0:
        direction = "up-left"
    var surface_label := "ceiling" if vflip else "floor"
    var grade_label := "rise %d / run %d (~%d deg)" % [abs(dy), run, angle]
    info["valid"] = true
    info["left_y"] = left_y
    info["right_y"] = right_y
    info["angle_deg"] = angle
    info["solid_samples"] = last_x - first_x + 1
    info["label"] = "%s %s" % [surface_label.capitalize(), direction]
    info["grade_label"] = grade_label
    return info


func get_slope_info_at(row: int, col: int) -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return {}
    var collision_v: Variant = room.get("collision", [])
    if typeof(collision_v) != TYPE_ARRAY:
        return {}
    var collision: Array = collision_v
    if row < 0 or row >= collision.size():
        return {}
    var row_v: Variant = collision[row]
    if typeof(row_v) != TYPE_ARRAY:
        return {}
    var cells: Array = row_v
    if col < 0 or col >= cells.size():
        return {}
    if (int(cells[col]) & 0xF) != EnvTypes.BT_SLOPE:
        return {}
    var slope_state := EnvTypes.decode_slope_bts(_get_bts_value(room, row, col), _slope_shapes.size())
    return get_slope_info(int(slope_state.get("shape", 0)), bool(slope_state.get("hflip", false)), bool(slope_state.get("vflip", false)))


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


func _slope_surface_y(shape: Array, x: int, hflip: bool, vflip: bool) -> int:
    if shape.is_empty():
        return 16
    var sample_x := clampi(x, 0, shape.size() - 1)
    if hflip:
        sample_x = shape.size() - 1 - sample_x
    var y := int(shape[sample_x])
    if y >= 16:
        return 16
    if vflip:
        return 16 - y
    return y


func _get_bts_grid(room: Dictionary) -> Array:
    var bts_v: Variant = room.get("bts", [])
    if typeof(bts_v) == TYPE_ARRAY:
        return bts_v
    return []


func _get_bts_value(room: Dictionary, row: int, col: int) -> int:
    var bts := _get_bts_grid(room)
    if row < 0 or row >= bts.size():
        return 0
    var row_v: Variant = bts[row]
    if typeof(row_v) != TYPE_ARRAY:
        return 0
    var arr: Array = row_v
    if col < 0 or col >= arr.size():
        return 0
    return int(arr[col])


func _set_bts_value(room: Dictionary, row: int, col: int, value: int) -> bool:
    var bts := _get_bts_grid(room)
    if row < 0 or row >= bts.size():
        return false
    var row_v: Variant = bts[row]
    if typeof(row_v) != TYPE_ARRAY:
        return false
    var arr: Array = row_v
    if col < 0 or col >= arr.size():
        return false
    if int(arr[col]) == value:
        return false
    arr[col] = value
    return true


func _selected_slope_bts() -> int:
    return EnvTypes.encode_slope_bts(selected_slope_shape, selected_slope_hflip, selected_slope_vflip)


func _selected_crumble_bts() -> int:
    return EnvTypes.encode_crumble_bts(selected_crumble_reload_only)


func _sync_selected_slope_from_cell(room: Dictionary, row: int, col: int) -> void:
    var slope_state := EnvTypes.decode_slope_bts(_get_bts_value(room, row, col), _slope_shapes.size())
    selected_slope_shape = int(slope_state.get("shape", selected_slope_shape))
    selected_slope_hflip = bool(slope_state.get("hflip", false))
    selected_slope_vflip = bool(slope_state.get("vflip", false))


func _sync_selected_crumble_from_cell(room: Dictionary, row: int, col: int) -> void:
    selected_crumble_reload_only = EnvTypes.crumble_is_reload_only(_get_bts_value(room, row, col))


func _paint_collision_metadata(room: Dictionary, row: int, col: int, old_nibble: int, new_nibble: int) -> bool:
    if new_nibble == EnvTypes.BT_SLOPE:
        return _set_bts_value(room, row, col, _selected_slope_bts())
    if new_nibble == EnvTypes.BT_CRUMBLE:
        return _set_bts_value(room, row, col, _selected_crumble_bts())
    if new_nibble == EnvTypes.BT_SPIKE:
        if old_nibble == EnvTypes.BT_SPIKE:
            return false
        return _set_bts_value(room, row, col, 0)
    return _set_bts_value(room, row, col, 0)


func _flood_fill_collision(room: Dictionary, layer: Array, start_row: int, start_col: int, from_val: int, to_val: int) -> bool:
    var rows := layer.size()
    if rows == 0:
        return false
    var cols := (layer[0] as Array).size()
    if start_row < 0 or start_row >= rows or start_col < 0 or start_col >= cols:
        return false
    if from_val == to_val and to_val != EnvTypes.BT_SLOPE:
        return false
    var stack: Array[Vector2i] = [Vector2i(start_col, start_row)]
    var changed := false
    while not stack.is_empty():
        var cell: Vector2i = stack.pop_back()
        var col := cell.x
        var row := cell.y
        if row < 0 or row >= rows or col < 0 or col >= cols:
            continue
        var row_ref: Array = layer[row]
        var current := int(row_ref[col])
        if current != from_val:
            continue
        if current == to_val and to_val != EnvTypes.BT_SLOPE:
            continue
        row_ref[col] = to_val
        _paint_collision_metadata(room, row, col, current, to_val)
        changed = true
        stack.append(Vector2i(col + 1, row))
        stack.append(Vector2i(col - 1, row))
        stack.append(Vector2i(col, row + 1))
        stack.append(Vector2i(col, row - 1))
    return changed


func request_import_tileset() -> void:
    # Native OS picker + multi-select. Users can shift/ctrl-click a batch
    # of individual tile PNGs and they'll be composed into one atlas.
    var dlg := FileDialog.new()
    dlg.use_native_dialog = true
    dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    dlg.access = FileDialog.ACCESS_FILESYSTEM
    dlg.filters = PackedStringArray(["*.png ; PNG images"])
    dlg.title = "Import PNG(s) as new tileset"
    _apply_last_import_dir(dlg)
    dlg.files_selected.connect(_on_tileset_files_selected)
    dlg.canceled.connect(_on_tileset_dialog_closed.bind(dlg))
    dlg.visibility_changed.connect(_on_tileset_dialog_visibility_changed.bind(dlg))
    add_child(dlg)
    dlg.popup_centered_ratio(0.7)


func request_append_to_tileset(tileset_idx: int) -> void:
    # Second dialog flavor: append PNGs to the clicked tileset. Uses the
    # tileset's existing tile_size (no prompt) so the user just picks art.
    var dlg := FileDialog.new()
    dlg.use_native_dialog = true
    dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    dlg.access = FileDialog.ACCESS_FILESYSTEM
    dlg.filters = PackedStringArray(["*.png ; PNG images"])
    dlg.title = "Append PNG(s) to tileset %02d" % tileset_idx
    _apply_last_import_dir(dlg)
    dlg.files_selected.connect(_on_append_files_selected.bind(tileset_idx))
    dlg.canceled.connect(_on_tileset_dialog_closed.bind(dlg))
    dlg.visibility_changed.connect(_on_tileset_dialog_visibility_changed.bind(dlg))
    add_child(dlg)
    dlg.popup_centered_ratio(0.7)


func _apply_last_import_dir(dlg: FileDialog) -> void:
    if _last_tileset_import_dir.is_empty():
        return
    if not DirAccess.dir_exists_absolute(_last_tileset_import_dir):
        return
    dlg.current_dir = _last_tileset_import_dir


func _remember_import_dir_from(paths: PackedStringArray) -> void:
    if paths.is_empty():
        return
    var first := String(paths[0])
    if first.is_empty():
        return
    var dir := first.get_base_dir()
    if dir.is_empty():
        return
    _last_tileset_import_dir = dir


func _on_tileset_dialog_visibility_changed(dlg: FileDialog) -> void:
    if not dlg.visible:
        dlg.queue_free()


func _on_tileset_dialog_closed(dlg: FileDialog) -> void:
    dlg.queue_free()


func _on_tileset_files_selected(paths: PackedStringArray) -> void:
    if paths.is_empty():
        return
    _remember_import_dir_from(paths)
    # Stage the paths on the instance and hand off to the tile-size modal.
    # When the user submits, _finish_tileset_import reads _pending_import_paths.
    _pending_import_paths = paths
    _show_tileset_import_modal("%d" % EnvIO.BLOCK_SIZE)


func _finish_tileset_import(tile_size_str: String) -> void:
    var paths := _pending_import_paths
    _pending_import_paths = PackedStringArray()
    if paths.is_empty():
        return
    var trimmed := tile_size_str.strip_edges()
    if not trimmed.is_valid_int():
        _reopen_tileset_import_modal(paths, tile_size_str, "Tile size must be a whole number like 16, 32, or 48.")
        return
    var parsed_size := int(trimmed)
    if parsed_size < EnvIO.BLOCK_SIZE or parsed_size % EnvIO.BLOCK_SIZE != 0:
        _reopen_tileset_import_modal(paths, trimmed, "Tile size must be at least %d and a multiple of %d." % [EnvIO.BLOCK_SIZE, EnvIO.BLOCK_SIZE])
        return
    var imported_idx := EnvIO.import_tileset(pack_id, paths, parsed_size)
    if imported_idx < 0:
        _reopen_tileset_import_modal(paths, trimmed, EnvIO.get_last_import_error())
        return
    var import_name := str(paths[0]).get_file().get_basename()
    if not import_name.is_empty():
        EnvIO.save_tileset_name(pack_id, imported_idx, import_name)
    _refresh_tileset_cache()
    selected_tileset_id = imported_idx
    selected_metatile_idx = 0
    selected_metatile_span = Vector2i.ONE


func _show_tileset_import_modal(default_text: String, error_text: String = "") -> void:
    show_text_modal("Tile size",
        default_text,
        _tileset_import_prompt(error_text),
        Callable(self, "_finish_tileset_import"))


func _reopen_tileset_import_modal(paths: PackedStringArray, attempted_text: String, error_text: String) -> void:
    _pending_import_paths = paths
    _show_tileset_import_modal(attempted_text, error_text)


func _tileset_import_prompt(error_text: String = "") -> String:
    var lines := PackedStringArray()
    var trimmed := error_text.strip_edges()
    if not trimmed.is_empty():
        lines.append("Error: %s" % trimmed)
    lines.append("Enter the pixel size of each logical tile.")
    lines.append("It must be a multiple of %d. Examples: 16, 32, 48, 64." % EnvIO.BLOCK_SIZE)
    return "\n".join(lines)


func request_rename_tileset(tileset_idx: int) -> void:
    _pending_rename_idx = tileset_idx
    var current := get_tileset_name(tileset_idx)
    show_text_modal("Rename tileset",
        current,
        "New display name for tileset %02d. The numeric ID stays the same — only the label in the dropdown changes." % tileset_idx,
        Callable(self, "_on_tileset_rename_submitted"))


func _on_tileset_rename_submitted(new_name: String) -> void:
    var idx := _pending_rename_idx
    _pending_rename_idx = -1
    if idx < 0:
        return
    var trimmed := new_name.strip_edges()
    if trimmed.is_empty():
        push_warning("[EnvEditor] empty tileset name ignored")
        return
    if not EnvIO.save_tileset_name(pack_id, idx, trimmed):
        return
    _tileset_names[idx] = trimmed


func request_delete_tileset(tileset_idx: int) -> void:
    var dlg := ConfirmationDialog.new()
    dlg.title = "Delete tileset?"
    dlg.dialog_text = "Delete tileset %02d — %s?\n\nThis removes it from the picker. Rooms painted with tiles from this set will render those cells empty until you repaint them." % [tileset_idx, get_tileset_name(tileset_idx)]
    dlg.get_ok_button().text = "Delete"
    dlg.confirmed.connect(_on_tileset_delete_confirmed.bind(tileset_idx))
    dlg.visibility_changed.connect(_on_confirm_dialog_visibility_changed.bind(dlg))
    add_child(dlg)
    dlg.popup_centered()


func _on_confirm_dialog_visibility_changed(dlg: ConfirmationDialog) -> void:
    if not dlg.visible:
        dlg.queue_free()


func _on_tileset_delete_confirmed(tileset_idx: int) -> void:
    if not EnvIO.delete_tileset(pack_id, tileset_idx):
        return
    _refresh_tileset_cache()
    # If we just deleted the active tileset, fall back to the first
    # remaining one (or 0 if the list is empty) so the picker doesn't
    # stay pointed at a ghost.
    if selected_tileset_id == tileset_idx:
        if not _tileset_indices.is_empty():
            selected_tileset_id = int(_tileset_indices[0])
        else:
            selected_tileset_id = 0
        selected_metatile_idx = _snap_to_metatile(1, selected_tileset_id)
        selected_metatile_span = Vector2i.ONE


func _on_append_files_selected(paths: PackedStringArray, tileset_idx: int) -> void:
    if paths.is_empty():
        return
    _remember_import_dir_from(paths)
    var n := EnvIO.append_to_tileset(pack_id, tileset_idx, paths)
    if n <= 0:
        return
    _refresh_tileset_cache()
    selected_tileset_id = tileset_idx
    selected_metatile_span = Vector2i.ONE


# ─── Tile layer queries ──────────────────────────────────────────────────

func _get_tile_layers() -> Array:
    var room := get_current_room()
    if room.is_empty():
        return []
    var v: Variant = room.get("tile_layers", [])
    if typeof(v) != TYPE_ARRAY:
        return []
    return v

func get_tile_layers() -> Array:
    return _get_tile_layers()

func get_tile_layer_role(idx: int) -> String:
    var layers := _get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return ""
    var layer_v: Variant = layers[idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return ""
    return str((layer_v as Dictionary).get("role", EnvTypes.ROLE_MAIN))

func is_main_tile_layer(idx: int) -> bool:
    return get_tile_layer_role(idx) == EnvTypes.ROLE_MAIN

func _active_target_grid() -> Array:
    # Returns the 2D grid currently being painted: tile_layers[idx].tiles
    # for MODE_TILE, or room.collision for MODE_COLLISION. Other modes
    # don't paint cells (entities/doors take pixel/cell args separately).
    var room := get_current_room()
    if room.is_empty():
        return []
    if active_mode == EnvTypes.MODE_COLLISION:
        var col_v: Variant = room.get("collision")
        if typeof(col_v) == TYPE_ARRAY:
            return col_v
        return []
    if active_mode == EnvTypes.MODE_TILE:
        var layers := _get_tile_layers()
        if active_tile_layer_idx < 0 or active_tile_layer_idx >= layers.size():
            return []
        var layer_v: Variant = layers[active_tile_layer_idx]
        if typeof(layer_v) != TYPE_DICTIONARY:
            return []
        var tiles_v: Variant = (layer_v as Dictionary).get("tiles")
        if typeof(tiles_v) != TYPE_ARRAY:
            return []
        return tiles_v
    return []


# ─── Undo stroke capture ─────────────────────────────────────────────────

func begin_stroke() -> void:
    _stroke_snapshot = _snapshot_active_surface()

func end_stroke() -> void:
    if _stroke_snapshot.is_empty():
        return
    var before: Dictionary = _stroke_snapshot
    var after: Dictionary = _snapshot_active_surface()
    if before == after:
        _stroke_snapshot = {}
        return
    if undo_mgr != null:
        var room_addr := current_room_addr
        var mode := active_mode
        var layer_idx := active_tile_layer_idx
        undo_mgr.push("paint %s" % room_addr,
            _restore_surface.bind(room_addr, mode, layer_idx, after),
            _restore_surface.bind(room_addr, mode, layer_idx, before))
    _stroke_snapshot = {}

func _snapshot_active_grid() -> Array:
    var grid: Array = _active_target_grid()
    if grid.is_empty():
        return []
    var snap: Array = []
    for row_v in grid:
        if typeof(row_v) == TYPE_ARRAY:
            snap.append((row_v as Array).duplicate())
        else:
            snap.append(row_v)
    return snap


func _snapshot_active_surface() -> Dictionary:
    var snap := {
        "grid": _snapshot_active_grid(),
    }
    var room := get_current_room()
    if room.is_empty():
        return snap
    if active_mode == EnvTypes.MODE_COLLISION:
        snap["bts"] = _snapshot_grid_array(_get_bts_grid(room))
    elif active_mode == EnvTypes.MODE_TILE:
        snap["animations"] = get_tile_layer_animations(active_tile_layer_idx).duplicate(true)
    elif active_mode == EnvTypes.MODE_BG_IMAGES:
        snap["background_images"] = _snapshot_list(_get_background_images_ref(room))
    elif active_mode == EnvTypes.MODE_ZONES:
        snap["zones"] = _snapshot_list(_get_zones_ref(room))
    return snap


func _snapshot_grid_array(grid: Array) -> Array:
    var snap: Array = []
    for row_v in grid:
        if typeof(row_v) == TYPE_ARRAY:
            snap.append((row_v as Array).duplicate())
        else:
            snap.append(row_v)
    return snap


func _restore_surface(room_addr: String, mode: int, layer_idx: int, snapshot: Dictionary) -> void:
    if current_room_addr != room_addr:
        switch_to_room(room_addr)
    active_mode = mode
    active_tile_layer_idx = layer_idx
    var grid_snap: Array = snapshot.get("grid", [])
    var grid: Array = _active_target_grid()
    if grid.size() != grid_snap.size():
        return
    for r in grid.size():
        if typeof(grid[r]) == TYPE_ARRAY and typeof(grid_snap[r]) == TYPE_ARRAY:
            var dst: Array = grid[r]
            var src: Array = grid_snap[r]
            for c in dst.size():
                if c < src.size():
                    dst[c] = src[c]
    var room := get_current_room()
    if mode == EnvTypes.MODE_COLLISION and not room.is_empty():
        var bts_snap: Array = snapshot.get("bts", [])
        var bts_grid := _get_bts_grid(room)
        if bts_grid.size() == bts_snap.size():
            for r in bts_grid.size():
                if typeof(bts_grid[r]) == TYPE_ARRAY and typeof(bts_snap[r]) == TYPE_ARRAY:
                    var dst_bts: Array = bts_grid[r]
                    var src_bts: Array = bts_snap[r]
                    for c in dst_bts.size():
                        if c < src_bts.size():
                            dst_bts[c] = src_bts[c]
    elif mode == EnvTypes.MODE_TILE and not room.is_empty():
        var layers := _get_tile_layers()
        if layer_idx >= 0 and layer_idx < layers.size():
            var layer_v: Variant = layers[layer_idx]
            if typeof(layer_v) == TYPE_DICTIONARY:
                (layer_v as Dictionary)["animations"] = (snapshot.get("animations", {}) as Dictionary).duplicate(true)
    elif mode == EnvTypes.MODE_BG_IMAGES and not room.is_empty():
        room["background_images"] = _snapshot_list(snapshot.get("background_images", []))
        _sync_legacy_background_image(room)
    elif mode == EnvTypes.MODE_ZONES and not room.is_empty():
        room["zones"] = _snapshot_list(snapshot.get("zones", []))
        _sync_room_zones(room)
    dirty = true


func copy_active_region(rect: Rect2i) -> bool:
    var grid: Array = _active_target_grid()
    if grid.is_empty() or rect.size.x <= 0 or rect.size.y <= 0:
        return false
    var rows: int = grid.size()
    var cols: int = (grid[0] as Array).size() if rows > 0 and typeof(grid[0]) == TYPE_ARRAY else 0
    if cols <= 0:
        return false
    var clipped := Rect2i(
        Vector2i(
            clampi(rect.position.x, 0, cols - 1),
            clampi(rect.position.y, 0, rows - 1)),
        Vector2i.ZERO)
    var max_x := clampi(rect.end.x, clipped.position.x + 1, cols)
    var max_y := clampi(rect.end.y, clipped.position.y + 1, rows)
    clipped.size = Vector2i(max_x - clipped.position.x, max_y - clipped.position.y)
    var cells: Array = []
    for y in clipped.size.y:
        var src_row: Array = grid[clipped.position.y + y]
        var out_row: Array = []
        for x in clipped.size.x:
            out_row.append(int(src_row[clipped.position.x + x]))
        cells.append(out_row)
    _grid_clipboard = {
        "kind": "grid",
        "mode": active_mode,
        "width": clipped.size.x,
        "height": clipped.size.y,
        "cells": cells,
    }
    if active_mode == EnvTypes.MODE_COLLISION:
        var room := get_current_room()
        var bts_grid := _get_bts_grid(room)
        var bts_cells: Array = []
        for y in clipped.size.y:
            var out_bts_row: Array = []
            var bts_row: Array = []
            if clipped.position.y + y < bts_grid.size() and typeof(bts_grid[clipped.position.y + y]) == TYPE_ARRAY:
                bts_row = bts_grid[clipped.position.y + y]
            for x in clipped.size.x:
                var bts_val := 0
                if clipped.position.x + x < bts_row.size():
                    bts_val = int(bts_row[clipped.position.x + x])
                out_bts_row.append(bts_val)
            bts_cells.append(out_bts_row)
        _grid_clipboard["bts"] = bts_cells
    elif active_mode == EnvTypes.MODE_TILE:
        var animations: Dictionary = get_tile_layer_animations(active_tile_layer_idx)
        var anim_clip: Dictionary = {}
        for key_v in animations.keys():
            var key := str(key_v)
            var parts := key.split(",", false)
            if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
                continue
            var col := int(parts[0])
            var row := int(parts[1])
            if col < clipped.position.x or col >= clipped.end.x or row < clipped.position.y or row >= clipped.end.y:
                continue
            anim_clip["%d,%d" % [col - clipped.position.x, row - clipped.position.y]] = (animations[key_v] as Dictionary).duplicate(true)
        _grid_clipboard["animations"] = anim_clip
    _grid_paste_preview_active = false
    return true


func has_grid_clipboard() -> bool:
    return str(_grid_clipboard.get("kind", "")) == "grid"


func get_grid_clipboard_size() -> Vector2i:
    if not has_grid_clipboard():
        return Vector2i.ZERO
    return Vector2i(int(_grid_clipboard.get("width", 0)), int(_grid_clipboard.get("height", 0)))


func start_grid_paste_preview() -> bool:
    if not has_grid_clipboard():
        return false
    if int(_grid_clipboard.get("mode", -1)) != active_mode:
        return false
    _grid_paste_preview_active = true
    return true


func cancel_grid_paste_preview() -> bool:
    if not _grid_paste_preview_active:
        return false
    _grid_paste_preview_active = false
    return true


func has_grid_paste_preview() -> bool:
    return _grid_paste_preview_active and has_grid_clipboard() and int(_grid_clipboard.get("mode", -1)) == active_mode


func paste_grid_clipboard(start_row: int, start_col: int) -> void:
    if not has_grid_paste_preview():
        return
    var grid: Array = _active_target_grid()
    if grid.is_empty():
        return
    var height := int(_grid_clipboard.get("height", 0))
    var width := int(_grid_clipboard.get("width", 0))
    var cells: Array = _grid_clipboard.get("cells", [])
    if width <= 0 or height <= 0 or cells.is_empty():
        return
    var rows: int = grid.size()
    var cols: int = (grid[0] as Array).size() if rows > 0 and typeof(grid[0]) == TYPE_ARRAY else 0
    var changed := false
    for y in height:
        var dst_row_idx := start_row + y
        if dst_row_idx < 0 or dst_row_idx >= rows or y >= cells.size():
            continue
        var src_row_v: Variant = cells[y]
        if typeof(src_row_v) != TYPE_ARRAY:
            continue
        var src_row: Array = src_row_v
        var dst_row: Array = grid[dst_row_idx]
        for x in width:
            var dst_col_idx := start_col + x
            if dst_col_idx < 0 or dst_col_idx >= cols or x >= src_row.size():
                continue
            var new_val := int(src_row[x])
            if int(dst_row[dst_col_idx]) != new_val:
                dst_row[dst_col_idx] = new_val
                changed = true
    if active_mode == EnvTypes.MODE_COLLISION:
        var room := get_current_room()
        var bts_cells: Array = _grid_clipboard.get("bts", [])
        for y in height:
            if y >= bts_cells.size():
                continue
            var src_bts_row_v: Variant = bts_cells[y]
            if typeof(src_bts_row_v) != TYPE_ARRAY:
                continue
            var src_bts_row: Array = src_bts_row_v
            for x in width:
                if x >= src_bts_row.size():
                    continue
                var dst_r := start_row + y
                var dst_c := start_col + x
                if dst_r < 0 or dst_r >= rows or dst_c < 0 or dst_c >= cols:
                    continue
                if _set_bts_value(room, dst_r, dst_c, int(src_bts_row[x])):
                    changed = true
        if changed:
            dirty = true
        return
    if active_mode == EnvTypes.MODE_TILE:
        var layers := _get_tile_layers()
        if active_tile_layer_idx >= 0 and active_tile_layer_idx < layers.size():
            var layer_v: Variant = layers[active_tile_layer_idx]
            if typeof(layer_v) == TYPE_DICTIONARY:
                var layer_d: Dictionary = layer_v
                if not layer_d.has("animations") or typeof(layer_d.get("animations", {})) != TYPE_DICTIONARY:
                    layer_d["animations"] = {}
                var anims: Dictionary = layer_d["animations"]
                for y in height:
                    for x in width:
                        var dst_r := start_row + y
                        var dst_c := start_col + x
                        if dst_r < 0 or dst_r >= rows or dst_c < 0 or dst_c >= cols:
                            continue
                        var dst_key := "%d,%d" % [dst_c, dst_r]
                        if anims.has(dst_key):
                            anims.erase(dst_key)
                            changed = true
                var anim_clip: Dictionary = _grid_clipboard.get("animations", {})
                for key_v in anim_clip.keys():
                    var key := str(key_v)
                    var parts := key.split(",", false)
                    if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
                        continue
                    var rel_c := int(parts[0])
                    var rel_r := int(parts[1])
                    var dst_c := start_col + rel_c
                    var dst_r := start_row + rel_r
                    if dst_r < 0 or dst_r >= rows or dst_c < 0 or dst_c >= cols:
                        continue
                    var dst_key := "%d,%d" % [dst_c, dst_r]
                    var src_anim: Dictionary = (anim_clip[key_v] as Dictionary).duplicate(true)
                    if not anims.has(dst_key) or anims[dst_key] != src_anim:
                        anims[dst_key] = src_anim
                        changed = true
        if changed:
            dirty = true


# ─── Entity / door list undo ─────────────────────────────────────────────

func _snapshot_list(arr: Array) -> Array:
    var out: Array = []
    for v in arr:
        if typeof(v) == TYPE_DICTIONARY:
            out.append((v as Dictionary).duplicate(true))
        else:
            out.append(v)
    return out


func _push_list_change(room_addr: String, key: String, desc: String,
        before: Array, after: Array) -> void:
    if undo_mgr == null:
        return
    if before == after:
        return
    undo_mgr.push(desc,
        _restore_list.bind(room_addr, key, after),
        _restore_list.bind(room_addr, key, before))


func _restore_list(room_addr: String, key: String, snapshot: Array) -> void:
    if current_room_addr != room_addr:
        switch_to_room(room_addr)
    var room := get_current_room()
    if room.is_empty():
        return
    room[key] = _snapshot_list(snapshot)
    if key == "background_images":
        _sync_legacy_background_image(room)
    dirty = true


# ─── Paint / erase ───────────────────────────────────────────────────────

func paint_cell(row: int, col: int) -> void:
    var layer: Array = _active_target_grid()
    if layer.is_empty():
        return
    if row < 0 or row >= layer.size():
        return
    var row_v: Variant = layer[row]
    if typeof(row_v) != TYPE_ARRAY:
        return
    var row_arr: Array = row_v
    if col < 0 or col >= row_arr.size():
        return

    var is_collision := active_mode == EnvTypes.MODE_COLLISION

    # ANIMATE tool: open animation modal for tile cells.
    if active_tool == EnvTypes.TOOL_ANIMATE and not is_collision:
        var existing := int(row_arr[col])
        if existing != 0:
            request_edit_tile_anim(row, col, existing)
        return

    if active_tool == EnvTypes.TOOL_PICK:
        var existing := int(row_arr[col])
        if is_collision:
            var nibble := existing & 0xF
            selected_collision_nibble = nibble
            if nibble == EnvTypes.BT_SLOPE:
                _sync_selected_slope_from_cell(get_current_room(), row, col)
            elif nibble == EnvTypes.BT_CRUMBLE:
                _sync_selected_crumble_from_cell(get_current_room(), row, col)
            # Open spike profile modal when picking a spike cell.
            if nibble == EnvTypes.BT_SPIKE:
                request_edit_spike(row, col)
                return
        elif existing != 0:
            var info := MvTileValue.unpack_full(existing)
            selected_tileset_id = int(info["tileset"])
            # Snap the picked sub-tile to its containing logical tile so
            # subsequent paints line up, and so the picker highlight lands
            # on the whole metatile rather than a silently-unhighlighted
            # mid-cell.
            selected_metatile_idx = _snap_to_metatile(int(info["idx"]), selected_tileset_id)
            selected_metatile_span = Vector2i.ONE
        return

    if active_tool == EnvTypes.TOOL_ERASE:
        if is_collision:
            if int(row_arr[col]) != 0:
                _set_bts_value(get_current_room(), row, col, 0)
                row_arr[col] = 0
                dirty = true
        else:
            _erase_metatile_brush(layer, row, col)
        return

    if is_collision:
        # Collision paint stays single-cell — the collision nibble isn't
        # owned by a tileset so there's no metatile to expand into.
        var nib_val := selected_collision_nibble
        var room := get_current_room()
        if active_tool == EnvTypes.TOOL_FILL:
            var existing_fill := int(row_arr[col])
            if existing_fill == nib_val \
                    and (nib_val != EnvTypes.BT_SLOPE or _get_bts_value(room, row, col) == _selected_slope_bts()) \
                    and (nib_val != EnvTypes.BT_CRUMBLE or _get_bts_value(room, row, col) == _selected_crumble_bts()):
                return
            if _flood_fill_collision(room, layer, row, col, existing_fill, nib_val):
                dirty = true
            return
        var existing_nibble := int(row_arr[col])
        var changed := false
        if existing_nibble != nib_val:
            row_arr[col] = nib_val
            changed = true
        if _paint_collision_metadata(room, row, col, existing_nibble, nib_val):
            changed = true
        if changed:
            dirty = true
        return

    # Tile paint: the brush expands to N×N 16-px sub-tiles where N is the
    # active tileset's tile_size / BLOCK_SIZE. Fill stays single-cell on
    # the underlying 16-px grid — flood-filling metatile chunks would be
    # unintuitive and mostly-useless.
    if active_tool == EnvTypes.TOOL_FILL:
        var new_val_fill := MvTileValue.pack(selected_metatile_idx, false, false, selected_tileset_id)
        var existing_fill2 := int(row_arr[col])
        if existing_fill2 == new_val_fill:
            return
        _flood_fill(layer, row, col, existing_fill2, new_val_fill)
        dirty = true
        return

    _paint_metatile_brush(layer, row, col)

func erase_cell(row: int, col: int) -> void:
    var layer: Array = _active_target_grid()
    if layer.is_empty():
        return
    if active_mode == EnvTypes.MODE_COLLISION:
        var room := get_current_room()
        if row < 0 or row >= layer.size():
            return
        var row_v: Variant = layer[row]
        if typeof(row_v) != TYPE_ARRAY:
            return
        var row_arr: Array = row_v
        if col < 0 or col >= row_arr.size():
            return
        if int(row_arr[col]) != 0:
            _set_bts_value(room, row, col, 0)
            row_arr[col] = 0
            dirty = true
        return
    _erase_metatile_brush(layer, row, col)


func _paint_metatile_brush(layer: Array, start_row: int, start_col: int) -> void:
    @warning_ignore("integer_division")
    var brush_n: int = maxi(get_tileset_tile_size(selected_tileset_id) / EnvIO.BLOCK_SIZE, 1)
    var grid_cols := get_tileset_grid_cols(selected_tileset_id)
    var rows := layer.size()
    if rows == 0:
        return
    var cols_len: int = (layer[0] as Array).size()
    var logical_w := maxi(selected_metatile_span.x, 1)
    var logical_h := maxi(selected_metatile_span.y, 1)
    if grid_cols <= 0:
        return
    var changed := false
    for logical_r in logical_h:
        for logical_c in logical_w:
            var logical_origin := selected_metatile_idx + logical_r * brush_n * grid_cols + logical_c * brush_n
            for dr in brush_n:
                for dc in brush_n:
                    var r := start_row + logical_r * brush_n + dr
                    var c := start_col + logical_c * brush_n + dc
                    if r < 0 or r >= rows or c < 0 or c >= cols_len:
                        continue
                    var sub_idx := logical_origin + dr * grid_cols + dc
                    var val2 := MvTileValue.pack(sub_idx, false, false, selected_tileset_id)
                    var row_ref: Array = layer[r]
                    if int(row_ref[c]) != val2:
                        row_ref[c] = val2
                        changed = true
    if changed:
        dirty = true


func _erase_metatile_brush(layer: Array, start_row: int, start_col: int) -> void:
    var brush_w: int = 1
    var brush_h: int = 1
    if active_mode == EnvTypes.MODE_TILE:
        @warning_ignore("integer_division")
        var brush_n := maxi(get_tileset_tile_size(selected_tileset_id) / EnvIO.BLOCK_SIZE, 1)
        brush_w = maxi(selected_metatile_span.x, 1) * brush_n
        brush_h = maxi(selected_metatile_span.y, 1) * brush_n
    var rows := layer.size()
    if rows == 0:
        return
    var cols_len: int = (layer[0] as Array).size()
    var changed := false
    for dr in brush_h:
        for dc in brush_w:
            var r := start_row + dr
            var c := start_col + dc
            if r < 0 or r >= rows or c < 0 or c >= cols_len:
                continue
            var row_ref: Array = layer[r]
            if int(row_ref[c]) != 0:
                row_ref[c] = 0
                changed = true
    if changed:
        dirty = true


# Given any 16-px sub-tile idx in a tileset, return the sub-tile idx of
# the top-left corner of the logical (metatile) tile that contains it.
# For tilesets with tile_size == BLOCK_SIZE this is a no-op. For larger
# tile sizes the result is always aligned to the tile_size grid so the
# picker highlight and paint expansion agree on the same anchor.
func _snap_to_metatile(sub_idx: int, tileset_idx: int) -> int:
    @warning_ignore("integer_division")
    var brush_n: int = maxi(get_tileset_tile_size(tileset_idx) / EnvIO.BLOCK_SIZE, 1)
    if brush_n == 1:
        return sub_idx
    var grid_cols := get_tileset_grid_cols(tileset_idx)
    if grid_cols <= 0:
        return sub_idx
    @warning_ignore("integer_division")
    var row := sub_idx / grid_cols
    var col := sub_idx % grid_cols
    @warning_ignore("integer_division")
    var aligned_row := (row / brush_n) * brush_n
    @warning_ignore("integer_division")
    var aligned_col := (col / brush_n) * brush_n
    return aligned_row * grid_cols + aligned_col


func _flood_fill(layer: Array, start_row: int, start_col: int, target: int, replacement: int) -> void:
    if target == replacement:
        return
    var rows := layer.size()
    if rows == 0:
        return
    var cols := (layer[0] as Array).size()
    var stack: Array = [[start_row, start_col]]
    while not stack.is_empty():
        var cell: Array = stack.pop_back()
        var r: int = cell[0]
        var c: int = cell[1]
        if r < 0 or r >= rows or c < 0 or c >= cols:
            continue
        var row_arr: Array = layer[r]
        if int(row_arr[c]) != target:
            continue
        row_arr[c] = replacement
        stack.append([r + 1, c])
        stack.append([r - 1, c])
        stack.append([r, c + 1])
        stack.append([r, c - 1])


# ─── Save / close ────────────────────────────────────────────────────────

func save_all() -> bool:
    _normalize_main_layer_scrolls()
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) == TYPE_DICTIONARY:
        for room_v in (rooms_v as Dictionary).values():
            if typeof(room_v) == TYPE_DICTIONARY:
                _sync_room_zones(room_v as Dictionary)
    var ok: bool
    if region_id != "":
        ok = RegIO.save_region_rooms(pack_id, region_id, rooms_data)
    else:
        ok = EnvIO.save_rooms(pack_id, rooms_data)
    if ok:
        dirty = false
        print("[EnvEditor] saved rooms for pack '%s' region '%s'" % [pack_id, region_id])
        _warn_dangling_door_targets()
        _ContentValidator.validate_and_log(pack_id, "environment save")
    else:
        push_error("[EnvEditor] save failed for pack '%s' region '%s'" % [pack_id, region_id])
    return ok


# Walk every room's doors and warn about any target addrs that don't match
# another known room. "exit_to_space"-tagged doors and overworld-return
# doors are exempt since their traversal is handled by PlanetaryInterface
# instead of room loading.
func _warn_dangling_door_targets() -> void:
    var rooms := _rooms_dict()
    var known_door_ids := _door_id_map()
    var bad: int = 0
    for addr in rooms.keys():
        var room_v: Variant = rooms[addr]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var zones := _get_zones_ref(room)
        for zone_v in zones:
            if typeof(zone_v) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zone_v
            if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
                continue
            if bool(zone.get("launch_to_space", false)):
                continue
            var target_door_id := str(zone.get("target_door_id", "")).strip_edges()
            var legacy_target_room := str(zone.get("target_room", "")).strip_edges()
            if target_door_id.is_empty():
                if not legacy_target_room.is_empty() and rooms.has(legacy_target_room):
                    continue
                push_warning("[EnvEditor] door '%s' in '%s' has no target door id" % [str(zone.get("id", "(unnamed)")), addr])
                bad += 1
            elif not known_door_ids.has(target_door_id):
                push_warning("[EnvEditor] door '%s' in '%s' targets unknown door id '%s'" % [str(zone.get("id", "(unnamed)")), addr, target_door_id])
                bad += 1
    if bad > 0:
        print("[EnvEditor] save warning: %d door link issue(s) — run Validate for details" % bad)

func request_close() -> void:
    visible = false
    closed.emit()


func request_validate() -> void:
    if dirty:
        if not save_all():
            push_warning("[EnvEditor] validate aborted because save failed")
            return
    var issues: Array = _ContentValidator.validate(pack_id)
    if issues.is_empty():
        print("[Validate] pack '%s' — no issues found" % pack_id)
        return
    var errors := 0
    var warnings := 0
    for iss in issues:
        if iss.severity == "error":
            errors += 1
            push_error("[Validate] %s" % iss.text())
        else:
            warnings += 1
            push_warning("[Validate] %s" % iss.text())
    print("[Validate] pack '%s' — %d errors, %d warnings" % [pack_id, errors, warnings])


# ─── Playtest round-trip (Ctrl+9) ────────────────────────────────────────
#
# Save any pending edits, find the current room's player_spawn entity,
# stash the editor's pack/region/room on PlanetaryInterface so the return
# hotkey can re-open us at the same spot, then scene-change to MV. MvMain
# reads pending_spawn_room/pos in _ready to spawn the player in the tested
# room instead of the pack's start room.
func request_playtest() -> void:
    if pack_id.is_empty():
        push_warning("[EnvEditor] playtest: no active pack")
        return
    if current_room_addr.is_empty():
        push_warning("[EnvEditor] playtest: no active room")
        return
    var room := get_current_room()
    if room.is_empty():
        push_warning("[EnvEditor] playtest: current room '%s' not found" % current_room_addr)
        return
    # Refuse playtest if the room doesn't carry a player_spawn entity —
    # without one MV would fall back to the first floor tile, which is
    # almost always not what the author wants when testing a specific room.
    if _find_player_spawn_pos(room).x < 0.0:
        push_warning("[EnvEditor] playtest: room '%s' has no player_spawn entity — place one and retry" % current_room_addr)
        return
    if dirty:
        if not save_all():
            push_warning("[EnvEditor] playtest aborted because save failed")
            return
    if MvTriggerEngine != null and MvTriggerEngine.has_method("clear_debug_history"):
        MvTriggerEngine.clear_debug_history()
    # The flat runtime rooms.json (built by RegIO.flatten_to_runtime on save)
    # prefixes every addr with its region_id. Editor state holds the un-
    # prefixed addr so we need to pass the bare room addr alongside the
    # region id so PlanetaryInterface can land in the right room.
    var runtime_addr := _current_runtime_room_addr()
    # poi_id is empty here because the editor playtest is not coming from a
    # POI surface; PlanetaryInterface snapshots under "<pack>::<region>".
    PlanetaryInterface.begin_landing(pack_id, "", region_id, current_room_addr)
    PlanetaryInterface.stage_return_to_editor(pack_id, region_id, current_room_addr)
    print("[EnvEditor] playtest: launching pack='%s' room='%s'" % [pack_id, runtime_addr])
    get_tree().change_scene_to_file.call_deferred("res://MV/scenes/main.tscn")


static func _find_player_spawn_pos(room: Dictionary) -> Vector2:
    var ents_v: Variant = room.get("entities", [])
    if typeof(ents_v) != TYPE_ARRAY:
        return Vector2(-1.0, -1.0)
    var ents: Array = ents_v
    for e_v in ents:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("type", "")) == "player_spawn":
            return Vector2(float(e.get("x", 0)), float(e.get("y", 0)))
    return Vector2(-1.0, -1.0)


func _rooms_dict() -> Dictionary:
    var rooms_v: Variant = rooms_data.get("rooms", {})
    if typeof(rooms_v) != TYPE_DICTIONARY:
        return {}
    return rooms_v


func _current_runtime_room_addr() -> String:
    if region_id.is_empty():
        return current_room_addr
    return RegIO.runtime_room_addr(region_id, current_room_addr)


static func _door_target_room(door: Dictionary) -> String:
    return str(door.get("target_room", door.get("target", ""))).strip_edges()


static func _door_launches_to_space(door: Dictionary) -> bool:
    return bool(door.get("launch_to_space", false))


# ─── Modal prompt plumbing ───────────────────────────────────────────────

func show_text_modal(title: String, default_text: String, prompt: String, cb: Callable) -> void:
    _modal_callback = cb
    text_modal.open(title, default_text, prompt)

func _on_modal_submit(text: String) -> void:
    var cb := _modal_callback
    _modal_callback = Callable()
    if cb.is_valid():
        cb.call(text)

func _on_modal_cancel() -> void:
    _modal_callback = Callable()


# ─── Room metadata modal ─────────────────────────────────────────────────

func request_edit_room_meta() -> void:
    if meta_modal == null:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var meta := {
        "width_blocks": int(room.get("width_blocks", 30)),
        "height_blocks": int(room.get("height_blocks", 17)),
        "tileset": int(room.get("tileset", 0)),
        "parallax_enabled": bool(room.get("parallax_enabled", true)),
        "parallax_layers": (room.get("parallax_layers", []) as Array).duplicate(true),
        "weather": (room.get("weather", EnvIO.default_weather()) as Dictionary).duplicate(true),
        "background_images": get_room_background_images(),
        "background_image": (room.get("background_image", EnvIO.default_background_image(
            int(room.get("width_blocks", 30)),
            int(room.get("height_blocks", 17)))) as Dictionary).duplicate(true),
    }
    meta_modal.open(current_room_addr, meta, _tileset_indices, pack_id)


func request_edit_room_triggers() -> void:
    if room_trigger_modal == null:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var triggers_v: Variant = room.get("triggers", [])
    room_trigger_modal.open_with_root(pack_id, triggers_v, Callable(self, "_apply_room_triggers"))
    room_trigger_modal.visible = true
    room_trigger_modal.size = get_viewport_rect().size
    room_trigger_modal.set_anchors_preset(PRESET_FULL_RECT)
    _set_background_panels_paused(true)


func _apply_room_triggers(root: Dictionary) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    room["triggers"] = root.duplicate(true)
    dirty = true


# Opens the per-room variants editor. Loads the region's room_variants.json
# (or seeds the default shape if missing), shows the modal scoped to the
# current room, and gathers sibling room ids so the "use" picker can offer
# them. Variants are persisted directly via RegIO on submit — they don't
# round-trip through rooms_data because the file is its own concern.
func request_edit_room_variants() -> void:
    if variants_modal == null:
        return
    if region_id.is_empty():
        push_warning("[EnvEditor] variants editor needs a region context (open a region first)")
        return
    if current_room_addr.is_empty():
        push_warning("[EnvEditor] variants editor needs an active room")
        return
    var variants_root: Dictionary = RegIO.load_room_variants(pack_id, region_id)
    var siblings: Array = _rooms_dict().keys()
    variants_modal.call("open_for_room", pack_id, region_id, current_room_addr, siblings, variants_root)
    variants_modal.visible = true
    variants_modal.size = get_viewport_rect().size
    variants_modal.set_anchors_preset(PRESET_FULL_RECT)
    _set_background_panels_paused(true)


func _on_variants_modal_submit(variants_root: Dictionary) -> void:
    if region_id.is_empty():
        return
    if not RegIO.save_room_variants(pack_id, region_id, variants_root):
        push_error("[EnvEditor] failed to save room_variants.json for region '%s'" % region_id)
    else:
        print("[EnvEditor] saved room_variants.json for region '%s'" % region_id)
    _set_background_panels_paused(false)


func _on_variants_modal_cancel() -> void:
    _set_background_panels_paused(false)


func _on_room_trigger_modal_closed() -> void:
    if room_trigger_modal != null:
        room_trigger_modal.visible = false
    _set_background_panels_paused(false)
    _trigger_camera_preview.clear()
    if canvas != null:
        canvas.queue_redraw()


func _set_background_panels_paused(paused: bool) -> void:
    for panel in [topbar, tool_palette, canvas, tileset_panel]:
        if panel == null:
            continue
        panel.set_process(not paused)


func _on_room_trigger_status_changed(text: String) -> void:
    if not text.is_empty():
        print("[EnvEditor] %s" % text)


func _on_room_trigger_camera_preview_changed(preview_items: Array) -> void:
    _trigger_camera_preview = _resolve_camera_preview_items(preview_items)
    if canvas != null:
        canvas.queue_redraw()


func _on_room_trigger_camera_preview_cleared() -> void:
    _trigger_camera_preview.clear()
    if canvas != null:
        canvas.queue_redraw()


func get_trigger_camera_preview() -> Array:
    return _trigger_camera_preview.duplicate(true)


func _resolve_camera_preview_items(preview_items: Array) -> Array:
    var room := get_current_room()
    if room.is_empty():
        return []
    var out: Array = []
    var entities: Array = []
    var entities_v: Variant = room.get("entities", [])
    if typeof(entities_v) == TYPE_ARRAY:
        entities = entities_v
    var previous_pos: Vector2 = Vector2(-1, -1)
    for item_v in preview_items:
        if typeof(item_v) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_v
        var resolved: Dictionary = _resolve_single_camera_preview(item, entities)
        if resolved.is_empty():
            continue
        if previous_pos.x >= 0.0 and previous_pos.y >= 0.0:
            resolved["from_x"] = previous_pos.x
            resolved["from_y"] = previous_pos.y
        previous_pos = Vector2(float(resolved.get("x", -1.0)), float(resolved.get("y", -1.0)))
        out.append(resolved)
    return out


func _resolve_single_camera_preview(item: Dictionary, entities: Array) -> Dictionary:
    var mode: String = str(item.get("mode", "")).strip_edges().to_lower()
    var target: String = str(item.get("target", "")).strip_edges()
    match mode:
        "position":
            return {
                "mode": mode,
                "label": "pos (%.0f, %.0f)" % [float(item.get("x", 0.0)), float(item.get("y", 0.0))],
                "x": float(item.get("x", 0.0)),
                "y": float(item.get("y", 0.0)),
            }
        "zone":
            return _resolve_zone_camera_preview(target, entities)
        "entity":
            return _resolve_entity_camera_preview(target, entities)
        "player":
            return _resolve_player_camera_preview(entities)
        _:
            return {}


func _resolve_zone_camera_preview(zone_id: String, entities: Array) -> Dictionary:
    for e_v in entities:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("type", "")) != "trigger_volume":
            continue
        var props_v: Variant = e.get("properties", {})
        if typeof(props_v) != TYPE_DICTIONARY:
            continue
        var props: Dictionary = props_v
        var candidate_zone: String = str(props.get("zone_id", props.get("instance_id", ""))).strip_edges()
        if candidate_zone != zone_id:
            continue
        return {
            "mode": "zone",
            "label": zone_id,
            "x": float(e.get("x", 0.0)),
            "y": float(e.get("y", 0.0)),
            "w": maxf(16.0, float(props.get("width", 16.0))),
            "h": maxf(16.0, float(props.get("height", 16.0))),
        }
    return {}


func _resolve_entity_camera_preview(entity_ref: String, entities: Array) -> Dictionary:
    for e_v in entities:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var props_v: Variant = e.get("properties", {})
        var props: Dictionary = props_v if typeof(props_v) == TYPE_DICTIONARY else {}
        var instance_id: String = str(props.get("instance_id", "")).strip_edges()
        var entity_id: String = str(e.get("id", e.get("type", ""))).strip_edges()
        if entity_ref != instance_id and entity_ref != entity_id:
            continue
        return {
            "mode": "entity",
            "label": entity_ref,
            "x": float(e.get("x", 0.0)),
            "y": float(e.get("y", 0.0)),
        }
    return {}


func _resolve_player_camera_preview(entities: Array) -> Dictionary:
    for e_v in entities:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("type", "")).strip_edges() != "player_spawn":
            continue
        return {
            "mode": "player",
            "label": "player_spawn",
            "x": float(e.get("x", 0.0)),
            "y": float(e.get("y", 0.0)),
        }
    return {}

func _on_meta_modal_submit(meta: Dictionary) -> void:
    apply_room_meta(meta)

func _on_meta_modal_cancel() -> void:
    pass

func apply_room_meta(meta: Dictionary) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    var new_w := int(meta.get("width_blocks", 30))
    var new_h := int(meta.get("height_blocks", 17))
    var new_tileset := int(meta.get("tileset", 0))
    var new_parallax_enabled := bool(meta.get("parallax_enabled", true))
    var new_parallax_layers: Array = meta.get("parallax_layers", EnvIO.default_parallax_layers())
    var new_weather: Dictionary = meta.get("weather", EnvIO.default_weather())
    var new_background_images: Array = meta.get("background_images", get_room_background_images())
    var new_background_image: Dictionary = meta.get("background_image", EnvIO.default_background_image(new_w, new_h))

    var old_w := int(room.get("width_blocks", 30))
    var old_h := int(room.get("height_blocks", 17))
    var size_changed := new_w != old_w or new_h != old_h

    if size_changed:
        var layers := _get_tile_layers()
        for layer_v in layers:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            _resize_grid_in_place(layer_v, "tiles", new_h, new_w)
        _resize_grid_in_place(room, "collision", new_h, new_w)
        _resize_grid_in_place(room, "bts", new_h, new_w)

        room["width_blocks"] = float(new_w)
        room["height_blocks"] = float(new_h)
        room["width_px"] = float(new_w * 16)
        room["height_px"] = float(new_h * 16)
        room["width_screens"] = float(new_w) / float(EnvIO.DEFAULT_ROOM_W_BLOCKS)
        room["height_screens"] = float(new_h) / float(EnvIO.DEFAULT_ROOM_H_BLOCKS)

        _cull_entities_outside(room, new_w, new_h)
        _cull_doors_outside(room, new_w, new_h)

    room["tileset"] = float(new_tileset)
    room["parallax_enabled"] = new_parallax_enabled
    room["parallax_layers"] = new_parallax_layers.duplicate(true)
    room["weather"] = new_weather.duplicate(true)
    room["background_images"] = new_background_images.duplicate(true)
    room["background_image"] = new_background_image.duplicate(true)
    dirty = true


func get_room_parallax_layers() -> Array:
    var room := get_current_room()
    if room.is_empty():
        return EnvIO.default_parallax_layers()
    if not bool(room.get("parallax_enabled", true)):
        return []
    var layers_v: Variant = room.get("parallax_layers", [])
    if typeof(layers_v) == TYPE_ARRAY:
        return (layers_v as Array).duplicate(true)
    return EnvIO.default_parallax_layers()


func get_room_background_image() -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return EnvIO.default_background_image()
    var raw_v: Variant = room.get("background_image", EnvIO.default_background_image(
        int(room.get("width_blocks", 30)),
        int(room.get("height_blocks", 17))))
    if typeof(raw_v) == TYPE_DICTIONARY:
        return (raw_v as Dictionary).duplicate(true)
    return EnvIO.default_background_image(
        int(room.get("width_blocks", 30)),
        int(room.get("height_blocks", 17)))


func get_room_background_images() -> Array:
    var room := get_current_room()
    if room.is_empty():
        return []
    var raw_v: Variant = room.get("background_images", [])
    if typeof(raw_v) == TYPE_ARRAY:
        return (raw_v as Array).duplicate(true)
    return []


func get_available_backdrop_images() -> Array:
    return PackAssetIndex.list_pack_pngs(pack_id, "Backdrops/Parallax")


func get_selected_background_asset() -> String:
    if not selected_background_asset.is_empty():
        return selected_background_asset
    var images := get_available_backdrop_images()
    if not images.is_empty():
        selected_background_asset = str(images[0])
    return selected_background_asset


func set_selected_background_asset(path: String) -> void:
    selected_background_asset = path.strip_edges()


func get_selected_background_image_id() -> String:
    return selected_background_image_id


func get_selected_background_image() -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return {}
    var arr := _get_background_images_ref(room)
    var idx := _find_background_image_index(arr, selected_background_image_id)
    if idx >= 0 and idx < arr.size() and typeof(arr[idx]) == TYPE_DICTIONARY:
        return (arr[idx] as Dictionary).duplicate(true)
    return {}


func load_backdrop_texture(rel_path: String) -> Texture2D:
    var trimmed := rel_path.strip_edges()
    if trimmed.is_empty():
        return null
    if _backdrop_textures.has(trimmed):
        return _backdrop_textures[trimmed]
    var tex := EnvIO.load_backdrop_texture(pack_id, trimmed)
    if tex != null:
        _backdrop_textures[trimmed] = tex
    return tex


func get_room_weather() -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return EnvIO.default_weather()
    var raw_v: Variant = room.get("weather", EnvIO.default_weather())
    if typeof(raw_v) == TYPE_DICTIONARY:
        return (raw_v as Dictionary).duplicate(true)
    return EnvIO.default_weather()


func get_room_shader_regions() -> Array:
    var room := get_current_room()
    if room.is_empty():
        return []
    var raw_v: Variant = room.get("shader_regions", [])
    if typeof(raw_v) == TYPE_ARRAY:
        return (raw_v as Array).duplicate(true)
    return []


func get_room_zones() -> Array:
    var room := get_current_room()
    if room.is_empty():
        return []
    var raw_v: Variant = room.get("zones", [])
    if typeof(raw_v) == TYPE_ARRAY:
        return (raw_v as Array).duplicate(true)
    return []


func _get_background_images_ref(room: Dictionary) -> Array:
    EnvIO.normalize_background_images(room)
    var arr_v: Variant = room.get("background_images", [])
    if typeof(arr_v) != TYPE_ARRAY:
        room["background_images"] = []
        return room["background_images"]
    return arr_v as Array


func _get_shader_regions_ref(room: Dictionary) -> Array:
    EnvIO.normalize_shader_regions(room)
    var arr_v: Variant = room.get("shader_regions", [])
    if typeof(arr_v) != TYPE_ARRAY:
        room["shader_regions"] = []
        return room["shader_regions"]
    return arr_v as Array


func _get_zones_ref(room: Dictionary) -> Array:
    EnvIO.normalize_zones(room)
    var arr_v: Variant = room.get("zones", [])
    if typeof(arr_v) != TYPE_ARRAY:
        room["zones"] = []
        return room["zones"]
    return arr_v as Array


func _sync_legacy_background_image(room: Dictionary) -> void:
    var arr := _get_background_images_ref(room)
    if not arr.is_empty() and typeof(arr[0]) == TYPE_DICTIONARY:
        room["background_image"] = (arr[0] as Dictionary).duplicate(true)
    else:
        room["background_image"] = EnvIO.default_background_image(
            int(room.get("width_blocks", 30)),
            int(room.get("height_blocks", 17)))


func _zone_id_map(arr: Array, exclude_id: String = "") -> Dictionary:
    var ids: Dictionary = {}
    var excluded := exclude_id.strip_edges()
    for entry_v in arr:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var zone_id := str(entry.get("id", "")).strip_edges()
        if zone_id.is_empty() or zone_id == excluded:
            continue
        ids[zone_id] = true
    return ids


func _door_id_map(exclude_id: String = "") -> Dictionary:
    var ids: Dictionary = {}
    var excluded := exclude_id.strip_edges()
    var rooms := _rooms_dict()
    for room_v in rooms.values():
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var zones := _get_zones_ref(room)
        for zone_v in zones:
            if typeof(zone_v) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zone_v
            if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
                continue
            var door_id := str(zone.get("id", "")).strip_edges()
            if door_id.is_empty() or door_id == excluded:
                continue
            ids[door_id] = true
    return ids


func _door_room_prefix(room_addr: String = "") -> String:
    var raw_addr := room_addr.strip_edges()
    if raw_addr.is_empty():
        raw_addr = current_room_addr.strip_edges()
    return RegIO.sanitize_content_id(raw_addr, "room")


func _door_local_name(raw_name: String, room_addr: String = "") -> String:
    var raw := raw_name.strip_edges()
    var prefix := _door_room_prefix(room_addr)
    if not prefix.is_empty():
        var full_prefix := prefix + "_"
        if raw == prefix:
            raw = ""
        elif raw.begins_with(full_prefix):
            raw = raw.substr(full_prefix.length())
    return RegIO.sanitize_content_id(raw, "door")


func _door_full_id(room_addr: String, raw_name: String) -> String:
    var prefix := _door_room_prefix(room_addr)
    var local_name := _door_local_name(raw_name, room_addr)
    if local_name.is_empty():
        local_name = "door"
    if prefix.is_empty():
        return local_name
    return "%s_%s" % [prefix, local_name]


func _rebase_room_door_ids(room: Dictionary, room_addr: String) -> Dictionary:
    var zones := _get_zones_ref(room)
    var used_ids := _door_id_map()
    for zone_v in zones:
        if typeof(zone_v) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zone_v
        if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
            continue
        var old_id := str(zone.get("id", "")).strip_edges()
        if not old_id.is_empty():
            used_ids.erase(old_id)
    var door_remap: Dictionary = {}
    for i in zones.size():
        if typeof(zones[i]) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zones[i]
        if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
            continue
        var old_id := str(zone.get("id", "")).strip_edges()
        var seed_name := str(zone.get("name", old_id)).strip_edges()
        if seed_name.is_empty():
            seed_name = old_id
        var desired_id := _door_full_id(room_addr, seed_name)
        var new_id := RegIO.unique_content_id(desired_id, used_ids, "door")
        zone["id"] = new_id
        zone["name"] = new_id
        zones[i] = zone
        if not old_id.is_empty() and old_id != new_id:
            door_remap[old_id] = new_id
        used_ids[new_id] = true
    for i in zones.size():
        if typeof(zones[i]) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zones[i]
        if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
            continue
        var target_id := str(zone.get("target_door_id", "")).strip_edges()
        if target_id.is_empty() or not door_remap.has(target_id):
            continue
        zone["target_door_id"] = str(door_remap[target_id])
        zones[i] = zone
    room["zones"] = zones
    _sync_room_zones(room)
    return door_remap


func _normalize_zone_kind(kind: String) -> String:
    var normalized := kind.strip_edges().to_lower()
    if normalized == "door" or normalized == "shader" or normalized == "interact" or normalized == "trigger":
        return normalized
    return "shader"


func _zone_default_name(kind: String, arr: Array) -> String:
    var base := "%s zone" % _normalize_zone_kind(kind)
    var suffix := 1
    while true:
        var candidate := "%s %d" % [base.capitalize(), suffix]
        var candidate_id := RegIO.unique_content_id(candidate, _zone_id_map(arr), "zone")
        if _find_zone_index(arr, candidate_id) < 0:
            return candidate
        suffix += 1
    return base.capitalize()


func _normalize_zone_for_room(entry: Dictionary, room: Dictionary, arr: Array,
        fallback_name: String = "", exclude_id: String = "") -> Dictionary:
    var source: Dictionary = entry.duplicate(true)
    var zone_name := str(source.get("name", fallback_name)).strip_edges()
    if zone_name.is_empty():
        zone_name = fallback_name if not fallback_name.is_empty() else str(source.get("id", "Zone")).strip_edges()
    if zone_name.is_empty():
        zone_name = "Zone"
    var kind := _normalize_zone_kind(str(source.get("kind", "")))
    if kind == "door":
        var room_addr := str(room.get("addr", current_room_addr)).strip_edges()
        var desired_id := _door_full_id(room_addr, zone_name if not zone_name.is_empty() else str(source.get("id", "")))
        source["id"] = RegIO.unique_content_id(desired_id, _door_id_map(exclude_id), "door", exclude_id)
        source["name"] = str(source["id"])
    else:
        source["name"] = zone_name
        var desired_id := str(source.get("id", zone_name)).strip_edges()
        if desired_id.is_empty():
            desired_id = zone_name
        source["id"] = RegIO.unique_content_id(desired_id, _zone_id_map(arr, exclude_id), "zone", exclude_id)
    return EnvIO._normalize_zone_entry(
        source,
        int(room.get("width_blocks", EnvIO.DEFAULT_ROOM_W_BLOCKS)),
        int(room.get("height_blocks", EnvIO.DEFAULT_ROOM_H_BLOCKS)),
        exclude_id)


func _zone_rect_from_entry(entry: Dictionary) -> Rect2:
    return Rect2(
        Vector2(float(entry.get("x_blocks", 0.0)), float(entry.get("y_blocks", 0.0))),
        Vector2(float(entry.get("width_blocks", 0.0)), float(entry.get("height_blocks", 0.0))))


func _find_zone_index(arr: Array, zone_id: String) -> int:
    if zone_id.is_empty():
        return -1
    for i in arr.size():
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        if str((entry_v as Dictionary).get("id", "")).strip_edges() == zone_id:
            return i
    return -1


func _find_region_door_zone(target_door_id: String) -> Dictionary:
    var wanted := target_door_id.strip_edges()
    if wanted.is_empty():
        return {}
    var rooms := _rooms_dict()
    for room_addr_v in rooms.keys():
        var room_v: Variant = rooms[room_addr_v]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var zones := _get_zones_ref(room)
        for zone_v in zones:
            if typeof(zone_v) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zone_v
            if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
                continue
            if str(zone.get("id", "")).strip_edges() == wanted:
                return {
                    "room_addr": str(room_addr_v),
                    "room": room,
                    "zone": zone,
                }
    return {}


func _door_spawn_pixels_for_zone(zone: Dictionary, room: Dictionary) -> Vector2i:
    if zone.is_empty() or room.is_empty():
        return Vector2i.ZERO
    var rect := _zone_rect_from_entry(zone)
    var width_px := maxi(16, int(room.get("width_blocks", EnvIO.DEFAULT_ROOM_W_BLOCKS)) * 16)
    var height_px := maxi(16, int(room.get("height_blocks", EnvIO.DEFAULT_ROOM_H_BLOCKS)) * 16)
    var left_px := int(round(rect.position.x * 16.0))
    var top_px := int(round(rect.position.y * 16.0))
    var right_px := int(round(rect.end.x * 16.0))
    var bottom_px := int(round(rect.end.y * 16.0))
    var center_x := int(round((rect.position.x + rect.size.x * 0.5) * 16.0))
    var center_y := int(round((rect.position.y + rect.size.y * 0.5) * 16.0))
    var spawn_x := center_x
    var spawn_y := center_y
    match str(zone.get("direction", "right")).strip_edges():
        "left":
            spawn_x = right_px + 8
        "right":
            spawn_x = left_px - 8
        "up":
            spawn_y = bottom_px + 8
        "down":
            spawn_y = top_px - 8
    spawn_x = clampi(spawn_x, 24, maxi(24, width_px - 24))
    spawn_y = clampi(spawn_y, 24, maxi(24, height_px - 24))
    return Vector2i(spawn_x, spawn_y)


func _retarget_door_links(old_id: String, new_id: String, skip_zone_id: String = "") -> void:
    var old_clean := old_id.strip_edges()
    var new_clean := new_id.strip_edges()
    var skipped := skip_zone_id.strip_edges()
    if old_clean.is_empty() or new_clean.is_empty() or old_clean == new_clean:
        return
    var rooms := _rooms_dict()
    for room_v in rooms.values():
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var zones := _get_zones_ref(room)
        var changed := false
        for i in zones.size():
            if typeof(zones[i]) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zones[i]
            if _normalize_zone_kind(str(zone.get("kind", ""))) != "door":
                continue
            if str(zone.get("id", "")).strip_edges() == skipped:
                continue
            if str(zone.get("target_door_id", "")).strip_edges() != old_clean:
                continue
            zone["target_door_id"] = new_clean
            zones[i] = zone
            changed = true
        if changed:
            room["zones"] = zones
            _sync_room_zones(room)


func _is_zone_entity(entity: Dictionary) -> bool:
    if str(entity.get("type", "")).strip_edges() != "trigger_volume":
        return false
    var props_v: Variant = entity.get("properties", {})
    if typeof(props_v) != TYPE_DICTIONARY:
        return false
    var props: Dictionary = props_v
    return not str(props.get("zone_id", props.get("instance_id", ""))).strip_edges().is_empty()


func _sync_room_zones(room: Dictionary) -> void:
    var zones := _get_zones_ref(room)
    var shader_regions: Array = []
    var doors: Array = []
    var entities_v: Variant = room.get("entities", [])
    var entities_out: Array = []
    if typeof(entities_v) == TYPE_ARRAY:
        for entity_v in entities_v:
            if typeof(entity_v) != TYPE_DICTIONARY:
                continue
            var entity: Dictionary = entity_v
            if _is_zone_entity(entity):
                continue
            entities_out.append(entity.duplicate(true))
    for zone_v in zones:
        if typeof(zone_v) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = zone_v
        var kind := _normalize_zone_kind(str(zone.get("kind", "shader")))
        if kind == "shader":
            shader_regions.append({
                "id": str(zone.get("id", "")),
                "x_blocks": float(zone.get("x_blocks", 0.0)),
                "y_blocks": float(zone.get("y_blocks", 0.0)),
                "width_blocks": float(zone.get("width_blocks", 0.0)),
                "height_blocks": float(zone.get("height_blocks", 0.0)),
                "shader_preset": str(zone.get("shader_preset", "flicker")),
                "shader_tint": str(zone.get("shader_tint", "ffffff")),
                "shader_strength": float(zone.get("shader_strength", 0.6)),
                "shader_speed": float(zone.get("shader_speed", 1.0)),
            })
            continue
        if kind == "door":
            var target_door_id := str(zone.get("target_door_id", "")).strip_edges()
            var legacy_target_room := str(zone.get("target_room", "")).strip_edges()
            var target_link := _find_region_door_zone(target_door_id)
            var target_room_addr := str(target_link.get("room_addr", ""))
            if target_room_addr.is_empty():
                target_room_addr = legacy_target_room
            var target_zone_v: Variant = target_link.get("zone", {})
            var target_room_v: Variant = target_link.get("room", {})
            var target_zone: Dictionary = target_zone_v if typeof(target_zone_v) == TYPE_DICTIONARY else {}
            var target_room: Dictionary = target_room_v if typeof(target_room_v) == TYPE_DICTIONARY else {}
            var dest_pixels := _door_spawn_pixels_for_zone(target_zone, target_room)
            var rect := _zone_rect_from_entry(zone)
            var start_x := floori(rect.position.x)
            var start_y := floori(rect.position.y)
            var end_x := maxi(start_x + 1, ceili(rect.end.x))
            var end_y := maxi(start_y + 1, ceili(rect.end.y))
            for row in range(start_y, end_y):
                for col in range(start_x, end_x):
                    doors.append({
                        "door_id": str(zone.get("id", "")),
                        "target_door_id": target_door_id,
                        "cap_x": col,
                        "cap_y": row,
                        "direction": str(zone.get("direction", selected_door_direction)),
                        "target_room": "" if bool(zone.get("launch_to_space", false)) else target_room_addr,
                        "launch_to_space": bool(zone.get("launch_to_space", false)),
                        "enabled": bool(zone.get("enabled", true)),
                        "locked": bool(zone.get("locked", false)),
                        "required_item_id": str(zone.get("required_item_id", "")).strip_edges(),
                        "required_item_count": maxi(1, int(zone.get("required_item_count", 1))),
                        "required_var_name": str(zone.get("required_var_name", "")).strip_edges(),
                        "required_var_value": zone.get("required_var_value", 1),
                        "required_global_tag": str(zone.get("required_global_tag", "")).strip_edges(),
                        "blocked_event_name": str(zone.get("blocked_event_name", "")).strip_edges(),
                        "success_event_name": str(zone.get("success_event_name", "")).strip_edges(),
                        "arrive_event_name": str(zone.get("arrive_event_name", "")).strip_edges(),
                        "dest_x": 0 if target_room_addr.is_empty() else dest_pixels.x,
                        "dest_y": 0 if target_room_addr.is_empty() else dest_pixels.y,
                    })
            continue
        if kind == "interact" or kind == "trigger":
            var trigger_props := {
                "instance_id": str(zone.get("id", "")),
                "zone_id": str(zone.get("id", "")),
                "name": str(zone.get("name", "")),
                "width": maxi(16, int(round(float(zone.get("width_blocks", 1.0)) * 16.0))),
                "height": maxi(16, int(round(float(zone.get("height_blocks", 1.0)) * 16.0))),
                "event_name": str(zone.get("event_name", "zone_enter")),
                "once": bool(zone.get("once", false)),
                "interaction_mode": "interact" if kind == "interact" else str(zone.get("interaction_mode", "enter")),
            }
            if kind == "interact":
                trigger_props["prompt_text"] = str(zone.get("prompt_text", "Interact"))
            entities_out.append({
                "type": "trigger_volume",
                "x": int(round(float(zone.get("x_blocks", 0.0)) * 16.0)),
                "y": int(round(float(zone.get("y_blocks", 0.0)) * 16.0)),
                "properties": trigger_props,
            })
    room["shader_regions"] = shader_regions
    room["doors"] = doors
    room["entities"] = entities_out


func _find_background_image_index(arr: Array, image_id: String) -> int:
    if image_id.is_empty():
        return -1
    for i in arr.size():
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        if str((entry_v as Dictionary).get("id", "")).strip_edges() == image_id:
            return i
    return -1


func _suggest_background_image_id(arr: Array) -> String:
    var suffix := maxi(arr.size() + 1, 1)
    while true:
        var candidate := "bg_%d" % suffix
        if _find_background_image_index(arr, candidate) < 0:
            return candidate
        suffix += 1
    return "bg_1"


func _find_shader_region_index(arr: Array, target_region_id: String) -> int:
    if target_region_id.is_empty():
        return -1
    for i in arr.size():
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        if str((entry_v as Dictionary).get("id", "")).strip_edges() == target_region_id:
            return i
    return -1


func _suggest_shader_region_id(arr: Array) -> String:
    var suffix := maxi(arr.size() + 1, 1)
    while true:
        var candidate := "shader_%d" % suffix
        if _find_shader_region_index(arr, candidate) < 0:
            return candidate
        suffix += 1
    return "shader_1"


func _normalize_background_rect(rect_blocks: Rect2) -> Rect2:
    var x1 := minf(rect_blocks.position.x, rect_blocks.end.x)
    var y1 := minf(rect_blocks.position.y, rect_blocks.end.y)
    var x2 := maxf(rect_blocks.position.x, rect_blocks.end.x)
    var y2 := maxf(rect_blocks.position.y, rect_blocks.end.y)
    return Rect2(Vector2(x1, y1), Vector2(maxf(0.0, x2 - x1), maxf(0.0, y2 - y1)))


func _background_rect_from_entry(entry: Dictionary) -> Rect2:
    return Rect2(
        Vector2(float(entry.get("x_blocks", 0.0)), float(entry.get("y_blocks", 0.0))),
        Vector2(float(entry.get("width_blocks", 0.0)), float(entry.get("height_blocks", 0.0))))


func _shader_region_rect_from_entry(entry: Dictionary) -> Rect2:
    return Rect2(
        Vector2(float(entry.get("x_blocks", 0.0)), float(entry.get("y_blocks", 0.0))),
        Vector2(float(entry.get("width_blocks", 0.0)), float(entry.get("height_blocks", 0.0))))


func create_background_image(rect_blocks: Rect2) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var rel_path := get_selected_background_asset()
    if rel_path.is_empty():
        return false
    var rect := _normalize_background_rect(rect_blocks)
    if rect.size.x <= 0.01 or rect.size.y <= 0.01:
        return false
    var arr := _get_background_images_ref(room)
    var entry: Dictionary = EnvIO.default_background_image(
        int(room.get("width_blocks", 30)),
        int(room.get("height_blocks", 17)))
    entry["id"] = _suggest_background_image_id(arr)
    entry["image"] = rel_path
    entry["x_blocks"] = rect.position.x
    entry["y_blocks"] = rect.position.y
    entry["width_blocks"] = rect.size.x
    entry["height_blocks"] = rect.size.y
    arr.append(entry)
    room["background_images"] = arr
    _sync_legacy_background_image(room)
    selected_background_image_id = str(entry.get("id", ""))
    dirty = true
    return true


func pick_background_image_at(world_x: float, world_y: float) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var hit := find_background_image_hit(world_x, world_y)
    if hit.is_empty():
        return false
    selected_background_image_id = str(hit.get("id", "")).strip_edges()
    selected_background_asset = str(hit.get("image", "")).strip_edges()
    return true


func find_background_image_hit(world_x: float, world_y: float) -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return {}
    var arr := _get_background_images_ref(room)
    for i in range(arr.size() - 1, -1, -1):
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var rect := _background_rect_from_entry(entry)
        if Rect2(rect.position * 16.0, rect.size * 16.0).has_point(Vector2(world_x, world_y)):
            return entry.duplicate(true)
    return {}


func delete_background_image_at(world_x: float, world_y: float) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    for i in range(arr.size() - 1, -1, -1):
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var rect := _background_rect_from_entry(entry)
        if Rect2(rect.position * 16.0, rect.size * 16.0).has_point(Vector2(world_x, world_y)):
            arr.remove_at(i)
            room["background_images"] = arr
            _sync_legacy_background_image(room)
            if selected_background_image_id == str(entry.get("id", "")):
                selected_background_image_id = ""
            dirty = true
            return true
    return false


func set_selected_background_image_rect(rect_blocks: Rect2) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    var idx := _find_background_image_index(arr, selected_background_image_id)
    if idx < 0 or idx >= arr.size() or typeof(arr[idx]) != TYPE_DICTIONARY:
        return false
    var rect := _normalize_background_rect(rect_blocks)
    var entry: Dictionary = arr[idx]
    entry["x_blocks"] = rect.position.x
    entry["y_blocks"] = rect.position.y
    entry["width_blocks"] = maxf(0.0, rect.size.x)
    entry["height_blocks"] = maxf(0.0, rect.size.y)
    room["background_images"] = arr
    _sync_legacy_background_image(room)
    dirty = true
    return true


func update_selected_background_image(data: Dictionary) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    var idx := _find_background_image_index(arr, selected_background_image_id)
    if idx < 0 or idx >= arr.size() or typeof(arr[idx]) != TYPE_DICTIONARY:
        return false
    var before := _snapshot_list(arr)
    var entry: Dictionary = arr[idx]
    for key_v in data.keys():
        entry[str(key_v)] = data[key_v]
    entry = EnvIO._normalize_background_image_entry(
        entry,
        int(room.get("width_blocks", 30)),
        int(room.get("height_blocks", 17)),
        selected_background_image_id)
    arr[idx] = entry
    room["background_images"] = arr
    _sync_legacy_background_image(room)
    selected_background_asset = str(entry.get("image", selected_background_asset)).strip_edges()
    dirty = true
    _push_list_change(current_room_addr, "background_images",
        "edit background image", before, _snapshot_list(arr))
    return true


func reorder_selected_background_image(delta: int) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    var idx := _find_background_image_index(arr, selected_background_image_id)
    if idx < 0:
        return false
    var new_idx := clampi(idx + delta, 0, arr.size() - 1)
    if new_idx == idx:
        return false
    var before := _snapshot_list(arr)
    var entry: Variant = arr[idx]
    arr.remove_at(idx)
    arr.insert(new_idx, entry)
    room["background_images"] = arr
    _sync_legacy_background_image(room)
    dirty = true
    _push_list_change(current_room_addr, "background_images",
        "reorder background image", before, _snapshot_list(arr))
    return true


func delete_selected_background_image() -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    var idx := _find_background_image_index(arr, selected_background_image_id)
    if idx < 0:
        return false
    var before := _snapshot_list(arr)
    arr.remove_at(idx)
    room["background_images"] = arr
    _sync_legacy_background_image(room)
    selected_background_image_id = ""
    dirty = true
    _push_list_change(current_room_addr, "background_images",
        "delete background image", before, _snapshot_list(arr))
    return true


func merge_background_images_to_baked() -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_background_images_ref(room)
    if arr.is_empty():
        push_warning("[EnvEditor] no background images to merge")
        return false
    var room_w_px := maxi(1, int(room.get("width_blocks", 30)) * EnvIO.BLOCK_SIZE)
    var room_h_px := maxi(1, int(room.get("height_blocks", 17)) * EnvIO.BLOCK_SIZE)
    var baked: Image = Image.create_empty(room_w_px, room_h_px, false, Image.FORMAT_RGBA8)
    baked.fill(Color(0, 0, 0, 0))
    var before := _snapshot_list(arr)
    for entry_v in arr:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var entry_rel_path := str(entry.get("image", "")).strip_edges()
        if entry_rel_path.is_empty():
            continue
        var src: Image = EnvIO.load_backdrop_image(pack_id, entry_rel_path)
        if src == null:
            continue
        if src.get_format() != Image.FORMAT_RGBA8:
            src.convert(Image.FORMAT_RGBA8)
        var frame_count := maxi(1, int(entry.get("anim_frames", 1)))
        @warning_ignore("integer_division")
        var frame_w := maxi(1, int(src.get_width() / frame_count))
        var frame_img: Image = src.get_region(Rect2i(0, 0, frame_w, src.get_height()))
        var target_w := maxi(1, int(round(float(entry.get("width_blocks", 0.0)) * EnvIO.BLOCK_SIZE)))
        var target_h := maxi(1, int(round(float(entry.get("height_blocks", 0.0)) * EnvIO.BLOCK_SIZE)))
        if frame_img.get_width() != target_w or frame_img.get_height() != target_h:
            frame_img.resize(target_w, target_h, Image.INTERPOLATE_NEAREST)
        var tint := Color.from_string(str(entry.get("shader_tint", "ffffff")), Color.WHITE)
        if tint != Color.WHITE:
            for y in range(frame_img.get_height()):
                for x in range(frame_img.get_width()):
                    frame_img.set_pixel(x, y, frame_img.get_pixel(x, y) * tint)
        var dst_pos := Vector2i(
            int(round(float(entry.get("x_blocks", 0.0)) * EnvIO.BLOCK_SIZE)),
            int(round(float(entry.get("y_blocks", 0.0)) * EnvIO.BLOCK_SIZE)))
        var src_rect := Rect2i(0, 0, frame_img.get_width(), frame_img.get_height())
        if dst_pos.x < 0:
            src_rect.position.x = -dst_pos.x
            src_rect.size.x -= src_rect.position.x
            dst_pos.x = 0
        if dst_pos.y < 0:
            src_rect.position.y = -dst_pos.y
            src_rect.size.y -= src_rect.position.y
            dst_pos.y = 0
        src_rect.size.x = mini(src_rect.size.x, room_w_px - dst_pos.x)
        src_rect.size.y = mini(src_rect.size.y, room_h_px - dst_pos.y)
        if src_rect.size.x <= 0 or src_rect.size.y <= 0:
            continue
        baked.blend_rect(frame_img, src_rect, dst_pos)
    var room_name := current_room_addr.strip_edges().to_lower()
    if room_name.is_empty():
        room_name = "room"
    var rel_path := EnvIO.save_baked_backdrop(pack_id, "%s_merged_bg.png" % room_name, baked)
    if rel_path.is_empty():
        return false
    var merged_entry: Dictionary = EnvIO.default_background_image(
        int(room.get("width_blocks", 30)),
        int(room.get("height_blocks", 17)))
    merged_entry["id"] = "bg_merged"
    merged_entry["image"] = rel_path
    merged_entry["x_blocks"] = 0.0
    merged_entry["y_blocks"] = 0.0
    merged_entry["width_blocks"] = float(room.get("width_blocks", 30))
    merged_entry["height_blocks"] = float(room.get("height_blocks", 17))
    merged_entry["scroll_speed_x"] = 1.0
    merged_entry["scroll_speed_y"] = 1.0
    room["background_images"] = [merged_entry]
    _sync_legacy_background_image(room)
    selected_background_image_id = str(merged_entry.get("id", ""))
    selected_background_asset = rel_path
    _backdrop_textures.erase(rel_path)
    dirty = true
    _push_list_change(current_room_addr, "background_images",
        "merge background images", before, _snapshot_list(room["background_images"]))
    return true


func get_selected_zone_id() -> String:
    return selected_zone_id


func get_selected_zone_kind() -> String:
    var selected := get_selected_zone()
    if not selected.is_empty():
        return _normalize_zone_kind(str(selected.get("kind", selected_zone_kind)))
    return _normalize_zone_kind(selected_zone_kind)


func get_selected_zone() -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return {}
    var arr := _get_zones_ref(room)
    var idx := _find_zone_index(arr, selected_zone_id)
    if idx >= 0 and idx < arr.size() and typeof(arr[idx]) == TYPE_DICTIONARY:
        return (arr[idx] as Dictionary).duplicate(true)
    return {}


func get_selected_shader_region_id() -> String:
    return selected_zone_id


func get_selected_shader_region() -> Dictionary:
    var selected := get_selected_zone()
    if _normalize_zone_kind(str(selected.get("kind", ""))) == "shader":
        return selected
    return {}


func create_zone(rect_blocks: Rect2) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var rect := _normalize_background_rect(rect_blocks)
    if rect.size.x <= 0.01 or rect.size.y <= 0.01:
        return false
    var arr := _get_zones_ref(room)
    var entry: Dictionary = EnvIO.default_zone()
    entry["kind"] = _normalize_zone_kind(selected_zone_kind)
    entry["name"] = _zone_default_name(str(entry.get("kind", "shader")), arr)
    entry["x_blocks"] = rect.position.x
    entry["y_blocks"] = rect.position.y
    entry["width_blocks"] = rect.size.x
    entry["height_blocks"] = rect.size.y
    if str(entry.get("kind", "")) == "door":
        entry["direction"] = selected_door_direction
        entry["target_door_id"] = selected_door_target_room
        entry["target_room"] = ""
        entry["launch_to_space"] = selected_door_launch_to_space
        entry["enabled"] = selected_door_enabled
        entry["locked"] = selected_door_locked
        entry["required_item_id"] = selected_door_required_item_id
        entry["required_item_count"] = selected_door_required_item_count
        entry["required_var_name"] = selected_door_required_var_name
        entry["required_var_value"] = selected_door_required_var_value
        entry["required_global_tag"] = selected_door_required_global_tag
        entry["blocked_event_name"] = selected_door_blocked_event_name
        entry["success_event_name"] = selected_door_success_event_name
        entry["arrive_event_name"] = selected_door_arrive_event_name
    elif str(entry.get("kind", "")) == "interact":
        entry["interaction_mode"] = "interact"
        entry["event_name"] = "interact"
    elif str(entry.get("kind", "")) == "trigger":
        entry["interaction_mode"] = "enter"
    var normalized := _normalize_zone_for_room(entry, room, arr, str(entry.get("name", "")))
    arr.append(normalized)
    room["zones"] = arr
    _sync_room_zones(room)
    selected_zone_id = str(normalized.get("id", ""))
    selected_zone_kind = str(normalized.get("kind", selected_zone_kind))
    selected_shader_region_id = selected_zone_id
    if selected_zone_kind == "door":
        _sync_selected_door_fields(normalized)
    dirty = true
    return true


func create_shader_region(rect_blocks: Rect2) -> bool:
    selected_zone_kind = "shader"
    return create_zone(rect_blocks)


func find_zone_hit(world_x: float, world_y: float) -> Dictionary:
    var room := get_current_room()
    if room.is_empty():
        return {}
    var arr := _get_zones_ref(room)
    for i in range(arr.size() - 1, -1, -1):
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var rect := _zone_rect_from_entry(entry)
        if Rect2(rect.position * 16.0, rect.size * 16.0).has_point(Vector2(world_x, world_y)):
            return entry.duplicate(true)
    return {}


func find_shader_region_hit(world_x: float, world_y: float) -> Dictionary:
    var hit := find_zone_hit(world_x, world_y)
    if _normalize_zone_kind(str(hit.get("kind", ""))) == "shader":
        return hit
    return {}


func pick_zone_at(world_x: float, world_y: float) -> bool:
    var hit: Dictionary = find_zone_hit(world_x, world_y)
    if hit.is_empty():
        return false
    selected_zone_id = str(hit.get("id", "")).strip_edges()
    selected_zone_kind = str(hit.get("kind", selected_zone_kind))
    selected_shader_region_id = selected_zone_id
    if selected_zone_kind == "door":
        _sync_selected_door_fields(hit)
    return true


func pick_shader_region_at(world_x: float, world_y: float) -> bool:
    return pick_zone_at(world_x, world_y)


func delete_zone_at(world_x: float, world_y: float) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_zones_ref(room)
    for i in range(arr.size() - 1, -1, -1):
        var entry_v: Variant = arr[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var rect := _zone_rect_from_entry(entry)
        if Rect2(rect.position * 16.0, rect.size * 16.0).has_point(Vector2(world_x, world_y)):
            var before := _snapshot_list(arr)
            arr.remove_at(i)
            room["zones"] = arr
            _sync_room_zones(room)
            if selected_zone_id == str(entry.get("id", "")):
                selected_zone_id = ""
                selected_shader_region_id = ""
            dirty = true
            _push_list_change(current_room_addr, "zones",
                "delete zone", before, _snapshot_list(arr))
            return true
    return false


func delete_shader_region_at(world_x: float, world_y: float) -> bool:
    return delete_zone_at(world_x, world_y)


func set_selected_zone_rect(rect_blocks: Rect2) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_zones_ref(room)
    var idx := _find_zone_index(arr, selected_zone_id)
    if idx < 0 or idx >= arr.size() or typeof(arr[idx]) != TYPE_DICTIONARY:
        return false
    var rect := _normalize_background_rect(rect_blocks)
    var entry: Dictionary = arr[idx]
    entry["x_blocks"] = rect.position.x
    entry["y_blocks"] = rect.position.y
    entry["width_blocks"] = maxf(0.0, rect.size.x)
    entry["height_blocks"] = maxf(0.0, rect.size.y)
    room["zones"] = arr
    _sync_room_zones(room)
    dirty = true
    return true


func set_selected_shader_region_rect(rect_blocks: Rect2) -> bool:
    return set_selected_zone_rect(rect_blocks)


func update_selected_zone(data: Dictionary) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_zones_ref(room)
    var idx := _find_zone_index(arr, selected_zone_id)
    if idx < 0 or idx >= arr.size() or typeof(arr[idx]) != TYPE_DICTIONARY:
        return false
    var before := _snapshot_list(arr)
    var entry: Dictionary = arr[idx]
    var old_id := str(entry.get("id", "")).strip_edges()
    var was_door := _normalize_zone_kind(str(entry.get("kind", ""))) == "door"
    for key_v in data.keys():
        entry[str(key_v)] = data[key_v]
    entry = _normalize_zone_for_room(entry, room, arr,
        str(entry.get("name", "")), selected_zone_id)
    arr[idx] = entry
    room["zones"] = arr
    _sync_room_zones(room)
    selected_zone_id = str(entry.get("id", selected_zone_id))
    selected_zone_kind = str(entry.get("kind", selected_zone_kind))
    selected_shader_region_id = selected_zone_id
    if selected_zone_kind == "door":
        _sync_selected_door_fields(entry)
    if was_door:
        var new_id := str(entry.get("id", old_id)).strip_edges()
        if new_id != old_id:
            _retarget_door_links(old_id, new_id, new_id)
    dirty = true
    _push_list_change(current_room_addr, "zones",
        "edit zone", before, _snapshot_list(arr))
    return true


func update_selected_shader_region(data: Dictionary) -> bool:
    return update_selected_zone(data)


func reorder_selected_zone(delta: int) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_zones_ref(room)
    var idx := _find_zone_index(arr, selected_zone_id)
    if idx < 0:
        return false
    var new_idx := clampi(idx + delta, 0, arr.size() - 1)
    if new_idx == idx:
        return false
    var before := _snapshot_list(arr)
    var entry_v: Variant = arr[idx]
    arr.remove_at(idx)
    arr.insert(new_idx, entry_v)
    room["zones"] = arr
    _sync_room_zones(room)
    dirty = true
    _push_list_change(current_room_addr, "zones",
        "reorder zone", before, _snapshot_list(arr))
    return true


func reorder_selected_shader_region(delta: int) -> bool:
    return reorder_selected_zone(delta)


func delete_selected_zone() -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr := _get_zones_ref(room)
    var idx := _find_zone_index(arr, selected_zone_id)
    if idx < 0:
        return false
    var before := _snapshot_list(arr)
    arr.remove_at(idx)
    room["zones"] = arr
    _sync_room_zones(room)
    selected_zone_id = ""
    selected_shader_region_id = ""
    dirty = true
    _push_list_change(current_room_addr, "zones",
        "delete zone", before, _snapshot_list(arr))
    return true


func delete_selected_shader_region() -> bool:
    return delete_selected_zone()

func _resize_grid_in_place(host: Dictionary, key: String, new_rows: int, new_cols: int) -> void:
    var old_v: Variant = host.get(key)
    var old_arr: Array = []
    if typeof(old_v) == TYPE_ARRAY:
        old_arr = old_v
    var new_arr: Array = []
    for r in new_rows:
        var row: Array = []
        row.resize(new_cols)
        row.fill(0)
        if r < old_arr.size():
            var old_row_v: Variant = old_arr[r]
            if typeof(old_row_v) == TYPE_ARRAY:
                var old_row: Array = old_row_v
                var copy_cols := mini(new_cols, old_row.size())
                for c in copy_cols:
                    row[c] = old_row[c]
        new_arr.append(row)
    host[key] = new_arr


# ─── Tile layer CRUD ─────────────────────────────────────────────────────

func add_tile_layer(role: String) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    var rows := int(room.get("height_blocks", 0))
    var cols := int(room.get("width_blocks", 0))
    var layers := _get_tile_layers()
    var scroll := EnvTypes.default_scroll_for_role(role)
    var suggested_name := _suggest_layer_name(role, layers)
    var layer := EnvIO.default_tile_layer(suggested_name, role, scroll.x, scroll.y, rows, cols)
    # Insert bg layers at the end of the bg group, fg at the end overall,
    # main right after the last bg. Keeps the array in role-draw order.
    var insert_at: int = _insert_index_for_role(role, layers)
    layers.insert(insert_at, layer)
    room["tile_layers"] = layers
    active_mode = EnvTypes.MODE_TILE
    active_tile_layer_idx = insert_at
    dirty = true

func remove_tile_layer(idx: int) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    var layers := _get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return
    if layers.size() <= 1:
        push_warning("[EnvEditor] refusing to remove last remaining tile layer")
        return
    layers.remove_at(idx)
    room["tile_layers"] = layers
    if active_tile_layer_idx >= layers.size():
        active_tile_layer_idx = layers.size() - 1
    dirty = true

func move_tile_layer(idx: int, delta: int) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    var layers := _get_tile_layers()
    var new_idx := idx + delta
    if idx < 0 or idx >= layers.size() or new_idx < 0 or new_idx >= layers.size():
        return
    var layer_v: Variant = layers[idx]
    layers.remove_at(idx)
    layers.insert(new_idx, layer_v)
    room["tile_layers"] = layers
    if active_tile_layer_idx == idx:
        active_tile_layer_idx = new_idx
    elif active_tile_layer_idx == new_idx:
        active_tile_layer_idx = idx
    dirty = true

func set_tile_layer_scroll(idx: int, _sx: float, _sy: float) -> void:
    var layers := _get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return
    var layer_v: Variant = layers[idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    var layer: Dictionary = layer_v
    layer["scroll_speed_x"] = 1.0
    layer["scroll_speed_y"] = 1.0
    dirty = true

func rename_tile_layer(idx: int, new_name: String) -> void:
    var layers := _get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return
    var layer_v: Variant = layers[idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    (layer_v as Dictionary)["name"] = new_name
    dirty = true

func _normalize_main_layer_scrolls() -> void:
    var rooms := _rooms_dict()
    for room_key in rooms.keys():
        var room_v: Variant = rooms[room_key]
        if typeof(room_v) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_v
        var layers_v: Variant = room.get("tile_layers", [])
        if typeof(layers_v) != TYPE_ARRAY:
            continue
        for layer_v in layers_v:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = layer_v
            layer["scroll_speed_x"] = 1.0
            layer["scroll_speed_y"] = 1.0

func _suggest_layer_name(role: String, layers: Array) -> String:
    var prefix := EnvTypes.role_label(role).capitalize()
    var count := 0
    for l_v in layers:
        if typeof(l_v) != TYPE_DICTIONARY:
            continue
        if str((l_v as Dictionary).get("role", "")) == role:
            count += 1
    if count == 0:
        return prefix
    return "%s %d" % [prefix, count + 1]

func _insert_index_for_role(role: String, layers: Array) -> int:
    # tile_layers array order is also draw order (back-to-front). We keep
    # bg first, then main, then fg — new layers of a role slot in at the
    # end of that role's run so the author's existing stack keeps its
    # relative z-order.
    if role == EnvTypes.ROLE_FG:
        return layers.size()
    if role == EnvTypes.ROLE_BG:
        for i in layers.size():
            var lv: Variant = layers[i]
            if typeof(lv) != TYPE_DICTIONARY:
                continue
            if str((lv as Dictionary).get("role", "")) != EnvTypes.ROLE_BG:
                return i
        return layers.size()
    # ROLE_MAIN: insert after the last bg (or at end if no main yet).
    var last_bg := -1
    for i in layers.size():
        var lv: Variant = layers[i]
        if typeof(lv) != TYPE_DICTIONARY:
            continue
        if str((lv as Dictionary).get("role", "")) == EnvTypes.ROLE_BG:
            last_bg = i
    return last_bg + 1

func _cull_entities_outside(room: Dictionary, new_w: int, new_h: int) -> void:
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    var limit_x := new_w * 16
    var limit_y := new_h * 16
    var kept: Array = []
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var x := int(e.get("x", 0))
        var y := int(e.get("y", 0))
        if x >= 0 and x < limit_x and y >= 0 and y < limit_y:
            kept.append(e)
    room["entities"] = kept

func _cull_doors_outside(room: Dictionary, new_w: int, new_h: int) -> void:
    var arr_v: Variant = room.get("doors", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    var kept: Array = []
    for d_v in arr:
        if typeof(d_v) != TYPE_DICTIONARY:
            continue
        var d: Dictionary = d_v
        var cap_x := int(d.get("cap_x", -1))
        var cap_y := int(d.get("cap_y", -1))
        if cap_x >= 0 and cap_x < new_w and cap_y >= 0 and cap_y < new_h:
            kept.append(d)
    room["doors"] = kept


# ─── Room CRUD ───────────────────────────────────────────────────────────

func request_new_room() -> void:
    show_text_modal("New room", _suggest_new_room_name(),
        "Room name. The room id will be generated from it.",
        Callable(self, "_create_new_room"))

func request_rename_room(addr: String) -> void:
    var room_name := addr
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if rooms.has(addr):
        room_name = str((rooms[addr] as Dictionary).get("friendly_name", addr))
    show_text_modal("Rename room", room_name,
        "Room name for \"%s\". The room id updates to match." % addr,
        Callable(self, "_rename_room_to").bind(addr))

func _suggest_new_room_name() -> String:
    var rooms: Dictionary = rooms_data.get("rooms", {})
    var i := 1
    while true:
        var candidate_name := "Room %d" % i
        var candidate_id := RegIO.unique_content_id(candidate_name, rooms, "room")
        if not rooms.has(candidate_id):
            return candidate_name
        i += 1
    return "Room"

func _create_new_room(room_name: String) -> void:
    var trimmed_name := room_name.strip_edges()
    if trimmed_name.is_empty():
        push_warning("[EnvEditor] empty room address ignored")
        return
    var rooms: Dictionary = rooms_data.get("rooms", {})
    var addr := RegIO.unique_content_id(trimmed_name, rooms, "room")
    if rooms.has(addr):
        push_warning("[EnvEditor] room '%s' already exists" % addr)
        return
    var new_room := EnvIO.default_room(addr, trimmed_name,
        EnvIO.DEFAULT_ROOM_W_BLOCKS, EnvIO.DEFAULT_ROOM_H_BLOCKS, selected_tileset_id)
    rooms[addr] = new_room
    rooms_data["rooms"] = rooms
    if str(rooms_data.get("start_room", "")).is_empty():
        rooms_data["start_room"] = addr
    current_room_addr = addr
    dirty = true

func _rename_room_to(new_name: String, old_addr: String) -> void:
    var trimmed_name := new_name.strip_edges()
    if trimmed_name.is_empty():
        return
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if not rooms.has(old_addr):
        return
    var new_addr := RegIO.unique_content_id(trimmed_name, rooms, "room", old_addr)
    if new_addr == old_addr and trimmed_name == str((rooms[old_addr] as Dictionary).get("friendly_name", old_addr)).strip_edges():
        return
    if new_addr != old_addr and rooms.has(new_addr):
        push_warning("[EnvEditor] room '%s' already exists" % new_addr)
        return
    var room: Dictionary = (rooms[old_addr] as Dictionary).duplicate(true)
    room["addr"] = new_addr
    room["friendly_name"] = trimmed_name
    var door_id_remap := _rebase_room_door_ids(room, new_addr)
    if new_addr == old_addr:
        rooms[old_addr] = room
    else:
        rooms[new_addr] = room
        rooms.erase(old_addr)
    if str(rooms_data.get("start_room", "")) == old_addr:
        rooms_data["start_room"] = new_addr
    if current_room_addr == old_addr:
        current_room_addr = new_addr
    if door_id_remap.has(selected_zone_id):
        selected_zone_id = str(door_id_remap[selected_zone_id])
        selected_shader_region_id = selected_zone_id
    # Fix up door targets that point at this room.
    for key in rooms.keys():
        var other: Variant = rooms[key]
        if typeof(other) != TYPE_DICTIONARY:
            continue
        var other_room := other as Dictionary
        var zones_v: Variant = other_room.get("zones", [])
        if typeof(zones_v) == TYPE_ARRAY:
            for zone_v in zones_v:
                if typeof(zone_v) != TYPE_DICTIONARY:
                    continue
                var zone: Dictionary = zone_v
                if _normalize_zone_kind(str(zone.get("kind", ""))) == "door" \
                        and str(zone.get("target_room", "")).strip_edges() == old_addr:
                    zone["target_room"] = new_addr
            _sync_room_zones(other_room)
        var doors_v: Variant = other_room.get("doors", [])
        if typeof(doors_v) != TYPE_ARRAY:
            continue
        for d_v in doors_v:
            if typeof(d_v) != TYPE_DICTIONARY:
                continue
            if str((d_v as Dictionary).get("target_room", "")) == old_addr:
                (d_v as Dictionary)["target_room"] = new_addr
    for old_door_id_v in door_id_remap.keys():
        var old_door_id := str(old_door_id_v)
        _retarget_door_links(old_door_id, str(door_id_remap[old_door_id]))
    dirty = true

func delete_room(addr: String) -> void:
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if not rooms.has(addr):
        return
    if rooms.size() <= 1:
        push_warning("[EnvEditor] refusing to delete last remaining room")
        return
    rooms.erase(addr)
    if str(rooms_data.get("start_room", "")) == addr:
        var keys := rooms.keys()
        keys.sort()
        rooms_data["start_room"] = str(keys[0]) if not keys.is_empty() else ""
    if current_room_addr == addr:
        var keys2 := rooms.keys()
        keys2.sort()
        current_room_addr = str(keys2[0]) if not keys2.is_empty() else ""
    dirty = true

func request_duplicate_room(addr: String) -> void:
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if not rooms.has(addr):
        return
    show_text_modal("Duplicate room", addr + "_copy",
        "Address for the copy of \"%s\"." % addr,
        Callable(self, "_duplicate_room").bind(addr))

func _duplicate_room(new_addr: String, src_addr: String) -> void:
    new_addr = new_addr.strip_edges()
    if new_addr.is_empty():
        return
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if rooms.has(new_addr):
        push_warning("[EnvEditor] room '%s' already exists" % new_addr)
        return
    if not rooms.has(src_addr):
        return
    var src: Dictionary = rooms[src_addr]
    var copy: Dictionary = _deep_copy_dict(src)
    copy["addr"] = new_addr
    copy["name"] = new_addr
    _rebase_room_door_ids(copy, new_addr)
    rooms[new_addr] = copy
    rooms_data["rooms"] = rooms
    current_room_addr = new_addr
    dirty = true
    print("[EnvEditor] duplicated room '%s' → '%s'" % [src_addr, new_addr])

static func _deep_copy_dict(d: Dictionary) -> Dictionary:
    var raw := JSON.stringify(d)
    var parsed: Variant = JSON.parse_string(raw)
    if typeof(parsed) == TYPE_DICTIONARY:
        return parsed
    return d.duplicate(true)

func set_start_room(addr: String) -> void:
    var rooms: Dictionary = rooms_data.get("rooms", {})
    if not rooms.has(addr):
        return
    rooms_data["start_room"] = addr
    dirty = true

func get_start_room_addr() -> String:
    return str(rooms_data.get("start_room", ""))


# ─── Entity placement ────────────────────────────────────────────────────

func _entity_cell_from_world(world_x: float, world_y: float) -> Vector2i:
    return Vector2i(
        maxi(0, floori(world_x / 16.0)),
        maxi(0, floori(world_y / 16.0))
    )


func _entity_base_instance_id(type_id: String, world_x: float, world_y: float) -> String:
    var cell := _entity_cell_from_world(world_x, world_y)
    if type_id == "trigger_volume":
        return "zone_%d_%d" % [cell.x, cell.y]
    return "%s_%d_%d" % [type_id, cell.x, cell.y]


func _entity_id_taken(arr: Array, instance_id: String) -> bool:
    if instance_id.is_empty():
        return false
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var props_v: Variant = e.get("properties", {})
        if typeof(props_v) != TYPE_DICTIONARY:
            continue
        if str((props_v as Dictionary).get("instance_id", "")).strip_edges() == instance_id:
            return true
    return false


func _suggest_entity_instance_id(type_id: String, world_x: float, world_y: float, arr: Array) -> String:
    var base := _entity_base_instance_id(type_id, world_x, world_y)
    if not _entity_id_taken(arr, base):
        return base
    var suffix := 2
    while true:
        var candidate := "%s_%d" % [base, suffix]
        if not _entity_id_taken(arr, candidate):
            return candidate
        suffix += 1
    return base


func _zone_id_taken(arr: Array, zone_id: String) -> bool:
    if zone_id.is_empty():
        return false
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("type", "")) != "trigger_volume":
            continue
        var props_v: Variant = e.get("properties", {})
        if typeof(props_v) != TYPE_DICTIONARY:
            continue
        if str((props_v as Dictionary).get("zone_id", "")).strip_edges() == zone_id:
            return true
    return false


func _suggest_zone_id(world_x: float, world_y: float, arr: Array) -> String:
    var cell := _entity_cell_from_world(world_x, world_y)
    var base := "zone_%d_%d" % [cell.x, cell.y]
    if not _zone_id_taken(arr, base):
        return base
    var suffix := 2
    while true:
        var candidate := "%s_%d" % [base, suffix]
        if not _zone_id_taken(arr, candidate):
            return candidate
        suffix += 1
    return base


func _default_entity_properties(type_id: String, world_x: float, world_y: float, arr: Array) -> Dictionary:
    if type_id == "player_spawn":
        return {
            "facing": "right",
        }
    var props: Dictionary = {
        "instance_id": _suggest_entity_instance_id(type_id, world_x, world_y, arr),
    }
    if type_id == "trigger_volume":
        props["width"] = 16
        props["height"] = 16
        props["zone_id"] = _suggest_zone_id(world_x, world_y, arr)
        props["event_name"] = "zone_enter"
        props["once"] = false
    return props


func _entity_palette_kind_for_type(type_id: String) -> String:
    var trimmed := type_id.strip_edges()
    if EnvTypes.ENTITY_TYPES.has(trimmed):
        return trimmed
    var data: Dictionary = EntIO.load_or_init(pack_id)
    var arr_v: Variant = data.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return trimmed
    for entity_v in arr_v:
        if typeof(entity_v) != TYPE_DICTIONARY:
            continue
        var entity: Dictionary = entity_v
        if str(entity.get("id", "")).strip_edges() != trimmed:
            continue
        var category := str(entity.get("category", "")).strip_edges().to_lower()
        if category == "interactable":
            return "npc"
        if category == "pickup":
            return "pickup"
        if category == "logic":
            return "trigger_volume"
        if category == "enemy" or category == "boss":
            return "enemy"
    return trimmed


func _entity_type_uses_authored_picker(type_id: String) -> bool:
    return type_id == "npc" or type_id == "sign" or type_id == "pickup" \
        or type_id == "patroller" or type_id == "enemy"


func _ensure_entity_def_cache() -> void:
    if not _entity_defs_by_id.is_empty():
        return
    var data: Dictionary = EntIO.load_or_init(pack_id)
    var arr_v: Variant = data.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    for entity_v in arr:
        if typeof(entity_v) != TYPE_DICTIONARY:
            continue
        var entity: Dictionary = entity_v
        var entity_id := str(entity.get("id", "")).strip_edges()
        if not entity_id.is_empty():
            _entity_defs_by_id[entity_id] = entity


func _entity_def_for_type(type_id: String) -> Dictionary:
    _ensure_entity_def_cache()
    var entity_v: Variant = _entity_defs_by_id.get(type_id, {})
    if typeof(entity_v) == TYPE_DICTIONARY:
        return entity_v
    return {}


func _pick_entity_preview_png(pngs: Array) -> String:
    if pngs.is_empty():
        return ""
    for name_v in pngs:
        var png_name := str(name_v).to_lower()
        if png_name.contains("idle"):
            return str(name_v)
    for name_v in pngs:
        var png_name := str(name_v).to_lower()
        if png_name.contains("walk"):
            return str(name_v)
    for name_v in pngs:
        var png_name := str(name_v).to_lower()
        if png_name.contains("default"):
            return str(name_v)
    return str(pngs[0])


func get_entity_preview_texture(type_id: String) -> Texture2D:
    var clean := type_id.strip_edges()
    if clean.is_empty():
        return null
    if _entity_preview_textures.has(clean):
        var cached: Variant = _entity_preview_textures.get(clean)
        if cached is Texture2D:
            return cached
        return null
    var entity := _entity_def_for_type(clean)
    if entity.is_empty():
        _entity_preview_textures[clean] = null
        return null
    var sprite_set_rel := str(entity.get("sprite_set", "")).strip_edges()
    if sprite_set_rel.is_empty():
        _entity_preview_textures[clean] = null
        return null
    var pngs := EntIO.list_sprite_pngs(pack_id, sprite_set_rel)
    if pngs.is_empty():
        _entity_preview_textures[clean] = null
        return null
    var preview_png := _pick_entity_preview_png(pngs)
    if preview_png.is_empty():
        _entity_preview_textures[clean] = null
        return null
    var tex := EntIO.load_sprite_png(pack_id, sprite_set_rel, preview_png)
    _entity_preview_textures[clean] = tex
    return tex


func get_entity_preview_label(type_id: String) -> String:
    var entity := _entity_def_for_type(type_id.strip_edges())
    if not entity.is_empty():
        var entity_name := str(entity.get("name", "")).strip_edges()
        if not entity_name.is_empty():
            return entity_name
    return EnvTypes.entity_label(type_id)


func place_entity_at(world_x: float, world_y: float) -> void:
    var room := get_current_room()
    if room.is_empty():
        return
    var rows := int(room.get("height_blocks", 0))
    var cols := int(room.get("width_blocks", 0))
    var room_w_px := float(cols * 16)
    var room_h_px := float(rows * 16)
    if world_x < 0 or world_y < 0 or world_x >= room_w_px or world_y >= room_h_px:
        return
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        arr_v = []
    var arr: Array = arr_v
    var before := _snapshot_list(arr)
    # player_spawn is singleton — replace any existing spawn instead of appending.
    if selected_entity_type == "player_spawn":
        for i in arr.size():
            var e_v: Variant = arr[i]
            if typeof(e_v) != TYPE_DICTIONARY:
                continue
            if str((e_v as Dictionary).get("type", "")) == "player_spawn":
                (e_v as Dictionary)["x"] = int(world_x)
                (e_v as Dictionary)["y"] = int(world_y)
                room["entities"] = arr
                dirty = true
                _push_list_change(current_room_addr, "entities",
                    "move player spawn", before, _snapshot_list(arr))
                return
    var entity := {
        "type": selected_entity_type,
        "x": int(world_x),
        "y": int(world_y),
    }
    var props := _default_entity_properties(selected_entity_type, world_x, world_y, arr)
    if not props.is_empty():
        entity["properties"] = props
    arr.append(entity)
    room["entities"] = arr
    dirty = true
    _push_list_change(current_room_addr, "entities",
        "place %s" % selected_entity_type, before, _snapshot_list(arr))
    if _entity_type_uses_authored_picker(selected_entity_type):
        request_edit_entity(arr.size() - 1, true)

func delete_entity_near(world_x: float, world_y: float, radius_px: float = 10.0) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return false
    var arr: Array = arr_v
    var best_idx := -1
    var best_dist := radius_px * radius_px
    for i in arr.size():
        var e_v: Variant = arr[i]
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var dx := float(e.get("x", 0)) - world_x
        var dy := float(e.get("y", 0)) - world_y
        var d := dx * dx + dy * dy
        if d <= best_dist:
            best_dist = d
            best_idx = i
    if best_idx < 0:
        return false
    var before := _snapshot_list(arr)
    arr.remove_at(best_idx)
    room["entities"] = arr
    dirty = true
    _push_list_change(current_room_addr, "entities",
        "delete entity", before, _snapshot_list(arr))
    return true

# ─── Door placement ──────────────────────────────────────────────────────

func place_door_at(row: int, col: int) -> void:
    selected_zone_kind = "door"
    create_zone(Rect2(Vector2(float(col), float(row)), Vector2.ONE))

func delete_door_at(row: int, col: int) -> bool:
    return delete_zone_at(float(col * 16 + 8), float(row * 16 + 8))

func pick_door_at(row: int, col: int) -> bool:
    var picked := pick_zone_at(float(col * 16 + 8), float(row * 16 + 8))
    var selected := get_selected_zone()
    if picked and _normalize_zone_kind(str(selected.get("kind", ""))) == "door":
        _sync_selected_door_fields(selected)
        return true
    return picked


func pick_entity_at(world_x: float, world_y: float, radius_px: float = 10.0) -> bool:
    var room := get_current_room()
    if room.is_empty():
        return false
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return false
    var arr: Array = arr_v
    var best_idx := -1
    var best_dist := radius_px * radius_px
    for i in arr.size():
        var e_v: Variant = arr[i]
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var dx := float(e.get("x", 0)) - world_x
        var dy := float(e.get("y", 0)) - world_y
        var d := dx * dx + dy * dy
        if d <= best_dist:
            best_dist = d
            best_idx = i
    if best_idx < 0:
        return false
    var hit: Dictionary = arr[best_idx]
    selected_entity_type = _entity_palette_kind_for_type(str(hit.get("type", selected_entity_type)))
    request_edit_entity(best_idx)
    return true


# ─── Spike profile modal ────────────────────────────────────────────────

# Pending cell coordinates for the spike modal — set before opening, read
# on submit to know which BTS cell to write the profile id into.
var _entity_pending_idx: int = -1
var _entity_pending_new_placement: bool = false
var _spike_pending_row: int = -1
var _spike_pending_col: int = -1

func request_edit_entity(index: int, from_new_placement: bool = false) -> void:
    if entity_modal == null:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    if index < 0 or index >= arr.size():
        return
    var entity_v: Variant = arr[index]
    if typeof(entity_v) != TYPE_DICTIONARY:
        return
    var entity: Dictionary = entity_v
    var props_v: Variant = entity.get("properties", {})
    var props: Dictionary = {}
    if typeof(props_v) == TYPE_DICTIONARY:
        props = props_v
    _entity_pending_idx = index
    _entity_pending_new_placement = from_new_placement
    entity_modal.open(
        pack_id,
        str(entity.get("type", "")),
        float(entity.get("x", 0)),
        float(entity.get("y", 0)),
        props
    )


func _on_entity_modal_submit(data: Dictionary) -> void:
    if _entity_pending_idx < 0:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var arr_v: Variant = room.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    var arr: Array = arr_v
    if _entity_pending_idx < 0 or _entity_pending_idx >= arr.size():
        return
    var entity_v: Variant = arr[_entity_pending_idx]
    if typeof(entity_v) != TYPE_DICTIONARY:
        return
    var before := _snapshot_list(arr)
    var entity: Dictionary = entity_v
    var type_override := str(data.get("type_id", "")).strip_edges()
    if not type_override.is_empty():
        entity["type"] = type_override
    var merged_props: Dictionary = {}
    var props_v: Variant = entity.get("properties", {})
    if typeof(props_v) == TYPE_DICTIONARY:
        merged_props = (props_v as Dictionary).duplicate(true)
    var clear_keys_v: Variant = data.get("clear_keys", [])
    if typeof(clear_keys_v) == TYPE_ARRAY:
        for key_v in clear_keys_v:
            merged_props.erase(str(key_v))
    for key_v in data.keys():
        var key := str(key_v)
        if key == "type_id" or key == "clear_keys":
            continue
        merged_props[key] = data[key_v]
    if merged_props.is_empty():
        entity.erase("properties")
    else:
        entity["properties"] = merged_props
    room["entities"] = arr
    dirty = true
    _push_list_change(current_room_addr, "entities",
        "edit entity properties", before, _snapshot_list(arr))
    _entity_pending_idx = -1
    _entity_pending_new_placement = false


func _on_entity_modal_cancel() -> void:
    if _entity_pending_new_placement and _entity_pending_idx >= 0:
        var room := get_current_room()
        if not room.is_empty():
            var arr_v: Variant = room.get("entities", [])
            if typeof(arr_v) == TYPE_ARRAY:
                var arr: Array = arr_v
                if _entity_pending_idx >= 0 and _entity_pending_idx < arr.size():
                    var before := _snapshot_list(arr)
                    arr.remove_at(_entity_pending_idx)
                    room["entities"] = arr
                    dirty = true
                    _push_list_change(current_room_addr, "entities",
                        "cancel new entity placement", before, _snapshot_list(arr))
    _entity_pending_idx = -1
    _entity_pending_new_placement = false

func request_edit_spike(row: int, col: int) -> void:
    if spike_modal == null:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var bts_v: Variant = room.get("bts", [])
    if typeof(bts_v) != TYPE_ARRAY:
        return
    var bts: Array = bts_v
    var current_bts: int = 0
    if row < bts.size():
        var bts_row_v: Variant = bts[row]
        if typeof(bts_row_v) == TYPE_ARRAY:
            var bts_row: Array = bts_row_v
            if col < bts_row.size():
                current_bts = int(bts_row[col])
    _spike_pending_row = row
    _spike_pending_col = col
    spike_modal.open(pack_id, current_bts)

func _on_spike_modal_submit(bts_value: int) -> void:
    if _spike_pending_row < 0 or _spike_pending_col < 0:
        return
    var room := get_current_room()
    if room.is_empty():
        return
    var bts_v: Variant = room.get("bts", [])
    if typeof(bts_v) != TYPE_ARRAY:
        return
    var bts: Array = bts_v
    if _spike_pending_row < bts.size():
        var bts_row_v: Variant = bts[_spike_pending_row]
        if typeof(bts_row_v) == TYPE_ARRAY:
            var bts_row: Array = bts_row_v
            if _spike_pending_col < bts_row.size():
                bts_row[_spike_pending_col] = bts_value
                dirty = true
    _spike_pending_row = -1
    _spike_pending_col = -1
    # Refresh cached profiles in case the user created/edited one.
    _spike_profiles = EnvIO.load_spike_profiles(pack_id)

func _on_spike_modal_cancel() -> void:
    _spike_pending_row = -1
    _spike_pending_col = -1

func get_spike_profiles() -> Array:
    return _spike_profiles

func get_spike_profile_name(bts_value: int) -> String:
    for p in _spike_profiles:
        if typeof(p) == TYPE_DICTIONARY and int((p as Dictionary).get("id", -1)) == bts_value:
            return str((p as Dictionary).get("name", ""))
    return ""


# ─── Tile animation modal ───────────────────────────────────────────────

func request_edit_tile_anim(row: int, col: int, packed_value: int) -> void:
    if anim_modal == null:
        return
    var info := MvTileValue.unpack_full(packed_value)
    var ts_id := int(info["tileset"])
    var metatile_idx := int(info["idx"])
    var tex := get_tileset_texture(ts_id)
    if tex == null:
        return
    var gcols := get_tileset_grid_cols(ts_id)

    # Look up existing animation for this cell in the active tile layer.
    var existing_anim: Dictionary = {}
    var layers := _get_tile_layers()
    if active_tile_layer_idx >= 0 and active_tile_layer_idx < layers.size():
        var layer_v: Variant = layers[active_tile_layer_idx]
        if typeof(layer_v) == TYPE_DICTIONARY:
            var layer_d: Dictionary = layer_v
            var anims_v: Variant = layer_d.get("animations", {})
            if typeof(anims_v) == TYPE_DICTIONARY:
                var key := "%d,%d" % [col, row]
                var entry_v: Variant = (anims_v as Dictionary).get(key, {})
                if typeof(entry_v) == TYPE_DICTIONARY:
                    existing_anim = entry_v

    _anim_pending_layer_idx = active_tile_layer_idx
    _anim_pending_row = row
    _anim_pending_col = col
    anim_modal.open(tex, ts_id, gcols, metatile_idx, existing_anim)


func _on_anim_modal_submit(anim_data: Dictionary) -> void:
    if _anim_pending_layer_idx < 0:
        return
    var layers := _get_tile_layers()
    if _anim_pending_layer_idx >= layers.size():
        return
    var layer_v: Variant = layers[_anim_pending_layer_idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    var layer_d: Dictionary = layer_v
    if not layer_d.has("animations"):
        layer_d["animations"] = {}
    var anims: Variant = layer_d["animations"]
    if typeof(anims) != TYPE_DICTIONARY:
        layer_d["animations"] = {}
        anims = layer_d["animations"]
    var anims_d: Dictionary = anims
    var key := "%d,%d" % [_anim_pending_col, _anim_pending_row]
    if anim_data.is_empty():
        # Clear animation
        anims_d.erase(key)
    else:
        anims_d[key] = anim_data
    dirty = true
    _anim_pending_layer_idx = -1
    _anim_pending_row = -1
    _anim_pending_col = -1


func _on_anim_modal_cancel() -> void:
    _anim_pending_layer_idx = -1
    _anim_pending_row = -1
    _anim_pending_col = -1


# Returns the animations dict for the given tile layer index, or empty.
func get_tile_layer_animations(layer_idx: int) -> Dictionary:
    var layers := _get_tile_layers()
    if layer_idx < 0 or layer_idx >= layers.size():
        return {}
    var layer_v: Variant = layers[layer_idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return {}
    var anims_v: Variant = (layer_v as Dictionary).get("animations", {})
    if typeof(anims_v) == TYPE_DICTIONARY:
        return anims_v
    return {}
