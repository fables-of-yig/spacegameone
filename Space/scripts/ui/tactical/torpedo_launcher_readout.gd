extends Control

# Torpedo-launcher readout. Tracks an int ammo count (0..ammo_max, per
# tokens.weapons.torpedoes), animates a fire flash + flight countdown
# after each fire(). No auto-reload in this slice — ammo is set by the
# owner (or by a debug poke) via `ammo` property.

const WeaponChrome := preload("res://Space/scripts/ui/tactical/weapon_chrome.gd")

signal fired(remaining_ammo: int)
signal exploded
signal dry_fire

const FIRE_FLASH_SEC := 0.6
const FLIGHT_SEC := 1.1

@export var key_label: String = "3"
@export var weapon_name: String = "Torpedoes"
@export var ammo_max: int = 6
@export var ammo: int = 4:
    set(value):
        ammo = clampi(value, 0, ammo_max)
        queue_redraw()

var _fire_flash_timer: float = 0.0
var _flight_timer: float = 0.0
# Index of the pip currently flashing during fire flash, so the visual
# matches the one that was just consumed. -1 when no flash is active.
var _flashing_pip_idx: int = -1


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func fire() -> bool:
    if ammo <= 0:
        dry_fire.emit()
        queue_redraw()
        return false
    _flashing_pip_idx = ammo - 1  # the pip about to empty
    ammo -= 1
    _fire_flash_timer = FIRE_FLASH_SEC
    _flight_timer = FLIGHT_SEC
    fired.emit(ammo)
    queue_redraw()
    return true


func _process(delta: float) -> void:
    var dirty := false
    if _fire_flash_timer > 0.0:
        _fire_flash_timer -= delta
        if _fire_flash_timer <= 0.0:
            _fire_flash_timer = 0.0
            _flashing_pip_idx = -1
        dirty = true
    if _flight_timer > 0.0:
        _flight_timer -= delta
        if _flight_timer <= 0.0:
            _flight_timer = 0.0
            exploded.emit()
        dirty = true
    if dirty:
        queue_redraw()


func _status_text() -> String:
    if _flight_timer > 0.0:
        return "In-Flight"
    if ammo <= 0:
        return "Empty"
    if _fire_flash_timer > 0.0:
        return "Firing"
    return "Ready"


func _status_color() -> Color:
    if ammo <= 0:
        return Tokens.danger
    if _flight_timer > 0.0:
        return Tokens.warn
    return Tokens.ok


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

    var pips_top := header_y + float(hotkey_size) + 16.0
    var pips_bottom := status_y - 28.0
    var pips_h := pips_bottom - pips_top
    if pips_h > 24.0:
        _draw_ammo_pips(pad_x, pips_top, size.x - pad_x * 2.0, pips_h)

    if _flight_timer > 0.0:
        var fl_y := status_y - 18.0
        _draw_flight_bar(pad_x, fl_y, size.x - pad_x * 2.0, 4.0)

    var status_value := "%d / %d" % [ammo, ammo_max]
    WeaponChrome.draw_status_line(self, Vector2(pad_x, status_y), size.x - pad_x * 2.0, _status_text(), _status_color(), status_value)


func _draw_ammo_pips(x: float, y: float, w: float, h: float) -> void:
    # Horizontal row of torpedo-shaped pips: rounded rect with a
    # pointed nose. Drawn loaded → empty left to right so the visual
    # order matches "next to fire is leftmost".
    if ammo_max <= 0:
        return
    var gap := 8.0
    var pip_w := (w - gap * float(ammo_max - 1)) / float(ammo_max)
    var pip_h := minf(h, 26.0)
    var center_y := y + (h - pip_h) * 0.5

    for i in ammo_max:
        var px := x + float(i) * (pip_w + gap)
        var loaded := i < ammo
        var pip_rect := Rect2(px, center_y, pip_w, pip_h)
        _draw_torpedo_pip(pip_rect, loaded, i == _flashing_pip_idx)


func _draw_torpedo_pip(rect: Rect2, loaded: bool, flashing: bool) -> void:
    var nose_len := 10.0
    var body_right := rect.position.x + rect.size.x - nose_len
    var pts := PackedVector2Array([
        Vector2(rect.position.x, rect.position.y),
        Vector2(body_right, rect.position.y),
        Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5),
        Vector2(body_right, rect.position.y + rect.size.y),
        Vector2(rect.position.x, rect.position.y + rect.size.y),
    ])

    var fill: Color
    if loaded:
        fill = Tokens.hud_color
        fill.a = 0.75
    else:
        fill = Tokens.hud_dim
        fill.a = 0.18
    draw_colored_polygon(pts, fill)

    var outline := Tokens.hud_dim
    outline.a = 0.75
    var border_pts := pts.duplicate()
    border_pts.append(pts[0])
    draw_polyline(border_pts, outline, 1.0, true)

    if flashing and _fire_flash_timer > 0.0:
        var t := 1.0 - (_fire_flash_timer / FIRE_FLASH_SEC)
        var flash_alpha := lerpf(0.8, 0.0, t)
        var flash := Color(1.0, 0.85, 0.45, flash_alpha)
        draw_colored_polygon(pts, flash)


func _draw_flight_bar(x: float, y: float, w: float, h: float) -> void:
    draw_rect(Rect2(x, y, w, h), Tokens.ink, true)
    var border := Tokens.hud_dim
    border.a = 0.4
    draw_rect(Rect2(x, y, w, h), border, false, 1.0)
    var t := 1.0 - clampf(_flight_timer / FLIGHT_SEC, 0.0, 1.0)
    var fill_w := w * t
    var col := Tokens.warn
    col.a = 0.9
    draw_rect(Rect2(x, y, fill_w, h), col, true)
