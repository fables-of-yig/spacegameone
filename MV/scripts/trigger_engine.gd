extends Node


# ECA (Event-Condition-Action) trigger engine. Autoloaded as `MvTriggerEngine`.
#
# fire_event("pickup", { "item_id": "coin" }) iterates loaded rules whose
# event field matches, evaluates conditions, and runs actions. Condition and
# action handlers live in dictionaries so packs can register custom types
# without touching this file.

signal event_fired(event_type: String, payload: Dictionary)
signal debug_entry_added(entry: Dictionary)
signal debug_state_changed()

# Host-routed action signals. MV main.gd connects these so the engine
# doesn't need to carry direct references to rooms/entities.
signal action_spawn_entity(entity_id: String, pos: Vector2, data: Dictionary)
signal action_despawn_entity(entity_id: String)
signal action_spawn_entity_at_zone(entity_id: String, zone_id: String, data: Dictionary)
signal action_spawn_space_ship(class_id: String, anchor: String, pos: Vector2, use_wormhole: bool, delay: float)
signal action_spawn_space_enemies(class_id: String, count: int, dist_min: int, dist_max: int, use_wormhole: bool)
signal action_move_entity_to_zone(entity_ref: String, zone_id: String, speed: float)
signal action_play_entity_anim(entity_ref: String, anim_name: String, loop: bool, speed_scale: float)
signal action_set_entity_facing(entity_ref: String, direction: String, zone_id: String)
signal action_camera_focus(mode: String, target_ref: String, pos: Vector2, duration: float, speed: float)
signal action_camera_unlock()
signal action_set_room_weather(room_addr: String, preset: String, color: String, intensity: float, speed: float)

var _global_rules: Array = []
var _room_rules: Array = []
var _condition_handlers: Dictionary = {}
var _action_handlers: Dictionary = {}

# Global tag dictionary. Shared between MV and Space so triggers can
# branch on world-scoped state ("defeated_boss_ice", "met_shopkeep_a").
# Entity-scoped tags still travel in the event payload; see `_cond_has_tag`
# for the payload form.
var global_tags: Dictionary = {}
var quest_state: Dictionary = {}
const RESERVED_LOCAL_KEY: String = "__trigger_locals"
var debug_history: Array = []
var debug_enabled: bool = true
var debug_max_entries: int = 200
var _active_sequences: Dictionary = {}
var _next_sequence_id: int = 1
var _breakpoint_rules: Dictionary = {}
var _paused: bool = false
var _pause_reason: String = ""
var _persistent_rule_locals: Dictionary = {}
var _step_budget: int = 0


func _ready() -> void:
	_register_builtins()


# ── Public API ──────────────────────────────────────────────────────────

func fire_event(event_type: String, payload: Dictionary = {}) -> bool:
	var public_payload: Dictionary = _public_payload(payload)
	var matched_any: bool = false
	_push_debug("event", {
		"event": event_type,
		"payload": public_payload,
	})
	event_fired.emit(event_type, public_payload)
	for rule in _combined_rules():
		if rule.get("event", "") != event_type:
			continue
		if not bool(rule.get("enabled", true)):
			continue
		var rule_payload: Dictionary = _make_rule_payload(rule, public_payload)
		var matched: bool = _evaluate_conditions(rule.get("conditions", []), rule_payload)
		if matched:
			matched_any = true
			_push_debug("rule_match", {
				"rule_id": str(rule.get("id", "")),
				"event": event_type,
				"locals": _locals_snapshot(rule_payload),
			})
			if bool(rule.get("once", false)):
				rule["enabled"] = false
			_run_rule_sequence.call_deferred(rule.duplicate(true), rule_payload)
		else:
			_push_debug("rule_blocked", {
				"rule_id": str(rule.get("id", "")),
				"event": event_type,
			})
	return matched_any


func register_condition(type: String, handler: Callable) -> void:
	_condition_handlers[type] = handler


func register_action(type: String, handler: Callable) -> void:
	_action_handlers[type] = handler


func load_triggers(pack_id: String) -> void:
	_global_rules.clear()
	_load_file(pack_id, "Triggers", "global.json")


func clear() -> void:
	_global_rules.clear()
	_room_rules.clear()
	_active_sequences.clear()
	_paused = false
	_pause_reason = ""
	_step_budget = 0
	_persistent_rule_locals.clear()
	quest_state.clear()


func get_rules() -> Array:
	return _combined_rules()


func get_debug_history() -> Array:
	return debug_history.duplicate(true)


func get_active_sequences() -> Array:
	var out: Array = []
	for key in _active_sequences.keys():
		var seq_v: Variant = _active_sequences[key]
		if typeof(seq_v) == TYPE_DICTIONARY:
			out.append((seq_v as Dictionary).duplicate(true))
	return out


func get_breakpoints() -> Array:
	var out: Array = []
	for rule_id in _breakpoint_rules.keys():
		out.append(str(rule_id))
	out.sort()
	return out


func has_breakpoint(rule_id: String) -> bool:
	return _breakpoint_rules.has(rule_id.strip_edges())


func set_breakpoint(rule_id: String, enabled: bool) -> void:
	var trimmed: String = rule_id.strip_edges()
	if trimmed.is_empty():
		return
	if enabled:
		_breakpoint_rules[trimmed] = true
		_push_debug("breakpoint_set", {"rule_id": trimmed})
	else:
		_breakpoint_rules.erase(trimmed)
		_push_debug("breakpoint_cleared", {"rule_id": trimmed})
	debug_state_changed.emit()


func toggle_breakpoint(rule_id: String) -> bool:
	var enabled: bool = not has_breakpoint(rule_id)
	set_breakpoint(rule_id, enabled)
	return enabled


func clear_breakpoints() -> void:
	_breakpoint_rules.clear()
	_push_debug("breakpoints_cleared")
	debug_state_changed.emit()


func request_pause() -> void:
	if _paused:
		return
	_paused = true
	_pause_reason = "manual"
	_step_budget = 0
	_push_debug("paused", {"reason": _pause_reason})
	debug_state_changed.emit()


func resume_sequences() -> void:
	if not _paused:
		return
	_paused = false
	_pause_reason = ""
	_step_budget = 0
	_push_debug("resumed")
	debug_state_changed.emit()


func is_paused() -> bool:
	return _paused


func request_step(count: int = 1) -> void:
	var grant: int = maxi(1, count)
	_paused = true
	_pause_reason = "step"
	_step_budget += grant
	_push_debug("step_granted", {"count": grant, "budget": _step_budget})
	debug_state_changed.emit()


func get_step_budget() -> int:
	return _step_budget


func clear_debug_history() -> void:
	debug_history.clear()
	_active_sequences.clear()
	debug_state_changed.emit()


func set_room_triggers(rules: Variant) -> void:
	_room_rules.clear()
	for rule_v in TriggerRoot.flatten_rules(rules):
		if typeof(rule_v) == TYPE_DICTIONARY:
			_room_rules.append((rule_v as Dictionary).duplicate(true))


func clear_room_triggers() -> void:
	_room_rules.clear()


# Append one authored rule live, without a full reload. Routes through
# TriggerRoot.flatten_rules (like _load_file / set_room_triggers) so an
# injected rule is normalized exactly like a disk-loaded one. Returns the
# number of rules added. Used by the in-game dev console.
func add_global_rule(rule: Dictionary) -> int:
	var added: int = 0
	for rule_v in TriggerRoot.flatten_rules([rule]):
		if typeof(rule_v) == TYPE_DICTIONARY:
			_global_rules.append((rule_v as Dictionary).duplicate(true))
			added += 1
	return added


func add_room_rule(rule: Dictionary) -> int:
	var added: int = 0
	for rule_v in TriggerRoot.flatten_rules([rule]):
		if typeof(rule_v) == TYPE_DICTIONARY:
			_room_rules.append((rule_v as Dictionary).duplicate(true))
			added += 1
	return added


# ── Global tag API ──────────────────────────────────────────────────────

func set_global_tag(tag_name: String, value: Variant = true) -> void:
	if tag_name.is_empty():
		return
	if typeof(value) == TYPE_BOOL and not value:
		global_tags.erase(tag_name)
	else:
		global_tags[tag_name] = value


func get_global_tag(tag_name: String, default: Variant = null) -> Variant:
	return global_tags.get(tag_name, default)


func has_global_tag(tag_name: String) -> bool:
	return global_tags.has(tag_name)


func clear_global_tag(tag_name: String) -> void:
	global_tags.erase(tag_name)


func clear_global_tags() -> void:
	global_tags.clear()


func snapshot_global_tags() -> Dictionary:
	return global_tags.duplicate()


func restore_global_tags(data: Dictionary) -> void:
	global_tags = data.duplicate() if data != null else {}


func snapshot_runtime_state() -> Dictionary:
	return {
		"global_tags": global_tags.duplicate(true),
		"quest_state": quest_state.duplicate(true),
		"persistent_rule_locals": _persistent_rule_locals.duplicate(true),
		"rule_enabled": _rule_enabled_snapshot(),
	}


func restore_runtime_state(data: Dictionary) -> void:
	if data == null:
		return
	var tags_v: Variant = data.get("global_tags", null)
	if typeof(tags_v) == TYPE_DICTIONARY:
		global_tags = (tags_v as Dictionary).duplicate(true)
	var locals_v: Variant = data.get("persistent_rule_locals", {})
	_persistent_rule_locals = (locals_v as Dictionary).duplicate(true) if typeof(locals_v) == TYPE_DICTIONARY else {}
	var quests_v: Variant = data.get("quest_state", {})
	quest_state = (quests_v as Dictionary).duplicate(true) if typeof(quests_v) == TYPE_DICTIONARY else {}
	var enabled_v: Variant = data.get("rule_enabled", {})
	if typeof(enabled_v) == TYPE_DICTIONARY:
		_restore_rule_enabled_states(enabled_v)


func snapshot_quest_state() -> Dictionary:
	return quest_state.duplicate(true)


func restore_quest_state(data: Dictionary) -> void:
	quest_state = data.duplicate(true) if data != null else {}


func get_quest_state(quest_id: String = "") -> Dictionary:
	var qid := quest_id.strip_edges()
	if qid.is_empty():
		return quest_state.duplicate(true)
	var state_v: Variant = quest_state.get(qid, {})
	return (state_v as Dictionary).duplicate(true) if typeof(state_v) == TYPE_DICTIONARY else {}


func quest_status(quest_id: String) -> String:
	return str(_ensure_quest_state(quest_id, false).get("status", "inactive"))


func quest_stage(quest_id: String) -> String:
	return str(_ensure_quest_state(quest_id, false).get("stage_id", ""))


func is_quest_objective_complete(quest_id: String, stage_id: String, objective_id: String) -> bool:
	var state := _ensure_quest_state(quest_id, false)
	var stage := stage_id.strip_edges()
	if stage.is_empty():
		stage = str(state.get("stage_id", "")).strip_edges()
	var obj := objective_id.strip_edges()
	if state.is_empty() or stage.is_empty() or obj.is_empty():
		return false
	var completed_v: Variant = state.get("completed_objectives", {})
	if typeof(completed_v) != TYPE_DICTIONARY:
		return false
	var stage_v: Variant = (completed_v as Dictionary).get(stage, {})
	if typeof(stage_v) != TYPE_DICTIONARY:
		return false
	return bool((stage_v as Dictionary).get(obj, false))


# ── Condition evaluation ────────────────────────────────────────────────

func evaluate_condition(cond: Dictionary, payload: Dictionary) -> bool:
	var type: String = cond.get("type", "")
	if not _condition_handlers.has(type):
		push_warning("MvTriggerEngine: unknown condition type '%s'" % type)
		return false
	return _condition_handlers[type].call(cond, payload)


func _evaluate_conditions(conditions: Array, payload: Dictionary) -> bool:
	for cond in conditions:
		if not evaluate_condition(cond, payload):
			return false
	return true


# ── Action execution ────────────────────────────────────────────────────

func execute_action(action: Dictionary, payload: Dictionary) -> void:
	var type: String = action.get("type", "")
	if not _action_handlers.has(type):
		push_warning("MvTriggerEngine: unknown action type '%s'" % type)
		return
	_action_handlers[type].call(action, payload)


func _execute_actions(actions: Array, payload: Dictionary) -> void:
	for action in actions:
		execute_action(action, payload)


# ── File loading ────────────────────────────────────────────────────────

func _load_file(pack_id: String, folder: String, file_name: String) -> void:
	var path := MvPackLoader.resolve_read_cascade(pack_id, folder, file_name)
	var raw := MvPackLoader.read_json_dict(path)
	for rule_v in TriggerRoot.flatten_rules(raw):
		if typeof(rule_v) == TYPE_DICTIONARY:
			_global_rules.append((rule_v as Dictionary).duplicate(true))


func _combined_rules() -> Array:
	var out: Array = []
	out.append_array(_global_rules)
	out.append_array(_room_rules)
	return out


func _public_payload(payload: Dictionary) -> Dictionary:
	var out: Dictionary = payload.duplicate(true)
	out.erase(RESERVED_LOCAL_KEY)
	out.erase("__trigger_rule_id")
	out.erase("__trigger_local_defs")
	return out


func _make_rule_payload(rule: Dictionary, payload: Dictionary) -> Dictionary:
	var out: Dictionary = _public_payload(payload)
	out[RESERVED_LOCAL_KEY] = _instantiate_rule_locals(rule)
	out["__trigger_rule_id"] = str(rule.get("id", "")).strip_edges()
	out["__trigger_local_defs"] = _safe_local_defs(rule)
	return out


func _instantiate_rule_locals(rule: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rule_id: String = str(rule.get("id", "")).strip_edges()
	var stored: Dictionary = _persistent_rule_locals.get(rule_id, {}) if not rule_id.is_empty() else {}
	var locals_v: Variant = rule.get("locals", [])
	if typeof(locals_v) != TYPE_ARRAY:
		return out
	for local_v in locals_v:
		if typeof(local_v) != TYPE_DICTIONARY:
			continue
		var local: Dictionary = local_v
		var local_name: String = str(local.get("name", "")).strip_edges()
		if local_name.is_empty():
			continue
		var type_name: String = str(local.get("type", "int")).strip_edges().to_lower()
		if bool(local.get("persistent", false)) and stored.has(local_name):
			out[local_name] = _coerce_local_value(_coerce_local_default(type_name, local.get("default", "")), stored.get(local_name))
		else:
			out[local_name] = _coerce_local_default(type_name, local.get("default", ""))
	return out


func _safe_local_defs(rule: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var locals_v: Variant = rule.get("locals", [])
	if typeof(locals_v) != TYPE_ARRAY:
		return out
	for local_v in locals_v:
		if typeof(local_v) != TYPE_DICTIONARY:
			continue
		var local: Dictionary = local_v
		var local_name: String = str(local.get("name", "")).strip_edges()
		if local_name.is_empty():
			continue
		out[local_name] = local.duplicate(true)
	return out


func _coerce_local_default(type_name: String, value: Variant) -> Variant:
	match type_name:
		"float":
			return float(value)
		"bool":
			return _variant_to_bool(value)
		"string":
			return str(value)
		_:
			return int(value)


func _variant_to_bool(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	var text: String = str(value).strip_edges().to_lower()
	return text == "1" or text == "true" or text == "yes" or text == "on"


func _locals_dict(payload: Dictionary) -> Dictionary:
	var locals_v: Variant = payload.get(RESERVED_LOCAL_KEY, {})
	if typeof(locals_v) == TYPE_DICTIONARY:
		return locals_v
	return {}


func _get_local(payload: Dictionary, var_name: String, default: Variant = null) -> Variant:
	return _locals_dict(payload).get(var_name, default)


func _set_local(payload: Dictionary, var_name: String, value: Variant) -> void:
	if var_name.is_empty():
		return
	var locals := _locals_dict(payload)
	locals[var_name] = value
	payload[RESERVED_LOCAL_KEY] = locals
	_store_persistent_local(payload, var_name, value)


func _coerce_local_value(existing: Variant, raw_value: Variant) -> Variant:
	match typeof(existing):
		TYPE_FLOAT:
			return float(raw_value)
		TYPE_BOOL:
			return _variant_to_bool(raw_value)
		TYPE_STRING:
			return str(raw_value)
		TYPE_INT:
			return int(raw_value)
		_:
			return raw_value


func _store_wait_result(action: Dictionary, payload: Dictionary, result: bool) -> void:
	var local_name: String = str(action.get("result_local", "")).strip_edges()
	if local_name.is_empty():
		return
	_set_local(payload, local_name, result)


func _locals_snapshot(payload: Dictionary) -> Dictionary:
	return _locals_dict(payload).duplicate(true)


func _store_persistent_local(payload: Dictionary, var_name: String, value: Variant) -> void:
	var defs_v: Variant = payload.get("__trigger_local_defs", {})
	if typeof(defs_v) != TYPE_DICTIONARY:
		return
	var defs: Dictionary = defs_v
	var def_v: Variant = defs.get(var_name, {})
	if typeof(def_v) != TYPE_DICTIONARY:
		return
	var def: Dictionary = def_v
	if not bool(def.get("persistent", false)):
		return
	var rule_id: String = str(payload.get("__trigger_rule_id", "")).strip_edges()
	if rule_id.is_empty():
		return
	var stored_v: Variant = _persistent_rule_locals.get(rule_id, {})
	var stored: Dictionary = stored_v if typeof(stored_v) == TYPE_DICTIONARY else {}
	stored[var_name] = value
	_persistent_rule_locals[rule_id] = stored


func _ensure_quest_state(quest_id: String, create: bool) -> Dictionary:
	var qid := quest_id.strip_edges()
	if qid.is_empty():
		return {}
	var state_v: Variant = quest_state.get(qid, {})
	if typeof(state_v) == TYPE_DICTIONARY:
		return (state_v as Dictionary).duplicate(true)
	if not create:
		return {}
	return {
		"status": "inactive",
		"stage_id": "",
		"completed_objectives": {},
		"completed_stages": {},
	}


func _store_quest_state(quest_id: String, state: Dictionary) -> void:
	var qid := quest_id.strip_edges()
	if qid.is_empty():
		return
	quest_state[qid] = state.duplicate(true)


func _set_active_sequence(sequence_id: int, rule: Dictionary, step: int, wait_state: String, payload: Dictionary) -> void:
	_active_sequences[sequence_id] = {
		"sequence_id": sequence_id,
		"rule_id": str(rule.get("id", "")),
		"event": str(rule.get("event", "")),
		"step": step,
		"wait": wait_state,
		"locals": _locals_snapshot(payload),
	}
	debug_state_changed.emit()


func _push_debug(kind: String, fields: Dictionary = {}) -> void:
	if not debug_enabled:
		return
	var entry: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"kind": kind,
	}
	for key_v in fields.keys():
		entry[key_v] = fields[key_v]
	debug_history.append(entry)
	while debug_history.size() > debug_max_entries:
		debug_history.remove_at(0)
	debug_entry_added.emit(entry.duplicate(true))
	debug_state_changed.emit()


func _run_rule_sequence(rule: Dictionary, payload: Dictionary) -> void:
	var actions_v: Variant = rule.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	var sequence_id: int = _next_sequence_id
	_next_sequence_id += 1
	var rule_id: String = str(rule.get("id", "")).strip_edges()
	_set_active_sequence(sequence_id, rule, 0, "", payload)
	_push_debug("sequence_start", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"event": str(rule.get("event", "")),
		"locals": _locals_snapshot(payload),
	})
	await _await_pause_gate(sequence_id, rule, 0, payload, true)
	await _run_action_list(actions_v as Array, rule, payload, sequence_id)
	if not rule_id.is_empty():
		fire_event("trigger_sequence_finished", {"rule_id": rule_id})
	_push_debug("sequence_finished", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"locals": _locals_snapshot(payload),
	})
	_active_sequences.erase(sequence_id)
	debug_state_changed.emit()


# Iterates an action array sequentially, awaiting waits and recursing into
# any nested action arrays carried by structural actions (random_pick today,
# if/else in Phase E). Extracted from _run_rule_sequence so the same logic
# drives both the top-level rule body and nested branch bodies.
func _run_action_list(actions: Array, rule: Dictionary, payload: Dictionary, sequence_id: int) -> void:
	var rule_id: String = str(rule.get("id", "")).strip_edges()
	for action_idx in range(actions.size()):
		var action_v: Variant = actions[action_idx]
		if typeof(action_v) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_v
		var atype: String = str(action.get("type", ""))
		await _await_pause_gate(sequence_id, rule, action_idx, payload, false)
		_set_active_sequence(sequence_id, rule, action_idx, "", payload)
		if atype == "delay":
			var seconds: float = maxf(0.0, float(action.get("seconds", 0.0)))
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "delay",
				"seconds": seconds,
			})
			_set_active_sequence(sequence_id, rule, action_idx, "delay", payload)
			if seconds > 0.0:
				await get_tree().create_timer(seconds).timeout
			_push_debug("wait_end", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "delay",
			})
			continue
		if atype == "wait_for_event":
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "event",
				"event": str(action.get("event", "")),
			})
			_set_active_sequence(sequence_id, rule, action_idx, "wait_for_event", payload)
			await _await_event(action, payload, sequence_id, rule_id)
			continue
		if atype == "wait_for_move":
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "move",
				"entity": str(action.get("entity", "")),
			})
			_set_active_sequence(sequence_id, rule, action_idx, "wait_for_move", payload)
			await _await_scripted_move(action, payload, sequence_id, rule_id)
			continue
		if atype == "wait_for_anim":
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "anim",
				"entity": str(action.get("entity", "")),
				"anim": str(action.get("anim", "")),
			})
			_set_active_sequence(sequence_id, rule, action_idx, "wait_for_anim", payload)
			await _await_scripted_animation(action, payload, sequence_id, rule_id)
			continue
		if atype == "wait_for_camera":
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "camera",
			})
			_set_active_sequence(sequence_id, rule, action_idx, "wait_for_camera", payload)
			await _await_camera(action, payload, sequence_id, rule_id)
			continue
		if atype == "wait_for_dialogue":
			_push_debug("wait_start", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"wait": "dialogue",
			})
			_set_active_sequence(sequence_id, rule, action_idx, "wait_for_dialogue", payload)
			await _await_dialogue(action, payload, sequence_id, rule_id)
			continue
		if atype == "random_pick":
			_push_debug("action", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"action": atype,
				"step": action_idx,
				"locals": _locals_snapshot(payload),
			})
			await _run_random_pick(action, rule, payload, sequence_id)
			continue
		if atype == "if":
			_push_debug("action", {
				"sequence_id": sequence_id,
				"rule_id": rule_id,
				"action": atype,
				"step": action_idx,
				"locals": _locals_snapshot(payload),
			})
			await _run_if(action, rule, payload, sequence_id)
			continue
		_push_debug("action", {
			"sequence_id": sequence_id,
			"rule_id": rule_id,
			"action": atype,
			"step": action_idx,
			"locals": _locals_snapshot(payload),
		})
		execute_action(action, payload)
		_set_active_sequence(sequence_id, rule, action_idx + 1, "", payload)


# Weighted random branch: rolls across `options[].weight` and recurses
# into the chosen entry's `actions` array via _run_action_list. Missing
# weights default to 1.0; empty/zero-weight option arrays no-op. The
# nested action list inherits the parent rule's payload (so locals,
# breakpoints, and wait semantics work transparently inside a branch).
func _run_random_pick(action: Dictionary, rule: Dictionary, payload: Dictionary, sequence_id: int) -> void:
	var options_v: Variant = action.get("options", [])
	if typeof(options_v) != TYPE_ARRAY:
		return
	var options: Array = options_v
	if options.is_empty():
		return
	var total: float = 0.0
	for opt_v in options:
		if typeof(opt_v) != TYPE_DICTIONARY:
			continue
		total += maxf(0.0, float((opt_v as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return
	var roll: float = randf() * total
	var accumulated: float = 0.0
	var picked: Dictionary = {}
	for opt_v in options:
		if typeof(opt_v) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = opt_v
		var w: float = maxf(0.0, float(opt.get("weight", 1.0)))
		accumulated += w
		if roll <= accumulated:
			picked = opt
			break
	if picked.is_empty():
		return
	var nested_v: Variant = picked.get("actions", [])
	if typeof(nested_v) != TYPE_ARRAY:
		return
	_push_debug("random_pick", {
		"sequence_id": sequence_id,
		"rule_id": str(rule.get("id", "")),
		"roll": roll,
		"total_weight": total,
	})
	await _run_action_list(nested_v as Array, rule, payload, sequence_id)


func _await_pause_gate(sequence_id: int, rule: Dictionary, step: int, payload: Dictionary, check_breakpoint: bool) -> void:
	var hit_breakpoint: bool = check_breakpoint and has_breakpoint(str(rule.get("id", "")))
	if hit_breakpoint and not _paused:
		_paused = true
		_pause_reason = "breakpoint"
		_step_budget = 0
		_push_debug("breakpoint_hit", {
			"sequence_id": sequence_id,
			"rule_id": str(rule.get("id", "")),
			"step": step,
		})
		debug_state_changed.emit()
	if not _paused:
		return
	_set_active_sequence(sequence_id, rule, step, "paused", payload)
	while _paused and _step_budget <= 0:
		await get_tree().process_frame
	if _step_budget > 0:
		_step_budget -= 1
		_push_debug("step_consumed", {
			"sequence_id": sequence_id,
			"rule_id": str(rule.get("id", "")),
			"step": step,
			"remaining": _step_budget,
		})
	_set_active_sequence(sequence_id, rule, step, "", payload)


func _find_rule_ref(rule_id: String) -> Dictionary:
	var trimmed: String = rule_id.strip_edges()
	if trimmed.is_empty():
		return {}
	for rule_v in _room_rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		if str(rule.get("id", "")).strip_edges() == trimmed:
			return rule
	for rule_v in _global_rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		if str(rule.get("id", "")).strip_edges() == trimmed:
			return rule
	return {}


# ── Built-in handlers ──────────────────────────────────────────────────

func _rule_enabled_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for rule_v in _combined_rules():
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		var rule_id := str(rule.get("id", "")).strip_edges()
		if rule_id.is_empty():
			continue
		out[rule_id] = bool(rule.get("enabled", true))
	return out


func _restore_rule_enabled_states(states: Dictionary) -> void:
	for rule_v in _combined_rules():
		if typeof(rule_v) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_v
		var rule_id := str(rule.get("id", "")).strip_edges()
		if rule_id.is_empty() or not states.has(rule_id):
			continue
		rule["enabled"] = bool(states.get(rule_id, true))


func _register_builtins() -> void:
	# Conditions
	register_condition("payload_eq", _cond_payload_eq)
	register_condition("has_tag", _cond_has_tag)
	register_condition("has_global_tag", _cond_has_global_tag)
	register_condition("var_eq", _cond_var_eq)
	register_condition("var_gte", _cond_var_gte)
	register_condition("var_eq_var", _cond_var_eq_var)
	register_condition("var_gte_var", _cond_var_gte_var)
	register_condition("chance_roll", _cond_chance_roll)
	register_condition("local_var_eq", _cond_local_var_eq)
	register_condition("local_var_gte", _cond_local_var_gte)
	register_condition("has_item", _cond_has_item)
	register_condition("has_ability", _cond_has_ability)
	register_condition("has_flag", _cond_has_flag)
	register_condition("has_global_flag", _cond_has_global_flag)
	register_condition("quest_status", _cond_quest_status)
	register_condition("quest_stage", _cond_quest_stage)
	register_condition("quest_objective_done", _cond_quest_objective_done)
	register_condition("and", _cond_and)
	register_condition("or", _cond_or)
	register_condition("not", _cond_not)

	# Actions
	register_action("comment", _act_comment)
	register_action("delay", _act_delay)
	register_action("wait_for_event", _act_wait_for_event)
	register_action("wait_for_move", _act_wait_for_move)
	register_action("wait_for_anim", _act_wait_for_anim)
	register_action("wait_for_camera", _act_wait_for_camera)
	register_action("wait_for_dialogue", _act_wait_for_dialogue)
	register_action("log", _act_log)
	register_action("set_var", _act_set_var)
	register_action("add_var", _act_add_var)
	register_action("set_local_var", _act_set_local_var)
	register_action("add_local_var", _act_add_local_var)
	register_action("give_item", _act_give_item)
	register_action("take_item", _act_take_item)
	register_action("give_ability", _act_give_ability)
	register_action("revoke_ability", _act_revoke_ability)
	register_action("play_sfx", _act_play_sfx)
	register_action("start_dialogue", _act_start_dialogue)
	register_action("end_dialogue", _act_end_dialogue)
	register_action("start_shop", _act_start_shop)
	register_action("set_flag", _act_set_flag)
	register_action("quest_start", _act_quest_start)
	register_action("quest_set_stage", _act_quest_set_stage)
	register_action("quest_complete_objective", _act_quest_complete_objective)
	register_action("quest_complete_stage", _act_quest_complete_stage)
	register_action("quest_complete", _act_quest_complete)
	register_action("add_tag", _act_add_tag)
	register_action("remove_tag", _act_remove_tag)
	register_action("teleport_player", _act_teleport_player)
	register_action("lock_player", _act_lock_player)
	register_action("unlock_player", _act_unlock_player)
	register_action("spawn_player", _act_spawn_player)
	register_action("spawn_entity", _act_spawn_entity)
	register_action("spawn_fx", _act_spawn_fx)
	register_action("despawn_entity", _act_despawn_entity)
	register_action("spawn_entity_at_zone", _act_spawn_entity_at_zone)
	register_action("spawn_space_ship", _act_spawn_space_ship)
	register_action("spawn_space_enemies", _act_spawn_space_enemies)
	register_action("move_entity_to_zone", _act_move_entity_to_zone)
	register_action("play_entity_anim", _act_play_entity_anim)
	register_action("set_entity_facing", _act_set_entity_facing)
	register_action("camera_focus", _act_camera_focus)
	register_action("camera_unlock", _act_camera_unlock)
	register_action("set_room_weather", _act_set_room_weather)
	register_action("fire_event", _act_fire_event)
	register_action("set_trigger_enabled", _act_set_trigger_enabled)
	register_action("set_door_enabled", _act_set_door_enabled)
	register_action("set_door_locked", _act_set_door_locked)
	register_action("save_checkpoint", _act_save_checkpoint)
	register_action("return_to_space", _act_return_to_space)
	register_action("heal_player", _act_heal_player)
	register_action("damage_player", _act_damage_player)
	register_action("play_music", _act_play_music)
	register_action("stop_music", _act_stop_music)
	register_action("pause_game", _act_pause_game)
	register_action("resume_game", _act_resume_game)
	register_action("end_game", _act_end_game)
	register_action("quest_fail", _act_quest_fail)
	register_action("camera_shake", _act_camera_shake)
	register_action("screen_flash", _act_screen_flash)
	register_action("set_player_invuln", _act_set_player_invuln)
	register_action("show_toast", _act_show_toast)
	register_action("reveal_system", _act_reveal_system)
	register_action("unlock_poi", _act_unlock_poi)
	register_action("space_add_credits", _act_space_add_credits)
	register_action("space_set_credits", _act_space_set_credits)
	register_action("set_global_flag", _act_set_global_flag)
	register_action("clear_global_flag", _act_clear_global_flag)
	register_action("space_spawn_ship_on_return", _act_space_spawn_ship_on_return)
	register_action("random_pick", _act_random_pick)
	register_action("if", _act_if)


# ── Condition implementations ──────────────────────────────────────────

func _cond_payload_eq(cond: Dictionary, payload: Dictionary) -> bool:
	var key: String = cond.get("key", "")
	return str(payload.get(key, "")) == str(cond.get("value", ""))


func _cond_has_tag(cond: Dictionary, payload: Dictionary) -> bool:
	var tags: Variant = payload.get("tags", [])
	if typeof(tags) == TYPE_ARRAY:
		return cond.get("tag", "") in tags
	return false


func _cond_var_eq(cond: Dictionary, _payload: Dictionary) -> bool:
	var val = PlayerInventory.get_var(cond.get("name", ""), 0)
	return val == cond.get("value", 0)


func _cond_var_gte(cond: Dictionary, _payload: Dictionary) -> bool:
	var val = float(PlayerInventory.get_var(cond.get("name", ""), 0))
	return val >= float(cond.get("value", 0))


func _cond_var_eq_var(cond: Dictionary, _payload: Dictionary) -> bool:
	var a := float(PlayerInventory.get_var(str(cond.get("name_a", "")), 0))
	var b := float(PlayerInventory.get_var(str(cond.get("name_b", "")), 0))
	return a == b


func _cond_var_gte_var(cond: Dictionary, _payload: Dictionary) -> bool:
	var a := float(PlayerInventory.get_var(str(cond.get("name_a", "")), 0))
	var b := float(PlayerInventory.get_var(str(cond.get("name_b", "")), 0))
	return a >= b


func _cond_chance_roll(cond: Dictionary, _payload: Dictionary) -> bool:
	var percent: float = clampf(float(cond.get("percent", 100.0)), 0.0, 100.0)
	return randf() * 100.0 < percent


func _cond_local_var_eq(cond: Dictionary, payload: Dictionary) -> bool:
	var var_name: String = str(cond.get("name", "")).strip_edges()
	if var_name.is_empty():
		return false
	return str(_get_local(payload, var_name, "")) == str(cond.get("value", ""))


func _cond_local_var_gte(cond: Dictionary, payload: Dictionary) -> bool:
	var var_name: String = str(cond.get("name", "")).strip_edges()
	if var_name.is_empty():
		return false
	return float(_get_local(payload, var_name, 0.0)) >= float(cond.get("value", 0.0))


func _cond_has_item(cond: Dictionary, _payload: Dictionary) -> bool:
	return PlayerInventory.has_item(
		cond.get("id", ""),
		int(cond.get("min_count", 1)))


func _cond_has_ability(cond: Dictionary, _payload: Dictionary) -> bool:
	return PlayerInventory.has_ability(cond.get("id", ""))


func _cond_has_global_tag(cond: Dictionary, _payload: Dictionary) -> bool:
	var tag_name: String = str(cond.get("tag", ""))
	if tag_name.is_empty():
		return false
	if cond.has("value"):
		return str(global_tags.get(tag_name, "")) == str(cond.get("value", ""))
	return global_tags.has(tag_name)


func _cond_has_flag(cond: Dictionary, _payload: Dictionary) -> bool:
	var flag_name: String = str(cond.get("name", ""))
	if flag_name.is_empty():
		return false
	var expected: Variant = cond.get("value", true)
	var actual: Variant = PlayerInventory.get_var("flag_" + flag_name, false)
	return bool(actual) == bool(expected)


func _cond_quest_status(cond: Dictionary, _payload: Dictionary) -> bool:
	var quest_id := str(cond.get("quest_id", "")).strip_edges()
	var expected := str(cond.get("status", "")).strip_edges()
	return not quest_id.is_empty() and not expected.is_empty() and quest_status(quest_id) == expected


func _cond_quest_stage(cond: Dictionary, _payload: Dictionary) -> bool:
	var quest_id := str(cond.get("quest_id", "")).strip_edges()
	var expected := str(cond.get("stage_id", "")).strip_edges()
	return not quest_id.is_empty() and not expected.is_empty() and quest_stage(quest_id) == expected


func _cond_quest_objective_done(cond: Dictionary, _payload: Dictionary) -> bool:
	return is_quest_objective_complete(
		str(cond.get("quest_id", "")),
		str(cond.get("stage_id", "")),
		str(cond.get("objective_id", "")))


func _cond_and(cond: Dictionary, payload: Dictionary) -> bool:
	var children: Variant = cond.get("children", [])
	if typeof(children) != TYPE_ARRAY:
		return false
	for child in children:
		if not evaluate_condition(child, payload):
			return false
	return true


func _cond_or(cond: Dictionary, payload: Dictionary) -> bool:
	var children: Variant = cond.get("children", [])
	if typeof(children) != TYPE_ARRAY:
		return false
	for child in children:
		if evaluate_condition(child, payload):
			return true
	return false


func _cond_not(cond: Dictionary, payload: Dictionary) -> bool:
	var child: Variant = cond.get("child", {})
	if typeof(child) != TYPE_DICTIONARY:
		return true
	return not evaluate_condition(child, payload)


# ── Action implementations ─────────────────────────────────────────────

# NOTE: comment / delay / wait_for_* handlers below are intentional no-ops.
# These action types are intercepted earlier in _run_rule_sequence so the
# sequence runner can suspend/resume the coroutine, which a fire-and-forget
# handler can't do. The registrations exist only so the dispatcher recognises
# the type and doesn't log "unknown action". Don't add behaviour here — edit
# _run_rule_sequence (and the matching _await_* helpers) instead.

func _act_comment(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_delay(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_wait_for_event(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_wait_for_move(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_wait_for_anim(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_wait_for_camera(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_wait_for_dialogue(_action: Dictionary, _payload: Dictionary) -> void:
	pass


func _act_log(action: Dictionary, _payload: Dictionary) -> void:
	print("[Trigger] %s" % action.get("message", ""))


func _act_set_var(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.set_var(
		action.get("name", ""),
		action.get("value", 0))


func _act_add_var(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.add_var(
		action.get("name", ""),
		float(action.get("delta", 0)))


func _act_set_local_var(action: Dictionary, payload: Dictionary) -> void:
	var var_name: String = str(action.get("name", "")).strip_edges()
	if var_name.is_empty():
		return
	var existing: Variant = _get_local(payload, var_name, "")
	_set_local(payload, var_name, _coerce_local_value(existing, action.get("value", "")))


func _act_add_local_var(action: Dictionary, payload: Dictionary) -> void:
	var var_name: String = str(action.get("name", "")).strip_edges()
	if var_name.is_empty():
		return
	var current: Variant = _get_local(payload, var_name, 0.0)
	var delta: float = float(action.get("delta", 0.0))
	if typeof(current) == TYPE_INT:
		_set_local(payload, var_name, int(current) + int(delta))
	else:
		_set_local(payload, var_name, float(current) + delta)


func _act_give_item(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.add_item(
		action.get("id", ""),
		int(action.get("count", 1)))
	fire_event("item_gain", { "item_id": action.get("id", "") })


func _act_take_item(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.remove_item(
		action.get("id", ""),
		int(action.get("count", 1)))


func _act_give_ability(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.grant_ability(action.get("id", ""))


func _act_revoke_ability(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.revoke_ability(action.get("id", ""))


func _act_play_sfx(action: Dictionary, _payload: Dictionary) -> void:
	var sfx_name: String = action.get("name", "")
	if sfx_name.is_empty():
		return
	AudioManager.play_sfx(sfx_name)


func _act_start_dialogue(action: Dictionary, _payload: Dictionary) -> void:
	var dialogue_id: String = action.get("id", "")
	if dialogue_id.is_empty():
		return
	MvDialogueRunner.start(dialogue_id)


func _act_end_dialogue(_action: Dictionary, _payload: Dictionary) -> void:
	MvDialogueRunner.stop()


func _act_start_shop(action: Dictionary, _payload: Dictionary) -> void:
	var shop_id: String = action.get("id", "")
	if shop_id.is_empty():
		return
	MvShopUI.open_shop(shop_id)


func _act_set_flag(action: Dictionary, _payload: Dictionary) -> void:
	PlayerInventory.set_var(
		"flag_" + action.get("name", ""),
		action.get("value", true))


func _act_quest_start(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	if quest_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	state["status"] = "active"
	var stage_id := str(action.get("stage_id", "")).strip_edges()
	if not stage_id.is_empty():
		state["stage_id"] = stage_id
	_store_quest_state(quest_id, state)
	fire_event("quest_started", {
		"quest_id": quest_id,
		"stage_id": str(state.get("stage_id", "")),
	})


func _act_quest_set_stage(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	var stage_id := str(action.get("stage_id", "")).strip_edges()
	if quest_id.is_empty() or stage_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	state["status"] = "active"
	state["stage_id"] = stage_id
	_store_quest_state(quest_id, state)
	fire_event("quest_stage_changed", {
		"quest_id": quest_id,
		"stage_id": stage_id,
	})


func _act_quest_complete_objective(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	var objective_id := str(action.get("objective_id", "")).strip_edges()
	if quest_id.is_empty() or objective_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	state["status"] = "active"
	var stage_id := str(action.get("stage_id", "")).strip_edges()
	if stage_id.is_empty():
		stage_id = str(state.get("stage_id", "")).strip_edges()
	if stage_id.is_empty():
		return
	state["stage_id"] = stage_id
	var completed_v: Variant = state.get("completed_objectives", {})
	var completed: Dictionary = completed_v if typeof(completed_v) == TYPE_DICTIONARY else {}
	var stage_v: Variant = completed.get(stage_id, {})
	var stage_completed: Dictionary = stage_v if typeof(stage_v) == TYPE_DICTIONARY else {}
	stage_completed[objective_id] = true
	completed[stage_id] = stage_completed
	state["completed_objectives"] = completed
	_store_quest_state(quest_id, state)
	fire_event("quest_objective_completed", {
		"quest_id": quest_id,
		"stage_id": stage_id,
		"objective_id": objective_id,
	})


func _act_quest_complete_stage(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	if quest_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	var stage_id := str(action.get("stage_id", "")).strip_edges()
	if stage_id.is_empty():
		stage_id = str(state.get("stage_id", "")).strip_edges()
	if stage_id.is_empty():
		return
	var completed_v: Variant = state.get("completed_stages", {})
	var completed: Dictionary = completed_v if typeof(completed_v) == TYPE_DICTIONARY else {}
	completed[stage_id] = true
	state["status"] = "active"
	state["stage_id"] = stage_id
	state["completed_stages"] = completed
	_store_quest_state(quest_id, state)
	fire_event("quest_stage_completed", {
		"quest_id": quest_id,
		"stage_id": stage_id,
	})


func _act_quest_complete(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	if quest_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	state["status"] = "complete"
	_store_quest_state(quest_id, state)
	fire_event("quest_completed", {
		"quest_id": quest_id,
		"stage_id": str(state.get("stage_id", "")),
	})


func _act_add_tag(action: Dictionary, _payload: Dictionary) -> void:
	var tag_name: String = str(action.get("tag", ""))
	if tag_name.is_empty():
		return
	set_global_tag(tag_name, action.get("value", true))


func _act_remove_tag(action: Dictionary, _payload: Dictionary) -> void:
	clear_global_tag(str(action.get("tag", "")))


func _find_mv_player() -> Node:
	var players := get_tree().get_nodes_in_group("mv_player")
	if players.is_empty():
		return null
	return players[0]


func _act_teleport_player(action: Dictionary, _payload: Dictionary) -> void:
	var p := _find_mv_player()
	if p == null:
		return
	var x: float = float(action.get("x", p.position.x))
	var y: float = float(action.get("y", p.position.y))
	var room_addr: String = str(action.get("room", ""))
	if not room_addr.is_empty() and MvGame.main != null \
			and MvGame.main.has_method("load_from_snapshot"):
		MvGame.main.load_from_snapshot(room_addr, Vector2(x, y), -1)
	else:
		p.position = Vector2(x, y)


func _act_lock_player(_action: Dictionary, _payload: Dictionary) -> void:
	var p := _find_mv_player()
	if p != null and p.has_method("set_locked"):
		p.call("set_locked", true)


func _act_unlock_player(_action: Dictionary, _payload: Dictionary) -> void:
	var p := _find_mv_player()
	if p != null and p.has_method("set_locked"):
		p.call("set_locked", false)


func _act_spawn_player(action: Dictionary, _payload: Dictionary) -> void:
	if MvGame.main == null or not MvGame.main.has_method("spawn_player"):
		return
	var room_addr: String = str(action.get("room", "")).strip_edges()
	var zone_id: String = str(action.get("zone_id", action.get("zone", ""))).strip_edges()
	var entry_direction: String = str(action.get("entry_direction",
		action.get("direction", ""))).strip_edges().to_lower()
	var facing_direction: String = str(action.get("facing", "")).strip_edges().to_lower()
	var pos := Vector2(-1, -1)
	var x_text: String = str(action.get("x", "")).strip_edges()
	var y_text: String = str(action.get("y", "")).strip_edges()
	var use_position: bool
	if action.has("use_position"):
		use_position = bool(action.get("use_position", false))
	else:
		# Back-compat: rules saved before use_position existed had x/y as
		# opt_strings and treated populated text as "teleport here." Honor
		# that convention when the explicit toggle isn't present.
		use_position = not x_text.is_empty() and not y_text.is_empty()
	if use_position and _is_optional_float(x_text) and _is_optional_float(y_text) \
			and not x_text.is_empty() and not y_text.is_empty():
		pos = Vector2(float(x_text), float(y_text))
	MvGame.main.spawn_player(pos, room_addr, zone_id, entry_direction,
		bool(action.get("emit_event", true)), facing_direction)


func _act_spawn_entity(action: Dictionary, _payload: Dictionary) -> void:
	var eid: String = str(action.get("id", ""))
	if eid.is_empty():
		return
	var x: float = float(action.get("x", 0.0))
	var y: float = float(action.get("y", 0.0))
	var data: Dictionary = action.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	action_spawn_entity.emit(eid, Vector2(x, y), data)


func _act_spawn_fx(action: Dictionary, payload: Dictionary) -> void:
	var effect_id: String = str(action.get("effect_id", "")).strip_edges()
	if effect_id.is_empty():
		return
	var pos := Vector2.ZERO
	var x_text := str(action.get("x", "")).strip_edges()
	var y_text := str(action.get("y", "")).strip_edges()
	if not x_text.is_empty() and not y_text.is_empty() and x_text.is_valid_float() and y_text.is_valid_float():
		pos = Vector2(float(x_text), float(y_text))
	elif typeof(payload.get("position")) == TYPE_VECTOR2:
		pos = payload.get("position")
	MvFx.spawn("", effect_id, null, pos)


func _act_despawn_entity(action: Dictionary, _payload: Dictionary) -> void:
	var eid: String = str(action.get("id", ""))
	if eid.is_empty():
		return
	action_despawn_entity.emit(eid)


func _act_spawn_entity_at_zone(action: Dictionary, _payload: Dictionary) -> void:
	var eid: String = str(action.get("id", ""))
	var zone_id: String = str(action.get("zone_id", "")).strip_edges()
	if eid.is_empty() or zone_id.is_empty():
		return
	var data: Dictionary = action.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	action_spawn_entity_at_zone.emit(eid, zone_id, data)


func _act_spawn_space_ship(action: Dictionary, _payload: Dictionary) -> void:
	var class_id: String = str(action.get("class", "")).strip_edges()
	if class_id.is_empty():
		return
	var anchor: String = str(action.get("anchor", "player")).strip_edges().to_lower()
	if anchor.is_empty():
		anchor = "player"
	var pos := Vector2(float(action.get("x", 0.0)), float(action.get("y", 0.0)))
	var use_wormhole: bool = bool(action.get("wormhole", true))
	var delay: float = maxf(0.0, float(action.get("delay", 0.0)))
	action_spawn_space_ship.emit(class_id, anchor, pos, use_wormhole, delay)


func _act_spawn_space_enemies(action: Dictionary, _payload: Dictionary) -> void:
	var class_id: String = str(action.get("class_id", "")).strip_edges()
	if class_id.is_empty():
		return
	var count: int = maxi(1, int(action.get("count", 1)))
	var dist_min: int = int(action.get("dist_min", 600))
	var dist_max: int = int(action.get("dist_max", 800))
	var use_wormhole: bool = bool(action.get("use_wormhole", true))
	action_spawn_space_enemies.emit(class_id, count, dist_min, dist_max, use_wormhole)


func _act_move_entity_to_zone(action: Dictionary, _payload: Dictionary) -> void:
	var entity_ref: String = str(action.get("entity", "")).strip_edges()
	var zone_id: String = str(action.get("zone_id", "")).strip_edges()
	if entity_ref.is_empty() or zone_id.is_empty():
		return
	action_move_entity_to_zone.emit(entity_ref, zone_id, maxf(1.0, float(action.get("speed", 64.0))))


func _act_play_entity_anim(action: Dictionary, _payload: Dictionary) -> void:
	var entity_ref: String = str(action.get("entity", "")).strip_edges()
	var anim_name: String = str(action.get("anim", "")).strip_edges()
	if entity_ref.is_empty() or anim_name.is_empty():
		return
	action_play_entity_anim.emit(entity_ref, anim_name, bool(action.get("loop", true)), maxf(0.05, float(action.get("speed", 1.0))))


func _act_set_entity_facing(action: Dictionary, _payload: Dictionary) -> void:
	var entity_ref: String = str(action.get("entity", "")).strip_edges()
	var direction: String = str(action.get("direction", "")).strip_edges().to_lower()
	var zone_id: String = str(action.get("zone_id", "")).strip_edges()
	if entity_ref.is_empty() or direction.is_empty():
		return
	action_set_entity_facing.emit(entity_ref, direction, zone_id)


func _act_camera_focus(action: Dictionary, _payload: Dictionary) -> void:
	var mode: String = str(action.get("mode", "")).strip_edges().to_lower()
	if mode.is_empty():
		return
	var target_ref: String = str(action.get("target", "")).strip_edges()
	var pos := Vector2(float(action.get("x", 0.0)), float(action.get("y", 0.0)))
	var duration: float = maxf(0.0, float(action.get("duration", 0.0)))
	var speed: float = maxf(0.0, float(action.get("speed", 0.0)))
	action_camera_focus.emit(mode, target_ref, pos, duration, speed)


func _act_camera_unlock(_action: Dictionary, _payload: Dictionary) -> void:
	action_camera_unlock.emit()


func _act_set_room_weather(action: Dictionary, _payload: Dictionary) -> void:
	var room_addr: String = str(action.get("room", "")).strip_edges()
	var preset: String = str(action.get("preset", "none")).strip_edges().to_lower()
	var color: String = str(action.get("color", "cfe8ffff")).strip_edges()
	var intensity: float = clampf(float(action.get("intensity", 0.7)), 0.0, 2.0)
	var speed: float = clampf(float(action.get("speed", 1.0)), 0.0, 4.0)
	action_set_room_weather.emit(room_addr, preset, color, intensity, speed)


func _act_fire_event(action: Dictionary, payload: Dictionary) -> void:
	var event_name: String = str(action.get("event", "")).strip_edges()
	if event_name.is_empty():
		return
	var next_payload: Dictionary = _public_payload(payload) if bool(action.get("inherit_payload", false)) else {}
	var key: String = str(action.get("key", "")).strip_edges()
	if not key.is_empty():
		next_payload[key] = action.get("value", "")
	fire_event(event_name, next_payload)


func _act_set_trigger_enabled(action: Dictionary, _payload: Dictionary) -> void:
	var rule_id: String = str(action.get("id", "")).strip_edges()
	if rule_id.is_empty():
		return
	var rule: Dictionary = _find_rule_ref(rule_id)
	if rule.is_empty():
		push_warning("MvTriggerEngine: set_trigger_enabled could not find rule '%s'" % rule_id)
		return
	rule["enabled"] = bool(action.get("enabled", true))


func _act_set_door_enabled(action: Dictionary, _payload: Dictionary) -> void:
	var door_id: String = str(action.get("id", "")).strip_edges()
	if door_id.is_empty() or MvRoomState == null:
		return
	MvRoomState.set_door_enabled(door_id, bool(action.get("enabled", true)))


func _act_set_door_locked(action: Dictionary, _payload: Dictionary) -> void:
	var door_id: String = str(action.get("id", "")).strip_edges()
	if door_id.is_empty() or MvRoomState == null:
		return
	MvRoomState.set_door_locked(door_id, bool(action.get("locked", true)))


func _await_scripted_move(action: Dictionary, payload: Dictionary, sequence_id: int = -1, rule_id: String = "") -> void:
	var entity_ref: String = str(action.get("entity", "")).strip_edges()
	if entity_ref.is_empty() or MvGame.main == null:
		_store_wait_result(action, payload, false)
		return
	var timeout: float = maxf(0.0, float(action.get("timeout", 0.0)))
	var finished: bool = false
	if MvGame.main.has_method("wait_for_scripted_move"):
		finished = await MvGame.main.wait_for_scripted_move(entity_ref, timeout)
	_store_wait_result(action, payload, finished)
	_push_debug("wait_end" if finished else "wait_timeout", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"wait": "move",
		"entity": entity_ref,
	})


func _await_scripted_animation(action: Dictionary, payload: Dictionary, sequence_id: int = -1, rule_id: String = "") -> void:
	var entity_ref: String = str(action.get("entity", "")).strip_edges()
	if entity_ref.is_empty() or MvGame.main == null:
		_store_wait_result(action, payload, false)
		return
	var anim_name: String = str(action.get("anim", "")).strip_edges()
	var timeout: float = maxf(0.0, float(action.get("timeout", 0.0)))
	var finished: bool = false
	if MvGame.main.has_method("wait_for_scripted_animation"):
		finished = await MvGame.main.wait_for_scripted_animation(entity_ref, anim_name, timeout)
	_store_wait_result(action, payload, finished)
	_push_debug("wait_end" if finished else "wait_timeout", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"wait": "anim",
		"entity": entity_ref,
		"anim": anim_name,
	})


func _await_event(action: Dictionary, payload: Dictionary, sequence_id: int = -1, rule_id: String = "") -> void:
	var wanted_event: String = str(action.get("event", "")).strip_edges()
	if wanted_event.is_empty():
		_store_wait_result(action, payload, false)
		return
	var wanted_key: String = str(action.get("key", "")).strip_edges()
	var wanted_value: String = str(action.get("value", "")).strip_edges()
	var timeout: float = maxf(0.0, float(action.get("timeout", 0.0)))
	var matched: bool = false
	var started_ms: int = Time.get_ticks_msec()
	@warning_ignore("confusable_local_declaration")
	var on_event := func(event_type: String, payload: Dictionary) -> void:
		if matched or event_type != wanted_event:
			return
		if wanted_key.is_empty():
			@warning_ignore("confusable_capture_reassignment")
			matched = true
			return
		if str(payload.get(wanted_key, "")).strip_edges() == wanted_value:
			@warning_ignore("confusable_capture_reassignment")
			matched = true
	event_fired.connect(on_event)
	while not matched:
		if timeout > 0.0:
			var elapsed: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
			if elapsed >= timeout:
				_push_debug("wait_timeout", {
					"sequence_id": sequence_id,
					"rule_id": rule_id,
					"wait": "event",
					"event": wanted_event,
				})
				break
		await get_tree().process_frame
	if event_fired.is_connected(on_event):
		event_fired.disconnect(on_event)
	_store_wait_result(action, payload, matched)
	if matched:
		_push_debug("wait_end", {
			"sequence_id": sequence_id,
			"rule_id": rule_id,
			"wait": "event",
			"event": wanted_event,
		})


func _await_camera(action: Dictionary, payload: Dictionary, sequence_id: int = -1, rule_id: String = "") -> void:
	if MvGame.main == null or not MvGame.main.has_method("wait_for_camera_focus"):
		_store_wait_result(action, payload, false)
		return
	var timeout: float = maxf(0.0, float(action.get("timeout", 0.0)))
	var finished: bool = await MvGame.main.wait_for_camera_focus(timeout)
	_store_wait_result(action, payload, finished)
	_push_debug("wait_end" if finished else "wait_timeout", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"wait": "camera",
	})


func _await_dialogue(action: Dictionary, payload: Dictionary, sequence_id: int = -1, rule_id: String = "") -> void:
	if MvGame.main == null or not MvGame.main.has_method("wait_for_dialogue"):
		_store_wait_result(action, payload, false)
		return
	var timeout: float = maxf(0.0, float(action.get("timeout", 0.0)))
	var finished: bool = await MvGame.main.wait_for_dialogue(timeout)
	_store_wait_result(action, payload, finished)
	_push_debug("wait_end" if finished else "wait_timeout", {
		"sequence_id": sequence_id,
		"rule_id": rule_id,
		"wait": "dialogue",
	})


func _act_save_checkpoint(action: Dictionary, _payload: Dictionary) -> void:
	var slot: int = int(action.get("slot", 0))
	if MvSaveManager != null and MvSaveManager.has_method("save_game"):
		MvSaveManager.save_game(slot)


func _act_return_to_space(_action: Dictionary, _payload: Dictionary) -> void:
	if MvGame.main == null:
		return
	if MvGame.main.has_method("launch_to_space"):
		MvGame.main.launch_to_space()
	else:
		PlanetaryInterface.begin_launch(MvGame.main)


func _act_heal_player(action: Dictionary, _payload: Dictionary) -> void:
	var amount: int = int(action.get("amount", 0))
	if amount <= 0:
		return
	var p := _find_mv_player()
	if p != null and p.has_method("heal"):
		p.call("heal", amount)


func _act_damage_player(action: Dictionary, _payload: Dictionary) -> void:
	var amount: int = int(action.get("amount", 0))
	if amount <= 0:
		return
	var p := _find_mv_player()
	if p != null and p.has_method("take_damage"):
		p.call("take_damage", amount, str(action.get("source", "")), null)


func _act_play_music(action: Dictionary, _payload: Dictionary) -> void:
	var track: String = str(action.get("track", "")).strip_edges()
	var am: Node = get_node_or_null("/root/AudioManager")
	if am == null or not am.has_method("set_ambient"):
		return
	am.call("set_ambient", track)


func _act_stop_music(_action: Dictionary, _payload: Dictionary) -> void:
	var am: Node = get_node_or_null("/root/AudioManager")
	if am == null or not am.has_method("set_ambient"):
		return
	am.call("set_ambient", "")


func _act_pause_game(_action: Dictionary, _payload: Dictionary) -> void:
	if MvGame != null:
		MvGame.simulation_paused = true


func _act_resume_game(_action: Dictionary, _payload: Dictionary) -> void:
	if MvGame != null:
		MvGame.simulation_paused = false


func _act_end_game(_action: Dictionary, _payload: Dictionary) -> void:
	if MvGameOver != null and MvGameOver.has_method("show_game_over"):
		MvGameOver.call("show_game_over")


func _act_quest_fail(action: Dictionary, _payload: Dictionary) -> void:
	var quest_id := str(action.get("quest_id", "")).strip_edges()
	if quest_id.is_empty():
		return
	var state := _ensure_quest_state(quest_id, true)
	state["status"] = "failed"
	_store_quest_state(quest_id, state)
	fire_event("quest_failed", {
		"quest_id": quest_id,
		"stage_id": str(state.get("stage_id", "")),
	})


func _act_camera_shake(action: Dictionary, _payload: Dictionary) -> void:
	if MvGame.main == null or not MvGame.main.has_method("camera_shake"):
		return
	var intensity: float = float(action.get("intensity", 0.0))
	var duration: float = float(action.get("duration", 0.0))
	MvGame.main.call("camera_shake", intensity, duration)


func _act_screen_flash(action: Dictionary, _payload: Dictionary) -> void:
	if MvGame.main == null or not MvGame.main.has_method("screen_flash"):
		return
	var color_text: String = str(action.get("color", "")).strip_edges()
	var color: Color = Color(1.0, 1.0, 1.0, 1.0)
	if not color_text.is_empty():
		color = Color.html(color_text) if Color.html_is_valid(color_text) else color
	var duration: float = float(action.get("duration", 0.2))
	MvGame.main.call("screen_flash", color, duration)


func _act_set_player_invuln(action: Dictionary, _payload: Dictionary) -> void:
	var seconds: float = float(action.get("seconds", 0.0))
	if seconds <= 0.0:
		return
	var p := _find_mv_player()
	if p != null and p.has_method("set_invuln"):
		p.call("set_invuln", seconds)


func _act_show_toast(action: Dictionary, _payload: Dictionary) -> void:
	var message: String = str(action.get("message", "")).strip_edges()
	if message.is_empty():
		return
	var duration: float = float(action.get("duration", 0.0))
	if duration <= 0.0:
		duration = 2.5
	var style: String = str(action.get("style", "info")).strip_edges()
	if style.is_empty():
		style = "info"
	var hud: Node = _find_mv_hud()
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", message, duration, style)


func _find_mv_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("mv_hud")


func _act_reveal_system(action: Dictionary, _payload: Dictionary) -> void:
	var sys_id: String = str(action.get("system_id", "")).strip_edges()
	if sys_id.is_empty():
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var visited_v: Variant = gm.get("visited_systems")
	if typeof(visited_v) != TYPE_ARRAY:
		return
	var visited: Array = visited_v
	if sys_id in visited:
		return
	visited.append(sys_id)
	gm.set("visited_systems", visited)


# Flip a `hidden: true` POI to visible by recording its id in
# GameManager.unlocked_pois. The change takes effect the next time the
# player jumps into `system_id` (spawn_system_pois reads the map at
# system entry); the POI does not appear live in the current session.
func _act_unlock_poi(action: Dictionary, _payload: Dictionary) -> void:
	var sys_id: String = str(action.get("system_id", "")).strip_edges()
	var poi_id: String = str(action.get("poi_id", "")).strip_edges()
	if sys_id.is_empty() or poi_id.is_empty():
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.has_method("unlock_poi"):
		gm.call("unlock_poi", sys_id, poi_id)


func _act_space_add_credits(action: Dictionary, _payload: Dictionary) -> void:
	var amount: int = int(action.get("amount", 0))
	if amount == 0:
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var current: int = int(gm.get("credits"))
	gm.set("credits", maxi(0, current + amount))


func _act_space_set_credits(action: Dictionary, _payload: Dictionary) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	gm.set("credits", maxi(0, int(action.get("amount", 0))))


func _act_set_global_flag(action: Dictionary, _payload: Dictionary) -> void:
	var flag_name: String = str(action.get("name", "")).strip_edges()
	if flag_name.is_empty():
		return
	var pi: Node = get_node_or_null("/root/PlanetaryInterface")
	if pi == null or not pi.has_method("set_global_flag"):
		return
	pi.call("set_global_flag", flag_name, action.get("value", true))


func _act_clear_global_flag(action: Dictionary, _payload: Dictionary) -> void:
	var flag_name: String = str(action.get("name", "")).strip_edges()
	if flag_name.is_empty():
		return
	var pi: Node = get_node_or_null("/root/PlanetaryInterface")
	if pi == null or not pi.has_method("clear_global_flag"):
		return
	pi.call("clear_global_flag", flag_name)


func _act_space_spawn_ship_on_return(action: Dictionary, _payload: Dictionary) -> void:
	var cls: String = str(action.get("class", "")).strip_edges()
	var sys_id: String = str(action.get("system_id", "")).strip_edges()
	if cls.is_empty() or sys_id.is_empty():
		return
	var pi: Node = get_node_or_null("/root/PlanetaryInterface")
	if pi == null or not pi.has_method("queue_ship_spawn"):
		return
	pi.call("queue_ship_spawn", sys_id, cls)


# Stub: the real logic lives in _run_action_list / _run_random_pick because
# the runner needs to await the chosen branch's nested actions (waits,
# breakpoints) cooperatively. This handler exists only so dispatching the
# raw action type by hand doesn't log an "unknown action" warning.
func _act_random_pick(_action: Dictionary, _payload: Dictionary) -> void:
	pass


# Stub: same pattern as random_pick — _run_action_list intercepts `if` and
# routes through _run_if to await the chosen branch.
func _act_if(_action: Dictionary, _payload: Dictionary) -> void:
	pass


# Inline conditional branch. Evaluates the action's `conditions` array
# against the current payload, then runs either `then` or `else` via
# _run_action_list. Both branches inherit the parent rule's payload so
# locals/waits/breakpoints work the same as in a flat sequence.
func _run_if(action: Dictionary, rule: Dictionary, payload: Dictionary, sequence_id: int) -> void:
	var conds_v: Variant = action.get("conditions", [])
	var conditions: Array = conds_v if typeof(conds_v) == TYPE_ARRAY else []
	var passed: bool = _evaluate_conditions(conditions, payload)
	_push_debug("if_branch", {
		"sequence_id": sequence_id,
		"rule_id": str(rule.get("id", "")),
		"passed": passed,
		"condition_count": conditions.size(),
	})
	var branch_key: String = "then" if passed else "else"
	var branch_v: Variant = action.get(branch_key, [])
	if typeof(branch_v) != TYPE_ARRAY:
		return
	await _run_action_list(branch_v as Array, rule, payload, sequence_id)


func _cond_has_global_flag(cond: Dictionary, _payload: Dictionary) -> bool:
	var flag_name: String = str(cond.get("name", "")).strip_edges()
	if flag_name.is_empty():
		return false
	var pi: Node = get_node_or_null("/root/PlanetaryInterface")
	if pi == null or not pi.has_method("get_global_flag"):
		return false
	var actual: Variant = pi.call("get_global_flag", flag_name, null)
	if cond.has("value"):
		return actual == cond.get("value")
	return actual != null


func _is_optional_float(text: String) -> bool:
	if text.is_empty():
		return true
	var start: int = 0
	var saw_dot: bool = false
	var saw_digit: bool = false
	if text.begins_with("-"):
		if text.length() == 1:
			return false
		start = 1
	for i in range(start, text.length()):
		var ch: int = text.unicode_at(i)
		if ch == 46:
			if saw_dot:
				return false
			saw_dot = true
			continue
		if ch < 48 or ch > 57:
			return false
		saw_digit = true
	return saw_digit
