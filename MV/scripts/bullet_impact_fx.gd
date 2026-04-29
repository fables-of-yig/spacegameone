class_name MvBulletImpactFx
extends Node2D

const DEFAULT_LIFETIME: float = 0.12

var _age: float = 0.0
var _lifetime: float = DEFAULT_LIFETIME
var _particles: Array = []


func setup(world_pos: Vector2, normal: Vector2 = Vector2.ZERO, count: int = 5) -> void:
	global_position = world_pos
	_lifetime = DEFAULT_LIFETIME
	_particles.clear()
	var bias := normal.normalized()
	for i in range(maxi(1, count)):
		var spread := randf_range(-1.15, 1.15)
		var dir := Vector2.RIGHT.rotated(spread)
		if bias != Vector2.ZERO:
			dir = bias.lerp(dir, 0.55).normalized()
		else:
			dir = Vector2.RIGHT.rotated(randf() * TAU)
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": dir * randf_range(18.0, 52.0),
			"radius": randf_range(0.8, 1.7),
			"color": Color(1.0, 0.92, 0.5, 1.0) if i % 2 == 0 else Color(1.0, 0.58, 0.18, 1.0),
		})
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	for i in range(_particles.size()):
		var particle: Dictionary = _particles[i]
		particle["pos"] = (particle.get("pos", Vector2.ZERO) as Vector2) + (particle.get("vel", Vector2.ZERO) as Vector2) * delta
		particle["vel"] = (particle.get("vel", Vector2.ZERO) as Vector2) * 0.82
		_particles[i] = particle
	queue_redraw()


func _draw() -> void:
	var fade := clampf(1.0 - (_age / _lifetime), 0.0, 1.0)
	for particle_v in _particles:
		if typeof(particle_v) != TYPE_DICTIONARY:
			continue
		var particle: Dictionary = particle_v
		var color: Color = particle.get("color", Color(1.0, 0.8, 0.3, 1.0))
		color.a *= fade
		draw_circle(particle.get("pos", Vector2.ZERO), float(particle.get("radius", 1.2)), color)
