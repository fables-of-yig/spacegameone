extends RefCounted

# Resolves bindings for an authored "toast" screen template — adds
# toast.message and toast.style on top of the standard HUD bindings so
# the authored toast layout can mix the toast text with regular player /
# game manager state (e.g. show the player's HP next to the message).
#
# Constructed per-toast by MvHud._build_authored_toast(); lives only as
# long as the toast Control is on-screen.

const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")

var message: String = ""
var style: String = "info"
var player: Node = null
var game_manager: Node = null

var _delegate: RefCounted = null


func _init(msg: String = "", st: String = "info", player_ref: Node = null, gm_ref: Node = null) -> void:
	message = msg
	style = st if not st.is_empty() else "info"
	player = player_ref
	game_manager = gm_ref
	_delegate = HudDataSource.new(player_ref, gm_ref)


func resolve(binding: String) -> Variant:
	match binding:
		"toast.message":
			return message
		"toast.style":
			return style
		_:
			return _delegate.resolve(binding)


func has_binding(binding: String) -> bool:
	if binding == "toast.message" or binding == "toast.style":
		return true
	return _delegate.has_binding(binding)


func has_resolved_binding(binding: String) -> bool:
	if binding == "toast.message" or binding == "toast.style":
		return resolve(binding) != null
	return _delegate.has_resolved_binding(binding)


func resolve_ratio(binding: String) -> float:
	return _delegate.resolve_ratio(binding)


func resolve_bar(current_bind: String, max_bind: String) -> float:
	return _delegate.resolve_bar(current_bind, max_bind)
