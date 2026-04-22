extends Area2D




var max_health: float = 50.0
var health: float = 50.0
var fire_rate: float = 1.8
var damage: float = 7.0
var proj_speed: float = 400.0
var turret_range: float = 600.0
var fire_timer: float = 0.0
var target: Node2D = null
var scanned: bool = false
var damage_flash: float = 0.0
var turret_color: Color = Color(0.6, 0.4, 0.3)
var tracking_angle: float = 0.0

signal died(pos: Vector2, size: float)

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("enemies")
    var shape = CircleShape2D.new()
    shape.radius = 14.0
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)
    area_entered.connect(_on_area_entered)
    fire_timer = randf_range(0.5, fire_rate)

func _process(delta: float):
    fire_timer -= delta
    if damage_flash > 0:
        damage_flash -= delta * 3.0

    if target == null or not is_instance_valid(target):
        var players = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            target = players[0]

    if target and is_instance_valid(target):
        var aim = (target.global_position - global_position).angle()

        if aim > 0.3 and aim < PI - 0.3:
            aim = 0.3 if aim < PI * 0.5 else PI - 0.3

        tracking_angle = lerp_angle(tracking_angle, aim, delta * 4.0)

        var dist = global_position.distance_to(target.global_position)
        if dist < turret_range and fire_timer <= 0:
            _fire()
            fire_timer = fire_rate

    queue_redraw()

func _fire():
    if not target:
        return
    var proj_scene = preload("res://Space/scenes/projectile.tscn")
    var proj = proj_scene.instantiate()
    proj.global_position = global_position + Vector2.from_angle(tracking_angle) * 22
    proj.rotation = tracking_angle
    proj.source = "enemy"
    proj.damage = damage
    proj.speed = proj_speed
    proj.proj_color = Color(1.0, 0.5, 0.2)
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("turret_fire", 0.3, 0.1)

func take_damage(amount: float):
    health -= amount
    damage_flash = 1.0
    if health <= 0:
        died.emit(global_position, 48.0)
        queue_free()

func _on_area_entered(_area: Area2D):
    pass

func _draw():
    var flash = clampf(damage_flash, 0, 1)
    var base = turret_color
    if flash > 0:
        base = base.lerp(Color.WHITE, flash)
    var hp_pct = health / max_health


    draw_rect(Rect2(-22, 8, 44, 3), Color(0, 0, 0, 0.2))


    var plat = PackedVector2Array([
        Vector2(-22, 3), Vector2(-18, -5), Vector2(-12, -7), 
        Vector2(12, -7), Vector2(18, -5), Vector2(22, 3), 
        Vector2(20, 9), Vector2(-20, 9), 
    ])
    draw_colored_polygon(plat, base * 0.45)

    draw_line(Vector2(-18, -5), Vector2(18, -5), base * 0.6, 0.8)

    for i in 4:
        var rx = lerpf(-14.0, 14.0, float(i) / 3.0)
        draw_circle(Vector2(rx, 5), 1.0, base * 0.3)


    draw_arc(Vector2(0, -2), 12, 0, TAU, 16, base * 0.55, 1.5)


    draw_circle(Vector2(0, -3), 10, base * 0.75)

    draw_arc(Vector2(0, -3), 8, - PI * 0.8, - PI * 0.2, 8, Color(base, 0.3) * 1.5, 1.5)

    draw_arc(Vector2(0, -3), 9, 0.2, PI - 0.2, 8, Color(0, 0, 0, 0.15), 2.0)


    var barrel_end = Vector2.from_angle(tracking_angle) * 22
    var barrel_perp = Vector2.from_angle(tracking_angle + PI * 0.5)

    draw_line(Vector2.ZERO, barrel_end, base * 1.2, 4.0)

    draw_line(Vector2.from_angle(tracking_angle) * 5, barrel_end, base * 0.5, 1.5)

    var muzzle_pos = barrel_end - Vector2.from_angle(tracking_angle) * 3
    draw_line(muzzle_pos + barrel_perp * 3.5, muzzle_pos - barrel_perp * 3.5, base * 0.8, 1.5)

    draw_circle(barrel_end, 3.0, Color(1.0, 0.6, 0.3, 0.2))
    draw_circle(barrel_end, 1.5, Color(1.0, 0.7, 0.4, 0.5))


    if hp_pct < 0.5:
        var time = Time.get_ticks_msec() * 0.001
        if fmod(time, 0.5) < 0.15:
            var sx = sin(time * 7.3) * 8
            var sy = cos(time * 5.1) * 4 - 3
            draw_circle(Vector2(sx, sy), 1.2, Color(1.0, 0.7, 0.2, 0.8))


    draw_arc(Vector2(0, -3), 10, 0, TAU, 16, base * 0.4, 1.0)


    if scanned or health < max_health:
        var bw = 28.0
        draw_rect(Rect2( - bw / 2, -22, bw, 3), Color(0.12, 0, 0))
        draw_rect(Rect2( - bw / 2, -22, bw * hp_pct, 3), Color(0.9, 0.25, 0.2))
        draw_rect(Rect2( - bw / 2, -22, bw, 3), Color(0.3, 0.2, 0.2), false, 0.5)
        if scanned:
            var font = ThemeDB.fallback_font
            draw_string(font, Vector2(-22, -26), "AA TURRET", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.5, 0.4))
