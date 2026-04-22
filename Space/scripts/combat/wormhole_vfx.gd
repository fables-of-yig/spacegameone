extends Node2D




signal finished

var duration: float = 2.0
var timer: float = 0.0
var wormhole_color: Color = Color(0.4, 0.2, 0.8)
var max_radius: float = 28.0
var spiral_arms: int = 5
var particle_count: int = 12


var particles: Array[Dictionary] = []

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    for i in particle_count:
        particles.append({
            "angle": randf() * TAU, 
            "dist": randf_range(0.3, 1.0), 
            "speed": randf_range(3.0, 8.0), 
            "size": randf_range(1.0, 2.5), 
        })

func _process(delta: float):
    timer += delta
    if timer >= duration:
        finished.emit()
        queue_free()
        return
    queue_redraw()

func _draw():
    var t = timer / duration
    var radius: float
    var alpha: float

    if t < 0.3:

        var open_t = t / 0.3
        radius = max_radius * open_t
        alpha = open_t * 0.8
    elif t < 0.75:

        radius = max_radius
        alpha = 0.8
    else:

        var close_t = (t - 0.75) / 0.25
        radius = max_radius * (1.0 - close_t)
        alpha = 0.8 * (1.0 - close_t)

    if radius < 1.0 or alpha < 0.01:
        return


    draw_circle(Vector2.ZERO, radius * 1.8, Color(wormhole_color, alpha * 0.08))
    draw_circle(Vector2.ZERO, radius * 1.4, Color(wormhole_color, alpha * 0.12))


    var spin = timer * 4.0
    for arm in spiral_arms:
        var arm_angle = spin + (float(arm) / spiral_arms) * TAU
        var points: PackedVector2Array = []
        var colors: PackedColorArray = []
        var steps = 12
        for step in steps:
            var st = float(step) / (steps - 1)
            var r = radius * st
            var a = arm_angle + st * 2.5
            var _w = (1.0 - st) * radius * 0.15 + 1.0
            points.append(Vector2(cos(a) * r, sin(a) * r))
            var c = wormhole_color.lerp(Color.WHITE, st * 0.3)
            c.a = alpha * (1.0 - st * 0.7)
            colors.append(c)


        for i in range(points.size() - 1):
            var width = lerpf(3.0, 0.5, float(i) / (points.size() - 1))
            draw_line(points[i], points[i + 1], colors[i], width)


    var core_pulse = sin(timer * 12.0) * 0.15 + 0.85
    var core_col = wormhole_color.lerp(Color.WHITE, 0.5)
    draw_circle(Vector2.ZERO, radius * 0.25 * core_pulse, Color(core_col, alpha * 0.6))
    draw_circle(Vector2.ZERO, radius * 0.12 * core_pulse, Color(Color.WHITE, alpha * 0.4))


    for p in particles:
        var pa = p["angle"] + timer * p["speed"]
        var pd = p["dist"] * radius
        var pp = Vector2(cos(pa) * pd, sin(pa) * pd)
        var pc = wormhole_color.lerp(Color.WHITE, 0.4)
        draw_circle(pp, p["size"] * alpha, Color(pc, alpha * 0.5))


    var rim_col = Color(wormhole_color.lerp(Color.WHITE, 0.3), alpha * 0.4)
    var rim_pts: PackedVector2Array = []
    for i in 32:
        var a = float(i) / 32.0 * TAU
        rim_pts.append(Vector2(cos(a) * radius, sin(a) * radius))
    rim_pts.append(rim_pts[0])
    draw_polyline(rim_pts, rim_col, 1.5)
