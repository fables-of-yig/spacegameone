extends Control

# Tactical minimap widget — the design's 360×360 disc with:
#   • Range rings @ 25/50/75/100% radius (outer solid, inner dashed)
#   • Vertical/horizontal dashed crosshairs
#   • 4 orbit ellipses at r=22/38/54/66 (decorative)
#   • Sweep wedge — 45°, gradient α, 5s clockwise rotation
#   • Self-triangle at center, pointed N, rotates with player heading
#   • Hostile contacts: red dot + ping ring expanding outward
#   • N/S/E/W bearing markers
#   • Footer readout: HDG · VEL · ZOOM
#
# Bind `player` from the host to drive heading / position / contact
# resolution. World positions are scaled to the minimap by `world_range`
# (game units across the visible disc).

@export var player_node: Node2D = null
@export var world_range: float = 4500.0
@export var zoom_label: String = "1×"

const SWEEP_PERIOD_SEC := 5.0
const SWEEP_WEDGE_DEG := 45.0
const PING_PERIOD_SEC := 1.6
const ORBIT_RADII := [22.0, 38.0, 54.0, 66.0]
const ENEMY_GROUP := "enemies"
# tokens.animations.drift — contact idle wobble: ~6px translate + 2°
# rotate over 4s, phase-staggered per contact.
const DRIFT_PERIOD_SEC := 4.0
const DRIFT_AMP_PX := 3.0

# Refs to enemy contacts captured each frame so ping rings can phase by
# index instead of waking on the same frame for every dot.
var _contacts: Array = []


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var pad := 12.0
    var inner_size := minf(size.x, size.y) - pad * 2.0
    if inner_size <= 0.0:
        return
    var inner_r := inner_size * 0.5
    var center := size * 0.5

    _draw_background(center, inner_r)
    _draw_orbit_ellipses(center, inner_r)
    _draw_crosshair(center, inner_r)
    _draw_range_rings(center, inner_r)
    _draw_sweep_wedge(center, inner_r)
    _draw_contacts(center, inner_r)
    _draw_self_triangle(center)
    _draw_bearings(center, inner_r)
    _draw_footer()


func _draw_background(center: Vector2, r: float) -> void:
    var fade := Tokens.hud_deep
    fade.a = 0.55
    draw_circle(center, r, fade)
    var outer_ring := Tokens.hud_dim
    outer_ring.a = 0.85
    draw_arc(center, r, 0.0, TAU, 64, outer_ring, 1.5, true)


func _draw_orbit_ellipses(center: Vector2, r: float) -> void:
    # Decorative ellipses suggesting orbital paths. Faint cyan.
    var col := Tokens.hud_color
    col.a = 0.10
    for orbit_r in ORBIT_RADII:
        var scaled := float(orbit_r) / 80.0 * r  # 80 ≈ design inner radius factor
        _draw_ellipse(center, scaled * 1.25, scaled * 0.55, col, 32)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int) -> void:
    if rx <= 0.0 or ry <= 0.0:
        return
    var pts := PackedVector2Array()
    for i in segments + 1:
        var theta := TAU * float(i) / float(segments)
        pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
    draw_polyline(pts, col, 1.0, true)


func _draw_crosshair(center: Vector2, r: float) -> void:
    var col := Tokens.hud_dim
    col.a = 0.45
    # Dashed segments — 8px on, 8px off.
    _draw_dashed_line(Vector2(center.x - r, center.y), Vector2(center.x + r, center.y), col, 8.0)
    _draw_dashed_line(Vector2(center.x, center.y - r), Vector2(center.x, center.y + r), col, 8.0)


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, dash: float) -> void:
    var dir := b - a
    var dist := dir.length()
    if dist <= 0.0:
        return
    var step := dash * 2.0
    var n := dir.normalized()
    var i := 0.0
    while i < dist:
        var seg_a := a + n * i
        var seg_b := a + n * minf(i + dash, dist)
        draw_line(seg_a, seg_b, col, 1.0)
        i += step


func _draw_range_rings(center: Vector2, r: float) -> void:
    for ring_idx in 4:
        var pct := float(ring_idx + 1) * 0.25
        var rad := r * pct
        var solid := ring_idx == 3
        var col := Tokens.hud_dim
        col.a = 0.6 if solid else 0.35
        if solid:
            draw_arc(center, rad, 0.0, TAU, 48, col, 1.0, true)
        else:
            _draw_dashed_circle(center, rad, col, 6.0)


func _draw_dashed_circle(center: Vector2, r: float, col: Color, dash_arc: float) -> void:
    var circ := TAU * r
    var n_dashes := maxi(8, int(circ / (dash_arc * 2.0)))
    var seg_arc := TAU / float(n_dashes)
    for i in n_dashes:
        if i % 2 == 0:
            var theta_a := seg_arc * float(i)
            var theta_b := seg_arc * float(i + 1)
            draw_arc(center, r, theta_a, theta_b, 6, col, 1.0, true)


func _draw_sweep_wedge(center: Vector2, r: float) -> void:
    var t := Time.get_ticks_msec() / 1000.0
    var rotation := fposmod(t / SWEEP_PERIOD_SEC, 1.0) * TAU
    var half_wedge := deg_to_rad(SWEEP_WEDGE_DEG * 0.5)
    var col := Tokens.hud_color
    # Triangle-fan wedge, fading from the leading edge.
    var fan := PackedVector2Array()
    fan.append(center)
    var steps := 24
    for i in steps + 1:
        var t_frac := float(i) / float(steps)
        var theta := rotation - half_wedge + half_wedge * 2.0 * t_frac
        fan.append(center + Vector2(cos(theta), sin(theta)) * r)
    var fill_col := col
    fill_col.a = 0.18
    draw_colored_polygon(fan, fill_col)
    # Leading edge — bright line.
    var edge_end := center + Vector2(cos(rotation + half_wedge), sin(rotation + half_wedge)) * r
    var edge_col := col
    edge_col.a = 0.65
    draw_line(center, edge_end, edge_col, 1.5)


func _draw_contacts(center: Vector2, r: float) -> void:
    _contacts.clear()
    if not is_instance_valid(player_node):
        return
    var origin: Vector2 = player_node.global_position
    var scale := r / world_range
    var enemies := get_tree().get_nodes_in_group(ENEMY_GROUP)
    var now := Time.get_ticks_msec() / 1000.0
    for e in enemies:
        if not is_instance_valid(e):
            continue
        var rel: Vector2 = (e.global_position - origin) * scale
        if rel.length() > r:
            continue
        _contacts.append({"local": rel})
        # tokens.animations.drift — phase by contact index so the row
        # of dots doesn't wobble in lockstep.
        var idx := _contacts.size()
        var drift_phase := fposmod(now / DRIFT_PERIOD_SEC + float(idx) * 0.21, 1.0)
        var drift_offset := Vector2(
            sin(drift_phase * TAU) * DRIFT_AMP_PX * 0.4,
            sin(drift_phase * TAU + PI * 0.5) * DRIFT_AMP_PX,
        )
        var dot_pos := center + rel + drift_offset
        var dot_col := Tokens.danger
        draw_circle(dot_pos, 3.0, dot_col)
        var ping_alpha_t: float = fposmod(now + float(idx) * 0.13, PING_PERIOD_SEC) / PING_PERIOD_SEC
        var ping_r := lerpf(4.0, 14.0, ping_alpha_t)
        var ping_col := Tokens.danger
        ping_col.a = lerpf(0.7, 0.0, ping_alpha_t)
        draw_arc(dot_pos, ping_r, 0.0, TAU, 24, ping_col, 1.0, true)


func _draw_self_triangle(center: Vector2) -> void:
    var heading := 0.0
    if is_instance_valid(player_node):
        heading = float(player_node.rotation)
    # Player rotation has 0 = +X; the minimap convention is 0 = N (up).
    # So forward direction = heading - PI/2 in screen coords.
    var fwd_theta := heading - PI * 0.5
    var fwd := Vector2(cos(fwd_theta), sin(fwd_theta))
    var p1 := center + fwd * 8.0
    var p2 := center + fwd.rotated(2.5) * 6.0
    var p3 := center + fwd.rotated(-2.5) * 6.0
    draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Tokens.hud_color)
    var rim := Tokens.hud_color.lerp(Color.WHITE, 0.5)
    rim.a = 0.7
    draw_line(p1, p2, rim, 1.0)
    draw_line(p1, p3, rim, 1.0)


func _draw_bearings(center: Vector2, r: float) -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var sz := Tokens.font_size("label_md")
    var col := Tokens.hud_dim
    col.a = 0.85
    var labels := [["N", Vector2(0.0, -r - 2.0)], ["E", Vector2(r + 4.0, 0.0)], ["S", Vector2(0.0, r + float(sz) + 2.0)], ["W", Vector2(-r - 14.0, 0.0)]]
    for entry in labels:
        var text: String = entry[0]
        var offset: Vector2 = entry[1]
        var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
        var draw_pos := center + offset - Vector2(text_size.x * 0.5, 0.0)
        draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw_footer() -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var sz := Tokens.font_size("tiny")
    var heading_deg := 0.0
    var vel_c := 0.0
    if is_instance_valid(player_node):
        var raw := rad_to_deg(player_node.rotation) + 90.0
        heading_deg = fposmod(raw, 360.0)
        if "velocity" in player_node:
            var v: Vector2 = player_node.velocity
            vel_c = v.length() / 800.0  # 800 ≈ "1c" — purely cosmetic
    var txt := "HDG %05.1f° · VEL %0.2fc · ZOOM %s" % [heading_deg, vel_c, zoom_label]
    var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
    var pos := Vector2((size.x - ts.x) * 0.5, size.y - 6.0)
    var col := Tokens.hud_dim
    col.a = 0.85
    draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
