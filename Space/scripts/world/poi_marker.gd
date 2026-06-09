extends Area2D




var poi_id: String = ""
var poi_name: String = ""
var poi_type: String = ""
var poi_description: String = ""
var event_id: String = ""
var planet_data: Dictionary = {}
var interact_radius: float = 120.0
var pulse_time: float = 0.0
var player_nearby: bool = false
var discovered: bool = false
var visited: bool = false
var scanned: bool = false
var scan_flash: float = 0.0
var sprite_path: String = ""
var sprite_texture: Texture2D = null
var visual_scale: float = 1.0
var gravity_radius: float = 0.0
var anim_frames: int = 1
var anim_fps: float = 0.0
var _anim_time: float = 0.0


var _prev_player_nearby: bool = false
var _prev_scanned: bool = false
var _prev_visited: bool = false


var orbit_center: Vector2 = Vector2.ZERO
var orbit_dist: float = 0.0
var orbit_angle: float = 0.0
var orbit_speed: float = 0.0
var orbit_parent: Area2D = null

signal interacted(event_id: String)
signal planet_entered(data: Dictionary)

var type_colors: Dictionary = {
    "station": Color(0.3, 0.85, 0.4), 
    "hostile_station": Color(0.95, 0.3, 0.2), 
    "salvage": Color(0.85, 0.75, 0.3), 
    "resource": Color(0.4, 0.7, 0.95), 
    "anomaly": Color(0.7, 0.4, 1.0), 
    "ruin": Color(0.2, 0.85, 0.95), 
    "planet": Color(0.3, 0.7, 0.3), 
    "npc_colony": Color(0.4, 0.85, 0.5), 
}

var type_symbols: Dictionary = {
    "station": "S", 
    "hostile_station": "!", 
    "salvage": "?", 
    "resource": "R", 
    "anomaly": "~", 
    "ruin": "A", 
    "planet": "P", 
    "npc_colony": "C", 
}

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("pois")

    var shape = CircleShape2D.new()
    shape.radius = interact_radius
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)
    queue_redraw()

func setup(data: Dictionary, eid: String):
    poi_id = str(data.get("id", ""))
    poi_name = data.get("name", "Unknown")
    poi_type = data.get("type", "anomaly")
    poi_description = data.get("description", "")
    event_id = eid
    if data.has("planet_data"):
        planet_data = data.get("planet_data", {})

    if poi_type == "planet":
        interact_radius = 600.0

    sprite_path = data.get("sprite", "")
    visual_scale = data.get("visual_scale", 1.0)
    gravity_radius = data.get("gravity_radius", 0.0)
    anim_frames = maxi(int(data.get("anim_frames", 1)), 1)
    anim_fps = maxf(float(data.get("anim_fps", 0.0)), 0.0)
    if sprite_path != "":
        sprite_texture = _load_texture_from_path(sprite_path)

    if eid != "" and GameManager.visited_events.has(eid):
        visited = true

func _process(delta: float):
    var prev_anim_frame: int = _current_anim_frame()
    pulse_time += delta
    if scan_flash > 0:
        scan_flash -= delta * 2.0
    if sprite_texture != null and anim_frames > 1 and anim_fps > 0.0:
        _anim_time += delta

    if orbit_speed != 0.0:
        orbit_angle += orbit_speed * delta
        var center = orbit_center
        if orbit_parent and is_instance_valid(orbit_parent):
            center = orbit_parent.global_position
        global_position = center + Vector2.from_angle(orbit_angle) * orbit_dist

    if poi_type in ["station", "hostile_station"]:
        return

    var _poi_cam = get_viewport().get_camera_2d()
    var _poi_cull_dist = 8000.0 if poi_type != "planet" else 20000.0
    if _poi_cam and global_position.distance_to(_poi_cam.global_position) > _poi_cull_dist:
        return

    var players = get_tree().get_nodes_in_group("player")
    player_nearby = false
    if not players.is_empty():
        var p = players[0]
        if global_position.distance_to(p.global_position) < interact_radius:
            player_nearby = true
            if Input.is_action_just_pressed("interact"):
                if poi_type == "planet" and not planet_data.is_empty():
                    planet_entered.emit(planet_data)
                elif event_id != "":
                    interacted.emit(event_id)

    var visual_changed = false
    if player_nearby != _prev_player_nearby:
        _prev_player_nearby = player_nearby
        visual_changed = true
    if scan_flash > 0:
        visual_changed = true
    if scanned != _prev_scanned:
        _prev_scanned = scanned
        visual_changed = true
    if visited != _prev_visited:
        _prev_visited = visited
        visual_changed = true
    if _current_anim_frame() != prev_anim_frame:
        visual_changed = true
    if visual_changed:
        queue_redraw()

func _draw():

    if poi_type in ["station", "hostile_station"]:
        return
    var base_color = type_colors.get(poi_type, Color(0.5, 0.5, 0.5))
    if visited:
        base_color = base_color * 0.5


    if scan_flash > 0:
        base_color = base_color.lerp(Color.WHITE, clampf(scan_flash, 0, 0.6))

    var r: float = 18.0 if poi_type != "planet" else 450.0
    var pulse = sin(pulse_time * 2.0) * 0.2 + 0.8
    var _slow_pulse = sin(pulse_time * 0.8) * 0.5 + 0.5


    var scan_offset: float = 14.0 if poi_type != "planet" else r * 0.05
    if scanned and not visited:
        draw_arc(Vector2.ZERO, r + scan_offset, 0, TAU, 32 if poi_type == "planet" else 24, Color(0.2, 0.9, 0.5, 0.2), 2.0 if poi_type == "planet" else 1.0)
        for i in 4:
            var a = TAU * i / 4.0 + pulse_time * 0.3
            var p1 = Vector2.from_angle(a) * (r + scan_offset - 2)
            var p2 = Vector2.from_angle(a) * (r + scan_offset + 4)
            draw_line(p1, p2, Color(0.2, 0.9, 0.5, 0.3), 2.0 if poi_type == "planet" else 1.0)


    r *= visual_scale

    # Gravity well visualization
    if gravity_radius > 0:
        for gi in 3:
            var gt = float(gi) / 3.0
            var gr = gravity_radius * (1.0 - gt * 0.3)
            draw_arc(Vector2.ZERO, gr, 0, TAU, 48, Color(base_color, 0.06 * (1.0 - gt)), 1.5)

    # Custom sprite rendering — skip procedural shapes
    if sprite_texture:
        var tex_size: Vector2 = sprite_texture.get_size()
        var frame_count: int = maxi(anim_frames, 1)
        var frame_w: float = tex_size.x / float(frame_count)
        var frame_size: Vector2 = Vector2(frame_w, tex_size.y)
        var src_rect: Rect2 = Rect2(frame_w * float(_current_anim_frame()), 0.0, frame_w, tex_size.y)
        var max_dim = maxf(frame_size.x, frame_size.y)
        var scale_factor = (r * 2.0) / max_dim
        var draw_sz: Vector2 = frame_size * scale_factor
        draw_texture_rect_region(sprite_texture, Rect2(-draw_sz * 0.5, draw_sz), src_rect)
        _draw_ring_and_labels(base_color, r, pulse)
        return

    if poi_type != "planet":

        draw_circle(Vector2.ZERO, r + 10, Color(base_color, 0.04 * pulse))

        draw_arc(Vector2.ZERO, r + 8, 0, TAU, 24, Color(base_color, 0.12 * pulse), 1.5)

        draw_circle(Vector2.ZERO, r, Color(0.04, 0.04, 0.06, 0.92))

        draw_arc(Vector2.ZERO, r - 1, 0, TAU, 20, Color(base_color, 0.08), 1.0)


    match poi_type:
        "station":

            var pts = PackedVector2Array([
                Vector2(0, - r * 0.7), Vector2(r * 0.7, 0), 
                Vector2(0, r * 0.7), Vector2( - r * 0.7, 0), 
            ])
            draw_colored_polygon(pts, base_color * 0.5)
            draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), base_color, 1.5)


            var inner_s = 0.35
            draw_line(Vector2(0, - r * inner_s), Vector2(r * inner_s, 0), base_color * 0.7, 0.8)
            draw_line(Vector2(r * inner_s, 0), Vector2(0, r * inner_s), base_color * 0.7, 0.8)
            draw_line(Vector2(0, r * inner_s), Vector2( - r * inner_s, 0), base_color * 0.7, 0.8)
            draw_line(Vector2( - r * inner_s, 0), Vector2(0, - r * inner_s), base_color * 0.7, 0.8)

            draw_circle(Vector2(0, - r * 0.7), 1.5, Color(base_color, 0.8))
            draw_circle(Vector2(0, r * 0.7), 1.5, Color(base_color, 0.8))
        "hostile_station":

            for i in 6:
                var a = TAU * i / 6.0
                var a2 = TAU * (i + 0.5) / 6.0
                draw_line(Vector2.from_angle(a) * r * 0.4, Vector2.from_angle(a2) * r * 0.85, base_color, 1.8)
                draw_line(Vector2.from_angle(a2) * r * 0.85, Vector2.from_angle(a + TAU / 6.0) * r * 0.4, base_color * 0.6, 1.0)

            draw_circle(Vector2.ZERO, r * 0.25, Color(base_color, 0.6 * pulse))
        "salvage":

            var cr = r * 0.55
            draw_rect(Rect2( - cr, - cr, cr * 2, cr * 2), base_color * 0.45)
            draw_rect(Rect2( - cr, - cr, cr * 2, cr * 2), base_color, false, 1.5)

            draw_line(Vector2( - cr, 0), Vector2(cr, 0), base_color * 0.65, 1.0)
            draw_line(Vector2(0, - cr), Vector2(0, cr), base_color * 0.65, 1.0)

            draw_circle(Vector2(0, cr * 0.15), 1.5, Color(base_color, 0.7 * pulse))
        "resource":

            var pts = PackedVector2Array()
            for i in 6:
                pts.append(Vector2.from_angle(TAU * i / 6.0 - PI / 6.0) * r * 0.65)
            draw_colored_polygon(pts, base_color * 0.45)
            draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[0]]), base_color, 1.5)

            draw_line(pts[0], pts[3], base_color * 0.35, 0.7)
            draw_line(pts[1], pts[4], base_color * 0.35, 0.7)
            draw_line(pts[2], pts[5], base_color * 0.35, 0.7)
        "anomaly":

            for i in 16:
                var a = TAU * i / 16.0 + pulse_time * 1.5
                var r2 = r * 0.2 + r * 0.45 * (float(i) / 16.0)
                var dot_a = 0.3 + pulse * 0.4 - float(i) / 16.0 * 0.3
                draw_circle(Vector2.from_angle(a) * r2, 1.2 + float(i) / 16.0, Color(base_color, clampf(dot_a, 0.1, 0.8)))

            draw_circle(Vector2.ZERO, 2.5, Color(base_color, 0.6 * pulse))
        "ruin":

            var pts = PackedVector2Array([
                Vector2(0, - r * 0.7), Vector2(r * 0.6, r * 0.5), Vector2( - r * 0.6, r * 0.5), 
            ])
            draw_colored_polygon(pts, base_color * 0.45)
            draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), base_color, 1.5)

            draw_circle(Vector2(0, r * 0.05), 2.5, Color(base_color, 0.6 * pulse))
            draw_arc(Vector2(0, r * 0.05), 4, - PI * 0.6, PI * 0.6, 6, Color(base_color, 0.4), 0.8)
        "planet":

            var pr: float = r

            var phash: float = 0.0
            for chi in poi_name.length():
                phash += float(poi_name.unicode_at(chi)) * (float(chi) + 1.0) * 0.137
            var ph1 = sin(phash * 1.37) * 0.5 + 0.5
            var ph2 = sin(phash * 2.71) * 0.5 + 0.5
            var ph3 = sin(phash * 3.14) * 0.5 + 0.5
            var ph4 = sin(phash * 4.56) * 0.5 + 0.5


            draw_circle(Vector2.ZERO, pr * 1.12, Color(base_color, 0.015))
            draw_circle(Vector2.ZERO, pr * 1.08, Color(base_color, 0.03))
            draw_circle(Vector2.ZERO, pr * 1.04, Color(base_color, 0.05))
            draw_arc(Vector2.ZERO, pr * 1.06, 0, TAU, 48, Color(base_color, 0.07), pr * 0.04)


            draw_circle(Vector2.ZERO, pr, base_color * 0.4)


            var band_count: int = 8 + int(ph1 * 4)
            for band_i in band_count:
                var band_t = float(band_i) / float(band_count)
                var band_y = - pr + band_t * pr * 2.0
                var band_half_w = sqrt(maxf(pr * pr - band_y * band_y, 0))
                if band_half_w < 2:
                    continue
                var band_bright = 0.35 + sin(band_t * 12.0 + phash) * 0.12
                var band_h = pr * 2.0 / float(band_count)
                var band_col = base_color * band_bright
                if int(band_i + int(phash)) % 3 == 0:
                    band_col = base_color.lerp(Color(base_color.r * 0.7, base_color.g * 1.1, base_color.b * 0.8), 0.3) * band_bright
                draw_line(Vector2( - band_half_w, band_y), Vector2(band_half_w, band_y), band_col, band_h * 0.8)


            for ci in 6:
                var ca = phash * float(ci + 1) * 0.7
                var cx_off = cos(ca) * pr * 0.35
                var cy_off = sin(ca) * pr * 0.3
                var crad = pr * (0.12 + sin(float(ci) * 3.7 + phash) * 0.06)
                if Vector2(cx_off, cy_off).length() + crad < pr * 0.9:
                    var continent_col = base_color.lerp(Color(0.2, 0.4, 0.15), 0.3 + ph2 * 0.3)
                    draw_circle(Vector2(cx_off, cy_off), crad, Color(continent_col, 0.25))
                    for bi in 4:
                        var boff = Vector2(cos(ca + float(bi) * 1.5) * crad * 0.5, sin(ca + float(bi) * 2.1) * crad * 0.4)
                        draw_circle(Vector2(cx_off, cy_off) + boff, crad * 0.4, Color(continent_col, 0.15))


            for ci in 8:
                var cloud_a = phash * 0.5 + float(ci) * 0.8 + pulse_time * 0.05
                var cloud_y = - pr * 0.7 + float(ci) * pr * 0.2
                var cloud_hw = sqrt(maxf(pr * pr - cloud_y * cloud_y, 0)) * (0.3 + ph3 * 0.25)
                var cloud_x = cos(cloud_a) * pr * 0.2
                if abs(cloud_y) < pr * 0.85:
                    draw_line(Vector2(cloud_x - cloud_hw, cloud_y), Vector2(cloud_x + cloud_hw, cloud_y), 
                        Color(1, 1, 1, 0.06 + sin(pulse_time * 0.3 + float(ci)) * 0.02), pr * 0.03)


            if ph4 > 0.3:
                draw_arc(Vector2.ZERO, pr * 0.95, - PI * 0.8, - PI * 0.2, 12, Color(0.85, 0.9, 1.0, 0.12), pr * 0.12)
                draw_arc(Vector2.ZERO, pr * 0.95, PI * 0.2, PI * 0.8, 12, Color(0.85, 0.9, 1.0, 0.1), pr * 0.1)


            for si in 6:
                var st = float(si) / 6.0
                var shadow_a = 0.08 + st * 0.12
                var shadow_offset = st * pr * 0.15
                draw_arc(Vector2(shadow_offset, 0), pr * (0.98 - st * 0.02), PI * 0.15, PI * 1.85, 32, 
                    Color(0, 0, 0, shadow_a), pr * 0.3)


            for di in 5:
                var da = phash * float(di + 1) * 1.3
                var dd = pr * (0.3 + sin(float(di) * 2.5) * 0.2)
                var dp = Vector2(cos(da) * dd, sin(da) * dd * 0.7)
                if dp.length() < pr * 0.75:
                    draw_arc(dp, pr * 0.06, 0, TAU, 10, Color(base_color * 0.5, 0.1), pr * 0.008)


            draw_arc(Vector2.ZERO, pr * 1.002, - PI * 0.5, PI * 0.4, 32, Color(base_color.lerp(Color.WHITE, 0.3), 0.35), pr * 0.02)
            draw_arc(Vector2.ZERO, pr * 1.008, - PI * 0.4, PI * 0.3, 28, Color(base_color, 0.15), pr * 0.015)
            draw_arc(Vector2.ZERO, pr * 1.015, - PI * 0.3, PI * 0.2, 24, Color(base_color, 0.06), pr * 0.01)


            draw_circle(Vector2( - pr * 0.25, - pr * 0.3), pr * 0.03, Color(1, 1, 1, 0.2))
            draw_circle(Vector2( - pr * 0.22, - pr * 0.27), pr * 0.015, Color(1, 1, 1, 0.35))

        "npc_colony":

            var dr = r * 0.65

            draw_rect(Rect2( - dr, dr * 0.1, dr * 2, dr * 0.4), base_color * 0.4)
            draw_rect(Rect2( - dr, dr * 0.1, dr * 2, dr * 0.4), base_color * 0.7, false, 1.0)

            draw_arc(Vector2.ZERO, dr * 0.55, PI, TAU, 12, base_color, 2.0)
            draw_circle(Vector2.ZERO, dr * 0.15, Color(base_color, 0.6 * pulse))

            draw_rect(Rect2( - dr * 0.8, - dr * 0.3, dr * 0.35, dr * 0.7), base_color * 0.5)
            draw_rect(Rect2(dr * 0.45, - dr * 0.15, dr * 0.35, dr * 0.55), base_color * 0.5)

            draw_circle(Vector2(0, - dr * 0.55), 2.0, Color(0.3, 1.0, 0.5, pulse))
        _:
            draw_circle(Vector2.ZERO, r * 0.5, base_color * 0.6)


    _draw_ring_and_labels(base_color, r, pulse)

func _draw_ring_and_labels(base_color: Color, r: float, pulse: float):
    var ring_width: float = 1.5 if poi_type != "planet" else 3.0
    draw_arc(Vector2.ZERO, r, 0, TAU, 32 if poi_type == "planet" else 24, base_color * pulse, ring_width)

    var font = ThemeDB.fallback_font
    var prompt_offset: float = r + 20
    if player_nearby and not visited:
        var prompt_text = "[E] " + poi_name
        var prompt_font_size: int = 12 if poi_type != "planet" else 16
        draw_rect(Rect2(-40, - prompt_offset - 12, prompt_text.length() * 8.0 + 10, 20), Color(0, 0, 0, 0.5))
        draw_string(font, Vector2(-36, - prompt_offset), prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_font_size, Color(base_color, 0.95))
    elif player_nearby and visited:
        var prompt_text = "[E] " + poi_name + " (visited)"
        draw_rect(Rect2(-40, - prompt_offset - 12, prompt_text.length() * 7.0 + 10, 20), Color(0, 0, 0, 0.35))
        draw_string(font, Vector2(-36, - prompt_offset), prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(base_color, 0.5))

    var label_size: int = 10 if poi_type != "planet" else 16
    var label_y: float = r + 20 if poi_type != "planet" else r + 40
    draw_string(font, Vector2( - poi_name.length() * 4, label_y), poi_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(base_color, 0.5))

    if scanned and poi_description != "":
        var desc_y: float = label_y + 18
        draw_string(font, Vector2( - poi_description.length() * 2.5, desc_y), poi_description, HORIZONTAL_ALIGNMENT_LEFT, 300, 10, Color(base_color, 0.35))


func _load_texture_from_path(path: String) -> Texture2D:
    var loaded: Variant = load(path)
    if loaded is Texture2D:
        return loaded
    if not FileAccess.file_exists(path):
        return null
    var img := Image.new()
    if img.load(path) != OK:
        return null
    return ImageTexture.create_from_image(img)


func _current_anim_frame() -> int:
    if sprite_texture == null or anim_frames <= 1 or anim_fps <= 0.0:
        return 0
    return int(floor(_anim_time * anim_fps)) % anim_frames
