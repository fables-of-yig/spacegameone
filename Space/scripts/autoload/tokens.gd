extends Node

# Design tokens for the Space tactical HUD. Source of truth is the SCS
# Meridian design package at `Space/art/ui/tactical_hud/tokens.json`.
#
# `hud_color`/`hud_dim`/`hud_deep` are derived from a single hue so the
# accent can be re-tinted by calling `apply_hue(degrees)`. State colors
# (warn/danger/ok) stay fixed regardless of hue.
#
# Sprite tinting strategy
# -----------------------
# The design package ships SVGs where every accent element is in a
# `.tint` class (baked at #5cf2ff for preview) and chassis art is in a
# `.chassis` class. Three approaches:
#   A) Pre-render variants (one SVG per hue)
#   B) Runtime modulate (only safe on single-color sprites)
#   C) Hue-shift shader on `.tint` pixels only
#
# Current usage only needs the reticle, which is solid accent — so B
# is in effect (see tactical_hud.gd: `_reticle.modulate = hud_color`).
# When/if the shield-glyph, cannon, or enemy-ship sprites get used in
# the tactical HUD, switch to A or C; CanvasItem.modulate would also
# tint the chassis art and break the look.

signal hue_changed(hue_deg: float)

const TOKENS_PATH := "res://Space/art/ui/tactical_hud/tokens.json"
const FONT_PATH := "res://Space/art/ui/fonts/RobynPulpSciFi-Regular.ttf"
const DEFAULT_HUE_DEG := 188.0

# Primary display face for tactical HUD labels. Treated as all-caps; per
# tokens.typography.primary. Falls back to the engine default if the
# file is missing so widgets degrade rather than crash.
var font: Font = null

var data: Dictionary = {}

# Resolved accent palette — re-resolved by apply_hue().
var hud_color: Color = Color(0.36, 0.95, 1.0)
var hud_dim: Color = Color(0.28, 0.58, 0.65)
var hud_deep: Color = Color(0.07, 0.21, 0.26)

# Fixed state colors (not hue-shifted).
var warn: Color = Color("ffb14a")
var danger: Color = Color("ff4a5e")
var ok: Color = Color("6cf08a")
var ink: Color = Color("061015")
var panel_fill: Color = Color(0.031, 0.086, 0.118, 0.72)
var grid: Color = Color(0.36, 0.95, 1.0, 0.08)
var bg_deep: Color = Color("02060b")
var bg_mid: Color = Color("061a26")

var _hue_deg: float = DEFAULT_HUE_DEG


func _ready() -> void:
    _load_tokens()
    _load_font()
    apply_hue(DEFAULT_HUE_DEG)


func _load_font() -> void:
    if not ResourceLoader.exists(FONT_PATH):
        push_error("Tokens: %s not found — falling back to engine default" % FONT_PATH)
        font = ThemeDB.fallback_font
        return
    var loaded: Resource = load(FONT_PATH)
    if loaded is Font:
        font = loaded
    else:
        push_error("Tokens: %s did not load as a Font" % FONT_PATH)
        font = ThemeDB.fallback_font


func _load_tokens() -> void:
    if not FileAccess.file_exists(TOKENS_PATH):
        push_error("Tokens: %s not found — using built-in defaults" % TOKENS_PATH)
        return
    var f := FileAccess.open(TOKENS_PATH, FileAccess.READ)
    if f == null:
        push_error("Tokens: failed to open %s" % TOKENS_PATH)
        return
    var raw_v: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw_v) != TYPE_DICTIONARY:
        push_error("Tokens: %s did not parse to a Dictionary" % TOKENS_PATH)
        return
    data = raw_v


func apply_hue(hue_deg: float) -> void:
    _hue_deg = wrapf(hue_deg, 0.0, 360.0)
    hud_color = Color.from_hsv(_hue_deg / 360.0, 0.95, 0.95)
    hud_dim = Color.from_hsv(_hue_deg / 360.0, 0.55, 0.55)
    hud_deep = Color.from_hsv(_hue_deg / 360.0, 0.60, 0.30)
    hue_changed.emit(_hue_deg)


func current_hue() -> float:
    return _hue_deg


# Returns the layout rect dict (anchor + x/y/w/h) for a HUD region defined
# in tokens.json `hud_geometry_1920x1080`. Empty Dictionary on miss.
func layout_for(region_name: String) -> Dictionary:
    if data.is_empty():
        return {}
    var geo_v: Variant = data.get("hud_geometry_1920x1080", {})
    if typeof(geo_v) != TYPE_DICTIONARY:
        return {}
    var entry_v: Variant = (geo_v as Dictionary).get(region_name, {})
    if typeof(entry_v) != TYPE_DICTIONARY:
        return {}
    return entry_v


# Segmented bar config from tokens.json `bars` (segments_per_bar,
# segment_skew_deg, segment_gap, segment_height, fill_thresholds,
# danger_pulse_seconds).
func bars_config() -> Dictionary:
    if data.is_empty():
        return {}
    var bars_v: Variant = data.get("bars", {})
    if typeof(bars_v) != TYPE_DICTIONARY:
        return {}
    return bars_v


# Returns the int font size for a named scale from
# tokens.typography.scales (e.g. "label_md", "label_lg", "label_xxl",
# "sublabel", "number_lg", "tiny"). Falls back to 11 on miss so widgets
# still render legibly.
func font_size(scale_id: String) -> int:
    if data.is_empty():
        return 11
    var typ_v: Variant = data.get("typography", {})
    if typeof(typ_v) != TYPE_DICTIONARY:
        return 11
    var scales_v: Variant = (typ_v as Dictionary).get("scales", {})
    if typeof(scales_v) != TYPE_DICTIONARY:
        return 11
    var entry_v: Variant = (scales_v as Dictionary).get(scale_id, {})
    if typeof(entry_v) != TYPE_DICTIONARY:
        return 11
    return int((entry_v as Dictionary).get("size", 11))


# Picks the right segment color for `fill_pct` (0..1) using token
# thresholds; falls back to the accent hud_color above warn.
func bar_color_for_fill(fill_pct: float) -> Color:
    var cfg := bars_config()
    var thresholds_v: Variant = cfg.get("fill_thresholds", {})
    var danger_below: float = 30.0
    var warn_below: float = 60.0
    if typeof(thresholds_v) == TYPE_DICTIONARY:
        danger_below = float((thresholds_v as Dictionary).get("danger_below", 30.0))
        warn_below = float((thresholds_v as Dictionary).get("warn_below", 60.0))
    var pct := clampf(fill_pct, 0.0, 1.0) * 100.0
    if pct < danger_below:
        return danger
    elif pct < warn_below:
        return warn
    return ok
