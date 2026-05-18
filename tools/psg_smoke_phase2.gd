extends SceneTree

# Phase 2 smoke check for the planet shader generator.
# Verifies:
#   1. write_strip_png composes frames into a single horizontal PNG
#   2. sidecar JSON round-trips through write_sidecar / read_sidecar
#   3. colors_to_json / colors_from_json round-trips
#   4. sidecar_path_for returns the expected .planetgen.json sibling
#   5. (live) preview.bake_strip_frames returns N frames for one body
# Run: godot --headless --script res://tools/psg_smoke_phase2.gd

const PsgIO = preload("res://Space/scripts/editor/psg/psg_io.gd")
const PsgPreview = preload("res://Space/scripts/editor/psg/psg_preview.gd")

const TEST_DIR: String = "user://psg_smoke_test"
const STRIP_FRAMES: int = 8
const FRAME_W: int = 32
const FRAME_H: int = 32


func _init() -> void:
	var failures: Array = []

	# 1. sidecar_path_for
	var sp: String = PsgIO.sidecar_path_for("res://foo/bar/baz.png")
	if sp != "res://foo/bar/baz.planetgen.json":
		failures.append("sidecar_path_for: got '%s'" % sp)

	# 2. strip PNG composition
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var frames: Array = []
	for i in STRIP_FRAMES:
		var img := Image.create(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
		var c := Color(float(i) / float(STRIP_FRAMES), 0.5, 1.0 - float(i) / float(STRIP_FRAMES), 1.0)
		img.fill(c)
		frames.append(img)
	var strip_path: String = TEST_DIR + "/strip.png"
	if not PsgIO.write_strip_png(frames, strip_path):
		failures.append("write_strip_png returned false")
	var loaded := Image.load_from_file(strip_path)
	if loaded == null:
		failures.append("strip.png: load failed")
	elif loaded.get_width() != FRAME_W * STRIP_FRAMES:
		failures.append("strip.png: width %d != expected %d" % [loaded.get_width(), FRAME_W * STRIP_FRAMES])
	elif loaded.get_height() != FRAME_H:
		failures.append("strip.png: height %d != expected %d" % [loaded.get_height(), FRAME_H])

	# 3. sidecar JSON round-trip
	var sidecar_path: String = TEST_DIR + "/strip.planetgen.json"
	var original_data: Dictionary = {
		"type": "GasPlanet",
		"seed": 4242,
		"params": {
			"size": 9.5,
			"OCTAVES": 5,
			"time_speed": 0.42,
			"light_angle": 137.0,
		},
		"colors": [[0.9, 0.2, 0.3, 1.0], [0.1, 0.8, 0.5, 1.0]],
		"anim": {"frames": STRIP_FRAMES, "fps": 12.0},
	}
	if not PsgIO.write_sidecar(sidecar_path, original_data):
		failures.append("write_sidecar returned false")
	var read_back: Dictionary = PsgIO.read_sidecar(sidecar_path)
	if read_back.is_empty():
		failures.append("read_sidecar returned empty")
	else:
		if int(read_back.get("seed", -1)) != 4242:
			failures.append("sidecar: seed mismatch")
		if not read_back.has("version"):
			failures.append("sidecar: missing version field after write")
		var params_v: Variant = read_back.get("params", null)
		if typeof(params_v) != TYPE_DICTIONARY \
				or abs(float((params_v as Dictionary).get("size", 0)) - 9.5) > 0.001:
			failures.append("sidecar: params.size mismatch")

	# 4. colors JSON round-trip
	var pca := PackedColorArray()
	pca.append(Color(0.1, 0.2, 0.3, 0.4))
	pca.append(Color(1.0, 0.5, 0.25, 0.75))
	var as_json: Array = PsgIO.colors_to_json(pca)
	if as_json.size() != 2:
		failures.append("colors_to_json: size %d != 2" % as_json.size())
	var pca2 := PsgIO.colors_from_json(as_json)
	if pca2.size() != 2:
		failures.append("colors_from_json: size %d != 2" % pca2.size())
	elif abs(pca2[0].r - 0.1) > 0.001 or abs(pca2[1].a - 0.75) > 0.001:
		failures.append("colors round-trip: value drift")

	# Live bake intentionally skipped here — RenderingServer.frame_post_draw
	# never fires in --headless mode, so bake_strip_frames() would hang
	# indefinitely. Visual verification happens in a windowed editor
	# session: open a planet POI, click Generate, hit Bake & Apply, then
	# check that <pack>/Systems/AstralBodies/{Pois,Stars}/ contains a
	# horizontal-strip PNG + matching .planetgen.json sidecar.

	# Cleanup
	var d := DirAccess.open(ProjectSettings.globalize_path(TEST_DIR))
	if d != null:
		d.remove("strip.png")
		d.remove("strip.planetgen.json")

	if failures.is_empty():
		print("\nPSG SMOKE PHASE 2: PASS")
		quit(0)
	else:
		print("\nPSG SMOKE PHASE 2: FAIL")
		for f in failures:
			print("  ", f)
		quit(1)
