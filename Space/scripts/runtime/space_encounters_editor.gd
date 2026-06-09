class_name SpaceEncountersEditor
extends Control

# In-game Encounters Editor (Frontier 3 / S2b). Opened from the dev console with
# `encounters`. Authors the void/random-encounter def table to the Claude Design
# handoff layout (list rail + Identity / Gating / Spawn / Story-nodes detail +
# Back/Test/Save bar), built against the REAL schema in
# res://Space/data/encounters/encounters.json (richer than the handoff mock:
# spawn = NPC-ship descriptors, node choices carry next + effects[], plus tags /
# chain_next / id). Edits a working copy; Save -> EncIO (copy-on-write to
# user://Packs/<pack>/GameTuning/encounter_defs.json) + EncounterManager applies
# it live. ▶ Test fires the selected encounter via EncounterManager.

const EncIO := preload("res://Space/scripts/shared/enc/enc_io.gd")

const THREATS := ["none", "low", "med", "high"]
const THREAT_COLORS := {
	"none": Color("#6f8694"), "low": Color("#5dd62c"), "med": Color("#ffcc33"), "high": Color("#e23a2e"),
}
const NPC_TYPES := ["trader", "pirate", "patrol", "scavenger", "civilian", "unknown"]
const FACTIONS := ["independent", "federation", "pirate", "syndicate", "alien", "none"]
const EFFECT_TYPES := ["take_credits", "give_credits", "give_fuel", "take_fuel", "set_flag", "give_item", "damage_ship", "spawn_fleet", "end"]

var _active := false
var _prev_paused := false
var _dirty := false
var _defs: Dictionary = {}            # working copy: "0".. -> def
var _sel := ""                        # selected key
var _list_host: VBoxContainer = null
var _detail_host: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = NebulaTheme.theme()
	visible = false


func open_editor() -> void:
	_active = true
	visible = true
	theme = NebulaTheme.theme()
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_defs = EncIO.load_defs(_pack_id()).duplicate(true)
	_sel = ""
	for k in _defs:
		_sel = str(k)
		break
	_dirty = false
	_build()


func close_editor() -> void:
	_active = false
	visible = false
	get_tree().paused = _prev_paused


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


# ── shell ──────────────────────────────────────────────────────────────────────

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.07, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Header.
	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.offset_left = 0
	header.offset_top = 0
	header.offset_right = 0
	var hbox := StyleBoxFlat.new()
	hbox.bg_color = Color(0.114, 0.165, 0.212, 0.96)
	hbox.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.18)
	hbox.border_width_bottom = 2
	hbox.set_content_margin_all(10)
	header.add_theme_stylebox_override("panel", hbox)
	add_child(header)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)
	hrow.add_child(NebulaTheme.title_label("Encounters"))
	var sub := Label.new()
	sub.text = "Void & random-encounter defs"
	sub.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	hrow.add_child(sub)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hsp)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_editor)
	hrow.add_child(close)

	# Left list rail.
	var rail := PanelContainer.new()
	rail.anchor_top = 0.0
	rail.anchor_bottom = 1.0
	rail.offset_top = 58
	rail.offset_left = 0
	rail.offset_right = 286
	rail.offset_bottom = -52
	var rbox := StyleBoxFlat.new()
	rbox.bg_color = Color(0.039, 0.059, 0.086, 0.78)
	rbox.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.16)
	rbox.border_width_right = 2
	rail.add_theme_stylebox_override("panel", rbox)
	add_child(rail)
	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 6)
	rail.add_child(rvb)
	var rhead := Label.new()
	rhead.name = "RailHead"
	rhead.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	rvb.add_child(rhead)
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rvb.add_child(rscroll)
	_list_host = VBoxContainer.new()
	_list_host.add_theme_constant_override("separation", 5)
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(_list_host)
	var newb := NebulaUi.button("＋ New encounter", "ghost")
	newb.pressed.connect(_new_encounter)
	rvb.add_child(newb)

	# Center detail scroll.
	var dscroll := ScrollContainer.new()
	dscroll.anchor_left = 0.0
	dscroll.anchor_right = 1.0
	dscroll.anchor_top = 0.0
	dscroll.anchor_bottom = 1.0
	dscroll.offset_left = 298
	dscroll.offset_right = -16
	dscroll.offset_top = 70
	dscroll.offset_bottom = -52
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(dscroll)
	_detail_host = VBoxContainer.new()
	_detail_host.add_theme_constant_override("separation", 14)
	_detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(_detail_host)

	# Bottom bar.
	var bar := PanelContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_top = -48
	var bbox := StyleBoxFlat.new()
	bbox.bg_color = Color(0.075, 0.106, 0.137, 0.96)
	bbox.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.18)
	bbox.border_width_top = 2
	bbox.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", bbox)
	add_child(bar)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	bar.add_child(brow)
	var back := NebulaUi.button("← Back", "ghost")
	back.pressed.connect(func(): _sel = ""; _rebuild_detail(); _rebuild_list())
	brow.add_child(back)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	brow.add_child(_status)
	var testb := NebulaUi.button("▶ Test", "gold")
	testb.pressed.connect(_test_selected)
	brow.add_child(testb)
	var saveb := NebulaUi.button("Save", "primary")
	saveb.pressed.connect(_save)
	brow.add_child(saveb)

	_rebuild_list()
	_rebuild_detail()


# ── list rail ──────────────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	if _list_host == null:
		return
	for c in _list_host.get_children():
		c.queue_free()
	var on := 0
	for k in _defs:
		if bool((_defs[k] as Dictionary).get("enabled", true)) and int((_defs[k] as Dictionary).get("weight", 0)) > 0:
			on += 1
	var head := _list_host.get_parent().get_parent().get_node_or_null("RailHead")
	if head is Label:
		(head as Label).text = "ENCOUNTERS   %d/%d on" % [on, _defs.size()]
	var keys := _defs.keys()
	keys.sort_custom(func(a, b): return int(str(a)) < int(str(b)))
	for k in keys:
		_list_host.add_child(_list_row(str(k), _defs[k]))


func _list_row(key: String, enc: Dictionary) -> Control:
	var sel := key == _sel
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_stylebox_override("normal", NebulaTheme.card_box(sel))
	btn.add_theme_stylebox_override("hover", NebulaTheme.card_box(sel))
	btn.add_theme_stylebox_override("pressed", NebulaTheme.card_box(true))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(hb)
	# enabled dot
	var enabled := bool(enc.get("enabled", true)) and int(enc.get("weight", 0)) > 0
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", Color("#5dd62c") if enabled else NebulaTheme.C_DIM)
	hb.add_child(dot)
	var title := Label.new()
	title.text = str(enc.get("title", "Untitled")) + ("  ◆" if bool(enc.get("unique", false)) else "")
	title.add_theme_color_override("font_color", NebulaTheme.C_TITLE if sel else NebulaTheme.C_BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	hb.add_child(title)
	hb.add_child(_threat_chip(str(enc.get("threat", "none"))))
	btn.pressed.connect(func(): _sel = key; _rebuild_detail(); _rebuild_list())
	return btn


func _threat_chip(threat: String) -> Control:
	var col: Color = THREAT_COLORS.get(threat, NebulaTheme.C_DIM)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.14)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.set_border_width_all(1)
	sb.border_color = Color(col.r, col.g, col.b, 0.5)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = threat.to_upper()
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	p.add_child(l)
	return p


# ── detail ─────────────────────────────────────────────────────────────────────

func _enc() -> Dictionary:
	return _defs.get(_sel, {})


func _mark() -> void:
	_dirty = true


func _rebuild_detail() -> void:
	if _detail_host == null:
		return
	for c in _detail_host.get_children():
		c.queue_free()
	if _sel == "" or not _defs.has(_sel):
		var empty := Label.new()
		empty.text = "Select an encounter, or + New encounter."
		empty.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		_detail_host.add_child(empty)
		return
	_detail_host.add_child(_section_identity())
	_detail_host.add_child(_section_gating())
	_detail_host.add_child(_section_spawn())
	_detail_host.add_child(_section_nodes())


func _section(title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", NebulaTheme.card_box(false))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	frame.add_child(vb)
	vb.add_child(NebulaUi.section_header(title))
	frame.set_meta("body", vb)
	return vb


func _section_identity() -> Control:
	var enc := _enc()
	var vb := _section("Identity")
	var title := LineEdit.new()
	title.text = str(enc.get("title", ""))
	title.text_changed.connect(func(t): enc["title"] = t; _mark(); _rebuild_list())
	vb.add_child(NebulaUi.labeled("Title", title, 90))
	# threat segmented
	vb.add_child(NebulaUi.labeled("Threat", _segmented(THREATS, str(enc.get("threat", "none")), func(v):
		enc["threat"] = v; _mark(); _rebuild_list(); _rebuild_detail()), true), )
	# weight
	var wt := SpinBox.new()
	wt.min_value = 0
	wt.max_value = 100
	wt.value = int(enc.get("weight", 10))
	wt.value_changed.connect(func(v): enc["weight"] = int(v); _mark(); _rebuild_list())
	vb.add_child(NebulaUi.labeled("Weight (how often)", wt, 130))
	vb.add_child(_toggle_row("Enabled", bool(enc.get("enabled", true)), func(on): enc["enabled"] = on; _mark(); _rebuild_list()))
	vb.add_child(_toggle_row("Unique (once per game)", bool(enc.get("unique", false)), func(on): enc["unique"] = on; _mark(); _rebuild_list()))
	vb.add_child(_chip_editor("Tags", enc, "tags", NebulaTheme.C_ACCENT))
	return _frame_of(vb)


func _section_gating() -> Control:
	var enc := _enc()
	var vb := _section("Gating")
	var days := HBoxContainer.new()
	days.add_theme_constant_override("separation", 10)
	days.add_child(_num_col("Min day", int(enc.get("min_day", 0)), -1, 9999, func(v): enc["min_day"] = v; _mark()))
	days.add_child(_num_col("Max day (-1 none)", int(enc.get("max_day", -1)), -1, 9999, func(v): enc["max_day"] = v; _mark()))
	days.add_child(_num_col("Cooldown (hrs)", int(enc.get("cooldown_hours", 0)), 0, 9999, func(v): enc["cooldown_hours"] = v; _mark()))
	vb.add_child(days)
	vb.add_child(_chip_editor("Required flags", enc, "required_flags", NebulaTheme.C_ACCENT))
	vb.add_child(_chip_editor("Excluded flags", enc, "excluded_flags", NebulaTheme.C_ERROR))
	vb.add_child(_chip_editor("Sets flags on complete", enc, "sets_flags", Color("#ffcc33")))
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", 10)
	chain.add_child(_num_col("Chain prev (id, -1)", int(enc.get("chain_prev", -1)), -1, 9999, func(v): enc["chain_prev"] = v; _mark()))
	chain.add_child(_num_col("Chain next (id, -1)", int(enc.get("chain_next", -1)), -1, 9999, func(v): enc["chain_next"] = v; _mark()))
	vb.add_child(chain)
	return _frame_of(vb)


func _section_spawn() -> Control:
	var enc := _enc()
	var vb := _section("Spawn")
	var spawns: Array = enc.get("spawn", [])
	if spawns.is_empty():
		var none := Label.new()
		none.text = "No ships — this is a non-combat encounter."
		none.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		vb.add_child(none)
	for i in spawns.size():
		vb.add_child(_spawn_row(enc, i))
	var addb := NebulaUi.button("＋ Ship", "ghost")
	addb.pressed.connect(func():
		(enc["spawn"] as Array).append(EncIO.default_spawn())
		_mark(); _rebuild_detail())
	vb.add_child(addb)
	return _frame_of(vb)


func _spawn_row(enc: Dictionary, idx: int) -> Control:
	var sp: Dictionary = (enc.get("spawn", []) as Array)[idx]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	var name := LineEdit.new()
	name.text = str(sp.get("name", ""))
	name.placeholder_text = "ship name"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_changed.connect(func(t): sp["name"] = t; _mark())
	r1.add_child(name)
	var rm := NebulaUi.button("✕", "ghost")
	rm.pressed.connect(func(): (enc["spawn"] as Array).remove_at(idx); _mark(); _rebuild_detail())
	r1.add_child(rm)
	vb.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	r2.add_child(_opt(NPC_TYPES, str(sp.get("npc_type", "trader")), func(v): sp["npc_type"] = v; _mark()))
	r2.add_child(_opt(FACTIONS, str(sp.get("faction", "independent")), func(v): sp["faction"] = v; _mark()))
	var dist := SpinBox.new()
	dist.min_value = 0
	dist.max_value = 9999
	dist.value = int(sp.get("distance", 400))
	dist.prefix = "d"
	dist.value_changed.connect(func(v): sp["distance"] = int(v); _mark())
	r2.add_child(dist)
	vb.add_child(r2)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 12)
	r3.add_child(_check("Hostile", bool(sp.get("hostile", false)), func(on): sp["hostile"] = on; _mark()))
	r3.add_child(_check("Wormhole entry", bool(sp.get("wormhole", true)), func(on): sp["wormhole"] = on; _mark()))
	vb.add_child(r3)
	return p


func _section_nodes() -> Control:
	var enc := _enc()
	var vb := _section("Story nodes")
	var nodes: Dictionary = enc.get("nodes", {})
	var keys := nodes.keys()
	# start first, then the rest in insertion order
	keys.sort_custom(func(a, b): return str(a) == "start" or (str(b) != "start" and str(a) < str(b)))
	for nk in keys:
		vb.add_child(_node_card(enc, str(nk)))
	var addb := NebulaUi.button("＋ Node", "ghost")
	addb.pressed.connect(func():
		var nn := "node_%d" % ((enc.get("nodes", {}) as Dictionary).size())
		(enc["nodes"] as Dictionary)[nn] = EncIO.default_node()
		_mark(); _rebuild_detail())
	vb.add_child(addb)
	return _frame_of(vb)


func _node_card(enc: Dictionary, nk: String) -> Control:
	var node: Dictionary = (enc.get("nodes", {}) as Dictionary)[nk]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	p.add_child(vb)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = "★ START" if nk == "start" else ("NODE  " + nk)
	tag.add_theme_color_override("font_color", Color("#ffcc33") if nk == "start" else NebulaTheme.C_TITLE)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(tag)
	if nk != "start":
		var rm := NebulaUi.button("✕", "ghost")
		rm.pressed.connect(func(): (enc["nodes"] as Dictionary).erase(nk); _mark(); _rebuild_detail())
		hdr.add_child(rm)
	vb.add_child(hdr)
	var spk := LineEdit.new()
	spk.text = str(node.get("speaker", ""))
	spk.placeholder_text = "speaker"
	spk.text_changed.connect(func(t): node["speaker"] = t; _mark())
	vb.add_child(spk)
	var txt := TextEdit.new()
	txt.text = str(node.get("text", ""))
	txt.custom_minimum_size = Vector2(0, 56)
	txt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	txt.text_changed.connect(func(): node["text"] = txt.text; _mark())
	vb.add_child(txt)
	var choices: Array = node.get("choices", [])
	for ci in choices.size():
		vb.add_child(_choice_row(enc, node, ci))
	var addc := NebulaUi.button("＋ choice", "ghost")
	addc.pressed.connect(func():
		(node["choices"] as Array).append({"label": "Choice.", "next": "", "effects": []})
		_mark(); _rebuild_detail())
	vb.add_child(addc)
	return p


func _choice_row(enc: Dictionary, node: Dictionary, idx: int) -> Control:
	var ch: Dictionary = (node.get("choices", []) as Array)[idx]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var lab := LineEdit.new()
	lab.text = str(ch.get("label", ""))
	lab.placeholder_text = "choice label"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.text_changed.connect(func(t): ch["label"] = t; _mark())
	r.add_child(lab)
	# "→ node" picker (node keys + "" = end)
	var node_keys := ["(end)"]
	for k in (enc.get("nodes", {}) as Dictionary):
		node_keys.append(str(k))
	var cur_next := str(ch.get("next", ""))
	var opt := OptionButton.new()
	for i in node_keys.size():
		opt.add_item("→ " + str(node_keys[i]))
		var v: String = "" if node_keys[i] == "(end)" else str(node_keys[i])
		if v == cur_next:
			opt.select(i)
	opt.item_selected.connect(func(i: int): ch["next"] = ("" if node_keys[i] == "(end)" else node_keys[i]); _mark())
	r.add_child(opt)
	var rm := NebulaUi.button("✕", "ghost")
	rm.pressed.connect(func(): (node["choices"] as Array).remove_at(idx); _mark(); _rebuild_detail())
	r.add_child(rm)
	vb.add_child(r)
	# effects mini-editor
	vb.add_child(_effects_editor(ch))
	return vb


func _effects_editor(ch: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	var fx: Array = ch.get("effects", [])
	for i in fx.size():
		var e: Dictionary = fx[i]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(16, 0)
		r.add_child(pad)
		r.add_child(_opt(EFFECT_TYPES, str(e.get("type", "set_flag")), func(v): e["type"] = v; _mark()))
		var amt := LineEdit.new()
		amt.text = str(e.get("amount", e.get("flag", "")))
		amt.placeholder_text = "amount / flag"
		amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amt.text_changed.connect(func(t):
			if t.is_valid_int():
				e["amount"] = int(t)
				e.erase("flag")
			else:
				e["flag"] = t
				e.erase("amount")
			_mark())
		r.add_child(amt)
		var rm := NebulaUi.button("✕", "ghost")
		rm.pressed.connect(func(): (ch["effects"] as Array).remove_at(i); _mark(); _rebuild_detail())
		r.add_child(rm)
		vb.add_child(r)
	var add := NebulaUi.button("＋ effect", "ghost")
	add.pressed.connect(func(): (ch["effects"] as Array).append({"type": "set_flag", "flag": ""}); _mark(); _rebuild_detail())
	vb.add_child(add)
	return vb


# ── small widgets ──────────────────────────────────────────────────────────────

func _frame_of(body: VBoxContainer) -> Control:
	return body.get_parent()


func _segmented(opts: Array, cur: String, on_change: Callable, colored := false) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	for v in opts:
		var s := str(v)
		var b := Button.new()
		b.text = s.to_upper()
		b.toggle_mode = true
		b.button_pressed = s == cur
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: Color = THREAT_COLORS.get(s, NebulaTheme.C_ACCENT) if colored else NebulaTheme.C_ACCENT
		var on := StyleBoxFlat.new()
		on.bg_color = col
		on.set_corner_radius_all(999)
		on.set_content_margin_all(7)
		var off := StyleBoxFlat.new()
		off.bg_color = Color(0.04, 0.06, 0.086, 0.6)
		off.set_corner_radius_all(999)
		off.set_content_margin_all(7)
		b.add_theme_stylebox_override("normal", on if s == cur else off)
		b.add_theme_stylebox_override("hover", on if s == cur else off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_color_override("font_color", NebulaTheme.C_INK if s == cur else NebulaTheme.C_DIM)
		b.add_theme_color_override("font_pressed_color", NebulaTheme.C_INK)
		b.pressed.connect(func(): on_change.call(s))
		hb.add_child(b)
	return hb


func _toggle_row(label: String, value: bool, on_change: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", NebulaTheme.C_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	hb.add_child(_check("", value, on_change))
	return hb


func _check(label: String, value: bool, on_change: Callable) -> Control:
	var cb := CheckButton.new()
	cb.text = label
	cb.button_pressed = value
	cb.toggled.connect(func(on): on_change.call(on))
	return cb


func _num_col(label: String, value: int, lo: int, hi: int, on_change: Callable) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label.to_upper()
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = clampi(value, lo, hi)
	sb.value_changed.connect(func(v): on_change.call(int(v)))
	vb.add_child(sb)
	return vb


func _opt(opts: Array, cur: String, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in opts.size():
		o.add_item(str(opts[i]))
		if str(opts[i]) == cur:
			o.select(i)
	o.item_selected.connect(func(i: int): on_change.call(str(opts[i])))
	return o


# Chip/tag editor over enc[key] (Array of strings): removable chips + add input.
func _chip_editor(label: String, owner: Dictionary, key: String, color: Color) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label.to_upper()
	l.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(l)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	var arr: Array = owner.get(key, [])
	for i in arr.size():
		var tagv := str(arr[i])
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color.r, color.g, color.b, 0.10)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(3)
		sb.content_margin_left = 8
		sb.set_border_width_all(1)
		sb.border_color = Color(color.r, color.g, color.b, 0.45)
		chip.add_theme_stylebox_override("panel", sb)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 4)
		chip.add_child(ch)
		var cl := Label.new()
		cl.text = tagv
		cl.add_theme_color_override("font_color", color)
		cl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		ch.add_child(cl)
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.add_theme_color_override("font_color", color)
		x.pressed.connect(func(): (owner[key] as Array).remove_at(i); _mark(); _rebuild_detail())
		ch.add_child(x)
		flow.add_child(chip)
	var add := LineEdit.new()
	add.placeholder_text = "+ add (Enter)"
	add.custom_minimum_size = Vector2(120, 0)
	add.text_submitted.connect(func(t):
		var v := str(t).strip_edges()
		if v != "":
			if not owner.has(key) or typeof(owner[key]) != TYPE_ARRAY:
				owner[key] = []
			(owner[key] as Array).append(v)
			_mark(); _rebuild_detail())
	flow.add_child(add)
	vb.add_child(flow)
	return vb


# ── ops ────────────────────────────────────────────────────────────────────────

func _new_encounter() -> void:
	var k := EncIO.next_key(_defs)
	_defs[k] = EncIO.default_encounter(int(k))
	_sel = k
	_mark()
	_rebuild_list()
	_rebuild_detail()
	_set_status("added encounter #%s" % k)


func _test_selected() -> void:
	if _sel == "" or not _defs.has(_sel):
		_set_status("nothing selected", true)
		return
	if EncounterManager.has_method("fire_encounter"):
		EncounterManager.load_encounters(_defs)
		EncounterManager.fire_encounter(_defs[_sel])
		close_editor()
	else:
		_set_status("EncounterManager.fire_encounter missing", true)


func _save() -> void:
	# Re-key sequentially so the table stays int-string-keyed and ids match.
	if EncIO.save_defs(_pack_id(), _defs):
		EncounterManager.reload_defs_for_pack(_pack_id())
		_dirty = false
		_set_status("saved %d encounters to '%s'" % [_defs.size(), _pack_id()])
	else:
		_set_status("save failed", true)


func _set_status(msg: String, is_err := false) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_ACCENT)
