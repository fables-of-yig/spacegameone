@tool
extends ActionLeaf

# Bursts horizontal velocity for a short window. Returns RUNNING for
# the duration, SUCCESS on the tick the dash completes, FAILURE while
# the subsequent cooldown is active. Dashes in beh_facing direction by
# default; override with params.dir (+1 / -1).
#
# params:
#   speed:    peak dash speed px/s. Default 200.
#   duration: seconds to sustain velocity. Default 0.25.
#   cooldown: seconds between dashes. Default 1.5.
#   dir:      optional fixed direction. Default: read from beh_facing.

var _dash_until: float = 0.0
var _next_ok_at: float = 0.0
var _dash_dir: float = 1.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    var params := _params()
    var speed: float = float(params.get("speed", 200.0))
    if now < _dash_until:
        (actor as CharacterBody2D).velocity.x = _dash_dir * speed
        if actor.has_method("ai_request_pose"):
            actor.call("ai_request_pose", "move", 0.1, true, 1.3)
        return RUNNING
    if _dash_until > 0.0 and now < _next_ok_at:
        # Just ended this tick.
        if abs(now - _dash_until) < 0.05:
            _dash_until = 0.0
            return SUCCESS
        return FAILURE
    _dash_dir = float(params.get("dir", 0.0))
    if _dash_dir == 0.0 and "beh_facing" in actor:
        _dash_dir = float(actor.beh_facing)
    if _dash_dir == 0.0:
        _dash_dir = 1.0
    (actor as CharacterBody2D).velocity.x = _dash_dir * speed
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", _dash_dir)
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "move", float(params.get("duration", 0.25)), true, 1.3)
    _dash_until = now + float(params.get("duration", 0.25))
    _next_ok_at = _dash_until + float(params.get("cooldown", 1.5))
    return RUNNING


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
