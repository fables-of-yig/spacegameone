extends Area2D





var velocity: Vector2 = Vector2.ZERO
var crew_data: Dictionary = {}
var pod_color: Color = Color(0.9, 0.6, 0.2)
var spin: float = 0.0
var lifetime: float = 15.0
var age: float = 0.0
var sos_ring_time: float = 0.0
var is_enemy: bool = false
var _contacted: bool = false

signal picked_up(crew_data: Dictionary)
signal enemy_pod_contacted(pod: Area2D)

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("escape_pods")

    spin = randf_range(-3.0, 3.0)
    age = 0.0
    sos_ring_time = 0.0


    var shape = CircleShape2D.new()
    shape.radius = 8.0
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child.call_deferred(col)

    area_entered.connect(_on_area_entered)

func _physics_process(delta: float):

    position += velocity * delta
    velocity *= 0.98


    rotation += spin * delta


    age += delta
    sos_ring_time += delta
    lifetime -= delta
    if lifetime <= 0:
        queue_free()
        return


    if lifetime < 4.0:
        modulate.a = clampf(lifetime / 4.0, 0.15, 1.0)

    queue_redraw()

func _on_area_entered(area: Area2D):
    if area.is_in_group("player"):
        if is_enemy:
            if not _contacted:
                _contacted = true
                enemy_pod_contacted.emit(self)
        else:
            picked_up.emit(crew_data)
            AudioManager.play_sfx("pickup", 0.5, 0.1)
            set_deferred("monitoring", false)
            queue_free()

func _draw():
    var s: float = 8.0
    var t = age


    var ring_period: float = 2.0
    var ring_phase = fmod(sos_ring_time, ring_period) / ring_period
    var ring_radius = s * 2.0 + ring_phase * 40.0
    var ring_alpha = (1.0 - ring_phase) * 0.25
    draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 24, Color(1.0, 0.3, 0.2, ring_alpha), 1.0)

    var ring_phase2 = fmod(sos_ring_time + ring_period * 0.5, ring_period) / ring_period
    var ring_radius2 = s * 2.0 + ring_phase2 * 40.0
    var ring_alpha2 = (1.0 - ring_phase2) * 0.15
    draw_arc(Vector2.ZERO, ring_radius2, 0, TAU, 24, Color(1.0, 0.3, 0.2, ring_alpha2), 0.7)


    draw_circle(Vector2.ZERO, s * 2.5, Color(pod_color, 0.04))
    draw_circle(Vector2.ZERO, s * 1.5, Color(pod_color, 0.08))


    if velocity.length() > 5.0:
        var puff_alpha = clampf(velocity.length() / 80.0, 0.1, 0.4)
        for i in 3:
            var puff_offset = Vector2( - s * 0.9 - float(i) * 3.0, sin(t * 8.0 + float(i) * 2.0) * 2.0)
            var puff_r = 1.5 + float(i) * 0.8
            draw_circle(puff_offset, puff_r, Color(0.5, 0.5, 0.55, puff_alpha * (1.0 - float(i) / 3.0)))
            if i == 0:
                draw_circle(puff_offset, puff_r * 0.5, Color(1.0, 0.6, 0.2, puff_alpha * 0.8))



    var body = PackedVector2Array([
        Vector2(s * 0.8, 0), 
        Vector2(s * 0.6, - s * 0.35), 
        Vector2(s * 0.2, - s * 0.45), 
        Vector2( - s * 0.3, - s * 0.42), 
        Vector2( - s * 0.65, - s * 0.3), 
        Vector2( - s * 0.8, 0), 
        Vector2( - s * 0.65, s * 0.3), 
        Vector2( - s * 0.3, s * 0.42), 
        Vector2(s * 0.2, s * 0.45), 
        Vector2(s * 0.6, s * 0.35), 
    ])
    var hull_color = pod_color * 0.6
    draw_colored_polygon(body, hull_color)


    var body_top = PackedVector2Array([
        Vector2(s * 0.8, 0), 
        Vector2(s * 0.6, - s * 0.35), 
        Vector2(s * 0.2, - s * 0.45), 
        Vector2( - s * 0.3, - s * 0.42), 
        Vector2( - s * 0.65, - s * 0.3), 
        Vector2( - s * 0.8, 0), 
        Vector2(s * 0.8, 0), 
    ])
    draw_colored_polygon(body_top, Color(1, 1, 1, 0.07))


    var body_bot = PackedVector2Array([
        Vector2(s * 0.8, 0), 
        Vector2( - s * 0.8, 0), 
        Vector2( - s * 0.65, s * 0.3), 
        Vector2( - s * 0.3, s * 0.42), 
        Vector2(s * 0.2, s * 0.45), 
        Vector2(s * 0.6, s * 0.35), 
    ])
    draw_colored_polygon(body_bot, Color(0, 0, 0, 0.1))


    draw_polyline(PackedVector2Array([
        body[0], body[1], body[2], body[3], body[4], body[5], 
        body[6], body[7], body[8], body[9], body[0]
    ]), pod_color * 1.1, 0.8)


    var win_center = Vector2(s * 0.3, - s * 0.1)
    draw_circle(win_center, s * 0.2, Color(0.15, 0.35, 0.5, 0.8))

    draw_circle(win_center + Vector2(-1, -1), s * 0.08, Color(0.5, 0.8, 1.0, 0.4))

    draw_arc(win_center, s * 0.2, 0, TAU, 10, Color(pod_color * 0.8, 0.6), 0.8)


    draw_line(Vector2(s * 0.5, - s * 0.38), Vector2( - s * 0.5, - s * 0.38), pod_color * 0.4, 0.5)
    draw_line(Vector2(s * 0.5, s * 0.38), Vector2( - s * 0.5, s * 0.38), pod_color * 0.4, 0.5)

    draw_line(Vector2( - s * 0.1, - s * 0.44), Vector2( - s * 0.1, s * 0.44), pod_color * 0.35, 0.4)


    var nose = PackedVector2Array([
        Vector2(s * 0.8, 0), 
        Vector2(s * 0.6, - s * 0.35), 
        Vector2(s * 0.55, - s * 0.2), 
        Vector2(s * 0.55, s * 0.2), 
        Vector2(s * 0.6, s * 0.35), 
    ])
    draw_colored_polygon(nose, pod_color * 0.45)


    var blink = sin(t * 6.0) * 0.5 + 0.5
    var distress_pos = Vector2(0, - s * 0.5)

    draw_circle(distress_pos, 4.0 + blink * 2.0, Color(1.0, 0.15, 0.1, 0.15 * blink))

    draw_circle(distress_pos, 1.5 + blink * 0.5, Color(1.0, 0.2, 0.15, 0.5 + blink * 0.5))

    if blink > 0.6:
        draw_circle(distress_pos, 1.0, Color(1.0, 0.8, 0.6, 0.9))


    var nozzle = PackedVector2Array([
        Vector2( - s * 0.75, - s * 0.18), 
        Vector2( - s * 0.85, - s * 0.12), 
        Vector2( - s * 0.85, s * 0.12), 
        Vector2( - s * 0.75, s * 0.18), 
    ])
    draw_colored_polygon(nozzle, pod_color * 0.35)
    draw_polyline(PackedVector2Array([nozzle[0], nozzle[1], nozzle[2], nozzle[3]]), pod_color * 0.5, 0.6)
