class_name MvPlayerWizard
extends CanvasLayer

# Picker-based in-game player setup wizard. Launched by the dev console's
# `wizard player`. Multi-step overlay (Back/Next/Finish):
#   1. Sprite & Animation — pick a preset (PspIO.apply_preset writes frames+poses)
#   2. Movement — physics fields (edits MvPhysicsProfile, ResourceSaver -> .tres)
#   3. Stats — base stats (PedIO.save_stats)
#   4. Abilities — grant ability ids (PedIO.save_abilities)
#   5. Review — apply + save everything
# Controls are fixed engine InputMap actions (not pack-authored) — noted, not edited.

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const PspIO := preload("res://Space/scripts/shared/psp/psp_io.gd")

const STEPS := ["Sprite & Animation", "Movement", "Stats", "Abilities", "Review"]
const PHYS_FIELDS := [
	{"key": "gravity", "label": "Gravity", "min": 0.0, "max": 2000.0, "step": 5.0, "def": 393.75},
	{"key": "jump_speed", "label": "Jump speed", "min": 0.0, "max": 800.0, "step": 5.0, "def": 292.5},
	{"key": "run_max", "label": "Run speed (max)", "min": 0.0, "max": 600.0, "step": 5.0, "def": 165.0},
	{"key": "run_accel", "label": "Run accel", "min": 0.0, "max": 6000.0, "step": 25.0, "def": 675.0},
	{"key": "air_accel", "label": "Air accel", "min": 0.0, "max": 6000.0, "step": 25.0, "def": 2700.0},
	{"key": "max_fall", "label": "Max fall speed", "min": 0.0, "max": 1200.0, "step": 5.0, "def": 300.0},
]
const STAT_FIELDS := [
	{"key": "hp_max", "label": "Max HP", "min": 1.0, "max": 9999.0, "step": 1.0, "def": 50},
	{"key": "str", "label": "Strength", "min": 0.0, "max": 99.0, "step": 1.0, "def": 5},
	{"key": "con", "label": "Constitution", "min": 0.0, "max": 99.0, "step": 1.0, "def": 4},
	{"key": "int", "label": "Intelligence", "min": 0.0, "max": 99.0, "step": 1.0, "def": 3},
	{"key": "lck", "label": "Luck", "min": 0.0, "max": 99.0, "step": 1.0, "def": 4},
]

var _step := 0
var _applied := false
var _result := ""
var _data := {}
var _presets: Array = []
var _title: Label = null
var _content: VBoxContainer = null
var _nav_back: Button = null
var _nav_next: Button = null
var _skin_host: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 132
	_build_shell()
	visible = false


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = Color(NebulaTheme.C_PANEL_DARK.r, NebulaTheme.C_PANEL_DARK.g, NebulaTheme.C_PANEL_DARK.b, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = NebulaTheme.theme()
	_skin_host = margin
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	add_child(margin)
	var frame := PanelContainer.new()
	margin.add_child(frame)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	frame.add_child(root)
	_title = Label.new()
	_title.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	_title.add_theme_font_size_override("font_size", NebulaTheme.size("title"))
	if NebulaTheme.font() != null:
		_title.add_theme_font_override("font", NebulaTheme.font())
	root.add_child(_title)
	root.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.self_modulate = NebulaTheme.C_BORDER
	cancel.pressed.connect(close_wizard)
	nav.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_nav_back = Button.new()
	_nav_back.text = "Back"
	_nav_back.self_modulate = NebulaTheme.C_BORDER
	_nav_back.pressed.connect(_go_back)
	nav.add_child(_nav_back)
	_nav_next = Button.new()
	_nav_next.text = "Next"
	_nav_next.pressed.connect(_go_next)
	nav.add_child(_nav_next)


# ── Lifecycle ────────────────────────────────────────────────────────────────

func open_wizard() -> void:
	_init_data()
	_step = 0
	_applied = false
	_result = ""
	_reskin()
	PlanetaryInterface.edit_session_active = true
	visible = true
	_show_step()


# Re-pick the scale profile (Space build vs MV show) and re-apply size-sensitive
# overrides. See NebulaTheme's SCALE PROFILES note.
func _reskin() -> void:
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()
	if _title != null:
		_title.add_theme_font_size_override("font_size", NebulaTheme.size("title"))


func close_wizard() -> void:
	visible = false
	PlanetaryInterface.edit_session_active = false


func _init_data() -> void:
	var pid := _pack_id()
	_data = {"preset_id": "", "physics": {}, "stats": {}, "abilities": []}
	var pack := MvPackLoader.current_pack
	var prof = pack.physics if pack != null else null
	for f in PHYS_FIELDS:
		var k := str(f["key"])
		_data["physics"][k] = float(prof.get(k)) if prof != null else float(f["def"])
	var st := PedIO.load_stats(pid)
	var base: Dictionary = st.get("base", {})
	for f in STAT_FIELDS:
		var k := str(f["key"])
		_data["stats"][k] = int(base.get(k, f["def"]))
	for a in PedIO.load_abilities(pid).get("abilities", []):
		if typeof(a) == TYPE_DICTIONARY:
			var aid := str((a as Dictionary).get("id", "")).strip_edges()
			if not aid.is_empty() and not (_data["abilities"] as Array).has(aid):
				(_data["abilities"] as Array).append(aid)
	_presets = PspIO.list_presets(pid)


# ── Navigation ───────────────────────────────────────────────────────────────

func _go_back() -> void:
	if _step > 0:
		_step -= 1
		_applied = false
		_show_step()


func _go_next() -> void:
	if _step < STEPS.size() - 1:
		_step += 1
		_show_step()
	elif not _applied:
		_apply_all()
		_applied = true
		_show_step()
	else:
		close_wizard()


func _show_step() -> void:
	_title.text = "PLAYER WIZARD   ·   (%d/%d) %s" % [_step + 1, STEPS.size(), STEPS[_step]]
	_nav_back.disabled = _step == 0
	if _step == STEPS.size() - 1:
		_nav_next.text = "Close" if _applied else "Finish"
	else:
		_nav_next.text = "Next"
	for ch in _content.get_children():
		ch.queue_free()
	match _step:
		0:
			_build_sprite_step()
		1:
			_build_field_step(PHYS_FIELDS, "physics")
		2:
			_build_field_step(STAT_FIELDS, "stats")
		3:
			_build_abilities_step()
		4:
			_build_review_step()


# ── Steps ────────────────────────────────────────────────────────────────────

func _build_sprite_step() -> void:
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _presets.is_empty():
		info.text = "This pack has no sprite presets — the current player sheet is kept. (Import presets via the desktop player editor's Sprites tab.)"
		_content.add_child(info)
		return
	info.text = "Pick a sprite + animation preset (applies its frames and poses), or leave unselected to keep the current sheet:"
	_content.add_child(info)
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(0, 140)
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _presets.size():
		var p: Dictionary = _presets[i]
		il.add_item(str(p.get("name", p.get("id", "preset %d" % i))))
		if str(p.get("id", "")) == str(_data["preset_id"]):
			il.select(i)
	il.item_selected.connect(_on_preset_selected)
	_content.add_child(il)


func _on_preset_selected(idx: int) -> void:
	if idx >= 0 and idx < _presets.size():
		_data["preset_id"] = str((_presets[idx] as Dictionary).get("id", ""))


func _build_field_step(fields: Array, bucket: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for f in fields:
		var key := str(f["key"])
		var lbl := Label.new()
		lbl.text = str(f["label"])
		grid.add_child(lbl)
		var sb := SpinBox.new()
		sb.min_value = float(f["min"])
		sb.max_value = float(f["max"])
		sb.step = float(f["step"])
		sb.value = float((_data[bucket] as Dictionary)[key])
		sb.custom_minimum_size = Vector2(120, 0)
		sb.value_changed.connect(_on_field_changed.bind(bucket, key))
		grid.add_child(sb)


func _on_field_changed(value: float, bucket: String, key: String) -> void:
	(_data[bucket] as Dictionary)[key] = value


func _build_abilities_step() -> void:
	var info := Label.new()
	info.text = "Ability ids granted to the player (any new id is created in the registry):"
	_content.add_child(info)
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(0, 110)
	for aid in _data["abilities"]:
		il.add_item(str(aid))
	_content.add_child(il)
	var row := HBoxContainer.new()
	var le := LineEdit.new()
	le.placeholder_text = "new ability id (e.g. double_jump)"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_on_add_ability.bind(le))
	row.add_child(add)
	_content.add_child(row)


func _on_add_ability(le: LineEdit) -> void:
	var t := le.text.strip_edges()
	if not t.is_empty() and not (_data["abilities"] as Array).has(t):
		(_data["abilities"] as Array).append(t)
		le.text = ""
		_show_step()


func _build_review_step() -> void:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var phys: Dictionary = _data["physics"]
	var stats: Dictionary = _data["stats"]
	var abilities: Array = _data["abilities"]
	var preset := str(_data["preset_id"])
	var s := "Sprite preset: %s\n" % (preset if not preset.is_empty() else "(keep current)")
	s += "Movement: gravity %d · jump %d · run %d · accel %d\n" % [
		int(phys["gravity"]), int(phys["jump_speed"]), int(phys["run_max"]), int(phys["run_accel"])]
	s += "Stats: HP %d · STR %d · CON %d · INT %d · LCK %d\n" % [
		int(stats["hp_max"]), int(stats["str"]), int(stats["con"]), int(stats["int"]), int(stats["lck"])]
	s += "Abilities: %s\n" % (", ".join(_to_str_array(abilities)) if not abilities.is_empty() else "(none)")
	s += "Controls: fixed engine actions (move / jump / shoot) — not pack-authored.\n"
	if _applied:
		s += "\n[ %s ]" % _result
	else:
		s += "\nClick Finish to apply + save everything to the user pack."
	lbl.text = s
	_content.add_child(lbl)


# ── Apply / save ─────────────────────────────────────────────────────────────

func _apply_all() -> void:
	var pid := _pack_id()
	var notes: Array = []

	var preset := str(_data["preset_id"])
	if not preset.is_empty():
		if PspIO.apply_preset(pid, preset):
			notes.append("sprite preset")
		else:
			notes.append("[preset failed]")

	var pack := MvPackLoader.current_pack
	if pack != null:
		var prof = pack.physics
		if prof == null:
			prof = MvPhysicsProfile.new()
			pack.physics = prof
		for f in PHYS_FIELDS:
			var k := str(f["key"])
			prof.set(k, float((_data["physics"] as Dictionary)[k]))
		var dir := str(pack.user_path)
		DirAccess.make_dir_recursive_absolute(dir)
		if ResourceSaver.save(prof, dir + "PhysicsProfile.tres") == OK:
			notes.append("physics")
		else:
			notes.append("[physics save failed]")

	var st := PedIO.load_stats(pid)
	var base: Dictionary = st.get("base", {})
	for f in STAT_FIELDS:
		base[str(f["key"])] = int((_data["stats"] as Dictionary)[str(f["key"])])
	if not base.has("level"):
		base["level"] = 1
		base["exp"] = 0
		base["exp_to_next"] = 100
	if not base.has("mp_max"):
		base["mp_max"] = 10
	if not base.has("heart_max"):
		base["heart_max"] = 5
	st["base"] = base
	if not st.has("growth"):
		st["growth"] = {
			"hp_per_level": 4, "mp_per_level": 2, "heart_per_level": 1,
			"str_per_level": 1, "con_per_level": 1, "int_per_level": 1,
			"lck_per_level": 1, "exp_curve_multiplier": 1.5,
		}
	if PedIO.save_stats(pid, st):
		notes.append("stats")

	var ab := PedIO.load_abilities(pid)
	var arr: Array = ab.get("abilities", [])
	var added := 0
	for aid_v in _data["abilities"]:
		var aid := str(aid_v)
		if not _has_ability(arr, aid):
			arr.append({"id": aid, "name": aid.capitalize(), "category": "movement", "description": "", "params": {}})
			added += 1
	ab["abilities"] = arr
	if PedIO.save_abilities(pid, ab):
		notes.append("abilities (+%d)" % added)

	_result = "Saved to '%s': %s" % [pid, ", ".join(_to_str_array(notes))] if not notes.is_empty() else "nothing to save"


func _has_ability(arr: Array, id: String) -> bool:
	for e in arr:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == id:
			return true
	return false


func _to_str_array(a: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for v in a:
		out.append(str(v))
	return out


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"
