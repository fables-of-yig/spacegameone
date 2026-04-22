extends CanvasLayer

# In-game HUD overlay. Shows player HP bar, energy/ammo, weapon indicator,
# and an optional boss HP bar. Updated every frame from the player node
# and PlayerInventory.

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")
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
var _boss_bar: Control = null
var _boss_label: Label = null

var boss_hp: int = 0
var boss_max_hp: int = 0
var show_boss_bar: bool = false
var _using_custom_screen: bool = false


func _ready() -> void:
	layer = 90
	_try_custom_screen()
	if not _using_custom_screen:
		_build_hp_bar()
		_build_weapon_label()
		_build_boss_bar()


func _try_custom_screen() -> void:
	var pack_id := ""
	if MvPackLoader.current_pack != null:
		pack_id = MvPackLoader.current_pack.pack_id
	if pack_id.is_empty():
		return
	if not UIIo.screen_exists(pack_id, "hud"):
		return
	var data := UIIo.load_screen(pack_id, "hud")
	if data.is_empty():
		return
	var renderer := Control.new()
	renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	renderer.set_script(AuthoredScreenRuntime)
	renderer.call("load_screen", "hud", data, HudDataSource.new(_find_player(), GameManager))
	add_child(renderer)
	_using_custom_screen = true


func _process(_delta: float) -> void:
	if _using_custom_screen:
		return
	_update_hp()
	_update_weapon()
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


# ── Boss HP bar ─────────────────────────────────────────────────────────

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
	var players := get_tree().get_nodes_in_group("mv_player")
	if players.is_empty():
		return null
	return players[0]
