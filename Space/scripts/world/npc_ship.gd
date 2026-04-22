extends "res://Space/scripts/ship/ship_base.gd"

const NpcShipBTBuilder = preload("res://Space/scripts/runtime/ship_ai/npc_ship_bt_builder.gd")




signal died(npc_id: String, pos: Vector2)
@warning_ignore("unused_signal")
signal hailed(npc_id: String)
var _proj_script: GDScript = preload("res://Space/scripts/combat/projectile.gd")
static var _spr_autocannon: Texture2D = preload("res://Space/art/projectiles/Autocannon.png")
static var _spr_pulse_mk1: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk1.png")
static var _spr_missile: Texture2D = preload("res://Space/art/projectiles/MissileBattery.png")
static var _spr_pulse_mk2: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk2.png")
static var _spr_railgun: Texture2D = preload("res://Space/art/projectiles/Railgun.png")


var npc_id: String = ""
var ship_name: String = "NPC Ship"
var npc_type: String = "trader"


var max_speed: float = 180.0
var acceleration: float = 500.0


var velocity: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var wait_timer: float = 0.0
var route_index: int = 0
var route_points: Array = []
var interact_radius: float = 150.0


var fire_timer: float = 0.0
var fire_rate: float = 1.5
var projectile_damage: float = 6.0
var projectile_speed: float = 450.0
var aggro_range: float = 800.0
var orbit_distance: float = 200.0
var combat_target: Node2D = null
var is_law_enforcement: bool = false
var _patrol_scan_timer: float = 0.0

var _juke_timer: float = 0.0
var _juke_dir: float = 1.0
@warning_ignore("unused_private_class_variable")
var _charge_timer: float = 0.0
var _combat_mode: int = 0
var _mode_timer: float = 0.0
var _npc_weapons: Array = []


var combat_style: String = "standard"
var placed_npc_id: String = ""
var hail_event_id: String = ""


enum HRPhase{APPROACH, ATTACK, DISENGAGE}
var _hr_phase: int = HRPhase.APPROACH
var _hr_attack_timer: float = 0.0
const HR_ATTACK_WINDOW: float = 3.0
var _hr_disengage_timer: float = 0.0
const HR_DISENGAGE_TIME: float = 6.0
const HR_DISENGAGE_SPEED_MULT: float = 1.35


var _npc_railgun_count: int = 0
var _npc_rail_data: Array = []
var _npc_rail_cooldowns: Array = []
const NPC_RAIL_COOLDOWN: float = 2.5
const NPC_RAIL_CHARGE_TIME: float = 0.8
var _npc_rail_charges: Array = []


var system_center: Vector2 = Vector2.ZERO


var _engine_flicker: float = 0.0
var _running_light_timer: float = 0.0
var ship_style: String = ""


var _was_moving: bool = false
var _prev_health: float = -1.0
var _cam_check_timer: float = 0.0
var _was_cam_near: bool = false
var _combat_bt: BeehaveTree = null

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("npc_ships")
    _init_collision(ship_size * 1.5)

func setup(data: Dictionary):
    npc_id = data.get("id", "")
    ship_name = data.get("name", "Ship")
    faction_id = data.get("faction", "independent")
    npc_type = data.get("npc_type", "trader")
    max_health = data.get("max_health", 60.0)
    health = data.get("health", max_health)
    max_shields = data.get("max_shields", 0.0)
    shields = data.get("shields", max_shields)
    max_speed = data.get("max_speed", 180.0)
    ship_size = data.get("ship_size", 14.0)
    hostile = data.get("hostile", false)
    is_law_enforcement = data.get("is_law_enforcement", false)

    var c = data.get("color", [0.5, 0.5, 0.55])
    ship_color = Color(c[0], c[1], c[2])
    ship_style = data.get("ship_style", "")

    var wp = data.get("world_pos", [0, 0])
    global_position = Vector2(wp[0], wp[1])
    rotation = data.get("rotation", 0.0)


    ship_modules = data.get("modules", [])
    static_hull_path = str(data.get("static_hull_path", ""))
    if ship_modules.is_empty():
        var rng = RandomNumberGenerator.new()
        rng.seed = npc_id.hash()
        ship_modules = GameManager._generate_npc_modules(rng, npc_type)

    for mod in ship_modules:
        if not mod.has("data"):
            mod["data"] = mod.get("data", {"type": "structural"})
        GameManager.init_module_hp(mod)

    var total_hp: float = 0.0
    var total_max: float = 0.0
    for mod in ship_modules:
        total_max += mod.get("max_hp", 0)
        total_hp += mod.get("hp", 0)
    if total_max > 0:
        max_health = total_max
        health = total_hp
    hull_hp = health
    hull_max_hp = max_health
    _compute_grid_center()
    _rebuild_hull_cache()

    _rebuild_module_colliders()


    route_points.clear()
    for rp in data.get("route", []):
        route_points.append(Vector2(rp[0], rp[1]))
    route_index = data.get("route_index", 0)

    if route_points.is_empty():
        _generate_wander_route()
    _pick_next_target()
    _apply_hostility()
    queue_redraw()


    combat_style = data.get("combat_style", "standard")
    placed_npc_id = data.get("placed_npc_id", "")
    hail_event_id = data.get("hail_event_id", "")
    _build_weapon_list()
    _ensure_combat_behavior_tree()

func _generate_wander_route():
    for i in 4:
        var angle = randf() * TAU
        var dist = randf_range(2500, 12000)
        route_points.append(system_center + Vector2.from_angle(angle) * dist)

func _pick_next_target():
    if route_points.is_empty():
        target_pos = system_center
        return
    route_index = route_index % route_points.size()
    target_pos = route_points[route_index]

func _physics_process(delta: float):
    if not alive:
        return
    _process_collisions(delta)

    var _cam = get_viewport().get_camera_2d()
    var _cam_dist: float = 99999.0
    if _cam:
        _cam_dist = global_position.distance_to(_cam.global_position)


    if _cam_dist <= 12000:
        var _need_redraw = damage_flash > 0 or _hull_cache_dirty
        var is_moving = velocity.length() > 15
        if is_moving != _was_moving:
            _was_moving = is_moving
            _need_redraw = true
        if health != _prev_health:
            _prev_health = health
            _need_redraw = true
        if not _need_redraw:
            _cam_check_timer -= delta
            if _cam_check_timer <= 0:
                _cam_check_timer = 0.5
                var cam_near = _cam_dist < 5200
                if cam_near != _was_cam_near:
                    _was_cam_near = cam_near
                    _need_redraw = true
        if _need_redraw:
            queue_redraw()

    damage_flash = maxf(damage_flash - delta * 4.0, 0.0)
    _engine_flicker += delta
    _running_light_timer += delta
    fire_timer = maxf(fire_timer - delta, 0.0)


    if hostile:
        _update_combat(delta)
        return


    if is_law_enforcement:
        _patrol_scan_timer -= delta
        if combat_target and is_instance_valid(combat_target):
            _update_combat(delta)
            return
        elif _patrol_scan_timer <= 0:
            _patrol_scan_timer = 2.0
            _scan_for_hostiles()

    if wait_timer > 0:
        wait_timer -= delta

        velocity *= 0.95
        position += velocity * delta
        return


    var to_target = target_pos - global_position
    var dist = to_target.length()

    if dist < 80.0:

        match npc_type:
            "trader":
                wait_timer = randf_range(3.0, 8.0)
            "patrol":
                wait_timer = randf_range(1.0, 3.0)
            "science":
                wait_timer = randf_range(5.0, 12.0)
            _:
                wait_timer = randf_range(1.0, 4.0)
        route_index += 1
        _pick_next_target()
    else:
        var dir = to_target.normalized()

        var speed_mult = clampf(dist / 300.0, 0.3, 1.0)
        velocity += dir * acceleration * delta
        velocity = velocity.limit_length(max_speed * speed_mult)


    _apply_star_avoidance(delta)

    position += velocity * delta


    if velocity.length() > 10:
        var target_rot = velocity.angle()
        rotation = lerp_angle(rotation, target_rot, 4.0 * delta)

func _update_combat(delta: float):

    if not combat_target or not is_instance_valid(combat_target):
        combat_target = null
        if is_law_enforcement:
            _scan_for_hostiles()
        else:
            var players = get_tree().get_nodes_in_group("player")
            if not players.is_empty():
                combat_target = players[0]

    if not combat_target:
        velocity *= 0.98
        position += velocity * delta
        return


    for w in _npc_weapons:
        w.cooldown = maxf(w.cooldown - delta, 0.0)


    for i in range(_npc_rail_charges.size() - 1, -1, -1):
        var ch = _npc_rail_charges[i]
        ch.timer += delta
        if ch.timer >= NPC_RAIL_CHARGE_TIME:
            _fire_npc_railgun(ch.gun_idx)
            _npc_rail_charges.remove_at(i)


    for i in _npc_rail_cooldowns.size():
        _npc_rail_cooldowns[i] = maxf(_npc_rail_cooldowns[i] - delta, 0.0)

    if _combat_bt == null or not is_instance_valid(_combat_bt):
        _ensure_combat_behavior_tree()

    if _combat_bt != null and is_instance_valid(_combat_bt):
        _combat_bt.blackboard.set_value("delta", delta)
        var status := _combat_bt.tick()
        if status != BeehaveTree.FAILURE:
            position += velocity * delta
            if velocity.length() > 10:
                rotation = lerp_angle(rotation, velocity.angle(), 8.0 * delta)
            return

    velocity *= pow(0.98, delta * 60.0)
    _apply_star_avoidance(delta)
    position += velocity * delta
    if velocity.length() > 10:
        rotation = lerp_angle(rotation, velocity.angle(), 8.0 * delta)

func _update_combat_standard(delta: float):

    var to_player = combat_target.global_position - global_position
    var dist = to_player.length()
    var dir = to_player.normalized()
    var perp = Vector2( - dir.y, dir.x) * _juke_dir
    var accel = acceleration * 1.4


    _juke_timer -= delta
    if _juke_timer <= 0:
        _juke_timer = randf_range(0.4, 1.2)
        _juke_dir = - _juke_dir if randf() < 0.6 else _juke_dir


    _mode_timer -= delta
    if _mode_timer <= 0:
        _combat_mode = randi() % 3
        match _combat_mode:
            0: _mode_timer = randf_range(2.0, 4.0)
            1: _mode_timer = randf_range(1.0, 2.5)
            2: _mode_timer = randf_range(1.5, 3.0)


    if dist > aggro_range * 2.5:
        velocity += dir * accel * delta
        velocity = velocity.limit_length(max_speed)
    else:
        match _combat_mode:
            0:
                velocity += perp * accel * 0.9 * delta
                if dist > orbit_distance * 1.2:
                    velocity += dir * accel * 0.7 * delta
                elif dist < orbit_distance * 0.5:
                    velocity -= dir * accel * 0.4 * delta
                velocity = velocity.limit_length(max_speed)
            1:
                velocity += dir * accel * 1.3 * delta

                velocity += perp * accel * 0.25 * sin(_juke_timer * 8.0) * delta
                velocity = velocity.limit_length(max_speed * 1.15)
            2:
                velocity -= dir * accel * 0.5 * delta
                velocity += perp * accel * 1.1 * delta
                velocity = velocity.limit_length(max_speed * 1.05)


    if dist < aggro_range * 1.5:
        _fire_all_weapons()

    _apply_star_avoidance(delta)
    position += velocity * delta

    if velocity.length() > 10:
        rotation = lerp_angle(rotation, velocity.angle(), 8.0 * delta)

func _update_combat_hit_and_run(delta: float):

    var to_target = combat_target.global_position - global_position
    var dist = to_target.length()
    var dir = to_target.normalized()
    var accel = acceleration * 1.4

    match _hr_phase:
        HRPhase.APPROACH:

            velocity += dir * accel * 1.5 * delta
            var weave = Vector2( - dir.y, dir.x) * sin(_juke_timer * 6.0) * 0.3
            velocity += weave * accel * delta
            velocity = velocity.limit_length(max_speed * 1.2)
            if dist < aggro_range * 0.9:
                _hr_phase = HRPhase.ATTACK
                _hr_attack_timer = HR_ATTACK_WINDOW
                _juke_dir = [-1.0, 1.0][randi() % 2]
        HRPhase.ATTACK:
            _hr_attack_timer -= delta
            var perp = Vector2( - dir.y, dir.x) * _juke_dir
            velocity += perp * accel * 1.0 * delta
            if dist > orbit_distance * 1.5:
                velocity += dir * accel * 0.7 * delta
            elif dist < orbit_distance * 0.4:
                velocity -= dir * accel * 0.6 * delta
            velocity = velocity.limit_length(max_speed * 1.1)
            _fire_all_weapons()
            if _hr_attack_timer <= 0 or _all_rails_on_cooldown():
                _hr_phase = HRPhase.DISENGAGE
                _hr_disengage_timer = HR_DISENGAGE_TIME
                _juke_dir = [-1.0, 1.0][randi() % 2]
        HRPhase.DISENGAGE:
            _hr_disengage_timer -= delta

            var flee_perp = Vector2( - dir.y, dir.x) * _juke_dir
            velocity -= dir * accel * 1.2 * delta
            velocity += flee_perp * accel * 0.6 * delta
            velocity = velocity.limit_length(max_speed * HR_DISENGAGE_SPEED_MULT)
            if _hr_disengage_timer <= 0:
                _hr_phase = HRPhase.APPROACH

    _juke_timer += delta
    _apply_star_avoidance(delta)
    position += velocity * delta

    if velocity.length() > 10:
        rotation = lerp_angle(rotation, velocity.angle(), 8.0 * delta)

func _apply_star_avoidance(delta: float):

    var to_star = system_center - global_position
    var star_dist = to_star.length()
    var danger_radius: float = 3000.0
    if star_dist < danger_radius and star_dist > 10.0:
        var avoidance_strength = (1.0 - star_dist / danger_radius)
        avoidance_strength = avoidance_strength * avoidance_strength
        var flee_dir = - to_star.normalized()
        velocity += flee_dir * acceleration * 3.0 * avoidance_strength * delta

func _build_weapon_list():

    _npc_weapons.clear()
    _npc_railgun_count = 0
    _npc_rail_data.clear()
    for mod in ship_modules:
        var d = mod.get("data", {})
        var mod_type = d.get("type", mod.get("type", ""))
        if mod_type != "weapon":
            continue
        var mod_id = mod.get("id", "")

        var full_data = DataManager.modules.get(mod_id, d) if mod_id != "" and not mod_id.begins_with("npc_mod_") else d
        var stats = full_data.get("stats", d.get("stats", {}))
        var subtype = full_data.get("subtype", d.get("subtype", "energy"))
        var gp = mod.get("grid_pos", [0, 0])
        if subtype == "railgun" or "railgun" in mod_id:
            _npc_railgun_count += 1
            _npc_rail_data.append({
                "grid_pos": gp, 
                "damage": stats.get("damage", 200), 
                "speed": stats.get("projectile_speed", 2000), 
                "shield_pierce": stats.get("shield_pierce", 0.7), 
            })
            continue

        var npc_fire_rate = stats.get("fire_rate", fire_rate) * 3.0
        _npc_weapons.append({
            "subtype": subtype, 
            "damage": stats.get("damage", projectile_damage), 
            "speed": stats.get("projectile_speed", projectile_speed), 
            "fire_rate": npc_fire_rate, 
            "cooldown": randf() * 0.5, 
            "shield_pierce": stats.get("shield_pierce", 0.0), 
            "splash_radius": stats.get("splash_radius", 0), 
            "tracking": stats.get("tracking", 0.0), 
            "grid_pos": gp, 
        })


    _npc_rail_cooldowns.resize(_npc_railgun_count)
    _npc_rail_cooldowns.fill(0.0)

func _any_rail_ready() -> bool:
    for cd in _npc_rail_cooldowns:
        if cd <= 0:
            return true
    return false

func _all_rails_on_cooldown() -> bool:
    for cd in _npc_rail_cooldowns:
        if cd <= 0:
            return false
    return true

func _fire_railgun_volley():

    for i in _npc_rail_cooldowns.size():
        if _npc_rail_cooldowns[i] <= 0:
            _npc_rail_cooldowns[i] = NPC_RAIL_COOLDOWN
            _npc_rail_charges.append({timer = 0.0, gun_idx = i})
            AudioManager.play_sfx("warp_charge", 0.03, 0.1)
            return

func _fire_npc_railgun(gun_idx: int = 0):

    if not combat_target or not is_instance_valid(combat_target):
        return
    var aim_dir = (combat_target.global_position - global_position).normalized()

    var rd = _npc_rail_data[gun_idx] if gun_idx < _npc_rail_data.size() else {}
    var local_pos = _hex_to_local(rd.get("grid_pos", [0, 0]))
    var spawn_pos = global_position + local_pos.rotated(rotation) + aim_dir * MCELL
    if _proj_script == null:
        return
    var proj = Area2D.new()
    proj.set_script(_proj_script)
    proj.source = "enemy"
    proj.direction = aim_dir
    proj.speed = rd.get("speed", 2000)
    proj.damage = rd.get("damage", 200)
    proj.proj_type = "railgun"
    proj.proj_color = Color(0.7, 0.85, 1.0)
    proj.proj_size = 3.0
    proj.shield_pierce = rd.get("shield_pierce", 0.7)
    proj.rotation = aim_dir.angle()
    proj.sprite_sheet = _spr_railgun
    proj.sprite_scale = 1.4
    proj.sprite_flip_h = false
    get_parent().add_child(proj)
    proj.global_position = spawn_pos
    AudioManager.play_sfx("railgun_fire", 0.5, 0.0)

func _fire_all_weapons():

    if not combat_target or not is_instance_valid(combat_target):
        return
    var aim_dir = (combat_target.global_position - global_position).normalized()
    if _proj_script == null:
        return
    var source = "patrol" if (is_law_enforcement and not hostile) else "enemy"
    for w in _npc_weapons:
        if w.cooldown > 0:
            continue
        w.cooldown = w.fire_rate

        var local_pos = _hex_to_local(w.grid_pos)
        var spawn_pos = global_position + local_pos.rotated(rotation) + aim_dir * MCELL
        var proj = Area2D.new()
        proj.set_script(_proj_script)
        proj.source = source
        proj.direction = aim_dir
        proj.speed = w.speed
        proj.damage = w.damage
        proj.shield_pierce = w.get("shield_pierce", 0.0)
        proj.rotation = aim_dir.angle()
        match w.subtype:
            "missile":
                proj.proj_type = "missile"
                proj.proj_color = Color(0.2, 0.7, 1.0)
                proj.proj_size = 5.0
                proj.homing_strength = w.get("tracking", 0.6) * 5.0
                proj.homing_target = combat_target
                proj.lifetime = 4.0
                proj.splash_radius = w.get("splash_radius", 40)
                proj.sprite_sheet = _spr_missile
                proj.sprite_scale = 1.6
                proj.sprite_flip_h = false
                AudioManager.play_sfx("heavy_shot", 0.3, 0.08)
            "torpedo":
                proj.proj_type = "missile"
                proj.proj_color = Color(1.0, 0.3, 0.15)
                proj.proj_size = 7.0
                proj.homing_strength = w.get("tracking", 0.4) * 3.5
                proj.homing_target = combat_target
                proj.lifetime = 6.0
                proj.splash_radius = w.get("splash_radius", 80)
                proj.sprite_sheet = _spr_missile
                proj.sprite_scale = 2.0
                proj.sprite_flip_h = false
                AudioManager.play_sfx("heavy_shot", 0.4, 0.05)
            "lance":
                proj.proj_color = Color(0.3, 0.9, 1.0)
                proj.proj_size = 2.0
                proj.lifetime = 1.2
                proj.sprite_sheet = _spr_pulse_mk2
                proj.sprite_scale = 0.88
                proj.sprite_flip_h = false
                AudioManager.play_sfx("laser_fire", 0.2, 0.15)
            "kinetic":
                proj.proj_color = Color(1.0, 0.8, 0.25)
                proj.proj_size = 2.5
                proj.lifetime = 1.2
                proj.sprite_sheet = _spr_autocannon
                proj.sprite_scale = 0.6
                AudioManager.play_sfx("cannon_fire", 0.25, 0.1)
            _:
                proj.proj_color = ship_color.lightened(0.3)
                proj.proj_size = 2.0
                proj.lifetime = 1.0
                proj.sprite_sheet = _spr_pulse_mk1
                proj.sprite_scale = 0.88
                AudioManager.play_sfx("laser_fire", 0.15, 0.1)
        get_parent().add_child(proj)
        proj.global_position = spawn_pos

    if _npc_railgun_count > 0 and _any_rail_ready():
        _fire_railgun_volley()

func _scan_for_hostiles():

    var closest: Node2D = null
    var closest_dist: float = aggro_range * 2.0
    for npc in get_tree().get_nodes_in_group("npc_ships"):
        if npc == self or not npc.alive:
            continue
        if npc.hostile:
            var d = global_position.distance_to(npc.global_position)
            if d < closest_dist:
                closest_dist = d
                closest = npc
    if closest:
        combat_target = closest

func become_hostile_to_player():

    if is_law_enforcement and not hostile:
        hostile = true
        combat_target = null
        add_to_group("enemies")


func _ensure_combat_behavior_tree() -> void:
    if _combat_bt != null and is_instance_valid(_combat_bt):
        _combat_bt.queue_free()
    _combat_bt = NpcShipBTBuilder.build_tree()
    add_child(_combat_bt)

func take_damage(amount: float, _shield_pierce: float = 0.0, hit_world_pos: Vector2 = Vector2.ZERO):
    if not alive:
        return

    if not combat_target or not is_instance_valid(combat_target):
        var players = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            combat_target = players[0]
            if not hostile:
                hostile = true
                _apply_hostility()
    var pierce = amount * _shield_pierce
    var blocked = amount - pierce
    var hull_dmg: float = 0.0
    if shields > 0 and blocked > 0:
        shields -= blocked
        if shields < 0:
            hull_dmg = - shields + pierce
            shields = 0
        else:
            hull_dmg = pierce
    else:
        hull_dmg = amount

    if hull_dmg > 0 and not ship_modules.is_empty():
        var hit_cell = _find_hit_cell(hit_world_pos)
        var dealt: float = 0.0
        if hit_cell != Vector2i(-9999, -9999):
            for mod in ship_modules:
                var cells = GameManager.get_mod_hex_cells(mod)
                if hit_cell in cells:
                    dealt = GameManager.damage_module(mod, hull_dmg)
                    break
        if dealt <= 0:

            var alive_mods: Array = []
            for mod in ship_modules:
                if mod.get("hp", 1.0) > 0:
                    alive_mods.append(mod)
            if not alive_mods.is_empty():
                GameManager.damage_module(alive_mods[randi() % alive_mods.size()], hull_dmg)

        var total_hp: float = 0.0
        for mod in ship_modules:
            total_hp += maxf(mod.get("hp", 0), 0)
        health = total_hp
        hull_hp = health
        _hull_cache_dirty = true
    damage_flash = 1.0
    if health <= 0:
        _on_death()

func _on_death():
    alive = false
    if placed_npc_id != "":
        GameManager.killed_placed_npcs[placed_npc_id] = GameManager.total_game_hours
    died.emit(npc_id, global_position)
    queue_free()

func get_hail_data() -> Dictionary:

    var result = {
        "npc_id": npc_id,
        "name": ship_name,
        "faction": faction_id,
        "type": npc_type,
        "hostile": hostile,
        "health_pct": health / max_health if max_health > 0 else 0.0,
        "hail_event_id": hail_event_id,
        "placed_npc_id": placed_npc_id,
    }

    var sys_ships = GameManager.npc_ships.get(GameManager.current_system, [])
    for ship in sys_ships:
        if ship.get("id") == npc_id:
            result["crew"] = ship.get("crew", [])
            result["cargo"] = ship.get("cargo", {})
            result["job"] = ship.get("job", 0)
            result["credits"] = ship.get("credits", 0)
            break
    return result





@export var static_hull_path: String = ""
var _static_hull_tex: Texture2D = null
var _static_hull_loaded: bool = false
var _static_hull_half: Vector2 = Vector2.ZERO

func _draw():
    if not alive:
        return

    var cam = get_viewport().get_camera_2d()
    if cam:
        if global_position.distance_to(cam.global_position) > 5000:
            return

    # Static hull short-circuit — load a PNG from an asset pack instead of
    # rendering the procedural ship. Damage flash and flame trails still
    # work; only the hull silhouette is replaced.
    if static_hull_path != "":
        if not _static_hull_loaded:
            _static_hull_loaded = true
            var loaded = load(static_hull_path)
            if loaded is Texture2D:
                _static_hull_tex = loaded
                var sz = loaded.get_size()
                _static_hull_half = Vector2(sz.x * 0.5, sz.y * 0.5)
            else:
                push_warning("npc_ship: failed to load static_hull_path " + static_hull_path)
        if _static_hull_tex != null:
            var t = _engine_flicker
            _draw_engine_flames(t, velocity.length(), max_speed)
            var tint = Color(1, 1, 1, 1)
            if damage_flash > 0:
                var fl = clampf(damage_flash, 0, 1)
                tint = Color(1.0 + fl * 3.0, 1.0 + fl * 3.0, 1.0 + fl * 3.0, 1.0)
            draw_texture_rect(_static_hull_tex, Rect2(-_static_hull_half, _static_hull_half * 2), false, tint)
            return

    var time = _engine_flicker
    var flash_lerp = damage_flash * 0.6


    _draw_engine_flames(time, velocity.length(), max_speed)


    _draw_hull(flash_lerp)


    _draw_module_accents(time)


    if ship_style != "":
        _draw_alien_effects(time)


    _draw_running_lights_auto(time)


    _draw_health_bar()


    var _hover_showing = _draw_hover_tooltip()
    if not _hover_showing:
        var player_nodes = get_tree().get_nodes_in_group("player")
        if not player_nodes.is_empty():
            var pdist = global_position.distance_to(player_nodes[0].global_position)
            if pdist < 250:
                var font = ThemeDB.fallback_font
                var label_alpha = clampf(1.0 - pdist / 250.0, 0.0, 0.6)
                var label_col = ship_color
                label_col.a = label_alpha
                var tw = font.get_string_size(ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
                draw_string(font, Vector2( - tw * 0.5, - ship_size - 8), ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_col)

func _draw_hover_tooltip() -> bool:

    var local_mouse = get_local_mouse_position()
    if local_mouse.length() > _ship_extent + 15.0:
        return false


    var data = get_hail_data()
    var job: int = int(data.get("job", 0))
    var cargo: Dictionary = data.get("cargo", {})
    var crew: Array = data.get("crew", [])
    var credits: int = int(data.get("credits", 0))


    var lines: Array = []
    lines.append(ship_name)


    var fdata = DataManager.galaxy_data.get("factions", {})
    var fname = fdata.get(faction_id, {}).get("name", faction_id.capitalize())
    if hostile:
        lines.append(fname + "  [HOSTILE]")
    else:
        lines.append(fname)


    var job_label: String
    match job:
        GameManager.NpcJob.HAULING: job_label = "Hauling cargo"
        GameManager.NpcJob.MINING: job_label = "Mining operations"
        GameManager.NpcJob.PATROL: job_label = "On patrol"
        GameManager.NpcJob.BOUNTY_HUNT: job_label = "Hunting bounties"
        GameManager.NpcJob.EXPLORING: job_label = "Exploration survey"
        GameManager.NpcJob.DOCKED: job_label = "Docked / refueling"
        _: job_label = "Idle"
    lines.append(job_label)


    var total_cargo: int = 0
    for rk in cargo:
        total_cargo += int(cargo[rk])
    if total_cargo > 0:
        var items: Array = []
        for rk in cargo:
            items.append("%s x%d" % [rk.capitalize(), int(cargo[rk])])
        lines.append("Cargo: " + ", ".join(items))
    else:
        lines.append("Cargo: Empty")


    lines.append("Crew: %d  |  %d cr" % [crew.size(), credits])


    var hp_pct = health / max_health if max_health > 0 else 1.0
    if hp_pct < 1.0 or max_shields > 0:
        var hp_str = "Hull: %d%%" % int(hp_pct * 100)
        if max_shields > 0:
            hp_str += "  Shields: %d%%" % int((shields / max_shields) * 100)
        lines.append(hp_str)


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
    var ty = - _ship_extent - panel_h - 10.0


    draw_rect(Rect2(tx, ty, panel_w, panel_h), Color(0.08, 0.1, 0.15, 0.92))
    draw_rect(Rect2(tx, ty, panel_w, panel_h), Color(0.3, 0.4, 0.55, 0.6), false, 1.0)


    var ly = ty + pad + 10
    for li in lines.size():
        var col: Color
        if li == 0:
            col = Color(0.9, 0.9, 0.95)
        elif li == 1 and hostile:
            col = Color(0.9, 0.3, 0.2)
        elif li == 2:
            col = Color(0.7, 0.8, 0.6)
        else:
            col = Color(0.65, 0.7, 0.8)
        var fs = 11 if li == 0 else 9
        draw_string(font, Vector2(tx + pad, ly), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
        ly += line_h


    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    return true

func _draw_alien_effects(time: float):

    match ship_style:
        "organic":

            for mod in ship_modules:
                var fp = _hex_to_local(mod.get("grid_pos", [0, 0]))
                var pulse = sin(time * 2.0 + fp.x * 0.3) * 0.15 + 0.15
                draw_circle(fp, MCELL * 0.5, Color(ship_color.r, ship_color.g, ship_color.b, pulse))
        "angular":

            for mod in ship_modules:
                var fp = _hex_to_local(mod.get("grid_pos", [0, 0]))
                var corners = HexUtil.hex_corners(fp, MCELL * 0.85)
                for ci in 3:
                    var idx = ci * 2
                    draw_line(corners[idx], corners[(idx + 1) % 6], Color(ship_color, 0.4), 1.0)
        "crystalline":

            for mod in ship_modules:
                var fp = _hex_to_local(mod.get("grid_pos", [0, 0]))
                var sparkle = abs(sin(time * 4.0 + fp.x * 2.0 + fp.y * 3.0))
                if sparkle > 0.85:
                    draw_circle(fp + Vector2(sin(time + fp.y) * 2, cos(time + fp.x) * 2), 1.0, Color(1, 1, 1, sparkle * 0.6))
        "hive":

            for i in ship_modules.size():
                var fp1 = _hex_to_local(ship_modules[i].get("grid_pos", [0, 0]))
                for j in range(i + 1, ship_modules.size()):
                    var fp2 = _hex_to_local(ship_modules[j].get("grid_pos", [0, 0]))
                    if fp1.distance_to(fp2) < MCELL * 3:
                        var pulse = sin(time * 1.5 + float(i)) * 0.1 + 0.15
                        draw_line(fp1, fp2, Color(ship_color.r, ship_color.g, ship_color.b, pulse), 0.5)
        "fluid":

            var pulse = sin(time * 1.0) * 0.03 + 0.08
            var extent = _compute_extent()
            draw_circle(Vector2.ZERO, extent * 0.8, Color(ship_color.r, ship_color.g, ship_color.b, pulse))


# ── Collision Damage ──────────────────────────────────────────────────

func _should_collide_with(other: Area2D) -> bool:
    if other.is_in_group("enemies") or other.is_in_group("station_entities"):
        return true
    if other.is_in_group("player") and hostile:
        return true
    return false
