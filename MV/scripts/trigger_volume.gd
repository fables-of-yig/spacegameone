class_name MvTriggerVolume
extends Area2D

# Invisible zone that fires events when the player enters or exits.
# Properties from the entity editor control size and behavior:
#   width, height — collision box (default 16×16)
#   event_name    — custom event type (default "zone_enter" / "zone_exit")
#   once          — if true, deactivate after first trigger
#   tag, zone_id  — passed in the payload for trigger condition matching

var pack_id: String = ""
var entity_id: String = ""
var instance_id: String = ""
var room_id: String = ""
var tags: Array = []
var properties: Dictionary = {}

var _triggered: bool = false
var _size: Vector2 = Vector2(16, 16)


func configure(p_pack_id: String, p_entity_id: String, p_tags: Array = [], p_props: Dictionary = {}) -> void:
	pack_id = p_pack_id
	entity_id = p_entity_id
	tags = p_tags
	properties = p_props


func _ready() -> void:
	add_to_group("mv_trigger_volume")
	collision_layer = 0
	collision_mask = 0x7fffffff

	var w: float = float(properties.get("width", 16))
	var h: float = float(properties.get("height", 16))
	_size = Vector2(maxf(1.0, w), maxf(1.0, h))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if _triggered and _is_once():
		return
	for player_v in get_tree().get_nodes_in_group("mv_player"):
		var player := player_v as Node2D
		if player != null and _contains_global_point(player.global_position):
			_fire_enter()
			return


func _on_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	_fire_enter()


func _fire_enter() -> void:
	if _triggered and _is_once():
		return
	_triggered = true

	var event_name: String = str(properties.get("event_name", "zone_enter"))
	MvTriggerEngine.fire_event(event_name, _build_payload())


func _on_body_exited(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	if _is_once():
		return
	MvTriggerEngine.fire_event("zone_exit", _build_payload())


func _build_payload() -> Dictionary:
	var payload: Dictionary = {
		"entity_id": entity_id,
		"zone_id": str(properties.get("zone_id", entity_id)),
		"tags": tags,
	}
	payload.merge(properties)
	return payload


func _is_once() -> bool:
	return str(properties.get("once", "false")).to_lower() == "true" \
		or properties.get("once", false) == true


func _is_player_body(body: Node) -> bool:
	return body != null and (body.is_in_group("mv_player") or body.is_in_group("player"))


func _contains_global_point(point: Vector2) -> bool:
	var local := to_local(point)
	return Rect2(_size * -0.5, _size).has_point(local)
