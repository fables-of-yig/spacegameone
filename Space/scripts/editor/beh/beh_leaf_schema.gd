class_name BehLeafSchema
extends RefCounted

# Schemas for every registered Beehave leaf (action or condition).
# Used by beh_props_panel.gd to render per-leaf-type param forms so
# authors don't have to remember which params each leaf accepts.
#
# Shape:
#   {name, label, kind ("action"|"condition"), fields: [...], help: String}
# Each field: [key, label, kind_str, default] where kind_str is one of
# "int", "float", "string", "bool", or "enum:val1|val2|...".

const ACTIONS: Array = [
	{"name": "idle", "label": "Idle", "fields": [],
	 "help": "Stops horizontal motion. Always SUCCESS."},
	{"name": "walk", "label": "Walk (by facing)",
	 "fields": [
		["dir", "direction (-1, 0=facing, +1)", "int", 0],
		["speed", "speed (px/s)", "float", 40.0],
	 ], "help": "Drives x-velocity by beh_facing; dir overrides."},
	{"name": "walk_left", "label": "Walk Left",
	 "fields": [["speed", "speed (px/s)", "float", 40.0]],
	 "help": "Always left. Does NOT flip beh_facing."},
	{"name": "walk_right", "label": "Walk Right",
	 "fields": [["speed", "speed (px/s)", "float", 40.0]],
	 "help": "Always right. Does NOT flip beh_facing."},
	{"name": "jump", "label": "Jump",
	 "fields": [["impulse", "impulse (px/s)", "float", 240.0]],
	 "help": "Upward impulse when on floor; FAILURE in air."},
	{"name": "turn_around", "label": "Turn Around",
	 "fields": [["cooldown", "cooldown (s)", "float", 0.4]],
	 "help": "Flips beh_facing. Cooldown prevents oscillation."},
	{"name": "attack", "label": "Melee Attack",
	 "fields": [
		["range", "range (px)", "float", 24.0],
		["damage", "damage (0=use actor's)", "int", 0],
		["cooldown", "cooldown (s)", "float", 0.8],
	 ], "help": "Hits nearest mv_player in range. SUCCESS if in range; FAILURE otherwise."},
	{"name": "flee", "label": "Flee From Player",
	 "fields": [["speed", "speed (px/s)", "float", 60.0]],
	 "help": "Run away from nearest mv_player. FAILURE if no player."},
	{"name": "pursue", "label": "Pursue Player",
	 "fields": [["speed", "speed (px/s)", "float", 80.0]],
	 "help": "Chase nearest mv_player. FAILURE if no player."},
	{"name": "flee_fly", "label": "Flee Fly",
	 "fields": [["speed", "speed (px/s)", "float", 60.0]],
	 "help": "Fly away from the nearest mv_player in both axes. Intended for hover/fly enemies."},
	{"name": "pursue_fly", "label": "Pursue Fly",
	 "fields": [["speed", "speed (px/s)", "float", 80.0]],
	 "help": "Fly toward the nearest mv_player in both axes. Intended for hover/fly enemies."},
	{"name": "patrol_point", "label": "Patrol to X",
	 "fields": [
		["target_x", "target world-x (px)", "float", 0.0],
		["speed", "speed (px/s)", "float", 40.0],
		["tolerance", "arrive radius (px)", "float", 4.0],
	 ], "help": "Walk toward target_x; flips facing on arrive. Two of these in sequence_star = ping-pong."},
	{"name": "shoot", "label": "Shoot Projectile",
	 "fields": [
		["speed", "projectile speed (px/s)", "float", 180.0],
		["damage", "damage", "int", 1],
		["lifetime", "lifetime (s)", "float", 2.0],
		["aim", "aim mode", "enum:facing|player", "facing"],
		["cooldown", "cooldown (s)", "float", 1.2],
	 ], "help": "Spawns an MvProjectile. Aim 'player' tracks nearest; 'facing' uses beh_facing."},
	{"name": "dash", "label": "Dash",
	 "fields": [
		["speed", "peak speed (px/s)", "float", 200.0],
		["duration", "dash length (s)", "float", 0.25],
		["cooldown", "cooldown (s)", "float", 1.5],
		["dir", "direction (0=facing, -1, +1)", "int", 0],
	 ], "help": "Short burst of horizontal velocity. RUNNING during dash, SUCCESS on end, FAILURE during cooldown."},
]

const CONDITIONS: Array = [
	{"name": "always", "label": "Always (true)", "fields": [],
	 "help": "Placeholder / true branch."},
	{"name": "wall_ahead", "label": "Wall Ahead", "fields": [],
	 "help": "CharacterBody2D.is_on_wall()."},
	{"name": "grounded", "label": "Grounded", "fields": [],
	 "help": "CharacterBody2D.is_on_floor()."},
	{"name": "in_air", "label": "In Air", "fields": [],
	 "help": "NOT on floor."},
	{"name": "player_near", "label": "Player Near",
	 "fields": [["range", "range (px)", "float", 80.0]],
	 "help": "Any mv_player within range, ignoring line-of-sight."},
	{"name": "edge_ahead", "label": "Edge Ahead",
	 "fields": [
		["ahead_px", "probe forward (px)", "float", 10.0],
		["drop_px", "probe down (px)", "float", 16.0],
	 ], "help": "No floor a short distance ahead of facing. Useful to stop before a ledge."},
	{"name": "player_seen", "label": "Player Seen",
	 "fields": [["range", "range (px)", "float", 150.0]],
	 "help": "In range AND line-of-sight to mv_player."},
	{"name": "hp_low", "label": "HP Low",
	 "fields": [["threshold", "threshold (<=1 is fraction, >1 is absolute)", "float", 0.3]],
	 "help": "SUCCESS when hp <= threshold (fraction of max or absolute)."},
	{"name": "cooldown_ready", "label": "Cooldown Ready",
	 "fields": [
		["name", "timer name", "string", "cd"],
		["seconds", "cooldown (s)", "float", 1.0],
	 ], "help": "Named timer. First tick SUCCESS, then FAILURE until `seconds` elapses."},
]


static func find_schema(leaf_kind: String, leaf_name: String) -> Dictionary:
	var pool: Array = ACTIONS if leaf_kind == "action" else CONDITIONS
	for entry_v in pool:
		var entry: Dictionary = entry_v
		if entry.get("name") == leaf_name:
			return entry
	return {}


static func action_names() -> Array:
	var out: Array = []
	for entry_v in ACTIONS:
		out.append(str((entry_v as Dictionary).get("name")))
	return out


static func condition_names() -> Array:
	var out: Array = []
	for entry_v in CONDITIONS:
		out.append(str((entry_v as Dictionary).get("name")))
	return out


static func action_labels() -> Array:
	var out: Array = []
	for entry_v in ACTIONS:
		out.append(str((entry_v as Dictionary).get("label")))
	return out


static func condition_labels() -> Array:
	var out: Array = []
	for entry_v in CONDITIONS:
		out.append(str((entry_v as Dictionary).get("label")))
	return out


static func default_params_for(leaf_kind: String, leaf_name: String) -> Dictionary:
	var schema := find_schema(leaf_kind, leaf_name)
	if schema.is_empty():
		return {}
	var out: Dictionary = {}
	var fields: Array = schema.get("fields", [])
	for f_v in fields:
		var f: Array = f_v
		out[str(f[0])] = f[3]
	return out


static func parse_value(raw: String, kind_str: String) -> Variant:
	var trimmed := raw.strip_edges()
	if kind_str == "int":
		if trimmed.is_valid_int():
			return int(trimmed)
		if trimmed.is_valid_float():
			return int(float(trimmed))
		return 0
	if kind_str == "float":
		if trimmed.is_valid_float():
			return float(trimmed)
		return 0.0
	if kind_str == "bool":
		return trimmed.to_lower() == "true" or trimmed == "1"
	if kind_str.begins_with("enum:"):
		return trimmed
	return trimmed


static func is_enum(kind_str: String) -> bool:
	return kind_str.begins_with("enum:")


static func enum_values(kind_str: String) -> Array:
	if not is_enum(kind_str):
		return []
	var rest := kind_str.substr("enum:".length())
	return rest.split("|")
