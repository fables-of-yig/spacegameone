extends CanvasLayer

# Death screen overlay. Shows "Game Over" with Continue (reload last save)
# and Quit options. Triggered by the player's player_died signal.

const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")

var _panel: Control = null
var _card: PanelContainer = null
var _active: bool = false
var _authored_screen: Control = null
var _authored_pack_id: String = ""

static var _singleton = null


static func instance():
	return _singleton


func _ready() -> void:
	_singleton = self
	layer = 99
	_build_ui()
	visible = false
	_connect_player_death()
	_authored_screen = Control.new()
	_authored_screen.set_script(AuthoredScreenRuntime)
	_authored_screen.visible = false
	add_child(_authored_screen)
	_authored_screen.action_requested.connect(_on_authored_action)


func show_game_over() -> void:
	if _active:
		return
	_active = true
	visible = true
	MvGame.simulation_paused = true
	_reskin()
	_refresh_authored_screen()


func _connect_player_death() -> void:
	get_tree().create_timer(0.5).timeout.connect(_deferred_connect)


func _deferred_connect() -> void:
	var players := get_tree().get_nodes_in_group("mv_player")
	for p in players:
		if p.has_signal("player_died"):
			p.player_died.connect(_on_player_died)


func _on_player_died(_source: String) -> void:
	show_game_over()


func _on_load_last_save() -> void:
	_active = false
	visible = false
	MvGame.simulation_paused = false
	var save_mgr: Node = get_node_or_null("/root/MvSaveManager")
	if save_mgr != null:
		var slot: int = int(save_mgr.call("most_recent_slot"))
		if slot >= 0:
			save_mgr.call("load_game", slot)
			return
	# No save exists yet (e.g. editor playtest, or died before first save):
	# fall back to respawning at the room start so the player isn't stuck.
	_respawn_fallback()


# Used only when no save is available. Restores the player into the current /
# start room without loading from disk.
func _respawn_fallback() -> void:
	if PlanetaryInterface.hosted or PlanetaryInterface.pending_return_to_editor:
		var room_mgr_hosted: Node = MvGame.room_manager
		if room_mgr_hosted != null and room_mgr_hosted.has_method("current_room"):
			var current_info: Dictionary = room_mgr_hosted.call("current_room")
			var current_room: String = str(current_info.get("addr", ""))
			if not current_room.is_empty() and MvGame.main != null and MvGame.main.has_method("load_room_by_addr"):
				MvGame.main.call("load_room_by_addr", current_room)
				return
		if room_mgr_hosted != null and room_mgr_hosted.has_method("load_start_room"):
			room_mgr_hosted.call("load_start_room")
			if MvGame.main != null and MvGame.main.has_method("_spawn_player_in_room"):
				MvGame.main.call("_spawn_player_in_room")
		return
	var room_mgr: Node = MvGame.room_manager
	if room_mgr != null and room_mgr.has_method("load_start_room"):
		room_mgr.call("load_start_room")


func _on_exit_to_menu() -> void:
	_active = false
	visible = false
	MvGame.simulation_paused = false
	if PlanetaryInterface.hosted:
		if PlanetaryInterface.has_method("reset_runtime_state"):
			PlanetaryInterface.reset_runtime_state(true, true)
		MvPackLoader.clear_runtime_state()
		MvGame.main = null
		MvGame.room_manager = null
		GameManager.skip_main_menu = false
		GameManager.auto_test_fly = false
		GameManager.reset_to_new_game()
		DataManager.systems = {}
		DataManager.galaxy_data = {}
		DataManager.galaxy_seed = 0
		get_tree().change_scene_to_file.call_deferred("res://Space/scenes/main.tscn")
		return
	# Standalone / editor playtest: return to the Space main menu rather than
	# quitting the application.
	GameManager.skip_main_menu = false
	get_tree().change_scene_to_file.call_deferred("res://Space/scenes/main.tscn")


# Built from the Claude Design "Game Over" handoff: heavily-dimmed veil + a
# centered armored card with a two-line red defeat title and exactly two
# full-width options — Load Game (cyan primary) / Exit (steel ghost).
func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.draw.connect(_draw_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	_card = PanelContainer.new()
	_card.theme = NebulaTheme.theme()
	_card.add_theme_stylebox_override("panel", NebulaTheme.panel_box())
	_card.custom_minimum_size = Vector2(430, 0)
	center.add_child(_card)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 28)
	_card.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(col)

	# Two-line red "GAME / OVER" defeat title (Robyn Brutalist, embossed).
	var title := Label.new()
	title.text = "GAME\nOVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", NebulaTheme.C_ERROR)
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#5a1410"))
	var tf := NebulaTheme.font()
	if tf != null:
		title.add_theme_font_override("font", tf)
	col.add_child(title)

	# Options ~78% of the body width, stacked.
	var btns_pad := MarginContainer.new()
	btns_pad.add_theme_constant_override("margin_left", 24)
	btns_pad.add_theme_constant_override("margin_right", 24)
	col.add_child(btns_pad)
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns_pad.add_child(btns)

	var load_btn := NebulaUi.button("Load Game", "primary")
	load_btn.custom_minimum_size = Vector2(0, 48)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_on_load_last_save)
	btns.add_child(load_btn)

	var exit_btn := NebulaUi.button("Exit", "ghost")
	exit_btn.custom_minimum_size = Vector2(0, 48)
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_to_menu)
	btns.add_child(exit_btn)

	add_child(_panel)


# Re-apply the scale-aware Nebula theme in case the profile changed since build.
func _reskin() -> void:
	if _card != null:
		_card.theme = NebulaTheme.theme()
		_card.add_theme_stylebox_override("panel", NebulaTheme.panel_box())


func _draw_bg() -> void:
	# Handoff veil: rgba(5,7,11,.72) over the dimmed deep-space snapshot.
	_panel.draw_rect(Rect2(Vector2.ZERO, _panel.size), Color(0.0196, 0.0275, 0.0431, 0.72))


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func _has_authored_screen() -> bool:
	return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
	if _authored_screen == null:
		return
	var pack_id := _current_pack_id()
	if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "game_over"):
		_authored_pack_id = ""
		_authored_screen.call("clear_screen")
		_panel.visible = true
		return
	if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
		_authored_pack_id = pack_id
		var data: Dictionary = UIIo.load_screen(pack_id, "game_over")
		_authored_screen.call("load_screen", "game_over", data, HudDataSource.new(null, null))
	_authored_screen.visible = true
	_panel.visible = false


func _on_authored_action(action_id: String, action_args: String, _element_id: String) -> void:
	_emit_ui_button_event(action_id, action_args, _element_id)
	match action_id:
		"load_slot":
			if action_args.is_valid_int():
				var forced_slot := int(action_args)
				var forced_save_mgr: Node = get_node_or_null("/root/MvSaveManager")
				if forced_save_mgr != null and forced_save_mgr.call("has_save", forced_slot):
					_active = false
					visible = false
					MvGame.simulation_paused = false
					forced_save_mgr.call("load_game", forced_slot)
					return
			_on_load_last_save()
		"load_game":
			if action_args.is_valid_int():
				var slot := int(action_args)
				var save_mgr: Node = get_node_or_null("/root/MvSaveManager")
				if save_mgr != null and save_mgr.call("has_save", slot):
					_active = false
					visible = false
					MvGame.simulation_paused = false
					save_mgr.call("load_game", slot)
					return
			_on_load_last_save()
		"quit_to_menu", "quit_game":
			_on_exit_to_menu()
		"close_screen":
			_on_load_last_save()
		"open_screen":
			if action_args in ["boss_intro", "cinematic"]:
				UiHostActions.open_cinematic(_current_pack_id(), "game_over", action_args)
		"fire_event":
			UiHostActions.fire_authored_event("game_over", "game_over", action_args, _element_id)
		"play_sfx":
			UiHostActions.play_authored_sfx(action_args)
		_:
			UiHostActions.warn_unhandled_action("game_over", action_id)


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
	UiHostActions.emit_ui_button_event("game_over", "game_over", action_id, action_args, element_id)
