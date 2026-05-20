extends CanvasLayer

const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")
const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")

static var _singleton: CanvasLayer = null

var _bars: Control = null
var _authored_screen: Control = null
var _active_pack_id: String = ""
var _active_screen_id: String = "boss_intro"
var _mv_lock_applied: bool = false


static func instance() -> CanvasLayer:
	return _singleton


func _ready() -> void:
	_singleton = self
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_STOP
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

	_authored_screen = Control.new()
	_authored_screen.set_script(AuthoredScreenRuntime)
	_authored_screen.visible = false
	add_child(_authored_screen)
	_authored_screen.action_requested.connect(_on_authored_action)


func open_cinematic(pack_id: String, screen_id: String = "boss_intro") -> void:
	_active_pack_id = pack_id
	_active_screen_id = screen_id
	var resolved_screen_id: String = "boss_intro" if screen_id == "cinematic" else screen_id
	var data: Dictionary = {}
	if not pack_id.is_empty():
		data = UIIo.load_screen(pack_id, resolved_screen_id)
	if data.is_empty():
		data = UIIo.default_stock_screen("boss_intro")
	if data.is_empty():
		return
	visible = true
	_bars.visible = true
	_authored_screen.visible = true
	_authored_screen.call("load_screen", resolved_screen_id, data, HudDataSource.new(null, GameManager))
	_lock_mv_player()
	_bars.queue_redraw()


func close_cinematic() -> void:
	_unlock_mv_player()
	visible = false
	_bars.visible = false
	if _authored_screen != null:
		_authored_screen.call("clear_screen")
		_authored_screen.visible = false


func is_open() -> bool:
	return visible


func _lock_mv_player() -> void:
	if has_node("/root/MvTriggerEngine"):
		MvTriggerEngine.execute_action({"type": "lock_player"}, {})
		_mv_lock_applied = true


func _unlock_mv_player() -> void:
	if _mv_lock_applied and has_node("/root/MvTriggerEngine"):
		MvTriggerEngine.execute_action({"type": "unlock_player"}, {})
	_mv_lock_applied = false


func _draw_bars() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _bars.size)
	UIPanels.draw_dim(_bars, rect, 0.2)
	var bar_h: float = floor(rect.size.y * 0.16)
	_bars.draw_rect(Rect2(0, 0, rect.size.x, bar_h), Color.BLACK)
	_bars.draw_rect(Rect2(0, rect.size.y - bar_h, rect.size.x, bar_h), Color.BLACK)


func _on_authored_action(action_id: String, action_args: String, element_id: String) -> void:
	UiHostActions.emit_ui_button_event("boss_intro", "cinematic_overlay", action_id, action_args, element_id, {
		"pack_id": _active_pack_id,
	})
	match action_id:
		"close_screen", "resume":
			close_cinematic()
		"fire_event":
			UiHostActions.fire_authored_event("boss_intro", "cinematic_overlay", action_args, element_id, {
				"pack_id": _active_pack_id,
			})
		"play_sfx":
			UiHostActions.play_authored_sfx(action_args)
		_:
			UiHostActions.warn_unhandled_action("cinematic_overlay", action_id)
