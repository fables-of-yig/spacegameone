extends Control

# Gauss-battery readout — heat-based shared bar plus a row of mount pips
# (count from tokens.weapons.gauss_battery.mount_count_default, range
# 3..8). fire() advances a round-robin mount index so the pip row
# flickers through at the simulated 1420 RPM.

const WeaponChrome := preload("res://Space/scripts/ui/tactical/weapon_chrome.gd")

signal fired(mount_idx: int)
signal overheated

const HEAT_PER_SHOT := 0.12
const HEAT_DECAY_PER_SEC := 0.04 / 0.260
const LOCKOUT_HEAT := 0.95
const FIRE_FLASH_SEC := 0.18
const MOUNT_FLASH_SEC := 0.12

@export var key_label: String = "2"
@export var weapon_name: String = "Gauss Battery"
@export_range(3, 8) var mount_count: int = 8

var heat: float = 0.0
var firing: bool = false

var _fire_flash_timer: float = 0.0
var _mount_flash_times: Array[float] = []  # secs remaining per mount
var _next_mount_idx: int = 0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _resize_mount_state()
    set_process(true)


func _resize_mount_state() -> void:
    _mount_flash_times.resize(mount_count)
    _mount_flash_times.fill(0.0)


func fire() -> bool:
    if heat > LOCKOUT_HEAT:
        overheated.emit()
        queue_redraw()
        return false
    heat = clampf(heat + HEAT_PER_SHOT, 0.0, 1.0)
    firing = true
    _fire_flash_timer = FIRE_FLASH_SEC
    var idx := _next_mount_idx
    if _mount_flash_times.size() != mount_count:
        _resize_mount_state()
    _mount_flash_times[idx] = MOUNT_FLASH_SEC
    _next_mount_idx = (idx + 1) % mount_count
    fired.emit(idx)
    queue_redraw()
    return true


func _process(delta: float) -> void:
    var dirty := false
    if heat > 0.0:
        heat = maxf(0.0, heat - HEAT_DECAY_PER_SEC * delta)
        dirty = true
    if firing:
        _fire_flash_timer -= delta
        if _fire_flash_timer <= 0.0:
            firing = false
            _fire_flash_timer = 0.0
        dirty = true
    for i in _mount_flash_times.size():
        if _mount_flash_times[i] > 0.0:
            _mount_flash_times[i] = maxf(0.0, _mount_flash_times[i] - delta)
            dirty = true
    if dirty:
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
    return Tokens.ok


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return

    var pad_x := 14.0
    var pad_y := 6.0
    var hdr_size := Tokens.font_size("label_md")
    var hotkey_size := Tokens.font_size("label_lg")
    var hdr_baseline := pad_y + float(hotkey_size)

    # Left cluster: hotkey + tight weapon name (single line).
    WeaponChrome.draw_hotkey_badge(self, Vector2(pad_x, pad_y), key_label)
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var name_x := pad_x + 42.0
    draw_string(font, Vector2(name_x, hdr_baseline), weapon_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, hdr_size, Tokens.hud_dim)

    # Right cluster: mount pips.
    var pip_r := 5.0
    var pip_gap := 9.0
    var pip_row_w := float(mount_count) * (pip_r * 2.0) + float(mount_count - 1) * pip_gap
    var pip_origin := Vector2(size.x - pad_x - pip_row_w, size.y * 0.5)
    _draw_mount_pips(pip_origin, pip_r, pip_gap)

    # Middle: heat bar between header right and pips.
    var bar_x := name_x + font.get_string_size(weapon_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, hdr_size).x + 18.0
    var bar_right := size.x - pad_x - pip_row_w - 18.0
    var bar_w := bar_right - bar_x
    if bar_w > 40.0:
        var bar_h := 16.0
        var bar_y := size.y * 0.5 - bar_h * 0.5
        _draw_heat_bar(bar_x, bar_y, bar_w, bar_h)

    # Status sublabel beneath the name, opposite the bar.
    var status_y := size.y - pad_y
    var status_text := "%s — %d%% HEAT" % [_status_text().to_upper(), int(round(heat * 100.0))]
    draw_string(font, Vector2(pad_x, status_y), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.font_size("sublabel"), _status_color())


func _draw_mount_pips(origin: Vector2, r: float, gap: float) -> void:
    for i in mount_count:
        var px := origin.x + float(i) * (r * 2.0 + gap) + r
        var py := origin.y
        var flash := _mount_flash_times[i] / MOUNT_FLASH_SEC if i < _mount_flash_times.size() else 0.0
        var base_a := 0.25 + clampf(flash, 0.0, 1.0) * 0.75
        var col: Color = Tokens.hud_color
        col.a = base_a
        draw_circle(Vector2(px, py), r, col)
        var ring: Color = Tokens.hud_dim
        ring.a = 0.65
        draw_arc(Vector2(px, py), r + 1.5, 0.0, TAU, 16, ring, 1.0)


func _draw_heat_bar(x: float, y: float, w: float, h: float) -> void:
    draw_rect(Rect2(x, y, w, h), Tokens.ink, true)
    var border := Tokens.hud_dim
    border.a = 0.5
    draw_rect(Rect2(x, y, w, h), border, false, 1.0)
    var fill_w := w * clampf(heat, 0.0, 1.0)
    if fill_w > 1.0:
        var pts := WeaponChrome.skew_rect(x, y, fill_w, h, -18.0)
        draw_colored_polygon(pts, WeaponChrome.heat_state_color(heat, LOCKOUT_HEAT))
    if firing and _fire_flash_timer > 0.0:
        var t := 1.0 - (_fire_flash_timer / FIRE_FLASH_SEC)
        var flash_col := Color(1.0, 0.94, 0.78, lerpf(0.55, 0.0, t))
        draw_rect(Rect2(x, y, w, h), flash_col, true)
    var lockout_x := x + w * LOCKOUT_HEAT
    var lockout_col := Tokens.danger
    lockout_col.a = 0.85
    draw_line(Vector2(lockout_x, y - 2.0), Vector2(lockout_x, y + h + 2.0), lockout_col, 1.5)
