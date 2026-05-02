extends Control


const ModuleVisuals = preload("res://Space/scripts/autoload/module_visuals.gd")




var HEX_SIZE: float = 28.0
var _base_hex_size: float = 28.0
var builder_zoom: float = 1.0
const BUILDER_ZOOM_MIN: float = 0.4
const BUILDER_ZOOM_MAX: float = 2.5
const BUILDER_ZOOM_STEP: float = 0.1


var hull_pattern: Array[String] = []
var hull_cells: Array = []
var hull_cell_set: Dictionary = {}
var engine_edge_cells: Array = []
var core_cells: Dictionary = {}


var grid_origin: Vector2 = Vector2.ZERO
var palette_rect: Rect2 = Rect2()
var stats_rect: Rect2 = Rect2()


var placed_modules: Array = []
var module_inventory: Dictionary = {}
var selected_module_id: String = ""
var hovered_cell: Vector2i = Vector2i(-9999, -9999)
var hovered_palette_idx: int = -1
var palette_scroll: float = 0.0
var placement_rotation: int = 0
var collapsed_categories: Dictionary = {}


var gamepad_cursor_pos: Vector2 = Vector2.ZERO
var gamepad_cursor_initialized: bool = false
var gamepad_palette_mode: bool = false
var gamepad_palette_idx: int = -1
var _gamepad_cursor_speed: float = 600.0


var search_text: String = ""
var search_active: bool = false
var search_bar_rect: Rect2 = Rect2()


var type_colors: Dictionary = {
    "weapon": Color(0.9, 0.25, 0.2), 
    "shield": Color(0.25, 0.45, 1.0), 
    "engine": Color(1.0, 0.6, 0.15), 
    "reactor": Color(0.95, 0.85, 0.15), 
    "armor": Color(0.5, 0.55, 0.6), 
    "sensor": Color(0.2, 0.85, 0.4), 
    "conduit": Color(0.6, 0.5, 0.2), 
    "hallway": Color(0.45, 0.45, 0.5), 
    "airlock": Color(0.7, 0.5, 0.2), 
    "structural": Color(0.5, 0.5, 0.55), 
    "cargo": Color(0.7, 0.55, 0.2), 
    "core": Color(0.8, 0.75, 0.9), 
    "quarters": Color(0.75, 0.55, 0.3), 
    "mess": Color(0.8, 0.5, 0.2), 
    "medbay": Color(0.3, 0.8, 0.4), 
    "construction_hangar": Color(0.55, 0.55, 0.6), 
    "docking_collar": Color(0.6, 0.45, 0.7), 
    "basic_workshop": Color(0.6, 0.5, 0.35), 
    "farmers_workshop": Color(0.4, 0.65, 0.3), 
    "solar_field": Color(0.85, 0.75, 0.3), 
    "life_support": Color(0.3, 0.7, 0.7), 
    "brig": Color(0.45, 0.4, 0.4), 
    "hangar": Color(0.4, 0.5, 0.7), 
    "hydroponics": Color(0.3, 0.75, 0.3), 
    "armory": Color(0.8, 0.4, 0.15), 
    "rec_room": Color(0.6, 0.5, 0.8), 
    "bridge": Color(0.5, 0.6, 0.9), 
    "fuel_scoop": Color(0.9, 0.7, 0.2), 
    "mining": Color(0.7, 0.5, 0.3), 
    "research_lab": Color(0.3, 0.6, 0.9), 
    "ladder": Color(0.65, 0.55, 0.35), 
    "colony_spear": Color(0.5, 0.8, 0.4), 
    "fleet_comm": Color(0.5, 0.65, 0.9), 
    "fuel_tank": Color(0.9, 0.65, 0.2), 
}


const PALETTE_CATEGORIES: Array = [
    {"label": "COMBAT", "types": ["weapon"], "color": Color(0.9, 0.3, 0.25)}, 
    {"label": "DEFENSE", "types": ["shield", "armor", "shield_supercharger"], "color": Color(0.3, 0.5, 1.0)},
    {"label": "PROPULSION", "types": ["engine"], "color": Color(1.0, 0.6, 0.2)}, 
    {"label": "POWER", "types": ["reactor", "conduit"], "color": Color(0.95, 0.85, 0.2)}, 
    {"label": "SENSORS", "types": ["sensor"], "color": Color(0.25, 0.85, 0.45)}, 
    {"label": "CREW", "types": ["quarters", "mess", "medbay", "life_support", "brig", "rec_room"], "color": Color(0.75, 0.55, 0.35)}, 
    {"label": "OPERATIONS", "types": ["bridge", "construction_hangar", "hangar", "research_lab", "armory"], "color": Color(0.5, 0.6, 0.85)}, 
    {"label": "PRODUCTION", "types": ["smelter", "kitchen", "brewery", "fabricator"], "color": Color(0.7, 0.55, 0.3)}, 
    {"label": "WORKSHOPS", "types": ["basic_workshop", "farmers_workshop", "solar_field"], "color": Color(0.55, 0.65, 0.35)}, 
    {"label": "LIVESTOCK", "types": ["animal_pen", "aquaculture_tank"], "color": Color(0.65, 0.5, 0.3)}, 
    {"label": "CARGO & MINING", "types": ["cargo", "mining", "fuel_scoop", "fuel_tank", "hydroponics"], "color": Color(0.7, 0.55, 0.25)}, 
    {"label": "STRUCTURE", "types": ["hallway", "airlock", "structural", "ladder"], "color": Color(0.5, 0.5, 0.55)}, 
    {"label": "FLEET & COLONY", "types": ["colony_spear", "fleet_comm", "docking_collar"], "color": Color(0.5, 0.75, 0.5)}, 
]


var powered_indices: Array = []

var _skip_close_frame: bool = false


var color_presets: Array[Color] = [
    Color(0.3, 0.55, 0.8), 
    Color(0.2, 0.65, 0.5), 
    Color(0.7, 0.3, 0.25), 
    Color(0.85, 0.55, 0.15), 
    Color(0.55, 0.35, 0.7), 
    Color(0.25, 0.7, 0.3), 
    Color(0.75, 0.75, 0.75), 
    Color(0.35, 0.35, 0.4), 
    Color(0.15, 0.2, 0.35), 
    Color(0.6, 0.5, 0.3), 
]
var editing_color_slot: int = 0
var color_picker_rects: Array[Rect2] = []
var color_slot_rects: Array[Rect2] = []
var color_picker_open: bool = false
var color_picker_hue: float = 0.6
var _cp_sv_rect: Rect2 = Rect2()
var _cp_hue_rect: Rect2 = Rect2()
var _cp_panel_rect: Rect2 = Rect2()


var core_ids: Array = []
var core_btn_rects: Array[Rect2] = []


var current_deck: int = 0
var deck_count: int = 1
var deck_tab_rects: Array[Rect2] = []
var _rotate_pressed: bool = false




var fleet_mode: bool = false
var fleet_core_id: String = ""
var _saved_player_core: String = ""



var creative_mode: bool = false


var colony_mode: bool = false
var colony_id: String = ""


var _t_pressed: bool = false
var template_naming: bool = false
var template_name_input: String = ""
var _template_save_flash: float = 0.0
var _template_save_name: String = ""


var _creative_templates: Array = []
var _creative_template_scroll: float = 0.0
var _creative_template_hovered: int = -1
var _creative_template_rects: Array = []
var _creative_show_templates: bool = false

var _btn_save_template: Rect2 = Rect2()
var _btn_test_fly: Rect2 = Rect2()
var _btn_load_template: Rect2 = Rect2()
var _btn_test_ships: Rect2 = Rect2()
var _btn_record_ai: Rect2 = Rect2()
var _btn_fight_ai: Rect2 = Rect2()
var _btn_ai_design: Rect2 = Rect2()
const _AIDesignPanelScript = preload("res://Space/scripts/ship_builder/ai_design_panel.gd")
var _ai_design_panel: Control = null
var _ai_design_open: bool = false
var _recording_after_save: bool = false
var _test_ships_open: bool = false
var _test_ships_rects: Array = []
var _test_ships_scroll: float = 0.0
var _fight_ai_open: bool = false
const TEST_SHIP_TEMPLATES: Array = ["superchargerhornet"]
var _l_pressed: bool = false
var _f_pressed: bool = false


const NPC_COMBAT_STYLES: Array = ["standard", "hit_and_run"]
var _template_combat_style: String = "standard"


var sub_hex_mode: bool = false
var sub_hex_cell: Vector2i = Vector2i.ZERO
var sub_hex_deck: int = 0
var sub_hex_hovered: int = -1
var sub_hex_module: Dictionary = {}
var _last_click_time: float = 0.0
var _last_click_cell: Vector2i = Vector2i(-9999, -9999)

signal closed(placed: Array)
signal test_fly_requested(placed: Array, core_id: String)
signal record_ai_requested(placed: Array, core_id: String, template_name: String)
signal fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String)

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = MOUSE_FILTER_STOP
    focus_mode = FOCUS_ALL
    _find_core_ids()
    _load_hull_from_core()
    refresh_layout()
    _load_state()
    # AI Design panel (child overlay)
    _ai_design_panel = _AIDesignPanelScript.new()
    _ai_design_panel.visible = false
    add_child(_ai_design_panel)
    _ai_design_panel.train_ai_requested.connect(_on_ai_design_train)
    _ai_design_panel.fight_ai_requested.connect(_on_ai_design_fight)
    _ai_design_panel.back_requested.connect(_on_ai_design_back)

func _notification(what: int):
    if what == NOTIFICATION_RESIZED and is_node_ready():
        refresh_layout()

func _find_core_ids():
    core_ids.clear()
    for id in DataManager.modules:
        if DataManager.modules[id].get("type", "") == "core":
            core_ids.append(id)

func _load_hull_from_core():
    var core_data = DataManager.modules.get(GameManager.equipped_core, {})
    deck_count = int(core_data.get("deck_count", 1))
    current_deck = mini(current_deck, deck_count - 1)
    var radius = int(core_data.get("hull_radius", 0))
    if radius > 0:

        hull_cells = HexUtil.generate_hex_disc(radius)
    else:

        var pattern = core_data.get("hull_pattern", [])
        hull_pattern.clear()
        if pattern.is_empty():
            hull_pattern = [
                "...XX...", "..XXXX..", "..XXXX..", ".XXXXXX.", 
                "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", 
                "..XXXX..", "...XX...", 
            ]
        else:
            for row in pattern:
                hull_pattern.append(str(row))
        hull_cells = HexUtil.parse_hull_pattern(hull_pattern)
    hull_cell_set.clear()
    engine_edge_cells.clear()
    core_cells.clear()
    for c in hull_cells:
        hull_cell_set[c] = true

    var core_hex_size = int(core_data.get("hex_size", 1))
    var core_shape = core_data.get("hex_shape", HexUtil.default_shape(core_hex_size))
    for s in core_shape:
        var cc = Vector2i(int(s[0]), int(s[1]))
        if hull_cell_set.has(cc):
            core_cells[cc] = true

func _update_layout():
    var vp = size

    if hull_cells.is_empty():
        grid_origin = vp * 0.5
        palette_rect = Rect2(30, 80, 300, vp.y - 200)
        stats_rect = Rect2(vp.x - 330, 80, 300, vp.y - 140)
        return

    var min_px = Vector2(INF, INF)
    var max_px = Vector2( - INF, - INF)
    for cell in hull_cells:
        var px = HexUtil.hex_to_pixel(cell, 1.0)
        min_px = min_px.min(px - Vector2(1.0, 1.0))
        max_px = max_px.max(px + Vector2(1.0, 1.0))
    var hull_w = max_px.x - min_px.x
    var hull_h = max_px.y - min_px.y
    var available_w = vp.x - 700
    var available_h = vp.y - 140
    var fit_w = available_w / maxf(hull_w, 1.0)
    var fit_h = available_h / maxf(hull_h, 1.0)
    _base_hex_size = clampf(minf(fit_w, fit_h), 10.0, 32.0)
    HEX_SIZE = _base_hex_size * builder_zoom

    var center_offset = (min_px + max_px) * 0.5 * HEX_SIZE
    grid_origin = Vector2(vp.x * 0.5, vp.y * 0.5 + 10) - center_offset
    palette_rect = Rect2(30, 80, 300, vp.y - 200)
    stats_rect = Rect2(vp.x - 330, 80, 300, vp.y - 140)

func refresh_layout() -> void:
    var vp := get_viewport_rect().size
    if vp == Vector2.ZERO:
        vp = Vector2(1920, 1080)
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _update_layout()
    queue_redraw()

func _load_state():
    if colony_mode:
        _load_colony_state()
        return
    placed_modules = GameManager.ship_modules.duplicate(true)
    module_inventory = GameManager.module_inventory.duplicate(true)

func _save_state():
    if colony_mode:
        _save_colony_state()
        return
    GameManager.ship_modules = placed_modules.duplicate(true)
    GameManager.module_inventory = module_inventory.duplicate(true)
    GameManager.room_detection_dirty = true

func _load_colony_hull():

    var colony = GameManager.get_colony(colony_id)
    deck_count = int(colony.get("deck_count", 3))
    current_deck = mini(current_deck, deck_count - 1)

    var radius: int = 8
    hull_cells = HexUtil.generate_hex_disc(radius)
    hull_cell_set.clear()
    engine_edge_cells.clear()
    core_cells.clear()
    for c in hull_cells:
        hull_cell_set[c] = true


func _load_colony_state():
    placed_modules = GameManager.get_colony_modules(colony_id).duplicate(true)
    module_inventory = GameManager.module_inventory.duplicate(true)

func _save_colony_state():
    GameManager.set_colony_modules(colony_id, placed_modules.duplicate(true))
    GameManager.module_inventory = module_inventory.duplicate(true)

func open_builder(_station = null):
    fleet_mode = false
    colony_mode = false
    colony_id = ""
    builder_zoom = 1.0
    _load_hull_from_core()
    refresh_layout()
    _load_state()
    _migrate_module_positions()
    visible = true
    grab_focus()
    _skip_close_frame = true
    _init_gamepad_cursor()

func open_colony_builder(col_id: String):

    fleet_mode = false
    colony_mode = true
    colony_id = col_id
    GameManager.active_colony_id = col_id
    _load_colony_hull()
    refresh_layout()
    _load_colony_state()
    visible = true
    grab_focus()
    _skip_close_frame = true
    _init_gamepad_cursor()

func _migrate_module_positions():


    if placed_modules.is_empty() or hull_cell_set.is_empty():
        return

    var inside_count: int = 0
    for pm in placed_modules:
        var gp = pm.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        if hull_cell_set.has(gp):
            inside_count += 1

    @warning_ignore("integer_division")
    if inside_count > placed_modules.size() / 2:
        return

    var mod_sum = Vector2i.ZERO
    for pm in placed_modules:
        var gp = pm.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        mod_sum += gp
    var mod_center_q = roundi(float(mod_sum.x) / placed_modules.size())
    var mod_center_r = roundi(float(mod_sum.y) / placed_modules.size())

    var offset = Vector2i( - mod_center_q, - mod_center_r)
    if offset == Vector2i.ZERO:
        return
    print("[ShipBuilder] Migrating %d module positions by offset (%d, %d)" % [placed_modules.size(), offset.x, offset.y])
    for pm in placed_modules:
        var gp = pm.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        pm["grid_pos"] = gp + offset

    _save_state()

func open_fleet_builder(core_id: String):


    fleet_mode = true
    fleet_core_id = core_id
    _saved_player_core = GameManager.equipped_core

    GameManager.equipped_core = core_id
    _load_hull_from_core()
    _update_layout()

    module_inventory = GameManager.module_inventory.duplicate(true)
    placed_modules = []
    powered_indices.clear()
    placement_rotation = 0
    current_deck = 0

    visible = true
    _skip_close_frame = true
    _init_gamepad_cursor()

func open_creative_builder(core_id: String = "core_cruiser"):

    creative_mode = true
    fleet_mode = false
    _saved_player_core = GameManager.equipped_core
    GameManager.equipped_core = core_id
    _load_hull_from_core()
    refresh_layout()
    placed_modules = []
    module_inventory = {}
    powered_indices.clear()
    placement_rotation = 0
    current_deck = 0

    visible = true
    _skip_close_frame = true
    _init_gamepad_cursor()

func _init_gamepad_cursor():

    gamepad_cursor_pos = size * 0.5
    gamepad_cursor_initialized = true
    gamepad_palette_mode = false
    gamepad_palette_idx = -1

func _process_gamepad_cursor(delta: float):

    if not gamepad_cursor_initialized:
        _init_gamepad_cursor()

    var stick = GameManager.poll_left_stick()
    if stick.length() > GameManager.STICK_DEADZONE:
        var magnitude = (stick.length() - GameManager.STICK_DEADZONE) / (1.0 - GameManager.STICK_DEADZONE)
        var dir = stick.normalized() * clampf(magnitude, 0, 1)
        gamepad_cursor_pos += dir * _gamepad_cursor_speed * delta

        gamepad_cursor_pos.x = clampf(gamepad_cursor_pos.x, 0, size.x)
        gamepad_cursor_pos.y = clampf(gamepad_cursor_pos.y, 0, size.y)

    var ry = GameManager.poll_right_stick().y
    if absf(ry) > GameManager.STICK_DEADZONE:
        if palette_rect.has_point(gamepad_cursor_pos):
            palette_scroll = maxf(palette_scroll + ry * 300.0 * delta, 0)


func _process(delta: float):
    if not visible:
        return
    if _skip_close_frame:
        _skip_close_frame = false
    elif not search_active and not creative_mode and Input.is_action_just_pressed("toggle_ship_builder"):
        close_builder()
        return

    if template_naming or search_active:
        if _template_save_flash > 0:
            _template_save_flash -= delta
        _update_hover()
        _sync_damage_states()
        compute_power_routing()
        queue_redraw()
        return

    if Input.is_key_pressed(KEY_Q):
        if not _rotate_pressed:
            _rotate_pressed = true
            placement_rotation = (placement_rotation + 5) % 6
    elif Input.is_key_pressed(KEY_E):
        if not _rotate_pressed:
            _rotate_pressed = true
            placement_rotation = (placement_rotation + 1) % 6
    else:
        _rotate_pressed = false

    if Input.is_key_pressed(KEY_T):
        if not _t_pressed:
            _t_pressed = true
            if not placed_modules.is_empty():
                template_naming = true
                template_name_input = ""
                grab_focus()
    else:
        _t_pressed = false

    if creative_mode and not template_naming:
        if Input.is_key_pressed(KEY_L):
            if not _l_pressed:
                _l_pressed = true
                _creative_show_templates = not _creative_show_templates
                if _creative_show_templates:
                    _refresh_creative_templates()
                    _creative_template_scroll = 0.0
                    _creative_template_hovered = -1
        else:
            _l_pressed = false
        if Input.is_key_pressed(KEY_F):
            if not _f_pressed:
                _f_pressed = true
                _creative_test_fly()
        else:
            _f_pressed = false
    if _template_save_flash > 0:
        _template_save_flash -= delta

    if GameManager.using_controller:
        _process_gamepad_cursor(delta)
    _update_hover()
    _sync_damage_states()
    compute_power_routing()
    queue_redraw()

func _sync_damage_states():

    if fleet_mode or creative_mode:
        return
    for pm in placed_modules:
        for gm_mod in GameManager.ship_modules:
            if gm_mod.get("grid_pos") == pm.get("grid_pos") and gm_mod.get("id") == pm.get("id") and GameManager.get_mod_deck(gm_mod) == GameManager.get_mod_deck(pm):
                pm["hp"] = gm_mod.get("hp", gm_mod.get("max_hp", 1.0))
                pm["max_hp"] = gm_mod.get("max_hp", 1.0)
                break

func _get_cursor_position() -> Vector2:

    if GameManager.using_controller and gamepad_cursor_initialized:
        return gamepad_cursor_pos
    return get_local_mouse_position()

func _update_hover():
    var mouse = _get_cursor_position()
    var local = mouse - grid_origin
    var cell = HexUtil.pixel_to_hex(local, HEX_SIZE)
    hovered_cell = cell if hull_cell_set.has(cell) else Vector2i(-9999, -9999)
    hovered_palette_idx = -1
    if palette_rect.has_point(mouse):
        var pal_y = mouse.y - palette_rect.position.y - 78 + palette_scroll
        var rows = _build_palette_rows()
        var y_acc: float = 0.0
        for i in rows.size():
            var row = rows[i]
            var h = HEADER_HEIGHT if row.row_type == "header" else ITEM_HEIGHT
            if pal_y >= y_acc and pal_y < y_acc + h:
                hovered_palette_idx = i
                break
            y_acc += h

func _gui_input(event: InputEvent):
    if not visible or _ai_design_open:
        return

    if sub_hex_mode and not search_active:
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
            sub_hex_mode = false
            accept_event()
            return
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
            sub_hex_mode = false
            accept_event()
            return

    if template_naming and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
        template_naming = false
        accept_event()
        return

    if template_naming and event is InputEventKey and event.pressed:
        if event.keycode == KEY_ENTER:
            if template_name_input.length() > 0:
                _save_npc_template()
            template_naming = false
        elif event.keycode == KEY_BACKSPACE:
            if template_name_input.length() > 0:
                template_name_input = template_name_input.substr(0, template_name_input.length() - 1)
        elif event.unicode > 0:
            var ch = char(event.unicode)

            if ch.is_valid_identifier() or ch == "-" or ch == " " or ch == "_" or ch.is_valid_int():
                template_name_input += ch
        accept_event()
        return

    if search_active and event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            search_active = false
            search_text = ""
        elif event.keycode == KEY_ENTER:
            search_active = false
        elif event.keycode == KEY_BACKSPACE:
            if search_text.length() > 0:
                search_text = search_text.substr(0, search_text.length() - 1)
        elif event.unicode > 0 and event.unicode < 128:
            search_text += char(event.unicode)
        palette_scroll = 0.0
        queue_redraw()
        accept_event()
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE or event.keycode == KEY_B:
            close_builder()
            accept_event()
            return
    if event is InputEventMouseMotion and color_picker_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        var mouse = get_local_mouse_position()
        if _cp_sv_rect.has_point(mouse):
            var s_val = clampf((mouse.x - _cp_sv_rect.position.x) / _cp_sv_rect.size.x, 0, 1)
            var v_val = 1.0 - clampf((mouse.y - _cp_sv_rect.position.y) / _cp_sv_rect.size.y, 0, 1)
            var col = Color.from_hsv(color_picker_hue, s_val, v_val)
            match editing_color_slot:
                0: GameManager.ship_color_primary = col
                1: GameManager.ship_color_secondary = col
            GameManager.invalidate_module_sprites()
            accept_event()
            return
        if _cp_hue_rect.has_point(mouse):
            color_picker_hue = clampf((mouse.y - _cp_hue_rect.position.y) / _cp_hue_rect.size.y, 0, 1)
            accept_event()
            return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _on_left_click()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _on_right_click()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            if creative_mode and _creative_show_templates:
                _creative_template_scroll = maxf(_creative_template_scroll - 1, 0)
                accept_event()
            elif palette_rect.has_point(get_local_mouse_position()):
                palette_scroll = maxf(palette_scroll - 40, 0)
                accept_event()
            else:
                builder_zoom = clampf(builder_zoom + BUILDER_ZOOM_STEP, BUILDER_ZOOM_MIN, BUILDER_ZOOM_MAX)
                _update_layout()
                accept_event()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if creative_mode and _creative_show_templates:
                _creative_template_scroll = minf(_creative_template_scroll + 1, maxf(0, _creative_templates.size() - 5))
                accept_event()
            elif palette_rect.has_point(get_local_mouse_position()):
                palette_scroll += 40
                accept_event()
            else:
                builder_zoom = clampf(builder_zoom - BUILDER_ZOOM_STEP, BUILDER_ZOOM_MIN, BUILDER_ZOOM_MAX)
                _update_layout()
                accept_event()
    elif event is InputEventJoypadButton and event.pressed:
        _handle_gamepad_button(event.button_index)



func _handle_gamepad_button(button: int):

    match button:
        JOY_BUTTON_A:

            _on_left_click()
            accept_event()
        JOY_BUTTON_B:

            if sub_hex_mode and not search_active:
                sub_hex_mode = false
                accept_event()
                return
            if template_naming:
                template_naming = false
                accept_event()
                return
            if search_active:
                search_active = false
                search_text = ""
                accept_event()
                return
            if selected_module_id != "":
                selected_module_id = ""
                accept_event()
                return
            if hovered_cell != Vector2i(-9999, -9999):
                _on_right_click()
                accept_event()
                return

            close_builder()
            accept_event()
        JOY_BUTTON_X:

            placement_rotation = (placement_rotation + 1) % 6
            accept_event()
        JOY_BUTTON_Y:

            _gamepad_cycle_palette_selection()
            accept_event()
        JOY_BUTTON_LEFT_SHOULDER:

            if deck_count > 1:
                current_deck = (current_deck - 1) % deck_count
                if current_deck < 0:
                    current_deck = deck_count - 1
            accept_event()
        JOY_BUTTON_RIGHT_SHOULDER:

            if deck_count > 1:
                current_deck = (current_deck + 1) % deck_count
            accept_event()
        JOY_BUTTON_DPAD_UP:

            if gamepad_palette_mode:
                _gamepad_palette_navigate(-1)
            else:
                palette_scroll = maxf(palette_scroll - 40, 0)
            accept_event()
        JOY_BUTTON_DPAD_DOWN:

            if gamepad_palette_mode:
                _gamepad_palette_navigate(1)
            else:
                palette_scroll += 40
            accept_event()
        JOY_BUTTON_DPAD_LEFT:

            gamepad_palette_mode = true
            if gamepad_palette_idx < 0:
                gamepad_palette_idx = 0
            accept_event()
        JOY_BUTTON_DPAD_RIGHT:

            gamepad_palette_mode = false
            accept_event()
        JOY_BUTTON_START:

            close_builder()
            accept_event()
        JOY_BUTTON_BACK:
            accept_event()

func _gamepad_cycle_palette_selection():

    var rows = _build_palette_rows()
    if rows.is_empty():
        return

    var current_idx: int = -1
    for i in rows.size():
        if rows[i].get("row_type") == "item" and rows[i].get("id", "") == selected_module_id:
            current_idx = i
            break

    var start = current_idx + 1 if current_idx >= 0 else 0
    for offset in rows.size():
        var idx = (start + offset) % rows.size()
        if rows[idx].get("row_type") == "item":
            selected_module_id = rows[idx].id
            placement_rotation = 0
            return

    selected_module_id = ""

func _gamepad_palette_navigate(direction: int):

    var rows = _build_palette_rows()
    if rows.is_empty():
        return
    gamepad_palette_idx = clampi(gamepad_palette_idx + direction, 0, rows.size() - 1)

    var attempts = 0
    while attempts < rows.size() and rows[gamepad_palette_idx].get("row_type") == "header":
        gamepad_palette_idx = clampi(gamepad_palette_idx + direction, 0, rows.size() - 1)
        attempts += 1
    var row = rows[gamepad_palette_idx]
    if row.get("row_type") == "item":
        hovered_palette_idx = gamepad_palette_idx
        selected_module_id = row.id
        placement_rotation = 0
    elif row.get("row_type") == "header":
        hovered_palette_idx = gamepad_palette_idx

        var lbl = row.label
        if collapsed_categories.get(lbl, false):
            collapsed_categories.erase(lbl)
        else:
            collapsed_categories[lbl] = true

func _on_left_click():
    var mouse = _get_cursor_position()

    if sub_hex_mode:

        if search_bar_rect.has_point(mouse):
            search_active = true
            grab_focus()
            return
        if search_active and not search_bar_rect.has_point(mouse):
            search_active = false

        if hovered_palette_idx >= 0:
            var rows = _build_palette_rows()
            if hovered_palette_idx < rows.size():
                var row = rows[hovered_palette_idx]
                if row.row_type == "header":
                    var lbl = row.label
                    if collapsed_categories.get(lbl, false):
                        collapsed_categories.erase(lbl)
                    else:
                        collapsed_categories[lbl] = true
                elif row.row_type == "item":
                    selected_module_id = row.id
                    placement_rotation = 0
            return

        _sub_hex_click(mouse)
        return

    if not template_naming:
        if _btn_save_template.size.x > 0 and _btn_save_template.has_point(mouse):
            if not placed_modules.is_empty():
                template_naming = true
                template_name_input = ""
                grab_focus()
            return
        if _btn_test_fly.size.x > 0 and _btn_test_fly.has_point(mouse):
            _creative_test_fly()
            return
        if _btn_load_template.size.x > 0 and _btn_load_template.has_point(mouse):
            _creative_show_templates = not _creative_show_templates
            _test_ships_open = false
            _fight_ai_open = false
            if _creative_show_templates:
                _refresh_creative_templates()
                _creative_template_scroll = 0.0
                _creative_template_hovered = -1
            return
        if _btn_test_ships.size.x > 0 and _btn_test_ships.has_point(mouse):
            _test_ships_open = not _test_ships_open
            _creative_show_templates = false
            _test_ships_scroll = 0.0
            _test_ships_rects.clear()
            return
        if _btn_ai_design.size.x > 0 and _btn_ai_design.has_point(mouse):
            _open_ai_design()
            return

    if creative_mode and _test_ships_open:
        for entry in _test_ships_rects:
            if entry.rect.has_point(mouse):
                _load_test_ship(entry.name)
                return
        if not _btn_test_ships.has_point(mouse):
            _test_ships_open = false
        return

    if creative_mode and _creative_show_templates:
        for entry in _creative_template_rects:
            var row_rect: Rect2 = entry.rect
            var idx: int = entry.idx

            var _load_r = Rect2(row_rect.position.x + row_rect.size.x - 90, row_rect.position.y - (row_rect.size.y * 0.5 - 6), 42, 20)

            if row_rect.has_point(mouse):

                if entry.has("style_rect") and entry.style_rect.has_point(mouse):
                    _cycle_template_combat_style(idx)
                    return

                if mouse.x > row_rect.position.x + row_rect.size.x - 42:
                    _delete_creative_template(idx)
                    return

                _load_creative_template(idx)
                return

        var panel_w: float = 350.0
        var panel_h: float = 500.0
        var px = (size.x - panel_w) * 0.5
        var py = (size.y - panel_h) * 0.5
        if not Rect2(px, py, panel_w, panel_h).has_point(mouse):
            _creative_show_templates = false
        return

    for i in deck_tab_rects.size():
        if deck_tab_rects[i].has_point(mouse):
            current_deck = i
            return

    if creative_mode:
        for i in core_btn_rects.size():
            if i < core_ids.size() and core_btn_rects[i].has_point(mouse):
                var cid = core_ids[i]
                if cid != GameManager.equipped_core:
                    placed_modules.clear()
                    powered_indices.clear()
                    GameManager.equipped_core = cid
                    current_deck = 0
                    _load_hull_from_core()
                    _update_layout()
                return

    if color_picker_open:
        # SV square click
        if _cp_sv_rect.has_point(mouse):
            var s_val = clampf((mouse.x - _cp_sv_rect.position.x) / _cp_sv_rect.size.x, 0, 1)
            var v_val = 1.0 - clampf((mouse.y - _cp_sv_rect.position.y) / _cp_sv_rect.size.y, 0, 1)
            var col = Color.from_hsv(color_picker_hue, s_val, v_val)
            match editing_color_slot:
                0: GameManager.ship_color_primary = col
                1: GameManager.ship_color_secondary = col
            GameManager.invalidate_module_sprites()
            return
        # Hue bar click
        if _cp_hue_rect.has_point(mouse):
            color_picker_hue = clampf((mouse.y - _cp_hue_rect.position.y) / _cp_hue_rect.size.y, 0, 1)
            return
        # Preset swatches
        for i in color_picker_rects.size():
            if i < color_presets.size() and color_picker_rects[i].has_point(mouse):
                match editing_color_slot:
                    0: GameManager.ship_color_primary = color_presets[i]
                    1: GameManager.ship_color_secondary = color_presets[i]
                GameManager.invalidate_module_sprites()
                color_picker_open = false
                return
        # Click inside panel but not on controls — ignore
        if _cp_panel_rect.has_point(mouse):
            return
        # Click outside panel — close
        color_picker_open = false

    for si in color_slot_rects.size():
        if color_slot_rects[si].has_point(mouse):
            editing_color_slot = si
            var current = GameManager.ship_color_primary if si == 0 else GameManager.ship_color_secondary
            color_picker_hue = current.h
            color_picker_open = true
            return

    if search_bar_rect.has_point(mouse):
        search_active = true
        grab_focus()
        return

    if search_active and not search_bar_rect.has_point(mouse):
        search_active = false

    if hovered_palette_idx >= 0:
        var rows = _build_palette_rows()
        if hovered_palette_idx < rows.size():
            var row = rows[hovered_palette_idx]
            if row.row_type == "header":

                var lbl = row.label
                if collapsed_categories.get(lbl, false):
                    collapsed_categories.erase(lbl)
                else:
                    collapsed_categories[lbl] = true
            elif row.row_type == "item":
                var clicked_id = row.id
                var _mod = DataManager.modules.get(clicked_id, {})
                if creative_mode:

                    selected_module_id = clicked_id
                    placement_rotation = 0
                else:

                    if GameManager.debug_mode and GameManager.can_craft(clicked_id):
                        GameManager.craft_module(clicked_id)
                        module_inventory = GameManager.module_inventory

                    elif module_inventory.get(clicked_id, 0) <= 0 and GameManager.CRAFTING_RECIPES.has(clicked_id):
                        if GameManager.craft_module(clicked_id):
                            module_inventory = GameManager.module_inventory
                        else:
                            return
                    selected_module_id = clicked_id
                    placement_rotation = 0
        return

    if hovered_cell != Vector2i(-9999, -9999):
        var now = Time.get_ticks_msec() * 0.001
        if hovered_cell == _last_click_cell and (now - _last_click_time) < 0.4:

            _enter_sub_hex_mode(hovered_cell)
            _last_click_cell = Vector2i(-9999, -9999)
            return
        _last_click_cell = hovered_cell
        _last_click_time = now
        if selected_module_id != "":
            _place_module()

func _on_right_click():
    if hovered_cell != Vector2i(-9999, -9999):
        _remove_module_at(hovered_cell)
    else:
        selected_module_id = ""

func _switch_core(core_id: String):
    if core_id == GameManager.equipped_core:
        return
    if creative_mode:

        placed_modules.clear()
        powered_indices.clear()
        GameManager.equipped_core = core_id
        current_deck = 0
        _load_hull_from_core()
        _update_layout()
        return

    if module_inventory.get(core_id, 0) <= 0:
        if GameManager.CRAFTING_RECIPES.has(core_id) and GameManager.can_craft(core_id):
            GameManager.craft_module(core_id)
            module_inventory = GameManager.module_inventory
        else:
            return

    module_inventory[core_id] = module_inventory.get(core_id, 0) - 1
    if module_inventory[core_id] <= 0:
        module_inventory.erase(core_id)

    var old_core = GameManager.equipped_core
    if not module_inventory.has(old_core):
        module_inventory[old_core] = 0
    module_inventory[old_core] += 1

    for pm in placed_modules:
        if not module_inventory.has(pm.id):
            module_inventory[pm.id] = 0
        module_inventory[pm.id] += 1
    placed_modules.clear()
    powered_indices.clear()
    GameManager.equipped_core = core_id
    current_deck = 0
    _load_hull_from_core()
    _update_layout()

func _place_module():
    var mod_data = DataManager.modules.get(selected_module_id, {})
    var mod_type = mod_data.get("type", "")
    var hex_size: int = mod_data.get("hex_size", 1)
    var hex_shape: Array = mod_data.get("hex_shape", HexUtil.default_shape(hex_size))
    var rot: int = placement_rotation % 6
    var shape = hex_shape
    if rot > 0:
        shape = hex_shape.duplicate(true)
        for _i in rot:
            shape = HexUtil.rotate_shape_cw(shape)

    var needed_cells: Array = []
    for offset in shape:
        var c = Vector2i(hovered_cell.x + offset[0], hovered_cell.y + offset[1])
        if not hull_cell_set.has(c):
            return
        if core_cells.has(c):
            return
        needed_cells.append(c)


    if not creative_mode:
        if not module_inventory.has(selected_module_id) or module_inventory[selected_module_id] <= 0:
            return


    var engine_blocked: Dictionary = _get_engine_exhaust_blocked(current_deck)
    for c in needed_cells:
        if engine_blocked.has(c):
            return

    if mod_type == "engine" and mod_data.get("subtype", "") != "engine_block":
        var behind: Dictionary = {}
        for c in needed_cells:
            _flood_south(c, behind)
        for pm in placed_modules:
            if GameManager.get_mod_deck(pm) != current_deck:
                continue
            var pm_cells = GameManager.get_mod_hex_cells(pm)
            for bc in behind:
                if bc in pm_cells:
                    return


    for pm in placed_modules:
        if GameManager.get_mod_deck(pm) != current_deck:
            continue
        if pm.get("id", "") == "deck_plate":
            continue
        var pm_cells = GameManager.get_mod_hex_cells(pm)
        for c in needed_cells:
            if c in pm_cells:
                return


    var entry = {
        "id": selected_module_id, 
        "grid_pos": hovered_cell, 
        "deck": current_deck, 
        "data": mod_data, 
    }
    if rot > 0:
        entry["rotation"] = rot
    placed_modules.append(entry)
    if not creative_mode:
        module_inventory[selected_module_id] -= 1
        if module_inventory[selected_module_id] <= 0:
            module_inventory.erase(selected_module_id)
            selected_module_id = ""

    if colony_mode:
        _save_colony_state()



func _flood_south(from_cell: Vector2i, blocked: Dictionary):
    var s = from_cell + Vector2i(0, 1)
    if hull_cell_set.has(s) and not blocked.has(s):
        blocked[s] = true
        _flood_south(s, blocked)


func _get_engine_exhaust_blocked(deck: int) -> Dictionary:
    var blocked: Dictionary = {}
    for pm in placed_modules:
        if GameManager.get_mod_deck(pm) != deck:
            continue
        var pm_data = pm.get("data", {})
        if pm_data.get("type", "") != "engine" or pm_data.get("subtype", "") == "engine_block":
            continue
        for ec in GameManager.get_mod_hex_cells(pm):
            _flood_south(ec, blocked)
    return blocked

func _remove_module_at(cell: Vector2i):

    for i in range(placed_modules.size() - 1, -1, -1):
        if GameManager.get_mod_deck(placed_modules[i]) != current_deck:
            continue
        var pm_cells = GameManager.get_mod_hex_cells(placed_modules[i])
        if cell in pm_cells:
            var mod = placed_modules[i]

            if mod.get("id", "") == "deck_plate":
                return
            placed_modules.remove_at(i)
            if not creative_mode:
                if not module_inventory.has(mod.id):
                    module_inventory[mod.id] = 0
                module_inventory[mod.id] += 1
            return

const HULL_RANKS: Array = ["pod", "scout", "corvette", "frigate", "cruiser"]

func _get_current_hull_rank() -> int:

    var core_name: String = GameManager.equipped_core
    for i in HULL_RANKS.size():
        if HULL_RANKS[i] in core_name:
            return i
    return 0

func _get_available_ids() -> Array:
    if creative_mode:
        @warning_ignore("confusable_local_declaration")
        var ids: Array = []
        for id in DataManager.modules:
            if DataManager.modules[id].get("type", "") != "core":
                ids.append(id)
        return ids
    var ids: Array = []
    var hull_rank = _get_current_hull_rank()
    for id in module_inventory:
        if module_inventory[id] > 0:
            var mod = DataManager.modules.get(id, {})
            if mod.get("type", "") == "core":
                continue
            ids.append(id)
    for id in GameManager.CRAFTING_RECIPES:
        if id in ids:
            continue
        var mod = DataManager.modules.get(id, {})
        if mod.is_empty() or mod.get("type", "") == "core":
            continue

        if not colony_mode:
            var min_hull: String = mod.get("min_hull", "")
            if min_hull != "":
                var required_rank = HULL_RANKS.find(min_hull)
                if required_rank >= 0 and hull_rank < required_rank:
                    continue
        ids.append(id)
    return ids




func _build_palette_rows() -> Array:
    var all_ids = _get_available_ids()
    var rows: Array = []
    var searching = search_text != ""
    if searching:

        var search_lower = search_text.to_lower()
        for id in all_ids:
            var mod = DataManager.modules.get(id, {})
            var mod_name: String = mod.get("name", id)
            if search_lower in mod_name.to_lower():
                rows.append({"row_type": "item", "id": id})
        return rows
    for cat_idx in PALETTE_CATEGORIES.size():
        var cat = PALETTE_CATEGORIES[cat_idx]
        var cat_types: Array = cat["types"]

        var filter_cat: String = cat.get("filter_cat", "")
        var cat_ids: Array = []
        for id in all_ids:
            var mod = DataManager.modules.get(id, {})
            if mod.get("type", "") in cat_types:
                if filter_cat != "" and mod.get("category", "") != filter_cat:
                    continue
                cat_ids.append(id)
        if cat_ids.is_empty():
            continue
        rows.append({"row_type": "header", "label": cat["label"], "color": cat["color"], "cat_idx": cat_idx, "count": cat_ids.size()})
        if not collapsed_categories.get(cat["label"], false):
            for id in cat_ids:
                rows.append({"row_type": "item", "id": id})
    return rows

const HEADER_HEIGHT: float = 30.0
const ITEM_HEIGHT: float = 52.0

func _save_npc_template():

    if placed_modules.is_empty():
        return

    var dir = DirAccess.open("user://")
    if dir and not dir.dir_exists("npc_templates"):
        dir.make_dir("npc_templates")

    var modules: Array = []
    for mod in placed_modules:
        var gp = mod.get("grid_pos", Vector2i(0, 0))
        var entry = {
            "id": mod.get("id", ""), 
            "grid_pos": [gp.x, gp.y] if gp is Vector2i else gp, 
            "deck": mod.get("deck", 0), 
        }
        if mod.has("rotation") and mod.get("rotation", 0) != 0:
            entry["rotation"] = mod["rotation"]
        modules.append(entry)

    var safe_name = template_name_input.strip_edges().replace(" ", "_").to_lower()
    if safe_name.is_empty():
        safe_name = "unnamed"
    var template = {
        "export_version": 1, 
        "name": template_name_input.strip_edges(), 
        "core_id": GameManager.equipped_core, 
        "module_count": modules.size(), 
        "modules": modules, 
        "combat_style": _template_combat_style, 
        "colors": {
            "primary": [GameManager.ship_color_primary.r, GameManager.ship_color_primary.g, GameManager.ship_color_primary.b],
            "secondary": [GameManager.ship_color_secondary.r, GameManager.ship_color_secondary.g, GameManager.ship_color_secondary.b],
        },
    }
    var json_text = JSON.stringify(template, "\t")
    var path = "user://npc_templates/%s.json" % safe_name
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(json_text)
        file.close()
        print("[ShipBuilder] Saved NPC template: ", path)

    if OS.has_feature("editor"):
        var res_dir = DirAccess.open("res://Space/data/")
        if res_dir and not res_dir.dir_exists("npc_templates"):
            res_dir.make_dir("npc_templates")
        var res_path = "res://Space/data/npc_templates/%s.json" % safe_name
        var res_file = FileAccess.open(res_path, FileAccess.WRITE)
        if res_file:
            res_file.store_string(json_text)
            res_file.close()
            print("[ShipBuilder] Bundled NPC template: ", res_path)
    _template_save_name = template_name_input.strip_edges()
    _template_save_flash = 3.0
    GameManager.reload_npc_templates()
    if _recording_after_save:
        _recording_after_save = false
        _creative_record_ai()

func _refresh_creative_templates():

    _creative_templates.clear()
    var dir = DirAccess.open("user://npc_templates/")
    if not dir:
        return
    dir.list_dir_begin()
    var fname = dir.get_next()
    while fname != "":
        if fname.ends_with(".json"):
            var file = FileAccess.open("user://npc_templates/%s" % fname, FileAccess.READ)
            if file:
                var json = JSON.new()
                if json.parse(file.get_as_text()) == OK:
                    var data = json.data
                    if data is Dictionary and data.has("modules"):
                        _creative_templates.append({
                            "name": data.get("name", fname.get_basename()), 
                            "filename": fname, 
                            "data": data, 
                        })
                file.close()
        fname = dir.get_next()
    _creative_templates.sort_custom( func(a, b): return a.name.to_lower() < b.name.to_lower())

func _load_creative_template(idx: int):

    if idx < 0 or idx >= _creative_templates.size():
        return
    _apply_creative_template(_creative_templates[idx].data, _creative_templates[idx].name)

func open_creative_template(template_data: Dictionary, display_name: String = "") -> void:
    var core_id := str(template_data.get("core_id", "")).strip_edges()
    if core_id.is_empty():
        core_id = "core_cruiser"
    open_creative_builder(core_id)
    _apply_creative_template(template_data, display_name)

func _apply_creative_template(tmpl: Dictionary, display_name: String = "") -> void:
    var core_id = tmpl.get("core_id", "")
    if core_id != "" and core_id != GameManager.equipped_core and DataManager.modules.has(core_id):
        GameManager.equipped_core = core_id
        _load_hull_from_core()
        _update_layout()

    placed_modules.clear()
    var tmpl_modules: Array = tmpl.get("modules", [])
    for entry in tmpl_modules:
        var gp = entry.get("grid_pos", [0, 0])
        var mod_id: String = entry.get("id", "")
        if mod_id == "" or not DataManager.modules.has(mod_id):
            var mtype = entry.get("type", "")
            if mtype != "":
                for key in DataManager.modules:
                    if DataManager.modules[key].get("type", "") == mtype:
                        mod_id = key
                        break
            if mod_id == "" or not DataManager.modules.has(mod_id):
                continue
        var mod_data = DataManager.modules[mod_id]
        var pm = {
            "id": mod_id,
            "grid_pos": Vector2i(int(gp[0]), int(gp[1])),
            "deck": entry.get("deck", 0),
            "data": mod_data,
        }
        if entry.get("rotation", 0) != 0:
            pm["rotation"] = entry["rotation"]
        placed_modules.append(pm)
    _template_combat_style = tmpl.get("combat_style", "standard")
    var colors = tmpl.get("colors", {})
    if colors.size() > 0:
        var pc = colors.get("primary", [GameManager.ship_color_primary.r, GameManager.ship_color_primary.g, GameManager.ship_color_primary.b])
        GameManager.ship_color_primary = Color(pc[0], pc[1], pc[2])
        var sc = colors.get("secondary", [GameManager.ship_color_secondary.r, GameManager.ship_color_secondary.g, GameManager.ship_color_secondary.b])
        GameManager.ship_color_secondary = Color(sc[0], sc[1], sc[2])
    powered_indices.clear()
    _creative_show_templates = false
    _template_save_flash = 3.0
    _template_save_name = display_name if not display_name.is_empty() else str(tmpl.get("name", "template"))
    print("[ShipBuilder] Loaded template '%s': %d modules (combat_style=%s)" % [_template_save_name, placed_modules.size(), _template_combat_style])
    for pm in placed_modules:
        var cells = GameManager.get_mod_hex_cells(pm)
        print("  - %s at %s rot=%d cells=%s" % [pm.get("id", "?"), pm.get("grid_pos", "?"), pm.get("rotation", 0), str(cells)])

func _delete_creative_template(idx: int):

    if idx < 0 or idx >= _creative_templates.size():
        return
    var fname = _creative_templates[idx].filename
    var path = "user://npc_templates/%s" % fname
    DirAccess.remove_absolute(path)
    _creative_templates.remove_at(idx)
    GameManager.reload_npc_templates()

func _cycle_template_combat_style(idx: int):

    if idx < 0 or idx >= _creative_templates.size():
        return
    var tmpl = _creative_templates[idx]
    var current = tmpl.data.get("combat_style", "standard")
    var ci = NPC_COMBAT_STYLES.find(current)
    var next_style = NPC_COMBAT_STYLES[(ci + 1) % NPC_COMBAT_STYLES.size()]
    tmpl.data["combat_style"] = next_style

    var path = "user://npc_templates/%s" % tmpl.filename
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(tmpl.data, "\t"))
        file.close()
    GameManager.reload_npc_templates()

func _load_test_ship(template_name: String):
    var tmpl = GameManager.get_template_by_name(template_name)
    if tmpl.is_empty():
        return
    var core_id = tmpl.get("core_id", "")
    if core_id != "" and core_id != GameManager.equipped_core and DataManager.modules.has(core_id):
        GameManager.equipped_core = core_id
        _load_hull_from_core()
        _update_layout()
    placed_modules.clear()
    for entry in tmpl.get("modules", []):
        var gp = entry.get("grid_pos", [0, 0])
        var mod_id: String = entry.get("id", "")
        if mod_id == "" or not DataManager.modules.has(mod_id):
            continue
        var pm = {
            "id": mod_id,
            "grid_pos": Vector2i(int(gp[0]), int(gp[1])),
            "deck": entry.get("deck", 0),
            "data": DataManager.modules[mod_id],
        }
        if entry.get("rotation", 0) != 0:
            pm["rotation"] = entry["rotation"]
        placed_modules.append(pm)
    powered_indices.clear()
    _test_ships_open = false
    _template_save_flash = 3.0
    _template_save_name = template_name

func _creative_test_fly():

    if placed_modules.is_empty():
        return
    test_fly_requested.emit(placed_modules.duplicate(true), GameManager.equipped_core)
    visible = false

func _creative_record_ai():
    if placed_modules.is_empty():
        return
    # Must have a saved template name to associate the recording with
    if _template_save_name == "":
        _recording_after_save = true
        template_naming = true
        template_name_input = ""
        grab_focus()
        return
    record_ai_requested.emit(placed_modules.duplicate(true), GameManager.equipped_core, _template_save_name)
    visible = false

func _start_fight_ai(template_name: String, recording_path: String):
    if placed_modules.is_empty():
        return
    _fight_ai_open = false
    fight_ai_requested.emit(placed_modules.duplicate(true), GameManager.equipped_core, template_name, recording_path)
    visible = false

func _open_ai_design():
    _creative_show_templates = false
    _test_ships_open = false
    _fight_ai_open = false
    _ai_design_open = true
    if _ai_design_panel:
        _ai_design_panel.show_panel()

func _on_ai_design_back():
    if _ai_design_panel:
        _ai_design_panel.visible = false
    _ai_design_open = false
    grab_focus()
    queue_redraw()

func _on_ai_design_train():
    if _ai_design_panel:
        _ai_design_panel.visible = false
    _ai_design_open = false
    _creative_record_ai()

func _on_ai_design_fight(template_name: String, recording_path: String):
    if _ai_design_panel:
        _ai_design_panel.visible = false
    _ai_design_open = false
    _start_fight_ai(template_name, recording_path)

func close_builder():
    search_text = ""
    search_active = false
    _test_ships_open = false
    _creative_show_templates = false
    _fight_ai_open = false
    _ai_design_open = false
    if _ai_design_panel:
        _ai_design_panel.visible = false
    if creative_mode:
        GameManager.equipped_core = _saved_player_core
        _load_hull_from_core()
        creative_mode = false
        closed.emit(placed_modules)
        visible = false
        return
    if colony_mode:
        _save_colony_state()
        colony_mode = false
        GameManager.active_colony_id = ""
        closed.emit(placed_modules)
        visible = false
        return
    if fleet_mode:

        GameManager.module_inventory = module_inventory.duplicate(true)
        GameManager.equipped_core = _saved_player_core
        _load_hull_from_core()
        closed.emit(placed_modules)
    else:
        _save_state()
        closed.emit(placed_modules)
    visible = false



func _get_module_cells(mod: Dictionary) -> Array:

    return GameManager.get_mod_hex_cells_3d(mod)

func _get_module_cells_2d(mod: Dictionary) -> Array:

    return GameManager.get_mod_hex_cells(mod)

func _are_adjacent(cells_a: Array, cells_b: Array) -> bool:

    for a in cells_a:
        for b in cells_b:
            if a.z != b.z:
                continue
            if HexUtil.are_neighbors(Vector2i(a.x, a.y), Vector2i(b.x, b.y)):
                return true
    return false

func compute_power_routing():


    powered_indices.clear()
    var total_output: float = 0.0
    var total_draw: float = 0.0
    for i in placed_modules.size():
        if placed_modules[i].get("hp", 1) <= 0:
            continue
        var stats: Dictionary = placed_modules[i].get("data", {}).get("stats", {})
        var type_str: String = placed_modules[i].get("data", {}).get("type", "")
        if type_str == "reactor":
            total_output += stats.get("power_output", 0)
        total_draw += stats.get("power_draw", 0)

    if total_draw <= total_output:

        for i in placed_modules.size():
            if placed_modules[i].get("hp", 1) > 0:
                powered_indices.append(i)
        return


    var alive: Array = []
    for i in placed_modules.size():
        if placed_modules[i].get("hp", 1) <= 0:
            continue
        var type_str: String = placed_modules[i].get("data", {}).get("type", "")
        var power_draw: float = placed_modules[i].get("data", {}).get("stats", {}).get("power_draw", 0)
        alive.append({idx = i, draw = power_draw, type = type_str})


    for entry in alive:
        if entry.type == "reactor":
            powered_indices.append(entry.idx)


    alive.sort_custom( func(a, b): return a.draw > b.draw)
    var remaining = total_output
    for entry in alive:
        if entry.type == "reactor":
            continue
        if entry.draw <= remaining:
            powered_indices.append(entry.idx)
            remaining -= entry.draw

func _ladder_connects(mod: Dictionary, powered_cells: Array, ladder_cells: Dictionary) -> bool:

    if mod.get("data", {}).get("type", "") != "ladder":
        return false
    var gp = mod.get("grid_pos", Vector2i(0, 0))
    var deck = GameManager.get_mod_deck(mod)
    var xy = Vector2i(gp.x, gp.y)
    if not ladder_cells.has(xy):
        return false
    for other_deck in ladder_cells[xy]:
        if absi(other_deck - deck) == 1:

            var other_cell = Vector3i(xy.x, xy.y, other_deck)
            if other_cell in powered_cells:
                return true
    return false




func calc_stats() -> Dictionary:
    var core_data = DataManager.modules.get(GameManager.equipped_core, {})
    var core_stats = core_data.get("stats", {})
    var hull: float = 100.0 + core_stats.get("hull_bonus", 0)
    var shields: float = 50.0
    var shield_rech: float = 5.0
    var speed: float = core_stats.get("base_max_speed", 400.0)
    var accel: float = core_stats.get("base_acceleration", 600.0)
    var weapon_count: int = 0
    var total_damage: float = 0.0
    var power_output: float = core_stats.get("power_output", 0)
    var power_draw: float = 0.0
    var unpowered_count: int = 0
    var cargo_cap: int = 0
    var crew_cap: int = 0
    var life_support_cap: int = 0
    var fuel_cap: float = 100.0
    var total_weight: float = 0.0
    var total_thrust: float = 0.0

    for i in placed_modules.size():
        var pm = placed_modules[i]
        var stats = pm.get("data", {}).get("stats", {})
        var type_str = pm.get("data", {}).get("type", "")
        total_weight += float(GameManager.get_mod_hex_size(pm))
        var is_powered = i in powered_indices
        power_output += stats.get("power_output", 0)
        power_draw += stats.get("power_draw", 0)
        if not is_powered:
            if stats.get("power_draw", 0) > 0:
                unpowered_count += 1
            continue
        match type_str:
            "weapon":
                weapon_count += 1
                total_damage += stats.get("damage", 0)
            "shield":
                shields += stats.get("shield_capacity", 0)
                shield_rech += stats.get("recharge_rate", 0)
            "engine":
                total_thrust += stats.get("thrust", 0)
                fuel_cap += 15.0
            "armor":
                hull += stats.get("hull_bonus", 0)
            "cargo":
                cargo_cap += stats.get("cargo_capacity", 0)
                fuel_cap += stats.get("cargo_capacity", 0) * 5.0
            "quarters":
                crew_cap += stats.get("crew_capacity", 0)
            "life_support":
                life_support_cap += stats.get("crew_supported", 0)

    var actual_crew_cap: int = maxi(mini(crew_cap, life_support_cap) if life_support_cap > 0 else crew_cap, 1)

    var raw_ratio = total_thrust / maxf(total_weight * 5.0, 1.0)
    var thrust_ratio = clampf(raw_ratio, 0.15, 1.0)
    speed *= thrust_ratio
    accel *= thrust_ratio
    return {
        "hull": hull, "shields": shields, "shield_recharge": shield_rech, 
        "speed": speed, "acceleration": accel, "weapon_count": weapon_count, 
        "damage": total_damage, "power_output": power_output, 
        "power_draw": power_draw, "unpowered_count": unpowered_count, 
        "cargo_capacity": cargo_cap, 
        "crew_capacity": actual_crew_cap, 
        "quarters_capacity": crew_cap, 
        "life_support_capacity": life_support_cap, 
        "fuel_capacity": fuel_cap, 
        "weight": total_weight, 
        "thrust": total_thrust, 
        "thrust_ratio": thrust_ratio, 
    }



func _draw():
    if not visible:
        return
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.02, 0.05, 0.97))
    if _ai_design_open:
        return
    var font = ThemeDB.fallback_font

    var title_x = size.x * 0.5
    var title_text = "CREATIVE BUILDER" if creative_mode else ("COLONY BUILDER" if colony_mode else ("FLEET BUILDER" if fleet_mode else "SHIP BUILDER"))
    var title_col = Color(0.3, 0.8, 0.55) if creative_mode else (Color(0.85, 0.65, 0.3) if colony_mode else (Color(0.7, 0.55, 0.9) if fleet_mode else Color(0.65, 0.75, 0.9)))
    var title_w = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
    draw_string(font, Vector2(title_x - title_w * 0.5, 30), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_col)
    var close_hint = "[B] Close to Menu" if creative_mode else "[B] Close & Apply"
    draw_string(font, Vector2(title_x - title_w * 0.5, 46), close_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))

    var hull_bounds = _get_hull_pixel_bounds()
    draw_string(font, Vector2(hull_bounds[0].x - 10, hull_bounds[1].y + 16), "ENGINES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.5, 0.2, 0.7))

    if deck_count > 1:
        _draw_deck_tabs(font)

    var mouse_pos = _get_cursor_position()
    var btn_h = 26.0
    var btn_y = hull_bounds[1].y + 34
    btn_y = minf(btn_y, size.y - 120)

    var save_w = 150.0
    var save_x = hull_bounds[0].x
    _btn_save_template = Rect2(save_x, btn_y, save_w, btn_h)
    var save_hov = _btn_save_template.has_point(mouse_pos)
    draw_rect(_btn_save_template, Color(0.08, 0.1, 0.06) if not save_hov else Color(0.14, 0.18, 0.1))
    draw_rect(_btn_save_template, Color(0.3, 0.45, 0.3) if not save_hov else Color(0.4, 0.65, 0.35), false, 1.0)
    draw_string(font, Vector2(save_x + 10, btn_y + 17), "Save NPC Template", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.65, 0.45) if not save_hov else Color(0.65, 0.95, 0.55))
    if creative_mode:

        var load_w = 130.0
        var load_x = hull_bounds[1].x - load_w
        _btn_load_template = Rect2(load_x, btn_y, load_w, btn_h)
        var load_hov = _btn_load_template.has_point(mouse_pos)
        draw_rect(_btn_load_template, Color(0.06, 0.08, 0.14) if not load_hov else Color(0.1, 0.14, 0.24))
        draw_rect(_btn_load_template, Color(0.25, 0.4, 0.65) if not load_hov else Color(0.35, 0.55, 0.95), false, 1.0)
        draw_string(font, Vector2(load_x + 10, btn_y + 17), "Load Template", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.55, 0.85) if not load_hov else Color(0.55, 0.75, 1.0))

        var fly_w = 80.0
        var fly_x = stats_rect.position.x + 10
        var fly_y = stats_rect.position.y - 34
        _btn_test_fly = Rect2(fly_x, fly_y, fly_w, btn_h)
        var fly_hov = _btn_test_fly.has_point(mouse_pos)
        draw_rect(_btn_test_fly, Color(0.06, 0.08, 0.14) if not fly_hov else Color(0.1, 0.14, 0.24))
        draw_rect(_btn_test_fly, Color(0.25, 0.4, 0.65) if not fly_hov else Color(0.35, 0.55, 0.95), false, 1.0)
        draw_string(font, Vector2(fly_x + 10, fly_y + 17), "Test Fly", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.55, 0.85) if not fly_hov else Color(0.55, 0.75, 1.0))

        var ts_w = 90.0
        var ts_x = fly_x + fly_w + 8
        var ts_y = fly_y
        _btn_test_ships = Rect2(ts_x, ts_y, ts_w, btn_h)
        var ts_hov = _btn_test_ships.has_point(mouse_pos)
        var ts_active = _test_ships_open
        draw_rect(_btn_test_ships, Color(0.14, 0.1, 0.06) if ts_active else (Color(0.06, 0.08, 0.14) if not ts_hov else Color(0.1, 0.14, 0.24)))
        draw_rect(_btn_test_ships, Color(0.65, 0.45, 0.25) if ts_active else (Color(0.25, 0.4, 0.65) if not ts_hov else Color(0.35, 0.55, 0.95)), false, 1.0)
        draw_string(font, Vector2(ts_x + 10, ts_y + 17), "Test Ships", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.65, 0.35) if ts_active else (Color(0.4, 0.55, 0.85) if not ts_hov else Color(0.55, 0.75, 1.0)))

        var aid_w = 85.0
        var aid_x = ts_x + ts_w + 8
        var aid_y = fly_y
        _btn_ai_design = Rect2(aid_x, aid_y, aid_w, btn_h)
        var aid_hov = _btn_ai_design.has_point(mouse_pos)
        draw_rect(_btn_ai_design, Color(0.06, 0.08, 0.14) if not aid_hov else Color(0.1, 0.14, 0.24))
        draw_rect(_btn_ai_design, Color(0.3, 0.55, 0.75) if not aid_hov else Color(0.45, 0.75, 1.0), false, 1.0)
        draw_string(font, Vector2(aid_x + 10, aid_y + 17), "AI Design", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.7, 0.95) if not aid_hov else Color(0.6, 0.85, 1.0))
        _btn_record_ai = Rect2()
        _btn_fight_ai = Rect2()
    else:
        _btn_test_fly = Rect2()
        _btn_load_template = Rect2()
        _btn_test_ships = Rect2()
        _btn_record_ai = Rect2()
        _btn_fight_ai = Rect2()
        _btn_ai_design = Rect2()

    _draw_palette(font)
    if sub_hex_mode:
        _draw_sub_hex_view(font)
    else:
        _draw_grid(font)
    _draw_stats_panel(font)
    _draw_module_info(font)
    if not fleet_mode or creative_mode:
        _draw_color_picker(font)
    _draw_tooltip(font)


    if template_naming:
        var prompt_x = size.x * 0.5 - 160
        var prompt_y = size.y * 0.5 - 30
        draw_rect(Rect2(prompt_x - 10, prompt_y - 25, 340, 55), Color(0.05, 0.06, 0.1, 0.95))
        draw_rect(Rect2(prompt_x - 10, prompt_y - 25, 340, 55), Color(0.4, 0.5, 0.7), false, 1.0)
        draw_string(font, Vector2(prompt_x, prompt_y - 6), "Template name:  (Enter to save, Esc to cancel)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))
        var cursor = "|" if fmod(Time.get_ticks_msec() * 0.001, 1.0) < 0.5 else ""
        draw_string(font, Vector2(prompt_x, prompt_y + 18), template_name_input + cursor, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 1.0))


    if _template_save_flash > 0:
        var flash_alpha = minf(_template_save_flash, 1.0)
        var fx = size.x * 0.5 - 60
        draw_string(font, Vector2(fx, 80), "Saved: %s" % _template_save_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.4, flash_alpha))


    if GameManager.using_controller and gamepad_cursor_initialized:
        _draw_gamepad_cursor(font)

func _draw_gamepad_cursor(_font: Font):

    var cp = gamepad_cursor_pos
    var pulse = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.003)
    var col = Color(0.4, 0.7, 1.0, pulse)
    var outer_col = Color(0.15, 0.3, 0.5, pulse * 0.5)

    draw_line(cp + Vector2(-10, 0), cp + Vector2(-4, 0), col, 2.0)
    draw_line(cp + Vector2(4, 0), cp + Vector2(10, 0), col, 2.0)
    draw_line(cp + Vector2(0, -10), cp + Vector2(0, -4), col, 2.0)
    draw_line(cp + Vector2(0, 4), cp + Vector2(0, 10), col, 2.0)

    draw_circle(cp, 2.0, col)

    draw_arc(cp, 8.0, 0, TAU, 24, outer_col, 1.0)

    if selected_module_id != "":
        var hint = "[A] Place  [X] Rotate  [B] Deselect"
        draw_string(_font, cp + Vector2(-80, 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.6, 0.7, 0.8))
    elif hovered_cell != Vector2i(-9999, -9999):
        var hint = "[A] Select  [B] Remove"
        draw_string(_font, cp + Vector2(-50, 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.6, 0.7, 0.8))

func _draw_palette(font: Font):
    var r = palette_rect
    draw_rect(r, Color(0.04, 0.05, 0.08, 1.0))
    draw_rect(r, Color(0.2, 0.25, 0.35), false, 1.0)
    draw_string(font, r.position + Vector2(12, 24), "MODULES", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.65, 0.75))
    draw_string(font, r.position + Vector2(12, 42), "Left-click to select", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.38, 0.48))


    search_bar_rect = Rect2(r.position.x + 6, r.position.y + 50, r.size.x - 12, 22)
    var sb_bg = Color(0.14, 0.14, 0.18) if search_active else Color(0.12, 0.12, 0.15)
    draw_rect(search_bar_rect, sb_bg)
    var sb_border = Color(0.4, 0.5, 0.7) if search_active else Color(0.3, 0.3, 0.35)
    draw_rect(search_bar_rect, sb_border, false, 1.0)
    var search_display = search_text if search_text != "" else "Search modules..."
    var search_col = Color(0.8, 0.8, 0.85) if search_text != "" else Color(0.4, 0.4, 0.45)
    if search_active and search_text != "":
        var cursor = "|" if fmod(Time.get_ticks_msec() * 0.001, 1.0) < 0.5 else ""
        search_display = search_text + cursor
    draw_string(font, Vector2(search_bar_rect.position.x + 4, search_bar_rect.position.y + 16), search_display, HORIZONTAL_ALIGNMENT_LEFT, int(search_bar_rect.size.x - 8), 10, search_col)

    var palette_content_top: float = 78.0
    var rows = _build_palette_rows()
    var y_acc: float = 0.0
    for i in rows.size():
        var row = rows[i]
        if row.row_type == "header":
            var iy = r.position.y + palette_content_top + y_acc - palette_scroll
            y_acc += HEADER_HEIGHT
            if iy < r.position.y + 75 or iy > r.end.y - 10:
                continue
            var is_hov = (i == hovered_palette_idx)
            var hdr_r = Rect2(r.position.x + 4, iy, r.size.x - 8, HEADER_HEIGHT - 2)
            var hdr_bg = Color(0.08, 0.09, 0.14) if not is_hov else Color(0.1, 0.12, 0.18)
            draw_rect(hdr_r, hdr_bg)
            var hdr_col: Color = row.color
            var collapsed = collapsed_categories.get(row.label, false)
            var arrow = ">" if collapsed else "v"
            draw_string(font, Vector2(hdr_r.position.x + 6, iy + 18), arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(hdr_col, 0.6))
            draw_string(font, Vector2(hdr_r.position.x + 18, iy + 18), row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(hdr_col, 0.9))
            draw_string(font, Vector2(hdr_r.end.x - 24, iy + 18), "(%d)" % row.count, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.42, 0.5))
        else:
            var id = row.id
            var mod = DataManager.modules.get(id, {})
            var iy = r.position.y + palette_content_top + y_acc - palette_scroll
            y_acc += ITEM_HEIGHT
            if iy < r.position.y + 75 or iy > r.end.y - 10:
                continue
            var item_r = Rect2(r.position.x + 6, iy, r.size.x - 12, 48)
            var is_sel = (id == selected_module_id)
            var is_hov = (i == hovered_palette_idx)
            if is_sel:
                draw_rect(item_r, Color(0.12, 0.16, 0.3))
                draw_rect(item_r, Color(0.4, 0.55, 0.9), false, 1.5)
            elif is_hov:
                draw_rect(item_r, Color(0.07, 0.09, 0.14))

            var type_str: String = mod.get("type", "")
            var tc = type_colors.get(type_str, Color.GRAY)
            var icon_center = item_r.position + Vector2(19, 22)
            _draw_module_shape_icon(icon_center, 12.0, type_str, tc)

            var mname: String = mod.get("name", id)
            var count: int = module_inventory.get(id, 0)
            var is_craft_only = count <= 0 and GameManager.CRAFTING_RECIPES.has(id)
            var name_col = Color(0.8, 0.82, 0.85)
            if count <= 0:
                name_col = Color(0.4, 0.75, 0.7) if is_craft_only else Color(0.4, 0.4, 0.42)
            draw_string(font, item_r.position + Vector2(42, 22), mname, HORIZONTAL_ALIGNMENT_LEFT, int(item_r.size.x - 85), 12, name_col)

            if is_craft_only:
                var can_do = GameManager.can_craft(id)
                var craft_col = Color(0.3, 0.8, 0.7) if can_do else Color(0.35, 0.35, 0.38)
                draw_string(font, item_r.position + Vector2(42, 38), "[CRAFT]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, craft_col)
                var recipe = GameManager.CRAFTING_RECIPES.get(id, {})
                var cx = item_r.position.x + 95
                for rt in recipe:
                    var needed = int(recipe[rt])
                    var have = GameManager.resources.get(rt, 0)
                    var rc_col = Color(0.4, 0.7, 0.4) if have >= needed else Color(0.7, 0.3, 0.2)
                    draw_string(font, Vector2(cx, item_r.position.y + 38), "%s:%d" % [rt.substr(0, 3), needed], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, rc_col)
                    cx += 42
            elif type_str == "engine" and mod.get("subtype", "") != "engine_block":
                draw_string(font, item_r.position + Vector2(42, 38), "x%d  (nothing behind)" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.6))
            else:
                draw_string(font, item_r.position + Vector2(42, 38), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.6))

func _draw_grid(font: Font):

    var exhaust_blocked: Dictionary = _get_engine_exhaust_blocked(current_deck)


    for cell in hull_cells:
        var center = grid_origin + HexUtil.hex_to_pixel(cell, HEX_SIZE)
        var corners = HexUtil.hex_corners(center, HEX_SIZE - 1.0)
        if core_cells.has(cell):

            draw_colored_polygon(corners, Color(0.25, 0.27, 0.32))
            _draw_hex_outline(center, HEX_SIZE - 1.0, Color(0.55, 0.6, 0.7), 1.5)
        else:
            if exhaust_blocked.has(cell):
                draw_colored_polygon(corners, Color(0.09, 0.05, 0.03))
            else:
                draw_colored_polygon(corners, Color(0.055, 0.065, 0.1))
            _draw_hex_outline(center, HEX_SIZE - 1.0, Color(0.14, 0.16, 0.22), 1.0)


    for cell in exhaust_blocked:
        var center = grid_origin + HexUtil.hex_to_pixel(cell, HEX_SIZE)
        _draw_hex_outline(center, HEX_SIZE - 2.0, Color(1.0, 0.4, 0.1, 0.15), 1.5)


    if not core_cells.is_empty():
        var core_center = Vector2.ZERO
        for cc in core_cells:
            core_center += grid_origin + HexUtil.hex_to_pixel(cc, HEX_SIZE)
        core_center /= float(core_cells.size())
        var core_name = DataManager.modules.get(GameManager.equipped_core, {}).get("name", "Core")
        draw_string(font, core_center + Vector2( - font.get_string_size(core_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x * 0.5, 4), core_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.65, 0.75))


    var hull_bounds = _get_hull_pixel_bounds()
    var _hull_label_y = maxf(hull_bounds[0].y - 30, 60.0)


    if deck_count > 1:
        for pm in placed_modules:
            if GameManager.get_mod_deck(pm) == current_deck:
                continue
            for hcell in GameManager.get_mod_hex_cells(pm):
                var center = grid_origin + HexUtil.hex_to_pixel(hcell, HEX_SIZE)
                var corners = HexUtil.hex_corners(center, HEX_SIZE - 3.0)
                draw_colored_polygon(corners, Color(0.2, 0.25, 0.35, 0.15))
                _draw_hex_outline(center, HEX_SIZE - 3.0, Color(0.3, 0.35, 0.45, 0.2), 1.0)


    for idx in placed_modules.size():
        var pm = placed_modules[idx]
        if GameManager.get_mod_deck(pm) != current_deck:
            continue
        var mod_data: Dictionary = pm.get("data", {})
        var type_str: String = mod_data.get("type", "")
        var tc = _get_builder_module_color(type_str)
        var is_powered = idx in powered_indices
        var is_damaged = pm.get("hp", 1) < pm.get("max_hp", 1)
        if is_damaged:
            tc = Color(0.4, 0.15, 0.1)
        var mod_cells = GameManager.get_mod_hex_cells(pm)
        var col = tc * 0.7 if is_powered else tc * 0.2
        var border_col = tc * 1.1 if is_powered else Color(0.6, 0.15, 0.1, 0.8)

        for hcell in mod_cells:
            var center = grid_origin + HexUtil.hex_to_pixel(hcell, HEX_SIZE)
            var corners = HexUtil.hex_corners(center, HEX_SIZE - 2.0)
            draw_colored_polygon(corners, col)
            _draw_hex_outline(center, HEX_SIZE - 2.0, border_col, 1.5)

        var sprite_name = mod_data.get("sprite", "")
        if sprite_name != "":
            var stex = GameManager.get_module_sprite(sprite_name)
            if stex != null:
                var mod_rot = int(pm.get("rotation", 0)) * PI / 3.0
                var spr_anchor = grid_origin + HexUtil.hex_to_pixel(pm.get("grid_pos", Vector2i.ZERO), HEX_SIZE)
                var sprite_offset = ModuleVisuals.get_canonical_sprite_center(mod_data, HEX_SIZE).rotated(mod_rot)
                var sprite_pos = spr_anchor + sprite_offset
                var shw = stex.get_width() * 0.5
                var shh = stex.get_height() * 0.5
                var spr_s = ModuleVisuals.get_sprite_scale(mod_data, HEX_SIZE)
                draw_set_transform(sprite_pos, mod_rot + ModuleVisuals.get_sprite_rotation_rad(mod_data), Vector2(spr_s, spr_s))
                draw_texture(stex, Vector2(-shw, -shh))
                draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

        var anchor_px = grid_origin + HexUtil.hex_to_pixel(pm.get("grid_pos", Vector2i.ZERO), HEX_SIZE)
        var short_label = _get_type_short_label(type_str)
        var label_w = short_label.length() * 3.5
        draw_string(font, Vector2(anchor_px.x - label_w, anchor_px.y + 3), short_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(border_col, 0.9))

        if is_damaged:
            draw_string(font, Vector2(anchor_px.x - 14, anchor_px.y + 12), "DMG", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.4, 0.15))
        elif not is_powered:
            var stats = mod_data.get("stats", {})
            if stats.get("power_draw", 0) > 0:
                draw_string(font, Vector2(anchor_px.x - 12, anchor_px.y + 12), "NO PWR", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1.0, 0.3, 0.2))


    _draw_power_lines()


    if hovered_cell == Vector2i(-9999, -9999):
        return
    var sel_data = DataManager.modules.get(selected_module_id, {})
    var sel_type: String = sel_data.get("type", "")


    var can_place = true
    var preview_cells: Array = []
    if selected_module_id != "":
        var hex_size: int = sel_data.get("hex_size", 1)
        var hex_shape: Array = sel_data.get("hex_shape", HexUtil.default_shape(hex_size))
        var shape = hex_shape
        var rot: int = placement_rotation % 6
        if rot > 0:
            shape = hex_shape.duplicate(true)
            for _i in rot:
                shape = HexUtil.rotate_shape_cw(shape)
        for offset in shape:
            var c = Vector2i(hovered_cell.x + offset[0], hovered_cell.y + offset[1])
            preview_cells.append(c)
            if not hull_cell_set.has(c):
                can_place = false

        if can_place:
            for c in preview_cells:
                if core_cells.has(c):
                    can_place = false
                    break

        if can_place:
            for c in preview_cells:
                if exhaust_blocked.has(c):
                    can_place = false
                    break

        if sel_type == "engine" and sel_data.get("subtype", "") != "engine_block" and can_place:
            var behind: Dictionary = {}
            for c in preview_cells:
                _flood_south(c, behind)
            for pm in placed_modules:
                if GameManager.get_mod_deck(pm) != current_deck:
                    continue
                var pm_cells = GameManager.get_mod_hex_cells(pm)
                for bc in behind:
                    if bc in pm_cells:
                        can_place = false
                        break
                if not can_place:
                    break
        for pm in placed_modules:
            if GameManager.get_mod_deck(pm) != current_deck:
                continue
            var pm_cells = GameManager.get_mod_hex_cells(pm)
            for c in preview_cells:
                if c in pm_cells:
                    can_place = false
                    break

    if selected_module_id != "" and preview_cells.size() > 0:
        var tc = type_colors.get(sel_type, Color.GRAY)
        for c in preview_cells:
            var center = grid_origin + HexUtil.hex_to_pixel(c, HEX_SIZE)
            var corners = HexUtil.hex_corners(center, HEX_SIZE - 1.0)
            if can_place:
                draw_colored_polygon(corners, Color(tc, 0.2))
                _draw_hex_outline(center, HEX_SIZE - 1.0, Color(tc, 0.7), 2.0)
            else:
                draw_colored_polygon(corners, Color(1.0, 0.15, 0.1, 0.15))
                _draw_hex_outline(center, HEX_SIZE - 1.0, Color(1.0, 0.3, 0.2, 0.7), 2.0)

    if selected_module_id != "":
        var sel_hex_size: int = sel_data.get("hex_size", 1)
        if sel_hex_size > 1:
            var rot_label = "[Q] ↺  [E] ↻"
            if placement_rotation > 0:
                rot_label += "  (rot %d)" % (placement_rotation * 60)
            var hb = _get_hull_pixel_bounds()
            draw_string(font, Vector2(hb[0].x, hb[1].y + 28), rot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))

    elif hovered_cell != Vector2i(-9999, -9999):
        var center = grid_origin + HexUtil.hex_to_pixel(hovered_cell, HEX_SIZE)
        var occupied = false
        for pm in placed_modules:
            if GameManager.get_mod_deck(pm) != current_deck:
                continue
            if hovered_cell in GameManager.get_mod_hex_cells(pm):
                occupied = true
                break
        if occupied:
            _draw_hex_outline(center, HEX_SIZE - 1.0, Color(1.0, 0.3, 0.2, 0.7), 2.0)
        else:
            var corners = HexUtil.hex_corners(center, HEX_SIZE - 1.0)
            draw_colored_polygon(corners, Color(0.3, 0.35, 0.5, 0.12))

func _draw_hex_outline(center: Vector2, hex_size: float, color: Color, width: float = 1.0):

    var corners = HexUtil.hex_corners(center, hex_size)
    for i in 6:
        draw_line(corners[i], corners[(i + 1) % 6], color, width)

func _get_hull_pixel_bounds() -> Array:

    var min_px = Vector2(INF, INF)
    var max_px = Vector2( - INF, - INF)
    for cell in hull_cells:
        var px = grid_origin + HexUtil.hex_to_pixel(cell, HEX_SIZE)
        min_px = min_px.min(px - Vector2(HEX_SIZE, HEX_SIZE))
        max_px = max_px.max(px + Vector2(HEX_SIZE, HEX_SIZE))
    if min_px.x == INF:
        return [Vector2.ZERO, size]
    return [min_px, max_px]

func _get_type_short_label(type_str: String) -> String:
    match type_str:
        "weapon": return "WPN"
        "shield": return "SHD"
        "engine": return "ENG"
        "reactor": return "PWR"
        "armor": return "ARM"
        "sensor": return "SNS"
        "conduit": return "CDT"
        "hallway": return "HAL"
        "airlock": return "ALK"
        "structural": return "STR"
        "cargo": return "CRG"
        "core": return "COR"
        "quarters": return "QTR"
        "mess": return "MES"
        "medbay": return "MED"
        "construction_hangar": return "CHG"
        "basic_workshop": return "WRK"
        "farmers_workshop": return "FRM"
        "solar_field": return "SOL"
        "life_support": return "LSP"
        "brig": return "BRG"
        "hangar": return "HNG"
        "hydroponics": return "HYD"
        "armory": return "ARM"
        "rec_room": return "REC"
        "bridge": return "BRD"
        "fuel_scoop": return "FSP"
        "mining": return "MIN"
        "research_lab": return "LAB"
        "ladder": return "LDR"
        "docking_collar": return "DCK"
        _: return type_str.substr(0, 3).to_upper()

func _draw_builder_module_shape(rect: Rect2, type_str: String, tc: Color, is_powered: bool, _font: Font):
    var cx = rect.position.x + rect.size.x * 0.5
    var cy = rect.position.y + rect.size.y * 0.5
    var hw = rect.size.x * 0.5
    var hh = rect.size.y * 0.5
    var col = tc * 0.7 if is_powered else tc * 0.2
    var border_col = tc * 1.1 if is_powered else Color(0.6, 0.15, 0.1, 0.8)

    match type_str:
        "weapon":

            var pts = PackedVector2Array([
                Vector2(cx, rect.position.y), 
                Vector2(rect.end.x, cy + hh * 0.3), 
                Vector2(rect.end.x - hw * 0.3, rect.end.y), 
                Vector2(rect.position.x + hw * 0.3, rect.end.y), 
                Vector2(rect.position.x, cy + hh * 0.3), 
            ])
            draw_colored_polygon(pts, col)
            draw_polyline(pts, border_col, 1.5)
            draw_line(pts[pts.size() - 1], pts[0], border_col, 1.5)

            if is_powered:
                draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.position.y - 4), tc * 1.3, 2.0)
                draw_circle(Vector2(cx, rect.position.y - 4), 2.0, Color(1.0, 0.8, 0.3, 0.4))
        "shield":

            var pts = PackedVector2Array()
            var steps = 12
            for i in range(steps + 1):
                var a = PI + float(i) / float(steps) * PI
                pts.append(Vector2(cx + cos(a) * hw, cy + sin(a) * hh * 0.8))
            pts.append(Vector2(cx + hw, rect.end.y))
            pts.append(Vector2(cx - hw, rect.end.y))
            draw_colored_polygon(pts, col)
            for i in range(pts.size() - 1):
                draw_line(pts[i], pts[i + 1], border_col, 1.0)
            draw_line(pts[pts.size() - 1], pts[0], border_col, 1.0)
            if is_powered:
                draw_arc(Vector2(cx, cy), minf(hw, hh) * 0.5, - PI * 0.8, PI * 0.2, 8, Color(0.5, 0.7, 1.0, 0.5), 1.5)
        "engine":

            var pts = PackedVector2Array([
                Vector2(cx - hw * 0.5, rect.position.y), 
                Vector2(cx + hw * 0.5, rect.position.y), 
                Vector2(cx + hw, rect.end.y - hh * 0.2), 
                Vector2(cx + hw * 0.8, rect.end.y), 
                Vector2(cx - hw * 0.8, rect.end.y), 
                Vector2(cx - hw, rect.end.y - hh * 0.2), 
            ])
            draw_colored_polygon(pts, col)
            draw_polyline(pts, border_col, 1.5)
            draw_line(pts[pts.size() - 1], pts[0], border_col, 1.5)

            if is_powered:
                draw_line(Vector2(cx - hw * 0.6, rect.end.y), Vector2(cx + hw * 0.6, rect.end.y), Color(1.0, 0.5, 0.15, 0.6), 3.0)
                draw_line(Vector2(cx - hw * 0.4, rect.end.y + 3), Vector2(cx + hw * 0.4, rect.end.y + 3), Color(1.0, 0.7, 0.3, 0.3), 2.0)
        "reactor":

            var pts = PackedVector2Array()
            for i in 6:
                var a = float(i) / 6.0 * TAU - PI / 6.0
                pts.append(Vector2(cx + cos(a) * hw * 0.9, cy + sin(a) * hh * 0.9))
            draw_colored_polygon(pts, col)
            draw_polyline(pts, border_col, 1.5)
            draw_line(pts[pts.size() - 1], pts[0], border_col, 1.5)
            if is_powered:
                var time = Time.get_ticks_msec() * 0.001
                var pulse = sin(time * 2.0) * 0.15 + 0.85
                draw_circle(Vector2(cx, cy), minf(hw, hh) * 0.35, Color(1.0, 0.95, 0.4, 0.5 * pulse))
                draw_arc(Vector2(cx, cy), minf(hw, hh) * 0.5, 0, TAU, 12, Color(tc, 0.4), 1.0)
        "armor":

            draw_rect(rect, col)

            draw_line(rect.position, Vector2(rect.end.x, rect.position.y), tc * 1.2 if is_powered else tc * 0.3, 2.0)
            draw_line(rect.position, Vector2(rect.position.x, rect.end.y), tc * 1.0 if is_powered else tc * 0.25, 1.5)
            draw_line(Vector2(rect.end.x, rect.position.y), rect.end, tc * 0.4, 1.5)
            draw_line(Vector2(rect.position.x, rect.end.y), rect.end, tc * 0.35, 1.5)

            if is_powered:
                var bolt_r = 2.5
                for corner in [rect.position + Vector2(6, 6), Vector2(rect.end.x - 6, rect.position.y + 6), Vector2(rect.position.x + 6, rect.end.y - 6), rect.end - Vector2(6, 6)]:
                    draw_circle(corner, bolt_r, tc * 0.5)
        "sensor":

            draw_circle(Vector2(cx, cy), minf(hw, hh) * 0.85, col)
            draw_arc(Vector2(cx, cy), minf(hw, hh) * 0.85, 0, TAU, 16, border_col, 1.5)
            if is_powered:
                var time = Time.get_ticks_msec() * 0.001
                draw_arc(Vector2(cx, cy), minf(hw, hh) * 0.5, 0, TAU, 10, Color(0.4, 1.0, 0.6, 0.4), 1.0)
                var sweep = fmod(time * 2.0, TAU)
                draw_line(Vector2(cx, cy), Vector2(cx + cos(sweep) * hw * 0.7, cy + sin(sweep) * hh * 0.7), Color(0.4, 1.0, 0.6, 0.6), 1.5)
                draw_circle(Vector2(cx, cy), 2.5, Color(0.4, 1.0, 0.6, 0.8))
        "conduit":

            var arm_w = minf(hw, hh) * 0.35

            draw_rect(Rect2(cx - arm_w, rect.position.y, arm_w * 2, rect.size.y), col)

            draw_rect(Rect2(rect.position.x, cy - arm_w, rect.size.x, arm_w * 2), col)
            draw_rect(Rect2(cx - arm_w, rect.position.y, arm_w * 2, rect.size.y), border_col, false, 1.0)
            draw_rect(Rect2(rect.position.x, cy - arm_w, rect.size.x, arm_w * 2), border_col, false, 1.0)
            if is_powered:
                var time = Time.get_ticks_msec() * 0.001
                var flow_t = fmod(time * 3.0, 1.0)
                var py = lerpf(rect.position.y, rect.end.y, flow_t)
                draw_circle(Vector2(cx, py), 2.0, Color(1.0, 0.9, 0.4, 0.6))
        "hallway":

            draw_rect(rect, col)

            draw_line(Vector2(rect.position.x, rect.position.y + 2), Vector2(rect.end.x, rect.position.y + 2), tc * 0.3, 1.5)
            draw_line(Vector2(rect.position.x, rect.end.y - 2), Vector2(rect.end.x, rect.end.y - 2), tc * 0.3, 1.5)

            var dash_len = 6.0
            var gap_len = 4.0
            var dx_pos = rect.position.x
            while dx_pos < rect.end.x - 1:
                var dash_end = minf(dx_pos + dash_len, rect.end.x)
                draw_line(Vector2(dx_pos, cy), Vector2(dash_end, cy), tc * 0.25, 1.0)
                dx_pos += dash_len + gap_len

            var tile_step = rect.size.x / maxf(float(int(rect.size.x / 20.0)), 1.0)
            var tx = rect.position.x + tile_step
            while tx < rect.end.x - 2:
                draw_line(Vector2(tx, rect.position.y + 4), Vector2(tx, rect.end.y - 4), tc * 0.15, 0.5)
                tx += tile_step
            draw_rect(rect, border_col, false, 1.5)
        "airlock":

            draw_rect(rect, col)

            draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)), tc * 0.25, false, 2.5)

            var stripe_y = rect.position.y + 4
            while stripe_y < rect.end.y - 6:
                draw_line(Vector2(rect.position.x + 3, stripe_y), Vector2(rect.position.x + 8, stripe_y + 4), Color(0.9, 0.7, 0.1, 0.35), 1.0)
                draw_line(Vector2(rect.end.x - 3, stripe_y), Vector2(rect.end.x - 8, stripe_y + 4), Color(0.9, 0.7, 0.1, 0.35), 1.0)
                stripe_y += 8

            draw_arc(Vector2(cx, cy), minf(hw, hh) * 0.4, 0, TAU, 12, tc * 0.45, 1.5)
            draw_circle(Vector2(cx, cy), minf(hw, hh) * 0.15, tc * 0.35)
            draw_rect(rect, border_col, false, 2.0)
        "structural":

            draw_rect(rect, col)

            var hatch_step = 8.0
            var hx_start = rect.position.x
            while hx_start < rect.end.x:
                draw_line(Vector2(hx_start, rect.position.y), Vector2(hx_start + rect.size.y, rect.end.y), tc * 0.15, 0.5)
                draw_line(Vector2(hx_start, rect.end.y), Vector2(hx_start + rect.size.y, rect.position.y), tc * 0.15, 0.5)
                hx_start += hatch_step

            var rivet_r = 2.0
            var rivet_inset = 5.0
            for corner in [rect.position + Vector2(rivet_inset, rivet_inset), Vector2(rect.end.x - rivet_inset, rect.position.y + rivet_inset), Vector2(rect.position.x + rivet_inset, rect.end.y - rivet_inset), rect.end - Vector2(rivet_inset, rivet_inset)]:
                draw_circle(corner, rivet_r, tc * 0.5)
                draw_arc(corner, rivet_r, 0, TAU, 6, tc * 0.3, 0.5)
            draw_rect(rect, border_col, false, 2.0)
        "cargo":

            draw_rect(rect, col)

            draw_line(Vector2(rect.position.x, cy), Vector2(rect.end.x, cy), tc * 0.4 if is_powered else tc * 0.15, 2.0)
            draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.end.y), tc * 0.4 if is_powered else tc * 0.15, 2.0)
            draw_rect(rect, border_col, false, 1.5)
            if is_powered:
                draw_rect(Rect2(cx - hw * 0.3, rect.position.y + 3, hw * 0.6, 4), tc * 0.8)
        "quarters":
            draw_rect(rect, col)
            var bed_gap = rect.size.y / 3.0
            for bi in 2:
                var by = rect.position.y + bed_gap * (bi + 1)
                draw_line(Vector2(rect.position.x + 2, by), Vector2(rect.end.x - 2, by), tc * 0.35, 1.5)
            draw_rect(rect, border_col, false, 1.5)
        "mess":
            draw_rect(rect, col)
            draw_circle(Vector2(cx, cy), minf(hw, hh) * 0.45, tc * 0.35)
            draw_rect(rect, border_col, false, 1.5)
        "medbay":
            draw_rect(rect, col)
            var arm_w = minf(hw, hh) * 0.22
            draw_rect(Rect2(cx - arm_w, rect.position.y + 2, arm_w * 2, rect.size.y - 4), Color(0.3, 0.85, 0.4, 0.4))
            draw_rect(Rect2(rect.position.x + 2, cy - arm_w, rect.size.x - 4, arm_w * 2), Color(0.3, 0.85, 0.4, 0.4))
            draw_rect(rect, border_col, false, 1.5)
        "construction_hangar":
            draw_rect(rect, col)
            var wr = minf(hw, hh) * 0.45
            for wi in 6:
                var a1 = float(wi) / 6.0 * TAU
                var a2 = float(wi + 1) / 6.0 * TAU
                draw_line(Vector2(cx + cos(a1) * wr, cy + sin(a1) * wr), 
                    Vector2(cx + cos(a2) * wr, cy + sin(a2) * wr), tc * 0.35, 1.0)
            draw_rect(rect, border_col, false, 1.5)
        "docking_collar":
            draw_rect(rect, col)

            var cw = minf(hw, hh) * 0.5
            draw_rect(Rect2(cx - cw, cy - cw * 0.6, cw * 0.3, cw * 1.2), tc * 0.45)
            draw_rect(Rect2(cx + cw * 0.7, cy - cw * 0.6, cw * 0.3, cw * 1.2), tc * 0.45)
            draw_line(Vector2(cx - cw * 0.3, cy), Vector2(cx + cw * 0.7, cy), tc * 0.3, 1.5)
            draw_rect(rect, border_col, false, 1.5)
        "basic_workshop", "farmers_workshop":
            draw_rect(rect, col)

            draw_rect(Rect2(cx - hw * 0.6, cy + hh * 0.1, hw * 1.2, hh * 0.3), tc * 0.4)
            draw_rect(Rect2(cx - hw * 0.2, cy - hh * 0.4, hw * 0.4, hh * 0.5), tc * 0.3)
            draw_rect(rect, border_col, false, 1.5)
        "solar_field":
            draw_rect(rect, col)

            var sr = minf(hw, hh) * 0.3
            draw_circle(Vector2(cx, cy), sr, Color(1.0, 0.85, 0.3, 0.5))
            for ri in 8:
                var ra = float(ri) / 8.0 * TAU
                draw_line(Vector2(cx + cos(ra) * sr, cy + sin(ra) * sr), 
                    Vector2(cx + cos(ra) * sr * 1.8, cy + sin(ra) * sr * 1.8), Color(1.0, 0.8, 0.2, 0.3), 1.0)
            draw_rect(rect, border_col, false, 1.5)
        "life_support":
            draw_rect(rect, col)
            var lr = minf(hw, hh) * 0.5
            draw_arc(Vector2(cx, cy), lr, 0, TAU, 10, tc * 0.4, 1.0)
            for li in 4:
                var la = float(li) / 4.0 * TAU
                draw_line(Vector2(cx, cy), Vector2(cx + cos(la) * lr, cy + sin(la) * lr), tc * 0.3, 0.8)
            draw_rect(rect, border_col, false, 1.5)
        "brig":
            draw_rect(rect, col)
            for bi in 3:
                var bx = rect.position.x + rect.size.x * (float(bi + 1) / 4.0)
                draw_line(Vector2(bx, rect.position.y + 2), Vector2(bx, rect.end.y - 2), tc * 0.3, 1.5)
            draw_rect(rect, border_col, false, 1.5)
        "hangar":
            draw_rect(rect, col)
            draw_line(Vector2(cx, rect.position.y + 2), Vector2(cx, rect.end.y - 2), Color(0, 0, 0, 0.25), 2.0)
            draw_rect(rect, border_col, false, 1.5)
        "hydroponics":
            draw_rect(rect, col)
            for hi in 3:
                var hx = rect.position.x + rect.size.x * (float(hi + 1) / 4.0)
                draw_line(Vector2(hx, cy + hh * 0.3), Vector2(hx, cy - hh * 0.4), tc * 0.35, 1.5)
                draw_line(Vector2(hx - 2, cy - hh * 0.3), Vector2(hx, cy - hh * 0.5), tc * 0.3, 1.0)
                draw_line(Vector2(hx + 2, cy - hh * 0.3), Vector2(hx, cy - hh * 0.5), tc * 0.3, 1.0)
            draw_rect(rect, border_col, false, 1.5)
        "armory":
            draw_rect(rect, col)
            draw_line(Vector2(cx - hw * 0.4, cy - hh * 0.4), Vector2(cx + hw * 0.4, cy + hh * 0.4), tc * 0.35, 1.5)
            draw_line(Vector2(cx + hw * 0.4, cy - hh * 0.4), Vector2(cx - hw * 0.4, cy + hh * 0.4), tc * 0.35, 1.5)
            draw_rect(rect, border_col, false, 1.5)
        "rec_room":
            draw_rect(rect, col)
            var sr = minf(hw, hh) * 0.45
            for si in 5:
                var sa = float(si) / 5.0 * TAU - PI / 2.0
                var sb = float(si + 2) / 5.0 * TAU - PI / 2.0
                draw_line(Vector2(cx + cos(sa) * sr, cy + sin(sa) * sr), 
                    Vector2(cx + cos(sb) * sr, cy + sin(sb) * sr), tc * 0.3, 1.0)
            draw_rect(rect, border_col, false, 1.5)
        "bridge":
            draw_rect(rect, col)
            draw_line(Vector2(cx - hw * 0.5, cy + hh * 0.3), Vector2(cx, cy - hh * 0.3), tc * 0.35, 1.5)
            draw_line(Vector2(cx + hw * 0.5, cy + hh * 0.3), Vector2(cx, cy - hh * 0.3), tc * 0.35, 1.5)
            draw_circle(Vector2(cx, cy - hh * 0.3), minf(hw, hh) * 0.15, tc * 0.3)
            draw_rect(rect, border_col, false, 1.5)
        "fuel_scoop":
            draw_rect(rect, col)

            var sun_r = minf(hw, hh) * 0.35
            draw_circle(Vector2(cx, cy), sun_r, tc * 0.4)
            for ri in 8:
                var ra = float(ri) / 8.0 * TAU
                var ray_inner = sun_r * 1.2
                var ray_outer = sun_r * 1.8
                draw_line(Vector2(cx + cos(ra) * ray_inner, cy + sin(ra) * ray_inner), 
                    Vector2(cx + cos(ra) * ray_outer, cy + sin(ra) * ray_outer), tc * 0.3, 1.0)
            draw_rect(rect, border_col, false, 1.5)
        "mining":
            draw_rect(rect, col)

            draw_line(Vector2(cx - hw * 0.5, cy - hh * 0.5), Vector2(cx + hw * 0.3, cy + hh * 0.5), tc * 0.35, 1.5)
            draw_line(Vector2(cx + hw * 0.5, cy - hh * 0.5), Vector2(cx, cy + hh * 0.1), tc * 0.35, 1.5)
            draw_line(Vector2(cx - hw * 0.5, cy - hh * 0.5), Vector2(cx + hw * 0.1, cy - hh * 0.5), tc * 0.3, 1.5)
            draw_rect(rect, border_col, false, 1.5)
        "research_lab":
            draw_rect(rect, col)

            var flask_w = hw * 0.3
            var flask_top = cy - hh * 0.45
            var flask_mid = cy + hh * 0.05
            var flask_bot = cy + hh * 0.4
            draw_line(Vector2(cx - flask_w * 0.5, flask_top), Vector2(cx + flask_w * 0.5, flask_top), tc * 0.4, 1.5)
            draw_line(Vector2(cx - flask_w * 0.5, flask_top), Vector2(cx - flask_w * 0.5, flask_mid), tc * 0.4, 1.5)
            draw_line(Vector2(cx + flask_w * 0.5, flask_top), Vector2(cx + flask_w * 0.5, flask_mid), tc * 0.4, 1.5)
            draw_line(Vector2(cx - flask_w * 0.5, flask_mid), Vector2(cx - hw * 0.4, flask_bot), tc * 0.4, 1.5)
            draw_line(Vector2(cx + flask_w * 0.5, flask_mid), Vector2(cx + hw * 0.4, flask_bot), tc * 0.4, 1.5)
            draw_line(Vector2(cx - hw * 0.4, flask_bot), Vector2(cx + hw * 0.4, flask_bot), tc * 0.4, 1.5)
            if is_powered:
                draw_circle(Vector2(cx, flask_bot - 3), hw * 0.18, Color(0.3, 0.6, 0.9, 0.5))
            draw_rect(rect, border_col, false, 1.5)
        "ladder":

            draw_rect(rect, col)

            draw_line(Vector2(rect.position.x + hw * 0.3, rect.position.y + 2), Vector2(rect.position.x + hw * 0.3, rect.end.y - 2), tc * 0.45, 2.0)
            draw_line(Vector2(rect.end.x - hw * 0.3, rect.position.y + 2), Vector2(rect.end.x - hw * 0.3, rect.end.y - 2), tc * 0.45, 2.0)

            var rung_count = 4
            for ri in rung_count:
                var ry = lerpf(rect.position.y + 5, rect.end.y - 5, float(ri + 0.5) / float(rung_count))
                draw_line(Vector2(rect.position.x + hw * 0.3, ry), Vector2(rect.end.x - hw * 0.3, ry), tc * 0.35, 1.5)

            if is_powered or true:
                draw_line(Vector2(cx, rect.position.y + 3), Vector2(cx, rect.position.y + 8), Color(0.8, 0.7, 0.3, 0.6), 1.5)
                draw_line(Vector2(cx - 3, rect.position.y + 6), Vector2(cx, rect.position.y + 3), Color(0.8, 0.7, 0.3, 0.6), 1.0)
                draw_line(Vector2(cx + 3, rect.position.y + 6), Vector2(cx, rect.position.y + 3), Color(0.8, 0.7, 0.3, 0.6), 1.0)
                draw_line(Vector2(cx, rect.end.y - 3), Vector2(cx, rect.end.y - 8), Color(0.8, 0.7, 0.3, 0.6), 1.5)
                draw_line(Vector2(cx - 3, rect.end.y - 6), Vector2(cx, rect.end.y - 3), Color(0.8, 0.7, 0.3, 0.6), 1.0)
                draw_line(Vector2(cx + 3, rect.end.y - 6), Vector2(cx, rect.end.y - 3), Color(0.8, 0.7, 0.3, 0.6), 1.0)
            draw_rect(rect, border_col, false, 1.5)
        _:
            draw_rect(rect, col)
            draw_rect(rect, border_col, false, 1.5)

func _draw_module_shape_icon(center: Vector2, r: float, type_str: String, tc: Color):
    match type_str:
        "weapon":
            var pts = PackedVector2Array([
                center + Vector2(0, - r), center + Vector2(r * 0.7, r * 0.3), 
                center + Vector2(r * 0.4, r), center + Vector2( - r * 0.4, r), 
                center + Vector2( - r * 0.7, r * 0.3), 
            ])
            draw_colored_polygon(pts, tc * 0.8)
        "shield":
            draw_arc(center, r * 0.7, PI, TAU, 8, tc, 2.5)
            draw_line(center + Vector2( - r * 0.7, 0), center + Vector2( - r * 0.7, r * 0.5), tc, 1.5)
            draw_line(center + Vector2(r * 0.7, 0), center + Vector2(r * 0.7, r * 0.5), tc, 1.5)
        "engine":
            var pts = PackedVector2Array([
                center + Vector2( - r * 0.4, - r), center + Vector2(r * 0.4, - r), 
                center + Vector2(r * 0.8, r), center + Vector2( - r * 0.8, r), 
            ])
            draw_colored_polygon(pts, tc * 0.8)
        "reactor":
            var pts = PackedVector2Array()
            for i in 6:
                var a = float(i) / 6.0 * TAU - PI / 6.0
                pts.append(center + Vector2(cos(a), sin(a)) * r * 0.8)
            draw_colored_polygon(pts, tc * 0.8)
        "armor":
            draw_rect(Rect2(center - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), tc * 0.8)
        "sensor":
            draw_circle(center, r * 0.7, tc * 0.8)
            draw_circle(center, r * 0.3, tc * 1.2)
        "conduit":
            draw_rect(Rect2(center.x - r * 0.2, center.y - r * 0.7, r * 0.4, r * 1.4), tc * 0.8)
            draw_rect(Rect2(center.x - r * 0.7, center.y - r * 0.2, r * 1.4, r * 0.4), tc * 0.8)
        "hallway":

            draw_rect(Rect2(center - Vector2(r, r) * 0.65, Vector2(r, r) * 1.3), tc * 0.7)
            draw_line(center + Vector2( - r * 0.5, 0), center + Vector2(r * 0.5, 0), tc * 0.35, 1.0)
        "airlock":

            draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), tc * 0.7)
            draw_arc(center, r * 0.35, 0, TAU, 8, tc * 0.4, 1.5)
            draw_circle(center, r * 0.12, tc * 0.5)
        "structural":

            draw_rect(Rect2(center - Vector2(r, r) * 0.65, Vector2(r, r) * 1.3), tc * 0.7)
            draw_line(center + Vector2( - r * 0.5, - r * 0.5), center + Vector2(r * 0.5, r * 0.5), tc * 0.4, 1.0)
            draw_line(center + Vector2(r * 0.5, - r * 0.5), center + Vector2( - r * 0.5, r * 0.5), tc * 0.4, 1.0)
        "cargo":
            draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), tc * 0.8)
            draw_line(center + Vector2( - r * 0.6, 0), center + Vector2(r * 0.6, 0), tc * 0.4, 1.0)
        "quarters":
            draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), tc * 0.7)
            draw_line(center + Vector2( - r * 0.5, - r * 0.2), center + Vector2(r * 0.5, - r * 0.2), tc * 0.4, 1.0)
            draw_line(center + Vector2( - r * 0.5, r * 0.2), center + Vector2(r * 0.5, r * 0.2), tc * 0.4, 1.0)
        "mess":
            draw_circle(center, r * 0.6, tc * 0.7)
            draw_circle(center, r * 0.3, tc * 0.4)
        "medbay":
            draw_rect(Rect2(center.x - r * 0.15, center.y - r * 0.6, r * 0.3, r * 1.2), tc * 0.8)
            draw_rect(Rect2(center.x - r * 0.6, center.y - r * 0.15, r * 1.2, r * 0.3), tc * 0.8)
        "construction_hangar":
            for wi in 6:
                var a1 = float(wi) / 6.0 * TAU
                var a2 = float(wi + 1) / 6.0 * TAU
                draw_line(center + Vector2(cos(a1), sin(a1)) * r * 0.6, 
                    center + Vector2(cos(a2), sin(a2)) * r * 0.6, tc * 0.7, 1.0)
        "docking_collar":
            var br = r * 0.45
            draw_rect(Rect2(center.x - br, center.y - br * 0.5, br * 0.3, br * 1.0), tc * 0.7)
            draw_rect(Rect2(center.x + br * 0.7, center.y - br * 0.5, br * 0.3, br * 1.0), tc * 0.7)
            draw_line(center + Vector2( - br * 0.3, 0), center + Vector2(br * 0.7, 0), tc * 0.5, 1.0)
        "basic_workshop", "farmers_workshop":
            draw_rect(Rect2(center.x - r * 0.5, center.y + r * 0.05, r * 1.0, r * 0.25), tc * 0.7)
            draw_rect(Rect2(center.x - r * 0.15, center.y - r * 0.4, r * 0.3, r * 0.45), tc * 0.5)
        "solar_field":
            draw_circle(center, r * 0.3, Color(1.0, 0.85, 0.3, 0.6))
            for ri in 8:
                var ra = float(ri) / 8.0 * TAU
                draw_line(center + Vector2(cos(ra), sin(ra)) * r * 0.3, 
                    center + Vector2(cos(ra), sin(ra)) * r * 0.6, Color(1.0, 0.8, 0.2, 0.4), 1.0)
        "life_support":
            draw_arc(center, r * 0.5, 0, TAU, 10, tc * 0.7, 1.0)
            for li in 4:
                var la = float(li) / 4.0 * TAU
                draw_line(center, center + Vector2(cos(la), sin(la)) * r * 0.5, tc * 0.5, 0.8)
        "brig":
            draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), tc * 0.6)
            for bi in 2:
                var bx = center.x + (float(bi) * 2.0 - 1.0) * r * 0.25
                draw_line(Vector2(bx, center.y - r * 0.5), Vector2(bx, center.y + r * 0.5), tc * 0.35, 1.0)
        "hangar":
            draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), tc * 0.7)
            draw_line(center + Vector2(0, - r * 0.5), center + Vector2(0, r * 0.5), Color(0, 0, 0, 0.3), 1.5)
        "hydroponics":
            draw_line(center + Vector2(0, r * 0.5), center + Vector2(0, - r * 0.2), tc * 0.7, 1.5)
            draw_line(center + Vector2( - r * 0.3, 0), center + Vector2(0, - r * 0.5), tc * 0.7, 1.0)
            draw_line(center + Vector2(r * 0.3, 0), center + Vector2(0, - r * 0.5), tc * 0.7, 1.0)
        "armory":
            draw_line(center + Vector2( - r * 0.5, - r * 0.5), center + Vector2(r * 0.5, r * 0.5), tc * 0.7, 1.5)
            draw_line(center + Vector2(r * 0.5, - r * 0.5), center + Vector2( - r * 0.5, r * 0.5), tc * 0.7, 1.5)
            draw_circle(center, r * 0.2, tc * 0.5)
        "rec_room":
            for si in 5:
                var sa = float(si) / 5.0 * TAU - PI / 2.0
                var sb = float(si + 2) / 5.0 * TAU - PI / 2.0
                draw_line(center + Vector2(cos(sa), sin(sa)) * r * 0.6, 
                    center + Vector2(cos(sb), sin(sb)) * r * 0.6, tc * 0.7, 1.0)
        "bridge":
            draw_line(center + Vector2( - r * 0.6, r * 0.4), center + Vector2(0, - r * 0.4), tc * 0.7, 1.5)
            draw_line(center + Vector2(r * 0.6, r * 0.4), center + Vector2(0, - r * 0.4), tc * 0.7, 1.5)
            draw_circle(center + Vector2(0, - r * 0.4), r * 0.2, tc * 0.6)
        "fuel_scoop":
            draw_circle(center, r * 0.45, tc * 0.7)
            for ri in 6:
                var ra = float(ri) / 6.0 * TAU
                draw_line(center + Vector2(cos(ra), sin(ra)) * r * 0.5, 
                    center + Vector2(cos(ra), sin(ra)) * r * 0.75, tc * 0.5, 1.0)
        "mining":
            draw_line(center + Vector2( - r * 0.5, - r * 0.5), center + Vector2(r * 0.3, r * 0.5), tc * 0.7, 1.5)
            draw_line(center + Vector2(r * 0.5, - r * 0.5), center + Vector2(0, r * 0.1), tc * 0.7, 1.5)
            draw_line(center + Vector2( - r * 0.5, - r * 0.5), center + Vector2(r * 0.1, - r * 0.5), tc * 0.5, 1.0)
        "research_lab":

            draw_line(center + Vector2( - r * 0.15, - r * 0.5), center + Vector2(r * 0.15, - r * 0.5), tc * 0.7, 1.0)
            draw_line(center + Vector2( - r * 0.15, - r * 0.5), center + Vector2( - r * 0.15, - r * 0.05), tc * 0.7, 1.0)
            draw_line(center + Vector2(r * 0.15, - r * 0.5), center + Vector2(r * 0.15, - r * 0.05), tc * 0.7, 1.0)
            draw_line(center + Vector2( - r * 0.15, - r * 0.05), center + Vector2( - r * 0.4, r * 0.45), tc * 0.7, 1.0)
            draw_line(center + Vector2(r * 0.15, - r * 0.05), center + Vector2(r * 0.4, r * 0.45), tc * 0.7, 1.0)
            draw_line(center + Vector2( - r * 0.4, r * 0.45), center + Vector2(r * 0.4, r * 0.45), tc * 0.7, 1.0)
            draw_circle(center + Vector2(0, r * 0.3), r * 0.15, tc * 0.5)
        "ladder":

            draw_line(center + Vector2( - r * 0.3, - r * 0.6), center + Vector2( - r * 0.3, r * 0.6), tc * 0.7, 1.5)
            draw_line(center + Vector2(r * 0.3, - r * 0.6), center + Vector2(r * 0.3, r * 0.6), tc * 0.7, 1.5)
            for ri in 3:
                var ry = lerpf( - r * 0.4, r * 0.4, float(ri) / 2.0)
                draw_line(center + Vector2( - r * 0.3, ry), center + Vector2(r * 0.3, ry), tc * 0.5, 1.0)
        _:
            draw_circle(center, r * 0.6, tc * 0.8)

func _draw_stats_panel(font: Font):
    var r = stats_rect
    draw_rect(r, Color(0.04, 0.05, 0.08, 1.0))
    draw_rect(r, Color(0.2, 0.25, 0.35), false, 1.0)
    draw_string(font, r.position + Vector2(12, 24), "SHIP STATS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.65, 0.75))

    var s = calc_stats()
    var lx = r.position.x + 16
    var vx = r.position.x + 170
    var y = r.position.y + 55
    var lh: float = 30.0

    _stat_line(font, y, lx, vx, "HULL", str(int(s.hull)), Color(0.15, 0.75, 0.25));y += lh
    _stat_line(font, y, lx, vx, "SHIELDS", str(int(s.shields)), Color(0.25, 0.45, 1.0));y += lh
    _stat_line(font, y, lx, vx, "MAX SPEED", str(int(s.speed)), Color(1.0, 0.6, 0.15));y += lh

    var tr_pct = int(s.get("thrust_ratio", 1.0) * 100)
    var tr_col = Color(0.2, 0.85, 0.4) if tr_pct >= 80 else (Color(1.0, 0.7, 0.2) if tr_pct >= 50 else Color(1.0, 0.3, 0.2))
    _stat_line(font, y, lx, vx, "THRUST/WEIGHT", "%d%%" % tr_pct, tr_col);y += lh
    _stat_line(font, y, lx, vx, "WEAPONS", str(s.weapon_count), Color(0.9, 0.25, 0.2));y += lh
    _stat_line(font, y, lx, vx, "TOTAL DAMAGE", str(int(s.damage)), Color(0.9, 0.25, 0.2));y += lh
    if s.cargo_capacity > 0:
        _stat_line(font, y, lx, vx, "CARGO", str(s.cargo_capacity), Color(0.7, 0.55, 0.2));y += lh
    if s.crew_capacity > 0 or s.quarters_capacity > 0:
        var crew_col = Color(0.75, 0.55, 0.3)
        var crew_label = str(s.crew_capacity)
        if s.life_support_capacity > 0 and s.life_support_capacity < s.quarters_capacity:
            crew_label += " (LS: %d)" % s.life_support_capacity
            crew_col = Color(1.0, 0.6, 0.2)
        _stat_line(font, y, lx, vx, "CREW CAP", crew_label, crew_col);y += lh
    _stat_line(font, y, lx, vx, "FUEL CAP", str(int(s.fuel_capacity)), Color(0.4, 0.6, 0.9));y += lh
    y += 10
    var over = s.power_draw > s.power_output
    var pc = Color(1.0, 0.3, 0.2) if over else Color(0.2, 0.85, 0.4)
    _stat_line(font, y, lx, vx, "POWER", "%d / %d" % [int(s.power_draw), int(s.power_output)], pc);y += lh
    var bw = r.size.x - 32
    var bh: float = 14.0
    var pct = clampf(s.power_draw / maxf(s.power_output, 1), 0, 1.5)
    draw_rect(Rect2(lx, y, bw, bh), Color(0.08, 0.08, 0.1))
    draw_rect(Rect2(lx, y, bw * minf(pct, 1.0), bh), pc)
    draw_rect(Rect2(lx, y, bw, bh), Color(0.25, 0.25, 0.3), false, 1.0)
    if over:
        draw_string(font, Vector2(lx, y + bh + 18), "OVER BUDGET!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.2))
    y += bh + 25
    if s.unpowered_count > 0:
        draw_string(font, Vector2(lx, y), "%d module(s) NO POWER" % s.unpowered_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.4, 0.2))
        y += 20
    draw_string(font, Vector2(lx, y), "Modules: %d" % placed_modules.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.48, 0.55))
    y += 20
    var used_cells = 0
    for pm in placed_modules:
        used_cells += _get_module_cells(pm).size()
    draw_string(font, Vector2(lx, y), "Cells: %d / %d" % [used_cells, hull_cells.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.48, 0.55))

    y = r.position.y + r.size.y - 80
    draw_string(font, Vector2(lx, y), "Left click : select & place", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.38, 0.48))
    draw_string(font, Vector2(lx, y + 18), "Right click: remove / deselect", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.38, 0.48))
    draw_string(font, Vector2(lx, y + 36), "Engines: bottom edge only", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.5, 0.2, 0.5))


    if creative_mode:
        _draw_core_selector(font)

        if _creative_show_templates:
            _draw_template_browser(font)

        if _test_ships_open:
            _draw_test_ships_picker(font)


func _draw_test_ships_picker(font: Font):
    _test_ships_rects.clear()
    if TEST_SHIP_TEMPLATES.is_empty():
        return
    var row_h: float = 36.0
    var panel_w: float = 200.0
    var panel_h: float = 34.0 + row_h * minf(TEST_SHIP_TEMPLATES.size(), 6)
    var px = _btn_test_ships.position.x
    var py = _btn_test_ships.position.y + _btn_test_ships.size.y + 4
    draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.03, 0.04, 0.07, 0.97))
    draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.65, 0.45, 0.25, 0.6), false, 2.0)
    draw_string(font, Vector2(px + 10, py + 20), "TEST SHIPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.65, 0.35))
    var list_y = py + 30.0
    var mouse_pos = get_local_mouse_position()
    for i in TEST_SHIP_TEMPLATES.size():
        var tname = TEST_SHIP_TEMPLATES[i]
        var ry = list_y + float(i) * row_h
        var row_rect = Rect2(px + 6, ry, panel_w - 12, row_h - 4)
        _test_ships_rects.append({"rect": row_rect, "name": tname})
        var is_hov = row_rect.has_point(mouse_pos)
        draw_rect(row_rect, Color(0.12, 0.1, 0.06) if is_hov else Color(0.05, 0.06, 0.08))
        draw_rect(row_rect, Color(0.5, 0.35, 0.2) if is_hov else Color(0.15, 0.18, 0.22), false, 1.0)
        var tmpl = GameManager.get_template_by_name(tname)
        var display_name = tmpl.get("name", tname) if not tmpl.is_empty() else tname
        draw_string(font, Vector2(row_rect.position.x + 8, ry + 16), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.75, 0.55) if is_hov else Color(0.65, 0.6, 0.5))
        var mod_count = tmpl.get("modules", []).size() if not tmpl.is_empty() else 0
        var core_id = tmpl.get("core_id", "")
        var core_label = DataManager.modules.get(core_id, {}).get("name", "") if core_id != "" else ""
        if core_label != "" or mod_count > 0:
            var info = "%s  |  %d modules" % [core_label, mod_count] if core_label != "" else "%d modules" % mod_count
            draw_string(font, Vector2(row_rect.position.x + 8, ry + 28), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.4, 0.35))

func _draw_module_info(font: Font):
    if selected_module_id == "":
        return
    var mod = DataManager.modules.get(selected_module_id, {})
    if mod.is_empty():
        return
    var bounds = _get_hull_pixel_bounds()
    var ix = bounds[0].x
    var iy = bounds[1].y + 24
    var iw = bounds[1].x - bounds[0].x
    draw_rect(Rect2(ix, iy, iw, 52), Color(0.04, 0.05, 0.08, 0.92))
    draw_rect(Rect2(ix, iy, iw, 52), Color(0.25, 0.3, 0.45), false, 1.0)
    var mname: String = mod.get("name", selected_module_id)
    var desc: String = mod.get("description", "")
    draw_string(font, Vector2(ix + 12, iy + 18), mname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.87, 0.92))
    draw_string(font, Vector2(ix + 12, iy + 38), desc, HORIZONTAL_ALIGNMENT_LEFT, int(iw - 24), 11, Color(0.55, 0.58, 0.65))

func _draw_core_selector(font: Font):
    var r = stats_rect
    var cx = r.position.x + 12
    var cy = r.position.y + r.size.y - 280
    core_btn_rects.clear()
    draw_string(font, Vector2(cx, cy), "HULL FRAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.65, 0.75))
    cy += 20
    for i in core_ids.size():
        var cid = core_ids[i]
        var cdata = DataManager.modules.get(cid, {})
        var btn_r = Rect2(cx, cy, r.size.x - 24, 28)
        core_btn_rects.append(btn_r)
        var is_active = (cid == GameManager.equipped_core)
        var has_core = module_inventory.get(cid, 0) > 0
        var can_craft_core = GameManager.CRAFTING_RECIPES.has(cid) and GameManager.can_craft(cid)
        var available = is_active or has_core or can_craft_core or creative_mode
        if is_active:
            draw_rect(btn_r, Color(0.15, 0.18, 0.3))
            draw_rect(btn_r, Color(0.5, 0.6, 1.0) if not creative_mode else Color(0.3, 0.8, 0.55), false, 1.5)
        elif available:
            draw_rect(btn_r, Color(0.06, 0.07, 0.1))
            draw_rect(btn_r, Color(0.2, 0.22, 0.3), false, 1.0)
        else:
            draw_rect(btn_r, Color(0.04, 0.04, 0.05))
            draw_rect(btn_r, Color(0.12, 0.12, 0.15), false, 1.0)
        var cname: String = cdata.get("name", cid)
        var label = cname
        if creative_mode:
            pass
        elif not is_active and not has_core and can_craft_core:
            label += " [CRAFT]"
        elif not is_active and not has_core and not can_craft_core:
            var req_research = GameManager.CORE_RESEARCH_REQS.get(cid, "")
            if req_research != "" and req_research not in GameManager.completed_research:
                var _proj = GameManager.RESEARCH_PROJECTS.get(req_research, {})
                label += " [RESEARCH]"
            else:
                label += " (need resources)"
        draw_string(font, Vector2(cx + 8, cy + 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 
            Color(0.9, 0.9, 0.95) if is_active else (Color(0.5, 0.52, 0.58) if available else Color(0.28, 0.28, 0.3)))
        cy += 34

func _draw_template_browser(font: Font):

    var panel_w: float = 350.0
    var panel_h: float = 500.0
    var px = (size.x - panel_w) * 0.5
    var py = (size.y - panel_h) * 0.5
    draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.03, 0.04, 0.07, 0.97))
    draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.3, 0.6, 0.4, 0.6), false, 2.0)
    draw_string(font, Vector2(px + 14, py + 26), "SAVED TEMPLATES", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 0.8, 0.55))
    draw_string(font, Vector2(px + panel_w - 90, py + 26), "[L] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.5, 0.45))

    _creative_template_rects.clear()
    if _creative_templates.is_empty():
        draw_string(font, Vector2(px + 14, py + 65), "No saved templates.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.42, 0.48))
        draw_string(font, Vector2(px + 14, py + 85), "Build a ship and press [T] to save.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.38, 0.42))
        return

    var row_h: float = 56.0
    var list_y = py + 44.0
    var max_visible = int((panel_h - 60) / row_h)
    var scroll_offset = int(_creative_template_scroll)
    for i in range(scroll_offset, mini(scroll_offset + max_visible, _creative_templates.size())):
        var tmpl = _creative_templates[i]
        var ry = list_y + float(i - scroll_offset) * row_h
        var row_rect = Rect2(px + 8, ry, panel_w - 16, row_h - 4)
        _creative_template_rects.append({"rect": row_rect, "idx": i})
        var is_hovered = (_creative_template_hovered == i)
        var bg_col = Color(0.08, 0.12, 0.15) if is_hovered else Color(0.05, 0.06, 0.08)
        draw_rect(row_rect, bg_col)
        draw_rect(row_rect, Color(0.2, 0.35, 0.3) if is_hovered else Color(0.15, 0.18, 0.22), false, 1.0)

        draw_string(font, Vector2(row_rect.position.x + 10, ry + 18), tmpl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.85))

        var core_id = tmpl.data.get("core_id", "")
        var core_label = DataManager.modules.get(core_id, {}).get("name", "Unknown") if core_id != "" else "Unknown"
        var mod_count = tmpl.data.get("module_count", 0)
        var info = "%s  |  %d modules" % [core_label, mod_count]
        draw_string(font, Vector2(row_rect.position.x + 10, ry + 36), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.55))

        var style = tmpl.data.get("combat_style", "standard")
        var style_label = style.to_upper().replace("_", " ")
        var style_col = Color(0.3, 0.75, 0.4) if style == "standard" else Color(0.9, 0.6, 0.2)
        var style_r = Rect2(row_rect.position.x + 10, ry + 40, 80, 14)
        draw_rect(style_r, Color(style_col, 0.15))
        draw_rect(style_r, Color(style_col, 0.4), false, 1.0)
        draw_string(font, Vector2(style_r.position.x + 4, style_r.position.y + 11), style_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, style_col)
        _creative_template_rects[_creative_template_rects.size() - 1]["style_rect"] = style_r

        var load_r = Rect2(row_rect.position.x + row_rect.size.x - 90, ry + 6, 42, 20)
        draw_rect(load_r, Color(0.1, 0.25, 0.2))
        draw_rect(load_r, Color(0.3, 0.7, 0.5), false, 1.0)
        draw_string(font, Vector2(load_r.position.x + 6, load_r.position.y + 15), "LOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.9, 0.6))

        var del_r = Rect2(row_rect.position.x + row_rect.size.x - 42, ry + 6, 32, 20)
        draw_rect(del_r, Color(0.2, 0.08, 0.08))
        draw_rect(del_r, Color(0.6, 0.25, 0.2), false, 1.0)
        draw_string(font, Vector2(del_r.position.x + 8, del_r.position.y + 15), "DEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.4, 0.35))

    if _creative_templates.size() > max_visible:
        var total = _creative_templates.size()
        var showing = mini(max_visible, total - scroll_offset)
        draw_string(font, Vector2(px + 14, py + panel_h - 16), "Showing %d-%d of %d  (scroll to browse)" % [scroll_offset + 1, scroll_offset + showing, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.38, 0.42))

func _draw_color_picker(font: Font):

    color_slot_rects.clear()
    color_picker_rects.clear()

    # Small color indicators past the module list
    var slot_x = 350.0
    var slot_y = size.y - 50
    var slot_sz: float = 24.0
    var slot_gap: float = 6.0
    var slot_colors = [GameManager.ship_color_primary, GameManager.ship_color_secondary]
    var slot_labels = ["P", "S"]

    var bg = Rect2(slot_x - 6, slot_y - 16, slot_sz * 2 + slot_gap + 12, slot_sz + 26)
    draw_rect(bg, Color(0.03, 0.04, 0.07, 0.85))
    draw_rect(bg, Color(0.15, 0.18, 0.25), false, 1.0)
    draw_string(font, Vector2(slot_x - 2, slot_y - 3), "COLORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.6))

    for si in 2:
        var sr = Rect2(slot_x + float(si) * (slot_sz + slot_gap), slot_y, slot_sz, slot_sz)
        color_slot_rects.append(sr)
        draw_rect(sr, slot_colors[si])
        if color_picker_open and editing_color_slot == si:
            draw_rect(sr, Color(1, 1, 1, 0.9), false, 2.0)
        else:
            draw_rect(sr, Color(0.2, 0.2, 0.25), false, 1.0)
        draw_string(font, Vector2(sr.position.x + 8, sr.position.y + 16), slot_labels[si], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.6))

    if not color_picker_open:
        return

    # Advanced color picker panel
    var pw: float = 220.0
    var ph: float = 250.0
    var px = slot_x
    var py = slot_y - ph - 8
    _cp_panel_rect = Rect2(px, py, pw, ph)
    draw_rect(_cp_panel_rect, Color(0.04, 0.05, 0.08, 0.95))
    draw_rect(_cp_panel_rect, Color(0.25, 0.3, 0.4), false, 1.0)

    # SV square
    var sv_x = px + 10
    var sv_y = py + 10
    var sv_sz: float = 160.0
    _cp_sv_rect = Rect2(sv_x, sv_y, sv_sz, sv_sz)
    var steps: int = 20
    var cell_sz = sv_sz / float(steps)
    for sy in steps:
        for sx in steps:
            var s_val = float(sx) / float(steps - 1)
            var v_val = 1.0 - float(sy) / float(steps - 1)
            var col = Color.from_hsv(color_picker_hue, s_val, v_val)
            draw_rect(Rect2(sv_x + float(sx) * cell_sz, sv_y + float(sy) * cell_sz, cell_sz + 1, cell_sz + 1), col)
    draw_rect(_cp_sv_rect, Color(0.3, 0.35, 0.45), false, 1.0)

    # Hue bar
    var hue_x = sv_x + sv_sz + 10
    var hue_y = sv_y
    var hue_w: float = 20.0
    var hue_h: float = sv_sz
    _cp_hue_rect = Rect2(hue_x, hue_y, hue_w, hue_h)
    var hue_steps: int = 30
    var hue_cell_h = hue_h / float(hue_steps)
    for hi in hue_steps:
        var h = float(hi) / float(hue_steps - 1)
        draw_rect(Rect2(hue_x, hue_y + float(hi) * hue_cell_h, hue_w, hue_cell_h + 1), Color.from_hsv(h, 1.0, 1.0))
    draw_rect(_cp_hue_rect, Color(0.3, 0.35, 0.45), false, 1.0)
    # Hue indicator
    var hue_ind_y = hue_y + color_picker_hue * hue_h
    draw_line(Vector2(hue_x - 2, hue_ind_y), Vector2(hue_x + hue_w + 2, hue_ind_y), Color.WHITE, 2.0)

    # Preset swatches below
    var preset_y = sv_y + sv_sz + 10
    var psw: float = 16.0
    var pgap: float = 3.0
    draw_string(font, Vector2(sv_x, preset_y + 2), "PRESETS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.6))
    preset_y += 10
    for i in color_presets.size():
        var psx = sv_x + float(i) * (psw + pgap)
        var pr = Rect2(psx, preset_y, psw, psw)
        color_picker_rects.append(pr)
        draw_rect(pr, color_presets[i])
        draw_rect(pr, Color(0, 0, 0, 0.3), false, 1.0)

    # Current color preview
    var current_col = GameManager.ship_color_primary if editing_color_slot == 0 else GameManager.ship_color_secondary
    var prev_r = Rect2(sv_x, preset_y + psw + 8, 60, 16)
    draw_rect(prev_r, current_col)
    draw_rect(prev_r, Color(0.3, 0.35, 0.45), false, 1.0)
    draw_string(font, Vector2(sv_x + 65, preset_y + psw + 20), "CURRENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.6))

func _draw_deck_tabs(font: Font):

    deck_tab_rects.clear()
    var deck_names = ["Main Deck", "Deck 2", "Deck 3", "Deck 4"]
    var tab_w: float = 100.0
    var tab_h: float = 26.0
    var tab_gap: float = 4.0
    var total_w = deck_count * (tab_w + tab_gap) - tab_gap
    var bounds = _get_hull_pixel_bounds()
    var start_x = bounds[0].x + ((bounds[1].x - bounds[0].x) - total_w) / 2.0
    var tab_y = maxf(bounds[0].y - 32, 56.0)
    for i in deck_count:
        var r = Rect2(start_x + i * (tab_w + tab_gap), tab_y, tab_w, tab_h)
        deck_tab_rects.append(r)
        var is_active = (i == current_deck)
        if is_active:
            draw_rect(r, Color(0.12, 0.16, 0.28))
            draw_rect(r, Color(0.4, 0.55, 0.9), false, 1.5)
        else:
            draw_rect(r, Color(0.06, 0.07, 0.1))
            draw_rect(r, Color(0.2, 0.22, 0.3), false, 1.0)
        var label: String
        if colony_mode:
            label = "Surface" if i == 0 else "Underground %d" % i
        else:
            label = deck_names[i] if i < deck_names.size() else "Deck " + str(i + 1)
        var col = Color(0.85, 0.88, 0.95) if is_active else Color(0.4, 0.42, 0.5)
        draw_string(font, Vector2(r.position.x + 8, r.position.y + 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)



func _stat_line(font: Font, y: float, lx: float, vx: float, label: String, value: String, color: Color):
    draw_string(font, Vector2(lx, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.53, 0.6))
    draw_string(font, Vector2(vx, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _draw_power_lines():
    var line_color = Color(0.85, 0.75, 0.2, 0.3)
    var mod_count = placed_modules.size()
    if mod_count == 0:
        return
    var module_cells_cache: Array = []
    for mod in placed_modules:
        module_cells_cache.append(_get_module_cells(mod))
    var drawn: Dictionary = {}
    for i in powered_indices:
        if i >= mod_count:
            continue
        if GameManager.get_mod_deck(placed_modules[i]) != current_deck:
            continue
        for j in powered_indices:
            if i >= j:
                continue
            if j >= mod_count:
                continue
            if GameManager.get_mod_deck(placed_modules[j]) != current_deck:
                continue
            var key = "%d_%d" % [i, j]
            if drawn.has(key):
                continue
            if _are_adjacent(module_cells_cache[i], module_cells_cache[j]):
                drawn[key] = true
                var mod_a = placed_modules[i]
                var mod_b = placed_modules[j]
                var center_a = grid_origin + HexUtil.hex_to_pixel(mod_a.get("grid_pos", Vector2i.ZERO), HEX_SIZE)
                var center_b = grid_origin + HexUtil.hex_to_pixel(mod_b.get("grid_pos", Vector2i.ZERO), HEX_SIZE)
                draw_line(center_a, center_b, line_color, 1.0)


func _get_builder_module_color(type_str: String) -> Color:
    var pri = GameManager.ship_color_primary
    var sec = GameManager.ship_color_secondary
    match type_str:
        "armor": return sec
        "conduit": return sec.lerp(pri, 0.3)
        "hallway": return sec.lerp(Color(0.45, 0.45, 0.5), 0.3)
        "airlock": return pri.lerp(Color(0.7, 0.5, 0.2), 0.2)
        "structural": return sec.lerp(Color(0.5, 0.5, 0.55), 0.3)
        "reactor": return pri.lerp(Color(0.95, 0.85, 0.3), 0.25)
        "weapon": return pri.lerp(Color(0.9, 0.3, 0.25), 0.15)
        "shield": return pri.lerp(Color(0.3, 0.5, 1.0), 0.15)
        "engine": return pri.lerp(Color(1.0, 0.6, 0.2), 0.12)
        "sensor": return pri.lerp(Color(0.25, 0.85, 0.45), 0.15)
        "cargo": return sec.lerp(Color(0.7, 0.55, 0.2), 0.3)
        "core": return pri.lerp(Color(0.7, 0.65, 0.9), 0.3)
        "quarters": return pri.lerp(Color(0.75, 0.55, 0.3), 0.2)
        "mess": return pri.lerp(Color(0.8, 0.5, 0.2), 0.2)
        "medbay": return pri.lerp(Color(0.3, 0.8, 0.4), 0.25)
        "construction_hangar": return sec.lerp(Color(0.55, 0.55, 0.6), 0.3)
        "basic_workshop": return sec.lerp(Color(0.6, 0.5, 0.35), 0.3)
        "farmers_workshop": return sec.lerp(Color(0.4, 0.65, 0.3), 0.3)
        "solar_field": return pri.lerp(Color(0.85, 0.75, 0.3), 0.2)
        "life_support": return pri.lerp(Color(0.3, 0.7, 0.7), 0.2)
        "brig": return sec.lerp(Color(0.45, 0.4, 0.4), 0.3)
        "hangar": return pri.lerp(Color(0.4, 0.5, 0.7), 0.2)
        "hydroponics": return pri.lerp(Color(0.3, 0.75, 0.3), 0.25)
        "armory": return pri.lerp(Color(0.8, 0.4, 0.15), 0.2)
        "rec_room": return pri.lerp(Color(0.6, 0.5, 0.8), 0.2)
        "bridge": return pri.lerp(Color(0.5, 0.6, 0.9), 0.25)
        "fuel_scoop": return pri.lerp(Color(0.9, 0.7, 0.2), 0.25)
        "mining": return pri.lerp(Color(0.7, 0.5, 0.3), 0.2)
        "research_lab": return pri.lerp(Color(0.3, 0.6, 0.9), 0.25)
        _: return pri



const STAT_LABELS: Dictionary = {
    "damage": "Damage", 
    "fire_rate": "Fire Rate", 
    "range": "Range", 
    "projectile_speed": "Proj Speed", 
    "shield_capacity": "Shields", 
    "recharge_rate": "Shield Regen", 
    "thrust": "Thrust", 
    "power_output": "Power Output", 
    "power_draw": "Power Draw", 
    "hull_bonus": "Hull", 
    "cargo_capacity": "Cargo", 
 
    "crew_supported": "Life Support", 
    "scan_range": "Scan Range", 
    "scan_speed": "Scan Speed", 
    "feed_capacity": "Feed Cap", 
    "food_generation": "Food/sec", 
    "damage_resist": "Damage Resist", 
    "scoop_rate": "Scoop Rate", 
    "mining_rate": "Mining Rate", 
    "mining_range": "Mining Range", 
    "boarding_power": "Boarding", 
}

func _draw_tooltip(font: Font):
    var mouse = _get_cursor_position()


    var tooltip_mod: Dictionary = {}
    var tooltip_damaged: bool = false
    if hovered_cell != Vector2i(-9999, -9999) and selected_module_id == "":
        for pm in placed_modules:
            if GameManager.get_mod_deck(pm) != current_deck:
                continue
            if hovered_cell in _get_module_cells_2d(pm):
                tooltip_mod = pm.get("data", {})
                tooltip_damaged = pm.get("hp", 1) < pm.get("max_hp", 1)
                break


    if tooltip_mod.is_empty() and hovered_palette_idx >= 0:
        var rows = _build_palette_rows()
        if hovered_palette_idx < rows.size():
            var row = rows[hovered_palette_idx]
            if row.row_type == "item":
                tooltip_mod = DataManager.modules.get(row.id, {})

    if tooltip_mod.is_empty():
        return

    var mname: String = tooltip_mod.get("name", "Unknown")
    var mtype: String = tooltip_mod.get("type", "")
    var desc: String = tooltip_mod.get("description", "")
    var tier: String = tooltip_mod.get("tier", "")
    var stats: Dictionary = tooltip_mod.get("stats", {})
    var hex_sz: int = tooltip_mod.get("hex_size", 1)


    var lines: Array = []
    lines.append({"text": mname, "color": Color(0.95, 0.95, 1.0), "size": 14})
    var type_label = mtype.capitalize()
    if tier != "":
        type_label += " (%s)" % tier.capitalize()
    type_label += "  %d hex" % hex_sz
    var tc = type_colors.get(mtype, Color.GRAY)
    lines.append({"text": type_label, "color": tc, "size": 11})
    if tooltip_damaged:
        lines.append({"text": "DAMAGED - NON-FUNCTIONAL", "color": Color(1.0, 0.3, 0.15), "size": 11})
    if desc != "":
        lines.append({"text": desc, "color": Color(0.6, 0.62, 0.68), "size": 10})

    for sk in stats:
        var label = STAT_LABELS.get(sk, sk.capitalize())
        var val = stats[sk]
        var val_str = str(val)
        if val is float:
            val_str = "%.1f" % val
        var scol = Color(0.5, 0.8, 0.5) if float(val) > 0 else Color(0.8, 0.4, 0.3)
        if float(val) > 0:
            val_str = "+" + val_str
        lines.append({"text": "%s: %s" % [label, val_str], "color": scol, "size": 10})


    var padding = Vector2(12, 8)
    var line_h: float = 16.0
    var max_w: float = 200.0
    for ln in lines:
        var tw = font.get_string_size(ln["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, ln["size"]).x + padding.x * 2
        max_w = maxf(max_w, tw)
    var total_h = padding.y * 2 + lines.size() * line_h


    var vp = size
    var tx = mouse.x + 16
    var ty = mouse.y + 16
    if tx + max_w > vp.x - 10:
        tx = mouse.x - max_w - 10
    if ty + total_h > vp.y - 10:
        ty = mouse.y - total_h - 10


    var tooltip_rect = Rect2(tx, ty, max_w, total_h)
    draw_rect(tooltip_rect, Color(0.03, 0.04, 0.07, 0.95))
    draw_rect(tooltip_rect, Color(0.3, 0.35, 0.5, 0.7), false, 1.0)


    var ly = ty + padding.y + 12
    for ln in lines:
        draw_string(font, Vector2(tx + padding.x, ly), ln["text"], HORIZONTAL_ALIGNMENT_LEFT, int(max_w - padding.x * 2), ln["size"], ln["color"])
        ly += line_h








const SUB_HEX_VIEW_SIZE: float = 80.0


const SUB_HEX_PREFABS: Dictionary = {}

var _prefab_buttons: Array = []

func _enter_sub_hex_mode(cell: Vector2i):

    var mod = _find_module_at_cell(cell, current_deck)
    if mod.is_empty():
        return
    sub_hex_mode = true
    sub_hex_cell = cell
    sub_hex_deck = current_deck
    sub_hex_module = mod
    sub_hex_hovered = -1
    selected_module_id = ""

func _find_module_at_cell(cell: Vector2i, deck: int) -> Dictionary:

    for pm in placed_modules:
        if GameManager.get_mod_deck(pm) != deck:
            continue
        var cells = _get_module_cells_2d(pm)
        if cell in cells:
            return pm
    return {}

func _draw_sub_hex_view(font: Font):

    var vp = size
    var hs = SUB_HEX_VIEW_SIZE
    var mouse = _get_cursor_position()

    var mod_data = sub_hex_module.get("data", {})
    var mod_type: String = mod_data.get("type", "structural")
    var mod_name: String = mod_data.get("name", sub_hex_module.get("id", "Unknown"))
    var filled = GameManager.get_mod_sub_footprint(sub_hex_module)
    var sub_items: Dictionary = sub_hex_module.get("sub_items", {})


    var pal_right = palette_rect.position.x + palette_rect.size.x + 10
    draw_rect(Rect2(Vector2(pal_right, 0), Vector2(vp.x - pal_right, vp.y)), Color(0.01, 0.012, 0.025, 0.92))


    var center = Vector2((pal_right + vp.x) * 0.5, vp.y * 0.5)


    var header_text = "CELL INTERIOR — %s" % mod_name
    var hw = font.get_string_size(header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
    draw_string(font, Vector2(center.x - hw * 0.5, 40), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.65, 0.75, 0.9))
    draw_string(font, Vector2(center.x - 120, 60), "Click open slot to place object — Esc/Right-click to exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.5, 0.6))


    sub_hex_hovered = -1
    for i in HexUtil.SUB_HEX_COUNT:
        var offset = HexUtil.sub_hex_pixel_offset(i, hs * 3.0)
        var sub_center = center + offset
        var corners = HexUtil.hex_corners(sub_center, hs * 0.92)

        var is_filled = i in filled
        var has_item = sub_items.has(i) or sub_items.has(str(i))
        var item_data: Dictionary = GameManager.get_mod_sub_item(sub_hex_module, i)


        if sub_center.distance_to(mouse) < hs * 0.85:
            sub_hex_hovered = i


        var fill_col: Color
        if is_filled:

            var tc = type_colors.get(mod_type, Color(0.4, 0.45, 0.5))
            fill_col = Color(tc, 0.25)
        elif has_item:

            var item_type = item_data.get("data", {}).get("type", "")
            var tc = type_colors.get(item_type, Color(0.85, 0.65, 0.45))
            fill_col = Color(tc, 0.2)
        else:

            fill_col = Color(0.08, 0.1, 0.15)


        if sub_hex_hovered == i:
            fill_col = fill_col.lightened(0.15)

        draw_colored_polygon(corners, fill_col)


        var outline_col: Color
        if is_filled:
            outline_col = Color(0.3, 0.35, 0.45, 0.5)
        elif has_item:
            outline_col = Color(0.6, 0.5, 0.35, 0.6)
        else:
            outline_col = Color(0.25, 0.35, 0.5, 0.5)
        if sub_hex_hovered == i and not is_filled:
            outline_col = Color(0.4, 0.7, 1.0, 0.8)
        for ci in corners.size():
            draw_line(corners[ci], corners[(ci + 1) % corners.size()], outline_col, 1.5)


        var label: String
        if is_filled:
            label = mod_type.capitalize() if i == 0 else "Equipment"
        elif has_item:
            label = item_data.get("data", {}).get("name", "Object")
        else:
            label = "Open Slot"
        var lw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
        draw_string(font, sub_center + Vector2( - lw * 0.5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 
            Color(0.5, 0.55, 0.65) if is_filled else Color(0.6, 0.7, 0.8))


        draw_string(font, sub_center + Vector2(hs * 0.4, - hs * 0.5), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.3, 0.35, 0.45, 0.4))


    var info_x = center.x + hs * 3.5
    var info_y: float = center.y - 100
    draw_string(font, Vector2(info_x, info_y), "Module: %s" % mod_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.85))
    info_y += 20
    draw_string(font, Vector2(info_x, info_y), "Type: %s" % mod_type.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))
    info_y += 18
    var open_count = GameManager.get_mod_open_sub_slots(sub_hex_module).size()
    draw_string(font, Vector2(info_x, info_y), "Open slots: %d" % open_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.65, 0.5))
    info_y += 18
    draw_string(font, Vector2(info_x, info_y), "Max spacers: 7", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))


    if selected_module_id != "" and sub_hex_hovered >= 0 and sub_hex_hovered not in filled:
        var sel_data = DataManager.modules.get(selected_module_id, {})
        if not sel_data.is_empty():
            info_y += 30
            draw_string(font, Vector2(info_x, info_y), "Place: %s" % sel_data.get("name", selected_module_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.85, 0.5))


    info_y += 40
    draw_string(font, Vector2(info_x, info_y), "PREFABS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
    info_y += 5
    draw_line(Vector2(info_x, info_y), Vector2(info_x + 180, info_y), Color(0.3, 0.35, 0.45, 0.5), 1.0)
    info_y += 8
    _prefab_buttons.clear()
    var any_prefab = false
    for pname in SUB_HEX_PREFABS:
        var prefab = SUB_HEX_PREFABS[pname]
        if mod_type not in prefab.get("module_types", []):
            continue
        any_prefab = true
        var btn_rect = Rect2(info_x, info_y - 12, 180, 22)
        var hov = btn_rect.has_point(mouse)
        var bg_col = Color(0.2, 0.35, 0.5, 0.4) if hov else Color(0.12, 0.15, 0.22, 0.5)
        draw_rect(btn_rect, bg_col)
        draw_rect(btn_rect, Color(0.3, 0.5, 0.7, 0.4) if hov else Color(0.25, 0.3, 0.4, 0.3), false, 1.0)
        draw_string(font, Vector2(info_x + 6, info_y), pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0) if hov else Color(0.5, 0.6, 0.75))
        info_y += 16
        draw_string(font, Vector2(info_x + 10, info_y), prefab.get("desc", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.55))
        info_y += 18
        _prefab_buttons.append({"rect": btn_rect, "name": pname})
    if not any_prefab:
        draw_string(font, Vector2(info_x, info_y), "No prefabs for this module type", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.4, 0.5))

func _sync_sub_items_to_gm():


    var gp = sub_hex_module.get("grid_pos", Vector2i(-1, -1))
    var dk = GameManager.get_mod_deck(sub_hex_module)
    var mid = sub_hex_module.get("id", "")
    for gm_mod in GameManager.ship_modules:
        if gm_mod.get("grid_pos") == gp and gm_mod.get("id") == mid and GameManager.get_mod_deck(gm_mod) == dk:
            gm_mod["sub_items"] = sub_hex_module.get("sub_items", {})
            break

func _apply_prefab(prefab_name: String):

    var prefab = SUB_HEX_PREFABS.get(prefab_name, {})
    if prefab.is_empty():
        return
    var filled = GameManager.get_mod_sub_footprint(sub_hex_module)
    var items: Dictionary = prefab.get("items", {})
    for slot in items:
        var slot_idx: int = int(slot)
        if slot_idx in filled:
            continue
        var item_id: String = items[slot]
        var item_data = DataManager.modules.get(item_id, {})
        if item_data.is_empty():
            continue
        GameManager.set_mod_sub_item(sub_hex_module, slot_idx, {"id": item_id, "data": item_data})
    _sync_sub_items_to_gm()

func _sub_hex_click(mouse: Vector2):


    for btn in _prefab_buttons:
        if btn.rect.has_point(mouse):
            _apply_prefab(btn.name)
            return

    if sub_hex_hovered < 0:
        return

    var filled = GameManager.get_mod_sub_footprint(sub_hex_module)
    if sub_hex_hovered in filled:
        return


    if selected_module_id != "":
        var sel_data = DataManager.modules.get(selected_module_id, {})
        if not sel_data.is_empty():
            var item = {
                "id": selected_module_id, 
                "data": sel_data, 
            }
            GameManager.set_mod_sub_item(sub_hex_module, sub_hex_hovered, item)
            _sync_sub_items_to_gm()
            return


    var existing = GameManager.get_mod_sub_item(sub_hex_module, sub_hex_hovered)
    if not existing.is_empty():
        GameManager.remove_mod_sub_item(sub_hex_module, sub_hex_hovered)
        _sync_sub_items_to_gm()
