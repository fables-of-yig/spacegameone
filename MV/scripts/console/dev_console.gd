extends CanvasLayer

# Unified in-game dev console — autoloaded as `DevConsole`, so ONE instance
# survives the MV<->Space scene swap and works in both engines. Toggle with the
# backtick/tilde key (it handles its own input). Engine-specific commands are
# routed by context: MV when an MV room is loaded, Space otherwise.
#
# Shared:   help · clear · flag <name>=<value> · wizard <player|enemy> · cancel
# MV:       <paste trigger JSON>  ·  fire <event> [json]  ·  spawn <entity_id>
# Space:    add_poi <type> <name>  ·  save_systems
#
# Validation reuses EcaSchema; persistence reuses PedIO / EntIO / BehIO /
# SystemIO (copy-on-write to the user pack). While open it flags
# PlanetaryInterface.edit_session_active (Slice 4).

const EcaSchema := preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")
const BehIO := preload("res://Space/scripts/shared/beh/beh_io.gd")
const SystemIO := preload("res://Space/scripts/shared/system_io.gd")

const LOGICAL_CONDITIONS := ["and", "or", "not"]
const POI_TYPES := ["station", "hostile_station", "salvage", "resource", "anomaly", "ruin", "npc_colony"]
const ENEMY_CATEGORIES := ["enemy", "boss", "interactable", "pickup", "logic", "fx", "other"]

# Wizard step tables. Each step: {key, prompt, def}. Empty answer takes the def.
const PLAYER_STEPS := [
	{"key": "id", "prompt": "player id (e.g. hero)", "def": ""},
	{"key": "name", "prompt": "display name", "def": ""},
	{"key": "hp_max", "prompt": "max HP", "def": "50"},
	{"key": "str", "prompt": "strength (melee)", "def": "5"},
	{"key": "con", "prompt": "constitution (defense)", "def": "4"},
	{"key": "int", "prompt": "intelligence (projectile)", "def": "3"},
	{"key": "lck", "prompt": "luck (crit/drops)", "def": "4"},
	{"key": "abilities", "prompt": "ability ids, comma-separated (or blank)", "def": ""},
]
const ENEMY_STEPS := [
	{"key": "id", "prompt": "enemy id (e.g. goblin)", "def": ""},
	{"key": "name", "prompt": "display name", "def": ""},
	{"key": "category", "prompt": "category: enemy/boss/interactable/pickup/logic", "def": "enemy"},
	{"key": "hp", "prompt": "HP", "def": "10"},
	{"key": "contact_damage", "prompt": "contact damage (on touch)", "def": "1"},
	{"key": "move_speed", "prompt": "move speed (px/sec)", "def": "40"},
	{"key": "sprite_set", "prompt": "sprite set path (or blank)", "def": ""},
	{"key": "behavior", "prompt": "behavior id — created idle if new (or blank)", "def": ""},
]

var _log_view: RichTextLabel = null
var _entry: TextEdit = null
var _open := false
var _wiz: Dictionary = {}   # {kind, step, answers} while a wizard is running


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 127
	_build_ui()
	visible = false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.9)
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
	_entry.custom_minimum_size = Vector2(0, 48)
	_entry.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(_entry)


# ── Open / close ─────────────────────────────────────────────────────────────

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
	PlanetaryInterface.edit_session_active = true
	if _log_view.get_parsed_text().strip_edges().is_empty():
		_print_help()
	_entry.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	PlanetaryInterface.edit_session_active = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_QUOTELEFT and not ke.ctrl_pressed and not ke.alt_pressed:
			get_viewport().set_input_as_handled()
			toggle()
			return
		if not _open:
			return
		if ke.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif (ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER) and ke.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_submit()


# ── Dispatch ─────────────────────────────────────────────────────────────────

func _submit() -> void:
	var text := _entry.text.strip_edges()
	_entry.text = ""
	_entry.grab_focus.call_deferred()
	if text.is_empty():
		return
	if not _wiz.is_empty():
		_wizard_answer(text)
		return
	var echo := text
	var nl := text.find("\n")
	if nl >= 0:
		echo = text.substr(0, nl) + " …"
	_log("[color=#8ab4ff]> %s[/color]" % _escape(echo))
	if text.begins_with("{") or text.begins_with("["):
		_handle_json(text)
	else:
		_handle_command(text)


func _handle_command(text: String) -> void:
	var sp := text.find(" ")
	var cmd := (text if sp < 0 else text.substr(0, sp)).strip_edges().to_lower()
	var rest := "" if sp < 0 else text.substr(sp + 1).strip_edges()
	match cmd:
		"help":
			_print_help()
		"clear":
			_log_view.clear()
		"cancel":
			_warn("nothing to cancel")
		"flag":
			_cmd_flag(rest)
		"wizard":
			_cmd_wizard(rest)
		"fire":
			_cmd_fire(rest)
		"spawn":
			_cmd_spawn(rest)
		"add_poi":
			_cmd_add_poi(rest)
		"save_systems":
			_cmd_save_systems()
		_:
			_err("unknown command '%s' — type 'help'" % cmd)


# ── Context ──────────────────────────────────────────────────────────────────

func _in_mv() -> bool:
	return MvGame.main != null and is_instance_valid(MvGame.main)


func _space_host() -> Node:
	# The active Space scene root (Node2D named Main) when not in MV.
	if _in_mv():
		return null
	var scene := get_tree().current_scene
	if scene != null and scene.get("system_world_positions") != null:
		return scene
	return null


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


# ── Shared commands ──────────────────────────────────────────────────────────

func _cmd_flag(rest: String) -> void:
	var eq := rest.find("=")
	if eq < 0:
		_err("usage: flag <name>=<value>")
		return
	var flag_name := rest.substr(0, eq).strip_edges()
	var raw := rest.substr(eq + 1).strip_edges()
	if flag_name.is_empty():
		_err("flag name is empty")
		return
	PlanetaryInterface.set_global_flag(flag_name, _coerce(raw))
	_ok("set global flag '%s' = %s" % [flag_name, raw])


# ── MV commands ──────────────────────────────────────────────────────────────

func _cmd_fire(rest: String) -> void:
	if rest.is_empty():
		_err("usage: fire <event> [json payload]")
		return
	var event := rest
	var payload: Dictionary = {}
	var brace := rest.find("{")
	if brace >= 0:
		event = rest.substr(0, brace).strip_edges()
		var parsed: Variant = JSON.parse_string(rest.substr(brace))
		if typeof(parsed) != TYPE_DICTIONARY:
			_err("the payload after the event must be a JSON object")
			return
		payload = parsed
	event = event.strip_edges()
	if event.is_empty():
		_err("usage: fire <event> [json payload]")
		return
	if MvTriggerEngine.fire_event(event, payload):
		_ok("fired '%s' — matched at least one trigger" % event)
	else:
		_warn("fired '%s' — no triggers matched" % event)


func _cmd_spawn(rest: String) -> void:
	var entity_id := rest.strip_edges()
	if entity_id.is_empty():
		_err("usage: spawn <entity_id>")
		return
	var rm := MvGame.room_manager as MvRoomManager
	if rm == null:
		_err("spawn is MV-only and no room is loaded")
		return
	var pos := Vector2.ZERO
	var m := MvGame.main as MvMain
	if m != null:
		pos = m.get_player_position()
	var node := rm.spawn_entity_dynamic(entity_id, pos)
	if node == null:
		_err("could not spawn '%s' (unknown entity id?)" % entity_id)
	else:
		_ok("spawned '%s' at %s" % [entity_id, str(pos.round())])


# Paste a trigger JSON object/array → validate (EcaSchema) → live-inject
# (MvTriggerEngine) → persist (PedIO). Works in either engine (global triggers).
func _handle_json(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_err("invalid JSON — parse failed")
		return
	var rules: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		rules = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if typeof(d.get("triggers")) == TYPE_ARRAY:
			rules = d.get("triggers")
		else:
			rules = [d]
	else:
		_err("expected a trigger object or array")
		return
	if rules.is_empty():
		_err("no triggers found in input")
		return
	for rule_v in rules:
		if typeof(rule_v) != TYPE_DICTIONARY:
			_err("skipped a non-object entry")
			continue
		_inject_and_persist(rule_v as Dictionary)


func _inject_and_persist(rule: Dictionary) -> void:
	var rid := str(rule.get("id", "")).strip_edges()
	var label := rid if not rid.is_empty() else "(unnamed)"
	var report := _validate_trigger(rule)
	for w in report["warnings"]:
		_warn(str(w))
	if not (report["errors"] as Array).is_empty():
		for e in report["errors"]:
			_err(str(e))
		_err("rejected '%s' — fix the above and re-paste" % label)
		return
	if not rid.is_empty() and _rule_id_exists(rid):
		_warn("a rule with id '%s' already exists — skipped" % rid)
		return
	var pack_id := _pack_id()
	var root := PedIO.load_triggers(pack_id)
	var arr_v: Variant = root.get("triggers", [])
	var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
	arr.append(rule)
	root["triggers"] = arr
	if not PedIO.save_triggers(pack_id, root):
		_err("save failed for '%s' (see Godot Output)" % label)
		return
	if MvTriggerEngine.add_global_rule(rule) > 0:
		_ok("added '%s' (event '%s') — live + saved to '%s'" % [label, str(rule.get("event", "")), pack_id])
	else:
		_warn("'%s' saved but produced no live rule" % label)


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
	elif not EcaSchema.event_type_names().has(event):
		warnings.append("event '%s' isn't a known editor event (ok if custom/code-fired)" % event)
	var conds_v: Variant = rule.get("conditions", [])
	if typeof(conds_v) == TYPE_ARRAY:
		for c in conds_v:
			_validate_condition(c, errors)
	elif rule.has("conditions"):
		errors.append("'conditions' must be an array")
	var acts_v: Variant = rule.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		for a in acts_v:
			if typeof(a) != TYPE_DICTIONARY:
				errors.append("each action must be an object")
				continue
			var at := str((a as Dictionary).get("type", "")).strip_edges()
			if at.is_empty():
				errors.append("an action is missing 'type'")
			elif EcaSchema.find_action_schema(at).is_empty():
				errors.append("unknown action type '%s'" % at)
	elif rule.has("actions"):
		errors.append("'actions' must be an array")
	return {"errors": errors, "warnings": warnings}


func _validate_condition(c: Variant, errors: Array) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		errors.append("each condition must be an object")
		return
	var ct := str((c as Dictionary).get("type", "")).strip_edges()
	if ct.is_empty():
		errors.append("a condition is missing 'type'")
		return
	if ct in LOGICAL_CONDITIONS:
		var subs_v: Variant = (c as Dictionary).get("conditions", [])
		if typeof(subs_v) == TYPE_ARRAY:
			for sub in subs_v:
				_validate_condition(sub, errors)
		return
	if EcaSchema.find_condition_schema(ct).is_empty():
		errors.append("unknown condition type '%s'" % ct)


# ── Space commands ───────────────────────────────────────────────────────────

func _cmd_add_poi(rest: String) -> void:
	var host := _space_host()
	if host == null:
		_err("add_poi is Space-only (fly into a system first)")
		return
	var sp := rest.find(" ")
	var poi_type := (rest if sp < 0 else rest.substr(0, sp)).strip_edges().to_lower()
	var poi_name := "" if sp < 0 else rest.substr(sp + 1).strip_edges()
	if not POI_TYPES.has(poi_type):
		_err("usage: add_poi <type> <name>  ·  type one of %s" % str(POI_TYPES))
		return
	if poi_name.is_empty():
		poi_name = poi_type.capitalize()
	var sys := str(GameManager.current_system)
	if sys.is_empty():
		_err("no current system")
		return
	var rel := _space_player_pos(host) - _space_system_center(host, sys)
	var poi := {
		"id": "%s_%d" % [_slug(poi_name), Time.get_ticks_msec()],
		"name": poi_name, "type": poi_type, "description": "placed in-game", "event_id": "",
		"orbit_dist": rel.length(), "orbit_angle": rad_to_deg(rel.angle()),
		"sprite": "", "visual_scale": 1.0, "anim_frames": 1, "anim_fps": 0.0, "gravity_radius": 0,
	}
	var systems: Dictionary = DataManager.systems
	var sysd_v: Variant = systems.get(sys, null)
	if typeof(sysd_v) != TYPE_DICTIONARY:
		_err("system '%s' has no data" % sys)
		return
	var sysd: Dictionary = sysd_v
	var pois_v: Variant = sysd.get("pois", [])
	var pois: Array = pois_v if typeof(pois_v) == TYPE_ARRAY else []
	pois.append(poi)
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	var saved := SystemIO.save(_pack_id(), systems)
	_space_respawn_pois(host, sys)
	if saved:
		_ok("added POI '%s' (%s) in '%s' — live + saved" % [poi_name, poi_type, sys])
	else:
		_warn("added POI '%s' live, but the disk save failed" % poi_name)


func _cmd_save_systems() -> void:
	if SystemIO.save(_pack_id(), DataManager.systems):
		_ok("saved systems → user pack '%s'" % _pack_id())
	else:
		_err("save failed")


func _space_system_center(host: Node, sys: String) -> Vector2:
	var swp: Variant = host.get("system_world_positions")
	if typeof(swp) == TYPE_DICTIONARY:
		return (swp as Dictionary).get(sys, Vector2.ZERO)
	return Vector2.ZERO


func _space_player_pos(host: Node) -> Vector2:
	var p: Variant = host.get("player")
	if p is Node2D:
		return (p as Node2D).global_position
	return Vector2.ZERO


func _space_respawn_pois(host: Node, sys: String) -> void:
	var spawn: Variant = host.get("_spawn")
	if spawn != null and is_instance_valid(spawn):
		spawn.clear_pois()
		spawn.spawn_system_pois(sys)


# ── Wizards ──────────────────────────────────────────────────────────────────

func _cmd_wizard(rest: String) -> void:
	var kind := rest.strip_edges().to_lower()
	if kind != "player" and kind != "enemy":
		_err("usage: wizard <player|enemy>")
		return
	_wiz = {"kind": kind, "step": 0, "answers": {}}
	_log("[color=#8ab4ff]── %s wizard ──[/color]  (Ctrl+Enter to answer, blank = default, 'cancel' to abort)" % kind)
	if kind == "player":
		_log("[color=#ffd166]note: this sets identity, stats and abilities. Sprite, animations,")
		_log("controls and physics are asset/resource-level — use the editors for those.[/color]")
	_wiz_prompt()


func _wiz_steps() -> Array:
	return PLAYER_STEPS if _wiz.get("kind", "") == "player" else ENEMY_STEPS


func _wiz_prompt() -> void:
	var steps := _wiz_steps()
	var i: int = _wiz.get("step", 0)
	if i >= steps.size():
		return
	var step: Dictionary = steps[i]
	var def: String = str(step.get("def", ""))
	var def_txt := "" if def.is_empty() else "  [default: %s]" % def
	_log("[color=#7fdc7f](%d/%d) %s[/color]%s" % [i + 1, steps.size(), str(step.get("prompt", "")), def_txt])


func _wizard_answer(text: String) -> void:
	if text.strip_edges().to_lower() == "cancel":
		_wiz = {}
		_warn("wizard cancelled")
		return
	var steps := _wiz_steps()
	var i: int = _wiz.get("step", 0)
	var step: Dictionary = steps[i]
	var key: String = str(step.get("key", ""))
	var ans := text.strip_edges()
	if ans.is_empty():
		ans = str(step.get("def", ""))
	# 'id' (step 0) is required.
	if key == "id" and ans.is_empty():
		_err("an id is required — type one")
		return
	(_wiz["answers"] as Dictionary)[key] = ans
	_wiz["step"] = i + 1
	if int(_wiz["step"]) >= steps.size():
		var kind: String = str(_wiz.get("kind", ""))
		var answers: Dictionary = _wiz.get("answers", {})
		_wiz = {}
		if kind == "player":
			_finish_player(answers)
		else:
			_finish_enemy(answers)
	else:
		_wiz_prompt()


func _finish_player(a: Dictionary) -> void:
	var pack_id := _pack_id()
	var stats := {
		"base": {
			"level": 1, "exp": 0, "exp_to_next": 100,
			"hp_max": int(str(a.get("hp_max", "50"))),
			"mp_max": 10, "heart_max": 5,
			"str": int(str(a.get("str", "5"))),
			"con": int(str(a.get("con", "4"))),
			"int": int(str(a.get("int", "3"))),
			"lck": int(str(a.get("lck", "4"))),
		},
		"growth": {
			"hp_per_level": 4, "mp_per_level": 2, "heart_per_level": 1,
			"str_per_level": 1, "con_per_level": 1, "int_per_level": 1,
			"lck_per_level": 1, "exp_curve_multiplier": 1.5,
		},
	}
	if not PedIO.save_stats(pack_id, stats):
		_err("player wizard: saving stats failed")
		return
	var ability_csv := str(a.get("abilities", "")).strip_edges()
	var added_abilities := 0
	if not ability_csv.is_empty():
		var root := PedIO.load_abilities(pack_id)
		var arr_v: Variant = root.get("abilities", [])
		var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
		for raw_id in ability_csv.split(",", false):
			var aid := str(raw_id).strip_edges()
			if aid.is_empty():
				continue
			if not _has_id(arr, aid):
				arr.append({"id": aid, "name": aid.capitalize(), "category": "movement", "description": "", "params": {}})
				added_abilities += 1
		root["abilities"] = arr
		PedIO.save_abilities(pack_id, root)
	_ok("player wizard: saved stats (hp %s) + %d new ability id(s) to '%s'" % [
		str(a.get("hp_max", "50")), added_abilities, pack_id])


func _finish_enemy(a: Dictionary) -> void:
	var pack_id := _pack_id()
	var id := str(a.get("id", "")).strip_edges()
	if id.is_empty():
		_err("enemy wizard: empty id")
		return
	var category := str(a.get("category", "enemy")).strip_edges().to_lower()
	if not ENEMY_CATEGORIES.has(category):
		category = "enemy"
	var behavior := str(a.get("behavior", "")).strip_edges()

	var ent := EntIO.default_entity(id)
	ent["name"] = str(a.get("name", "")).strip_edges() if not str(a.get("name", "")).strip_edges().is_empty() else id.capitalize()
	ent["category"] = category
	ent["hp"] = int(str(a.get("hp", "10")))
	ent["contact_damage"] = int(str(a.get("contact_damage", "1")))
	ent["move_speed"] = float(str(a.get("move_speed", "40")))
	ent["sprite_set"] = str(a.get("sprite_set", "")).strip_edges()
	ent["behavior"] = behavior

	var ents := EntIO.load_or_init(pack_id)
	var arr_v: Variant = ents.get("entities", [])
	var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
	var replaced := false
	for i in arr.size():
		if typeof(arr[i]) == TYPE_DICTIONARY and str((arr[i] as Dictionary).get("id", "")) == id:
			arr[i] = ent
			replaced = true
			break
	if not replaced:
		arr.append(ent)
	ents["entities"] = arr
	if not EntIO.save_entities(pack_id, ents):
		_err("enemy wizard: saving entity failed (validation?)")
		return

	# Create a default idle behavior if the named one doesn't exist yet.
	var beh_note := ""
	if not behavior.is_empty():
		var beh := BehIO.load_or_init(pack_id)
		var blist_v: Variant = beh.get("behaviors", [])
		var blist: Array = blist_v if typeof(blist_v) == TYPE_ARRAY else []
		if not _has_id(blist, behavior):
			var nb := BehIO.default_behavior(behavior)
			blist.append(nb)
			beh["behaviors"] = blist
			if BehIO.save_behaviors(pack_id, beh):
				beh_note = " + created idle behavior '%s'" % behavior
	_ok("enemy wizard: saved '%s' (%s, hp %s)%s to '%s'%s" % [
		id, category, str(a.get("hp", "10")), beh_note, pack_id,
		"  — replaced existing" if replaced else ""])


func _has_id(arr: Array, id: String) -> bool:
	for e in arr:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == id:
			return true
	return false


# ── Helpers ──────────────────────────────────────────────────────────────────

func _coerce(raw: String) -> Variant:
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


func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "_" or ch == "-":
			out += "_"
	return out if not out.is_empty() else "poi"


func _print_help() -> void:
	_log("[color=#8ab4ff]── dev console ──[/color]")
	_log("Shared:  flag <name>=<value>   wizard <player|enemy>   clear   help")
	if _in_mv():
		_log("MV:  <paste trigger JSON>   fire <event> [json]   spawn <entity_id>")
	else:
		_log("Space:  add_poi <type> <name>   save_systems")
	_log("Submit: Ctrl+Enter    Close: Esc or backtick")


func _log(line: String) -> void:
	if _log_view != null:
		_log_view.append_text(line + "\n")


func _ok(m: String) -> void:
	_log("[color=#7fdc7f]✓ %s[/color]" % _escape(m))


func _warn(m: String) -> void:
	_log("[color=#ffd166]! %s[/color]" % _escape(m))


func _err(m: String) -> void:
	_log("[color=#ff7b7b]✗ %s[/color]" % _escape(m))


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
