extends CanvasLayer

# Unified in-game dev console — autoloaded as `DevConsole`, so ONE instance
# survives the MV<->Space scene swap and works in both engines. Toggle with the
# backtick/tilde key (it handles its own input). Engine-specific commands are
# routed by context: MV when an MV room is loaded, Space otherwise.
#
# Shared:   help · clear · flag <name>=<value> · wizard <player|enemy> · workshop · cancel
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
const POI_TYPES := ["station", "hostile_station", "salvage", "resource", "anomaly", "ruin", "npc_colony", "planet"]
const ENEMY_CATEGORIES := ["enemy", "boss", "interactable", "pickup", "logic", "fx", "other"]

# Wizard step tables. Each step: {key, prompt, def}. Empty answer takes the def.
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
var _wiz: Dictionary = {}   # {kind, step, answers} while an (enemy) wizard runs
var _player_wizard: MvPlayerWizard = null
var _workshop: MvCombatWorkshop = null
var _trigger_editor: MvTriggerEditor = null
var _dialogue_editor: MvDialogueEditor = null
var _hint: Label = null
var _skin_host: Control = null
var _title_lbl: Label = null
var _chip_row: HBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 127
	_build_ui()
	_player_wizard = MvPlayerWizard.new()
	add_child(_player_wizard)
	_workshop = MvCombatWorkshop.new()
	add_child(_workshop)
	_trigger_editor = MvTriggerEditor.new()
	add_child(_trigger_editor)
	_dialogue_editor = MvDialogueEditor.new()
	add_child(_dialogue_editor)
	_build_hint()
	visible = false


# Slide-up terminal (Nebula mockup): dim backdrop + a bottom panel with a title
# row, colored output log in a recessed well, a command-chip strip, and an input
# line. Stays in game space (no content-scale flip) so the visible game above
# doesn't jump scale.
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(NebulaTheme.C_PANEL_DARK.r, NebulaTheme.C_PANEL_DARK.g, NebulaTheme.C_PANEL_DARK.b, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = NebulaTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skin_host = root
	add_child(root)

	# Bottom terminal panel (lower ~55% of the screen).
	var term := PanelContainer.new()
	term.anchor_left = 0.0
	term.anchor_right = 1.0
	term.anchor_top = 0.45
	term.anchor_bottom = 1.0
	term.offset_left = 8
	term.offset_right = -8
	term.offset_bottom = -8
	root.add_child(term)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	term.add_child(pad)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	pad.add_child(vbox)

	# Title row.
	var titlerow := HBoxContainer.new()
	titlerow.add_theme_constant_override("separation", 12)
	vbox.add_child(titlerow)
	_title_lbl = NebulaTheme.title_label("Dev Console")
	titlerow.add_child(_title_lbl)
	var tspacer := Control.new()
	tspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlerow.add_child(tspacer)
	var hint := Label.new()
	hint.text = "Ctrl+Enter run   ·   Esc / ` close"
	hint.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titlerow.add_child(hint)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_active = true
	_log_view.scroll_following = true
	_log_view.focus_mode = Control.FOCUS_NONE
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_stylebox_override("normal", NebulaTheme.well_box())
	vbox.add_child(_log_view)

	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_chip_row)

	_entry = TextEdit.new()
	_entry.placeholder_text = "Paste trigger JSON or type a command (help)…"
	_entry.custom_minimum_size = Vector2(0, 48)
	_entry.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(_entry)


# Command chips for the current context; clicking pre-fills the input line.
func _refresh_chips() -> void:
	if _chip_row == null:
		return
	for c in _chip_row.get_children():
		c.queue_free()
	var cmds := ["help", "flag", "wizard", "workshop", "triggers", "dialogue", "spawn", "fire"] if _in_mv() else ["help", "flag", "add_poi", "save_systems"]
	for cmd in cmds:
		var chip := NebulaUi.button(str(cmd), "ghost")
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_chip.bind(str(cmd)))
		_chip_row.add_child(chip)


func _on_chip(cmd: String) -> void:
	_entry.text = cmd + " "
	_entry.set_caret_column(_entry.text.length())
	_entry.grab_focus()


# A small always-on corner hint so the authoring tools are discoverable without
# knowing the keybinds. Lives on its own CanvasLayer so the console's visibility
# toggle doesn't hide it; it hides itself whenever an authoring overlay is open.
func _build_hint() -> void:
	var hl := CanvasLayer.new()
	hl.layer = 90
	add_child(hl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.add_child(root)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position += Vector2(8, -26)
	_hint.modulate = Color(0.82, 0.86, 0.96, 0.5)
	root.add_child(_hint)


func _process(_delta: float) -> void:
	if _hint == null:
		return
	var busy := _open or PlanetaryInterface.edit_session_active
	_hint.visible = not busy
	if not busy:
		_hint.text = "`  authoring console" + ("    ·    F2  edit room" if _in_mv() else "")


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
	# Native resolution now — full profile everywhere; just re-assign the theme.
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()
	if _title_lbl != null:
		_title_lbl.add_theme_font_size_override("font_size", NebulaTheme.size("title"))
	_refresh_chips()
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
		"workshop":
			_cmd_workshop()
		"triggers", "trig":
			_cmd_triggers()
		"dialogue", "dlg":
			_cmd_dialogue()
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
	if poi_type == "planet":
		poi["planet_data"] = _default_planet_data(poi_name, str(poi["id"]))
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
		if poi_type == "planet":
			_warn("planet lands at region 'surface' → room 'start' by default — set the real region/room in the editor")
	else:
		_warn("added POI '%s' live, but the disk save failed" % poi_name)


func _default_planet_data(planet_name: String, poi_id: String) -> Dictionary:
	return {
		"name": planet_name,
		"pack_id": _pack_id(),
		"poi_id": poi_id,
		"regions": [{"id": "surface", "name": "Surface", "spawn_room": "start"}],
		"sky_color": [0.35, 0.5, 0.8],
		"horizon_color": [0.5, 0.6, 0.35],
		"terrain_colors": [[0.16, 0.3, 0.16], [0.1, 0.22, 0.1], [0.08, 0.18, 0.06]],
		"roughness": 0.6,
		"turret_count": [0, 0],
		"patrol_count": [0, 0],
		"surface_pois": [],
	}


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
	if kind == "player":
		_open_player_wizard()
		return
	if kind != "enemy":
		_err("usage: wizard <player|enemy>")
		return
	_wiz = {"kind": "enemy", "step": 0, "answers": {}}
	_log("[color=#8ab4ff]── enemy wizard ──[/color]  (Ctrl+Enter to answer, blank = default, 'cancel' to abort)")
	_wiz_prompt()


# `wizard player` opens the picker-based overlay (sprite/physics/stats/abilities)
# rather than a text Q&A. The console hides while it's up.
func _open_player_wizard() -> void:
	if _player_wizard == null:
		_player_wizard = MvPlayerWizard.new()
		add_child(_player_wizard)
	close()
	_player_wizard.open_wizard()


# `workshop` opens the guided enemy builder (sprite/stats/behavior + spawn-to-fight).
# MV-only — enemies live in the platformer. The console hides while it's up.
func _cmd_workshop() -> void:
	if not _in_mv():
		_err("workshop is MV-only — land on a planet first")
		return
	if _workshop == null:
		_workshop = MvCombatWorkshop.new()
		add_child(_workshop)
	close()
	if not _workshop.open_workshop():
		_err("could not open workshop (no live MV room)")


# `triggers` opens the visual trigger editor (list + event/condition/action forms).
func _cmd_triggers() -> void:
	if _trigger_editor == null:
		_trigger_editor = MvTriggerEditor.new()
		add_child(_trigger_editor)
	close()
	_trigger_editor.open_editor()


# `dialogue` opens the conversation editor (lines + branching choices + Play).
func _cmd_dialogue() -> void:
	if _dialogue_editor == null:
		_dialogue_editor = MvDialogueEditor.new()
		add_child(_dialogue_editor)
	close()
	_dialogue_editor.open_editor()


func _wiz_steps() -> Array:
	return ENEMY_STEPS


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
		var answers: Dictionary = _wiz.get("answers", {})
		_wiz = {}
		_finish_enemy(answers)
	else:
		_wiz_prompt()


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
	_log("[color=#7fdc7f]Authoring:[/color]  workshop (enemy)   wizard <player|enemy>   triggers   dialogue")
	_log("Shared:  flag <name>=<value>   clear   help")
	if _in_mv():
		_log("MV:  <paste trigger JSON>   fire <event> [json]   spawn <entity_id>   ·   F2 = edit room")
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
