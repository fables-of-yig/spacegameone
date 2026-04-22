extends Node2D

const RegIO = preload("res://Space/scripts/editor/reg/reg_io.gd")
const OverworldAtlas = preload("res://MV/scripts/overworld_atlas.gd")
const OverworldShip = preload("res://MV/scripts/overworld_ship.gd")
const OverworldBillboards = preload("res://MV/scripts/overworld_billboards.gd")
const BLOCK_SIZE: int = 16
const LAND_INTERACT_RADIUS: float = 22.0
const LANDING_DURATION: float = 0.42

signal land_requested(region_id: String)
signal exit_requested
signal hud_info_changed(region_name: String, can_land: bool, col: int, row: int, grid_w: int, grid_h: int)

var pack_id: String = ""
var realm_id: String = ""
var realm_data: Dictionary = {}
var _region_lookup: Dictionary = {}
var _region_meta_by_id: Dictionary = {}

const BASE_CAM_HEIGHT: float = 120.0
const BASE_HORIZON: float = 0.35
const BASE_FOV_SCALE: float = 1.5

var cam_height: float = BASE_CAM_HEIGHT
var horizon: float = BASE_HORIZON
var fov_scale: float = BASE_FOV_SCALE

var _sky_bg: ColorRect = null
var _ground_plane: Sprite2D = null
var _ground_material: ShaderMaterial = null
var _billboard_mgr: Node2D = null
var _ship: Node2D = null
var _screen_size: Vector2 = Vector2(640, 360)
var _near_region_id: String = ""
var _near_region_name: String = ""
var _landing_region_id: String = ""
var _landing_timer: float = 0.0
var _landing_cam_height_start: float = BASE_CAM_HEIGHT
var _landing_horizon_start: float = BASE_HORIZON
var _landing_fov_start: float = BASE_FOV_SCALE
var _last_hud_payload: Dictionary = {}
var _flight_bob_time: float = 0.0


func enter_overworld(p_pack_id: String, p_realm_id: String = "", spawn_pos: Vector2 = Vector2(-1, -1)) -> void:
    pack_id = p_pack_id
    realm_id = p_realm_id.strip_edges()
    var bundle := RegIO.load_or_init(pack_id, realm_id)
    realm_id = str(bundle.get("realm_id", realm_id))
    realm_data = bundle.get("realm", {})
    var regions_full: Variant = bundle.get("regions", {})
    if typeof(regions_full) == TYPE_DICTIONARY:
        _region_meta_by_id = regions_full
    else:
        _region_meta_by_id = {}
    _build_region_lookup()

    _screen_size = get_viewport_rect().size
    _build_scene()

    var grid_w: int = int(realm_data.get("realm_grid_cells_x", 32))
    var grid_h: int = int(realm_data.get("realm_grid_cells_y", 32))
    (_ship as OverworldShip).grid_cells_x = grid_w
    (_ship as OverworldShip).grid_cells_y = grid_h

    if spawn_pos.x >= 0:
        (_ship as OverworldShip).world_pos = spawn_pos
    else:
        var center := Vector2(float(grid_w * BLOCK_SIZE) * 0.5,
            float(grid_h * BLOCK_SIZE) * 0.5)
        (_ship as OverworldShip).world_pos = center
    _update_near_region(_ship as OverworldShip)
    _emit_hud_info(
        _near_region_name,
        not _near_region_id.is_empty(),
        (_ship as OverworldShip).grid_col(),
        (_ship as OverworldShip).grid_row(),
        grid_w,
        grid_h
    )

    var atlas_tex := OverworldAtlas.bake_ground_atlas(pack_id, realm_data)
    if _ground_material != null:
        _ground_material.set_shader_parameter("ground_atlas", atlas_tex)
        _ground_material.set_shader_parameter("atlas_size_px",
            Vector2(atlas_tex.get_width(), atlas_tex.get_height()))
        _ground_material.set_shader_parameter("cam_height", cam_height)
        _ground_material.set_shader_parameter("horizon", horizon)
        _ground_material.set_shader_parameter("fov_scale", fov_scale)

    (_billboard_mgr as OverworldBillboards).load_billboards(pack_id, realm_data)

    visible = true


func exit_overworld() -> void:
    visible = false
    for child in get_children():
        child.queue_free()
    _sky_bg = null
    _ground_plane = null
    _ground_material = null
    _billboard_mgr = null
    _ship = null
    _emit_hud_info("", false, 0, 0, 0, 0, true)


func _input(event: InputEvent) -> void:
    if not visible or _landing_timer > 0.0:
        return
    if event.is_action_pressed("liftoff"):
        exit_requested.emit()
        get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
    if not visible or _ship == null:
        return

    # Advance animated ground tiles.
    OverworldAtlas.update_animations(_delta, pack_id)

    var ship_ref := _ship as OverworldShip
    var cam_pos := ship_ref.world_pos
    var cam_angle := ship_ref.angle
    _flight_bob_time += _delta * lerpf(1.2, 3.2, ship_ref.speed_ratio())

    _update_region_cam(ship_ref, _delta)
    _update_near_region(ship_ref)
    if _landing_timer > 0.0:
        _landing_timer = maxf(0.0, _landing_timer - _delta)
        var landing_t: float = 1.0 - (_landing_timer / LANDING_DURATION if LANDING_DURATION > 0.0 else 1.0)
        cam_height = lerpf(_landing_cam_height_start, maxf(36.0, _landing_cam_height_start * 0.55), landing_t)
        horizon = lerpf(_landing_horizon_start, minf(0.52, _landing_horizon_start + 0.10), landing_t)
        fov_scale = lerpf(_landing_fov_start, maxf(0.7, _landing_fov_start * 0.92), landing_t)
        if _landing_timer <= 0.0 and _landing_region_id != "":
            land_requested.emit(_landing_region_id)
            return

    if _ground_material != null:
        _ground_material.set_shader_parameter("cam_world_pos", cam_pos)
        _ground_material.set_shader_parameter("cam_angle", cam_angle)
        _ground_material.set_shader_parameter("cam_height", cam_height)
        _ground_material.set_shader_parameter("horizon", horizon)
        _ground_material.set_shader_parameter("fov_scale", fov_scale)

    (_billboard_mgr as OverworldBillboards).update_billboards(
        cam_pos, cam_angle, cam_height, horizon, fov_scale, _screen_size, _delta)

    var ship_screen_y: float = _screen_size.y * 0.7
    var bob_strength: float = ship_ref.speed_ratio()
    var bob_offset: float = sin(_flight_bob_time) * lerpf(0.0, 5.5, bob_strength)
    if _landing_timer > 0.0:
        var ship_drop_t: float = 1.0 - (_landing_timer / LANDING_DURATION if LANDING_DURATION > 0.0 else 1.0)
        ship_screen_y = lerpf(ship_screen_y, _screen_size.y * 0.82, ship_drop_t)
        bob_offset = lerpf(bob_offset, 0.0, ship_drop_t)
    _ship.position = Vector2(_screen_size.x * 0.5, ship_screen_y + bob_offset)

    var col := ship_ref.grid_col()
    var row := ship_ref.grid_row()
    var region_name := _near_region_name
    var can_land := not _near_region_id.is_empty() and _landing_timer <= 0.0
    _emit_hud_info(region_name, can_land, col, row, ship_ref.grid_cells_x, ship_ref.grid_cells_y)

    if _landing_timer <= 0.0 and Input.is_action_just_pressed("interact") and not _near_region_id.is_empty():
        _start_landing(_near_region_id)


func _build_scene() -> void:
    _sky_bg = ColorRect.new()
    _sky_bg.size = _screen_size
    _sky_bg.color = Color(0.04, 0.06, 0.14, 1.0)
    add_child(_sky_bg)

    _build_sky_gradient()

    var shader := load("res://MV/shaders/mode7_ground.gdshader") as Shader
    _ground_material = ShaderMaterial.new()
    _ground_material.shader = shader

    _ground_plane = Sprite2D.new()
    _ground_plane.centered = false
    _ground_plane.position = Vector2.ZERO
    var placeholder_img := Image.create(int(_screen_size.x), int(_screen_size.y),
        false, Image.FORMAT_RGBA8)
    placeholder_img.fill(Color(1, 1, 1, 1))
    _ground_plane.texture = ImageTexture.create_from_image(placeholder_img)
    _ground_plane.material = _ground_material
    add_child(_ground_plane)

    _billboard_mgr = OverworldBillboards.new()
    add_child(_billboard_mgr)

    _ship = OverworldShip.new()
    add_child(_ship)


func _build_sky_gradient() -> void:
    var grad_h: int = int(_screen_size.y * horizon)
    if grad_h <= 0:
        return
    var img := Image.create(1, grad_h, false, Image.FORMAT_RGBA8)
    var top_col := Color(0.02, 0.03, 0.08, 1.0)
    var bot_col := Color(0.08, 0.12, 0.22, 1.0)
    for y in grad_h:
        var t := float(y) / float(grad_h)
        img.set_pixel(0, y, top_col.lerp(bot_col, t))
    var tex := ImageTexture.create_from_image(img)
    var grad_rect := TextureRect.new()
    grad_rect.texture = tex
    grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
    grad_rect.size = Vector2(_screen_size.x, float(grad_h))
    grad_rect.position = Vector2.ZERO
    add_child(grad_rect)


func _build_region_lookup() -> void:
    _region_lookup.clear()
    var regions_v: Variant = realm_data.get("regions", [])
    if typeof(regions_v) != TYPE_ARRAY:
        return
    for entry_v in regions_v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var col: int = int(entry.get("col", 0))
        var row: int = int(entry.get("row", 0))
        _region_lookup["%d,%d" % [col, row]] = entry


func _update_near_region(ship_ref: OverworldShip) -> void:
    _near_region_id = ""
    _near_region_name = ""
    var nearest_region: Dictionary = {}
    var nearest_distance: float = LAND_INTERACT_RADIUS
    var max_x: float = float(ship_ref.grid_cells_x * BLOCK_SIZE)
    var max_y: float = float(ship_ref.grid_cells_y * BLOCK_SIZE)
    for region_v in _region_lookup.values():
        if typeof(region_v) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_v
        var center := Vector2(
            (float(int(region.get("col", 0))) + 0.5) * BLOCK_SIZE,
            (float(int(region.get("row", 0))) + 0.5) * BLOCK_SIZE
        )
        var delta := _wrapped_world_delta(ship_ref.world_pos, center, max_x, max_y)
        var dist := delta.length()
        if dist > nearest_distance:
            continue
        nearest_distance = dist
        nearest_region = region
    if nearest_region.is_empty():
        return
    _near_region_id = str(nearest_region.get("id", "")).strip_edges()
    _near_region_name = str(nearest_region.get("name", _near_region_id)).strip_edges()


func _wrapped_world_delta(from_pos: Vector2, to_pos: Vector2, max_x: float, max_y: float) -> Vector2:
    var dx: float = to_pos.x - from_pos.x
    var dy: float = to_pos.y - from_pos.y
    if max_x > 0.0 and absf(dx) > max_x * 0.5:
        dx -= signf(dx) * max_x
    if max_y > 0.0 and absf(dy) > max_y * 0.5:
        dy -= signf(dy) * max_y
    return Vector2(dx, dy)


func _start_landing(region_id: String) -> void:
    var trimmed_region_id: String = region_id.strip_edges()
    if trimmed_region_id.is_empty() or _ship == null:
        return
    _landing_region_id = trimmed_region_id
    _landing_timer = LANDING_DURATION
    _landing_cam_height_start = cam_height
    _landing_horizon_start = horizon
    _landing_fov_start = fov_scale
    var ship_ref := _ship as OverworldShip
    if ship_ref != null:
        ship_ref.controls_enabled = false


func _update_region_cam(ship_ref: OverworldShip, delta: float) -> void:
    var col: int = ship_ref.grid_col()
    var row: int = ship_ref.grid_row()
    var key: String = "%d,%d" % [col, row]

    var target_h: float = BASE_CAM_HEIGHT
    var target_horizon: float = BASE_HORIZON
    var target_fov: float = BASE_FOV_SCALE

    if _region_lookup.has(key):
        var entry: Dictionary = _region_lookup[key]
        var region_id: String = str(entry.get("id", ""))
        var meta_v: Variant = _region_meta_by_id.get(region_id, null)
        if typeof(meta_v) == TYPE_DICTIONARY:
            var meta: Dictionary = meta_v
            target_h = float(meta.get("cam_height", BASE_CAM_HEIGHT))
            target_horizon = float(meta.get("horizon", BASE_HORIZON))
            target_fov = float(meta.get("fov_scale", BASE_FOV_SCALE))

    # Smooth the transition so crossing region boundaries doesn't snap.
    var lerp_rate: float = clampf(delta * 4.0, 0.0, 1.0)
    cam_height = lerpf(cam_height, target_h, lerp_rate)
    horizon = lerpf(horizon, target_horizon, lerp_rate)
    fov_scale = lerpf(fov_scale, target_fov, lerp_rate)


func _emit_hud_info(
    region_name: String,
    can_land: bool,
    col: int,
    row: int,
    grid_w: int,
    grid_h: int,
    force: bool = false
) -> void:
    var payload := {
        "region_name": region_name,
        "can_land": can_land,
        "col": col,
        "row": row,
        "grid_w": grid_w,
        "grid_h": grid_h,
    }
    if not force and payload == _last_hud_payload:
        return
    _last_hud_payload = payload
    hud_info_changed.emit(region_name, can_land, col, row, grid_w, grid_h)
