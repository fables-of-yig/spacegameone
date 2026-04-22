extends Area2D





@warning_ignore("unused_signal")
signal mine_started(asteroid: Node2D)
const HARPOON_COLLISION_MASS: float = 1000000.0
var field_seed: int = 0
var resource_type: String = "ore"
var richness: float = 1.0
var remaining: float = 100.0
var max_remaining: float = 100.0
var interact_radius: float = 150.0
var ship_size: float = 72.0
var player_nearby: bool = false
var mining: bool = false
var mine_progress: float = 0.0


var rocks: Array = []
var pulse_time: float = 0.0
var field_color: Color = Color(0.5, 0.45, 0.4)
var rng: RandomNumberGenerator

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("asteroids")
    var shape = CircleShape2D.new()
    shape.radius = interact_radius
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)

func setup(seed_val: int, res_type: String, rich: float, amount: float):
    field_seed = seed_val
    resource_type = res_type
    richness = rich
    remaining = amount
    max_remaining = amount
    rng = RandomNumberGenerator.new()
    rng.seed = seed_val

    var res_info = GameManager.RESOURCE_TYPES.get(res_type, {})
    var rc = res_info.get("color", [0.5, 0.45, 0.4])
    field_color = Color(rc[0], rc[1], rc[2])
    _generate_rocks()
    _refresh_harpoon_profile()

func get_harpoon_hit_radius() -> float:
    return ship_size

func _get_collision_mass() -> float:
    return HARPOON_COLLISION_MASS

func _refresh_harpoon_profile() -> void:
    var max_rock_extent: float = 40.0
    for rock in rocks:
        var offset: Vector2 = rock.get("offset", Vector2.ZERO)
        var rock_size: float = float(rock.get("size", 12.0))
        max_rock_extent = maxf(max_rock_extent, offset.length() + rock_size)
    ship_size = max_rock_extent

func _generate_rocks():
    rocks.clear()
    var count = rng.randi_range(4, 8)
    for i in count:
        var angle = rng.randf() * TAU
        var dist = rng.randf_range(15, 50)
        var rock_size = rng.randf_range(8, 22)
        var rot = rng.randf() * TAU

        var verts: PackedVector2Array = []
        var sides = rng.randi_range(5, 8)
        for s in sides:
            var a = float(s) / float(sides) * TAU + rot
            var r = rock_size * rng.randf_range(0.6, 1.0)
            verts.append(Vector2(cos(a), sin(a)) * r)

        var color_hash = hash(field_seed * 1000 + i * 137)
        var hue_shift = fmod(float(color_hash & 65535) / 65535.0, 1.0) * 0.15 - 0.075
        var val_shift = fmod(float((color_hash >> 16) & 65535) / 65535.0, 1.0) * 0.2 - 0.1

        var cracks: Array = []
        var crack_count = rng.randi_range(2, 3)
        for _c in crack_count:
            var ci1 = rng.randi_range(0, sides - 1)
            var ci2 = rng.randi_range(0, sides - 1)
            if ci1 == ci2:
                ci2 = (ci2 + 1) % sides
            var t1 = rng.randf_range(0.25, 0.6)
            var t2 = rng.randf_range(0.25, 0.6)
            var center_off = Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
            cracks.append({"i1": ci1, "i2": ci2, "t1": t1, "t2": t2, "center_off": center_off})

        var glints: Array = []
        var glint_count = rng.randi_range(2, 4)
        for _g in glint_count:
            var ga = rng.randf() * TAU
            var gr = rng.randf_range(0.2, 0.7) * rock_size
            glints.append(Vector2(cos(ga), sin(ga)) * gr)
        rocks.append({
            "offset": Vector2(cos(angle), sin(angle)) * dist, 
            "size": rock_size, 
            "verts": verts, 
            "hue_shift": hue_shift, 
            "val_shift": val_shift, 
            "cracks": cracks, 
            "glints": glints, 
        })

func _process(delta: float):
    pulse_time += delta
    var players = get_tree().get_nodes_in_group("player")
    player_nearby = false
    mining = false
    if not players.is_empty():
        var p = players[0]
        var dist = global_position.distance_to(p.global_position)
        if dist < interact_radius:
            player_nearby = true

            var mine_rate = GameManager.get_mine_rate()
            if mine_rate > 0 and remaining > 0:
                mining = true
                mine_progress += mine_rate * richness * delta
                if mine_progress >= 1.0:
                    var units = int(mine_progress)
                    mine_progress -= float(units)
                    var added = GameManager.add_resource(resource_type, units)
                    remaining = maxf(remaining - float(added), 0)

    queue_redraw()

func _draw():

    var depletion = 1.0 - clampf(remaining / max_remaining, 0, 1)
    var base_alpha = lerpf(0.9, 0.3, depletion)
    var time = pulse_time

    var light_dir = Vector2(-0.7, -0.7).normalized()

    var res_info_glint = GameManager.RESOURCE_TYPES.get(resource_type, {})
    var rc_glint = res_info_glint.get("color", [0.5, 0.45, 0.4])
    var glint_base = Color(rc_glint[0], rc_glint[1], rc_glint[2])
    var glint_col = Color(
        minf(glint_base.r * 1.4 + 0.2, 1.0), 
        minf(glint_base.g * 1.4 + 0.2, 1.0), 
        minf(glint_base.b * 1.4 + 0.2, 1.0)
    )


    var dust_alpha = base_alpha * 0.06
    draw_circle(Vector2.ZERO, interact_radius * 0.6, Color(field_color, dust_alpha))
    draw_circle(Vector2(15, -10), interact_radius * 0.45, Color(field_color, dust_alpha * 0.7))
    draw_circle(Vector2(-20, 8), interact_radius * 0.4, Color(field_color, dust_alpha * 0.5))


    for di in 12:
        var da = float(di) / 12.0 * TAU + float(field_seed) * 0.1
        var dd = 25.0 + sin(da * 3.0 + float(field_seed)) * 15.0
        var dp = Vector2(cos(da) * dd, sin(da) * dd)
        var ds = 1.0 + sin(float(di) * 2.3) * 0.5
        draw_circle(dp, ds, Color(field_color.r * 0.5, field_color.g * 0.45, field_color.b * 0.4, base_alpha * 0.4))

    for rock in rocks:
        var offset: Vector2 = rock.offset
        var verts: PackedVector2Array = rock.verts
        if verts.size() < 3:
            continue
        var shifted: PackedVector2Array = []
        for v in verts:
            shifted.append(v + offset)
        var rock_size: float = rock.get("size", 12.0)
        var hue_shift: float = rock.get("hue_shift", 0.0)
        var val_shift: float = rock.get("val_shift", 0.0)


        var warm_base = Color(
            clampf(field_color.r * 0.7 + 0.18 + hue_shift, 0.15, 0.85), 
            clampf(field_color.g * 0.6 + 0.12, 0.1, 0.7), 
            clampf(field_color.b * 0.5 + 0.08 - abs(hue_shift) * 0.5, 0.05, 0.6)
        )
        var body_col = Color(
            clampf(warm_base.r + val_shift, 0.12, 0.9), 
            clampf(warm_base.g + val_shift * 0.7, 0.08, 0.8), 
            clampf(warm_base.b + val_shift * 0.4, 0.05, 0.7), 
            base_alpha
        )
        draw_colored_polygon(shifted, body_col)


        var center = offset
        var shadow_shifted: PackedVector2Array = []
        var shadow_dir = - light_dir * rock_size * 0.15
        for v in verts:
            shadow_shifted.append(v * 0.6 + offset + shadow_dir)
        if shadow_shifted.size() >= 3:
            draw_colored_polygon(shadow_shifted, Color(body_col.r * 0.6, body_col.g * 0.55, body_col.b * 0.5, base_alpha * 0.3))


        var highlight_shifted: PackedVector2Array = []
        var highlight_dir = light_dir * rock_size * 0.1
        for v in verts:
            highlight_shifted.append(v * 0.4 + offset + highlight_dir)
        if highlight_shifted.size() >= 3:
            draw_colored_polygon(highlight_shifted, Color(1.0, 0.97, 0.9, base_alpha * 0.08))


        var vert_count = shifted.size()
        for vi in vert_count:
            var next_i = (vi + 1) % vert_count
            var edge_mid = (shifted[vi] + shifted[next_i]) * 0.5
            var edge_dir = (edge_mid - center).normalized()
            var dot = edge_dir.dot(light_dir)
            if dot > 0.1:
                var highlight_a = dot * 0.45 * base_alpha
                draw_line(shifted[vi], shifted[next_i], Color(1.0, 0.95, 0.85, highlight_a), 1.8)
            elif dot < -0.1:
                var shadow_a = abs(dot) * 0.55 * base_alpha
                draw_line(shifted[vi], shifted[next_i], Color(0.03, 0.01, 0.0, shadow_a), 2.5)


        var outline_col = Color(
            body_col.r * 0.25, 
            body_col.g * 0.2, 
            body_col.b * 0.15, 
            base_alpha * 0.85
        )
        for vi in vert_count:
            var next_i = (vi + 1) % vert_count

            draw_line(shifted[vi], shifted[next_i], Color(body_col, base_alpha * 0.08), 4.0)
        for vi in vert_count:
            var next_i = (vi + 1) % vert_count
            draw_line(shifted[vi], shifted[next_i], outline_col, 1.3)


        var crack_col = Color(body_col.r * 0.25, body_col.g * 0.2, body_col.b * 0.15, base_alpha * 0.65)
        var rock_cracks: Array = rock.get("cracks", [])
        for cr in rock_cracks:
            var i1: int = clampi(cr.get("i1", 0), 0, verts.size() - 1)
            var i2: int = clampi(cr.get("i2", 1), 0, verts.size() - 1)
            var t1: float = cr.get("t1", 0.4)
            var t2: float = cr.get("t2", 0.4)
            var c_off: Vector2 = cr.get("center_off", Vector2.ZERO)
            var p1 = verts[i1].lerp(Vector2.ZERO, t1) + offset
            var p2 = c_off + offset
            var p3 = verts[i2].lerp(Vector2.ZERO, t2) + offset
            draw_line(p1, p2, crack_col, 0.9)
            draw_line(p2, p3, crack_col, 0.9)

            var branch_dir = Vector2(c_off.y, - c_off.x).normalized() * rock_size * 0.2
            draw_line(p2, p2 + branch_dir, Color(crack_col, crack_col.a * 0.5), 0.6)


        var rock_glints: Array = rock.get("glints", [])
        var gi_idx = 0
        for gp in rock_glints:
            var glint_pos: Vector2 = gp + offset

            var sparkle = sin(time * (2.0 + float(gi_idx) * 0.7) + float(gi_idx) * 1.3) * 0.4 + 0.6

            draw_circle(glint_pos, 2.0, Color(glint_col, base_alpha * 0.15 * sparkle))

            draw_circle(glint_pos, 1.0, Color(glint_col, base_alpha * 0.9 * sparkle))

            draw_circle(glint_pos, 0.4, Color(1.0, 1.0, 1.0, base_alpha * 0.8 * sparkle))

            if sparkle > 0.8:
                var slen = 2.5 * sparkle
                var sa = base_alpha * 0.4 * (sparkle - 0.8) * 5.0
                draw_line(glint_pos + Vector2( - slen, 0), glint_pos + Vector2(slen, 0), Color(1.0, 1.0, 1.0, sa), 0.5)
                draw_line(glint_pos + Vector2(0, - slen), glint_pos + Vector2(0, slen), Color(1.0, 1.0, 1.0, sa), 0.5)
            gi_idx += 1


    var res_info = GameManager.RESOURCE_TYPES.get(resource_type, {})
    var res_name = res_info.get("name", resource_type)


    if player_nearby:
        var label_y = -65.0
        var font = ThemeDB.fallback_font

        draw_string(font, Vector2(-40, label_y), res_name, HORIZONTAL_ALIGNMENT_LEFT, 80, 11, field_color)

        var pct = int(remaining / max_remaining * 100)
        draw_string(font, Vector2(-40, label_y + 13), "%d%% remaining" % pct, HORIZONTAL_ALIGNMENT_LEFT, 80, 10, Color(0.5, 0.5, 0.55))

        if mining:
            var pulse = sin(pulse_time * 4.0) * 0.3 + 0.7
            draw_string(font, Vector2(-30, label_y + 26), "MINING...", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.7, 0.2, pulse))

            draw_line(Vector2.ZERO, Vector2.ZERO + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), Color(0.9, 0.7, 0.2, 0.3 * pulse), 2.0)
        elif GameManager.get_mine_rate() <= 0 and remaining > 0:
            draw_string(font, Vector2(-40, label_y + 26), "Need Mining Laser", HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color(0.6, 0.4, 0.2))
        elif remaining <= 0:
            draw_string(font, Vector2(-30, label_y + 26), "DEPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.35, 0.3))




    if player_nearby:
        var ring_alpha = sin(pulse_time * 2.0) * 0.1 + 0.15
        draw_arc(Vector2.ZERO, interact_radius * 0.8, 0, TAU, 24, Color(field_color, ring_alpha), 0.5)
