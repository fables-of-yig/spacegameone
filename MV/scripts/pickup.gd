class_name MvPickup
extends Area2D

# Touch-collectable item. Fires a "pickup" event through MvTriggerEngine
# and marks itself as collected in MvRoomState so it stays gone on revisit.

const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")

const PLACEHOLDER_SIZE: Vector2 = Vector2(12, 12)

var pack_id: String = ""
var entity_id: String = ""
var instance_id: String = ""
var room_id: String = ""
var tags: Array = []
var properties: Dictionary = {}

var _entity: Dictionary = {}
var _sprite: Sprite2D = null


func configure(p_pack_id: String, p_entity_id: String, p_tags: Array = [], p_props: Dictionary = {}) -> void:
	pack_id = p_pack_id
	entity_id = p_entity_id
	tags = p_tags
	properties = p_props


func _ready() -> void:
	add_to_group("mv_pickup")
	if pack_id == "":
		pack_id = _current_pack_id()
	_entity = _load_entity()

	if not instance_id.is_empty() and not room_id.is_empty():
		if MvRoomState.is_collected(room_id, instance_id):
			queue_free()
			return

	collision_layer = 0
	collision_mask = 0x7fffffff
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = PLACEHOLDER_SIZE
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)
	_mount_sprite()
	queue_redraw()


func _draw() -> void:
	if _sprite != null:
		return
	var half := PLACEHOLDER_SIZE / 2.0
	var rect := Rect2(-half, PLACEHOLDER_SIZE)
	draw_rect(rect, _placeholder_color())
	draw_rect(rect, Color(0.05, 0.05, 0.07, 0.9), false, 1.0)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if _is_player_body(body):
			_collect()
			return
	for player_v in get_tree().get_nodes_in_group("mv_player"):
		var player := player_v as Node2D
		if player != null and player.global_position.distance_to(global_position) <= 24.0:
			_collect()
			return


func _on_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	_collect()


func _collect() -> void:
	if not instance_id.is_empty() and not room_id.is_empty():
		MvRoomState.mark_collected(room_id, instance_id)

	var item_id: String = str(properties.get("item_id", ""))
	var payload: Dictionary = {
		"entity_id": entity_id,
		"item_id": item_id,
		"tags": tags,
	}
	payload.merge(properties)
	MvTriggerEngine.fire_event("pickup", payload)

	if not item_id.is_empty():
		PlayerInventory.add_item(item_id, int(properties.get("count", 1)))

	queue_free()


func _mount_sprite() -> void:
	var sprite_set: String = str(_entity.get("sprite_set", ""))
	if sprite_set.is_empty():
		return
	var pngs := EntIO.list_sprite_pngs(pack_id, sprite_set)
	if pngs.is_empty():
		return
	var tex := EntIO.load_sprite_png(pack_id, sprite_set, pngs[0])
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	var fc := EntIO.autodetect_frame_count(tex)
	if fc > 1:
		_sprite.hframes = fc
	add_child(_sprite)
	queue_redraw()


func _load_entity() -> Dictionary:
	var data := EntIO.load_or_init(pack_id)
	var list_v: Variant = data.get("entities", [])
	if typeof(list_v) != TYPE_ARRAY:
		return {}
	for row_v in list_v:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		if str(row_v.get("id", "")) == entity_id:
			return row_v
	return {}


func _placeholder_color() -> Color:
	var item_id := str(properties.get("item_id", "")).strip_edges()
	if item_id.is_empty():
		return Color(1.0, 0.85, 0.3, 0.9)
	var def := PlayerInventory.get_item_definition(item_id)
	match str(def.get("use_effect", "")).strip_edges():
		"heal_hp":
			return Color(0.25, 0.95, 0.35, 0.9)
		"add_ammo":
			return Color(0.3, 0.7, 1.0, 0.9)
		"max_hp_up":
			return Color(1.0, 0.25, 0.35, 0.9)
		"max_ammo_up":
			return Color(0.55, 0.5, 1.0, 0.9)
	return Color(1.0, 0.85, 0.3, 0.9)


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func _is_player_body(body: Node) -> bool:
	return body != null and (body.is_in_group("mv_player") or body.is_in_group("player"))
