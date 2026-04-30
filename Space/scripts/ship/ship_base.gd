extends Area2D


const ModuleVisuals = preload("res://Space/scripts/autoload/module_visuals.gd")











var faction_id: String = "independent"


var alive: bool = true
var hostile: bool = false
var scanned: bool = false
var damage_flash: float = 0.0


var hull_hp: float = 100.0
var hull_max_hp: float = 100.0
var health: float = 100.0
var max_health: float = 100.0
var shields: float = 0.0
var max_shields: float = 0.0
var shield_recharge_rate: float = 3.0
var damage_resist: float = 0.0


var shield_timer: float = 0.0
var no_damage_timer: float = 0.0
var module_repair_rate: float = 3.0


var ship_color: Color = Color(0.5, 0.5, 0.55)
var ship_size: float = 14.0


var ship_modules: Array = []
var MCELL: float = 7.0
var grid_center_px: Vector2 = Vector2.ZERO


var _hull_cache_dirty: bool = true
var _cached_hull_contour: PackedVector2Array = PackedVector2Array()
var _cached_all_cells: Dictionary = {}
var _cached_cell_corners: Dictionary = {}
var _cached_cell_draws: Array = []
var _cached_sprite_draws: Array = []

var _light_front: Vector2 = Vector2.ZERO
var _light_rear: Vector2 = Vector2.ZERO
var _light_top: Vector2 = Vector2.ZERO
var _light_bot: Vector2 = Vector2.ZERO


var _col_shape: CollisionShape2D
var _module_colliders: Array = []
var _ship_extent: float = 15.0





func _init_collision(radius: float):

    var shape = CircleShape2D.new()
    shape.radius = radius
    _col_shape = CollisionShape2D.new()
    _col_shape.shape = shape
    add_child(_col_shape)

func _update_collision_radius(radius: float):

    _ship_extent = radius
    if _col_shape and _col_shape.shape is CircleShape2D:
        _col_shape.shape.radius = radius

func _rebuild_module_colliders():



    for col in _module_colliders:
        if is_instance_valid(col):
            col.queue_free()
    _module_colliders.clear()
    if _cached_all_cells.is_empty():

        if not _col_shape or not is_instance_valid(_col_shape):
            _init_collision(_ship_extent)
        return

    if _col_shape and is_instance_valid(_col_shape):
        _col_shape.queue_free()
        _col_shape = null
    var max_extent: float = 10.0
    for cell in _cached_all_cells:
        var corners = _cached_cell_corners.get(cell)
        if corners == null or corners.size() < 3:
            corners = _hex_polygon_local(cell)
        var shape = ConvexPolygonShape2D.new()
        shape.points = corners
        var col_node = CollisionShape2D.new()
        col_node.shape = shape
        add_child(col_node)
        _module_colliders.append(col_node)
        for c in corners:
            max_extent = maxf(max_extent, c.length())
    _ship_extent = max_extent + 2.0

func _apply_hostility():

    if hostile:
        add_to_group("enemies")





func _get_mod_type(mod: Dictionary) -> String:


    var t = mod.get("type", "")
    if t == "":
        t = mod.get("data", {}).get("type", "")
    return t

func _get_mod_grid_pos(mod: Dictionary):

    var gp = mod.get("grid_pos", Vector2i(0, 0))
    if gp is Array:
        return Vector2i(int(gp[0]), int(gp[1]))
    return gp





func _compute_grid_center():

    if ship_modules.is_empty():
        grid_center_px = Vector2.ZERO
        return
    var sum = Vector2.ZERO
    var count: int = 0
    for mod in ship_modules:
        var gp = mod.get("grid_pos", [0, 0])
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        elif gp is Vector2i:
            pass
        else:
            continue
        sum += HexUtil.hex_to_pixel(gp, MCELL)
        count += 1
    if count > 0:
        grid_center_px = sum / float(count)

func _hex_to_local(hex) -> Vector2:


    var gp: Vector2i
    if hex is Array:
        gp = Vector2i(int(hex[0]), int(hex[1]))
    elif hex is Vector2i:
        gp = hex
    else:
        gp = Vector2i(0, 0)
    var px = HexUtil.hex_to_pixel(gp, MCELL)
    return Vector2( - px.y + grid_center_px.y, px.x - grid_center_px.x)

func _hex_polygon_local(cell: Vector2i) -> PackedVector2Array:


    var px = HexUtil.hex_to_pixel(cell, MCELL)
    var pixel_corners = HexUtil.hex_corners(px, MCELL)
    var result = PackedVector2Array()
    for c in pixel_corners:
        result.append(Vector2( - c.y + grid_center_px.y, c.x - grid_center_px.x))
    return result

func _compute_extent() -> float:

    var max_dist: float = 10.0
    for mod in ship_modules:
        var cells = GameManager.get_mod_hex_cells(mod)
        for cell in cells:
            var fp = _hex_to_local(cell)
            max_dist = maxf(max_dist, fp.length() + MCELL)
    return max_dist





func _rebuild_hull_cache():


    _cached_all_cells.clear()
    _cached_cell_corners.clear()
    _cached_cell_draws.clear()
    _cached_sprite_draws.clear()
    for mod in ship_modules:
        var hex_cells = GameManager.get_mod_hex_cells(mod)
        for hcell in hex_cells:
            _cached_all_cells[hcell] = mod
            _cached_cell_corners[hcell] = _hex_polygon_local(hcell)

    for cell in _cached_all_cells:
        var mod = _cached_all_cells[cell]
        var mtype = _get_mod_type(mod)
        var tint = _get_module_draw_color(mtype)
        var mod_hp: float = mod.get("hp", 1.0)
        var mod_max_hp: float = mod.get("max_hp", 1.0)
        if mod_hp <= 0:
            tint = Color(0.15, 0.1, 0.08)
        elif mod_hp < mod_max_hp:
            tint = tint.lerp(Color(0.5, 0.15, 0.1), 0.4)
        elif not mod.get("powered", true):
            tint = tint * 0.3
        _cached_cell_draws.append({poly = _cached_cell_corners[cell], color = tint})

    var _seen_mods: Array = []
    for mod in ship_modules:
        if mod in _seen_mods:
            continue
        _seen_mods.append(mod)
        var sprite_name = mod.get("data", {}).get("sprite", "")
        if sprite_name == "":
            var def = DataManager.modules.get(mod.get("id", ""), {})
            sprite_name = def.get("sprite", "")
        if sprite_name == "":
            continue
        var tex = GameManager.get_module_sprite(sprite_name)
        if tex == null:
            continue
        var mod_data = mod.get("data", {})
        var mod_rot = int(mod.get("rotation", 0)) * PI / 3.0
        var anchor_local = _hex_to_local(mod.get("grid_pos", Vector2i.ZERO))
        var hex_offset = ModuleVisuals.get_canonical_sprite_center(mod_data, MCELL)
        var local_offset = Vector2(-hex_offset.y, hex_offset.x).rotated(mod_rot)
        var center = anchor_local + local_offset
        var spr_scale = ModuleVisuals.get_sprite_scale(mod_data, MCELL)
        _cached_sprite_draws.append({tex = tex, pos = center, spr_scale = spr_scale, rot = mod_rot + PI / 2.0 + ModuleVisuals.get_sprite_rotation_rad(mod_data), mod_ref = mod})

    var nb_map: Array = [
        Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
        Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
    ]
    _cached_hull_contour = _build_smooth_hull(_cached_all_cells, nb_map)

    var front_x: float = -999.0
    var rear_x: float = 999.0
    var top_y: float = 999.0
    var bot_y: float = -999.0
    for cell in _cached_all_cells:
        var fp = _hex_to_local(cell)
        if fp.x + MCELL > front_x:
            front_x = fp.x + MCELL
            _light_front = Vector2(fp.x + MCELL, fp.y)
        if fp.x - MCELL < rear_x:
            rear_x = fp.x - MCELL
            _light_rear = Vector2(fp.x - MCELL, fp.y)
        if fp.y - MCELL < top_y:
            top_y = fp.y - MCELL
            _light_top = Vector2(fp.x, fp.y - MCELL)
        if fp.y + MCELL > bot_y:
            bot_y = fp.y + MCELL
            _light_bot = Vector2(fp.x, fp.y + MCELL)
    _hull_cache_dirty = false

func _build_smooth_hull(all_cells: Dictionary, nb_map: Array) -> PackedVector2Array:

    if all_cells.is_empty():
        return PackedVector2Array()
    var edge_list: Array = []
    for cell in all_cells:
        var corners = _hex_polygon_local(cell)
        for ei in 6:
            var nb_cell = cell + nb_map[ei]
            if not all_cells.has(nb_cell):
                edge_list.append([corners[ei], corners[(ei + 1) % 6]])
    if edge_list.is_empty():
        return PackedVector2Array()
    var contour = _chain_edges(edge_list)
    if contour.size() < 3:
        var all_pts = PackedVector2Array()
        for e in edge_list:
            all_pts.append(e[0])
            all_pts.append(e[1])
        contour = Geometry2D.convex_hull(all_pts)
    if contour.size() < 3:
        return PackedVector2Array()
    return _chaikin_smooth(contour, 2)

func _chain_edges(edges: Array) -> PackedVector2Array:

    if edges.is_empty():
        return PackedVector2Array()
    var snap_scale: float = 100.0
    var adj: Dictionary = {}
    for ei in edges.size():
        var a = edges[ei][0]
        var b = edges[ei][1]
        var ka = Vector2i(roundi(a.x * snap_scale), roundi(a.y * snap_scale))
        var kb = Vector2i(roundi(b.x * snap_scale), roundi(b.y * snap_scale))
        if not adj.has(ka):
            adj[ka] = []
        adj[ka].append({"pt": b, "key": kb, "idx": ei})
        if not adj.has(kb):
            adj[kb] = []
        adj[kb].append({"pt": a, "key": ka, "idx": ei})
    var result = PackedVector2Array()
    var used: Dictionary = {}
    var a0 = edges[0][0]
    var b0 = edges[0][1]
    var start_key = Vector2i(roundi(a0.x * snap_scale), roundi(a0.y * snap_scale))
    var current_key = Vector2i(roundi(b0.x * snap_scale), roundi(b0.y * snap_scale))
    result.append(a0)
    result.append(b0)
    used[0] = true
    for _safety in range(edges.size() * 2 + 10):
        if current_key == start_key:
            break
        var found = false
        for ne in adj.get(current_key, []):
            if not used.has(ne["idx"]):
                used[ne["idx"]] = true
                current_key = ne["key"]
                result.append(ne["pt"])
                found = true
                break
        if not found:
            break
    return result

func _chaikin_smooth(poly: PackedVector2Array, passes: int) -> PackedVector2Array:

    var pts = poly
    for _p in passes:
        var smoothed = PackedVector2Array()
        var n = pts.size()
        if n < 3:
            return pts
        for i in n:
            var a = pts[i]
            var b = pts[(i + 1) % n]
            smoothed.append(a * 0.75 + b * 0.25)
            smoothed.append(a * 0.25 + b * 0.75)
        pts = smoothed
    return pts





func _draw_hull(flash_lerp: float = 0.0):


    if _hull_cache_dirty:
        _rebuild_hull_cache()

    for cd in _cached_cell_draws:
        var col = cd.color
        if flash_lerp > 0:
            col = col.lerp(Color.WHITE, flash_lerp)
        draw_colored_polygon(cd.poly, col)

    for sd in _cached_sprite_draws:
        var s = sd.spr_scale
        var hw = sd.tex.get_width() * 0.5
        var hh = sd.tex.get_height() * 0.5
        draw_set_transform(sd.pos, sd.rot, Vector2(s, s))
        var mod_ref = sd.get("mod_ref", {})
        var spr_hp: float = mod_ref.get("hp", 1.0)
        var spr_max: float = mod_ref.get("max_hp", 1.0)
        if spr_hp <= 0:
            # Destroyed — don't draw the sprite, let the burnt hex cell show through
            pass
        elif spr_hp < spr_max:
            var dmg_t := 1.0 - (spr_hp / maxf(spr_max, 0.01))
            var tint := Color.WHITE.lerp(Color(1.0, 0.3, 0.15), dmg_t * 0.7)
            tint.a = lerpf(1.0, 0.5, dmg_t)
            draw_texture(sd.tex, Vector2(-hw, -hh), tint)
        else:
            draw_texture(sd.tex, Vector2(-hw, -hh))
        draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

    if _cached_hull_contour.size() >= 3:
        var outline = Color(ship_color, 0.5)
        if flash_lerp > 0:
            outline = outline.lerp(Color.WHITE, flash_lerp)
        var closed = PackedVector2Array(_cached_hull_contour)
        closed.append(_cached_hull_contour[0])
        draw_polyline(closed, Color(outline, 0.12), 4.0)
        draw_polyline(closed, outline, 1.2)

func _draw_engine_flames(time: float, vel_length: float, max_spd: float):

    if vel_length < 15:
        return
    var intensity = clampf(vel_length / maxf(max_spd, 1.0), 0, 1)
    for mod in ship_modules:
        var mtype = _get_mod_type(mod)
        if mtype != "engine":
            continue
        if mod.get("hp", 1.0) <= 0:
            continue
        if not mod.get("powered", true):
            continue
        var fp = _hex_to_local(mod.get("grid_pos", Vector2i(0, 0)))
        var flicker = 0.8 + sin(time * 12 + fp.x) * 0.2
        var flame_len = MCELL * 2.0 * intensity * flicker
        var hh = MCELL * 0.5
        var rear_x = fp.x - MCELL * 0.7

        var outer = PackedVector2Array([
            Vector2(rear_x, fp.y - hh * 0.95), 
            Vector2(rear_x - flame_len * 1.15, fp.y), 
            Vector2(rear_x, fp.y + hh * 0.95), 
        ])
        draw_colored_polygon(outer, Color(1.0, 0.5, 0.1, 0.25 * intensity))

        var flame = PackedVector2Array([
            Vector2(rear_x, fp.y - hh * 0.7), 
            Vector2(rear_x - flame_len, fp.y), 
            Vector2(rear_x, fp.y + hh * 0.7), 
        ])
        var eng_col = Color(1.0, 0.5, 0.1, clampf(intensity, 0, 1))
        draw_colored_polygon(flame, eng_col)

        draw_colored_polygon(PackedVector2Array([
            Vector2(rear_x, fp.y - hh * 0.35), 
            Vector2(rear_x - flame_len * 0.55, fp.y), 
            Vector2(rear_x, fp.y + hh * 0.35), 
        ]), Color(1.0, 0.9, 0.5, 0.4 * intensity))

func _draw_module_accents(time: float):

    for mod in ship_modules:
        var mod_hp: float = mod.get("hp", 1.0)
        var gp = mod.get("grid_pos", Vector2i(0, 0))
        var fp = _hex_to_local(gp)
        var gx = float(gp.x if gp is Vector2i else int(gp[0]))
        var gy = float(gp.y if gp is Vector2i else int(gp[1]))
        if mod_hp <= 0:
            var r = MCELL * 0.4
            for si in 3:
                var seed_f = gx * 3.7 + gy * 5.3 + float(si) * 2.1
                var spark_t = fmod(time * (2.5 + float(si) * 0.7) + seed_f, 1.0)
                if spark_t < 0.2:
                    var sx = fp.x + sin(seed_f * 4.1 + time * 3.0) * r
                    var sy = fp.y + cos(seed_f * 3.3 + time * 2.5) * r
                    var alpha = 1.0 - spark_t * 5.0
                    draw_circle(Vector2(sx, sy), 1.0, Color(1.0, 0.7, 0.2, alpha))
                    if si == 0 and spark_t < 0.08:
                        var ex = fp.x + sin(seed_f * 2.9 + time * 4.0) * r * 0.6
                        var ey = fp.y + cos(seed_f * 1.7 + time * 3.5) * r * 0.6
                        draw_line(Vector2(sx, sy), Vector2(ex, ey), Color(1.0, 0.85, 0.4, alpha * 0.6), 0.6)
            continue
        var mod_max_hp: float = mod.get("max_hp", 1.0)
        if mod_hp < mod_max_hp:
            var spark_t = fmod(time * 3.0 + gx * 1.7, 1.0)
            if spark_t < 0.3:
                draw_circle(Vector2(fp.x + sin(time * 7) * 3, fp.y + cos(time * 5) * 2), 1.5, Color(1.0, 0.6, 0.1, 1.0 - spark_t * 3.0))
        elif mod.get("powered", true):
            var r = MCELL * 0.45
            var mtype = _get_mod_type(mod)
            match mtype:
                "reactor":
                    var pulse = sin(time * 2.0) * 0.15 + 0.85
                    draw_circle(fp, r * 0.6, Color(1.0, 0.95, 0.4, 0.25 * pulse))
                "weapon":
                    draw_circle(fp + Vector2(r * 0.5, 0), 1.2, Color(1.0, 0.4, 0.2, 0.5))
                "shield":
                    var shimmer = sin(time * 3.0) * 0.15 + 0.85
                    draw_arc(fp, r * 0.6, - PI * 0.4, PI * 0.4, 6, Color(0.5, 0.7, 1.0, 0.3 * shimmer), 0.8)
                "sensor":
                    var sweep_a = fmod(time * 2.0, TAU)
                    draw_arc(fp, r * 0.5, sweep_a, sweep_a + PI * 0.5, 5, Color(0.4, 1.0, 0.6, 0.3), 0.6)

func _draw_running_lights_auto(time: float):

    if ship_modules.is_empty():
        return
    var blink = sin(time * 3.0) * 0.5 + 0.5
    var blink2 = sin(time * 3.0 + PI) * 0.5 + 0.5

    draw_circle(_light_top, 1.8, Color(1.0, 0.15, 0.1, 0.2))
    draw_circle(_light_top, 1.0, Color(1.0, 0.2, 0.15, blink * 0.9))

    draw_circle(_light_bot, 1.8, Color(0.1, 1.0, 0.15, 0.2))
    draw_circle(_light_bot, 1.0, Color(0.15, 1.0, 0.2, blink * 0.9))

    draw_circle(_light_front, 1.5, Color(1.0, 1.0, 1.0, 0.15))
    draw_circle(_light_front, 0.8, Color(1.0, 1.0, 1.0, blink2 * 0.8))

    draw_circle(_light_rear, 1.5, Color(1.0, 0.6, 0.1, 0.15))
    draw_circle(_light_rear, 0.8, Color(1.0, 0.65, 0.15, blink2 * 0.7))

func _draw_shield_bubble(time: float):

    if shields <= 0 or max_shields <= 0:
        return
    var shield_frac = shields / max_shields
    var shield_alpha = shield_frac * 0.3
    var sr = _ship_extent + 4
    draw_arc(Vector2.ZERO, sr + 2, 0, TAU, 48, Color(0.2, 0.4, 1.0, shield_alpha * 0.15), 5.0)
    draw_arc(Vector2.ZERO, sr, 0, TAU, 48, Color(0.3, 0.5, 1.0, shield_alpha), 2.0)
    var hex_count: int = 12
    for hi in hex_count:
        var ha = float(hi) / float(hex_count) * TAU
        var ha2 = float(hi + 1) / float(hex_count) * TAU
        var shimmer = sin(time * 2.0 + ha * 3.0) * 0.3 + 0.7
        draw_line(
            Vector2(cos(ha) * sr, sin(ha) * sr), 
            Vector2(cos(ha2) * sr, sin(ha2) * sr), 
            Color(0.4, 0.6, 1.0, shield_alpha * shimmer * 1.5), 1.0)
        var spoke_len = sr * 0.15
        draw_line(
            Vector2(cos(ha) * (sr - spoke_len), sin(ha) * (sr - spoke_len)), 
            Vector2(cos(ha) * sr, sin(ha) * sr), 
            Color(0.3, 0.5, 1.0, shield_alpha * 0.4 * shimmer), 0.6)

func _draw_health_bar():

    if health >= max_health or max_health <= 0:
        return
    var hp_pct = health / max_health
    var bar_w = _ship_extent * 2.0
    var bar_y = _ship_extent + 8.0
    draw_rect(Rect2( - bar_w * 0.5, bar_y, bar_w, 2), Color(0.1, 0.1, 0.12))
    var hp_col = Color(0.2, 0.9, 0.3) if hp_pct > 0.5 else Color(0.9, 0.8, 0.2) if hp_pct > 0.25 else Color(0.9, 0.2, 0.2)
    draw_rect(Rect2( - bar_w * 0.5, bar_y, bar_w * hp_pct, 2), hp_col)





func _find_hit_cell(world_pos: Vector2) -> Vector2i:

    if world_pos == Vector2.ZERO:
        return Vector2i(-9999, -9999)
    var local = (world_pos - global_position).rotated( - rotation)
    var px = Vector2(local.y + grid_center_px.x, grid_center_px.y - local.x)
    return HexUtil.pixel_to_hex(px, MCELL)

func _find_module_at_cell(cell: Vector2i) -> Dictionary:

    for mod in ship_modules:
        var cells = GameManager.get_mod_hex_cells(mod)
        if cell in cells:
            return mod
    return {}





func take_damage(amount: float, pierce: float = 0.0, hit_world_pos: Vector2 = Vector2.ZERO):


    if not alive:
        return
    shield_timer = 5.0
    no_damage_timer = 0.0

    var pierce_dmg = amount * clampf(pierce, 0, 1)
    var normal_dmg = amount - pierce_dmg

    if shields > 0 and normal_dmg > 0:
        var absorbed = minf(shields, normal_dmg)
        shields -= absorbed
        normal_dmg -= absorbed

    var hull_dmg: float = 0.0
    if normal_dmg > 0 and not ship_modules.is_empty():
        var hit_cell = _find_hit_cell(hit_world_pos)
        if hit_cell != Vector2i(-9999, -9999):
            var mod = _find_module_at_cell(hit_cell)
            if not mod.is_empty() and mod.get("hp", 0) > 0:
                var before_hp: float = mod.get("hp", 0)
                GameManager.damage_module(mod, normal_dmg)
                if mod.get("hp", 0) <= 0:
                    hull_dmg += maxf(normal_dmg - before_hp, 0)
            else:
                hull_dmg += normal_dmg
        else:
            _damage_random_alive_module(normal_dmg)
    elif normal_dmg > 0:
        hull_dmg += normal_dmg

    hull_dmg += pierce_dmg

    if hull_dmg > 0:
        hull_dmg *= (1.0 - damage_resist)
        hull_hp = maxf(hull_hp - hull_dmg, 0)

    _on_damage_dealt()
    damage_flash = 1.0

    if hull_hp <= 0:
        _on_death()

func _damage_random_alive_module(dmg: float):

    var alive_mods: Array = []
    for m in ship_modules:
        if m.get("hp", 1.0) > 0:
            alive_mods.append(m)
    if not alive_mods.is_empty():
        GameManager.damage_module(alive_mods[randi() % alive_mods.size()], dmg)

func _on_damage_dealt():

    _sync_hull_health()
    _hull_cache_dirty = true

func _sync_hull_health():

    health = hull_hp
    max_health = hull_max_hp

func _on_death():

    alive = false





func _handle_regen(delta: float):

    no_damage_timer += delta
    if shield_timer > 0:
        shield_timer -= delta
    elif shields < max_shields and max_shields > 0:
        shields = minf(shields + shield_recharge_rate * delta, max_shields)
    var shields_ready: bool = max_shields <= 0 or shields >= max_shields
    var repair_delay: float = 10.0 if max_shields <= 0 else 5.0
    if shields_ready and no_damage_timer >= repair_delay:
        _repair_damaged_modules(delta)

func _repair_damaged_modules(delta: float):

    var repaired_any: bool = false
    for mod in ship_modules:
        if not mod.has("max_hp"):
            GameManager.init_module_hp(mod)
        var hp: float = mod.get("hp", 0)
        var max_hp: float = mod.get("max_hp", 1.0)
        if hp < max_hp:
            mod["hp"] = minf(hp + module_repair_rate * delta, max_hp)
            if mod["hp"] >= max_hp:
                mod["damaged"] = false
                mod.erase("destroyed")
            repaired_any = true
    if repaired_any:
        _on_modules_repaired()

func _on_modules_repaired():

    _hull_cache_dirty = true





# ── Collision Damage ──────────────────────────────────────────────────
# Every physics frame: detect overlaps, push apart, bounce velocity,
# and deal damage.  No cooldowns — if you're inside something you keep
# getting hurt until you're not.

const COLLISION_MIN_DAMAGE_SPEED: float = 40.0
const COLLISION_RESTITUTION: float = 0.5

var _damage_number_script: GDScript = preload("res://Space/scripts/combat/damage_number.gd")

func _get_collision_mass() -> float:
    if not ship_modules.is_empty():
        return float(ship_modules.size())
    return maxf(_ship_extent / 10.0, 1.0)

func _get_collision_radius() -> float:
    return _ship_extent

func _get_average_armor() -> float:
    if ship_modules.is_empty():
        return 0.0
    var total_armor: float = 0.0
    var count: int = 0
    for mod in ship_modules:
        if mod.get("hp", 0) > 0:
            total_armor += mod.get("armor", 0)
            count += 1
    return total_armor / maxf(count, 1)

func _should_collide_with(_other: Area2D) -> bool:
    return false

func _process_collisions(_delta: float):
    if not alive:
        return
    for other in get_overlapping_areas():
        if is_instance_valid(other) and _should_collide_with(other):
            _resolve_collision(other, _delta)

func _resolve_collision(other: Area2D, _delta: float):
    # ── direction & overlap ──
    var sep = other.global_position - global_position
    var dist = sep.length()
    if dist < 0.1:
        sep = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
        dist = 0.1
    var dir = sep / dist

    var my_radius = _get_collision_radius()
    var other_radius: float = other._get_collision_radius() if other.has_method("_get_collision_radius") else (other.ship_size if "ship_size" in other else 15.0)
    var min_dist = my_radius + other_radius
    var overlap = min_dist - dist
    if overlap <= 0:
        return

    # ── masses ──
    var my_mass = _get_collision_mass()
    var other_mass = _get_other_collision_mass(other)
    var total_mass = my_mass + other_mass
    var my_ratio = other_mass / total_mass  # how much I move (light = more)

    # ── separate positions so nothing overlaps ──
    if "velocity" in self:
        global_position -= dir * overlap * my_ratio

    # ── velocities ──
    var my_vel: Vector2 = self.get("velocity") if "velocity" in self else Vector2.ZERO
    var other_vel: Vector2 = other.get("velocity") if "velocity" in other else Vector2.ZERO
    var closing_speed = (my_vel - other_vel).dot(dir)

    # ── velocity bounce (only when approaching) ──
    if closing_speed > 0 and "velocity" in self:
        var bounce = closing_speed * my_ratio * (1.0 + COLLISION_RESTITUTION)
        self.set("velocity", my_vel - dir * bounce)

    # ── damage ──
    if closing_speed > COLLISION_MIN_DAMAGE_SPEED:
        # Quadratic scaling: slow bumps sting, full-speed rams devastate
        var raw_damage = closing_speed * 0.3 + closing_speed * closing_speed * 0.01
        # Heavier target = more damage to you (up to 2.5x), lighter = still hurts (floor 0.3x)
        var mass_factor = clampf(other_mass / maxf(my_mass, 0.1), 0.3, 2.5)
        raw_damage *= mass_factor

        if raw_damage >= 1.0:
            var hit_pos = global_position + dir * my_radius
            _apply_collision_damage(raw_damage, hit_pos)
            _spawn_collision_damage_number(raw_damage, hit_pos)
            AudioManager.play_sfx("hull_hit", clampf(raw_damage / 30.0, 0.2, 0.9), 0.15)
            _on_collision_impact(raw_damage, closing_speed)
    elif overlap > 3.0:
        # Grinding damage — you're pressed against something
        var grind = overlap * 2.0 * _delta
        if grind >= 0.5:
            var hit_pos = global_position + dir * my_radius
            _apply_collision_damage(grind, hit_pos)
            _on_collision_impact(grind, 0.0)

func _on_collision_impact(_damage: float, _closing_speed: float):
    pass

func _apply_collision_damage(amount: float, hit_pos: Vector2):
    # Kinetic ram — rips through modules front-to-back.
    # Each module's armor slows the force, its HP absorbs some,
    # and if it breaks the remaining force keeps going.
    shield_timer = 5.0
    no_damage_timer = 0.0

    # Shields only intercept 40% of kinetic impact
    if shields > 0:
        var shield_portion = amount * 0.4
        var absorbed = minf(shields, shield_portion)
        shields -= absorbed
        amount -= absorbed

    # Rip through modules starting at the impact point
    if not ship_modules.is_empty() and amount > 0:
        # First hit: the module at the point of impact
        var hit_cell = _find_hit_cell(hit_pos)
        if hit_cell != Vector2i(-9999, -9999):
            var first_mod = _find_module_at_cell(hit_cell)
            if not first_mod.is_empty() and first_mod.get("hp", 0) > 0:
                amount = _collision_rip_module(first_mod, amount)

        # Force keeps going — tears through alive modules until spent
        while amount > 0:
            var alive_mods: Array = []
            for m in ship_modules:
                if m.get("hp", 0) > 0:
                    alive_mods.append(m)
            if alive_mods.is_empty():
                break
            amount = _collision_rip_module(alive_mods[randi() % alive_mods.size()], amount)

    # Sync hull_hp to actual total module HP so the health bar stays correct
    var total_hp: float = 0.0
    var total_max: float = 0.0
    for mod in ship_modules:
        total_hp += maxf(mod.get("hp", 0), 0)
        total_max += mod.get("max_hp", 0)
    if total_max > 0:
        hull_hp = total_hp
        hull_max_hp = total_max

    # Anything left after all modules hits bare hull
    if amount > 0:
        hull_hp = maxf(hull_hp - amount, 0)

    _on_damage_dealt()
    damage_flash = 1.0

    if hull_hp <= 0:
        _on_death()

func _collision_rip_module(mod: Dictionary, amount: float) -> float:
    var hp: float = mod.get("hp", 0)
    if hp <= 0:
        return amount
    var armor: float = mod.get("armor", 0)
    # Armor bleeds off some force — but at least 15% always gets through
    var effective = maxf(amount - armor, amount * 0.15)
    if effective >= hp:
        # Module destroyed — remaining force continues deeper
        mod["hp"] = 0
        mod["destroyed"] = true
        mod["damaged"] = true
        return effective - hp
    else:
        # Module stopped the collision
        mod["hp"] = hp - effective
        if mod["hp"] < mod.get("max_hp", 1.0) * 0.5:
            mod["damaged"] = true
        return 0.0

func _get_other_collision_mass(other: Area2D) -> float:
    if other.has_method("_get_collision_mass"):
        return other._get_collision_mass()
    if "ship_weight" in other:
        return other.ship_weight
    if "ship_modules" in other and not other.ship_modules.is_empty():
        return float(other.ship_modules.size())
    if "ship_size" in other:
        return other.ship_size / 12.0
    return 1.0

func _spawn_collision_damage_number(dmg: float, pos: Vector2):
    var dmg_num = Node2D.new()
    dmg_num.set_script(_damage_number_script)
    dmg_num.global_position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 5))
    var col = Color(1.0, 0.6, 0.2)
    if dmg >= 30:
        col = Color(1.0, 0.3, 0.1)
        dmg_num.font_size = 16
    elif dmg >= 15:
        col = Color(1.0, 0.5, 0.15)
        dmg_num.font_size = 14
    dmg_num.setup(dmg, col)
    get_tree().current_scene.add_child(dmg_num)




func _get_module_draw_color(mtype: String) -> Color:


    var base = ship_color
    match mtype:
        "weapon": return base.lerp(Color(0.9, 0.25, 0.2), 0.3)
        "shield": return base.lerp(Color(0.25, 0.45, 1.0), 0.3)
        "engine": return base.lerp(Color(1.0, 0.6, 0.15), 0.25)
        "reactor": return base.lerp(Color(0.95, 0.85, 0.15), 0.3)
        "armor": return base.lerp(Color(0.5, 0.55, 0.6), 0.2)
        "sensor": return base.lerp(Color(0.2, 0.85, 0.4), 0.3)
        "conduit": return base.lerp(Color(0.6, 0.5, 0.2), 0.2)
        "cargo": return base.lerp(Color(0.7, 0.55, 0.2), 0.25)
        "quarters": return base.lerp(Color(0.75, 0.55, 0.3), 0.2)
        "mess": return base.lerp(Color(0.8, 0.5, 0.2), 0.2)
        "medbay": return base.lerp(Color(0.3, 0.8, 0.4), 0.25)
        "bridge": return base.lerp(Color(0.5, 0.6, 0.9), 0.25)
        "life_support": return base.lerp(Color(0.3, 0.7, 0.7), 0.2)
        "construction_hangar": return base.lerp(Color(0.55, 0.55, 0.6), 0.2)
        "basic_workshop", "farmers_workshop": return base.lerp(Color(0.6, 0.5, 0.35), 0.2)
        "hydroponics": return base.lerp(Color(0.3, 0.75, 0.3), 0.25)
        "armory": return base.lerp(Color(0.8, 0.4, 0.15), 0.2)
        "hangar": return base.lerp(Color(0.4, 0.5, 0.7), 0.2)
        "fuel_scoop": return base.lerp(Color(0.9, 0.7, 0.2), 0.25)
        "mining": return base.lerp(Color(0.7, 0.5, 0.3), 0.2)
        _: return base * 0.7

func _get_type_color(mtype: String) -> Color:

    return _get_module_draw_color(mtype)
