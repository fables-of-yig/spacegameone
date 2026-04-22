extends "res://Space/scripts/ship/ship_base.gd"




@export var max_speed: float = 310.0
@export var acceleration: float = 460.0
@export var friction: float = 40.0
@export var rotation_speed: float = 4.0


@export var shield_recharge_delay: float = 1.5
@export var fire_rate: float = 0.12
@export var secondary_fire_rate: float = 0.45


@export var boost_impulse: float = 400.0
@export var boost_cooldown: float = 1.5

var velocity: Vector2 = Vector2.ZERO
var can_fire: bool = true


var power_preset: int = 0
var power_mult_weapon: float = 1.0
var power_mult_shield: float = 1.0
var power_mult_engine: float = 1.0


var staff_mult_weapon: float = 1.0
var staff_mult_shield: float = 1.0
var staff_mult_engine: float = 1.0
var staff_fuel_efficiency: float = 1.0


const FUEL_BURN_RATE: float = 0.24
const FUEL_BOOST_COST: float = 1.5
const FUEL_EMPTY_MULT: float = 0.25


var base_max_speed: float = 440.0
var base_acceleration: float = 660.0
var base_shield_recharge: float = 5.0

const POWER_PRESETS = [
    {"name": "BALANCED", "weapon": 1.0, "shield": 1.0, "engine": 1.0, "repair": 1.0, "color": [0.6, 0.6, 0.6]},
    {"name": "WEAPONS", "weapon": 1.4, "shield": 0.6, "engine": 0.85, "repair": 1.0, "color": [0.9, 0.3, 0.25]},
    {"name": "SHIELDS", "weapon": 0.7, "shield": 1.5, "engine": 0.85, "repair": 1.0, "color": [0.3, 0.5, 1.0]},
    {"name": "ENGINES", "weapon": 0.75, "shield": 0.7, "engine": 1.4, "repair": 1.0, "color": [1.0, 0.6, 0.2]},
    {"name": "REPAIRS", "weapon": 0.7, "shield": 0.7, "engine": 0.85, "repair": 3.0, "color": [0.2, 0.9, 0.4]},
]


var boost_cd_timer: float = 0.0
var boost_ready: bool = true


var ship_weight: float = 1.0
var thrust_ratio: float = 1.0
var aim_angle: float = 0.0
var auto_fire_target: Node2D = null
var input_blocked: bool = false


var cmd_waypoint: Vector2 = Vector2.ZERO
var cmd_has_waypoint: bool = false
var cmd_orbit_target: Node2D = null


var shake_amount: float = 0.0
var camera: Camera2D = null
var death_cause: String = ""

# Radial menu state
var radial_open: int = -1
var radial_options: Array = []
var radial_highlight: int = -1
var radial_current: int = 0
var radial_origin: Vector2 = Vector2.ZERO
const RADIAL_HOLD_TIME: float = 0.25
var _radial_press_time: float = -1.0
var _radial_slot: int = -1
const _RADIAL_ACTIONS: Array = ["cycle_primary", "cycle_secondary", "cycle_special", "cycle_power"]


const AUTO_REPAIR_DELAY: float = 5.0
const AUTO_REPAIR_BASE_TIME: float = 3.0
var auto_repair_speed_mult: float = 1.0
var _last_damage_time: float = -999.0
var _repair_target_idx: int = -1

var projectile_scene: PackedScene


var scan_range: float = 500.0
var scan_speed: float = 1.0
var detection_radius: float = 1500.0
var scan_pulse_radius: float = 0.0
var scan_pulse_active: bool = false
var scan_cooldown: float = 0.0
const SCAN_COOLDOWN_TIME: float = 3.0

signal scan_pulse_hit(target: Node2D)

var parry_active: bool = false
var parry_timer: float = 0.0
var parry_duration: float = 0.9
var parry_spin_angle: float = 0.0
var parry_cooldown: float = 0.0
const PARRY_COOLDOWN_TIME: float = 4.0
const PARRY_BLOWOUT_COOLDOWN: float = 12.0
const PARRY_SPIN_SPEED: float = 30.0
const PARRY_MAX_DURATION: float = 2.0
var parry_max_duration_mult: float = 1.0
var parry_reflected_count: int = 0
var parry_hp: float = 0.0
var parry_max_hp: float = 600.0  # total damage the shield can absorb before popping

var damage_number_script: GDScript = preload("res://Space/scripts/combat/damage_number.gd")

static var _spr_pulse_mk1: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk1.png")
static var _spr_pulse_mk2: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk2.png")
static var _spr_autocannon: Texture2D = preload("res://Space/art/projectiles/Autocannon.png")
static var _spr_gauss: Texture2D = preload("res://Space/art/projectiles/GaussBattery.png")
static var _spr_railgun: Texture2D = preload("res://Space/art/projectiles/Railgun.png")
static var _spr_mac: Texture2D = preload("res://Space/art/projectiles/MAC Gun.png")
static var _spr_missile: Texture2D = preload("res://Space/art/projectiles/MissileBattery.png")
static var _spr_hornet: Texture2D = preload("res://Space/art/projectiles/HornetPrimary.png")
static var _spr_harpoon: Texture2D = preload("res://Space/art/projectiles/WretchedHarpoon.png")

# --- Wretched Harpoon ---
enum HarpoonState { IDLE, EXTENDING, ATTACHED, RETRACTING }
var harpoon_state: int = HarpoonState.IDLE
var harpoon_has_module: bool = false
var harpoon_max_tether: float = 500.0
var harpoon_pull_force: float = 200.0
var harpoon_target: Node2D = null
var harpoon_head_pos: Vector2 = Vector2.ZERO
var harpoon_head_vel: Vector2 = Vector2.ZERO
var harpoon_range: float = 600.0
var harpoon_proj_speed: float = 3600.0
var harpoon_damage: float = 10.0
var harpoon_time: float = 0.0
var harpoon_slingshot_timer: float = 0.0

var beam_active: bool = false
var beam_end_positions: Dictionary = {}


var ship_layout: Array = []
var weapon_modules: Array = []
var primary_group_keys: Array = []
var active_primary_idx: int = 0
var secondary_weapons: Array = []
var secondary_group_keys: Array = []
var active_secondary_idx: int = 0
var secondary_cooldowns: Dictionary = {}
var special_weapons: Array = []
var special_group_keys: Array = []
var active_special_idx: int = 0
var special_cooldowns: Dictionary = {}
var _hornet_arm_played: bool = false


var weapon_charges: Array = []
const RAILGUN_CHARGE_TIME: float = 1.8
const MACRO_CHARGE_TIME: float = 0.15
var _pulse_laser_idx: int = 0
const PULSE_LASER_SOUNDS: Array = ["pulse_laser_1", "pulse_laser_2", "pulse_laser_3"]


const SPECIAL_FIRE_INTERVAL: float = 0.3
var special_fire_cooldown: float = 0.0

# --- Overheat System ---
var weapon_heat: Dictionary = {}
var overheat_threshold: float = 100.0
var overheat_lockout: Dictionary = {}
var _heat_per_shot: Dictionary = {}    # subtype -> float (from module stats)
var _heat_decay_rate: Dictionary = {}  # subtype -> float (from module stats)
const DEFAULT_HEAT_PER_SHOT: float = 3.0
const DEFAULT_HEAT_DECAY: float = 6.0
const OVERHEAT_LOCKOUT_TIME: float = 1.5


var weapon_flash: float = 0.0
var weapon_flash_color: Color = Color.WHITE



signal health_changed(health: float, max_health: float, shields: float, max_shields: float)
signal destroyed
signal power_preset_changed(preset: int)

var ai_controlled: bool = false
var cloned_ai: ClonedAI = null
var proj_source: String = "player"

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    MCELL = 9.0
    ship_size = 20.0
    damage_resist = 0.0
    max_health = 100.0
    max_shields = 0.0
    shield_recharge_rate = 5.0
    health = max_health
    shields = max_shields
    if ai_controlled:
        add_to_group("enemies")
        proj_source = "enemy"
    else:
        add_to_group("player")
    projectile_scene = preload("res://Space/scenes/projectile.tscn")
    camera = get_node_or_null("Camera2D") if not ai_controlled else null


    _init_collision(ship_size)

var scooping: bool = false

func _process(delta: float):

    position += velocity * delta
    queue_redraw()

func _physics_process(delta: float):
    _process_collisions(delta)

    for k in secondary_cooldowns.keys():
        secondary_cooldowns[k] = maxf(secondary_cooldowns[k] - delta, 0.0)
    for k in special_cooldowns.keys():
        var _old_cd = special_cooldowns[k]
        special_cooldowns[k] = maxf(_old_cd - delta, 0.0)
        if not _hornet_arm_played and _old_cd > 2.0 and special_cooldowns[k] <= 2.0:
            if k < special_weapons.size() and special_weapons[k].get("subtype", "") == "hornet":
                _hornet_arm_played = true
                AudioManager.play_sfx("hornet_armed", 0.7, 0.0)


    if special_fire_cooldown > 0:
        special_fire_cooldown -= delta
    for ht_key in weapon_heat.keys():
        var decay = _heat_decay_rate.get(ht_key, DEFAULT_HEAT_DECAY)
        weapon_heat[ht_key] = maxf(weapon_heat[ht_key] - decay * delta, 0.0)
    for lk_key in overheat_lockout.keys():
        overheat_lockout[lk_key] = maxf(overheat_lockout[lk_key] - delta, 0.0)
    var _macro_sfx_played := false
    for i in range(weapon_charges.size() - 1, -1, -1):
        var ch = weapon_charges[i]
        ch.timer += delta
        if ch.type == "railgun" and not ch.get("sfx_played", false) and ch.timer >= ch.time - 1.0:
            ch["sfx_played"] = true
            AudioManager.play_sfx("railgun_fire", 0.9, 0.0)
        if ch.timer >= ch.time:
            var wpos_ch = _get_weapon_world_pos(ch.data.get("grid_pos", Vector2i.ZERO))
            var aim_ch = (_get_aim_target() - wpos_ch).angle()
            match ch.type:
                "railgun":
                    _spawn_railgun(aim_ch, ch.data)
                    _add_shake(5.0)
                    weapon_flash = 0.25
                    weapon_flash_color = Color(0.7, 0.85, 1.0)
                "macro":
                    _spawn_macro(aim_ch, ch.data)
                    _add_shake(6.0)
                    weapon_flash = 0.4
                    weapon_flash_color = Color(1.0, 0.65, 0.15)
                    if not _macro_sfx_played:
                        AudioManager.play_sfx("cannon_fire", 0.8, 0.05)
                        _macro_sfx_played = true
                "hornet":
                    var hproj = _spawn_proj(aim_ch, ch.data.get("damage", 50), ch.data.get("projectile_speed", 600), ch.data.get("shield_pierce", 0.0), "hornet", wpos_ch)
                    if hproj:
                        hproj.proj_size = 4.0
                    _add_shake(2.5)
            weapon_charges.remove_at(i)


    if GameManager.docked_at_station:
        velocity = Vector2.ZERO
        _handle_shields(delta)
        _handle_shake(delta)
        if damage_flash > 0:
            damage_flash -= delta * 4.0
        if weapon_flash > 0:
            weapon_flash -= delta * 4.0
        queue_redraw()
        return

    if ai_controlled:
        _handle_ai(delta)
    elif not input_blocked:
        _handle_harpoon(delta)
        if harpoon_state != HarpoonState.ATTACHED:
            _handle_movement(delta)
            _handle_rotation(delta)
        _handle_boost(delta)
        _handle_shooting()
        _handle_scan(delta)
        _handle_power_presets()
        _handle_weapon_select()
    elif orbit_locked and handbrake_target and is_instance_valid(handbrake_target):

        _handle_handbrake(delta)
    _handle_shields(delta)
    _handle_shake(delta)
    if not ai_controlled:
        _handle_fuel_scoop(delta)
        _handle_star_danger(delta)


    if damage_flash > 0:
        damage_flash -= delta * 4.0
    if weapon_flash > 0:
        weapon_flash -= delta * 4.0


var star_speed_mult: float = 1.0
const STAR_INNER_RADIUS: float = 2000.0
const STAR_OUTER_RADIUS: float = 25000.0
const STAR_GRAVITY_RADIUS: float = 3500.0
const STAR_HEAT_RADIUS: float = 1800.0
const STAR_MIN_MULT: float = 0.15
const STAR_MAX_MULT: float = 1.3
const STAR_GRAVITY_FORCE: float = 60.0
const STAR_HEAT_DPS: float = 20.0

var nearest_star_pos: Vector2 = Vector2.ZERO
var nearest_star_radius: float = 1200.0
var star_heat_warning: bool = false
var star_gravity_warning: bool = false

func _update_star_speed_mult():
    var dist = global_position.distance_to(nearest_star_pos)
    if dist <= STAR_INNER_RADIUS:
        star_speed_mult = lerpf(STAR_MIN_MULT, 1.0, clampf(dist / STAR_INNER_RADIUS, 0, 1))
    elif dist <= STAR_OUTER_RADIUS:
        star_speed_mult = lerpf(1.0, STAR_MAX_MULT, (dist - STAR_INNER_RADIUS) / (STAR_OUTER_RADIUS - STAR_INNER_RADIUS))
    else:
        star_speed_mult = STAR_MAX_MULT

var handbrake_target: Node2D = null
var orbit_locked: bool = false
var orbit_dist_override: float = 0.0
const HANDBRAKE_ORBIT_RANGE: float = 8000.0
const HANDBRAKE_ORBIT_DIST: float = 240.0
const HANDBRAKE_BRAKE_FORCE: float = 800.0


var space_held_time: float = 0.0
var space_was_held: bool = false
const SPACE_TAP_THRESHOLD: float = 0.25
var weapon_bark_cooldown: float = 0.0

func _handle_movement(delta: float):
    _update_star_speed_mult()
    var fuel_mult = 1.0 if GameManager.fuel > 0 else FUEL_EMPTY_MULT
    var effective_speed = max_speed * star_speed_mult * staff_mult_engine * fuel_mult
    var effective_accel = acceleration * star_speed_mult * staff_mult_engine * fuel_mult
    var facing_dir = Vector2.from_angle(rotation)


    if Input.is_action_pressed("handbrake") and harpoon_state == HarpoonState.IDLE:
        space_held_time += delta
        if space_held_time > SPACE_TAP_THRESHOLD and not orbit_locked:

            var hold_extra = space_held_time - SPACE_TAP_THRESHOLD
            var brake_ramp = clampf(hold_extra / 0.5, 0.0, 1.0)
            velocity = velocity.move_toward(Vector2.ZERO, HANDBRAKE_BRAKE_FORCE * brake_ramp * delta)
            space_was_held = true
    elif space_held_time > 0.0:

        if space_held_time < SPACE_TAP_THRESHOLD and not space_was_held:

            if orbit_locked:
                _release_orbit()
            else:
                var lockable = _find_nearest_lockable()
                if lockable:
                    handbrake_target = lockable
                    orbit_locked = true
                    orbit_dist_override = _get_orbit_dist_for(lockable)
        space_held_time = 0.0
        space_was_held = false


    if orbit_locked:
        if not handbrake_target or not is_instance_valid(handbrake_target):
            _release_orbit()
        elif Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down"):
            _release_orbit()
        elif GameManager.using_controller:
            var lstick = GameManager.poll_left_stick()
            if lstick.length() > 0.3:
                _release_orbit()

    if orbit_locked and handbrake_target:
        _handle_handbrake(delta)
        return


    var thrust_input: float = 0.0
    var _turn_from_stick: float = 0.0
    if GameManager.using_controller:
        var lstick = GameManager.poll_left_stick()

        thrust_input = - lstick.y
        if thrust_input < 0:
            thrust_input *= 0.5

        _turn_from_stick = lstick.x
    if Input.is_action_pressed("move_up"):
        thrust_input = maxf(thrust_input, 1.0)
    if Input.is_action_pressed("move_down"):
        thrust_input = minf(thrust_input, -0.5)

    if absf(thrust_input) > 0.01:
        var speed_before = velocity.length()
        velocity += facing_dir * thrust_input * effective_accel * delta

        var clamp_to = maxf(effective_speed, speed_before)
        velocity = velocity.limit_length(clamp_to)
        if GameManager.fuel > 0:
            GameManager.consume_fuel(absf(thrust_input) * FUEL_BURN_RATE * staff_fuel_efficiency * delta)

    if harpoon_slingshot_timer > 0:
        harpoon_slingshot_timer -= delta
        # Gentle drag only during slingshot — preserve most momentum
        velocity = velocity.move_toward(velocity.normalized() * effective_speed, friction * 0.3 * delta)
    elif velocity.length() > effective_speed:
        velocity = velocity.move_toward(velocity.normalized() * effective_speed, friction * 3.0 * delta)
    elif absf(thrust_input) <= 0.01:
        velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func _handle_handbrake(delta: float):

    var to_target = handbrake_target.global_position - global_position
    var dist = to_target.length()
    var dir = to_target.normalized()
    var orb_dist = orbit_dist_override if orbit_dist_override > 0.0 else HANDBRAKE_ORBIT_DIST
    var orbit_speed = clampf(orb_dist * 0.4, 30.0, 120.0)

    if dist > orb_dist * 1.5:

        var approach_speed = clampf((dist - orb_dist) * 0.5, 60.0, 200.0)
        velocity = velocity.move_toward(dir * approach_speed, HANDBRAKE_BRAKE_FORCE * delta)
    elif dist < orb_dist * 0.5:

        velocity = velocity.move_toward( - dir * 40.0, HANDBRAKE_BRAKE_FORCE * delta)
    else:

        var tangent = Vector2( - dir.y, dir.x)
        var radial_correction = dir * (dist - orb_dist) * 2.0
        velocity = velocity.move_toward(tangent * orbit_speed + radial_correction, HANDBRAKE_BRAKE_FORCE * delta)

func _find_nearest_lockable() -> Node2D:
    var best: Node2D = null
    var best_dist: float = HANDBRAKE_ORBIT_RANGE

    var groups = ["pois", "enemies", "npc_ships", "station_entities"]
    for group_name in groups:
        for node in get_tree().get_nodes_in_group(group_name):
            if not is_instance_valid(node):
                continue
            var d = global_position.distance_to(node.global_position)
            if d < best_dist:
                best_dist = d
                best = node

    var star_dist = global_position.distance_to(nearest_star_pos)
    if star_dist < best_dist and star_dist < HANDBRAKE_ORBIT_RANGE:


        best = null
        best_dist = star_dist

        var star_marker = Node2D.new()
        star_marker.name = "star_orbit_marker"
        star_marker.global_position = nearest_star_pos
        star_marker.add_to_group("star_orbit_marker")
        get_parent().add_child(star_marker)
        best = star_marker
    return best

func _get_orbit_dist_for(target: Node2D) -> float:

    if target.is_in_group("star_orbit_marker"):

        return nearest_star_radius + 2000.0
    if target.is_in_group("station_entities"):
        return 800.0
    if target.is_in_group("pois"):
        return 150.0
    return HANDBRAKE_ORBIT_DIST

func _release_orbit():

    if handbrake_target and is_instance_valid(handbrake_target) and handbrake_target.is_in_group("star_orbit_marker"):
        handbrake_target.queue_free()
    orbit_locked = false
    handbrake_target = null
    orbit_dist_override = 0.0


# --- Wretched Harpoon ---

func _release_harpoon():
    if harpoon_state == HarpoonState.ATTACHED:
        harpoon_slingshot_timer = 3.0
    harpoon_state = HarpoonState.IDLE
    harpoon_target = null
    harpoon_time = 0.0

func _find_harpoon_hit() -> Node2D:
    var groups = ["asteroids", "pois", "enemies", "npc_ships", "station_entities"]
    for group_name in groups:
        for node in get_tree().get_nodes_in_group(group_name):
            if not is_instance_valid(node):
                continue
            var hit_r: float = 30.0
            if node.has_method("get_harpoon_hit_radius"):
                hit_r = float(node.call("get_harpoon_hit_radius"))
            elif "ship_size" in node:
                hit_r = float(node.get("ship_size"))
            elif "interact_radius" in node:
                hit_r = float(node.get("interact_radius")) * 0.45
            var dist = harpoon_head_pos.distance_to(node.global_position)
            if dist < hit_r + 10.0:
                return node
    return null

func _get_harpoon_stability(target: Node2D) -> float:
    if target.is_in_group("asteroids") or target.is_in_group("pois") or target.is_in_group("station_entities"):
        return 1.0
    var target_size: float = target.get("ship_size") if "ship_size" in target else 20.0
    return clampf(target_size / (target_size + ship_size), 0.2, 1.0)

func _handle_harpoon(delta: float):
    if not harpoon_has_module:
        if harpoon_state != HarpoonState.IDLE:
            _release_harpoon()
        return

    match harpoon_state:
        HarpoonState.IDLE:
            if Input.is_action_just_pressed("fire_harpoon"):
                if orbit_locked:
                    return
                var aim_dir = (_get_aim_target() - global_position).normalized()
                harpoon_head_pos = global_position
                harpoon_head_vel = aim_dir * harpoon_proj_speed + velocity
                harpoon_target = null
                harpoon_state = HarpoonState.EXTENDING
                harpoon_time = 0.0
                #AudioManager.play_sfx("warp_charge", 0.06, 0.0)

        HarpoonState.EXTENDING:
            harpoon_time += delta
            if Input.is_action_just_pressed("fire_harpoon"):
                harpoon_state = HarpoonState.RETRACTING
                return
            harpoon_head_pos += harpoon_head_vel * delta
            # Check for hits along the way
            var hit = _find_harpoon_hit()
            if hit:
                harpoon_target = hit
                harpoon_state = HarpoonState.ATTACHED
                harpoon_time = 0.0
                if harpoon_damage > 0 and not hit.is_in_group("asteroids") and hit.has_method("take_damage"):
                    hit.take_damage(harpoon_damage)
                #AudioManager.play_sfx("hull_hit", 0.4, 0.1)
                return
            var dist_from_player = harpoon_head_pos.distance_to(global_position)
            if dist_from_player > harpoon_range or harpoon_time > 1.5:
                harpoon_state = HarpoonState.RETRACTING
                return

        HarpoonState.ATTACHED:
            if Input.is_action_just_pressed("fire_harpoon"):
                _release_harpoon()
                return
            if not harpoon_target or not is_instance_valid(harpoon_target):
                _release_harpoon()
                return
            var anchor_pos = harpoon_target.global_position
            var to_anchor = anchor_pos - global_position
            var dist = to_anchor.length()
            if dist > harpoon_max_tether * 2.5:
                _release_harpoon()
                return

            var dir = to_anchor.normalized() if dist > 1.0 else Vector2.RIGHT

            # Mass ratio — determines who gets pulled
            var my_mass = maxf(ship_weight, 1.0)
            var target_mass = _get_other_collision_mass(harpoon_target)
            var total_mass = my_mass + target_mass
            var my_ratio = target_mass / total_mass  # how much player is affected (heavy target = 1.0)
            var target_ratio = my_mass / total_mass  # how much target is affected (heavy player = 1.0)

            # Normal thrust — accelerate in facing direction, tether handles the curving
            var fuel_mult = 1.0 if GameManager.fuel > 0 else FUEL_EMPTY_MULT
            var effective_accel = acceleration * star_speed_mult * staff_mult_engine * fuel_mult
            var thrust_input: float = 0.0
            if GameManager.using_controller:
                var lstick = GameManager.poll_left_stick()
                thrust_input = -lstick.y
            if Input.is_action_pressed("move_up"):
                thrust_input = maxf(thrust_input, 1.0)
            if Input.is_action_pressed("move_down"):
                thrust_input = minf(thrust_input, -0.5)
            if absf(thrust_input) > 0.01:
                velocity += Vector2.from_angle(rotation) * thrust_input * effective_accel * 1.5 * delta
                if GameManager.fuel > 0:
                    GameManager.consume_fuel(absf(thrust_input) * FUEL_BURN_RATE * staff_fuel_efficiency * delta)

            # Tether constraint — only when taut
            if dist >= harpoon_max_tether:
                var outward_vel = -velocity.dot(dir)  # positive = moving away from anchor
                if outward_vel > 0:
                    # Strip outward velocity from player, proportional to target's share of mass
                    velocity += dir * outward_vel * my_ratio
                # Pull target toward player if they have velocity
                if "velocity" in harpoon_target:
                    var target_outward = harpoon_target.velocity.dot(dir)  # positive = moving away from player
                    if target_outward > 0:
                        harpoon_target.velocity -= dir * target_outward * target_ratio
                # Soft position correction — lerp back, don't hard snap
                var overshoot = dist - harpoon_max_tether
                global_position += dir * overshoot * my_ratio
                if "velocity" in harpoon_target:
                    harpoon_target.global_position -= dir * overshoot * target_ratio

            # Continuous drag on light targets
            if "velocity" in harpoon_target and target_ratio > 0.1:
                harpoon_target.velocity -= dir * harpoon_pull_force * target_ratio * delta

            # Tether stress damage
            var tangent = Vector2(-dir.y, dir.x)
            var tangential_speed = absf(velocity.dot(tangent))
            if tangential_speed > 100.0 and not harpoon_target.is_in_group("asteroids") and harpoon_target.has_method("take_damage"):
                var stress_dmg = tangential_speed * 0.02 * my_ratio * delta
                harpoon_target.take_damage(stress_dmg)

            # Face direction of travel
            if velocity.length() > 10.0:
                rotation = velocity.angle()

            harpoon_head_pos = harpoon_target.global_position

        HarpoonState.RETRACTING:
            var to_player = global_position - harpoon_head_pos
            var dist = to_player.length()
            if dist < 20.0:
                _release_harpoon()
                return
            harpoon_head_pos += to_player.normalized() * harpoon_proj_speed * 3.0 * delta


func _handle_boost(delta: float):

    if boost_cd_timer > 0:
        boost_cd_timer -= delta
        if boost_cd_timer <= 0:
            boost_ready = true


    if Input.is_action_just_pressed("boost") and boost_ready and GameManager.fuel > 0:
        var facing = Vector2.from_angle(rotation)
        velocity += facing * boost_impulse
        boost_ready = false
        boost_cd_timer = boost_cooldown
        GameManager.consume_fuel(FUEL_BOOST_COST * staff_fuel_efficiency)
        AudioManager.play_sfx("boost", 0.6)
        _add_shake(3.0)

func _handle_shake(delta: float):
    if shake_amount > 0:
        shake_amount = maxf(shake_amount - delta * 12.0, 0.0)
        if camera:
            camera.offset = Vector2(
                randf_range( - shake_amount, shake_amount), 
                randf_range( - shake_amount, shake_amount)
            )
    elif camera and camera.offset != Vector2.ZERO:
        camera.offset = Vector2.ZERO

func _add_shake(amount: float):
    shake_amount = maxf(shake_amount, amount)

func _handle_rotation(delta: float):

    var turn_input: float = 0.0
    if Input.is_action_pressed("move_right"):
        turn_input += 1.0
    if Input.is_action_pressed("move_left"):
        turn_input -= 1.0

    if GameManager.using_controller:
        var lstick = GameManager.poll_left_stick()
        if absf(lstick.x) > absf(turn_input):
            turn_input = lstick.x
    rotation += turn_input * rotation_speed * delta


    if GameManager.using_controller:
        var rstick = GameManager.poll_right_stick()
        if rstick.length() > 0.1:
            aim_angle = rstick.angle()

    else:
        var mouse_pos = get_global_mouse_position()
        aim_angle = (mouse_pos - global_position).angle()

func _handle_ai(delta: float):
    if cloned_ai == null:
        return
    # Tick parry timer/cooldown for AI ships (normally done in _handle_scan)
    _tick_parry(delta)
    # Find nearest player to target
    var target: Node2D = null
    var best_dist: float = INF
    for p in get_tree().get_nodes_in_group("player"):
        if is_instance_valid(p):
            var d = global_position.distance_to(p.global_position)
            if d < best_dist:
                best_dist = d
                target = p
    if target == null:
        return
    cloned_ai.decide(self, target, delta)

func _handle_shooting():
    if weapon_bark_cooldown > 0:
        weapon_bark_cooldown -= get_physics_process_delta_time()

    var trying_to_fire = Input.is_action_pressed("fire_primary") or Input.is_action_pressed("fire_special") or Input.is_action_pressed("fire_secondary")
    if trying_to_fire and weapon_bark_cooldown <= 0:
        if weapon_modules.is_empty() and secondary_weapons.is_empty() and special_weapons.is_empty():
            GameManager.pending_barks.append({"speaker": "WEAPONS", "text": "WEAPONS UNPOWERED — check power routing", "color": [0.9, 0.5, 0.2], "duration": 3.0})
            weapon_bark_cooldown = 5.0
            return

    var manual_fired = false
    if Input.is_action_pressed("fire_primary") and can_fire:
        _fire_primary()
        can_fire = false
        manual_fired = true
        get_tree().create_timer(fire_rate).timeout.connect( func(): can_fire = true)

    if not manual_fired and auto_fire_target and is_instance_valid(auto_fire_target) and can_fire:
        aim_angle = (auto_fire_target.global_position - global_position).angle()
        _fire_primary()
        can_fire = false
        get_tree().create_timer(fire_rate * 1.3).timeout.connect( func(): can_fire = true)

    var was_beam_active = beam_active
    beam_active = false
    beam_end_positions.clear()
    if Input.is_action_pressed("fire_secondary") and not secondary_weapons.is_empty():
        _fire_secondary_weapon()
        if not secondary_group_keys.is_empty():
            var gidx = clampi(active_secondary_idx, 0, secondary_group_keys.size() - 1)
            if gidx < secondary_group_keys.size() and secondary_group_keys[gidx] == "beam":
                beam_active = true
    if beam_active and not was_beam_active:
        AudioManager.beam_start(0.7)
    elif not beam_active and was_beam_active:
        AudioManager.beam_stop_immediate()

    if Input.is_action_pressed("fire_special") and not special_weapons.is_empty():
        var gidx = clampi(active_special_idx, 0, special_group_keys.size() - 1)
        var is_lance = special_group_keys.size() > 0 and special_group_keys[gidx] == "lance"
        if is_lance or special_fire_cooldown <= 0:
            _fire_special_weapon()
            if not is_lance:
                special_fire_cooldown = SPECIAL_FIRE_INTERVAL

func _handle_shields(delta: float):
    if not alive:
        return
    if shield_timer > 0:
        shield_timer -= delta
    elif shields < max_shields:
        shields = minf(shields + shield_recharge_rate * staff_mult_shield * delta, max_shields)
        health_changed.emit(health, max_health, shields, max_shields)

    var now = Time.get_ticks_msec() / 1000.0
    if now - _last_damage_time >= AUTO_REPAIR_DELAY:
        # Validate current repair target against ship_layout
        if _repair_target_idx >= 0:
            if _repair_target_idx >= ship_layout.size():
                _repair_target_idx = -1
            elif ship_layout[_repair_target_idx].get("hp", 0.0) >= ship_layout[_repair_target_idx].get("max_hp", 0.0):
                _repair_target_idx = -1
        # Pick new target — first damaged module in layout
        if _repair_target_idx < 0:
            for i in ship_layout.size():
                var mhp = ship_layout[i].get("max_hp", 0.0)
                if mhp > 0 and ship_layout[i].get("hp", 0.0) < mhp:
                    _repair_target_idx = i
                    break
        # Repair the locked target
        if _repair_target_idx >= 0 and _repair_target_idx < ship_layout.size():
            var entry = ship_layout[_repair_target_idx]
            var max_hp = entry.get("max_hp", 0.0)
            var hp = entry.get("hp", 0.0)
            var repair_rate = max_hp / AUTO_REPAIR_BASE_TIME * auto_repair_speed_mult
            var new_hp = minf(hp + repair_rate * delta, max_hp)
            entry["hp"] = new_hp
            var stats_changed = false
            if new_hp >= max_hp and hp < max_hp:
                stats_changed = true
            elif hp <= 0 and new_hp > 0:
                stats_changed = true
            # Push HP back to GameManager for persistence (skip for AI clones)
            if not ai_controlled:
                var rt_id = entry.get("id", "")
                var rt_gp = entry.get("grid_pos", null)
                for gm_mod in GameManager.ship_modules:
                    if gm_mod.get("id", "") == rt_id and gm_mod.get("grid_pos", null) == rt_gp:
                        gm_mod["hp"] = new_hp
                        if new_hp >= max_hp:
                            gm_mod["damaged"] = false
                            gm_mod["destroyed"] = false
                        elif hp <= 0 and new_hp > 0:
                            gm_mod["destroyed"] = false
                            gm_mod["damaged"] = true
                        break
            if stats_changed:
                if not ai_controlled:
                    _sync_layout_hp_to_gm()
                _recalc_module_stats()
            # Compute HP from ship_layout directly — it's the source of truth
            var total_hp: float = 0.0
            var total_max: float = 0.0
            for sl_entry in ship_layout:
                total_max += sl_entry.get("max_hp", 0.0)
                total_hp += maxf(sl_entry.get("hp", 0.0), 0.0)
            health = total_hp
            max_health = total_max
            health_changed.emit(health, max_health, shields, max_shields)
            _hull_cache_dirty = true
    else:
        _repair_target_idx = -1

func _tick_parry(delta: float):
    if parry_cooldown > 0:
        parry_cooldown -= delta
    if parry_active:
        parry_timer -= delta
        parry_spin_angle += PARRY_SPIN_SPEED * delta
        _parry_reflect_projectiles()
        if parry_timer <= 0:
            parry_active = false
            parry_spin_angle = 0.0
            parry_cooldown = PARRY_COOLDOWN_TIME
        queue_redraw()

func _handle_scan(delta: float):
    if scan_cooldown > 0:
        scan_cooldown -= delta
    _tick_parry(delta)
    if parry_active:
        return

    if Input.is_action_just_pressed("scan"):
        if GameManager.has_shield_supercharger():
            if parry_cooldown <= 0:
                parry_active = true
                parry_timer = parry_duration
                parry_spin_angle = 0.0
                parry_reflected_count = 0
                parry_hp = parry_max_hp
                AudioManager.play_sfx("shield_up", 0.8, 0.0)
                _add_shake(2.0)
                return
        elif GameManager.has_sensor() and not scan_pulse_active and scan_cooldown <= 0:
            scan_pulse_active = true
            scan_pulse_radius = 0.0
            scan_cooldown = SCAN_COOLDOWN_TIME
            AudioManager.play_sfx("scan_pulse", 0.5)
            _add_shake(1.0)

    if scan_pulse_active:
        scan_pulse_radius += scan_range * scan_speed * delta * 2.0
        var scan_groups = ["pois", "enemies", "loot"]
        for group_name in scan_groups:
            for node in get_tree().get_nodes_in_group(group_name):
                var dist = global_position.distance_to(node.global_position)
                if dist <= scan_pulse_radius and dist >= scan_pulse_radius - scan_range * scan_speed * delta * 2.5:
                    scan_pulse_hit.emit(node)
        if scan_pulse_radius > scan_range:
            scan_pulse_active = false

func _parry_reflect_projectiles():
    var parry_radius = ship_size * 1.0
    var my_source = "enemy" if ai_controlled else "player"
    for proj in get_tree().get_nodes_in_group("projectiles"):
        if not is_instance_valid(proj):
            continue
        # Don't reflect our own team's projectiles
        if proj.source == my_source:
            continue
        var dist = global_position.distance_to(proj.global_position)
        if dist > parry_radius:
            continue
        proj.direction = -proj.direction
        proj.rotation = proj.direction.angle()
        proj.speed *= 2.0
        proj.damage *= 1.5
        proj.source = my_source
        proj.proj_color = Color(0.3, 0.8, 1.0) if not ai_controlled else Color(1.0, 0.4, 0.3)
        parry_timer = minf(parry_timer + 0.2, PARRY_MAX_DURATION * parry_max_duration_mult)
        parry_reflected_count += 1
        AudioManager.play_sfx("shield_hit", 0.4, 0.15)
        _add_shake(1.5)

func _parry_blowout():
    parry_active = false
    parry_hp = 0.0
    parry_spin_angle = 0.0
    parry_cooldown = PARRY_BLOWOUT_COOLDOWN
    _add_shake(8.0)
    damage_flash = 1.0
    AudioManager.play_sfx("hull_hit", 0.9, 0.05)
    queue_redraw()

func _handle_power_presets():
    pass

func _handle_weapon_select():
    _handle_radial_menus()

func _handle_radial_menus():
    # Check for new presses
    if radial_open < 0:
        for i in 4:
            if Input.is_action_just_pressed(_RADIAL_ACTIONS[i]):
                _radial_press_time = Time.get_ticks_msec() / 1000.0
                _radial_slot = i
                break

    # While held, check if we should open the radial
    if _radial_slot >= 0 and radial_open < 0:
        if Input.is_action_pressed(_RADIAL_ACTIONS[_radial_slot]):
            var held = Time.get_ticks_msec() / 1000.0 - _radial_press_time
            if held >= RADIAL_HOLD_TIME:
                _open_radial(_radial_slot)
        elif Input.is_action_just_released(_RADIAL_ACTIONS[_radial_slot]):
            # Quick tap — cycle
            _cycle_slot(_radial_slot)
            _radial_slot = -1
            _radial_press_time = -1.0

    # Radial is open — update highlight and check for release
    if radial_open >= 0:
        _update_radial_highlight()
        if Input.is_action_just_released(_RADIAL_ACTIONS[radial_open]):
            if radial_highlight >= 0 and radial_highlight < radial_options.size():
                _apply_radial_selection(radial_open, radial_highlight)
            radial_open = -1
            radial_options.clear()
            radial_highlight = -1
            _radial_slot = -1
            _radial_press_time = -1.0

func _cycle_slot(slot: int):
    match slot:
        0:
            if not primary_group_keys.is_empty():
                active_primary_idx = (active_primary_idx + 1) % primary_group_keys.size()
        1:
            if not secondary_group_keys.is_empty():
                active_secondary_idx = (active_secondary_idx + 1) % secondary_group_keys.size()
        2:
            if not special_group_keys.is_empty():
                active_special_idx = (active_special_idx + 1) % special_group_keys.size()
        3:
            _set_power_preset((power_preset + 1) % POWER_PRESETS.size())

func _open_radial(slot: int):
    radial_options.clear()
    match slot:
        0:
            for st in primary_group_keys:
                var label = st.to_upper()
                for w in weapon_modules:
                    if w.get("subtype", "") == st:
                        label = w.get("name", label)
                        break
                radial_options.append(label)
            radial_current = active_primary_idx
        1:
            for st in secondary_group_keys:
                var label = st.to_upper()
                for w in secondary_weapons:
                    if w.get("subtype", "") == st:
                        label = w.get("name", label)
                        break
                radial_options.append(label)
            radial_current = active_secondary_idx
        2:
            for st in special_group_keys:
                var label = st.to_upper()
                for w in special_weapons:
                    if w.get("subtype", "") == st:
                        label = w.get("name", label)
                        break
                radial_options.append(label)
            radial_current = active_special_idx
        3:
            for p in POWER_PRESETS:
                radial_options.append(p.name)
            radial_current = power_preset
    if radial_options.size() <= 1:
        _cycle_slot(slot)
        radial_options.clear()
        _radial_slot = -1
        _radial_press_time = -1.0
        return
    radial_open = slot
    radial_highlight = radial_current
    var vp = get_viewport()
    if vp:
        radial_origin = vp.get_mouse_position()

func _update_radial_highlight():
    var vp = get_viewport()
    if not vp:
        return
    var mouse = vp.get_mouse_position()
    var dir = mouse - radial_origin
    if dir.length() < 40.0:
        radial_highlight = radial_current
        return
    var count = radial_options.size()
    var slice = TAU / count
    var angle = fmod(dir.angle() + PI * 0.5 + slice * 0.5 + TAU, TAU)
    radial_highlight = int(angle / slice) % count

func _apply_radial_selection(slot: int, idx: int):
    match slot:
        0:
            if idx < primary_group_keys.size():
                active_primary_idx = idx
        1:
            if idx < secondary_group_keys.size():
                active_secondary_idx = idx
        2:
            if idx < special_group_keys.size():
                active_special_idx = idx
        3:
            if idx < POWER_PRESETS.size():
                _set_power_preset(idx)

func _set_power_preset(preset: int):
    if preset == power_preset:
        return
    power_preset = preset
    var p = POWER_PRESETS[preset]
    power_mult_weapon = p.weapon
    power_mult_shield = p.shield
    power_mult_engine = p.engine
    auto_repair_speed_mult = p.get("repair", 1.0)

    max_speed = base_max_speed * power_mult_engine
    acceleration = base_acceleration * power_mult_engine
    shield_recharge_rate = base_shield_recharge * power_mult_shield
    boost_impulse = max_speed * 0.6
    power_preset_changed.emit(preset)


func _handle_fuel_scoop(delta: float):
    var scoop_rate = GameManager.get_scoop_rate()
    if scoop_rate <= 0 or GameManager.fuel >= GameManager.fuel_capacity:
        scooping = false
        return

    var dist = global_position.distance_to(nearest_star_pos)
    var scoop_range = STAR_GRAVITY_RADIUS
    if dist > scoop_range:
        scooping = false
        return

    var efficiency = 1.0 - clampf(dist / scoop_range, 0, 1)
    efficiency = efficiency * efficiency
    if efficiency < 0.05:
        scooping = false
        return
    scooping = true

    GameManager.fuel = minf(GameManager.fuel + scoop_rate * 0.15 * efficiency * delta, GameManager.fuel_capacity)

func _handle_star_danger(delta: float):

    var dist = global_position.distance_to(nearest_star_pos)

    if dist < STAR_GRAVITY_RADIUS and dist > 10.0:
        star_gravity_warning = true
        var gravity_strength = (1.0 - dist / STAR_GRAVITY_RADIUS)
        gravity_strength = gravity_strength * gravity_strength
        var pull_dir = (nearest_star_pos - global_position).normalized()
        var tangent = Vector2( - pull_dir.y, pull_dir.x)

        var lateral_speed = velocity.dot(tangent)

        velocity += pull_dir * STAR_GRAVITY_FORCE * gravity_strength * delta

        var new_lateral = velocity.dot(tangent)
        if absf(lateral_speed) > 10.0 and absf(new_lateral) < absf(lateral_speed):
            velocity += tangent * (lateral_speed - new_lateral) * 0.8
    else:
        star_gravity_warning = false

    # Star core collision — inside the star's inner core = instant death
    if dist < nearest_star_radius * 0.25 and dist > 0.1:
        health = 0
        emit_signal("destroyed")
        return

    if dist < STAR_HEAT_RADIUS and dist > 10.0:
        star_heat_warning = true
        var heat_intensity = (1.0 - dist / STAR_HEAT_RADIUS)
        heat_intensity = heat_intensity * heat_intensity * heat_intensity

        # Within 600px of the star surface, heat ramps up massively
        var core_dist = dist - nearest_star_radius * 0.25
        var core_mult = 1.0
        if core_dist < 600.0 and core_dist > 0.0:
            # Exponential ramp: at 600px out = 1x, at 0px = 50x
            var core_t = 1.0 - core_dist / 600.0
            core_mult = lerpf(1.0, 50.0, core_t * core_t * core_t)

        var heat_dmg = STAR_HEAT_DPS * heat_intensity * core_mult * delta

        # Shields absorb most heat, but some always bleeds through to hull
        var hull_dmg = heat_dmg * 0.3
        if shields > 0:
            shields = maxf(shields - heat_dmg * 2.0, 0)
        else:
            hull_dmg = heat_dmg

        if hull_dmg > 0:
            health -= hull_dmg
            # Damage random modules to show the heat cooking the ship
            if not GameManager.ship_modules.is_empty() and heat_intensity > 0.15:
                var gm_mod = GameManager.ship_modules[randi() % GameManager.ship_modules.size()]
                if gm_mod is Dictionary and gm_mod.get("hp", 0) > 0:
                    gm_mod["hp"] = maxf(gm_mod["hp"] - hull_dmg * 0.5, 0)
                    _hull_cache_dirty = true
            if health <= 0:
                health = 0
                emit_signal("destroyed")

        if heat_intensity > 0.3:
            _add_shake(heat_intensity * 2.0 * minf(core_mult, 5.0))
    else:
        star_heat_warning = false


func _fire():
    # Entry point for ClonedAI — fires primary weapons with cooldown
    if not can_fire:
        return
    _fire_primary()
    can_fire = false
    get_tree().create_timer(fire_rate).timeout.connect(func(): can_fire = true)

func _fire_primary():
    if weapon_modules.is_empty():
        return
    var aim_target = _get_aim_target()

    var group_subtype: String = ""
    if not primary_group_keys.is_empty():
        var gidx = clampi(active_primary_idx, 0, primary_group_keys.size() - 1)
        group_subtype = primary_group_keys[gidx]

    # Overheat lockout blocks firing
    if group_subtype == "energy" and overheat_lockout.get("energy", 0.0) > 0.0:
        return

    var fired: int = 0
    for w in weapon_modules:
        if group_subtype != "" and w.get("subtype", "energy") != group_subtype:
            continue
        var wpos = _get_weapon_world_pos(w.get("grid_pos", Vector2i.ZERO))
        var angle = (aim_target - wpos).angle()
        _spawn_proj(angle, w.get("damage", 10), w.get("projectile_speed", 800), w.get("shield_pierce", 0.0), w.get("subtype", ""), wpos)
        fired += 1
    _add_shake(0.8 + fired * 0.3)
    if group_subtype == "energy" and fired > 0:
        weapon_heat["energy"] = weapon_heat.get("energy", 0.0) + _heat_per_shot.get("energy", DEFAULT_HEAT_PER_SHOT)
        if weapon_heat["energy"] >= overheat_threshold:
            _overheat_blowout("energy")

func _fire_spread():
    var shots: Array = []
    if weapon_modules.is_empty():
        for i in 3:
            shots.append({"damage": 5, "projectile_speed": 550})
    else:
        shots = weapon_modules.duplicate()
        if shots.size() < 3:
            for i in (3 - shots.size()):
                shots.append({"damage": 4, "projectile_speed": 550})
    var spread = 0.5
    for i in shots.size():
        var w = shots[i]
        var t = float(i) / maxf(shots.size() - 1, 1)
        var angle = aim_angle + lerpf( - spread / 2.0, spread / 2.0, t)
        var proj = _spawn_proj(angle, w.get("damage", 5) * 0.7, w.get("projectile_speed", 550), w.get("shield_pierce", 0.0))
        if proj:
            proj.proj_size = 2.5
    _add_shake(2.5)

func _fire_secondary_weapon():
    if secondary_group_keys.is_empty():
        return
    var gidx = clampi(active_secondary_idx, 0, secondary_group_keys.size() - 1)
    var group_subtype = secondary_group_keys[gidx]

    # Overheat lockout blocks lance firing
    if group_subtype == "lance" and overheat_lockout.get("lance", 0.0) > 0.0:
        return

    var group_indices: Array = []
    for i in secondary_weapons.size():
        if secondary_weapons[i].get("subtype", "") == group_subtype:
            group_indices.append(i)

    var fired_count: int = 0
    for i in group_indices:
        if secondary_cooldowns.get(i, 0.0) <= 0.0:
            _fire_single_secondary(i, secondary_weapons[i])
            fired_count += 1

    # Apply heat once for the whole group, not per module
    if fired_count > 0:
        if group_subtype == "beam":
            var delta_t = get_physics_process_delta_time()
            weapon_heat["beam"] = weapon_heat.get("beam", 0.0) + _heat_per_shot.get("beam", DEFAULT_HEAT_PER_SHOT) * delta_t * 4.0
            if weapon_heat["beam"] >= overheat_threshold:
                _overheat_blowout("beam")
        elif group_subtype == "lance":
            weapon_heat["lance"] = weapon_heat.get("lance", 0.0) + _heat_per_shot.get("lance", DEFAULT_HEAT_PER_SHOT) * 0.5
            if weapon_heat["lance"] >= overheat_threshold:
                _overheat_blowout("lance")

func _fire_single_secondary(idx: int, w: Dictionary):
    var subtype = w.get("subtype", "energy")
    var dmg = w.get("damage", 15)
    var spd = w.get("projectile_speed", 500)
    var pierce = w.get("shield_pierce", 0.0)
    var wfire_rate = w.get("fire_rate", 1.0)
    var wpos = _get_weapon_world_pos(w.get("grid_pos", Vector2i.ZERO))
    var aim_target = _get_aim_target()
    var angle = (aim_target - wpos).angle()

    match subtype:
        "missile":
            _spawn_missile(angle, w)
            _add_shake(2.0)
        "torpedo":
            _spawn_torpedo(angle, w)
            _add_shake(3.5)
        "beam":
            if overheat_lockout.get("beam", 0.0) > 0.0:
                return
            _beam_tick_damage(w, wpos, angle, aim_target)
            _add_shake(0.3)
        "lance":
            var proj = _spawn_proj(angle, dmg, spd, pierce, "lance", wpos)
            if proj:
                proj.proj_size = 2.0
                proj.lifetime = 1.2
            _add_shake(0.3)
            AudioManager.play_sfx("laser_fire", 0.4, 0.15)
        _:
            var proj = _spawn_proj(angle, dmg, spd, pierce, subtype, wpos)
            if proj:
                proj.proj_size = 2.5
            _add_shake(1.0)
    if subtype != "beam":
        secondary_cooldowns[idx] = wfire_rate

func _fire_special_weapon():
    if special_group_keys.is_empty():
        return
    var gidx = clampi(active_special_idx, 0, special_group_keys.size() - 1)
    var group_subtype = special_group_keys[gidx]

    var group_indices: Array = []
    for i in special_weapons.size():
        if special_weapons[i].get("subtype", "") == group_subtype:
            group_indices.append(i)

    for i in group_indices:
        if special_cooldowns.get(i, 0.0) <= 0.0:
            _fire_single_special(i, special_weapons[i])
            return

func _fire_single_special(idx: int, w: Dictionary):
    var subtype = w.get("subtype", "kinetic")
    var dmg = w.get("damage", 30)
    var spd = w.get("projectile_speed", 500)
    var pierce = w.get("shield_pierce", 0.0)
    var wfire_rate = w.get("fire_rate", 1.0)
    var wpos = _get_weapon_world_pos(w.get("grid_pos", Vector2i.ZERO))
    var aim_target = _get_aim_target()
    var angle = (aim_target - wpos).angle()

    match subtype:
        "railgun":
            weapon_charges.append({timer = 0.0, time = RAILGUN_CHARGE_TIME, type = "railgun", data = w, sfx_played = false})
        "hornet":
            for hi in 4:
                weapon_charges.append({timer = 0.0, time = 0.6 + hi * 0.2, type = "hornet", data = w})
            _hornet_arm_played = false
            AudioManager.play_sfx("hornet_fire", 0.8, 0.03)
        "gauss":
            var spray_count = 6
            var spread = 0.15
            for si in spray_count:
                var spray_offset = lerpf(-spread, spread, float(si) / maxf(spray_count - 1, 1)) + randf_range(-0.03, 0.03)
                var proj = _spawn_proj(angle + spray_offset, dmg, spd + randf_range(-200, 200), pierce, "kinetic", wpos)
                if proj:
                    proj.proj_size = 2.5
                    proj.proj_color = Color(0.5, 0.7, 1.0)
                    proj.sprite_sheet = _spr_gauss
                    proj.sprite_scale = 0.6
                    proj.sprite_flip_h = false
                    proj.splash_radius = w.get("aoe_radius", 0.0)
                    proj.mac_knockback = w.get("knockback", 0.0)
            _add_shake(3.0)
            AudioManager.play_sfx("cannon_fire", 0.7, 0.1)
            special_cooldowns[idx] = 8.0
            return
        _:
            weapon_charges.append({timer = 0.0, time = MACRO_CHARGE_TIME, type = "macro", data = w})

    special_cooldowns[idx] = wfire_rate

func _overheat_blowout(subtype: String):
    weapon_heat[subtype] = 0.0
    overheat_lockout[subtype] = OVERHEAT_LOCKOUT_TIME
    var matching: Array = []
    for i in ship_layout.size():
        var entry = ship_layout[i]
        if entry.get("hp", 0.0) <= 0.0:
            continue
        var mod_info = DataManager.modules.get(entry.get("id", ""), {})
        if mod_info.get("type", "") != "weapon":
            continue
        if mod_info.get("subtype", "") == subtype:
            matching.append(i)
    @warning_ignore("integer_division")
    var destroy_count = ceili(float(matching.size()) / 2.0)
    for j in destroy_count:
        var idx = matching[j]
        ship_layout[idx]["hp"] = 0.0
        var entry = ship_layout[idx]
        for gm_mod in GameManager.ship_modules:
            if gm_mod.get("id", "") == entry.get("id", "") and gm_mod.get("grid_pos", null) == entry.get("grid_pos", null):
                gm_mod["hp"] = 0.0
                gm_mod["destroyed"] = true
                break
    _recalc_module_stats()
    _add_shake(5.0)
    AudioManager.play_sfx("hull_hit", 0.8, 0.05)
    GameManager.pending_barks.append({"speaker": "WEAPONS", "text": "OVERHEAT — %s BURNED OUT!" % subtype.to_upper(), "color": [1.0, 0.3, 0.1], "duration": 3.0})

func _get_weapon_world_pos(grid_pos) -> Vector2:
    var local = _hex_to_local(grid_pos)
    return global_position + local.rotated(rotation)

func _get_aim_target() -> Vector2:
    if ai_controlled:
        return global_position + Vector2.from_angle(aim_angle) * 4000.0
    if GameManager.using_controller:
        return global_position + Vector2.from_angle(aim_angle) * 400.0
    return get_global_mouse_position()

func _spawn_proj(angle: float, dmg: float, spd: float, pierce: float = 0.0, subtype: String = "", spawn_pos: Vector2 = Vector2.ZERO) -> Node:
    var proj = projectile_scene.instantiate()
    if spawn_pos == Vector2.ZERO:
        var muzzle_dist = ship_size + 6
        spawn_pos = global_position + Vector2.from_angle(angle) * muzzle_dist
    proj.global_position = spawn_pos
    proj.rotation = angle
    proj.source = proj_source
    proj.damage = dmg
    proj.speed = spd
    proj.shield_pierce = pierce
    proj.base_velocity = velocity

    match subtype:
        "kinetic":
            proj.proj_color = Color(1.0, 0.8, 0.25)
            proj.proj_size = 10.0
            proj.sprite_sheet = _spr_autocannon
            proj.sprite_scale = 2.4
            proj.lifetime = 6.0
        "beam":
            proj.proj_color = Color(0.4, 0.8, 1.0)
            proj.proj_size = 1.5
        "lance":
            proj.proj_color = Color(0.3, 0.9, 1.0)
            proj.proj_size = 2.0
            proj.sprite_sheet = _spr_pulse_mk2
            proj.sprite_scale = 0.88
            proj.sprite_flip_h = false
        "hornet":
            proj.proj_type = "hornet"
            proj.proj_color = Color(1.0, 0.7, 0.2)
            proj.proj_size = 3.0
            proj.sprite_sheet = _spr_hornet
            proj.sprite_scale = 1.2
            proj.sprite_flip_h = false
        _:
            proj.proj_color = Color(0.3, 1.0, 0.5)
            proj.proj_size = 3.0
            proj.lifetime = 6.0
            if dmg >= 35:
                proj.sprite_sheet = _spr_pulse_mk2
                proj.sprite_scale = 1.12
                proj.sprite_flip_h = false
            else:
                proj.sprite_sheet = _spr_pulse_mk1
                proj.sprite_scale = 0.88
    get_tree().current_scene.add_child(proj)

    if pierce > 0:
        AudioManager.play_sfx("cannon_fire", 0.6, 0.08)
    else:
        AudioManager.play_sfx(PULSE_LASER_SOUNDS[_pulse_laser_idx], 0.5, 0.1)
        _pulse_laser_idx = (_pulse_laser_idx + 1) % PULSE_LASER_SOUNDS.size()
    return proj

func _spawn_missile(angle: float, weapon_data: Dictionary):
    var proj = projectile_scene.instantiate()
    var wpos = _get_weapon_world_pos(weapon_data.get("grid_pos", Vector2i.ZERO))
    proj.global_position = wpos
    proj.rotation = angle
    proj.source = proj_source
    proj.proj_type = "missile"
    proj.damage = weapon_data.get("damage", 35)
    proj.speed = weapon_data.get("projectile_speed", 400)
    proj.lifetime = 4.0
    proj.proj_color = Color(0.2, 0.7, 1.0)
    proj.proj_size = 5.0
    proj.homing_strength = weapon_data.get("tracking", 0.6) * 5.0
    proj.splash_radius = weapon_data.get("splash_radius", 40)
    proj.base_velocity = velocity

    var best_target: Node2D = null
    var best_dist: float = 1000.0
    var aim_dir = Vector2.from_angle(angle)
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(enemy):
            continue
        var to_e = enemy.global_position - global_position
        var dist = to_e.length()

        var dot = to_e.normalized().dot(aim_dir)
        if dot > 0.3 and dist < best_dist:
            best_dist = dist
            best_target = enemy
    proj.homing_target = best_target
    proj.sprite_sheet = _spr_missile
    proj.sprite_scale = 1.6
    proj.sprite_flip_h = false
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("heavy_shot", 0.5, 0.08)
    _add_shake(2.0)

func _spawn_torpedo(angle: float, weapon_data: Dictionary):
    var proj = projectile_scene.instantiate()
    var wpos = _get_weapon_world_pos(weapon_data.get("grid_pos", Vector2i.ZERO))
    proj.global_position = wpos
    proj.rotation = angle
    proj.source = proj_source
    proj.proj_type = "missile"
    proj.damage = weapon_data.get("damage", 70)
    proj.speed = weapon_data.get("projectile_speed", 300)
    proj.lifetime = 6.0
    proj.proj_color = Color(1.0, 0.3, 0.15)
    proj.proj_size = 7.0
    proj.homing_strength = weapon_data.get("tracking", 0.4) * 3.5
    proj.splash_radius = weapon_data.get("splash_radius", 80)
    proj.shield_pierce = weapon_data.get("shield_pierce", 0.5)
    proj.base_velocity = velocity

    var best_target: Node2D = null
    var best_dist: float = 1500.0
    var aim_dir = Vector2.from_angle(angle)
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(enemy):
            continue
        var to_e = enemy.global_position - global_position
        var dist = to_e.length()
        var dot = to_e.normalized().dot(aim_dir)
        if dot > 0.2 and dist < best_dist:
            best_dist = dist
            best_target = enemy
    proj.homing_target = best_target
    proj.sprite_sheet = _spr_missile
    proj.sprite_scale = 2.0
    proj.sprite_flip_h = false
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("heavy_shot", 0.7, 0.05)

func _spawn_macro(angle: float, weapon_data: Dictionary):
    var proj = projectile_scene.instantiate()
    var wpos = _get_weapon_world_pos(weapon_data.get("grid_pos", Vector2i.ZERO))
    proj.global_position = wpos
    proj.rotation = angle
    proj.source = proj_source
    proj.proj_type = "mac"
    proj.damage = weapon_data.get("damage", 120)
    proj.speed = weapon_data.get("projectile_speed", 900)
    proj.lifetime = 2.5
    proj.proj_color = Color(1.0, 0.55, 0.1)
    proj.proj_size = 14.0
    proj.shield_pierce = weapon_data.get("shield_pierce", 0.5)
    proj.splash_radius = weapon_data.get("splash_radius", 80) * 4.0
    proj.mac_knockback = weapon_data.get("knockback", 400)
    proj.base_velocity = velocity
    proj.sprite_sheet = _spr_mac
    proj.sprite_scale = 3.6
    proj.sprite_flip_h = false
    get_tree().current_scene.add_child(proj)

func _spawn_railgun(angle: float, weapon_data: Dictionary):
    var proj = projectile_scene.instantiate()
    var wpos = _get_weapon_world_pos(weapon_data.get("grid_pos", Vector2i.ZERO))
    proj.global_position = wpos
    proj.rotation = angle
    proj.source = proj_source
    proj.proj_type = "railgun"
    proj.damage = weapon_data.get("damage", 80)
    proj.speed = weapon_data.get("projectile_speed", 2000)
    proj.lifetime = 1.5
    proj.proj_color = Color(0.7, 0.85, 1.0)
    proj.proj_size = 3.5
    proj.shield_pierce = weapon_data.get("shield_pierce", 0.7)
    proj.base_velocity = velocity
    proj.sprite_sheet = _spr_railgun
    proj.sprite_scale = 1.4
    proj.sprite_flip_h = false
    get_tree().current_scene.add_child(proj)

func apply_loadout(modules: Array):


    if not modules.is_empty():
        var avg = Vector2.ZERO
        var count: int = 0
        for mod in modules:
            var gp = mod.get("grid_pos", Vector2i.ZERO)
            if gp is Array:
                gp = Vector2i(int(gp[0]), int(gp[1]))
            avg += HexUtil.hex_to_pixel(gp, MCELL)
            count += 1
        if count > 0:
            grid_center_px = avg / float(count)
    else:
        grid_center_px = Vector2.ZERO
    var core_data = DataManager.modules.get(GameManager.equipped_core, {})


    var core_stats = core_data.get("stats", {})


    max_health = 100.0
    max_shields = 0.0
    shield_recharge_rate = 0.0
    max_speed = 0.0
    acceleration = 0.0
    weapon_modules.clear()
    secondary_weapons.clear()
    special_weapons.clear()
    ship_layout.clear()

    max_health += core_stats.get("hull_bonus", 0)


    for mod in modules:
        var mod_id: String = mod.get("id", "")
        var data: Dictionary = DataManager.modules.get(mod_id, mod.get("data", {}))
        var stats: Dictionary = data.get("stats", {})
        var type_str: String = data.get("type", "")
        var grid_pos = mod.get("grid_pos", Vector2i(0, 0))
        var hex_size: int = data.get("hex_size", 1)
        # Ensure GM module has proper HP initialized
        GameManager.init_module_hp(mod)
        var mod_hp: float = mod.get("hp", mod.get("max_hp", 1.0))
        var mod_max_hp: float = mod.get("max_hp", 1.0)
        ship_layout.append({
            "grid_pos": grid_pos,
            "type": type_str,
            "hex_size": hex_size,
            "hex_cells": GameManager.get_mod_hex_cells(mod),
            "stats": stats,
            "id": mod_id,
            "powered": false,
            "hp": mod_hp,
            "max_hp": mod_max_hp,
            "data": data,
            "rotation": mod.get("rotation", 0),
        })


    ship_modules = ship_layout

    ship_color = GameManager.ship_color_primary


    _compute_power_routing()
    _recalc_module_stats()
    # Compute HP from ship_layout — single source of truth
    var total_hp: float = 0.0
    var total_max: float = 0.0
    for sl_entry in ship_layout:
        total_max += sl_entry.get("max_hp", 0.0)
        total_hp += maxf(sl_entry.get("hp", 0.0), 0.0)
    health = total_hp
    max_health = total_max
    _update_ship_bounds()

func _sync_layout_hp_to_gm():
    for entry in ship_layout:
        var eid = entry.get("id", "")
        var egp = entry.get("grid_pos", null)
        for gm_mod in GameManager.ship_modules:
            if gm_mod.get("id", "") == eid and gm_mod.get("grid_pos", null) == egp:
                gm_mod["hp"] = entry.get("hp", 0.0)
                if entry.get("hp", 0.0) >= entry.get("max_hp", 1.0):
                    gm_mod["damaged"] = false
                    gm_mod["destroyed"] = false
                elif entry.get("hp", 0.0) <= 0:
                    gm_mod["destroyed"] = true
                    gm_mod["damaged"] = true
                else:
                    gm_mod["destroyed"] = false
                    gm_mod["damaged"] = true
                break

func _recalc_module_stats():

    var core_data = DataManager.modules.get(GameManager.equipped_core, {})
    var core_stats = core_data.get("stats", {})


    max_health = 100.0 + core_stats.get("hull_bonus", 0)
    max_shields = 0.0
    shield_recharge_rate = 0.0
    max_speed = 0.0
    acceleration = 0.0
    weapon_modules.clear()
    secondary_weapons.clear()
    special_weapons.clear()
    harpoon_has_module = false
    _heat_per_shot.clear()
    _heat_decay_rate.clear()


    scan_range = 3000.0
    scan_speed = 0.8
    damage_resist = 0.0
    var total_weight: float = 0.0
    var total_thrust: float = 0.0
    var extra_boost: float = 0.0
    var _engine_blocks: Array = []
    var _thrusters: Array = []


    for entry in ship_layout:
        total_weight += float(entry.get("hex_size", 1))


    if not ai_controlled:
        for i in ship_layout.size():
            var layout_id = ship_layout[i].get("id", "")
            var layout_gp = ship_layout[i].get("grid_pos", Vector2i.ZERO)
            for gm_mod in GameManager.ship_modules:
                if gm_mod.get("id", "") == layout_id and gm_mod.get("grid_pos", Vector2i.ZERO) == layout_gp:
                    ship_layout[i]["hp"] = gm_mod.get("hp", ship_layout[i].get("max_hp", 1.0))
                    break


    _compute_power_routing()


    # Armor hull_bonus always counts, even when destroyed
    for entry in ship_layout:
        var stats_a: Dictionary = entry.stats
        if entry.type == "armor":
            max_health += stats_a.get("hull_bonus", 0)
            damage_resist += stats_a.get("damage_resist", 0)

    for entry in ship_layout:
        if not entry.powered or entry.get("hp", 1) <= 0:
            continue
        var stats: Dictionary = entry.stats
        var type_str: String = entry.type
        match type_str:
            "weapon":
                var wdata = stats.duplicate()
                var mod_info = DataManager.modules.get(entry.get("id", ""), {})
                var wsub: String = mod_info.get("subtype", "energy")
                wdata["subtype"] = wsub
                wdata["name"] = mod_info.get("name", "Weapon")
                wdata["grid_pos"] = entry.grid_pos
                # Collect per-subtype heat stats from weapon modules
                if stats.has("heat_per_shot"):
                    _heat_per_shot[wsub] = stats.get("heat_per_shot")
                if stats.has("heat_decay"):
                    _heat_decay_rate[wsub] = stats.get("heat_decay")
                var wclass = mod_info.get("weapon_class", "primary")
                if wclass == "secondary":
                    secondary_weapons.append(wdata)
                elif wclass == "special":
                    special_weapons.append(wdata)
                elif wclass == "utility":
                    harpoon_has_module = true
                    harpoon_max_tether = wdata.get("tether_length", 500.0)
                    harpoon_pull_force = wdata.get("pull_force", 200.0)
                    harpoon_range = wdata.get("range", 600.0)
                    harpoon_proj_speed = wdata.get("projectile_speed", 1200.0)
                    harpoon_damage = wdata.get("damage", 10.0)
                else:
                    weapon_modules.append(wdata)
            "shield":
                max_shields += stats.get("shield_capacity", 0)
                shield_recharge_rate += stats.get("recharge_rate", 0)
            "engine":
                var mod_info_e = DataManager.modules.get(entry.get("id", ""), {})
                if mod_info_e.get("subtype", "") == "engine_block":
                    _engine_blocks.append(entry)
                else:
                    _thrusters.append(entry)
                extra_boost += stats.get("boost_impulse_bonus", 0)
            "sensor":
                scan_range += stats.get("scan_range", 0)
                scan_speed += stats.get("scan_speed", 0)


    damage_resist = minf(damage_resist, 0.6)

    # Shield supercharger parry HP — diminishing returns: each additional halves the bonus
    var sc_count: int = 0
    for entry in ship_layout:
        if entry.type == "shield_supercharger" and entry.get("hp", 1) > 0 and entry.powered:
            sc_count += 1
    var base_parry_hp: float = 600.0
    parry_max_hp = 0.0
    for i in sc_count:
        parry_max_hp += base_parry_hp / pow(2.0, i)

    # Engine Block adjacency — each block boosts adjacent thrusters by 100%,
    # plus 20% per adjacent Engine Block
    var block_boosts: Array = []
    for bi in _engine_blocks.size():
        var adj_blocks := 0
        for bj in _engine_blocks.size():
            if bi == bj:
                continue
            if HexUtil.cells_adjacent(_engine_blocks[bi].hex_cells, _engine_blocks[bj].hex_cells):
                adj_blocks += 1
        block_boosts.append(1.0 + adj_blocks * 0.2)

    for ti in _thrusters.size():
        var thrust_val: float = _thrusters[ti].stats.get("thrust", 0)
        var boost_mult := 0.0
        for bi in _engine_blocks.size():
            if HexUtil.cells_adjacent(_thrusters[ti].hex_cells, _engine_blocks[bi].hex_cells):
                boost_mult += block_boosts[bi]
        total_thrust += thrust_val * (1.0 + boost_mult)

    # Pure thrust-to-weight speed calculation
    const SPEED_PER_RATIO := 18.0
    const ACCEL_PER_RATIO := 28.0
    ship_weight = maxf(total_weight, 1.0)
    var tw_ratio = total_thrust / ship_weight
    max_speed = maxf(tw_ratio * SPEED_PER_RATIO, 50.0)
    acceleration = maxf(tw_ratio * ACCEL_PER_RATIO, 80.0)
    thrust_ratio = clampf(tw_ratio / 30.0, 0.1, 3.0)


    primary_group_keys.clear()
    for w in weapon_modules:
        var st = w.get("subtype", "energy")
        if st not in primary_group_keys:
            primary_group_keys.append(st)
    active_primary_idx = clampi(active_primary_idx, 0, maxi(primary_group_keys.size() - 1, 0))

    secondary_group_keys.clear()
    for w in secondary_weapons:
        var st = w.get("subtype", "kinetic")
        if st not in secondary_group_keys:
            secondary_group_keys.append(st)
    active_secondary_idx = clampi(active_secondary_idx, 0, maxi(secondary_group_keys.size() - 1, 0))

    special_group_keys.clear()
    for w in special_weapons:
        var st = w.get("subtype", "kinetic")
        if st not in special_group_keys:
            special_group_keys.append(st)
    active_special_idx = clampi(active_special_idx, 0, maxi(special_group_keys.size() - 1, 0))

    detection_radius = scan_range * GameManager.DETECTION_RANGE_MULT

    fire_rate = 0.15 if not weapon_modules.is_empty() else 0.25


    base_max_speed = max_speed
    base_acceleration = acceleration
    base_shield_recharge = shield_recharge_rate
    var p = POWER_PRESETS[power_preset]
    max_speed = base_max_speed * p.engine
    acceleration = base_acceleration * p.engine
    shield_recharge_rate = base_shield_recharge * p.shield
    boost_impulse = max_speed * 0.6 + extra_boost

func _compute_power_routing():


    var total_output: float = 0.0
    var total_draw: float = 0.0
    for entry in ship_layout:
        entry.powered = false
        if entry.get("hp", 1) <= 0:
            continue
        if entry.type == "reactor":
            total_output += entry.stats.get("power_output", 0)
        total_draw += entry.stats.get("power_draw", 0)

    if total_draw <= total_output:

        for entry in ship_layout:
            entry.powered = entry.get("hp", 1) > 0
        return


    var alive_entries: Array = []
    for entry in ship_layout:
        if entry.get("hp", 1) > 0:
            alive_entries.append(entry)
    alive_entries.sort_custom( func(a, b): return a.stats.get("power_draw", 0) < b.stats.get("power_draw", 0))


    var remaining = total_output
    for entry in alive_entries:
        if entry.type == "reactor":
            entry.powered = true


    for i in range(alive_entries.size() - 1, -1, -1):
        var entry = alive_entries[i]
        if entry.type == "reactor":
            continue
        var power_draw: float = entry.stats.get("power_draw", 0)
        if power_draw <= remaining:
            entry.powered = true
            remaining -= power_draw

func take_damage(amount: float, pierce: float = 0.0, hit_world_pos: Vector2 = Vector2.ZERO):
    if not alive:
        return
    if parry_active:
        parry_hp -= amount
        _add_shake(1.5)
        AudioManager.play_sfx("shield_hit", 0.3, 0.1)
        if parry_hp <= 0:
            _parry_blowout()
        return
    var _old_health = health
    var _old_max = max_health
    var _old_shields = shields
    shield_timer = shield_recharge_delay
    _last_damage_time = Time.get_ticks_msec() / 1000.0

    var pierce_dmg = amount * clampf(pierce, 0, 1)
    var shield_dmg = amount - pierce_dmg
    var absorbed: float = 0.0
    if shields > 0 and shield_dmg > 0:
        absorbed = minf(shields, shield_dmg)
        shields -= absorbed
        shield_dmg -= absorbed
    var hull_dmg = (shield_dmg + pierce_dmg) * (1.0 - damage_resist)

    var actual_dealt: float = 0.0
    if hull_dmg > 0:
        if ai_controlled:
            # AI clone: damage local ship_layout only, never touch GameManager.ship_modules
            var hit_cell = _find_hit_cell(hit_world_pos)
            var hit_mod: Dictionary = {}
            if hit_cell != Vector2i(-9999, -9999):
                for entry in ship_layout:
                    var cells = GameManager.get_mod_hex_cells(entry)
                    if hit_cell in cells:
                        hit_mod = entry
                        break
                if hit_mod.is_empty():
                    # No exact match — find nearest alive module to the hit cell
                    actual_dealt = GameManager._damage_nearest_module(hit_cell, hull_dmg, ship_layout)
            if hit_mod.is_empty() and actual_dealt == 0.0:
                # No hit position at all — random fallback
                var alive_mods: Array = []
                for entry in ship_layout:
                    if entry.get("hp", 1.0) > 0:
                        alive_mods.append(entry)
                if not alive_mods.is_empty():
                    hit_mod = alive_mods[randi() % alive_mods.size()]
            if not hit_mod.is_empty():
                actual_dealt = GameManager.damage_module(hit_mod, hull_dmg)
        else:
            var hit_cell = _find_hit_cell(hit_world_pos)
            if hit_cell != Vector2i(-9999, -9999):
                actual_dealt = GameManager.damage_ship_at_cell(hit_cell, hull_dmg)
            else:
                actual_dealt = GameManager.damage_random_module(hull_dmg)

        _recalc_module_stats()
        # Compute HP from ship_layout — single source of truth
        var total_hp: float = 0.0
        var total_max: float = 0.0
        for sl_entry in ship_layout:
            total_max += sl_entry.get("max_hp", 0.0)
            total_hp += maxf(sl_entry.get("hp", 0.0), 0.0)
        health = total_hp
        max_health = total_max

        _hull_cache_dirty = true
    damage_flash = 1.0
    _add_shake(4.0)
    var dmg_num = Node2D.new()
    dmg_num.set_script(damage_number_script)
    dmg_num.global_position = global_position + Vector2(randf_range(-10, 10), -20)
    var actual_dmg = actual_dealt if actual_dealt > 0 else absorbed
    dmg_num.setup(maxf(actual_dmg, 1.0), Color(1.0, 0.4, 0.3), 13)
    get_tree().current_scene.add_child(dmg_num)

    if absorbed > 0:
        AudioManager.play_sfx("shield_hit", 0.5, 0.1)
    else:
        AudioManager.play_sfx("hull_hit", 0.6, 0.08)
    health_changed.emit(health, max_health, shields, max_shields)
    queue_redraw()
    if health <= 0:
        death_cause = "combat"
        _on_death()


func _update_ship_bounds():

    if ship_layout.is_empty():
        ship_size = 20.0
        _ship_extent = ship_size
        _update_collision_radius(ship_size)
        return
    var max_extent: float = 0.0
    for mod in ship_layout:
        for hcell in mod.get("hex_cells", [mod.grid_pos]):
            var fp = _hex_to_local(hcell)
            max_extent = maxf(max_extent, fp.length() + MCELL)
    ship_size = maxf(max_extent + 4.0, 16.0)

    _rebuild_hull_cache()

    _rebuild_module_colliders()

func _draw():
    if ship_layout.is_empty():
        _draw_default_ship()
        return

    var flash_lerp = clampf(damage_flash, 0, 1)
    var time = Time.get_ticks_msec() * 0.001


    var glow_col = GameManager.ship_color_primary
    draw_circle(Vector2.ZERO, ship_size * 1.8, Color(glow_col, 0.03))
    draw_circle(Vector2.ZERO, ship_size * 1.2, Color(glow_col, 0.05))


    var rail_count: int = 0
    var rail_max_ct: float = 0.0
    var mac_count: int = 0
    var mac_max_ct: float = 0.0
    for ch in weapon_charges:
        if ch.type == "railgun":
            rail_count += 1
            var ct = clampf(ch.timer / RAILGUN_CHARGE_TIME, 0, 1)
            rail_max_ct = maxf(rail_max_ct, ct)
        elif ch.type == "macro":
            mac_count += 1
            var ct = clampf(ch.timer / MACRO_CHARGE_TIME, 0, 1)
            mac_max_ct = maxf(mac_max_ct, ct)
    if rail_count > 0:
        var ct = rail_max_ct
        var intensity = minf(rail_count, 4)
        var ease_ct = ct * ct * ct
        var rc = Color(0.7, 0.85, 1.0)
        var glow_r = ship_size * (0.24 + ease_ct * 0.32)
        draw_circle(Vector2.ZERO, glow_r, Color(rc, (0.004 + ease_ct * 0.024) * intensity))
        if ct > 0.4:
            var arc_alpha = clampf((ct - 0.4) / 0.6, 0, 1)
            for i in 3:
                var a = i * TAU / 3.0 + time * 2.0 + i * 0.5
                var outer_r = ship_size * (0.6 - arc_alpha * 0.32)
                var outer = Vector2.from_angle(a) * outer_r
                var inner = Vector2.from_angle(a + 0.3 * arc_alpha) * ship_size * 0.12
                draw_line(outer, inner, Color(rc, 0.04 * arc_alpha * intensity), 0.6 + arc_alpha * 0.4)
        if ct > 0.7:
            var core_alpha = clampf((ct - 0.7) / 0.3, 0, 1)
            draw_circle(Vector2.ZERO, ship_size * 0.16, Color(1.0, 1.0, 1.0, core_alpha * 0.06 * intensity))
    if mac_count > 0:
        var ct = mac_max_ct
        var mc = Color(1.0, 0.65, 0.15)
        for i in 6:
            var a = i * TAU / 6.0 + time * 3.0
            var outer_r = ship_size * (1.5 - ct * 0.8)
            var outer = Vector2.from_angle(a) * outer_r
            var inner = Vector2.from_angle(a) * ship_size * 0.2
            draw_line(outer, inner, Color(mc, 0.15 + ct * 0.3), 1.0 + ct)
        draw_circle(Vector2.ZERO, ship_size * (0.6 + ct * 0.4), Color(mc, 0.03 + ct * 0.1))
    if weapon_flash > 0:
        var wf = clampf(weapon_flash, 0, 1)
        draw_circle(Vector2.ZERO, ship_size * 1.5, Color(weapon_flash_color, 0.1 * wf))
        draw_circle(Vector2.ZERO, ship_size * 0.8, Color(Color.WHITE, 0.15 * wf))


    _draw_engine_flames(time, velocity.length(), max_speed)


    _draw_hull(flash_lerp)


    _draw_module_accents(time)


    _draw_running_lights_auto(time)


    _draw_shield_bubble(time)


    if scan_pulse_active:
        var pulse_alpha = 1.0 - clampf(scan_pulse_radius / scan_range, 0, 1)
        draw_arc(Vector2.ZERO, scan_pulse_radius, 0, TAU, 48, Color(0.2, 0.9, 0.5, pulse_alpha * 0.6), 2.0)
        draw_arc(Vector2.ZERO, scan_pulse_radius * 0.95, 0, TAU, 48, Color(0.2, 0.9, 0.5, pulse_alpha * 0.2), 4.0)

    if parry_active:
        var parry_r = ship_size * 1.0
        var parry_alpha = clampf(parry_timer / 0.15, 0.3, 1.0)
        draw_circle(Vector2.ZERO, parry_r, Color(0.2, 0.6, 1.0, 0.06 * parry_alpha))
        for i in 6:
            var a = parry_spin_angle + i * TAU / 6.0
            var p1 = Vector2.from_angle(a) * parry_r
            var p2 = Vector2.from_angle(a + 0.4) * parry_r
            draw_line(p1, p2, Color(0.3, 0.8, 1.0, 0.6 * parry_alpha), 2.5)
            draw_circle(p1, 3.0, Color(0.5, 0.9, 1.0, 0.5 * parry_alpha))
        draw_arc(Vector2.ZERO, parry_r, 0, TAU, 36, Color(0.3, 0.7, 1.0, 0.35 * parry_alpha), 1.5)
        draw_arc(Vector2.ZERO, parry_r * 0.9, 0, TAU, 36, Color(0.2, 0.5, 0.9, 0.15 * parry_alpha), 3.0)

    if beam_active:
        _draw_beam(time)

    if harpoon_state != HarpoonState.IDLE:
        _draw_harpoon_tether(time)

    var arrow_dist = ship_size + 10.0
    var arrow_len = 8.0
    var arrow_w = 4.0
    var arrow_tip = Vector2(arrow_dist + arrow_len, 0)
    var arrow_base_l = Vector2(arrow_dist, - arrow_w)
    var arrow_base_r = Vector2(arrow_dist, arrow_w)
    var arrow_col = Color(0.3, 0.6, 1.0, 0.7)
    draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_base_l, arrow_base_r]), arrow_col)

    draw_circle(Vector2(arrow_dist + arrow_len * 0.4, 0), arrow_len * 0.8, Color(0.3, 0.6, 1.0, 0.1))

func _beam_tick_damage(w: Dictionary, wpos: Vector2, angle: float, cursor_pos: Vector2):
    var beam_range = float(w.get("range", 3150))
    var dmg = float(w.get("damage", 60))
    var pierce = float(w.get("shield_pierce", 0.0))
    var beam_dir = Vector2.from_angle(angle)
    var gp = w.get("grid_pos", Vector2i.ZERO)
    var cursor_dist = minf(wpos.distance_to(cursor_pos), beam_range)
    var closest_dist: float = cursor_dist
    var closest_target: Node2D = null
    var closest_point: Vector2 = wpos + beam_dir * cursor_dist
    var groups = ["enemies", "npc_ships"]
    if ai_controlled:
        groups = ["player", "npc_ships"]
    for group_name in groups:
        for t in get_tree().get_nodes_in_group(group_name):
            if t == self:
                continue
            if not is_instance_valid(t) or not t.has_method("take_damage"):
                continue
            var to_t = t.global_position - wpos
            var proj_len = to_t.dot(beam_dir)
            if proj_len < 0 or proj_len > closest_dist:
                continue
            var on_beam = wpos + beam_dir * proj_len
            var perp_dist = on_beam.distance_to(t.global_position)
            var hit_r: float = t.get("ship_size") if "ship_size" in t else 20.0
            if perp_dist < hit_r + 12.0:
                closest_dist = proj_len
                closest_target = t
                closest_point = on_beam
    beam_end_positions[gp] = closest_point
    if closest_target:
        var delta = get_physics_process_delta_time()
        closest_target.take_damage(dmg * delta * power_mult_weapon, pierce, closest_point)

func _draw_beam(time: float):
    for w in secondary_weapons:
        if w.get("subtype", "") != "beam":
            continue
        var gp = w.get("grid_pos", Vector2i.ZERO)
        var wpos_local = _hex_to_local(gp)
        var end_global = beam_end_positions.get(gp, Vector2.ZERO)
        if end_global == Vector2.ZERO:
            continue
        var end_local = (end_global - global_position).rotated(-rotation)
        var pulse = 0.93 + sin(time * 3.0) * 0.07
        # Wide outer glow — deep crimson
        draw_line(wpos_local, end_local, Color(0.6, 0.05, 0.05, 0.08), 36.0)
        # Mid glow — crimson
        draw_line(wpos_local, end_local, Color(0.8, 0.1, 0.05, 0.15), 20.0)
        # Core beam — bright red, steady
        draw_line(wpos_local, end_local, Color(1.0, 0.2, 0.1, 0.85), 8.0 * pulse)
        # Hot center — near-white red
        draw_line(wpos_local, end_local, Color(1.0, 0.6, 0.5, 0.6), 3.0)
        # Muzzle glow
        draw_circle(wpos_local, 12.0, Color(1.0, 0.3, 0.1, 0.35))
        # Impact glow
        draw_circle(end_local, 10.0, Color(1.0, 0.2, 0.05, 0.3))

func _draw_harpoon_tether(time: float):
    var end_local = (harpoon_head_pos - global_position).rotated(-rotation)
    var start_local = Vector2.ZERO
    var chain_dir = end_local - start_local
    var chain_len = chain_dir.length()
    if chain_len < 1.0:
        return
    var chain_norm = chain_dir.normalized()
    var chain_perp = Vector2(-chain_norm.y, chain_norm.x)

    var seg_count: int = clampi(int(chain_len / 12.0), 4, 40)
    var points: PackedVector2Array = PackedVector2Array()
    for i in seg_count + 1:
        var t = float(i) / float(seg_count)
        var base = start_local + chain_dir * t
        var wave1 = sin(t * 12.0 + time * 6.0) * 4.0
        var wave2 = sin(t * 18.0 - time * 9.0) * 2.0
        var taper = sin(t * PI) * 0.8 + 0.2
        points.append(base + chain_perp * (wave1 + wave2) * taper)

    # Outer glow (purple)
    for i in points.size() - 1:
        draw_line(points[i], points[i + 1], Color(0.5, 0.15, 0.7, 0.12), 6.0)
    # Main line (green)
    for i in points.size() - 1:
        draw_line(points[i], points[i + 1], Color(0.2, 0.75, 0.3, 0.6), 2.5)
    # Inner core (bright green)
    for i in points.size() - 1:
        draw_line(points[i], points[i + 1], Color(0.4, 1.0, 0.5, 0.85), 1.0)

    # Particles along chain
    for i in range(0, points.size(), 3):
        var particle_pulse = sin(time * 8.0 + float(i) * 1.5) * 0.3 + 0.7
        draw_circle(points[i], 2.0 * particle_pulse, Color(0.3, 0.9, 0.4, 0.3 * particle_pulse))

    # Harpoon head glow
    var head_pulse = sin(time * 5.0) * 0.2 + 0.8
    draw_circle(end_local, 8.0, Color(0.4, 0.2, 0.6, 0.15 * head_pulse))
    draw_circle(end_local, 4.0, Color(0.3, 0.9, 0.4, 0.5 * head_pulse))

    # Harpoon sprite during EXTENDING
    if harpoon_state == HarpoonState.EXTENDING:
        var head_angle = chain_dir.angle()
        draw_set_transform(end_local, head_angle, Vector2(0.5, 0.5))
        draw_texture(_spr_harpoon, -Vector2(8, 8), Color(1, 1, 1, 0.9))
        draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _get_module_draw_color(type_str: String) -> Color:

    var pri = GameManager.ship_color_primary
    var sec = GameManager.ship_color_secondary

    match type_str:
        "armor":
            return sec
        "conduit":
            return sec.lerp(pri, 0.3)
        "hallway":
            return sec.lerp(Color(0.45, 0.45, 0.5), 0.3)
        "airlock":
            return pri.lerp(Color(0.7, 0.5, 0.2), 0.2)
        "structural":
            return sec.lerp(Color(0.5, 0.5, 0.55), 0.3)
        "reactor":
            return pri.lerp(Color(0.95, 0.85, 0.3), 0.25)
        "weapon":
            return pri.lerp(Color(0.9, 0.3, 0.25), 0.15)
        "shield":
            return pri.lerp(Color(0.3, 0.5, 1.0), 0.15)
        "engine":
            return pri.lerp(Color(1.0, 0.6, 0.2), 0.12)
        "sensor":
            return pri.lerp(Color(0.25, 0.85, 0.45), 0.15)
        "cargo":
            return sec.lerp(Color(0.7, 0.55, 0.2), 0.3)
        "quarters":
            return pri.lerp(Color(0.75, 0.55, 0.3), 0.2)
        "mess":
            return pri.lerp(Color(0.8, 0.5, 0.2), 0.2)
        "medbay":
            return pri.lerp(Color(0.3, 0.8, 0.4), 0.25)
        "construction_hangar":
            return sec.lerp(Color(0.55, 0.55, 0.6), 0.3)
        "basic_workshop", "farmers_workshop":
            return sec.lerp(Color(0.6, 0.5, 0.35), 0.3)
        "solar_field":
            return pri.lerp(Color(0.85, 0.75, 0.3), 0.2)
        "life_support":
            return pri.lerp(Color(0.3, 0.7, 0.7), 0.2)
        "brig":
            return sec.lerp(Color(0.45, 0.4, 0.4), 0.3)
        "hangar":
            return pri.lerp(Color(0.4, 0.5, 0.7), 0.2)
        "hydroponics":
            return pri.lerp(Color(0.3, 0.75, 0.3), 0.25)
        "armory":
            return pri.lerp(Color(0.8, 0.4, 0.15), 0.2)
        "rec_room":
            return pri.lerp(Color(0.6, 0.5, 0.8), 0.2)
        "bridge":
            return pri.lerp(Color(0.5, 0.6, 0.9), 0.25)
        "fuel_scoop":
            return pri.lerp(Color(0.9, 0.7, 0.2), 0.25)
        "mining":
            return pri.lerp(Color(0.7, 0.5, 0.3), 0.2)
        "research_lab":
            return pri.lerp(Color(0.3, 0.6, 0.9), 0.25)
        "ladder":
            return sec.lerp(Color(0.65, 0.55, 0.35), 0.3)
        _:
            return pri

func _rebuild_hull_cache():

    _cached_all_cells.clear()
    _cached_cell_corners.clear()
    _cached_cell_draws.clear()
    _cached_sprite_draws.clear()
    for mod in ship_layout:
        for hcell in mod.get("hex_cells", [mod.grid_pos]):
            _cached_all_cells[hcell] = mod
            _cached_cell_corners[hcell] = _hex_polygon_local(hcell)

    for cell in _cached_all_cells:
        var mod = _cached_all_cells[cell]
        var tint = _get_module_draw_color(mod.type)
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
    for mod in ship_layout:
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
        var shape = mod_data.get("hex_shape", HexUtil.default_shape(mod_data.get("hex_size", 1)))
        var sp0 = HexUtil.hex_to_pixel(Vector2i(shape[0][0], shape[0][1]), MCELL)
        var smin = sp0
        var smax = sp0
        for sc in shape:
            var sp = HexUtil.hex_to_pixel(Vector2i(sc[0], sc[1]), MCELL)
            smin.x = minf(smin.x, sp.x)
            smin.y = minf(smin.y, sp.y)
            smax.x = maxf(smax.x, sp.x)
            smax.y = maxf(smax.y, sp.y)
        var hex_offset = (smin + smax) * 0.5
        var local_offset = Vector2(-hex_offset.y, hex_offset.x).rotated(mod_rot)
        var center = anchor_local + local_offset
        var spr_scale = MCELL / 50.0
        _cached_sprite_draws.append({tex = tex, pos = center, spr_scale = spr_scale, rot = mod_rot + PI / 2.0, mod_ref = mod})

    var nb_map: Array = [
        Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
        Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
    ]
    _cached_hull_contour = _build_smooth_hull(_cached_all_cells, nb_map)
    _hull_cache_dirty = false


func _draw_default_ship():

    var pri = GameManager.ship_color_primary
    var sec = GameManager.ship_color_secondary
    var color = pri
    if damage_flash > 0:
        color = color.lerp(Color.WHITE, clampf(damage_flash, 0, 1))
        sec = sec.lerp(Color.WHITE, clampf(damage_flash, 0, 1))
    var s = ship_size
    var time = Time.get_ticks_msec() * 0.001


    draw_circle(Vector2.ZERO, s * 1.6, Color(color, 0.04))


    if velocity.length() > 20:
        var def_speed_frac = velocity.length() / maxf(max_speed, 1.0)
        var intensity = clampf(def_speed_frac, 0.3, 1.5)
        var eng_color = Color(1.0, 0.5, 0.1, clampf(intensity, 0, 1))
        if def_speed_frac > 1.3:
            eng_color = Color(0.4, 0.6, 1.0, 0.95)
        var flicker = sin(time * 12.0) * 0.1 + 0.9
        var flicker2 = sin(time * 15.0 + 2.0) * 0.08 + 0.92
        var flame_len = s * 0.55 * intensity * flicker
        var flame_len2 = s * 0.45 * intensity * flicker2

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, - s * 0.27), Vector2( - s * 0.3 - flame_len * 1.2, - s * 0.12), Vector2( - s * 0.3, - s * 0.01)]), Color(eng_color, eng_color.a * 0.15))

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, - s * 0.22), Vector2( - s * 0.3 - flame_len, - s * 0.12), Vector2( - s * 0.3, - s * 0.03)]), eng_color)

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, - s * 0.17), Vector2( - s * 0.3 - flame_len * 0.5, - s * 0.12), Vector2( - s * 0.3, - s * 0.07)]), Color(1.0, 0.92, 0.6, 0.5 * intensity))

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, s * 0.01), Vector2( - s * 0.3 - flame_len2 * 1.2, s * 0.12), Vector2( - s * 0.3, s * 0.27)]), Color(eng_color, eng_color.a * 0.15))

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, s * 0.03), Vector2( - s * 0.3 - flame_len2, s * 0.12), Vector2( - s * 0.3, s * 0.22)]), eng_color)

        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.3, s * 0.07), Vector2( - s * 0.3 - flame_len2 * 0.5, s * 0.12), Vector2( - s * 0.3, s * 0.17)]), Color(1.0, 0.92, 0.6, 0.5 * intensity))

        var cfl = flame_len * 0.4 * flicker2
        draw_colored_polygon(PackedVector2Array([Vector2( - s * 0.38, - s * 0.04), Vector2( - s * 0.38 - cfl, 0), Vector2( - s * 0.38, s * 0.04)]), Color(eng_color, eng_color.a * 0.6))


    var wing_u = PackedVector2Array([
        Vector2(s * 0.1, - s * 0.22), 
        Vector2(s * 0.05, - s * 0.38), 
        Vector2( - s * 0.15, - s * 0.55), 
        Vector2( - s * 0.58, - s * 0.62), 
        Vector2( - s * 0.25, - s * 0.2), 
    ])
    draw_colored_polygon(wing_u, sec * 0.9)
    var wing_l = PackedVector2Array([
        Vector2(s * 0.1, s * 0.22), 
        Vector2(s * 0.05, s * 0.38), 
        Vector2( - s * 0.15, s * 0.55), 
        Vector2( - s * 0.58, s * 0.62), 
        Vector2( - s * 0.25, s * 0.2), 
    ])
    draw_colored_polygon(wing_l, sec * 0.9)


    draw_colored_polygon(PackedVector2Array([
        Vector2(s * 0.08, - s * 0.24), 
        Vector2(s * 0.03, - s * 0.36), 
        Vector2( - s * 0.12, - s * 0.48), 
        Vector2( - s * 0.22, - s * 0.22), 
    ]), sec * 1.05)


    var body = PackedVector2Array([
        Vector2(s * 0.95, 0), 
        Vector2(s * 0.5, - s * 0.17), 
        Vector2(s * 0.1, - s * 0.22), 
        Vector2( - s * 0.15, - s * 0.21), 
        Vector2( - s * 0.3, - s * 0.14), 
        Vector2( - s * 0.38, 0), 
        Vector2( - s * 0.3, s * 0.14), 
        Vector2( - s * 0.15, s * 0.21), 
        Vector2(s * 0.1, s * 0.22), 
        Vector2(s * 0.5, s * 0.17), 
    ])
    draw_colored_polygon(body, color * 0.85)


    var highlight = PackedVector2Array([
        Vector2(s * 0.9, - s * 0.01), 
        Vector2(s * 0.48, - s * 0.15), 
        Vector2(s * 0.1, - s * 0.2), 
        Vector2( - s * 0.12, - s * 0.18), 
        Vector2( - s * 0.25, - s * 0.1), 
        Vector2( - s * 0.25, - s * 0.02), 
        Vector2(s * 0.1, - s * 0.04), 
        Vector2(s * 0.5, - s * 0.02), 
    ])
    draw_colored_polygon(highlight, Color(1.0, 1.0, 1.0, 0.06))


    var shadow = PackedVector2Array([
        Vector2(s * 0.3, s * 0.05), 
        Vector2( - s * 0.25, s * 0.05), 
        Vector2( - s * 0.3, s * 0.14), 
        Vector2( - s * 0.15, s * 0.21), 
        Vector2(s * 0.1, s * 0.22), 
        Vector2(s * 0.3, s * 0.16), 
    ])
    draw_colored_polygon(shadow, Color(0, 0, 0, 0.08))


    var nac_col = sec * 0.7

    draw_colored_polygon(PackedVector2Array([
        Vector2( - s * 0.15, - s * 0.12), 
        Vector2( - s * 0.15, - s * 0.24), 
        Vector2( - s * 0.32, - s * 0.24), 
        Vector2( - s * 0.32, - s * 0.12), 
    ]), nac_col)

    draw_line(Vector2( - s * 0.32, - s * 0.25), Vector2( - s * 0.32, - s * 0.11), sec * 0.45, 1.5)

    draw_colored_polygon(PackedVector2Array([
        Vector2( - s * 0.15, s * 0.12), 
        Vector2( - s * 0.15, s * 0.24), 
        Vector2( - s * 0.32, s * 0.24), 
        Vector2( - s * 0.32, s * 0.12), 
    ]), nac_col)
    draw_line(Vector2( - s * 0.32, s * 0.11), Vector2( - s * 0.32, s * 0.25), sec * 0.45, 1.5)


    draw_line(Vector2(s * 0.5, 0), Vector2( - s * 0.15, 0), color * 0.55, 0.8)
    draw_line(Vector2(s * 0.7, 0), Vector2(s * 0.85, 0), color * 0.65, 0.5)


    var cockpit = PackedVector2Array([
        Vector2(s * 0.88, 0), 
        Vector2(s * 0.5, - s * 0.1), 
        Vector2(s * 0.38, - s * 0.06), 
        Vector2(s * 0.35, 0), 
        Vector2(s * 0.38, s * 0.06), 
        Vector2(s * 0.5, s * 0.1), 
    ])
    draw_colored_polygon(cockpit, Color(0.2, 0.45, 0.7, 0.75))

    draw_polyline(PackedVector2Array([Vector2(s * 0.88, 0), Vector2(s * 0.5, - s * 0.1), Vector2(s * 0.38, - s * 0.06), Vector2(s * 0.35, 0), Vector2(s * 0.38, s * 0.06), Vector2(s * 0.5, s * 0.1), Vector2(s * 0.88, 0)]), 
        Color(0.5, 0.75, 1.0, 0.6), 0.8)

    draw_line(Vector2(s * 0.8, - s * 0.02), Vector2(s * 0.5, - s * 0.08), Color(0.7, 0.9, 1.0, 0.35), 0.7)
    draw_line(Vector2(s * 0.55, - s * 0.07), Vector2(s * 0.42, - s * 0.04), Color(0.7, 0.9, 1.0, 0.2), 0.5)


    draw_line(Vector2(s * 0.4, - s * 0.17), Vector2(s * 0.4, s * 0.17), color * 0.45, 0.5)
    draw_line(Vector2(s * 0.1, - s * 0.22), Vector2(s * 0.1, s * 0.22), color * 0.45, 0.5)
    draw_line(Vector2( - s * 0.12, - s * 0.2), Vector2( - s * 0.12, s * 0.2), color * 0.45, 0.5)

    draw_line(Vector2(s * 0.45, - s * 0.14), Vector2( - s * 0.1, - s * 0.18), color * 0.48, 0.4)
    draw_line(Vector2(s * 0.45, s * 0.14), Vector2( - s * 0.1, s * 0.18), color * 0.48, 0.4)


    draw_line(Vector2(s * 0.0, - s * 0.3), Vector2( - s * 0.4, - s * 0.5), sec * 0.55, 0.5)
    draw_line(Vector2(s * 0.0, s * 0.3), Vector2( - s * 0.4, s * 0.5), sec * 0.55, 0.5)


    draw_line(Vector2(s * 0.05, - s * 0.38), Vector2( - s * 0.15, - s * 0.55), sec * 1.3, 0.8)
    draw_line(Vector2(s * 0.05, s * 0.38), Vector2( - s * 0.15, s * 0.55), sec * 1.3, 0.8)

    draw_line(Vector2( - s * 0.25, - s * 0.2), Vector2( - s * 0.58, - s * 0.62), sec * 0.5, 0.7)
    draw_line(Vector2( - s * 0.25, s * 0.2), Vector2( - s * 0.58, s * 0.62), sec * 0.5, 0.7)


    draw_circle(Vector2( - s * 0.5, - s * 0.58), 2.0, sec * 0.5)
    draw_circle(Vector2( - s * 0.5, - s * 0.58), 1.2, Color(0.9, 0.3, 0.2, 0.5))
    draw_line(Vector2( - s * 0.5, - s * 0.58), Vector2( - s * 0.42, - s * 0.58), sec * 0.6, 1.0)
    draw_circle(Vector2( - s * 0.5, s * 0.58), 2.0, sec * 0.5)
    draw_circle(Vector2( - s * 0.5, s * 0.58), 1.2, Color(0.9, 0.3, 0.2, 0.5))
    draw_line(Vector2( - s * 0.5, s * 0.58), Vector2( - s * 0.42, s * 0.58), sec * 0.6, 1.0)


    var body_outline = PackedVector2Array([
        Vector2(s * 0.95, 0), Vector2(s * 0.5, - s * 0.17), Vector2(s * 0.1, - s * 0.22), 
        Vector2( - s * 0.15, - s * 0.21), Vector2( - s * 0.3, - s * 0.14), Vector2( - s * 0.38, 0), 
        Vector2( - s * 0.3, s * 0.14), Vector2( - s * 0.15, s * 0.21), Vector2(s * 0.1, s * 0.22), 
        Vector2(s * 0.5, s * 0.17), Vector2(s * 0.95, 0), 
    ])
    draw_polyline(body_outline, Color(color, 0.12), 4.0)
    draw_polyline(body_outline, Color(color, 0.35), 1.2)


    var blink = sin(time * 3.0) * 0.5 + 0.5
    var blink2 = sin(time * 3.0 + PI) * 0.5 + 0.5

    draw_circle(Vector2( - s * 0.58, - s * 0.62), 2.0, Color(1.0, 0.15, 0.1, 0.15))
    draw_circle(Vector2( - s * 0.58, - s * 0.62), 1.2, Color(1.0, 0.2, 0.15, blink * 0.9))

    draw_circle(Vector2( - s * 0.58, s * 0.62), 2.0, Color(0.1, 1.0, 0.15, 0.15))
    draw_circle(Vector2( - s * 0.58, s * 0.62), 1.2, Color(0.15, 1.0, 0.2, blink * 0.9))

    draw_circle(Vector2(s * 0.95, 0), 1.5, Color(1.0, 1.0, 1.0, 0.1))
    draw_circle(Vector2(s * 0.95, 0), 0.8, Color(1.0, 1.0, 1.0, blink2 * 0.85))

    draw_circle(Vector2( - s * 0.38, 0), 1.3, Color(1.0, 0.6, 0.1, 0.1))
    draw_circle(Vector2( - s * 0.38, 0), 0.7, Color(1.0, 0.65, 0.15, blink2 * 0.7))


    if shields > 0:
        var shield_frac = shields / max_shields
        var shield_alpha = shield_frac * 0.25
        var sr = s + 6
        draw_arc(Vector2.ZERO, sr + 2, 0, TAU, 48, Color(0.2, 0.4, 1.0, shield_alpha * 0.15), 5.0)
        draw_arc(Vector2.ZERO, sr, 0, TAU, 48, Color(0.3, 0.5, 1.0, shield_alpha), 2.0)
        var hex_count = 12
        for hi in hex_count:
            var ha = float(hi) / float(hex_count) * TAU
            var ha2 = float(hi + 1) / float(hex_count) * TAU
            var shimmer = sin(time * 2.0 + ha * 3.0) * 0.3 + 0.7
            draw_line(Vector2(cos(ha) * sr, sin(ha) * sr), Vector2(cos(ha2) * sr, sin(ha2) * sr), 
                Color(0.4, 0.6, 1.0, shield_alpha * shimmer * 1.5), 1.0)


    if scan_pulse_active:
        var pulse_alpha = 1.0 - clampf(scan_pulse_radius / scan_range, 0, 1)
        draw_arc(Vector2.ZERO, scan_pulse_radius, 0, TAU, 48, Color(0.2, 0.9, 0.5, pulse_alpha * 0.6), 2.0)



# ── Collision Damage ──────────────────────────────────────────────────

func _get_collision_mass() -> float:
    return ship_weight

func _should_collide_with(other: Area2D) -> bool:
    if ai_controlled:
        return other.is_in_group("player") or other.is_in_group("station_entities")
    return other.is_in_group("enemies") or other.is_in_group("station_entities") or other.is_in_group("npc_ships")

func _on_collision_impact(damage: float, _closing_speed: float):
    _add_shake(clampf(damage / 5.0, 1.0, 8.0))

func _on_death():
    alive = false
    destroyed.emit()

func _apply_collision_damage(amount: float, _hit_pos: Vector2):
    if parry_active:
        parry_hp -= amount
        parry_timer = minf(parry_timer + 0.2, PARRY_MAX_DURATION * parry_max_duration_mult)
        parry_reflected_count += 1
        AudioManager.play_sfx("shield_hit", 0.6, 0.1)
        _add_shake(1.5)
        if parry_hp <= 0:
            _parry_blowout()
        return
    _last_damage_time = Time.get_ticks_msec() / 1000.0
    death_cause = "collision"
    super._apply_collision_damage(amount, _hit_pos)
    # Sync collision damage to GameManager so weapon hits don't recalculate stale HP
    if not ai_controlled:
        _sync_layout_hp_to_gm()
    _recalc_module_stats()
    # Recompute health from ship_layout (single source of truth)
    var total_hp: float = 0.0
    var total_max: float = 0.0
    for sl_entry in ship_layout:
        total_max += sl_entry.get("max_hp", 0.0)
        total_hp += maxf(sl_entry.get("hp", 0.0), 0.0)
    health = total_hp
    max_health = total_max
    health_changed.emit(health, max_health, shields, max_shields)
