extends Node2D

# Starfield rendering: procedural stars/nebulae/galaxies + animated system
# stars + baked-texture background. Extracted from main.gd.
#
# The baked background lives on a child _BgLayer (z=-100) and the animated
# system-star sprites on a child _StarSpriteLayer (z=-99, additive). Both
# layers call back into this node's _draw_bg_on_layer / _draw_star_sprites
# so the heavy draw loops stay in one place.
#
# Game state this node reads through owner_main:
#   - on_surface, menu_open, jumping (don't draw background during these)
#   - player (camera center)
#   - loaded_system, system_world_positions (which system to center on)

var stars: Array[Dictionary] = []
var nebula_clouds: Array[Dictionary] = []
var dust_motes: Array[Dictionary] = []
var gas_filaments: Array[Dictionary] = []
var distant_galaxies: Array[Dictionary] = []
var star_field_radius: float = 3000.0

var _bg_layer: Node2D
var _star_sprite_layer: Node2D
var _bg_texture: ImageTexture = null
var _bg_dirty: bool = true
var _bg_cam_pos: Vector2 = Vector2.ZERO

# Per-system background image cache. Keyed by system id; value is either a
# Texture2D loaded from system.background_image or null when the system has
# no background. Drawn behind the procedural starfield.
var _system_bg_textures: Dictionary = {}
var _custom_star_textures: Dictionary = {}

var _star_spritesheet: Texture2D = null
var _star_frame_rects: Array = []        # 30 Rect2 source regions
var _star_anim_states: Dictionary = {}   # sys_id -> {frame, dir, turn_at, accum, speed}

const STAR_SPRITE_COLS: int = 5
const STAR_SPRITE_ROWS: int = 6
const STAR_SPRITE_FRAMES: int = 30
const STAR_ANIM_SPD: float = 0.1         # ~10 fps base

# Reference to the main Node2D so we can read player/loaded_system/etc.
var owner_main: Node = null


class _BgLayer extends Node2D:
    func _draw():
        var p = get_parent()
        if p:
            p._draw_bg_on_layer(self)


class _BgBaker extends Node2D:
    var renderer_ref
    func _draw():
        if renderer_ref:
            renderer_ref._draw_bg_bake(self)


class _StarSpriteLayer extends Node2D:
    func _draw():
        var p = get_parent()
        if p:
            p._draw_star_sprites(self)


func _ready():
    _bg_layer = _BgLayer.new()
    _bg_layer.z_index = -100
    add_child(_bg_layer)
    _star_sprite_layer = _StarSpriteLayer.new()
    _star_sprite_layer.z_index = -99
    var mat = CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    _star_sprite_layer.material = mat
    add_child(_star_sprite_layer)
    _load_star_spritesheet()


func mark_dirty() -> void:
    _bg_dirty = true


# Called by main.gd each frame. Handles bg redraw gating (the baked
# background only redraws when the camera has moved enough) and advances
# the star sprite animations.
func tick(delta: float, player: Node2D) -> void:
    if player and is_instance_valid(player):
        if player.global_position.distance_squared_to(_bg_cam_pos) > 900.0:
            _bg_dirty = true
            _bg_cam_pos = player.global_position
    if _bg_dirty and _bg_layer:
        _bg_layer.queue_redraw()
        if _star_sprite_layer:
            _star_sprite_layer.queue_redraw()
        _bg_dirty = false
    _advance_star_anims(delta)


func _get_system_bg_texture(loaded_system: String) -> Texture2D:
    if loaded_system == "":
        return null
    if _system_bg_textures.has(loaded_system):
        return _system_bg_textures[loaded_system]
    var sys = DataManager.systems.get(loaded_system, {})
    var path: String = sys.get("background_image", "")
    if path == "":
        _system_bg_textures[loaded_system] = null
        return null
    var tex = load(path)
    if tex is Texture2D:
        _system_bg_textures[loaded_system] = tex
        return tex
    push_warning("system bg: failed to load %s for system %s" % [path, loaded_system])
    _system_bg_textures[loaded_system] = null
    return null


# Tiles the system background texture across the visible area with a parallax
# offset so the field feels infinite without pop-in. Tiles offset by the
# camera position scaled by (1 - parallax_factor); parallax_factor controls
# how much the bg lags behind the camera (0 = locked to camera, 1 = locked
# to world).
func _draw_system_bg(n: Node2D, cam_center: Vector2, loaded_system: String, camera_zoom: float):
    var tex = _get_system_bg_texture(loaded_system)
    if tex == null:
        return
    var sz: Vector2 = tex.get_size()
    if sz.x <= 0 or sz.y <= 0:
        return
    var parallax_factor: float = 0.18
    var view: Vector2 = Vector2(get_viewport_rect().size) / camera_zoom
    var view_tl: Vector2 = cam_center - view * 0.5
    var anchor: Vector2 = cam_center * (1.0 - parallax_factor)
    var origin: Vector2 = view_tl - (view_tl - anchor)
    var tile_x: int = int(floor((origin.x) / sz.x))
    var tile_y: int = int(floor((origin.y) / sz.y))
    var tiles_x: int = int(ceil(view.x / sz.x)) + 2
    var tiles_y: int = int(ceil(view.y / sz.y)) + 2
    for tx in tiles_x:
        for ty in tiles_y:
            var p: Vector2 = Vector2((tile_x + tx) * sz.x, (tile_y + ty) * sz.y)
            n.draw_texture(tex, p, Color(1, 1, 1, 0.85))


func generate(count: int) -> void:
    stars.clear()
    nebula_clouds.clear()
    dust_motes.clear()
    gas_filaments.clear()
    distant_galaxies.clear()

    var sfr = star_field_radius

    var star_palette: Array = [
        Color(0.75, 0.82, 1.0),
        Color(1.0, 0.95, 0.82),
        Color(1.0, 0.65, 0.35),
        Color(0.65, 0.75, 1.0),
        Color(1.0, 0.88, 0.72),
        Color(1.0, 0.45, 0.3),
        Color(0.9, 0.9, 1.0),
    ]

    var c: Color
    for i in int(count * 0.6):
        c = star_palette.pick_random().lerp(Color(0.7, 0.7, 0.8), randf_range(0.3, 0.6))
        c.a = randf_range(0.15, 0.4)
        stars.append({
            "offset": Vector2(randf_range( - sfr, sfr), randf_range( - sfr, sfr)),
            "size": randf_range(0.3, 0.8),
            "color": c,
            "twinkle": randf_range(0.5, 2.0) * [-1.0, 1.0].pick_random(),
        })

    for i in int(count * 0.3):
        c = star_palette.pick_random().lerp(Color.WHITE, randf_range(0.0, 0.3))
        c.a = randf_range(0.5, 0.85)
        stars.append({
            "offset": Vector2(randf_range( - sfr, sfr), randf_range( - sfr, sfr)),
            "size": randf_range(0.8, 1.8),
            "color": c,
            "twinkle": randf_range(1.5, 4.0) * [-1.0, 1.0].pick_random(),
        })

    for i in int(count * 0.1):
        c = star_palette.pick_random()
        c.a = randf_range(0.8, 1.0)
        var sz = randf_range(2.0, 3.5)
        if randf() < 0.15:
            sz = randf_range(3.5, 5.0)
        stars.append({
            "offset": Vector2(randf_range( - sfr, sfr), randf_range( - sfr, sfr)),
            "size": sz,
            "color": c,
            "twinkle": randf_range(2.0, 5.0) * [-1.0, 1.0].pick_random(),
        })


    var nebula_themes: Array = [
        [Color(0.5, 0.15, 0.6), Color(0.25, 0.1, 0.45)],
        [Color(0.15, 0.35, 0.65), Color(0.08, 0.18, 0.5)],
        [Color(0.6, 0.2, 0.15), Color(0.45, 0.1, 0.08)],
        [Color(0.2, 0.55, 0.45), Color(0.1, 0.35, 0.3)],
        [Color(0.55, 0.4, 0.15), Color(0.4, 0.25, 0.08)],
        [Color(0.35, 0.15, 0.5), Color(0.6, 0.2, 0.35)],
    ]
    var nebula_count = randi_range(6, 10)
    for i in nebula_count:
        var theme = nebula_themes.pick_random()
        var core_col: Color = theme[0]
        var edge_col: Color = theme[1]
        core_col = core_col.lerp(Color(randf_range(0.2, 0.8), randf_range(0.1, 0.6), randf_range(0.2, 0.9)), 0.15)
        var r = randf_range(400, 1000)
        var cloud_offset = Vector2(randf_range( - sfr * 0.9, sfr * 0.9), randf_range( - sfr * 0.9, sfr * 0.9))

        var blobs: Array = []
        var num_blobs = randi_range(14, 28)
        for bi in num_blobs:

            var blob_dist = r * randf() * randf()
            var blob_angle = randf() * TAU
            var blob_pos = Vector2.from_angle(blob_angle) * blob_dist
            var blob_r = r * randf_range(0.2, 0.55) * (1.0 - blob_dist / r * 0.4)

            var dist_t = blob_dist / r
            var blob_col = core_col.lerp(edge_col, dist_t * 0.8)
            blob_col.a = randf_range(0.01, 0.03) * (1.0 - dist_t * 0.5)

            var verts = PackedVector2Array()
            var nv = randi_range(12, 20)
            var f1 = randf_range(2.0, 4.0)
            var f2 = randf_range(4.0, 7.0)
            var a1 = randf_range(0.15, 0.35)
            var a2 = randf_range(0.05, 0.2)
            var p1 = randf() * TAU
            var p2 = randf() * TAU
            for vi in nv:
                var va = float(vi) / float(nv) * TAU
                var noise_r = 1.0 + sin(va * f1 + p1) * a1 + sin(va * f2 + p2) * a2
                verts.append(blob_pos + Vector2.from_angle(va) * blob_r * noise_r)
            blobs.append({"verts": verts, "color": blob_col})

        var wisp_count = randi_range(2, 5)
        for wi in wisp_count:
            var wa = randf() * TAU
            var wdir = Vector2.from_angle(wa)
            var wlen = r * randf_range(0.6, 1.2)
            var wwidth = maxf(r * randf_range(0.04, 0.1), 2.0)
            var wcol = core_col.lerp(edge_col, 0.6)
            wcol.a = randf_range(0.006, 0.015)

            var wverts = PackedVector2Array()
            var wsegs = randi_range(8, 14)
            var perp = Vector2( - wdir.y, wdir.x)
            var min_taper = wwidth * 0.08

            for ws in wsegs + 1:
                var wt = float(ws) / float(wsegs)
                var along = wdir * wlen * wt
                var wave = sin(wt * PI * 2.0 + float(wi) * 3.1) * wwidth * 0.5
                var taper = maxf(sin(wt * PI) * wwidth, min_taper)
                wverts.append(along + perp * (taper + wave))

            for ws in range(wsegs, -1, -1):
                var wt = float(ws) / float(wsegs)
                var along = wdir * wlen * wt
                var wave = sin(wt * PI * 2.0 + float(wi) * 3.1 + 1.0) * wwidth * 0.5
                var taper = maxf(sin(wt * PI) * wwidth, min_taper)
                wverts.append(along - perp * (taper + wave))
            blobs.append({"verts": wverts, "color": wcol})

        var valid_blobs: Array = []
        for b in blobs:
            if b.verts.size() < 3:
                continue
            if Geometry2D.triangulate_polygon(b.verts).is_empty():
                continue
            valid_blobs.append(b)
        nebula_clouds.append({"offset": cloud_offset, "blobs": valid_blobs})


    for i in randi_range(4, 8):
        var start = Vector2(randf_range( - sfr * 0.8, sfr * 0.8), randf_range( - sfr * 0.8, sfr * 0.8))
        var angle = randf() * TAU
        var length = randf_range(600, 1500)
        var fcol = nebula_themes.pick_random()[0]
        fcol.a = randf_range(0.008, 0.02)
        var segments: int = randi_range(6, 12)
        var points: Array = []
        for si in segments + 1:
            var t = float(si) / float(segments)
            var base = start + Vector2.from_angle(angle) * length * t

            var wave = sin(t * PI * 2.5 + float(i) * 1.7) * randf_range(30, 80)
            var perp = Vector2.from_angle(angle + PI * 0.5) * wave
            points.append(base + perp)
        gas_filaments.append({
            "points": points,
            "color": fcol,
            "width": randf_range(15, 50),
        })


    for i in 150:
        var dcol: Color
        if randf() < 0.3:

            dcol = Color(0.85, 0.7, 0.5)
        elif randf() < 0.5:

            dcol = Color(0.6, 0.65, 0.85)
        else:
            dcol = Color(0.75, 0.75, 0.8)
        dust_motes.append({
            "offset": Vector2(randf_range( - sfr, sfr), randf_range( - sfr, sfr)),
            "drift": Vector2(randf_range(-3, 3), randf_range(-3, 3)),
            "size": randf_range(0.3, 1.8),
            "alpha": randf_range(0.03, 0.1),
            "color": dcol,
        })


    for i in randi_range(2, 4):
        var gcol = Color(randf_range(0.5, 0.8), randf_range(0.5, 0.8), randf_range(0.7, 1.0))
        gcol.a = randf_range(0.01, 0.02)
        var gr = randf_range(40, 90)
        var tilt = randf() * PI
        var gblobs: Array = []

        for gi in randi_range(5, 8):
            var gd = gr * randf() * randf() * 0.6
            var ga = randf() * TAU
            var gpos = Vector2.from_angle(ga) * gd
            var gbr = gr * randf_range(0.15, 0.4)
            var gverts = PackedVector2Array()
            var gnv = randi_range(8, 12)
            for vi in gnv:
                var va = float(vi) / float(gnv) * TAU
                var nr = 1.0 + sin(va * 3.0 + float(gi)) * 0.2

                var pt = Vector2.from_angle(va) * gbr * nr
                pt.y *= 0.5

                var rx = pt.x * cos(tilt) - pt.y * sin(tilt)
                var ry = pt.x * sin(tilt) + pt.y * cos(tilt)
                gverts.append(gpos + Vector2(rx, ry))
            gblobs.append({"verts": gverts, "color": Color(gcol, gcol.a * (1.0 - gd / gr))})

        var valid_gblobs: Array = []
        for b in gblobs:
            if b.verts.size() < 3:
                continue
            if Geometry2D.triangulate_polygon(b.verts).is_empty():
                continue
            valid_gblobs.append(b)
        distant_galaxies.append({
            "offset": Vector2(randf_range( - sfr * 0.7, sfr * 0.7), randf_range( - sfr * 0.7, sfr * 0.7)),
            "blobs": valid_gblobs,
        })


func bake_bg_texture() -> void:
    var field = star_field_radius * 2.0
    var tex_size: int = 4096
    var scale_factor: float = float(tex_size) / field

    var vp = SubViewport.new()
    vp.size = Vector2i(tex_size, tex_size)
    vp.transparent_bg = true
    vp.render_target_update_mode = SubViewport.UPDATE_ONCE
    vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE

    var baker = _BgBaker.new()
    baker.renderer_ref = self
    baker.position = Vector2(tex_size * 0.5, tex_size * 0.5)
    baker.scale = Vector2(scale_factor, scale_factor)
    vp.add_child(baker)
    add_child(vp)

    await RenderingServer.frame_post_draw

    var img = vp.get_texture().get_image()
    _bg_texture = ImageTexture.create_from_image(img)
    vp.queue_free()
    _bg_dirty = true


func _draw_bg_bake(n: Node2D):
    for gal in distant_galaxies:
        n.draw_set_transform(gal.offset)
        for blob in gal.blobs:
            n.draw_colored_polygon(blob.verts, blob.color)
        n.draw_set_transform(Vector2.ZERO)

    for fil in gas_filaments:
        var pts: Array = fil.points
        var fc: Color = fil.color
        var fw: float = fil.width
        for pi in pts.size() - 1:
            var p0 = pts[pi]
            var p1 = pts[pi + 1]
            var seg_t = float(pi) / float(pts.size() - 1)
            var taper = sin(seg_t * PI) * fw
            n.draw_line(p0, p1, Color(fc, fc.a * sin(seg_t * PI)), maxf(taper, 1.0))

    for cloud in nebula_clouds:
        n.draw_set_transform(cloud.offset)
        for blob in cloud.blobs:
            n.draw_colored_polygon(blob.verts, blob.color)
        n.draw_set_transform(Vector2.ZERO)

    for mote in dust_motes:
        n.draw_circle(mote.offset, mote.size, Color(mote.color, mote.alpha * 0.7))

    for star in stars:
        var sc: Color = star.color
        var sz: float = star.size
        if star.size > 1.3:
            n.draw_circle(star.offset, sz * 3.0, Color(sc, sc.a * 0.04))
            n.draw_circle(star.offset, sz * 2.0, Color(sc, sc.a * 0.1))
        n.draw_circle(star.offset, sz, sc)
        if sz > 0.8:
            n.draw_circle(star.offset, sz * 0.5, Color(sc.lerp(Color.WHITE, 0.6), sc.a * 0.9))
        if sz > 1.5:
            n.draw_circle(star.offset, sz * 0.25, Color(1.0, 1.0, 1.0, sc.a * 0.7))
        if star.size > 1.8:
            var spike_a = sc.a * 0.5
            var spike_len = sz * 4.0
            n.draw_line(star.offset + Vector2(-spike_len, 0), star.offset + Vector2(spike_len, 0), Color(sc, spike_a), 0.8)
            n.draw_line(star.offset + Vector2(0, -spike_len), star.offset + Vector2(0, spike_len), Color(sc, spike_a), 0.8)
            n.draw_line(star.offset + Vector2(-spike_len * 0.7, 0), star.offset + Vector2(spike_len * 0.7, 0), Color(sc, spike_a * 0.3), 2.5)
            n.draw_line(star.offset + Vector2(0, -spike_len * 0.7), star.offset + Vector2(0, spike_len * 0.7), Color(sc, spike_a * 0.3), 2.5)
            if star.size > 2.2:
                var dlen = spike_len * 0.6
                n.draw_line(star.offset + Vector2(-dlen, -dlen), star.offset + Vector2(dlen, dlen), Color(sc, spike_a * 0.4), 0.6)
                n.draw_line(star.offset + Vector2(dlen, -dlen), star.offset + Vector2(-dlen, dlen), Color(sc, spike_a * 0.4), 0.6)
        if star.size > 2.5:
            n.draw_circle(star.offset, sz * 5.0, Color(sc, sc.a * 0.025))
            n.draw_circle(star.offset, sz * 3.5, Color(sc, sc.a * 0.05))


# Called by the child _BgLayer's _draw(). Reads owner_main for game state.
func _draw_bg_on_layer(n: Node2D):
    if owner_main == null:
        return
    if owner_main.on_surface or owner_main.menu_open:
        return
    var player: Node2D = owner_main.player
    var loaded_system: String = owner_main.loaded_system
    var system_world_positions: Dictionary = owner_main.system_world_positions
    var camera_zoom: float = owner_main.camera_zoom

    var time = Time.get_ticks_msec() * 0.001
    var cam_center = player.global_position if player else Vector2.ZERO

    # Per-system background image (if the current system has one configured).
    # Drawn first so the procedural nebulae/stars/galaxies layer on top.
    _draw_system_bg(n, cam_center, loaded_system, camera_zoom)

    # Baked background texture — replaces ~2000 individual star/nebula/galaxy draw calls
    if _bg_texture:
        var field = star_field_radius * 2.0
        var sfr = star_field_radius
        var base_x = floor((cam_center.x + sfr) / field) * field - sfr
        var base_y = floor((cam_center.y + sfr) / field) * field - sfr
        for tx in range(-1, 2):
            for ty in range(-1, 2):
                var origin = Vector2(base_x + float(tx) * field, base_y + float(ty) * field)
                var tile_center = origin + Vector2(sfr, sfr)
                if tile_center.distance_to(cam_center) > sfr + 4000.0:
                    continue
                n.draw_texture_rect(_bg_texture, Rect2(origin, Vector2(field, field)), false)

    # Star gradient near system star
    if player:
        var nearest_star = system_world_positions.get(loaded_system, Vector2.ZERO)
        var sys = DataManager.systems.get(loaded_system, {})
        var sc_arr = sys.get("star_color", [1.0, 1.0, 0.8])
        var tint = Color(sc_arr[0], sc_arr[1], sc_arr[2])
        var star_dist = player.global_position.distance_to(nearest_star)
        var gradient_strength = clampf(1.0 - star_dist / 8000.0, 0, 1) * 0.025
        if gradient_strength > 0.001:
            for gi in 8:
                var gt = float(gi) / 8.0
                var gr = 6000.0 * (1.0 - gt * 0.6)
                var ga = gradient_strength * (1.0 - gt) * (1.0 - gt)
                n.draw_arc(nearest_star, gr, 0, TAU, 16, Color(tint, ga), gr * 0.15)

    # System stars — always live (animated corona/pulse)
    for sys_id in system_world_positions:
        var star_pos = system_world_positions[sys_id]
        var dist_to_cam = star_pos.distance_to(cam_center)
        if dist_to_cam < 25000.0:
            _draw_system_star_on(n, time, sys_id, star_pos, dist_to_cam)


func _load_star_spritesheet():
    _star_spritesheet = load("res://Space/art/vfx/YellowWhiteOrangeBlueStar.png")
    if _star_spritesheet == null:
        push_warning("Star spritesheet not found at res://Space/art/vfx/YellowWhiteOrangeBlueStar.png")
        return
    var fw: float = _star_spritesheet.get_width() / float(STAR_SPRITE_COLS)
    var fh: float = _star_spritesheet.get_height() / float(STAR_SPRITE_ROWS)
    for row in STAR_SPRITE_ROWS:
        for col in STAR_SPRITE_COLS:
            _star_frame_rects.append(Rect2(col * fw, row * fh, fw, fh))


func _get_or_init_star_anim(sys_id: String) -> Dictionary:
    if _star_anim_states.has(sys_id):
        return _star_anim_states[sys_id]
    var st = {
        "frame": randi_range(0, STAR_SPRITE_FRAMES - 1),
        "dir": 1 if randf() > 0.5 else -1,
        "turn_at": 0,
        "accum": randf() * STAR_ANIM_SPD,
        "speed": STAR_ANIM_SPD * (0.8 + randf() * 0.4),
    }
    if st.dir > 0:
        st.turn_at = randi_range(mini(st.frame + 8, STAR_SPRITE_FRAMES - 1), STAR_SPRITE_FRAMES - 1)
    else:
        st.turn_at = randi_range(0, maxi(st.frame - 8, 0))
    _star_anim_states[sys_id] = st
    return st


func _advance_star_anims(delta: float):
    var any_changed: bool = false
    for sys_id in _star_anim_states:
        var st = _star_anim_states[sys_id]
        var old_frame = st.frame
        st.accum += delta
        while st.accum >= st.speed:
            st.accum -= st.speed
            st.frame += st.dir
            if st.frame == st.turn_at or st.frame <= 0 or st.frame >= STAR_SPRITE_FRAMES - 1:
                st.frame = clampi(st.frame, 0, STAR_SPRITE_FRAMES - 1)
                st.dir = -st.dir
                if st.dir > 0:
                    st.turn_at = randi_range(mini(st.frame + 8, STAR_SPRITE_FRAMES - 1), STAR_SPRITE_FRAMES - 1)
                else:
                    st.turn_at = randi_range(0, maxi(st.frame - 8, 0))
        if st.frame != old_frame:
            any_changed = true
    for sys_id in DataManager.systems:
        var sys = DataManager.systems[sys_id]
        if str(sys.get("star_sprite", "")).strip_edges().is_empty():
            continue
        if int(sys.get("star_anim_frames", 1)) > 1 and float(sys.get("star_anim_fps", 0.0)) > 0.0:
            any_changed = true
            break
    if any_changed and _star_sprite_layer:
        _star_sprite_layer.queue_redraw()


func _draw_star_sprites(n: Node2D):
    if _star_spritesheet == null or _star_frame_rects.is_empty():
        return
    if owner_main == null:
        return
    if owner_main.on_surface or owner_main.menu_open:
        return
    var system_world_positions: Dictionary = owner_main.system_world_positions
    var player: Node2D = owner_main.player
    var cam_center = player.global_position if player and is_instance_valid(player) else _bg_cam_pos
    for sys_id in system_world_positions:
        var star_pos = system_world_positions[sys_id]
        var dist_to_cam = star_pos.distance_to(cam_center)
        if dist_to_cam > 25000.0:
            continue
        var sys = DataManager.systems.get(sys_id, {})
        var base_r: float = sys.get("star_size", 60)
        var star_r: float = base_r * 20.0
        # Custom star sprite override
        var custom_path: String = sys.get("star_sprite", "")
        if custom_path != "":
            var custom_tex: Texture2D = _get_custom_star_texture(custom_path)
            if custom_tex != null:
                var frame_count: int = maxi(int(sys.get("star_anim_frames", 1)), 1)
                var frame_w: float = custom_tex.get_width() / float(frame_count)
                var frame_idx: int = 0
                var anim_fps: float = maxf(float(sys.get("star_anim_fps", 0.0)), 0.0)
                if frame_count > 1 and anim_fps > 0.0:
                    frame_idx = int(floor(Time.get_ticks_msec() * 0.001 * anim_fps)) % frame_count
                @warning_ignore("confusable_local_declaration")
                var src = Rect2(frame_w * float(frame_idx), 0.0, frame_w, float(custom_tex.get_height()))
                var draw_scale: float = (star_r * 2.2) / maxf(frame_w, float(custom_tex.get_height()))
                @warning_ignore("confusable_local_declaration")
                var draw_size: Vector2 = Vector2(frame_w, float(custom_tex.get_height())) * draw_scale
                @warning_ignore("confusable_local_declaration")
                var dest = Rect2(star_pos - draw_size * 0.5, draw_size)
                n.draw_texture_rect_region(custom_tex, dest, src)
                continue

        var st = _get_or_init_star_anim(sys_id)
        var src = _star_frame_rects[st.frame]
        var draw_size = star_r * 2.2
        var dest = Rect2(star_pos - Vector2(draw_size, draw_size) * 0.5, Vector2(draw_size, draw_size))
        n.draw_texture_rect_region(_star_spritesheet, dest, src)


func _get_custom_star_texture(path: String) -> Texture2D:
    if _custom_star_textures.has(path):
        var cached: Variant = _custom_star_textures[path]
        return cached if cached is Texture2D else null
    var tex: Texture2D = _load_texture_from_path(path)
    _custom_star_textures[path] = tex
    return tex


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


func _draw_system_star_on(n: Node2D, _time: float, sys_id: String, pos: Vector2, _cam_dist: float = 0.0):
    var sys = DataManager.systems.get(sys_id, {})
    var sc = sys.get("star_color", [1.0, 1.0, 0.8])
    var star_col = Color(sc[0], sc[1], sc[2])
    var base_r: float = sys.get("star_size", 60)
    var star_r: float = base_r * 20.0

    # Soft glow halo behind the sprite
    for gi in 4:
        var gt = float(gi) / 4.0
        var gr = star_r * (1.5 + gt * 2.5)
        var ga = (1.0 - gt) * (1.0 - gt) * 0.008
        n.draw_circle(pos, gr, Color(star_col, ga))

    # Star body is rendered by _StarSpriteLayer (additive blended spritesheet)

    # Star gravity well visualization
    var star_grav: float = sys.get("star_gravity", 0)
    if star_grav > 0:
        for ggi in 3:
            var ggt = float(ggi) / 3.0
            var ggr = star_grav * (1.0 - ggt * 0.3)
            n.draw_arc(pos, ggr, 0, TAU, 48, Color(star_col, 0.06 * (1.0 - ggt)), 2.0)

    var font = ThemeDB.fallback_font
    var sname = sys.get("name", "")
    if sname != "":
        var label_pos = pos + Vector2(-sname.length() * 5.0, star_r * 1.1 + 40)
        n.draw_string(font, label_pos, sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(star_col, 0.5))
