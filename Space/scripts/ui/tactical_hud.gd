extends Control

# Tactical HUD — re-skin of the Space-side combat HUD using the SCS
# Meridian design package. Lives alongside the legacy `hud.gd`; the two
# are mounted on separate CanvasLayers and toggled via
# `GameManager.use_tactical_hud` (see UICoordinator.setup_hud).
#
# Each panel slot from tokens.hud_geometry_1920x1080 hosts a widget:
#   • status_bars  — HULL + SHIELDS segmented bars
#   • pulse_readout / gauss_readout / torpedo_readout / shield_parry —
#     self-contained weapon state machines (no SVG art; see *_readout.gd)
#   • minimap      — full minimap (rings, sweep, contacts, bearings)
#
# Plus a centered reticle (reticle.svg) and the scanline overlay. Player
# bindings are pushed in `_process` so widgets don't have to reach back.

const PanelFrame := preload("res://Space/scripts/ui/tactical/panel_frame.gd")
const SegmentedBar := preload("res://Space/scripts/ui/tactical/segmented_bar.gd")
const PulseCannonReadout := preload("res://Space/scripts/ui/tactical/pulse_cannon_readout.gd")
const GaussBatteryReadout := preload("res://Space/scripts/ui/tactical/gauss_battery_readout.gd")
const TorpedoLauncherReadout := preload("res://Space/scripts/ui/tactical/torpedo_launcher_readout.gd")
const ShieldParryReadout := preload("res://Space/scripts/ui/tactical/shield_parry_readout.gd")
const MinimapWidget := preload("res://Space/scripts/ui/tactical/minimap_widget.gd")

const RETICLE_TEX := preload("res://Space/art/ui/tactical_hud/sprites/reticle.svg")

var player: Node2D = null

var _panels: Dictionary = {}
var _hull_bar: Control = null
var _shield_bar: Control = null
var _reticle: TextureRect = null
var _scanlines: Control = null
var _pulse_readout: Control = null
var _gauss_readout: Control = null
var _torpedo_readout: Control = null
var _shield_readout: Control = null
var _minimap: Control = null


func _ready() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    process_mode = PROCESS_MODE_ALWAYS
    _build_layout()
    _connect_player_signals()


# Hooks the four player fire events to the matching readout. Signals
# are connected in `_ready` once and stay live for the lifetime of the
# HUD — even while the legacy HUD is visible, so readout state stays
# accurate across F10 toggles.
func _connect_player_signals() -> void:
    if not is_instance_valid(player):
        return
    if _pulse_readout != null and player.has_signal("primary_fired"):
        player.primary_fired.connect(_on_player_primary_fired)
    if _gauss_readout != null and player.has_signal("secondary_fired"):
        player.secondary_fired.connect(_on_player_secondary_fired)
    if _torpedo_readout != null and player.has_signal("special_fired"):
        player.special_fired.connect(_on_player_special_fired)
    if _shield_readout != null and player.has_signal("parry_activated"):
        player.parry_activated.connect(_on_player_parry_activated)


func _on_player_primary_fired() -> void:
    _pulse_readout.fire()


func _on_player_secondary_fired() -> void:
    _gauss_readout.fire()


func _on_player_special_fired() -> void:
    _torpedo_readout.fire()


func _on_player_parry_activated() -> void:
    _shield_readout.fire()


func _process(_delta: float) -> void:
    _refresh_bars()


func _refresh_bars() -> void:
    if not is_instance_valid(player):
        return

    if _hull_bar != null and "health" in player and "max_health" in player:
        var max_h: float = float(player.max_health)
        if max_h > 0.0:
            _hull_bar.fill = float(player.health) / max_h

    if _shield_bar != null and "shields" in player and "max_shields" in player:
        var max_s: float = float(player.max_shields)
        if max_s > 0.0:
            _shield_bar.fill = float(player.shields) / max_s
        else:
            _shield_bar.fill = 0.0


func _build_layout() -> void:
    # Panels host their respective readouts, which draw their own
    # hotkey + name header, so the PanelFrame chrome stays title-less.
    _add_panel("shield_parry", "")
    _add_panel("minimap", "")
    _add_panel("pulse_readout", "")
    _add_panel("torpedo_readout", "")
    _add_panel("gauss_readout", "")
    _add_panel("status_bars", "")

    _add_status_bars()
    _add_pulse_readout()
    _add_gauss_readout()
    _add_torpedo_readout()
    _add_shield_readout()
    _add_minimap()
    _add_reticle()
    _add_scanlines()


func _add_pulse_readout() -> void:
    var host: Control = _panels.get("pulse_readout", null) as Control
    if host == null:
        return
    _pulse_readout = _mount_widget(host, PulseCannonReadout, "PulseReadout")


func _add_gauss_readout() -> void:
    var host: Control = _panels.get("gauss_readout", null) as Control
    if host == null:
        return
    _gauss_readout = _mount_widget(host, GaussBatteryReadout, "GaussReadout")


func _add_torpedo_readout() -> void:
    var host: Control = _panels.get("torpedo_readout", null) as Control
    if host == null:
        return
    _torpedo_readout = _mount_widget(host, TorpedoLauncherReadout, "TorpedoReadout")


func _add_shield_readout() -> void:
    var host: Control = _panels.get("shield_parry", null) as Control
    if host == null:
        return
    _shield_readout = _mount_widget(host, ShieldParryReadout, "ShieldReadout")


func _add_minimap() -> void:
    var host: Control = _panels.get("minimap", null) as Control
    if host == null:
        return
    _minimap = _mount_widget(host, MinimapWidget, "Minimap")
    _minimap.set("player_node", player)


# Mounts a widget Control as a full-rect child of `host`. Returns the
# widget so callers can stash refs or set bindings.
func _mount_widget(host: Control, widget_script: GDScript, widget_name: String) -> Control:
    var w := Control.new()
    w.set_script(widget_script)
    w.name = widget_name
    w.mouse_filter = Control.MOUSE_FILTER_IGNORE
    host.add_child(w)
    w.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    return w


func _add_panel(region_id: String, title: String) -> void:
    var rect_data := Tokens.layout_for(region_id)
    if rect_data.is_empty():
        push_error("TacticalHUD: missing layout for '%s'" % region_id)
        return

    var panel := Control.new()
    panel.set_script(PanelFrame)
    panel.name = region_id
    panel.title = title
    add_child(panel)
    _apply_anchor(panel, rect_data)
    _panels[region_id] = panel


func _add_status_bars() -> void:
    var host: Control = _panels.get("status_bars", null) as Control
    if host == null:
        return

    # Two stacked SegmentedBars filling the StatusBars panel — HULL on
    # top, SHIELDS underneath. Inner padding keeps the skewed segments
    # from clipping into the panel's corner-cut chrome.
    var inset_x := 18.0
    var inset_y := 8.0
    var gap := 6.0
    var bar_h := (host.size.y - inset_y * 2.0 - gap) * 0.5
    if bar_h <= 0.0:
        # host.size isn't valid until after a frame; fall back to the
        # spec'd 56-tall StatusBars panel so the layout looks right on
        # the first frame.
        bar_h = (56.0 - inset_y * 2.0 - gap) * 0.5

    _hull_bar = _make_bar("HULL", host)
    _shield_bar = _make_bar("SHIELDS", host)

    _hull_bar.anchor_left = 0.0; _hull_bar.anchor_top = 0.0
    _hull_bar.anchor_right = 1.0; _hull_bar.anchor_bottom = 0.0
    _hull_bar.offset_left = inset_x
    _hull_bar.offset_top = inset_y
    _hull_bar.offset_right = -inset_x
    _hull_bar.offset_bottom = inset_y + bar_h

    _shield_bar.anchor_left = 0.0; _shield_bar.anchor_top = 1.0
    _shield_bar.anchor_right = 1.0; _shield_bar.anchor_bottom = 1.0
    _shield_bar.offset_left = inset_x
    _shield_bar.offset_top = -inset_y - bar_h
    _shield_bar.offset_right = -inset_x
    _shield_bar.offset_bottom = -inset_y


func _make_bar(label: String, host: Control) -> Control:
    var bar := Control.new()
    bar.set_script(SegmentedBar)
    bar.name = label
    bar.label = label
    bar.fill = 1.0
    host.add_child(bar)
    return bar


func _add_reticle() -> void:
    var rect_data := Tokens.layout_for("reticle")
    if rect_data.is_empty():
        return
    _reticle = TextureRect.new()
    _reticle.name = "Reticle"
    _reticle.texture = RETICLE_TEX
    _reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _reticle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _reticle.modulate = Tokens.hud_color
    add_child(_reticle)
    _apply_anchor(_reticle, rect_data)


func _add_scanlines() -> void:
    _scanlines = Control.new()
    _scanlines.name = "Scanlines"
    _scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _scanlines.set_script(preload("res://Space/scripts/ui/tactical/scanline_overlay.gd"))
    add_child(_scanlines)
    _scanlines.set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _apply_anchor(c: Control, rect_data: Dictionary) -> void:
    var anchor := str(rect_data.get("anchor", "top-left"))
    var x := float(rect_data.get("x", 0.0))
    var y := float(rect_data.get("y", 0.0))
    var w := float(rect_data.get("w", 0.0))
    var h := float(rect_data.get("h", 0.0))

    match anchor:
        "top-left":
            c.anchor_left = 0.0; c.anchor_top = 0.0
            c.anchor_right = 0.0; c.anchor_bottom = 0.0
            c.offset_left = x; c.offset_top = y
            c.offset_right = x + w; c.offset_bottom = y + h
        "top-right":
            c.anchor_left = 1.0; c.anchor_top = 0.0
            c.anchor_right = 1.0; c.anchor_bottom = 0.0
            c.offset_left = x - w; c.offset_top = y
            c.offset_right = x; c.offset_bottom = y + h
        "bottom-left":
            c.anchor_left = 0.0; c.anchor_top = 1.0
            c.anchor_right = 0.0; c.anchor_bottom = 1.0
            c.offset_left = x; c.offset_top = y - h
            c.offset_right = x + w; c.offset_bottom = y
        "bottom-right":
            c.anchor_left = 1.0; c.anchor_top = 1.0
            c.anchor_right = 1.0; c.anchor_bottom = 1.0
            c.offset_left = x - w; c.offset_top = y - h
            c.offset_right = x; c.offset_bottom = y
        "bottom-center":
            c.anchor_left = 0.5; c.anchor_top = 1.0
            c.anchor_right = 0.5; c.anchor_bottom = 1.0
            c.offset_left = x - w * 0.5; c.offset_top = y - h
            c.offset_right = x + w * 0.5; c.offset_bottom = y
        "center":
            c.anchor_left = 0.5; c.anchor_top = 0.5
            c.anchor_right = 0.5; c.anchor_bottom = 0.5
            c.offset_left = x - w * 0.5; c.offset_top = y - h * 0.5
            c.offset_right = x + w * 0.5; c.offset_bottom = y + h * 0.5
        _:
            push_error("TacticalHUD: unknown anchor '%s'" % anchor)
