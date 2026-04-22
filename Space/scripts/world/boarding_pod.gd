extends Area2D




var velocity: Vector2 = Vector2.ZERO
var target: Node2D = null
var speed: float = 300.0
var marines: Array = []
var source: String = "player"
var pod_color: Color = Color(0.4, 0.7, 1.0)
var arrived: bool = false

var age: float = 0.0
var drift_timer: float = 0.0
var drifting: bool = false
const TURN_RATE: float = 4.0
const DRIFT_DESPAWN: float = 5.0

signal boarded(marines: Array)

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("boarding_pods")
    age = 0.0


    var shape = CircleShape2D.new()
    shape.radius = 6.0
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)

    area_entered.connect(_on_area_entered)

func _physics_process(delta: float):
    age += delta

    if not drifting and target and is_instance_valid(target):

        var to_target = (target.global_position - global_position).normalized()
        var current_angle = velocity.angle() if velocity.length() > 1.0 else rotation
        var target_angle = to_target.angle()
        var new_angle = lerp_angle(current_angle, target_angle, TURN_RATE * delta)
        velocity = Vector2.from_angle(new_angle) * speed
        rotation = new_angle
    else:

        if not drifting:
            drifting = true
            drift_timer = 0.0
        drift_timer += delta

        velocity *= 0.99
        if drift_timer >= DRIFT_DESPAWN:
            queue_free()
            return

    position += velocity * delta


    if drifting and drift_timer > DRIFT_DESPAWN - 2.0:
        modulate.a = clampf((DRIFT_DESPAWN - drift_timer) / 2.0, 0.1, 1.0)

    queue_redraw()

func _on_area_entered(area: Area2D):
    if arrived:
        return

    if source == "player" and area.is_in_group("enemies"):
        arrived = true
        if area.has_method("receive_boarders"):
            area.receive_boarders(marines)
        boarded.emit(marines)
        set_deferred("monitoring", false)
        queue_free()
    elif source == "enemy" and area.is_in_group("player"):
        arrived = true
        if area.has_method("receive_boarders"):
            area.receive_boarders(marines)
        boarded.emit(marines)
        set_deferred("monitoring", false)
        queue_free()

func _draw():
    var s: float = 6.0
    var t = age
    var _dir_n = velocity.normalized() if velocity.length() > 1.0 else Vector2.from_angle(rotation)


    draw_circle(Vector2.ZERO, s * 2.5, Color(pod_color, 0.04))


    var flame_flicker = sin(t * 20.0) * 0.3 + 0.7
    if not drifting:

        var flame_len = s * 2.0 * flame_flicker
        var outer_flame = PackedVector2Array([
            Vector2( - s * 0.9, - s * 0.25), 
            Vector2( - s * 0.9 - flame_len, 0), 
            Vector2( - s * 0.9, s * 0.25), 
        ])
        draw_colored_polygon(outer_flame, Color(1.0, 0.4, 0.1, 0.5))

        var inner_flame = PackedVector2Array([
            Vector2( - s * 0.9, - s * 0.12), 
            Vector2( - s * 0.9 - flame_len * 0.6, 0), 
            Vector2( - s * 0.9, s * 0.12), 
        ])
        draw_colored_polygon(inner_flame, Color(1.0, 0.85, 0.4, 0.7))

        var hot_flame = PackedVector2Array([
            Vector2( - s * 0.9, - s * 0.05), 
            Vector2( - s * 0.9 - flame_len * 0.3, 0), 
            Vector2( - s * 0.9, s * 0.05), 
        ])
        draw_colored_polygon(hot_flame, Color(1.0, 1.0, 0.8, 0.6))
    else:

        if fmod(t, 0.6) < 0.15:
            var sputter = PackedVector2Array([
                Vector2( - s * 0.9, - s * 0.1), 
                Vector2( - s * 1.2, 0), 
                Vector2( - s * 0.9, s * 0.1), 
            ])
            draw_colored_polygon(sputter, Color(1.0, 0.4, 0.1, 0.25))



    var body = PackedVector2Array([
        Vector2(s * 1.2, 0), 
        Vector2(s * 0.5, - s * 0.35), 
        Vector2( - s * 0.2, - s * 0.45), 
        Vector2( - s * 0.8, - s * 0.35), 
        Vector2( - s * 0.9, 0), 
        Vector2( - s * 0.8, s * 0.35), 
        Vector2( - s * 0.2, s * 0.45), 
        Vector2(s * 0.5, s * 0.35), 
    ])
    var hull_color = pod_color * 0.55
    draw_colored_polygon(body, hull_color)


    var body_top = PackedVector2Array([
        Vector2(s * 1.2, 0), 
        Vector2(s * 0.5, - s * 0.35), 
        Vector2( - s * 0.2, - s * 0.45), 
        Vector2( - s * 0.8, - s * 0.35), 
        Vector2( - s * 0.9, 0), 
        Vector2(s * 1.2, 0), 
    ])
    draw_colored_polygon(body_top, Color(1, 1, 1, 0.06))


    var body_bot = PackedVector2Array([
        Vector2(s * 1.2, 0), 
        Vector2( - s * 0.9, 0), 
        Vector2( - s * 0.8, s * 0.35), 
        Vector2( - s * 0.2, s * 0.45), 
        Vector2(s * 0.5, s * 0.35), 
    ])
    draw_colored_polygon(body_bot, Color(0, 0, 0, 0.1))


    draw_polyline(PackedVector2Array([
        body[0], body[1], body[2], body[3], body[4], 
        body[5], body[6], body[7], body[0]
    ]), pod_color * 0.9, 0.8)



    draw_line(Vector2(s * 0.3, - s * 0.38), Vector2( - s * 0.6, - s * 0.38), pod_color * 0.35, 0.7)
    draw_line(Vector2(s * 0.3, s * 0.38), Vector2( - s * 0.6, s * 0.38), pod_color * 0.35, 0.7)

    draw_line(Vector2(s * 0.0, - s * 0.44), Vector2(s * 0.0, s * 0.44), pod_color * 0.3, 0.5)
    draw_line(Vector2( - s * 0.45, - s * 0.42), Vector2( - s * 0.45, s * 0.42), pod_color * 0.3, 0.5)

    draw_line(Vector2(s * 0.5, - s * 0.35), Vector2(s * 0.2, - s * 0.1), pod_color * 0.3, 0.4)
    draw_line(Vector2(s * 0.5, s * 0.35), Vector2(s * 0.2, s * 0.1), pod_color * 0.3, 0.4)


    var prow = PackedVector2Array([
        Vector2(s * 1.2, 0), 
        Vector2(s * 0.5, - s * 0.35), 
        Vector2(s * 0.5, - s * 0.15), 
        Vector2(s * 0.5, s * 0.15), 
        Vector2(s * 0.5, s * 0.35), 
    ])
    draw_colored_polygon(prow, pod_color * 0.7)

    draw_line(Vector2(s * 1.2, 0), Vector2(s * 0.5, - s * 0.35), pod_color * 1.3, 1.0)
    draw_line(Vector2(s * 1.2, 0), Vector2(s * 0.5, s * 0.35), pod_color * 1.3, 1.0)


    var prow_pulse = sin(t * 5.0) * 0.3 + 0.7
    draw_circle(Vector2(s * 1.2, 0), 3.0, Color(pod_color, 0.12 * prow_pulse))
    draw_circle(Vector2(s * 1.2, 0), 1.5, Color(pod_color.lerp(Color.WHITE, 0.4), 0.6 * prow_pulse))
    draw_circle(Vector2(s * 1.2, 0), 0.8, Color(1.0, 1.0, 1.0, 0.5 * prow_pulse))



    var plate_u = PackedVector2Array([
        Vector2(s * 0.4, - s * 0.36), 
        Vector2(s * 0.1, - s * 0.44), 
        Vector2( - s * 0.3, - s * 0.44), 
        Vector2( - s * 0.15, - s * 0.36), 
    ])
    draw_colored_polygon(plate_u, pod_color * 0.45)

    var plate_l = PackedVector2Array([
        Vector2(s * 0.4, s * 0.36), 
        Vector2(s * 0.1, s * 0.44), 
        Vector2( - s * 0.3, s * 0.44), 
        Vector2( - s * 0.15, s * 0.36), 
    ])
    draw_colored_polygon(plate_l, pod_color * 0.4)


    var nozzle = PackedVector2Array([
        Vector2( - s * 0.8, - s * 0.3), 
        Vector2( - s * 0.95, - s * 0.22), 
        Vector2( - s * 0.95, s * 0.22), 
        Vector2( - s * 0.8, s * 0.3), 
    ])
    draw_colored_polygon(nozzle, pod_color * 0.35)
    draw_polyline(PackedVector2Array([nozzle[0], nozzle[1], nozzle[2], nozzle[3]]), pod_color * 0.5, 0.6)


    for i in 3:
        var rx = lerpf( - s * 0.4, s * 0.3, float(i) / 2.0)
        draw_circle(Vector2(rx, - s * 0.44), 0.6, pod_color * 0.3)
        draw_circle(Vector2(rx, s * 0.44), 0.6, pod_color * 0.3)


    var blink = sin(t * 4.0) * 0.5 + 0.5

    draw_circle(Vector2( - s * 0.3, - s * 0.46), 1.0, Color(1.0, 0.2, 0.2, blink * 0.7))
    draw_circle(Vector2( - s * 0.3, s * 0.46), 1.0, Color(0.2, 1.0, 0.2, blink * 0.7))
