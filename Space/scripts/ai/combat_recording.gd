class_name CombatRecording
extends RefCounted
## Stores a sequence of (state, action) snapshots from combat.
## Used by CombatRecorder to write and ClonedAI to read.

# --- State indices ---
const S_DIST          = 0   # distance to target
const S_REL_X         = 1   # target pos in ship-local frame X
const S_REL_Y         = 2   # target pos in ship-local frame Y
const S_REL_VX        = 3   # relative velocity local X
const S_REL_VY        = 4   # relative velocity local Y
const S_MY_SPEED      = 5   # own speed
const S_HP            = 6   # own health ratio 0-1
const S_SHIELD        = 7   # own shield ratio 0-1
const S_TARGET_HP     = 8   # target health ratio 0-1
const S_TARGET_SHIELD = 9   # target shield ratio 0-1
const S_CAN_PRIMARY   = 10  # bool as 0/1
const S_CAN_SECONDARY = 11
const S_CAN_SPECIAL   = 12
const S_BOOST_READY   = 13
const S_HARPOON       = 14  # harpoon state enum int
const STATE_SIZE      = 15

# --- Action indices ---
const A_THRUST        = 0   # -0.5 to 1.0
const A_TURN          = 1   # -1.0 to 1.0
const A_AIM_LOCAL     = 2   # aim angle relative to ship rotation
const A_FIRE_PRIMARY  = 3   # bool
const A_FIRE_SECONDARY= 4
const A_FIRE_SPECIAL  = 5
const A_FIRE_HARPOON  = 6
const A_BOOST         = 7
const A_HANDBRAKE     = 8
const A_PARRY         = 9   # shield supercharger / parry activation
const ACTION_SIZE     = 10

# --- Weights for k-NN distance ---
const STATE_WEIGHTS: Array[float] = [
	1.0,    # dist
	2.0,    # rel_x  (most important)
	2.0,    # rel_y
	0.5,    # rel_vx
	0.5,    # rel_vy
	0.3,    # my_speed
	0.2,    # hp
	0.2,    # shield
	0.3,    # target_hp
	0.2,    # target_shield
	0.0,    # can_primary  (don't match on cooldowns)
	0.0,    # can_secondary
	0.0,    # can_special
	0.0,    # boost_ready
	0.0,    # harpoon
]

var recording_name: String = ""
var template_name: String = ""
var ship_config: Dictionary = {}
var frames: Array = []  # Array of {s: Array, a: Array}

# --- Tuning metadata (editable in AI Design panel) ---
var quality_threshold: float = 0.0   # min quality for k-NN consideration (0 = use all)
var aggression_bias: float = 1.0     # multiplier on quality bonus in k-NN (higher = prefer hit frames more)

# Bucketed index: dist_bucket -> array of frame indices
var _buckets: Dictionary = {}
const BUCKET_SIZE: float = 200.0

func add_frame(state: Array, action: Array, quality: float = 0.0):
	var idx = frames.size()
	frames.append({s = state, a = action, q = quality})
	var bucket = int(state[S_DIST] / BUCKET_SIZE)
	if not _buckets.has(bucket):
		_buckets[bucket] = []
	_buckets[bucket].append(idx)

func boost_recent_frames(count: int, amount: float = 1.0):
	var start = maxi(frames.size() - count, 0)
	for i in range(start, frames.size()):
		frames[i].q = maxf(frames[i].q, amount)

func get_frame_count() -> int:
	return frames.size()

func get_nearby_buckets(dist: float) -> Array:
	var b = int(dist / BUCKET_SIZE)
	var result: Array = []
	for offset in [-1, 0, 1]:
		var key = b + offset
		if _buckets.has(key):
			result.append_array(_buckets[key])
	return result

func snapshot() -> CombatRecording:
	var copy = CombatRecording.new()
	copy.recording_name = recording_name
	copy.template_name = template_name
	copy.quality_threshold = quality_threshold
	copy.aggression_bias = aggression_bias
	copy.ship_config = ship_config.duplicate()
	for f in frames:
		copy.add_frame(f.s.duplicate(), f.a.duplicate(), f.q)
	return copy

func get_stats() -> Dictionary:
	var total = frames.size()
	var quality_count: int = 0
	var total_dist: float = 0.0
	var fire_count: int = 0
	var min_dist: float = INF
	var max_dist: float = 0.0
	for f in frames:
		if f.q > 0.0:
			quality_count += 1
		if f.s.size() > S_DIST:
			var d = f.s[S_DIST]
			total_dist += d
			min_dist = minf(min_dist, d)
			max_dist = maxf(max_dist, d)
		if f.a.size() > A_FIRE_PRIMARY and f.a[A_FIRE_PRIMARY] > 0.5:
			fire_count += 1
	return {
		total_frames = total,
		quality_frames = quality_count,
		quality_pct = (quality_count * 100.0 / maxf(total, 1)),
		avg_dist = total_dist / maxf(total, 1),
		min_dist = min_dist if min_dist < INF else 0.0,
		max_dist = max_dist,
		fire_rate_pct = (fire_count * 100.0 / maxf(total, 1)),
	}

func trim_frames(trim_start: int, trim_end: int):
	var end_idx = maxi(frames.size() - trim_end, 0)
	var start_idx = mini(trim_start, end_idx)
	frames = frames.slice(start_idx, end_idx)
	_rebuild_buckets()

func merge_from(other: CombatRecording):
	for f in other.frames:
		add_frame(f.s.duplicate(), f.a.duplicate(), f.get("q", 0.0))

func purge_low_quality(threshold: float = 0.0):
	var kept: Array = []
	for f in frames:
		if f.q > threshold:
			kept.append(f)
	frames = kept
	_rebuild_buckets()

func _rebuild_buckets():
	_buckets.clear()
	for idx in frames.size():
		var f = frames[idx]
		if f.s.size() > S_DIST:
			var bucket = int(f.s[S_DIST] / BUCKET_SIZE)
			if not _buckets.has(bucket):
				_buckets[bucket] = []
			_buckets[bucket].append(idx)

func save_to_file(path: String) -> bool:
	var compact_frames: Array = []
	for f in frames:
		if f.q > 0.0:
			compact_frames.append({s = f.s, a = f.a, q = f.q})
		else:
			compact_frames.append({s = f.s, a = f.a})
	var data = {
		version = 1,
		name = recording_name,
		template = template_name,
		ship_config = ship_config,
		quality_threshold = quality_threshold,
		aggression_bias = aggression_bias,
		frame_count = frames.size(),
		frames = compact_frames,
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("CombatRecording: could not write " + path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func load_from_file(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return false
	var data = json.data
	if not data is Dictionary:
		return false
	recording_name = data.get("name", "")
	template_name = data.get("template", "")
	ship_config = data.get("ship_config", {})
	quality_threshold = data.get("quality_threshold", 0.0)
	aggression_bias = data.get("aggression_bias", 1.0)
	frames.clear()
	_buckets.clear()
	for f in data.get("frames", []):
		add_frame(f.get("s", []), f.get("a", []), f.get("q", 0.0))
	return true

static func list_recordings() -> Array[String]:
	var dir_path = "user://combat_recordings"
	var result: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			result.append(dir_path + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return result
