extends Control

# Segmented-bar widget from the SCS Meridian HUD design. Draws a row of
# skewed parallelogram segments where the first `fill * segments` are
# lit in the threshold state color (danger/warn/ok) and the rest in a
# darkened "off" version of the same.
#
# Settings come from Tokens.bars_config() so segment count / skew / gap
# stay in sync with tokens.json `bars`.

const DEFAULT_SEGMENTS := 36
const DEFAULT_SKEW_DEG := -18.0
const DEFAULT_GAP := 3.0

@export_range(0.0, 1.0, 0.001) var fill: float = 1.0:
    set(value):
        fill = clampf(value, 0.0, 1.0)
        queue_redraw()

@export var label: String = ""
@export var show_percent: bool = true


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func _process(_delta: float) -> void:
    # The danger pulse needs a continuous redraw while fill is in the
    # danger band; cheaper than running an AnimationPlayer for one line.
    if _is_in_danger():
        queue_redraw()


func _is_in_danger() -> bool:
    var thresholds := _thresholds()
    return fill * 100.0 < thresholds.x


func _thresholds() -> Vector2:
    var cfg := Tokens.bars_config()
    var th_v: Variant = cfg.get("fill_thresholds", {})
    var danger_below := 30.0
    var warn_below := 60.0
    if typeof(th_v) == TYPE_DICTIONARY:
        danger_below = float((th_v as Dictionary).get("danger_below", 30.0))
        warn_below = float((th_v as Dictionary).get("warn_below", 60.0))
    return Vector2(danger_below, warn_below)


func _segments_count() -> int:
    var cfg := Tokens.bars_config()
    return int(cfg.get("segments_per_bar", DEFAULT_SEGMENTS))


func _skew_deg() -> float:
    var cfg := Tokens.bars_config()
    return float(cfg.get("segment_skew_deg", DEFAULT_SKEW_DEG))


func _gap_px() -> float:
    var cfg := Tokens.bars_config()
    return float(cfg.get("segment_gap", DEFAULT_GAP))


func _danger_pulse_alpha() -> float:
    var cfg := Tokens.bars_config()
    var period := float(cfg.get("danger_pulse_seconds", 0.8))
    if period <= 0.0:
        return 1.0
    var t := Time.get_ticks_msec() / 1000.0
    var phase := fposmod(t, period) / period
    # 1.0 → 0.55 → 1.0, matches tokens.animations.danger_pulse
    return lerpf(0.55, 1.0, abs(phase - 0.5) * 2.0)


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return

    var w := size.x
    var h := size.y
    var segments := _segments_count()
    var gap := _gap_px()
    var skew := _skew_deg()

    var seg_w := (w - gap * float(segments - 1)) / float(segments)
    if seg_w <= 0.0:
        return

    var filled := roundi(fill * float(segments))
    var state_col := _state_color()
    var off_col := state_col.darkened(0.85)
    off_col.a = 0.65

    var pulse_a := _danger_pulse_alpha() if _is_in_danger() else 1.0

    for i in segments:
        var x := float(i) * (seg_w + gap)
        var pts := _skew_rect(x, 0.0, seg_w, h, skew)
        var lit := i < filled
        var col := state_col if lit else off_col
        if lit:
            col.a = clampf(col.a * pulse_a, 0.0, 1.0)
        draw_colored_polygon(pts, col)

    if not label.is_empty() or show_percent:
        _draw_label()


func _state_color() -> Color:
    var th := _thresholds()
    var pct := fill * 100.0
    if pct < th.x:
        return Tokens.danger
    elif pct < th.y:
        return Tokens.warn
    return Tokens.ok


func _skew_rect(x: float, y: float, w: float, h: float, deg: float) -> PackedVector2Array:
    # Shear the top edge of the rect by `deg` degrees relative to the
    # bottom edge — matches CSS `transform: skewX(deg)` on a row.
    var dx := h * tan(deg_to_rad(deg))
    return PackedVector2Array([
        Vector2(x + dx, y),
        Vector2(x + w + dx, y),
        Vector2(x + w, y + h),
        Vector2(x, y + h),
    ])


func _draw_label() -> void:
    var font: Font = Tokens.font if Tokens.font != null else ThemeDB.fallback_font
    var label_sz := Tokens.font_size("sublabel")
    if not label.is_empty():
        draw_string(font, Vector2(0.0, -4.0), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, label_sz, Tokens.hud_dim)
    if show_percent:
        var pct_text := "%d%%" % int(round(fill * 100.0))
        var pct_size := font.get_string_size(pct_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_sz)
        draw_string(font, Vector2(size.x - pct_size.x, -4.0), pct_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_sz, _state_color())
