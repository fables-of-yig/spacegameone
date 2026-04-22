extends Area2D




@export var speed: float = 800.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0
var shield_pierce: float = 0.0

var source: String = "player"
var direction: Vector2 = Vector2.RIGHT
var base_velocity: Vector2 = Vector2.ZERO
var proj_color: Color = Color(0.3, 1.0, 0.5)
var proj_size: float = 3.0
var age: float = 0.0


var proj_type: String = "bolt"


var homing_target: Node2D = null
var homing_strength: float = 3.0
var splash_radius: float = 0.0


var mac_knockback: float = 0.0
var _pierced_targets: Dictionary = {}


var volley_ticks: int = 0
var _volley_tick_timer: float = 0.0
var _volley_ticks_dealt: int = 0
var _volley_hit_targets: Dictionary = {}


var sprite_sheet: Texture2D = null
var sprite_frames: int = 4
var sprite_fps: float = 10.0
var sprite_scale: float = 1.0
var sprite_flip_h: bool = false

var smoke_trail: Array[Dictionary] = []
const SMOKE_MAX: int = 20
var _smoke_idx: int = 0
var max_missile_speed: float = 0.0


const TRAIL_MAX: int = 6
var trail: Array[Vector2] = []
var _trail_idx: int = 0
var _trail_count: int = 0


static var _explosion_script: GDScript = preload("res://Space/scripts/combat/explosion.gd")
static var _projectile_scene: PackedScene
static var _spr_hornet_child: Texture2D = preload("res://Space/art/projectiles/HornetSecondary.png")

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("projectiles")
    direction = Vector2.from_angle(rotation)

    if source == "enemy" and proj_type == "bolt":
        proj_color = Color(1.0, 0.3, 0.3)
    elif source == "patrol" and proj_type == "bolt":
        proj_color = Color(0.8, 0.3, 0.3)


    var shape = CircleShape2D.new()
    match proj_type:
        "hornet_volley":
            shape.radius = proj_size * 3.0
        "mac":
            shape.radius = proj_size * 2.0
        "bolt":
            shape.radius = proj_size
        _:
            shape.radius = proj_size * 1.5
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)

    if proj_type == "missile":
        max_missile_speed = speed * 2.0

    if proj_type == "railgun":
        lifetime = 1.5


    var max_trail = 20 if proj_type == "railgun" else TRAIL_MAX
    trail.resize(max_trail)
    trail.fill(global_position)
    if proj_type == "missile":
        smoke_trail.resize(SMOKE_MAX)
        for i in SMOKE_MAX:
            smoke_trail[i] = {"pos": global_position, "age": 999.0, "size": 3.0}


    if proj_type != "hornet_volley":
        area_entered.connect(_on_area_entered)
    get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float):
    age += delta


    var cam = get_viewport().get_camera_2d()
    if cam:
        var cam_dist_sq = global_position.distance_squared_to(cam.global_position)
        visible = cam_dist_sq < 16000000.0


    if proj_type == "missile" and homing_target and is_instance_valid(homing_target):
        var to_target = (homing_target.global_position - global_position).normalized()
        var current_angle = direction.angle()
        var target_angle = to_target.angle()
        var new_angle = lerp_angle(current_angle, target_angle, homing_strength * delta)
        direction = Vector2.from_angle(new_angle)
        rotation = new_angle

        speed = minf(speed + 80.0 * delta, max_missile_speed)

    if proj_type == "hornet_child":
        if homing_target and is_instance_valid(homing_target):
            var to_t = (homing_target.global_position - global_position).normalized()
            var facing_dot = direction.dot(to_t)
            if facing_dot < 0.2:
                # Target is behind or far to the side — switch to something ahead
                homing_target = _find_forward_enemy()
            if homing_target and is_instance_valid(homing_target):
                var to_h = (homing_target.global_position - global_position).normalized()
                var ca = direction.angle()
                var ta = to_h.angle()
                var na = lerp_angle(ca, ta, homing_strength * delta)
                direction = Vector2.from_angle(na)
                rotation = na
        else:
            homing_target = _find_forward_enemy()

    position += (direction * speed + base_velocity) * delta


    trail[_trail_idx] = global_position
    _trail_idx = (_trail_idx + 1) % trail.size()
    _trail_count = mini(_trail_count + 1, trail.size())


    if proj_type == "missile":
        var entry = smoke_trail[_smoke_idx]
        entry["pos"] = global_position
        entry["age"] = 0.0
        entry["size"] = randf_range(2.0, 4.5)
        _smoke_idx = (_smoke_idx + 1) % SMOKE_MAX
        for s in smoke_trail:
            s["age"] += delta


    if proj_type == "hornet_volley" and volley_ticks > 0:
        var tick_interval = lifetime / float(volley_ticks)
        _volley_tick_timer += delta
        if _volley_tick_timer >= tick_interval and _volley_ticks_dealt < volley_ticks:
            _volley_tick_timer -= tick_interval
            _volley_ticks_dealt += 1
            _hornet_volley_tick()

func _hornet_volley_tick():
    var frame = Engine.get_physics_frames()
    var target_group = "enemies" if source in ["player", "patrol"] else "player"
    for area in get_overlapping_areas():
        if not is_instance_valid(area):
            continue
        if not area.is_in_group(target_group):
            continue
        var iid = area.get_instance_id()
        if _volley_hit_targets.get(iid, -1) == frame:
            continue
        _volley_hit_targets[iid] = frame
        if area.has_method("take_damage"):
            if target_group == "player":
                area.take_damage(damage, shield_pierce, global_position)
            else:
                area.take_damage(damage, 0.0, global_position)

func _on_area_entered(area: Area2D):
    var iid = area.get_instance_id()
    if _pierced_targets.has(iid):
        return
    if source == "player" and area.is_in_group("enemies"):
        if area.has_method("take_damage"):
            area.take_damage(damage, 0.0, global_position)
        _on_impact_effects(area)
        if proj_type == "railgun" and "health" in area and area.health <= 0:
            _pierced_targets[iid] = true
            damage *= 0.7
            return
        set_deferred("monitoring", false)
        queue_free()
    elif source == "player" and area.is_in_group("station_entities"):
        if area.has_method("take_damage"):
            area.take_damage(damage, 0.0, global_position)
        _on_impact_effects(area)
        set_deferred("monitoring", false)
        queue_free()
    elif source == "enemy" and area.is_in_group("player"):
        if area.has_method("take_damage"):
            area.take_damage(damage, shield_pierce, global_position)
        _on_impact_effects(area)
        set_deferred("monitoring", false)
        queue_free()
    elif source == "patrol" and area.is_in_group("enemies"):
        if area.has_method("take_damage"):
            area.take_damage(damage, 0.0, global_position)
        _on_impact_effects(area)
        if proj_type == "railgun" and "health" in area and area.health <= 0:
            _pierced_targets[iid] = true
            damage *= 0.7
            return
        set_deferred("monitoring", false)
        queue_free()

func _on_impact_effects(hit_area: Area2D):
    match proj_type:
        "missile":
            _missile_explode()
        "railgun":
            var explosion = Node2D.new()
            explosion.set_script(_explosion_script)
            explosion.global_position = global_position
            explosion.setup(proj_color, 12)
            get_tree().current_scene.add_child(explosion)
        "mac":
            _mac_explode(hit_area)
        "hornet":
            _hornet_explode()
        "hornet_child":
            var child_exp = Node2D.new()
            child_exp.set_script(_explosion_script)
            child_exp.global_position = global_position
            child_exp.setup(Color(1.0, 0.5, 0.15), 6)
            get_tree().current_scene.add_child(child_exp)

func _hornet_explode():
    var explosion = Node2D.new()
    explosion.set_script(_explosion_script)
    explosion.global_position = global_position
    explosion.setup(Color(1.0, 0.7, 0.2), 15)
    explosion.shockwave_speed = 400.0
    get_tree().current_scene.add_child(explosion)

    var target_group = "enemies" if source in ["player", "patrol"] else "player"
    var targets = get_tree().get_nodes_in_group(target_group)
    var child_speed = speed * 3.0
    var child_damage = damage * 0.5

    for i in 8:
        var angle = float(i) / 8.0 * TAU
        var child_dir = Vector2.from_angle(angle)

        var best_target: Node2D = null
        var best_dot: float = 0.0
        for t in targets:
            if not is_instance_valid(t):
                continue
            var to_t = (t.global_position - global_position).normalized()
            var dot = child_dir.dot(to_t)
            if dot > best_dot:
                best_dot = dot
                best_target = t

        if not _projectile_scene:
            _projectile_scene = load("res://Space/scenes/projectile.tscn")
        var child = _projectile_scene.instantiate()
        child.global_position = global_position + child_dir * 15.0
        child.rotation = angle
        child.speed = child_speed
        child.damage = child_damage
        child.lifetime = 6.0
        child.source = source
        child.proj_type = "hornet_child"
        child.proj_color = Color(1.0, 0.5, 0.15)
        child.proj_size = 2.0
        child.homing_target = best_target
        child.homing_strength = 4.0
        child.shield_pierce = shield_pierce
        child.sprite_sheet = _spr_hornet_child
        child.sprite_scale = 0.72
        child.sprite_flip_h = false
        get_tree().current_scene.add_child.call_deferred(child)

    AudioManager.play_sfx("heavy_shot", 0.7, 0.05)

func _find_forward_enemy() -> Node2D:
    var group = "enemies" if source in ["player", "patrol"] else "player"
    var targets = get_tree().get_nodes_in_group(group)
    # Score = dot product * distance falloff — prefer close targets ahead of us
    var best: Node2D = null
    var best_score: float = -INF
    for t in targets:
        if not is_instance_valid(t):
            continue
        var to_t = (t.global_position - global_position)
        var dist = to_t.length()
        if dist < 1.0:
            continue
        var dot = direction.dot(to_t / dist)
        if dot < 0.0:
            continue
        # Favor close + ahead: dot [0-1] / distance gives higher scores for near+forward
        var score = dot / (dist * 0.001 + 0.1)
        if score > best_score:
            best_score = score
            best = t
    # Fallback: if nothing forward, take nearest regardless
    if not best:
        return _find_nearest_enemy()
    return best

func _find_nearest_enemy() -> Node2D:
    var group = "enemies" if source in ["player", "patrol"] else "player"
    var targets = get_tree().get_nodes_in_group(group)
    var best: Node2D = null
    var best_dist: float = INF
    for t in targets:
        if not is_instance_valid(t):
            continue
        var d = global_position.distance_to(t.global_position)
        if d < best_dist:
            best_dist = d
            best = t
    return best

func _missile_explode():

    var explosion = Node2D.new()
    explosion.set_script(_explosion_script)
    explosion.global_position = global_position
    explosion.setup(proj_color, 18)
    explosion.shockwave_speed = 500.0
    get_tree().current_scene.add_child(explosion)


    if splash_radius > 0:
        var group = "enemies" if source in ["player", "patrol"] else "player"
        var targets = get_tree().get_nodes_in_group(group)
        for t in targets:
            if not is_instance_valid(t) or t == self:
                continue
            var dist = t.global_position.distance_to(global_position)
            if dist < splash_radius:
                var falloff = 1.0 - (dist / splash_radius)
                var splash_dmg = damage * 0.5 * falloff
                if t.has_method("take_damage"):
                    if group == "player":
                        t.take_damage(splash_dmg, shield_pierce, global_position)
                    else:
                        t.take_damage(splash_dmg, 0.0, global_position)

    AudioManager.play_sfx("heavy_shot", 0.6, 0.05)

func _mac_explode(hit_area: Area2D):

    var exp1 = Node2D.new()
    exp1.set_script(_explosion_script)
    exp1.global_position = global_position
    exp1.setup(Color(1.0, 0.6, 0.1), 25)
    exp1.shockwave_speed = 600.0
    get_tree().current_scene.add_child(exp1)

    var exp2 = Node2D.new()
    exp2.set_script(_explosion_script)
    exp2.global_position = global_position
    exp2.setup(Color(1.0, 0.9, 0.7), 15)
    get_tree().current_scene.add_child(exp2)


    if mac_knockback > 0 and is_instance_valid(hit_area):
        var push_dir = (hit_area.global_position - global_position).normalized()
        if "knockback_vel" in hit_area:
            hit_area.knockback_vel += push_dir * mac_knockback
        elif "velocity" in hit_area:
            hit_area.velocity += push_dir * mac_knockback


    if splash_radius > 0:
        var group = "enemies" if source in ["player", "patrol"] else "player"
        var targets = get_tree().get_nodes_in_group(group)
        for t in targets:
            if not is_instance_valid(t) or t == hit_area or t == self:
                continue
            var dist = t.global_position.distance_to(global_position)
            if dist < splash_radius:
                var falloff = 1.0 - (dist / splash_radius)
                var splash_dmg = damage * 0.4 * falloff
                if t.has_method("take_damage"):
                    if group == "player":
                        t.take_damage(splash_dmg, shield_pierce, global_position)
                    else:
                        t.take_damage(splash_dmg, 0.0, global_position)

                if mac_knockback > 0:
                    var push_dir = (t.global_position - global_position).normalized()
                    if "knockback_vel" in t:
                        t.knockback_vel += push_dir * mac_knockback * 0.5 * falloff
                    elif "velocity" in t:
                        t.velocity += push_dir * mac_knockback * 0.5 * falloff

    AudioManager.play_sfx("heavy_shot", 0.9, 0.0)

func _draw():
    if sprite_sheet:
        _draw_sprite()
        return
    match proj_type:
        "missile":
            _draw_missile()
        "railgun":
            _draw_railgun()
        "mac":
            _draw_mac()
        "hornet_volley":
            _draw_hornet_volley()
        "hornet":
            _draw_hornet()
        "hornet_child":
            _draw_hornet_child()
        _:
            _draw_bolt()

func _draw_sprite():
    var frame = int(age * sprite_fps) % sprite_frames
    var tex_w = sprite_sheet.get_width()
    var tex_h = sprite_sheet.get_height()
    @warning_ignore("integer_division")
    var fw = tex_w / sprite_frames
    var fh = tex_h
    var src = Rect2(frame * fw, 0, fw, fh)
    var target_w = fw * sprite_scale
    var target_h = fh * sprite_scale
    var dst: Rect2
    if sprite_flip_h:
        dst = Rect2(target_w * 0.5, -target_h * 0.5, -target_w, target_h)
    else:
        dst = Rect2(-target_w * 0.5, -target_h * 0.5, target_w, target_h)
    draw_texture_rect_region(sprite_sheet, dst, src)

func _draw_hornet():
    var dir_n = Vector2.RIGHT
    var perp = Vector2(-dir_n.y, dir_n.x)
    var s = proj_size
    var trail_len = s * 10.0
    var trail_end = -dir_n * trail_len
    draw_colored_polygon(PackedVector2Array([
        perp * s * 0.8, trail_end + perp * s * 0.2,
        trail_end - perp * s * 0.2, -perp * s * 0.8,
    ]), Color(1.0, 0.5, 0.1, 0.2))
    draw_colored_polygon(PackedVector2Array([
        perp * s * 0.4, trail_end * 0.5, -perp * s * 0.4,
    ]), Color(1.0, 0.7, 0.2, 0.4))
    draw_circle(Vector2.ZERO, s * 3.0, Color(1.0, 0.5, 0.1, 0.08))
    draw_circle(Vector2.ZERO, s * 2.0, Color(1.0, 0.6, 0.15, 0.15))
    draw_circle(Vector2.ZERO, s * 1.2, Color(1.0, 0.65, 0.2))
    draw_circle(Vector2.ZERO, s * 0.7, Color(1.0, 0.85, 0.4))
    draw_circle(Vector2.ZERO, s * 0.35, Color(1.0, 1.0, 0.9, 0.9))

func _draw_hornet_child():
    var dir_n = Vector2.RIGHT
    var perp = Vector2(-dir_n.y, dir_n.x)
    var s = proj_size
    var trail_len = s * 8.0
    var trail_end = -dir_n * trail_len
    draw_colored_polygon(PackedVector2Array([
        perp * s * 0.4, trail_end + perp * s * 0.1,
        trail_end - perp * s * 0.1, -perp * s * 0.4,
    ]), Color(1.0, 0.4, 0.1, 0.25))
    draw_colored_polygon(PackedVector2Array([
        perp * s * 0.2, trail_end * 0.4, -perp * s * 0.2,
    ]), Color(1.0, 0.7, 0.3, 0.5))
    draw_circle(Vector2.ZERO, s * 1.5, Color(proj_color, 0.15))
    draw_circle(Vector2.ZERO, s * 0.9, proj_color)
    draw_circle(Vector2.ZERO, s * 0.4, Color(1.0, 0.9, 0.6, 0.9))
    var pulse = sin(age * 15.0) * 0.15 + 0.85
    draw_circle(dir_n * s * 0.3, s * 0.25, Color(1.0, 0.8, 0.3, pulse))

func _draw_bolt():
    var dir_n = Vector2.RIGHT
    var perp = Vector2( - dir_n.y, dir_n.x)


    draw_circle(Vector2.ZERO, proj_size * 5.0, Color(proj_color, 0.03))

    draw_circle(Vector2.ZERO, proj_size * 3.0, Color(proj_color, 0.1))


    var trail_len = proj_size * 12.0
    var trail_end = - dir_n * trail_len

    var trail_pts = PackedVector2Array([
        perp * proj_size * 0.8, 
        trail_end + perp * proj_size * 0.1, 
        trail_end - perp * proj_size * 0.1, 
        - perp * proj_size * 0.8, 
    ])
    draw_colored_polygon(trail_pts, Color(proj_color, 0.15))


    var core_pts = PackedVector2Array([
        perp * proj_size * 0.4, 
        trail_end * 0.7 + perp * proj_size * 0.05, 
        trail_end * 0.7 - perp * proj_size * 0.05, 
        - perp * proj_size * 0.4, 
    ])
    draw_colored_polygon(core_pts, Color(proj_color, 0.3))


    draw_circle(Vector2.ZERO, proj_size * 1.5, Color(proj_color, 0.25))


    draw_circle(Vector2.ZERO, proj_size, proj_color)


    var hot = proj_color.lerp(Color.WHITE, 0.6)
    draw_circle(Vector2.ZERO, proj_size * 0.5, hot)


    draw_circle(dir_n * proj_size * 0.5, proj_size * 0.3, Color(1.0, 1.0, 1.0, 0.6))

func _draw_railgun():
    var dir_n = Vector2.RIGHT
    var perp = Vector2( - dir_n.y, dir_n.x)


    var trail_len = proj_size * 25.0
    var trail_end = - dir_n * trail_len


    var glow_pts = PackedVector2Array([
        perp * proj_size * 1.5, 
        trail_end + perp * proj_size * 0.2, 
        trail_end - perp * proj_size * 0.2, 
        - perp * proj_size * 1.5, 
    ])
    draw_colored_polygon(glow_pts, Color(proj_color, 0.08))


    var core_pts = PackedVector2Array([
        perp * proj_size * 0.6, 
        trail_end * 0.8 + perp * proj_size * 0.05, 
        trail_end * 0.8 - perp * proj_size * 0.05, 
        - perp * proj_size * 0.6, 
    ])
    draw_colored_polygon(core_pts, Color(proj_color, 0.4))


    var hot_pts = PackedVector2Array([
        perp * proj_size * 0.3, 
        trail_end * 0.5, 
        - perp * proj_size * 0.3, 
    ])
    draw_colored_polygon(hot_pts, Color(1.0, 1.0, 1.0, 0.3))


    draw_circle(Vector2.ZERO, proj_size * 2.0, Color(proj_color, 0.15))
    draw_circle(Vector2.ZERO, proj_size, proj_color)
    draw_circle(Vector2.ZERO, proj_size * 0.5, Color(1.0, 1.0, 1.0, 0.8))


    draw_circle(dir_n * proj_size, proj_size * 0.4, Color(1.0, 1.0, 1.0, 0.6))

func _draw_mac():
    var dir_n = Vector2.RIGHT
    var perp = Vector2( - dir_n.y, dir_n.x)
    var s = proj_size


    var trail_len = s * 18.0
    var trail_end = - dir_n * trail_len
    var heat_pts = PackedVector2Array([
        perp * s * 1.2, 
        trail_end + perp * s * 0.3, 
        trail_end - perp * s * 0.3, 
        - perp * s * 1.2, 
    ])
    draw_colored_polygon(heat_pts, Color(1.0, 0.4, 0.05, 0.1))

    var inner_pts = PackedVector2Array([
        perp * s * 0.6, 
        trail_end * 0.6 + perp * s * 0.1, 
        trail_end * 0.6 - perp * s * 0.1, 
        - perp * s * 0.6, 
    ])
    draw_colored_polygon(inner_pts, Color(1.0, 0.6, 0.15, 0.25))


    draw_circle(Vector2.ZERO, s * 3.0, Color(1.0, 0.5, 0.1, 0.06))
    draw_circle(Vector2.ZERO, s * 1.8, Color(1.0, 0.5, 0.1, 0.12))


    var body = PackedVector2Array([
        dir_n * s * 1.2, 
        dir_n * s * 0.4 + perp * s * 0.5, 
        - dir_n * s * 0.8 + perp * s * 0.45, 
        - dir_n * s * 1.0, 
        - dir_n * s * 0.8 - perp * s * 0.45, 
        dir_n * s * 0.4 - perp * s * 0.5, 
    ])
    draw_colored_polygon(body, Color(0.25, 0.22, 0.2))


    for i in body.size():
        var p1 = body[i]
        var p2 = body[(i + 1) % body.size()]
        draw_line(p1, p2, Color(1.0, 0.5, 0.15, 0.5), 1.5)


    draw_colored_polygon(PackedVector2Array([
        dir_n * s * 1.1, 
        dir_n * s * 0.3 + perp * s * 0.35, 
        - dir_n * s * 0.5 + perp * s * 0.3, 
        dir_n * s * 0.3, 
    ]), Color(1, 1, 1, 0.08))


    draw_circle(Vector2.ZERO, s * 0.6, Color(1.0, 0.55, 0.1, 0.35))
    draw_circle(dir_n * s * 0.3, s * 0.3, Color(1.0, 0.8, 0.4, 0.4))

func _draw_hornet_volley():
    var dir_n = Vector2.RIGHT
    var perp = Vector2( - dir_n.y, dir_n.x)
    var s = proj_size


    var beam_len = s * 15.0
    var beam_end = - dir_n * beam_len
    var beam_pts = PackedVector2Array([
        perp * s * 0.5, 
        beam_end + perp * s * 0.2, 
        beam_end - perp * s * 0.2, 
        - perp * s * 0.5, 
    ])
    draw_colored_polygon(beam_pts, Color(proj_color, 0.25))

    var core_pts = PackedVector2Array([
        perp * s * 0.2, 
        beam_end * 0.5, 
        - perp * s * 0.2, 
    ])
    draw_colored_polygon(core_pts, Color(1.0, 0.9, 0.5, 0.4))


    var rng_seed = get_instance_id()
    for i in 20:
        var t = float(i) / 20.0
        var along = - dir_n * beam_len * t

        var scatter_x = sin(float(rng_seed + i) * 7.3 + age * 12.0) * s * 1.5 * t
        var scatter_y = cos(float(rng_seed + i) * 4.7 + age * 9.0) * s * 1.0 * t
        var pos = along + perp * scatter_x + dir_n * scatter_y
        var round_size = s * lerpf(0.4, 0.15, t)
        var round_alpha = lerpf(0.7, 0.1, t)
        draw_circle(pos, round_size, Color(proj_color, round_alpha))
        if t < 0.3:
            draw_circle(pos, round_size * 0.5, Color(1.0, 1.0, 0.8, round_alpha * 0.8))


    var flash_alpha = 0.3 + sin(age * 40.0) * 0.15
    draw_circle(Vector2.ZERO, s * 2.0, Color(proj_color, flash_alpha * 0.3))
    draw_circle(Vector2.ZERO, s * 1.0, Color(1.0, 0.9, 0.5, flash_alpha))

    draw_circle(Vector2.ZERO, s * 4.0, Color(proj_color, 0.04))

func _draw_missile():
    var s = proj_size


    for smoke in smoke_trail:
        var sp = smoke.pos - global_position

        sp = sp.rotated( - rotation)
        var sa = clampf(1.0 - smoke.age * 2.5, 0, 1) * 0.35
        var sr = smoke.size * (1.0 + smoke.age * 3.0)

        draw_circle(sp, sr, Color(0.5, 0.5, 0.55, sa))
        if smoke.age < 0.15:

            draw_circle(sp, sr * 0.5, Color(1.0, 0.6, 0.2, sa * 1.5))


    var flame_len = s * 2.5 + sin(age * 25.0) * s * 0.5
    var flame = PackedVector2Array([
        Vector2( - s * 1.0, - s * 0.3), 
        Vector2( - s * 1.0 - flame_len, 0), 
        Vector2( - s * 1.0, s * 0.3), 
    ])
    draw_colored_polygon(flame, Color(1.0, 0.5, 0.1, 0.7))
    var flame_hot = PackedVector2Array([
        Vector2( - s * 1.0, - s * 0.15), 
        Vector2( - s * 1.0 - flame_len * 0.6, 0), 
        Vector2( - s * 1.0, s * 0.15), 
    ])
    draw_colored_polygon(flame_hot, Color(1.0, 0.9, 0.5, 0.8))



    var body = PackedVector2Array([
        Vector2(s * 0.6, - s * 0.35), 
        Vector2( - s * 1.0, - s * 0.35), 
        Vector2( - s * 1.0, s * 0.35), 
        Vector2(s * 0.6, s * 0.35), 
    ])
    var body_col = proj_color.lerp(Color(0.3, 0.3, 0.35), 0.4)
    draw_colored_polygon(body, body_col)

    draw_colored_polygon(PackedVector2Array([
        Vector2(s * 0.6, - s * 0.35), 
        Vector2( - s * 1.0, - s * 0.35), 
        Vector2( - s * 1.0, - s * 0.1), 
        Vector2(s * 0.6, - s * 0.1), 
    ]), Color(1, 1, 1, 0.08))


    var nose = PackedVector2Array([
        Vector2(s * 1.4, 0), 
        Vector2(s * 0.6, - s * 0.35), 
        Vector2(s * 0.6, s * 0.35), 
    ])
    draw_colored_polygon(nose, proj_color)

    draw_colored_polygon(PackedVector2Array([
        Vector2(s * 1.35, - s * 0.05), 
        Vector2(s * 0.65, - s * 0.3), 
        Vector2(s * 0.65, - s * 0.05), 
    ]), Color(1, 1, 1, 0.12))


    var fin_col = proj_color.lerp(Color(0.2, 0.2, 0.25), 0.3)

    var fin_u = PackedVector2Array([
        Vector2( - s * 0.7, - s * 0.35), 
        Vector2( - s * 1.3, - s * 0.8), 
        Vector2( - s * 1.1, - s * 0.35), 
    ])
    draw_colored_polygon(fin_u, fin_col)

    var fin_l = PackedVector2Array([
        Vector2( - s * 0.7, s * 0.35), 
        Vector2( - s * 1.3, s * 0.8), 
        Vector2( - s * 1.1, s * 0.35), 
    ])
    draw_colored_polygon(fin_l, fin_col)


    draw_line(Vector2(s * 0.3, - s * 0.36), Vector2(s * 0.3, s * 0.36), proj_color * 1.3, 1.5)
    draw_line(Vector2(s * 0.1, - s * 0.36), Vector2(s * 0.1, s * 0.36), proj_color * 1.3, 1.0)


    draw_polyline(PackedVector2Array([
        Vector2(s * 1.4, 0), Vector2(s * 0.6, - s * 0.35), 
        Vector2( - s * 1.0, - s * 0.35), Vector2( - s * 1.0, s * 0.35), 
        Vector2(s * 0.6, s * 0.35), Vector2(s * 1.4, 0)
    ]), Color(proj_color, 0.5), 0.8)


    draw_circle(Vector2(s * 0.9, 0), s * 1.5, Color(proj_color, 0.06))
