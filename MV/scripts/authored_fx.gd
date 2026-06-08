class_name MvAuthoredFx
extends Node2D

# Data-driven particle burst — the runtime renderer for authored effects (see
# EffIO effect defs, spawned via MvFx). Generalizes MvBulletImpactFx: configurable
# particle count, color cycle, speed/size ranges, lifetime, gravity, drag, spread
# cone, and optional directional bias toward a travel direction. Self-frees when
# its lifetime elapses.
#
# Set up with setup(effect_def, world_pos, direction). Cheap _draw circles, no
# texture dependencies.

var _age: float = 0.0
var _lifetime: float = 0.2
var _gravity: float = 0.0
var _drag: float = 0.85
var _particles: Array = []


func setup(def: Dictionary, world_pos: Vector2, direction: Vector2 = Vector2.ZERO) -> void:
	global_position = world_pos
	_lifetime = maxf(0.02, float(def.get("lifetime", 0.2)))
	_gravity = float(def.get("gravity", 0.0))
	_drag = clampf(float(def.get("drag", 0.85)), 0.0, 1.0)
	var count := maxi(1, int(def.get("count", 8)))
	var spd_min := float(def.get("speed_min", 18.0))
	var spd_max := maxf(spd_min, float(def.get("speed_max", 52.0)))
	var sz_min := float(def.get("size_min", 0.8))
	var sz_max := maxf(sz_min, float(def.get("size_max", 1.8)))
	var spread := clampf(float(def.get("spread", TAU)), 0.0, TAU)
	var directional := bool(def.get("directional", false))
	var colors := _parse_colors(def.get("colors", []))
	var bias := direction.normalized()
	var aim_dir := directional and bias != Vector2.ZERO
	var base_ang := bias.angle() if aim_dir else 0.0
	_particles.clear()
	for i in range(count):
		var ang: float
		if aim_dir:
			ang = base_ang + randf_range(-spread * 0.5, spread * 0.5)
		elif spread >= TAU - 0.001:
			ang = randf() * TAU
		else:
			ang = randf_range(-spread * 0.5, spread * 0.5)
		var dir := Vector2.RIGHT.rotated(ang)
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": dir * randf_range(spd_min, spd_max),
			"radius": randf_range(sz_min, sz_max),
			"color": colors[i % colors.size()],
		})
	queue_redraw()


func _parse_colors(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for c in raw:
			out.append(_to_color(c))
	if out.is_empty():
		out = [Color(1.0, 0.85, 0.4, 1.0)]
	return out


func _to_color(c: Variant) -> Color:
	if c is Color:
		return c
	var s := str(c).strip_edges()
	if s.is_empty():
		return Color(1, 1, 1, 1)
	return Color.html(s)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	for i in range(_particles.size()):
		var p: Dictionary = _particles[i]
		var vel: Vector2 = p.get("vel", Vector2.ZERO)
		vel.y += _gravity * delta
		vel *= _drag
		p["vel"] = vel
		p["pos"] = (p.get("pos", Vector2.ZERO) as Vector2) + vel * delta
		_particles[i] = p
	queue_redraw()


func _draw() -> void:
	var fade := clampf(1.0 - (_age / _lifetime), 0.0, 1.0)
	for p_v in _particles:
		if typeof(p_v) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_v
		var color: Color = p.get("color", Color(1, 1, 1, 1))
		color.a *= fade
		draw_circle(p.get("pos", Vector2.ZERO), float(p.get("radius", 1.2)), color)
