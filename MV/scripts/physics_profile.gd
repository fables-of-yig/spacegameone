class_name MvPhysicsProfile
extends Resource

# Per-content-pack physics constants for the Player controller. Every value
# here derives from Super Metroid ROM constants — see the comments for the
# SNES addresses. Saved as a .tres resource in each content pack so different
# packs can have different movement feels without touching code.
#
# SNES -> Godot unit conversion:
#   V = 60 px/frame  -> px/s   (60 fps)
#   A = 3600 px/frame^2 -> px/s^2

# Gravity — ROM $90:9EA1 $1C00 = 0.109375 px/frame^2 * A
@export var gravity: float = 0.109375 * 3600.0

# Terminal fall speed — ROM $90:910F CMP #5 = 5.0 px/frame * V
@export var max_fall: float = 5.0 * 60.0

# Initial jump velocity — ROM $90:9EB9 $0004.$E000 = 4.875 px/frame * V
@export var jump_speed: float = 4.875 * 60.0

# Ground run — ROM $90:9F55[1] accel / max / decel
@export var run_accel: float = 0.1875 * 3600.0
@export var run_max:   float = 2.75   * 60.0
@export var run_decel: float = 0.5    * 3600.0

# Airborne control — ROM $90:9F55[2]
@export var air_accel: float = 0.75 * 3600.0
@export var air_decel: float = 0.5  * 3600.0

# Collision width (constant across poses, diortem Samus.cs ColW)
@export var collision_width: int = 14

# Beam cooldown — ROM $90:C254 = 15 SNES frames between shots
@export var beam_cooldown: float = 15.0 / 60.0

# Max simultaneous beam projectiles — ROM $90:AC3C CMP #$0005
@export var max_beams: int = 5

# Beam charge time — hold shoot this long to fire a charged shot
@export var beam_charge_seconds: float = 0.6

# Grapple behavior. PENDULUM is the modern metroidvania swing (gravity-driven,
# pump with move stick to build amplitude). CLASSIC mimics the Super Metroid
# grapple (fixed rotation rate, left/right rotates the rope, up/down adjusts
# length). Packs choose per-pack in their .tres.
enum GrappleMode { PENDULUM = 0, CLASSIC = 1 }
@export var grapple_mode: GrappleMode = GrappleMode.PENDULUM

# Pendulum-mode tunables (ignored in Classic mode).
@export var grapple_gravity:       float = 600.0
@export var grapple_pump_power:    float = 4.0
@export var grapple_damping:       float = 0.4
@export var grapple_release_boost: float = 1.1

# Classic-mode tunables (ignored in Pendulum mode).
@export var grapple_rotate_speed: float = 2.2    # rad/s while rotating
@export var grapple_length_rate:  float = 60.0   # px/s for up/down trim
@export var grapple_min_len:      float = 8.0
@export var grapple_max_len:      float = 240.0

# Show a HUD health bar while a boss enemy is active. Off by default because
# plenty of metroidvania packs prefer to communicate boss state visually
# (sprite damage, camera zoom) rather than with an explicit bar.
@export var show_boss_hp_bar: bool = false
