extends Control

# Shield-parry readout. Dual-ring circular widget:
#   - Outer tick ring (36 ticks) rotates clockwise 0→360° over 40s
#     (tokens.animations.shield_rotate).
#   - Inner charge ring (24 segments) rotates counter-clockwise over 28s
#     (tokens.animations.shield_counter); fills with recharge.
# Center holds a procedural shield emblem (no SVG, per slice scope).
#
# State: ready bool + recharge_timer counting down from
# tokens.weapons.shield_parry.recharge_ms (2500ms default). fire() drains
# the shield when ready; recharge starts immediately.

const WeaponChrome := preload("res://Space/scripts/ui/tactical/weapon_chrome.gd")

signal fired
signal recharged

const RECHARGE_SEC := 2.5
const OUTER_TICK_COUNT := 36
const INNER_SEGMENT_COUNT := 24
const OUTER_ROTATE_SEC := 40.0
const INNER_ROTATE_SEC := 28.0
const IDLE_PULSE_SEC := 3.0

@export var key_label: String = "SPACE"
@export var weapon_name: String = "Shield Parry"

var ready_to_fire: bool = true
var recharge_timer: float = 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func fire() -> bool:
    if not ready_to_fire:
        return false
    ready_to_fire = false
    recharge_timer = RECHARGE_SEC
    fired.emit()
    queue_redraw()
    return true


func _process(delta: float) -> void:
    if not ready_to_fire:
        recharge_timer = maxf(0.0, recharge_timer - delta)
        if recharge_timer <= 0.0:
            ready_to_fire = true
            recharged.emit()
    queue_redraw()  # rings rotate continuously, idle pulse breathes


func _charge_pct() -> float:
    if ready_to_fire:
        return 1.0
    return 1.0 - clampf(recharge_timer / RECHARGE_SEC, 0.0, 1.0)


func _status_text() -> String:
    if ready_to_fire:
        return "Ready"
    return "Recharging %.1fs" % recharge_timer


func _status_color() -> Color:
    return Tokens.ok if ready_to_fire else Tokens.hud_dim


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return

    var pad_x := 14.0
    var pad_y := 8.0
    var hotkey_size := Tokens.font_size("label_lg")
    var header_y := pad_y
    var status_y := size.y - pad_y

    WeaponChrome.draw_hotkey_badge(self, Vector2(pad_x, header_y), key_label)
    WeaponChrome.draw_weapon_name(self, header_y + float(hotkey_size), size.x - pad_x, weapon_name)

    var ring_top := header_y + float(hotkey_size) + 14.0
    var ring_bottom := status_y - 20.0
    var ring_h := ring_bottom - ring_top
    var ring_size := minf(ring_h, size.x - pad_x * 2.0)
    var center := Vector2(size.x * 0.5, ring_top + ring_h * 0.5)
    var outer_r := ring_size * 0.5
    if outer_r > 8.0:
        _draw_outer_tick_ring(center, outer_r)
        _draw_inner_charge_ring(center, outer_r * 0.72)
        _draw_shield_emblem(center, outer_r * 0.42)

    WeaponChrome.draw_status_line(self, Vector2(pad_x, status_y), size.x - pad_x * 2.0, _status_text(), _status_color())


func _draw_outer_tick_ring(center: Vector2, r: float) -> void:
    var t := Time.get_ticks_msec() / 1000.0
    var rotation := fposmod(t / OUTER_ROTATE_SEC, 1.0) * TAU
    var tick_inner := r - 6.0
    var tick_outer := r
    var col := Tokens.hud_dim
    col.a = 0.7
    for i in OUTER_TICK_COUNT:
        var theta := rotation + (TAU * float(i) / float(OUTER_TICK_COUNT))
        var sn := sin(theta)
        var cs := cos(theta)
        var a := center + Vector2(cs * tick_inner, sn * tick_inner)
        var b := center + Vector2(cs * tick_outer, sn * tick_outer)
        draw_line(a, b, col, 1.0)


func _draw_inner_charge_ring(center: Vector2, r: float) -> void:
    var t := Time.get_ticks_msec() / 1000.0
    var rotation := -fposmod(t / INNER_ROTATE_SEC, 1.0) * TAU
    var seg_arc := TAU / float(INNER_SEGMENT_COUNT)
    var gap_arc := seg_arc * 0.18
    var filled_count := int(round(_charge_pct() * float(INNER_SEGMENT_COUNT)))
    var ring_thickness := 6.0
    var idle_pulse := 1.0
    if ready_to_fire:
        var phase := fposmod(t, IDLE_PULSE_SEC) / IDLE_PULSE_SEC
        idle_pulse = 0.7 + sin(phase * TAU) * 0.3
    var lit_col := Tokens.hud_color
    lit_col.a = clampf(0.85 * idle_pulse, 0.0, 1.0)
    var off_col := Tokens.hud_dim
    off_col.a = 0.25
    for i in INNER_SEGMENT_COUNT:
        var theta_start := rotation + seg_arc * float(i) + gap_arc * 0.5
        var theta_end := rotation + seg_arc * float(i + 1) - gap_arc * 0.5
        var col := lit_col if i < filled_count else off_col
        draw_arc(center, r, theta_start, theta_end, 6, col, ring_thickness, true)


func _draw_shield_emblem(center: Vector2, r: float) -> void:
    # Stylized 5-vertex shield: pointed bottom, two arched shoulders.
    var pts := PackedVector2Array([
        Vector2(center.x, center.y - r),
        Vector2(center.x + r * 0.78, center.y - r * 0.35),
        Vector2(center.x + r * 0.55, center.y + r * 0.75),
        Vector2(center.x - r * 0.55, center.y + r * 0.75),
        Vector2(center.x - r * 0.78, center.y - r * 0.35),
    ])
    var fill := Tokens.hud_deep
    fill.a = 0.8 if ready_to_fire else 0.4
    draw_colored_polygon(pts, fill)
    var border_pts := pts.duplicate()
    border_pts.append(pts[0])
    var ring_col := Tokens.hud_color if ready_to_fire else Tokens.hud_dim
    ring_col.a = 0.9 if ready_to_fire else 0.5
    draw_polyline(border_pts, ring_col, 2.0, true)
    # Center cross-stroke — vertical divider.
    var top := Vector2(center.x, center.y - r * 0.85)
    var bot := Vector2(center.x, center.y + r * 0.7)
    var div_col := Tokens.hud_dim
    div_col.a = 0.5
    draw_line(top, bot, div_col, 1.0)
