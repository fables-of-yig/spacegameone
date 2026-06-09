class_name MvPlayer
extends CharacterBody2D


# Player character controller. Ported from MVMania's C# Player (diortem
# Samus.cs lineage) with the same three structural changes:
#   1. Physics constants → loaded from the current MvPhysicsProfile resource.
#   2. Pose table → loaded from JSON at _ready; packs with fewer poses
#      silently degrade via the _try_set_pose fallback.
#   3. Frame map → loaded from pack-relative path via MvPackLoader.
#
# The physics state machine is a verbatim port of the SM-derived C# code so
# pose/movement behaviour matches SM's feel. Every ROM comment is preserved
# because the correctness story comes from the ROM.
#
# AbilityRegistry param lookups use hardcoded defaults; NPC/Sign interact
# uses group-based dispatch against MvInteractable; grenade launcher spawns
# MvGrenade projectiles with arc + AoE + bomb-jump on detonate.

# ===== Movement types (from ROM $91:B629 movement type field) =====
const MV_STAND: int = 0
const MV_RUN: int = 1
const MV_JUMP: int = 2
const MV_SPIN: int = 3
const MV_CROUCH: int = 5
const MV_FALL: int = 6
const MV_TURN: int = 14
const MV_TRANS: int = 15
const MV_WALLJUMP: int = 20
const MV_TURN_AIR: int = 23
const MV_TURN_FALL: int = 24
const MV_PARRY: int = 30
const MV_KNOCKDOWN: int = 31
const MV_STAND_UP: int = 32

# ===== Physics profile (loaded from the current content pack) =====
var _profile: MvPhysicsProfile = null

# ===== Nodes =====
var _sprite: Sprite2D = null
var _sprite_layers: Dictionary = {}
var _sheet_defs: Array = []
var _sheet_textures: Dictionary = {}
var _frame_width: int = 50
var _frame_height: int = 44
var _sheet_cols: int = 10
var _col: CollisionShape2D = null
var _rect: RectangleShape2D = null
var _hurtbox_area: Area2D = null
var _hurtbox_col: CollisionShape2D = null
var _hurtbox_rect: RectangleShape2D = null
var _beam_scene: PackedScene = null
var _beam_sfx: AudioStreamPlayer2D = null
var _interact_zone: Area2D = null
var _charge_fx_sprite: Sprite2D = null
var _charge_fx_texture: Texture2D = null
var _charge_fx_attack_id: String = ""
var _charge_fx_sheet_path: String = ""
var _charge_fx_frame_width: int = 32
var _charge_fx_frame_height: int = 32
var _charge_fx_frame_index: int = 0
var _charge_fx_frame_count: int = 1
var _charge_fx_frame_tick: int = 6
var _charge_fx_anim_timer: float = 0.0
var _charge_fx_anim_frame: int = 0

# ===== Pose + frame data (loaded from JSON at _ready) =====
# Poses: int → Dictionary { dir, mvtype, y_radius, y_offset, collision_width,
#                           hurtbox_x/y/w/h, weapon_anchor_x/y,
#                           timing, anim_speed, frame_boxes, loop_from, transition_to }
# Frames: int → Array[int]  (sheet frame indices)
var _poses: Dictionary = {}
var _frames: Dictionary = {}

# ===== State =====
var _pose: int = 1
var _yr: int = 16              # current collision Y-radius
var _right: bool = true        # current facing
var _was_jump_held: bool = false
var _was_on_floor: bool = true
var _locked: bool = false      # true while a script/cutscene owns the player
var _script_move_active: bool = false
var _script_move_target: Vector2 = Vector2.ZERO
var _script_move_speed: float = 64.0
var _script_anim_active: bool = false
var _script_anim_pose_id: int = -1
var _script_anim_loop: bool = true
var _script_anim_speed_scale: float = 1.0
var _script_anim_name: String = ""
var _dodge_roll_timer: float = 0.0
var _dodge_roll_dir: int = 0
const DODGE_ROLL_SEC: float = 0.28
const DODGE_ROLL_SPEED_MULT: float = 1.85
const DODGE_ROLL_IFRAME_SEC: float = 0.20

# ===== Beam state =====
var _shoot_cooldown: float = 0.0
var _beam_count: int = 0
# Beam charge: hold shoot to build a meter; release at
# _profile.beam_charge_seconds to fire a 5× damage charged variant.
# Visual cue is a cyan modulate while charged.
var _beam_charge_timer: float = 0.0
var _was_shoot_held: bool = false
var _authored_melee_attack: Dictionary = {}
var _melee_input_locked: bool = false
var _secondary_mode_active: bool = false

# Grace window: after an authored melee attack ends, allow a follow-up
# click to chain `combo_next_id` for COMBO_GRACE_SECONDS so the player
# doesn't have to mash inside the active animation frames.
var _combo_grace_timer: float = 0.0
var _combo_grace_next_id: String = ""
const COMBO_GRACE_SECONDS: float = 0.2

# Knockdown state: true between apply_knockdown() and the pose chain leaving
# MV_KNOCKDOWN / MV_STAND_UP. While active the player is set_locked(true) and
# _invuln_timer is held high so the recovery animation can't be interrupted
# by another hit.
var _knockdown_active: bool = false

# ===== Bomb state (grenade launcher) =====
var _bomb_count: int = 0
var _bomb_cooldown: float = 0.0
const MAX_BOMBS: int          = 3       # SM cap ($90:C3C9)
const BOMB_COOLDOWN: float    = 10.0 / 60.0
const BOMB_THROW_SPEED: float = 220.0
const BOMB_UP_BOOST: float    = 180.0
const _MvGrenade := preload("res://MV/scripts/grenade.gd")
const _MvAuthoredProjectile := preload("res://MV/scripts/authored_projectile.gd")
const _MvAuthoredMeleeHitbox := preload("res://MV/scripts/authored_melee_hitbox.gd")

# ===== Grapple state =====
var _grapple_projectile: MvGrappleBeam = null
var _grapple_swinging: bool = false
var _grapple_pivot: Vector2 = Vector2.ZERO
var _grapple_len: float = 0.0
var _grapple_angle: float = 0.0       # CCW from +X, radians
var _grapple_ang_vel: float = 0.0     # rad/s

# ===== Animation state =====
var _anim_idx: int = 0
var _anim_ticks: float = 0.0
var _anim_count: int = 0

# ===== Phase 7 ability state =====
var _air_jumps_remaining: int = 0
var _wall_jump_cooldown: float = 0.0
const DEF_WALL_JUMP_COOLDOWN_SEC: float = 0.25

# Default values for each ability param we look up. These are the fallbacks
# that apply when a pack's abilities.json doesn't define the key — everything
# still works with no registry data, and packs can override any one value
# without shipping the whole ability def.
const DEF_SPEED_BOOSTER_CHARGE_SEC: float = 1.0
const DEF_SPEED_BOOSTER_BOOST_MULT: float = 1.6
const DEF_HIGH_JUMP_MULT: float           = 1.4
const DEF_DOUBLE_JUMP_EXTRA: int          = 1
const DEF_SPACE_JUMP_AIR_JUMPS: int       = 99   # effectively infinite
const DEF_WALL_JUMP_X_SPEED: float        = 200.0
const DEF_WALL_JUMP_Y_SPEED: float        = 280.0
const DEF_SHINESPARK_SPEED: float         = 600.0
const DEF_SHINE_SPARK_SEC: float          = 0.6
const DEF_SHINE_STASH_SEC: float          = 5.0

var _speed_charge_timer: float = 0.0
var _speed_charge_dir: int = 0
var _shine_active: bool = false

var _shine_stash_timer: float = 0.0
var _shine_spark_timer: float = 0.0
var _shine_spark_vel: Vector2 = Vector2.ZERO
var _shine_spark_active: bool = false

# ===== Phase 8 player stats (HP / iframes) =====
# HP and Energy are tank-based vitals on the Nebula HUD: each tank = 100, and
# collectible upgrades raise the cap toward HP_TANK_MAX / ENERGY_TANK_MAX tanks
# (the fully-upgraded maxima). Starting capacity comes from authored stats.
# Energy is a real persisted/authorable stat; no ability spends it yet (spell
# costs aren't built) — spend_energy() is ready for when they are.
const HP_TANK_MAX: int = 14       # fully upgraded = 1400
const ENERGY_TANK_MAX: int = 10   # fully upgraded = 1000
@export var max_hp: int = 99
@export var hp: int = 99
@export var max_energy: int = 100
@export var energy: int = 100
@export var invuln_seconds: float = 1.0
var _invuln_timer: float = 0.0
# Knockback: brief input lockout + horizontal impulse away from the damage
# source. ROM $91:AD20 holds Samus for 12 SNES frames (0.2s) with +/- 1.5
# px/frame horizontal velocity and a small upward kick.
var _knockback_timer: float = 0.0
const KNOCKBACK_SEC: float   = 12.0 / 60.0
const KNOCKBACK_X_SPD: float = 150.0
const KNOCKBACK_Y_SPD: float = 120.0
# Door entry lock: after spawning at a door edge, walk inward on autopilot
# for DOOR_LOCK_SEC so the transition feels intentional and the camera has
# time to settle on the new room.
var _door_lock_timer: float = 0.0
const DOOR_LOCK_SEC: float = 0.35
var _door_lock_dir: int = 0

# ===== Status effects (burn/poison/slow from spike hazards) =====
# Each entry: {type:String, remaining:float, tick_interval:float,
#              tick_damage:int, speed_mult:float, _tick_acc:float}
var _active_effects: Array = []

# ===== Shooting — Dread-style twin-stick free aim =====
const STICK_DEADZONE: float = 0.3
const BARREL_RADIUS: float  = 10.0   # muzzle offset from shoulder
const SHOULDER_Y: float     = -8.0   # pixels above Position.Y - _yr
const SLOPE_STEP_UP_MAX: float = 16.0

signal entered_door(door_id: String)
signal player_damaged(amount: int, hp_remaining: int, source: String)
signal player_died(source: String)
signal player_spawned(spawn_pos: Vector2)
signal player_interacted(entity_type: String, pos: Vector2)
signal scripted_move_finished
signal scripted_animation_finished(anim_name: String)

# ===== Init =====

func _ready() -> void:
    add_to_group("mv_player")
    _sprite = $Sprite2D
    _sprite_layers["base"] = _sprite
    _col = $CollisionShape2D
    _rect = _col.shape
    # Keep the body attached to authored slope geometry when walking across
    # room collision. The smooth ramp collider fixed the old stair-step
    # sticking, so we can use a stronger snap again for uphill walking.
    floor_snap_length = 8.0
    _beam_scene = load("res://MV/scenes/beam.tscn")
    _beam_sfx = get_node_or_null("BeamSfx")
    _build_hurtbox()
    _build_charge_fx_sprite()

    # 32×32 interact Area2D centred on the player. Pressing the interact
    # action calls interact() on the closest overlapping "mv_interactable"
    # body. MvInteractable implements that contract; any custom node in
    # the group with a public interact() method qualifies too.
    _build_interact_zone()

    var pack: MvPackRef = MvPackLoader.current_pack
    if pack != null:
        _profile = pack.physics
        _load_frames(pack.player_frames_path(), pack)
        _load_poses(pack.player_poses_path())
    else:
        push_error("MvPlayer: no content pack loaded — using default MvPhysicsProfile")
        _profile = MvPhysicsProfile.new()

    # Force a collision-shape rebuild so _profile.collision_width takes effect.
    _yr = -1
    _set_collision(16)
    _set_pose(1)
    _show_frame()


func _normalize_sheet_defs(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) == TYPE_ARRAY:
        for entry_v in v:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_v
            var sheet_id: String = str(entry.get("id", "")).strip_edges()
            var file_name: String = str(entry.get("file", "")).strip_edges()
            if sheet_id.is_empty() or file_name.is_empty():
                continue
            out.append({
                "id": sheet_id,
                "file": file_name,
                "z": int(entry.get("z", out.size())),
            })
    if out.is_empty():
        out.append({
            "id": "base",
            "file": "player_sheet.png",
            "z": 0,
        })
    return out


func _normalize_frame_layers(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) == TYPE_ARRAY:
        for layer_v in v:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = layer_v
            out.append({
                "sheet": str(layer.get("sheet", "base")).strip_edges(),
                "index": int(layer.get("index", 0)),
            })
    if out.is_empty():
        out.append({
            "sheet": "base",
            "index": 0,
        })
    return out


func _normalize_frame_entry(v: Variant) -> Dictionary:
    if typeof(v) == TYPE_DICTIONARY:
        var entry: Dictionary = v
        if entry.has("layers"):
            return {
                "pose": int(entry.get("pose", 0)),
                "rotation_deg": float(entry.get("rotation_deg", 0.0)),
                "layers": _normalize_frame_layers(entry.get("layers", [])),
            }
        return {
            "pose": int(entry.get("pose", 0)),
            "rotation_deg": float(entry.get("rotation_deg", 0.0)),
            "layers": [{
                "sheet": "base",
                "index": int(entry.get("index", 0)),
            }],
        }
    return {
        "pose": 0,
        "rotation_deg": 0.0,
        "layers": [{
            "sheet": "base",
            "index": int(v),
        }],
    }


func _sheet_texture_path(pack: MvPackRef, file_name: String) -> String:
    if pack == null:
        return ""
    return MvPackLoader.resolve_read_cascade(pack.pack_id, "Sprites", file_name)


func _load_sheet_textures(pack: MvPackRef) -> void:
    _sheet_textures.clear()
    for sheet_def_v in _sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var sheet_id: String = str(sheet_def.get("id", "")).strip_edges()
        var file_name: String = str(sheet_def.get("file", "")).strip_edges()
        if sheet_id.is_empty() or file_name.is_empty():
            continue
        var tex_path: String = _sheet_texture_path(pack, file_name)
        if tex_path.is_empty():
            continue
        if not FileAccess.file_exists(tex_path):
            _sheet_textures[sheet_id] = _make_placeholder_sheet(sheet_id)
            continue
        var img := Image.new()
        var err: int = img.load(tex_path)
        if err != OK:
            _sheet_textures[sheet_id] = _make_placeholder_sheet(sheet_id)
            continue
        _sheet_textures[sheet_id] = ImageTexture.create_from_image(img)


func _make_placeholder_sheet(sheet_id: String) -> Texture2D:
    var cols := maxi(1, _sheet_cols)
    var rows := 24
    var cell_w := maxi(1, _frame_width)
    var cell_h := maxi(1, _frame_height)
    var img := Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    var fill := Color(0.25, 0.85, 1.0, 1.0) if sheet_id == "base" else Color(1.0, 0.7, 0.25, 0.9)
    var edge := Color(0.05, 0.08, 0.12, 1.0)
    for row in range(rows):
        for col in range(cols):
            var origin := Vector2i(col * cell_w, row * cell_h)
            @warning_ignore("integer_division")
            var body := Rect2i(origin + Vector2i(maxi(1, cell_w / 4), maxi(1, cell_h / 6)), Vector2i(maxi(2, cell_w / 2), maxi(2, cell_h * 2 / 3)))
            img.fill_rect(body, fill)
            img.fill_rect(Rect2i(body.position, Vector2i(body.size.x, 1)), edge)
            img.fill_rect(Rect2i(body.position + Vector2i(0, body.size.y - 1), Vector2i(body.size.x, 1)), edge)
            img.fill_rect(Rect2i(body.position, Vector2i(1, body.size.y)), edge)
            img.fill_rect(Rect2i(body.position + Vector2i(body.size.x - 1, 0), Vector2i(1, body.size.y)), edge)
    return ImageTexture.create_from_image(img)


func _ensure_layer_sprite(sheet_id: String, z_order: int) -> Sprite2D:
    if _sprite_layers.has(sheet_id):
        var existing: Sprite2D = _sprite_layers[sheet_id]
        if is_instance_valid(existing):
            existing.z_index = z_order
            return existing
    var spr := Sprite2D.new()
    spr.centered = true
    spr.z_index = z_order
    add_child(spr)
    _sprite_layers[sheet_id] = spr
    return spr


func _rebuild_layer_sprites() -> void:
    var keep_ids: Dictionary = {"base": true}
    if _sprite != null:
        _sprite.centered = true
    for sheet_def_v in _sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var sheet_id: String = str(sheet_def.get("id", "")).strip_edges()
        if sheet_id.is_empty():
            continue
        keep_ids[sheet_id] = true
        var spr: Sprite2D = _sprite if sheet_id == "base" else _ensure_layer_sprite(sheet_id, int(sheet_def.get("z", 0)))
        spr.texture = _sheet_textures.get(sheet_id, null) as Texture2D
        spr.visible = false
        spr.z_index = int(sheet_def.get("z", 0))
    for sheet_id_v in _sprite_layers.keys():
        var sheet_id: String = str(sheet_id_v)
        if keep_ids.has(sheet_id):
            continue
        var stale: Sprite2D = _sprite_layers[sheet_id]
        if stale != null and stale != _sprite and is_instance_valid(stale):
            stale.queue_free()
        _sprite_layers.erase(sheet_id)


func _set_sprite_flip_all(flip_h: bool) -> void:
    for spr_v in _sprite_layers.values():
        var spr: Sprite2D = spr_v
        if is_instance_valid(spr):
            spr.flip_h = flip_h


func _set_sprite_offset_all(offset: Vector2) -> void:
    for spr_v in _sprite_layers.values():
        var spr: Sprite2D = spr_v
        if is_instance_valid(spr):
            # Keep the sprite pivot at its visual center so authored per-frame
            # rotations match the sprite editor preview instead of orbiting
            # around the player root.
            spr.position = offset
            spr.offset = Vector2.ZERO


func _set_sprite_modulate_all(color: Color) -> void:
    for spr_v in _sprite_layers.values():
        var spr: Sprite2D = spr_v
        if is_instance_valid(spr):
            spr.modulate = color


func _sprite_offset_for_pose(base_info: Dictionary, effective_info: Dictionary = {}) -> Vector2:
    var sprite_base_radius := int(base_info.get("y_radius", _yr))
    var y_off := int(effective_info.get("y_offset", base_info.get("y_offset", 0)))
    return Vector2(0, -sprite_base_radius - y_off)


func _build_charge_fx_sprite() -> void:
    _charge_fx_sprite = Sprite2D.new()
    _charge_fx_sprite.centered = true
    _charge_fx_sprite.visible = false
    _charge_fx_sprite.z_index = 30
    add_child(_charge_fx_sprite)


func _load_poses(path: String) -> void:
    # Optional per-pack asset. A fresh pack with no sprite data just leaves
    # _poses empty and falls back to whatever _set_pose does with id=1.
    if not FileAccess.file_exists(path):
        return
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("MvPlayer: failed to open %s" % path)
        return
    var text := f.get_as_text()
    f.close()

    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("MvPlayer: failed to parse %s" % path)
        return

    var root: Dictionary = parsed
    if not root.has("poses"):
        push_error("MvPlayer: %s has no 'poses' section" % path)
        return

    var poses: Dictionary = root["poses"]
    for key in poses.keys():
        var key_str := str(key)
        if not key_str.is_valid_int():
            continue
        var pose_id := int(key_str)
        var p: Dictionary = poses[key]

        var timing_src: Array = p.get("timing", [])
        var timing: Array = []
        timing.resize(timing_src.size())
        for i in range(timing_src.size()):
            timing[i] = int(timing_src[i])
        var frame_boxes_src: Variant = p.get("frame_boxes", [])
        var frame_boxes: Array = []
        if typeof(frame_boxes_src) == TYPE_ARRAY:
            for box_v in frame_boxes_src:
                if typeof(box_v) != TYPE_DICTIONARY:
                    frame_boxes.append({})
                    continue
                var box_src: Dictionary = box_v
                var box: Dictionary = {}
                for box_key in ["y_radius", "y_offset", "collision_x", "collision_width", "hurtbox_x", "hurtbox_y", "hurtbox_w", "hurtbox_h"]:
                    if box_src.has(box_key):
                        box[box_key] = int(box_src.get(box_key, 0))
                frame_boxes.append(box)

        _poses[pose_id] = {
            "name":          str(p.get("name", "")),
            "dir":           int(p.get("dir", 1)),
            "mvtype":        int(p.get("mvtype", MV_STAND)),
            "y_radius":      int(p.get("y_radius", 16)),
            "y_offset":      int(p.get("y_offset", 0)),
            "collision_x":   int(p.get("collision_x", 0)),
            "collision_width": int(p.get("collision_width", _profile.collision_width if _profile != null else 24)),
            "hurtbox_x":     int(p.get("hurtbox_x", 0)),
            "hurtbox_y":     int(p.get("hurtbox_y", -int(p.get("y_radius", 16)))),
            "hurtbox_w":     int(p.get("hurtbox_w", int(p.get("collision_width", _profile.collision_width if _profile != null else 24)))),
            "hurtbox_h":     int(p.get("hurtbox_h", int(p.get("y_radius", 16)) * 2)),
            "weapon_anchor_x": int(p.get("weapon_anchor_x", 0)),
            "weapon_anchor_y": int(p.get("weapon_anchor_y", -int(p.get("y_radius", 16)) + int(SHOULDER_Y))),
            "timing":        timing,
            "anim_speed":    maxf(0.05, float(p.get("anim_speed", 1.0))),
            "frame_boxes":   frame_boxes,
            "loop_from":     int(p.get("loop_from", -1)),
            "transition_to": int(p.get("transition_to", -1)),
        }

    print("MvPlayer: loaded %d poses from %s" % [_poses.size(), path])


func _load_frames(path: String, pack: MvPackRef = null) -> void:
    # Optional per-pack asset. See _load_poses.
    if not FileAccess.file_exists(path):
        return
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("MvPlayer: failed to open %s" % path)
        return
    var text := f.get_as_text()
    f.close()

    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("MvPlayer: failed to parse %s" % path)
        return

    var data: Dictionary = parsed
    if not data.has("frames"):
        return
    _frame_width = int(data.get("frame_width", 50))
    _frame_height = int(data.get("frame_height", 44))
    _sheet_cols = int(data.get("sheet_cols", 10))
    _sheet_defs = _normalize_sheet_defs(data.get("sheets", []))
    _load_sheet_textures(pack)
    _rebuild_layer_sprites()

    for item in data["frames"]:
        var fr: Dictionary = _normalize_frame_entry(item)
        var pose := int(fr.get("pose", 0))
        if not _frames.has(pose):
            _frames[pose] = []
        (_frames[pose] as Array).append(fr)

    print("MvPlayer: loaded frame map (%d poses) from %s" % [_frames.size(), path])


# ===== Pose management =====

func _set_pose(p: int) -> void:
    if p == _pose and _anim_idx == 0:
        return
    if not _poses.has(p):
        return
    var anim_owner: int = _resolved_animation_owner(p)
    if anim_owner < 0:
        return

    if _knockdown_active:
        var new_mv: int = int((_poses[p] as Dictionary).get("mvtype", -999))
        if new_mv != MV_KNOCKDOWN and new_mv != MV_STAND_UP:
            _release_knockdown()

    _pose = p
    var info: Dictionary = _poses[p]
    _right = _pose_dir_value(info) > 0

    _apply_pose_sprite_flip(p)

    _set_collision(int(info["y_radius"]), _collision_width_for_pose(info), _collision_x_for_pose(info))
    _set_sprite_offset_all(_sprite_offset_for_pose(info, info))
    _apply_pose_hurtbox(info)

    _anim_idx = 0
    _anim_ticks = 0.0
    var anim_info: Dictionary = _poses[anim_owner]
    var timing: Array = anim_info["timing"]
    var frames: Array = _frames[anim_owner]
    _anim_count = min(timing.size(), frames.size())
    _show_frame()


# Try a preferred pose; fall back to alternate if the pack doesn't define it.
# Lets packs with minimal pose coverage still face the correct direction
# instead of freezing on one pose forever.
func _try_set_pose(preferred: int, fallback: int = -1) -> bool:
    var melee_locked_pose: int = int(_authored_melee_attack.get("pose", -1))
    if melee_locked_pose >= 0 and preferred != melee_locked_pose and fallback != melee_locked_pose:
        return false
    if _poses.has(preferred) and _resolved_animation_owner(preferred) >= 0:
        _set_pose(preferred)
        return true
    if fallback >= 0 and _poses.has(fallback) and _resolved_animation_owner(fallback) >= 0:
        _set_pose(fallback)
        return true
    return false


func _find_pose_id_by_name(pose_name: String) -> int:
    if pose_name.is_empty():
        return -1
    for pose_id_v in _poses.keys():
        var pose_id: int = int(pose_id_v)
        var info: Dictionary = _poses[pose_id]
        if str(info.get("name", "")) == pose_name:
            return pose_id
    return -1


func _pose_dir_value(info: Dictionary) -> int:
    var pose_name: String = str(info.get("name", ""))
    if pose_name.ends_with("_left"):
        return -1
    if pose_name.ends_with("_right"):
        return 1
    var raw_dir: int = int(info.get("dir", 1))
    return -1 if raw_dir < 0 else 1


func _mirror_source_pose_id(pose_id: int) -> int:
    if not _poses.has(pose_id):
        return -1
    var info: Dictionary = _poses[pose_id]
    if _pose_dir_value(info) >= 0:
        return -1
    var pose_name: String = str(info.get("name", ""))
    if pose_name.ends_with("_left"):
        var partner_id: int = _find_pose_id_by_name(pose_name.trim_suffix("_left") + "_right")
        if partner_id >= 0:
            return partner_id
    var mvtype: int = int(info.get("mvtype", MV_STAND))
    for other_id_v in _poses.keys():
        var other_id: int = int(other_id_v)
        if other_id == pose_id:
            continue
        var other: Dictionary = _poses[other_id]
        if _pose_dir_value(other) > 0 and int(other.get("mvtype", -999)) == mvtype:
            return other_id
    return -1


func _matching_pose_id_for_dir(pose_id: int, desired_dir: int) -> int:
    if not _poses.has(pose_id):
        return -1
    var info: Dictionary = _poses[pose_id]
    if _pose_dir_value(info) == desired_dir:
        return pose_id
    var pose_name: String = str(info.get("name", ""))
    if desired_dir < 0 and pose_name.ends_with("_right"):
        var left_id: int = _find_pose_id_by_name(pose_name.trim_suffix("_right") + "_left")
        if left_id >= 0:
            return left_id
    elif desired_dir > 0 and pose_name.ends_with("_left"):
        var right_id: int = _find_pose_id_by_name(pose_name.trim_suffix("_left") + "_right")
        if right_id >= 0:
            return right_id
    var mvtype: int = int(info.get("mvtype", MV_STAND))
    for other_id_v in _poses.keys():
        var other_id: int = int(other_id_v)
        var other: Dictionary = _poses[other_id]
        if _pose_dir_value(other) == desired_dir and int(other.get("mvtype", -999)) == mvtype:
            return other_id
    return -1


func _resolved_animation_owner(pose_id: int) -> int:
    var local_seq: Array = (_frames[pose_id] as Array) if _frames.has(pose_id) else []
    if not local_seq.is_empty() and not (_pose_dir_value(_poses.get(pose_id, {})) < 0 and _frame_sequence_is_legacy_placeholder(local_seq)):
        return pose_id
    var mirror_id: int = _mirror_source_pose_id(pose_id)
    if mirror_id >= 0 and _frames.has(mirror_id) and not (_frames[mirror_id] as Array).is_empty():
        return mirror_id
    return -1


func _pose_uses_mirrored_fallback(pose_id: int) -> bool:
    if not _poses.has(pose_id):
        return false
    var owner_id: int = _resolved_animation_owner(pose_id)
    if owner_id < 0 or owner_id == pose_id:
        return false
    var pose_info: Dictionary = _poses[pose_id]
    return _pose_dir_value(pose_info) < 0


func _frame_sequence_is_legacy_placeholder(seq: Array) -> bool:
    if seq.is_empty():
        return false
    for entry_v in seq:
        var entry: Dictionary = _normalize_frame_entry(entry_v)
        var layers_v: Variant = entry.get("layers", [])
        if typeof(layers_v) != TYPE_ARRAY:
            return false
        var layers: Array = layers_v
        if layers.size() != 1:
            return false
        var layer: Dictionary = layers[0] if typeof(layers[0]) == TYPE_DICTIONARY else {}
        if str(layer.get("sheet", "base")).strip_edges() != "base":
            return false
        if int(layer.get("index", -1)) != 0:
            return false
    return true


func _apply_pose_sprite_flip(pose_id: int) -> void:
    _set_sprite_flip_all(_pose_uses_mirrored_fallback(pose_id))


func _display_frame_rotation(pose_id: int, rotation_deg: float) -> float:
    return -rotation_deg if _pose_uses_mirrored_fallback(pose_id) else rotation_deg


func _resolved_attack_pose_id(pose_id: int) -> int:
    if pose_id < 0 or not _poses.has(pose_id):
        return pose_id
    var desired_dir: int = 1 if _right else -1
    var matched_id: int = _matching_pose_id_for_dir(pose_id, desired_dir)
    if matched_id >= 0:
        return matched_id
    return pose_id


func _apply_attack_facing_from_aim(aim: Vector2) -> void:
    if absf(aim.x) <= 0.001:
        return
    var desired_right: bool = aim.x > 0.0
    if desired_right == _right:
        return
    _right = desired_right
    var matched_pose: int = _matching_pose_id_for_dir(_pose, 1 if _right else -1)
    if matched_pose >= 0 and matched_pose != _pose:
        _set_pose(matched_pose)
        return
    _apply_pose_sprite_flip(_pose)


func _set_collision(yr: int, width: float = -1.0, offset_x: float = 0.0) -> void:
    if width < 0.0:
        @warning_ignore("incompatible_ternary")
        width = _profile.collision_width if _profile != null else 24.0
    if yr == _yr and is_equal_approx(_rect.size.x, width) and is_equal_approx(_col.position.x, offset_x):
        return
    _yr = yr
    _rect.size = Vector2(width, yr * 2)
    _col.position = Vector2(offset_x, -yr)


func _collision_width_for_pose(info: Dictionary) -> float:
    return maxf(1.0, float(int(info.get("collision_width", _profile.collision_width if _profile != null else 24))))


func _collision_x_for_pose(info: Dictionary) -> float:
    return float(int(info.get("collision_x", 0)))


func _default_weapon_anchor(info: Dictionary) -> Vector2:
    return Vector2(0.0, -float(int(info.get("y_radius", _yr))) + SHOULDER_Y)


func _weapon_anchor_local_for_pose(pose_id: int) -> Vector2:
    var info: Dictionary = _poses.get(pose_id, {})
    if info.is_empty():
        return Vector2(0.0, -float(_yr) + SHOULDER_Y)

    var default_anchor := _default_weapon_anchor(info)
    var local_anchor := Vector2(
        float(int(info.get("weapon_anchor_x", 0))),
        float(int(info.get("weapon_anchor_y", int(default_anchor.y))))
    )

    if not _pose_uses_mirrored_fallback(pose_id):
        return local_anchor

    var anchor_is_default := int(local_anchor.x) == 0 and int(local_anchor.y) == int(default_anchor.y)
    if not anchor_is_default:
        return local_anchor

    var owner_id: int = _resolved_animation_owner(pose_id)
    if owner_id < 0 or owner_id == pose_id or not _poses.has(owner_id):
        return local_anchor

    var owner_info: Dictionary = _poses[owner_id]
    var owner_default := _default_weapon_anchor(owner_info)
    var owner_anchor := Vector2(
        float(int(owner_info.get("weapon_anchor_x", 0))),
        float(int(owner_info.get("weapon_anchor_y", int(owner_default.y))))
    )
    return Vector2(-owner_anchor.x, owner_anchor.y)


func _pose_has_custom_weapon_anchor(pose_id: int) -> bool:
    if not _poses.has(pose_id):
        return false
    var info: Dictionary = _poses[pose_id]
    var default_anchor := _default_weapon_anchor(info)
    var anchor := _weapon_anchor_local_for_pose(pose_id)
    return int(anchor.x) != 0 or int(anchor.y) != int(default_anchor.y)


func _weapon_anchor_local() -> Vector2:
    return _weapon_anchor_local_for_pose(_pose)


func _apply_pose_hurtbox(info: Dictionary) -> void:
    if _hurtbox_col == null or _hurtbox_rect == null:
        return
    var width := maxf(1.0, float(int(info.get("hurtbox_w", _collision_width_for_pose(info)))))
    var height := maxf(1.0, float(int(info.get("hurtbox_h", int(info.get("y_radius", _yr)) * 2))))
    _hurtbox_rect.size = Vector2(width, height)
    _hurtbox_col.position = Vector2(
        float(int(info.get("hurtbox_x", 0))),
        float(int(info.get("hurtbox_y", -int(info.get("y_radius", _yr)))))
    )


func _hurtbox_world_center() -> Vector2:
    if _hurtbox_col == null:
        return global_position + Vector2(0.0, -float(_yr))
    return global_position + _hurtbox_col.position


func combat_origin() -> Vector2:
    return _hurtbox_world_center()


func hurtbox_world_rect() -> Rect2:
    var center := _hurtbox_world_center()
    var half_w := (_hurtbox_rect.size.x * 0.5) if _hurtbox_rect != null else (_rect.size.x * 0.5 if _rect != null else 5.0)
    var half_h := (_hurtbox_rect.size.y * 0.5) if _hurtbox_rect != null else float(_yr)
    return Rect2(center - Vector2(half_w, half_h), Vector2(half_w * 2.0, half_h * 2.0))


func hurtbox_intersects_rect(world_rect: Rect2) -> bool:
    return hurtbox_world_rect().intersects(world_rect)


func _hurtbox_sample_points() -> Array:
    var center := _hurtbox_world_center()
    var half_w := (_hurtbox_rect.size.x * 0.5) if _hurtbox_rect != null else (_rect.size.x * 0.5 if _rect != null else 5.0)
    var half_h := (_hurtbox_rect.size.y * 0.5) if _hurtbox_rect != null else float(_yr)
    return [
        center,
        center + Vector2(-half_w, 0.0),
        center + Vector2(half_w, 0.0),
        center + Vector2(0.0, -half_h),
        center + Vector2(0.0, half_h),
        center + Vector2(-half_w, half_h),
        center + Vector2(half_w, half_h),
    ]


func _foot_contact_points() -> Array:
    var half_w := (_rect.size.x * 0.5) if _rect != null else 6.0
    var foot_y := global_position.y + 1.0
    return [
        Vector2(global_position.x, foot_y),
        Vector2(global_position.x - half_w * 0.7, foot_y),
        Vector2(global_position.x + half_w * 0.7, foot_y),
    ]


func _step_up_slope_ahead(move_dir: float) -> void:
    if move_dir == 0.0:
        return
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null or not room_mgr.has_method("try_get_slope_floor"):
        return
    var half_w := (_rect.size.x * 0.5) if _rect != null else 6.0
    var foot_y := global_position.y
    var probe_points := [
        global_position.x + signf(move_dir) * (half_w + 1.0),
        global_position.x + signf(move_dir) * (half_w + 4.0),
    ]
    var best_floor_y := INF
    for probe_x_v in probe_points:
        var probe_x: float = float(probe_x_v)
        var floor_y := _find_reachable_slope_floor(room_mgr, probe_x, foot_y)
        if floor_y < best_floor_y:
            best_floor_y = floor_y
    if is_inf(best_floor_y):
        return
    global_position.y = best_floor_y
    if velocity.y > 0.0:
        velocity.y = 0.0


func _find_reachable_slope_floor(room_mgr: Node, probe_x: float, foot_y: float) -> float:
    var best_rise := INF
    var best_floor_y := INF
    for step in range(int(SLOPE_STEP_UP_MAX) + 2):
        var sample_y := foot_y - float(step)
        var slope_v: Variant = room_mgr.call("try_get_slope_floor", probe_x, sample_y)
        if typeof(slope_v) != TYPE_DICTIONARY:
            continue
        var slope: Dictionary = slope_v
        if not bool(slope.get("hit", false)):
            continue
        var floor_y := float(slope.get("floor_y", foot_y))
        var rise := foot_y - floor_y
        if rise < 0.5 or rise > SLOPE_STEP_UP_MAX:
            continue
        if rise < best_rise:
            best_rise = rise
            best_floor_y = floor_y
    return best_floor_y


func _show_frame() -> void:
    var anim_owner: int = _resolved_animation_owner(_pose)
    if anim_owner < 0 or not _frames.has(anim_owner):
        return
    _apply_pose_sprite_flip(_pose)
    var fl: Array = _frames[anim_owner]
    if _anim_idx < fl.size():
        for spr_v in _sprite_layers.values():
            var hidden_sprite: Sprite2D = spr_v
            if is_instance_valid(hidden_sprite):
                hidden_sprite.visible = false
                hidden_sprite.rotation_degrees = 0.0
        var frame_entry: Dictionary = _normalize_frame_entry(fl[_anim_idx])
        var frame_rotation: float = float(frame_entry.get("rotation_deg", 0.0))
        var display_rotation: float = _display_frame_rotation(_pose, frame_rotation)
        var layers_v: Variant = frame_entry.get("layers", [])
        if typeof(layers_v) == TYPE_ARRAY:
            var layers: Array = layers_v
            for layer_v in layers:
                if typeof(layer_v) != TYPE_DICTIONARY:
                    continue
                var layer: Dictionary = layer_v
                var sheet_id: String = str(layer.get("sheet", "base")).strip_edges()
                var spr: Sprite2D = _sprite_layers.get(sheet_id, null) as Sprite2D
                if spr == null:
                    continue
                var tex: Texture2D = _sheet_textures.get(sheet_id, null) as Texture2D
                if tex == null:
                    continue
                spr.texture = tex
                spr.hframes = maxi(1, _sheet_cols)
                spr.vframes = maxi(1, int(ceil(tex.get_size().y / float(maxi(1, _frame_height)))))
                spr.frame = int(layer.get("index", 0))
                spr.rotation_degrees = display_rotation
                spr.visible = true
        _apply_frame_box_overrides(_pose, _anim_idx)


func _apply_frame_box_overrides(pose_id: int, frame_idx: int) -> void:
    if not _poses.has(pose_id):
        return
    var info: Dictionary = _poses[pose_id]
    var effective: Dictionary = info.duplicate(true)
    var frame_boxes_v: Variant = info.get("frame_boxes", [])
    if typeof(frame_boxes_v) == TYPE_ARRAY:
        var frame_boxes: Array = frame_boxes_v
        if frame_idx >= 0 and frame_idx < frame_boxes.size() and typeof(frame_boxes[frame_idx]) == TYPE_DICTIONARY:
            var box: Dictionary = frame_boxes[frame_idx]
            for key in ["y_radius", "y_offset", "collision_x", "collision_width", "hurtbox_x", "hurtbox_y", "hurtbox_w", "hurtbox_h"]:
                if box.has(key):
                    effective[key] = int(box.get(key, effective.get(key, 0)))
    _set_collision(int(effective["y_radius"]), _collision_width_for_pose(effective), _collision_x_for_pose(effective))
    # Frame-box collision overrides should not drag the art around; only the
    # authored sprite offset should move the sprite baseline.
    _set_sprite_offset_all(_sprite_offset_for_pose(info, effective))
    _apply_pose_hurtbox(effective)


func _is_transition() -> bool:
    if not _poses.has(_pose):
        return false
    var pi: Dictionary = _poses[_pose]
    var mv: int = int(pi["mvtype"])
    return mv == MV_TRANS or mv == MV_TURN or mv == MV_TURN_AIR or mv == MV_TURN_FALL \
        or (int(pi["transition_to"]) >= 0 and int(pi["loop_from"]) < 0)


func _is_airborne() -> bool:
    if not _poses.has(_pose):
        return false
    var mv: int = int((_poses[_pose] as Dictionary)["mvtype"])
    return mv == MV_JUMP or mv == MV_SPIN or mv == MV_FALL \
        or mv == MV_WALLJUMP or mv == MV_TURN_AIR or mv == MV_TURN_FALL


# ===== Main loop =====

func _process(delta: float) -> void:
    # Animation ticks in _process, not _physics_process, so it keeps running
    # even while the simulation is paused (editor live-edit). Physics state
    # changes only fire from _physics_process and are correctly frozen there.
    if MvGame.simulation_paused:
        _advance_animation(delta)


func _physics_process(delta: float) -> void:
    var dt := delta

    # Editor live-edit pause: physics frozen, input ignored, but _process
    # still ticks animations above so the player doesn't look dead.
    if MvGame.simulation_paused:
        velocity = Vector2.ZERO
        return

    # Grapple swing overrides all normal movement physics. The pendulum
    # integrator drives position; release with jump or grapple button.
    if _grapple_swinging:
        _tick_grapple_swing(dt)
        if Input.is_action_just_pressed("jump"):
            _end_grapple_swing(true)
        if _invuln_timer > 0.0:
            _invuln_timer -= dt
        return

    # Shinespark dash overrides all normal physics with a constant velocity
    # until tile collision or timer expiry, whichever comes first. Impact
    # applies a small self-damage payload (SM's "ouch on land" behaviour).
    if _shine_spark_active:
        _tick_shine_spark(dt)
        return

    if _script_move_active:
        position = position.move_toward(_script_move_target, _script_move_speed * dt)
        velocity = Vector2.ZERO
        _advance_animation(dt)
        if position.distance_to(_script_move_target) <= 0.5:
            position = _script_move_target
            _script_move_active = false
            set_locked(false)
            scripted_move_finished.emit()
        return

    if _dodge_roll_timer > 0.0:
        _tick_dodge_roll(dt)
        return

    var vel := velocity

    var on_floor := is_on_floor()
    var jump_held := Input.is_action_pressed("jump")
    var jump_pressed := Input.is_action_just_pressed("jump")
    var down_pressed := Input.is_action_just_pressed("crouch")
    var dodge_pressed := Input.is_action_just_pressed("dodge_roll")
    var active_ranged_attack := _active_ranged_attack()
    var has_authored_ranged_attack := not active_ranged_attack.is_empty()
    var authored_hold_behavior := _active_ranged_attack_hold_behavior(active_ranged_attack)
    var authored_full_auto := authored_hold_behavior == "full_auto"
    var secondary_held := Input.is_action_pressed("fire_secondary") and not _melee_input_locked and not _locked
    var ranged_held := Input.is_action_pressed("ranged_attack") and not secondary_held and not _melee_input_locked and not _locked
    if _melee_input_locked or _locked:
        jump_held = false
        jump_pressed = false
        down_pressed = false
        dodge_pressed = false

    # Input lockouts: knockback from damage, door-entry walk-in. While
    # either is active we ignore movement input and force horizontal
    # velocity (knockback keeps its impulse; door-entry gently pushes
    # inward). Jump/down/shoot all stay live so the player isn't completely
    # frozen — matches SM's "reeling but still reactive" state.
    var input_locked := _locked \
        or _knockback_timer > 0.0 \
        or _door_lock_timer > 0.0 \
        or _melee_input_locked \
        or (has_authored_ranged_attack and authored_full_auto and ranged_held)

    var dir := 0.0
    if not input_locked:
        if Input.is_action_pressed("move_left"):
            dir -= 1.0
        if Input.is_action_pressed("move_right"):
            dir += 1.0
    elif _door_lock_timer > 0.0:
        dir = float(_door_lock_dir)
    # During knockback, dir stays 0 so the air/ground friction code doesn't
    # fight the impulse — the velocity we set in take_damage carries through
    # move_and_slide naturally.

    if dodge_pressed and _can_start_dodge_roll(on_floor):
        _start_dodge_roll(dir)
        _tick_dodge_roll(dt)
        return

    # ---- Speed Booster charge ----
    _tick_speed_booster_charge(dir, vel.x, on_floor, dt)

    # Shinespark stash: holding crouch while shining converts the active
    # speed boost into a stored "primed" state. The stash ticks down over
    # shinespark.stash_seconds; if it expires the player just loses it.
    if _shine_active and down_pressed and PlayerInventory.has_ability("shinespark"):
        _shine_stash_timer = MvAbilityParams.param_float("shinespark", "stash_seconds", DEF_SHINE_STASH_SEC)
        _shine_active = false
        _speed_charge_timer = 0.0
        _speed_charge_dir = 0
        vel.x = 0.0
    if _shine_stash_timer > 0.0:
        _shine_stash_timer -= dt
        if _shine_stash_timer <= 0.0:
            _shine_stash_timer = 0.0
        # Jump while stashed → launch the spark.
        if _shine_stash_timer > 0.0 and jump_pressed:
            _launch_shine_spark()
            return

    # ---- Gravity ----
    if not on_floor:
        vel.y += _profile.gravity * dt
        if vel.y > _profile.max_fall:
            vel.y = _profile.max_fall

    # ---- Phase 7: reset air-jump count on land ----
    if on_floor and not _was_on_floor:
        _reset_air_jumps()

    # ---- Landing ----
    if on_floor and not _was_on_floor and _poses.has(_pose):
        var pi_land: Dictionary = _poses[_pose]
        var mv_land: int = int(pi_land["mvtype"])
        if mv_land == MV_SPIN:
            _try_set_pose(166 if _right else 167, 1 if _right else 2)
        elif mv_land == MV_JUMP or mv_land == MV_FALL or mv_land == MV_WALLJUMP \
                or mv_land == MV_TURN_AIR or mv_land == MV_TURN_FALL:
            _try_set_pose(164 if _right else 165, 1 if _right else 2)

    # ---- Became airborne (walked off edge) ----
    if not on_floor and _was_on_floor and _poses.has(_pose):
        var pi_air: Dictionary = _poses[_pose]
        var mv_air: int = int(pi_air["mvtype"])
        if mv_air != MV_JUMP and mv_air != MV_SPIN and mv_air != MV_FALL \
                and mv_air != MV_WALLJUMP and mv_air != MV_TRANS and mv_air != MV_TURN_AIR:
            _try_set_pose(41 if _right else 42, 1 if _right else 2)  # fall (ROM $29/$2A)

    # Ground transition poses (turn / land / stand-up) should stay
    # jump-cancellable so they don't feel like hard input locks.
    if on_floor and jump_pressed and _poses.has(_pose) and _is_transition():
        var transition_pi: Dictionary = _poses[_pose]
        var transition_mv: int = int(transition_pi.get("mvtype", MV_STAND))
        var running_jump := transition_mv == MV_TURN \
            or (absf(vel.x) >= 10.0 and transition_mv != MV_CROUCH)
        vel.y = -_jump_speed_with_run_bonus(vel.x) if running_jump else -_effective_jump_speed()
        _try_set_pose(75 if _right else 76)

    # ---- State transitions ----
    # When the pack lacks jump/fall/run poses, the "became airborne"
    # fallback above lands the player in stand pose (1/2). Without this
    # synthetic air-state routing, an airborne MV_STAND would hit the
    # ground-state branch below, which has no on_floor guard, so every jump
    # press would stack another vel.y kick → infinite jump. Route airborne
    # ground-state poses through MV_FALL so air jumps are gated on the
    # usual abilities.
    if not _is_transition() and _poses.has(_pose):
        var pi: Dictionary = _poses[_pose]
        var eff_mv: int = int(pi["mvtype"])
        if not on_floor and (eff_mv == MV_STAND or eff_mv == MV_RUN or eff_mv == MV_CROUCH):
            eff_mv = MV_FALL

        if eff_mv == MV_STAND and int(pi["transition_to"]) < 0:
            if _pose == 0:
                _set_pose(1)
            elif dir != 0.0 and (dir > 0.0) != _right:
                # Turn; fall back to direct opposite stand so the player
                # at least faces the correct direction when packs don't
                # define turn poses.
                _try_set_pose(37 if _right else 38, 2 if _right else 1)
            elif dir != 0.0:
                _try_set_pose(9 if _right else 10)   # run (may not exist)
            elif down_pressed:
                _try_set_pose(53 if _right else 54)  # crouch trans
            elif jump_pressed:
                vel.y = -_jump_speed_with_run_bonus(vel.x)
                _try_set_pose(75 if _right else 76)  # jump trans
        elif eff_mv == MV_RUN:
            if dir != 0.0 and (dir > 0.0) != _right:
                _try_set_pose(37 if _right else 38, 10 if _right else 9)
            elif dir == 0.0 and absf(vel.x) < 10.0:
                _try_set_pose(1 if _right else 2)
            elif jump_pressed:
                vel.y = -_jump_speed_with_run_bonus(vel.x)
                _try_set_pose(75 if _right else 76)
            elif down_pressed:
                _try_set_pose(53 if _right else 54)
        elif eff_mv == MV_CROUCH:
            if dir != 0.0 and (dir > 0.0) != _right:
                _try_set_pose(67 if _right else 68)
            elif jump_pressed:
                vel.y = -_effective_jump_speed()
                _try_set_pose(75 if _right else 76)
            elif Input.is_action_just_pressed("aim_up"):
                _try_set_pose(59 if _right else 60)
            elif dir != 0.0:
                _try_set_pose(1 if _right else 2)
        elif eff_mv == MV_JUMP:
            if dir != 0.0 and (dir > 0.0) != _right:
                _try_set_pose(47 if _right else 48)
            if vel.y > 0.0 and not on_floor:
                _try_set_pose(41 if _right else 42)
            vel = _try_air_jump_or_wall_jump(jump_pressed, vel)
        elif eff_mv == MV_SPIN:
            if dir != 0.0:
                _right = dir > 0.0
            vel = _try_air_jump_or_wall_jump(jump_pressed, vel)
        elif eff_mv == MV_FALL:
            if dir != 0.0 and (dir > 0.0) != _right:
                _try_set_pose(135 if _right else 136)
            vel = _try_air_jump_or_wall_jump(jump_pressed, vel)

    # ---- Physics ----
    # Effective top speed factors in Speed Booster shine. While shining,
    # RunMax is multiplied by the ability's boost_speed_multiplier (default
    # 1.6x). The shine is preserved through jumps so the cap stays elevated
    # mid-air too.
    var run_max := _profile.run_max
    if _shine_active:
        run_max *= MvAbilityParams.param_float("speed_booster", "boost_speed_multiplier", DEF_SPEED_BOOSTER_BOOST_MULT)
    # Status effect speed multiplier (e.g. slow from tar pit spikes).
    run_max *= get_effect_speed_mult()

    if _poses.has(_pose):
        var cur_pi: Dictionary = _poses[_pose]
        var cur_mv: int = int(cur_pi["mvtype"])
        var ground_transition_control := on_floor and cur_mv != MV_CROUCH and _is_transition()
        var ground_accel_scale := 0.62 if ground_transition_control else 1.0
        var ground_decel_scale := 0.38 if ground_transition_control else 1.0
        if on_floor and cur_mv != MV_CROUCH:
            if dir != 0.0:
                if ground_transition_control and absf(vel.x) > 0.01 and signf(vel.x) != signf(dir):
                    vel.x = move_toward(vel.x, 0.0, _profile.run_decel * dt * 0.55)
                vel.x += dir * _profile.run_accel * dt * ground_accel_scale
                vel.x = clampf(vel.x, -run_max, run_max)
            else:
                vel.x = move_toward(vel.x, 0.0, _profile.run_decel * dt * ground_decel_scale)
        elif not on_floor:
            if dir != 0.0 and not _is_transition():
                vel.x += dir * _profile.air_accel * dt
                if absf(vel.x) > run_max:
                    vel.x = signf(vel.x) * run_max
            else:
                vel.x = move_toward(vel.x, 0.0, _profile.air_decel * dt)
        else:  # crouching
            vel.x = move_toward(vel.x, 0.0, _profile.run_decel * dt)

    # Variable jump cut (ROM $90:8FE4): releasing jump while rising clamps
    # the remaining upward velocity. SM only kills the portion above a floor
    # threshold so tiny hops (already slowing through the cut point) aren't
    # clipped any further — otherwise a half-height hop and a tap-jump feel
    # indistinguishable. The 60 px/s threshold matches 1 px/SNES-frame, the
    # value the ROM uses in its compare.
    if not on_floor and vel.y < -60.0 and not jump_held and _was_jump_held:
        vel.y = -60.0

    _was_jump_held = jump_held
    _was_on_floor = on_floor
    if _invuln_timer > 0.0:
        _invuln_timer -= dt
    if _wall_jump_cooldown > 0.0:
        _wall_jump_cooldown -= dt
    if _knockback_timer > 0.0:
        _knockback_timer -= dt
    if _door_lock_timer > 0.0:
        _door_lock_timer -= dt

    velocity = vel
    if (_was_on_floor or on_floor) and dir != 0.0 and vel.y >= 0.0:
        _step_up_slope_ahead(dir)
        vel = velocity
    if (_was_on_floor or on_floor) and vel.y >= 0.0 and not jump_pressed:
        apply_floor_snap()
    move_and_slide()

    if is_on_floor():
        var room_mgr_after_move: Node = MvGame.room_manager
        if room_mgr_after_move != null and room_mgr_after_move.has_method("notify_crumble_contacts"):
            room_mgr_after_move.notify_crumble_contacts(_foot_contact_points())

    # ---- Spike hazard detection ----
    _check_spike_overlap(dt)

    # ---- Status effect tick ----
    _process_effects(dt)

    # ---- Shooting ($90:B887) ----
    if _shoot_cooldown > 0.0:
        _shoot_cooldown -= dt
    var melee_pressed := Input.is_action_just_pressed("melee_attack") and not _locked
    var ranged_pressed := Input.is_action_just_pressed("ranged_attack") and not secondary_held and not _melee_input_locked and not _locked
    var secondary_pressed := Input.is_action_just_pressed("fire_secondary") and not _melee_input_locked and not _locked
    var parry_pressed := InputMap.has_action("parry") and Input.is_action_just_pressed("parry") and not _melee_input_locked and not _locked
    var authored_charge := authored_hold_behavior == "charge_release"
    var charge_feedback_active := authored_charge or not has_authored_ranged_attack

    if melee_pressed:
        _try_melee_attack()

    if parry_pressed:
        _try_parry()

    if secondary_pressed:
        _toggle_secondary_mode()

    if has_authored_ranged_attack:
        if authored_full_auto:
            if ranged_held:
                _apply_full_auto_hold_pose(active_ranged_attack)
                _try_ranged_attack()
        elif ranged_pressed:
            _try_ranged_attack()
        if authored_charge and ranged_held:
            _apply_ranged_charge_hold_pose(active_ranged_attack)
    elif ranged_pressed:
        _try_ranged_attack()

    var released_charge_timer: float = _beam_charge_timer
    if charge_feedback_active and ranged_held:
        _beam_charge_timer += dt
        released_charge_timer = _beam_charge_timer
    else:
        released_charge_timer = _beam_charge_timer

    # Sprite modulate priority: Speed Booster shine (orange) wins over
    # charged beam (cyan) wins over neutral. Both states are visually
    # important so neither can quietly override the other.
    if _sprite != null:
        var target_color: Color = Color.WHITE
        if _shine_active:
            target_color = Color(1.0, 0.7, 0.3, 1.0)    # shine orange
        elif charge_feedback_active and _beam_charge_timer >= _ranged_charge_threshold_seconds():
            target_color = Color(0.65, 1.0, 1.0, 1.0)   # charge cyan
        if _sprite.modulate != target_color:
            _set_sprite_modulate_all(target_color)
    _update_charge_fx(ranged_held, dt)

    # Fire on release if a charged round was primed. Held → released
    # transition below the threshold just cancels the charge without firing
    # anything extra.
    if _was_shoot_held and not ranged_held:
        if authored_charge:
            if released_charge_timer >= _ranged_charge_threshold_seconds():
                _try_fire_authored_ranged_charged()
            elif released_charge_timer > 0.0:
                _try_ranged_attack()
        elif not has_authored_ranged_attack and released_charge_timer >= _ranged_charge_threshold_seconds():
            _try_fire_charged()
        _beam_charge_timer = 0.0
    elif not charge_feedback_active:
        _beam_charge_timer = 0.0
    _was_shoot_held = ranged_held

    if has_authored_ranged_attack and authored_full_auto and not ranged_held:
        _restore_after_full_auto_hold(on_floor, dir, vel)

    # ---- Grapple ----
    if not _melee_input_locked and not _locked and Input.is_action_just_pressed("grapple"):
        if _grapple_swinging:
            _end_grapple_swing(true)
        else:
            _try_grapple()

    if _bomb_cooldown > 0.0:
        _bomb_cooldown -= dt

    _advance_animation(dt)
    _tick_authored_melee_attack()
    if _combo_grace_timer > 0.0:
        _combo_grace_timer -= dt
        if _combo_grace_timer <= 0.0:
            _combo_grace_timer = 0.0
            _combo_grace_next_id = ""
    _check_door_edges()


# ===== External control (scripts, cutscenes, elevator sequences) =====

func set_locked(locked: bool) -> void:
    _locked = locked


func is_locked() -> bool:
    return _locked


func set_scripted_facing(dir: float) -> void:
    if dir == 0.0:
        return
    _right = dir > 0.0
    var matched_pose: int = _matching_pose_id_for_dir(_pose, 1 if _right else -1)
    if matched_pose >= 0 and matched_pose != _pose:
        _set_pose(matched_pose)
        return
    _apply_pose_sprite_flip(_pose)


func _apply_spawn_facing(direction: String) -> void:
    var trimmed: String = direction.strip_edges().to_lower()
    match trimmed:
        "left":
            set_scripted_facing(-1.0)
        "right":
            set_scripted_facing(1.0)
        _:
            pass


func begin_scripted_move(target_pos: Vector2, speed: float = 64.0) -> void:
    _script_move_target = target_pos
    _script_move_speed = maxf(1.0, speed)
    _script_move_active = true
    set_locked(true)


func play_scripted_animation(anim_name: String, loop: bool = true, speed_scale: float = 1.0) -> void:
    var pose_id := _resolve_script_pose_id(anim_name)
    if pose_id < 0:
        return
    _script_anim_active = true
    _script_anim_pose_id = pose_id
    _script_anim_loop = loop
    _script_anim_speed_scale = maxf(0.05, speed_scale)
    _script_anim_name = anim_name.strip_edges()
    if pose_id != _pose:
        _set_pose(pose_id)
    else:
        _anim_idx = 0
        _anim_ticks = 0.0
        _show_frame()


func stop_scripted_animation() -> void:
    _script_anim_active = false
    _script_anim_pose_id = -1
    _script_anim_speed_scale = 1.0
    _script_anim_name = ""


func is_scripted_move_active() -> bool:
    return _script_move_active


func is_scripted_animation_active() -> bool:
    return _script_anim_active


func current_scripted_animation_name() -> String:
    return _script_anim_name


func _resolve_script_pose_id(anim_name: String) -> int:
    var trimmed := anim_name.strip_edges()
    if trimmed.is_empty():
        return -1
    var direct := _find_pose_id_by_name(trimmed)
    if direct >= 0:
        return direct
    var with_dir := "%s_%s" % [trimmed, "right" if _right else "left"]
    direct = _find_pose_id_by_name(with_dir)
    if direct >= 0:
        return direct
    var desired_dir := 1 if _right else -1
    for pose_id_v in _poses.keys():
        var pose_id := int(pose_id_v)
        var info: Dictionary = _poses[pose_id]
        var pose_name := str(info.get("name", ""))
        if pose_name.contains(trimmed) and int(info.get("dir", desired_dir)) == desired_dir:
            return pose_id
    return -1


func _can_start_dodge_roll(on_floor: bool) -> bool:
    return on_floor \
        and not _locked \
        and not _grapple_swinging \
        and not _shine_spark_active \
        and _knockback_timer <= 0.0 \
        and _door_lock_timer <= 0.0 \
        and _dodge_roll_timer <= 0.0


func _start_dodge_roll(input_dir: float) -> void:
    _dodge_roll_dir = int(signf(input_dir))
    if _dodge_roll_dir == 0:
        _dodge_roll_dir = 1 if _right else -1
    _right = _dodge_roll_dir > 0
    _dodge_roll_timer = DODGE_ROLL_SEC
    _beam_charge_timer = 0.0
    _was_shoot_held = false
    _authored_melee_attack.clear()
    _invuln_timer = maxf(_invuln_timer, DODGE_ROLL_IFRAME_SEC)
    var roll_pose_id: int = _find_dodge_roll_pose_id()
    if roll_pose_id >= 0:
        _try_set_pose(roll_pose_id)
    else:
        _try_set_pose(53 if _right else 54, 1 if _right else 2)


func _find_dodge_roll_pose_id() -> int:
    var desired_dir: int = 1 if _right else -1
    var pose_names: Array = []
    if desired_dir > 0:
        pose_names = [
            "dodge_roll_right",
            "roll_right",
            "dodge_right",
        ]
    else:
        pose_names = [
            "dodge_roll_left",
            "roll_left",
            "dodge_left",
        ]
    for pose_name_v in pose_names:
        var pose_id: int = _find_pose_id_by_name(str(pose_name_v))
        if pose_id >= 0:
            return pose_id
    return -1


func _tick_dodge_roll(dt: float) -> void:
    velocity.x = float(_dodge_roll_dir) * maxf(_profile.run_max * DODGE_ROLL_SPEED_MULT, 280.0)
    if is_on_floor():
        velocity.y = 0.0
    move_and_slide()
    _was_on_floor = is_on_floor()
    if _invuln_timer > 0.0:
        _invuln_timer = maxf(0.0, _invuln_timer - dt)
    if _shoot_cooldown > 0.0:
        _shoot_cooldown = maxf(0.0, _shoot_cooldown - dt)
    if _bomb_cooldown > 0.0:
        _bomb_cooldown = maxf(0.0, _bomb_cooldown - dt)
    _dodge_roll_timer = maxf(0.0, _dodge_roll_timer - dt)
    _check_spike_overlap(dt)
    _process_effects(dt)
    _advance_animation(dt)
    _check_door_edges()
    if _dodge_roll_timer <= 0.0:
        velocity.x = move_toward(velocity.x, 0.0, _profile.run_decel * dt)
        _try_set_pose(1 if _right else 2)


# Force pose 0 (facing camera). Used by scripted start sequences.
func set_forward_pose() -> void:
    if _poses.has(0):
        _set_pose(0)


# P6b: hot-swap the player's physics profile. Called by the set_physics
# trigger action so a content pack can flip between SM and SOTN feel
# mid-game (or per-room: door enters → set physics).
func set_physics_profile(profile: MvPhysicsProfile) -> void:
    if profile == null:
        return
    _profile = profile
    # Reapply collision so collision_width changes take effect.
    var yr := _yr
    _yr = -1
    var info: Dictionary = _poses.get(_pose, {})
    _set_collision(yr, _collision_width_for_pose(info), _collision_x_for_pose(info))
    _apply_pose_hurtbox(info)


# ===== Phase 7 ability hooks =====

# Apply ability multipliers to the base MvPhysicsProfile.jump_speed. Only
# High Jump Boots layers in today; future content can stack other jump-boost
# passives by reading more abilities here.
func _effective_jump_speed() -> float:
    var speed := _profile.jump_speed
    if PlayerInventory.has_ability("high_jump"):
        speed *= MvAbilityParams.param_float("high_jump", "jump_multiplier", DEF_HIGH_JUMP_MULT)
    return speed


# Running jumps go higher in SM — the ROM biases initial jump velocity by
# the player's horizontal run speed. Linear 25% bonus at full RunMax,
# interpolating from 0% at rest. Applied on top of High Jump so ability
# stacking stays clean.
func _jump_speed_with_run_bonus(vel_x: float) -> float:
    var base_spd := _effective_jump_speed()
    var run_max := _profile.run_max
    if run_max <= 1.0:
        return base_spd
    var bonus := clampf(absf(vel_x) / run_max, 0.0, 1.0) * 0.25
    return base_spd * (1.0 + bonus)


# Speed Booster charge tick. Build the meter while: has ability, on floor,
# holding a single direction, at (or near) RunMax. After charge_seconds the
# shine activates and effective RunMax is multiplied. Reversing direction
# or stopping cancels. Damage hits go through take_damage → _reset_shine.
func _tick_speed_booster_charge(dir: float, vel_x: float, on_floor: bool, dt: float) -> void:
    if not PlayerInventory.has_ability("speed_booster"):
        if _shine_active or _speed_charge_timer > 0.0:
            _reset_shine()
        return

    # Cancellation paths: direction reversed, no direction, or stopped.
    if dir == 0.0 or (_speed_charge_dir != 0 and int(signf(dir)) != _speed_charge_dir):
        if _shine_active or _speed_charge_timer > 0.0:
            _reset_shine()
        return

    # Lock in the charge direction on the first tick we see input.
    if _speed_charge_dir == 0:
        _speed_charge_dir = int(signf(dir))

    # Once shine is active we leave it engaged even mid-air so jumps carry
    # the boost — SM's "shinespark setup" relies on this.
    if _shine_active:
        return

    if not on_floor:
        return
    if absf(vel_x) < _profile.run_max * 0.95:
        return

    _speed_charge_timer += dt
    if _speed_charge_timer >= MvAbilityParams.param_float("speed_booster", "charge_seconds", DEF_SPEED_BOOSTER_CHARGE_SEC):
        _shine_active = true


func _reset_shine() -> void:
    _shine_active = false
    _speed_charge_timer = 0.0
    _speed_charge_dir = 0
    _shine_stash_timer = 0.0


# Convert a stashed shine into an active dash. Direction is the current
# aim vector; if the aim is nearly horizontal we lock to pure horizontal
# so the player can't accidentally diagonal-spark when she meant to go
# flat. SM's spark speed is ~6 px/frame (360 px/s in our units, bumped to
# 600 here for a snappier feel).
func _launch_shine_spark() -> void:
    var aim := get_aim_direction()
    if aim.length() < 0.2:
        aim = Vector2.UP

    _shine_spark_vel = aim.normalized() * MvAbilityParams.param_float("shinespark", "dash_speed", DEF_SHINESPARK_SPEED)
    _shine_spark_active = true
    _shine_spark_timer = MvAbilityParams.param_float("shinespark", "dash_seconds", DEF_SHINE_SPARK_SEC)
    _shine_stash_timer = 0.0
    _was_jump_held = false


# Per-frame shinespark integrator. Position advances by the constant
# velocity; any contact ends the dash and applies self-damage. Timer
# expiry releases cleanly without the damage payload.
func _tick_shine_spark(dt: float) -> void:
    _shine_spark_timer -= dt
    velocity = _shine_spark_vel
    move_and_slide()

    var hit_wall := get_slide_collision_count() > 0
    if hit_wall or _shine_spark_timer <= 0.0:
        _shine_spark_active = false
        _shine_spark_timer = 0.0
        if hit_wall:
            # Self-damage on impact. ROM uses 0x1E (30); we keep it small
            # here so testing isn't punishing.
            take_damage(15, "shinespark_impact")
        # Bleed velocity so the player doesn't keep the spark momentum.
        velocity = Vector2.ZERO
        _was_on_floor = is_on_floor()

    if _invuln_timer > 0.0:
        _invuln_timer -= dt


# Unified air-jump / wall-jump handler. Called from every airborne state
# branch (MV_JUMP, MV_FALL, MV_SPIN). Air jump priority beats wall jump so
# the player can't accidentally waste a double_jump charge by pressing
# near a wall. Returns the (possibly modified) vel.
func _try_air_jump_or_wall_jump(jump_pressed: bool, vel: Vector2) -> Vector2:
    if not jump_pressed:
        return vel
    if _wall_jump_cooldown > 0.0:
        return vel

    if _air_jumps_remaining > 0:
        vel.y = -_effective_jump_speed()
        _air_jumps_remaining -= 1
        _try_set_pose(75 if _right else 76)
        return vel
    if is_on_wall() and PlayerInventory.has_ability("wall_jump"):
        vel = _do_wall_jump(vel)
    return vel


# Refill mid-air jump counter. space_jump grants effectively infinite
# rejumps (we cap at a large number); double_jump grants exactly the
# extra_jumps param value (default 1).
func _reset_air_jumps() -> void:
    if PlayerInventory.has_ability("space_jump"):
        _air_jumps_remaining = MvAbilityParams.param_int("space_jump", "max_air_jumps", DEF_SPACE_JUMP_AIR_JUMPS)
        return
    if PlayerInventory.has_ability("double_jump"):
        _air_jumps_remaining = MvAbilityParams.param_int("double_jump", "extra_jumps", DEF_DOUBLE_JUMP_EXTRA)
        return
    _air_jumps_remaining = 0


# Wall jump impulse — push away from the wall and up. Ported from SM's
# wall-jump handler ($91:E1A3): fixed X velocity away from the wall + fixed
# upward Y velocity, facing flips, small post-jump cooldown so spamming
# doesn't chain instant walljumps against the same wall.
#
# SM ROM stores the impulse as $0002.8000 (2.5 px/frame horizontal) and
# $0003.0000 (3.0 px/frame upward). Our defaults (200/280 px/s) are scaled
# up because the metroidvania camera is bigger than SM's.
func _do_wall_jump(vel: Vector2) -> Vector2:
    # Wall normal points away from the wall — push in that direction.
    var n := get_wall_normal()
    if n == Vector2.ZERO:
        n = Vector2(-1.0 if _right else 1.0, 0.0)  # fallback: back the way we faced
    vel.x = n.x * MvAbilityParams.param_float("wall_jump", "wall_jump_x", DEF_WALL_JUMP_X_SPEED)
    vel.y = -MvAbilityParams.param_float("wall_jump", "wall_jump_y", DEF_WALL_JUMP_Y_SPEED)

    # Flip facing to match new horizontal direction.
    _right = vel.x > 0.0
    if _sprite != null:
        _set_sprite_flip_all(not _right)

    _wall_jump_cooldown = MvAbilityParams.param_float("wall_jump", "cooldown_seconds", DEF_WALL_JUMP_COOLDOWN_SEC)
    _try_set_pose(75 if _right else 76)
    return vel


# ===== Animation =====

func _advance_animation(dt: float) -> void:
    if not _poses.has(_pose):
        return
    var anim_owner: int = _resolved_animation_owner(_pose)
    if anim_owner < 0:
        return
    var anim_pi: Dictionary = _poses[anim_owner]
    var pi: Dictionary = _poses[_pose]
    var timing: Array = anim_pi["timing"]
    if timing.size() == 0 or _anim_count == 0:
        return

    var speed_scale := _script_anim_speed_scale if _script_anim_active and _pose == _script_anim_pose_id else 1.0
    speed_scale *= _pose_anim_speed_scale(_pose, anim_owner)
    var mvtype: int = int(pi.get("mvtype", MV_STAND))
    if mvtype == MV_TURN:
        speed_scale *= 2.0
    _anim_ticks += dt * 60.0 * maxf(0.01, speed_scale)

    var frame_idx: int = min(_anim_idx, timing.size() - 1)
    var frame_dur: float = float(timing[frame_idx])

    while _anim_ticks >= frame_dur:
        _anim_ticks -= frame_dur
        _anim_idx += 1

        if _anim_idx >= _anim_count:
            if _script_anim_active and _pose == _script_anim_pose_id:
                var script_loop_from := int(pi["loop_from"])
                if _script_anim_loop:
                    _anim_idx = script_loop_from if script_loop_from >= 0 else 0
                else:
                    var finished_anim := _script_anim_name
                    _anim_idx = _anim_count - 1
                    _anim_ticks = 0.0
                    _script_anim_active = false
                    _script_anim_pose_id = -1
                    _script_anim_speed_scale = 1.0
                    _script_anim_name = ""
                    scripted_animation_finished.emit(finished_anim)
                    break
                _show_frame()
                frame_idx = min(_anim_idx, timing.size() - 1)
                frame_dur = float(timing[frame_idx])
                continue
            var transition_to: int = int(pi["transition_to"])
            var loop_from: int = int(pi["loop_from"])
            if transition_to >= 0:
                if _poses.has(transition_to) and _resolved_animation_owner(transition_to) >= 0:
                    _set_pose(transition_to)
                    return
                else:
                    _try_set_pose(1 if _right else 2)
                    return
            elif loop_from >= 0:
                _anim_idx = loop_from
            else:
                _anim_idx = _anim_count - 1
                _anim_ticks = 0.0
                break

        _show_frame()
        frame_idx = min(_anim_idx, timing.size() - 1)
        frame_dur = float(timing[frame_idx])


func _pose_anim_speed_scale(pose_id: int, anim_owner: int = -1) -> float:
    if _poses.has(pose_id):
        return maxf(0.05, float((_poses[pose_id] as Dictionary).get("anim_speed", 1.0)))
    if anim_owner >= 0 and _poses.has(anim_owner):
        return maxf(0.05, float((_poses[anim_owner] as Dictionary).get("anim_speed", 1.0)))
    return 1.0


# ===== Shooting =====

func _can_shoot() -> bool:
    if not _poses.has(_pose):
        return false
    var mv: int = int((_poses[_pose] as Dictionary)["mvtype"])
    return mv != MV_SPIN and mv != MV_TURN \
        and mv != MV_WALLJUMP and mv != MV_TURN_AIR and mv != MV_TURN_FALL


func _attack_definition_by_id(attack_id: String) -> Dictionary:
    var clean_id: String = attack_id.strip_edges()
    if clean_id.is_empty():
        return {}
    return PlayerInventory.get_attack_definition(clean_id)


func _active_ranged_attack() -> Dictionary:
    return _attack_definition_by_id(PlayerInventory.get_ranged_attack_id())


func _ranged_charge_threshold_seconds() -> float:
    var attack := _active_ranged_attack()
    if not attack.is_empty():
        if _active_ranged_attack_hold_behavior(attack) == "charge_release":
            var charge_ticks := int(attack.get("charge_ticks", 0))
            return float(charge_ticks) / 60.0
    return _profile.beam_charge_seconds


func _active_ranged_attack_supports_charge() -> bool:
    var attack := _active_ranged_attack()
    if attack.is_empty():
        return false
    return _active_ranged_attack_hold_behavior(attack) == "charge_release"


func _active_ranged_attack_hold_behavior(attack: Dictionary = {}) -> String:
    var resolved_attack: Dictionary = attack
    if resolved_attack.is_empty():
        resolved_attack = _active_ranged_attack()
    if resolved_attack.is_empty():
        return ""
    var hold_behavior := str(resolved_attack.get("hold_behavior", "")).strip_edges()
    if hold_behavior == "full_auto" or hold_behavior == "single_press" or hold_behavior == "charge_release":
        return hold_behavior
    var charged_attack_id := str(resolved_attack.get("charged_attack_id", "")).strip_edges()
    var charge_ticks := int(resolved_attack.get("charge_ticks", 0))
    if not charged_attack_id.is_empty() and charge_ticks > 0:
        return "charge_release"
    return "full_auto"


func _full_auto_hold_pose_id(attack: Dictionary = {}) -> int:
    var resolved_attack: Dictionary = attack
    if resolved_attack.is_empty():
        resolved_attack = _active_ranged_attack()
    if resolved_attack.is_empty():
        return -1

    var charged_attack_id := str(resolved_attack.get("charged_attack_id", "")).strip_edges()
    if not charged_attack_id.is_empty():
        var charged_attack: Dictionary = _attack_definition_by_id(charged_attack_id)
        if not charged_attack.is_empty():
            var charged_pose_id := _resolved_attack_pose_id(int(charged_attack.get("player_pose", -1)))
            if charged_pose_id >= 0:
                return charged_pose_id

    var pose_names: Array = []
    if _right:
        pose_names = ["ranged_charge_right", "charged_right", "charge_right"]
    else:
        pose_names = ["ranged_charge_left", "charged_left", "charge_left"]
    for pose_name_v in pose_names:
        var pose_id := _find_pose_id_by_name(str(pose_name_v))
        if pose_id >= 0 and _resolved_animation_owner(pose_id) >= 0:
            return pose_id
    return -1


func _apply_full_auto_hold_pose(attack: Dictionary = {}) -> void:
    var hold_pose_id := _full_auto_hold_pose_id(attack)
    if hold_pose_id < 0:
        return
    if _pose == hold_pose_id:
        return
    _try_set_pose(hold_pose_id)


# Pose displayed while holding the ranged-attack button on a charge_release
# weapon. Prefers an authored ranged_charge_* pose for the current facing —
# that's the dedicated "winding up a charged shot" loop authors set in the
# sprite editor. Falls back to the charged variant's player_pose if no
# dedicated charge pose exists so the player isn't stuck idle during the
# hold.
func _ranged_charge_hold_pose_id(attack: Dictionary = {}) -> int:
    var pose_names: Array = []
    if _right:
        pose_names = ["ranged_charge_right", "charged_right", "charge_right"]
    else:
        pose_names = ["ranged_charge_left", "charged_left", "charge_left"]
    for pose_name_v in pose_names:
        var pose_id := _find_pose_id_by_name(str(pose_name_v))
        if pose_id >= 0 and _resolved_animation_owner(pose_id) >= 0:
            return pose_id

    var resolved_attack: Dictionary = attack
    if resolved_attack.is_empty():
        resolved_attack = _active_ranged_attack()
    if resolved_attack.is_empty():
        return -1
    var charged_attack_id := str(resolved_attack.get("charged_attack_id", "")).strip_edges()
    if not charged_attack_id.is_empty():
        var charged_attack: Dictionary = _attack_definition_by_id(charged_attack_id)
        if not charged_attack.is_empty():
            var charged_pose_id := _resolved_attack_pose_id(int(charged_attack.get("player_pose", -1)))
            if charged_pose_id >= 0:
                return charged_pose_id
    return -1


func _apply_ranged_charge_hold_pose(attack: Dictionary = {}) -> void:
    var hold_pose_id := _ranged_charge_hold_pose_id(attack)
    if hold_pose_id < 0:
        return
    if _pose == hold_pose_id:
        return
    _try_set_pose(hold_pose_id)


func _restore_after_full_auto_hold(on_floor: bool, dir: float, vel: Vector2) -> void:
    var hold_pose_id := _full_auto_hold_pose_id()
    if hold_pose_id < 0 or _pose != hold_pose_id:
        return
    if not on_floor:
        if vel.y < 0.0:
            _try_set_pose(75 if _right else 76, 41 if _right else 42)
        else:
            _try_set_pose(41 if _right else 42)
        return
    if Input.is_action_pressed("crouch"):
        _try_set_pose(53 if _right else 54, 67 if _right else 68)
        return
    if dir != 0.0:
        _try_set_pose(9 if _right else 10, 1 if _right else 2)
        return
    _try_set_pose(1 if _right else 2)


func _update_charge_fx(ranged_held: bool, delta: float) -> void:
    if _charge_fx_sprite == null:
        return
    if not ranged_held:
        _hide_charge_fx()
        return
    var attack := _active_ranged_attack()
    if attack.is_empty() or not _attack_supports_charge_fx(attack):
        _hide_charge_fx()
        return
    _ensure_charge_fx_loaded(attack)
    if _charge_fx_texture == null:
        _hide_charge_fx()
        return

    var aim := get_aim_direction()
    _charge_fx_sprite.position = _attack_spawn_local_position(attack, aim)
    if aim.length_squared() > 0.0001:
        _charge_fx_sprite.rotation = aim.angle()
    _charge_fx_sprite.visible = true

    _charge_fx_anim_timer += delta * 60.0
    if _charge_fx_anim_timer >= float(_charge_fx_frame_tick):
        _charge_fx_anim_timer -= float(_charge_fx_frame_tick)
        _charge_fx_anim_frame = (_charge_fx_anim_frame + 1) % _charge_fx_frame_count
        _apply_charge_fx_frame()

    var threshold := maxf(_ranged_charge_threshold_seconds(), 0.001)
    var charge_ratio := clampf(_beam_charge_timer / threshold, 0.0, 1.0)
    var sprite_scale := 0.85 + charge_ratio * 0.35
    _charge_fx_sprite.scale = Vector2.ONE * sprite_scale
    _charge_fx_sprite.modulate = Color(1.0, 1.0, 1.0, 0.4 + charge_ratio * 0.6)


func _attack_supports_charge_fx(attack: Dictionary) -> bool:
    return not str(attack.get("charge_fx_sheet", "")).strip_edges().is_empty() \
        and _active_ranged_attack_hold_behavior(attack) == "charge_release"


func _ensure_charge_fx_loaded(attack: Dictionary) -> void:
    var attack_id := str(attack.get("id", "")).strip_edges()
    var sheet_path := str(attack.get("charge_fx_sheet", "")).strip_edges()
    var frame_width := maxi(1, int(attack.get("charge_fx_frame_width", 32)))
    var frame_height := maxi(1, int(attack.get("charge_fx_frame_height", 32)))
    var frame_index := maxi(0, int(attack.get("charge_fx_frame_index", 0)))
    var frame_count := maxi(1, int(attack.get("charge_fx_frame_count", 1)))
    var frame_tick := maxi(1, int(attack.get("charge_fx_frame_tick", 6)))
    if attack_id == _charge_fx_attack_id \
            and sheet_path == _charge_fx_sheet_path \
            and frame_width == _charge_fx_frame_width \
            and frame_height == _charge_fx_frame_height \
            and frame_index == _charge_fx_frame_index \
            and frame_count == _charge_fx_frame_count \
            and frame_tick == _charge_fx_frame_tick:
        return

    _charge_fx_attack_id = attack_id
    _charge_fx_sheet_path = sheet_path
    _charge_fx_frame_width = frame_width
    _charge_fx_frame_height = frame_height
    _charge_fx_frame_index = frame_index
    _charge_fx_frame_count = frame_count
    _charge_fx_frame_tick = frame_tick
    _charge_fx_anim_timer = 0.0
    _charge_fx_anim_frame = 0
    _charge_fx_texture = null
    _charge_fx_sprite.texture = null

    if MvPackLoader.current_pack == null or sheet_path.is_empty():
        return
    var tex_path := MvPackLoader.resolve_read_cascade(MvPackLoader.current_pack.pack_id, "Sprites", sheet_path)
    var tex := load(tex_path)
    if tex is Texture2D:
        _charge_fx_texture = tex
        _apply_charge_fx_frame()


func _apply_charge_fx_frame() -> void:
    if _charge_fx_sprite == null or _charge_fx_texture == null:
        return
    var atlas := AtlasTexture.new()
    atlas.atlas = _charge_fx_texture
    atlas.region = Rect2(
        float((_charge_fx_frame_index + _charge_fx_anim_frame) * _charge_fx_frame_width),
        0.0,
        float(_charge_fx_frame_width),
        float(_charge_fx_frame_height)
    )
    _charge_fx_sprite.texture = atlas


func _hide_charge_fx() -> void:
    if _charge_fx_sprite == null:
        return
    _charge_fx_sprite.visible = false


# Continuous aim vector. Right stick wins if deflected; otherwise the
# mouse cursor delta from the player's world position. If neither is
# active, falls back to pure horizontal facing.
func get_aim_direction() -> Vector2:
    # Right stick: Godot exposes axes 2/3 for the right stick on xinput
    # pads. Reading raw axes avoids having to add input-map entries.
    var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
    var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
    var stick := Vector2(sx, sy)
    if stick.length() > STICK_DEADZONE:
        return stick.normalized()

    # Mouse aim: cursor position relative to shoulder. get_global_mouse_position
    # honours the viewport transform, so this works in SubViewport hosted mode.
    var shoulder := global_position + _weapon_anchor_local()
    var to_mouse := get_global_mouse_position() - shoulder
    if to_mouse.length_squared() > 0.5:
        return to_mouse.normalized()

    return Vector2(1.0 if _right else -1.0, 0.0)


func _try_melee_attack() -> void:
    if not _authored_melee_attack.is_empty():
        _consume_authored_combo_input()
        return
    if _combo_grace_timer > 0.0 and not _combo_grace_next_id.is_empty():
        var grace_next_id: String = _combo_grace_next_id
        _combo_grace_timer = 0.0
        _combo_grace_next_id = ""
        _try_fire_authored_attack(grace_next_id, true)
        return
    if not _can_shoot():
        return
    var melee_attack_id: String = PlayerInventory.get_melee_attack_id()
    if melee_attack_id.is_empty():
        return
    if not _consume_authored_combo_input():
        _try_fire_authored_attack(melee_attack_id)


# Parry: swap to the first authored pose with mvtype == MV_PARRY for the
# current facing. No deflect / damage gating yet — this just plays the
# authored animation so the sprite editor's parry slot has a runtime hook.
# Combat behavior (timing window, deflect, iframes) is a future slice.
func _try_parry() -> void:
    if not _authored_melee_attack.is_empty():
        return
    var pose_id: int = _find_pose_id_by_mvtype(MV_PARRY, 1 if _right else -1)
    if pose_id < 0:
        # Try the opposite facing as a fallback; mirror lookup will flip it.
        pose_id = _find_pose_id_by_mvtype(MV_PARRY, -1 if _right else 1)
    if pose_id < 0:
        return
    _try_set_pose(pose_id)


func _find_pose_id_by_mvtype(mvtype: int, desired_dir: int) -> int:
    for pose_id_v in _poses.keys():
        var pose_id: int = int(pose_id_v)
        var info: Dictionary = _poses[pose_id]
        if int(info.get("mvtype", -999)) != mvtype:
            continue
        if _pose_dir_value(info) != desired_dir:
            continue
        return pose_id
    return -1


# Public mirror of _is_parry_active() so projectiles and other external
# damage sources can check parry state before applying damage. They use
# this to deflect themselves instead of just being absorbed silently.
func is_parry_active() -> bool:
    return _is_parry_active()


# True when the player is in a parry pose AND the current animation frame
# is the active window (anything except the first and last frame). Authors
# need at least 3 frames of parry animation: first = windup, last =
# recovery, middles = active window.
func _is_parry_active() -> bool:
    if not _poses.has(_pose):
        return false
    var info: Dictionary = _poses[_pose]
    if int(info.get("mvtype", -999)) != MV_PARRY:
        return false
    var anim_owner: int = _resolved_animation_owner(_pose)
    if anim_owner < 0 or not _frames.has(anim_owner):
        return false
    var frame_count: int = (_frames[anim_owner] as Array).size()
    if frame_count < 3:
        return false
    return _anim_idx > 0 and _anim_idx < frame_count - 1


# Counter-attack fired by a successful parry. Reuses the equipped melee
# attack with damage doubled. Ignores cooldown so the counter always
# triggers when the parry lands.
func _fire_parry_counter() -> void:
    var melee_attack_id: String = PlayerInventory.get_melee_attack_id()
    if melee_attack_id.is_empty():
        return
    var attack: Dictionary = PlayerInventory.get_attack_definition(melee_attack_id)
    if attack.is_empty():
        return
    if str(attack.get("type", "")).strip_edges() != "melee":
        return
    attack = attack.duplicate(true)
    attack["damage"] = int(attack.get("damage", 0)) * 2

    var aim := get_aim_direction()
    _apply_attack_facing_from_aim(aim)
    var pose_id := _resolved_attack_pose_id(int(attack.get("player_pose", -1)))
    if pose_id >= 0:
        _try_set_pose(pose_id)
    _begin_authored_melee_attack(attack, pose_id)
    var cooldown_ticks := maxf(0.0, float(int(attack.get("cooldown_ticks", 0))))
    var reload_mult := maxf(0.01, float(PlayerInventory.get_var("mv_reload_speed_mult", 1.0)))
    _shoot_cooldown = (cooldown_ticks / 60.0) / reload_mult


# Public API: knock the player down. Cancels any in-flight melee combo, plays
# the MV_KNOCKDOWN pose for the matching facing, and locks input + invuln
# until the pose chain (knockdown -> stand_up -> idle) leaves the recovery
# state. Returns false if a cutscene already owns the player or if no
# MV_KNOCKDOWN pose has been authored. from_pos faces the player toward the
# threat the same way take_damage() does.
func apply_knockdown(from_pos = null) -> bool:
    if _knockdown_active:
        return false
    if _locked:
        return false
    var desired_dir: int = 1 if _right else -1
    if from_pos != null and typeof(from_pos) == TYPE_VECTOR2:
        var fp: Vector2 = from_pos
        _right = fp.x < position.x
        desired_dir = 1 if _right else -1
        if _sprite != null:
            _set_sprite_flip_all(not _right)
    var pose_id: int = _find_pose_id_by_mvtype(MV_KNOCKDOWN, desired_dir)
    if pose_id < 0:
        pose_id = _find_pose_id_by_mvtype(MV_KNOCKDOWN, -desired_dir)
    if pose_id < 0:
        return false
    if not _authored_melee_attack.is_empty():
        _authored_melee_attack.clear()
    _melee_input_locked = false
    _combo_grace_timer = 0.0
    _combo_grace_next_id = ""
    _knockdown_active = true
    set_locked(true)
    # Held high so the recovery animation can't be interrupted by a second
    # hit. _release_knockdown() drops it to invuln_seconds when the chain
    # exits MV_STAND_UP, which leaves a small post-getup grace.
    _invuln_timer = maxf(_invuln_timer, 99.0)
    _set_pose(pose_id)
    return true


# Called from _set_pose when the active pose's mvtype leaves the knockdown /
# stand_up chain. Restores normal input + caps invuln to invuln_seconds.
func _release_knockdown() -> void:
    _knockdown_active = false
    set_locked(false)
    _invuln_timer = minf(_invuln_timer, invuln_seconds)


# True while apply_knockdown() has the player locked into the
# knockdown -> stand_up chain. Lets external systems (HUD, AI) check the
# recovery state.
func is_knockdown_active() -> bool:
    return _knockdown_active


func _try_ranged_attack() -> void:
    if not _can_shoot():
        return

    if _secondary_mode_active:
        if _try_secondary_attack() or _shoot_cooldown > 0.0:
            return

    var ranged_attack_id: String = PlayerInventory.get_ranged_attack_id()
    if not ranged_attack_id.is_empty():
        _try_fire_authored_attack(ranged_attack_id)
        return

    # Dispatch on the equipped weapon. Bare-handed defaults to Beam so the
    # player is never weaponless. Each branch enforces its own cooldown +
    # in-flight cap so switching weapons doesn't bypass either budget.
    var wt: int = PlayerInventory.get_active_weapon_type()
    if wt == PlayerInventory.WeaponType.GRENADE_LAUNCHER:
        _fire_grenade_launcher()
    else:
        _fire_beam()


func _toggle_secondary_mode() -> void:
    if _secondary_mode_active:
        _secondary_mode_active = false
        return
    if PlayerInventory.get_secondary_attack_id().is_empty():
        return
    if not _secondary_has_ammo():
        return
    _secondary_mode_active = true


func is_secondary_mode_active() -> bool:
    return _secondary_mode_active


func _try_secondary_attack() -> bool:
    if not _can_shoot() or _shoot_cooldown > 0.0:
        return false
    var attack_id: String = PlayerInventory.get_secondary_attack_id()
    if attack_id.is_empty() or PlayerInventory.get_attack_definition(attack_id).is_empty():
        _secondary_mode_active = false
        return false
    var ammo_key: String = PlayerInventory.get_secondary_ammo_key()
    var ammo_cost: int = PlayerInventory.get_secondary_ammo_cost()
    if ammo_cost > 0:
        if ammo_key.is_empty():
            _secondary_mode_active = false
            return false
        var max_ammo := int(PlayerInventory.get_var("max_ammo_%s" % ammo_key, 0))
        var ammo := int(PlayerInventory.get_var("ammo_%s" % ammo_key, max_ammo))
        if max_ammo <= 0 or ammo < ammo_cost:
            _secondary_mode_active = false
            return false
        PlayerInventory.set_var("ammo_%s" % ammo_key, maxi(0, ammo - ammo_cost))
    _try_fire_authored_attack(attack_id)
    return true


func _secondary_has_ammo() -> bool:
    var ammo_cost: int = PlayerInventory.get_secondary_ammo_cost()
    if ammo_cost <= 0:
        return true
    var ammo_key: String = PlayerInventory.get_secondary_ammo_key()
    if ammo_key.is_empty():
        return false
    var max_ammo := int(PlayerInventory.get_var("max_ammo_%s" % ammo_key, 0))
    var ammo := int(PlayerInventory.get_var("ammo_%s" % ammo_key, max_ammo))
    return max_ammo > 0 and ammo >= ammo_cost


func _fire_beam() -> void:
    if _shoot_cooldown > 0.0:
        return
    if _beam_count >= _profile.max_beams:
        return

    var aim := get_aim_direction()
    _apply_attack_facing_from_aim(aim)
    var spawn_pos := get_shoulder_world() + aim * BARREL_RADIUS

    var beam: MvBeam = _beam_scene.instantiate()
    beam.position = spawn_pos
    beam.init_aimed(aim)
    beam.tree_exited.connect(_on_beam_despawned)
    get_parent().add_child(beam)

    _beam_count += 1
    _shoot_cooldown = _profile.beam_cooldown
    if _beam_sfx != null:
        _beam_sfx.play()


func _try_fire_authored_attack(attack_id: String, ignore_cooldown: bool = false) -> void:
    if not ignore_cooldown and _shoot_cooldown > 0.0:
        return
    var attack := PlayerInventory.get_attack_definition(attack_id)
    if attack.is_empty():
        return

    var aim := get_aim_direction()
    _apply_attack_facing_from_aim(aim)

    var pose_id := _resolved_attack_pose_id(int(attack.get("player_pose", -1)))
    var attack_type := str(attack.get("type", "")).strip_edges()
    var hold_behavior := _active_ranged_attack_hold_behavior(attack)
    var moving_horizontally := absf(velocity.x) > 10.0
    var should_reset_pose := pose_id >= 0
    if should_reset_pose and attack_type == "projectile":
        if hold_behavior == "full_auto":
            var hold_pose_id := _full_auto_hold_pose_id(attack)
            if hold_pose_id >= 0 or _pose == pose_id:
                should_reset_pose = false
        elif not is_on_floor() or moving_horizontally:
            should_reset_pose = false
    if should_reset_pose:
        _try_set_pose(pose_id)

    match attack_type:
        "projectile":
            _spawn_authored_projectile_attack(attack, aim, pose_id)
        "melee":
            _begin_authored_melee_attack(attack, pose_id)
        _:
            return

    var cooldown_ticks := maxf(0.0, float(int(attack.get("cooldown_ticks", 0))))
    var reload_mult := maxf(0.01, float(PlayerInventory.get_var("mv_reload_speed_mult", 1.0)))
    _shoot_cooldown = (cooldown_ticks / 60.0) / reload_mult


func _try_fire_authored_ranged_charged() -> void:
    if not _can_shoot():
        return
    var attack := _active_ranged_attack()
    if attack.is_empty():
        return
    var charged_attack_id := str(attack.get("charged_attack_id", "")).strip_edges()
    if charged_attack_id.is_empty():
        return
    _try_fire_authored_attack(charged_attack_id)


func _spawn_authored_projectile_attack(attack: Dictionary, aim: Vector2, pose_id: int = -1) -> void:
    var projectile_id := str(attack.get("projectile_id", "")).strip_edges()
    if projectile_id.is_empty():
        return
    var projectile_def := PlayerInventory.get_projectile_definition(projectile_id)
    if projectile_def.is_empty():
        return

    if aim.length_squared() < 0.0001:
        aim = Vector2(1.0 if _right else -1.0, 0.0)
    var spread_deg := float(PlayerInventory.get_var("mv_projectile_spread", 0.0))
    if absf(spread_deg) > 0.001:
        aim = aim.rotated(deg_to_rad(spread_deg))

    var projectile := _MvAuthoredProjectile.new()
    var damage_mult := float(PlayerInventory.get_var("mv_projectile_damage_mult", 1.0))
    var damage_bonus := int(round(float(PlayerInventory.get_var("mv_projectile_damage_bonus", 0.0))))
    if damage_bonus != 0:
        projectile_def = projectile_def.duplicate(true)
        projectile_def["damage"] = int(projectile_def.get("damage", 0)) + damage_bonus
    projectile.configure(projectile_def, _attack_spawn_position(attack, aim, pose_id), aim, damage_mult)
    get_parent().add_child(projectile)


func _begin_authored_melee_attack(attack: Dictionary, pose_id: int) -> void:
    var hit_frames: Array = _normalized_attack_hit_frames(attack)
    if hit_frames.is_empty():
        return
    _authored_melee_attack = {
        "pose": pose_id,
        "def": attack.duplicate(true),
        "spawned_frames": {},
        "hit_targets": {},
        "min_frame": _min_hit_frame(hit_frames),
        "max_frame": _max_hit_frame(hit_frames),
        "combo_open_frame": _min_hit_frame(hit_frames),
        "queued_next_id": "",
    }
    _melee_input_locked = true


func _tick_authored_melee_attack() -> void:
    if _authored_melee_attack.is_empty():
        _melee_input_locked = false
        return
    var pose_id := int(_authored_melee_attack.get("pose", -1))
    if pose_id >= 0 and _pose != pose_id:
        _authored_melee_attack.clear()
        _melee_input_locked = false
        return
    var attack: Dictionary = _authored_melee_attack.get("def", {})
    if attack.is_empty():
        _authored_melee_attack.clear()
        _melee_input_locked = false
        return
    var _hit_frames: Array = _normalized_attack_hit_frames(attack)
    var spawned: Dictionary = _authored_melee_attack.get("spawned_frames", {})
    var hit_targets: Dictionary = _authored_melee_attack.get("hit_targets", {})
    var min_frame: int = int(_authored_melee_attack.get("min_frame", 0))
    var max_frame: int = int(_authored_melee_attack.get("max_frame", -1))
    var hit_active: bool = _anim_idx >= min_frame and _anim_idx <= max_frame
    if hit_active:
        _apply_authored_melee_geometry_hits(attack, hit_targets)
        _authored_melee_attack["hit_targets"] = hit_targets
    if hit_active and not spawned.has(_anim_idx):
        _spawn_authored_melee_hitbox(attack)
        spawned[_anim_idx] = true
        _authored_melee_attack["spawned_frames"] = spawned
    if _anim_idx > max_frame:
        var queued_next_id: String = str(_authored_melee_attack.get("queued_next_id", "")).strip_edges()
        var combo_next_id: String = str(attack.get("combo_next_id", "")).strip_edges()
        _authored_melee_attack.clear()
        _melee_input_locked = false
        if not queued_next_id.is_empty():
            _try_fire_authored_attack(queued_next_id, true)
        elif not combo_next_id.is_empty():
            _combo_grace_timer = COMBO_GRACE_SECONDS
            _combo_grace_next_id = combo_next_id


func _spawn_authored_melee_hitbox(attack: Dictionary) -> void:
    var range_mult := maxf(0.1, float(PlayerInventory.get_var("mv_melee_range_mult", 1.0)))
    var damage_mult := float(PlayerInventory.get_var("mv_melee_damage_mult", 1.0))
    var offset_x := float(int(attack.get("hitbox_x", 0))) * range_mult
    if not _right:
        offset_x = -offset_x
    var offset_y := float(int(attack.get("hitbox_y", 0))) * range_mult
    var size := Vector2(
        maxf(1.0, float(int(attack.get("hitbox_w", 1))) * range_mult),
        maxf(1.0, float(int(attack.get("hitbox_h", 1))) * range_mult)
    )
    var hitbox := _MvAuthoredMeleeHitbox.new()
    var damage_bonus := int(round(float(PlayerInventory.get_var("mv_melee_damage_bonus", 0.0))))
    hitbox.configure(combat_origin() + Vector2(offset_x, offset_y), size, int(round(float(attack.get("damage", 0)) * damage_mult)) + damage_bonus)
    get_parent().add_child(hitbox)


func _apply_authored_melee_geometry_hits(attack: Dictionary, hit_targets: Dictionary) -> void:
    var range_mult := maxf(0.1, float(PlayerInventory.get_var("mv_melee_range_mult", 1.0)))
    var damage_mult := float(PlayerInventory.get_var("mv_melee_damage_mult", 1.0))
    var offset_x := float(int(attack.get("hitbox_x", 0))) * range_mult
    if not _right:
        offset_x = -offset_x
    var offset_y := float(int(attack.get("hitbox_y", 0))) * range_mult
    var size := Vector2(
        maxf(1.0, float(int(attack.get("hitbox_w", 1))) * range_mult),
        maxf(1.0, float(int(attack.get("hitbox_h", 1))) * range_mult)
    )
    var world_rect := Rect2(combat_origin() + Vector2(offset_x, offset_y) - size * 0.5, size)
    var damage_bonus := int(round(float(PlayerInventory.get_var("mv_melee_damage_bonus", 0.0))))
    var damage := int(round(float(attack.get("damage", 0)) * damage_mult)) + damage_bonus
    if damage <= 0:
        return
    for enemy in get_tree().get_nodes_in_group("mv_enemy"):
        if not is_instance_valid(enemy):
            continue
        var enemy_id := enemy.get_instance_id()
        if hit_targets.has(enemy_id):
            continue
        var intersects := false
        if enemy.has_method("hurtbox_intersects_rect"):
            intersects = bool(enemy.call("hurtbox_intersects_rect", world_rect))
        elif enemy is Node2D:
            intersects = world_rect.has_point((enemy as Node2D).global_position)
        if not intersects:
            continue
        hit_targets[enemy_id] = true
        if enemy.has_method("take_damage"):
            enemy.call("take_damage", damage, combat_origin())


func _attack_spawn_position(attack: Dictionary, aim: Vector2, pose_id: int = -1) -> Vector2:
    return position + _attack_spawn_local_position(attack, aim, pose_id)


func _attack_spawn_local_position(attack: Dictionary, aim: Vector2, pose_id: int = -1) -> Vector2:
    var spawn_pose_id: int = pose_id if pose_id >= 0 else _pose
    var base := _weapon_anchor_local_for_pose(spawn_pose_id)
    var use_attack_offset: bool = bool(attack.get("use_muzzle_offset", not _pose_has_custom_weapon_anchor(spawn_pose_id)))
    if not use_attack_offset:
        return base
    var offset := Vector2(float(int(attack.get("muzzle_x", 0))), float(int(attack.get("muzzle_y", 0))))
    if aim.length_squared() > 0.0001:
        var forward := aim.normalized()
        var up := Vector2(-forward.y, forward.x)
        return base + forward * offset.x + up * offset.y
    if not _right:
        offset.x = -offset.x
    return base + offset


func _max_hit_frame(frames: Array) -> int:
    var max_frame := -1
    for frame_v in frames:
        max_frame = maxi(max_frame, int(frame_v))
    return max_frame


func _min_hit_frame(frames: Array) -> int:
    var min_frame := 2147483647
    for frame_v in frames:
        min_frame = mini(min_frame, int(frame_v))
    if min_frame == 2147483647:
        return 0
    return min_frame


func _normalized_attack_hit_frames(attack: Dictionary) -> Array:
    var out: Array = []
    var hit_frames_v: Variant = attack.get("hit_frames", [])
    if typeof(hit_frames_v) != TYPE_ARRAY:
        return out
    for frame_v in hit_frames_v as Array:
        out.append(int(frame_v))
    return out


func _consume_authored_combo_input() -> bool:
    if _authored_melee_attack.is_empty():
        return false
    var attack: Dictionary = _authored_melee_attack.get("def", {})
    if attack.is_empty():
        return true
    var combo_next_id: String = str(attack.get("combo_next_id", "")).strip_edges()
    if combo_next_id.is_empty():
        return true
    if not str(_authored_melee_attack.get("queued_next_id", "")).strip_edges().is_empty():
        return true
    _authored_melee_attack["queued_next_id"] = combo_next_id
    return true


# Release-to-fire charged beam. Ignores normal cooldown because the charge
# itself was the gate, but still honours the per-flight cap. Equipment-gated
# on the beam weapon type so a grenade-launcher player can't release one.
func _try_fire_charged() -> void:
    if not _can_shoot():
        return
    if _beam_count >= _profile.max_beams:
        return
    if PlayerInventory.get_active_weapon_type() != PlayerInventory.WeaponType.BEAM:
        return

    var aim := get_aim_direction()
    _apply_attack_facing_from_aim(aim)
    var spawn_pos := get_shoulder_world() + aim * BARREL_RADIUS

    var beam: MvBeam = _beam_scene.instantiate()
    beam.position = spawn_pos
    beam.init_charged(aim)
    beam.tree_exited.connect(_on_beam_despawned)
    get_parent().add_child(beam)

    _beam_count += 1
    _shoot_cooldown = _profile.beam_cooldown
    if _beam_sfx != null:
        _beam_sfx.play()


func _on_beam_despawned() -> void:
    _beam_count -= 1
    if _beam_count < 0:
        _beam_count = 0


# Grenade launcher — tosses an MvGrenade in the aim direction with a
# slight upward boost so it arcs naturally. Gated on MAX_BOMBS in-flight
# and BOMB_COOLDOWN between throws. tree_exited decrements the counter
# so the player can chain bombs as soon as one detonates.
func _fire_grenade_launcher() -> void:
    if _bomb_cooldown > 0.0:
        return
    if _bomb_count >= MAX_BOMBS:
        return

    var aim := get_aim_direction()
    if aim.length_squared() < 0.0001:
        aim = Vector2(1.0 if _right else -1.0, 0.0)
    _apply_attack_facing_from_aim(aim)

    var bomb := _MvGrenade.new()
    bomb.throw_dir = aim
    bomb.throw_speed = BOMB_THROW_SPEED
    bomb.throw_up = BOMB_UP_BOOST
    bomb.position = get_shoulder_world() + aim * BARREL_RADIUS
    bomb.tree_exited.connect(_on_grenade_despawned)
    get_parent().add_child(bomb)

    _bomb_count += 1
    _bomb_cooldown = BOMB_COOLDOWN


func _on_grenade_despawned() -> void:
    _bomb_count -= 1
    if _bomb_count < 0:
        _bomb_count = 0


# World-space muzzle/shoulder point — used by beams, the grapple projectile,
# and the rope renderer so visuals line up.
func get_shoulder_world() -> Vector2:
    return position + _weapon_anchor_local()


# Called by MvGrenade when it detonates while the player is inside its
# blast radius — classic SM bomb-jump, turns the explosion into free
# upward traversal.
func apply_bomb_jump(up_speed: float) -> void:
    var v := velocity
    v.y = -up_speed
    velocity = v
    _was_jump_held = true
    _was_on_floor = false


# ===== Grapple =====

func _try_grapple() -> void:
    # Reject if there's already a projectile in flight or a swing active —
    # the press in those states is handled by the caller (cancels flight,
    # or releases the swing).
    if _grapple_projectile != null or _grapple_swinging:
        return
    if not PlayerInventory.has_ability("grapple_beam"):
        return

    var aim := get_aim_direction()
    _grapple_projectile = MvGrappleBeam.new()
    _grapple_projectile.fire(self, get_shoulder_world(), aim)
    get_parent().add_child(_grapple_projectile)
    _grapple_projectile.position = get_shoulder_world()
    _grapple_projectile.tree_exited.connect(_on_grapple_projectile_exited)


func _on_grapple_projectile_exited() -> void:
    if not _grapple_swinging:
        _grapple_projectile = null


# Called by MvGrappleBeam on latch. Seeds the pendulum state from the
# player's current position + velocity so the swing starts with the
# momentum she had when the rope caught.
func begin_grapple_swing(pivot: Vector2, projectile: MvGrappleBeam) -> void:
    _grapple_swinging = true
    _grapple_pivot = pivot
    _grapple_projectile = projectile

    var offset := position - pivot
    _grapple_len = maxf(16.0, offset.length())
    _grapple_angle = atan2(offset.y, offset.x)

    # Convert linear velocity to tangential angular velocity. Tangent at
    # angle θ is (-sin, cos); angVel = (v · tangent) / len.
    var tangent := Vector2(-sin(_grapple_angle), cos(_grapple_angle))
    _grapple_ang_vel = velocity.dot(tangent) / _grapple_len

    velocity = Vector2.ZERO


func _tick_grapple_swing(dt: float) -> void:
    if _profile.grapple_mode == MvPhysicsProfile.GrappleMode.CLASSIC:
        _tick_grapple_classic(dt)
    else:
        _tick_grapple_pendulum(dt)

    var offset := Vector2(cos(_grapple_angle), sin(_grapple_angle)) * _grapple_len
    position = _grapple_pivot + offset

    # Facing follows the swing direction so the sprite doesn't flip wildly:
    # reconstruct linear velocity from tangential angVel.
    var tangent := Vector2(-sin(_grapple_angle), cos(_grapple_angle))
    var linear_vel := tangent * (_grapple_ang_vel * _grapple_len)
    velocity = linear_vel
    if absf(linear_vel.x) > 10.0:
        _right = linear_vel.x > 0.0
        if _sprite != null:
            _set_sprite_flip_all(not _right)

    if _grapple_projectile != null:
        _grapple_projectile.refresh_line()


# Bionic-Commando / SOTN style pendulum. Angular acceleration is
# -(g/L)·cos(θ); move_left/move_right pumps amplitude; damping prevents
# perpetual motion. Feels modern — carries momentum into and out of the
# swing, and you build height by pumping at the right phase.
func _tick_grapple_pendulum(dt: float) -> void:
    var ang_acc := -(_profile.grapple_gravity / _grapple_len) * cos(_grapple_angle)

    var pump_x := 0.0
    if Input.is_action_pressed("move_left"):
        pump_x -= 1.0
    if Input.is_action_pressed("move_right"):
        pump_x += 1.0
    var tangent_x := -sin(_grapple_angle)
    var tangent_sign := 1.0 if tangent_x == 0.0 else signf(tangent_x)
    ang_acc += pump_x * _profile.grapple_pump_power * tangent_sign

    if Input.is_action_pressed("aim_up"):
        _grapple_len = maxf(16.0, _grapple_len - 40.0 * dt)
    if Input.is_action_pressed("crouch"):
        _grapple_len = minf(MvAbilityParams.param_float("grapple_beam", "max_length", MvGrappleBeam.DEFAULT_MAX_RANGE), _grapple_len + 40.0 * dt)

    ang_acc -= _grapple_ang_vel * _profile.grapple_damping
    _grapple_ang_vel += ang_acc * dt
    _grapple_angle  += _grapple_ang_vel * dt


# Super Metroid grapple. Not a physical pendulum: Samus rotates around the
# pivot at a fixed angular rate while rotate-input is held, and stops
# rotating the moment input releases. Up/down trim rope length within
# [min_len, max_len]. Release on jump launches tangentially with the
# angular velocity she had at release.
#
# Mirrors ROM behavior: no gravity swing, no damping, no pumping — direct-
# drive orbit controlled by the d-pad/stick. Faithful to the original's
# "clunky but precise" feel.
func _tick_grapple_classic(dt: float) -> void:
    # Rotation input: move_left/move_right → CCW/CW. In screen space,
    # angles grow CCW when viewed in math coords but screen Y is inverted,
    # so "rotate left" (CCW on screen) decreases _grapple_angle in our
    # (cos, sin) convention where +Y is down.
    var rotate_input := 0.0
    if Input.is_action_pressed("move_left"):
        rotate_input -= 1.0
    if Input.is_action_pressed("move_right"):
        rotate_input += 1.0

    # When the player is below the pivot, "rotate right" should move her
    # right (angle increases). When she's above the pivot, "rotate right"
    # should still move her right — but that means angle decreases.
    # Invert when above the pivot.
    if sin(_grapple_angle) < 0.0:
        rotate_input = -rotate_input

    _grapple_ang_vel = rotate_input * _profile.grapple_rotate_speed
    _grapple_angle  += _grapple_ang_vel * dt

    # Length trim.
    if Input.is_action_pressed("aim_up"):
        _grapple_len = maxf(_profile.grapple_min_len, _grapple_len - _profile.grapple_length_rate * dt)
    if Input.is_action_pressed("crouch"):
        _grapple_len = minf(_profile.grapple_max_len, _grapple_len + _profile.grapple_length_rate * dt)


func _end_grapple_swing(release_boost: bool) -> void:
    if not _grapple_swinging:
        return
    _grapple_swinging = false

    # Convert final angular velocity to a linear release velocity so the
    # player exits with physical momentum.
    var tangent := Vector2(-sin(_grapple_angle), cos(_grapple_angle))
    velocity = tangent * (_grapple_ang_vel * _grapple_len)
    if release_boost:
        velocity *= _profile.grapple_release_boost

    if _grapple_projectile != null:
        _grapple_projectile.despawn()
    _grapple_projectile = null
    _was_jump_held = false
    _was_on_floor  = false


# ===== Utility =====

func current_authored_door(preferred_direction: String = "") -> Dictionary:
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null or not room_mgr.has_method("find_door_for_points"):
        return {}
    var sample_points := _hurtbox_sample_points()
    sample_points.append(global_position)
    return room_mgr.find_door_for_points(sample_points, preferred_direction)


func cleanup_room_transition_transients() -> void:
    _authored_melee_attack.clear()
    _melee_input_locked = false
    _combo_grace_timer = 0.0
    _combo_grace_next_id = ""
    _beam_count = 0
    _bomb_count = 0
    _grapple_swinging = false
    _grapple_ang_vel = 0.0
    if _grapple_projectile != null and is_instance_valid(_grapple_projectile):
        _grapple_projectile.despawn()
    _grapple_projectile = null


func _check_door_edges() -> void:
    if _door_lock_timer > 0.0:
        return
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null:
        return
    var authored_door := current_authored_door()
    if not authored_door.is_empty():
        var authored_door_id := str(authored_door.get("id", "")).strip_edges()
        if not authored_door_id.is_empty():
            entered_door.emit(authored_door_id)
            return


func spawn_at(pos: Vector2, entry_direction: String = "", facing_direction: String = "") -> void:
    position = pos
    velocity = Vector2.ZERO
    _was_jump_held = false
    _was_on_floor = true
    _set_pose(1)
    _show_frame()
    _apply_spawn_facing(facing_direction)
    _invuln_timer = 0.0
    _knockback_timer = 0.0

    # Door entry lockout: when we just came through a horizontal door,
    # force the player to keep walking in the original direction for a
    # short window so the transition has presence (otherwise she teleports
    # and the camera snaps instantly). entry_direction is the direction
    # she was moving when she triggered the door. Vertical doors skip the
    # walk-in but still tick the timer so the camera can settle.
    if not entry_direction.is_empty():
        _door_lock_timer = DOOR_LOCK_SEC
        match entry_direction:
            "left":
                _door_lock_dir = -1
            "right":
                _door_lock_dir = 1
            _:
                _door_lock_dir = 0

    player_spawned.emit(pos)


# Phase 8: damage entry point. Returns true if damage was applied, false
# if the player was invulnerable. Equipment with damage_reduction stat mods
# and triggers can scale `amount` before calling this.
#
# from_pos is the world-space position of the damage source (enemy body,
# spike tile center, projectile impact). When provided, the player is
# knocked away from it for KNOCKBACK_SEC seconds with her movement input
# locked — SM's classic "get hit, fly backwards" behaviour.
func take_damage(amount: int, source: String = "", from_pos = null) -> bool:
    if _invuln_timer > 0.0 or amount <= 0:
        return false
    if _is_parry_active():
        if from_pos != null and typeof(from_pos) == TYPE_VECTOR2:
            var parry_target: Vector2 = from_pos
            _right = parry_target.x >= position.x
            if _sprite != null:
                _set_sprite_flip_all(not _right)
        _fire_parry_counter()
        return false
    hp = max(0, hp - amount)
    _invuln_timer = invuln_seconds

    if from_pos != null and typeof(from_pos) == TYPE_VECTOR2:
        var fp: Vector2 = from_pos
        var dx := position.x - fp.x
        var s := 1 if dx >= 0.0 else -1  # push away from source
        var v := velocity
        v.x = float(s) * KNOCKBACK_X_SPD
        v.y = -KNOCKBACK_Y_SPD
        velocity = v
        _knockback_timer = KNOCKBACK_SEC
        # Face the direction she got hit FROM so the sprite turns toward
        # the threat — matches SM's hit reaction.
        _right = s < 0
        if _sprite != null:
            _set_sprite_flip_all(not _right)
        _combo_grace_timer = 0.0
        _combo_grace_next_id = ""

    # SM rule: any hit cancels Speed Booster charge + shine state.
    _reset_shine()

    player_damaged.emit(amount, hp, source)
    MvTriggerEngine.fire_event("player_damage", {
        "amount": amount,
        "hp": hp,
        "max_hp": max_hp,
        "source": source,
    })
    if hp == 0:
        player_died.emit(source)
        MvTriggerEngine.fire_event("player_death", { "source": source })
    return true


func heal(amount: int) -> void:
    if amount <= 0:
        return
    hp = min(max_hp, hp + amount)


# ===== Energy (Nebula HUD vital) =====

# Restores energy up to the current cap. Used by future energy pickups.
func add_energy(amount: int) -> void:
    if amount <= 0:
        return
    energy = min(max_energy, energy + amount)


# Spends energy if enough is available; returns true on success. The hook a
# future spell/ability system calls before firing a costed attack.
func spend_energy(amount: int) -> bool:
    if amount <= 0:
        return true
    if energy < amount:
        return false
    energy = maxi(0, energy - amount)
    return true


# Raises the HP capacity by one tank (collectible upgrade), capped at
# HP_TANK_MAX tanks, and tops the player off to the new max.
func grant_hp_tank() -> void:
    max_hp = mini(HP_TANK_MAX * 100, ((max_hp / 100) + 1) * 100)
    hp = max_hp


# Raises the energy capacity by one tank, capped at ENERGY_TANK_MAX tanks.
func grant_energy_tank() -> void:
    max_energy = mini(ENERGY_TANK_MAX * 100, ((max_energy / 100) + 1) * 100)
    energy = max_energy


# Grants the player invulnerability frames for `seconds`. The existing
# _invuln_timer already gates damage in _check_spike_overlap and take_damage,
# so this just raises that timer when the requested duration is longer than
# what's already running.
func set_invuln(seconds: float) -> void:
    if seconds <= 0.0:
        return
    _invuln_timer = maxf(_invuln_timer, seconds)


# ===== Spike hazard detection =====
# Each physics frame, check if the player's collision rect overlaps any
# BT_SPIKE cells. If so, look up the spike profile from the room manager
# and apply damage + knockback + effect.

func _check_spike_overlap(_dt: float) -> void:
    if _invuln_timer > 0.0:
        return
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null or not room_mgr.has_method("query_spike_at"):
        return
    # Sample authored hurtbox points so hazards match the same pack-authored
    # vulnerable shape enemy projectiles already use.
    var sample_points := _hurtbox_sample_points()
    for pt in sample_points:
        var spike: Dictionary = room_mgr.query_spike_at(pt)
        if spike.is_empty():
            continue
        var dmg := int(spike.get("damage", 10))
        var kb_mode: String = str(spike.get("knockback", "push_away"))
        var spike_center := Vector2(float(spike.get("cx", pt.x)), float(spike.get("cy", pt.y)))

        # Apply knockback based on mode
        if kb_mode == "push_away":
            take_damage(dmg, "spike", spike_center)
        elif kb_mode == "launch_up":
            if take_damage(dmg, "spike", null):
                velocity.y = -KNOCKBACK_Y_SPD * 2.5
                velocity.x = 0.0
                _knockback_timer = KNOCKBACK_SEC
        elif kb_mode == "pull_in":
            if take_damage(dmg, "spike", null):
                var dir_to_spike := (spike_center - position).normalized()
                velocity = dir_to_spike * KNOCKBACK_X_SPD * 0.5
                _knockback_timer = KNOCKBACK_SEC * 0.5
        elif kb_mode == "none":
            take_damage(dmg, "spike", null)

        # Apply lasting effect
        var eff: String = str(spike.get("effect", "none"))
        if eff != "none":
            var eff_dur := float(spike.get("effect_duration", 0.0))
            var eff_tick_dmg := int(spike.get("effect_tick_damage", 0))
            var eff_tick_int := float(spike.get("effect_tick_interval", 0.5))
            var eff_speed := float(spike.get("effect_speed_mult", 1.0))
            apply_effect(eff, eff_dur, eff_tick_dmg, eff_tick_int, eff_speed)
        break  # Only process one spike hit per frame


# ===== Status effect system =====

func apply_effect(type: String, duration: float, tick_dmg: int = 0, tick_interval: float = 0.5, speed_mult: float = 1.0) -> void:
    if duration <= 0.0:
        return
    # Refresh existing effect of same type instead of stacking.
    for eff in _active_effects:
        if str(eff.get("type", "")) == type:
            eff["remaining"] = maxf(float(eff["remaining"]), duration)
            eff["tick_damage"] = tick_dmg
            eff["tick_interval"] = tick_interval
            eff["speed_mult"] = speed_mult
            return
    _active_effects.append({
        "type": type,
        "remaining": duration,
        "tick_interval": tick_interval,
        "tick_damage": tick_dmg,
        "speed_mult": speed_mult,
        "_tick_acc": 0.0,
    })


func _process_effects(dt: float) -> void:
    if _active_effects.is_empty():
        return
    var i := _active_effects.size() - 1
    while i >= 0:
        var eff: Dictionary = _active_effects[i]
        eff["remaining"] = float(eff["remaining"]) - dt

        # Tick damage (burn/poison)
        var tick_dmg := int(eff.get("tick_damage", 0))
        if tick_dmg > 0:
            eff["_tick_acc"] = float(eff.get("_tick_acc", 0.0)) + dt
            var interval := float(eff.get("tick_interval", 0.5))
            if interval > 0.0 and float(eff["_tick_acc"]) >= interval:
                eff["_tick_acc"] = float(eff["_tick_acc"]) - interval
                # Tick damage bypasses invuln and knockback — it's a DOT.
                hp = max(0, hp - tick_dmg)
                player_damaged.emit(tick_dmg, hp, str(eff.get("type", "effect")))
                if hp == 0:
                    player_died.emit(str(eff.get("type", "effect")))

        # Remove expired effects
        if float(eff["remaining"]) <= 0.0:
            _active_effects.remove_at(i)
        i -= 1


# Returns the current speed multiplier from all active effects. Called by
# the run physics to slow the player when a "slow" effect is active.
func get_effect_speed_mult() -> float:
    var mult := 1.0
    for eff in _active_effects:
        mult *= float(eff.get("speed_mult", 1.0))
    return mult


func clear_effects() -> void:
    _active_effects.clear()


func _build_hurtbox() -> void:
    _hurtbox_area = Area2D.new()
    _hurtbox_area.name = "Hurtbox"
    _hurtbox_area.monitoring = false
    _hurtbox_area.monitorable = true
    _hurtbox_area.add_to_group("mv_player_hurt")
    _hurtbox_area.set_meta("player", self)
    _hurtbox_col = CollisionShape2D.new()
    _hurtbox_rect = RectangleShape2D.new()
    _hurtbox_rect.size = Vector2(24, 32)
    _hurtbox_col.shape = _hurtbox_rect
    _hurtbox_col.position = Vector2(0, -16)
    _hurtbox_area.add_child(_hurtbox_col)
    add_child(_hurtbox_area)


func _build_interact_zone() -> void:
    _interact_zone = Area2D.new()
    _interact_zone.name = "InteractZone"
    var s := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(32, 32)
    s.shape = rect
    s.position = Vector2(0, -16)
    _interact_zone.add_child(s)
    _interact_zone.collision_layer = 0
    _interact_zone.collision_mask = 0x7fffffff
    add_child(_interact_zone)


func _unhandled_input(event: InputEvent) -> void:
    if MvGame.simulation_paused:
        return
    if event.is_action_pressed("interact"):
        _try_interact()
        get_viewport().set_input_as_handled()


func _try_interact() -> void:
    if _interact_zone == null:
        return

    # Find the nearest overlapping interactable body and call its
    # interact() method. Any node in the "mv_interactable" group with a
    # public interact() method qualifies — MvInteractable is the canonical
    # NPC/Sign implementation.
    var best: Node2D = null
    var best_dist := INF
    for body in _interact_zone.get_overlapping_bodies():
        if body.is_in_group("mv_interactable") and body.has_method("interact"):
            var d: float = (body as Node2D).global_position.distance_squared_to(global_position)
            if d < best_dist:
                best_dist = d
                best = body
    if best == null:
        for node in get_tree().get_nodes_in_group("mv_interactable"):
            if node is Node2D and node.has_method("interact"):
                var d2: float = (node as Node2D).global_position.distance_squared_to(global_position)
                if d2 <= 40.0 * 40.0 and d2 < best_dist:
                    best_dist = d2
                    best = node
    if best != null:
        best.call("interact")
        return

    # No interactable — fire a generic interact signal so triggers can
    # still hook "press E with empty hands while standing here".
    player_interacted.emit("none", position)
