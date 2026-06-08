class_name MvFx
extends RefCounted

# Global spawner + cache for authored effects. Resolves an effect id to a def
# (built-in EffIO.default_effects() layered under the pack's Effects/effects.json)
# and spawns an MvAuthoredFx renderer into the live MV world. Call clear_cache()
# after authoring an effect so the new def is picked up on the next spawn.

const EffIO := preload("res://Space/scripts/shared/eff/eff_io.gd")
const _AuthoredFx := preload("res://MV/scripts/authored_fx.gd")

static var _cache: Dictionary = {}   # pack_id -> { effect_id: def }


static func _resolve_pack_id(pack_id: String) -> String:
	if not pack_id.strip_edges().is_empty():
		return pack_id
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	return "demo"


# id -> def, with the pack's effects.json layered over the built-in seed set.
static func effects(pack_id: String) -> Dictionary:
	var pid := _resolve_pack_id(pack_id)
	if _cache.has(pid):
		return _cache[pid]
	var out: Dictionary = {}
	for d in EffIO.default_effects():
		if typeof(d) == TYPE_DICTIONARY:
			out[str((d as Dictionary).get("id", ""))] = d
	var packed: Variant = EffIO.load_or_init(pid).get("effects", [])
	if typeof(packed) == TYPE_ARRAY:
		for d in packed:
			if typeof(d) == TYPE_DICTIONARY:
				var did := str((d as Dictionary).get("id", "")).strip_edges()
				if not did.is_empty():
					out[did] = d
	out.erase("")
	_cache[pid] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


static func list_ids(pack_id: String) -> Array:
	var ids := effects(pack_id).keys()
	ids.sort()
	return ids


static func find(pack_id: String, effect_id: String) -> Dictionary:
	var d: Variant = effects(pack_id).get(effect_id, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


# Spawn an authored effect by id. Returns the node, or null if the id is unknown.
static func spawn(pack_id: String, effect_id: String, parent: Node, pos: Vector2, direction: Vector2 = Vector2.ZERO) -> Node:
	var def := find(pack_id, effect_id)
	if def.is_empty():
		push_warning("MvFx: unknown effect id '%s'" % effect_id)
		return null
	return spawn_def(def, parent, pos, direction)


# Spawn directly from an effect def (used for live preview before saving).
static func spawn_def(def: Dictionary, parent: Node, pos: Vector2, direction: Vector2 = Vector2.ZERO) -> Node:
	if def.is_empty():
		return null
	var host := parent
	if host == null or not is_instance_valid(host):
		host = _world_parent()
	if host == null:
		return null
	var fx := _AuthoredFx.new()
	host.add_child(fx)
	fx.setup(def, pos, direction)
	return fx


static func _world_parent() -> Node:
	if MvGame.room_manager != null and is_instance_valid(MvGame.room_manager):
		return MvGame.room_manager
	if MvGame.main != null and is_instance_valid(MvGame.main):
		return MvGame.main
	return null
