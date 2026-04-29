class_name MvWeatherOverlay
extends Control

const MAX_PARTICLES: int = 220
const MAX_SPLASHES: int = 56
const BLOCK_SIZE: int = 16

const BT_SLOPE: int = 0x1
const BT_SOLID: int = 0x8
const BT_DOOR: int = 0x9
const BT_SPIKE: int = 0xA
const BT_CRUMBLE: int = 0xB
const BT_SHOOT_SOLID: int = 0xC
const BT_BOMB_SOLID: int = 0xE
const BT_GRAPPLE_BLOCK: int = 0xF

const RAIN_DIRECTION: Vector2 = Vector2(-0.119145, 0.992877)
const RAIN_BASE_SPEED: float = 520.0
const SNOW_BASE_SPEED: float = 42.0
const RAIN_SPAWN_OVERSCAN: float = 56.0
const SNOW_SPAWN_OVERSCAN: float = 20.0
const SPLASH_GRAVITY: float = 220.0

var preset: String = "none"
var tint: Color = Color(0.81, 0.91, 1.0, 1.0)
var intensity: float = 0.7
var speed_scale: float = 1.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _particles: Array = []
var _splashes: Array = []


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(PRESET_FULL_RECT)
    _rng.randomize()
    visible = false
    set_process(true)


func configure(data: Dictionary) -> void:
    var next_preset := str(data.get("preset", "none")).strip_edges().to_lower()
    if next_preset != "rain" and next_preset != "snow":
        next_preset = "none"
    preset = next_preset
    var color_v: Variant = data.get("color", tint)
    if typeof(color_v) == TYPE_COLOR:
        tint = color_v
    else:
        tint = Color.from_string(str(color_v), Color(0.81, 0.91, 1.0, 1.0))
    intensity = clampf(float(data.get("intensity", intensity)), 0.0, 2.0)
    speed_scale = clampf(float(data.get("speed", speed_scale)), 0.0, 4.0)
    visible = preset != "none" and intensity > 0.0
    _rebuild_particles()
    if preset != "rain":
        _splashes.clear()
    queue_redraw()


func clear_weather() -> void:
    preset = "none"
    _particles.clear()
    _splashes.clear()
    visible = false
    queue_redraw()


func _process(delta: float) -> void:
    size = get_viewport_rect().size
    if not visible:
        if not _splashes.is_empty():
            _splashes.clear()
            queue_redraw()
        return

    _ensure_particle_count()
    var width := maxf(1.0, size.x)
    var height := maxf(1.0, size.y)
    var cam: Camera2D = get_viewport().get_camera_2d()
    var cam_center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
    var cam_zoom := cam.zoom if cam != null else Vector2.ONE
    var player_rect := _current_player_hurtbox_rect()
    var room_mgr: Node = MvGame.room_manager
    var room_info: Dictionary = room_mgr.current_room() if room_mgr != null and room_mgr.has_method("current_room") else {}

    for i in range(_particles.size()):
        var particle_v: Variant = _particles[i]
        if typeof(particle_v) != TYPE_DICTIONARY:
            continue
        var particle: Dictionary = particle_v
        var prev_screen := Vector2(float(particle.get("x", 0.0)), float(particle.get("y", 0.0)))

        if preset == "rain":
            var next_screen := prev_screen + _rain_velocity(particle) * speed_scale * delta
            particle["x"] = next_screen.x
            particle["y"] = next_screen.y
            var impact := _find_rain_impact(prev_screen, next_screen, player_rect, room_info, room_mgr, cam_center, cam_zoom, size)
            if bool(impact.get("hit", false)):
                _spawn_splash(Vector2(float(impact.get("screen_x", next_screen.x)), float(impact.get("screen_y", next_screen.y))), bool(impact.get("player", false)))
                particle = _spawn_particle(-_rng.randf_range(8.0, 56.0), width)
            elif next_screen.y > height + 28.0 or next_screen.x < -RAIN_SPAWN_OVERSCAN or next_screen.x > width + RAIN_SPAWN_OVERSCAN:
                particle = _spawn_particle(-_rng.randf_range(8.0, 56.0), width)
        else:
            particle["x"] = prev_screen.x + (float(particle.get("drift", 0.0))) * speed_scale * delta
            particle["y"] = prev_screen.y + (SNOW_BASE_SPEED + float(particle.get("vy", 0.0))) * speed_scale * delta
            if float(particle["y"]) > height + 24.0 or float(particle["x"]) < -SNOW_SPAWN_OVERSCAN:
                particle = _spawn_particle(-_rng.randf_range(4.0, 40.0), width)
        _particles[i] = particle

    _update_splashes(delta)
    queue_redraw()


func _draw() -> void:
    if not visible:
        return
    var base_alpha := clampf(0.34 + intensity * 0.18, 0.16, 0.82)
    for particle_v in _particles:
        if typeof(particle_v) != TYPE_DICTIONARY:
            continue
        var particle: Dictionary = particle_v
        var alpha := base_alpha * float(particle.get("alpha", 1.0))
        var color := Color(tint.r, tint.g, tint.b, tint.a * alpha)
        var pos := Vector2(float(particle.get("x", 0.0)), float(particle.get("y", 0.0)))
        if preset == "rain":
            var length := float(particle.get("length", 10.0))
            var thickness := float(particle.get("thickness", 1.0))
            var tail := pos - RAIN_DIRECTION * length
            draw_line(tail, pos, color, thickness, false)
        elif preset == "snow":
            draw_circle(pos, float(particle.get("radius", 1.8)), color)

    for splash_v in _splashes:
        if typeof(splash_v) != TYPE_DICTIONARY:
            continue
        var splash: Dictionary = splash_v
        var alpha := clampf(1.0 - float(splash.get("age", 0.0)) / maxf(0.01, float(splash.get("life", 0.18))), 0.0, 1.0)
        var color := Color(tint.r, tint.g, tint.b, tint.a * alpha * 0.85)
        var pos := Vector2(float(splash.get("x", 0.0)), float(splash.get("y", 0.0)))
        var radius := float(splash.get("radius", 2.5))
        draw_line(pos + Vector2(-radius, 0.0), pos + Vector2(radius, 0.0), color, 1.0, true)
        draw_line(pos, pos + Vector2(-radius * 0.35, -radius * 0.55), color, 1.0, true)
        draw_line(pos, pos + Vector2(radius * 0.35, -radius * 0.55), color, 1.0, true)
        var droplets_v: Variant = splash.get("droplets", [])
        if typeof(droplets_v) != TYPE_ARRAY:
            continue
        for drop_v in droplets_v:
            if typeof(drop_v) != TYPE_DICTIONARY:
                continue
            var drop: Dictionary = drop_v
            draw_circle(
                pos + Vector2(float(drop.get("x", 0.0)), float(drop.get("y", 0.0))),
                float(drop.get("radius", 0.8)),
                color
            )


func _target_particle_count() -> int:
    if preset == "none":
        return 0
    var base := 78 if preset == "rain" else 54
    return clampi(int(round(float(base) * intensity)), 8, MAX_PARTICLES)


func _ensure_particle_count() -> void:
    var wanted := _target_particle_count()
    var width := maxf(1.0, size.x)
    while _particles.size() < wanted:
        _particles.append(_spawn_particle(_rng.randf_range(-16.0, size.y + 16.0), width))
    while _particles.size() > wanted:
        _particles.remove_at(_particles.size() - 1)


func _rebuild_particles() -> void:
    _particles.clear()
    _ensure_particle_count()


func _spawn_particle(start_y: float, width: float) -> Dictionary:
    if preset == "rain":
        return {
            "x": _rng.randf_range(-8.0, width + RAIN_SPAWN_OVERSCAN),
            "y": start_y,
            "speed": _rng.randf_range(RAIN_BASE_SPEED * 0.82, RAIN_BASE_SPEED * 1.18),
            "length": _rng.randf_range(4.0, 5.4),
            "thickness": _rng.randf_range(1.0, 1.35),
            "alpha": _rng.randf_range(0.45, 0.82),
        }
    return {
        "x": _rng.randf_range(-20.0, width + 20.0),
        "y": start_y,
        "vy": _rng.randf_range(-8.0, 26.0),
        "drift": _rng.randf_range(-9.0, 6.0),
        "radius": _rng.randf_range(1.0, 2.5),
        "alpha": _rng.randf_range(0.5, 1.0),
    }


func _rain_velocity(particle: Dictionary) -> Vector2:
    return RAIN_DIRECTION * float(particle.get("speed", RAIN_BASE_SPEED))


func _current_player_hurtbox_rect() -> Rect2:
    for player in get_tree().get_nodes_in_group("mv_player"):
        if not is_instance_valid(player):
            continue
        if player.has_method("hurtbox_world_rect"):
            var rect_v: Variant = player.call("hurtbox_world_rect")
            if typeof(rect_v) == TYPE_RECT2:
                return rect_v
    return Rect2()


func _find_rain_impact(prev_screen: Vector2, next_screen: Vector2, player_rect: Rect2,
        room_info: Dictionary, room_mgr: Node, cam_center: Vector2, cam_zoom: Vector2,
        viewport_size: Vector2) -> Dictionary:
    var travel := next_screen - prev_screen
    var steps := maxi(1, int(ceil(travel.length() / 4.0)))
    for step in range(1, steps + 1):
        var t := float(step) / float(steps)
        var screen_point := prev_screen.lerp(next_screen, t)
        var world_point := _screen_to_world(screen_point, cam_center, cam_zoom, viewport_size)
        if player_rect.size.x > 0.0 and player_rect.size.y > 0.0 and player_rect.has_point(world_point):
            return {
                "hit": true,
                "player": true,
                "screen_x": screen_point.x,
                "screen_y": screen_point.y,
            }
        if _rain_hits_world(world_point, room_info, room_mgr):
            return {
                "hit": true,
                "player": false,
                "screen_x": screen_point.x,
                "screen_y": screen_point.y,
            }
    return {}


func _rain_hits_world(world_point: Vector2, room_info: Dictionary, room_mgr: Node) -> bool:
    if room_info.is_empty():
        return false
    var collision_v: Variant = room_info.get("collision", [])
    if typeof(collision_v) != TYPE_ARRAY:
        return false
    var collision: Array = collision_v
    var row := int(floor(world_point.y / BLOCK_SIZE))
    var col := int(floor(world_point.x / BLOCK_SIZE))
    if row < 0 or row >= collision.size():
        return false
    var row_v: Variant = collision[row]
    if typeof(row_v) != TYPE_ARRAY:
        return false
    var cols: Array = row_v
    if col < 0 or col >= cols.size():
        return false
    var block := int(cols[col])
    if block == BT_SLOPE and room_mgr != null and room_mgr.has_method("try_get_slope_floor"):
        var slope_v: Variant = room_mgr.call("try_get_slope_floor", world_point.x, world_point.y)
        if typeof(slope_v) == TYPE_DICTIONARY:
            var slope: Dictionary = slope_v
            return bool(slope.get("hit", false)) and world_point.y >= float(slope.get("floor_y", world_point.y + 1.0))
        return false
    return _is_rain_blocking_block(block)


func _is_rain_blocking_block(block: int) -> bool:
    return block == BT_SOLID \
        or block == BT_DOOR \
        or block == BT_SPIKE \
        or block == BT_CRUMBLE \
        or block == BT_SHOOT_SOLID \
        or block == BT_BOMB_SOLID \
        or block == BT_GRAPPLE_BLOCK


func _screen_to_world(screen_point: Vector2, cam_center: Vector2, cam_zoom: Vector2,
        viewport_size: Vector2) -> Vector2:
    return cam_center + Vector2(
        (screen_point.x - viewport_size.x * 0.5) * cam_zoom.x,
        (screen_point.y - viewport_size.y * 0.5) * cam_zoom.y
    )


func _spawn_splash(screen_point: Vector2, hit_player: bool) -> void:
    var splash := {
        "x": screen_point.x,
        "y": screen_point.y,
        "age": 0.0,
        "life": _rng.randf_range(0.08, 0.14),
        "radius": _rng.randf_range(0.9, 1.5) if not hit_player else _rng.randf_range(0.75, 1.2),
        "droplets": [],
    }
    var droplets: Array = []
    var burst_count := 1 if hit_player else 2
    for i in range(burst_count):
        droplets.append({
            "x": 0.0,
            "y": 0.0,
            "vx": _rng.randf_range(-9.0, 9.0),
            "vy": _rng.randf_range(-16.0, -7.0) if not hit_player else _rng.randf_range(-12.0, -5.0),
            "radius": _rng.randf_range(0.4, 0.75),
        })
    splash["droplets"] = droplets
    _splashes.append(splash)
    while _splashes.size() > MAX_SPLASHES:
        _splashes.remove_at(0)


func _update_splashes(delta: float) -> void:
    for i in range(_splashes.size() - 1, -1, -1):
        var splash_v: Variant = _splashes[i]
        if typeof(splash_v) != TYPE_DICTIONARY:
            _splashes.remove_at(i)
            continue
        var splash: Dictionary = splash_v
        splash["age"] = float(splash.get("age", 0.0)) + delta
        if float(splash.get("age", 0.0)) >= float(splash.get("life", 0.18)):
            _splashes.remove_at(i)
            continue
        var next_droplets: Array = []
        var droplets_v: Variant = splash.get("droplets", [])
        if typeof(droplets_v) == TYPE_ARRAY:
            for drop_v in droplets_v:
                if typeof(drop_v) != TYPE_DICTIONARY:
                    continue
                var drop: Dictionary = drop_v
                drop["x"] = float(drop.get("x", 0.0)) + float(drop.get("vx", 0.0)) * delta
                drop["y"] = float(drop.get("y", 0.0)) + float(drop.get("vy", 0.0)) * delta
                drop["vy"] = float(drop.get("vy", 0.0)) + SPLASH_GRAVITY * delta
                next_droplets.append(drop)
        splash["droplets"] = next_droplets
        _splashes[i] = splash
