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
	{"name": "idle", "label": "Stand still", "fields": [],
	 "help": "The actor stops moving for this tick."},
	{"name": "walk", "label": "Walk forward",
	 "fields": [
		["dir", "direction (-1, 0=facing, +1)", "int", 0],
		["speed", "speed (px/s)", "float", 40.0],
	 ], "help": "The actor walks in its current facing direction unless direction overrides it."},
	{"name": "walk_left", "label": "Walk left",
	 "fields": [["speed", "speed (px/s)", "float", 40.0]],
	 "help": "The actor always walks left."},
	{"name": "walk_right", "label": "Walk right",
	 "fields": [["speed", "speed (px/s)", "float", 40.0]],
	 "help": "The actor always walks right."},
	{"name": "jump", "label": "Jump",
	 "fields": [["impulse", "impulse (px/s)", "float", 240.0]],
	 "help": "The actor jumps if it is standing on the floor."},
	{"name": "turn_around", "label": "Turn around",
	 "fields": [["cooldown", "cooldown (s)", "float", 0.4]],
	 "help": "The actor flips to face the other way. Cooldown prevents rapid flickering."},
	{"name": "attack", "label": "Attack in melee",
	 "fields": [
		["range", "range (px)", "float", 24.0],
		["damage", "damage (0=use actor's)", "int", 0],
		["cooldown", "cooldown (s)", "float", 0.8],
	 ], "help": "The actor hits the player if the player is close enough."},
	{"name": "flee", "label": "Run away from the player",
	 "fields": [["speed", "speed (px/s)", "float", 60.0]],
	 "help": "The actor runs away from the nearest player."},
	{"name": "pursue", "label": "Chase the player",
	 "fields": [["speed", "speed (px/s)", "float", 80.0]],
	 "help": "The actor chases the nearest player."},
	{"name": "flee_fly", "label": "Fly away from the player",
	 "fields": [["speed", "speed (px/s)", "float", 60.0]],
	 "help": "A flying actor moves away from the nearest player in both axes."},
	{"name": "pursue_fly", "label": "Fly toward the player",
	 "fields": [["speed", "speed (px/s)", "float", 80.0]],
	 "help": "A flying actor moves toward the nearest player in both axes."},
	{"name": "patrol_point", "label": "Walk to patrol point",
	 "fields": [
		["target_x", "target world-x (px)", "float", 0.0],
		["speed", "speed (px/s)", "float", 40.0],
		["tolerance", "arrive radius (px)", "float", 4.0],
	 ], "help": "The actor walks toward a target X position and turns around when it arrives."},
	{"name": "shoot", "label": "Shoot a projectile",
	 "fields": [
		["speed", "projectile speed (px/s)", "float", 180.0],
		["damage", "damage", "int", 1],
		["lifetime", "lifetime (s)", "float", 2.0],
		["aim", "aim mode", "enum:facing|player", "facing"],
		["cooldown", "cooldown (s)", "float", 1.2],
	 ], "help": "The actor fires a projectile. Aim can use the actor's facing or the player's position."},
	{"name": "dash", "label": "Dash",
	 "fields": [
		["speed", "peak speed (px/s)", "float", 200.0],
		["duration", "dash length (s)", "float", 0.25],
		["cooldown", "cooldown (s)", "float", 1.5],
		["dir", "direction (0=facing, -1, +1)", "int", 0],
	 ], "help": "The actor makes a short burst of horizontal movement."},
]

const CONDITIONS: Array = [
	{"name": "always", "label": "Always true", "fields": [],
	 "help": "This check always passes."},
	{"name": "wall_ahead", "label": "Wall ahead", "fields": [],
	 "help": "Passes when the actor is touching a wall."},
	{"name": "grounded", "label": "On the ground", "fields": [],
	 "help": "Passes when the actor is standing on the floor."},
	{"name": "in_air", "label": "In the air", "fields": [],
	 "help": "Passes when the actor is not on the floor."},
	{"name": "player_near", "label": "Player is nearby",
	 "fields": [["range", "range (px)", "float", 80.0]],
	 "help": "Passes when any player is within range, ignoring line of sight."},
	{"name": "edge_ahead", "label": "Ledge ahead",
	 "fields": [
		["ahead_px", "probe forward (px)", "float", 10.0],
		["drop_px", "probe down (px)", "float", 16.0],
	 ], "help": "Passes when there is no floor a short distance ahead. Useful to stop before a ledge."},
	{"name": "player_seen", "label": "Player is visible",
	 "fields": [["range", "range (px)", "float", 150.0]],
	 "help": "Passes when the player is in range and line of sight."},
	{"name": "hp_low", "label": "Health is low",
	 "fields": [["threshold", "threshold (<=1 is fraction, >1 is absolute)", "float", 0.3]],
	 "help": "Passes when health is below the threshold. Values under 1 are treated as a fraction of max health."},
	{"name": "cooldown_ready", "label": "Enough time has passed",
	 "fields": [
		["name", "timer name", "string", "cd"],
		["seconds", "cooldown (s)", "float", 1.0],
	 ], "help": "Passes once, then waits the chosen number of seconds before passing again."},
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
