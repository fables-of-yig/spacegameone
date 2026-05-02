extends CanvasLayer

# In-game HUD overlay. Shows player HP bar, energy/ammo, weapon indicator,
# and an optional boss HP bar. Updated every frame from the player node
# and PlayerInventory.

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")
const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")
const AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
const BAR_WIDTH: int = 80
const BAR_HEIGHT: int = 8
const MARGIN: int = 8
const HP_COLOR: Color = Color(0.2, 0.85, 0.3)
const HP_BG: Color = Color(0.15, 0.15, 0.2, 0.8)
const BOSS_COLOR: Color = Color(0.9, 0.25, 0.2)
const BOSS_BG: Color = Color(0.15, 0.15, 0.2, 0.8)

var _hp_bar: Control = null
var _hp_label: Label = null
var _weapon_label: Label = null
var _resource_label: Label = null
var _quest_label: Label = null
var _boss_bar: Control = null
var _boss_label: Label = null

var boss_hp: int = 0
var boss_max_hp: int = 0
var show_boss_bar: bool = false
var _using_custom_screen: bool = false


func _ready() -> void:
	layer = 90
	name = "MvHud"
	add_to_group("mv_hud")
	visible = false
	_try_custom_screen()
	if not _using_custom_screen:
		_build_hp_bar()
		_build_weapon_label()
		_build_resource_label()
		_build_quest_label()
		_build_boss_bar()


func _try_custom_screen() -> void:
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
	_update_hp()
	_update_weapon()
	_update_resources()
	_update_quest()
	_update_boss()


# ── HP bar ──────────────────────────────────────────────────────────────

func _build_hp_bar() -> void:
	_hp_bar = Control.new()
	_hp_bar.position = Vector2(MARGIN, MARGIN)
	_hp_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_hp_bar.draw.connect(_draw_hp_bar)
	add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.position = Vector2(MARGIN, MARGIN + BAR_HEIGHT + 2)
	_hp_label.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	_hp_label.add_theme_color_override("font_color", UIPanels.text_color("body"))
	add_child(_hp_label)


func _draw_hp_bar() -> void:
	var player := _find_player()
	if player == null:
		return
	var ratio: float = clampf(float(player.hp) / float(maxi(player.max_hp, 1)), 0.0, 1.0)
	_hp_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_WIDTH, BAR_HEIGHT)), HP_BG)
	_hp_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_WIDTH * ratio, BAR_HEIGHT)), HP_COLOR)


func _update_hp() -> void:
	var player := _find_player()
	if player == null:
		return
	_hp_label.text = "%d / %d" % [player.hp, player.max_hp]
	_hp_bar.queue_redraw()


# ── Weapon indicator ────────────────────────────────────────────────────

func _build_weapon_label() -> void:
	_weapon_label = Label.new()
	_weapon_label.position = Vector2(MARGIN, MARGIN + BAR_HEIGHT + 18)
	_weapon_label.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	_weapon_label.add_theme_color_override("font_color", UIPanels.text_color("button"))
	add_child(_weapon_label)


func _update_weapon() -> void:
	if PlayerInventory.has_method("get_active_attack_id") and PlayerInventory.has_method("get_attack_definition"):
		var attack_id := str(PlayerInventory.get_active_attack_id())
		if not attack_id.is_empty():
			var attack_def: Dictionary = PlayerInventory.get_attack_definition(attack_id)
			var attack_name := str(attack_def.get("name", "")).strip_edges()
			if not attack_name.is_empty():
				_weapon_label.text = attack_name.to_upper()
				return
	var w := PlayerInventory.get_active_weapon_type()
	match w:
		PlayerInventory.WeaponType.GRENADE_LAUNCHER:
			_weapon_label.text = "GRENADE"
		_:
			_weapon_label.text = "BEAM"


func _build_resource_label() -> void:
	_resource_label = Label.new()
	_resource_label.position = Vector2(MARGIN, MARGIN + BAR_HEIGHT + 36)
	_resource_label.add_theme_font_size_override("font_size", UIPanels.font_size("hint_size"))
	_resource_label.add_theme_color_override("font_color", UIPanels.text_color("body"))
	add_child(_resource_label)


func _update_resources() -> void:
	if _resource_label == null:
		return
	var gold := int(PlayerInventory.get_var("gold", 0))
	var ammo := int(PlayerInventory.get_var("ammo_missile", 0))
	var max_ammo := int(PlayerInventory.get_var("max_ammo_missile", 0))
	var player := _find_player()
	var missile_mode := ""
	if player != null and player.has_method("is_secondary_mode_active") and bool(player.call("is_secondary_mode_active")):
		missile_mode = " ON"
	_resource_label.text = "GOLD %d   MISSILES%s %d / %d" % [gold, missile_mode, ammo, max_ammo]


# ── Boss HP bar ─────────────────────────────────────────────────────────

func _build_quest_label() -> void:
	_quest_label = Label.new()
	_quest_label.position = Vector2(MARGIN, MARGIN + BAR_HEIGHT + 54)
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
	_boss_bar.position = Vector2(-BAR_WIDTH * 0.5, MARGIN)
	_boss_bar.size = Vector2(BAR_WIDTH * 2, BAR_HEIGHT + 2)
	_boss_bar.draw.connect(_draw_boss_bar)
	_boss_bar.visible = false
	add_child(_boss_bar)

	_boss_label = Label.new()
	_boss_label.anchor_left = 0.5
	_boss_label.anchor_right = 0.5
	_boss_label.position = Vector2(-BAR_WIDTH * 0.5, MARGIN + BAR_HEIGHT + 4)
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
