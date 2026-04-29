extends Node2D

# World-space immediate-mode drawing. _draw() dispatches to the space or
# surface branch based on host.on_surface, then the branch helpers issue
# draw_* calls against this node. Runs queue_redraw() every frame so it
# keeps up with constantly-changing state (camera, orbit pulses, etc.).
#
# State accessed via owner_main (main.gd):
#   - on_surface, player, camera_zoom, hail_target, in_combat, event_open
#   - creative_test_flying, creative_previewing_ai, creative_training_ai
#   - creative_recording_ai, _training_round
#   - jumping, jump_timer, JUMP_DURATION
#   - surface_data, surface_seed, surface_entry_timer, surface_exit_timer
#   - SURFACE_RADIUS, SURFACE_TRANSITION_TIME, _cached_pois

var owner_main: Node = null

func _h() -> Node:
    return owner_main

func _process(_delta: float):
    queue_redraw()

func _draw():
    var host = _h()
    if host == null:
        return
    if host.on_surface:
        _draw_surface()
    else:
        _draw_space()

func _wrap_pos(offset: Vector2, center: Vector2, radius: float) -> Vector2:
    var p = offset
    p.x = fmod(p.x - center.x + radius, radius * 2.0)
    if p.x < 0: p.x += radius * 2.0
    p.x += center.x - radius
    p.y = fmod(p.y - center.y + radius, radius * 2.0)
    if p.y < 0: p.y += radius * 2.0
    p.y += center.y - radius
    return p

func _draw_space():
    var host = _h()
    var time = Time.get_ticks_msec() * 0.001

    var ot: Vector2
    var orbit_r: float
    var a1: float
    var a2: float
    var player = host.player
    if player and player.orbit_locked and player.handbrake_target and is_instance_valid(player.handbrake_target):
        ot = player.handbrake_target.global_position
        orbit_r = player.HANDBRAKE_ORBIT_DIST
        var orbit_pulse = sin(time * 3.0) * 0.12 + 0.28
        draw_arc(ot, orbit_r, 0, TAU, 24, Color(0.3, 0.8, 0.95, orbit_pulse), 1.5)

        for di in 16:
            a1 = float(di) / 16.0 * TAU + time * 0.3
            a2 = a1 + TAU / 32.0
            draw_arc(ot, orbit_r * 0.85, a1, a2, 4, Color(0.3, 0.8, 0.95, orbit_pulse * 0.5), 0.8)


    var font = ThemeDB.fallback_font
    var hail_target = host.hail_target
    if hail_target and is_instance_valid(hail_target) and not host.in_combat and not host.event_open:
        var hp = hail_target.global_position + Vector2(0, - hail_target.ship_size - 22)
        var hail_text = "[E] Hail %s" % hail_target.ship_name
        var tw = font.get_string_size(hail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        draw_string(font, hp + Vector2( - tw * 0.5, 0), hail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.8, 1.0, 0.85))


    if host.creative_test_flying or host.creative_previewing_ai:
        font = ThemeDB.fallback_font
        var vp = get_viewport_rect().size
        var test_text: String
        var banner_col: Color
        var banner_bg: Color
        if host.creative_training_ai:
            test_text = "CLONE TRAINING — Round %d  [B] Update  [Esc] Save & Exit" % host._training_round
            banner_col = Color(0.3, 0.8, 1.0)
            banner_bg = Color(0.05, 0.1, 0.15, 0.8)
        elif host.creative_recording_ai:
            test_text = "RECORDING AI — [B] Start Training  [Esc] Discard"
            banner_col = Color(0.8, 0.3, 0.3)
            banner_bg = Color(0.15, 0.05, 0.05, 0.8)
        elif host.creative_previewing_ai:
            test_text = "AI PREVIEW — [B] Return to Builder"
            banner_col = Color(0.6, 0.5, 1.0)
            banner_bg = Color(0.1, 0.05, 0.15, 0.8)
        else:
            test_text = "TEST FLIGHT — [B] Return to Builder"
            banner_col = Color(0.3, 0.8, 0.55)
            banner_bg = Color(0.05, 0.15, 0.1, 0.8)
        var flash = 0.7 + sin(time * 2.5) * 0.3
        draw_rect(Rect2(vp.x * 0.5 - 180, 8, 360, 30), banner_bg)
        draw_rect(Rect2(vp.x * 0.5 - 180, 8, 360, 30), Color(banner_col, flash * 0.6), false, 1.5)
        draw_string(font, Vector2(vp.x * 0.5 - 150, 30), test_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(banner_col, flash))


    if host.jumping and player:
        _draw_jump_kaleidoscope()


    if host.surface_exit_timer > 0:
        var alpha = clampf(host.surface_exit_timer / host.SURFACE_TRANSITION_TIME, 0, 1) * 0.5
        if player:
            draw_rect(Rect2(player.position - Vector2(1000, 600), Vector2(2000, 1200)), Color(1, 1, 1, alpha))

func _draw_jump_kaleidoscope():
    var host = _h()
    var progress = clampf(host.jump_timer / host.JUMP_DURATION, 0, 1)
    var t = host.jump_timer * 5.0
    var center = host.player.position
    var vp = get_viewport_rect().size
    var max_r = vp.length() * 0.8
    var intensity = clampf(progress * 2.5, 0, 1)
    var half = vp * 0.5


    draw_rect(Rect2(center - half * 1.5, vp * 1.5), Color(0, 0, 0, 1.0))


    var bg_hue = fmod(t * 0.15, 1.0)
    for bg_i in 5:
        var bg_r = max_r * (1.0 - float(bg_i) * 0.15)
        var bg_h = fmod(bg_hue + float(bg_i) * 0.1, 1.0)
        draw_circle(center, bg_r, Color.from_hsv(bg_h, 0.8, 0.15 + float(bg_i) * 0.03, intensity * 0.6))

    var hue_speed = 3.0 + progress * 8.0
    var segments: int = 6 + int(progress * 8)


    var ring_count: int = int(15 + progress * 35)
    for i in ring_count:
        var ring_t = float(i) / float(ring_count)
        var radius = 30.0 + ring_t * max_r
        var hue = fmod(ring_t * 4.0 + t * hue_speed * 0.25 + float(i) * 0.13, 1.0)
        var sat = 0.9 + sin(t * 1.5 + float(i)) * 0.1
        var val = 0.8 + ring_t * 0.2
        var alpha = intensity * (0.25 + ring_t * 0.2)
        var col = Color.from_hsv(hue, sat, val, alpha)
        var spin = t * (0.8 + ring_t * 3.0) * (1.0 if i % 2 == 0 else -1.0)
        var wobble_x = sin(t * 2.3 + float(i) * 0.7) * 12.0 * ring_t
        var wobble_y = cos(t * 1.9 + float(i) * 0.5) * 8.0 * ring_t
        var c = center + Vector2(wobble_x, wobble_y)
        var width = 3.0 + ring_t * 6.0 + sin(t * 3.0 + float(i) * 0.4) * 2.0
        for s in segments:
            var a0 = TAU * float(s) / float(segments) + spin
            var a1 = a0 + TAU / float(segments) * 0.75
            draw_arc(c, radius, a0, a1, 10, col, width)

            draw_arc(c, radius, a0, a1, 10, Color(col, alpha * 0.3), width * 2.5)


    var wedge_count: int = int(progress * 12)
    for i in wedge_count:
        var base_a = t * (1.0 + float(i) * 0.15) + float(i) * TAU / 5.0
        var inner_r = 40.0 + float(i) * 25.0
        var outer_r = inner_r + 60.0 + sin(t * 2.0 + float(i)) * 30.0
        var wedge_w = TAU / float(segments) * 0.6
        var hue = fmod(float(i) * 0.09 + t * hue_speed * 0.12, 1.0)
        for s in segments:
            var wa = base_a + TAU * float(s) / float(segments)
            var pts = PackedVector2Array()
            pts.append(center + Vector2.from_angle(wa) * inner_r)
            pts.append(center + Vector2.from_angle(wa) * outer_r)
            pts.append(center + Vector2.from_angle(wa + wedge_w) * outer_r)
            pts.append(center + Vector2.from_angle(wa + wedge_w) * inner_r)
            var h2 = fmod(hue + float(s) * 0.08, 1.0)
            draw_colored_polygon(pts, Color.from_hsv(h2, 1.0, 1.0, intensity * 0.25))


    var tri_count: int = int(progress * 30)
    for i in tri_count:
        var angle_base = t * (1.2 + float(i) * 0.12) + float(i) * TAU / 11.0
        var dist = 80.0 + float(i) * 25.0 + sin(t * 1.3 + float(i)) * 60.0
        var tri_center = center + Vector2.from_angle(angle_base) * dist
        var tri_size = 20.0 + float(i) * 3.0 + sin(t * 3.0 + float(i) * 0.5) * 12.0
        var hue = fmod(float(i) * 0.07 + t * hue_speed * 0.08, 1.0)
        var rot = angle_base * 2.0 + t * 0.5

        var pts = PackedVector2Array()
        for v in 3:
            pts.append(tri_center + Vector2.from_angle(rot + TAU * float(v) / 3.0) * tri_size)
        draw_colored_polygon(pts, Color.from_hsv(hue, 1.0, 1.0, intensity * 0.45))

        var outline_pts = PackedVector2Array([pts[0], pts[1], pts[2], pts[0]])
        draw_polyline(outline_pts, Color.from_hsv(hue, 0.5, 1.0, intensity * 0.6), 2.0)

        var mpts = PackedVector2Array()
        for v in 3:
            mpts.append(center * 2.0 - pts[v])
        draw_colored_polygon(mpts, Color.from_hsv(fmod(hue + 0.5, 1.0), 1.0, 1.0, intensity * 0.3))


    for arm in 6:
        var arm_offset = TAU * float(arm) / 6.0
        var point_count: int = int(30 + progress * 50)
        for p in point_count:
            var pt = float(p) / float(point_count)
            var spiral_a = arm_offset + pt * TAU * 4.0 + t * (4.0 + progress * 5.0)
            var spiral_r = pt * max_r
            var hue = fmod(pt + float(arm) * 0.167 + t * hue_speed * 0.06, 1.0)
            var alpha = intensity * (1.0 - pt * 0.6) * 0.6
            var dot_size = 3.0 + pt * 8.0 + sin(t * 5.0 + float(p) * 0.3) * 3.0
            var pos = center + Vector2.from_angle(spiral_a) * spiral_r
            draw_circle(pos, dot_size, Color.from_hsv(hue, 1.0, 1.0, alpha))

            if p % 3 == 0:
                draw_circle(pos, dot_size * 2.0, Color.from_hsv(hue, 0.6, 1.0, alpha * 0.2))


    var petal_layers: int = int(3 + progress * 5)
    for li in petal_layers:
        var lr = 100.0 + float(li) * 80.0
        var petals = segments + li * 2
        var petal_spin = t * (1.5 - float(li) * 0.2) * (1.0 if li % 2 == 0 else -1.0)
        for pi in petals:
            var pa = TAU * float(pi) / float(petals) + petal_spin
            var tip = center + Vector2.from_angle(pa) * (lr + 40.0)
            var left = center + Vector2.from_angle(pa - 0.15) * lr
            var right = center + Vector2.from_angle(pa + 0.15) * lr
            var hue = fmod(float(pi) * (1.0 / float(petals)) + float(li) * 0.15 + t * 0.5, 1.0)
            draw_colored_polygon(PackedVector2Array([left, tip, right]),
                Color.from_hsv(hue, 0.9, 1.0, intensity * 0.18))


    var core_pulse = 0.5 + sin(t * 6.0) * 0.5
    var core_r = 25.0 + progress * 20.0 + core_pulse * 8.0
    for cr in 10:
        var cr_t = float(cr) / 10.0
        var hue = fmod(cr_t * 2.0 + t * 3.0, 1.0)
        var cr_r = core_r * (2.5 - cr_t * 1.5)
        draw_circle(center, cr_r, Color.from_hsv(hue, 0.8, 1.0, intensity * 0.2))
    draw_circle(center, core_r * 1.2, Color(1, 1, 1, intensity * 0.4))
    draw_circle(center, core_r, Color(1, 1, 1, intensity * 0.7))
    draw_circle(center, core_r * 0.4, Color(1, 1, 1, intensity))


    if progress > 0.75:
        var flash = clampf((progress - 0.75) / 0.25, 0, 1)
        draw_rect(Rect2(center - half * 1.5, vp * 1.5), Color(1, 1, 1, flash * flash))

func _surface_noise(wx: float, wy: float) -> float:
    var s = _h().surface_seed
    var h: float = 0.0
    h += sin(wx * 0.001 + s) * sin(wy * 0.0012 + s * 1.3) * 0.4
    h += sin(wx * 0.003 + s * 2.3) * sin(wy * 0.0028 + s * 0.7) * 0.3
    h += sin(wx * 0.008 + s * 3.7) * sin(wy * 0.007 + s * 1.1) * 0.2
    h += sin(wx * 0.02 + s * 0.5) * sin(wy * 0.018 + s * 2.1) * 0.1
    return h

func _draw_surface():
    var host = _h()
    if not host.player:
        return

    var cam = host.player.global_position
    var vp = get_viewport_rect().size
    var hw: float = (vp.x / host.camera_zoom) * 0.5 + 120.0
    var hh: float = (vp.y / host.camera_zoom) * 0.5 + 120.0


    var terrain_arrs = host.surface_data.get("terrain_colors", [[0.15, 0.3, 0.2], [0.1, 0.22, 0.12], [0.06, 0.18, 0.06]])
    var base_col = Color(terrain_arrs[2][0], terrain_arrs[2][1], terrain_arrs[2][2])
    var alt_col = Color(terrain_arrs[1][0], terrain_arrs[1][1], terrain_arrs[1][2])
    var accent_col = Color(terrain_arrs[0][0], terrain_arrs[0][1], terrain_arrs[0][2])


    draw_rect(Rect2(cam.x - hw, cam.y - hh, hw * 2, hh * 2), base_col)


    var patch_size: float = 100.0
    var start_x = snappedf(cam.x - hw - patch_size, patch_size)
    var start_y = snappedf(cam.y - hh - patch_size, patch_size)
    var px = start_x
    while px <= cam.x + hw + patch_size:
        var py = start_y
        while py <= cam.y + hh + patch_size:
            var n = _surface_noise(px, py)
            var col: Color
            if n > 0.2:
                col = base_col.lerp(alt_col, clampf((n - 0.2) / 0.8, 0, 1))
            elif n < -0.2:
                col = base_col.lerp(accent_col, clampf(( - n - 0.2) / 0.8, 0, 1))
            else:
                col = base_col

            var bright = 1.0 + _surface_noise(px * 1.7 + 500, py * 1.3 + 300) * 0.08
            col *= bright
            draw_rect(Rect2(px, py, patch_size, patch_size), col)
            py += patch_size
        px += patch_size


    _draw_surface_features(cam, base_col, alt_col, accent_col)


    _draw_surface_details_topdown(cam, base_col)


    _draw_colony_modules_topdown(cam)



    var dist_from_center = cam.length()
    if dist_from_center > host.SURFACE_RADIUS * 0.7:
        var alpha = clampf((dist_from_center - host.SURFACE_RADIUS * 0.7) / (host.SURFACE_RADIUS * 0.3), 0, 0.6)
        draw_rect(Rect2(cam.x - hw, cam.y - hh, hw * 2, hh * 2), Color(0.05, 0.05, 0.1, alpha))


    if host.surface_entry_timer > 0:
        var alpha = clampf(host.surface_entry_timer / host.SURFACE_TRANSITION_TIME, 0, 1)
        draw_rect(Rect2(cam.x - hw, cam.y - hh, hw * 2, hh * 2), Color(1, 1, 1, alpha * 0.8))


    _draw_surface_poi_indicators(cam, hw, hh)


    var font = ThemeDB.fallback_font
    draw_string(font, Vector2(cam.x - 80, cam.y - hh + 40), "[T] Return to Orbit",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.85, 1.0, 0.4))


    var pname = host.surface_data.get("name", "")
    if pname != "":
        draw_string(font, Vector2(cam.x - hw + 12, cam.y - hh + 40), pname,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.9, 1.0, 0.5))

func _draw_surface_poi_indicators(cam: Vector2, hw: float, hh: float):
    var host = _h()
    var font = ThemeDB.fallback_font
    var pois = host._cached_pois
    for poi in pois:
        if not is_instance_valid(poi):
            continue
        if poi.poi_type in ["station", "hostile_station"]:
            continue
        var poi_world: Vector2 = poi.global_position
        var rel: Vector2 = poi_world - cam
        var margin: float = 50.0
        var on_screen: bool = abs(rel.x) < hw - margin and abs(rel.y) < hh - margin
        var col: Color = poi.type_colors.get(poi.poi_type, Color(0.5, 0.5, 0.5))
        var _sym: String = poi.type_symbols.get(poi.poi_type, "?")
        var dist_to_poi: float = rel.length()

        if on_screen:

            var pulse = sin(poi.pulse_time * 2.5) * 0.3 + 0.7
            var beacon_r: float = 28.0
            draw_arc(poi_world, beacon_r, 0, TAU, 20, Color(col, 0.5 * pulse), 2.0)
            draw_arc(poi_world, beacon_r + 6, 0, TAU, 20, Color(col, 0.2 * pulse), 1.5)

            var tip = poi_world + Vector2(0, - beacon_r - 4)
            var tri = PackedVector2Array([
                tip,
                tip + Vector2(-6, -10),
                tip + Vector2(6, -10),
            ])
            if _is_valid_triangle(tri):
                _draw_filled_triangle(tri, Color(col, 0.6 * pulse))
        else:

            if rel.length_squared() <= 0.0001:
                continue
            var dir: Vector2 = rel.normalized()

            var edge_x: float = clampf(rel.x, - hw + margin, hw - margin)
            var edge_y: float = clampf(rel.y, - hh + margin, hh - margin)

            if abs(rel.x) >= hw - margin or abs(rel.y) >= hh - margin:
                var scale_x: float = (hw - margin) / maxf(abs(rel.x), 0.001)
                var scale_y: float = (hh - margin) / maxf(abs(rel.y), 0.001)
                var s: float = minf(scale_x, scale_y)
                edge_x = rel.x * s
                edge_y = rel.y * s
            var edge_pos: Vector2 = cam + Vector2(edge_x, edge_y)


            var arrow_size: float = 12.0
            var perp: Vector2 = Vector2( - dir.y, dir.x)
            var tip = edge_pos + dir * arrow_size
            var tri = PackedVector2Array([
                tip,
                edge_pos - dir * 4 + perp * arrow_size * 0.5,
                edge_pos - dir * 4 - perp * arrow_size * 0.5,
            ])
            var pulse = sin(poi.pulse_time * 3.0) * 0.2 + 0.8
            if _is_valid_triangle(tri):
                _draw_filled_triangle(tri, Color(col, 0.7 * pulse))
                draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(col, 0.9), 1.5)


            var dist_text = str(int(dist_to_poi)) + "m"
            var label_pos = edge_pos - dir * 18
            draw_string(font, label_pos + Vector2( - dist_text.length() * 3, 4),
                dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.7))


            var name_pos = edge_pos - dir * 18 + perp * 14
            draw_string(font, name_pos + Vector2( - poi.poi_name.length() * 2.5, 4),
                poi.poi_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.6))


func _is_valid_triangle(points: PackedVector2Array) -> bool:
    if points.size() != 3:
        return false
    for p in points:
        if is_nan(p.x) or is_inf(p.x) or is_nan(p.y) or is_inf(p.y):
            return false
    var area2: float = absf(
        (points[1].x - points[0].x) * (points[2].y - points[0].y) -
        (points[1].y - points[0].y) * (points[2].x - points[0].x)
    )
    return area2 > 0.001


func _draw_filled_triangle(points: PackedVector2Array, color: Color) -> void:
    if not _is_valid_triangle(points):
        return
    var colors := PackedColorArray([color, color, color])
    var uvs := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
    draw_primitive(points, colors, uvs)

func _draw_surface_features(cam: Vector2, _base_col: Color, alt_col: Color, accent_col: Color):
    var host = _h()
    var roughness = host.surface_data.get("roughness", 0.6)
    var is_volcanic = roughness > 0.75
    var is_oceanic = roughness < 0.45
    var hw: float = 1050.0
    var hh: float = 650.0


    var feature_step: float = 300.0
    var fx = snappedf(cam.x - hw - feature_step, feature_step)
    while fx <= cam.x + hw + feature_step:
        var fy = snappedf(cam.y - hh - feature_step, feature_step)
        while fy <= cam.y + hh + feature_step:
            var fhash = sin(fx * 0.0731 + fy * 0.0529 + host.surface_seed * 0.41) * 43758.5453
            var fr = fhash - floorf(fhash)
            if fr > 0.15:
                fy += feature_step
                continue

            if is_volcanic:

                var llen = 80.0 + fr * 200.0
                var langle = sin(fx * 0.01 + host.surface_seed) * TAU
                var lstart = Vector2(fx, fy)
                var lend = lstart + Vector2(cos(langle), sin(langle)) * llen

                draw_line(lstart, lend, Color(1.0, 0.35, 0.05, 0.15), 12.0)
                draw_line(lstart, lend, Color(1.0, 0.5, 0.1, 0.25), 5.0)
                draw_line(lstart, lend, Color(1.0, 0.7, 0.2, 0.4), 2.0)
            elif is_oceanic:

                var pool_r = 30.0 + fr * 60.0
                draw_circle(Vector2(fx, fy), pool_r, Color(0.12, 0.22, 0.38, 0.25))
                draw_circle(Vector2(fx, fy), pool_r * 0.7, Color(0.15, 0.28, 0.45, 0.2))

                draw_arc(Vector2(fx, fy), pool_r, 0, TAU, 12, Color(0.3, 0.4, 0.35, 0.15), 1.5)
            else:

                var cr = 20.0 + fr * 40.0
                var ccol = accent_col.lerp(alt_col, fr)
                draw_circle(Vector2(fx, fy), cr, Color(ccol, 0.1))

            fy += feature_step
        fx += feature_step

func _draw_surface_details_topdown(cam: Vector2, base_color: Color):
    var host = _h()
    var roughness = host.surface_data.get("roughness", 0.6)
    var is_volcanic = roughness > 0.75
    var is_lush = roughness < 0.5

    var step: float = 70.0
    var start_x = snappedf(cam.x - 1050, step)
    var start_y = snappedf(cam.y - 650, step)

    var x = start_x
    while x <= cam.x + 1050:
        var y = start_y
        while y <= cam.y + 650:

            var hash_val = sin(x * 0.137 + y * 0.219 + host.surface_seed * 0.31) * 43758.5453
            var r = hash_val - floorf(hash_val)
            var hash2 = sin(x * 0.293 + y * 0.183 + host.surface_seed * 0.67) * 43758.5453
            var r2 = hash2 - floorf(hash2)

            if r > 0.35:
                y += step
                continue


            if Vector2(x, y).length() > host.SURFACE_RADIUS:
                y += step
                continue

            var detail_type = int(r * 100) % 6

            if is_volcanic:
                match detail_type % 4:
                    0:
                        var rr = 4.0 + r * 8.0
                        var pts = PackedVector2Array()
                        for i in 5:
                            var a = float(i) / 5.0 * TAU + r2
                            pts.append(Vector2(x + cos(a) * rr * (0.7 + r * 0.3), y + sin(a) * rr * (0.6 + r2 * 0.4)))
                        draw_colored_polygon(pts, base_color * 0.35)
                    1:
                        var lr = 5.0 + r * 10.0
                        draw_circle(Vector2(x, y), lr, Color(0.8, 0.3, 0.05, 0.35))
                        draw_circle(Vector2(x, y), lr * 0.5, Color(1.0, 0.5, 0.1, 0.45))
                    2:
                        draw_circle(Vector2(x, y), 6.0 + r * 8.0, Color(0.3, 0.28, 0.25, 0.08))
                    3:
                        var clen = 10.0 + r * 20.0
                        var cangle = r2 * TAU
                        draw_line(Vector2(x, y), Vector2(x + cos(cangle) * clen, y + sin(cangle) * clen), Color(0.6, 0.2, 0.05, 0.25), 1.5)
            elif is_lush:
                match detail_type:
                    0:
                        var cr = 8.0 + r * 12.0
                        var canopy_col = base_color.lerp(Color(0.2, 0.55, 0.15), r2 * 0.4)

                        draw_circle(Vector2(x + 3, y + 3), cr * 0.9, Color(0, 0, 0, 0.06))
                        draw_circle(Vector2(x, y), cr, canopy_col * 0.65)
                        draw_circle(Vector2(x - cr * 0.3, y + cr * 0.2), cr * 0.7, canopy_col * 0.7)
                        draw_circle(Vector2(x + cr * 0.25, y - cr * 0.15), cr * 0.55, canopy_col * 0.75)
                    1:
                        var br = 5.0 + r * 6.0
                        var bcol = base_color.lerp(Color(0.25, 0.5, 0.2), r * 0.5)
                        draw_circle(Vector2(x, y), br, bcol * 0.6)
                        draw_circle(Vector2(x + 3, y - 2), br * 0.7, bcol * 0.55)
                    2:
                        var gr = 3.0 + r * 5.0
                        var gcol = base_color.lerp(Color(0.3, 0.55, 0.15), r2 * 0.4)
                        draw_circle(Vector2(x, y), gr, gcol * 0.45)
                    3:
                        for j in 3:
                            var fx2 = x + (float(j) - 1.0) * 4.0 * r2
                            var fy2 = y + (float(j) - 1.0) * 3.0 * r
                            var fc = Color(0.8 + r2 * 0.2, 0.3 + r * 0.4, 0.5 + r2 * 0.3)
                            draw_circle(Vector2(fx2, fy2), 2.0, fc * 0.7)
                    4:
                        var mr = 5.0 + r * 6.0
                        draw_circle(Vector2(x, y), mr, base_color * 0.4)
                        draw_arc(Vector2(x, y), mr * 0.7, 0, PI, 5, Color(0.2, 0.5, 0.15, 0.35), 2.0)
                    5:
                        var pr = 4.0 + r * 8.0
                        draw_circle(Vector2(x, y), pr, Color(0.15, 0.25, 0.4, 0.3))
                        draw_circle(Vector2(x, y), pr * 0.5, Color(0.2, 0.3, 0.5, 0.2))
            else:

                match detail_type % 4:
                    0:
                        var cr = 5.0 + r * 8.0
                        draw_circle(Vector2(x + 2, y + 2), cr * 0.85, Color(0, 0, 0, 0.04))
                        draw_circle(Vector2(x, y), cr, base_color * 0.65)
                    1:
                        var rr = 4.0 + r * 6.0
                        draw_circle(Vector2(x, y), rr, base_color * 0.4)
                        draw_arc(Vector2(x, y), rr * 0.6, 0, PI * 0.7, 4, base_color * 0.55, 1.0)
                    2:
                        var gr = 3.0 + r * 4.0
                        draw_circle(Vector2(x, y), gr, base_color.lerp(Color(0.35, 0.5, 0.2), r * 0.3) * 0.5)
                    3:
                        var dlen = 5.0 + r * 8.0
                        var dangle = r2 * TAU
                        draw_line(Vector2(x, y), Vector2(x + cos(dangle) * dlen, y + sin(dangle) * dlen), base_color * 0.38, 1.5)
            y += step
        x += step

func _draw_colony_modules_topdown(cam: Vector2):
    var host = _h()
    var planet_name = host.surface_data.get("name", "")
    if planet_name == "":
        return
    var colony = GameManager.get_colony_for_planet(planet_name, GameManager.current_system)
    if colony.is_empty():
        return
    var modules: Array = colony.get("colony_modules", [])
    if modules.is_empty():
        return


    var type_colors: Dictionary = {
        "reactor": Color(0.9, 0.6, 0.2),
        "engine": Color(0.3, 0.5, 0.9),
        "weapon": Color(0.9, 0.25, 0.2),
        "shield": Color(0.3, 0.7, 0.9),
        "quarters": Color(0.4, 0.7, 0.3),
        "life_support": Color(0.3, 0.8, 0.5),
        "cargo": Color(0.6, 0.5, 0.3),
        "medbay": Color(0.8, 0.3, 0.5),
        "sensor": Color(0.6, 0.3, 0.8),
        "bridge": Color(0.8, 0.75, 0.3),
        "mining": Color(0.65, 0.55, 0.35),
        "hydroponics": Color(0.3, 0.75, 0.3),
        "solar_field": Color(0.9, 0.85, 0.3),
        "hallway": Color(0.35, 0.35, 0.4),
        "structural": Color(0.3, 0.3, 0.35),
    }

    var hex_size: float = 80.0
    var hw: float = 1050.0
    var hh: float = 650.0


    for mod in modules:
        if int(mod.get("deck", 0)) != 0:
            continue
        var gp = mod.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        var mod_data = mod.get("data", {})
        var mtype = mod_data.get("type", "structural")
        var base_col = type_colors.get(mtype, Color(0.4, 0.4, 0.45))


        var hex_shape = mod_data.get("hex_shape", HexUtil.default_shape(int(mod_data.get("hex_size", 1))))
        var rot = int(mod.get("rotation", 0)) % 6
        if rot > 0:
            for _i in rot:
                hex_shape = HexUtil.rotate_shape_cw(hex_shape)

        for offset in hex_shape:
            var cell = Vector2i(gp.x + offset[0], gp.y + offset[1])
            var px = HexUtil.hex_to_pixel(cell, hex_size)

            if absf(px.x - cam.x) > hw + hex_size or absf(px.y - cam.y) > hh + hex_size:
                continue

            var corners = HexUtil.hex_corners(px, hex_size * 0.95)
            draw_colored_polygon(corners, Color(base_col, 0.7))
            draw_polyline(corners, Color(base_col * 1.3, 0.8), 1.5)

            if corners.size() >= 2:
                draw_line(corners[corners.size() - 1], corners[0], Color(base_col * 1.3, 0.8), 1.5)


    var dome_r: float = hex_size * 1.5

    draw_arc(Vector2.ZERO, dome_r * 1.8, 0, TAU, 32, Color(0.4, 0.7, 0.3, 0.4), 3.0)

    var pad_size: float = hex_size * 0.8
    draw_line(Vector2( - pad_size, 0), Vector2(pad_size, 0), Color(0.6, 0.6, 0.5, 0.5), 2.0)
    draw_line(Vector2(0, - pad_size), Vector2(0, pad_size), Color(0.6, 0.6, 0.5, 0.5), 2.0)

    draw_circle(Vector2.ZERO, dome_r * 0.6, Color(0.25, 0.45, 0.3, 0.6))
    draw_arc(Vector2.ZERO, dome_r * 0.6, 0, TAU, 24, Color(0.4, 0.8, 0.4, 0.7), 2.0)

    var beacon_pulse = sin(Time.get_ticks_msec() * 0.003) * 0.3 + 0.7
    draw_circle(Vector2.ZERO, 6.0, Color(0.3, 1.0, 0.5, beacon_pulse))
    draw_circle(Vector2.ZERO, 12.0 * beacon_pulse, Color(0.3, 1.0, 0.5, 0.15))


    var font = ThemeDB.fallback_font
    var col_name = colony.get("name", "Colony")
    var tier_text = " [T%d]" % int(colony.get("tier", 1))
    var pop_text = " Pop: %d" % int(colony.get("population", 0))
    draw_string(font, Vector2(-60, - hex_size * 2.5 - 10), col_name + tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.95, 0.7, 0.9))
    draw_string(font, Vector2(-40, - hex_size * 2.5 + 10), pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 0.65, 0.7))
