extends CanvasLayer

# In-game HUD overlay. Shows player HP bar, energy/ammo, weapon indicator,
# and an optional boss HP bar. Updated every frame from the player node
# and PlayerInventory.

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo = preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
const ToastDataSource = preload("res://Space/scripts/ui/toast_data_source.gd")
const BAR_WIDTH: int = 80
const BAR_HEIGHT: int = 8
const MARGIN: int = 8
const HP_COLOR: Color = Color(0.2, 0.85, 0.3)
const HP_BG: Color = Color(0.15, 0.15, 0.2, 0.8)
const BOSS_COLOR: Color = Color(0.9, 0.25, 0.2)
const BOSS_BG: Color = Color(0.15, 0.15, 0.2, 0.8)

var _top_hud: Control = null
var _spell_ids: Array = []   # attack ids per spell slot, parallel to the bar
var _quest_label: Label = null
var _boss_bar: Control = null
var _boss_label: Label = null

# Minimap room grid, recomputed (BFS over room doors) only when the current
# room changes — not every frame.
var _map_cells: Array = []
var _map_cols: int = 0
var _map_rows: int = 0
var _map_room: String = ""

var boss_hp: int = 0
var boss_max_hp: int = 0
var show_boss_bar: bool = false
var _using_custom_screen: bool = false

# Toast stack — top-right vertical column populated by show_toast(). Newest
# toast lands on top, fades in over 0.2s, holds for `duration`, fades out
# over 0.5s, then queue_free's itself. Authored pack template (B-2) takes
# precedence over the default Panel+Label card built here.
var _toast_stack: VBoxContainer = null
const TOAST_WIDTH: int = 240
const TOAST_FADE_IN: float = 0.2
const TOAST_FADE_OUT: float = 0.5
const TOAST_DEFAULT_DURATION: float = 2.5


func _ready() -> void:
	layer = 90
	name = "MvHud"
	add_to_group("mv_hud")
	visible = false
	_build_hud()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed"):
		sm.settings_changed.connect(_on_settings_changed)


func _build_hud() -> void:
	_try_custom_screen()
	if not _using_custom_screen:
		_build_top_hud()
		_build_quest_label()
		_build_boss_bar()


# Tears down and rebuilds the HUD, switching between the canonical Nebula HUD and
# the pack's authored HUD screen. Called when the "Use authored pack UI" setting
# is toggled at runtime.
func _rebuild_hud() -> void:
	for c in get_children():
		c.queue_free()
	_top_hud = null
	_quest_label = null
	_boss_bar = null
	_boss_label = null
	_toast_stack = null
	_using_custom_screen = false
	_build_hud()


func _on_settings_changed(section: String, key: String) -> void:
	if section == "gameplay" and key == "authored_ui_path":
		_rebuild_hud()
	elif section == "" and key == "":
		# Restore Defaults fired a blanket reset.
		_rebuild_hud()


# Whether the loaded pack's authored HUD screen should override the canonical
# Nebula tank-gauge HUD. Driven by the "Use authored pack UI" setting (off by
# default). When off, the Nebula HUD is canonical and UIIo's auto-provisioned
# stock hud_mv is ignored.
func _authored_ui_enabled() -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return false
	return bool(sm.get_setting("gameplay", "authored_ui_path", false))


func _try_custom_screen() -> void:
	if not _authored_ui_enabled():
		return
	if _using_custom_screen or not _mv_runtime_available():
		return
	var pack_id := ""
	if MvPackLoader.current_pack != null:
		pack_id = MvPackLoader.current_pack.pack_id
	if pack_id.is_empty():
		return
	var screen_id := ""
	if UIIo.screen_exists(pack_id, "hud_mv"):
		screen_id = "hud_mv"
	elif UIIo.screen_exists(pack_id, "hud"):
		screen_id = "hud"
	if screen_id.is_empty():
		return
	var data := UIIo.load_screen(pack_id, screen_id)
	if data.is_empty():
		return
	var source := HudDataSource.new(_find_player(), GameManager)
	if not _custom_screen_sources_ready(source, screen_id):
		return
	var renderer := Control.new()
	renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	renderer.set_script(AuthoredScreenRuntime)
	renderer.call("load_screen", screen_id, data, source)
	add_child(renderer)
	_using_custom_screen = true


func _process(_delta: float) -> void:
	visible = _mv_runtime_available()
	if not visible:
		return
	if not _using_custom_screen:
		_try_custom_screen()
	if _using_custom_screen:
		return
	if _top_hud != null:
		_top_hud.queue_redraw()
	_update_quest()
	_update_boss()


# ── Nebula top HUD (HP + Energy tanks · Spells · Minimap) ─────────────────
# Ported 1:1 from the Claude Design Game-HUD handoff. Drawn in immediate mode
# via NebulaHud from a full-rect child Control; data is live player state.

func _build_top_hud() -> void:
	_top_hud = Control.new()
	_top_hud.name = "NebulaTopHud"
	_top_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_hud.draw.connect(_draw_top_hud)
	add_child(_top_hud)


func _draw_top_hud() -> void:
	var player := _find_player()
	if player == null:
		return
	var ci: CanvasItem = _top_hud
	# LEFT — HP (red, danger purple) + Energy (cyan) tank gauges.
	var hp_size := NebulaHud.draw_tank_gauge(ci, Vector2(16, 14), {
		"label": "HP", "value": int(player.hp), "max": int(player.max_hp),
		"total": maxi(1, int(ceil(float(player.max_hp) / 100.0))),
		"tone": "energy", "danger_tone": "crystal", "danger_at": 0.2,
		"per_row": 7, "size": 30.0, "low_at": 2.0, "glyph": "hp", "icon_tex": NebulaHud.icon("hp"),
	})
	NebulaHud.draw_tank_gauge(ci, Vector2(16 + hp_size.x + 22.0, 14), {
		"label": "Energy", "value": int(player.energy), "max": int(player.max_energy),
		"total": maxi(1, int(ceil(float(player.max_energy) / 100.0))),
		"tone": "magic", "per_row": 5, "size": 30.0, "low_at": 1.0, "glyph": "bolt", "icon_tex": NebulaHud.icon("lightning"),
	})
	# CENTER — spell bar (real abilities; active one selected).
	NebulaHud.draw_ability_bar(ci, _top_hud.size.x * 0.5, 18.0, "Spells", _gather_spells(), 54.0, true)
	# RIGHT — room minimap.
	_ensure_minimap()
	if not _map_cells.is_empty():
		NebulaHud.draw_minimap(ci, Vector2(_top_hud.size.x - 16.0, 14.0), _map_cells,
			_map_cols, _map_rows, 28.0, "Map", "", 5, 4)


# Real ability slots: primary ranged, melee, secondary (with ammo). The active
# attack is shown selected. No fake cooldown animation — cd is 0 (ready) unless
# a real timer exists.
func _gather_spells() -> Array:
	var slots: Array = []
	_spell_ids = []
	if not PlayerInventory.has_method("get_active_attack_id"):
		return slots
	var active := str(PlayerInventory.get_active_attack_id())
	var ranged := str(PlayerInventory.get_ranged_attack_id()) if PlayerInventory.has_method("get_ranged_attack_id") else ""
	var melee := str(PlayerInventory.get_melee_attack_id()) if PlayerInventory.has_method("get_melee_attack_id") else ""
	var secondary := str(PlayerInventory.get_secondary_attack_id()) if PlayerInventory.has_method("get_secondary_attack_id") else ""
	var seen: Dictionary = {}
	var idx := 1
	for entry in [[ranged, "lightning"], [melee, "fire"], [secondary, "fire"]]:
		var aid := str(entry[0])
		if aid.is_empty() or seen.has(aid):
			continue
		seen[aid] = true
		var def: Dictionary = PlayerInventory.get_attack_definition(aid)
		var ability_name := str(def.get("name", aid))
		var slot := {
			"key": str(idx),
			"tex": NebulaHud.icon(_attack_icon(aid, ability_name, str(entry[1]))),
			"glow": NebulaHud.C_ACCENT,
			"cd": 0.0,
			"selected": aid == active,
		}
		if aid == secondary and PlayerInventory.has_method("get_secondary_ammo_key"):
			var akey := str(PlayerInventory.get_secondary_ammo_key())
			if not akey.is_empty():
				var amax := int(PlayerInventory.get_var("max_%s" % akey, 0))
				if amax > 0:
					slot["ammo"] = int(PlayerInventory.get_var(akey, 0))
					slot["ammo_max"] = amax
		slots.append(slot)
		_spell_ids.append(aid)
		idx += 1
	return slots


# Number keys 1..N select the matching spell slot (sets the active attack so the
# bar highlights it and the primary fire uses it when it's a ranged attack).
func _input(event: InputEvent) -> void:
	if _using_custom_screen or _top_hud == null or not _mv_runtime_available():
		return
	if MvGame.simulation_paused:  # console / edit mode open
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var idx := -1
	match k.keycode:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
		KEY_4: idx = 3
	if idx < 0 or idx >= _spell_ids.size():
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return
	var aid := str(_spell_ids[idx])
	if aid != "" and PlayerInventory.has_method("set_active_attack_id"):
		PlayerInventory.set_active_attack_id(aid)
		_top_hud.queue_redraw()
		get_viewport().set_input_as_handled()


# Maps an attack to a HUD icon by keyword, falling back to a per-slot default.
func _attack_icon(attack_id: String, ability_name: String, fallback: String) -> String:
	var s := (attack_id + " " + ability_name).to_lower()
	if s.findn("frost") >= 0 or s.findn("ice") >= 0 or s.findn("cryo") >= 0 or s.findn("crystal") >= 0:
		return "crystal"
	if s.findn("fire") >= 0 or s.findn("flame") >= 0 or s.findn("burn") >= 0:
		return "fire"
	if s.findn("shield") >= 0 or s.findn("aegis") >= 0 or s.findn("guard") >= 0:
		return "shield"
	if s.findn("magnet") >= 0 or s.findn("pull") >= 0 or s.findn("grapple") >= 0:
		return "magnet"
	if s.findn("missile") >= 0 or s.findn("rocket") >= 0 or s.findn("grenade") >= 0:
		return "fire"
	if s.findn("beam") >= 0 or s.findn("laser") >= 0 or s.findn("energy") >= 0 or s.findn("shot") >= 0:
		return "lightning"
	return fallback


# Recomputes the minimap room grid (BFS over room doors from the current room),
# only when the current room changes.
func _ensure_minimap() -> void:
	var rm: Node = MvGame.room_manager
	if rm == null or not rm.has_method("rooms") or not rm.has_method("current_room"):
		_map_cells = []
		return
	var cur := str(rm.current_room().get("addr", ""))
	if cur == _map_room and not _map_cells.is_empty():
		return
	_map_room = cur
	var all_rooms: Dictionary = rm.rooms()
	if all_rooms.is_empty() or cur.is_empty():
		_map_cells = []
		return
	var grid: Dictionary = { cur: Vector2i.ZERO }
	var queue: Array = [cur]
	while not queue.is_empty():
		var addr: String = queue.pop_front()
		var info: Dictionary = all_rooms.get(addr, {})
		var base: Vector2i = grid[addr]
		var w := maxi(int(info.get("width_screens", 1)), 1)
		var h := maxi(int(info.get("height_screens", 1)), 1)
		for door in info.get("doors", []):
			var target := str(door.get("target", ""))
			if target.is_empty() or grid.has(target) or not all_rooms.has(target):
				continue
			var tinfo: Dictionary = all_rooms.get(target, {})
			var tw := maxi(int(tinfo.get("width_screens", 1)), 1)
			var th := maxi(int(tinfo.get("height_screens", 1)), 1)
			var off := Vector2i.ZERO
			match str(door.get("direction", "")):
				"right": off = Vector2i(w, 0)
				"left": off = Vector2i(-tw, 0)
				"down": off = Vector2i(0, h)
				"up": off = Vector2i(0, -th)
			grid[target] = base + off
			queue.append(target)
	var vis: Dictionary = {}
	if MvMapScreen != null and MvMapScreen.has_method("visited_snapshot"):
		vis = MvMapScreen.visited_snapshot()
	var min_c := 0
	var min_r := 0
	var max_c := 1
	var max_r := 1
	var first := true
	for addr in grid:
		var p: Vector2i = grid[addr]
		var info: Dictionary = all_rooms.get(addr, {})
		var w := maxi(int(info.get("width_screens", 1)), 1)
		var h := maxi(int(info.get("height_screens", 1)), 1)
		if first:
			min_c = p.x ; min_r = p.y ; max_c = p.x + w ; max_r = p.y + h ; first = false
		else:
			min_c = mini(min_c, p.x) ; min_r = mini(min_r, p.y)
			max_c = maxi(max_c, p.x + w) ; max_r = maxi(max_r, p.y + h)
	var cells: Array = []
	for addr in grid:
		var p: Vector2i = grid[addr]
		var info: Dictionary = all_rooms.get(addr, {})
		var st := "unx"
		if addr == cur:
			st = "cur"
		elif vis.has(addr):
			st = "exp"
		cells.append({
			"col": p.x - min_c, "row": p.y - min_r,
			"w": maxi(int(info.get("width_screens", 1)), 1),
			"h": maxi(int(info.get("height_screens", 1)), 1),
			"state": st,
		})
	_map_cells = cells
	_map_cols = maxi(1, max_c - min_c)
	_map_rows = maxi(1, max_r - min_r)


# ── Boss HP bar ─────────────────────────────────────────────────────────

func _build_quest_label() -> void:
	_quest_label = Label.new()
	# Below the Nebula top-HUD tank gauges (two pip rows).
	_quest_label.position = Vector2(16, 128)
	_quest_label.custom_minimum_size = Vector2(260, 36)
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_label.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	_quest_label.add_theme_color_override("font_color", UIPanels.text_color("body"))
	add_child(_quest_label)


func _update_quest() -> void:
	if _quest_label == null:
		return
	var text := _active_quest_text()
	_quest_label.text = text
	_quest_label.visible = not text.is_empty()


func _active_quest_text() -> String:
	var engine := get_tree().root.get_node_or_null("MvTriggerEngine")
	if engine == null or not engine.has_method("get_quest_state"):
		return ""
	var states_v: Variant = engine.get_quest_state()
	if typeof(states_v) != TYPE_DICTIONARY:
		return ""
	var defs := _quest_definitions_by_id()
	for quest_id_v in (states_v as Dictionary).keys():
		var quest_id := str(quest_id_v).strip_edges()
		var state_v: Variant = (states_v as Dictionary).get(quest_id, {})
		if quest_id.is_empty() or typeof(state_v) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_v
		if str(state.get("status", "")) != "active":
			continue
		var quest_def: Dictionary = defs.get(quest_id, {})
		var title := str(quest_def.get("title", quest_id)).strip_edges()
		var stage_id := str(state.get("stage_id", "")).strip_edges()
		var stage := _quest_stage_def(quest_def, stage_id)
		var stage_title := str(stage.get("title", stage_id)).strip_edges()
		return "%s\n%s" % [title, stage_title] if not stage_title.is_empty() else title
	return ""


func _quest_definitions_by_id() -> Dictionary:
	var pack_id := ""
	if MvPackLoader.current_pack != null:
		pack_id = str(MvPackLoader.current_pack.pack_id).strip_edges()
	if pack_id.is_empty():
		return {}
	var quests_v: Variant = QuestIO.load_or_init(pack_id).get("quests", [])
	if typeof(quests_v) != TYPE_ARRAY:
		return {}
	var out: Dictionary = {}
	for quest_v in quests_v:
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		var quest_id := str(quest.get("id", "")).strip_edges()
		if not quest_id.is_empty():
			out[quest_id] = quest
	return out


func _quest_stage_def(quest_def: Dictionary, stage_id: String) -> Dictionary:
	var stages_v: Variant = quest_def.get("stages", [])
	if typeof(stages_v) != TYPE_ARRAY:
		return {}
	for stage_v in stages_v:
		if typeof(stage_v) != TYPE_DICTIONARY:
			continue
		var stage: Dictionary = stage_v
		if str(stage.get("id", "")).strip_edges() == stage_id:
			return stage
	return {}


func _build_boss_bar() -> void:
	_boss_bar = Control.new()
	_boss_bar.anchor_left = 0.5
	_boss_bar.anchor_right = 0.5
	# Below the centered spell bar.
	_boss_bar.position = Vector2(-BAR_WIDTH * 0.5, 124)
	_boss_bar.size = Vector2(BAR_WIDTH * 2, BAR_HEIGHT + 2)
	_boss_bar.draw.connect(_draw_boss_bar)
	_boss_bar.visible = false
	add_child(_boss_bar)

	_boss_label = Label.new()
	_boss_label.anchor_left = 0.5
	_boss_label.anchor_right = 0.5
	_boss_label.position = Vector2(-BAR_WIDTH * 0.5, 124 + BAR_HEIGHT + 4)
	_boss_label.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	_boss_label.add_theme_color_override("font_color", UIPanels.text_color("error"))
	_boss_label.visible = false
	add_child(_boss_label)


func _draw_boss_bar() -> void:
	if boss_max_hp <= 0:
		return
	var w: float = BAR_WIDTH * 2.0
	var ratio := clampf(float(boss_hp) / float(boss_max_hp), 0.0, 1.0)
	_boss_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(w, BAR_HEIGHT)), BOSS_BG)
	_boss_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(w * ratio, BAR_HEIGHT)), BOSS_COLOR)


func _update_boss() -> void:
	_boss_bar.visible = show_boss_bar
	_boss_label.visible = show_boss_bar
	if show_boss_bar:
		_boss_label.text = "%d / %d" % [boss_hp, boss_max_hp]
		_boss_bar.queue_redraw()


func set_boss(current: int, maximum: int) -> void:
	boss_hp = current
	boss_max_hp = maximum
	show_boss_bar = maximum > 0


func hide_boss() -> void:
	show_boss_bar = false
	boss_hp = 0
	boss_max_hp = 0


# ── Toast notifications ─────────────────────────────────────────────────

# Spawn a transient notification card in the top-right toast stack.
# message: the text to display.
# duration: hold time in seconds before fade-out (defaults to 2.5).
# style: one of "info" (default), "success", "warning", "error" — picks
#        background + accent border on the default card. Ignored if the
#        pack provides an authored "toast" screen (B-2).
func show_toast(message: String, duration: float = TOAST_DEFAULT_DURATION, style: String = "info") -> void:
	var trimmed := message.strip_edges()
	if trimmed.is_empty():
		return
	_ensure_toast_stack()
	var dur: float = duration if duration > 0.0 else TOAST_DEFAULT_DURATION
	var style_id: String = style.strip_edges()
	if style_id.is_empty():
		style_id = "info"
	var card: Control = _build_authored_toast(trimmed, style_id, dur)
	if card == null:
		card = _build_default_toast(trimmed, style_id)
	_attach_toast(card, dur)


func _ensure_toast_stack() -> void:
	if _toast_stack != null and is_instance_valid(_toast_stack):
		return
	_toast_stack = VBoxContainer.new()
	_toast_stack.name = "ToastStack"
	_toast_stack.anchor_left = 1.0
	_toast_stack.anchor_right = 1.0
	_toast_stack.anchor_top = 0.0
	_toast_stack.anchor_bottom = 0.0
	_toast_stack.offset_left = -TOAST_WIDTH - 8.0
	_toast_stack.offset_right = -8.0
	_toast_stack.offset_top = 8.0
	_toast_stack.offset_bottom = 8.0
	_toast_stack.add_theme_constant_override("separation", 4)
	_toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_stack)


func _build_default_toast(message: String, style: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(TOAST_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = _toast_bg_color(style)
	stylebox.border_color = _toast_border_color(style)
	stylebox.border_width_left = 3
	stylebox.corner_radius_top_left = 3
	stylebox.corner_radius_top_right = 3
	stylebox.corner_radius_bottom_left = 3
	stylebox.corner_radius_bottom_right = 3
	stylebox.content_margin_left = 10
	stylebox.content_margin_right = 8
	stylebox.content_margin_top = 6
	stylebox.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", stylebox)
	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	lbl.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lbl)
	return card


func _toast_bg_color(style: String) -> Color:
	match style:
		"warning":
			return Color(0.35, 0.25, 0.05, 0.92)
		"success":
			return Color(0.05, 0.32, 0.10, 0.92)
		"error":
			return Color(0.42, 0.06, 0.06, 0.92)
		_:
			return Color(0.08, 0.10, 0.18, 0.92)


func _toast_border_color(style: String) -> Color:
	match style:
		"warning":
			return Color(0.95, 0.78, 0.20)
		"success":
			return Color(0.30, 0.85, 0.40)
		"error":
			return Color(0.95, 0.32, 0.25)
		_:
			return Color(0.45, 0.65, 0.95)


# Returns an AuthoredScreenRuntime hosting the pack's authored "toast"
# screen, or null when the pack has not authored one. The runtime is
# constructed per-toast so each card has its own data source frozen
# around the message at fire time — switching messages on a live toast
# is intentionally not supported.
func _build_authored_toast(message: String, style: String, _duration: float) -> Control:
	var pack_id := ""
	if MvPackLoader.current_pack != null:
		pack_id = str(MvPackLoader.current_pack.pack_id).strip_edges()
	if pack_id.is_empty():
		return null
	if not UIIo.screen_exists(pack_id, "toast"):
		return null
	var data := UIIo.load_screen(pack_id, "toast")
	if data.is_empty():
		return null
	var source := ToastDataSource.new(message, style, _find_player(), GameManager)
	var renderer := Control.new()
	renderer.custom_minimum_size = Vector2(TOAST_WIDTH, 0)
	renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	renderer.set_script(AuthoredScreenRuntime)
	renderer.call("load_screen", "toast", data, source)
	return renderer


func _attach_toast(card: Control, duration: float) -> void:
	_toast_stack.add_child(card)
	_toast_stack.move_child(card, 0)
	card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, TOAST_FADE_IN)
	tween.tween_interval(maxf(duration, 0.2))
	tween.tween_property(card, "modulate:a", 0.0, TOAST_FADE_OUT)
	tween.tween_callback(Callable(card, "queue_free"))


# ── Utility ─────────────────────────────────────────────────────────────

func _find_player() -> Node:
	if MvGame.main != null and is_instance_valid(MvGame.main):
		var main_player: Variant = MvGame.main.get("_player")
		if main_player is Node and is_instance_valid(main_player):
			return main_player
	var players := get_tree().get_nodes_in_group("mv_player")
	if players.is_empty():
		return null
	return players[0]


func _custom_screen_sources_ready(source: RefCounted, screen_id: String) -> bool:
	if screen_id != "hud_mv":
		return true
	for binding in ["player.hp", "player.max_hp", "room.name"]:
		if source.call("resolve", binding) == null:
			return false
	return true


func _mv_runtime_available() -> bool:
	return MvGame.main != null
