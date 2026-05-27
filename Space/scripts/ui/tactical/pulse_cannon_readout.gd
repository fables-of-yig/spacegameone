extends Control

# Pulse-cannon readout widget. Owns its own heat state per tokens.weapons.
# pulse_cannons: heat 0..1, +0.18 per shot, decays at 0.03 per 260ms tick
# (~0.115/sec), locked out at >= 0.95 until cool. fire_flash_ms=280.
#
# fire() is the public hook — call it on every shot fire from the player
# pipeline (or for now, from a debug timer). Emits `fired` on success and
# `overheated` when the lockout refuses a shot.

const WeaponChrome := preload("res://Space/scripts/ui/tactical/weapon_chrome.gd")

signal fired
signal overheated

const HEAT_PER_SHOT := 0.18
const HEAT_DECAY_PER_SEC := 0.03 / 0.260
const LOCKOUT_HEAT := 0.95
const FIRE_FLASH_SEC := 0.28
# Number of barrel-coil pips drawn above the bar; mirrors the prototype's
# four coil_pulse tracks staggered 40ms apart.
const COIL_COUNT := 4
const COIL_STAGGER_MS := 40

@export var key_label: String = "1"
@export var weapon_name: String = "Pulse Cannons"

var heat: float = 0.0
var firing: bool = false

var _fire_flash_timer: float = 0.0
# Timestamp of last fire(), in seconds, used by coil_pulse rendering so
# each barrel pulse lines up with the fire event that triggered it.
var _last_fire_t: float = -10.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func fire() -> bool:
    if heat > LOCKOUT_HEAT:
        overheated.emit()
        queue_redraw()
        return false
    heat = clampf(heat + HEAT_PER_SHOT, 0.0, 1.0)
    firing = true
    _fire_flash_timer = FIRE_FLASH_SEC
    _last_fire_t = Time.get_ticks_msec() / 1000.0
    fired.emit()
    queue_redraw()
    return true


func _process(delta: float) -> void:
    if heat > 0.0:
        heat = maxf(0.0, heat - HEAT_DECAY_PER_SEC * delta)
        queue_redraw()
    if firing:
        _fire_flash_timer -= delta
        if _fire_flash_timer <= 0.0:
            firing = false
            _fire_flash_timer = 0.0
        queue_redraw()


func _status_text() -> String:
    if heat > LOCKOUT_HEAT:
        return "Lockout"
    if firing:
        return "Firing"
    if heat > 0.7:
        return "Warning"
    return "Ready"


func _status_color() -> Color:
    if heat > LOCKOUT_HEAT:
        return Tokens.danger
    if heat > 0.7:
        return Tokens.warn
    if firing:
        return Tokens.hud_color
    return Tokens.ok


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return

    var pad_x := 14.0
    var pad_y := 8.0
    var header_y := pad_y
    var header_h := 26.0
    var coil_y := header_y + header_h + 6.0
    var coil_h := 14.0
    var bar_y := coil_y + coil_h + 10.0
    var bar_h := 36.0
    var status_y := size.y - pad_y

    # Header — hotkey on left, weapon name on right, baselines aligned.
    var font_size_lg := Tokens.font_size("label_lg")
    WeaponChrome.draw_hotkey_badge(self, Vector2(pad_x, header_y), key_label)
    WeaponChrome.draw_weapon_name(self, header_y + float(font_size_lg), size.x - pad_x, weapon_name)

    _draw_coil_row(pad_x, coil_y, size.x - pad_x * 2.0, coil_h)
    _draw_heat_bar(pad_x, bar_y, size.x - pad_x * 2.0, bar_h)
    WeaponChrome.draw_status_line(self, Vector2(pad_x, status_y), size.x - pad_x * 2.0, _status_text(), _status_color(), "%d%% HEAT" % int(round(heat * 100.0)))


func _draw_coil_row(x: float, y: float, w: float, h: float) -> void:
    # Four staggered coil pulses across the top of the bar. Each pip's
    # opacity ramps with `firing` and a small offset so they march
    # left→right; matches tokens.animations.coil_pulse.
    var gap := 6.0
    var pip_w := (w - gap * float(COIL_COUNT - 1)) / float(COIL_COUNT)
    var now := Time.get_ticks_msec() / 1000.0
    for i in COIL_COUNT:
        var px := x + float(i) * (pip_w + gap)
        var alpha := 0.3
        if firing:
            var stagger := float(i) * (float(COIL_STAGGER_MS) / 1000.0)
            var since := (now - _last_fire_t) - stagger
            if since >= 0.0 and since < 0.18:
                var t := since / 0.18
                alpha = lerpf(1.0, 0.3, t)
        var col := Tokens.hud_color
        col.a = alpha
        draw_rect(Rect2(px, y, pip_w, h), col, true)
        var outline := Tokens.hud_dim
        outline.a = 0.6
        draw_rect(Rect2(px, y, pip_w, h), outline, false, 1.0)


func _draw_heat_bar(x: float, y: float, w: float, h: float) -> void:
    # Background panel ink + a skewed fill that ramps with heat.
    draw_rect(Rect2(x, y, w, h), Tokens.ink, true)
    var border := Tokens.hud_dim
    border.a = 0.5
    draw_rect(Rect2(x, y, w, h), border, false, 1.0)

    var fill_w := w * clampf(heat, 0.0, 1.0)
    if fill_w > 1.0:
        var fill_col := WeaponChrome.heat_state_color(heat, LOCKOUT_HEAT)
        var pts := WeaponChrome.skew_rect(x, y, fill_w, h, -18.0)
        draw_colored_polygon(pts, fill_col)
        # Top inner highlight.
        var hi := fill_col.lerp(Color.WHITE, 0.35)
        hi.a = 0.5
        draw_line(Vector2(x, y), Vector2(x + fill_w, y), hi, 1.0)

    # Fire flash overlay — bright white veneer fading over fire_flash_sec.
    if firing and _fire_flash_timer > 0.0:
        var t := 1.0 - (_fire_flash_timer / FIRE_FLASH_SEC)
        var flash_alpha := lerpf(0.55, 0.0, t)
        var flash_col := Color(1.0, 0.94, 0.78, flash_alpha)
        draw_rect(Rect2(x, y, w, h), flash_col, true)

    # Lockout tick at 95%.
    var lockout_x := x + w * LOCKOUT_HEAT
    var lockout_col := Tokens.danger
    lockout_col.a = 0.85
    draw_line(Vector2(lockout_x, y - 2.0), Vector2(lockout_x, y + h + 2.0), lockout_col, 1.5)
