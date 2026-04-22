class_name ManiaVars
extends RefCounted

# ManiaVars: the vocabulary of runtime physics/gameplay variables that player
# stats, equipment, abilities, and zone overrides can modify. Each ManiaVar
# maps to a field on MvPhysicsProfile or a player state value.
#
# The stat system uses effects that target ManiaVar names. At runtime, a
# StatsApplier computes the composite value from base profile + all active
# effects, then writes the result back to the live profile/player state.

# ─── Registry ────────────────────────────────────────────────────────────
# Every known ManiaVar: { id, label, description, category, type, default }

const VARS: Array = [
	# Movement & Gravity
	{"id": "gravity", "label": "Gravity", "desc": "Downward acceleration (px/s²). Lower = floatier jumps.", "category": "movement", "type": "float"},
	{"id": "max_fall", "label": "Max Fall Speed", "desc": "Terminal fall velocity (px/s). Caps how fast the player drops.", "category": "movement", "type": "float"},
	{"id": "jump_speed", "label": "Jump Speed", "desc": "Initial upward velocity on jump (px/s). Higher = higher jumps.", "category": "movement", "type": "float"},
	{"id": "run_accel", "label": "Run Accel", "desc": "Ground run acceleration (px/s²). How quickly the player reaches top speed.", "category": "movement", "type": "float"},
	{"id": "run_max", "label": "Run Max Speed", "desc": "Top ground running speed (px/s).", "category": "movement", "type": "float"},
	{"id": "run_decel", "label": "Run Decel", "desc": "Ground deceleration when releasing input (px/s²). Higher = snappier stops.", "category": "movement", "type": "float"},
	{"id": "air_accel", "label": "Air Accel", "desc": "Horizontal acceleration while airborne (px/s²).", "category": "movement", "type": "float"},
	{"id": "air_decel", "label": "Air Decel", "desc": "Horizontal deceleration while airborne (px/s²).", "category": "movement", "type": "float"},
	{"id": "collision_width", "label": "Collision Width", "desc": "Player hitbox width in pixels.", "category": "movement", "type": "int"},

	# Weapons
	{"id": "beam_cooldown", "label": "Beam Cooldown", "desc": "Seconds between shots.", "category": "weapon", "type": "float"},
	{"id": "max_beams", "label": "Max Beams", "desc": "Maximum simultaneous beam projectiles on screen.", "category": "weapon", "type": "int"},
	{"id": "beam_charge_seconds", "label": "Charge Time", "desc": "Seconds to hold shoot for a charged shot.", "category": "weapon", "type": "float"},

	# Grapple
	{"id": "grapple_gravity", "label": "Grapple Gravity", "desc": "Pendulum gravity strength (px/s²).", "category": "grapple", "type": "float"},
	{"id": "grapple_pump_power", "label": "Grapple Pump", "desc": "Pendulum pump amplification from input.", "category": "grapple", "type": "float"},
	{"id": "grapple_damping", "label": "Grapple Damping", "desc": "Pendulum energy loss per second.", "category": "grapple", "type": "float"},
	{"id": "grapple_release_boost", "label": "Grapple Release Boost", "desc": "Velocity multiplier on grapple release.", "category": "grapple", "type": "float"},
	{"id": "grapple_rotate_speed", "label": "Grapple Rotate Speed", "desc": "Classic mode rotation rate (rad/s).", "category": "grapple", "type": "float"},
	{"id": "grapple_length_rate", "label": "Grapple Length Rate", "desc": "Classic mode reel speed (px/s).", "category": "grapple", "type": "float"},
	{"id": "grapple_min_len", "label": "Grapple Min Length", "desc": "Minimum grapple rope length (px).", "category": "grapple", "type": "float"},
	{"id": "grapple_max_len", "label": "Grapple Max Length", "desc": "Maximum grapple rope length (px).", "category": "grapple", "type": "float"},

	# Player state
	{"id": "max_hp", "label": "Max HP", "desc": "Maximum hit points.", "category": "player", "type": "int"},
	{"id": "max_mp", "label": "Max MP", "desc": "Maximum magic/energy points.", "category": "player", "type": "int"},
	{"id": "max_heart", "label": "Max Heart", "desc": "Maximum heart resource.", "category": "player", "type": "int"},
	{"id": "invuln_seconds", "label": "I-Frames Duration", "desc": "Invulnerability duration after taking damage (seconds).", "category": "player", "type": "float"},

	# Combat
	{"id": "melee_damage_mult", "label": "Melee Damage Mult", "desc": "Multiplier on all melee attack damage.", "category": "combat", "type": "float"},
	{"id": "projectile_damage_mult", "label": "Projectile Damage Mult", "desc": "Multiplier on all projectile damage.", "category": "combat", "type": "float"},
	{"id": "projectile_spread", "label": "Projectile Spread", "desc": "Angle spread in degrees for projectile accuracy.", "category": "combat", "type": "float"},
	{"id": "melee_range_mult", "label": "Melee Range Mult", "desc": "Multiplier on melee hitbox size.", "category": "combat", "type": "float"},
	{"id": "reload_speed_mult", "label": "Reload Speed Mult", "desc": "Multiplier on weapon cooldown speed (higher = faster).", "category": "combat", "type": "float"},

	# Defenses
	{"id": "damage_reduction", "label": "Damage Reduction", "desc": "Flat damage subtracted from each hit before HP loss.", "category": "defense", "type": "int"},
	{"id": "damage_mult", "label": "Damage Taken Mult", "desc": "Multiplier on incoming damage (0.5 = half damage).", "category": "defense", "type": "float"},
]

const CATEGORIES: Array = ["movement", "weapon", "grapple", "player", "combat", "defense"]

const CATEGORY_LABELS: Dictionary = {
	"movement": "Movement & Gravity",
	"weapon": "Weapons & Beams",
	"grapple": "Grapple",
	"player": "Player State",
	"combat": "Combat & Offense",
	"defense": "Defense & Resistance",
}

const OPERATIONS: Array = ["add", "multiply", "set"]

const OPERATION_LABELS: Dictionary = {
	"add": "Add (+/-)",
	"multiply": "Multiply (×)",
	"set": "Set (=)",
}


static func get_var_ids() -> Array:
	var out: Array = []
	for v in VARS:
		out.append(str(v["id"]))
	return out


static func get_var_info(var_id: String) -> Dictionary:
	for v in VARS:
		if str(v["id"]) == var_id:
			return v
	return {}


static func get_vars_in_category(category: String) -> Array:
	var out: Array = []
	for v in VARS:
		if str(v["category"]) == category:
			out.append(v)
	return out


# Read a ManiaVar's base value from a physics profile.
static func read_from_profile(profile: MvPhysicsProfile, var_id: String) -> float:
	if profile == null:
		return 0.0
	if var_id in ["gravity", "max_fall", "jump_speed", "run_accel", "run_max",
			"run_decel", "air_accel", "air_decel", "beam_cooldown",
			"beam_charge_seconds", "grapple_gravity", "grapple_pump_power",
			"grapple_damping", "grapple_release_boost", "grapple_rotate_speed",
			"grapple_length_rate", "grapple_min_len", "grapple_max_len"]:
		return float(profile.get(var_id))
	if var_id == "collision_width":
		return float(profile.collision_width)
	if var_id == "max_beams":
		return float(profile.max_beams)
	return 0.0


# Apply a single effect to a running value.
static func apply_effect(current: float, operation: String, value: float) -> float:
	match operation:
		"add":
			return current + value
		"multiply":
			return current * value
		"set":
			return value
	return current


# Default effect entry.
static func default_effect() -> Dictionary:
	return {
		"target": "gravity",
		"operation": "add",
		"value": 0.0,
		"level_threshold": 1,
	}
