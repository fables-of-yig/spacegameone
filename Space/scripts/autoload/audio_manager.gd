extends Node





var sfx_pool: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE: int = 8
var sfx_cache: Dictionary = {}


var ambient_player: AudioStreamPlayer = null
var ambient_target: String = ""
var ambient_fade_timer: float = 0.0
var ambient_fade_dir: float = 0.0
const AMBIENT_FADE_TIME: float = 2.0


var sfx_volume: float = 0.8
var ambient_volume: float = 0.5


var _beam_player: AudioStreamPlayer = null
var _beam_state: int = 0  # 0=off, 1=starting, 2=looping, 3=ending


const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")

const SFX_DIR: String = "res://Space/audio/sfx/"
const AMBIENCE_DIR: String = "res://Space/audio/ambience/"

var _audio_manifest: Dictionary = {}

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    print("[AudioManager] Initializing...")

    for i in SFX_POOL_SIZE:
        var p = AudioStreamPlayer.new()
        p.bus = &"Master"
        add_child(p)
        sfx_pool.append(p)


    ambient_player = AudioStreamPlayer.new()
    ambient_player.bus = &"Master"
    ambient_player.volume_db = -80.0
    add_child(ambient_player)
    ambient_player.finished.connect(_on_ambient_finished)

    _beam_player = AudioStreamPlayer.new()
    _beam_player.bus = &"Master"
    add_child(_beam_player)
    _beam_player.finished.connect(_on_beam_finished)


    var sfx_names = [
        "laser_fire", "cannon_fire", "explosion", "shield_hit", "hull_hit", 
        "boost", "scan_pulse", "loot_pickup", "ui_click", "jump_warp", 
        "module_place", "turret_fire", "plasma_fire", "heavy_shot", 
        "wormhole_open", "mission_accept", "mission_complete", 
        "dock_clamp", "airlock_cycle", "crew_footstep", "alert_klaxon", 
        "power_down", "power_up", "menu_open", "menu_close", 
        "repair", "cargo_load", "crew_board", 
        "comms_hail", "mining_laser", "colony_deploy", "fleet_warp", 
        "discovery_chime", "warning_beep", "fuel_scoop", "system_online", 
        "shield_up", "hull_creak", 
        "tractor_beam", "airlock_open", "craft_complete", "craft_start", 
        "module_destroy", "warp_charge", "scan_complete", "crew_assign", 
        "resource_collect", "alarm_hull_breach", "torpedo_launch", 
        "missile_lock", "docking_complete", "undock", "construction_hit", 
        "reactor_hum", "door_open", "comm_static", "level_up", "trade_complete",
        "hornet_armed",
    ]
    var sfx_ogg = [
        "railgun_fire", "pulse_laser_1", "pulse_laser_2", "pulse_laser_3", "hornet_fire",
        "ship_explode_1", "ship_explode_2", "ship_explode_3", "ship_explode_4",
        "ship_explode_5", "ship_explode_6", "ship_explode_7",
        "beam_start", "beam_loop", "beam_end",
    ]
    for sname in sfx_names:
        var stream = _load_audio(SFX_DIR + sname + ".wav")
        if stream:
            sfx_cache[sname] = stream
            print("[AudioManager] Cached SFX: ", sname)
        else:
            print("[AudioManager] MISSING SFX: ", sname)
    for sname in sfx_ogg:
        var stream = _load_audio(SFX_DIR + sname + ".ogg")
        if stream:
            sfx_cache[sname] = stream
            print("[AudioManager] Cached SFX: ", sname)
        else:
            print("[AudioManager] MISSING SFX: ", sname)
    print("[AudioManager] Ready. ", sfx_cache.size(), " SFX loaded.")
    _load_audio_manifest()

func _process(delta: float):

    if ambient_fade_dir != 0.0:
        ambient_fade_timer += delta
        var t = clampf(ambient_fade_timer / AMBIENT_FADE_TIME, 0, 1)
        if ambient_fade_dir > 0:

            var vol = t * ambient_volume
            ambient_player.volume_db = linear_to_db(vol) if vol > 0.001 else -80.0
            if t >= 1.0:
                ambient_fade_dir = 0.0
        else:

            var vol = (1.0 - t) * ambient_volume
            ambient_player.volume_db = linear_to_db(vol) if vol > 0.001 else -80.0
            if t >= 1.0:
                ambient_fade_dir = 0.0
                ambient_player.stop()

                if ambient_target != "":
                    _start_ambient(ambient_target)
                    ambient_target = ""


func play_sfx(sfx_name: String, volume_scale: float = 1.0, pitch_variance: float = 0.05, from_position: float = 0.0):
    var stream: AudioStream = sfx_cache.get(sfx_name)
    if not stream:
        stream = _resolve_manifest_sfx(sfx_name)
    if not stream:
        return


    var player: AudioStreamPlayer = null
    for p in sfx_pool:
        if not p.playing:
            player = p
            break

    if not player:
        player = sfx_pool[0]

    player.stream = stream
    var vol = sfx_volume * volume_scale
    player.volume_db = linear_to_db(vol) if vol > 0.001 else -80.0
    player.pitch_scale = 1.0 + randf_range( - pitch_variance, pitch_variance)
    player.play(from_position)


func set_ambient(ambient_name: String):
    if ambient_name == "":
        if ambient_player.playing:
            ambient_fade_timer = 0.0
            ambient_fade_dir = -1.0
        return


    if ambient_player.playing and ambient_player.stream:
        var current_path: String = ambient_player.stream.resource_path
        var target_path = AMBIENCE_DIR + ambient_name + ".wav"
        if current_path == target_path:
            return

    if ambient_player.playing:

        ambient_target = ambient_name
        ambient_fade_timer = 0.0
        ambient_fade_dir = -1.0
    else:
        _start_ambient(ambient_name)

func _start_ambient(ambient_name: String):
    var path = AMBIENCE_DIR + ambient_name + ".wav"
    var stream = _load_audio(path)
    if not stream:
        print("[AudioManager] Ambient not found: ", path)
        return
    ambient_player.stream = stream
    ambient_player.volume_db = -80.0
    ambient_player.play()
    ambient_fade_timer = 0.0
    ambient_fade_dir = 1.0
    print("[AudioManager] Playing ambient: ", ambient_name)

func _on_ambient_finished():

    if ambient_player.stream and ambient_fade_dir >= 0:
        ambient_player.play()

func _load_audio(path: String) -> AudioStream:
    if not ResourceLoader.exists(path):
        return null
    return load(path) as AudioStream



const AMBIENT_POOLS: Dictionary = {
    "space": ["space_ambience", "deep_space_drift", "nebula_hum", "solar_wind", "asteroid_field_ambience", "comm_chatter", "space_ethereal", "space_whispers", "void_drone", "nebula_song", "space_radiation_belt"], 
    "combat": ["combat_ambience", "combat_intense", "combat_skirmish"], 
    "station": ["station_ambience", "station_systems", "engine_room", "station_crowd", "station_cantina", "station_docking_bay", "station_market"], 
    "surface": ["surface_ambience", "planet_atmosphere", "surface_ice_world", "surface_volcanic"], 
    "warp": ["warp_tunnel", "warp_hyperspace"], 
    "derelict": ["derelict_ship", "derelict_interior", "derelict_power_failing"], 
    "encounter": ["encounter_tension", "encounter_mysterious"], 
}
var _last_ambient_category: String = ""



func set_ambient_varied(category: String):
    var pool: Array = AMBIENT_POOLS.get(category, [])
    if pool.is_empty():
        set_ambient(category)
        return
    _last_ambient_category = category
    var pick = pool[randi() % pool.size()]

    if pool.size() > 1 and ambient_player.playing and ambient_player.stream:
        var current = ambient_player.stream.resource_path.get_file().get_basename()
        if current == pick:
            pick = pool[(pool.find(pick) + 1) % pool.size()]
    set_ambient(pick)

func linear_to_db(linear: float) -> float:
    if linear <= 0.001:
        return -80.0
    return 20.0 * log(linear) / log(10.0)


func beam_start(volume_scale: float = 0.7):
    if _beam_state == 2:
        return  # already looping
    var stream = sfx_cache.get("beam_start")
    if not stream:
        beam_loop(volume_scale)
        return
    _beam_state = 1
    _beam_player.stream = stream
    var vol = sfx_volume * volume_scale
    _beam_player.volume_db = linear_to_db(vol)
    _beam_player.pitch_scale = 1.0
    _beam_player.play()

func beam_loop(volume_scale: float = 0.7):
    var stream = sfx_cache.get("beam_loop")
    if not stream:
        return
    _beam_state = 2
    _beam_player.stream = stream
    var vol = sfx_volume * volume_scale
    _beam_player.volume_db = linear_to_db(vol)
    _beam_player.pitch_scale = 1.0
    _beam_player.play()

func beam_stop(volume_scale: float = 0.7):
    if _beam_state == 0 or _beam_state == 3:
        return
    var stream = sfx_cache.get("beam_end")
    if not stream:
        _beam_player.stop()
        _beam_state = 0
        return
    _beam_state = 3
    _beam_player.stream = stream
    var vol = sfx_volume * volume_scale
    _beam_player.volume_db = linear_to_db(vol)
    _beam_player.pitch_scale = 1.0
    _beam_player.play()

func beam_stop_immediate():
    _beam_player.stop()
    _beam_state = 0

func _on_beam_finished():
    if _beam_state == 1:
        beam_loop()
    elif _beam_state == 2:
        # Loop the beam sound
        _beam_player.play()
    elif _beam_state == 3:
        _beam_state = 0


func _load_audio_manifest() -> void:
    var pack_id := ""
    if MvPackLoader.current_pack != null:
        pack_id = MvPackLoader.current_pack.pack_id
    if pack_id.is_empty():
        pack_id = "demo"
    for path in [
        PedIO.user_file(pack_id, "Audio", "manifest.json"),
        PedIO.shipped_file(pack_id, "Audio", "manifest.json"),
        PedIO.demo_file("Audio", "manifest.json"),
    ]:
        if FileAccess.file_exists(path):
            var f := FileAccess.open(path, FileAccess.READ)
            if f == null:
                push_warning("[AudioManager] manifest open failed: %s" % path)
                continue
            var raw = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(raw) != TYPE_DICTIONARY:
                push_warning("[AudioManager] manifest %s is not a JSON object — ignored" % path)
                continue
            _audio_manifest = _sanitize_manifest(raw, path)
            return
    _audio_manifest = {}


# Validate a parsed manifest: ensure the expected sections exist and are
# dictionaries, and that each value is a non-empty string path that
# actually loads as audio. Invalid entries are stripped and logged so
# the runtime never silently serves bad paths from play_sfx.
func _sanitize_manifest(raw: Dictionary, source_path: String) -> Dictionary:
    var out: Dictionary = {"sfx": {}, "ambience": {}, "music": {}}
    var dropped: int = 0
    for section_name in ["sfx", "ambience", "music"]:
        var section_v: Variant = raw.get(section_name, {})
        if typeof(section_v) != TYPE_DICTIONARY:
            if raw.has(section_name):
                push_warning("[AudioManager] %s: '%s' is not an object, skipping" %
                    [source_path, section_name])
            continue
        var section: Dictionary = section_v
        var cleaned: Dictionary = {}
        for k_v in section.keys():
            var k: String = str(k_v).strip_edges()
            var path: String = str(section[k_v]).strip_edges()
            if k.is_empty() or path.is_empty():
                dropped += 1
                push_warning("[AudioManager] %s: dropped '%s'.'%s' (blank name or path)" %
                    [source_path, section_name, k])
                continue
            if not ResourceLoader.exists(path):
                dropped += 1
                push_warning("[AudioManager] %s: '%s'.'%s' -> '%s' not found on disk" %
                    [source_path, section_name, k, path])
                continue
            cleaned[k] = path
        out[section_name] = cleaned
    if dropped > 0:
        print("[AudioManager] manifest loaded with %d invalid entr(ies) dropped" % dropped)
    return out


# Re-read Audio/manifest.json for the current pack and drop any cached
# streams that came from the manifest so the next play_sfx picks up
# updated paths. Callers: audio editor after save, pack reload flows.
func reload_manifest() -> void:
    var old_keys: Array = []
    var sfx_map_v: Variant = _audio_manifest.get("sfx", {})
    if typeof(sfx_map_v) == TYPE_DICTIONARY:
        old_keys = (sfx_map_v as Dictionary).keys()
    for key in old_keys:
        if sfx_cache.has(key):
            sfx_cache.erase(key)
    _load_audio_manifest()
    print("[AudioManager] manifest reloaded — %d sfx entries" %
        (_audio_manifest.get("sfx", {}) as Dictionary).size())


func _resolve_manifest_sfx(sfx_name: String) -> AudioStream:
    var sfx_map: Variant = _audio_manifest.get("sfx", {})
    if typeof(sfx_map) != TYPE_DICTIONARY:
        return null
    var path_v: Variant = (sfx_map as Dictionary).get(sfx_name, "")
    var path: String = str(path_v)
    if path.is_empty():
        return null
    var stream := _load_audio(path)
    if stream != null:
        sfx_cache[sfx_name] = stream
    return stream
