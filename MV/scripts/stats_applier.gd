class_name StatsApplier
extends RefCounted

# Loads stats_manifest.json from the current pack at runtime, reads the
# player's current stat levels from PlayerInventory game_vars, computes
# which ManiaVar effects are active, and writes the composite values back
# to the live MvPhysicsProfile and player state.
#
# Call apply() after spawning the player and after any stat level-up.

# ManiaVars is a class_name — access it directly, no preload needed.


static func apply(player: MvPlayer, profile: MvPhysicsProfile) -> void:
	if player == null or profile == null:
		return
	var pack: MvPackRef = MvPackLoader.current_pack
	if pack == null:
		return

	var manifest := _load_manifest(pack)
	if manifest.is_empty():
		return

	var stats: Array = manifest.get("stats", [])
	if typeof(stats) != TYPE_ARRAY or stats.is_empty():
		return

	# Collect all active effects based on current stat levels.
	# Stat levels are stored as game_vars: "stat_<id>" = int level.
	# If no game_var exists, use the stat's base_value as the current level.
	var active_effects: Array = []
	for stat_v in stats:
		if typeof(stat_v) != TYPE_DICTIONARY:
			continue
		var stat: Dictionary = stat_v
		var stat_id: String = str(stat.get("id", ""))
		var base_value: int = int(stat.get("base_value", 0))
		var current_level: int = int(PlayerInventory.get_var("stat_%s" % stat_id, base_value))

		var effects_v: Variant = stat.get("effects", [])
		if typeof(effects_v) != TYPE_ARRAY:
			continue
		for eff_v in (effects_v as Array):
			if typeof(eff_v) != TYPE_DICTIONARY:
				continue
			var eff: Dictionary = eff_v
			var threshold: int = int(eff.get("level_threshold", 1))
			if current_level >= threshold:
				active_effects.append(eff)

	# Apply effects to the physics profile.
	# First pass: collect per-target operations.
	var targets: Dictionary = {}  # target_id -> [{operation, value}]
	for eff in active_effects:
		var target: String = str(eff.get("target", ""))
		var operation: String = str(eff.get("operation", "add"))
		var value: float = float(eff.get("value", 0.0))
		if target.is_empty():
			continue
		if not targets.has(target):
			targets[target] = []
		targets[target].append({"operation": operation, "value": value})

	# Apply to profile fields.
	for target in targets.keys():
		var ops: Array = targets[target]
		var base: float = _read_base(profile, player, target)
		var result: float = base
		# Apply "set" ops first (last one wins), then "multiply", then "add".
		var has_set := false
		var set_val := 0.0
		var multiply_total := 1.0
		var add_total := 0.0
		for op in ops:
			var operation: String = str(op["operation"])
			var value: float = float(op["value"])
			match operation:
				"set":
					has_set = true
					set_val = value
				"multiply":
					multiply_total *= value
				"add":
					add_total += value
		if has_set:
			result = set_val
		result *= multiply_total
		result += add_total
		_write_result(profile, player, target, result)

	print("[StatsApplier] applied %d effects from %d stats" % [active_effects.size(), stats.size()])


static func _load_manifest(pack: MvPackRef) -> Dictionary:
	return MvPackLoader.read_json_dict(pack.resolve_read("Player/stats_manifest.json"))


static func _read_base(profile: MvPhysicsProfile, player: MvPlayer, target: String) -> float:
	# Physics profile fields
	match target:
		"gravity": return profile.gravity
		"max_fall": return profile.max_fall
		"jump_speed": return profile.jump_speed
		"run_accel": return profile.run_accel
		"run_max": return profile.run_max
		"run_decel": return profile.run_decel
		"air_accel": return profile.air_accel
		"air_decel": return profile.air_decel
		"collision_width": return float(profile.collision_width)
		"beam_cooldown": return profile.beam_cooldown
		"max_beams": return float(profile.max_beams)
		"beam_charge_seconds": return profile.beam_charge_seconds
		"grapple_gravity": return profile.grapple_gravity
		"grapple_pump_power": return profile.grapple_pump_power
		"grapple_damping": return profile.grapple_damping
		"grapple_release_boost": return profile.grapple_release_boost
		"grapple_rotate_speed": return profile.grapple_rotate_speed
		"grapple_length_rate": return profile.grapple_length_rate
		"grapple_min_len": return profile.grapple_min_len
		"grapple_max_len": return profile.grapple_max_len
	# Player state fields
	match target:
		"max_hp": return float(player.max_hp)
		"invuln_seconds": return player.invuln_seconds
	# Combat/defense vars default to neutral values
	match target:
		"melee_damage_mult", "projectile_damage_mult", "melee_range_mult", "reload_speed_mult", "damage_mult":
			return 1.0
		"damage_reduction", "projectile_spread":
			return 0.0
	return 0.0


static func _write_result(profile: MvPhysicsProfile, player: MvPlayer, target: String, value: float) -> void:
	match target:
		"gravity": profile.gravity = value
		"max_fall": profile.max_fall = value
		"jump_speed": profile.jump_speed = value
		"run_accel": profile.run_accel = value
		"run_max": profile.run_max = value
		"run_decel": profile.run_decel = value
		"air_accel": profile.air_accel = value
		"air_decel": profile.air_decel = value
		"collision_width": profile.collision_width = int(value)
		"beam_cooldown": profile.beam_cooldown = value
		"max_beams": profile.max_beams = int(value)
		"beam_charge_seconds": profile.beam_charge_seconds = value
		"grapple_gravity": profile.grapple_gravity = value
		"grapple_pump_power": profile.grapple_pump_power = value
		"grapple_damping": profile.grapple_damping = value
		"grapple_release_boost": profile.grapple_release_boost = value
		"grapple_rotate_speed": profile.grapple_rotate_speed = value
		"grapple_length_rate": profile.grapple_length_rate = value
		"grapple_min_len": profile.grapple_min_len = value
		"grapple_max_len": profile.grapple_max_len = value
		"max_hp":
			player.max_hp = int(value)
			player.hp = mini(player.hp, player.max_hp)
		"invuln_seconds": player.invuln_seconds = value
		# Combat/defense vars stored as game_vars for other systems to read
		"melee_damage_mult", "projectile_damage_mult", "melee_range_mult", \
		"reload_speed_mult", "damage_mult", "damage_reduction", "projectile_spread":
			PlayerInventory.set_var("mv_%s" % target, value)
