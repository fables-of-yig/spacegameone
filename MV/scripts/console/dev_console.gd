class_name MvDevConsole
extends CanvasLayer

# In-game developer console — Slice 1 of the in-game authoring build.
#
# Toggle with the backtick/tilde key (wired in MvMain._input). While open the
# simulation is frozen (MvGame.simulation_paused) so the player, camera and
# enemy AI hold still. You can:
#   - paste a trigger JSON object/array   → validated, injected live, and saved
#                                           to the pack's Triggers/global.json
#   - fire <event> [json payload]         → fire a test event
#   - spawn <entity_id>                   → spawn an entity at the player
#   - flag <name>=<value>                 → set a global flag
#   - help / clear
#
# Validation reuses EcaSchema — the same action/condition vocabulary the
# desktop editor and ContentValidator use — so a bad paste is rejected with a
# reason instead of failing silently. Persistence reuses PedIO.save_triggers,
# which re-validates and writes in the editor's exact format (copy-on-write to
# the user pack). No new serialization, no format drift.
#
# Autoloads used: MvGame, MvTriggerEngine, PlanetaryInterface. Global classes:
# MvPackLoader (current pack). EcaSchema/PedIO are preloaded under private
# aliases so they can't collide with any class_name registration.

const _Eca = preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const _Ped = preload("res://Space/scripts/shared/ped/ped_io.gd")

const _LOGICAL_CONDITIONS := ["and", "or", "not"]

var _log_view: RichTextLabel = null
var _entry: TextEdit = null
var _open: bool = false
var _prev_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	_build_ui()
	visible = false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "DEV CONSOLE   ·   Ctrl+Enter run   ·   Esc / ` close"
	vbox.add_child(title)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_active = true
	_log_view.scroll_following = true
	_log_view.focus_mode = Control.FOCUS_NONE
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_view)

	_entry = TextEdit.new()
	_entry.placeholder_text = "Paste trigger JSON or type a command (help)…"
	_entry.custom_minimum_size = Vector2(0, 54)
	_entry.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(_entry)


# ── Open / close ──────────────────────────────────────────────────────────

func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_prev_paused = MvGame.simulation_paused
	MvGame.simulation_paused = true
	PlanetaryInterface.edit_session_active = true
	if _log_view.get_parsed_text().strip_edges().is_empty():
		_print_help()
	_entry.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	MvGame.simulation_paused = _prev_paused
	PlanetaryInterface.edit_session_active = false


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif (ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER) and ke.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_submit()


# ── Submit / dispatch ──────────────────────────────────────────────────────

func _submit() -> void:
	var text := _entry.text.strip_edges()
	if text.is_empty():
		return
	var echo := text
	var nl := text.find("\n")
	if nl >= 0:
		echo = text.substr(0, nl) + " …"
	_log("[color=#8ab4ff]> %s[/color]" % _escape(echo))

	var ok := false
	if text.begins_with("{") or text.begins_with("["):
		ok = _handle_json(text)
	else:
		ok = _handle_command(text)

	if ok:
		_entry.text = ""
	else:
		_entry.select_all()
	_entry.grab_focus.call_deferred()


# ── Trigger JSON path ──────────────────────────────────────────────────────

func _handle_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_err("invalid JSON — parse failed")
		return false

	var rules: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		rules = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if typeof(d.get("triggers")) == TYPE_ARRAY:
			rules = d.get("triggers")  # accept a full {triggers:[...]} root
		else:
			rules = [d]                 # or a single bare rule
	else:
		_err("expected a trigger object or an array of triggers")
		return false

	if rules.is_empty():
		_err("no triggers found in input")
		return false

	var all_ok := true
	for rule_v in rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			_err("skipped a non-object entry in the array")
			all_ok = false
			continue
		if not _inject_and_persist(rule_v as Dictionary):
			all_ok = false
	return all_ok


func _inject_and_persist(rule: Dictionary) -> bool:
	var rid := str(rule.get("id", "")).strip_edges()
	var label := rid if not rid.is_empty() else "(unnamed)"

	var report := _validate_trigger(rule)
	for w in report["warnings"]:
		_warn(str(w))
	if not (report["errors"] as Array).is_empty():
		for e in report["errors"]:
			_err(str(e))
		_err("rejected '%s' — fix the above and re-paste" % label)
		return false

	if not rid.is_empty() and _rule_id_exists(rid):
		_warn("a rule with id '%s' already exists — skipped (rename to add a copy)" % rid)
		return false

	# Persist first (copy-on-write to the user pack; PedIO re-validates), then
	# go live — so the in-memory rules and the on-disk file never disagree.
	var pack_id := _current_pack_id()
	var root := _Ped.load_triggers(pack_id)
	var arr_v: Variant = root.get("triggers", [])
	var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
	arr.append(rule)
	root["triggers"] = arr
	if not _Ped.save_triggers(pack_id, root):
		_err("save failed for '%s' (see Godot Output for the validation reason)" % label)
		return false

	var added := MvTriggerEngine.add_global_rule(rule)
	if added <= 0:
		_warn("'%s' saved but produced no live rule" % label)
		return false
	_ok("added '%s' (event '%s') — live now + saved to user pack '%s'" % [
		label, str(rule.get("event", "")), pack_id])
	return true


func _rule_id_exists(rid: String) -> bool:
	for r in MvTriggerEngine.get_rules():
		if typeof(r) == TYPE_DICTIONARY and str((r as Dictionary).get("id", "")).strip_edges() == rid:
			return true
	return false


func _validate_trigger(rule: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	var event := str(rule.get("event", "")).strip_edges()
	if event.is_empty():
		errors.append("trigger is missing 'event'")
	elif not _Eca.event_type_names().has(event):
		warnings.append("event '%s' isn't a known editor event (ok if it's custom/code-fired)" % event)

	var conds_v: Variant = rule.get("conditions", [])
	if typeof(conds_v) == TYPE_ARRAY:
		for c in conds_v:
			_validate_condition(c, errors)
	elif rule.has("conditions"):
		errors.append("'conditions' must be an array")

	var acts_v: Variant = rule.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		if (acts_v as Array).is_empty():
			warnings.append("trigger has no actions (it will match but do nothing)")
		for a in acts_v:
			if typeof(a) != TYPE_DICTIONARY:
				errors.append("each action must be an object")
				continue
			var at := str((a as Dictionary).get("type", "")).strip_edges()
			if at.is_empty():
				errors.append("an action is missing 'type'")
			elif _Eca.find_action_schema(at).is_empty():
				errors.append("unknown action type '%s'" % at)
	elif rule.has("actions"):
		errors.append("'actions' must be an array")
	else:
		warnings.append("trigger has no actions (it will match but do nothing)")

	return {"errors": errors, "warnings": warnings}


func _validate_condition(c: Variant, errors: Array) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		errors.append("each condition must be an object")
		return
	var ct := str((c as Dictionary).get("type", "")).strip_edges()
	if ct.is_empty():
		errors.append("a condition is missing 'type'")
		return
	if ct in _LOGICAL_CONDITIONS:
		var subs_v: Variant = (c as Dictionary).get("conditions", [])
		if typeof(subs_v) == TYPE_ARRAY:
			for sub in subs_v:
				_validate_condition(sub, errors)
		return
	if _Eca.find_condition_schema(ct).is_empty():
		errors.append("unknown condition type '%s'" % ct)


# ── Commands ───────────────────────────────────────────────────────────────

func _handle_command(text: String) -> bool:
	var sp := text.find(" ")
	var cmd := (text if sp < 0 else text.substr(0, sp)).strip_edges().to_lower()
	var rest := "" if sp < 0 else text.substr(sp + 1).strip_edges()
	match cmd:
		"help":
			_print_help()
			return true
		"clear":
			_log_view.clear()
			return true
		"fire":
			return _cmd_fire(rest)
		"spawn":
			return _cmd_spawn(rest)
		"flag":
			return _cmd_flag(rest)
		_:
			_err("unknown command '%s' — type 'help'" % cmd)
			return false


func _cmd_fire(rest: String) -> bool:
	if rest.is_empty():
		_err("usage: fire <event> [json payload]")
		return false
	var event := rest
	var payload: Dictionary = {}
	var brace := rest.find("{")
	if brace >= 0:
		event = rest.substr(0, brace).strip_edges()
		var parsed: Variant = JSON.parse_string(rest.substr(brace))
		if typeof(parsed) != TYPE_DICTIONARY:
			_err("the payload after the event must be a JSON object")
			return false
		payload = parsed
	event = event.strip_edges()
	if event.is_empty():
		_err("usage: fire <event> [json payload]")
		return false
	var matched: bool = MvTriggerEngine.fire_event(event, payload)
	if matched:
		_ok("fired '%s' — matched at least one trigger" % event)
	else:
		_warn("fired '%s' — no triggers matched" % event)
	return true


func _cmd_spawn(rest: String) -> bool:
	var entity_id := rest.strip_edges()
	if entity_id.is_empty():
		_err("usage: spawn <entity_id>")
		return false
	var rm := MvGame.room_manager as MvRoomManager
	if rm == null:
		_err("no room is loaded")
		return false
	var pos := _player_position()
	var node := rm.spawn_entity_dynamic(entity_id, pos)
	if node == null:
		_err("could not spawn '%s' (unknown entity id?)" % entity_id)
		return false
	_ok("spawned '%s' at %s" % [entity_id, str(pos.round())])
	return true


func _cmd_flag(rest: String) -> bool:
	var eq := rest.find("=")
	if eq < 0:
		_err("usage: flag <name>=<value>   (value: true/false, a number, or text)")
		return false
	var flag_name := rest.substr(0, eq).strip_edges()
	var raw := rest.substr(eq + 1).strip_edges()
	if flag_name.is_empty():
		_err("flag name is empty")
		return false
	PlanetaryInterface.set_global_flag(flag_name, _coerce_value(raw))
	_ok("set global flag '%s' = %s" % [flag_name, raw])
	return true


func _coerce_value(raw: String) -> Variant:
	var low := raw.to_lower()
	if low == "true":
		return true
	if low == "false":
		return false
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	return raw


# ── Context + logging ──────────────────────────────────────────────────────

func _player_position() -> Vector2:
	var m := MvGame.main as MvMain
	if m != null:
		return m.get_player_position()
	return Vector2.ZERO


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	return "demo"


func _print_help() -> void:
	_log("[color=#8ab4ff]── in-game console ──[/color]")
	_log("Paste a trigger JSON object or array → validated, injected live, saved to the pack.")
	_log("Commands:")
	_log("  fire <event> [json]   test-fire an event, e.g. fire interact {\"entity_type\":\"sign\"}")
	_log("  spawn <entity_id>     spawn an entity at the player")
	_log("  flag <name>=<value>   set a global flag")
	_log("  clear                 clear this log         help   show this help")


func _log(line: String) -> void:
	if _log_view != null:
		_log_view.append_text(line + "\n")


func _ok(msg: String) -> void:
	_log("[color=#7fdc7f]✓ %s[/color]" % _escape(msg))


func _warn(msg: String) -> void:
	_log("[color=#ffd166]! %s[/color]" % _escape(msg))


func _err(msg: String) -> void:
	_log("[color=#ff7b7b]✗ %s[/color]" % _escape(msg))


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
