class_name MvPlayerAttackWorkshop
extends CanvasLayer

# In-game guided PLAYER attack builder — the player-side companion to the enemy
# Combat Workshop. Opened from the dev console with `attacks` (MV-only). A
# multi-step picker overlay that authors the player's attacks.json (and, for
# ranged attacks, projectiles.json), copy-on-write to the user pack via PedIO:
#   1. Attack            — id / name / type (melee|projectile) / cooldown / hold
#   2. Hit / Projectile  — melee hitbox + hit frames + combo, OR projectile def
#   3. Test & Save       — save (PedIO) → reload defs → fire it live
# After a save, PlayerInventory.reload_combat_defs() drops the def cache so the
# attack is usable immediately. Projectile attacks are set active so your shoot
# input fires them right away; melee attacks save to attacks.json and play when
# reached through your combo chain.
#
# Scope (honest): this authors the data fields the runtime actually consumes
# (player.gd melee geometry + authored projectiles). It deliberately omits
# `player_pose` (no authored-pose picker yet → no pose override), `knockback`
# (saved but the player melee path does not yet apply it), and charge-release
# chains. Those are future slices.

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")

const STEPS := ["Attack", "Hit / Projectile", "Test & Save"]
const STEP_SUBS := ["id, name, type", "hitbox or projectile", "save & fire"]
const ATTACK_TYPES := ["melee", "projectile"]
const HOLD_BEHAVIORS := ["single_press", "full_auto"]

var _step := 0
var _data: Dictionary = {}
var _existing_attack_ids: Array = []  # for the melee combo target picker
var _title: Label = null
var _status: Label = null
var _content: VBoxContainer = null
var _work_host: VBoxContainer = null
var _rail_host: VBoxContainer = null
var _nav_back: Button = null
var _nav_next: Button = null
var _nav_test: Button = null
var _shell_root: Control = null
var _skin_host: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 134
	_build_shell()
	visible = false


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
	_build_editor(margin)


func _build_editor(parent: Control) -> void:
	_shell_root = VBoxContainer.new()
	_shell_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell_root.add_theme_constant_override("separation", 0)
	parent.add_child(_shell_root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	_shell_root.add_child(header)
	_title = NebulaTheme.title_label("Player Attack Workshop")
	header.add_child(_title)
	var hspacer := Control.new()
	hspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hspacer)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_workshop)
	header.add_child(close)
	_shell_root.add_child(_hsep())

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
	_nav_test.pressed.connect(_test_attack)
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
	_init_data()
	_step = 0
	_reskin()
	PlanetaryInterface.edit_session_active = true
	MvGame.simulation_paused = true
	visible = true
	_set_status("")
	_show_step()
	return true


func close_workshop() -> void:
	visible = false
	PlanetaryInterface.edit_session_active = false
	MvGame.simulation_paused = false


func _reskin() -> void:
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()


func _init_data() -> void:
	_data = {
		"id": "", "name": "", "type": "melee",
		"cooldown_ticks": 24, "hold_behavior": "single_press",
		"muzzle_x": 20, "muzzle_y": -8,
		# melee
		"damage": 12, "hitbox_x": 18, "hitbox_y": -6, "hitbox_w": 28, "hitbox_h": 24,
		"hit_frames": "1,2", "combo_next_id": "",
		# projectile (nested def)
		"proj": {
			"id": "", "name": "", "speed": 360, "damage": 12, "lifetime_ticks": 120,
			"gravity": 0, "pierces": false, "homing": false, "homing_strength": 90,
			"rotate_to_velocity": false, "trail_color": "#88ccff",
			"hitbox_w": 12, "hitbox_h": 6,
			"explosive": false, "blast_radius": 40, "explosion_damage": 20,
		},
	}
	_existing_attack_ids = _load_existing_attack_ids()


func _load_existing_attack_ids() -> Array:
	var out: Array = []
	var doc := PedIO.load_attacks(_pack_id())
	var arr_v: Variant = doc.get("attacks", [])
	if typeof(arr_v) == TYPE_ARRAY:
		for e_v in (arr_v as Array):
			if typeof(e_v) == TYPE_DICTIONARY:
				var aid := str((e_v as Dictionary).get("id", "")).strip_edges()
				if not aid.is_empty():
					out.append(aid)
	return out


# ── Navigation ───────────────────────────────────────────────────────────────

func _go_back() -> void:
	if _step > 0:
		_step -= 1
		_show_step()


func _go_next() -> void:
	if _step == 0 and not _validate_identity():
		return
	if _step < STEPS.size() - 1:
		_step += 1
		_show_step()
	elif _save_all():
		close_workshop()


func _validate_identity() -> bool:
	var id := str(_data["id"]).strip_edges()
	if id.is_empty():
		_set_status("An attack id is required to continue.", true)
		return false
	if id.contains(" "):
		_set_status("Attack id can't contain spaces.", true)
		return false
	return true


func _show_step() -> void:
	_refresh_rail()
	for c in _work_host.get_children():
		c.queue_free()
	var wp := NebulaUi.work_panel("")
	var panel: Control = wp["root"]
	_content = wp["body"]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(880 if NebulaTheme.profile() == "full" else 300, 0)
	_work_host.add_child(panel)
	match _step:
		0: _build_identity()
		1: _build_hit()
		2: _build_review()
	_nav_back.disabled = _step == 0
	_nav_test.disabled = false
	_nav_next.text = "Save & Close →" if _step == STEPS.size() - 1 else "Next →"


func _refresh_rail() -> void:
	for c in _rail_host.get_children():
		c.queue_free()
	_rail_host.add_child(NebulaUi.step_rail(STEPS, STEP_SUBS, _step, func(i): _jump_to_step(i)))


func _jump_to_step(i: int) -> void:
	if i > 0 and not _validate_identity():
		return
	_step = clampi(i, 0, STEPS.size() - 1)
	_show_step()


# ── Step 1: Attack identity ──────────────────────────────────────────────────

func _build_identity() -> void:
	_content.add_child(_section("What attack are you building?"))
	var id_edit := LineEdit.new()
	id_edit.text = str(_data["id"])
	id_edit.placeholder_text = "id (e.g. fire_slash) — required, no spaces"
	id_edit.text_changed.connect(func(t): _data["id"] = t.strip_edges())
	_content.add_child(_labeled("Attack id", id_edit))
	var name_edit := LineEdit.new()
	name_edit.text = str(_data["name"])
	name_edit.placeholder_text = "display name (optional)"
	name_edit.text_changed.connect(func(t): _data["name"] = t.strip_edges())
	_content.add_child(_labeled("Name", name_edit))
	var type_opt := OptionButton.new()
	for i in ATTACK_TYPES.size():
		type_opt.add_item(str(ATTACK_TYPES[i]).capitalize(), i)
	type_opt.selected = max(0, ATTACK_TYPES.find(str(_data["type"])))
	type_opt.item_selected.connect(func(idx):
		_data["type"] = ATTACK_TYPES[idx]
		_data["hold_behavior"] = "single_press" if ATTACK_TYPES[idx] == "melee" else "full_auto")
	_content.add_child(_labeled("Type", type_opt))
	var cd := _spin(0.0, 600.0, 1.0, float(_data["cooldown_ticks"]))
	cd.value_changed.connect(func(v): _data["cooldown_ticks"] = int(round(v)))
	_content.add_child(_labeled("Cooldown (ticks, 60 = 1s)", cd))
	var hold := OptionButton.new()
	for i in HOLD_BEHAVIORS.size():
		hold.add_item(str(HOLD_BEHAVIORS[i]).capitalize().replace("_", " "), i)
	hold.selected = max(0, HOLD_BEHAVIORS.find(str(_data["hold_behavior"])))
	hold.item_selected.connect(func(idx): _data["hold_behavior"] = HOLD_BEHAVIORS[idx])
	_content.add_child(_labeled("Hold behavior", hold))
	_content.add_child(_hint("Melee attacks use a per-frame hitbox; projectile attacks spawn a projectile you'll define next. 'full auto' fires while held, 'single press' fires once per press."))


# ── Step 2: Hit geometry / projectile ─────────────────────────────────────────

func _build_hit() -> void:
	if str(_data["type"]) == "melee":
		_build_melee()
	else:
		_build_projectile()


func _build_melee() -> void:
	_content.add_child(_section("Melee hit"))
	var dmg := _spin(0.0, 999.0, 1.0, float(_data["damage"]))
	dmg.value_changed.connect(func(v): _data["damage"] = int(round(v)))
	_content.add_child(_labeled("Damage", dmg))
	for spec in [["hitbox_x", "Hitbox X (px, +forward)"], ["hitbox_y", "Hitbox Y (px, -up)"],
			["hitbox_w", "Hitbox width (px)"], ["hitbox_h", "Hitbox height (px)"]]:
		var key := str(spec[0])
		var lo := 1.0 if key in ["hitbox_w", "hitbox_h"] else -200.0
		var sb := _spin(lo, 400.0, 1.0, float(_data[key]))
		sb.value_changed.connect(func(v): _data[key] = int(round(v)))
		_content.add_child(_labeled(str(spec[1]), sb))
	var frames := LineEdit.new()
	frames.text = str(_data["hit_frames"])
	frames.placeholder_text = "e.g. 1,2 — animation frames the hitbox is live"
	frames.text_changed.connect(func(t): _data["hit_frames"] = t)
	_content.add_child(_labeled("Hit frames", frames))
	var combo := OptionButton.new()
	combo.add_item("(none)", 0)
	var combo_ids: Array = []
	for aid in _existing_attack_ids:
		if str(aid) != str(_data["id"]):
			combo_ids.append(str(aid))
	for i in combo_ids.size():
		combo.add_item(str(combo_ids[i]), i + 1)
	var cur := combo_ids.find(str(_data["combo_next_id"]))
	combo.selected = (cur + 1) if cur >= 0 else 0
	combo.item_selected.connect(func(idx): _data["combo_next_id"] = "" if idx == 0 else str(combo_ids[idx - 1]))
	_content.add_child(_labeled("Combo into (next attack)", combo))
	_content.add_child(_hint("Hit frames are the animation frames during which the hitbox deals damage. Combo chains this attack into an existing attack when you press again in time."))


func _build_projectile() -> void:
	var p: Dictionary = _data["proj"]
	_content.add_child(_section("Projectile"))
	var pid := LineEdit.new()
	pid.text = str(p["id"])
	pid.placeholder_text = "projectile id (blank = <attack>_proj)"
	pid.text_changed.connect(func(t): p["id"] = t.strip_edges())
	_content.add_child(_labeled("Projectile id", pid))
	var spd := _spin(0.0, 1200.0, 5.0, float(p["speed"]))
	spd.value_changed.connect(func(v): p["speed"] = int(round(v)))
	_content.add_child(_labeled("Speed (px/s)", spd))
	var dmg := _spin(0.0, 999.0, 1.0, float(p["damage"]))
	dmg.value_changed.connect(func(v): p["damage"] = int(round(v)))
	_content.add_child(_labeled("Damage", dmg))
	var life := _spin(1.0, 1200.0, 5.0, float(p["lifetime_ticks"]))
	life.value_changed.connect(func(v): p["lifetime_ticks"] = int(round(v)))
	_content.add_child(_labeled("Lifetime (ticks)", life))
	var grav := _spin(-600.0, 1200.0, 10.0, float(p["gravity"]))
	grav.value_changed.connect(func(v): p["gravity"] = int(round(v)))
	_content.add_child(_labeled("Gravity (px/s², arc)", grav))
	var pierce := CheckBox.new()
	pierce.button_pressed = bool(p["pierces"])
	pierce.toggled.connect(func(v): p["pierces"] = v)
	_content.add_child(_labeled("Pierces enemies", pierce))
	var home := CheckBox.new()
	home.button_pressed = bool(p["homing"])
	home.toggled.connect(func(v):
		p["homing"] = v
		_show_step())
	_content.add_child(_labeled("Homing", home))
	if bool(p["homing"]):
		var hs := _spin(0.0, 720.0, 5.0, float(p["homing_strength"]))
		hs.value_changed.connect(func(v): p["homing_strength"] = int(round(v)))
		_content.add_child(_labeled("Homing strength", hs))
	var col := ColorPickerButton.new()
	col.color = Color.html(str(p["trail_color"])) if Color.html_is_valid(str(p["trail_color"])) else Color(0.5, 0.8, 1.0)
	col.custom_minimum_size = Vector2(120, 0)
	col.color_changed.connect(func(c): p["trail_color"] = "#" + c.to_html(false))
	_content.add_child(_labeled("Trail color", col))
	var expl := CheckBox.new()
	expl.button_pressed = bool(p["explosive"])
	expl.toggled.connect(func(v):
		p["explosive"] = v
		_show_step())
	_content.add_child(_labeled("Explosive", expl))
	if bool(p["explosive"]):
		var br := _spin(1.0, 400.0, 1.0, float(p["blast_radius"]))
		br.value_changed.connect(func(v): p["blast_radius"] = int(round(v)))
		_content.add_child(_labeled("Blast radius (px)", br))
		var ed := _spin(0.0, 999.0, 1.0, float(p["explosion_damage"]))
		ed.value_changed.connect(func(v): p["explosion_damage"] = int(round(v)))
		_content.add_child(_labeled("Explosion damage", ed))
	_content.add_child(HSeparator.new())
	_content.add_child(_section("Muzzle (spawn offset)"))
	var mx := _spin(-64.0, 64.0, 1.0, float(_data["muzzle_x"]))
	mx.value_changed.connect(func(v): _data["muzzle_x"] = int(round(v)))
	_content.add_child(_labeled("Muzzle X (px, +forward)", mx))
	var my := _spin(-64.0, 64.0, 1.0, float(_data["muzzle_y"]))
	my.value_changed.connect(func(v): _data["muzzle_y"] = int(round(v)))
	_content.add_child(_labeled("Muzzle Y (px, -up)", my))
	_content.add_child(_hint("Art is optional — without a sprite sheet the projectile renders as a trail in the chosen color."))


# ── Step 3: Test & Save ──────────────────────────────────────────────────────

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
	var test_btn := Button.new()
	test_btn.text = "▶  Save & Fire"
	test_btn.pressed.connect(_test_attack)
	_content.add_child(test_btn)
	_content.add_child(_hint("Save & Fire saves, reloads the player's attack defs, selects this attack, then closes and unpauses. Projectile attacks fire on your shoot input; melee attacks play when reached via your combo chain. Re-open with `attacks` to tweak."))


func _summary_text() -> String:
	var lines: Array = []
	var nm := str(_data["name"]).strip_edges()
	lines.append("%s  (%s)" % [nm if not nm.is_empty() else str(_data["id"]), str(_data["type"])])
	lines.append("cooldown %s ticks · %s" % [_data["cooldown_ticks"], str(_data["hold_behavior"])])
	if str(_data["type"]) == "melee":
		lines.append("melee: dmg %s · hitbox %sx%s @ (%s,%s) · frames %s" % [
			_data["damage"], _data["hitbox_w"], _data["hitbox_h"],
			_data["hitbox_x"], _data["hitbox_y"], str(_data["hit_frames"])])
		var combo := str(_data["combo_next_id"]).strip_edges()
		if not combo.is_empty():
			lines.append("combos into: %s" % combo)
	else:
		var p: Dictionary = _data["proj"]
		lines.append("projectile: dmg %s · speed %s · life %s ticks%s%s" % [
			p["damage"], p["speed"], p["lifetime_ticks"],
			" · homing" if bool(p["homing"]) else "",
			" · explosive" if bool(p["explosive"]) else ""])
	return "\n".join(lines)


func _test_attack() -> void:
	if not _save_all():
		return
	var id := str(_data["id"]).strip_edges()
	PlayerInventory.set_active_attack_id(id)
	close_workshop()


# ── Persistence ──────────────────────────────────────────────────────────────

func _save_all() -> bool:
	if not _validate_identity():
		return false
	var pid := _pack_id()
	var id := str(_data["id"]).strip_edges()
	var type := str(_data["type"])

	# Projectile attacks need their projectile def saved FIRST so the attack's
	# projectile_id foreign key resolves during attack validation.
	var projectile_id := ""
	if type == "projectile":
		projectile_id = str((_data["proj"] as Dictionary).get("id", "")).strip_edges()
		if projectile_id.is_empty():
			projectile_id = id + "_proj"
			(_data["proj"] as Dictionary)["id"] = projectile_id
		if not PedIO.save_projectiles(pid, {"projectiles": [_make_projectile(projectile_id)]}):
			_set_status("Saving the projectile failed (see Godot Output).", true)
			return false

	if not PedIO.save_attacks(pid, {"attacks": [_make_attack(id, type, projectile_id)]}):
		_set_status("Saving the attack failed — check the rules in Godot Output.", true)
		return false

	# Drop the player's def cache so the new attack is live without a room reload.
	PlayerInventory.reload_combat_defs()
	if not _existing_attack_ids.has(id):
		_existing_attack_ids.append(id)
	return true


# Build a complete, validator-passing attack def. `player_pose` is intentionally
# omitted (no authored-pose picker yet) so PedIO's pose foreign-key check is
# skipped; charge-release fields are left at their inert defaults.
func _make_attack(id: String, type: String, projectile_id: String) -> Dictionary:
	var nm := str(_data["name"]).strip_edges()
	var is_melee := type == "melee"
	var att := {
		"id": id,
		"name": nm if not nm.is_empty() else id.capitalize(),
		"type": type,
		"projectile_id": projectile_id,
		"cooldown_ticks": int(_data["cooldown_ticks"]),
		"cost_mp": 0,
		"hold_behavior": str(_data["hold_behavior"]),
		"charge_ticks": 0,
		"charged_attack_id": "",
		"combo_next_id": str(_data["combo_next_id"]).strip_edges() if is_melee else "",
		"hit_frames": _parse_hit_frames() if is_melee else [],
		"hitbox_x": int(_data["hitbox_x"]) if is_melee else 0,
		"hitbox_y": int(_data["hitbox_y"]) if is_melee else 0,
		"hitbox_w": maxi(1, int(_data["hitbox_w"])) if is_melee else 0,
		"hitbox_h": maxi(1, int(_data["hitbox_h"])) if is_melee else 0,
		"damage": int(_data["damage"]) if is_melee else 0,
		"knockback": 0,
		"muzzle_x": int(_data["muzzle_x"]),
		"muzzle_y": int(_data["muzzle_y"]),
		"sprite_sheet": "",
		"frame_width": 32,
		"frame_height": 32,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 6,
	}
	return att


func _make_projectile(pid: String) -> Dictionary:
	var p: Dictionary = _data["proj"]
	var nm := str(p.get("name", "")).strip_edges()
	var trail := str(p.get("trail_color", "")).strip_edges()
	if not Color.html_is_valid(trail):
		trail = "#88ccff"
	var proj := {
		"id": pid,
		"name": nm if not nm.is_empty() else pid.capitalize(),
		"sprite_sheet": "",
		"frame_width": 16,
		"frame_height": 8,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 10,
		"speed": int(p["speed"]),
		"gravity": int(p["gravity"]),
		"lifetime_ticks": maxi(1, int(p["lifetime_ticks"])),
		"damage": int(p["damage"]),
		"pierces": bool(p["pierces"]),
		"homing": bool(p["homing"]),
		"homing_strength": int(p["homing_strength"]) if bool(p["homing"]) else 0,
		"hitbox_w": maxi(1, int(p["hitbox_w"])),
		"hitbox_h": maxi(1, int(p["hitbox_h"])),
		"rotate_to_velocity": bool(p["rotate_to_velocity"]),
		"trail_color": trail,
	}
	if bool(p["explosive"]):
		proj["explosive"] = true
		proj["blast_radius"] = maxi(1, int(p["blast_radius"]))
		proj["explosion_damage"] = int(p["explosion_damage"])
		proj["explode_on_hit"] = true
		proj["explode_on_timeout"] = false
	return proj


func _parse_hit_frames() -> Array:
	var out: Array = []
	for tok in str(_data["hit_frames"]).split(",", false):
		var s := str(tok).strip_edges()
		if s.is_valid_int():
			out.append(maxi(0, int(s)))
	if out.is_empty():
		out.append(0)  # melee validation requires at least one hit frame
	return out


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
