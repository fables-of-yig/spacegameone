extends Control





signal jump_requested(system_id: String)
@warning_ignore("unused_signal")
signal waypoint_set(world_pos: Vector2)
signal closed

var systems: Dictionary = {}
var current_system: String = ""
var selected_system: String = ""
var hovered_system: String = ""


const NODE_RADIUS: float = 18.0
const NODE_RADIUS_HOVER: float = 22.0
const LANE_COLOR: Color = Color(0.3, 0.35, 0.5, 0.4)
const LANE_COLOR_ACTIVE: Color = Color(0.4, 0.6, 1.0, 0.6)
const SELECT_COLOR: Color = Color(1.0, 0.85, 0.2, 0.9)
const CURRENT_COLOR: Color = Color(0.3, 1.0, 0.5, 0.9)
const BG_COLOR: Color = Color(0.02, 0.02, 0.06, 0.95)


var map_offset: Vector2 = Vector2.ZERO
var map_scale: float = 1.0
var _base_scale: float = 1.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 0.15


var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _offset_at_drag_start: Vector2 = Vector2.ZERO


var pulse_time: float = 0.0
var _skip_close_frame: bool = false


var info_scroll: float = 0.0


var player_data_pos: Vector2 = Vector2.ZERO

func _ready():
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_STOP
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)

var _known_systems: Dictionary = {}

func open_map(sys_data: Dictionary, current: String, player_pos: Vector2 = Vector2.ZERO):
    systems = sys_data
    current_system = current
    player_data_pos = player_pos
    selected_system = ""
    hovered_system = ""
    visible = true
    _skip_close_frame = true
    _dragging = false
    _build_known_systems()
    _center_on_current()
    queue_redraw()

func _build_known_systems():

    _known_systems.clear()

    _known_systems[current_system] = true

    for sys_id in GameManager.visited_systems:
        _known_systems[sys_id] = true
        var sys = systems.get(sys_id, {})
        for conn_id in sys.get("connections", []):
            if systems.has(conn_id):
                _known_systems[conn_id] = true

    var cur = systems.get(current_system, {})
    for conn_id in cur.get("connections", []):
        if systems.has(conn_id):
            _known_systems[conn_id] = true

func close_map():
    visible = false
    closed.emit()

func _center_on_current():

    if systems.is_empty():
        return
    var current_pos = _get_sys_data_pos(current_system)

    var max_neighbor_dist: float = 200.0
    var sys = systems.get(current_system, {})
    for conn_id in sys.get("connections", []):
        if systems.has(conn_id):
            var neighbor_pos = _get_sys_data_pos(conn_id)
            var d = current_pos.distance_to(neighbor_pos)
            max_neighbor_dist = maxf(max_neighbor_dist, d)

    for conn_id in sys.get("connections", []):
        var conn_sys = systems.get(conn_id, {})
        for conn2_id in conn_sys.get("connections", []):
            if systems.has(conn2_id):
                var p2 = _get_sys_data_pos(conn2_id)
                var d2 = current_pos.distance_to(p2)
                max_neighbor_dist = maxf(max_neighbor_dist, d2)


    var view_half = minf((size.x - 340.0) * 0.5, size.y * 0.5) - 80.0
    _base_scale = view_half / maxf(max_neighbor_dist, 100.0)
    map_scale = _base_scale


    var view_center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
    map_offset = view_center - current_pos * map_scale

func _get_sys_data_pos(sys_id: String) -> Vector2:
    var sys = systems.get(sys_id, {})
    var p = sys.get("position", [0, 0])
    return Vector2(p[0], p[1])

func _sys_screen_pos(sys_id: String) -> Vector2:
    return _get_sys_data_pos(sys_id) * map_scale + map_offset

func _screen_to_data(screen_pos: Vector2) -> Vector2:
    return (screen_pos - map_offset) / map_scale

func _process(delta: float):
    if not visible:
        return

    if _skip_close_frame:
        _skip_close_frame = false
    else:
        if Input.is_action_just_pressed("toggle_star_map"):
            close_map()
            return


    if GameManager.using_controller:
        var left_stick := GameManager.poll_left_stick()
        if left_stick.length() > GameManager.STICK_DEADZONE:
            map_offset += left_stick * -400.0 * delta

        var ry = GameManager.poll_right_stick().y
        if absf(ry) > GameManager.STICK_DEADZONE:
            var center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
            _zoom_at(center, - ry * ZOOM_STEP * delta * 6.0)

        var lt = Input.get_action_strength("fire_secondary")
        var rt = Input.get_action_strength("fire_primary")
        if lt > 0.1:
            var center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
            _zoom_at(center, - lt * ZOOM_STEP * delta * 4.0)
        if rt > 0.1:
            var center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
            _zoom_at(center, rt * ZOOM_STEP * delta * 4.0)

    pulse_time += delta
    queue_redraw()

func _gui_input(event: InputEvent):
    if not visible:
        return

    if event is InputEventMouseMotion:
        _update_hover(event.position)
        if _dragging:
            map_offset = _offset_at_drag_start + (event.position - _drag_start)
            accept_event()

    if event is InputEventMouseButton:
        if event.pressed:
            if event.button_index == MOUSE_BUTTON_LEFT:
                if hovered_system != "":
                    selected_system = hovered_system
                    queue_redraw()

            elif event.button_index == MOUSE_BUTTON_RIGHT:
                if selected_system != "" and selected_system != current_system:
                    if _can_jump_to(selected_system):
                        jump_requested.emit(selected_system)
                        close_map()

            elif event.button_index == MOUSE_BUTTON_MIDDLE:
                _dragging = true
                _drag_start = event.position
                _offset_at_drag_start = map_offset
                accept_event()

            elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
                _zoom_at(event.position, ZOOM_STEP)
                accept_event()

            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                _zoom_at(event.position, - ZOOM_STEP)
                accept_event()
        else:
            if event.button_index == MOUSE_BUTTON_MIDDLE:
                _dragging = false
                accept_event()


    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_H or event.keycode == KEY_HOME:
            _center_on_current()
            accept_event()


    if event is InputEventJoypadButton and event.pressed:
        match event.button_index:
            JOY_BUTTON_A:

                if selected_system != "" and selected_system != current_system and _can_jump_to(selected_system):
                    jump_requested.emit(selected_system)
                    close_map()
                elif hovered_system != "":
                    selected_system = hovered_system
                    queue_redraw()
                accept_event()
            JOY_BUTTON_B:
                close_map()
                accept_event()
            JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
                _cycle_system_dpad(event.button_index)
                accept_event()
            JOY_BUTTON_LEFT_SHOULDER:
                var center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
                _zoom_at(center, - ZOOM_STEP)
                accept_event()
            JOY_BUTTON_RIGHT_SHOULDER:
                var center = Vector2((size.x - 300.0) * 0.5, size.y * 0.5)
                _zoom_at(center, ZOOM_STEP)
                accept_event()
            JOY_BUTTON_Y:
                _center_on_current()
                accept_event()

func _cycle_system_dpad(button: int):

    var reference = selected_system if selected_system != "" else current_system
    var ref_pos = _sys_screen_pos(reference)
    var dir: = Vector2.ZERO
    match button:
        JOY_BUTTON_DPAD_UP: dir = Vector2.UP
        JOY_BUTTON_DPAD_DOWN: dir = Vector2.DOWN
        JOY_BUTTON_DPAD_LEFT: dir = Vector2.LEFT
        JOY_BUTTON_DPAD_RIGHT: dir = Vector2.RIGHT
    var best_id: = ""
    var best_score: float = INF
    for sys_id in _known_systems:
        if sys_id == reference:
            continue
        var sp = _sys_screen_pos(sys_id)
        var delta_vec = sp - ref_pos
        var dist = delta_vec.length()
        if dist < 1.0:
            continue
        var alignment = delta_vec.normalized().dot(dir)
        if alignment < 0.3:
            continue

        var score = dist * (1.0 - alignment * 0.5)
        if score < best_score:
            best_score = score
            best_id = sys_id
    if best_id != "":
        selected_system = best_id
        hovered_system = best_id
        queue_redraw()

func _zoom_at(mouse_pos: Vector2, zoom_delta: float):

    var old_scale = map_scale
    map_scale = clampf(map_scale * (1.0 + zoom_delta), ZOOM_MIN, ZOOM_MAX)

    var data_under_mouse = (mouse_pos - map_offset) / old_scale
    map_offset = mouse_pos - data_under_mouse * map_scale

func _update_hover(mouse_pos: Vector2):
    hovered_system = ""
    var best_dist = (NODE_RADIUS_HOVER + 5.0)
    for sys_id in _known_systems:
        var sp = _sys_screen_pos(sys_id)

        if sp.x < -50 or sp.x > size.x + 50 or sp.y < -50 or sp.y > size.y + 50:
            continue
        var d = mouse_pos.distance_to(sp)
        if d < best_dist:
            best_dist = d
            hovered_system = sys_id

func _can_jump_to(target_id: String) -> bool:
    var current = systems.get(current_system, {})
    var connections: Array = current.get("connections", [])
    if target_id not in connections:
        return false
    return target_id in GameManager.visited_systems

func _is_connected(target_id: String) -> bool:
    var current = systems.get(current_system, {})
    return target_id in current.get("connections", [])

func _draw():

    draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)

    var font = ThemeDB.fallback_font


    draw_string(font, Vector2(size.x * 0.5 - 60, 35), "SECTOR MAP", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(0.7, 0.8, 1.0))


    var hint: String
    if GameManager.using_controller:
        hint = "A: Select/Jump   B: Close   D-pad: Navigate   Stick: Pan   LB/RB: Zoom   Y: Recenter"
    else:
        hint = "LMB: Select   RMB: Jump   Scroll: Zoom   MMB: Pan   H: Recenter   M/Esc: Close"
    draw_string(font, Vector2(20, size.y - 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.42, 0.5))

    if systems.is_empty():
        return

    var current_connections: Array = systems.get(current_system, {}).get("connections", [])

    var map_area = Rect2(0, 0, size.x - 300, size.y)


    var drawn_lanes: Dictionary = {}
    for sys_id in _known_systems:
        var sys = systems.get(sys_id, {})
        var from_pos = _sys_screen_pos(sys_id)
        for conn_id in sys.get("connections", []):
            if not _known_systems.has(conn_id):
                continue
            var lane_key = [sys_id, conn_id]
            lane_key.sort()
            var key_str = str(lane_key)
            if drawn_lanes.has(key_str):
                continue
            drawn_lanes[key_str] = true

            var to_pos = _sys_screen_pos(conn_id)


            if not _line_in_rect(from_pos, to_pos, map_area):
                continue


            var lane_col = LANE_COLOR
            var lane_width = 1.5
            var both_visited = sys_id in GameManager.visited_systems and conn_id in GameManager.visited_systems
            var touches_current = sys_id == current_system or conn_id == current_system

            if touches_current:
                lane_col = LANE_COLOR_ACTIVE if both_visited else Color(0.5, 0.35, 0.15, 0.4)
            elif not both_visited:
                lane_col = Color(0.25, 0.2, 0.15, 0.2)

            if selected_system != "":
                if (sys_id == current_system and conn_id == selected_system) or \
(conn_id == current_system and sys_id == selected_system):
                    var can_jump = selected_system in GameManager.visited_systems
                    lane_col = SELECT_COLOR * Color(1, 1, 1, 0.6) if can_jump else Color(0.9, 0.5, 0.15, 0.5)
                    lane_width = 2.5

            draw_line(from_pos, to_pos, lane_col, lane_width)


            var lane_len = from_pos.distance_to(to_pos)
            var dot_count = int(lane_len / 30.0)
            for i in range(1, dot_count):
                var t = float(i) / float(dot_count)
                var dp = from_pos.lerp(to_pos, t)
                draw_circle(dp, 1.0, lane_col * Color(1, 1, 1, 0.5))


    for sys_id in _known_systems:
        var sys = systems.get(sys_id, {})
        var sp = _sys_screen_pos(sys_id)


        if sp.x < -60 or sp.x > size.x - 260 or sp.y < -40 or sp.y > size.y + 40:
            continue

        var sc = sys.get("star_color", [1, 1, 1])
        var star_col = Color(sc[0], sc[1], sc[2])
        var is_current = sys_id == current_system
        var is_selected = sys_id == selected_system
        var is_hovered = sys_id == hovered_system
        var sys_is_connected = sys_id in current_connections
        var is_visited = sys_id in GameManager.visited_systems
        var is_jumpable = sys_is_connected and is_visited

        var r = NODE_RADIUS
        if is_hovered:
            r = NODE_RADIUS_HOVER


        if is_jumpable and not is_current:
            var ring_alpha = 0.3 + sin(pulse_time * 2.0) * 0.15
            draw_arc(sp, r + 6, 0, TAU, 24, Color(0.4, 0.6, 1.0, ring_alpha), 1.5)
        elif sys_is_connected and not is_visited and not is_current:
            var ring_alpha = 0.15 + sin(pulse_time * 1.5) * 0.1
            for seg in 8:
                var a0 = float(seg) / 8.0 * TAU
                var a1 = a0 + TAU / 16.0
                draw_arc(sp, r + 6, a0, a1, 3, Color(0.6, 0.4, 0.2, ring_alpha), 1.5)


        var faction = sys.get("faction", "independent")
        var factions_data = DataManager.galaxy_data.get("factions", {})
        var faction_info = factions_data.get(faction, {})
        var faction_color_arr = faction_info.get("color", [0.5, 0.5, 0.55])
        var faction_col = Color(faction_color_arr[0], faction_color_arr[1], faction_color_arr[2])
        draw_circle(sp, r + 2, Color(faction_col, 0.2))
        draw_arc(sp, r + 1, 0, TAU, 24, Color(faction_col, 0.5), 1.5)


        draw_circle(sp, r, Color(0.08, 0.08, 0.12))

        if is_visited or is_current:

            var glow_r = r * (0.7 + sin(pulse_time * 1.5 + sp.x * 0.01) * 0.1)
            draw_circle(sp, glow_r, star_col * Color(1, 1, 1, 0.3))

            draw_circle(sp, r * 0.4, star_col)
        else:

            draw_circle(sp, r * 0.4, star_col * Color(1, 1, 1, 0.15))
            draw_string(font, sp + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.45, 0.35))


        if is_current:
            draw_arc(sp, r + 3, 0, TAU, 24, CURRENT_COLOR, 2.0)
            draw_circle(sp + Vector2(0, - r - 10), 3.0, CURRENT_COLOR)


        if is_selected:
            draw_arc(sp, r + 4, 0, TAU, 24, SELECT_COLOR, 2.5)


        if is_visited or is_current:
            var threat = sys.get("threat_level", 1)
            var pip_y = sp.y + r + 8
            var pip_start_x = sp.x - (threat - 1) * 4.0
            for i in threat:
                var pip_col = Color(0.3, 0.8, 0.3) if threat <= 2 else (Color(1.0, 0.7, 0.2) if threat <= 3 else Color(1.0, 0.3, 0.2))
                draw_circle(Vector2(pip_start_x + i * 8.0, pip_y), 2.5, pip_col)


        var name_str: String = sys.get("name", sys_id) if (is_visited or is_current) else "???"
        var name_col = Color(0.6, 0.65, 0.75)
        if is_current:
            name_col = CURRENT_COLOR
        elif is_selected and is_visited:
            name_col = SELECT_COLOR
        elif is_hovered:
            name_col = Color(0.85, 0.85, 0.95) if is_visited else Color(0.6, 0.5, 0.4)
        elif not is_visited:
            name_col = Color(0.35, 0.3, 0.25)
        draw_string(font, Vector2(sp.x - name_str.length() * 3.5, sp.y + r + 22), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, name_col)


    var player_screen = player_data_pos * map_scale + map_offset
    var ship_col = Color(0.3, 1.0, 0.5, 0.9)
    var ship_pulse = 0.6 + sin(pulse_time * 3.0) * 0.4
    draw_circle(player_screen, 8.0, Color(ship_col, 0.08 * ship_pulse))
    var sd = 5.0
    var ship_pts = PackedVector2Array([
        player_screen + Vector2(0, - sd), 
        player_screen + Vector2(sd * 0.6, 0), 
        player_screen + Vector2(0, sd), 
        player_screen + Vector2( - sd * 0.6, 0), 
    ])
    draw_colored_polygon(ship_pts, Color(ship_col, 0.9))
    draw_polyline(PackedVector2Array([ship_pts[0], ship_pts[1], ship_pts[2], ship_pts[3], ship_pts[0]]), 
        Color(ship_col, 0.5), 1.0)


    var zoom_pct = int(map_scale / _base_scale * 100)
    draw_string(font, Vector2(20, 35), "%d%%" % zoom_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.45, 0.55))


    var legend_factions = DataManager.galaxy_data.get("factions", {})
    if not legend_factions.is_empty():
        var legend_y = size.y - 40.0 - legend_factions.size() * 14.0
        draw_rect(Rect2(10, legend_y - 5, 140, legend_factions.size() * 14.0 + 10), Color(0, 0, 0, 0.6))
        var ly = legend_y
        for fid in legend_factions:
            var fd = legend_factions[fid]
            var fc = fd.get("color", [0.5, 0.5, 0.55])
            var fcol = Color(fc[0], fc[1], fc[2])
            draw_circle(Vector2(22, ly + 5), 4.0, fcol)
            draw_string(font, Vector2(30, ly + 9), fd.get("name", fid), HORIZONTAL_ALIGNMENT_LEFT, 110, 9, Color(0.7, 0.7, 0.75))
            ly += 14.0


    _draw_info_panel(font, 14)


func _clamp_to_edge(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:

    var dir = to - from
    var t_min = INF

    if dir.x != 0:
        var t = (rect.position.x - from.x) / dir.x
        if t > 0:
            var y = from.y + dir.y * t
            if y >= rect.position.y and y <= rect.position.y + rect.size.y:
                t_min = minf(t_min, t)

    if dir.x != 0:
        var t = (rect.position.x + rect.size.x - from.x) / dir.x
        if t > 0:
            var y = from.y + dir.y * t
            if y >= rect.position.y and y <= rect.position.y + rect.size.y:
                t_min = minf(t_min, t)

    if dir.y != 0:
        var t = (rect.position.y - from.y) / dir.y
        if t > 0:
            var x = from.x + dir.x * t
            if x >= rect.position.x and x <= rect.position.x + rect.size.x:
                t_min = minf(t_min, t)

    if dir.y != 0:
        var t = (rect.position.y + rect.size.y - from.y) / dir.y
        if t > 0:
            var x = from.x + dir.x * t
            if x >= rect.position.x and x <= rect.position.x + rect.size.x:
                t_min = minf(t_min, t)
    if t_min == INF:
        return to
    return from + dir * t_min

func _line_in_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:

    var expanded = rect.grow(60)
    return expanded.has_point(a) or expanded.has_point(b) or \
(a.x < expanded.position.x and b.x > expanded.position.x + expanded.size.x) or \
(a.y < expanded.position.y and b.y > expanded.position.y + expanded.size.y)

func _draw_info_panel(font: Font, font_size: int):
    var panel_x = size.x - 300.0
    var panel_w = 280.0
    var panel_y = 60.0


    draw_rect(Rect2(panel_x, panel_y, panel_w, size.y - 120), Color(0.05, 0.05, 0.1, 0.9))
    draw_rect(Rect2(panel_x, panel_y, panel_w, size.y - 120), Color(0.3, 0.4, 0.6, 0.3), false, 1.0)

    var tx = panel_x + 15.0
    var ty = panel_y + 30.0
    var line_h = 20.0

    var display_id = selected_system if selected_system != "" else current_system
    if display_id == "" or not systems.has(display_id):
        draw_string(font, Vector2(tx, ty), "No system selected", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.6))
        return

    var sys = systems[display_id]
    var sc = sys.get("star_color", [1, 1, 1])
    var star_col = Color(sc[0], sc[1], sc[2])
    var is_known = display_id in GameManager.visited_systems or display_id == current_system


    if is_known:
        draw_string(font, Vector2(tx, ty), sys.get("name", display_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, star_col)
    else:
        draw_string(font, Vector2(tx, ty), "UNEXPLORED SYSTEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.45, 0.25))
    ty += line_h + 4

    if not is_known:
        draw_string(font, Vector2(tx, ty), "Star class: Unknown", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.45, 0.4, 0.35))
        ty += line_h
        draw_string(font, Vector2(tx, ty), "Threat: Unknown", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.45, 0.4, 0.35))
        ty += line_h + 8
        draw_line(Vector2(tx, ty), Vector2(tx + panel_w - 30, ty), Color(0.3, 0.3, 0.4), 1.0)
        ty += 14
        draw_string(font, Vector2(tx, ty), "No beacon established.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.45, 0.35))
        ty += line_h
        draw_string(font, Vector2(tx, ty), "Travel through open space to", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.42, 0.4))
        ty += 16
        draw_string(font, Vector2(tx, ty), "discover this system.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.42, 0.4))
        ty += line_h + 8

    if is_known:

        draw_string(font, Vector2(tx, ty), "Class: " + sys.get("star_class", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.6, 0.7))
        ty += line_h


        var threat = sys.get("threat_level", 1)
        var threat_label = ["", "LOW", "MODERATE", "HIGH", "DANGEROUS", "EXTREME"]
        var threat_col = Color(0.3, 0.8, 0.3) if threat <= 2 else (Color(1.0, 0.7, 0.2) if threat <= 3 else Color(1.0, 0.3, 0.2))
        draw_string(font, Vector2(tx, ty), "Threat: " + threat_label[clampi(threat, 1, 5)], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, threat_col)
        ty += line_h


        var panel_faction = sys.get("faction", "unknown")
        var panel_faction_str: String = panel_faction.replace("_", " ").capitalize()
        var panel_factions_data = DataManager.galaxy_data.get("factions", {})
        var panel_faction_info = panel_factions_data.get(panel_faction, {})
        var panel_fc = panel_faction_info.get("color", [0.6, 0.6, 0.7])
        var panel_faction_col = Color(panel_fc[0], panel_fc[1], panel_fc[2])
        var panel_faction_name: String = panel_faction_info.get("name", panel_faction_str)
        draw_string(font, Vector2(tx, ty), "Faction: ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.6, 0.7))
        draw_string(font, Vector2(tx + 56, ty), panel_faction_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, panel_faction_col)
        ty += line_h + 8


    if is_known:
        draw_line(Vector2(tx, ty), Vector2(tx + panel_w - 30, ty), Color(0.3, 0.3, 0.4), 1.0)
        ty += 14

        var desc: String = sys.get("description", "")
        var words = desc.split(" ")
        var line_text = ""
        var max_line_w = panel_w - 30
        for word in words:
            var test = line_text + (" " if line_text != "" else "") + word
            if test.length() * 7.5 > max_line_w and line_text != "":
                draw_string(font, Vector2(tx, ty), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.58, 0.65))
                ty += line_h - 2
                line_text = word
            else:
                line_text = test
        if line_text != "":
            draw_string(font, Vector2(tx, ty), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.58, 0.65))
            ty += line_h + 4


        ty += 6
        draw_string(font, Vector2(tx, ty), "POINTS OF INTEREST", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.75, 0.85))
        ty += line_h + 2

        var pois: Array = sys.get("pois", [])
        for poi in pois:
            var poi_name: String = poi.get("name", "Unknown")
            var poi_type: String = poi.get("type", "unknown")
            var type_col = Color(0.5, 0.5, 0.5)
            match poi_type:
                "station": type_col = Color(0.3, 0.8, 0.4)
                "hostile_station": type_col = Color(0.9, 0.3, 0.2)
                "salvage": type_col = Color(0.8, 0.7, 0.3)
                "resource": type_col = Color(0.4, 0.7, 0.9)
                "anomaly": type_col = Color(0.7, 0.4, 1.0)
                "ruin": type_col = Color(0.2, 0.8, 0.9)
                "planet": type_col = Color(0.35, 0.75, 0.35)
            draw_rect(Rect2(tx, ty - 9, 8, 8), type_col)
            draw_string(font, Vector2(tx + 14, ty), poi_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.68, 0.75))
            ty += line_h - 2
            var poi_desc: String = poi.get("description", "")
            draw_string(font, Vector2(tx + 14, ty), poi_desc, HORIZONTAL_ALIGNMENT_LEFT, int(max_line_w - 14), 11, Color(0.45, 0.48, 0.55))
            ty += line_h


    if display_id != current_system:
        ty += 12
        draw_line(Vector2(tx, ty), Vector2(tx + panel_w - 30, ty), Color(0.3, 0.3, 0.4), 1.0)
        ty += 18
        var is_visited = display_id in GameManager.visited_systems
        var sys_is_connected = _is_connected(display_id)
        if _can_jump_to(display_id):
            var has_fuel = GameManager.fuel >= 20.0
            var btn_rect = Rect2(tx, ty - 12, panel_w - 30, 28)
            draw_rect(btn_rect, Color(0.15, 0.25, 0.4, 0.8) if has_fuel else Color(0.25, 0.12, 0.1, 0.8))
            draw_rect(btn_rect, Color(0.4, 0.6, 1.0, 0.6) if has_fuel else Color(0.7, 0.3, 0.2, 0.6), false, 1.0)
            if has_fuel:
                var jump_label = "PRESS [A] TO JUMP  (-20 fuel)" if GameManager.using_controller else "RIGHT-CLICK TO JUMP  (-20 fuel)"
                draw_string(font, Vector2(tx + 30, ty + 8), jump_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 1.0))
            else:
                draw_string(font, Vector2(tx + 30, ty + 8), "NOT ENOUGH FUEL  (need 20)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.4, 0.25))
        elif sys_is_connected and not is_visited:
            draw_string(font, Vector2(tx, ty), "UNEXPLORED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.6, 0.2))
            ty += 18
            draw_string(font, Vector2(tx, ty), "Travel to this system to", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.45, 0.35))
            ty += 14
            draw_string(font, Vector2(tx, ty), "discover and establish beacon", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.45, 0.35))
        else:
            draw_string(font, Vector2(tx, ty), "No direct route", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.35, 0.35))
