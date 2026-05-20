class_name MvEnemy
extends CharacterBody2D

# Generic enemy body. Reads an entity id from the pack's entities.json,
# resolves its bound `behavior` id, builds a BeehaveTree from the
# behaviors.json authored in the behavior editor, and mounts the tree
# as a child so it ticks every physics frame.
#
# Leaves read the actor via BeehaveTree's default parent fallback — so
# walk_action / wall_ahead_condition / player_near_condition all see
# THIS node (a CharacterBody2D) without any per-leaf wiring.
#
# Process order inside _physics_process:
#   1. Zero velocity.x (so "no leaf ran" == idle; leaves must re-assert
#      motion each tick if they want to keep moving).
#   2. Tick the tree manually — leaves mutate velocity.
#   3. Apply gravity, clamp fall, move_and_slide.
#
# The tree is set to MANUAL process_thread so we own the tick order;
# otherwise BeehaveTree._physics_process would race ours and you'd get
# stale velocity one frame per tick.

const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")
const BehIO := preload("res://Space/scripts/shared/beh/beh_io.gd")
const BehLoader := preload("res://Space/scripts/runtime/beh/beh_loader.gd")
const MvPickupScene := preload("res://MV/scripts/pickup.gd")

const FALLBACK_GRAVITY: float = 0.109375 * 3600.0
const FALLBACK_MAX_FALL: float = 5.0 * 60.0
const PLACEHOLDER_SIZE: Vector2 = Vector2(14, 18)
const DEFAULT_FPS: float = 8.0
const DEFAULT_HOVER_BOB_AMPLITUDE: float = 6.0
const DEFAULT_HOVER_BOB_SPEED: float = 1.2
const VALID_MOVEMENT_MODES := {
    "ground": true,
    "hover": true,
    "fly": true,
}

var pack_id: String = ""
var entity_id: String = ""
var instance_id: String = ""

var _entity: Dictionary = {}
var _behavior: Dictionary = {}
var _tree: BeehaveTree = null
var _col_shape: CollisionShape2D = null
var _contact_area: Area2D = null
var _contact_shape: CollisionShape2D = null
var _placeholder_color: Color = Color(0.85, 0.4, 0.45, 1)

# Sprite state. When an entity authors a sprite_set, _mount_sprite picks
# the first PNG alphabetically and mounts it as a Sprite2D child with
# hframes driven by the pose's frames field (or autodetected). Animation
# ticks in _process so it keeps running even when physics is paused.
var _sprite: Sprite2D = null
var _pose: Dictionary = {}
var _frame_count: int = 1
var _frame_index: int = 0
var _frame_time: float = 0.0
var _last_facing_right: bool = true
var _sprite_set_rel: String = ""
var _available_pose_pngs: Array = []
var _pose_registry: Dictionary = {}
var _pose_stems: Dictionary = {}
var _current_pose_png: String = ""
var _script_move_active: bool = false
var _script_move_target: Vector2 = Vector2.ZERO
var _script_move_speed: float = 64.0
var _script_anim_active: bool = false
var _script_anim_speed_scale: float = 1.0
var _script_anim_loop: bool = true
var _script_anim_name: String = ""
var _ai_pose_state: String = ""
var _ai_pose_hold_until: float = 0.0
var _ai_pose_loop: bool = true
var _ai_pose_speed_scale: float = 1.0
var _ai_pose_restart_pending: bool = false
var _vertical_drive_active: bool = false
var _movement_mode: String = "ground"
var _hover_anchor_y: float = 0.0
var _hover_bob_phase: float = 0.0
var _hover_bob_amplitude: float = DEFAULT_HOVER_BOB_AMPLITUDE
var _hover_bob_speed: float = DEFAULT_HOVER_BOB_SPEED

# Combat state. hp is read from the entity def's "hp" field (default 10).
# attack_damage is read from "attack_damage" (default 1). take_damage()
# is the single entry point for anything hurting an enemy; _on_defeat
# handles death (drops, event fire, queue_free). Bosses override via
# MvBoss which has its own take_damage/boss_hp pipeline.
var hp: int = 10
var max_hp: int = 10
var attack_damage: int = 1
var contact_damage: int = 0
var contact_cooldown: float = 0.8
var move_speed: float = 40.0
var projectile_damage: int = 1
var projectile_speed: float = 180.0
var melee_range: float = 24.0
var projectile_range: float = 220.0
var melee_attack_trigger_frame: int = -1
var projectile_attack_trigger_frame: int = -1
var _hit_flash_timer: float = 0.0
var _dead: bool = false
var _contact_cooldown_left: float = 0.0
var _defeat_cleanup_at: float = -1.0
var _pending_attack: Dictionary = {}

# Authored-direction flag used by walk/turn_around leaves to persist
# facing across ticks. +1 = right, -1 = left. Walk leaves without an
# explicit "dir" param read this; turn_around negates it.
var beh_facing: int = 1

signal enemy_damaged(amount: int, remaining_hp: int)
signal enemy_defeated(entity_id: String)
signal scripted_move_finished
signal scripted_animation_finished(anim_name: String)


# Call before add_child(enemy). Stores config — the actual load happens
# in _ready once the pack loader is guaranteed to be initialized.
func configure(p_pack_id: String, p_entity_id: String) -> void:
    pack_id = p_pack_id
    entity_id = p_entity_id


func _ready() -> void:
    add_to_group("mv_enemy")
    if pack_id == "":
        pack_id = _current_pack_id()
    _entity = _load_entity()
    _ensure_collision_shape()
    _ensure_contact_area()
    _load_combat_stats()
    _mount_sprite()
    _behavior = _load_behavior()
    _mount_tree()
    _hover_anchor_y = global_position.y
    queue_redraw()


# Read hp / attack_damage out of the entity definition. Called after
# _load_entity so _entity is populated. Safe when keys are missing — the
# defaults on the fields take over.
func _load_combat_stats() -> void:
    max_hp = maxi(1, int(_entity.get("hp", max_hp)))
    hp = max_hp
    attack_damage = maxi(0, int(_entity.get("attack_damage", attack_damage)))
    if _entity.has("contact_damage"):
        contact_damage = maxi(0, int(_entity.get("contact_damage", contact_damage)))
    else:
        contact_damage = attack_damage
    contact_cooldown = maxf(0.0, float(_entity.get("contact_cooldown", contact_cooldown)))
    move_speed = maxf(0.0, float(_entity.get("move_speed", move_speed)))
    projectile_damage = maxi(0, int(_entity.get("projectile_damage", projectile_damage)))
    projectile_speed = maxf(0.0, float(_entity.get("projectile_speed", projectile_speed)))
    melee_range = maxf(0.0, float(_entity.get("melee_range", melee_range)))
    projectile_range = maxf(0.0, float(_entity.get("projectile_range", projectile_range)))
    melee_attack_trigger_frame = max(-1, int(_entity.get("melee_attack_trigger_frame", melee_attack_trigger_frame)))
    projectile_attack_trigger_frame = max(-1, int(_entity.get("projectile_attack_trigger_frame", projectile_attack_trigger_frame)))
    _movement_mode = str(_entity.get("movement_mode", "ground")).strip_edges().to_lower()
    if not VALID_MOVEMENT_MODES.has(_movement_mode):
        _movement_mode = "ground"
    _hover_bob_amplitude = maxf(0.0, float(_entity.get("hover_bob_amplitude", DEFAULT_HOVER_BOB_AMPLITUDE)))
    _hover_bob_speed = maxf(0.0, float(_entity.get("hover_bob_speed", DEFAULT_HOVER_BOB_SPEED)))
    _sync_contact_shape()


# Damage entry point. amount clamped to >= 0; no-op when already dead.
# from_pos (Vector2) is optional and currently informational only —
# subclasses (MvBoss) use it for knockback. Emits enemy_damaged + fires
# enemy_defeated when hp hits zero.
func take_damage(amount: int, _from_pos = null) -> void:
    if _dead or amount <= 0:
        return
    hp = maxi(0, hp - amount)
    _hit_flash_timer = 0.15
    if _sprite == null:
        queue_redraw()
    ai_request_pose("hurt", 0.14, false, 1.0)
    enemy_damaged.emit(amount, hp)
    if hp == 0:
        _on_defeat()


func _on_defeat() -> void:
    if _dead:
        return
    _dead = true
    velocity = Vector2.ZERO
    if _contact_area != null:
        _contact_area.monitoring = false
    if _col_shape != null:
        _col_shape.set_deferred("disabled", true)
    if _contact_shape != null:
        _contact_shape.set_deferred("disabled", true)
    _play_death_pose()
    _spawn_item_drops()
    enemy_defeated.emit(entity_id)
    MvTriggerEngine.fire_event("enemy_defeated", { "entity_id": entity_id })


func _spawn_item_drops() -> void:
    var drops: Array = []
    var drops_v: Variant = _entity.get("item_drops", [])
    if typeof(drops_v) == TYPE_ARRAY:
        drops = drops_v
    elif not str(_entity.get("drop_item_id", "")).strip_edges().is_empty():
        drops = [{
            "id": str(_entity.get("drop_item_id", "")).strip_edges(),
            "count": int(_entity.get("drop_count", 1)),
            "chance": float(_entity.get("drop_chance", 1.0)),
        }]
    if drops.is_empty():
        return
    var parent := get_parent()
    if parent == null:
        return
    var spawned := 0
    for drop_v in drops:
        if typeof(drop_v) != TYPE_DICTIONARY:
            continue
        var drop: Dictionary = drop_v
        var item_id := str(drop.get("id", drop.get("item_id", ""))).strip_edges()
        if item_id.is_empty():
            continue
        var chance := clampf(float(drop.get("chance", 1.0)), 0.0, 1.0)
        if randf() > chance:
            continue
        var pickup := MvPickupScene.new()
        pickup.configure(pack_id, str(drop.get("pickup_entity", "pickup")), [], {
            "item_id": item_id,
            "count": maxi(1, int(drop.get("count", 1))),
        })
        pickup.global_position = global_position + Vector2(float(spawned * 10), -8.0)
        parent.add_child(pickup)
        spawned += 1


func _process(delta: float) -> void:
    # Hit flash: modulate the sprite red briefly after taking damage, or
    # draw a red overlay on the placeholder if the enemy has no sprite.
    if _hit_flash_timer > 0.0:
        _hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
        if _sprite != null:
            var t := _hit_flash_timer / 0.15
            _sprite.modulate = Color(1.0, 1.0 - t, 1.0 - t, 1.0)
        elif _hit_flash_timer == 0.0:
            queue_redraw()
        else:
            queue_redraw()
    elif _sprite != null and _sprite.modulate != Color.WHITE:
        _sprite.modulate = Color.WHITE

    if _dead and _defeat_cleanup_at >= 0.0 and _now_seconds() >= _defeat_cleanup_at:
        queue_free()
        return

    if _sprite == null:
        return
    # Prefer the authored/AI facing flag over live velocity so hovering
    # and flying enemies do not flicker when their horizontal speed
    # oscillates around zero while aiming.
    if beh_facing > 0:
        _last_facing_right = true
    elif beh_facing < 0:
        _last_facing_right = false
    elif velocity.x > 0.01:
        _last_facing_right = true
    elif velocity.x < -0.01:
        _last_facing_right = false
    _sprite.flip_h = not _last_facing_right

    if _frame_count <= 1:
        _maybe_execute_pending_attack()
        return
    var fps: float = DEFAULT_FPS
    if _pose.has("fps"):
        fps = float(_pose["fps"])
    if fps <= 0.0:
        fps = DEFAULT_FPS
    fps *= maxf(0.05, _script_anim_speed_scale)
    var frame_dur := 1.0 / fps
    _frame_time += delta
    while _frame_time >= frame_dur:
        _frame_time -= frame_dur
        _frame_index += 1
        if _frame_index >= _frame_count:
            var loop_from := 0
            if _pose.has("loop_from"):
                loop_from = int(_pose["loop_from"])
            loop_from = clamp(loop_from, 0, _frame_count - 1)
            if not _script_anim_loop:
                var finished_anim := _script_anim_name
                _frame_index = _frame_count - 1
                _frame_time = 0.0
                _script_anim_active = false
                _script_anim_speed_scale = 1.0
                _script_anim_name = ""
                scripted_animation_finished.emit(finished_anim)
                break
            _frame_index = loop_from
        _sprite.frame = _frame_index
        _maybe_execute_pending_attack()
    _maybe_execute_pending_attack()


func _physics_process(delta: float) -> void:
    if _dead or MvGame.simulation_paused:
        velocity = Vector2.ZERO
        return
    if _script_move_active:
        var to_target: Vector2 = _script_move_target - position
        if to_target.length() <= maxf(1.0, _script_move_speed * delta):
            position = _script_move_target
            velocity = Vector2.ZERO
            _script_move_active = false
            scripted_move_finished.emit()
        else:
            velocity = to_target.normalized() * _script_move_speed
            move_and_slide()
        return
    if _contact_cooldown_left > 0.0:
        _contact_cooldown_left = maxf(0.0, _contact_cooldown_left - delta)
    _vertical_drive_active = false

    # Step 1: clear horizontal drive. Leaves re-assert it if they want
    # to keep moving. This makes "no action ran" equal to "idle".
    velocity.x = 0.0
    if _movement_mode != "ground":
        velocity.y = 0.0

    # Step 2: tick behavior tree manually so it runs BEFORE gravity +
    # move_and_slide. Leaves like walk_action write to velocity here.
    if _tree != null:
        _tree.tick()

    _apply_runtime_pose()

    # Step 3: gravity / hover sustain + clamp + slide.
    if _movement_mode == "ground":
        var gravity: float = FALLBACK_GRAVITY
        var max_fall: float = FALLBACK_MAX_FALL
        var profile: MvPhysicsProfile = _get_profile()
        if profile != null:
            gravity = profile.gravity
            max_fall = profile.max_fall

        velocity.y += gravity * delta
        if velocity.y > max_fall:
            velocity.y = max_fall
    else:
        _apply_hover_motion(delta)

    move_and_slide()
    _tick_contact_damage()


func _draw() -> void:
    # Placeholder square — only drawn when no sprite was mounted so
    # entities without an authored sprite_set still show up in-game.
    if _sprite != null:
        return
    var half := PLACEHOLDER_SIZE * 0.5
    var rect := Rect2(-half, PLACEHOLDER_SIZE)
    var col := Color(1.0, 0.2, 0.2, 1.0) if _hit_flash_timer > 0.0 else _placeholder_color
    draw_rect(rect, col)
    draw_rect(rect, Color(1, 1, 1, 0.8), false, 1.0)


func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    return "demo"


func _get_profile() -> MvPhysicsProfile:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.physics
    return null


func _load_entity() -> Dictionary:
    var data := EntIO.load_or_init(pack_id)
    var list_v: Variant = data.get("entities", [])
    if typeof(list_v) != TYPE_ARRAY:
        return {}
    for row_v in list_v:
        if typeof(row_v) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_v
        if str(row.get("id", "")) == entity_id:
            return row
    push_warning("[MvEnemy] entity '%s' not found in pack '%s'" % [entity_id, pack_id])
    return {}


func _load_behavior() -> Dictionary:
    var behavior_id := str(_entity.get("behavior", ""))
    if behavior_id == "":
        return {}
    var data := BehIO.load_or_init(pack_id)
    var list_v: Variant = data.get("behaviors", [])
    if typeof(list_v) != TYPE_ARRAY:
        return {}
    for row_v in list_v:
        if typeof(row_v) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_v
        if str(row.get("id", "")) == behavior_id:
            return row
    push_warning("[MvEnemy] behavior '%s' missing for entity '%s'" % [behavior_id, entity_id])
    return {}


func _mount_tree() -> void:
    if _behavior.is_empty():
        return
    _tree = BehLoader.build_tree(_behavior)
    if _tree == null:
        return
    _tree.process_thread = BeehaveTree.ProcessThread.MANUAL
    add_child(_tree)


func _ensure_collision_shape() -> void:
    for child in get_children():
        if child is CollisionShape2D:
            _col_shape = child
            return
    _col_shape = CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = PLACEHOLDER_SIZE
    _col_shape.shape = rect
    add_child(_col_shape)


func _ensure_contact_area() -> void:
    if _contact_area != null:
        return
    _contact_area = Area2D.new()
    _contact_area.name = "TouchDamageArea"
    _contact_area.monitoring = true
    _contact_area.monitorable = true
    _contact_area.collision_layer = 0
    _contact_area.collision_mask = 0x7fffffff
    _contact_area.add_to_group("mv_enemy_hurt")
    _contact_shape = CollisionShape2D.new()
    _contact_area.add_child(_contact_shape)
    add_child(_contact_area)


func _sync_contact_shape() -> void:
    if _contact_shape == null:
        return
    var rect := RectangleShape2D.new()
    if _col_shape != null and _col_shape.shape is RectangleShape2D:
        rect.size = (_col_shape.shape as RectangleShape2D).size
        _contact_shape.position = _col_shape.position
    else:
        rect.size = PLACEHOLDER_SIZE
        _contact_shape.position = Vector2.ZERO
    rect.size += Vector2(10.0, 10.0)
    _contact_shape.shape = rect


func combat_origin() -> Vector2:
    if _col_shape != null:
        return global_position + _col_shape.position
    return global_position


func hurtbox_world_rect() -> Rect2:
    if _contact_shape != null and _contact_shape.shape is RectangleShape2D:
        var size := (_contact_shape.shape as RectangleShape2D).size
        return Rect2(_contact_shape.global_position - size * 0.5, size)
    if _col_shape != null and _col_shape.shape is RectangleShape2D:
        var fallback_size := (_col_shape.shape as RectangleShape2D).size
        return Rect2(_col_shape.global_position - fallback_size * 0.5, fallback_size)
    return Rect2(global_position - PLACEHOLDER_SIZE * 0.5, PLACEHOLDER_SIZE)


func hurtbox_contains_point(world_pos: Vector2) -> bool:
    return hurtbox_world_rect().has_point(world_pos)


func hurtbox_intersects_rect(world_rect: Rect2) -> bool:
    return hurtbox_world_rect().intersects(world_rect)


func _tick_contact_damage() -> void:
    if contact_damage <= 0 or _contact_area == null or _contact_cooldown_left > 0.0:
        return
    for area in _contact_area.get_overlapping_areas():
        if area == null or not area.is_in_group("mv_player_hurt"):
            continue
        var player: Variant = area.get_meta("player") if area.has_meta("player") else area.get_parent()
        if player == null or not player.has_method("take_damage"):
            continue
        player.call("take_damage", contact_damage, "enemy_contact", global_position)
        _contact_cooldown_left = contact_cooldown
        return
    for player_v in get_tree().get_nodes_in_group("mv_player"):
        var player_node := player_v as Node2D
        if player_node == null or not player_node.has_method("take_damage"):
            continue
        if player_node.global_position.distance_to(global_position) > 24.0:
            continue
        player_node.call("take_damage", contact_damage, "enemy_contact", global_position)
        _contact_cooldown_left = contact_cooldown
        return


# Reads the entity's sprite_set, picks the first PNG alphabetically,
# loads its pose metadata, and mounts a Sprite2D child driven by
# hframes so horizontal strips animate natively. Silently no-ops when
# the entity has no sprite_set — the placeholder square draws instead.
#
# The sprite is positioned so its feet land on the bottom of the
# collision box (plus any y_offset authored in the pose). First PNG
# wins because the current entity editor doesn't expose a "default
# pose" selector — if the user wants a specific frame, they name it
# to sort first (a_idle.png, 00_idle.png, etc.) or we add a default
# picker later.
func _mount_sprite() -> void:
    _sprite_set_rel = str(_entity.get("sprite_set", ""))
    if _sprite_set_rel == "":
        return
    _available_pose_pngs = EntIO.list_sprite_pngs(pack_id, _sprite_set_rel)
    if _available_pose_pngs.is_empty():
        return
    _rebuild_pose_stems()
    var poses_doc := EntIO.load_poses(pack_id, _sprite_set_rel)
    var poses_v: Variant = poses_doc.get("poses", {})
    if typeof(poses_v) == TYPE_DICTIONARY:
        _pose_registry = poses_v
    var default_pose := _resolve_state_pose("idle")
    if default_pose.is_empty():
        default_pose = str(_available_pose_pngs[0])
    _apply_pose_texture(default_pose)


func begin_scripted_move(target_pos: Vector2, speed: float = 64.0) -> void:
    _script_move_target = target_pos
    _script_move_speed = maxf(1.0, speed)
    _script_move_active = true


func set_scripted_facing(dir: float) -> void:
    if dir == 0.0:
        return
    beh_facing = 1 if dir > 0.0 else -1
    _last_facing_right = beh_facing > 0
    if _sprite != null:
        _sprite.flip_h = not _last_facing_right


func play_scripted_animation(anim_name: String, loop: bool = true, speed_scale: float = 1.0) -> void:
    var png_name := _resolve_pose_png(anim_name)
    if png_name.is_empty():
        return
    _script_anim_active = true
    _script_anim_loop = loop
    _script_anim_speed_scale = maxf(0.05, speed_scale)
    _script_anim_name = anim_name.strip_edges()
    _apply_pose_texture(png_name, true)


func stop_scripted_animation() -> void:
    _script_anim_active = false
    _script_anim_speed_scale = 1.0
    _script_anim_name = ""


func is_scripted_move_active() -> bool:
    return _script_move_active


func is_scripted_animation_active() -> bool:
    return _script_anim_active


func current_scripted_animation_name() -> String:
    return _script_anim_name


func ai_request_pose(state: String, hold_seconds: float = 0.12,
        loop: bool = true, speed_scale: float = 1.0) -> void:
    if _script_anim_active:
        return
    var trimmed := state.strip_edges().to_lower()
    if trimmed.is_empty():
        return
    var now := _now_seconds()
    if not _ai_pose_state.is_empty() and now <= _ai_pose_hold_until:
        if _pose_state_priority(trimmed) < _pose_state_priority(_ai_pose_state):
            return
    _ai_pose_state = trimmed
    _ai_pose_hold_until = now + maxf(0.0, hold_seconds)
    _ai_pose_loop = loop
    _ai_pose_speed_scale = maxf(0.05, speed_scale)
    _ai_pose_restart_pending = true


func ai_face_dir(dir: float) -> void:
    if dir == 0.0:
        return
    beh_facing = 1 if dir > 0.0 else -1
    _last_facing_right = beh_facing > 0


func ai_set_vertical_drive(active: bool = true) -> void:
    _vertical_drive_active = active


func fire_projectile(dir: Vector2, speed: float = -1.0, damage: int = -1,
        lifetime: float = 2.0) -> bool:
    if dir.length_squared() <= 0.0001:
        return false
    var parent := get_parent()
    if parent == null:
        return false
    var proj := MvProjectile.new()
    proj.direction = dir.normalized()
    proj.speed = speed if speed > 0.0 else projectile_speed
    proj.damage = damage if damage >= 0 else projectile_damage
    proj.lifetime = maxf(0.05, lifetime)
    proj.global_position = global_position
    parent.add_child(proj)
    return true


func default_melee_range() -> float:
    return melee_range


func default_projectile_range() -> float:
    return projectile_range


func queue_melee_attack(target: Node, range_px: float = -1.0, damage: int = -1) -> bool:
    if _dead:
        return false
    var attack_range: float = range_px if range_px >= 0.0 else melee_range
    var attack_damage_value: int = damage if damage >= 0 else attack_damage
    if _should_execute_attack_immediately():
        return _execute_melee_attack(target, attack_range, attack_damage_value)
    _pending_attack = {
        "type": "melee",
        "target_ref": weakref(target),
        "range": attack_range,
        "damage": attack_damage_value,
        "trigger_frame": _resolved_attack_trigger_frame(melee_attack_trigger_frame),
    }
    ai_request_pose("attack", _attack_pose_hold_seconds(int(_pending_attack["trigger_frame"])), false, 1.0)
    return true


func queue_projectile_attack(target: Node, dir: Vector2, speed: float = -1.0,
        damage: int = -1, lifetime: float = 2.0, range_px: float = -1.0) -> bool:
    if _dead or dir.length_squared() <= 0.0001:
        return false
    var attack_speed: float = speed if speed > 0.0 else projectile_speed
    var attack_damage_value: int = damage if damage >= 0 else projectile_damage
    var attack_range: float = range_px if range_px >= 0.0 else projectile_range
    if _should_execute_attack_immediately():
        return _execute_projectile_attack(target, dir, attack_speed, attack_damage_value, lifetime, attack_range)
    _pending_attack = {
        "type": "projectile",
        "target_ref": weakref(target),
        "dir": dir.normalized(),
        "speed": attack_speed,
        "damage": attack_damage_value,
        "lifetime": maxf(0.05, lifetime),
        "range": attack_range,
        "trigger_frame": _resolved_attack_trigger_frame(projectile_attack_trigger_frame),
    }
    ai_request_pose("attack", _attack_pose_hold_seconds(int(_pending_attack["trigger_frame"])), false, 1.0)
    return true


func _resolve_pose_png(anim_name: String) -> String:
    var trimmed := anim_name.strip_edges().to_lower()
    if trimmed.is_empty():
        return ""
    for png_v in _available_pose_pngs:
        var png_name := str(png_v)
        var stem := png_name.get_basename().to_lower()
        if stem == trimmed or stem.ends_with("_" + trimmed):
            return png_name
    for png_v in _available_pose_pngs:
        var png_name := str(png_v)
        if png_name.get_basename().to_lower().contains(trimmed):
            return png_name
    return ""


func _should_execute_attack_immediately() -> bool:
    return _sprite == null or _attack_pose_frame_count() <= 1


func _resolved_attack_trigger_frame(configured_frame: int) -> int:
    var frame_count := _attack_pose_frame_count()
    if frame_count <= 1:
        return 0
    if configured_frame < 0:
        return frame_count - 1
    return clampi(configured_frame, 0, frame_count - 1)


func _attack_pose_hold_seconds(trigger_frame: int) -> float:
    var frame_count := _attack_pose_frame_count()
    var fps := _attack_pose_fps()
    if frame_count <= 1 or fps <= 0.0:
        return 0.18
    var clamped_trigger := clampi(trigger_frame, 0, frame_count - 1)
    return maxf(0.18, float(clamped_trigger + 1) / fps + 0.05)


func _attack_pose_frame_count() -> int:
    var attack_png := _resolve_state_pose("attack")
    if attack_png.is_empty():
        return _frame_count
    if _current_pose_png == attack_png and _frame_count > 0:
        return _frame_count
    var pose_v: Variant = _pose_registry.get(attack_png, {})
    if typeof(pose_v) == TYPE_DICTIONARY:
        var pose: Dictionary = pose_v
        if pose.has("frames"):
            return maxi(1, int(pose.get("frames", 1)))
    var tex := EntIO.load_sprite_png(pack_id, _sprite_set_rel, attack_png)
    return EntIO.autodetect_frame_count(tex)


func _attack_pose_fps() -> float:
    var attack_png := _resolve_state_pose("attack")
    if attack_png.is_empty():
        return DEFAULT_FPS
    if _current_pose_png == attack_png and _pose.has("fps"):
        return maxf(0.01, float(_pose.get("fps", DEFAULT_FPS)))
    var pose_v: Variant = _pose_registry.get(attack_png, {})
    if typeof(pose_v) == TYPE_DICTIONARY:
        return maxf(0.01, float((pose_v as Dictionary).get("fps", DEFAULT_FPS)))
    return DEFAULT_FPS


func _maybe_execute_pending_attack() -> void:
    if _pending_attack.is_empty():
        return
    var trigger_frame: int = int(_pending_attack.get("trigger_frame", 0))
    if _frame_index < trigger_frame:
        return
    var pending := _pending_attack
    _pending_attack = {}
    var attack_type := str(pending.get("type", ""))
    if attack_type == "melee":
        _execute_melee_attack(
            _deref_attack_target(pending.get("target_ref", null)),
            float(pending.get("range", melee_range)),
            int(pending.get("damage", attack_damage))
        )
    elif attack_type == "projectile":
        _execute_projectile_attack(
            _deref_attack_target(pending.get("target_ref", null)),
            pending.get("dir", Vector2.RIGHT),
            float(pending.get("speed", projectile_speed)),
            int(pending.get("damage", projectile_damage)),
            float(pending.get("lifetime", 2.0)),
            float(pending.get("range", projectile_range))
        )


func _deref_attack_target(target_ref: Variant) -> Node:
    if target_ref is WeakRef:
        return (target_ref as WeakRef).get_ref()
    if target_ref is Node:
        return target_ref as Node
    return null


func _execute_melee_attack(target: Node, range_px: float, damage: int) -> bool:
    if target == null or not is_instance_valid(target) or not (target is Node2D):
        return false
    var target_node := target as Node2D
    var a_pos := combat_origin()
    var target_pos := _combat_origin(target_node)
    if target_pos.distance_to(a_pos) > range_px:
        return false
    if target.has_method("take_damage"):
        target.call("take_damage", damage, "enemy", a_pos)
        return true
    return false


func _execute_projectile_attack(target: Node, dir: Vector2, speed: float, damage: int,
        lifetime: float, range_px: float) -> bool:
    var shot_dir := dir.normalized()
    if target != null and is_instance_valid(target) and target is Node2D:
        var a_pos := combat_origin()
        var target_pos := _combat_origin(target)
        if range_px < INF and target_pos.distance_to(a_pos) > range_px:
            return false
        var target_vec := target_pos - a_pos
        if target_vec.length_squared() > 0.001:
            shot_dir = target_vec.normalized()
    return fire_projectile(shot_dir, speed, damage, lifetime)


func _combat_origin(node: Node) -> Vector2:
    if node != null and node.has_method("combat_origin"):
        var origin_v: Variant = node.call("combat_origin")
        if typeof(origin_v) == TYPE_VECTOR2:
            return origin_v
    return (node as Node2D).global_position if node is Node2D else Vector2.ZERO


func _rebuild_pose_stems() -> void:
    _pose_stems.clear()
    for png_v in _available_pose_pngs:
        var png_name := str(png_v)
        var stem := png_name.get_basename().to_lower()
        if not _pose_stems.has(stem):
            _pose_stems[stem] = png_name


func _resolve_state_pose(state: String) -> String:
    var aliases := _state_aliases(state)
    var alias_overrides_v: Variant = _entity.get("anim_aliases", {})
    var alias_overrides: Dictionary = {}
    if typeof(alias_overrides_v) == TYPE_DICTIONARY:
        alias_overrides = alias_overrides_v
    if alias_overrides.has(state):
        var override_v: Variant = alias_overrides.get(state)
        if typeof(override_v) == TYPE_STRING:
            var override_name := _resolve_pose_png(str(override_v))
            if not override_name.is_empty():
                return override_name
        elif typeof(override_v) == TYPE_ARRAY:
            for alias_v in override_v:
                var override_name := _resolve_pose_png(str(alias_v))
                if not override_name.is_empty():
                    return override_name
    for alias in aliases:
        if _pose_stems.has(alias):
            return str(_pose_stems[alias])
    for alias in aliases:
        for stem_v in _pose_stems.keys():
            var stem := str(stem_v)
            if stem == alias or stem.ends_with("_" + alias):
                return str(_pose_stems[stem_v])
    for alias in aliases:
        for stem_v in _pose_stems.keys():
            var stem := str(stem_v)
            if stem.contains(alias):
                return str(_pose_stems[stem_v])
    return ""


func _state_aliases(state: String) -> Array:
    match state:
        "idle":
            return ["idle", "stand", "hang", "front"]
        "move":
            return ["walk", "run", "fly", "float", "chase", "move"]
        "attack":
            return ["attack", "shoot", "cast", "slash", "bite", "throw", "special", "fire", "spit", "breath"]
        "hurt":
            return ["hurt", "hithurt", "hit", "damage"]
        "death":
            return ["death", "die", "dying", "defeat"]
        "jump":
            return ["jump", "rise", "upward", "up"]
        "fall":
            return ["fall", "inair", "air", "drop", "flying"]
        "spawn":
            return ["spawn", "appear", "rise"]
        _:
            return [state]


func _apply_runtime_pose() -> void:
    if _sprite == null or _script_anim_active:
        return
    var target_state := ""
    var loop := true
    var speed_scale := 1.0
    var restart_pose := false
    if not _ai_pose_state.is_empty() and _now_seconds() <= _ai_pose_hold_until:
        target_state = _ai_pose_state
        loop = _ai_pose_loop
        speed_scale = _ai_pose_speed_scale
        restart_pose = _ai_pose_restart_pending and not loop
        _ai_pose_restart_pending = false
    else:
        _ai_pose_state = ""
        _ai_pose_restart_pending = false
        if _dead:
            target_state = "death"
        elif _movement_mode == "ground" and not is_on_floor():
            target_state = "jump" if velocity.y < -4.0 else "fall"
        elif absf(velocity.x) > 2.0 or (_movement_mode != "ground" and absf(velocity.y) > 2.0):
            target_state = "move"
        else:
            target_state = "idle"
    var png_name := _resolve_state_pose(target_state)
    if png_name.is_empty():
        return
    _script_anim_loop = loop
    _script_anim_speed_scale = speed_scale
    _apply_pose_texture(png_name, restart_pose)


func _apply_hover_motion(delta: float) -> void:
    var speed_limit := maxf(24.0, move_speed)
    if _vertical_drive_active:
        _hover_anchor_y = global_position.y
        velocity.y = clampf(velocity.y, -speed_limit, speed_limit)
        return
    _hover_bob_phase += delta * TAU * _hover_bob_speed
    var target_y := _hover_anchor_y + sin(_hover_bob_phase) * _hover_bob_amplitude
    var correction := (target_y - global_position.y) * 6.0
    velocity.y = clampf(correction, -speed_limit, speed_limit)


func _now_seconds() -> float:
    return float(Time.get_ticks_msec()) / 1000.0


func _pose_state_priority(state: String) -> int:
    match state:
        "death":
            return 4
        "hurt":
            return 3
        "attack":
            return 2
        "move":
            return 1
        "idle":
            return 0
        _:
            return 0


func _play_death_pose() -> void:
    var death_png := _resolve_state_pose("death")
    if death_png.is_empty():
        _defeat_cleanup_at = _now_seconds() + 0.08
        return
    _script_anim_active = false
    _script_anim_name = "death"
    _script_anim_loop = false
    _script_anim_speed_scale = 1.0
    _apply_pose_texture(death_png, true)
    _defeat_cleanup_at = _now_seconds() + _current_pose_duration_seconds() + 0.05


func _current_pose_duration_seconds() -> float:
    var fps: float = DEFAULT_FPS
    if _pose.has("fps"):
        fps = float(_pose["fps"])
    if fps <= 0.0:
        fps = DEFAULT_FPS
    return maxf(0.08, float(maxi(1, _frame_count)) / fps)


func _apply_pose_texture(png_name: String, force_restart: bool = false) -> void:
    if _sprite_set_rel.is_empty() or png_name.is_empty():
        return
    if png_name == _current_pose_png and _sprite != null and not force_restart:
        return
    var tex: Texture2D = _sprite.texture if _sprite != null and png_name == _current_pose_png else null
    if tex == null:
        tex = EntIO.load_sprite_png(pack_id, _sprite_set_rel, png_name)
        if tex == null:
            return
        _current_pose_png = png_name
        _pose = {}
        if _pose_registry.has(png_name):
            var p_v: Variant = _pose_registry[png_name]
            if typeof(p_v) == TYPE_DICTIONARY:
                _pose = p_v
        if _pose.has("frames"):
            _frame_count = max(1, int(_pose["frames"]))
        else:
            _frame_count = EntIO.autodetect_frame_count(tex)
        if _sprite == null:
            _sprite = Sprite2D.new()
            _sprite.centered = true
            add_child(_sprite)
        _sprite.texture = tex
        _sprite.hframes = _frame_count
    _frame_index = 0
    _frame_time = 0.0
    _sprite.frame = 0

    var frame_h: float = float(tex.get_height())
    var collision_half_h: float = PLACEHOLDER_SIZE.y * 0.5
    if _col_shape != null and _col_shape.shape is RectangleShape2D:
        collision_half_h = (_col_shape.shape as RectangleShape2D).size.y * 0.5
    var y_off: float = 0.0
    if _pose.has("y_offset"):
        y_off = float(_pose["y_offset"])
    _sprite.position = Vector2(0, collision_half_h - frame_h * 0.5 + y_off)
