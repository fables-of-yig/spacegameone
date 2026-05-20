class_name MvInteractable
extends StaticBody2D

signal scripted_move_finished
signal scripted_animation_finished(anim_name: String)

# NPC or sign the player can interact with. The player scans for the
# nearest body in the "mv_interactable" group and calls interact() when
# the interact action is pressed. interact() fires an "interact" event
# through MvTriggerEngine with the entity's tags and properties, and if
# the entity has a "dialogue_id" property it also starts that dialogue
# directly — so the simplest NPC-authoring path (entity + dialogue file)
# works without needing a separate trigger rule.

const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")

const PLACEHOLDER_SIZE: Vector2 = Vector2(14, 24)
const INTERACT_RADIUS: float = 24.0

var pack_id: String = ""
var entity_id: String = ""
var instance_id: String = ""
var tags: Array = []
var properties: Dictionary = {}

var _entity: Dictionary = {}
var _col_shape: CollisionShape2D = null
var _interact_area: Area2D = null
var _sprite: Sprite2D = null
var _player_inside: bool = false
var _prompt_label: Label = null
var _sprite_set_rel: String = ""
var _available_pose_pngs: Array = []
var _pose_registry: Dictionary = {}
var _pose_data: Dictionary = {}
var _frame_count: int = 1
var _frame_index: int = 0
var _frame_time: float = 0.0
var _anim_fps: float = 8.0
var _script_move_active: bool = false
var _script_move_target: Vector2 = Vector2.ZERO
var _script_move_speed: float = 64.0
var _script_anim_active: bool = false
var _script_anim_speed_scale: float = 1.0
var _script_anim_loop: bool = true
var _script_anim_name: String = ""
var _facing_right: bool = true


func configure(p_pack_id: String, p_entity_id: String, p_tags: Array = [], p_props: Dictionary = {}) -> void:
	pack_id = p_pack_id
	entity_id = p_entity_id
	tags = p_tags
	properties = p_props


func _ready() -> void:
	add_to_group("mv_interactable")
	if pack_id == "":
		pack_id = _current_pack_id()
	_entity = _load_entity()
	_ensure_collision()
	_ensure_interact_area()
	_mount_sprite()
	_create_prompt()
	queue_redraw()


func _draw() -> void:
	if _sprite != null:
		return
	var half := PLACEHOLDER_SIZE / 2.0
	draw_rect(Rect2(-half, PLACEHOLDER_SIZE), Color(0.3, 0.7, 0.9, 0.8))


func _process(delta: float) -> void:
	if not _script_move_active:
		pass
	else:
		position = position.move_toward(_script_move_target, _script_move_speed * delta)
		if _sprite != null:
			_facing_right = _script_move_target.x >= position.x
			_sprite.flip_h = not _facing_right
		if position.distance_to(_script_move_target) <= 0.5:
			position = _script_move_target
			_script_move_active = false
			scripted_move_finished.emit()
	if _sprite == null or _frame_count <= 1:
		return
	var frame_dur := 1.0 / maxf(0.01, _anim_fps * _script_anim_speed_scale)
	_frame_time += delta
	while _frame_time >= frame_dur:
		_frame_time -= frame_dur
		_frame_index += 1
		if _frame_index >= _frame_count:
			var loop_from := int(_pose_data.get("loop_from", 0))
			if _script_anim_loop:
				_frame_index = clampi(loop_from, 0, _frame_count - 1)
			else:
				var finished_anim := _script_anim_name
				_frame_index = _frame_count - 1
				_frame_time = 0.0
				_script_anim_active = false
				_script_anim_name = ""
				scripted_animation_finished.emit(finished_anim)
				break
		_sprite.frame = _frame_index


# Public entry point called by the player when interact is pressed
# inside the player's interact zone. Fires the trigger event first so
# custom rules run, then auto-starts dialogue if the entity authored a
# dialogue_id property.
func interact() -> void:
	var payload: Dictionary = {
		"entity_id": entity_id,
		"entity_type": _entity.get("id", entity_id),
		"tags": tags,
	}
	payload.merge(properties)
	MvTriggerEngine.fire_event("interact", payload)

	var dialogue_id := str(properties.get("dialogue_id", ""))
	if dialogue_id.is_empty():
		dialogue_id = str(_entity.get("dialogue_id", ""))
	if not dialogue_id.is_empty():
		MvDialogueRunner.start(dialogue_id)


func _ensure_collision() -> void:
	_col_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = PLACEHOLDER_SIZE
	_col_shape.shape = rect
	add_child(_col_shape)


func _ensure_interact_area() -> void:
	_interact_area = Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = INTERACT_RADIUS
	shape.shape = circle
	_interact_area.add_child(shape)
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 0x7fffffff
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	add_child(_interact_area)


func _on_body_entered(body: Node2D) -> void:
	if _is_player_body(body):
		_player_inside = true
		if _prompt_label != null:
			_prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if _is_player_body(body):
		_player_inside = false
		if _prompt_label != null:
			_prompt_label.visible = false


func _create_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.text = "Interact"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(-30, -PLACEHOLDER_SIZE.y - 8)
	_prompt_label.size = Vector2(60, 16)
	_prompt_label.visible = false
	_prompt_label.add_theme_font_size_override("font_size", 8)
	add_child(_prompt_label)


func _mount_sprite() -> void:
	_sprite_set_rel = str(_entity.get("sprite_set", ""))
	if _sprite_set_rel.is_empty():
		return
	_available_pose_pngs = EntIO.list_sprite_pngs(pack_id, _sprite_set_rel)
	if _available_pose_pngs.is_empty():
		return
	var poses_doc := EntIO.load_poses(pack_id, _sprite_set_rel)
	var poses_v: Variant = poses_doc.get("poses", {})
	if typeof(poses_v) == TYPE_DICTIONARY:
		_pose_registry = poses_v
	_apply_pose_texture(str(_available_pose_pngs[0]))
	queue_redraw()


func begin_scripted_move(target_pos: Vector2, speed: float = 64.0) -> void:
	_script_move_target = target_pos
	_script_move_speed = maxf(1.0, speed)
	_script_move_active = true


func set_scripted_facing(dir: float) -> void:
	if dir == 0.0:
		return
	_facing_right = dir > 0.0
	if _sprite != null:
		_sprite.flip_h = not _facing_right


func play_scripted_animation(anim_name: String, loop: bool = true, speed_scale: float = 1.0) -> void:
	var png_name := _resolve_pose_png(anim_name)
	if png_name.is_empty():
		return
	_script_anim_active = true
	_script_anim_loop = loop
	_script_anim_speed_scale = maxf(0.05, speed_scale)
	_script_anim_name = anim_name.strip_edges()
	_apply_pose_texture(png_name)


func stop_scripted_animation() -> void:
	_script_anim_active = false
	_script_anim_speed_scale = 1.0
	_script_anim_name = ""


func is_scripted_move_active() -> bool:
	return _script_move_active


func is_scripted_animation_active() -> bool:
	return _script_anim_active


func current_scripted_animation_name() -> String:
	return _script_anim_name


func _resolve_pose_png(anim_name: String) -> String:
	var trimmed := anim_name.strip_edges().to_lower()
	if trimmed.is_empty():
		return ""
	for png_v in _available_pose_pngs:
		var png_name := str(png_v)
		var stem := png_name.get_basename().to_lower()
		if stem == trimmed or stem.ends_with("_" + trimmed):
			return png_name
	for png_v in _available_pose_pngs:
		var png_name := str(png_v)
		if png_name.get_basename().to_lower().contains(trimmed):
			return png_name
	return ""


func _apply_pose_texture(png_name: String) -> void:
	if _sprite_set_rel.is_empty() or png_name.is_empty():
		return
	var tex := EntIO.load_sprite_png(pack_id, _sprite_set_rel, png_name)
	if tex == null:
		return
	_pose_data = {}
	if _pose_registry.has(png_name):
		var pose_v: Variant = _pose_registry[png_name]
		if typeof(pose_v) == TYPE_DICTIONARY:
			_pose_data = pose_v
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)
	_sprite.texture = tex
	var fc := EntIO.autodetect_frame_count(tex)
	_frame_count = fc if fc > 1 else 1
	_frame_index = 0
	_frame_time = 0.0
	_anim_fps = float(_pose_data.get("fps", 8.0))
	_sprite.hframes = _frame_count
	_sprite.frame = 0


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


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func _is_player_body(body: Node) -> bool:
	return body != null and (body.is_in_group("mv_player") or body.is_in_group("player"))
