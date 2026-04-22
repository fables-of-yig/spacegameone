extends Control





var active: bool = false
var art_id: String = ""
var art_params: Dictionary = {}
var _time: float = 0.0
var _particles: Array = []
var _shapes: Array = []
var _entities: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bg_stars: Array = []

func _ready():
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)

    var star_rng = RandomNumberGenerator.new()
    star_rng.seed = 12345
    for i in 150:
        _bg_stars.append({
            "pos": Vector2(star_rng.randf() * size.x, star_rng.randf() * size.y), 
            "brightness": star_rng.randf_range(0.15, 0.6), 
            "sz": star_rng.randf_range(0.5, 1.5), 
        })

func start_art(id: String, params: Dictionary = {}):
    art_id = id
    art_params = params
    _time = 0.0
    _particles.clear()
    _shapes.clear()
    _entities.clear()
    _rng.seed = hash(id)
    _init_art()
    active = true
    visible = true

func stop_art():
    active = false
    visible = false
    art_id = ""
    _particles.clear()
    _shapes.clear()
    _entities.clear()

func _process(delta: float):
    if not active:
        return
    _time += delta
    _update_particles(delta)
    queue_redraw()

func _init_art():
    match art_id:
        "void_jellyfish": _init_void_jellyfish()
        "void_whale": _init_void_whale()
        "void_kraken": _init_void_kraken()
        "ion_storm": _init_ion_storm()
        "gravitational_lens": _init_gravitational_lens()
        "nebula": _init_nebula()
        "ghost_fleet": _init_ghost_fleet()
        "megastructure": _init_megastructure()
        "dimensional_tear": _init_dimensional_tear()
        "spore_cloud": _init_spore_cloud()
        "crystalline": _init_crystalline()
        "solar_event": _init_solar_event()
        "swarm": _init_swarm()
        "darkness": _init_darkness()
        "derelict": _init_derelict()
        "wormhole": _init_wormhole()
        "aurora": _init_aurora()
        "leviathan": _init_leviathan()

func _update_particles(delta: float):
    for p in _particles:
        p.pos += p.vel * delta
        if p.has("life"):
            p.life -= delta

func _draw():
    if not active:
        return

    draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))

    _draw_bg_stars()

    match art_id:
        "void_jellyfish": _draw_void_jellyfish()
        "void_whale": _draw_void_whale()
        "void_kraken": _draw_void_kraken()
        "ion_storm": _draw_ion_storm()
        "gravitational_lens": _draw_gravitational_lens()
        "nebula": _draw_nebula()
        "ghost_fleet": _draw_ghost_fleet()
        "megastructure": _draw_megastructure()
        "dimensional_tear": _draw_dimensional_tear()
        "spore_cloud": _draw_spore_cloud()
        "crystalline": _draw_crystalline()
        "solar_event": _draw_solar_event()
        "swarm": _draw_swarm()
        "darkness": _draw_darkness()
        "derelict": _draw_derelict()
        "wormhole": _draw_wormhole()
        "aurora": _draw_aurora()
        "leviathan": _draw_leviathan()

func _draw_bg_stars():
    for s in _bg_stars:
        var twinkle = sin(_time * 1.5 + s.pos.x * 0.1) * 0.15 + 0.85
        var alpha = s.brightness * twinkle
        draw_circle(s.pos, s.sz, Color(1, 1, 1, alpha))





func _hue_color(hue: float, sat: float = 0.7, val: float = 0.8, alpha: float = 1.0) -> Color:
    return Color.from_hsv(fmod(absf(hue), 1.0), clampf(sat, 0.0, 1.0), clampf(val, 0.0, 1.0), clampf(alpha, 0.0, 1.0))

func _param_f(key: String, fallback: float) -> float:
    return float(art_params.get(key, fallback))

func _param_i(key: String, fallback: int) -> int:
    return int(art_params.get(key, fallback))

func _param_s(key: String, fallback: String) -> String:
    return str(art_params.get(key, fallback))

func _param_b(key: String, fallback: bool) -> bool:
    return bool(art_params.get(key, fallback))

func _screen_center() -> Vector2:
    return size * 0.5

func _noise1d(x: float) -> float:

    return sin(x * 1.0) * 0.5 + sin(x * 2.3 + 1.7) * 0.3 + sin(x * 4.1 + 3.2) * 0.2

func _noise2d(x: float, y: float) -> float:
    return sin(x * 1.3 + y * 0.7) * 0.4 + sin(x * 2.7 - y * 1.9 + 2.1) * 0.35 + sin(x * 0.5 + y * 3.1 + 4.7) * 0.25

func _draw_glow_circle(pos: Vector2, radius: float, color: Color, layers: int = 3):
    for i in layers:
        var t = float(i) / float(layers)
        var r = radius * (1.0 + t * 1.5)
        var a = color.a * (1.0 - t) * 0.4
        draw_circle(pos, r, Color(color.r, color.g, color.b, a))
    draw_circle(pos, radius, color)

func _draw_curved_line(points: PackedVector2Array, color: Color, width: float = 1.0):
    if points.size() < 2:
        return
    for i in range(points.size() - 1):
        var alpha_mult = 1.0 - float(i) / float(points.size())
        var col = Color(color.r, color.g, color.b, color.a * alpha_mult)
        draw_line(points[i], points[i + 1], col, width)





func _init_void_jellyfish():
    var hue = _param_f("color", 0.75)
    var count = _param_i("count", 1)
    var sz_scale = _param_f("size_scale", 1.5)
    for i in count:
        var jelly = {
            "pos": Vector2(
                _rng.randf_range(size.x * 0.2, size.x * 0.8), 
                _rng.randf_range(size.y * 0.15, size.y * 0.55)), 
            "bell_radius": _rng.randf_range(40, 80) * sz_scale, 
            "hue": hue + _rng.randf_range(-0.05, 0.05), 
            "pulse_phase": _rng.randf() * TAU, 
            "drift_speed": Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-3, 3)), 
            "tentacle_count": _rng.randi_range(6, 10), 
            "tentacle_length": _rng.randf_range(120, 200) * sz_scale, 
            "nodes": [], 
        }

        for t in jelly.tentacle_count:
            var node_count = _rng.randi_range(3, 6)
            var nodes = []
            for n in node_count:
                nodes.append(_rng.randf_range(0.2, 0.95))
            jelly.nodes.append(nodes)
        _entities.append(jelly)

func _draw_void_jellyfish():
    for jelly in _entities:
        var pos = jelly.pos + jelly.drift_speed * _time

        pos.y += sin(_time * 0.8 + jelly.pulse_phase) * 12.0
        pos.x += sin(_time * 0.5 + jelly.pulse_phase * 1.3) * 6.0
        var pulse = sin(_time * 1.5 + jelly.pulse_phase) * 0.15 + 0.85
        var bell_r = jelly.bell_radius * pulse
        var hue = jelly.hue


        for layer in 5:
            var lr = bell_r * (1.0 - float(layer) * 0.08)
            var la = 0.06 + float(layer) * 0.03
            var lhue = hue + float(layer) * 0.02
            var col = _hue_color(lhue, 0.5, 0.7, la)

            var bell_pts: PackedVector2Array = PackedVector2Array()
            for seg in 25:
                var a = PI + float(seg) / 24.0 * PI
                bell_pts.append(pos + Vector2(cos(a) * lr, sin(a) * lr * 0.7))
            if bell_pts.size() >= 3:
                draw_colored_polygon(bell_pts, col)


        var glow_pulse = sin(_time * 2.0 + jelly.pulse_phase) * 0.3 + 0.7
        var outline_col = _hue_color(hue, 0.6, 0.9, 0.25 * glow_pulse)
        draw_arc(pos, bell_r, PI, TAU, 24, outline_col, 2.0)


        var base_y = pos.y + bell_r * 0.2
        for t in jelly.tentacle_count:
            var t_angle = - PI * 0.4 + float(t) / float(jelly.tentacle_count - 1) * PI * 0.8 if jelly.tentacle_count > 1 else 0.0
            var t_base_x = pos.x + cos(PI + t_angle) * bell_r * 0.7
            var seg_count = 20
            var prev_pt = Vector2(t_base_x, base_y)
            for seg in range(1, seg_count + 1):
                var frac = float(seg) / float(seg_count)
                var seg_y = base_y + frac * jelly.tentacle_length
                var wave = sin(_time * 2.0 + frac * 4.0 + float(t) * 1.5 + jelly.pulse_phase) * (15.0 + frac * 25.0)
                var seg_x = t_base_x + wave
                var pt = Vector2(seg_x, seg_y)
                var alpha = (1.0 - frac) * 0.35
                var col = _hue_color(hue + frac * 0.1, 0.5, 0.8, alpha)
                draw_line(prev_pt, pt, col, maxf(1.0, 2.5 * (1.0 - frac)))
                prev_pt = pt


            if t < jelly.nodes.size():
                for node_frac in jelly.nodes[t]:
                    var ny = base_y + node_frac * jelly.tentacle_length
                    var nwave = sin(_time * 2.0 + node_frac * 4.0 + float(t) * 1.5 + jelly.pulse_phase) * (15.0 + node_frac * 25.0)
                    var nx = t_base_x + nwave
                    var node_pulse = sin(_time * 3.0 + node_frac * 5.0 + float(t)) * 0.4 + 0.6
                    var node_col = _hue_color(hue + 0.15, 0.4, 1.0, 0.5 * node_pulse)
                    _draw_glow_circle(Vector2(nx, ny), 3.0, node_col, 2)





func _init_void_whale():
    var hue = _param_f("color", 0.6)
    var count = _param_i("count", 1)
    var sz_scale = _param_f("size_scale", 1.0)
    for i in count:
        _entities.append({
            "pos": Vector2(
                _rng.randf_range(size.x * 0.15, size.x * 0.85), 
                _rng.randf_range(size.y * 0.2, size.y * 0.5)), 
            "body_length": _rng.randf_range(200, 350) * sz_scale, 
            "body_width": _rng.randf_range(50, 80) * sz_scale, 
            "hue": hue + _rng.randf_range(-0.05, 0.05), 
            "phase": _rng.randf() * TAU, 
            "drift_speed": Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-2, 2)), 
            "bio_dots": _generate_whale_dots(_rng, 20), 
            "organ_count": _rng.randi_range(2, 4), 
        })

func _generate_whale_dots(rng: RandomNumberGenerator, count: int) -> Array:
    var dots = []
    for i in count:
        dots.append({
            "x": rng.randf_range(-0.4, 0.4), 
            "y": rng.randf_range(-0.3, 0.3), 
            "pulse_phase": rng.randf() * TAU, 
            "sz": rng.randf_range(1.5, 3.5), 
        })
    return dots

func _draw_void_whale():
    for whale in _entities:
        var pos = whale.pos + whale.drift_speed * _time
        var undulate = sin(_time * 0.6 + whale.phase) * 8.0
        pos.y += undulate
        var body_len = whale.body_length
        var body_w = whale.body_width
        var hue = whale.hue


        var body_segs = 12
        for seg in body_segs:
            var frac = float(seg) / float(body_segs - 1) - 0.5
            var seg_x = pos.x + frac * body_len
            var seg_wave = sin(_time * 0.8 + frac * 3.0 + whale.phase) * 6.0
            var seg_y = pos.y + seg_wave

            var width_mult = 1.0 - (absf(frac) * 2.0) ** 1.5
            var seg_w = body_w * maxf(width_mult, 0.1)
            for layer in 3:
                var lr = seg_w * (1.0 - float(layer) * 0.15)
                var la = 0.04 + float(layer) * 0.025
                var col = _hue_color(hue + float(layer) * 0.02, 0.35, 0.5, la)
                draw_circle(Vector2(seg_x, seg_y), lr, col)


        for organ_i in whale.organ_count:
            var organ_frac = float(organ_i + 1) / float(whale.organ_count + 1) - 0.5
            var organ_x = pos.x + organ_frac * body_len * 0.6
            var organ_wave = sin(_time * 0.8 + organ_frac * 3.0 + whale.phase) * 6.0
            var organ_y = pos.y + organ_wave
            var organ_pulse = sin(_time * 1.2 + float(organ_i) * 2.0 + whale.phase) * 0.3 + 0.7
            var organ_col = _hue_color(hue + 0.1, 0.4, 0.9, 0.12 * organ_pulse)
            draw_circle(Vector2(organ_x, organ_y), body_w * 0.3 * organ_pulse, organ_col)


        for dot in whale.bio_dots:
            var dx = pos.x + dot.x * body_len
            var dwave = sin(_time * 0.8 + dot.x * 3.0 + whale.phase) * 6.0
            var dy = pos.y + dot.y * body_w + dwave
            var dot_pulse = sin(_time * 2.5 + dot.pulse_phase) * 0.4 + 0.6
            var dot_col = _hue_color(hue + 0.15, 0.3, 1.0, 0.4 * dot_pulse)
            draw_circle(Vector2(dx, dy), dot.sz, dot_col)


        var tail_x = pos.x - body_len * 0.5
        var tail_wave = sin(_time * 0.8 - 0.5 * 3.0 + whale.phase) * 6.0
        var tail_y = pos.y + tail_wave
        var tail_swing = sin(_time * 1.2 + whale.phase) * 20.0
        for fluke in 2:
            var fluke_dir = -1.0 if fluke == 0 else 1.0
            var fluke_pts: PackedVector2Array = PackedVector2Array()
            fluke_pts.append(Vector2(tail_x, tail_y))
            fluke_pts.append(Vector2(tail_x - 30, tail_y + (25 + tail_swing) * fluke_dir))
            fluke_pts.append(Vector2(tail_x - 50, tail_y + (15 + tail_swing * 0.5) * fluke_dir))
            var col = _hue_color(hue, 0.35, 0.45, 0.15)
            if fluke_pts.size() >= 3:
                draw_colored_polygon(fluke_pts, col)





func _init_void_kraken():
    var tentacle_count = _param_i("tentacle_count", 8)
    var hue = _param_f("color", 0.8)
    for i in tentacle_count:
        var edge = _rng.randi_range(0, 3)
        var origin: Vector2
        match edge:
            0: origin = Vector2(_rng.randf_range(0, size.x), -20)
            1: origin = Vector2(size.x + 20, _rng.randf_range(0, size.y))
            2: origin = Vector2(_rng.randf_range(0, size.x), size.y + 20)
            3: origin = Vector2(-20, _rng.randf_range(0, size.y))
        var target = _screen_center() + Vector2(_rng.randf_range(-150, 150), _rng.randf_range(-150, 150))
        _entities.append({
            "origin": origin, 
            "target": target, 
            "hue": hue + _rng.randf_range(-0.05, 0.05), 
            "width": _rng.randf_range(8, 22), 
            "seg_count": _rng.randi_range(15, 25), 
            "phase": _rng.randf() * TAU, 
            "node_positions": [], 
            "luminous_nodes": _rng.randi_range(3, 6), 
        })

func _draw_void_kraken():
    var hue = _param_f("color", 0.8)

    var center = _screen_center()
    var dark_pulse = sin(_time * 0.7) * 0.05 + 0.2
    for r_layer in 4:
        var r = 180.0 - float(r_layer) * 40.0
        draw_circle(center, r, Color(0, 0, 0, dark_pulse * (1.0 + float(r_layer) * 0.3)))

    for tent in _entities:
        var origin = tent.origin
        var target = tent.target
        var seg_count = tent.seg_count
        var w = tent.width
        var phase = tent.phase


        var reach = minf(_time * 0.15, 1.0)

        var prev_pt = origin
        var luminous_spacing = maxf(1, seg_count / tent.luminous_nodes)
        for seg in range(1, seg_count + 1):
            var frac = float(seg) / float(seg_count)
            var base_pt = origin.lerp(target, frac * reach)

            var writhe_x = sin(_time * 1.5 + frac * 5.0 + phase) * (20.0 + frac * 30.0)
            var writhe_y = cos(_time * 1.8 + frac * 4.0 + phase * 1.3) * (15.0 + frac * 25.0)
            var pt = base_pt + Vector2(writhe_x, writhe_y)
            var seg_w = w * (1.0 - frac * 0.6)
            var alpha = 0.5 * (1.0 - frac * 0.3)
            var col = _hue_color(tent.hue, 0.4, 0.3, alpha)
            draw_line(prev_pt, pt, col, seg_w)

            draw_line(prev_pt + Vector2(0, seg_w * 0.3), pt + Vector2(0, seg_w * 0.3), Color(col.r, col.g, col.b, alpha * 0.5), seg_w * 0.6)


            if seg % luminous_spacing == 0:
                var node_pulse = sin(_time * 3.0 + frac * 4.0 + phase) * 0.4 + 0.6
                var node_col = _hue_color(tent.hue + 0.1, 0.5, 1.0, 0.5 * node_pulse)
                _draw_glow_circle(pt, 4.0 + seg_w * 0.15, node_col, 3)

            prev_pt = pt


        var tip_pulse = sin(_time * 4.0 + phase) * 0.3 + 0.7
        var tip_col = _hue_color(tent.hue + 0.15, 0.6, 1.0, 0.6 * tip_pulse * reach)
        _draw_glow_circle(prev_pt, 5.0, tip_col, 2)





func _init_ion_storm():
    var intensity = _param_f("intensity", 1.0)

    for i in int(6 * intensity):
        _entities.append({
            "type": "bolt", 
            "start": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y * 0.3)), 
            "end": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(size.y * 0.5, size.y)), 
            "phase": _rng.randf() * TAU, 
            "branch_count": _rng.randi_range(2, 5), 
            "lifetime": _rng.randf_range(0.8, 2.5), 
            "timer": _rng.randf_range(0, 3.0), 
        })

    for i in int(30 * intensity):
        _particles.append({
            "pos": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)), 
            "vel": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(10, 40)), 
            "sz": _rng.randf_range(15, 45), 
            "alpha": _rng.randf_range(0.03, 0.08), 
            "phase": _rng.randf() * TAU, 
        })

func _draw_ion_storm():
    var hue = _param_f("color", 0.6)
    var intensity = _param_f("intensity", 1.0)


    var wall_y = size.y * 0.2 + sin(_time * 0.3) * 30
    var wall_alpha = 0.08 * intensity
    draw_rect(Rect2(0, 0, size.x, wall_y), _hue_color(hue, 0.4, 0.3, wall_alpha))

    for i in 20:
        var wx = float(i) / 20.0 * size.x
        var wy = wall_y + sin(_time * 5.0 + float(i) * 2.3) * 8.0
        var spark_col = _hue_color(hue, 0.5, 1.0, 0.3 + sin(_time * 8.0 + float(i)) * 0.2)
        draw_circle(Vector2(wx, wy), 2.0, spark_col)


    for p in _particles:
        var pulse = sin(_time * 1.5 + p.phase) * 0.03 + p.alpha
        var col = _hue_color(hue, 0.3, 0.5, pulse)
        draw_circle(p.pos, p.sz, col)


    for bolt in _entities:
        bolt.timer += 0.016
        if fmod(bolt.timer, bolt.lifetime) > bolt.lifetime * 0.85:

            _draw_lightning_bolt(bolt.start, bolt.end, hue, bolt.branch_count, intensity)


    for i in 3:
        var arc_phase = _time * 2.0 + float(i) * 2.0
        if sin(arc_phase) > 0.7:
            var ax1 = _rng.randf_range(size.x * 0.1, size.x * 0.9)
            var ax2 = ax1 + sin(arc_phase * 3) * 200
            var ay1 = size.y * 0.1
            var ay2 = size.y * 0.6
            _draw_lightning_bolt(Vector2(ax1, ay1), Vector2(ax2, ay2), hue + 0.05, 1, intensity * 0.6)

func _draw_lightning_bolt(start: Vector2, end: Vector2, hue: float, branches: int, intensity: float):
    var seg_count = 12
    var deviation = 40.0 * intensity
    var pts: PackedVector2Array = PackedVector2Array()
    pts.append(start)
    for seg in range(1, seg_count):
        var frac = float(seg) / float(seg_count)
        var base = start.lerp(end, frac)
        var offset = Vector2(
            sin(_time * 15.0 + frac * 7.0 + start.x * 0.01) * deviation, 
            cos(_time * 12.0 + frac * 5.0 + start.y * 0.01) * deviation * 0.5)
        pts.append(base + offset)
    pts.append(end)

    var bolt_col = _hue_color(hue, 0.4, 1.0, 0.7)
    var glow_col = _hue_color(hue, 0.3, 1.0, 0.2)
    for i in range(pts.size() - 1):
        draw_line(pts[i], pts[i + 1], bolt_col, 2.0)
        draw_line(pts[i], pts[i + 1], glow_col, 6.0)

    for b in branches:
        var branch_start_idx = _rng.randi_range(2, pts.size() - 3) if pts.size() > 4 else 1
        var branch_start = pts[branch_start_idx]
        var branch_dir = (end - start).normalized().rotated(_rng.randf_range(-0.8, 0.8))
        var branch_end = branch_start + branch_dir * _rng.randf_range(30, 80)
        var branch_col = _hue_color(hue, 0.5, 0.9, 0.4)
        var branch_segs = 4
        var bprev = branch_start
        for bs in range(1, branch_segs + 1):
            var bf = float(bs) / float(branch_segs)
            var bpt = branch_start.lerp(branch_end, bf) + Vector2(sin(_time * 20 + bf * 5) * 10, cos(_time * 18 + bf * 3) * 8)
            draw_line(bprev, bpt, branch_col, 1.0)
            bprev = bpt





func _init_gravitational_lens():
    var ring_count = _param_i("ring_count", 2)
    var strength = _param_f("strength", 1.0)
    _entities.append({
        "ring_count": ring_count, 
        "strength": strength, 
    })

func _draw_gravitational_lens():
    var center = _screen_center()
    var strength = _param_f("strength", 1.0)
    var ring_count = _param_i("ring_count", 2)


    for s in _bg_stars:
        var to_center = center - s.pos
        var dist = to_center.length()
        if dist < 10:
            continue
        var warp_amount = strength * 8000.0 / (dist * dist + 100.0)
        var warped_pos = s.pos + to_center.normalized() * warp_amount

        var bright_boost = clampf(200.0 / (dist + 50.0), 0.0, 0.8) * strength
        var alpha = s.brightness + bright_boost
        draw_circle(warped_pos, s.sz * (1.0 + bright_boost * 0.5), Color(1, 1, 1, alpha))

        if dist < 200 * strength:
            var tangent = Vector2( - to_center.y, to_center.x).normalized()
            var stretch = warped_pos + tangent * warp_amount * 0.3
            draw_circle(stretch, s.sz * 0.5, Color(1, 1, 1, alpha * 0.3))


    for ring_i in ring_count:
        var ring_r = 80.0 + float(ring_i) * 60.0
        var ring_pulse = sin(_time * 0.8 + float(ring_i) * 1.5) * 5.0
        var r = ring_r + ring_pulse

        var arc_count = 3 + ring_i
        for arc_i in arc_count:
            var a_start = float(arc_i) * TAU / float(arc_count) + _time * 0.1 * (1.0 + float(ring_i) * 0.3)
            var a_span = TAU / float(arc_count) * 0.6
            var arc_alpha = 0.3 + sin(_time * 1.5 + float(arc_i)) * 0.15
            draw_arc(center, r, a_start, a_start + a_span, 20, Color(0.8, 0.85, 1.0, arc_alpha), 1.5 + float(ring_i) * 0.5)

            draw_arc(center, r, a_start, a_start + a_span, 20, Color(0.6, 0.7, 1.0, arc_alpha * 0.3), 5.0)


    for rip in 5:
        var rip_r = 30.0 + float(rip) * 50.0 + sin(_time * 0.5 + float(rip)) * 10.0
        var rip_alpha = 0.05 + sin(_time * 1.0 + float(rip) * 0.8) * 0.03
        draw_arc(center, rip_r, 0, TAU, 32, Color(0.5, 0.6, 0.9, rip_alpha), 1.0)


    draw_circle(center, 15.0, Color(0, 0, 0, 0.9))
    draw_circle(center, 20.0, Color(0, 0, 0, 0.4))





func _init_nebula():
    var hue1 = _param_f("color1", 0.75)
    var hue2 = _param_f("color2", 0.55)
    var density = _param_f("density", 1.0)
    var proto_stars = _param_i("proto_stars", 2)

    var cloud_count = int(15 * density)
    for i in cloud_count:
        _shapes.append({
            "pos": Vector2(_rng.randf_range(size.x * 0.1, size.x * 0.9), _rng.randf_range(size.y * 0.1, size.y * 0.9)), 
            "radius": _rng.randf_range(60, 180), 
            "hue": lerpf(hue1, hue2, _rng.randf()), 
            "alpha": _rng.randf_range(0.02, 0.06), 
            "drift": Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-2, 2)), 
            "phase": _rng.randf() * TAU, 
        })

    for i in proto_stars:
        _entities.append({
            "pos": Vector2(_rng.randf_range(size.x * 0.2, size.x * 0.8), _rng.randf_range(size.y * 0.2, size.y * 0.8)), 
            "brightness": _rng.randf_range(0.5, 1.0), 
            "pulse_phase": _rng.randf() * TAU, 
            "hue": lerpf(hue1, hue2, _rng.randf()), 
        })

    for i in int(40 * density):
        _particles.append({
            "pos": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)), 
            "vel": Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-3, 3)), 
            "sz": _rng.randf_range(1, 3), 
            "hue": lerpf(hue1, hue2, _rng.randf()), 
            "alpha": _rng.randf_range(0.1, 0.3), 
            "phase": _rng.randf() * TAU, 
        })

func _draw_nebula():

    for cloud in _shapes:
        var pos = cloud.pos + cloud.drift * _time
        var pulse = sin(_time * 0.5 + cloud.phase) * 0.15 + 0.85
        var r = cloud.radius * pulse
        for layer in 4:
            var lr = r * (1.0 - float(layer) * 0.15)
            var la = cloud.alpha * (1.0 - float(layer) * 0.2)
            var col = _hue_color(cloud.hue + float(layer) * 0.02, 0.4, 0.5, la)
            draw_circle(pos, lr, col)


    for p in _particles:
        var pulse = sin(_time * 2.0 + p.phase) * 0.15 + 0.85
        var col = _hue_color(p.hue, 0.4, 0.8, p.alpha * pulse)
        draw_circle(p.pos, p.sz, col)


    for star in _entities:
        var pulse = sin(_time * 1.5 + star.pulse_phase) * 0.3 + 0.7
        var bright = star.brightness * pulse
        var col = _hue_color(star.hue, 0.3, 1.0, bright * 0.8)
        _draw_glow_circle(star.pos, 6.0 * bright, col, 4)





func _init_ghost_fleet():
    var count = _param_i("count", 15)
    var opacity = _param_f("opacity", 0.2)
    for i in count:
        _entities.append({
            "pos": Vector2(_rng.randf_range(size.x * 0.05, size.x * 0.95), _rng.randf_range(size.y * 0.05, size.y * 0.95)), 
            "angle": _rng.randf_range(-0.3, 0.3), 
            "ship_scale": _rng.randf_range(8, 25), 
            "opacity": opacity * _rng.randf_range(0.5, 1.5), 
            "flicker_phase": _rng.randf() * TAU, 
            "flicker_speed": _rng.randf_range(1.0, 3.0), 
            "drift": Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-5, 5)), 
        })

func _draw_ghost_fleet():
    var hue = _param_f("color", 0.6)
    for ship in _entities:
        var pos = ship.pos + ship.drift * _time

        pos.x = fmod(pos.x + size.x, size.x)
        pos.y = fmod(pos.y + size.y, size.y)

        var flicker = sin(_time * ship.flicker_speed + ship.flicker_phase)
        if flicker < -0.3:
            continue
        var alpha = ship.opacity * clampf(flicker * 0.5 + 0.5, 0.05, 1.0)
        var col = _hue_color(hue, 0.2, 0.7, alpha)
        var wire_col = _hue_color(hue, 0.3, 0.9, alpha * 0.8)
        var s = ship.ship_scale
        var angle = ship.angle


        var pts: PackedVector2Array = PackedVector2Array()
        pts.append(pos + Vector2(s * 2.0, 0).rotated(angle))
        pts.append(pos + Vector2( - s, - s * 0.8).rotated(angle))
        pts.append(pos + Vector2( - s * 0.5, 0).rotated(angle))
        pts.append(pos + Vector2( - s, s * 0.8).rotated(angle))

        draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha * 0.15))

        for ei in pts.size():
            draw_line(pts[ei], pts[(ei + 1) % pts.size()], wire_col, 1.0)

        draw_circle(pos, 2.0, _hue_color(hue, 0.1, 1.0, alpha * 0.6))





func _init_megastructure():
    var shape = _param_s("shape", "monolith")
    _entities.append({"shape": shape})

func _draw_megastructure():
    var shape = _param_s("shape", "monolith")
    var hue = _param_f("color", 0.6)
    var has_glow = _param_b("glow", true)
    var center = _screen_center()
    var rot = _time * 0.1

    match shape:
        "monolith":
            _draw_mega_monolith(center, hue, has_glow, rot)
        "ring":
            _draw_mega_ring(center, hue, has_glow, rot)
        "sphere":
            _draw_mega_sphere(center, hue, has_glow, rot)
        "lattice":
            _draw_mega_lattice(center, hue, has_glow, rot)
        _:
            _draw_mega_monolith(center, hue, has_glow, rot)

func _draw_mega_monolith(center: Vector2, hue: float, has_glow: bool, rot: float):
    var h = 300.0
    var w = 80.0

    var tl = center + Vector2( - w * 0.5, - h * 0.5).rotated(rot * 0.1)
    var top_right = center + Vector2(w * 0.5, - h * 0.5).rotated(rot * 0.1)
    var br = center + Vector2(w * 0.55, h * 0.5).rotated(rot * 0.1)
    var bl = center + Vector2( - w * 0.55, h * 0.5).rotated(rot * 0.1)
    var pts: PackedVector2Array = PackedVector2Array([tl, top_right, br, bl])
    draw_colored_polygon(pts, Color(0.01, 0.01, 0.02, 0.95))

    var edge_col = _hue_color(hue, 0.3, 0.6, 0.5)
    for i in pts.size():
        draw_line(pts[i], pts[(i + 1) % pts.size()], edge_col, 1.5)

    for i in 8:
        var frac = float(i + 1) / 9.0
        var ly = tl.y + (bl.y - tl.y) * frac
        var lx1 = tl.x + (bl.x - tl.x) * frac
        var lx2 = top_right.x + (br.x - top_right.x) * frac
        draw_line(Vector2(lx1, ly), Vector2(lx2, ly), Color(0.15, 0.15, 0.2, 0.2), 0.5)
    if has_glow:

        for i in 6:
            var gy = center.y + sin(_time * 1.5 + float(i) * 1.0) * h * 0.4
            var gx = center.x + w * 0.55
            var pulse = sin(_time * 2.0 + float(i)) * 0.3 + 0.7
            draw_circle(Vector2(gx, gy), 3.0 * pulse, _hue_color(hue, 0.5, 1.0, 0.4 * pulse))
            draw_circle(Vector2(center.x - w * 0.55, gy), 3.0 * pulse, _hue_color(hue, 0.5, 1.0, 0.4 * pulse))

func _draw_mega_ring(center: Vector2, hue: float, has_glow: bool, rot: float):
    var ring_r = 150.0

    draw_arc(center, ring_r, rot, rot + TAU, 48, _hue_color(hue, 0.3, 0.5, 0.4), 12.0)
    draw_arc(center, ring_r - 8, rot, rot + TAU, 48, Color(0.02, 0.02, 0.03, 0.8), 4.0)
    draw_arc(center, ring_r + 8, rot, rot + TAU, 48, _hue_color(hue, 0.4, 0.7, 0.3), 1.5)
    draw_arc(center, ring_r - 12, rot, rot + TAU, 48, _hue_color(hue, 0.4, 0.7, 0.3), 1.5)

    for i in 8:
        var a = float(i) * TAU / 8.0 + rot
        var npos = center + Vector2.from_angle(a) * ring_r
        var pulse = sin(_time * 2.0 + float(i)) * 0.3 + 0.7
        draw_circle(npos, 4.0 * pulse, _hue_color(hue, 0.5, 1.0, 0.5 * pulse))
    if has_glow:

        var core_pulse = sin(_time * 1.5) * 0.3 + 0.7
        _draw_glow_circle(center, 20.0 * core_pulse, _hue_color(hue, 0.4, 1.0, 0.3 * core_pulse), 4)

        for i in 4:
            var a = float(i) * TAU / 4.0 + _time * 0.3
            var p1 = center + Vector2.from_angle(a) * ring_r
            var p2 = center + Vector2.from_angle(a + PI) * ring_r
            var beam_alpha = sin(_time * 2.5 + float(i)) * 0.15 + 0.15
            draw_line(p1, p2, _hue_color(hue, 0.3, 1.0, beam_alpha), 1.5)

func _draw_mega_sphere(center: Vector2, hue: float, has_glow: bool, rot: float):
    var radius = 120.0

    var lat_count = 8
    var lon_count = 12

    for i in lat_count:
        var lat = -1.0 + 2.0 * float(i + 1) / float(lat_count + 1)
        var r = radius * sqrt(1.0 - lat * lat)
        var cy = center.y + lat * radius
        var alpha = 0.2 + absf(lat) * 0.1
        draw_arc(Vector2(center.x, cy), r, 0, TAU, 24, _hue_color(hue, 0.3, 0.6, alpha), 1.0)

    for i in lon_count:
        var lon_angle = float(i) * TAU / float(lon_count) + rot
        var pts: PackedVector2Array = PackedVector2Array()
        for seg in 25:
            var t = float(seg) / 24.0 * PI
            var px = center.x + sin(lon_angle) * sin(t) * radius
            var py = center.y - cos(t) * radius
            pts.append(Vector2(px, py))
        for j in range(pts.size() - 1):
            draw_line(pts[j], pts[j + 1], _hue_color(hue, 0.3, 0.6, 0.2), 1.0)
    if has_glow:

        var pulse = sin(_time * 1.2) * 0.2 + 0.5
        _draw_glow_circle(center, radius * 0.4, _hue_color(hue, 0.3, 0.8, 0.1 * pulse), 4)

func _draw_mega_lattice(center: Vector2, hue: float, has_glow: bool, _rot: float):

    var grid_size = 8
    var spacing = 50.0
    var half = float(grid_size) * spacing * 0.5
    for i in range(grid_size + 1):
        for j in range(grid_size + 1):
            var gx = center.x - half + float(i) * spacing
            var gy = center.y - half + float(j) * spacing
            var node_pos = Vector2(gx, gy)

            if i < grid_size:
                var next_pos = Vector2(gx + spacing, gy)
                var line_alpha = 0.15 + sin(_time * 1.0 + float(i + j) * 0.5) * 0.08
                draw_line(node_pos, next_pos, _hue_color(hue, 0.3, 0.6, line_alpha), 1.0)

            if j < grid_size:
                var next_pos = Vector2(gx, gy + spacing)
                var line_alpha = 0.15 + sin(_time * 1.0 + float(i + j) * 0.5) * 0.08
                draw_line(node_pos, next_pos, _hue_color(hue, 0.3, 0.6, line_alpha), 1.0)

            if has_glow:
                var pulse = sin(_time * 2.0 + float(i) * 1.3 + float(j) * 0.7) * 0.4 + 0.6
                draw_circle(node_pos, 2.5 * pulse, _hue_color(hue, 0.5, 1.0, 0.4 * pulse))





func _init_dimensional_tear():
    var width = _param_f("width", 1.0)

    var center = _screen_center()
    var point_count = 15
    for i in point_count:
        var frac = float(i) / float(point_count - 1) - 0.5
        var base_y = center.y + frac * size.y * 0.7
        var base_x = center.x + sin(frac * 3.0) * 30.0 * width
        _shapes.append({
            "pos": Vector2(base_x, base_y), 
            "jag_x": _rng.randf_range(-25, 25) * width, 
            "jag_phase": _rng.randf() * TAU, 
        })

func _draw_dimensional_tear():
    var hue = _param_f("color", 0.85)
    var width = _param_f("width", 1.0)
    var crackling = _param_b("crackling", true)
    var center = _screen_center()


    var tear_pts_left: PackedVector2Array = PackedVector2Array()
    var tear_pts_right: PackedVector2Array = PackedVector2Array()
    for i in _shapes.size():
        var shape = _shapes[i]
        var jag = sin(_time * 2.0 + shape.jag_phase) * shape.jag_x
        var pos = shape.pos + Vector2(jag, 0)
        tear_pts_left.append(pos + Vector2(-15 * width, 0))
        tear_pts_right.append(pos + Vector2(15 * width, 0))


    if tear_pts_left.size() >= 3 and tear_pts_right.size() >= 3:
        var fill_pts: PackedVector2Array = PackedVector2Array()
        for pt in tear_pts_left:
            fill_pts.append(pt)
        for i in range(tear_pts_right.size() - 1, -1, -1):
            fill_pts.append(tear_pts_right[i])
        var alien_col = _hue_color(hue, 0.8, 0.6, 0.25 + sin(_time * 1.5) * 0.1)
        if fill_pts.size() >= 3:
            draw_colored_polygon(fill_pts, alien_col)


    for side in 2:
        var pts = tear_pts_left if side == 0 else tear_pts_right
        if pts.size() < 2:
            continue
        for i in range(pts.size() - 1):
            var rift_col = _hue_color(hue + 0.1, 0.6, 1.0, 0.6 + sin(_time * 3.0 + float(i)) * 0.2)
            draw_line(pts[i], pts[i + 1], rift_col, 2.0)

            draw_line(pts[i], pts[i + 1], Color(rift_col.r, rift_col.g, rift_col.b, 0.15), 8.0)


    if crackling:
        for i in _shapes.size():
            if sin(_time * 5.0 + float(i) * 2.3) > 0.5:
                var shape = _shapes[i]
                var jag = sin(_time * 2.0 + shape.jag_phase) * shape.jag_x
                var pos = shape.pos + Vector2(jag, 0)
                var spark_dir = Vector2(sin(_time * 8.0 + float(i)) * 30, cos(_time * 6.0 + float(i)) * 15)
                var spark_col = _hue_color(hue + 0.15, 0.7, 1.0, 0.5)
                draw_line(pos, pos + spark_dir, spark_col, 1.0)
                draw_line(pos, pos - spark_dir * 0.7, spark_col, 1.0)


    for s in _bg_stars:
        var dist_to_tear = absf(s.pos.x - center.x)
        if dist_to_tear < 100 * width:
            var distort = (100 * width - dist_to_tear) / (100 * width)
            var warped = s.pos + Vector2(sin(_time * 3.0 + s.pos.y * 0.05) * 10 * distort, 0)
            draw_circle(warped, s.sz * 1.5, _hue_color(hue, 0.3, 1.0, s.brightness * distort * 0.5))





func _init_spore_cloud():
    var hue = _param_f("color", 0.33)
    var density = _param_i("density", 200)
    var glow = _param_f("glow_intensity", 1.0)
    for i in density:
        var angle = _rng.randf() * TAU
        var dist = _rng.randf_range(0, size.x * 0.5)

        dist = dist * dist / (size.x * 0.5)
        _particles.append({
            "pos": _screen_center() + Vector2.from_angle(angle) * dist, 
            "vel": Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-6, 6)), 
            "sz": _rng.randf_range(1.0, 3.5), 
            "hue": hue + _rng.randf_range(-0.06, 0.06), 
            "alpha": _rng.randf_range(0.2, 0.6) * glow, 
            "phase": _rng.randf() * TAU, 
            "cluster_id": _rng.randi_range(0, 4), 
        })

func _draw_spore_cloud():
    var hue = _param_f("color", 0.33)

    for i in 6:
        var cloud_pos = _screen_center() + Vector2(sin(_time * 0.3 + float(i) * 1.5) * 80, cos(_time * 0.4 + float(i) * 1.2) * 60)
        var cloud_r = 120 + sin(_time * 0.5 + float(i)) * 20
        draw_circle(cloud_pos, cloud_r, _hue_color(hue, 0.3, 0.3, 0.04))


    for p in _particles:
        var pulse = sin(_time * 2.5 + p.phase) * 0.3 + 0.7
        var col = _hue_color(p.hue, 0.5, 0.8, p.alpha * pulse)
        draw_circle(p.pos, p.sz, col)

        if p.sz > 2.0:
            draw_circle(p.pos, p.sz * 2.5, Color(col.r, col.g, col.b, p.alpha * pulse * 0.15))





func _init_crystalline():
    var count = _param_i("count", 8)
    var sz_scale = _param_f("size_scale", 1.0)
    for i in count:
        var vert_count = _rng.randi_range(5, 8)
        var verts = []
        for v in vert_count:
            var a = float(v) * TAU / float(vert_count) + _rng.randf_range(-0.2, 0.2)
            var r = _rng.randf_range(20, 50) * sz_scale
            verts.append({"angle": a, "dist": r})
        _entities.append({
            "pos": Vector2(_rng.randf_range(size.x * 0.1, size.x * 0.9), _rng.randf_range(size.y * 0.1, size.y * 0.9)), 
            "verts": verts, 
            "rot_speed": _rng.randf_range(-0.3, 0.3), 
            "hue": _rng.randf() if _param_b("color_shift", false) else _param_f("color", 0.55), 
            "hue_speed": 0.1 if _param_b("color_shift", false) else 0.0, 
            "sparkle_phase": _rng.randf() * TAU, 
        })

func _draw_crystalline():
    var color_shift = _param_b("color_shift", false)
    for crystal in _entities:
        var hue = crystal.hue + crystal.hue_speed * _time if color_shift else crystal.hue
        var rot = crystal.rot_speed * _time
        var pos = crystal.pos


        var pts: PackedVector2Array = PackedVector2Array()
        for v in crystal.verts:
            var a = v.angle + rot
            pts.append(pos + Vector2.from_angle(a) * v.dist)

        if pts.size() < 3:
            continue


        var fill_col = _hue_color(hue, 0.4, 0.5, 0.12)
        draw_colored_polygon(pts, fill_col)


        for i in pts.size():
            var edge_hue = hue + float(i) * 0.04
            var edge_col = _hue_color(edge_hue, 0.5, 0.9, 0.5)
            draw_line(pts[i], pts[(i + 1) % pts.size()], edge_col, 1.5)


        for i in pts.size():
            var facet_center = (pts[i] + pts[(i + 1) % pts.size()]) * 0.5
            var outward = (facet_center - pos).normalized()
            var refract_len = 30 + sin(_time * 2.0 + float(i)) * 15
            var refract_col = _hue_color(hue + float(i) * 0.08, 0.8, 1.0, 0.2 + sin(_time * 3.0 + float(i)) * 0.1)
            draw_line(facet_center, facet_center + outward * refract_len, refract_col, 1.0)


        for i in pts.size():
            var sparkle = sin(_time * 5.0 + crystal.sparkle_phase + float(i) * 1.5)
            if sparkle > 0.6:
                var sp_alpha = (sparkle - 0.6) / 0.4
                var sp_col = Color(1, 1, 1, sp_alpha * 0.7)
                draw_circle(pts[i], 3.0, sp_col)

                var sp_len = 8.0 * sp_alpha
                draw_line(pts[i] - Vector2(sp_len, 0), pts[i] + Vector2(sp_len, 0), sp_col, 1.0)
                draw_line(pts[i] - Vector2(0, sp_len), pts[i] + Vector2(0, sp_len), sp_col, 1.0)





func _init_solar_event():
    var event_type = _param_s("type", "flare")
    var intensity = _param_f("intensity", 1.0)
    _entities.append({"type": event_type, "intensity": intensity})

    for i in int(40 * intensity):
        var angle = _rng.randf_range(-0.5, 0.5)
        var speed = _rng.randf_range(30, 150) * intensity
        _particles.append({
            "pos": Vector2( - size.x * 0.05, size.y * 0.5), 
            "vel": Vector2(speed, 0).rotated(angle), 
            "sz": _rng.randf_range(1.5, 4.0), 
            "alpha": _rng.randf_range(0.2, 0.5), 
            "phase": _rng.randf() * TAU, 
            "life": _rng.randf_range(2.0, 8.0), 
        })

func _draw_solar_event():
    var hue = _param_f("color", 0.08)
    var event_type = _param_s("type", "flare")
    var intensity = _param_f("intensity", 1.0)


    var star_pos = Vector2(-30, size.y * 0.5)
    var star_r = 120.0


    for layer in 8:
        var lr = star_r + float(layer) * 30
        var la = 0.06 * (1.0 - float(layer) / 8.0) * intensity
        var pulse = sin(_time * 1.5 + float(layer)) * 0.02 + 1.0
        draw_circle(star_pos, lr * pulse, _hue_color(hue, 0.5 - float(layer) * 0.04, 0.9, la))


    draw_circle(star_pos, star_r, _hue_color(hue, 0.3, 1.0, 0.8))
    draw_circle(star_pos, star_r * 0.8, Color(1, 0.95, 0.85, 0.4))


    match event_type:
        "flare":
            _draw_solar_flare(star_pos, star_r, hue, intensity)
        "birth":
            _draw_star_birth(star_pos, star_r, hue, intensity)
        "prominence":
            _draw_solar_prominence(star_pos, star_r, hue, intensity)
        _:
            _draw_solar_flare(star_pos, star_r, hue, intensity)


    for p in _particles:
        if p.has("life") and p.life <= 0:
            continue
        var pulse = sin(_time * 3.0 + p.phase) * 0.2 + 0.8
        var col = _hue_color(hue, 0.5, 1.0, p.alpha * pulse)
        draw_circle(p.pos, p.sz, col)

func _draw_solar_flare(star_pos: Vector2, star_r: float, hue: float, intensity: float):
    for flare_i in 3:
        var flare_angle = sin(_time * 0.3 + float(flare_i) * 2.0) * 0.8
        var flare_len = 150 + sin(_time * 0.5 + float(flare_i)) * 50
        flare_len *= intensity
        var seg_count = 20
        var prev_pt = star_pos + Vector2.from_angle(flare_angle) * star_r
        for seg in range(1, seg_count + 1):
            var frac = float(seg) / float(seg_count)
            var arc_angle = flare_angle + frac * 1.5
            var r = star_r + frac * flare_len
            var pt = star_pos + Vector2.from_angle(arc_angle) * r
            var alpha = (1.0 - frac) * 0.4 * intensity
            var col = _hue_color(hue + frac * 0.05, 0.6, 1.0, alpha)
            draw_line(prev_pt, pt, col, 3.0 * (1.0 - frac * 0.5))
            prev_pt = pt

func _draw_star_birth(star_pos: Vector2, star_r: float, hue: float, intensity: float):

    for wave_i in 4:
        var wave_r = star_r * 2 + float(wave_i) * 80 - fmod(_time * 40, 320)
        if wave_r < star_r:
            wave_r += 320
        var wave_alpha = 0.1 * (1.0 - clampf((wave_r - star_r) / 300.0, 0, 1)) * intensity
        draw_arc(star_pos, wave_r, - PI * 0.4, PI * 0.4, 20, _hue_color(hue, 0.4, 1.0, wave_alpha), 2.0)

func _draw_solar_prominence(star_pos: Vector2, star_r: float, hue: float, intensity: float):

    var seg_count = 30
    var arc_height = 200.0 * intensity
    var prev_pt = star_pos + Vector2(star_r, -20)
    for seg in range(1, seg_count + 1):
        var frac = float(seg) / float(seg_count)
        var px = star_pos.x + star_r + frac * 300 * intensity
        var arc = sin(frac * PI) * arc_height
        var wave = sin(_time * 2.0 + frac * 5.0) * 10.0
        var py = star_pos.y - 20 - arc + wave
        var pt = Vector2(px, py)
        var alpha = sin(frac * PI) * 0.5 * intensity
        var w = (4.0 + sin(frac * PI) * 6.0) * intensity
        draw_line(prev_pt, pt, _hue_color(hue, 0.6, 1.0, alpha), w)

        draw_line(prev_pt, pt, _hue_color(hue, 0.4, 1.0, alpha * 0.2), w * 3)
        prev_pt = pt





func _init_swarm():
    var count = _param_i("count", 500)
    var _behavior = _param_s("behavior", "murmuration")
    count = mini(count, 2000)
    for i in count:
        _particles.append({
            "pos": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)), 
            "vel": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)), 
            "sz": _rng.randf_range(1.0, 2.5), 
            "phase": _rng.randf() * TAU, 
            "orbit_r": _rng.randf_range(50, 300), 
            "orbit_speed": _rng.randf_range(0.3, 1.2) * (1.0 if _rng.randf() > 0.5 else -1.0), 
        })

func _draw_swarm():
    var hue = _param_f("color", 0.55)
    var behavior = _param_s("behavior", "murmuration")
    var center = _screen_center()

    for p in _particles:
        var pos: Vector2
        match behavior:
            "murmuration":

                var angle = p.phase + _time * p.orbit_speed
                var r = p.orbit_r + sin(_time * 0.8 + p.phase * 2.0) * 50.0
                pos = center + Vector2(cos(angle) * r, sin(angle * 0.7 + _time * 0.3) * r * 0.6)
            "converge":

                var t = clampf(_time * 0.1, 0, 1)
                pos = p.pos.lerp(center, t) + Vector2(sin(_time * 3 + p.phase) * 20 * (1 - t), cos(_time * 2.5 + p.phase) * 15 * (1 - t))
            "scatter":

                var dir = (p.pos - center).normalized()
                pos = p.pos + dir * _time * 15 + Vector2(sin(_time * 2 + p.phase) * 10, cos(_time * 1.5 + p.phase) * 8)
            _:
                pos = p.pos + p.vel * _time

        var pulse = sin(_time * 3.0 + p.phase) * 0.2 + 0.8
        var col = _hue_color(hue + sin(p.phase) * 0.05, 0.4, 0.8, 0.5 * pulse)
        draw_circle(pos, p.sz, col)





func _init_darkness():
    var edge_shapes = _param_b("edge_shapes", false)
    if edge_shapes:
        for i in 6:
            var edge = _rng.randi_range(0, 3)
            var pos: Vector2
            match edge:
                0: pos = Vector2(_rng.randf_range(0, size.x), _rng.randf_range(-50, 50))
                1: pos = Vector2(_rng.randf_range(size.x - 50, size.x + 50), _rng.randf_range(0, size.y))
                2: pos = Vector2(_rng.randf_range(0, size.x), _rng.randf_range(size.y - 50, size.y + 50))
                3: pos = Vector2(_rng.randf_range(-50, 50), _rng.randf_range(0, size.y))
            _entities.append({
                "pos": pos, 
                "shape_radius": _rng.randf_range(60, 150), 
                "drift": (_screen_center() - pos).normalized() * _rng.randf_range(2, 8), 
                "phase": _rng.randf() * TAU, 
            })

func _draw_darkness():
    var intensity = _param_f("intensity", 0.7)
    var edge_shapes = _param_b("edge_shapes", false)
    var center = _screen_center()


    var dark_progress = minf(_time * 0.08, 1.0) * intensity
    for s in _bg_stars:
        var fade = maxf(0, s.brightness * (1.0 - dark_progress))
        if fade > 0.01:
            draw_circle(s.pos, s.sz, Color(1, 1, 1, fade))


    draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dark_progress * 0.5))


    var light_r = 80.0 * (1.0 - dark_progress * 0.5)
    var light_pulse = sin(_time * 2.0) * 0.1 + 0.9
    for layer in 5:
        var lr = light_r * (1.0 + float(layer) * 0.5)
        var la = 0.06 * (1.0 - float(layer) / 5.0) * light_pulse
        draw_circle(center, lr, Color(0.8, 0.85, 0.9, la))
    draw_circle(center, 4.0, Color(0.9, 0.95, 1.0, 0.6 * light_pulse))


    if edge_shapes:
        for shape in _entities:
            var pos = shape.pos + shape.drift * _time
            var r = shape.shape_radius + sin(_time * 0.8 + shape.phase) * 20
            var alpha = dark_progress * 0.3

            for blob in 4:
                var offset = Vector2(sin(shape.phase + float(blob) * 1.5) * r * 0.3, 
                    cos(shape.phase + float(blob) * 1.2) * r * 0.3)
                draw_circle(pos + offset, r * 0.6, Color(0, 0, 0, alpha))





func _init_derelict():
    var _derelict_type = _param_s("type", "wreck")
    var count = _param_i("count", 3)
    var organic = _param_b("organic", false)
    for i in count:
        var hull_points = []
        var vert_count = _rng.randi_range(5, 9)
        for v in vert_count:
            var a = float(v) * TAU / float(vert_count) + _rng.randf_range(-0.3, 0.3)
            var r = _rng.randf_range(15, 50)
            hull_points.append({"angle": a, "dist": r})
        _entities.append({
            "pos": Vector2(_rng.randf_range(size.x * 0.1, size.x * 0.9), _rng.randf_range(size.y * 0.1, size.y * 0.9)), 
            "hull": hull_points, 
            "rot": _rng.randf() * TAU, 
            "rot_speed": _rng.randf_range(-0.05, 0.05), 
            "interior_glow_pos": Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-10, 10)), 
            "glow_phase": _rng.randf() * TAU, 
        })

    for i in int(20 * count):
        _particles.append({
            "pos": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)), 
            "vel": Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-3, 3)), 
            "sz": _rng.randf_range(0.5, 2.5), 
            "alpha": _rng.randf_range(0.15, 0.4), 
            "is_organic": organic and _rng.randf() < 0.3, 
            "phase": _rng.randf() * TAU, 
        })

func _draw_derelict():
    var _derelict_type = _param_s("type", "wreck")
    var organic = _param_b("organic", false)


    for p in _particles:
        if p.is_organic:
            var pulse = sin(_time * 2.0 + p.phase) * 0.2 + 0.8
            draw_circle(p.pos, p.sz, Color(0.2, 0.8, 0.4, p.alpha * pulse))
        else:
            draw_circle(p.pos, p.sz, Color(0.4, 0.35, 0.3, p.alpha))


    for hull in _entities:
        var pos = hull.pos
        var rot = hull.rot + hull.rot_speed * _time


        var pts: PackedVector2Array = PackedVector2Array()
        for v in hull.hull:
            var a = v.angle + rot
            pts.append(pos + Vector2.from_angle(a) * v.dist)

        if pts.size() < 3:
            continue


        draw_colored_polygon(pts, Color(0.06, 0.06, 0.08, 0.85))

        for i in pts.size():
            draw_line(pts[i], pts[(i + 1) % pts.size()], Color(0.25, 0.22, 0.2, 0.5), 1.5)


        var glow_pulse = sin(_time * 1.5 + hull.glow_phase) * 0.3 + 0.5
        var glow_pos = pos + hull.interior_glow_pos
        if organic:

            draw_circle(glow_pos, 8.0, Color(0.1, 0.6, 0.3, 0.15 * glow_pulse))
            draw_circle(glow_pos + Vector2(5, -3), 5.0, Color(0.1, 0.5, 0.7, 0.12 * glow_pulse))
        else:

            draw_circle(glow_pos, 5.0, Color(0.8, 0.6, 0.3, 0.15 * glow_pulse))





func _init_wormhole():
    var count = _param_i("count", 1)
    for i in count:
        _entities.append({
            "pos": Vector2(
                _rng.randf_range(size.x * 0.2, size.x * 0.8), 
                _rng.randf_range(size.y * 0.2, size.y * 0.8)), 
            "radius": _rng.randf_range(60, 120), 
            "rot_speed": _rng.randf_range(0.5, 1.5), 
            "phase": _rng.randf() * TAU, 
        })

func _draw_wormhole():
    var hue = _param_f("color", 0.7)
    var collapsing = _param_b("collapsing", false)

    for wh in _entities:
        var pos = wh.pos
        var base_r = wh.radius
        var rot = _time * wh.rot_speed
        var collapse_factor = 1.0
        if collapsing:
            collapse_factor = maxf(0.1, 1.0 - _time * 0.05)


        var ring_count = 8
        for ring_i in ring_count:
            var frac = float(ring_i) / float(ring_count)
            var r = base_r * (1.0 - frac * 0.8) * collapse_factor
            var ring_rot = rot * (1.0 + frac * 2.0)
            var alpha = 0.15 + frac * 0.15
            var ring_hue = hue + frac * 0.15

            for seg in 24:
                var a1 = float(seg) / 24.0 * TAU + ring_rot
                var a2 = float(seg + 1) / 24.0 * TAU + ring_rot
                var spiral_offset1 = sin(a1 * 3 + _time * 2) * r * 0.1
                var spiral_offset2 = sin(a2 * 3 + _time * 2) * r * 0.1
                var p1 = pos + Vector2.from_angle(a1) * (r + spiral_offset1)
                var p2 = pos + Vector2.from_angle(a2) * (r + spiral_offset2)
                draw_line(p1, p2, _hue_color(ring_hue, 0.5, 0.7, alpha), 1.5 - frac)


        var core_pulse = sin(_time * 3.0 + wh.phase) * 0.3 + 0.7
        var core_r = base_r * 0.15 * collapse_factor
        _draw_glow_circle(pos, core_r * core_pulse, _hue_color(hue, 0.6, 1.0, 0.5 * core_pulse), 4)


        for s in _bg_stars:
            var dist = s.pos.distance_to(pos)
            if dist < base_r * 2:
                var pull = (base_r * 2 - dist) / (base_r * 2)
                var warped = s.pos.lerp(pos, pull * 0.3)
                var stretched = warped + (warped - pos).normalized() * pull * 15
                draw_circle(stretched, s.sz * (1.0 + pull), Color(1, 1, 1, s.brightness * (1.0 + pull * 0.5)))





func _init_aurora():
    var waviness = _param_f("waviness", 1.0)
    var band_count = 8
    for i in band_count:
        _entities.append({
            "x_base": size.x * 0.1 + float(i) / float(band_count - 1) * size.x * 0.8, 
            "width": _rng.randf_range(15, 40), 
            "phase": _rng.randf() * TAU, 
            "speed": _rng.randf_range(0.3, 0.8), 
            "amplitude": _rng.randf_range(15, 40) * waviness, 
        })

func _draw_aurora():
    var hue1 = _param_f("color1", 0.35)
    var hue2 = _param_f("color2", 0.75)
    var _waviness = _param_f("waviness", 1.0)

    for band in _entities:
        var seg_count = 30
        var x_base = band.x_base
        var w = band.width


        var left_pts: PackedVector2Array = PackedVector2Array()
        var right_pts: PackedVector2Array = PackedVector2Array()
        for seg in range(seg_count + 1):
            var frac = float(seg) / float(seg_count)
            var y = frac * size.y
            var wave = sin(_time * band.speed + frac * 4.0 + band.phase) * band.amplitude
            var x = x_base + wave
            left_pts.append(Vector2(x - w * 0.5, y))
            right_pts.append(Vector2(x + w * 0.5, y))


        var hue_frac = (band.x_base - size.x * 0.1) / (size.x * 0.8)
        var band_hue = lerpf(hue1, hue2, hue_frac)
        for seg in seg_count:
            var frac = float(seg) / float(seg_count)

            var y_alpha = sin(frac * PI) * 0.15
            var time_pulse = sin(_time * 1.5 + band.phase + frac * 2.0) * 0.05
            var alpha = y_alpha + time_pulse
            var col = _hue_color(band_hue + frac * 0.05, 0.5, 0.7, maxf(alpha, 0.01))
            var quad: PackedVector2Array = PackedVector2Array([
                left_pts[seg], right_pts[seg], right_pts[seg + 1], left_pts[seg + 1]
            ])
            draw_colored_polygon(quad, col)


        for seg in seg_count:
            var frac = float(seg) / float(seg_count)
            var edge_alpha = sin(frac * PI) * 0.2
            var edge_col = _hue_color(band_hue, 0.6, 1.0, edge_alpha)
            draw_line(left_pts[seg], left_pts[seg + 1], edge_col, 0.5)





func _init_leviathan():
    var visible_part = _param_s("visible_part", "body")
    var sz_scale = _param_f("size_scale", 1.0)
    _entities.append({
        "visible_part": visible_part, 
        "size_scale": sz_scale, 
    })

func _draw_leviathan():
    var visible_part = _param_s("visible_part", "body")
    var sz_scale = _param_f("size_scale", 1.0)

    match visible_part:
        "eye":
            _draw_leviathan_eye(sz_scale)
        "body":
            _draw_leviathan_body(sz_scale)
        "tentacles":
            _draw_leviathan_tentacles(sz_scale)
        _:
            _draw_leviathan_body(sz_scale)

func _draw_leviathan_eye(sz_scale: float):
    var center = _screen_center() + Vector2(50, 0)
    var eye_r = 100 * sz_scale


    for layer in 6:
        var lr = eye_r * (1.0 + float(layer) * 0.15)
        var la = 0.08 * (1.0 - float(layer) / 6.0)
        draw_circle(center, lr, Color(0.6, 0.55, 0.4, la))
    draw_circle(center, eye_r, Color(0.7, 0.65, 0.5, 0.3))


    var iris_r = eye_r * 0.65
    var iris_hue = 0.12
    for ring in 4:
        var rr = iris_r - float(ring) * iris_r * 0.1
        var ra = 0.15 + float(ring) * 0.05
        draw_arc(center, rr, 0, TAU, 32, _hue_color(iris_hue + float(ring) * 0.02, 0.7, 0.8, ra), 3.0)

    for i in 20:
        var a = float(i) * TAU / 20.0 + sin(_time * 0.5) * 0.02
        var inner_r = eye_r * 0.25
        var p1 = center + Vector2.from_angle(a) * inner_r
        var p2 = center + Vector2.from_angle(a) * iris_r
        draw_line(p1, p2, _hue_color(iris_hue, 0.6, 0.6, 0.1), 1.0)


    var pupil_offset = Vector2(sin(_time * 0.3) * 5, cos(_time * 0.4) * 3)
    var pupil_r = eye_r * 0.25
    draw_circle(center + pupil_offset, pupil_r, Color(0, 0, 0, 0.95))

    var highlight_pos = center + pupil_offset + Vector2( - pupil_r * 0.3, - pupil_r * 0.3)
    draw_circle(highlight_pos, pupil_r * 0.15, Color(1, 1, 1, 0.4))


    for i in 6:
        var start_a = float(i) * TAU / 6.0 + _rng.randf_range(-0.2, 0.2)
        var start_pt = center + Vector2.from_angle(start_a) * iris_r
        var end_pt = center + Vector2.from_angle(start_a + _rng.randf_range(-0.3, 0.3)) * eye_r * 0.95
        var mid = (start_pt + end_pt) * 0.5 + Vector2(sin(_time * 0.8 + float(i)) * 5, cos(_time + float(i)) * 3)
        draw_line(start_pt, mid, Color(0.7, 0.2, 0.15, 0.15), 1.0)
        draw_line(mid, end_pt, Color(0.7, 0.2, 0.15, 0.1), 0.5)

func _draw_leviathan_body(sz_scale: float):

    var center_x = size.x + 200 * sz_scale
    var center_y = size.y * 0.5
    var body_r = 500 * sz_scale


    for layer in 8:
        var lr = body_r - float(layer) * 15
        var la = 0.04 + float(layer) * 0.02
        var arc_start = PI * 0.6
        var arc_end = PI * 1.4
        draw_arc(Vector2(center_x, center_y), lr, arc_start, arc_end, 40, 
            Color(0.15 + float(layer) * 0.01, 0.12 + float(layer) * 0.008, 0.1, la), 8.0)


    for ridge in 15:
        var ridge_r = body_r - 30 - float(ridge) * 20
        var arc_start = PI * 0.65 + sin(_time * 0.3 + float(ridge)) * 0.02
        var arc_end = PI * 1.35
        var ridge_alpha = 0.08 + sin(_time * 0.5 + float(ridge) * 0.7) * 0.03
        draw_arc(Vector2(center_x, center_y), ridge_r, arc_start, arc_end, 20, 
            Color(0.2, 0.18, 0.15, ridge_alpha), 1.5)


    for i in 10:
        var a = PI * 0.7 + float(i) / 10.0 * PI * 0.6
        var r = body_r - 50 + sin(_time * 1.5 + float(i) * 2.0) * 8
        var pt = Vector2(center_x, center_y) + Vector2.from_angle(a) * r
        var pulse = sin(_time * 2.0 + float(i)) * 0.15 + 0.15
        draw_circle(pt, 4.0, Color(0.3, 0.25, 0.2, pulse))

func _draw_leviathan_tentacles(sz_scale: float):

    var tentacle_count = 4
    for t_i in tentacle_count:
        var origin = Vector2(size.x + 30, size.y * (0.15 + float(t_i) * 0.22))
        var target = Vector2(size.x * 0.15, size.y * (0.2 + float(t_i) * 0.2 + sin(_time * 0.5 + float(t_i)) * 0.05))
        var seg_count = 25
        var width = (20 + float(t_i) * 5) * sz_scale
        var prev_pt = origin
        for seg in range(1, seg_count + 1):
            var frac = float(seg) / float(seg_count)
            var base_pt = origin.lerp(target, frac)
            var wave_x = sin(_time * 1.2 + frac * 5.0 + float(t_i) * 2.0) * 20 * frac
            var wave_y = cos(_time * 1.5 + frac * 4.0 + float(t_i) * 1.5) * 15 * frac
            var pt = base_pt + Vector2(wave_x, wave_y)
            var seg_w = width * (1.0 - frac * 0.7)
            var alpha = 0.35 * (1.0 - frac * 0.4)
            draw_line(prev_pt, pt, Color(0.2, 0.18, 0.15, alpha), seg_w)

            if seg % 3 == 0:
                var ridge_dir = (pt - prev_pt).normalized().rotated(PI * 0.5)
                draw_line(pt - ridge_dir * seg_w * 0.5, pt + ridge_dir * seg_w * 0.5, 
                    Color(0.25, 0.2, 0.18, alpha * 0.5), 1.0)
            prev_pt = pt
