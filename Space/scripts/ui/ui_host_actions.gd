class_name UiHostActions
extends RefCounted


const CinematicOverlay := preload("res://Space/scripts/ui/cinematic_overlay.gd")


static func emit_ui_button_event(screen_id: String, host_id: String,
		action_id: String, action_args: String, element_id: String,
		extra_payload: Dictionary = {}) -> void:
	var payload: Dictionary = {
		"screen_id": screen_id,
		"element_id": element_id,
		"action_id": action_id,
		"action_args": action_args,
		"host": host_id,
	}
	for key_v in extra_payload.keys():
		payload[key_v] = extra_payload[key_v]
	MvTriggerEngine.fire_event("ui_button", payload)


static func fire_authored_event(screen_id: String, host_id: String,
		event_name: String, element_id: String,
		extra_payload: Dictionary = {}) -> bool:
	var trimmed := event_name.strip_edges()
	if trimmed.is_empty():
		push_warning("%s: fire_event requires action_args = event name" % host_id)
		return false
	var payload: Dictionary = {
		"screen_id": screen_id,
		"element_id": element_id,
		"host": host_id,
	}
	for key_v in extra_payload.keys():
		payload[key_v] = extra_payload[key_v]
	MvTriggerEngine.fire_event(trimmed, payload)
	return true


static func play_authored_sfx(sfx_name: String) -> void:
	var trimmed := sfx_name.strip_edges()
	if trimmed.is_empty():
		return
	AudioManager.play_sfx(trimmed)


static func open_cinematic(pack_id: String, host_id: String, target: String) -> bool:
	var trimmed := target.strip_edges()
	if trimmed.is_empty():
		return false
	if not UiContract.host_supports_open_target(host_id, trimmed):
		return false
	var overlay := CinematicOverlay.instance()
	if overlay != null:
		overlay.open_cinematic(pack_id, trimmed)
		return true
	push_warning("%s: cinematic overlay host is not available" % host_id)
	return true


static func warn_unhandled_action(host_id: String, action_id: String, action_args: String = "") -> void:
	if action_args.is_empty():
		push_warning("%s: unhandled authored action '%s'" % [host_id, action_id])
		return
	push_warning("%s: unhandled authored action '%s' (%s)" % [host_id, action_id, action_args])
