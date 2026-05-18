extends SceneTree

# Phase 1 smoke check for the planet shader generator.
# Verifies:
#   - psg_io / psg_preview / psg_panel parse and load
#   - every body type in PsgIO.TYPE_ORDER resolves to a real .tscn
#   - every body type instantiates cleanly via psg_preview
#   - psg_panel instantiates and can open with a valid type/seed
# Run: godot --headless --script res://tools/psg_smoke.gd

const PsgIO = preload("res://Space/scripts/editor/psg/psg_io.gd")
const PsgPreview = preload("res://Space/scripts/editor/psg/psg_preview.gd")
const PsgPanel = preload("res://Space/scripts/editor/psg/psg_panel.gd")


func _init() -> void:
	var failures: Array = []

	for type_id_v in PsgIO.TYPE_ORDER:
		var type_id: String = str(type_id_v)
		var scene_path: String = PsgIO.scene_path_for(type_id)
		if scene_path.is_empty():
			failures.append("%s: scene_path_for returned empty" % type_id)
			continue
		var packed: PackedScene = load(scene_path)
		if packed == null:
			failures.append("%s: load('%s') returned null" % [type_id, scene_path])
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			failures.append("%s: instantiate() returned null" % type_id)
			continue
		var label: String = PsgIO.type_label(type_id)
		print("OK  %-20s  -> %s" % [type_id, label])
		inst.free()

	var preview: Control = Control.new()
	preview.set_script(PsgPreview)
	root.add_child(preview)
	for type_id_v in PsgIO.TYPE_ORDER:
		var type_id: String = str(type_id_v)
		if not preview.set_body_type(type_id):
			failures.append("preview.set_body_type('%s') returned false" % type_id)
		preview.set_seed(int(hash(type_id)) % 10000)
	preview.queue_free()

	var panel: Control = Control.new()
	panel.set_script(PsgPanel)
	root.add_child(panel)
	panel.size = Vector2(1280, 720)
	panel.open("GasPlanet", 4242)
	if not panel.visible:
		failures.append("panel.open() did not set visible=true")
	panel.close()
	if panel.visible:
		failures.append("panel.close() did not set visible=false")
	panel.queue_free()

	if failures.is_empty():
		print("\nPSG SMOKE: PASS  (%d body types, preview + panel both instantiate)" % PsgIO.TYPE_ORDER.size())
		quit(0)
	else:
		print("\nPSG SMOKE: FAIL")
		for f in failures:
			print("  ", f)
		quit(1)
