class_name MvCombatWorkshop
extends CanvasLayer

# In-game guided enemy builder — the "Combat Workshop" (enemy track). Opened from
# the dev console with `workshop`. A multi-step picker overlay:
#   1. Identity & Sprite — id / name / category / sprite_set / movement_mode
#   2. Stats & Combat    — hp + contact / melee / projectile stat fields
#   3. Behavior          — WHEN <condition> DO <action> rules -> a Beehave selector tree
#   4. Effects           — pick/create death + projectile-impact effects (EffIO + MvFx)
#   5. Test & Save       — Save (EntIO + BehIO) and Spawn & Fight (spawn_entity_dynamic)
# Everything writes copy-on-write to the user pack (EntIO/BehIO) and the saved enemy
# is immediately spawnable, so the loop is build -> fight -> tweak -> re-fight.
#
# NOTE on scope (honest): an enemy attacks via behavior leaves (`attack`/`shoot`) plus
# the stat fields below — NOT via the player's authored attacks.json/projectiles.json.
# Rich per-frame hitboxes / authored projectiles / FX are the PLAYER track (not built
# here yet). FX is engine-fixed and not authorable.

const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")
const BehIO := preload("res://Space/scripts/shared/beh/beh_io.gd")
const EffIO := preload("res://Space/scripts/shared/eff/eff_io.gd")

const STEPS := ["Identity & Sprite", "Stats & Combat", "Behavior", "Effects", "Test & Save"]
const CATEGORIES := ["enemy", "boss"]
const MOVEMENT_MODES := ["ground", "hover", "fly"]

# Stat fields shown on step 2. INT_KEYS are stored as ints; the rest as floats.
const STAT_FIELDS := [
	{"key": "hp", "label": "Max HP", "min": 1.0, "max": 9999.0, "step": 1.0, "def": 10},
	{"key": "contact_damage", "label": "Contact damage (on touch)", "min": 0.0, "max": 999.0, "step": 1.0, "def": 2},
	{"key": "contact_cooldown", "label": "Contact cooldown (s)", "min": 0.0, "max": 10.0, "step": 0.1, "def": 0.8},
	{"key": "move_speed", "label": "Move speed (px/s)", "min": 0.0, "max": 600.0, "step": 5.0, "def": 40},
	{"key": "attack_damage", "label": "Melee damage", "min": 0.0, "max": 999.0, "step": 1.0, "def": 3},
	{"key": "melee_range", "label": "Melee range (px)", "min": 0.0, "max": 400.0, "step": 1.0, "def": 24},
	{"key": "melee_attack_trigger_frame", "label": "Melee hit frame (-1 = last)", "min": -1.0, "max": 32.0, "step": 1.0, "def": -1},
	{"key": "projectile_damage", "label": "Projectile damage", "min": 0.0, "max": 999.0, "step": 1.0, "def": 3},
	{"key": "projectile_speed", "label": "Projectile speed (px/s)", "min": 0.0, "max": 1200.0, "step": 5.0, "def": 180},
	{"key": "projectile_range", "label": "Projectile range (px)", "min": 0.0, "max": 2000.0, "step": 5.0, "def": 220},
	{"key": "projectile_attack_trigger_frame", "label": "Fire frame (-1 = last)", "min": -1.0, "max": 32.0, "step": 1.0, "def": -1},
]
const INT_KEYS := ["hp", "contact_damage", "attack_damage", "projectile_damage",
	"melee_attack_trigger_frame", "projectile_attack_trigger_frame"]

const STEP_SUBS := ["name, category, sprite", "hp, melee, ranged", "WHEN → DO rules", "death & impact FX", "spawn, tweak, save"]

var _step := 0
var _track := ""  # "" = track select, "enemy" = enemy track, "player" = (not built)
var _data: Dictionary = {}
var _sprite_sets: Array = []
var _title: Label = null
var _track_label: Label = null
var _status: Label = null
var _content: VBoxContainer = null  # per-step WorkPanel body, rebuilt each step
var _work_host: VBoxContainer = null  # scroll's content column
var _rail_host: VBoxContainer = null
var _nav_back: Button = null
var _nav_next: Button = null
var _nav_test: Button = null
var _shell_root: Control = null
var _track_root: Control = null
var _skin_host: Control = null
var _prev_scale_size := Vector2i.ZERO  # restored on close (full-res content-scale flip)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 133
	_build_shell()
	visible = false


# Builds both the entry track-select screen and the three-zone editor shell
# (header / [step rail | work area] / bottom nav), per the Nebula mockup. Only
# one is visible at a time (_show_screen toggles).
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
	_build_track_select(margin)
	_build_editor(margin)


func _build_track_select(parent: Control) -> void:
	_track_root = CenterContainer.new()
	_track_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(_track_root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_track_root.add_child(col)
	var title := NebulaTheme.title_label("Combat Workshop")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "CHOOSE WHAT TO BUILD"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	col.add_child(sub)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	cards.add_child(NebulaUi.track_card("Build an Enemy",
		"Identity, stats, melee & ranged, then assemble AI as WHEN → DO rules. Spawn & fight to tune.",
		func(): _pick_track("enemy")))
	cards.add_child(NebulaUi.track_card("Player's Attacks",
		"Per-frame melee hitboxes and rich projectiles. Not wired into the engine yet — coming next.",
		func(): _pick_track("player")))


func _build_editor(parent: Control) -> void:
	_shell_root = VBoxContainer.new()
	_shell_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell_root.add_theme_constant_override("separation", 0)
	parent.add_child(_shell_root)

	# Header: title + track label + Switch Track + close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	_shell_root.add_child(header)
	_title = NebulaTheme.title_label("Combat Workshop")
	header.add_child(_title)
	_track_label = Label.new()
	_track_label.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	_track_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_track_label)
	var hspacer := Control.new()
	hspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hspacer)
	var switch := NebulaUi.button("Switch Track", "ghost")
	switch.pressed.connect(func(): _pick_track(""))
	header.add_child(switch)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_workshop)
	header.add_child(close)
	_shell_root.add_child(_hsep())

	# Body: step rail + work area.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell_root.add_child(body)
	var rail_pad := MarginContainer.new()
	rail_pad.add_theme_constant_override("margin_top", 12)
	rail_pad.add_theme_constant_override("margin_right", 8)
	rail_pad.custom_minimum_size = Vector2(248 if NebulaTheme.profile() == "full" else 130, 0)
	body.add_child(rail_pad)
	_rail_host = VBoxContainer.new()
	rail_pad.add_child(_rail_host)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_work_host = VBoxContainer.new()
	_work_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_work_host.add_theme_constant_override("separation", 16)
	scroll.add_child(_work_host)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shell_root.add_child(_status)

	# Bottom nav: ← Back (ghost) · ▶ Test (gold) · Next → (cyan).
	_shell_root.add_child(_hsep())
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	_shell_root.add_child(nav)
	_nav_back = NebulaUi.button("← Back", "ghost")
	_nav_back.pressed.connect(_go_back)
	nav.add_child(_nav_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_nav_test = NebulaUi.button("▶ Test", "gold")
	_nav_test.pressed.connect(_spawn_and_fight)
	nav.add_child(_nav_test)
	_nav_next = NebulaUi.button("Next →", "primary")
	_nav_next.pressed.connect(_go_next)
	nav.add_child(_nav_next)


func _hsep() -> Control:
	var s := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.18)
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	s.add_theme_stylebox_override("panel", box)
	s.custom_minimum_size = Vector2(0, 2)
	return s


# ── Lifecycle ────────────────────────────────────────────────────────────────

func open_workshop() -> bool:
	if MvGame.main == null or not is_instance_valid(MvGame.main):
		return false
	# The game renders at native 1920 now, so the editor is already full-res.
	_init_data()
	_step = 0
	_reskin()
	PlanetaryInterface.edit_session_active = true
	MvGame.simulation_paused = true
	visible = true
	_set_status("")
	_pick_track("")
	return true


func close_workshop() -> void:
	visible = false
	PlanetaryInterface.edit_session_active = false
	MvGame.simulation_paused = false


# Re-pick the scale profile and re-apply the shared theme. See NebulaTheme.
func _reskin() -> void:
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()


# Pick a track ("" = entry select, "enemy", "player") and show the right screen.
func _pick_track(track: String) -> void:
	_track = track
	if _track_label != null:
		_track_label.text = "/ Build an Enemy" if track == "enemy" else ("/ Player's Attacks" if track == "player" else "")
	_track_root.visible = track == ""
	_shell_root.visible = track != ""
	_set_status("")
	if track == "enemy":
		_init_data()
		_step = 0
		_show_step()
	elif track == "player":
		_show_player_placeholder()


func _show_player_placeholder() -> void:
	for c in _rail_host.get_children():
		c.queue_free()
	for c in _work_host.get_children():
		c.queue_free()
	var wp := NebulaUi.work_panel("Player's Attacks — not wired yet")
	_work_host.add_child(wp["root"])
	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_color_override("font_color", NebulaTheme.C_BODY)
	msg.text = "The player-attack track (per-frame melee hitboxes + authored projectiles with homing/explosive/trails) isn't built into the engine yet. The enemy track is fully working — use Switch Track to build an enemy."
	wp["body"].add_child(msg)
	_nav_back.disabled = false
	_nav_next.disabled = true
	_nav_test.disabled = true


func _init_data() -> void:
	_data = {
		"id": "", "name": "", "category": "enemy",
		"sprite_set": "", "movement_mode": "ground",
		"hover_amp": 6.0, "hover_speed": 1.2,
		"death_fx": "", "impact_fx": "",
		"fx_draft": EffIO.default_effect("new_effect"),
		"stats": {}, "rules": [],
	}
	for f in STAT_FIELDS:
		_data["stats"][str(f["key"])] = f["def"]
	(_data["rules"] as Array).append(_default_rule())
	_sprite_sets = EntIO.list_sprite_sets(_pack_id())


func _default_rule() -> Dictionary:
	return {
		"cond": "player_near",
		"cond_params": BehLeafSchema.default_params_for("condition", "player_near"),
		"action": "pursue",
		"action_params": BehLeafSchema.default_params_for("action", "pursue"),
	}


# ── Navigation ───────────────────────────────────────────────────────────────

func _go_back() -> void:
	if _step > 0:
		_step -= 1
		_show_step()
	else:
		_pick_track("")  # back from step 1 returns to track select


func _go_next() -> void:
	if _step == 0 and str(_data["id"]).strip_edges().is_empty():
		_set_status("An entity id is required to continue.", true)
		return
	if _step < STEPS.size() - 1:
		_step += 1
		_show_step()
	elif _save_all():
		close_workshop()


func _show_step() -> void:
	_refresh_rail()
	for c in _work_host.get_children():
		c.queue_free()
	# Each step's content lives inside a framed WorkPanel. Steps that have a
	# preview render two columns (work | preview), per the mockup; the rest cap
	# the work panel width so fields don't stretch edge-to-edge.
	var wp := NebulaUi.work_panel("")
	var panel: Control = wp["root"]
	_content = wp["body"]
	var preview := _build_preview(_step)
	if preview != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = 1.1
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_stretch_ratio = 0.9
		row.add_child(panel)
		row.add_child(preview)
		_work_host.add_child(row)
	else:
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.custom_minimum_size = Vector2(880 if NebulaTheme.profile() == "full" else 300, 0)
		_work_host.add_child(panel)
	match _step:
		0: _build_identity()
		1: _build_stats()
		2: _build_behavior()
		3: _build_effects()
		4: _build_review()
	_nav_back.disabled = false
	_nav_test.disabled = false
	_nav_next.disabled = false
	_nav_next.text = "Save & Close →" if _step == STEPS.size() - 1 else "Next →"


# Builds the right-side "Preview" column for steps that have one (identity,
# stats, test). Returns null for full-width steps (behavior, effects). The
# hurtbox is auto-derived from the body, so it shows even without art.
func _build_preview(step: int) -> Control:
	var boxes: Array = []
	var label := ""
	match step:
		0:
			label = "Idle · " + _disp_name()
			boxes = [{"x": 0.37, "y": 0.26, "w": 0.26, "h": 0.48, "color": NebulaTheme.C_SUCCESS, "label": "hurtbox (auto)"}]
		1:
			label = "Body / hurtbox · " + _disp_name()
			boxes = [
				{"x": 0.37, "y": 0.24, "w": 0.26, "h": 0.50, "color": NebulaTheme.C_SUCCESS, "label": "hurtbox"},
				{"x": 0.30, "y": 0.70, "w": 0.40, "h": 0.14, "color": NebulaTheme.C_ACCENT_2, "fill": true, "label": "melee range"},
			]
		4:
			label = "Live · " + _disp_name()
			boxes = [{"x": 0.37, "y": 0.24, "w": 0.26, "h": 0.50, "color": NebulaTheme.C_SUCCESS, "label": "hp %s" % _data["stats"].get("hp", 0)}]
		_:
			return null
	var wp := NebulaUi.work_panel("Preview")
	wp["body"].add_child(NebulaUi.preview_pane(label, boxes))
	if step == 1:
		var note := _hint("The hurtbox is derived from the sprite size — it can't be hand-drawn for enemies.")
		wp["body"].add_child(note)
	return wp["root"]


func _disp_name() -> String:
	var nm := str(_data["name"]).strip_edges()
	if not nm.is_empty():
		return nm
	var id := str(_data["id"]).strip_edges()
	return id if not id.is_empty() else "(unnamed)"


func _refresh_rail() -> void:
	for c in _rail_host.get_children():
		c.queue_free()
	var rail := NebulaUi.step_rail(STEPS, STEP_SUBS, _step, func(i): _jump_to_step(i))
	_rail_host.add_child(rail)


func _jump_to_step(i: int) -> void:
	# Don't let the user skip past step 1 without an id.
	if i > 0 and str(_data["id"]).strip_edges().is_empty():
		_set_status("An entity id is required first.", true)
		return
	_step = clampi(i, 0, STEPS.size() - 1)
	_show_step()


# ── Step 1: Identity & Sprite ────────────────────────────────────────────────

func _build_identity() -> void:
	_content.add_child(_section("Who is this creature?"))
	var id_edit := LineEdit.new()
	id_edit.text = str(_data["id"])
	id_edit.placeholder_text = "id (e.g. goblin) — required, no spaces"
	id_edit.text_changed.connect(func(t): _data["id"] = t.strip_edges())
	_content.add_child(_labeled("Entity id", id_edit))
	var name_edit := LineEdit.new()
	name_edit.text = str(_data["name"])
	name_edit.placeholder_text = "display name (optional)"
	name_edit.text_changed.connect(func(t): _data["name"] = t.strip_edges())
	_content.add_child(_labeled("Name", name_edit))
	var cat := OptionButton.new()
	for i in CATEGORIES.size():
		cat.add_item(str(CATEGORIES[i]).capitalize(), i)
	cat.selected = max(0, CATEGORIES.find(str(_data["category"])))
	cat.item_selected.connect(func(idx): _data["category"] = CATEGORIES[idx])
	_content.add_child(_labeled("Category", cat))
	var spr := OptionButton.new()
	spr.add_item("(none → placeholder box)", 0)
	for i in _sprite_sets.size():
		spr.add_item(str(_sprite_sets[i]), i + 1)
	var cur := _sprite_sets.find(str(_data["sprite_set"]))
	spr.selected = (cur + 1) if cur >= 0 else 0
	spr.item_selected.connect(func(idx): _data["sprite_set"] = "" if idx == 0 else str(_sprite_sets[idx - 1]))
	_content.add_child(_labeled("Sprite set", spr))
	if _sprite_sets.is_empty():
		_content.add_child(_hint("No sprite folders found under Sprites/. The creature will render as a placeholder box; drop PNGs in Content/<pack>/Sprites/<name>/ to give it art."))
	var mv := OptionButton.new()
	for i in MOVEMENT_MODES.size():
		mv.add_item(str(MOVEMENT_MODES[i]).capitalize(), i)
	mv.selected = max(0, MOVEMENT_MODES.find(str(_data["movement_mode"])))
	mv.item_selected.connect(func(idx):
		_data["movement_mode"] = MOVEMENT_MODES[idx]
		_show_step())
	_content.add_child(_labeled("Movement", mv))
	if str(_data["movement_mode"]) != "ground":
		var amp := _spin(0.0, 64.0, 0.5, float(_data["hover_amp"]))
		amp.value_changed.connect(func(v): _data["hover_amp"] = v)
		_content.add_child(_labeled("Hover bob amplitude", amp))
		var hs := _spin(0.0, 10.0, 0.1, float(_data["hover_speed"]))
		hs.value_changed.connect(func(v): _data["hover_speed"] = v)
		_content.add_child(_labeled("Hover bob speed", hs))


# ── Step 2: Stats & Combat ───────────────────────────────────────────────────

func _build_stats() -> void:
	_content.add_child(_section("Combat stats"))
	var stats: Dictionary = _data["stats"]
	for f in STAT_FIELDS:
		var key := str(f["key"])
		var sb := _spin(float(f["min"]), float(f["max"]), float(f["step"]), float(stats.get(key, f["def"])))
		sb.value_changed.connect(func(v): stats[key] = v)
		_content.add_child(_labeled(str(f["label"]), sb))
	_content.add_child(_hint("Melee fields apply when a behavior rule uses 'Attack in melee'; projectile fields when it uses 'Shoot a projectile'. Trigger frame -1 means fire on the last animation frame."))


# ── Step 3: Behavior ─────────────────────────────────────────────────────────

func _build_behavior() -> void:
	_content.add_child(_section("Behavior — WHEN a condition is true, DO an action"))
	_content.add_child(_hint("Rules run top-to-bottom each tick; the first whose condition passes runs its action. An automatic 'idle' fallback is appended last."))
	var rules: Array = _data["rules"]
	for ri in rules.size():
		_content.add_child(_build_rule_row(ri))
	var add := Button.new()
	add.text = "+ Add rule"
	add.pressed.connect(func():
		(_data["rules"] as Array).append(_default_rule())
		_show_step())
	_content.add_child(add)


func _build_rule_row(ri: int) -> Control:
	var rule: Dictionary = _data["rules"][ri]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", NebulaTheme.card_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	box.add_child(vb)
	var head := HBoxContainer.new()
	head.add_child(_tag("WHEN"))
	var cnames := BehLeafSchema.condition_names()
	var clabels := BehLeafSchema.condition_labels()
	var cond_opt := OptionButton.new()
	for i in cnames.size():
		cond_opt.add_item(str(clabels[i]), i)
	cond_opt.selected = max(0, cnames.find(str(rule["cond"])))
	cond_opt.item_selected.connect(func(idx): _set_rule_cond(ri, str(cnames[idx])))
	head.add_child(cond_opt)
	head.add_child(_tag("DO"))
	var anames := BehLeafSchema.action_names()
	var alabels := BehLeafSchema.action_labels()
	var act_opt := OptionButton.new()
	for i in anames.size():
		act_opt.add_item(str(alabels[i]), i)
	act_opt.selected = max(0, anames.find(str(rule["action"])))
	act_opt.item_selected.connect(func(idx): _set_rule_action(ri, str(anames[idx])))
	head.add_child(act_opt)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(func():
		(_data["rules"] as Array).remove_at(ri)
		if (_data["rules"] as Array).is_empty():
			(_data["rules"] as Array).append(_default_rule())
		_show_step())
	head.add_child(del)
	vb.add_child(head)
	_build_params(vb, "condition", str(rule["cond"]), rule["cond_params"])
	_build_params(vb, "action", str(rule["action"]), rule["action_params"])
	return box


func _set_rule_cond(ri: int, cond: String) -> void:
	var rule: Dictionary = _data["rules"][ri]
	rule["cond"] = cond
	rule["cond_params"] = BehLeafSchema.default_params_for("condition", cond)
	_show_step()


func _set_rule_action(ri: int, action: String) -> void:
	var rule: Dictionary = _data["rules"][ri]
	rule["action"] = action
	rule["action_params"] = BehLeafSchema.default_params_for("action", action)
	_show_step()


func _build_params(parent: VBoxContainer, kind: String, leaf_name: String, params: Dictionary) -> void:
	var schema := BehLeafSchema.find_schema(kind, leaf_name)
	var fields: Array = schema.get("fields", [])
	for f_v in fields:
		var f: Array = f_v
		var fkey := str(f[0])
		var flabel := str(f[1])
		var fkind := str(f[2])
		var ctrl: Control = _param_control(fkey, fkind, params)
		parent.add_child(_labeled("       " + flabel, ctrl))


func _param_control(fkey: String, fkind: String, params: Dictionary) -> Control:
	if BehLeafSchema.is_enum(fkind):
		var opt := OptionButton.new()
		var vals := BehLeafSchema.enum_values(fkind)
		for i in vals.size():
			opt.add_item(str(vals[i]), i)
		opt.selected = max(0, vals.find(str(params.get(fkey, ""))))
		opt.item_selected.connect(func(idx): params[fkey] = str(vals[idx]))
		return opt
	if fkind == "bool":
		var cb := CheckBox.new()
		cb.button_pressed = bool(params.get(fkey, false))
		cb.toggled.connect(func(v): params[fkey] = v)
		return cb
	if fkind == "string":
		var le := LineEdit.new()
		le.text = str(params.get(fkey, ""))
		le.text_changed.connect(func(t): params[fkey] = t)
		return le
	var isint := fkind == "int"
	var sb := SpinBox.new()
	sb.min_value = -9999
	sb.max_value = 9999
	sb.step = 1.0 if isint else 0.05
	sb.value = float(params.get(fkey, 0))
	sb.custom_minimum_size = Vector2(120, 0)
	sb.value_changed.connect(func(v): params[fkey] = int(round(v)) if isint else v)
	return sb


# ── Step 4: Effects ──────────────────────────────────────────────────────────

func _build_effects() -> void:
	_content.add_child(_section("Effects"))
	var ids := MvFx.list_ids(_pack_id())
	_content.add_child(_fx_picker("Death effect", "death_fx", ids))
	_content.add_child(_fx_picker("Projectile impact effect", "impact_fx", ids))
	_content.add_child(_hint("Death effect plays when the creature dies. Impact effect only applies to ranged enemies (a behavior rule using 'Shoot a projectile'). Pick a built-in or make your own below."))
	_content.add_child(HSeparator.new())
	_content.add_child(_section("Create / tune an effect"))
	_build_effect_creator()


func _fx_picker(label: String, key: String, ids: Array) -> Control:
	var opt := OptionButton.new()
	opt.add_item("(none)", 0)
	for i in ids.size():
		opt.add_item(str(ids[i]), i + 1)
	var cur := ids.find(str(_data[key]))
	opt.selected = (cur + 1) if cur >= 0 else 0
	opt.item_selected.connect(func(idx): _data[key] = "" if idx == 0 else str(ids[idx - 1]))
	return _labeled(label, opt)


func _build_effect_creator() -> void:
	var d: Dictionary = _data["fx_draft"]
	var id_e := LineEdit.new()
	id_e.text = str(d.get("id", ""))
	id_e.placeholder_text = "effect id (e.g. fire_burst)"
	id_e.text_changed.connect(func(t): d["id"] = t.strip_edges())
	_content.add_child(_labeled("Effect id", id_e))
	var nm_e := LineEdit.new()
	nm_e.text = str(d.get("name", ""))
	nm_e.text_changed.connect(func(t): d["name"] = t)
	_content.add_child(_labeled("Name", nm_e))
	_content.add_child(_labeled("Particle count", _fx_spin(d, "count", 1.0, 64.0, 1.0, true)))
	var cols: Array = d.get("colors", ["#ffffff"])
	var c1 := ColorPickerButton.new()
	c1.color = _html(str(cols[0]) if cols.size() > 0 else "#ffffff")
	c1.custom_minimum_size = Vector2(120, 0)
	c1.color_changed.connect(func(c): _set_color(d, 0, c))
	_content.add_child(_labeled("Color A", c1))
	var c2 := ColorPickerButton.new()
	c2.color = _html(str(cols[1]) if cols.size() > 1 else "#ffffff")
	c2.custom_minimum_size = Vector2(120, 0)
	c2.color_changed.connect(func(c): _set_color(d, 1, c))
	_content.add_child(_labeled("Color B", c2))
	_content.add_child(_labeled("Speed min (px/s)", _fx_spin(d, "speed_min", 0.0, 600.0, 2.0, false)))
	_content.add_child(_labeled("Speed max (px/s)", _fx_spin(d, "speed_max", 0.0, 600.0, 2.0, false)))
	_content.add_child(_labeled("Size min", _fx_spin(d, "size_min", 0.1, 8.0, 0.1, false)))
	_content.add_child(_labeled("Size max", _fx_spin(d, "size_max", 0.1, 8.0, 0.1, false)))
	_content.add_child(_labeled("Lifetime (s)", _fx_spin(d, "lifetime", 0.05, 3.0, 0.05, false)))
	_content.add_child(_labeled("Gravity (px/s²)", _fx_spin(d, "gravity", -600.0, 1200.0, 10.0, false)))
	_content.add_child(_labeled("Spread (rad, 6.28 = full)", _fx_spin(d, "spread", 0.0, 6.283, 0.1, false)))
	var dir_cb := CheckBox.new()
	dir_cb.button_pressed = bool(d.get("directional", false))
	dir_cb.toggled.connect(func(v): d["directional"] = v)
	_content.add_child(_labeled("Directional (bias toward travel)", dir_cb))
	var btns := HBoxContainer.new()
	var test_b := Button.new()
	test_b.text = "▶  Test at player"
	test_b.pressed.connect(_test_effect)
	btns.add_child(test_b)
	var save_b := Button.new()
	save_b.text = "💾  Save effect to pack"
	save_b.pressed.connect(_save_effect)
	btns.add_child(save_b)
	_content.add_child(btns)


func _fx_spin(d: Dictionary, key: String, lo: float, hi: float, step: float, isint: bool) -> SpinBox:
	var sb := _spin(lo, hi, step, float(d.get(key, 0)))
	sb.value_changed.connect(func(v): d[key] = int(round(v)) if isint else v)
	return sb


func _html(s: String) -> Color:
	return Color.html(s) if not s.strip_edges().is_empty() else Color(1, 1, 1)


func _set_color(d: Dictionary, idx: int, c: Color) -> void:
	var cols: Array = d.get("colors", [])
	while cols.size() <= idx:
		cols.append("#ffffff")
	cols[idx] = "#" + c.to_html(false)
	d["colors"] = cols


func _save_effect() -> void:
	var draft: Dictionary = _data["fx_draft"]
	var id := str(draft.get("id", "")).strip_edges()
	if id.is_empty():
		_set_status("The effect needs an id before saving.", true)
		return
	var pid := _pack_id()
	var root := EffIO.load_or_init(pid)
	var arr_v: Variant = root.get("effects", [])
	var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
	var replaced := false
	for i in arr.size():
		if typeof(arr[i]) == TYPE_DICTIONARY and str((arr[i] as Dictionary).get("id", "")) == id:
			arr[i] = draft.duplicate(true)
			replaced = true
			break
	if not replaced:
		arr.append(draft.duplicate(true))
	root["effects"] = arr
	if not EffIO.save_effects(pid, root):
		_set_status("Saving the effect failed (see Godot Output).", true)
		return
	MvFx.clear_cache()
	_set_status("Saved effect '%s' — now selectable above." % id)
	_show_step()


func _test_effect() -> void:
	var m := MvGame.main as MvMain
	if m == null:
		_set_status("Test needs a live MV room.", true)
		return
	var draft: Dictionary = _data["fx_draft"]
	var pos := m.get_player_position() + Vector2(0, -8)
	visible = false
	MvFx.spawn_def(draft, null, pos)
	var dur := maxf(0.3, float(draft.get("lifetime", 0.3)) + 0.2)
	var timer := get_tree().create_timer(dur)
	timer.timeout.connect(func(): visible = true)


# ── Step 5: Test & Save ──────────────────────────────────────────────────────

func _build_review() -> void:
	_content.add_child(_section("Review"))
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = _summary_text()
	_content.add_child(summary)
	_content.add_child(HSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "💾  Save to pack"
	save_btn.pressed.connect(func():
		if _save_all():
			_set_status("Saved '%s' to pack '%s'." % [str(_data["id"]).strip_edges(), _pack_id()]))
	_content.add_child(save_btn)
	var fight_btn := Button.new()
	fight_btn.text = "⚔  Spawn & Fight"
	fight_btn.pressed.connect(_spawn_and_fight)
	_content.add_child(fight_btn)
	_content.add_child(_hint("Spawn & Fight saves, closes the workshop, unpauses, and drops the creature next to you. Re-open with `workshop` and tweak, then fight again."))


func _summary_text() -> String:
	var s: Dictionary = _data["stats"]
	var lines: Array = []
	lines.append("%s  (%s, %s)" % [
		str(_data["name"]) if not str(_data["name"]).strip_edges().is_empty() else str(_data["id"]),
		str(_data["category"]), str(_data["movement_mode"])])
	lines.append("HP %s · contact %s · move %s px/s" % [s.get("hp"), s.get("contact_damage"), s.get("move_speed")])
	lines.append("sprite: %s" % ("(placeholder)" if str(_data["sprite_set"]).is_empty() else str(_data["sprite_set"])))
	var dfx := str(_data["death_fx"]).strip_edges()
	var ifx := str(_data["impact_fx"]).strip_edges()
	if not dfx.is_empty() or not ifx.is_empty():
		lines.append("fx: death=%s · impact=%s" % [dfx if not dfx.is_empty() else "—", ifx if not ifx.is_empty() else "—"])
	var rules: Array = _data["rules"]
	for r_v in rules:
		var r: Dictionary = r_v
		lines.append("WHEN %s DO %s" % [str(r["cond"]), str(r["action"])])
	return "\n".join(lines)


func _spawn_and_fight() -> void:
	if not _save_all():
		return
	var rm := MvGame.room_manager as MvRoomManager
	var m := MvGame.main as MvMain
	if rm == null or m == null:
		_set_status("Spawn needs a live MV room.", true)
		return
	var id := str(_data["id"]).strip_edges()
	var pos := m.get_player_position() + Vector2(56, -8)
	var node := rm.spawn_entity_dynamic(id, pos)
	if node == null:
		_set_status("Spawn failed — entity '%s' not found after save." % id, true)
		return
	close_workshop()


# ── Persistence ──────────────────────────────────────────────────────────────

func _save_all() -> bool:
	var pid := _pack_id()
	var id := str(_data["id"]).strip_edges()
	if id.is_empty():
		_set_status("An entity id is required (step 1).", true)
		return false
	var beh_id := id + "_ai"
	var ent := EntIO.default_entity(id)
	var nm := str(_data["name"]).strip_edges()
	ent["name"] = nm if not nm.is_empty() else id.capitalize()
	ent["category"] = str(_data["category"])
	ent["sprite_set"] = str(_data["sprite_set"]).strip_edges()
	ent["movement_mode"] = str(_data["movement_mode"])
	ent["behavior"] = beh_id
	ent["death_fx"] = str(_data["death_fx"]).strip_edges()
	ent["impact_fx"] = str(_data["impact_fx"]).strip_edges()
	var stats: Dictionary = _data["stats"]
	for f in STAT_FIELDS:
		var k := str(f["key"])
		var v: float = float(stats.get(k, f["def"]))
		ent[k] = int(round(v)) if INT_KEYS.has(k) else v
	if str(_data["movement_mode"]) != "ground":
		ent["hover_bob_amplitude"] = float(_data["hover_amp"])
		ent["hover_bob_speed"] = float(_data["hover_speed"])

	var ents := EntIO.load_or_init(pid)
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
	if not EntIO.save_entities(pid, ents):
		_set_status("Saving the entity failed (see Godot Output).", true)
		return false

	var beh := BehIO.load_or_init(pid)
	var blist_v: Variant = beh.get("behaviors", [])
	var blist: Array = blist_v if typeof(blist_v) == TYPE_ARRAY else []
	var nb := _compile_behavior(beh_id)
	var beh_replaced := false
	for i in blist.size():
		if typeof(blist[i]) == TYPE_DICTIONARY and str((blist[i] as Dictionary).get("id", "")) == beh_id:
			blist[i] = nb
			beh_replaced = true
			break
	if not beh_replaced:
		blist.append(nb)
	beh["behaviors"] = blist
	if not BehIO.save_behaviors(pid, beh):
		_set_status("Entity saved, but saving the behavior failed (see Output).", true)
		return false
	return true


# Build a Beehave selector: each rule becomes a sequence[condition, action]; an
# idle action is appended as the always-true fallback. Matches beh_loader's schema.
func _compile_behavior(beh_id: String) -> Dictionary:
	var children: Array = []
	var rules: Array = _data["rules"]
	for r_v in rules:
		var r: Dictionary = r_v
		children.append({
			"type": "sequence",
			"name": "%s→%s" % [str(r["cond"]), str(r["action"])],
			"params": {},
			"children": [
				{"type": "condition", "name": str(r["cond"]), "condition": str(r["cond"]), "params": (r["cond_params"] as Dictionary).duplicate(true)},
				{"type": "action", "name": str(r["action"]), "action": str(r["action"]), "params": (r["action_params"] as Dictionary).duplicate(true)},
			],
		})
	children.append({"type": "action", "name": "idle", "action": "idle", "params": {}})
	var nm := str(_data["name"]).strip_edges()
	return {
		"id": beh_id,
		"name": "%s AI" % (nm if not nm.is_empty() else str(_data["id"])),
		"description": "Authored in the Combat Workshop.",
		"root": {"type": "selector", "name": "root", "params": {}, "children": children},
	}


# ── Helpers ──────────────────────────────────────────────────────────────────

func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


func _section(text: String) -> Control:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", NebulaTheme.size("section"))
	l.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	return l


func _hint(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	return l


func _tag(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	return l


func _labeled(text: String, control: Control) -> Control:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(230, 0)
	hb.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	return hb


func _spin(lo: float, hi: float, step: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	sb.custom_minimum_size = Vector2(120, 0)
	return sb


func _set_status(msg: String, is_err: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_SUCCESS)
