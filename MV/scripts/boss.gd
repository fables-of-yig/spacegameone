class_name MvBoss
extends MvEnemy

# Boss enemy with HP phases, arena locking, and HUD integration.
# Extends MvEnemy so behavior trees, sprites, and physics work identically.
# Configure phases in the entity's properties:
#   phases: [{ "hp_pct": 0.5, "behavior": "boss_phase2" }]
#   arena_lock: true  — fires lock/unlock events on engage/defeat

var boss_hp: int = 100
var boss_max_hp: int = 100
var _phases: Array = []
var _current_phase: int = 0
var _engaged: bool = false
var _defeated: bool = false
var _arena_lock: bool = false

signal boss_engaged
signal boss_defeated
signal boss_hp_changed(current: int, maximum: int)


func _ready() -> void:
	super._ready()
	add_to_group("mv_boss")
	_load_boss_config()


func _load_boss_config() -> void:
	boss_max_hp = int(_entity.get("hp", 100))
	boss_hp = boss_max_hp
	_arena_lock = str(_entity.get("arena_lock", "false")).to_lower() == "true" \
		or _entity.get("arena_lock", false) == true

	var phases_v: Variant = _entity.get("phases", [])
	if typeof(phases_v) == TYPE_ARRAY:
		_phases = phases_v


func engage() -> void:
	if _engaged:
		return
	_engaged = true
	boss_engaged.emit()
	boss_hp_changed.emit(boss_hp, boss_max_hp)

	if _arena_lock:
		MvTriggerEngine.fire_event("boss_arena_lock", { "entity_id": entity_id })

	var hud := _find_hud()
	if hud != null:
		hud.set_boss(boss_hp, boss_max_hp)


func take_damage(amount: int, _from_pos = null) -> void:
	if _defeated or amount <= 0:
		return
	if not _engaged:
		engage()

	boss_hp = maxi(boss_hp - amount, 0)
	_hit_flash_timer = 0.15
	boss_hp_changed.emit(boss_hp, boss_max_hp)
	enemy_damaged.emit(amount, boss_hp)

	var hud := _find_hud()
	if hud != null:
		hud.set_boss(boss_hp, boss_max_hp)

	_check_phases()

	if boss_hp <= 0:
		_on_defeat()


func _check_phases() -> void:
	if _phases.is_empty():
		return
	var hp_pct := float(boss_hp) / float(maxi(boss_max_hp, 1))
	for i in range(_current_phase, _phases.size()):
		var phase: Dictionary = _phases[i]
		var threshold := float(phase.get("hp_pct", 0))
		if hp_pct <= threshold:
			_current_phase = i + 1
			MvTriggerEngine.fire_event("boss_phase", {
				"entity_id": entity_id,
				"phase": _current_phase,
			})


func _on_defeat() -> void:
	_defeated = true
	boss_defeated.emit()
	MvTriggerEngine.fire_event("boss_defeated", { "entity_id": entity_id })

	if _arena_lock:
		MvTriggerEngine.fire_event("boss_arena_unlock", { "entity_id": entity_id })

	var hud := _find_hud()
	if hud != null:
		hud.hide_boss()

	queue_free()


func _find_hud() -> Node:
	var huds := get_tree().get_nodes_in_group("mv_hud")
	if not huds.is_empty():
		return huds[0]
	# Fallback: try the autoload by name
	return get_node_or_null("/root/MvHud")
