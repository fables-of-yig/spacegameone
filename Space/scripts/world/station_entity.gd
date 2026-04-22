extends "res://Space/scripts/ship/ship_base.gd"





signal died(station_key: String, pos: Vector2)
@warning_ignore("unused_signal")
signal hailed(station_key: String)


var station_key: String = ""
var station_name: String = "Station"
var station_type: String = "trade"
var station_color: Color = Color(0.55, 0.55, 0.6)


var shield_recharge_delay: float = 5.0
var _shield_recharge_cooldown: float = 0.0


var weapon_modules: Array = []
var weapon_cooldowns: Dictionary = {}
var weapon_range: float = 600.0
var projectile_damage: float = 10.0
var projectile_speed: float = 500.0
var fire_rate: float = 1.2
var combat_target: Node2D = null
var _target_scan_timer: float = 0.0


var hull_radius: int = 7
var _cached_hull_cells: Dictionary = {}


var poi_marker: Node2D = null


var ship_name: String:
    get: return station_name


var _running_light_timer: float = 0.0
var _docking_light_timer: float = 0.0
var _shield_shimmer_timer: float = 0.0
var _redraw_accum: float = 0.0
var _station_extent: float = 40.0

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("station_entities")
    MCELL = 10.0
    _init_collision(40.0)

func setup(data: Dictionary):
    station_key = data.get("station_key", "")
    station_name = data.get("name", data.get("station_key", "Station"))
    faction_id = data.get("faction", "independent")
    station_type = data.get("station_type", "trade")
    hostile = data.get("hostile", false)


    max_health = data.get("max_health", 500.0)
    health = data.get("health", max_health)
    hull_hp = health
    hull_max_hp = max_health
    max_shields = data.get("max_shields", 0.0)
    shields = data.get("shields", max_shields)


    match station_type:
        "trade": station_color = Color(0.45, 0.55, 0.65)
        "military": station_color = Color(0.5, 0.45, 0.55)
        "pirate": station_color = Color(0.6, 0.4, 0.35)
        "science": station_color = Color(0.4, 0.6, 0.55)
        "gateway": station_color = Color(0.55, 0.5, 0.65)
        _: station_color = Color(0.55, 0.55, 0.6)


    ship_color = station_color

    MCELL = 10.0

    var wp = data.get("world_pos", data.get("spawn_point", [0, 0]))
    if wp is Array:
        global_position = Vector2(wp[0], wp[1])
    elif wp is Vector2:
        global_position = wp


    ship_modules = data.get("modules", [])
    hull_radius = data.get("hull_radius", 7)
    _compute_grid_center()
    _rebuild_hull_cache()
    _cache_weapon_modules()


    var extent = _compute_station_extent()
    _station_extent = extent
    _ship_extent = extent
    ship_size = extent
    if _cached_hull_contour.size() >= 3:
        var hull_pts = Geometry2D.convex_hull(_cached_hull_contour)
        if hull_pts.size() >= 3:
            var poly_shape = ConvexPolygonShape2D.new()
            poly_shape.points = hull_pts
            if _col_shape:
                _col_shape.shape = poly_shape
            else:
                _init_collision(extent)
                _col_shape.shape = poly_shape
        else:
            _update_collision_radius(extent)
    else:
        _update_collision_radius(extent)

    _apply_hostility()

func _compute_station_extent() -> float:
    var max_dist: float = 20.0

    var hull_cells: Array = HexUtil.generate_hex_disc(hull_radius)
    for cell in hull_cells:
        var fp = _hex_to_local(cell)
        max_dist = maxf(max_dist, fp.length() + MCELL)
    return max_dist

func _cache_weapon_modules():

    weapon_modules.clear()
    weapon_cooldowns.clear()
    for i in ship_modules.size():
        var mod = ship_modules[i]
        var mdata = mod.get("data", {})
        if mdata.get("type", "") == "weapon":
            weapon_modules.append(i)
            weapon_cooldowns[i] = 0.0





func _rebuild_hull_cache():


    _cached_all_cells.clear()
    _cached_hull_cells.clear()
    _cached_cell_corners.clear()
    _cached_cell_draws.clear()


    for mod in ship_modules:
        var hex_cells = GameManager.get_mod_hex_cells(mod)
        for hcell in hex_cells:
            _cached_all_cells[hcell] = mod


    var full_hull: Array = HexUtil.generate_hex_disc(hull_radius)
    for hcell in full_hull:
        _cached_hull_cells[hcell] = true
        if not _cached_cell_corners.has(hcell):
            _cached_cell_corners[hcell] = _hex_polygon_local(hcell)

    var nb_map: Array = [
        Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), 
        Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), 
    ]
    _cached_hull_contour = _build_smooth_hull(_cached_hull_cells, nb_map)
    _hull_cache_dirty = false





func take_damage(amount: float, _shield_pierce: float = 0.0, hit_world_pos: Vector2 = Vector2.ZERO):
    if not alive:
        return

    _shield_recharge_cooldown = shield_recharge_delay


    var pierce = amount * _shield_pierce
    var blocked = amount - pierce
    var hull_damage: float = pierce
    if shields > 0 and blocked > 0:
        shields -= blocked
        if shields < 0:
            hull_damage += - shields
            shields = 0
    else:
        hull_damage = amount


    if hull_damage > 0 and hit_world_pos != Vector2.ZERO:
        var cell = _find_hit_cell(hit_world_pos)
        var mod = _find_module_at_cell(cell)
        if not mod.is_empty():
            GameManager.damage_module(mod, hull_damage)
        else:

            var nearest_mod = _find_nearest_module(cell)
            if not nearest_mod.is_empty():
                GameManager.damage_module(nearest_mod, hull_damage)
    elif hull_damage > 0:

        if not ship_modules.is_empty():
            var idx = randi() % ship_modules.size()
            GameManager.damage_module(ship_modules[idx], hull_damage)


    _recompute_health()

    damage_flash = 1.0
    _hull_cache_dirty = true


    if health <= 0:
        _on_death()

func _find_nearest_module(cell: Vector2i) -> Dictionary:

    var best_mod: Dictionary = {}
    var best_dist: float = INF
    var cell_px = HexUtil.hex_to_pixel(cell, MCELL)
    for mod in ship_modules:
        if mod.get("hp", 0) <= 0:
            continue
        var gp = mod.get("grid_pos", [0, 0])
        var gp_v: Vector2i
        if gp is Array:
            gp_v = Vector2i(int(gp[0]), int(gp[1]))
        else:
            gp_v = gp
        var mod_px = HexUtil.hex_to_pixel(gp_v, MCELL)
        var d = cell_px.distance_to(mod_px)
        if d < best_dist:
            best_dist = d
            best_mod = mod
    return best_mod

func _recompute_health():

    var total_hp: float = 0.0
    var total_max: float = 0.0
    for mod in ship_modules:
        total_hp += mod.get("hp", mod.get("max_hp", 40.0))
        total_max += mod.get("max_hp", 40.0)
    health = total_hp
    max_health = total_max
    hull_hp = health
    hull_max_hp = max_health

    if station_key != "" and GameManager.persistent_stations.has(station_key):
        var sdata = GameManager.persistent_stations[station_key]
        sdata["health"] = health
        sdata["max_health"] = max_health
        sdata["shields"] = shields

func _on_death():
    alive = false

    if station_key != "" and GameManager.persistent_stations.has(station_key):
        GameManager.persistent_stations[station_key]["destroyed"] = true
    died.emit(station_key, global_position)

    var explosion_script = load("res://Space/scripts/combat/explosion.gd")
    if explosion_script:
        for i in 5:
            var explosion = Node2D.new()
            explosion.set_script(explosion_script)
            var offset = Vector2(randf_range( - _station_extent * 0.5, _station_extent * 0.5), 
                                randf_range( - _station_extent * 0.5, _station_extent * 0.5))
            explosion.global_position = global_position + offset
            explosion.setup(station_color.lightened(0.3), 25)
            get_parent().add_child(explosion)
    AudioManager.play_sfx("heavy_shot", 0.8, 0.05)
    queue_free()

func _fire_at_target(weapon_idx: int):

    if not combat_target or not is_instance_valid(combat_target):
        return
    if weapon_idx >= ship_modules.size():
        return
    var mod = ship_modules[weapon_idx]
    if mod.get("hp", 0) <= 0:
        return

    var weapon_pos = global_position + _hex_to_local(mod.get("grid_pos", [0, 0])).rotated(rotation)
    var aim_dir = (combat_target.global_position - weapon_pos).normalized()

    var proj_script = load("res://Space/scripts/combat/projectile.gd")
    if proj_script == null:
        return
    var proj = Area2D.new()
    proj.set_script(proj_script)
    proj.source = "enemy"
    proj.direction = aim_dir
    proj.speed = projectile_speed
    proj.damage = projectile_damage
    proj.proj_color = station_color.lightened(0.4)
    proj.rotation = aim_dir.angle()
    get_parent().add_child(proj)
    proj.global_position = weapon_pos + aim_dir * (MCELL + 3)
    AudioManager.play_sfx("laser_fire", 0.15, 0.1)

func _update_combat(delta: float):

    if weapon_modules.is_empty():
        return


    for wi in weapon_cooldowns:
        weapon_cooldowns[wi] = maxf(weapon_cooldowns[wi] - delta, 0.0)


    if not combat_target or not is_instance_valid(combat_target):
        combat_target = null
        _target_scan_timer -= delta
        if _target_scan_timer <= 0:
            _target_scan_timer = 1.5
            _scan_for_targets()

    if not combat_target:
        return

    var dist = global_position.distance_to(combat_target.global_position)
    if dist > weapon_range * 2.0:

        combat_target = null
        return

    if dist > weapon_range:
        return


    for wi in weapon_modules:
        if weapon_cooldowns.get(wi, 0.0) <= 0:
            _fire_at_target(wi)
            weapon_cooldowns[wi] = fire_rate

func _scan_for_targets():

    var closest: Node2D = null
    var closest_dist: float = weapon_range * 2.0

    if hostile:

        var players = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            var d = global_position.distance_to(players[0].global_position)
            if d < closest_dist:
                closest = players[0]
                closest_dist = d
    else:

        for npc in get_tree().get_nodes_in_group("npc_ships"):
            if not npc.alive or not npc.hostile:
                continue
            var d = global_position.distance_to(npc.global_position)
            if d < closest_dist:
                closest_dist = d
                closest = npc

    if closest:
        combat_target = closest





func _physics_process(delta: float):
    if not alive:
        return
    _process_collisions(delta)

    if poi_marker and is_instance_valid(poi_marker):
        global_position = poi_marker.global_position

    damage_flash = maxf(damage_flash - delta * 4.0, 0.0)
    _running_light_timer += delta
    _docking_light_timer += delta
    _shield_shimmer_timer += delta


    if max_shields > 0:
        _shield_recharge_cooldown = maxf(_shield_recharge_cooldown - delta, 0.0)
        if _shield_recharge_cooldown <= 0 and shields < max_shields:
            shields = minf(shields + shield_recharge_rate * delta, max_shields)


    if not weapon_modules.is_empty():
        if hostile or station_type == "military" or station_type == "pirate":
            _update_combat(delta)


    var _sta_cam = get_viewport().get_camera_2d()
    if _sta_cam and global_position.distance_to(_sta_cam.global_position) > 8000:
        return
    _redraw_accum += delta
    if damage_flash > 0 or _hull_cache_dirty or _redraw_accum >= 0.5:
        _redraw_accum = 0.0
        queue_redraw()





func _draw():
    if not alive:
        return
    var time = _docking_light_timer
    var flash_lerp = damage_flash * 0.6


    if _hull_cache_dirty:
        _rebuild_hull_cache()



    var hull_base = station_color * 0.65
    if flash_lerp > 0:
        hull_base = hull_base.lerp(Color.WHITE, flash_lerp)
    if _cached_hull_contour.size() >= 3:
        draw_colored_polygon(_cached_hull_contour, hull_base)
    else:
        for cell in _cached_hull_cells:
            draw_colored_polygon(_cached_cell_corners.get(cell, _hex_polygon_local(cell)), hull_base)


    for mod in ship_modules:
        var mdata = mod.get("data", {})
        var mtype = mdata.get("type", "")
        var tint = _get_type_color(mtype)
        if flash_lerp > 0:
            tint = tint.lerp(Color.WHITE, flash_lerp)
        var fp = _hex_to_local(mod.get("grid_pos", [0, 0]))

        var mod_hp = mod.get("hp", mod.get("max_hp", 40.0))
        var mod_alpha = 0.4 if mod_hp > 0 else 0.1
        draw_circle(fp, MCELL * 0.35, Color(tint, mod_alpha))

        if mod_hp <= 0:
            draw_line(fp + Vector2( - MCELL * 0.25, - MCELL * 0.25), fp + Vector2(MCELL * 0.25, MCELL * 0.25), Color(0.9, 0.2, 0.1, 0.4), 1.0)
            draw_line(fp + Vector2(MCELL * 0.25, - MCELL * 0.25), fp + Vector2( - MCELL * 0.25, MCELL * 0.25), Color(0.9, 0.2, 0.1, 0.4), 1.0)


    if _cached_hull_contour.size() >= 3:
        var outline_col = Color(station_color, 0.5)
        if flash_lerp > 0:
            outline_col = outline_col.lerp(Color.WHITE, flash_lerp)
        var closed = PackedVector2Array(_cached_hull_contour)
        closed.append(_cached_hull_contour[0])
        draw_polyline(closed, Color(outline_col, 0.12), 4.0)
        draw_polyline(closed, outline_col, 1.2)




    for wi in weapon_modules:
        var mod = ship_modules[wi]
        if mod.get("hp", 0) <= 0:
            continue
        var fp = _hex_to_local(mod.get("grid_pos", [0, 0]))
        var turret_angle = time * 0.5 + float(wi) * 1.3
        var turret_dir = Vector2.from_angle(turret_angle)
        var barrel_len = MCELL * 0.6
        draw_line(fp, fp + turret_dir * barrel_len, Color(0.9, 0.3, 0.2, 0.6), 1.5)
        draw_circle(fp, MCELL * 0.2, Color(0.9, 0.3, 0.2, 0.35))


    var dock_pulse = sin(_docking_light_timer * 2.0) * 0.4 + 0.5
    var dock_r = _station_extent * 0.85
    for i in 4:
        var angle = float(i) * TAU / 4.0 + TAU / 8.0
        var dp = Vector2.from_angle(angle) * dock_r
        var dock_col: Color
        match station_type:
            "trade": dock_col = Color(0.2, 0.8, 0.3, dock_pulse * 0.7)
            "military": dock_col = Color(0.8, 0.4, 0.2, dock_pulse * 0.7)
            "pirate": dock_col = Color(0.9, 0.2, 0.15, dock_pulse * 0.7)
            "science": dock_col = Color(0.3, 0.6, 0.9, dock_pulse * 0.7)
            "gateway": dock_col = Color(0.7, 0.5, 0.9, dock_pulse * 0.7)
            _: dock_col = Color(0.5, 0.6, 0.7, dock_pulse * 0.7)
        draw_circle(dp, 2.5, dock_col)

        draw_circle(dp, 5.0, Color(dock_col.r, dock_col.g, dock_col.b, dock_pulse * 0.15))


    if shields > 0 and max_shields > 0:
        var shield_pct = shields / max_shields
        var shimmer = sin(_shield_shimmer_timer * 3.0) * 0.03 + 0.07
        var shield_alpha = shimmer * shield_pct
        draw_arc(Vector2.ZERO, _station_extent + 4.0, 0, TAU, 48, Color(0.3, 0.5, 1.0, shield_alpha), 2.0)

        var arc_start = fmod(_shield_shimmer_timer * 1.5, TAU)
        var arc_len = PI * 0.4
        draw_arc(Vector2.ZERO, _station_extent + 4.0, arc_start, arc_start + arc_len, 12, Color(0.4, 0.6, 1.0, shield_alpha * 2.5), 1.5)


    var port_phase = sin(_running_light_timer * 1.5) * 0.5 + 0.5
    var nav_r = _station_extent * 0.7
    draw_circle(Vector2(0, - nav_r), 2.0, Color(1.0, 0.15, 0.1, port_phase * 0.8))
    draw_circle(Vector2(0, nav_r), 2.0, Color(0.1, 1.0, 0.2, port_phase * 0.8))

    if fmod(_running_light_timer, 3.0) < 0.15:
        draw_circle(Vector2(nav_r, 0), 1.5, Color(1.0, 1.0, 1.0, 0.9))


    if health < max_health:
        var hp_pct = health / max_health
        var bar_w = _station_extent * 1.5
        var bar_y = _station_extent + 10.0

        if max_shields > 0:
            var sp = shields / max_shields
            draw_rect(Rect2( - bar_w * 0.5, bar_y - 4, bar_w, 2), Color(0.05, 0.05, 0.1))
            draw_rect(Rect2( - bar_w * 0.5, bar_y - 4, bar_w * sp, 2), Color(0.3, 0.5, 1.0))

        draw_rect(Rect2( - bar_w * 0.5, bar_y, bar_w, 3), Color(0.1, 0.1, 0.12))
        var hp_col = Color(0.2, 0.9, 0.3) if hp_pct > 0.5 else Color(0.9, 0.8, 0.2) if hp_pct > 0.25 else Color(0.9, 0.2, 0.2)
        draw_rect(Rect2( - bar_w * 0.5, bar_y, bar_w * hp_pct, 3), hp_col)


    var _hover_showing = _draw_hover_tooltip()
    if not _hover_showing:
        var player_nodes = get_tree().get_nodes_in_group("player")
        if not player_nodes.is_empty():
            var pdist = global_position.distance_to(player_nodes[0].global_position)
            if pdist < 400:
                var font = ThemeDB.fallback_font
                var label_alpha = clampf(1.0 - pdist / 400.0, 0.0, 0.6)
                var label_col = station_color
                label_col.a = label_alpha
                var tw = font.get_string_size(station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
                draw_string(font, Vector2( - tw * 0.5, - _station_extent - 10), station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)

func _draw_hover_tooltip() -> bool:

    var local_mouse = get_local_mouse_position()
    if local_mouse.length() > _station_extent + 20.0:
        return false


    var lines: Array = []
    lines.append(station_name)


    var fdata = DataManager.galaxy_data.get("factions", {})
    var fname = fdata.get(faction_id, {}).get("name", faction_id.capitalize())
    if hostile:
        lines.append(fname + "  [HOSTILE]")
    else:
        lines.append(fname)


    lines.append(station_type.capitalize() + " Station")


    var hp_pct = health / max_health if max_health > 0 else 1.0
    var hp_str = "Hull: %d%%" % int(hp_pct * 100)
    if max_shields > 0:
        var sp = shields / max_shields if max_shields > 0 else 0.0
        hp_str += "  Shields: %d%%" % int(sp * 100)
    lines.append(hp_str)


    var active_weapons: int = 0
    for wi in weapon_modules:
        if ship_modules[wi].get("hp", 0) > 0:
            active_weapons += 1
    if weapon_modules.size() > 0:
        lines.append("Weapons: %d / %d active" % [active_weapons, weapon_modules.size()])


    var font = ThemeDB.fallback_font
    var line_h: float = 14.0
    var pad: float = 8.0
    var max_w: float = 0
    for li in lines.size():
        var fs = 11 if li == 0 else 9
        var w = font.get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        max_w = maxf(max_w, w)
    var panel_w = max_w + pad * 2
    var panel_h = lines.size() * line_h + pad * 2


    draw_set_transform(Vector2.ZERO, - rotation, Vector2.ONE)

    var tx = - panel_w * 0.5
    var ty = - _station_extent - panel_h - 14.0


    draw_rect(Rect2(tx, ty, panel_w, panel_h), Color(0.08, 0.1, 0.15, 0.92))
    draw_rect(Rect2(tx, ty, panel_w, panel_h), Color(0.3, 0.4, 0.55, 0.6), false, 1.0)


    var ly = ty + pad + 10
    for li in lines.size():
        var col: Color
        if li == 0:
            col = Color(0.9, 0.9, 0.95)
        elif li == 1 and hostile:
            col = Color(0.9, 0.3, 0.2)
        elif li == 1:
            col = Color(0.6, 0.7, 0.85)
        elif li == 2:
            col = Color(0.7, 0.8, 0.6)
        else:
            col = Color(0.65, 0.7, 0.8)
        var fs = 11 if li == 0 else 9
        draw_string(font, Vector2(tx + pad, ly), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
        ly += line_h


    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    return true





func get_hail_data() -> Dictionary:

    var active_weapons: int = 0
    for wi in weapon_modules:
        if ship_modules[wi].get("hp", 0) > 0:
            active_weapons += 1
    return {
        "station_key": station_key, 
        "name": station_name, 
        "faction": faction_id, 
        "type": station_type, 
        "hostile": hostile, 
        "health_pct": health / max_health if max_health > 0 else 0.0, 
        "shield_pct": shields / max_shields if max_shields > 0 else 0.0, 
        "weapon_count": weapon_modules.size(), 
        "active_weapons": active_weapons, 
        "population": 0, 
        "is_station": true, 
    }

func become_hostile():

    if not hostile:
        hostile = true
        combat_target = null
        add_to_group("enemies")

func sync_from_persistent():

    if station_key == "" or not GameManager.persistent_stations.has(station_key):
        return
    var sdata = GameManager.persistent_stations[station_key]
    ship_modules = sdata.get("modules", ship_modules)
    health = sdata.get("health", health)
    max_health = sdata.get("max_health", max_health)
    hull_hp = health
    hull_max_hp = max_health
    shields = sdata.get("shields", shields)
    max_shields = sdata.get("max_shields", max_shields)
    _cache_weapon_modules()
    _hull_cache_dirty = true


# ── Collision Damage ──────────────────────────────────────────────────

func _get_collision_mass() -> float:
    if not ship_modules.is_empty():
        return float(ship_modules.size()) * 3.0
    return 50.0

func _get_collision_radius() -> float:
    return _station_extent

func _should_collide_with(other: Area2D) -> bool:
    return other.is_in_group("enemies") or other.is_in_group("player")
