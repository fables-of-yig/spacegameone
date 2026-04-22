extends Node

const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")

signal encounter_started(event_id: String, enc_id: int)


var all_encounters: Dictionary = {}


var void_timer: float = 0.0
var encounter_cooldown: float = 0.0
var in_void: bool = false
var encounters_this_trip: int = 0


var MIN_VOID_TIME: float = 30.0
var ENCOUNTER_CHANCE_PER_SEC: float = 0.003
var ENCOUNTER_INTERVAL_MIN: float = 45.0
var ENCOUNTER_INTERVAL_MAX: float = 120.0
var MAX_ENCOUNTERS_PER_TRIP: int = 3
var CHAIN_WEIGHT_BOOST: float = 3.0
var VOID_DISTANCE: float = 18000.0


var encounter_flags: Dictionary = {}
var seen_encounters: Dictionary = {}
var encounter_counts: Dictionary = {}

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_encounter_tuning()

func load_encounters(data: Dictionary):

    all_encounters.clear()
    for key in data:
        var enc = data[key]
        var enc_id = int(key)
        enc["id"] = enc_id
        all_encounters[enc_id] = enc
    print("[EncounterManager] Loaded %d encounters." % all_encounters.size())

func tick(delta: float, nearest_system_dist: float):

    if nearest_system_dist < VOID_DISTANCE:

        if in_void:
            in_void = false
            encounters_this_trip = 0
        void_timer = 0.0
        return


    if not in_void:
        in_void = true
        void_timer = 0.0
        encounter_cooldown = 0.0
        encounters_this_trip = 0

    void_timer += delta


    if encounter_cooldown > 0:
        encounter_cooldown -= delta
        return


    if void_timer < MIN_VOID_TIME:
        return
    if encounters_this_trip >= MAX_ENCOUNTERS_PER_TRIP:
        return


    if randf() < ENCOUNTER_CHANCE_PER_SEC * delta:
        var enc = pick_encounter()
        if enc != null:
            fire_encounter(enc)
            encounter_cooldown = randf_range(ENCOUNTER_INTERVAL_MIN, ENCOUNTER_INTERVAL_MAX)

func pick_encounter() -> Variant:

    var candidates: Array = []
    var total_weight: float = 0.0
    var current_day: int = GameManager.game_day + (GameManager.game_month - 1) * 30 + (GameManager.game_year - 1) * 360
    var current_hour: int = GameManager.total_game_hours
    var player_power: int = GameManager.ship_modules.size()

    for enc_id in all_encounters:
        var enc = all_encounters[enc_id]


        if enc.get("unique", false) and seen_encounters.has(enc_id):
            continue


        var last_hour = seen_encounters.get(enc_id, -9999)
        var cd_hours = int(enc.get("cooldown_hours", 0))
        if cd_hours > 0 and (current_hour - last_hour) < cd_hours:
            continue


        var min_d = int(enc.get("min_day", 0))
        var max_d = int(enc.get("max_day", -1))
        if current_day < min_d:
            continue
        if max_d > 0 and current_day > max_d:
            continue


        var required: Array = enc.get("required_flags", [])
        var has_all = true
        for flag in required:
            if not encounter_flags.has(flag):
                has_all = false
                break
        if not has_all:
            continue


        var excluded: Array = enc.get("excluded_flags", [])
        var has_excluded = false
        for flag in excluded:
            if encounter_flags.has(flag):
                has_excluded = true
                break
        if has_excluded:
            continue


        var w: float = float(enc.get("weight", 10))


        var chain_prev = int(enc.get("chain_prev", -1))
        if chain_prev >= 0 and seen_encounters.has(chain_prev):
            w *= CHAIN_WEIGHT_BOOST


        var threat: String = enc.get("threat", "none")
        if player_power < 8:

            if threat == "extreme":
                w *= 0.05
            elif threat == "high":
                w *= 0.2
        elif player_power > 20:

            if threat == "extreme":
                w *= 2.0
            elif threat == "high":
                w *= 1.5
            elif threat == "none":
                w *= 0.6


        if seen_encounters.has(enc_id):
            var hours_since = current_hour - seen_encounters[enc_id]
            if hours_since < 48:
                w *= 0.1
            elif hours_since < 168:
                w *= 0.5

        candidates.append({"enc": enc, "weight": w})
        total_weight += w

    if candidates.is_empty():
        return null


    var roll = randf() * total_weight
    var running: float = 0.0
    for c in candidates:
        running += c["weight"]
        if roll <= running:
            return c["enc"]
    return candidates[-1]["enc"]

func fire_encounter(enc: Dictionary):

    var enc_id: int = int(enc["id"])


    for flag in enc.get("sets_flags", []):
        encounter_flags[flag] = true


    seen_encounters[enc_id] = GameManager.total_game_hours
    encounter_counts[enc_id] = encounter_counts.get(enc_id, 0) + 1
    encounters_this_trip += 1


    var event_id = "encounter_%d" % enc_id
    DataManager.events[event_id] = {
        "title": enc.get("title", "Encounter"), 
        "nodes": enc.get("nodes", {}), 
    }

    print("[EncounterManager] Firing encounter #%d: %s" % [enc_id, enc.get("title", "?")])
    encounter_started.emit(event_id, enc_id)

func get_spawn_data(enc_id: int) -> Array:

    var enc = all_encounters.get(enc_id, {})
    return enc.get("spawn", [])



func get_save_data() -> Dictionary:
    return {
        "encounter_flags": encounter_flags, 
        "seen_encounters": seen_encounters, 
        "encounter_counts": encounter_counts, 
    }

func load_save_data(data: Dictionary):
    encounter_flags = data.get("encounter_flags", {})

    var raw_seen = data.get("seen_encounters", {})
    seen_encounters.clear()
    for k in raw_seen:
        seen_encounters[int(k)] = int(raw_seen[k])
    var raw_counts = data.get("encounter_counts", {})
    encounter_counts.clear()
    for k in raw_counts:
        encounter_counts[int(k)] = int(raw_counts[k])

func reset():
    encounter_flags.clear()
    seen_encounters.clear()
    encounter_counts.clear()
    void_timer = 0.0
    encounter_cooldown = 0.0
    in_void = false
    encounters_this_trip = 0
    _load_encounter_tuning()


func _load_encounter_tuning() -> void:
    var pack_id := ""
    if MvPackLoader.current_pack != null:
        pack_id = MvPackLoader.current_pack.pack_id
    if pack_id.is_empty():
        pack_id = "demo"
    for path in [
        PedIO.user_file(pack_id, "GameTuning", "encounters.json"),
        PedIO.shipped_file(pack_id, "GameTuning", "encounters.json"),
        PedIO.demo_file("GameTuning", "encounters.json"),
    ]:
        if FileAccess.file_exists(path):
            var f := FileAccess.open(path, FileAccess.READ)
            if f == null:
                continue
            var raw = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(raw) == TYPE_DICTIONARY:
                MIN_VOID_TIME = float(raw.get("min_void_time", 30.0))
                ENCOUNTER_CHANCE_PER_SEC = float(raw.get("encounter_chance_per_sec", 0.003))
                ENCOUNTER_INTERVAL_MIN = float(raw.get("encounter_interval_min", 45.0))
                ENCOUNTER_INTERVAL_MAX = float(raw.get("encounter_interval_max", 120.0))
                MAX_ENCOUNTERS_PER_TRIP = int(raw.get("max_encounters_per_trip", 3))
                CHAIN_WEIGHT_BOOST = float(raw.get("chain_weight_boost", 3.0))
                VOID_DISTANCE = float(raw.get("void_distance", 18000.0))
                return
