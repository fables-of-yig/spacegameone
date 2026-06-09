class_name MvTriggerEditor
extends CanvasLayer

# In-game visual trigger editor (Frontier 1 / T1). Opened from the dev console
# with `triggers`. Lists the pack's global trigger rules and edits them with
# forms (event + conditions + actions) instead of hand-pasting JSON. Saves the
# same Triggers/global.json the desktop editor + console write, then re-syncs
# the live engine.
#
# Reuses: EcaSchema (event/condition/action catalog + field kinds), TriggerRoot
# (root shape {triggers, libraries}), PedIO.load_triggers/save_triggers
# (validated, copy-on-write), MvTriggerEngine.load_triggers (live re-sync) +
# fire_event (test). UI via NebulaUi/NebulaTheme.

const EcaSchema := preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const TriggerRoot := preload("res://Space/scripts/shared/trigger_root.gd")

var _rules: Array = []          # working copy of root.triggers (array of rule dicts)
var _libraries: Array = []      # preserved verbatim across save
var _editing := -1              # index into _rules being edited, or -1 = list view
var _open := false

var _skin_host: Control = null
var _title: Label = null
var _content: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 134
	_build_shell()
	visible = false


# ── Lifecycle ────────────────────────────────────────────────────────────────

func open_editor() -> void:
	var pid := _pack_id()
	var root := PedIO.load_triggers(pid)
	_rules = (root.get("triggers", []) as Array).duplicate(true)
	_libraries = (root.get("libraries", []) as Array).duplicate(true)
	_editing = -1
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()
	PlanetaryInterface.edit_session_active = true
	MvGame.simulation_paused = true
	visible = true
	_set_status("")
	_show()


func close_editor() -> void:
	visible = false
	PlanetaryInterface.edit_session_active = false
	MvGame.simulation_paused = false


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = NebulaTheme.C_PANEL_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = NebulaTheme.theme()
	_skin_host = margin
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	_title = NebulaTheme.title_label("Triggers")
	header.add_child(_title)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hsp)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_editor)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _show() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _editing < 0:
		_build_list()
	else:
		_build_edit()


# ── List view ────────────────────────────────────────────────────────────────

func _build_list() -> void:
	_title.text = "TRIGGERS"
	var wp := NebulaUi.work_panel("Global rules")
	var panel: Control = wp["root"]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(900, 0)
	_content.add_child(panel)
	var body: VBoxContainer = wp["body"]
	if _rules.is_empty():
		body.add_child(_hint("No trigger rules yet. Add one — a rule runs its ACTIONS when its EVENT fires and all its CONDITIONS pass."))
	for i in _rules.size():
		body.add_child(_rule_row(i))
	var add := NebulaUi.button("＋ New rule", "primary")
	add.pressed.connect(func():
		_rules.append({"id": _unique_id("rule"), "event": "interact", "conditions": [], "actions": []})
		_editing = _rules.size() - 1
		_show())
	body.add_child(add)


func _rule_row(i: int) -> Control:
	var rule: Dictionary = _rules[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", NebulaTheme.card_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var lbl := Label.new()
	lbl.text = "%s   ·   on %s   ·   %d cond / %d act" % [
		str(rule.get("id", "(unnamed)")), str(rule.get("event", "?")),
		(rule.get("conditions", []) as Array).size(), (rule.get("actions", []) as Array).size()]
	lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var fire := NebulaUi.button("▶ Fire", "gold")
	fire.pressed.connect(func(): _fire_rule(rule))
	row.add_child(fire)
	var edit := NebulaUi.button("Edit", "primary")
	edit.pressed.connect(func():
		_editing = i
		_show())
	row.add_child(edit)
	var del := NebulaUi.button("✕", "ghost")
	del.pressed.connect(func():
		_rules.remove_at(i)
		_save_all()
		_show())
	row.add_child(del)
	return card


# ── Edit view ────────────────────────────────────────────────────────────────

func _build_edit() -> void:
	var rule: Dictionary = _rules[_editing]
	_title.text = "TRIGGER  ·  %s" % str(rule.get("id", ""))
	var wp := NebulaUi.work_panel("Rule")
	var panel: Control = wp["root"]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(900, 0)
	_content.add_child(panel)
	var body: VBoxContainer = wp["body"]

	var id_edit := LineEdit.new()
	id_edit.text = str(rule.get("id", ""))
	id_edit.placeholder_text = "rule id (unique, required)"
	id_edit.text_changed.connect(func(t): rule["id"] = t.strip_edges())
	body.add_child(NebulaUi.labeled("Rule id", id_edit, 160))

	var events := EcaSchema.event_type_names()
	var ev := OptionButton.new()
	for i in events.size():
		ev.add_item(EcaSchema.event_label(str(events[i])), i)
	ev.selected = maxi(0, events.find(str(rule.get("event", ""))))
	ev.item_selected.connect(func(idx): rule["event"] = str(events[idx]))
	body.add_child(NebulaUi.labeled("WHEN (event)", ev, 160))

	# Conditions
	body.add_child(NebulaUi.section_header("Conditions (all must pass)"))
	var conds: Array = rule.get("conditions", [])
	rule["conditions"] = conds
	for ci in conds.size():
		body.add_child(_clause_row("condition", conds, ci))
	var addc := NebulaUi.button("＋ Add condition", "ghost")
	addc.pressed.connect(func():
		conds.append(_default_clause("condition", str(EcaSchema.condition_type_names()[0])))
		_show())
	body.add_child(addc)

	# Actions
	body.add_child(NebulaUi.section_header("DO (actions, in order)"))
	var acts: Array = rule.get("actions", [])
	rule["actions"] = acts
	for ai in acts.size():
		body.add_child(_clause_row("action", acts, ai))
	var adda := NebulaUi.button("＋ Add action", "ghost")
	adda.pressed.connect(func():
		acts.append(_default_clause("action", str(EcaSchema.action_type_names()[0])))
		_show())
	body.add_child(adda)

	# Nav
	body.add_child(NebulaUi.section_header(""))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	body.add_child(nav)
	var back := NebulaUi.button("← Rules", "ghost")
	back.pressed.connect(func():
		_editing = -1
		_show())
	nav.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	var test := NebulaUi.button("▶ Test fire", "gold")
	test.pressed.connect(func(): _fire_rule(rule))
	nav.add_child(test)
	var save := NebulaUi.button("Save", "primary")
	save.pressed.connect(func():
		if _save_all():
			_set_status("saved %d rule(s) to '%s'" % [_rules.size(), _pack_id()]))
	nav.add_child(save)


# One condition/action row: type Select + its param fields + remove.
func _clause_row(kind: String, arr: Array, idx: int) -> Control:
	var clause: Dictionary = arr[idx]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", NebulaTheme.card_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var names := EcaSchema.condition_type_names() if kind == "condition" else EcaSchema.action_type_names()
	var labels := EcaSchema.condition_labels() if kind == "condition" else EcaSchema.action_labels()
	var opt := OptionButton.new()
	for i in names.size():
		opt.add_item(str(labels[i]) if i < labels.size() else str(names[i]), i)
	opt.selected = maxi(0, names.find(str(clause.get("type", ""))))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(i):
		arr[idx] = _default_clause(kind, str(names[i]))
		_show())
	head.add_child(opt)
	var del := NebulaUi.button("✕", "ghost")
	del.pressed.connect(func():
		arr.remove_at(idx)
		_show())
	head.add_child(del)
	# Param fields from the schema.
	var schema := EcaSchema.find_condition_schema(str(clause.get("type", ""))) if kind == "condition" else EcaSchema.find_action_schema(str(clause.get("type", "")))
	for f_v in schema.get("fields", []):
		var f: Array = f_v
		vb.add_child(NebulaUi.labeled("   " + str(f[1]), _field_control(str(f[0]), str(f[2]), clause), 200))
	return card


func _field_control(key: String, kind: String, params: Dictionary) -> Control:
	match kind:
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(params.get(key, false))
			cb.toggled.connect(func(v): params[key] = v)
			return cb
		"int":
			var sb := SpinBox.new()
			sb.min_value = -999999
			sb.max_value = 999999
			sb.step = 1
			sb.value = float(params.get(key, 0))
			sb.value_changed.connect(func(v): params[key] = int(round(v)))
			return sb
		"float", "opt_float":
			var fb := SpinBox.new()
			fb.min_value = -999999
			fb.max_value = 999999
			fb.step = 0.05
			fb.value = float(params.get(key, 0.0))
			fb.value_changed.connect(func(v): params[key] = v)
			return fb
		_:
			var le := LineEdit.new()
			le.text = str(params.get(key, ""))
			le.text_changed.connect(func(t): params[key] = t)
			return le


# ── Persistence + test ───────────────────────────────────────────────────────

func _save_all() -> bool:
	for rule_v in _rules:
		var rule: Dictionary = rule_v
		if str(rule.get("id", "")).strip_edges().is_empty():
			_set_status("every rule needs a unique id", true)
			return false
	var pid := _pack_id()
	var root := {"triggers": _rules, "libraries": _libraries}
	if not PedIO.save_triggers(pid, root):
		_set_status("save rejected by validation — check ids/events/fields (see Output)", true)
		return false
	MvTriggerEngine.load_triggers(pid)  # re-sync live global rules
	return true


func _fire_rule(rule: Dictionary) -> void:
	var event := str(rule.get("event", "")).strip_edges()
	if event.is_empty():
		_set_status("rule has no event to fire", true)
		return
	MvTriggerEngine.fire_event(event, {})
	_set_status("fired '%s'" % event)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _default_clause(kind: String, type_name: String) -> Dictionary:
	var schema := EcaSchema.find_condition_schema(type_name) if kind == "condition" else EcaSchema.find_action_schema(type_name)
	var out := {"type": type_name}
	for f_v in schema.get("fields", []):
		var f: Array = f_v
		var fk := str(f[2])
		out[str(f[0])] = (false if fk == "bool" else (0 if fk == "int" else (0.0 if fk == "float" or fk == "opt_float" else "")))
	return out


func _unique_id(prefix: String) -> String:
	var n := 1
	while true:
		var candidate := "%s_%d" % [prefix, n]
		var taken := false
		for r_v in _rules:
			if str((r_v as Dictionary).get("id", "")) == candidate:
				taken = true
				break
		if not taken:
			return candidate
		n += 1
	return prefix


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


func _hint(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	return l


func _set_status(msg: String, is_err := false) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_SUCCESS)
