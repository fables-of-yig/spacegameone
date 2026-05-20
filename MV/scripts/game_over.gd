extends CanvasLayer

# Death screen overlay. Shows "Game Over" with Continue (reload last save)
# and Quit options. Triggered by the player's player_died signal.

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")

var _panel: Control = null
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


func _on_continue() -> void:
	_active = false
	visible = false
	MvGame.simulation_paused = false
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
	var save_mgr: Node = get_node_or_null("/root/MvSaveManager")
	if save_mgr != null:
		for i in 3:
			if save_mgr.call("has_save", i):
				save_mgr.call("load_game", i)
				return
	var room_mgr: Node = MvGame.room_manager
	if room_mgr != null and room_mgr.has_method("load_start_room"):
		room_mgr.call("load_start_room")


func _on_quit() -> void:
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
	get_tree().quit()


func _build_ui() -> void:
	_panel = Control.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.draw.connect(_draw_bg)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.4
	vbox.offset_left = -80
	vbox.offset_right = 80
	vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UIPanels.text_color("error"))
	vbox.add_child(title)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.pressed.connect(_on_continue)
	vbox.add_child(continue_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	_panel.add_child(vbox)
	add_child(_panel)


func _draw_bg() -> void:
	UIPanels.draw_dim(_panel, Rect2(Vector2.ZERO, _panel.size))


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
			_on_continue()
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
			_on_continue()
		"quit_to_menu", "quit_game":
			_on_quit()
		"close_screen":
			_on_continue()
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
