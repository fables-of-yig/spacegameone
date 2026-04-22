extends Area2D

const EnemyShipBTBuilder = preload("res://Space/scripts/runtime/ship_ai/enemy_ship_bt_builder.gd")


var max_speed: float = 220.0
var acceleration: float = 400.0
var max_health: float = 40.0
var fire_rate: float = 1.2
var damage: float = 8.0
var proj_speed: float = 500.0

var health: float
var velocity: Vector2 = Vector2.ZERO
var knockback_vel: Vector2 = Vector2.ZERO
var target: Node2D = null
var can_fire: bool = true
var ai_controller: RefCounted = null  # ClonedAI instance, or null for default AI
var _ship_bt: BeehaveTree = null
var damage_flash: float = 0.0
var ship_size: float = 16.0
var ship_color: Color = Color(1.0, 0.3, 0.2)
var orbit_distance: float = 280.0
var orbit_dir: float = 1.0

var class_id: String = "fighter"
var enemy_name: String = "Fighter"
var shape_type: String = "chevron"
var behavior: String = "orbit"
var weapon_type: String = "laser"
var scanned: bool = false
var crew_count: int = 2
var damage_reduction: float = 0.0
var shields: float = 0.0
var max_shields: float = 0.0
var shield_regen: float = 0.0
var shield_regen_delay: float = 3.0
var _shield_hit_timer: float = 0.0


var strafe_timer: float = 0.0
var strafe_dir: float = 1.0
var burst_count: int = 0
var burst_timer: float = 0.0
var dodge_timer: float = 0.0
var _locked_dir: Vector2 = Vector2.ZERO
var _lock_timer: float = 0.0
var turn_rate: float = 3.0  # radians/sec — how fast we can change velocity direction


var spark_timer: float = 0.0
var engine_flicker: float = 0.0
var running_light_phase: float = 0.0

var _bake_ci: CanvasItem = null
var _hull_texture: ImageTexture = null
# Optional static hull image — when non-empty, _bake_hull_texture loads this
# PNG instead of procedurally baking from modules. Lets a NPC template or
# enemy class reference a single PNG sprite from an asset pack
# (e.g., "res://Space/art/ships/enemy_spaceship_game_sprites/ship_01.png")
# rather than building the visual from a hex module grid.
@export var static_hull_path: String = ""
var _hull_tex_half: Vector2 = Vector2.ZERO

var damage_number_script: GDScript = preload("res://Space/scripts/combat/damage_number.gd")
var projectile_scene: PackedScene

static var _spr_pulse_mk1: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk1.png")
static var _spr_pulse_mk2: Texture2D = preload("res://Space/art/projectiles/PulseLaserMk2.png")
static var _spr_autocannon: Texture2D = preload("res://Space/art/projectiles/Autocannon.png")
static var _spr_railgun: Texture2D = preload("res://Space/art/projectiles/Railgun.png")
static var _spr_mac: Texture2D = preload("res://Space/art/projectiles/MAC Gun.png")
static var _spr_missile: Texture2D = preload("res://Space/art/projectiles/MissileBattery.png")

enum AI{IDLE, APPROACH, ORBIT, FLEE, STRAFE, CHARGE}
var ai_state: AI = AI.IDLE

signal died(pos: Vector2, size: float)

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    health = max_health
    add_to_group("enemies")
    orbit_dir = [-1.0, 1.0].pick_random()
    projectile_scene = preload("res://Space/scenes/projectile.tscn")
    running_light_phase = randf() * TAU


    var shape = CircleShape2D.new()
    shape.radius = ship_size
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)

func setup_class(cid: String):
    class_id = cid
    var data = DataManager.enemy_classes.get(cid, {})
    if data.is_empty():
        return
    enemy_name = data.get("name", "Enemy")
    max_health = data.get("max_health", 40)
    max_speed = data.get("max_speed", 220)
    acceleration = data.get("acceleration", 400)
    fire_rate = data.get("fire_rate", 1.2)
    damage = data.get("damage", 8)
    proj_speed = data.get("proj_speed", 500)
    ship_size = data.get("ship_size", 16) * 6.0
    orbit_distance = data.get("orbit_distance", 280)
    shape_type = data.get("shape", "chevron")
    behavior = data.get("behavior", "orbit")
    weapon_type = data.get("weapon_type", "laser")
    crew_count = data.get("crew_count", 2)
    damage_reduction = data.get("damage_reduction", 0.0)
    max_shields = data.get("max_shields", 0.0)
    shield_regen = data.get("shield_regen", 0.0)
    shield_regen_delay = data.get("shield_regen_delay", 3.0)
    shields = max_shields

    # Turn rate — heavier ships commit harder to their direction
    match behavior:
        "approach":   turn_rate = 1.0   # bomber: ~3s for a 180
        "tank":       turn_rate = 0.8   # gunship: ~4s for a 180
        "kite":       turn_rate = 1.5   # missile frigate: ~2s for a 180
        "orbit":      turn_rate = 2.5   # fighter: moderate agility
        "strafe":     turn_rate = 3.0   # scout: nimble
        "aggressive": turn_rate = 2.5   # interceptor: moderate turn, commits during locked passes
        "elite":      turn_rate = 2.8   # elite: fast but not instant
        _:            turn_rate = 2.5

    var cb = data.get("color_base", [1.0, 0.3, 0.2])
    ship_color = Color(
        cb[0] + randf_range(-0.1, 0.1),
        cb[1] + randf_range(-0.1, 0.1),
        cb[2] + randf_range(-0.1, 0.1)
    )

    health = max_health


    for child in get_children():
        if child is CollisionShape2D and child.shape is CircleShape2D:
            child.shape.radius = ship_size
    _ensure_behavior_tree()
    queue_redraw()
    _bake_hull_texture.call_deferred()

func _physics_process(delta: float):
    if behavior == "dummy":
        # Target dummy — stationary, no AI, no shooting
        if damage_flash > 0:
            damage_flash -= delta * 4.0
        running_light_phase += delta * 3.0
        queue_redraw()
        return

    _process_enemy_collisions(delta)

    # Cloned AI controller — if set, it handles movement + firing
    if not _target_valid():
        _find_target()

    if ai_controller and _target_valid() and ai_controller.decide(self, target, delta):
        pass  # Cloned AI handles movement and firing
    else:
        # Tick direction lock — AI functions use _locked_dir while locked
        if _lock_timer > 0:
            _lock_timer -= delta

        # Save pre-AI velocity so we can apply turn rate limiting
        var old_vel = velocity

        if _ship_bt == null or not is_instance_valid(_ship_bt):
            _ensure_behavior_tree()

        var bt_status: int = BeehaveTree.FAILURE
        if _ship_bt != null and is_instance_valid(_ship_bt):
            _ship_bt.blackboard.set_value("delta", delta)
            bt_status = _ship_bt.tick()
        if bt_status == BeehaveTree.FAILURE:
            velocity = velocity.move_toward(Vector2.ZERO, acceleration * 0.6 * delta)

        # Steering limiter — ships can't change direction instantly
        # This gives everything real momentum and commit to their heading
        var old_speed = old_vel.length()
        if old_speed > 30.0:
            var new_speed = velocity.length()
            var old_dir = old_vel / old_speed
            var desired_dir = velocity.normalized() if new_speed > 1.0 else old_dir
            var angle_diff = old_dir.angle_to(desired_dir)
            var max_turn = turn_rate * delta
            var clamped_angle = clampf(angle_diff, -max_turn, max_turn)
            var steered_dir = old_dir.rotated(clamped_angle)
            velocity = steered_dir * new_speed

        # Collision avoidance — hard velocity redirect, not a gentle force
        # Skip for aggressive (interceptor) during attack runs — they WANT to fly past
        if _target_valid():
            var to_target = target.global_position - global_position
            var dist = to_target.length()
            var dir = to_target.normalized()
            var avoid_radius = maxf(ship_size + 300.0, orbit_distance)
            if dist < avoid_radius and not (behavior == "aggressive" and _lock_timer > 0):
                var closing = velocity.dot(dir)
                if closing > 0:
                    var urgency = clampf(1.0 - dist / avoid_radius, 0.0, 1.0)
                    var perp = Vector2(-dir.y, dir.x)
                    if velocity.dot(perp) < 0:
                        perp = -perp
                    var strip = closing * urgency
                    velocity -= dir * strip
                    velocity += perp * strip
                    if urgency > 0.5 and _lock_timer > 0:
                        _lock_timer = 0.0

        var speed_cap = max_speed * 2.0 if (behavior == "aggressive" and _lock_timer > 0) else max_speed * 1.6
        velocity = velocity.limit_length(speed_cap)
        position += velocity * delta
        # Gentle drag toward base max_speed so bursts decay naturally
        if velocity.length() > max_speed:
            velocity = velocity.move_toward(velocity.normalized() * max_speed, acceleration * 0.3 * delta)

        if knockback_vel.length_squared() > 1.0:
            position += knockback_vel * delta
            knockback_vel *= exp(-4.0 * delta)


        if _target_valid():
            var target_angle = (target.global_position - global_position).angle()
            rotation = lerp_angle(rotation, target_angle, 5.0 * delta)
        elif velocity.length() > 8.0:
            rotation = lerp_angle(rotation, velocity.angle(), 4.0 * delta)

    if damage_flash > 0:
        damage_flash -= delta * 4.0

    if max_shields > 0:
        _shield_hit_timer += delta
        if _shield_hit_timer >= shield_regen_delay and shields < max_shields:
            shields = minf(shields + shield_regen * delta, max_shields)


    running_light_phase += delta * 3.0
    engine_flicker += delta * 12.0
    if health < max_health * 0.4:
        spark_timer += delta
    var _cam = get_viewport().get_camera_2d()
    if _cam and global_position.distance_squared_to(_cam.global_position) < 4000000.0:
        queue_redraw()



func _ai_orbit(delta: float, dir: Vector2, dist: float):
    # Fighter — aggressive orbit, periodic hard lunges that pass beside player
    if health < max_health * 0.2:
        velocity -= dir * acceleration * 1.5 * delta
        return
    if _lock_timer > 0:
        velocity += _locked_dir * acceleration * 1.5 * delta
        return
    strafe_timer += delta
    if strafe_timer > 2.5:
        strafe_timer = 0.0
        # Lunge offset — aim to pass well beside, not through
        var lunge_perp = Vector2(-dir.y, dir.x) * orbit_dir
        _locked_dir = (dir + lunge_perp * 0.8).normalized()
        _lock_timer = 2.0
        velocity = _locked_dir * max_speed * 1.2
    elif dist > orbit_distance * 1.5:
        velocity += dir * acceleration * 2.0 * delta
    elif dist < orbit_distance:
        # Inside orbit range — pure tangent, push outward if too close
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 1.5 * delta
        if dist < orbit_distance * 0.6:
            velocity -= dir * acceleration * 1.0 * delta
    else:
        # In approach band — mostly tangent with slight inward drift
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 1.4 * delta
        velocity += dir * acceleration * 0.3 * delta

func _ai_strafe(delta: float, dir: Vector2, dist: float):
    # Scout — high-speed flyby passes, never settles into orbit
    if _lock_timer > 0:
        # Committed to flyby — keep going in locked direction
        velocity += _locked_dir * acceleration * 2.0 * delta
        return
    strafe_timer += delta
    if strafe_timer > 1.5:
        strafe_timer = 0.0
        strafe_dir *= -1.0
        # Dart toward player — offset so we pass well beside, not through
        var flyby_perp = Vector2(-dir.y, dir.x) * strafe_dir
        _locked_dir = (dir + flyby_perp * 0.8).normalized()
        _lock_timer = 2.5
        velocity = _locked_dir * max_speed * 1.3
    elif dist > orbit_distance * 2.0:
        velocity += dir * acceleration * 2.5 * delta
    else:
        # Strafe with slight approach — mostly sideways
        var tangent = Vector2(-dir.y, dir.x) * strafe_dir
        velocity += (tangent * 0.8 + dir * 0.3).normalized() * acceleration * 2.0 * delta

func _ai_approach(delta: float, dir: Vector2, dist: float):
    # Bomber — full-speed strafing runs, charges THROUGH and past, loops back
    if _lock_timer > 0:
        # COMMITTED to charge direction — don't recalculate, just push
        velocity += _locked_dir * acceleration * 2.5 * delta
        return
    dodge_timer += delta
    if dodge_timer > 3.0 or dist > orbit_distance * 5.0:
        dodge_timer = 0.0
        # New attack run — offset to strafe past, not ram through
        var run_perp = Vector2(-dir.y, dir.x) * orbit_dir
        _locked_dir = (dir + run_perp * 0.35).normalized()
        _lock_timer = 5.0
        velocity = _locked_dir * max_speed * 1.5
    else:
        # Closing in — push toward target
        velocity += dir * acceleration * 2.0 * delta
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 0.15 * delta

func _ai_aggressive(delta: float, dir: Vector2, dist: float):
    # Interceptor — boom-and-zoom jousting: wide strafing passes from far out
    # Obstacle avoidance for non-player objects (stations, POIs)
    _aggressive_avoid_obstacles(delta)

    if _lock_timer > 0:
        # Committed to attack run — full burn in locked direction
        velocity += _locked_dir * acceleration * 2.5 * delta
        # Fly far past (>1200px away and moving away) before looping back
        if dist > 1200.0 and velocity.dot(dir) < 0:
            _lock_timer = 0.0
            # Immediately kick velocity toward target so we don't drift forever
            velocity = dir * max_speed * 0.6
        return

    # Always be actively pursuing attack runs — accelerate toward player
    velocity += dir * acceleration * 3.0 * delta

    if dist > orbit_distance * 5.0:
        # Far enough — once fast and closing, commit to a wide strafing run
        if velocity.length() > max_speed * 0.5 and velocity.dot(dir) > 0:
            var pass_perp = Vector2(-dir.y, dir.x) * orbit_dir
            _locked_dir = (dir * 0.55 + pass_perp * 0.85).normalized()
            _lock_timer = 5.0
            orbit_dir *= -1.0
    elif dist < orbit_distance * 3.0:
        # Got too close — immediately commit to flying past wide
        var pass_perp = Vector2(-dir.y, dir.x) * orbit_dir
        _locked_dir = (dir * 0.4 + pass_perp * 0.9).normalized()
        if velocity.length() < max_speed * 0.6:
            velocity = _locked_dir * max_speed * 1.4
        _lock_timer = 5.0
        orbit_dir *= -1.0

func _aggressive_avoid_obstacles(_delta: float):
    # Steer away from stations and POIs so we don't crash into them
    var avoid_radius := 400.0
    for node in get_tree().get_nodes_in_group("station_entities"):
        if not is_instance_valid(node):
            continue
        var to_obs = global_position - node.global_position
        var obs_dist = to_obs.length()
        if obs_dist < avoid_radius and obs_dist > 1.0:
            var push = to_obs.normalized() * max_speed * (1.0 - obs_dist / avoid_radius)
            velocity += push
    for node in get_tree().get_nodes_in_group("pois"):
        if not is_instance_valid(node):
            continue
        var to_obs = global_position - node.global_position
        var obs_dist = to_obs.length()
        if obs_dist < avoid_radius and obs_dist > 1.0:
            var push = to_obs.normalized() * max_speed * (1.0 - obs_dist / avoid_radius)
            velocity += push

func _ai_tank(delta: float, dir: Vector2, dist: float):
    # Gunship — unstoppable forward push, but keeps a minimum standoff distance
    if dist > orbit_distance * 0.5:
        velocity += dir * acceleration * 1.8 * delta
    else:
        # Too close — hold position, lateral drift only
        var tangent_hold = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent_hold * acceleration * 1.0 * delta
    # Very slight lateral drift so multiple gunships don't stack perfectly
    strafe_timer += delta
    if strafe_timer > 4.0:
        strafe_timer = 0.0
        orbit_dir *= -1.0
    var tangent = Vector2(-dir.y, dir.x) * orbit_dir
    velocity += tangent * acceleration * 0.1 * delta

func _ai_elite(delta: float, dir: Vector2, dist: float):
    # Elite — teleport-like dashes, unpredictable, fast direction changes
    if _lock_timer > 0:
        # Committed to dash — push in locked direction
        velocity += _locked_dir * acceleration * 2.0 * delta
        # Still allow reactive dodge even while dashing
        if damage_flash > 0.3:
            _locked_dir = Vector2(-dir.y, dir.x) * orbit_dir
            velocity = _locked_dir * max_speed * 1.5
            _lock_timer = 1.0
        return
    dodge_timer += delta
    if dodge_timer > 1.2:
        dodge_timer = 0.0
        orbit_dir *= -1.0
        var roll = randf()
        if roll < 0.4:
            _locked_dir = dir
            velocity = dir * max_speed * 1.6
        elif roll < 0.7:
            _locked_dir = Vector2(-dir.y, dir.x) * orbit_dir
            velocity = _locked_dir * max_speed * 1.5
        else:
            _locked_dir = -dir
            velocity = _locked_dir * max_speed * 1.3
        _lock_timer = 1.5
    if dist > orbit_distance * 2.0:
        velocity += dir * acceleration * 3.0 * delta
    elif dist < orbit_distance * 0.5:
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 2.5 * delta
    else:
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 1.5 * delta
        velocity += dir * acceleration * 0.8 * delta
    if damage_flash > 0.3:
        _locked_dir = Vector2(-dir.y, dir.x) * orbit_dir
        velocity = _locked_dir * max_speed * 1.5
        _lock_timer = 1.0

func _ai_kite(delta: float, dir: Vector2, dist: float):
    # Missile frigate — fights hard to maintain distance, flees if approached
    if _lock_timer > 0:
        velocity += _locked_dir * acceleration * 2.0 * delta
        return
    if dist < orbit_distance * 0.6:
        # Panic — full burn away from player, lock retreat for 3 seconds
        _locked_dir = -dir
        _lock_timer = 3.0
        velocity = -dir * max_speed * 1.5
    elif dist < orbit_distance:
        # Too close, retreat hard
        velocity -= dir * acceleration * 3.0 * delta
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 0.5 * delta
    elif dist > orbit_distance * 2.5:
        # Too far, close in a bit
        velocity += dir * acceleration * 1.5 * delta
    else:
        # Sweet spot — strafe and fire
        var tangent = Vector2(-dir.y, dir.x) * orbit_dir
        velocity += tangent * acceleration * 1.5 * delta
    strafe_timer += delta
    if strafe_timer > 2.0:
        strafe_timer = 0.0
        orbit_dir *= -1.0

func _handle_shooting(dist: float, _delta: float):
    if dist > orbit_distance * 6.0:
        return
    if not can_fire:
        return

    match behavior:
        "aggressive":
            # Interceptor — fire during the entire approach/pass, long range
            if dist < orbit_distance * 5.0:
                _fire()
                can_fire = false
                get_tree().create_timer(fire_rate * 0.5, true, false, false).timeout.connect(func(): can_fire = true)
        "approach":
            if dist < orbit_distance * 3.0:
                _fire()
                can_fire = false
                get_tree().create_timer(fire_rate * 0.7, true, false, false).timeout.connect(func(): can_fire = true)
        "elite":
            if dist < orbit_distance * 3.0:
                _fire()
                burst_count += 1
                can_fire = false
                if burst_count >= 4:
                    burst_count = 0
                    get_tree().create_timer(fire_rate * 2.0, true, false, false).timeout.connect(func(): can_fire = true)
                else:
                    get_tree().create_timer(fire_rate * 0.2, true, false, false).timeout.connect(func(): can_fire = true)
        "kite":
            if dist < orbit_distance * 3.5:
                _fire()
                can_fire = false
                get_tree().create_timer(fire_rate * 0.8, true, false, false).timeout.connect(func(): can_fire = true)
        _:
            if dist < orbit_distance * 3.0 and can_fire:
                _fire()
                can_fire = false
                get_tree().create_timer(fire_rate * 0.8, true, false, false).timeout.connect(func(): can_fire = true)

func _find_target():
    var players = get_tree().get_nodes_in_group("player")
    if not players.is_empty():
        target = players[0]


func _target_valid() -> bool:
    return target != null and is_instance_valid(target)


func _ensure_behavior_tree() -> void:
    if _ship_bt != null and is_instance_valid(_ship_bt):
        _ship_bt.queue_free()
    _ship_bt = EnemyShipBTBuilder.build_tree()
    add_child(_ship_bt)

func _fire():
    match weapon_type:
        "rapid":
            _fire_rapid()
        "heavy":
            _fire_heavy()
        "twin":
            _fire_twin()
        "spread":
            _fire_spread()
        "plasma":
            _fire_plasma()
        "burst":
            _fire_burst()
        "missile":
            _fire_missile()
        _:
            _fire_laser()

func _fire_laser():

    var proj = _make_proj(Vector2.from_angle(rotation) * (ship_size + 6), rotation)
    proj.proj_color = Color(1.0, 0.3, 0.3)
    proj.proj_size = 3.0
    proj.sprite_sheet = _spr_pulse_mk1
    proj.sprite_scale = 0.88
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("laser_fire", 0.25, 0.15)

func _fire_rapid():

    var proj = _make_proj(Vector2.from_angle(rotation) * (ship_size + 6), rotation)
    proj.proj_color = Color(1.0, 0.7, 0.2)
    proj.proj_size = 2.0
    proj.speed = proj_speed * 1.1
    proj.damage = damage
    proj.sprite_sheet = _spr_autocannon
    proj.sprite_scale = 0.6
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("laser_fire", 0.15, 0.25)

func _fire_heavy():

    var proj = _make_proj(Vector2.from_angle(rotation) * (ship_size + 8), rotation)
    proj.proj_type = "mac"
    proj.proj_color = Color(1.0, 0.15, 0.3)
    proj.proj_size = 5.5
    proj.speed = proj_speed
    proj.damage = damage
    proj.lifetime = 3.0
    proj.mac_knockback = 800.0
    proj.splash_radius = 60.0
    proj.sprite_sheet = _spr_mac
    proj.sprite_scale = 1.12
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("railgun_fire", 0.4, 0.08)

func _fire_twin():

    var fwd = Vector2.from_angle(rotation)
    var perp = Vector2( - fwd.y, fwd.x)
    var offset = ship_size * 0.35
    for side in [-1.0, 1.0]:
        var spawn_pos = fwd * (ship_size + 6) + perp * offset * side
        var proj = _make_proj(spawn_pos, rotation)
        proj.proj_color = Color(0.3, 0.9, 1.0)
        proj.proj_size = 2.5
        proj.sprite_sheet = _spr_pulse_mk2
        proj.sprite_scale = 0.88
        get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("laser_fire", 0.2, 0.2)

func _fire_spread():

    var base_angle = rotation
    for offset_deg in [-8.0, 0.0, 8.0]:
        var angle = base_angle + deg_to_rad(offset_deg)
        var proj = _make_proj(Vector2.from_angle(angle) * (ship_size + 6), angle)
        proj.proj_color = Color(0.7, 0.3, 1.0)
        proj.proj_size = 3.0
        proj.damage = damage * 0.6
        proj.sprite_sheet = _spr_autocannon
        proj.sprite_scale = 0.6
        get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("cannon_fire", 0.3, 0.1)

func _fire_plasma():

    var proj = _make_proj(Vector2.from_angle(rotation) * (ship_size + 6), rotation)
    proj.proj_color = Color(0.2, 1.0, 0.4)
    proj.proj_size = 4.5
    proj.speed = proj_speed
    proj.damage = damage
    proj.sprite_sheet = _spr_railgun
    proj.sprite_scale = 1.0
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("plasma_fire", 0.3, 0.15)

func _fire_burst():

    var base_angle = rotation
    for i in 3:
        var spread = deg_to_rad(randf_range(-3.0, 3.0))
        var angle = base_angle + spread
        var proj = _make_proj(Vector2.from_angle(angle) * (ship_size + 6), angle)
        proj.proj_color = Color(0.3, 0.85, 1.0)
        proj.proj_size = 2.5
        proj.speed = proj_speed * 1.15
        proj.damage = damage * 0.7
        proj.sprite_sheet = _spr_pulse_mk2
        proj.sprite_scale = 0.75
        get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("laser_fire", 0.3, 0.2)

func _fire_missile():

    var proj = _make_proj(Vector2.from_angle(rotation) * (ship_size + 8), rotation)
    proj.proj_type = "missile"
    proj.proj_color = Color(1.0, 0.4, 0.15)
    proj.proj_size = 5.0
    proj.speed = proj_speed * 0.6
    proj.damage = damage * 1.5
    proj.lifetime = 4.0
    proj.homing_target = target
    proj.homing_strength = 2.5
    proj.splash_radius = 50.0
    proj.sprite_sheet = _spr_missile
    proj.sprite_scale = 1.0
    get_tree().current_scene.add_child(proj)
    AudioManager.play_sfx("heavy_shot", 0.4, 0.08)

func set_cloned_ai(recording: CombatRecording):
    var ai = ClonedAI.new()
    ai.setup(recording, max_speed)
    ai_controller = ai

func _make_proj(offset: Vector2, angle: float) -> Area2D:
    var proj = projectile_scene.instantiate()
    proj.global_position = global_position + offset
    proj.rotation = angle
    proj.source = "enemy"
    proj.speed = proj_speed
    proj.damage = damage
    proj.base_velocity = velocity
    return proj

func take_damage(amount: float, shield_pierce: float = 0.0, _hit_world_pos: Vector2 = Vector2.ZERO):
    amount *= (1.0 - damage_reduction)
    _shield_hit_timer = 0.0
    if shields > 0 and shield_pierce < 1.0:
        var to_shields = amount * (1.0 - shield_pierce)
        var to_hull = amount * shield_pierce
        if to_shields <= shields:
            shields -= to_shields
            amount = to_hull
        else:
            to_hull += to_shields - shields
            shields = 0.0
            amount = to_hull
    health -= amount
    damage_flash = 1.0
    queue_redraw()

    var dmg_num = Node2D.new()
    dmg_num.set_script(damage_number_script)
    dmg_num.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-15, -5))

    var col = Color(1.0, 1.0, 1.0)
    if amount >= 40:
        col = Color(1.0, 0.3, 0.2)
        dmg_num.font_size = 16
    elif amount >= 20:
        col = Color(1.0, 0.7, 0.2)
        dmg_num.font_size = 14
    dmg_num.setup(amount, col)
    get_tree().current_scene.add_child(dmg_num)

    AudioManager.play_sfx("hull_hit", 0.3, 0.15)
    if health <= 0:
        #_spawn_escape_pods()  # disabled — clutters battlefield with coin-like objects
        died.emit(global_position, ship_size)
        queue_free()

func _spawn_escape_pods():

    if crew_count <= 0:
        return
    var pod_script = preload("res://Space/scripts/world/escape_pod.gd")
    @warning_ignore("integer_division")
    var pods_to_spawn = maxi(1, crew_count / 2)
    for i in pods_to_spawn:
        var pod = Area2D.new()
        pod.set_script(pod_script)
        pod.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
        var eject_angle = randf() * TAU
        pod.velocity = Vector2.from_angle(eject_angle) * randf_range(80, 180) + velocity * 0.5
        pod.pod_color = ship_color
        pod.crew_data = GameManager.generate_crew()
        pod.is_enemy = true
        get_tree().current_scene.add_child(pod)


func _d_poly(pts: PackedVector2Array, col: Color):
    if _bake_ci: _bake_ci.draw_colored_polygon(pts, col)
    else: draw_colored_polygon(pts, col)

func _d_circle(pos: Vector2, r: float, col: Color):
    if _bake_ci: _bake_ci.draw_circle(pos, r, col)
    else: draw_circle(pos, r, col)

func _d_line(from: Vector2, to: Vector2, col: Color, width: float = -1.0):
    if _bake_ci: _bake_ci.draw_line(from, to, col, width)
    else: draw_line(from, to, col, width)

func _d_polyline(pts: PackedVector2Array, col: Color, width: float = -1.0):
    if _bake_ci: _bake_ci.draw_polyline(pts, col, width)
    else: draw_polyline(pts, col, width)

func _d_arc(center: Vector2, r: float, start: float, end: float, pts: int, col: Color, width: float = -1.0):
    if _bake_ci: _bake_ci.draw_arc(center, r, start, end, pts, col, width)
    else: draw_arc(center, r, start, end, pts, col, width)

func _d_rect(rect: Rect2, col: Color, filled: bool = true, width: float = -1.0):
    if _bake_ci: _bake_ci.draw_rect(rect, col, filled, width)
    else: draw_rect(rect, col, filled, width)

func _draw_hull_to(ci: CanvasItem):
    _bake_ci = ci
    var s = ship_size
    var color = ship_color
    _d_circle(Vector2.ZERO, s * 1.2, Color(color, 0.04))
    _d_circle(Vector2.ZERO, s * 0.8, Color(color, 0.06))
    match shape_type:
        "chevron": _draw_chevron(s, color)
        "dart": _draw_dart(s, color)
        "heavy": _draw_heavy(s, color)
        "needle": _draw_needle(s, color)
        "bulky": _draw_bulky(s, color)
        "winged": _draw_winged(s, color)
        _: _draw_chevron(s, color)
    _d_circle(Vector2(s * 0.2, -s * 0.1), s * 0.5, Color(1, 1, 1, 0.04))
    _d_circle(Vector2(-s * 0.2, s * 0.1), s * 0.6, Color(0, 0, 0, 0.06))
    _d_arc(Vector2.ZERO, s * 0.55, 0, TAU, 16, Color(color, 0.12), 1.5)
    _bake_ci = null

func _bake_hull_texture():
    # Static hull short-circuit: if a PNG path is set, load it and skip the
    # SubViewport bake entirely. The PNG can come from any asset pack
    # ingested via tools/import_pack.gd into Space/art/ships/.
    if static_hull_path != "":
        var loaded = load(static_hull_path)
        if loaded is Texture2D:
            var img = (loaded as Texture2D).get_image()
            if img != null:
                _hull_texture = ImageTexture.create_from_image(img)
                var sz = _hull_texture.get_size()
                _hull_tex_half = Vector2(sz.x * 0.5, sz.y * 0.5)
                return
        push_warning("enemy_ship: failed to load static_hull_path " + static_hull_path)

    var s = ship_size
    var tex_px = int(s * 5.0) + 8
    var vp = SubViewport.new()
    vp.transparent_bg = true
    vp.size = Vector2i(tex_px, tex_px)
    vp.render_target_update_mode = SubViewport.UPDATE_ONCE
    var drawer = Node2D.new()
    drawer.position = Vector2(tex_px / 2.0, tex_px / 2.0)
    var ship_ref = self
    drawer.draw.connect(func(): ship_ref._draw_hull_to(drawer))
    vp.add_child(drawer)
    add_child(vp)
    drawer.queue_redraw()
    await RenderingServer.frame_post_draw
    if not is_instance_valid(vp):
        return
    var img = vp.get_texture().get_image()
    _hull_texture = ImageTexture.create_from_image(img)
    _hull_tex_half = Vector2(tex_px / 2.0, tex_px / 2.0)
    vp.queue_free()

func _draw():
    var color = ship_color
    if damage_flash > 0:
        color = color.lerp(Color.WHITE, clampf(damage_flash, 0, 1))
    var s = ship_size
    var hp_pct = health / max_health

    if _hull_texture:
        var flash = clampf(damage_flash, 0, 1)
        var tint = Color(1.0 + flash * 3.0, 1.0 + flash * 3.0, 1.0 + flash * 3.0, 1.0)
        draw_texture_rect(_hull_texture, Rect2(-_hull_tex_half, _hull_tex_half * 2), false, tint)
    else:
        # Fallback before bake completes
        draw_circle(Vector2.ZERO, s * 1.2, Color(color, 0.04))
        draw_circle(Vector2.ZERO, s * 0.8, Color(color, 0.06))
        match shape_type:
            "chevron": _draw_chevron(s, color)
            "dart": _draw_dart(s, color)
            "heavy": _draw_heavy(s, color)
            "needle": _draw_needle(s, color)
            "bulky": _draw_bulky(s, color)
            "winged": _draw_winged(s, color)
            _: _draw_chevron(s, color)
        draw_circle(Vector2(s * 0.2, -s * 0.1), s * 0.5, Color(1, 1, 1, 0.04))
        draw_circle(Vector2(-s * 0.2, s * 0.1), s * 0.6, Color(0, 0, 0, 0.06))
        draw_arc(Vector2.ZERO, s * 0.55, 0, TAU, 16, Color(color, 0.12), 1.5)

    # Dynamic effects (always per-frame)
    _draw_engines(s, color)
    if hp_pct < 0.6:
        _draw_damage_effects(s, color, hp_pct)
    _draw_running_lights(s, color)
    if hp_pct > 0.8 and damage_flash <= 0:
        var shimmer = sin(Time.get_ticks_msec() * 0.003) * 0.03 + 0.03
        draw_arc(Vector2.ZERO, s * 1.0, 0, TAU, 16, Color(0.3, 0.6, 1.0, shimmer), 1.0)

    # Shield bubble
    if shields > 0 and max_shields > 0:
        var sh_pct = shields / max_shields
        var sh_alpha = 0.08 + sh_pct * 0.12
        var sh_pulse = sin(running_light_phase * 1.5) * 0.02
        draw_arc(Vector2.ZERO, s * 1.3, 0, TAU, 24, Color(0.3, 0.6, 1.0, sh_alpha + sh_pulse), 1.5)
        draw_arc(Vector2.ZERO, s * 1.35, 0, TAU * sh_pct, 24, Color(0.4, 0.7, 1.0, sh_alpha * 0.7), 1.0)

    # Health bar
    var bar_w = s * 2.2
    var bar_h = 3.0
    var bar_y = -s - 10
    draw_rect(Rect2(-bar_w / 2 - 1, bar_y - 1, bar_w + 2, bar_h + 2), Color(0, 0, 0, 0.4))
    draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h), Color(0.08, 0.08, 0.1))
    var bar_color = Color(0.2, 1.0, 0.2) if hp_pct > 0.5 else Color(1.0, 0.8, 0.2) if hp_pct > 0.25 else Color(1.0, 0.2, 0.2)
    draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_pct, bar_h), bar_color)
    draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_pct, bar_h * 0.4), Color(bar_color, 0.5))
    draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h), Color(0.35, 0.35, 0.4), false, 0.8)

    # Shield bar (below health bar)
    if max_shields > 0:
        var sh_bar_y = bar_y + bar_h + 2
        draw_rect(Rect2(-bar_w / 2, sh_bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.1))
        var sh_fill = shields / max_shields
        draw_rect(Rect2(-bar_w / 2, sh_bar_y, bar_w * sh_fill, bar_h), Color(0.3, 0.6, 1.0))
        draw_rect(Rect2(-bar_w / 2, sh_bar_y, bar_w * sh_fill, bar_h * 0.4), Color(0.5, 0.8, 1.0, 0.5))
        draw_rect(Rect2(-bar_w / 2, sh_bar_y, bar_w, bar_h), Color(0.35, 0.35, 0.4), false, 0.8)

    if scanned:
        var font = ThemeDB.fallback_font
        draw_string(font, Vector2(-s, -s - 16), enemy_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ship_color, 0.7))

func _draw_engines(s: float, color: Color):
    if velocity.length() < 15:
        return
    var intensity = clampf(velocity.length() / max_speed, 0.3, 1.0)
    var flicker = sin(engine_flicker) * 0.15 + 0.85


    var eng_positions: Array[Vector2] = []
    var eng_widths: Array[float] = []
    match shape_type:
        "heavy", "bulky":
            eng_positions = [Vector2( - s * 0.65, - s * 0.35), Vector2( - s * 0.65, s * 0.35)]
            eng_widths = [s * 0.18, s * 0.18]
        "winged":
            eng_positions = [Vector2( - s * 0.45, - s * 0.5), Vector2( - s * 0.45, 0), Vector2( - s * 0.45, s * 0.5)]
            eng_widths = [s * 0.1, s * 0.14, s * 0.1]
        "dart", "needle":
            eng_positions = [Vector2( - s * 0.55, 0)]
            eng_widths = [s * 0.12]
        _:
            eng_positions = [Vector2( - s * 0.55, - s * 0.15), Vector2( - s * 0.55, s * 0.15)]
            eng_widths = [s * 0.1, s * 0.1]

    for i in eng_positions.size():
        var ep = eng_positions[i]
        var ew = eng_widths[i]
        var flame_len = s * 0.45 * intensity * flicker


        var outer = PackedVector2Array([
            ep + Vector2(0, - ew * 1.3), 
            Vector2(ep.x - flame_len * 1.1, ep.y), 
            ep + Vector2(0, ew * 1.3), 
        ])
        draw_colored_polygon(outer, Color(color.r * 0.5, 0.15, 0.05, 0.3 * intensity))


        var inner = PackedVector2Array([
            ep + Vector2(0, - ew), 
            Vector2(ep.x - flame_len, ep.y), 
            ep + Vector2(0, ew), 
        ])
        var flame_col = Color(1.0, 0.5 + intensity * 0.3, 0.1, 0.7 * intensity)
        draw_colored_polygon(inner, flame_col)


        var hot = PackedVector2Array([
            ep + Vector2(0, - ew * 0.5), 
            Vector2(ep.x - flame_len * 0.6, ep.y), 
            ep + Vector2(0, ew * 0.5), 
        ])
        draw_colored_polygon(hot, Color(1.0, 0.9, 0.5, 0.5 * intensity))


        draw_line(ep + Vector2(2, - ew * 1.1), ep + Vector2(2, ew * 1.1), Color(color, 0.4) * 0.7, 1.5)

func _draw_damage_effects(s: float, _color: Color, hp_pct: float):
    var severity = 1.0 - hp_pct


    if severity > 0.4:
        var smoke_count = int(severity * 4)
        for i in smoke_count:
            var hash_v = sin(float(i) * 7.3 + spark_timer * 0.5) * 43758.5453
            var r = hash_v - floorf(hash_v)
            var sx = (r - 0.5) * s * 1.4
            var sy = (sin(float(i) * 3.1 + spark_timer) * 0.5) * s * 0.8
            var smoke_r = 3.0 + severity * 4.0
            draw_circle(Vector2(sx, sy), smoke_r, Color(0.3, 0.3, 0.35, 0.15 * severity))

            draw_circle(Vector2(sx - 1, sy - 1), smoke_r * 0.5, Color(0.15, 0.15, 0.18, 0.2 * severity))


    if severity > 0.2 and fmod(spark_timer, 0.4) < 0.15:
        var spark_count = int(severity * 6)
        for i in spark_count:
            var hash_v = sin(float(i) * 13.7 + spark_timer * 8.0) * 43758.5453
            var r = hash_v - floorf(hash_v)
            var sp = Vector2((r - 0.5) * s * 1.6, sin(r * TAU + spark_timer * 5.0) * s * 0.6)
            draw_circle(sp, 1.0 + r, Color(1.0, 0.7, 0.2, 0.7))


    if severity > 0.7:
        var fire_x = sin(spark_timer * 2.0) * s * 0.3
        var fire_y = cos(spark_timer * 1.7) * s * 0.2
        for j in 3:
            var fr = 3.0 + sin(spark_timer * 4.0 + float(j)) * 2.0
            draw_circle(Vector2(fire_x + float(j) * 2, fire_y - float(j) * 3), fr, 
                Color(1.0, 0.4, 0.1, 0.4 - float(j) * 0.1))

func _draw_running_lights(s: float, _color: Color):
    var blink = sin(running_light_phase) * 0.5 + 0.5
    var blink2 = sin(running_light_phase * 0.7 + 1.5) * 0.5 + 0.5

    match shape_type:
        "chevron":
            draw_circle(Vector2(s * 0.1, - s * 0.42), 1.5, Color(1.0, 0.3, 0.3, blink * 0.8))
            draw_circle(Vector2(s * 0.1, s * 0.42), 1.5, Color(0.3, 1.0, 0.3, blink * 0.8))
        "dart":
            draw_circle(Vector2( - s * 0.45, - s * 0.45), 1.2, Color(1.0, 0.2, 0.2, blink * 0.7))
            draw_circle(Vector2( - s * 0.45, s * 0.45), 1.2, Color(0.2, 1.0, 0.2, blink * 0.7))
        "heavy":
            draw_circle(Vector2( - s * 0.45, - s * 0.55), 2.0, Color(1.0, 0.8, 0.2, blink * 0.6))
            draw_circle(Vector2( - s * 0.45, s * 0.55), 2.0, Color(1.0, 0.8, 0.2, blink * 0.6))
            draw_circle(Vector2(s * 0.6, 0), 1.5, Color(1.0, 1.0, 1.0, blink2 * 0.5))
        "needle":
            draw_circle(Vector2(s * 0.9, 0), 1.0, Color(1.0, 0.3, 0.3, blink * 0.9))
        "bulky":
            draw_circle(Vector2( - s * 0.6, - s * 0.5), 2.0, Color(1.0, 0.6, 0.1, blink * 0.7))
            draw_circle(Vector2( - s * 0.6, s * 0.5), 2.0, Color(1.0, 0.6, 0.1, blink * 0.7))
            draw_circle(Vector2(s * 0.5, 0), 1.5, Color(1.0, 1.0, 1.0, blink2 * 0.4))
        "winged":
            draw_circle(Vector2( - s * 0.08, - s * 0.65), 1.5, Color(0.3, 0.5, 1.0, blink * 0.8))
            draw_circle(Vector2( - s * 0.08, s * 0.65), 1.5, Color(0.3, 0.5, 1.0, blink * 0.8))
            draw_circle(Vector2(s * 0.8, 0), 1.2, Color(1.0, 0.85, 0.3, blink2 * 0.6))

func _draw_chevron(s: float, color: Color):
    var dark = color * 0.55
    var mid = color * 0.75
    var light = color * 1.15


    var body = PackedVector2Array([
        Vector2(s, 0), 
        Vector2(s * 0.15, - s * 0.2), 
        Vector2( - s * 0.1, - s * 0.25), 
        Vector2( - s * 0.35, - s * 0.18), 
        Vector2( - s * 0.5, 0), 
        Vector2( - s * 0.35, s * 0.18), 
        Vector2( - s * 0.1, s * 0.25), 
        Vector2(s * 0.15, s * 0.2), 
    ])
    _d_poly(body, mid)

    var body_top = PackedVector2Array([
        Vector2(s, 0), 
        Vector2(s * 0.15, - s * 0.2), 
        Vector2( - s * 0.1, - s * 0.25), 
        Vector2( - s * 0.35, - s * 0.18), 
        Vector2( - s * 0.5, 0), 
        Vector2(s, 0), 
    ])
    _d_poly(body_top, Color(1, 1, 1, 0.06))

    var body_bot = PackedVector2Array([
        Vector2(s, 0), 
        Vector2( - s * 0.5, 0), 
        Vector2( - s * 0.35, s * 0.18), 
        Vector2( - s * 0.1, s * 0.25), 
        Vector2(s * 0.15, s * 0.2), 
    ])
    _d_poly(body_bot, Color(0, 0, 0, 0.08))

    _d_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[5], body[6], body[7], body[0]]), 
        light, 0.8)


    var wing_u = PackedVector2Array([
        Vector2(s * 0.15, - s * 0.2), 
        Vector2(s * 0.05, - s * 0.5), 
        Vector2( - s * 0.6, - s * 0.4), 
        Vector2( - s * 0.1, - s * 0.25), 
    ])
    _d_poly(wing_u, color)

    _d_poly(PackedVector2Array([
        Vector2(s * 0.15, - s * 0.2), Vector2(s * 0.05, - s * 0.5), 
        Vector2( - s * 0.3, - s * 0.45), Vector2( - s * 0.1, - s * 0.25), 
    ]), Color(1, 1, 1, 0.05))


    var wing_l = PackedVector2Array([
        Vector2(s * 0.15, s * 0.2), 
        Vector2(s * 0.05, s * 0.5), 
        Vector2( - s * 0.6, s * 0.4), 
        Vector2( - s * 0.1, s * 0.25), 
    ])
    _d_poly(wing_l, color * 0.9)

    _d_poly(PackedVector2Array([
        Vector2(s * 0.15, s * 0.2), Vector2(s * 0.05, s * 0.5), 
        Vector2( - s * 0.3, s * 0.45), Vector2( - s * 0.1, s * 0.25), 
    ]), Color(0, 0, 0, 0.06))


    var cockpit = PackedVector2Array([
        Vector2(s * 0.85, 0), 
        Vector2(s * 0.3, - s * 0.1), 
        Vector2(s * 0.2, 0), 
        Vector2(s * 0.3, s * 0.1), 
    ])
    _d_poly(cockpit, Color(0.2, 0.5, 0.7, 0.8))

    _d_poly(PackedVector2Array([
        Vector2(s * 0.8, - s * 0.01), 
        Vector2(s * 0.4, - s * 0.08), 
        Vector2(s * 0.35, - s * 0.03), 
        Vector2(s * 0.65, - s * 0.01), 
    ]), Color(0.6, 0.85, 1.0, 0.3))

    _d_polyline(PackedVector2Array([cockpit[0], cockpit[1], cockpit[2], cockpit[3], cockpit[0]]), 
        Color(0.5, 0.8, 1.0, 0.6), 1.0)


    _d_line(Vector2(s * 0.1, - s * 0.23), Vector2( - s * 0.35, - s * 0.18), dark, 0.7)
    _d_line(Vector2(s * 0.1, s * 0.23), Vector2( - s * 0.35, s * 0.18), dark, 0.7)
    _d_line(Vector2(s * 0.4, - s * 0.08), Vector2( - s * 0.2, - s * 0.08), dark, 0.5)
    _d_line(Vector2(s * 0.4, s * 0.08), Vector2( - s * 0.2, s * 0.08), dark, 0.5)

    _d_line(Vector2(s * 0.7, 0), Vector2( - s * 0.4, 0), dark, 0.6)

    _d_line(Vector2(s * 0.0, - s * 0.15), Vector2(s * 0.0, s * 0.15), dark, 0.4)
    _d_line(Vector2( - s * 0.25, - s * 0.12), Vector2( - s * 0.25, s * 0.12), dark, 0.4)


    _d_line(Vector2(s * 0.15, - s * 0.2), Vector2(s * 0.05, - s * 0.5), light, 1.0)
    _d_line(Vector2(s * 0.15, s * 0.2), Vector2(s * 0.05, s * 0.5), light, 1.0)

    _d_line(Vector2(s * 0.05, - s * 0.5), Vector2( - s * 0.6, - s * 0.4), Color(light, 0.5), 0.6)
    _d_line(Vector2(s * 0.05, s * 0.5), Vector2( - s * 0.6, s * 0.4), Color(light, 0.5), 0.6)


    for wy in [ - s * 0.38, s * 0.38]:
        var wp = Vector2( - s * 0.2, wy)
        _d_circle(wp, 3.0, dark)
        _d_circle(wp, 2.0, Color(1.0, 0.5, 0.3, 0.5))
        _d_circle(wp, 1.0, Color(1.0, 0.8, 0.5, 0.8))


    _d_circle(Vector2(s * 0.9, 0), 1.5, Color(light, 0.4))

func _draw_dart(s: float, color: Color):


    var body = PackedVector2Array([
        Vector2(s * 1.1, 0), 
        Vector2(s * 0.4, - s * 0.12), 
        Vector2(s * 0.1, - s * 0.18), 
        Vector2( - s * 0.3, - s * 0.15), 
        Vector2( - s * 0.5, 0), 
        Vector2( - s * 0.3, s * 0.15), 
        Vector2(s * 0.1, s * 0.18), 
        Vector2(s * 0.4, s * 0.12), 
    ])
    _d_poly(body, color * 0.9)


    var fin_u = PackedVector2Array([
        Vector2(s * 0.1, - s * 0.18), 
        Vector2( - s * 0.15, - s * 0.55), 
        Vector2( - s * 0.5, - s * 0.5), 
        Vector2( - s * 0.3, - s * 0.15), 
    ])
    _d_poly(fin_u, color)

    var fin_l = PackedVector2Array([
        Vector2(s * 0.1, s * 0.18), 
        Vector2( - s * 0.15, s * 0.55), 
        Vector2( - s * 0.5, s * 0.5), 
        Vector2( - s * 0.3, s * 0.15), 
    ])
    _d_poly(fin_l, color)


    var cockpit = PackedVector2Array([
        Vector2(s * 1.05, 0), 
        Vector2(s * 0.55, - s * 0.06), 
        Vector2(s * 0.55, s * 0.06), 
    ])
    _d_poly(cockpit, Color(0.4, 0.65, 0.85, 0.65))
    _d_polyline(PackedVector2Array([Vector2(s * 1.05, 0), Vector2(s * 0.55, - s * 0.06), Vector2(s * 0.55, s * 0.06), Vector2(s * 1.05, 0)]), 
        Color(0.5, 0.8, 1.0, 0.4), 0.7)


    _d_line(Vector2(s * 0.8, - s * 0.04), Vector2(s * 0.1, - s * 0.04), color * 1.5, 0.7)
    _d_line(Vector2(s * 0.8, s * 0.04), Vector2(s * 0.1, s * 0.04), color * 1.5, 0.7)


    _d_line(Vector2(s * 0.4, - s * 0.12), Vector2( - s * 0.1, - s * 0.17), color * 0.5, 0.5)
    _d_line(Vector2(s * 0.4, s * 0.12), Vector2( - s * 0.1, s * 0.17), color * 0.5, 0.5)


    _d_line(Vector2(s * 0.1, - s * 0.18), Vector2( - s * 0.15, - s * 0.55), color * 1.4, 0.8)
    _d_line(Vector2(s * 0.1, s * 0.18), Vector2( - s * 0.15, s * 0.55), color * 1.4, 0.8)

func _draw_heavy(s: float, color: Color):


    var body = PackedVector2Array([
        Vector2(s * 0.7, 0), 
        Vector2(s * 0.5, - s * 0.3), 
        Vector2(s * 0.2, - s * 0.45), 
        Vector2( - s * 0.4, - s * 0.5), 
        Vector2( - s * 0.65, - s * 0.4), 
        Vector2( - s * 0.7, 0), 
        Vector2( - s * 0.65, s * 0.4), 
        Vector2( - s * 0.4, s * 0.5), 
        Vector2(s * 0.2, s * 0.45), 
        Vector2(s * 0.5, s * 0.3), 
    ])
    _d_poly(body, color * 0.8)


    var armor = PackedVector2Array([
        Vector2(s * 0.35, - s * 0.22), 
        Vector2( - s * 0.3, - s * 0.28), 
        Vector2( - s * 0.45, - s * 0.2), 
        Vector2( - s * 0.45, s * 0.2), 
        Vector2( - s * 0.3, s * 0.28), 
        Vector2(s * 0.35, s * 0.22), 
    ])
    _d_poly(armor, color * 0.55)
    _d_polyline(PackedVector2Array([
        Vector2(s * 0.35, - s * 0.22), Vector2( - s * 0.3, - s * 0.28), Vector2( - s * 0.45, - s * 0.2), 
        Vector2( - s * 0.45, s * 0.2), Vector2( - s * 0.3, s * 0.28), Vector2(s * 0.35, s * 0.22), Vector2(s * 0.35, - s * 0.22)
    ]), color * 0.4, 0.8)


    _d_rect(Rect2(s * 0.35, - s * 0.08, s * 0.25, s * 0.16), Color(0.25, 0.5, 0.7, 0.6))
    _d_rect(Rect2(s * 0.35, - s * 0.08, s * 0.25, s * 0.16), Color(0.4, 0.7, 0.9, 0.35), false, 0.7)


    _d_line(Vector2(s * 0.15, - s * 0.44), Vector2( - s * 0.35, - s * 0.48), color * 0.45, 1.2)
    _d_line(Vector2(s * 0.15, s * 0.44), Vector2( - s * 0.35, s * 0.48), color * 0.45, 1.2)
    _d_line(Vector2( - s * 0.1, - s * 0.35), Vector2( - s * 0.55, - s * 0.35), color * 0.4, 0.7)
    _d_line(Vector2( - s * 0.1, s * 0.35), Vector2( - s * 0.55, s * 0.35), color * 0.4, 0.7)


    _d_circle(Vector2(s * 0.1, - s * 0.38), 3.0, color * 0.5)
    _d_circle(Vector2(s * 0.1, - s * 0.38), 1.8, Color(1.0, 0.4, 0.2, 0.7))
    _d_line(Vector2(s * 0.1, - s * 0.38), Vector2(s * 0.3, - s * 0.42), color * 0.7, 1.5)

    _d_circle(Vector2(s * 0.1, s * 0.38), 3.0, color * 0.5)
    _d_circle(Vector2(s * 0.1, s * 0.38), 1.8, Color(1.0, 0.4, 0.2, 0.7))
    _d_line(Vector2(s * 0.1, s * 0.38), Vector2(s * 0.3, s * 0.42), color * 0.7, 1.5)


    for i in 4:
        var rx = lerpf( - s * 0.3, s * 0.3, float(i) / 3.0)
        _d_circle(Vector2(rx, - s * 0.28), 0.8, color * 0.35)
        _d_circle(Vector2(rx, s * 0.28), 0.8, color * 0.35)

func _draw_needle(s: float, color: Color):


    var body = PackedVector2Array([
        Vector2(s * 1.2, 0), 
        Vector2(s * 0.5, - s * 0.08), 
        Vector2(s * 0.2, - s * 0.15), 
        Vector2( - s * 0.1, - s * 0.2), 
        Vector2( - s * 0.5, - s * 0.15), 
        Vector2( - s * 0.6, 0), 
        Vector2( - s * 0.5, s * 0.15), 
        Vector2( - s * 0.1, s * 0.2), 
        Vector2(s * 0.2, s * 0.15), 
        Vector2(s * 0.5, s * 0.08), 
    ])
    _d_poly(body, color * 0.85)


    var wing_u = PackedVector2Array([
        Vector2( - s * 0.1, - s * 0.2), 
        Vector2( - s * 0.25, - s * 0.4), 
        Vector2( - s * 0.45, - s * 0.35), 
        Vector2( - s * 0.5, - s * 0.15), 
    ])
    _d_poly(wing_u, color)

    var wing_l = PackedVector2Array([
        Vector2( - s * 0.1, s * 0.2), 
        Vector2( - s * 0.25, s * 0.4), 
        Vector2( - s * 0.45, s * 0.35), 
        Vector2( - s * 0.5, s * 0.15), 
    ])
    _d_poly(wing_l, color)


    _d_line(Vector2(s * 1.2, 0), Vector2(s * 0.6, 0), Color(color, 0.8) * 1.5, 1.5)


    _d_line(Vector2(s * 0.5, - s * 0.08), Vector2(s * 0.8, - s * 0.06), color * 0.6, 1.5)
    _d_line(Vector2(s * 0.5, s * 0.08), Vector2(s * 0.8, s * 0.06), color * 0.6, 1.5)
    _d_circle(Vector2(s * 0.8, - s * 0.06), 1.5, Color(1.0, 0.6, 0.3, 0.8))
    _d_circle(Vector2(s * 0.8, s * 0.06), 1.5, Color(1.0, 0.6, 0.3, 0.8))


    _d_line(Vector2(s * 0.9, 0), Vector2( - s * 0.4, 0), color * 0.45, 0.5)


    _d_circle(Vector2( - s * 0.25, - s * 0.4), 1.5, color * 1.4)
    _d_circle(Vector2( - s * 0.25, s * 0.4), 1.5, color * 1.4)

func _draw_bulky(s: float, color: Color):


    var body = PackedVector2Array([
        Vector2(s * 0.55, - s * 0.15), 
        Vector2(s * 0.55, s * 0.15), 
        Vector2(s * 0.3, s * 0.35), 
        Vector2( - s * 0.15, s * 0.5), 
        Vector2( - s * 0.55, s * 0.55), 
        Vector2( - s * 0.7, s * 0.35), 
        Vector2( - s * 0.7, - s * 0.35), 
        Vector2( - s * 0.55, - s * 0.55), 
        Vector2( - s * 0.15, - s * 0.5), 
        Vector2(s * 0.3, - s * 0.35), 
    ])
    _d_poly(body, color * 0.75)


    var bridge = PackedVector2Array([
        Vector2(s * 0.55, - s * 0.15), 
        Vector2(s * 0.7, 0), 
        Vector2(s * 0.55, s * 0.15), 
    ])
    _d_poly(bridge, color * 0.9)

    _d_line(Vector2(s * 0.62, - s * 0.06), Vector2(s * 0.62, s * 0.06), Color(0.3, 0.6, 0.8, 0.6), 2.0)


    _d_line(Vector2(s * 0.25, - s * 0.38), Vector2( - s * 0.5, - s * 0.52), color * 0.4, 1.5)
    _d_line(Vector2(s * 0.25, s * 0.38), Vector2( - s * 0.5, s * 0.52), color * 0.4, 1.5)

    _d_line(Vector2(s * 0.0, - s * 0.48), Vector2(s * 0.0, - s * 0.3), color * 0.4, 1.0)
    _d_line(Vector2(s * 0.0, s * 0.48), Vector2(s * 0.0, s * 0.3), color * 0.4, 1.0)
    _d_line(Vector2( - s * 0.35, - s * 0.5), Vector2( - s * 0.35, s * 0.5), color * 0.35, 0.8)


    var gun = PackedVector2Array([
        Vector2(s * 0.3, - s * 0.08), 
        Vector2(s * 0.9, - s * 0.04), 
        Vector2(s * 0.9, s * 0.04), 
        Vector2(s * 0.3, s * 0.08), 
    ])
    _d_poly(gun, color * 1.2)
    _d_circle(Vector2(s * 0.9, 0), 2.5, Color(1.0, 0.5, 0.2, 0.8))


    for i in 5:
        var rx = lerpf( - s * 0.5, s * 0.2, float(i) / 4.0)
        _d_circle(Vector2(rx, - s * 0.5), 1.0, color * 0.35)
        _d_circle(Vector2(rx, s * 0.5), 1.0, color * 0.35)


    _d_line(Vector2( - s * 0.55, - s * 0.55), Vector2( - s * 0.55, - s * 0.7), color * 0.6, 0.8)
    _d_circle(Vector2( - s * 0.55, - s * 0.7), 1.0, Color(1.0, 0.3, 0.3, 0.5))

func _draw_winged(s: float, color: Color):


    var body = PackedVector2Array([
        Vector2(s * 1.0, 0), 
        Vector2(s * 0.5, - s * 0.1), 
        Vector2(s * 0.2, - s * 0.15), 
        Vector2( - s * 0.2, - s * 0.15), 
        Vector2( - s * 0.4, 0), 
        Vector2( - s * 0.2, s * 0.15), 
        Vector2(s * 0.2, s * 0.15), 
        Vector2(s * 0.5, s * 0.1), 
    ])
    _d_poly(body, color * 0.85)


    var wing_u = PackedVector2Array([
        Vector2(s * 0.2, - s * 0.15), 
        Vector2(s * 0.0, - s * 0.2), 
        Vector2( - s * 0.15, - s * 0.75), 
        Vector2( - s * 0.35, - s * 0.65), 
        Vector2( - s * 0.2, - s * 0.15), 
    ])
    _d_poly(wing_u, color)


    var wing_l = PackedVector2Array([
        Vector2(s * 0.2, s * 0.15), 
        Vector2(s * 0.0, s * 0.2), 
        Vector2( - s * 0.15, s * 0.75), 
        Vector2( - s * 0.35, s * 0.65), 
        Vector2( - s * 0.2, s * 0.15), 
    ])
    _d_poly(wing_l, color)


    var cockpit = PackedVector2Array([
        Vector2(s * 0.95, 0), 
        Vector2(s * 0.55, - s * 0.07), 
        Vector2(s * 0.4, 0), 
        Vector2(s * 0.55, s * 0.07), 
    ])
    _d_poly(cockpit, Color(0.35, 0.55, 0.8, 0.65))
    _d_polyline(PackedVector2Array([Vector2(s * 0.95, 0), Vector2(s * 0.55, - s * 0.07), Vector2(s * 0.4, 0), Vector2(s * 0.55, s * 0.07), Vector2(s * 0.95, 0)]), 
        Color(0.5, 0.75, 1.0, 0.4), 0.7)


    _d_line(Vector2(s * 0.7, 0), Vector2( - s * 0.15, 0), Color(1.0, 0.85, 0.3, 0.7), 1.5)


    _d_line(Vector2(s * 0.05, - s * 0.25), Vector2( - s * 0.2, - s * 0.6), color * 0.5, 0.6)
    _d_line(Vector2( - s * 0.05, - s * 0.35), Vector2( - s * 0.25, - s * 0.6), color * 0.5, 0.6)
    _d_line(Vector2(s * 0.05, s * 0.25), Vector2( - s * 0.2, s * 0.6), color * 0.5, 0.6)
    _d_line(Vector2( - s * 0.05, s * 0.35), Vector2( - s * 0.25, s * 0.6), color * 0.5, 0.6)


    _d_line(Vector2(s * 0.0, - s * 0.2), Vector2( - s * 0.15, - s * 0.75), color * 1.5, 1.0)
    _d_line(Vector2(s * 0.0, s * 0.2), Vector2( - s * 0.15, s * 0.75), color * 1.5, 1.0)


    _d_circle(Vector2( - s * 0.15, - s * 0.75), 3.0, Color(color, 0.3))
    _d_circle(Vector2( - s * 0.15, - s * 0.75), 1.5, color * 1.6)
    _d_circle(Vector2( - s * 0.15, s * 0.75), 3.0, Color(color, 0.3))
    _d_circle(Vector2( - s * 0.15, s * 0.75), 1.5, color * 1.6)


    _d_line(Vector2(s * 0.3, - s * 0.12), Vector2( - s * 0.15, - s * 0.14), color * 0.45, 0.5)
    _d_line(Vector2(s * 0.3, s * 0.12), Vector2( - s * 0.15, s * 0.14), color * 0.45, 0.5)


# ── Collision Damage ──────────────────────────────────────────────────

const COLLISION_MIN_DAMAGE_SPEED: float = 40.0
const COLLISION_RESTITUTION: float = 0.5

func _get_collision_mass() -> float:
    return ship_size / 12.0

func _get_collision_radius() -> float:
    return ship_size

func _process_enemy_collisions(_delta: float):
    if health <= 0:
        return
    for other in get_overlapping_areas():
        if not is_instance_valid(other):
            continue
        if other.is_in_group("player") or other.is_in_group("fleet_ships") or other.is_in_group("npc_ships") or other.is_in_group("station_entities"):
            _resolve_enemy_collision(other, _delta)

func _resolve_enemy_collision(other: Area2D, _delta: float):
    var sep = other.global_position - global_position
    var dist = sep.length()
    if dist < 0.1:
        sep = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
        dist = 0.1
    var dir = sep / dist

    var my_radius = ship_size
    var other_radius: float = other._get_collision_radius() if other.has_method("_get_collision_radius") else (other.ship_size if "ship_size" in other else 15.0)
    var min_dist = my_radius + other_radius
    var overlap = min_dist - dist
    if overlap <= 0:
        return

    var my_mass = _get_collision_mass()
    var other_mass: float = 1.0
    if other.has_method("_get_collision_mass"):
        other_mass = other._get_collision_mass()
    elif "ship_weight" in other:
        other_mass = other.ship_weight
    elif "ship_modules" in other and not other.ship_modules.is_empty():
        other_mass = float(other.ship_modules.size())
    var total_mass = my_mass + other_mass
    var my_ratio = other_mass / total_mass

    # Separate
    global_position -= dir * overlap * my_ratio

    # Velocity
    var other_vel: Vector2 = other.get("velocity") if "velocity" in other else Vector2.ZERO
    var closing_speed = (velocity - other_vel).dot(dir)

    if closing_speed > 0:
        velocity -= dir * closing_speed * my_ratio * (1.0 + COLLISION_RESTITUTION)

    # Damage
    if closing_speed > COLLISION_MIN_DAMAGE_SPEED:
        var raw_damage = closing_speed * 0.3 + closing_speed * closing_speed * 0.01
        var mass_factor = clampf(other_mass / maxf(my_mass, 0.1), 0.3, 2.5)
        raw_damage *= mass_factor
        if raw_damage >= 1.0:
            var hit_pos = global_position + dir * my_radius
            take_damage(raw_damage, 0.0, hit_pos)
            var dmg_num = Node2D.new()
            dmg_num.set_script(damage_number_script)
            dmg_num.global_position = hit_pos + Vector2(randf_range(-10, 10), randf_range(-10, 5))
            var col = Color(1.0, 0.6, 0.2)
            if raw_damage >= 30:
                col = Color(1.0, 0.3, 0.1)
                dmg_num.font_size = 16
            elif raw_damage >= 15:
                col = Color(1.0, 0.5, 0.15)
                dmg_num.font_size = 14
            dmg_num.setup(raw_damage, col)
            get_tree().current_scene.add_child(dmg_num)
            AudioManager.play_sfx("hull_hit", clampf(raw_damage / 30.0, 0.2, 0.9), 0.15)
    elif overlap > 3.0:
        var grind = overlap * 2.0 * _delta
        if grind >= 0.5:
            take_damage(grind, 0.0, global_position + dir * my_radius)
