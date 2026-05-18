extends RefCounted

# Type registry, file paths, and PNG/sidecar I/O for the planet shader
# generator (psg). Each entry in TYPE_ORDER maps a body type id (matching
# the upstream PixelPlanets folder name) to a label and the .tscn path
# to instantiate.
#
# Bake output is a horizontal strip PNG (anim_frames * viewport_res
# wide). The same stem owns a `<stem>.planetgen.json` sidecar that
# preserves shader params, colors, and seed so the body can be reopened
# in the panel and tweaked without redoing all the authoring work.

const VENDOR_ROOT: String = "res://Space/vendor/pixel_planets/"
const SIDECAR_EXT: String = ".planetgen.json"
const SIDECAR_VERSION: int = 1

# Display order in the picker UI. Lead with the bodies most likely to be
# authored as planet/star POIs; place the exotic ones (galaxy, black
# hole) at the end.
const TYPE_ORDER: Array = [
	"Star",
	"GasPlanet",
	"GasPlanetLayers",
	"DryTerran",
	"LandMasses",
	"Rivers",
	"IceWorld",
	"LavaWorld",
	"NoAtmosphere",
	"Asteroids",
	"BlackHole",
	"Galaxy",
]

const TYPE_LABELS: Dictionary = {
	"Star": "Star",
	"GasPlanet": "Gas Giant",
	"GasPlanetLayers": "Gas Giant (Ringed)",
	"DryTerran": "Dry Terran",
	"LandMasses": "Continents",
	"Rivers": "Rivers (Terran)",
	"IceWorld": "Ice World",
	"LavaWorld": "Lava World",
	"NoAtmosphere": "Airless Rock",
	"Asteroids": "Asteroid Field",
	"BlackHole": "Black Hole",
	"Galaxy": "Galaxy",
}

# Upstream has one folder-name-vs-scene-name mismatch: the `Asteroids/`
# folder contains `Asteroid.tscn` (singular). All other body types use
# their folder name verbatim as the scene name.
const SCENE_NAME_OVERRIDES: Dictionary = {
	"Asteroids": "Asteroid",
}


static func type_label(type_id: String) -> String:
	return str(TYPE_LABELS.get(type_id, type_id))


static func scene_path_for(type_id: String) -> String:
	if not TYPE_LABELS.has(type_id):
		return ""
	var scene_name: String = str(SCENE_NAME_OVERRIDES.get(type_id, type_id))
	return "%s%s/%s.tscn" % [VENDOR_ROOT, type_id, scene_name]


static func is_known_type(type_id: String) -> bool:
	return TYPE_LABELS.has(type_id)


static func sidecar_path_for(sprite_path: String) -> String:
	var s: String = sprite_path.strip_edges()
	if s.is_empty():
		return ""
	var stem: String = s.get_basename()
	return stem + SIDECAR_EXT


# Writes the N captured frames as a horizontal strip PNG to dest_path.
# All frames must share the same size; the strip width is N * frame_w
# and height is frame_h. The destination directory must already exist.
static func write_strip_png(frames: Array, dest_path: String) -> bool:
	if frames.is_empty():
		push_warning("psg_io.write_strip_png: no frames")
		return false
	var first: Image = frames[0]
	if first == null:
		push_warning("psg_io.write_strip_png: first frame is null")
		return false
	var frame_w: int = first.get_width()
	var frame_h: int = first.get_height()
	if frame_w <= 0 or frame_h <= 0:
		push_warning("psg_io.write_strip_png: invalid frame size %dx%d" % [frame_w, frame_h])
		return false
	var strip := Image.create(frame_w * frames.size(), frame_h, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var f: Image = frames[i]
		if f == null:
			push_warning("psg_io.write_strip_png: frame %d is null" % i)
			return false
		if f.get_width() != frame_w or f.get_height() != frame_h:
			push_warning("psg_io.write_strip_png: frame %d size mismatch" % i)
			return false
		if f.get_format() != Image.FORMAT_RGBA8:
			f.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(f, Rect2i(0, 0, frame_w, frame_h),
			Vector2i(i * frame_w, 0))
	var err: int = strip.save_png(dest_path)
	if err != OK:
		push_warning("psg_io.write_strip_png: save_png failed with err %d for '%s'" % [err, dest_path])
		return false
	return true


static func write_sidecar(sidecar_path: String, data: Dictionary) -> bool:
	if sidecar_path.is_empty():
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["version"] = SIDECAR_VERSION
	var file := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if file == null:
		push_warning("psg_io.write_sidecar: open failed for '%s'" % sidecar_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func read_sidecar(sidecar_path: String) -> Dictionary:
	if sidecar_path.is_empty() or not FileAccess.file_exists(sidecar_path):
		return {}
	var file := FileAccess.open(sidecar_path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


# Serialise an Array of Color into a JSON-friendly Array of [r,g,b,a]
# float arrays. The shader uniforms take PackedColorArray; this round-
# trips through `colors_from_json` below.
static func colors_to_json(colors: Variant) -> Array:
	var out: Array = []
	if typeof(colors) == TYPE_PACKED_COLOR_ARRAY:
		var pca: PackedColorArray = colors
		for c in pca:
			out.append([c.r, c.g, c.b, c.a])
		return out
	if typeof(colors) == TYPE_ARRAY:
		var arr: Array = colors
		for c_v in arr:
			if c_v is Color:
				var c: Color = c_v
				out.append([c.r, c.g, c.b, c.a])
	return out


static func colors_from_json(json_colors: Variant) -> PackedColorArray:
	var out := PackedColorArray()
	if typeof(json_colors) != TYPE_ARRAY:
		return out
	for entry_v in (json_colors as Array):
		if typeof(entry_v) != TYPE_ARRAY:
			continue
		var entry: Array = entry_v
		if entry.size() < 3:
			continue
		var r: float = float(entry[0])
		var g: float = float(entry[1])
		var b: float = float(entry[2])
		var a: float = float(entry[3]) if entry.size() >= 4 else 1.0
		out.append(Color(r, g, b, a))
	return out


static func ensure_dir(dir_path: String) -> void:
	if dir_path.is_empty():
		return
	var global_path: String = ProjectSettings.globalize_path(dir_path)
	if not global_path.is_empty():
		DirAccess.make_dir_recursive_absolute(global_path)
