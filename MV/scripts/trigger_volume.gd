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


func configure(p_pack_id: String, p_entity_id: String, p_tags: Array = [], p_props: Dictionary = {}) -> void:
	pack_id = p_pack_id
	entity_id = p_entity_id
	tags = p_tags
	properties = p_props


func _ready() -> void:
	add_to_group("mv_trigger_volume")
	collision_layer = 0
	collision_mask = 1

	var w: float = float(properties.get("width", 16))
	var h: float = float(properties.get("height", 16))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _triggered and _is_once():
		return
	_triggered = true

	var event_name: String = str(properties.get("event_name", "zone_enter"))
	MvTriggerEngine.fire_event(event_name, _build_payload())


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
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
