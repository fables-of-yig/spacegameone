extends Node2D



var particles: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var lifetime: float = 0.8
var timer: float = 0.0
var flash_intensity: float = 1.0
var shockwave_radius: float = 0.0
var shockwave_speed: float = 350.0
var base_color: Color = Color(1, 0.6, 0.2)

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE

func setup(color: Color = Color(1, 0.6, 0.2), count: int = 10):
    base_color = color

    for i in count:
        var angle = randf() * TAU
        var spd = randf_range(60, 220)
        var hot = randf()
        var pcol: Color
        if hot > 0.7:
            pcol = Color(1.0, 0.95, 0.7)
        elif hot > 0.3:
            pcol = color.lerp(Color(1.0, 0.8, 0.2), randf_range(0, 0.5))
        else:
            pcol = color.lerp(Color(1, 0.15, 0.0), randf_range(0, 0.5))
        particles.append({
            "pos": Vector2.ZERO, 
            "vel": Vector2.from_angle(angle) * spd, 
            "size": randf_range(2.0, 6.0), 
            "color": pcol, 
            "decay": randf_range(0.8, 1.2), 
        })


    var debris_count = int(count * 0.6)
    for i in debris_count:
        var angle = randf() * TAU
        var spd = randf_range(100, 320)
        var spin = randf_range(-8.0, 8.0)
        var chunk_size = randf_range(2.0, 5.0)

        var verts = randi_range(3, 5)
        var shape: PackedVector2Array = PackedVector2Array()
        for v in verts:
            var va = TAU * float(v) / float(verts) + randf_range(-0.3, 0.3)
            var vr = chunk_size * randf_range(0.5, 1.0)
            shape.append(Vector2.from_angle(va) * vr)
        var dcol = color.lerp(Color(0.3, 0.3, 0.35), randf_range(0.3, 0.7))
        debris.append({
            "pos": Vector2.ZERO, 
            "vel": Vector2.from_angle(angle) * spd, 
            "rot": 0.0, 
            "spin": spin, 
            "shape": shape, 
            "color": dcol, 
        })


    var spark_count = int(count * 0.8)
    for i in spark_count:
        var angle = randf() * TAU
        var spd = randf_range(200, 500)
        sparks.append({
            "pos": Vector2.ZERO, 
            "vel": Vector2.from_angle(angle) * spd, 
            "life": randf_range(0.2, 0.5), 
        })

func _process(delta: float):
    timer += delta
    if timer >= lifetime:
        queue_free()
        return

    flash_intensity = maxf(flash_intensity - delta * 6.0, 0.0)
    shockwave_radius += shockwave_speed * delta

    for p in particles:
        p.pos += p.vel * delta
        p.vel *= 0.92

    for d in debris:
        d.pos += d.vel * delta
        d.vel *= 0.95
        d.rot += d.spin * delta

    for s in sparks:
        s.pos += s.vel * delta
        s.vel *= 0.88
        s.life -= delta

    queue_redraw()

func _draw():
    var progress = timer / lifetime
    var alpha = 1.0 - progress


    if flash_intensity > 0:
        draw_circle(Vector2.ZERO, 20.0 * flash_intensity, Color(1.0, 0.95, 0.8, flash_intensity * 0.6))
        draw_circle(Vector2.ZERO, 10.0 * flash_intensity, Color(1.0, 1.0, 0.9, flash_intensity * 0.8))


    if shockwave_radius > 5.0 and shockwave_radius < 180.0:
        var ring_alpha = clampf(1.0 - shockwave_radius / 180.0, 0, 0.6)
        draw_arc(Vector2.ZERO, shockwave_radius, 0, TAU, 16, Color(base_color, ring_alpha), 2.0)

        draw_arc(Vector2.ZERO, shockwave_radius * 0.85, 0, TAU, 12, Color(1.0, 0.9, 0.7, ring_alpha * 0.3), 3.0)


    if progress > 0.15:
        var smoke_alpha = clampf((progress - 0.15) * 2.0, 0, 0.3) * (1.0 - progress)
        for i in 5:
            var hash_v = sin(float(i) * 7.3 + 0.5) * 43758.5453
            var r = hash_v - floorf(hash_v)
            var sx = (r - 0.5) * 60.0 * progress
            var sy = (sin(float(i) * 2.7) - 0.5) * 50.0 * progress
            var sr = 8.0 + progress * 25.0
            draw_circle(Vector2(sx, sy), sr, Color(0.25, 0.22, 0.2, smoke_alpha))


    for p in particles:
        var c: Color = p.color
        var decay_t = progress * p.decay
        c.a = clampf(alpha * (1.0 - decay_t * 0.5), 0, 1)
        var sz: float = p.size * (1.0 + progress * 0.3) * clampf(1.0 - decay_t, 0.2, 1.0)

        draw_circle(p.pos, sz * 1.8, Color(c, c.a * 0.2))

        draw_circle(p.pos, sz, c)


    for d in debris:
        var da = clampf(alpha * 1.3, 0, 1)
        if da < 0.05:
            continue
        var c: Color = d.color
        c.a = da
        var xf = Transform2D(d.rot, d.pos)

        var pts: PackedVector2Array = d.shape
        var transformed: PackedVector2Array = d.get("_xf_shape", PackedVector2Array())
        if transformed.size() != pts.size():
            transformed.resize(pts.size())
            d["_xf_shape"] = transformed
        for i in pts.size():
            transformed[i] = xf * pts[i]
        if transformed.size() >= 3:
            draw_colored_polygon(transformed, c)


    for s in sparks:
        if s.life <= 0:
            continue
        var sa = clampf(s.life * 3.0, 0, 1)
        var trail_end = s.pos - s.vel.normalized() * 6.0
        draw_line(s.pos, trail_end, Color(1.0, 0.8, 0.3, sa * 0.5), 0.8)
        draw_circle(s.pos, 1.0, Color(1.0, 0.9, 0.5, sa))
