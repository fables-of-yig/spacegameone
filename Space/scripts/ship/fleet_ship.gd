extends "res://Space/scripts/ship/ship_base.gd"





signal died(fleet_id: String, pos: Vector2)

var fleet_id: String = ""
var fleet_name: String = ""
var core_id: String = "core_pod"


var velocity: Vector2 = Vector2.ZERO
var max_speed: float = 300.0
var acceleration: float = 400.0
var target_rotation: float = 0.0


var shield_recharge: float = 0.0
var shield_delay_timer: float = 0.0


var order: int = 0
var order_target_id: String = ""
var order_target_node: Node2D = null


var orbit_angle: float = 0.0
var orbit_dist: float = 200.0
var patrol_angle: float = 0.0
var patrol_center: Vector2 = Vector2.ZERO
var system_center: Vector2 = Vector2.ZERO
var mine_target: Node2D = null
var mine_beam_timer: float = 0.0


var player_controlled: bool = false
var aim_angle: float = 0.0
var weapon_modules: Array = []
var fire_rate: float = 0.12
var can_fire: bool = true
var input_blocked: bool = false
var projectile_scene: PackedScene = null
var secondary_weapons: Array = []
var active_secondary_idx: int = 0
var secondary_cooldowns: Dictionary = {}


var handbrake_target: Node2D = null
var orbit_locked: bool = false
const HANDBRAKE_ORBIT_RANGE: float = 350.0
const HANDBRAKE_ORBIT_DIST: float = 80.0
const HANDBRAKE_BRAKE_FORCE: float = 800.0


var weapon_charging: bool = false
var weapon_charge_timer: float = 0.0
var weapon_charge_time: float = 0.0
var weapon_charge_type: String = ""
var weapon_charge_data: Dictionary = {}
const RAILGUN_CHARGE_TIME: float = 0.6
const MACRO_CHARGE_TIME: float = 0.35


const FUEL_BURN_RATE: float = 0.4
const FUEL_EMPTY_MULT: float = 0.25
var scooping: bool = false
var boost_impulse: float = 300.0
var boost_cooldown: float = 1.5
var boost_cd_timer: float = 0.0
var boost_ready: bool = true
var friction: float = 40.0


var power_preset: int = 0
var power_mult_weapon: float = 1.0
var power_mult_shield: float = 1.0
var power_mult_engine: float = 1.0
const POWER_PRESETS = [
    {"name": "BALANCED", "weapon": 1.0, "shield": 1.0, "engine": 1.0}, 
    {"name": "WEAPONS", "weapon": 1.4, "shield": 0.6, "engine": 0.85}, 
    {"name": "SHIELDS", "weapon": 0.7, "shield": 1.5, "engine": 0.85}, 
    {"name": "ENGINES", "weapon": 0.75, "shield": 0.7, "engine": 1.4}, 
]


var star_speed_mult: float = 1.0
var nearest_star_pos: Vector2 = Vector2.ZERO


var running_light_phase: float = 0.0


var _was_moving: bool = false
var _prev_health: float = -1.0
var _prev_order: int = -1
var _cam_check_timer: float = 0.0
var _was_cam_near: bool = false

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("fleet_ships")

    _init_collision(30.0)

    orbit_angle = randf() * TAU
    patrol_angle = randf() * TAU

    projectile_scene = preload("res://Space/scenes/projectile.tscn")

func setup(ship_data: Dictionary):

    fleet_id = ship_data.get("id", "")
    fleet_name = ship_data.get("name", "Fleet Ship")
    core_id = ship_data.get("core_id", "core_pod")
    ship_modules = ship_data.get("modules", [])
    order = int(ship_data.get("order", 0))
    order_target_id = ship_data.get("order_target", "")
    health = float(ship_data.get("health", 100))
    max_health = float(ship_data.get("max_health", 100))
    max_shields = float(ship_data.get("max_shield", 0))
    shields = float(ship_data.get("shield", 0))
    shield_recharge = float(ship_data.get("shield_regen", 0))
    max_speed = float(ship_data.get("max_speed", 300))
    acceleration = float(ship_data.get("acceleration", 400))

    ship_color = Color(0.4, 0.55, 0.75)

    var wp = ship_data.get("world_pos", [0, 0])
    if wp is Array and wp.size() >= 2:
        global_position = Vector2(float(wp[0]), float(wp[1]))
    rotation = float(ship_data.get("rotation", 0))

    for mod in ship_modules:
        if not mod.has("data"):
            mod["data"] = DataManager.modules.get(mod.get("id", ""), {})
        GameManager.init_module_hp(mod)

    var total_hp: float = 0.0
    var total_max: float = 0.0
    for mod in ship_modules:
        total_max += mod.get("max_hp", 0)
        total_hp += mod.get("hp", 0)
    if total_max > 0:
        max_health = total_max
        health = total_hp

    _compute_grid_center()
    _rebuild_hull_cache()

    _rebuild_module_colliders()

    weapon_modules.clear()
    secondary_weapons.clear()
    secondary_cooldowns.clear()
    active_secondary_idx = 0
    for mod in ship_modules:
        var mdata = mod.get("data", {})
        if mdata.get("type", "") == "weapon":
            var stats = mdata.get("stats", {}).duplicate()
            var mod_info = DataManager.modules.get(mod.get("id", ""), {})
            stats["subtype"] = mod_info.get("subtype", "energy")
            stats["name"] = mod_info.get("name", "Weapon")
            var wclass = mod_info.get("weapon_class", "primary")
            if wclass == "secondary":
                secondary_weapons.append(stats)
            else:
                weapon_modules.append(stats)
    boost_impulse = max_speed * 0.6
    nearest_star_pos = system_center

func take_control():

    player_controlled = true
    add_to_group("player")
    power_preset = 0
    power_mult_weapon = 1.0
    power_mult_shield = 1.0
    power_mult_engine = 1.0

func release_control():

    player_controlled = false
    input_blocked = false
    orbit_locked = false
    handbrake_target = null
    weapon_charging = false
    if is_in_group("player"):
        remove_from_group("player")

func _physics_process(delta: float):
    _process_collisions(delta)

    for k in secondary_cooldowns.keys():
        secondary_cooldowns[k] = maxf(secondary_cooldowns[k] - delta, 0.0)

    if weapon_charging:
        weapon_charge_timer += delta
        if weapon_charge_timer >= weapon_charge_time:
            weapon_charging = false
            match weapon_charge_type:
                "railgun":
                    _spawn_proj(aim_angle, weapon_charge_data.get("damage", 30) * power_mult_weapon, weapon_charge_data.get("projectile_speed", 1200), weapon_charge_data.get("shield_pierce", 0.3), "railgun")
                "macro":
                    _spawn_proj(aim_angle, weapon_charge_data.get("damage", 25) * power_mult_weapon, weapon_charge_data.get("projectile_speed", 600), weapon_charge_data.get("shield_pierce", 0.0), "kinetic")

    var ship_data = GameManager.get_fleet_ship(fleet_id)
    if ship_data.is_empty():
        queue_free()
        return
    order = int(ship_data.get("order", 0))
    order_target_id = ship_data.get("order_target", "")
    health = float(ship_data.get("health", max_health))


    if player_controlled:
        _handle_player_control(delta)
    else:

        match order:
            0: _order_hold(delta)
            1: _order_orbit(delta)
            2: _order_patrol(delta)
            3: _order_escort(delta)
            4: _order_mine(delta)
            5: _order_scoop(delta)
            6: _order_transport(delta)

        if velocity.length() > 5:
            target_rotation = velocity.angle()
        rotation = lerp_angle(rotation, target_rotation, 3.0 * delta)


    position += velocity * delta


    if shield_delay_timer > 0:
        shield_delay_timer -= delta
    elif shields < max_shields and shield_recharge > 0:
        shields = minf(shields + shield_recharge * power_mult_shield * delta, max_shields)


    var _had_flash = damage_flash > 0
    if damage_flash > 0:
        damage_flash -= delta * 3.0


    ship_data["world_pos"] = [global_position.x, global_position.y]
    ship_data["rotation"] = rotation
    ship_data["shield"] = shields

    running_light_phase += delta * 2.5


    var _fleet_cam = get_viewport().get_camera_2d()
    var _fleet_cam_dist: float = 99999.0
    if _fleet_cam:
        _fleet_cam_dist = global_position.distance_to(_fleet_cam.global_position)
    if _fleet_cam_dist <= 12000:
        var _need_redraw = _had_flash or _hull_cache_dirty or player_controlled
        var is_moving = velocity.length() > 15
        if is_moving != _was_moving:
            _was_moving = is_moving
            _need_redraw = true
        if health != _prev_health:
            _prev_health = health
            _need_redraw = true
        if order != _prev_order:
            _prev_order = order
            _need_redraw = true

        if not _need_redraw and not player_controlled:
            if order == 4 and mine_target and is_instance_valid(mine_target):
                _need_redraw = true
            elif order == 5:
                _need_redraw = true
            elif order == 6:
                if ship_data.get("transport_state", "moving") in ["loading", "unloading"]:
                    _need_redraw = true
        if not _need_redraw:
            _cam_check_timer -= delta
            if _cam_check_timer <= 0:
                _cam_check_timer = 0.5
                var cam_near = _fleet_cam_dist < 5200
                if cam_near != _was_cam_near:
                    _was_cam_near = cam_near
                    _need_redraw = true
        if _need_redraw:
            queue_redraw()



func _handle_player_control(delta: float):
    if not input_blocked:
        _handle_pc_movement(delta)
        _handle_pc_boost(delta)
        _handle_pc_rotation(delta)
        _handle_pc_shooting()
        _handle_pc_power_presets()
    elif orbit_locked and handbrake_target and is_instance_valid(handbrake_target):
        _handle_handbrake(delta)

func _handle_pc_movement(delta: float):
    _update_star_speed_mult()
    var ship_data = GameManager.get_fleet_ship(fleet_id)
    var ship_fuel: float = ship_data.get("fuel", 0)
    var fuel_mult = 1.0 if ship_fuel > 0 else FUEL_EMPTY_MULT
    var effective_speed = max_speed * star_speed_mult * power_mult_engine * fuel_mult
    var effective_accel = acceleration * star_speed_mult * power_mult_engine * fuel_mult
    var facing_dir = Vector2.from_angle(rotation)


    if Input.is_action_just_pressed("handbrake"):
        if orbit_locked:
            orbit_locked = false
            handbrake_target = null
        else:
            var lockable = _find_nearest_lockable()
            if lockable:
                handbrake_target = lockable
                orbit_locked = true
            else:
                velocity = velocity.move_toward(Vector2.ZERO, HANDBRAKE_BRAKE_FORCE * 0.5)


    if orbit_locked:
        if not handbrake_target or not is_instance_valid(handbrake_target):
            orbit_locked = false
            handbrake_target = null
        elif global_position.distance_to(handbrake_target.global_position) > HANDBRAKE_ORBIT_RANGE * 3:
            orbit_locked = false
            handbrake_target = null
        elif Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down"):
            orbit_locked = false
            handbrake_target = null
        elif GameManager.using_controller:
            var lstick = GameManager.poll_left_stick()
            if lstick.length() > 0.3:
                orbit_locked = false
                handbrake_target = null

    if orbit_locked and handbrake_target:
        _handle_handbrake(delta)
        return

    var thrust_input: float = 0.0
    if GameManager.using_controller:
        var lstick = GameManager.poll_left_stick()
        thrust_input = - lstick.y
        if thrust_input < 0:
            thrust_input *= 0.5
    if Input.is_action_pressed("move_up"):
        thrust_input = maxf(thrust_input, 1.0)
    if Input.is_action_pressed("move_down"):
        thrust_input = minf(thrust_input, -0.5)

    if absf(thrust_input) > 0.01:
        velocity += facing_dir * thrust_input * effective_accel * delta
        if velocity.length() > effective_speed:
            var boost_decay = maxf(effective_accel * 1.5, 200.0)
            velocity = velocity.move_toward(
                velocity.normalized() * effective_speed, boost_decay * delta)
        else:
            velocity = velocity.limit_length(effective_speed)
        if ship_fuel > 0:
            ship_data["fuel"] = maxf(ship_fuel - absf(thrust_input) * FUEL_BURN_RATE * delta, 0)
    else:
        var decay = friction
        if velocity.length() > effective_speed:
            decay = maxf(friction * 6.0, 200.0)
        velocity = velocity.move_toward(Vector2.ZERO, decay * delta)

func _handle_pc_boost(delta: float):
    if boost_cd_timer > 0:
        boost_cd_timer -= delta
        if boost_cd_timer <= 0:
            boost_ready = true
    var ship_data = GameManager.get_fleet_ship(fleet_id)
    var ship_fuel: float = ship_data.get("fuel", 0)
    if Input.is_action_just_pressed("boost") and boost_ready and ship_fuel > 0:
        var facing = Vector2.from_angle(rotation)
        velocity += facing * boost_impulse
        var boost_cap = max_speed * 1.6
        if velocity.length() > boost_cap:
            velocity = velocity.normalized() * boost_cap
        boost_ready = false
        boost_cd_timer = boost_cooldown
        ship_data["fuel"] = maxf(ship_fuel - 1.5, 0)
        AudioManager.play_sfx("boost", 0.6)

func _handle_pc_rotation(delta: float):
    var turn_input: float = 0.0
    if Input.is_action_pressed("move_right"):
        turn_input += 1.0
    if Input.is_action_pressed("move_left"):
        turn_input -= 1.0
    if GameManager.using_controller:
        var lstick = GameManager.poll_left_stick()
        if absf(lstick.x) > absf(turn_input):
            turn_input = lstick.x
    rotation += turn_input * 4.0 * delta

    if GameManager.using_controller:
        var rstick = GameManager.poll_right_stick()
        if rstick.length() > 0.1:
            aim_angle = rstick.angle()
    else:
        var mouse_pos = get_global_mouse_position()
        aim_angle = (mouse_pos - global_position).angle()

func _handle_handbrake(delta: float):
    var to_target = handbrake_target.global_position - global_position
    var dist = to_target.length()
    var dir = to_target.normalized()
    if dist > HANDBRAKE_ORBIT_DIST * 1.5:
        velocity = velocity.move_toward(dir * 60.0, HANDBRAKE_BRAKE_FORCE * delta)
    elif dist < HANDBRAKE_ORBIT_DIST * 0.5:
        velocity = velocity.move_toward( - dir * 40.0, HANDBRAKE_BRAKE_FORCE * delta)
    else:
        var tangent = Vector2( - dir.y, dir.x)
        var orbit_speed = 30.0
        var radial_correction = dir * (dist - HANDBRAKE_ORBIT_DIST) * 2.0
        velocity = velocity.move_toward(tangent * orbit_speed + radial_correction, HANDBRAKE_BRAKE_FORCE * delta)

func _find_nearest_lockable() -> Node2D:
    var best: Node2D = null
    var best_dist: float = HANDBRAKE_ORBIT_RANGE
    for poi in get_tree().get_nodes_in_group("pois"):
        if not is_instance_valid(poi):
            continue
        var d = global_position.distance_to(poi.global_position)
        if d < best_dist:
            best_dist = d
            best = poi
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(enemy):
            continue
        var d = global_position.distance_to(enemy.global_position)
        if d < best_dist:
            best_dist = d
            best = enemy
    for fs in get_tree().get_nodes_in_group("fleet_ships"):
        if not is_instance_valid(fs) or fs == self:
            continue
        var d = global_position.distance_to(fs.global_position)
        if d < best_dist:
            best_dist = d
            best = fs
    return best

func _handle_pc_shooting():

    if not weapon_modules.is_empty() and Input.is_action_pressed("fire_primary") and can_fire:
        _fire_weapons()
        can_fire = false
        get_tree().create_timer(fire_rate).timeout.connect( func(): can_fire = true)

    if Input.is_action_pressed("fire_secondary"):
        _fire_secondary_weapon()

    if Input.is_action_just_pressed("cycle_secondary") and not secondary_weapons.is_empty():
        active_secondary_idx = (active_secondary_idx + 1) % secondary_weapons.size()
        var w = secondary_weapons[active_secondary_idx]
        var wname = w.get("name", "Unknown")
        var main_node = get_tree().current_scene
        if main_node and "hud_control" in main_node and main_node.hud_control:
            main_node.hud_control.show_bark("WEAPONS", "Secondary: %s" % wname, Color(1.0, 0.8, 0.3), 1.5)

func _fire_secondary_weapon():
    if secondary_weapons.is_empty():
        return
    var idx = active_secondary_idx % secondary_weapons.size()
    var cd = secondary_cooldowns.get(idx, 0.0)
    if cd > 0.0:
        return
    var w = secondary_weapons[idx]
    var subtype = w.get("subtype", "kinetic")
    var dmg = w.get("damage", 30) * power_mult_weapon
    var spd = w.get("projectile_speed", 500)
    var pierce = w.get("shield_pierce", 0.0)
    var wfire_rate = w.get("fire_rate", 1.0)
    match subtype:
        "missile":

            var proj = _spawn_proj(aim_angle, dmg, spd, pierce, "missile")
            if proj:
                AudioManager.play_sfx("laser_fire", 0.6, 0.2)
        "torpedo":
            var proj = _spawn_proj(aim_angle, dmg, spd * 0.6, pierce, "torpedo")
            if proj:
                AudioManager.play_sfx("laser_fire", 0.7, 0.3)
        "lance":
            var proj = _spawn_proj(aim_angle, dmg, spd, pierce, "beam")
            if proj:
                AudioManager.play_sfx("laser_fire", 0.4, 0.15)
        "railgun":
            if not weapon_charging:
                weapon_charging = true
                weapon_charge_timer = 0.0
                weapon_charge_time = RAILGUN_CHARGE_TIME
                weapon_charge_type = "railgun"
                weapon_charge_data = w
                AudioManager.play_sfx("warp_charge", 0.5, 0.0)
        _:

            if not weapon_charging:
                weapon_charging = true
                weapon_charge_timer = 0.0
                weapon_charge_time = MACRO_CHARGE_TIME
                weapon_charge_type = "macro"
                weapon_charge_data = w
    secondary_cooldowns[idx] = wfire_rate

func _fire_weapons():
    var bolts: Array = []
    for w in weapon_modules:
        if w.get("subtype", "") != "missile":
            bolts.append(w)
    if bolts.is_empty():
        return
    if bolts.size() == 1:
        var w = bolts[0]
        @warning_ignore("return_value_discarded")
        _spawn_proj(aim_angle, w.get("damage", 10), w.get("projectile_speed", 800), w.get("shield_pierce", 0.0), w.get("subtype", ""))
    else:
        var spread = minf(bolts.size() * 0.09, 0.45)
        for i in bolts.size():
            var w = bolts[i]
            var t = float(i) / maxf(bolts.size() - 1, 1)
            var angle = aim_angle + lerpf( - spread / 2.0, spread / 2.0, t)
            @warning_ignore("return_value_discarded")
            _spawn_proj(angle, w.get("damage", 10), w.get("projectile_speed", 800), w.get("shield_pierce", 0.0), w.get("subtype", ""))

func _spawn_proj(angle: float, dmg: float, spd: float, pierce: float = 0.0, subtype: String = "") -> Node:
    if not projectile_scene:
        return null
    var proj = projectile_scene.instantiate()
    var muzzle_dist: float = 30.0
    proj.global_position = global_position + Vector2.from_angle(angle) * muzzle_dist
    proj.rotation = angle
    proj.source = "player"
    proj.damage = dmg * power_mult_weapon
    proj.speed = spd
    proj.shield_pierce = pierce
    match subtype:
        "kinetic":
            proj.proj_color = Color(1.0, 0.8, 0.25)
            proj.proj_size = 2.5
        "beam":
            proj.proj_color = Color(0.4, 0.8, 1.0)
            proj.proj_size = 2.0
        "railgun":
            proj.proj_color = Color(0.7, 0.85, 1.0)
            proj.proj_size = 3.5
            proj.lifetime = 1.5
        "missile":
            proj.proj_color = Color(1.0, 0.6, 0.2)
            proj.proj_size = 3.0
        "torpedo":
            proj.proj_color = Color(0.9, 0.3, 0.3)
            proj.proj_size = 4.0
        _:
            proj.proj_color = Color(0.3, 1.0, 0.5)
            proj.proj_size = 3.0
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("laser_fire", 0.5, 0.1)
    return proj

func _handle_pc_power_presets():
    if Input.is_action_just_pressed("cycle_power"):
        _set_power((power_preset + 1) % 4)

func _set_power(preset: int):
    if preset == power_preset:
        return
    power_preset = preset
    var p = POWER_PRESETS[preset]
    power_mult_weapon = p.weapon
    power_mult_shield = p.shield
    power_mult_engine = p.engine
    boost_impulse = max_speed * 0.6

func _update_star_speed_mult():
    var dist = global_position.distance_to(nearest_star_pos)
    if dist <= 1500.0:
        star_speed_mult = lerpf(0.2, 1.0, clampf(dist / 1500.0, 0, 1))
    elif dist <= 14000.0:
        star_speed_mult = lerpf(1.0, 1.3, (dist - 1500.0) / 12500.0)
    else:
        star_speed_mult = 1.3



func _order_hold(delta: float):
    velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)

func _order_orbit(delta: float):

    var target = _find_orbit_target()
    if target:
        _orbit_around(target.global_position, 200.0, delta)
    else:
        _order_hold(delta)

func _order_patrol(delta: float):

    if patrol_center == Vector2.ZERO:
        patrol_center = global_position
    patrol_angle += 0.15 * delta
    var target_pos = patrol_center + Vector2.from_angle(patrol_angle) * 2000.0
    _move_toward_point(target_pos, delta)

func _order_escort(delta: float):

    var players = get_tree().get_nodes_in_group("player")
    if players.is_empty():
        _order_hold(delta)
        return
    var player = players[0]
    var offset = Vector2.from_angle(orbit_angle) * 150.0
    var target_pos = player.global_position + offset
    var dist = global_position.distance_to(player.global_position)
    if dist > 180:
        _move_toward_point(target_pos, delta)
    else:
        velocity = velocity.move_toward(Vector2.ZERO, acceleration * 0.5 * delta)

    orbit_angle += 0.3 * delta

func _order_mine(delta: float):

    if mine_target == null or not is_instance_valid(mine_target):
        mine_target = _find_nearest_asteroid()
    if mine_target:
        _orbit_around(mine_target.global_position, 120.0, delta)
        mine_beam_timer += delta

        var ship_data = GameManager.get_fleet_ship(fleet_id)
        if not ship_data.is_empty():
            ship_data["mine_resource_type"] = mine_target.resource_type
            ship_data["mine_richness"] = mine_target.richness

            var rate = float(ship_data.get("mine_rate", 0))
            if rate > 0 and mine_target.remaining > 0:
                mine_target.remaining = maxf(mine_target.remaining - rate * mine_target.richness * delta * 0.1, 0)
    else:
        mine_beam_timer = 0.0
        _order_patrol(delta)

func _order_scoop(delta: float):

    var sys_pos = _get_system_center()
    _orbit_around(sys_pos, 2800.0, delta)

func _order_transport(delta: float):

    var ship_data = GameManager.get_fleet_ship(fleet_id)
    if ship_data.is_empty():
        _order_patrol(delta)
        return
    var route: Array = ship_data.get("transport_route", [])
    if route.size() < 2:
        _order_patrol(delta)
        return
    var state: String = ship_data.get("transport_state", "moving")
    if state == "loading" or state == "unloading":

        velocity = velocity.lerp(Vector2.ZERO, 3.0 * delta)
        return

    var idx = int(ship_data.get("transport_waypoint_idx", 0))
    var stop_id = route[idx % route.size()]
    var target_pos = _find_colony_position(stop_id)
    if target_pos == Vector2.ZERO:
        _order_patrol(delta)
        return
    var dist = global_position.distance_to(target_pos)
    if dist < 80.0:


        ship_data["transport_state"] = "loading" if idx % 2 == 0 else "unloading"
        ship_data["transport_timer"] = 0.0
        velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
    else:

        var dir = global_position.direction_to(target_pos)
        velocity = velocity.lerp(dir * max_speed * 0.6, 1.5 * delta)

func _find_colony_position(colony_id: String) -> Vector2:

    var colony = GameManager.get_colony(colony_id)
    if colony.is_empty():
        return Vector2.ZERO
    var planet_name = colony.get("planet_name", "")

    for marker in get_tree().get_nodes_in_group("pois"):
        if marker.get("poi_name") == planet_name:
            return marker.global_position

    return system_center + Vector2(randf_range(-500, 500), randf_range(-500, 500))



func _orbit_around(center: Vector2, dist: float, delta: float):
    orbit_angle += (max_speed * 0.3 / maxf(dist, 100.0)) * delta
    var desired_pos = center + Vector2.from_angle(orbit_angle) * dist
    var to_desired = desired_pos - global_position
    var target_vel = to_desired.normalized() * minf(to_desired.length() * 2.0, max_speed * 0.6)
    velocity = velocity.move_toward(target_vel, acceleration * delta)

func _move_toward_point(target: Vector2, delta: float):
    var to_target = target - global_position
    var dist = to_target.length()
    if dist < 20:
        velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
        return
    var desired_speed = minf(dist * 1.5, max_speed)
    var desired_vel = to_target.normalized() * desired_speed
    velocity = velocity.move_toward(desired_vel, acceleration * delta)

    _apply_star_avoidance(delta)

func _apply_star_avoidance(delta: float):

    var to_star = system_center - global_position
    var star_dist = to_star.length()
    var danger_radius: float = 5000.0
    if star_dist < danger_radius and star_dist > 10.0:
        var avoidance_strength = (1.0 - star_dist / danger_radius)
        avoidance_strength = avoidance_strength * avoidance_strength
        var flee_dir = - to_star.normalized()
        velocity += flee_dir * acceleration * 3.0 * avoidance_strength * delta

func _find_orbit_target() -> Node2D:

    var best: Node2D = null
    var best_dist: float = 2000.0
    for poi in get_tree().get_nodes_in_group("pois"):
        var d = global_position.distance_to(poi.global_position)
        if d < best_dist:
            best_dist = d
            best = poi
    return best

func _find_nearest_asteroid() -> Node2D:

    var best: Node2D = null
    var best_dist: float = 3000.0
    for ast in get_tree().get_nodes_in_group("asteroids"):
        if ast.remaining <= 0:
            continue
        var d = global_position.distance_to(ast.global_position)
        if d < best_dist:
            best_dist = d
            best = ast
    return best

func _get_system_center() -> Vector2:

    return system_center



func take_damage(amount: float, _shield_pierce: float = 0.0, hit_world_pos: Vector2 = Vector2.ZERO):
    var hull_dmg: float = amount
    if shields > 0 and _shield_pierce < 1.0:
        var absorbed = amount * (1.0 - _shield_pierce)
        shields -= absorbed
        hull_dmg = amount - absorbed
        if shields < 0:
            hull_dmg += - shields
            shields = 0
        shield_delay_timer = 3.0

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
        _hull_cache_dirty = true
    damage_flash = 1.0

    var ship_data = GameManager.get_fleet_ship(fleet_id)
    if not ship_data.is_empty():
        ship_data["health"] = health
        ship_data["shield"] = shields
    if health <= 0:
        _on_death()

func _on_death():
    died.emit(fleet_id, global_position)
    queue_free()



func _draw():

    var cam = get_viewport().get_camera_2d()
    if cam:
        var dist_to_cam = global_position.distance_to(cam.global_position)
        if dist_to_cam > 5000:
            return
    var time = Time.get_ticks_msec() * 0.001
    var flash_lerp = clampf(damage_flash, 0, 1)


    if not ship_modules.is_empty():
        _draw_modules(time, flash_lerp)
    else:
        _draw_simple_ship(time, flash_lerp)


    if not player_controlled and order == 4 and mine_target and is_instance_valid(mine_target):
        var beam_alpha = sin(mine_beam_timer * 5.0) * 0.2 + 0.5
        var to_ast = mine_target.global_position - global_position
        var beam_col = Color(0.9, 0.7, 0.2, beam_alpha * 0.6)
        draw_line(Vector2.ZERO, to_ast, beam_col, 1.5)

        var spark_off = to_ast + Vector2(sin(time * 8) * 4, cos(time * 11) * 4)
        draw_circle(spark_off, 3.0, Color(0.9, 0.7, 0.2, beam_alpha * 0.4))


    if not player_controlled and order == 5:
        var scoop_alpha = sin(time * 3.0) * 0.15 + 0.3
        var to_star = system_center - global_position
        if to_star.length() > 10:
            var scoop_dir = to_star.normalized() * 40.0
            draw_line(Vector2.ZERO, scoop_dir, Color(0.9, 0.6, 0.1, scoop_alpha), 1.0)
            draw_circle(scoop_dir, 2.0, Color(1.0, 0.8, 0.2, scoop_alpha * 0.5))


    if not player_controlled and order == 6:
        var ship_data = GameManager.get_fleet_ship(fleet_id)
        var tstate = ship_data.get("transport_state", "moving") if not ship_data.is_empty() else "moving"
        if tstate == "loading" or tstate == "unloading":
            var pulse = sin(time * 4.0) * 0.2 + 0.5
            var tcol = Color(0.3, 0.8, 0.5, pulse) if tstate == "loading" else Color(0.8, 0.5, 0.3, pulse)

            for i in 3:
                var off_y = fmod(time * 20.0 + i * 12.0, 30.0)
                if tstate == "unloading":
                    off_y = - off_y
                draw_circle(Vector2(randf_range(-6, 6), -15 - off_y), 2.0, tcol)


    var font = ThemeDB.fallback_font
    draw_string(font, Vector2(-30, -35), fleet_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(0.5, 0.6, 0.75, 0.7))


    if health < max_health:
        var bar_w: float = 30.0
        var bar_h: float = 3.0
        var bar_x: float = - bar_w * 0.5
        var bar_y: float = 28.0
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15))
        var hp_pct = health / maxf(max_health, 1)
        var hp_col = Color(0.3, 0.8, 0.4) if hp_pct > 0.5 else Color(0.85, 0.5, 0.2) if hp_pct > 0.25 else Color(0.9, 0.25, 0.2)
        draw_rect(Rect2(bar_x, bar_y, bar_w * hp_pct, bar_h), hp_col)


    var order_colors = [
        Color(0.5, 0.5, 0.6), 
        Color(0.3, 0.7, 0.9), 
        Color(0.4, 0.8, 0.5), 
        Color(0.6, 0.7, 0.9), 
        Color(0.8, 0.6, 0.3), 
        Color(0.9, 0.7, 0.2), 
        Color(0.7, 0.5, 0.8), 
    ]
    var ocol = order_colors[clampi(order, 0, order_colors.size() - 1)]
    draw_circle(Vector2(0, 34), 2.5, ocol)

func _draw_modules(time: float, flash_lerp: float):

    _draw_engine_flames(time, velocity.length(), max_speed)


    _draw_hull(flash_lerp)


    _draw_module_accents(time)


    _draw_running_lights_auto(time)

func _draw_simple_ship(_time: float, flash_lerp: float):

    var col = ship_color
    if flash_lerp > 0:
        col = col.lerp(Color.WHITE, flash_lerp)
    var pts = PackedVector2Array([
        Vector2(14, 0), 
        Vector2(-10, -8), 
        Vector2(-6, 0), 
        Vector2(-10, 8), 
    ])
    draw_colored_polygon(pts, col)


# ── Collision Damage ──────────────────────────────────────────────────

func _should_collide_with(other: Area2D) -> bool:
    return other.is_in_group("enemies") or other.is_in_group("station_entities")
