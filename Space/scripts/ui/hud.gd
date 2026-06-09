extends Control




var player: Node2D = null
var bark_text: String = ""
var bark_speaker: String = ""
var bark_crew_id: String = ""
var bark_timer: float = 0.0
var bark_color: Color = Color(0.3, 0.8, 1.0)


var speech_bubbles: Array = []
const BUBBLE_DURATION: float = 3.5
const BUBBLE_RISE_SPEED: float = 25.0
const MAX_BUBBLES: int = 5

var kill_count: int = 0
var system_name: String = ""
var power_preset: int = 0
var system_positions: Dictionary = {}
var loaded_system_id: String = ""
var time_frozen: bool = false
var command_mode: bool = false
var on_surface: bool = false
var commanding_fleet_ship: String = ""
var show_fps: bool = false
var test_fly_controls_timer: float = 0.0
var combat_recorder: Node = null
var training_round: int = 0
var training_naming: bool = false

const PRESET_NAMES = ["BALANCED", "WEAPONS", "SHIELDS", "ENGINES", "REPAIRS"]
const PRESET_COLORS = [
    Color(0.6, 0.6, 0.6),
    Color(0.9, 0.3, 0.25),
    Color(0.3, 0.5, 1.0),
    Color(1.0, 0.6, 0.2),
    Color(0.2, 0.9, 0.4),
]

func _ready():
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    process_mode = PROCESS_MODE_ALWAYS

func _process(delta: float):
    if bark_timer > 0:
        bark_timer -= delta
        if bark_timer <= 0:
            bark_text = ""

    if test_fly_controls_timer > 0 and not get_tree().paused:
        test_fly_controls_timer -= delta

    var i = speech_bubbles.size() - 1
    while i >= 0:
        var b = speech_bubbles[i]
        b["timer"] += delta
        b["rise"] = b.get("rise", 0.0) + BUBBLE_RISE_SPEED * delta
        if b["timer"] >= b["max_time"]:
            speech_bubbles.remove_at(i)
        i -= 1
    queue_redraw()

func spawn_speech_bubble(text: String, color: Color = Color(0.7, 0.8, 0.95)):

    if text.length() > 50:
        text = text.substr(0, 47) + "..."
    var offset_x = randf_range(-40.0, 40.0)
    if speech_bubbles.size() >= MAX_BUBBLES:
        speech_bubbles.pop_front()
    speech_bubbles.append({
        "text": text, 
        "timer": 0.0, 
        "max_time": BUBBLE_DURATION, 
        "color": color, 
        "offset_x": offset_x, 
        "rise": 0.0, 
    })

func show_bark(speaker: String, text: String, color: Color = Color(0.3, 0.8, 1.0), duration: float = 3.5, crew_id: String = ""):
    bark_speaker = speaker
    bark_text = text
    bark_color = color
    bark_timer = duration
    bark_crew_id = crew_id

func _draw():
    if not player or not is_instance_valid(player):
        return
    var _scene_ref = get_tree().current_scene
    if _scene_ref and (_scene_ref.get("builder_open") or _scene_ref.get("editor_open")):
        return

    var m: float = 16.0
    var bw: float = 200.0
    var bh: float = 16.0
    var gap: float = 3.0
    var font = ThemeDB.fallback_font


    var bar_x = m
    var bar_y = m


    # Hull + Shields Nebula tank gauges (ported from the Ship-HUD handoff).
    var max_health: float = maxf(player.max_health, 1.0)
    var hull_size := NebulaHud.draw_tank_gauge(self, Vector2(bar_x, bar_y), {
        "label": "Hull", "value": int(player.health), "max": int(max_health),
        "total": maxi(1, int(ceil(max_health / 100.0))),
        "tone": "energy", "danger_tone": "crystal", "danger_at": 0.2,
        "per_row": 7, "size": 26.0, "low_at": 2.0, "glyph": "hp",
    })
    var max_shields: float = maxf(player.max_shields, 1.0)
    NebulaHud.draw_tank_gauge(self, Vector2(bar_x + hull_size.x + 22.0, bar_y), {
        "label": "Shields", "value": int(player.shields), "max": int(max_shields),
        "total": maxi(1, int(ceil(max_shields / 100.0))),
        "tone": "shield", "per_row": 5, "size": 26.0, "low_at": 1.0, "glyph": "shield",
    })
    bar_y += hull_size.y + gap + 4


    var boost_pct = 1.0
    var boost_is_ready = true
    if not player.boost_ready:
        boost_pct = 1.0 - clampf(player.boost_cd_timer / player.boost_cooldown, 0, 1)
    boost_is_ready = player.boost_ready
    var boost_color = Color(0.4, 0.65, 1.0) if boost_is_ready else Color(0.35, 0.35, 0.4)
    _draw_bar(Vector2(bar_x, bar_y), bw, bh - 2, boost_pct, boost_color, "BOOST")
    bar_y += bh - 2 + gap


    var scan_pct = 1.0
    if player.scan_cooldown > 0:
        scan_pct = 1.0 - clampf(player.scan_cooldown / player.SCAN_COOLDOWN_TIME, 0, 1)
    var scan_color = Color(0.2, 0.8, 0.5) if player.scan_cooldown <= 0 else Color(0.3, 0.35, 0.4)
    var scan_label = "SCAN [LB]" if GameManager.using_controller else "SCAN [Q]"
    _draw_bar(Vector2(bar_x, bar_y), bw, bh - 2, scan_pct, scan_color, scan_label)
    bar_y += bh - 2 + gap


    if player.orbit_locked and player.handbrake_target and is_instance_valid(player.handbrake_target):
        var orbit_pulse = sin(Time.get_ticks_msec() * 0.003) * 0.12 + 0.88
        var orbit_col = Color(0.95, 0.97, 1.0, orbit_pulse)

        var orbit_x = size.x - m - 160
        var orbit_y = m + 60

        draw_string(font, Vector2(orbit_x - 1, orbit_y), "ORBIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.3, 0.7, 0.95, 0.15))
        draw_string(font, Vector2(orbit_x, orbit_y), "ORBIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, orbit_col)

        draw_line(Vector2(orbit_x, orbit_y + 4), Vector2(orbit_x + 100, orbit_y + 4), Color(0.4, 0.7, 0.95, orbit_pulse * 0.4), 1.5)

        var target_name = ""
        if "poi_name" in player.handbrake_target:
            target_name = player.handbrake_target.poi_name
        elif "fleet_name" in player.handbrake_target:
            target_name = player.handbrake_target.fleet_name
        if target_name != "":
            draw_string(font, Vector2(orbit_x, orbit_y + 18), target_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 0.85, 0.7))

    if "harpoon_state" in player and player.harpoon_state == 2:  # HarpoonState.ATTACHED
        var teth_pulse = sin(Time.get_ticks_msec() * 0.004) * 0.15 + 0.85
        var teth_col = Color(0.3, 0.9, 0.4, teth_pulse)

        var teth_x = size.x - m - 160
        var teth_y = m + 95

        draw_string(font, Vector2(teth_x - 1, teth_y), "TETHERED", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.15, 0.5, 0.2, 0.15))
        draw_string(font, Vector2(teth_x, teth_y), "TETHERED", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, teth_col)

        draw_line(Vector2(teth_x, teth_y + 4), Vector2(teth_x + 100, teth_y + 4), Color(0.2, 0.7, 0.3, teth_pulse * 0.4), 1.5)

        var release_key = "[B]" if GameManager.using_controller else "[R]"
        draw_string(font, Vector2(teth_x, teth_y + 18), release_key + " release", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.7, 0.4, 0.7))

    bar_y += 2


    var panel_x = m
    var panel_w = bw
    var panel_inner_m = 8.0
    var line_h = 15.0
    var col2_x = panel_x + panel_w * 0.52


    var line_count: int = 3
    var total_res = GameManager.get_total_resources()


    var zone_text = ""
    var zone_col = Color(0.45, 0.45, 0.5)
    if player.star_speed_mult < 0.6:
        zone_col = Color(0.9, 0.4, 0.2)
        zone_text = "GRAVITY WELL"
    elif player.star_speed_mult < 0.95:
        zone_col = Color(0.75, 0.6, 0.25)
        zone_text = "INNER SYSTEM"
    elif player.star_speed_mult > 1.1:
        zone_col = Color(0.35, 0.65, 0.85)
        zone_text = "OPEN SPACE"
    if zone_text != "":
        line_count += 1

    var panel_h = line_count * line_h + panel_inner_m * 2
    var panel_y = bar_y


    draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.03, 0.035, 0.05, 0.85))
    draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.2, 0.25, 0.35, 0.4), false, 1.0)

    draw_line(Vector2(panel_x, panel_y), Vector2(panel_x + panel_w, panel_y), Color(0.3, 0.4, 0.55, 0.5), 1.0)

    var ly = panel_y + panel_inner_m + 10


    draw_string(font, Vector2(panel_x + panel_inner_m, ly), "CR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.45, 0.3))
    draw_string(font, Vector2(panel_x + panel_inner_m + 22, ly), "%d" % GameManager.credits, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.78, 0.3))
    draw_string(font, Vector2(col2_x, ly), "KILLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
    draw_string(font, Vector2(col2_x + 40, ly), "%d" % kill_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.65, 0.7))
    ly += line_h


    var active_preset = power_preset
    var pcolor = PRESET_COLORS[active_preset]
    draw_rect(Rect2(panel_x + panel_inner_m, ly - 8, 6, 6), pcolor)
    draw_string(font, Vector2(panel_x + panel_inner_m + 10, ly), "PWR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
    draw_string(font, Vector2(panel_x + panel_inner_m + 32, ly), PRESET_NAMES[active_preset], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pcolor)
    var spd: int
    var spd_max: float
    spd = int(player.velocity.length())
    spd_max = player.max_speed
    var spd_col = Color(0.5, 0.6, 0.7)
    if spd > int(spd_max * 1.05):
        spd_col = Color(1.0, 0.6, 0.2)
    draw_string(font, Vector2(col2_x, ly), "SPD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
    draw_string(font, Vector2(col2_x + 28, ly), "%d" % spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, spd_col)
    ly += line_h


    var fuel_pct: float
    var is_scooping: bool = false
    fuel_pct = GameManager.fuel / maxf(GameManager.fuel_capacity, 1) * 100
    is_scooping = player.scooping
    var fuel_col = Color(0.5, 0.6, 0.75) if fuel_pct > 15 else Color(0.9, 0.3, 0.2)
    draw_string(font, Vector2(panel_x + panel_inner_m, ly), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
    var fuel_val_text = "%d%%" % int(fuel_pct)
    if is_scooping:
        var pulse = sin(Time.get_ticks_msec() * 0.008) * 0.3 + 0.7
        fuel_col = Color(0.9, 0.7, 0.2, pulse)
        fuel_val_text += " SCOOPING"
    draw_string(font, Vector2(panel_x + panel_inner_m + 35, ly), fuel_val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, fuel_col)

    if total_res > 0:
        draw_string(font, Vector2(col2_x, ly), "RES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.45, 0.5))
        draw_string(font, Vector2(col2_x + 28, ly), "%d/%d" % [total_res, GameManager.resource_capacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.55, 0.3))
    ly += line_h





    if zone_text != "":
        draw_string(font, Vector2(panel_x + panel_inner_m, ly), zone_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, zone_col)
        ly += line_h



    if bark_text != "":
        _draw_bark(m, font)

    # Shield Supercharger cooldown arc — bottom-left
    if GameManager.has_shield_supercharger():
        _draw_parry_cooldown(m, font)

    var sys_x = size.x - 280 - m
    if system_name != "":
        draw_string(font, Vector2(sys_x, m + 16), system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.7, 0.85))

        var clock_str = GameManager.get_short_clock()
        draw_string(font, Vector2(sys_x + 200, m + 16), clock_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65))
        if GameManager.using_controller:
            draw_string(font, Vector2(sys_x, m + 32), "%s:Map  %s:Builder  %s:Pause" % [
                GameManager.get_button_prompt("toggle_star_map"),
                GameManager.get_button_prompt("toggle_ship_builder"),
                GameManager.get_button_prompt("toggle_pause"),
            ], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.5))
            draw_string(font, Vector2(sys_x, m + 46), "%s:Scan  %s:Fire  %s:Secondary  %s:Boost" % [
                GameManager.get_button_prompt("scan"),
                GameManager.get_button_prompt("fire_primary"),
                GameManager.get_button_prompt("fire_secondary"),
                GameManager.get_button_prompt("boost"),
            ], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.5))
        else:
            draw_string(font, Vector2(sys_x, m + 32), "[%s] Map  [%s] Builder  [%s] Pause" % [
                GameManager.get_button_prompt("toggle_star_map"),
                GameManager.get_button_prompt("toggle_ship_builder"),
                GameManager.get_button_prompt("toggle_pause"),
            ], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.5))
            draw_string(font, Vector2(sys_x, m + 46), "[%s] Save  [%s] Load  [%s] Scan" % [
                GameManager.get_button_prompt("save_game"),
                GameManager.get_button_prompt("load_game"),
                GameManager.get_button_prompt("scan"),
            ], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.5))


    var cx = size.x * 0.5
    if time_frozen:
        var freeze_text = "|| TIME FROZEN ||"
        var fw = freeze_text.length() * 7.0
        draw_rect(Rect2(cx - fw * 0.5 - 6, 4, fw + 12, 22), Color(0.15, 0.1, 0.0, 0.85))
        draw_rect(Rect2(cx - fw * 0.5 - 6, 4, fw + 12, 22), Color(0.9, 0.6, 0.1, 0.7), false, 1.5)
        draw_string(font, Vector2(cx - fw * 0.5, 21), freeze_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.2))
    var mode_text = "COMMAND" if command_mode else "PILOT"
    var mode_col = Color(0.3, 0.8, 1.0) if command_mode else Color(0.4, 0.9, 0.4)
    var mode_y = 30.0 if time_frozen else 8.0
    draw_string(font, Vector2(cx - 30, mode_y + 14), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, mode_col * Color(1, 1, 1, 0.7))


    if commanding_fleet_ship != "":
        var cmd_pulse = sin(Time.get_ticks_msec() * 0.003) * 0.1 + 0.9
        var cmd_text = "COMMANDING: " + commanding_fleet_ship
        var cmd_w = cmd_text.length() * 6.5
        var cmd_y = mode_y + 18
        draw_rect(Rect2(cx - cmd_w * 0.5 - 6, cmd_y, cmd_w + 12, 18), Color(0.05, 0.12, 0.08, 0.85))
        draw_rect(Rect2(cx - cmd_w * 0.5 - 6, cmd_y, cmd_w + 12, 18), Color(0.3, 0.8, 0.4, 0.5 * cmd_pulse), false, 1.0)
        draw_string(font, Vector2(cx - cmd_w * 0.5, cmd_y + 13), cmd_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.9, 0.5, cmd_pulse))

        var fleet_hint = "[A] Fleet to return" if GameManager.using_controller else "[G] Fleet  to return"
        draw_string(font, Vector2(cx - 40, cmd_y + 28), fleet_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.5, 0.4, 0.6))


    var main = get_tree().current_scene
    var p_src: Node = null
    if main and main.player and is_instance_valid(main.player):
        p_src = main.player

    _draw_weapon_bar(font, p_src)
    _draw_radial_menu(font, p_src)





    _draw_minimap(m, font)


    _draw_crosshair()


    _draw_star_warnings(font)


    _draw_speech_bubbles()


    if test_fly_controls_timer > 0:
        _draw_controls_overlay(font)

    if combat_recorder and combat_recorder.is_recording:
        var rec_y = 30.0
        var blink = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.7
        if blink:
            draw_circle(Vector2(size.x - 110, rec_y - 4), 6.0, Color(0.9, 0.15, 0.15))
        var frames_captured = combat_recorder.recording.get_frame_count() if combat_recorder.recording else 0
        var rec_text = "REC %d" % frames_captured
        draw_string(font, Vector2(size.x - 98, rec_y), rec_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.15, 0.15))
        if training_round > 0:
            rec_y += 20.0
            var round_text = "TRAINING ROUND %d" % training_round
            draw_string(font, Vector2(size.x - 170, rec_y), round_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.8, 1.0))
            rec_y += 16.0
            draw_string(font, Vector2(size.x - 170, rec_y), "[B] Update  [ESC] Save & Exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6, 0.7))

    if training_naming:
        # Dark overlay + prompt label above the LineEdit
        draw_rect(Rect2(0, 0, size.x, size.y), Color(0, 0, 0, 0.6))
        var ncx = size.x * 0.5
        var ncy = size.y * 0.5
        draw_string(font, Vector2(ncx - 150, ncy - 20), "SAVE AI RECORDING AS:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.8, 1.0))
        draw_string(font, Vector2(ncx - 150, ncy + 50), "Enter to save  |  ESC to cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5, 0.8))

    if show_fps:
        var fps = Engine.get_frames_per_second()
        var frame_time = 1000.0 / maxf(fps, 1.0)
        var fps_col = Color(0.2, 0.9, 0.2) if fps >= 55 else (Color(1.0, 0.7, 0.2) if fps >= 30 else Color(1.0, 0.3, 0.2))
        var fps_text = "%d FPS (%.1f ms)" % [fps, frame_time]
        draw_string(font, Vector2(size.x - 180, size.y - 8), fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fps_col)

func _draw_bar(pos: Vector2, w: float, h: float, pct: float, color: Color, label: String):
    pct = clampf(pct, 0.0, 1.0)

    draw_rect(Rect2(pos, Vector2(w, h)), Color(0.04, 0.04, 0.06, 0.9))

    var fill_w = w * pct
    if fill_w > 1:
        draw_rect(Rect2(pos, Vector2(fill_w, h)), color * 0.7)

        draw_rect(Rect2(pos, Vector2(fill_w, 1)), Color(color.lerp(Color.WHITE, 0.3), 0.35))

    draw_rect(Rect2(pos, Vector2(w, h)), Color(0.2, 0.25, 0.3, 0.5), false, 1.0)

    var font = ThemeDB.fallback_font
    draw_string(font, pos + Vector2(5, h - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.87, 0.92))
    var pct_text = "%d%%" % int(pct * 100)
    draw_string(font, pos + Vector2(w - 34, h - 3), pct_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.87, 0.92))


func _wrap_bark_text(text: String, max_width: float, char_w: float) -> Array:
    var lines: Array = []
    var words = text.split(" ")
    var line = ""
    for word in words:
        var test = line + (" " if line != "" else "") + word
        if test.length() * char_w > max_width and line != "":
            lines.append(line)
            line = word
        else:
            line = test
    if line != "":
        lines.append(line)
    return lines

func _draw_bark(m: float, font: Font):
    var bark_w = 700.0
    var text_x = m
    var line_h = 20.0
    var char_w = 7.8
    var text_max_w = bark_w - 28.0


    var lines = _wrap_bark_text(bark_text, text_max_w, char_w)
    var text_block_h = lines.size() * line_h


    var bark_h = 36.0 + text_block_h + 12.0
    bark_h = maxf(bark_h, 60.0)
    var bark_y = size.y - bark_h - m


    draw_rect(Rect2(m, bark_y, bark_w, bark_h), Color(0.01, 0.01, 0.03, 0.9))

    for gi in 3:
        var gw = 1.0 + float(gi) * 1.0
        draw_rect(Rect2(m - gi, bark_y - gi, bark_w + gi * 2, bark_h + gi * 2), 
            Color(bark_color, 0.15 - float(gi) * 0.04), false, gw)
    draw_rect(Rect2(m, bark_y, bark_w, bark_h), Color(bark_color, 0.55), false, 1.5)

    draw_line(Vector2(m, bark_y), Vector2(m + bark_w, bark_y), Color(bark_color, 0.8), 2.0)
    draw_line(Vector2(m, bark_y - 1), Vector2(m + bark_w, bark_y - 1), Color(bark_color, 0.2), 3.0)


    var name_y = bark_y + 24
    draw_string(font, Vector2(text_x + 7, name_y), bark_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(bark_color, 0.15))
    draw_string(font, Vector2(text_x + 8, name_y), bark_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, bark_color)

    var name_w = bark_speaker.length() * 9.0
    draw_line(Vector2(text_x + 8, name_y + 4), Vector2(text_x + 8 + name_w, name_y + 4), Color(bark_color, 0.3), 1.0)


    var ty = name_y + 22.0
    for line in lines:
        draw_string(font, Vector2(text_x + 10, ty), line, HORIZONTAL_ALIGNMENT_LEFT, int(text_max_w), 14, Color(0.85, 0.88, 0.92))
        ty += line_h

func _draw_parry_cooldown(m: float, font: Font):
    var radius: float = 66.0
    var cx = m + radius + 4.0
    var cy = size.y - radius - m - 4.0

    # Shift up if bark text is visible
    if bark_text != "":
        cy -= 80.0

    var cd = player.parry_cooldown if "parry_cooldown" in player else 0.0
    var cd_max = player.PARRY_COOLDOWN_TIME if "PARRY_COOLDOWN_TIME" in player else 4.0
    var is_active = player.parry_active if "parry_active" in player else false

    if is_active:
        # Active — draining arc that refills on reflects/collisions
        var parry_timer = player.parry_timer if "parry_timer" in player else 0.0
        var parry_max = player.PARRY_MAX_DURATION if "PARRY_MAX_DURATION" in player else 2.0
        var parry_mult = player.parry_max_duration_mult if "parry_max_duration_mult" in player else 1.0
        var effective_max = parry_max * parry_mult
        var remaining_pct = clampf(parry_timer / effective_max, 0.0, 1.0)
        var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.012) * 0.3
        draw_circle(Vector2(cx, cy), radius, Color(0.15, 0.3, 0.5, 0.6))
        draw_arc(Vector2(cx, cy), radius, 0, TAU, 32, Color(0.3, 0.7, 1.0, pulse), 4.0)
        if remaining_pct > 0.01:
            draw_arc(Vector2(cx, cy), radius * 0.6, -PI / 2.0, -PI / 2.0 + remaining_pct * TAU, 32, Color(0.4, 0.85, 1.0, 0.9), radius * 0.5)
        var t_text = "%.1f" % parry_timer
        var tw = font.get_string_size(t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
        draw_string(font, Vector2(cx - tw * 0.5, cy + 7), t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.95, 1.0))
        var label = "SUPERCHARGER"
        var lw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        draw_string(font, Vector2(cx - lw * 0.5, cy + radius + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.85, 1.0))
    elif cd > 0:
        # On cooldown — dark ring with filling arc
        var progress = 1.0 - clampf(cd / cd_max, 0.0, 1.0)
        draw_circle(Vector2(cx, cy), radius, Color(0.05, 0.06, 0.08, 0.7))
        if progress > 0.01:
            draw_arc(Vector2(cx, cy), radius * 0.65, -PI / 2.0, -PI / 2.0 + progress * TAU, 32, Color(0.3, 0.6, 0.9, 0.8), radius * 0.5)
        draw_arc(Vector2(cx, cy), radius, 0, TAU, 32, Color(0.25, 0.3, 0.4, 0.5), 2.0)
        var cd_text = "%.1f" % cd
        var tw = font.get_string_size(cd_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
        draw_string(font, Vector2(cx - tw * 0.5, cy + 7), cd_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.55, 0.65))
        var label = "SUPERCHARGER"
        var lw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        draw_string(font, Vector2(cx - lw * 0.5, cy + radius + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.55))
    else:
        # Ready — bright ring
        draw_circle(Vector2(cx, cy), radius, Color(0.1, 0.18, 0.25, 0.6))
        draw_arc(Vector2(cx, cy), radius * 0.65, -PI / 2.0, -PI / 2.0 + TAU, 32, Color(0.3, 0.85, 1.0, 0.9), radius * 0.5)
        draw_arc(Vector2(cx, cy), radius, 0, TAU, 32, Color(0.3, 0.6, 0.9, 0.7), 2.0)
        var label = "SUPERCHARGER"
        var lw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        draw_string(font, Vector2(cx - lw * 0.5, cy + radius + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.85, 1.0))

func _draw_speech_bubbles():

    if speech_bubbles.is_empty():
        return
    var font = ThemeDB.fallback_font
    var font_size: int = 11
    var pad_x: float = 6.0
    var pad_y: float = 4.0
    var pill_h: float = font_size + pad_y * 2
    var stack_gap: float = 4.0
    var center_x: float = size.x * 0.5
    var base_y: float = size.y * 0.5 - 50.0

    var sorted = speech_bubbles.duplicate()
    sorted.sort_custom( func(a, b2): return a["timer"] < b2["timer"])

    for idx in sorted.size():
        var b = sorted[idx]
        var t: float = b["timer"] / b["max_time"]
        var alpha: float = 1.0
        if t < 0.1:
            alpha = t / 0.1
        elif t > 0.7:
            alpha = 1.0 - (t - 0.7) / 0.3
        alpha = clampf(alpha, 0, 1)
        var text: String = b["text"]
        var pos_x: float = center_x + b.get("offset_x", 0.0)
        var pos_y: float = base_y - b.get("rise", 0.0) - idx * (pill_h + stack_gap)
        var col: Color = b["color"]
        var text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var pill_w = text_w + pad_x * 2
        var pill_pos = Vector2(pos_x - pill_w * 0.5, pos_y - pill_h)

        draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.05, 0.05, 0.12, 0.75 * alpha))

        draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(col, 0.5 * alpha), false, 1.0)

        if idx == 0:
            var tail_top = pill_pos.y + pill_h
            draw_colored_polygon(PackedVector2Array([
                Vector2(pos_x - 4, tail_top), 
                Vector2(pos_x + 4, tail_top), 
                Vector2(pos_x, tail_top + 6), 
            ]), Color(0.05, 0.05, 0.12, 0.75 * alpha))

        draw_string(font, pill_pos + Vector2(pad_x, pad_y + font_size * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col, alpha))

func _draw_star_warnings(font: Font):

    var main_node = get_tree().current_scene
    if not main_node or not ("player" in main_node) or not main_node.player:
        return
    var p = main_node.player
    if not ("star_heat_warning" in p):
        return
    var warn_y: float = size.y * 0.25
    var center_x: float = size.x * 0.5
    var flash = sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
    if p.star_heat_warning:
        var heat_col = Color(1.0, 0.3, 0.1, 0.7 + flash * 0.3)
        var heat_text = "!! STELLAR HEAT DAMAGE !!"
        var tw = font.get_string_size(heat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x

        draw_rect(Rect2(center_x - tw * 0.5 - 10, warn_y - 18, tw + 20, 24), Color(0.15, 0.02, 0.02, 0.7 + flash * 0.2))
        draw_string(font, Vector2(center_x - tw * 0.5, warn_y), heat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, heat_col)
        warn_y += 28
    if p.star_gravity_warning and not p.star_heat_warning:
        var grav_col = Color(1.0, 0.7, 0.2, 0.5 + flash * 0.3)
        var grav_text = "GRAVITATIONAL PULL"
        var tw = font.get_string_size(grav_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
        draw_rect(Rect2(center_x - tw * 0.5 - 8, warn_y - 16, tw + 16, 22), Color(0.12, 0.08, 0.02, 0.5))
        draw_string(font, Vector2(center_x - tw * 0.5, warn_y), grav_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, grav_col)

func _draw_minimap(m: float, font: Font):

    if size.x < 1 or size.y < 1:
        return

    var map_size: float = 160.0
    var map_x = size.x - map_size - m
    var map_y = size.y - map_size - m
    var center = Vector2(map_x + map_size * 0.5, map_y + map_size * 0.5)
    var map_rect = Rect2(map_x, map_y, map_size, map_size)


    draw_rect(map_rect, Color(0.04, 0.04, 0.08, 0.92))

    draw_rect(Rect2(map_x + 1, map_y + 1, map_size - 2, map_size - 2), Color(0.12, 0.15, 0.22, 0.4), false, 1.0)

    draw_rect(map_rect, Color(0.3, 0.4, 0.55, 0.8), false, 1.5)


    var cb = 8.0
    var cc = Color(0.4, 0.55, 0.7, 0.7)

    draw_line(Vector2(map_x, map_y), Vector2(map_x + cb, map_y), cc, 1.5)
    draw_line(Vector2(map_x, map_y), Vector2(map_x, map_y + cb), cc, 1.5)

    draw_line(Vector2(map_x + map_size, map_y), Vector2(map_x + map_size - cb, map_y), cc, 1.5)
    draw_line(Vector2(map_x + map_size, map_y), Vector2(map_x + map_size, map_y + cb), cc, 1.5)

    draw_line(Vector2(map_x, map_y + map_size), Vector2(map_x + cb, map_y + map_size), cc, 1.5)
    draw_line(Vector2(map_x, map_y + map_size), Vector2(map_x, map_y + map_size - cb), cc, 1.5)

    draw_line(Vector2(map_x + map_size, map_y + map_size), Vector2(map_x + map_size - cb, map_y + map_size), cc, 1.5)
    draw_line(Vector2(map_x + map_size, map_y + map_size), Vector2(map_x + map_size, map_y + map_size - cb), cc, 1.5)


    if on_surface:
        _draw_minimap_surface(map_x, map_y, map_size, center, map_rect, font)
    else:
        var in_transit = false
        if player and is_instance_valid(player):
            in_transit = player.global_position.distance_to(player.nearest_star_pos) > 35000.0
        if in_transit:
            _draw_minimap_transit(map_x, map_y, map_size, center, map_rect, font)
        else:
            _draw_minimap_system(map_x, map_y, map_size, center, map_rect, font)

func _draw_minimap_system(map_x: float, map_y: float, map_size: float, center: Vector2, map_rect: Rect2, font: Font):


    var sys = DataManager.systems.get(GameManager.current_system, {})
    var pois: Array = sys.get("pois", [])
    var max_dist: float = 800.0
    for poi in pois:
        var od: float = poi.get("orbit_dist", 500.0)
        if od > max_dist:
            max_dist = od
    var mm_scale = (map_size * 0.42) / max_dist


    draw_arc(center, max_dist * mm_scale, 0, TAU, 32, Color(0.2, 0.25, 0.3, 0.25), 0.5)

    draw_line(Vector2(map_x + 4, center.y), Vector2(map_x + map_size - 4, center.y), Color(0.15, 0.18, 0.22, 0.3), 0.5)
    draw_line(Vector2(center.x, map_y + 4), Vector2(center.x, map_y + map_size - 4), Color(0.15, 0.18, 0.22, 0.3), 0.5)


    var sc_arr = sys.get("star_color", [1.0, 1.0, 0.8])
    var star_col = Color(1.0, 1.0, 0.8)
    if sc_arr is Array and sc_arr.size() >= 3:
        star_col = Color(sc_arr[0], sc_arr[1], sc_arr[2])
    draw_circle(center, 5.0, Color(star_col, 0.2))
    draw_circle(center, 3.0, star_col)


    var type_colors: Dictionary = {
        "station": Color(0.3, 0.9, 0.4), 
        "hostile_station": Color(1.0, 0.3, 0.2), 
        "salvage": Color(0.9, 0.8, 0.3), 
        "resource": Color(0.4, 0.75, 1.0), 
        "anomaly": Color(0.75, 0.4, 1.0), 
        "ruin": Color(0.2, 0.9, 1.0), 
        "planet": Color(0.35, 0.75, 0.35), 
    }
    var star_pos = Vector2.ZERO
    if player and is_instance_valid(player):
        star_pos = player.nearest_star_pos
    var poi_nodes = get_tree().get_nodes_in_group("pois")
    for poi_node in poi_nodes:

        if "discovered" in poi_node and not poi_node.discovered:
            continue
        var pp = center + (poi_node.global_position - star_pos) * mm_scale
        if not map_rect.has_point(pp):
            continue
        var poi_type: String = poi_node.poi_type if "poi_type" in poi_node else "anomaly"
        var pc = type_colors.get(poi_type, Color(0.5, 0.5, 0.5))

        if poi_type == "planet" and "planet_data" in poi_node and not poi_node.planet_data.is_empty():
            pc = Color(0.65, 0.45, 0.25)
        var pip_r = 3.5 if poi_type == "planet" else 2.5
        if poi_type == "station":

            pip_r = 4.5
            draw_circle(pp, pip_r + 3.0, Color(pc, 0.12))
            draw_arc(pp, pip_r + 2.0, 0, TAU, 12, Color(pc, 0.5), 0.8)
        draw_circle(pp, pip_r + 1.5, Color(pc, 0.15))
        draw_circle(pp, pip_r, pc)


    if player and is_instance_valid(player):
        var player_map_pos = center + (player.global_position - star_pos) * mm_scale

        player_map_pos.x = clampf(player_map_pos.x, map_x + 5, map_x + map_size - 5)
        player_map_pos.y = clampf(player_map_pos.y, map_y + 5, map_y + map_size - 5)

        var fwd = Vector2.from_angle(player.rotation)
        var p1 = player_map_pos + fwd * 5
        var p2 = player_map_pos + fwd.rotated(2.5) * 4
        var p3 = player_map_pos + fwd.rotated(-2.5) * 4
        draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.3, 1.0, 0.5))

        draw_line(p1, p2, Color(0.5, 1.0, 0.7, 0.6), 0.8)
        draw_line(p1, p3, Color(0.5, 1.0, 0.7, 0.6), 0.8)


    if player and is_instance_valid(player) and player.is_inside_tree():
        var enemies = player.get_tree().get_nodes_in_group("enemies")
        for e in enemies:
            if not is_instance_valid(e):
                continue
            var ep = center + (e.global_position - star_pos) * mm_scale
            if map_rect.has_point(ep):
                draw_circle(ep, 2.0, Color(1.0, 0.3, 0.2, 0.85))


    draw_string(font, Vector2(map_x + 4, map_y + 12), "SYSTEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.65, 0.8))

func _draw_minimap_transit(map_x: float, map_y: float, map_size: float, center: Vector2, map_rect: Rect2, font: Font):

    var player_world = player.global_position
    var transit_range: float = 15000.0
    var mm_scale = (map_size * 0.42) / transit_range


    draw_line(Vector2(map_x + 4, center.y), Vector2(map_x + map_size - 4, center.y), Color(0.15, 0.18, 0.22, 0.3), 0.5)
    draw_line(Vector2(center.x, map_y + 4), Vector2(center.x, map_y + map_size - 4), Color(0.15, 0.18, 0.22, 0.3), 0.5)


    var visible_systems: Dictionary = {}
    for sys_id in system_positions:
        var world_pos: Vector2 = system_positions[sys_id]
        var dist = player_world.distance_to(world_pos)
        if dist > transit_range:
            continue
        var screen_pos = center + (world_pos - player_world) * mm_scale
        if map_rect.has_point(screen_pos):
            visible_systems[sys_id] = screen_pos


    for sys_id in visible_systems:
        var sys_data = DataManager.systems.get(sys_id, {})
        var connections: Array = sys_data.get("connections", [])
        for conn_id in connections:
            if conn_id in visible_systems and conn_id > sys_id:
                draw_line(visible_systems[sys_id], visible_systems[conn_id], Color(0.25, 0.3, 0.4, 0.3), 0.5)


    for sys_id in visible_systems:
        var sp: Vector2 = visible_systems[sys_id]
        var sys_data = DataManager.systems.get(sys_id, {})

        var sc_arr = sys_data.get("star_color", [1.0, 1.0, 0.8])
        var star_col = Color(1.0, 1.0, 0.8)
        if sc_arr is Array and sc_arr.size() >= 3:
            star_col = Color(sc_arr[0], sc_arr[1], sc_arr[2])

        var dot_r = 4.0 if sys_id == loaded_system_id else 3.0
        draw_circle(sp, dot_r + 1.5, Color(star_col, 0.15))
        draw_circle(sp, dot_r, star_col)

        var full_name: String = sys_data.get("name", sys_id)
        var short_name: String = full_name.split(" ")[0]
        draw_string(font, sp + Vector2(dot_r + 3, 4), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.55, 0.65, 0.7))


    var fwd = Vector2.from_angle(player.rotation)
    var p1 = center + fwd * 5
    var p2 = center + fwd.rotated(2.5) * 4
    var p3 = center + fwd.rotated(-2.5) * 4
    draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.3, 1.0, 0.5))
    draw_line(p1, p2, Color(0.5, 1.0, 0.7, 0.6), 0.8)
    draw_line(p1, p3, Color(0.5, 1.0, 0.7, 0.6), 0.8)


    # Draw enemies on transit minimap
    if player.is_inside_tree():
        var enemies = player.get_tree().get_nodes_in_group("enemies")
        for e in enemies:
            if not is_instance_valid(e):
                continue
            var ep = center + (e.global_position - player_world) * mm_scale
            if map_rect.has_point(ep):
                draw_circle(ep, 2.5, Color(1.0, 0.3, 0.2, 0.85))

    draw_string(font, Vector2(map_x + 4, map_y + 12), "TRANSIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.65, 0.8))

func _draw_minimap_surface(map_x: float, map_y: float, map_size: float, center: Vector2, map_rect: Rect2, font: Font):

    if not player or not is_instance_valid(player):
        return
    var player_pos = player.global_position
    var surface_range: float = 5000.0
    var mm_scale = (map_size * 0.4) / surface_range


    draw_rect(Rect2(map_x + 1, map_y + 1, map_size - 2, map_size - 2), Color(0.15, 0.12, 0.08, 0.2))


    draw_line(Vector2(map_x + 4, center.y), Vector2(map_x + map_size - 4, center.y), Color(0.15, 0.18, 0.22, 0.3), 0.5)
    draw_line(Vector2(center.x, map_y + 4), Vector2(center.x, map_y + map_size - 4), Color(0.15, 0.18, 0.22, 0.3), 0.5)


    var bound_r = surface_range * mm_scale
    var origin_mm = center + (Vector2.ZERO - player_pos) * mm_scale
    draw_arc(origin_mm, bound_r, 0, TAU, 16, Color(0.4, 0.3, 0.2, 0.3), 1.0)


    for poi_node in get_tree().get_nodes_in_group("pois"):
        if not is_instance_valid(poi_node):
            continue
        var pp = center + (poi_node.global_position - player_pos) * mm_scale
        if not map_rect.has_point(pp):
            continue
        var poi_type_str: String = poi_node.poi_type if "poi_type" in poi_node else "anomaly"
        var pc = Color(0.4, 0.7, 0.95)
        match poi_type_str:
            "station": pc = Color(0.3, 0.9, 0.4)
            "resource": pc = Color(0.9, 0.8, 0.3)
            "anomaly": pc = Color(0.7, 0.4, 1.0)
        draw_circle(pp, 2.5, pc)


    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e):
            continue
        var ep = center + (e.global_position - player_pos) * mm_scale
        if map_rect.has_point(ep):
            draw_circle(ep, 2.0, Color(1.0, 0.3, 0.2, 0.85))


    var fwd = Vector2.from_angle(player.rotation)
    var p1 = center + fwd * 5
    var p2 = center + fwd.rotated(2.5) * 4
    var p3 = center + fwd.rotated(-2.5) * 4
    draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.3, 1.0, 0.5))
    draw_line(p1, p2, Color(0.5, 1.0, 0.7, 0.6), 0.8)
    draw_line(p1, p3, Color(0.5, 1.0, 0.7, 0.6), 0.8)


    draw_string(font, Vector2(map_x + 4, map_y + 12), "SURFACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.5, 0.4, 0.8))

func _draw_crosshair():
    var main = get_tree().current_scene
    if main and (main.builder_open or main.star_map_open or main.event_open or main.editor_open or main.creative_mode_active):
        return
    var aim_pos: Vector2
    if GameManager.using_controller and player and is_instance_valid(player):

        var rstick = GameManager.controller_aim
        if rstick.length() > 0.1:
            aim_pos = size * 0.5 + rstick.normalized() * 120.0
        else:

            aim_pos = size * 0.5 + Vector2.from_angle(player.rotation) * 80.0
    else:
        aim_pos = get_local_mouse_position()
    var cr = 12.0
    var cc = Color(0.5, 0.7, 0.9, 0.3)

    draw_line(aim_pos + Vector2( - cr, 0), aim_pos + Vector2( - cr * 0.45, 0), cc, 1.0)
    draw_line(aim_pos + Vector2(cr, 0), aim_pos + Vector2(cr * 0.45, 0), cc, 1.0)
    draw_line(aim_pos + Vector2(0, - cr), aim_pos + Vector2(0, - cr * 0.45), cc, 1.0)
    draw_line(aim_pos + Vector2(0, cr), aim_pos + Vector2(0, cr * 0.45), cc, 1.0)

    draw_circle(aim_pos, 1.5, Color(cc, cc.a * 0.6))

    draw_arc(aim_pos, cr * 0.8, 0, TAU, 16, Color(cc, cc.a * 0.15), 0.5)

func _draw_weapon_bar(_font: Font, p_src: Node):
    if not p_src:
        return

    var colors = [
        Color(0.9, 0.35, 0.3),
        Color(0.35, 0.85, 0.4),
        Color(0.7, 0.35, 0.9),
        Color(0.9, 0.8, 0.2),
    ]
    var keys = ["1", "2", "3", "Tab"]

    # --- Gather slot data ---
    var slot_names: Array = ["", "", "", ""]
    var slot_counts: Array = [0, 0, 0, 0]
    var slot_subtypes: Array = ["", "", "", ""]
    # "none", "heat", "cooldown"
    var slot_indicator: Array = ["none", "none", "none", "none"]
    # For cooldown slots: array of {remaining, max_cd}
    var slot_cooldowns: Array = [[], [], [], []]

    # Slot 0: Primary (key 1)
    if "primary_group_keys" in p_src and not p_src.primary_group_keys.is_empty():
        var gidx = clampi(p_src.active_primary_idx, 0, p_src.primary_group_keys.size() - 1)
        var st = p_src.primary_group_keys[gidx]
        slot_subtypes[0] = st
        for w in p_src.weapon_modules:
            if w.get("subtype", "") == st:
                slot_names[0] = w.get("name", st.to_upper())
                slot_counts[0] += 1
        if slot_names[0] == "":
            slot_names[0] = st.to_upper()
        if st == "energy":
            slot_indicator[0] = "heat"

    # Slot 1: Secondary (key 2)
    if "secondary_group_keys" in p_src and not p_src.secondary_group_keys.is_empty():
        var gidx = clampi(p_src.active_secondary_idx, 0, p_src.secondary_group_keys.size() - 1)
        var st = p_src.secondary_group_keys[gidx]
        slot_subtypes[1] = st
        var sec_cds: Array = []
        for i in p_src.secondary_weapons.size():
            if p_src.secondary_weapons[i].get("subtype", "") == st:
                if slot_names[1] == "":
                    slot_names[1] = p_src.secondary_weapons[i].get("name", st.to_upper())
                slot_counts[1] += 1
                sec_cds.append({"remaining": p_src.secondary_cooldowns.get(i, 0.0), "max_cd": p_src.secondary_weapons[i].get("fire_rate", 1.0)})
        if slot_names[1] == "":
            slot_names[1] = st.to_upper()
        if st == "lance" or st == "beam":
            slot_indicator[1] = "heat"
        else:
            slot_indicator[1] = "cooldown"
            slot_cooldowns[1] = sec_cds

    # Slot 2: Special (key 3)
    if "special_group_keys" in p_src and not p_src.special_group_keys.is_empty():
        var gidx = clampi(p_src.active_special_idx, 0, p_src.special_group_keys.size() - 1)
        var st = p_src.special_group_keys[gidx]
        slot_subtypes[2] = st
        var spc_cds: Array = []
        for i in p_src.special_weapons.size():
            if p_src.special_weapons[i].get("subtype", "") == st:
                if slot_names[2] == "":
                    slot_names[2] = p_src.special_weapons[i].get("name", st.to_upper())
                slot_counts[2] += 1
                spc_cds.append({"remaining": p_src.special_cooldowns.get(i, 0.0), "max_cd": p_src.special_weapons[i].get("fire_rate", 1.0)})
        if slot_names[2] == "":
            slot_names[2] = st.to_upper()
        slot_indicator[2] = "cooldown"
        slot_cooldowns[2] = spc_cds

    # Slot 3: Power (Tab)
    slot_names[3] = PRESET_NAMES[p_src.power_preset] if p_src.power_preset < PRESET_NAMES.size() else "?"

    # --- Nebula weapon bar: icon slots + cooldown/heat sweep + ∞ ammo + name ---
    # Space weapons aren't ammo-counted (energy/heat + per-module cooldowns), so
    # the ammo readout is ∞; the cooldown sweep reflects heat or the longest
    # remaining module cooldown.
    var slots: Array = []
    for si in 4:
        var cd := 0.0
        if slot_indicator[si] == "heat" and "weapon_heat" in p_src:
            var heat = p_src.weapon_heat.get(slot_subtypes[si], 0.0)
            var threshold = p_src.overheat_threshold if "overheat_threshold" in p_src else 100.0
            cd = clampf(heat / maxf(threshold, 1.0), 0.0, 1.0)
        elif slot_indicator[si] == "cooldown":
            for cdd in slot_cooldowns[si]:
                var fr := float(cdd.get("remaining", 0.0)) / maxf(float(cdd.get("max_cd", 1.0)), 0.01)
                cd = maxf(cd, clampf(fr, 0.0, 1.0))
        var slot := {
            "key": str(keys[si]),
            "tex": NebulaHud.icon(_weapon_icon(str(slot_subtypes[si]), str(slot_names[si]), si)),
            "glow": colors[si],
            "cd": cd,
            "name": str(slot_names[si]) if slot_names[si] != "" else "--",
        }
        if si < 3:
            slot["ammo"] = -1
            slot["ammo_max"] = -1
        slots.append(slot)
    NebulaHud.draw_ability_bar(self, size.x * 0.5, size.y - 132.0, "Weapons", slots, 52.0, true)


# Maps a Space weapon subtype/name to a HUD icon.
func _weapon_icon(subtype: String, wname: String, slot: int) -> String:
    var s := (subtype + " " + wname).to_lower()
    if s.findn("plasma") >= 0 or s.findn("crystal") >= 0:
        return "crystal"
    if s.findn("missile") >= 0 or s.findn("rocket") >= 0 or s.findn("torpedo") >= 0:
        return "comet"
    if s.findn("mine") >= 0 or s.findn("bomb") >= 0 or s.findn("flak") >= 0:
        return "burst"
    if s.findn("fire") >= 0 or s.findn("flame") >= 0 or s.findn("incend") >= 0:
        return "fire"
    if s.findn("beam") >= 0 or s.findn("lance") >= 0 or s.findn("laser") >= 0 or s.findn("energy") >= 0 or s.findn("pulse") >= 0:
        return "bolt"
    if slot == 3:
        return "sun"
    return "star"

func _draw_radial_menu(font: Font, p_src: Node):
    if not p_src or not "radial_open" in p_src:
        return
    if p_src.radial_open < 0 or p_src.radial_options.is_empty():
        return
    var options: Array = p_src.radial_options
    var highlight: int = p_src.radial_highlight
    var current: int = p_src.radial_current
    var slot: int = p_src.radial_open
    var count = options.size()

    var slot_colors = [
        Color(0.9, 0.35, 0.3),
        Color(0.35, 0.85, 0.4),
        Color(0.7, 0.35, 0.9),
        Color(0.9, 0.8, 0.2),
    ]
    var col = slot_colors[slot] if slot < slot_colors.size() else Color(0.7, 0.7, 0.7)

    var center: Vector2 = p_src.radial_origin if "radial_origin" in p_src else size * 0.5
    var radius: float = 120.0
    # Clamp so the radial doesn't go off screen
    center.x = clampf(center.x, radius + 30.0, size.x - radius - 30.0)
    center.y = clampf(center.y, radius + 30.0, size.y - radius - 30.0)

    # Dim background
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.35))

    # Center ring
    draw_arc(center, radius, 0, TAU, 48, Color(col, 0.3), 2.0)
    draw_arc(center, 30.0, 0, TAU, 24, Color(col, 0.15), 1.5)

    # Slice lines and options
    var slice = TAU / count
    for i in count:
        var angle = -PI * 0.5 + slice * i
        var mid_angle = angle + slice * 0.5

        # Slice divider line
        var line_start = center + Vector2.from_angle(angle) * 30.0
        var line_end = center + Vector2.from_angle(angle) * radius
        draw_line(line_start, line_end, Color(col, 0.15), 1.0)

        # Option position
        var opt_pos = center + Vector2.from_angle(mid_angle) * (radius * 0.6)

        # Highlight wedge
        if i == highlight:
            var wedge_pts: PackedVector2Array = PackedVector2Array()
            wedge_pts.append(center + Vector2.from_angle(angle) * 30.0)
            var arc_steps = 12
            for s in arc_steps + 1:
                var a = angle + slice * float(s) / float(arc_steps)
                wedge_pts.append(center + Vector2.from_angle(a) * radius)
            wedge_pts.append(center + Vector2.from_angle(angle + slice) * 30.0)
            draw_colored_polygon(wedge_pts, Color(col, 0.2))

        # Dot
        var dot_r: float = 6.0
        var dot_col = col if i == highlight else Color(col, 0.5)
        if i == current:
            draw_circle(opt_pos, dot_r + 2.0, Color(col, 0.25))
        draw_circle(opt_pos, dot_r, dot_col)

        # Label
        var label_pos = center + Vector2.from_angle(mid_angle) * (radius + 18.0)
        var label = options[i]
        var label_w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        var lx = label_pos.x - label_w * 0.5
        var ly = label_pos.y + 4.0
        var label_col = Color(1.0, 1.0, 1.0, 0.95) if i == highlight else Color(0.7, 0.7, 0.7, 0.7)
        if i == current and i != highlight:
            label_col = Color(col, 0.85)
        var fs = 12 if i == highlight else 11
        draw_string(font, Vector2(lx, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)

func _draw_controls_overlay(font: Font):
    var fade = clampf(test_fly_controls_timer / 2.0, 0.0, 1.0)
    var pw = 340.0
    var ph = 428.0
    var panel_x = size.x - pw - 16.0
    var panel_y = (size.y - ph) * 0.5
    var panel = Rect2(panel_x, panel_y, pw, ph)

    draw_rect(panel, Color(0.02, 0.02, 0.06, 0.85 * fade))
    draw_rect(panel, Color(0.9, 0.4, 0.15, 0.6 * fade), false, 2.0)

    var tx = panel.position.x + 20
    var ty = panel.position.y + 30
    var title_col = Color(1.0, 0.7, 0.3, fade)
    var key_col = Color(0.9, 0.55, 0.2, fade)
    var desc_col = Color(0.7, 0.75, 0.85, fade)
    var lh = 22.0

    draw_string(font, Vector2(panel_x + pw * 0.5 - 55, ty), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, title_col)
    ty += lh + 8

    var controls: Array = []
    if GameManager.using_controller:
        controls = [
            ["%s / %s / %s / %s" % [
                GameManager.get_button_prompt("controller_move_up"),
                GameManager.get_button_prompt("controller_move_left"),
                GameManager.get_button_prompt("controller_move_down"),
                GameManager.get_button_prompt("controller_move_right"),
            ], "Move / Strafe"],
            ["%s / %s / %s / %s" % [
                GameManager.get_button_prompt("controller_aim_up"),
                GameManager.get_button_prompt("controller_aim_left"),
                GameManager.get_button_prompt("controller_aim_down"),
                GameManager.get_button_prompt("controller_aim_right"),
            ], "Aim"],
            [GameManager.get_button_prompt("fire_primary"), "Fire Primary"],
            [GameManager.get_button_prompt("fire_secondary"), "Fire Secondary"],
            [GameManager.get_button_prompt("fire_special"), "Fire Special Weapons"],
            [GameManager.get_button_prompt("boost"), "Boost"],
            [GameManager.get_button_prompt("handbrake"), "Handbrake / Orbit Lock"],
            [GameManager.get_button_prompt("fire_harpoon"), "Wretched Harpoon"],
            [GameManager.get_button_prompt("scan"), "Shield Supercharger"],
            [GameManager.get_button_prompt("interact"), "Interact"],
            [GameManager.get_button_prompt("cycle_primary"), "Cycle Primary Weapons"],
            [GameManager.get_button_prompt("cycle_secondary"), "Cycle Secondary Weapons"],
            [GameManager.get_button_prompt("cycle_special"), "Cycle Special Weapons"],
            [GameManager.get_button_prompt("cycle_power"), "Cycle Power Preset"],
            [GameManager.get_button_prompt("toggle_star_map"), "Sector Map"],
        ]
    else:
        controls = [
            ["%s / %s / %s / %s" % [
                GameManager.get_button_prompt("move_up"),
                GameManager.get_button_prompt("move_left"),
                GameManager.get_button_prompt("move_down"),
                GameManager.get_button_prompt("move_right"),
            ], "Move / Strafe"],
            ["Mouse", "Aim"],
            [GameManager.get_button_prompt("fire_primary"), "Fire Primary"],
            [GameManager.get_button_prompt("fire_secondary"), "Fire Secondary"],
            [GameManager.get_button_prompt("fire_special"), "Fire Special Weapons"],
            [GameManager.get_button_prompt("boost"), "Boost"],
            [GameManager.get_button_prompt("handbrake"), "Handbrake / Orbit Lock"],
            [GameManager.get_button_prompt("fire_harpoon"), "Wretched Harpoon"],
            [GameManager.get_button_prompt("scan"), "Shield Supercharger"],
            [GameManager.get_button_prompt("interact"), "Interact"],
            [GameManager.get_button_prompt("cycle_primary"), "Cycle Primary Weapons"],
            [GameManager.get_button_prompt("cycle_secondary"), "Cycle Secondary Weapons"],
            [GameManager.get_button_prompt("cycle_special"), "Cycle Special Weapons"],
            [GameManager.get_button_prompt("cycle_power"), "Cycle Power Preset"],
            ["Mouse Scroll", "Zoom In/Out"],
        ]
    for c in controls:
        draw_string(font, Vector2(tx, ty), c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, key_col)
        draw_string(font, Vector2(tx + 130, ty), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, desc_col)
        ty += lh

    ty += 6
    var countdown = ceili(test_fly_controls_timer)
    var wave_col = Color(0.6, 0.7, 0.9, fade * (sin(Time.get_ticks_msec() * 0.003) * 0.2 + 0.8))
    draw_string(font, Vector2(panel_x + pw * 0.5 - 80, ty), "First wave in %ds" % countdown, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, wave_col)
