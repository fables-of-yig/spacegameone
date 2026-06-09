extends Node2D


const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const RegIO = preload("res://Space/scripts/shared/reg/reg_io.gd")
const SystemIO = preload("res://Space/scripts/shared/system_io.gd")
const StarfieldRenderer = preload("res://Space/scripts/world/starfield_renderer.gd")
const WorldRenderer = preload("res://Space/scripts/world/world_renderer.gd")
const UICoordinator = preload("res://Space/scripts/ui/ui_coordinator.gd")
const SpawnManager = preload("res://Space/scripts/runtime/spawn_manager.gd")
const CreativeModeController = preload("res://Space/scripts/runtime/creative_mode_controller.gd")
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")


var player_scene: PackedScene = preload("res://Space/scenes/player_ship.tscn")
var enemy_scene: PackedScene = preload("res://Space/scenes/enemy_ship.tscn")
var explosion_script: GDScript = preload("res://Space/scripts/combat/explosion.gd")
var poi_script: GDScript = preload("res://Space/scripts/world/poi_marker.gd")
var loot_script: GDScript = preload("res://Space/scripts/world/loot_drop.gd")
var turret_script: GDScript = preload("res://Space/scripts/combat/surface_turret.gd")
var wormhole_script: GDScript = preload("res://Space/scripts/combat/wormhole_vfx.gd")
var warpin_script: GDScript = preload("res://Space/scripts/combat/warpin_vfx.gd")
var ship_explosion_script: GDScript = preload("res://Space/scripts/combat/ship_explosion_vfx.gd")
var warp_portal_script: GDScript = preload("res://Space/scripts/combat/warp_portal_vfx.gd")
var asteroid_script: GDScript = preload("res://Space/scripts/world/asteroid_field.gd")
var npc_ship_script: GDScript = preload("res://Space/scripts/world/npc_ship.gd")
var station_entity_script: GDScript = preload("res://Space/scripts/world/station_entity.gd")



var player: Node2D = null
var hud_control = null
var builder = null
var star_map = null
var event_panel = null
var content_editor = null
var region_editor = null
var environment_editor = null
var entity_editor = null
var behavior_editor = null
var theme_editor = null
var audio_editor = null
var player_editor = null
var system_editor = null
var ship_editor = null
var modules_editor = null
var loot_editor = null
var trigger_editor = null
var dialogue_editor = null
var factions_editor = null
var shop_editor = null
var quest_editor = null
var _editor_active_pack_id: String = ""
var _editor_active_region_id: String = ""
var _editor_return_to_content_hub: bool = false
var _content_editor_return_mode: String = "campaign"
var docked_station_key: String = ""
var main_menu = null
var pause_menu = null
var death_screen = null
var menu_open: bool = true
var creative_mode_active: bool = false
var creative_test_flying: bool = false
@warning_ignore("unused_private_class_variable")
var _combat_recorder: Node = null
@warning_ignore("unused_private_class_variable")
var _cloned_recordings: Array = []  # loaded CombatRecording instances for AI
var creative_recording_ai: bool = false
var creative_previewing_ai: bool = false
var creative_training_ai: bool = false
@warning_ignore("unused_private_class_variable")
var _training_round: int = 0
var _training_clone: Node2D = null
@warning_ignore("unused_private_class_variable")
var _training_advance_pending: bool = false
var _training_naming: bool = false
@warning_ignore("unused_private_class_variable")
var _training_name_input: String = ""
@warning_ignore("unused_private_class_variable")
var _training_name_edit: LineEdit = null
@warning_ignore("unused_private_class_variable")
var _recording_template_name: String = ""
@warning_ignore("unused_private_class_variable")
var _creative_saved_modules: Array = []
@warning_ignore("unused_private_class_variable")
var _creative_saved_core: String = ""
@warning_ignore("unused_private_class_variable")
var _creative_test_modules: Array = []
@warning_ignore("unused_private_class_variable")
var _creative_test_core: String = ""
var _creative_runtime_source: String = ""
var pause_open: bool = false
var time_frozen: bool = false
var editor_open: bool = false
var _pending_open: String = ""


var on_surface: bool = false
var surface_data: Dictionary = {}
var surface_seed: float = 0.0
const SURFACE_RADIUS: float = 5000.0
const SURFACE_SPACE_FREEZE_GROUPS: Array[StringName] = [
    &"player",
    &"enemies",
    &"npc_ships",
    &"station_entities",
    &"projectiles",
    &"asteroids",
    &"pois",
    &"loot",
    &"fleet_ships",
    &"boarding_pods",
    &"escape_pods",
]
var surface_entry_timer: float = 0.0
var surface_exit_timer: float = 0.0
var hail_target: Node2D = null
var _space_simulation_surface_locked: bool = false


var _cached_enemies: Array = []
var _cached_npc_ships: Array = []
var _cached_station_entities: Array = []
var _cached_pois: Array = []
var _group_cache_frame: int = 0
# Per-rule arm state for ECA rules with event="space_proximity_band".
# Keyed by rule_id; true while the player is currently inside the band, so
# subsequent ticks don't re-fire. Cleared on band exit so a re-entry fires
# again. Replaces the old per-system spawn_triggers proximity tracking.
var _proximity_band_armed: Dictionary = {}
# Cached band specs for the current system. Rebuilt on system entry from
# the ECA rule registry: [{rule_id, band_min, band_max}]. _poll_proximity_bands
# iterates this every tick — cheap as long as authors keep band rules in
# the dozens, not thousands.
var _proximity_bands_cache: Array = []

var starfield: Node2D = null
var _ui: Node = null
var _spawn: Node = null
var _cmc: Node = null
var _map_editor: SpaceMapEditor = null
var _world_renderer: Node2D = null

var camera_zoom: float = 1.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 2.5
const ZOOM_STEP: float = 0.1
const ZOOM_SMOOTH_SPEED: float = 8.0
var _target_zoom: float = 1.0
var surface_return_pos: Vector2 = Vector2.ZERO
const SURFACE_TRANSITION_TIME: float = 1.2

# MVMania planet surface integration — the hand-off target for planet POIs.
# planet_viewport_container is a full-screen SubViewportContainer with
# stretch_shrink=4 so a 480x270 SubViewport scales 4x to 1920x1080.
# planet_main_instance is the MVMania Main scene, instantiated fresh per
# landing (disposed on launch) so each planet gets a clean pack load.
var planet_viewport_layer: CanvasLayer = null
var planet_viewport_container: SubViewportContainer = null
var planet_viewport: SubViewport = null
var planet_overlay_layer: CanvasLayer = null
var planet_overlay_root: Control = null
var planet_main_instance: Node = null
var _planet_overlay_hud: Control = null
var _surface_death_blocked: bool = false

# Region landing picker — populated by UICoordinator. Opened when the player
# presses interact on a landable planet POI; emits region_chosen / cancelled.
var region_picker: Control = null
# Tracks the POI currently associated with the open picker so we can auto-
# close if the player drifts out of range while it's up.
var _region_picker_poi: Node2D = null
var _region_picker_pending_data: Dictionary = {}

# Tracks whether the current planet visit was launched from the SSB main
# menu (TEST PLANET / EDITOR buttons) so that on launch, we return to the
# menu instead of dropping into an uninitialized space session.
var _entered_planet_from_menu: bool = false
# Tracks whether the current planet visit was entered from a live in-space
# session, so liftoff should restore the player's ship instead of bouncing
# back to the main menu.
var _planet_visit_from_space_session: bool = false
# Distinguishes "Play Pack" menu entry from the demo/test-planet preview so
# liftoff can bootstrap a real authored space session for campaign packs.
var _entered_authored_pack_from_menu: bool = false

# Cached reference to the C# PlanetaryInterface autoload. GDScript can't see
# C# autoload symbols at parse time (the `PlanetaryInterface` identifier
# resolves to the CSharpScript resource, not the live node instance), so we
# look it up by /root path and call methods/connect signals through this var.
var _planet_iface: Node = null

var in_combat: bool = false
var combat_timer: float = 0.0
var builder_open: bool = false
var star_map_open: bool = false
var event_open: bool = false
var _current_event_poi_id: String = ""


var jumping: bool = false
var jump_timer: float = 0.0
var jump_target: String = ""
const JUMP_DURATION: float = 1.5


const WORLD_SCALE: float = 150.0
var system_world_positions: Dictionary = {}
var loaded_system: String = ""

func _ready():
    process_mode = PROCESS_MODE_ALWAYS
    # Boot order is load-bearing. The runtime controllers split out of the
    # former monolithic main (StarfieldRenderer, WorldRenderer, SpawnManager,
    # CreativeModeController, UICoordinator) each take `owner_main = self` and
    # reach back into this node's fields/methods through that reference, so the
    # creation order below matters:
    #   - SpawnManager.spawn_player() sets `player` and MUST run before
    #     UICoordinator.setup_hud(player, ...), which is handed `player`.
    #     Reordering it after setup_hud() leaves `player` null and the HUD
    #     unbound.
    #   - CreativeModeController owns the creative-mode / combat-recording state
    #     declared near the top of this script (the @warning_ignore block) — that
    #     state is written/read by the controller via host._x, not here, which is
    #     why the warnings are suppressed.
    #   - UICoordinator.setup_editors() returns {} in shipped builds, so each
    #     editor handle below is fetched with .get(..., null).
    # The owner_main back-reference is the implicit coupling ROADMAP flags for a
    # future typed runtime contract.
    starfield = StarfieldRenderer.new()
    starfield.owner_main = self
    add_child(starfield)
    _apply_current_pack_systems_if_any()
    _compute_world_positions()
    starfield.generate(900)
    starfield.bake_bg_texture.call_deferred()
    _world_renderer = WorldRenderer.new()
    _world_renderer.owner_main = self
    add_child(_world_renderer)
    _spawn = SpawnManager.new()
    _spawn.owner_main = self
    add_child(_spawn)
    _spawn.spawn_player()
    _cmc = CreativeModeController.new()
    _cmc.owner_main = self
    add_child(_cmc)
    _map_editor = SpaceMapEditor.new()
    _map_editor.setup(self)
    add_child(_map_editor)
    _ui = UICoordinator.new()
    add_child(_ui)
    hud_control = _ui.setup_hud(player, system_world_positions)
    builder = _ui.setup_builder(self)
    star_map = _ui.setup_star_map(self)
    event_panel = _ui.setup_event_panel(self)
    # In shipped builds setup_editors returns {} (no editor scripts in the
    # export); use .get(..., null) so every editor handle stays null and
    # the rest of boot just no-ops past missing entries.
    var editors = _ui.setup_editors(self)
    content_editor = editors.get("content_editor", null)
    region_editor = editors.get("region_editor", null)
    environment_editor = editors.get("environment_editor", null)
    entity_editor = editors.get("entity_editor", null)
    behavior_editor = editors.get("behavior_editor", null)
    theme_editor = editors.get("theme_editor", null)
    audio_editor = editors.get("audio_editor", null)
    player_editor = editors.get("player_editor", null)
    system_editor = editors.get("system_editor", null)
    ship_editor = editors.get("ship_editor", null)
    modules_editor = editors.get("modules_editor", null)
    loot_editor = editors.get("loot_editor", null)
    trigger_editor = editors.get("trigger_editor", null)
    dialogue_editor = editors.get("dialogue_editor", null)
    factions_editor = editors.get("factions_editor", null)
    shop_editor = editors.get("shop_editor", null)
    quest_editor = editors.get("quest_editor", null)
    _restore_editor_from_playtest_if_any()
    pause_menu = _ui.setup_pause_menu(self)
    _ui.setup_cinematic_overlay()
    death_screen = _ui.setup_death_screen(self)
    main_menu = _ui.setup_main_menu(self, GameManager)
    _auto_route_to_shipped_pack_if_any()
    var pv = _ui.setup_planet_viewport()
    planet_viewport_layer = pv["layer"]
    planet_viewport_container = pv["container"]
    planet_viewport = pv["viewport"]
    planet_overlay_layer = pv["overlay_layer"]
    planet_overlay_root = pv["overlay_root"]
    GameManager.hour_changed.connect(_on_game_hour_changed)
    GameManager.day_changed.connect(_on_game_day_changed)
    EncounterManager.encounter_started.connect(_on_encounter_started)
    _planet_iface = get_node_or_null("/root/PlanetaryInterface")
    if _planet_iface and _planet_iface.has_signal("launch_requested"):
        _planet_iface.launch_requested.connect(_on_launch_requested)
    else:
        push_warning("PlanetaryInterface autoload not found — planet handoff disabled")

    region_picker = _ui.setup_region_picker(self)

    if MvTriggerEngine != null and MvTriggerEngine.has_signal("action_spawn_space_ship"):
        if not MvTriggerEngine.action_spawn_space_ship.is_connected(_on_trigger_spawn_space_ship):
            MvTriggerEngine.action_spawn_space_ship.connect(_on_trigger_spawn_space_ship)
    if MvTriggerEngine != null and MvTriggerEngine.has_signal("action_spawn_space_enemies"):
        if not MvTriggerEngine.action_spawn_space_enemies.is_connected(_on_trigger_spawn_space_enemies):
            MvTriggerEngine.action_spawn_space_enemies.connect(_on_trigger_spawn_space_enemies)
    if not menu_open:
        var start_pos = system_world_positions.get(GameManager.current_system, Vector2.ZERO)

        var _start_sys = DataManager.systems.get(GameManager.current_system, {})
        var _start_star_r = _start_sys.get("star_size", 60) * 20.0
        start_pos += Vector2(_start_star_r + 2000.0, 0)
        if player:
            player.position = start_pos
            player.nearest_star_pos = system_world_positions.get(GameManager.current_system, Vector2.ZERO)
        _load_system_content(GameManager.current_system)
    else:
        get_tree().paused = true

    if not menu_open:
        _apply_initial_loadout.call_deferred()

func _notification(what: int):

    if what == NOTIFICATION_APPLICATION_FOCUS_IN:
        if time_frozen:
            get_tree().paused = true

func _compute_world_positions():

    system_world_positions.clear()
    for sys_id in DataManager.systems:
        var sys = DataManager.systems[sys_id]
        var p = sys.get("position", [0, 0])
        system_world_positions[sys_id] = Vector2(p[0], p[1]) * WORLD_SCALE
    if hud_control:
        hud_control.system_positions = system_world_positions


func _apply_current_pack_systems_if_any() -> void:
    if MvPackLoader.current_pack == null:
        return
    _apply_pack_systems(MvPackLoader.current_pack.pack_id)


func _apply_pack_systems(pack_id: String) -> void:
    var pid: String = pack_id.strip_edges()
    if pid.is_empty() or not SystemIO.exists(pid):
        return
    if MvTriggerEngine != null and MvTriggerEngine.has_method("load_triggers"):
        MvTriggerEngine.load_triggers(pid)
    DataManager.systems = SystemIO.load_or_init(pid)
    if DataManager.systems.is_empty():
        system_world_positions.clear()
        loaded_system = ""
        GameManager.current_system = ""
        GameManager.visited_systems = []
        if hud_control:
            hud_control.system_positions = system_world_positions
        if starfield != null:
            starfield.mark_dirty()
        if _world_renderer != null:
            _world_renderer.queue_redraw()
        return

    if GameManager.current_system.is_empty() or not DataManager.systems.has(GameManager.current_system):
        GameManager.current_system = str(DataManager.systems.keys()[0])
        GameManager.visited_systems = [GameManager.current_system]
    _compute_world_positions()
    if starfield != null:
        starfield.mark_dirty()
    if _world_renderer != null:
        _world_renderer.queue_redraw()
    if not menu_open and not editor_open and not on_surface and not GameManager.current_system.is_empty():
        loaded_system = ""
        _load_system_content(GameManager.current_system)

func _apply_initial_loadout():
    _migrate_module_positions()
    if player and is_instance_valid(player) and not GameManager.ship_modules.is_empty():
        player.apply_loadout(GameManager.ship_modules)

    if not player.power_preset_changed.is_connected(_on_power_preset_changed):
        player.power_preset_changed.connect(_on_power_preset_changed)

    if hud_control:
        var sys = DataManager.systems.get(GameManager.current_system, {})
        hud_control.system_name = sys.get("name", "Unknown")
        hud_control.kill_count = GameManager.kill_count

    GameManager.update_cargo_capacity()

    AudioManager.set_ambient_varied("space")

func _migrate_module_positions():


    if GameManager.ship_modules.is_empty():
        return
    var core_data = DataManager.modules.get(GameManager.equipped_core, {})
    var hull_radius = int(core_data.get("hull_radius", 0))
    if hull_radius <= 0:
        return
    var hull_set: Dictionary = {}
    for c in HexUtil.generate_hex_disc(hull_radius):
        hull_set[c] = true
    var inside: int = 0
    for mod in GameManager.ship_modules:
        var gp = mod.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        if hull_set.has(gp):
            inside += 1
    @warning_ignore("integer_division")
    if inside > GameManager.ship_modules.size() / 2:
        return
    var sum = Vector2i.ZERO
    for mod in GameManager.ship_modules:
        var gp = mod.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        sum += gp
    var cq = roundi(float(sum.x) / GameManager.ship_modules.size())
    var cr = roundi(float(sum.y) / GameManager.ship_modules.size())
    var offset = Vector2i( - cq, - cr)
    if offset == Vector2i.ZERO:
        return
    for mod in GameManager.ship_modules:
        var gp = mod.get("grid_pos", Vector2i.ZERO)
        if gp is Array:
            gp = Vector2i(int(gp[0]), int(gp[1]))
        mod["grid_pos"] = gp + offset

# Scans the loaded ECA ruleset for rules with event="space_proximity_band"
# whose event_params.system_id matches the active system, and caches their
# band parameters so _poll_proximity_bands can check them cheaply. Called
# on system entry; rebuilds the cache from scratch (and clears arm state
# so stale arms from a prior system don't suppress fires in the new one).
func _rebuild_proximity_bands_for_system(sys_id: String) -> void:
    _proximity_bands_cache.clear()
    _proximity_band_armed.clear()
    if MvTriggerEngine == null or not MvTriggerEngine.has_method("get_rules"):
        return
    for rule_v in MvTriggerEngine.get_rules():
        if typeof(rule_v) != TYPE_DICTIONARY:
            continue
        var rule: Dictionary = rule_v
        if str(rule.get("event", "")) != "space_proximity_band":
            continue
        var params_v: Variant = rule.get("event_params", {})
        if typeof(params_v) != TYPE_DICTIONARY:
            continue
        var params: Dictionary = params_v
        if str(params.get("system_id", "")) != sys_id:
            continue
        _proximity_bands_cache.append({
            "rule_id": str(rule.get("id", "")),
            "band_min": float(params.get("band_min", 0.0)),
            "band_max": float(params.get("band_max", 0.0)),
        })


# Polled every Space-layer tick. For each cached band rule, checks whether
# the player ship is currently inside its [band_min, band_max] ring around
# the star. Fires "space_proximity_band" once per entry (arms the rule),
# and clears the arm on exit so the next entry fires again.
func _poll_proximity_bands() -> void:
    if _proximity_bands_cache.is_empty():
        return
    if player == null or not is_instance_valid(player):
        return
    var sys_id: String = GameManager.current_system
    if not system_world_positions.has(sys_id):
        return
    var dist: float = player.global_position.distance_to(system_world_positions[sys_id])
    for entry_v in _proximity_bands_cache:
        var entry: Dictionary = entry_v
        var rule_id: String = str(entry.get("rule_id", ""))
        if rule_id.is_empty():
            continue
        var band_min: float = float(entry.get("band_min", 0.0))
        var band_max: float = float(entry.get("band_max", 0.0))
        var inside: bool = dist >= band_min and dist <= band_max
        if not inside:
            _proximity_band_armed.erase(rule_id)
            continue
        if bool(_proximity_band_armed.get(rule_id, false)):
            continue
        _proximity_band_armed[rule_id] = true
        if MvTriggerEngine != null:
            MvTriggerEngine.fire_event("space_proximity_band", {
                "system_id": sys_id,
                "band_min": band_min,
                "band_max": band_max,
                "distance": dist,
                "rule_id": rule_id,
            })

func _despawn_npc_ships():

    for npc in _cached_npc_ships:
        if is_instance_valid(npc):
            npc.queue_free()

func _should_spawn_procedural_npcs(sys_id: String) -> bool:
    if creative_test_flying:
        return false
    var sys: Dictionary = DataManager.systems.get(sys_id, {})
    if sys.is_empty():
        return false
    if sys.has("auto_spawn_npcs"):
        return bool(sys.get("auto_spawn_npcs", false))
    return bool(sys.get("procedural", false))

func _should_spawn_procedural_asteroids(sys_id: String) -> bool:
    var sys: Dictionary = DataManager.systems.get(sys_id, {})
    if sys.is_empty():
        return false
    if sys.has("auto_spawn_asteroids"):
        return bool(sys.get("auto_spawn_asteroids", false))
    return bool(sys.get("procedural", false))

func _on_npc_ship_died(npc_id: String, pos: Vector2):

    var sys_id = loaded_system
    var ships = GameManager.get_npc_ships_in_system(sys_id)
    for ship_data in ships:
        if ship_data.get("id") == npc_id:
            ship_data["alive"] = false
            var faction = ship_data.get("faction", "")
            if faction != "" and not ship_data.get("hostile", false):

                GameManager.modify_reputation(faction, -10.0)
                if hud_control:
                    var fname = DataManager.galaxy_data.get("factions", {}).get(faction, {}).get("name", faction)
                    hud_control.show_bark("REPUTATION", "Standing with %s decreased" % fname, Color(0.9, 0.5, 0.2), 3.0)

                for npc in _cached_npc_ships:
                    if not is_instance_valid(npc):
                        continue
                    if npc.is_law_enforcement and not npc.hostile:
                        var dist_to_crime = npc.global_position.distance_to(pos)
                        if dist_to_crime < 3000.0:
                            npc.become_hostile_to_player()
                if hud_control:
                    var has_le = false
                    for npc in _cached_npc_ships:
                        if not is_instance_valid(npc):
                            continue
                        if npc.hostile and npc.is_law_enforcement:
                            has_le = true
                            break
                    if has_le:
                        hud_control.show_bark("CRIME", "ISD patrols are responding!", Color(0.9, 0.2, 0.2), 3.0)
            elif ship_data.get("hostile", false):

                GameManager.modify_reputation("union_militia", 2.0)
                GameManager.modify_reputation("cotac", 1.0)
                GameManager.modify_reputation("isd", 1.0)
            break

    var expl = Node2D.new()
    expl.set_script(explosion_script)
    expl.global_position = pos
    add_child(expl)
    expl.setup(Color(1, 0.5, 0.2), 12)
    var explode_sfx = "ship_explode_%d" % randi_range(1, 7)
    AudioManager.play_sfx(explode_sfx, 0.8, 0.05)

    var sys = DataManager.systems.get(sys_id, {})
    var threat = int(sys.get("threat_level", 1))
    var credit_drop = randi_range(5, 15) * threat
    GameManager.credits += credit_drop
    if randf() < 0.3:
        GameManager.fuel = minf(GameManager.fuel + randf_range(2, 6) * threat, GameManager.fuel_capacity)
    if randf() < 0.15:
        var res_keys = GameManager.RESOURCE_TYPES.keys()
        GameManager.add_resource(res_keys[randi() % res_keys.size()], randi_range(1, 2))
    #if randf() < DataManager.get_drop_chance(threat):
    #    _spawn_loot.call_deferred(pos)
    GameManager.kill_count += 1
    GameManager.total_kills += 1
    if hud_control:
        hud_control.kill_count = GameManager.kill_count
        hud_control.queue_redraw()


func _on_station_destroyed(station_key: String, pos: Vector2):
    if station_key != "" and GameManager.persistent_stations.has(station_key):
        var sdata: Dictionary = GameManager.persistent_stations[station_key]
        sdata["destroyed"] = true
        sdata["health"] = 0.0
    if hud_control:
        hud_control.show_bark("STATION", "Station destroyed", Color(0.95, 0.45, 0.35), 2.5)
    if MvTriggerEngine != null:
        MvTriggerEngine.fire_event("space_station_destroyed", {
            "system_id": loaded_system,
            "station_key": station_key,
            "x": pos.x,
            "y": pos.y,
        })

func _load_system_content(sys_id: String):

    if loaded_system == sys_id:
        return

    for e in _cached_enemies:
        e.queue_free()
    for l in get_tree().get_nodes_in_group("loot"):
        l.queue_free()
    for a in get_tree().get_nodes_in_group("asteroids"):
        a.queue_free()
    _despawn_npc_ships()
    _spawn.clear_pois()

    loaded_system = sys_id
    if starfield:
        starfield.mark_dirty()
    GameManager.current_system = sys_id
    if hud_control:
        hud_control.loaded_system_id = sys_id
    if sys_id not in GameManager.visited_systems:
        GameManager.visited_systems.append(sys_id)


    # expand_frontier used to lazy-expand procedural systems around the
    # player; with procedural generation deleted, all systems are
    # pack-authored and the call is a noop.

    _spawn.spawn_system_pois(sys_id)
    if _should_spawn_procedural_asteroids(sys_id):
        _spawn.spawn_asteroid_fields(sys_id)
    if not creative_test_flying:
        if _should_spawn_procedural_npcs(sys_id):
            _spawn.spawn_npc_ships(sys_id)
        _spawn.spawn_placed_npcs(sys_id)

    _rebuild_proximity_bands_for_system(sys_id)
    if MvTriggerEngine != null:
        MvTriggerEngine.fire_event("space_system_enter", {"system_id": sys_id})

    # Drain any ship spawns queued by MV-side triggers for this system.
    # Authors push these via the space_spawn_ship_on_return action — the
    # ship class id is spawned at the system center using the standard
    # enemy spawn manager (matching the spawn_space_ship action's anchor
    # = "system" with no offset).
    if PlanetaryInterface != null and PlanetaryInterface.has_method("consume_ship_spawn_queue") and _spawn != null:
        var queued: Array = PlanetaryInterface.consume_ship_spawn_queue(sys_id)
        var sys_center: Vector2 = system_world_positions.get(sys_id, Vector2.ZERO)
        for class_v in queued:
            var class_id: String = str(class_v).strip_edges()
            if not class_id.is_empty():
                _spawn.spawn_enemy_ship(sys_center, class_id, false, 0.0)


    in_combat = false
    combat_timer = 0.0

    if hud_control:
        var sys = DataManager.systems.get(sys_id, {})
        hud_control.system_name = sys.get("name", "Unknown")

func _find_nearest_system(world_pos: Vector2) -> String:

    var best_id: String = ""
    var best_dist: float = INF
    for sys_id in system_world_positions:
        var d = world_pos.distance_to(system_world_positions[sys_id])
        if d < best_dist:
            best_dist = d
            best_id = sys_id
    return best_id

func _update_current_system():



    if not player or not is_instance_valid(player):
        return
    var check_pos: Vector2 = player.global_position
    var nearest = _find_nearest_system(check_pos)
    if nearest != "" and nearest != loaded_system:
        var dist_to_new = check_pos.distance_to(system_world_positions[nearest])
        var dist_to_current = INF
        if loaded_system != "" and system_world_positions.has(loaded_system):
            dist_to_current = check_pos.distance_to(system_world_positions[loaded_system])

        if dist_to_new < 30000.0 and dist_to_current > 40000.0:
            _load_system_content(nearest)


    if nearest != "":
        player.nearest_star_pos = system_world_positions[nearest]
        var _sys_data = DataManager.systems.get(nearest, {})
        player.nearest_star_radius = _sys_data.get("star_size", 60) * 20.0
        GameManager.near_star = player.global_position.distance_to(system_world_positions[nearest]) < 6000.0

func _on_creative_mode():
    _cmc.on_creative_mode()

@warning_ignore("unused_private_class_variable")
var _creative_saved_fuel: float = 0.0
@warning_ignore("unused_private_class_variable")
var _creative_saved_credits: int = 0

func _on_test_fly():
    _cmc.on_test_fly()

func _on_creative_test_fly(placed: Array, core_id: String):
    _creative_runtime_source = "builder"
    _cmc.on_creative_test_fly(placed, core_id)

func _on_record_ai_requested(placed: Array, core_id: String, template_name: String):
    _creative_runtime_source = "builder"
    _cmc.on_record_ai_requested(placed, core_id, template_name)

func _spawn_warp_portal(pos: Vector2, ship: Node2D, start_waves: bool = false):
    var portal = Node2D.new()
    portal.set_script(warp_portal_script)
    portal.global_position = pos
    add_child(portal)
    portal.setup(ship.ship_size if ship else 20.0, ship)
    if start_waves:
        portal.finished.connect(_cmc.spawn_test_fly_waves)

func _discard_recording_and_return():
    _cmc.discard_recording_and_return()

func _end_creative_test_fly():
    _cmc.end_creative_test_fly()

func _end_ai_preview():
    _cmc.end_ai_preview()

func _advance_training_round():
    _cmc.advance_training_round()

func _start_training_naming():
    _cmc.start_training_naming()

func _cancel_training_naming():
    _cmc.cancel_training_naming()

var _fight_ai_active: bool = false
@warning_ignore("unused_private_class_variable")
var _fight_ai_clone: Node2D = null

func _on_fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String):
    _cmc.on_fight_ai_requested(placed, core_id, template_name, recording_path)

func _end_fight_ai():
    _cmc.end_fight_ai()

# The procedural "New Game" flow (_on_new_game / _finalize_new_game) and
# the hardcoded intro sequence that it triggered (warp portal, drift,
# intro.json dialogue, intro interceptors) used to live here. Both were
# the only path through DataManager.generate_new_galaxy + the engine-level
# galaxy_generator.gd; gameplay now enters exclusively through the pack
# picker in main_menu, which loads authored systems.json. Author intros
# as ECA rules on the `game_started` event in the active pack instead.

func _on_load_slot(slot: int):
    menu_open = false
    GameManager.skip_main_menu = true
    if GameManager.load_game(slot):
        get_tree().paused = false
        get_tree().reload_current_scene()
    else:
        get_tree().paused = false

func _on_pause_resumed():
    pause_open = false

    get_tree().paused = time_frozen

func _on_pause_load():
    pause_open = false
    GameManager.skip_main_menu = true
    if GameManager.load_game():
        get_tree().paused = false
        get_tree().reload_current_scene()
    else:

        pause_open = true
        pause_menu.open_menu()

func _on_quit_to_menu():

    pause_open = false
    time_frozen = false
    _reset_mv_runtime_for_launcher()
    GameManager.skip_main_menu = false
    GameManager.reset_to_new_game()
    DataManager.systems = {}
    DataManager.galaxy_data = {}
    DataManager.galaxy_seed = 0
    get_tree().paused = false
    get_tree().reload_current_scene()

func _on_game_hour_changed(_hour: int, _day: int, _month: int, _year: int):

    GameManager.tick_npc_jobs_hourly()

func _on_game_day_changed(_day: int, _month: int, _year: int):

    GameManager.tick_npc_daily_wages()
    GameManager.tick_npc_population_movement()
    GameManager.tick_npc_contracts()
    GameManager.tick_npc_colonies()


func _toggle_editor(pack_id: String = "demo"):
    if editor_open or builder_open or star_map_open or jumping or event_open:
        return
    _editor_active_pack_id = pack_id
    _editor_active_region_id = ""
    _editor_return_to_content_hub = false
    _content_editor_return_mode = "campaign"
    if menu_open and main_menu:
        main_menu.visible = false
    UIPanels.load_pack_theme(pack_id)
    _apply_pack_systems(pack_id)
    content_editor.open_editor(pack_id)
    editor_open = true

func _on_editor_closed():
    editor_open = false
    _editor_return_to_content_hub = false
    _content_editor_return_mode = "campaign"
    _editor_active_pack_id = ""
    _editor_active_region_id = ""
    if menu_open and main_menu:
        main_menu.reopen_editor_picker()

    if player and is_instance_valid(player) and not GameManager.ship_modules.is_empty():
        player.apply_loadout(GameManager.ship_modules)

func _on_planet_entered(data: Dictionary):
    if on_surface or jumping or builder_open or star_map_open or event_open or editor_open:
        return
    if region_picker != null and region_picker.has_method("is_open") and region_picker.is_open():
        return
    _open_region_picker_for_poi(data)


# Resolves the POI's planet_data into a picker invocation. Pulls the pack id
# off planet_data (Phase 6 will populate it on the authored side; for now we
# fall back to the active pack so test/dev sessions keep working). Builds a
# synthetic single-region list out of RegIO if the POI has no authored
# regions[] entry yet — Phase 6 rewrites packs to populate this field.
func _open_region_picker_for_poi(data: Dictionary) -> void:
    var pack_id: String = _resolve_planet_pack_id(data)
    if pack_id.is_empty():
        push_error("PlanetaryInterface: planet POI has no resolvable pack_id")
        return
    var poi_id: String = str(data.get("poi_id", "")).strip_edges()
    if poi_id.is_empty():
        poi_id = str(data.get("planet_key", "")).strip_edges()
    var poi_name: String = str(data.get("poi_name", data.get("name", ""))).strip_edges()
    var regions: Array = _resolve_landing_regions(pack_id, data)

    var pending: Dictionary = data.duplicate(true)
    pending["pack_id"] = pack_id
    pending["poi_id"] = poi_id
    pending["poi_name"] = poi_name
    _region_picker_pending_data = pending
    _region_picker_poi = _find_planet_poi_for_data(data)

    if region_picker == null:
        push_error("UI: region picker not mounted — cannot open landing prompt")
        return
    region_picker.call("open", pack_id, poi_id, poi_name, regions)


# Returns the regions[] entries declared in planet_data, or a synthetic
# single-entry array built from RegIO defaults if the POI has none (Phase 6
# packs will populate the field; pre-Phase-6 packs need this fallback so the
# picker doesn't show "No landable regions" against a perfectly valid pack).
func _resolve_landing_regions(pack_id: String, data: Dictionary) -> Array:
    var regions_v: Variant = data.get("regions", null)
    if regions_v == null:
        var planet_v: Variant = data.get("planet_data", null)
        if typeof(planet_v) == TYPE_DICTIONARY:
            regions_v = (planet_v as Dictionary).get("regions", null)
    if typeof(regions_v) == TYPE_ARRAY:
        var out: Array = []
        for entry_v in (regions_v as Array):
            if typeof(entry_v) == TYPE_DICTIONARY:
                out.append((entry_v as Dictionary).duplicate(true))
        if not out.is_empty():
            return out

    var default_region: String = RegIO.default_region_id(pack_id)
    if default_region.is_empty():
        return []
    var spawn_room: String = RegIO.get_region_start_room(pack_id, default_region)
    var fallback: Dictionary = {
        "id": default_region,
        "name": default_region.capitalize(),
        "spawn_room": spawn_room,
    }
    return [fallback]


# Walks the live POI cache looking for the marker whose planet_data matches
# the dict we were handed. Used so the picker can auto-close if the player
# drifts out of range while it's open.
func _find_planet_poi_for_data(data: Dictionary) -> Node2D:
    var planet_key: String = str(data.get("planet_key", "")).strip_edges()
    var poi_name: String = str(data.get("poi_name", data.get("name", ""))).strip_edges()
    for poi in _cached_pois:
        if not is_instance_valid(poi):
            continue
        if not ("planet_data" in poi):
            continue
        var pd_v: Variant = poi.planet_data
        if typeof(pd_v) != TYPE_DICTIONARY:
            continue
        var pd: Dictionary = pd_v
        if not planet_key.is_empty() and str(pd.get("planet_key", "")).strip_edges() == planet_key:
            return poi
        if not poi_name.is_empty() and "poi_name" in poi and str(poi.poi_name) == poi_name:
            return poi
    return null


# Picker confirmed — stage the landing and hand off to the existing MV
# landing flow. region is the dict the picker emitted (copy of the entry
# from planet_data.regions[] or the synthetic RegIO fallback).
func _on_region_picker_chosen(pack_id: String, poi_id: String, region: Dictionary) -> void:
    _region_picker_poi = null
    var pending: Dictionary = _region_picker_pending_data
    _region_picker_pending_data = {}
    if region.is_empty() or pack_id.is_empty():
        return
    var region_id: String = str(region.get("id", "")).strip_edges()
    var spawn_room: String = str(region.get("spawn_room", "")).strip_edges()
    if spawn_room.is_empty() and not region_id.is_empty():
        spawn_room = RegIO.get_region_start_room(pack_id, region_id)
    _trigger_landing(pack_id, poi_id, region_id, spawn_room, pending)


func _on_region_picker_cancelled() -> void:
    _region_picker_poi = null
    _region_picker_pending_data = {}

# Main-menu TEST PLANET button. Lands on the demo pack inside the planet
# viewport. SSB stays paused (MVMania runs via the planet layer's always-
# process inheritance) so we don't need to spin up a real space session.
# On launch, we return to the menu instead of dropping into uninitialized
# space gameplay (tracked via _entered_planet_from_menu).
func _on_test_planet():
    _entered_planet_from_menu = menu_open
    _planet_visit_from_space_session = false
    _entered_authored_pack_from_menu = false
    if menu_open:
        menu_open = false
    if main_menu:
        main_menu.visible = false
    var demo_region: String = RegIO.default_region_id("demo")
    var demo_room: String = RegIO.get_region_start_room("demo", demo_region)
    _trigger_landing("demo", "", demo_region, demo_room,
        {"pack_id": "demo", "name": "Test Planet"})


func _on_play_pack(pack_id: String):
    if pack_id.is_empty():
        return
    MvPackLoader.clear_runtime_state()
    MvPackLoader.reset_last_loaded_pack_id()
    if _planet_iface == null:
        _planet_iface = get_node_or_null("/root/PlanetaryInterface")
    if _planet_iface != null and _planet_iface.has_method("reset_runtime_state"):
        # "New Game" from the pack menu must not inherit any pending or cached
        # planet snapshot, otherwise MV boots as a restore and skips the
        # authored new_game_started trigger chain.
        _planet_iface.call("reset_runtime_state", true, true)
    _entered_planet_from_menu = true
    _planet_visit_from_space_session = false
    _entered_authored_pack_from_menu = true
    menu_open = false
    if main_menu:
        main_menu.visible = false
    var manifest: Dictionary = _load_pack_manifest(pack_id)
    var start_region: String = str(manifest.get("start_region", "")).strip_edges()
    if start_region.is_empty():
        start_region = RegIO.default_region_id(pack_id)
    var entry_room: String = str(manifest.get("entry_room", "")).strip_edges()
    if entry_room.is_empty():
        entry_room = RegIO.get_region_start_room(pack_id, start_region)
    _trigger_landing(pack_id, "", start_region, entry_room, {
        "pack_id": pack_id,
        "name": pack_id,
    })

# Main-menu EDITOR chooser callback. Fires after the user picks a campaign
# pack AND a sub-editor. "ship" now opens the pack authoring hub for that
# campaign; the rest open specific pack-aware editors directly.
func _on_editor_chosen(kind: String, pack_id: String):
    match kind:
        "ship":
            _toggle_editor(pack_id)
        "entity":
            _open_mv_editor(entity_editor, pack_id)
        "behavior":
            _open_mv_editor(behavior_editor, pack_id)
        "theme":
            _open_mv_editor(theme_editor, pack_id)
        "audio":
            _open_mv_editor(audio_editor, pack_id)
        "player":
            _open_mv_editor(player_editor, pack_id)
        "system":
            _open_mv_editor(system_editor, pack_id)
        "ships":
            _open_mv_editor(ship_editor, pack_id)
        "modules":
            _open_mv_editor(modules_editor, pack_id)
        "loot":
            _open_mv_editor(loot_editor, pack_id)
        "trigger":
            _open_mv_editor(trigger_editor, pack_id)
        "dialogue":
            _open_mv_editor(dialogue_editor, pack_id)
        "shop":
            _open_mv_editor(shop_editor, pack_id)
        "quest":
            _open_mv_editor(quest_editor, pack_id)
        _:
            push_warning("main._on_editor_chosen: unknown kind '%s'" % kind)

func _open_mv_editor(target: Node, pack_id: String):
    if target == null:
        return
    # Editor layer uses PROCESS_MODE_ALWAYS, so we can leave the tree paused
    # and still have the editor's _process/_gui_input run. Just hide the menu
    # and flag editor_open so nothing else in SSB tries to grab input.
    if main_menu:
        main_menu.visible = false
    # Swap to the pack's UI theme so all editor chrome reflects the active
    # pack's palette/9-slice art.
    UIPanels.load_pack_theme(pack_id)
    _apply_pack_systems(pack_id)
    target.open_editor(pack_id)
    editor_open = true


func _on_content_editor_editor_requested(kind: String, pack_id: String) -> void:
    _editor_active_pack_id = pack_id
    _editor_active_region_id = ""
    _editor_return_to_content_hub = true
    if content_editor != null and content_editor.has_method("current_mode"):
        _content_editor_return_mode = str(content_editor.current_mode())
    match kind:
        "entity":
            _open_mv_editor(entity_editor, pack_id)
        "behavior":
            _open_mv_editor(behavior_editor, pack_id)
        "theme":
            _open_mv_editor(theme_editor, pack_id)
        "audio":
            _open_mv_editor(audio_editor, pack_id)
        "player":
            _open_mv_editor(player_editor, pack_id)
        "system":
            _open_mv_editor(system_editor, pack_id)
        "ships":
            _open_mv_editor(ship_editor, pack_id)
        "modules":
            _open_mv_editor(modules_editor, pack_id)
        "loot":
            _open_mv_editor(loot_editor, pack_id)
        "trigger":
            _open_mv_editor(trigger_editor, pack_id)
        "dialogue":
            _open_mv_editor(dialogue_editor, pack_id)
        "shop":
            _open_mv_editor(shop_editor, pack_id)
        "quest":
            _open_mv_editor(quest_editor, pack_id)
        "factions":
            _open_mv_editor(factions_editor, pack_id)
        _:
            _editor_return_to_content_hub = false
            push_warning("main._on_content_editor_editor_requested: unknown kind '%s'" % kind)

func _on_content_editor_playtest_requested(pack_id: String) -> void:
    _editor_return_to_content_hub = false
    _content_editor_return_mode = "playtest"
    _editor_active_pack_id = pack_id
    _editor_active_region_id = ""
    editor_open = false
    if content_editor != null:
        content_editor.visible = false
    _on_play_pack(pack_id)

func _leave_editor_shell_for_runtime() -> void:
    _editor_return_to_content_hub = false
    editor_open = false
    menu_open = false
    get_tree().paused = false
    if main_menu != null:
        main_menu.visible = false
    if content_editor != null:
        content_editor.visible = false
    if system_editor != null:
        system_editor.visible = false
    if ship_editor != null:
        ship_editor.visible = false
    if starfield != null:
        starfield.mark_dirty()
    if _world_renderer != null:
        _world_renderer.queue_redraw()


func _on_ship_editor_test_fly_requested(placed: Array, core_id: String) -> void:
    _creative_runtime_source = "ship_editor"
    _leave_editor_shell_for_runtime()
    _cmc.on_creative_test_fly(placed, core_id)


func _on_ship_editor_record_ai_requested(placed: Array, core_id: String, template_name: String) -> void:
    _creative_runtime_source = "ship_editor"
    _leave_editor_shell_for_runtime()
    _cmc.on_record_ai_requested(placed, core_id, template_name)


func _on_ship_editor_fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String) -> void:
    _creative_runtime_source = "ship_editor"
    _leave_editor_shell_for_runtime()
    _cmc.on_fight_ai_requested(placed, core_id, template_name, recording_path)


func _resume_creative_authoring(core_id: String, placed: Array) -> void:
    if death_screen != null:
        death_screen.visible = false
    if _creative_runtime_source == "ship_editor" and ship_editor != null:
        if main_menu != null:
            main_menu.visible = false
        editor_open = true
        builder_open = false
        GameManager.builder_open = false
        menu_open = false
        get_tree().paused = false
        UIPanels.load_pack_theme(_editor_active_pack_id)
        ship_editor.open_editor(_editor_active_pack_id)
        if ship_editor.has_method("resume_builder_state"):
            ship_editor.resume_builder_state(placed, core_id)
        return
    creative_mode_active = true
    builder.open_creative_builder(core_id)
    builder.placed_modules = placed.duplicate(true)
    if builder.has_method("compute_power_routing"):
        builder.compute_power_routing()
    builder.queue_redraw()
    builder_open = true
    GameManager.builder_open = true


func _on_mv_editor_closed():
    editor_open = false
    if _editor_return_to_content_hub and content_editor != null:
        _editor_return_to_content_hub = false
        UIPanels.load_pack_theme(_editor_active_pack_id)
        content_editor.open_editor(_editor_active_pack_id, _content_editor_return_mode)
        editor_open = true
        return
    # Return to the editor picker modal instead of dropping to main menu.
    if main_menu and menu_open:
        main_menu.reopen_editor_picker()


func _on_system_editor_saved(pack_id: String, _systems: Dictionary) -> void:
    _apply_pack_systems(pack_id)


# Region editor opened from the POI detail panel. system_editor stays open
# underneath; closing the region editor returns there.
func _open_region_editor_from_system(pack_id: String, region_id: String) -> void:
    if region_editor == null:
        return
    _editor_active_pack_id = pack_id
    _editor_active_region_id = region_id
    if system_editor != null:
        system_editor.visible = false
    region_editor.open_editor(pack_id, region_id)


# Region → pack (close button or BACK). Returns to whichever surface opened
# the region editor: the POI detail panel if system_editor is active, else
# the mv-editor close path.
func _on_region_back_to_pack():
    _editor_active_region_id = ""
    region_editor.visible = false
    if system_editor != null:
        UIPanels.load_pack_theme(_editor_active_pack_id)
        system_editor.open_editor(_editor_active_pack_id)
        editor_open = true
        return
    _on_mv_editor_closed()


# Region → main menu (direct close path; currently unreachable through the UI
# since region only exposes BACK, but wired for completeness).
func _on_region_closed():
    if not _editor_return_to_content_hub:
        _editor_active_pack_id = ""
    _editor_active_region_id = ""
    _on_mv_editor_closed()


# Region → env. User double-clicked a room in region_editor.
func _on_region_room_chosen(region_id: String, room_addr: String):
    _editor_active_region_id = region_id
    region_editor.visible = false
    environment_editor.open_editor(_editor_active_pack_id, region_id, room_addr)


# Called from _ready after _setup_editor. When MvMain's Ctrl+9 return
# handler scene-changes back to Space, PlanetaryInterface.pending_return_to_editor
# is set and the pack/region/room triple is stashed. Re-open the env editor at
# that exact spot instead of dropping the user on the main menu.
# Shipped builds carry a res://shipped_pack.json at the project root
# saying which pack the binary is glued to. When present, skip the dev
# main menu entirely and call _start_play_pack_menu on the pack id so
# the player lands directly on that pack's authored main_menu screen.
# Deferred because setup is still finishing — the dev main_menu hasn't
# finished its first _draw yet, and _start_play_pack_menu touches its
# _authored_screen child + sets _authored_pack_id. Empty / missing /
# malformed config: silently no-op (boot proceeds as a normal dev build).
func _auto_route_to_shipped_pack_if_any() -> void:
    var ui_script = preload("res://Space/scripts/ui/ui_coordinator.gd")
    if not ui_script.is_shipped_build():
        return
    var cfg: Dictionary = ui_script.read_shipped_pack_config()
    var pack_id: String = str(cfg.get("pack_id", "")).strip_edges()
    if pack_id.is_empty():
        push_warning("[main] shipped_pack.json missing pack_id — falling back to dev main menu.")
        return
    if main_menu == null:
        return
    # Suppress dev-menu interactivity while we wait for the deferred call.
    # The authored screen will overlay once load completes; the starfield
    # behind it is harmless ambient draw.
    menu_open = false
    main_menu._start_play_pack_menu.call_deferred(pack_id)


func _restore_editor_from_playtest_if_any() -> void:
    var pi = get_node_or_null("/root/PlanetaryInterface")
    if pi == null or not pi.pending_return_to_editor:
        return
    var info: Dictionary = pi.consume_return_to_editor()
    var pack_id: String = str(info.get("pack_id", ""))
    var region_id: String = str(info.get("region_id", ""))
    var room_addr: String = str(info.get("room_addr", ""))
    if pack_id.is_empty():
        return
    # Shipped builds have no editor; the playtest-return path is a
    # dev-only roundtrip from the environment editor, so the stash should
    # never even be set. Defensive guard in case PlanetaryInterface ends
    # up with stale state from a transferred save.
    if environment_editor == null:
        return
    if main_menu:
        main_menu.visible = false
    menu_open = false
    _editor_active_pack_id = pack_id
    _editor_active_region_id = region_id
    UIPanels.load_pack_theme(pack_id)
    editor_open = true
    environment_editor.open_editor.call_deferred(pack_id, region_id, room_addr)


# Env → region (or menu, if there's no active region context).
func _on_env_editor_closed():
    if _editor_active_region_id != "" and region_editor != null:
        region_editor.open_editor(_editor_active_pack_id, _editor_active_region_id)
        return
    _on_mv_editor_closed()

func _trigger_landing(pack_id: String, poi_id: String, region_id: String,
        spawn_room: String, data: Dictionary = {}) -> void:
    if planet_viewport == null:
        var pv = _ui.setup_planet_viewport()
        planet_viewport_layer = pv["layer"]
        planet_viewport_container = pv["container"]
        planet_viewport = pv["viewport"]
        planet_overlay_layer = pv["overlay_layer"]
        planet_overlay_root = pv["overlay_root"]

    # Stash orbital return position so the ship lifts off from where it landed.
    if player and is_instance_valid(player):
        surface_return_pos = player.position
    surface_data = data
    surface_entry_timer = SURFACE_TRANSITION_TIME

    # Resolve the planetary interface autoload + read the pending edit mode
    # flag so we know whether to size the planet viewport for gameplay
    # (480x270 pixel art) or for the MVMania editor (full 1920x1080 canvas).
    if _planet_iface == null:
        _planet_iface = get_node_or_null("/root/PlanetaryInterface")
    if _planet_iface == null:
        push_error("PlanetaryInterface autoload missing — cannot land")
        return
    var edit_mode: bool = _planet_iface.pending_edit_mode

    var pid: String = pack_id.strip_edges()
    if pid.is_empty():
        push_error("PlanetaryInterface: _trigger_landing called without pack_id")
        return
    var manifest: Dictionary = _load_pack_manifest(pid)
    if manifest.is_empty():
        push_error("PlanetaryInterface: pack '%s' has no readable Pack.json" % pid)
        return

    var resolved_region: String = region_id.strip_edges()
    if resolved_region.is_empty():
        resolved_region = RegIO.default_region_id(pid)
    var resolved_room: String = spawn_room.strip_edges()
    if resolved_room.is_empty() and not resolved_region.is_empty():
        resolved_room = RegIO.get_region_start_room(pid, resolved_region)

    _planet_iface.begin_landing(pid, poi_id, resolved_region, resolved_room)

    # The planet SubViewport always renders at native 1920x1080 now
    # (stretch_shrink=1). MVMania frames gameplay via Camera2D zoom rather than a
    # 480x270 downscale, so both the game and its editor get the full canvas.
    planet_viewport_container.stretch_shrink = 1
    # Force a resort so the SubViewport's size is recomputed from the new
    # stretch_shrink value — Godot's SubViewportContainer only updates the
    # inner size on NOTIFICATION_SORT_CHILDREN.
    planet_viewport_container.queue_sort()

    # Tear down any stale MVMania instance before loading a new one.
    _teardown_planet_instances()
    _enter_mv_for_pack()

    _surface_death_blocked = false
    on_surface = true
    _set_space_simulation_surface_locked(true)
    planet_viewport_container.visible = true
    if player: player.visible = false
    if hud_control: hud_control.visible = false
    get_tree().paused = true

    AudioManager.set_ambient_varied("surface")
    print("PlanetaryInterface: landed on pack='%s' region='%s' room='%s' edit_mode=%s" % [
        pid, resolved_region, resolved_room, edit_mode])

func _on_launch_requested(_pack_id: String):
    _teardown_planet_instances()
    if planet_viewport_container:
        planet_viewport_container.visible = false
        # Reset to gameplay scale so the next landing renders pixel art
        # correctly even after an editor visit.
        planet_viewport_container.stretch_shrink = 4
        planet_viewport_container.queue_sort()
    _clear_planet_overlay()

    _surface_death_blocked = false
    on_surface = false
    surface_exit_timer = SURFACE_TRANSITION_TIME

    if hud_control:
        hud_control.on_surface = false
    AudioManager.set_ambient_varied("space")
    queue_redraw()

    if not _planet_visit_from_space_session:
        if _entered_authored_pack_from_menu and _bootstrap_authored_space_session(_pack_id):
            _entered_planet_from_menu = false
            _planet_visit_from_space_session = false
            _entered_authored_pack_from_menu = false
            print("PlanetaryInterface: launched into authored space session for '%s'" % _pack_id)
            return
        # Came from the main menu (TEST PLANET or EDITOR button) — bounce
        # back to the menu instead of dropping into an uninitialized space
        # session. Tree stays paused, menu re-shows.
        _entered_planet_from_menu = false
        _planet_visit_from_space_session = false
        _entered_authored_pack_from_menu = false
        menu_open = true
        if main_menu:
            main_menu.visible = true
        if player:
            player.visible = false
        if hud_control:
            hud_control.visible = false
        _set_space_simulation_surface_locked(true)
        get_tree().paused = true
        print("PlanetaryInterface: launched back to main menu from '%s'" % _pack_id)
        return

    # Real return to space — unpause and restore the ship at its orbital position.
    _entered_planet_from_menu = false
    _planet_visit_from_space_session = false
    _entered_authored_pack_from_menu = false
    get_tree().paused = false
    _set_space_simulation_surface_locked(false)
    if player and is_instance_valid(player):
        player.position = surface_return_pos
        player.velocity = Vector2.ZERO
        player.visible = true
    if hud_control:
        hud_control.visible = true
    # Save checkpoint so Retry returns to orbit instead of a stale pre-landing state.
    GameManager.save_game(GameManager.current_save_slot)
    print("PlanetaryInterface: launched from pack='%s'" % _pack_id)


func _bootstrap_authored_space_session(pack_id: String) -> bool:
    var pid: String = pack_id.strip_edges()
    if pid.is_empty() or not SystemIO.exists(pid):
        return false

    var manifest: Dictionary = _load_pack_manifest(pid)
    var start_system: String = str(manifest.get("start_system", "")).strip_edges()
    GameManager.skip_main_menu = true
    GameManager.current_system = start_system
    GameManager.visited_systems = [start_system] if not start_system.is_empty() else []

    var starter_path: String = _resolve_start_ship_template_path(manifest)
    if not starter_path.is_empty():
        GameManager.start_template_path = starter_path
    GameManager.reset_to_new_game()
    GameManager.current_system = start_system
    GameManager.visited_systems = [start_system] if not start_system.is_empty() else []

    menu_open = false
    if main_menu:
        main_menu.visible = false

    _apply_pack_systems(pid)
    if GameManager.current_system.is_empty() or not DataManager.systems.has(GameManager.current_system):
        return false
    if GameManager.visited_systems.is_empty():
        GameManager.visited_systems = [GameManager.current_system]

    get_tree().paused = false
    _set_space_simulation_surface_locked(false)

    var start_pos: Vector2 = system_world_positions.get(GameManager.current_system, Vector2.ZERO)
    var start_sys: Dictionary = DataManager.systems.get(GameManager.current_system, {})
    var start_star_r: float = float(start_sys.get("star_size", 60)) * 20.0
    start_pos += Vector2(start_star_r + 2000.0, 0.0)
    if player and is_instance_valid(player):
        player.position = start_pos
        player.velocity = Vector2.ZERO
        player.visible = true
        player.nearest_star_pos = system_world_positions.get(GameManager.current_system, Vector2.ZERO)
    if hud_control:
        hud_control.on_surface = false
        hud_control.visible = true
    loaded_system = ""
    _load_system_content(GameManager.current_system)
    _apply_initial_loadout()
    # Save checkpoint so authored-pack deaths can retry from the spawned starter ship.
    GameManager.save_game(GameManager.current_save_slot)
    return true


func _resolve_start_ship_template_path(manifest: Dictionary) -> String:
    var starter_id: String = _normalize_template_id(str(manifest.get("start_ship_template", "")))
    if starter_id.is_empty():
        return ""
    if GameManager.has_method("get_template_list"):
        for entry_v in GameManager.get_template_list():
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_v
            var entry_id: String = _normalize_template_id(str(entry.get("filename", "")))
            if entry_id.is_empty():
                entry_id = _normalize_template_id(str(entry.get("path", "")))
            if entry_id.is_empty():
                entry_id = _normalize_template_id(str(entry.get("name", "")))
            if entry_id == starter_id:
                return str(entry.get("path", ""))
    var builtin_path := "res://Space/data/npc_templates/%s.json" % starter_id
    if FileAccess.file_exists(builtin_path):
        return builtin_path
    return ""


static func _normalize_template_id(value: String) -> String:
    var trimmed := value.strip_edges()
    if trimmed.is_empty():
        return ""
    if trimmed.contains("/"):
        trimmed = trimmed.get_file()
    if trimmed.ends_with(".json"):
        trimmed = trimmed.get_basename()
    return trimmed


func _close_mv_runtime_overlays() -> void:
    var cinematic_script := preload("res://Space/scripts/ui/cinematic_overlay.gd")
    var cinematic_overlay = cinematic_script.instance()
    if cinematic_overlay != null and cinematic_overlay.has_method("close_cinematic"):
        cinematic_overlay.call("close_cinematic")

    var mv_hud := get_node_or_null("/root/MvHud")
    if mv_hud != null:
        mv_hud.visible = false

    for node_name in ["MvInventoryScreen", "MvMapScreen", "MvShopUI"]:
        var ui_node := get_node_or_null("/root/%s" % node_name)
        if ui_node == null:
            continue
        if ui_node.has_method("close"):
            ui_node.call("close")
        else:
            ui_node.visible = false
            ui_node.set("_active", false)

    var dialogue_runner := get_node_or_null("/root/MvDialogueRunner")
    if dialogue_runner != null:
        if dialogue_runner.has_method("stop"):
            dialogue_runner.call("stop")
        else:
            dialogue_runner.visible = false
            dialogue_runner.set("_active", false)

    var game_over := get_node_or_null("/root/MvGameOver")
    if game_over != null:
        game_over.visible = false
        game_over.set("_active", false)
        var authored_screen = game_over.get("_authored_screen")
        if authored_screen != null and authored_screen.has_method("clear_screen"):
            authored_screen.call("clear_screen")
            authored_screen.visible = false

    if has_node("/root/MvGame"):
        MvGame.simulation_paused = false


func _reset_mv_runtime_for_launcher() -> void:
    _teardown_planet_instances()
    if planet_viewport_container:
        planet_viewport_container.visible = false
        planet_viewport_container.stretch_shrink = 4
        planet_viewport_container.queue_sort()
    _clear_planet_overlay()
    on_surface = false
    surface_data = {}
    surface_entry_timer = 0.0
    surface_exit_timer = 0.0
    _entered_planet_from_menu = false
    _planet_visit_from_space_session = false
    _entered_authored_pack_from_menu = false
    _surface_death_blocked = false
    if player and is_instance_valid(player):
        player.visible = false
    if hud_control:
        hud_control.visible = false
        hud_control.on_surface = false
    if _planet_iface == null:
        _planet_iface = get_node_or_null("/root/PlanetaryInterface")
    if _planet_iface != null and _planet_iface.has_method("reset_runtime_state"):
        _planet_iface.call("reset_runtime_state", true, true)
    MvPackLoader.clear_runtime_state()
    if has_node("/root/MvGame"):
        MvGame.main = null
        MvGame.room_manager = null
        MvGame.simulation_paused = false


func _teardown_planet_instances() -> void:
    _close_mv_runtime_overlays()
    _surface_death_blocked = false
    _clear_planet_overlay()
    if planet_main_instance and is_instance_valid(planet_main_instance):
        if planet_main_instance.has_method("prepare_for_teardown"):
            planet_main_instance.call("prepare_for_teardown")
        planet_main_instance.queue_free()
        planet_main_instance = null


func _clear_planet_overlay() -> void:
    if _planet_overlay_hud and is_instance_valid(_planet_overlay_hud):
        _planet_overlay_hud.queue_free()
    _planet_overlay_hud = null
    if planet_overlay_root:
        planet_overlay_root.visible = false
    if planet_overlay_layer:
        planet_overlay_layer.visible = false


func _enter_mv_for_pack() -> void:
    _clear_planet_overlay()
    var mv_scene: PackedScene = load("res://MV/scenes/main.tscn") as PackedScene
    if mv_scene == null:
        push_error("PlanetaryInterface: failed to load res://MV/scenes/main.tscn")
        return
    planet_main_instance = mv_scene.instantiate()
    planet_main_instance.process_mode = Node.PROCESS_MODE_ALWAYS
    planet_viewport.add_child(planet_main_instance)


func _resolve_planet_pack_id(data: Dictionary) -> String:
    var pack_id := str(data.get("pack_id", "")).strip_edges()
    if not pack_id.is_empty():
        return pack_id
    if MvPackLoader.current_pack != null:
        var current_pack_id := str(MvPackLoader.current_pack.pack_id).strip_edges()
        if not current_pack_id.is_empty():
            return current_pack_id
    # No pack_id on the POI data and no current pack loaded. Falling back to the
    # demo pack is expected when entering a planet straight from the main menu;
    # reaching here on an in-game landing means the POI is missing its pack_id.
    if not _entered_planet_from_menu:
        push_warning("_resolve_planet_pack_id: no pack_id in data and no current pack — defaulting to 'demo' (POI likely missing pack_id)")
    return "demo"


func _load_pack_manifest(pack_id: String) -> Dictionary:
    for path in [
        PackPaths.writable_pack_file(pack_id, "Pack.json"),
        PackPaths.shipped_pack_file(pack_id, "Pack.json"),
    ]:
        if not FileAccess.file_exists(path):
            continue
        var file: FileAccess = FileAccess.open(path, FileAccess.READ)
        if file == null:
            continue
        var parsed: Variant = JSON.parse_string(file.get_as_text())
        file.close()
        if typeof(parsed) == TYPE_DICTIONARY:
            return parsed
    return {}


func _enter_surface(data: Dictionary):
    surface_data = data
    surface_seed = randf() * 1000.0

    if player and is_instance_valid(player):
        surface_return_pos = player.position
    surface_entry_timer = SURFACE_TRANSITION_TIME
    surface_exit_timer = 0.0
    on_surface = true
    _set_space_simulation_surface_locked(true)


    for e in _cached_enemies:
        e.queue_free()
    for l in get_tree().get_nodes_in_group("loot"):
        l.queue_free()
    _spawn.clear_pois()


    if player and is_instance_valid(player):
        player.position = Vector2.ZERO
        player.velocity = Vector2.ZERO


    _spawn_surface_enemies()
    _spawn_surface_pois()
    _spawn_npc_colony_poi()


    if hud_control:
        hud_control.system_name = surface_data.get("name", "Planet Surface")
        hud_control.on_surface = true
    AudioManager.set_ambient_varied("surface")

func _spawn_surface_enemies():
    var turret_range = surface_data.get("turret_count", [2, 4])
    var turret_count = randi_range(int(turret_range[0]), int(turret_range[1]))
    for i in turret_count:
        var turret = Area2D.new()
        turret.set_script(turret_script)

        var angle = randf() * TAU
        var dist = randf_range(400, SURFACE_RADIUS * 0.8)
        turret.position = Vector2(cos(angle) * dist, sin(angle) * dist)
        add_child(turret)
        turret.died.connect(_on_enemy_died)


    var patrol_range = surface_data.get("patrol_count", [1, 2])
    var patrol_count = randi_range(int(patrol_range[0]), int(patrol_range[1]))
    var sys = DataManager.systems.get(GameManager.current_system, {})
    var threat = sys.get("threat_level", 1)
    for i in patrol_count:
        var enemy = enemy_scene.instantiate()
        var angle = randf() * TAU
        var dist = randf_range(500, SURFACE_RADIUS * 0.6)
        enemy.position = Vector2(cos(angle) * dist, sin(angle) * dist)
        add_child(enemy)
        enemy.setup_class(_spawn.pick_enemy_class(threat))
        enemy.died.connect(_on_enemy_died)

func _spawn_surface_pois():
    var spois: Array = surface_data.get("surface_pois", [])
    for i in spois.size():
        var sp = spois[i]
        var marker = Area2D.new()
        marker.set_script(poi_script)

        var angle = (float(i) / maxf(spois.size(), 1)) * TAU + surface_seed
        var dist = randf_range(600, SURFACE_RADIUS * 0.6)
        marker.position = Vector2(cos(angle) * dist, sin(angle) * dist)
        add_child(marker)
        marker.setup(sp, sp.get("event_id", ""))
        marker.interacted.connect(_on_poi_interacted)

func _spawn_npc_colony_poi():

    var planet_name = surface_data.get("name", "")
    if planet_name == "":
        return
    for col in GameManager.npc_colonies:
        if col.get("planet", "") != planet_name or col.get("system", "") != GameManager.current_system:
            continue

        var seed_val = col.get("id", "").hash()
        var rng = RandomNumberGenerator.new()
        rng.seed = seed_val
        var angle = rng.randf() * TAU
        var dist = rng.randf_range(300, SURFACE_RADIUS * 0.4)
        var colony_pos = Vector2(cos(angle) * dist, sin(angle) * dist)
        var col_name = col.get("name", "Settlement")
        var faction = col.get("faction", "independent")
        var tier = int(col.get("tier", 1))
        var pop = int(col.get("population", 5))

        var marker = Area2D.new()
        marker.set_script(poi_script)
        marker.position = colony_pos
        add_child(marker)
        var poi_data = {
            "name": col_name, 
            "type": "npc_colony", 
            "description": "%s colony — Pop: %d — Faction: %s" % [GameManager.COLONY_TIER_NAMES[tier] if tier < GameManager.COLONY_TIER_NAMES.size() else "Outpost", pop, faction.capitalize()], 
            "npc_colony_id": col.get("id", ""), 
        }
        marker.setup(poi_data, "npc_colony_trade_%s" % col.get("id", ""))
        marker.interacted.connect(_on_poi_interacted)
        marker.discovered = true

        var station_key = "colony_%s" % col.get("id", "")
        var stype = "trade"
        var sdata = GameManager.get_or_create_station(station_key, stype, seed_val)
        sdata["name"] = col_name
        sdata["faction"] = faction
        sdata["hostile"] = false
        var entity = Area2D.new()
        entity.set_script(station_entity_script)
        add_child(entity)
        entity.setup(sdata)
        entity.global_position = colony_pos
        entity.poi_marker = marker

        _register_npc_colony_event(col)
        break

func _register_npc_colony_event(col: Dictionary):

    var eid = "npc_colony_trade_%s" % col.get("id", "")
    if DataManager.events.has(eid):
        return
    var col_name = col.get("name", "Settlement")
    var faction = col.get("faction", "independent")
    var pop = int(col.get("population", 5))
    var credits = int(col.get("credits", 100))
    var buy_price = maxf(credits * 0.1, 10)
    DataManager.events[eid] = {
        "title": col_name, 
        "text": "A %s settlement with %d colonists. The settlers welcome traders.\n\nFaction: %s\nPopulation: %d\nTrade credits: %d" % [faction.capitalize(), pop, faction.capitalize(), pop, credits], 
        "choices": [
            {
                "text": "Trade — Sell 10 food for %d credits" % int(buy_price), 
                "effects": [{"type": "give_food", "amount": -10}, {"type": "give_credits", "amount": int(buy_price)}], 
            }, 
            {
                "text": "Trade — Buy fuel (50 credits)", 
                "effects": [{"type": "give_credits", "amount": -50}, {"type": "give_fuel", "amount": 20}], 
            }, 
            {
                "text": "Leave", 
                "effects": [], 
            }, 
        ], 
    }

func _exit_surface():
    on_surface = false
    surface_exit_timer = SURFACE_TRANSITION_TIME
    _set_space_simulation_surface_locked(false)


    for e in _cached_enemies:
        e.queue_free()
    for l in get_tree().get_nodes_in_group("loot"):
        l.queue_free()
    _spawn.clear_pois()
    for a in get_tree().get_nodes_in_group("asteroids"):
        a.queue_free()


    if player and is_instance_valid(player):
        player.position = surface_return_pos
        player.velocity = Vector2.ZERO


    var sys_id = GameManager.current_system
    loaded_system = sys_id
    _spawn.spawn_system_pois(sys_id)
    _spawn.spawn_asteroid_fields(sys_id)
    AudioManager.set_ambient_varied("space")
    if hud_control:
        hud_control.on_surface = false
    queue_redraw()



func _any_panel_open() -> bool:
    var picker_open: bool = region_picker != null \
        and region_picker.has_method("is_open") \
        and region_picker.is_open()
    return builder_open or star_map_open or event_open or editor_open or pause_open or picker_open

# In-game Space map editor (drag/place/rename/delete POIs). Console: `mapedit`.
func toggle_map_editor() -> void:
    if _map_editor != null:
        _map_editor.toggle()


# Open the ship builder for authoring (console `shipbuilder`), bypassing the
# near-a-station gameplay gate so you can build/test-fly anywhere while editing.
func open_ship_builder_authoring() -> void:
    if builder_open or star_map_open or jumping or event_open or editor_open:
        return
    builder.open_builder()
    builder_open = true
    GameManager.builder_open = true


func _toggle_builder():
    if builder_open or star_map_open or jumping or event_open or editor_open:
        return

    if not GameManager.has_construction_hangar() and not _near_station():
        if hud_control:
            hud_control.show_bark("SYSTEM", "Need a Construction Hangar or station to modify ship.", Color(0.9, 0.6, 0.2), 3.0)
        return
    builder.open_builder()
    builder_open = true
    GameManager.builder_open = true

func _near_station() -> bool:
    if not player or not is_instance_valid(player):
        return false
    for poi in _cached_pois:
        if not is_instance_valid(poi):
            continue
        if poi.poi_type in ["station", "hostile_station"]:
            if player.global_position.distance_to(poi.global_position) < 250:
                return true
    return false

func _toggle_star_map():
    if star_map_open or builder_open or jumping or event_open or editor_open:
        return

    if on_surface:
        _exit_surface()
        return

    # expand_frontier deleted — see _load_system_content for context.
    var player_data = player.global_position / WORLD_SCALE if player else Vector2.ZERO
    star_map.open_map(DataManager.systems, GameManager.current_system, player_data)
    star_map_open = true

func _on_builder_closed(placed: Array):
    builder_open = false
    GameManager.builder_open = false
    if creative_mode_active:
        creative_mode_active = false
        menu_open = true
        main_menu.visible = true
        get_tree().paused = true
        return
    GameManager.ship_modules = placed
    if player and is_instance_valid(player):
        player.apply_loadout(GameManager.ship_modules)
    GameManager.update_cargo_capacity()
    GameManager.update_resource_capacity()

func _on_star_map_closed():
    star_map_open = false

func _on_star_map_waypoint(world_pos: Vector2):
    if player and is_instance_valid(player):
        player.cmd_waypoint = world_pos
        player.cmd_has_waypoint = true
        player.cmd_orbit_target = null
        AudioManager.play_sfx("ui_click", 0.4)

func _dock_at_station():

    if _hail_station_key == "":
        return
    var s_key = _hail_station_key
    var s_name = _hail_station_name
    _hail_station_key = ""
    _hail_station_type = ""
    _hail_station_name = ""
    docked_station_key = s_key
    if player and is_instance_valid(player):
        player.velocity = Vector2.ZERO
    AudioManager.play_sfx("dock_clamp", 0.7)
    if hud_control:
        hud_control.show_bark("SYSTEM", "Docked at %s." % s_name, Color(0.4, 0.8, 0.5), 3.0)

const JUMP_FUEL_COST: float = 10.0

func _on_jump_requested(system_id: String):

    if GameManager.fuel < JUMP_FUEL_COST:
        if hud_control:
            hud_control.show_bark("SYSTEM", "Not enough fuel to jump! Need %d units." % int(JUMP_FUEL_COST), Color(0.9, 0.3, 0.2), 3.0)
        star_map_open = false
        return
    GameManager.consume_fuel(JUMP_FUEL_COST)
    star_map_open = false

    jumping = true
    jump_target = system_id
    jump_timer = 0.0
    AudioManager.play_sfx("jump_warp", 0.8)

func _on_poi_interacted(event_id: String):
    if event_open or builder_open or star_map_open or jumping or editor_open:
        return
    if MvTriggerEngine != null:
        MvTriggerEngine.fire_event("space_poi_interact", {
            "system_id": loaded_system,
            "event_id": event_id,
        })
    if event_id == "":
        return

    if not DataManager.events.has(event_id) and event_id.begins_with("proc_"):
        var poi_node = _find_poi_by_event_id(event_id)
        if poi_node:
            var sys_data = DataManager.systems.get(loaded_system, {})
            var rng = RandomNumberGenerator.new()
            rng.seed = event_id.hash()
            var event = DataManager.generate_proc_event(poi_node.poi_type, poi_node.poi_name, sys_data, rng)
            if not event.is_empty():
                DataManager.events[event_id] = event
    if not DataManager.events.has(event_id):
        return

    var actual_event_id = event_id
    var ev_data = DataManager.events.get(event_id, {})
    var first_id = ev_data.get("first_visit", "")
    if first_id != "" and DataManager.events.has(first_id):
        if not GameManager.visited_events.has(event_id):
            actual_event_id = first_id
    GameManager.visited_events[event_id] = true

    var poi_name: String = ""
    var poi_type: String = ""
    for poi in _cached_pois:
        if poi.event_id == event_id:
            poi.visited = true
            poi_name = poi.poi_name if "poi_name" in poi else ""
            poi_type = poi.poi_type if "poi_type" in poi else ""

    if actual_event_id in ["home_station", "home_station_first"] and poi_name != "":
        DataManager.events[actual_event_id]["title"] = poi_name

    _current_event_poi_id = event_id
    event_panel.open_event(DataManager.events, actual_event_id)
    event_open = true
    get_tree().paused = true

var _hail_npc_id: String = ""
var _hail_station_key: String = ""
var _hail_station_type: String = ""
var _hail_station_name: String = ""

func _hail_npc_ship(npc: Node2D):

    if event_open or builder_open or star_map_open:
        return
    var data = npc.get_hail_data()
    var _npc_name = data.get("name", "Ship")
    var _npc_type = data.get("type", "wanderer")
    var faction = data.get("faction", "independent")
    var _hostile = data.get("hostile", false)
    var disposition = GameManager.get_faction_disposition(faction)

    var factions = DataManager.galaxy_data.get("factions", {})
    var faction_name = factions.get(faction, {}).get("name", "Unknown")
    var rep = GameManager.get_reputation(faction)
    var event_id = "hail_%s" % data.get("npc_id", "unknown")
    _hail_npc_id = data.get("npc_id", "")

    var custom_hail: String = data.get("hail_event_id", "")
    if custom_hail != "" and DataManager.events.has(custom_hail):
        _current_event_poi_id = ""
        event_panel.open_event(DataManager.events, custom_hail)
        event_open = true
        get_tree().paused = true
        return

    var event: Dictionary = _generate_hail_event(data, faction_name, disposition, rep)
    DataManager.events[event_id] = event

    _current_event_poi_id = ""
    event_panel.open_event(DataManager.events, event_id)
    event_open = true
    get_tree().paused = true

func _generate_hail_event(data: Dictionary, faction_name: String, disposition: String, rep: float = 0.0) -> Dictionary:
    var nodes: Dictionary = {}
    var info: Dictionary
    var rname: String
    var ship_name: String = data.get("name", "Ship")
    var npc_type: String = data.get("type", "wanderer")
    var hostile: bool = data.get("hostile", false)
    var cargo: Dictionary = data.get("cargo", {})
    var job: int = int(data.get("job", 0))
    var title = ship_name
    var standing_line = "\n[%s standing: %+.0f — %s]" % [faction_name, rep, disposition.to_upper()]


    if hostile:
        nodes["start"] = {
            "speaker": "Hostile Comm", 
            "text": "You're hailing %s — a %s vessel. They respond with a burst of static and weapons lock.\n[%s standing: %+.0f — HOSTILE]" % [ship_name, faction_name, faction_name, rep], 
            "choices": [{"label": "Break off.", "next": ""}]
        }
        return {"title": title, "nodes": nodes}


    var cargo_lines: String = ""
    var total_cargo: int = 0
    if not cargo.is_empty():
        cargo_lines = "\n\nCargo:"
        for rk in cargo:
            var amt = int(cargo[rk])
            if amt <= 0:
                continue
            total_cargo += amt
            info = GameManager.RESOURCE_TYPES.get(rk, {})
            rname = info.get("name", rk)
            cargo_lines += "\n  %s x%d" % [rname, amt]


    var job_label: String = ""
    match job:
        GameManager.NpcJob.HAULING: job_label = "Hauling cargo"
        GameManager.NpcJob.MINING: job_label = "Mining operations"
        GameManager.NpcJob.PATROL: job_label = "On patrol"
        GameManager.NpcJob.BOUNTY_HUNT: job_label = "Hunting bounties"
        GameManager.NpcJob.EXPLORING: job_label = "Exploration survey"
        GameManager.NpcJob.DOCKED: job_label = "Docked / refueling"
        _: job_label = "Idle"


    var start_choices: Array = []


    if total_cargo > 0:
        start_choices.append({"label": "Interested in trading cargo.", "next": "trade_cargo"})

    match npc_type:
        "trader":
            start_choices.append({"label": "What's the situation out here?", "next": "intel"})
        "patrol":
            start_choices.append({"label": "Any threats in the area?", "next": "threats"})
        "science":
            start_choices.append({"label": "Found anything interesting?", "next": "findings"})
    start_choices.append({"label": "Fly safe. Out.", "next": ""})


    var opening: String
    var fdata = DataManager.galaxy_data.get("factions", {}).get(data.get("faction", ""), {})
    var is_alien_ship: bool = fdata.get("is_alien", false)
    if is_alien_ship:

        var body_desc: String = fdata.get("body_type", {}).get("desc", "alien physiology")
        var alien_greeting: String = fdata.get("greeting", "...")
        var org: String = fdata.get("org_name", faction_name)
        opening = "[%s vessel — crew: %s, %s]\n\"%s\"" % [org, body_desc, faction_name, alien_greeting]
    else:
        match npc_type:
            "trader":
                opening = "\"%s here, %s registry. %s through this system. What can we do for you, captain?\"" % [ship_name, faction_name, job_label]
            "patrol":
                opening = "\"%s patrol vessel %s. %s. Identify yourself and state your business.\"" % [faction_name, ship_name, job_label]
            "science":
                opening = "\"%s research vessel %s. %s in this sector. Go ahead, captain.\"" % [faction_name, ship_name, job_label]
            _:
                opening = "\"%s, independent vessel. %s. Nice to see a friendly face out here.\"" % [ship_name, job_label]

    nodes["start"] = {
        "speaker": "Comm Channel", 
        "text": opening + standing_line, 
        "choices": start_choices, 
    }


    if total_cargo > 0:

        var total_value: int = 0
        for rk in cargo:
            info = GameManager.RESOURCE_TYPES.get(rk, {})
            total_value += int(cargo[rk]) * int(info.get("sell_price", 2))

        var buy_price = int(total_value * 1.2)
        nodes["trade_cargo"] = {
            "speaker": ship_name, 
            "text": "\"We've got some goods we could part with.\"%s\n\nTotal value: %d cr (asking %d cr)" % [cargo_lines, total_value, buy_price], 
            "choices": [
                {"label": "Buy all cargo (%d cr)" % buy_price, "next": "trade_done", "effects": [{"type": "buy_npc_cargo", "price": buy_price}]}, 
                {"label": "Too rich for me.", "next": "start"}, 
            ], 
        }
        nodes["trade_done"] = {
            "speaker": ship_name, 
            "text": "\"Pleasure doing business. Cargo is yours, captain.\"", 
            "choices": [{"label": "Thanks.", "next": "start"}], 
        }


    match npc_type:
        "trader":
            nodes["intel"] = {
                "speaker": ship_name, 
                "text": "\"Standard run. Pirates have been a nuisance near the outer belts, but nothing we can't handle. Watch yourself out there.\"", 
                "choices": [{"label": "Copy that. Fly safe.", "next": "start"}], 
            }
        "patrol":
            nodes["threats"] = {
                "speaker": ship_name, 
                "text": "\"Scattered pirate activity on the system fringe. We've been running sweeps but they're slippery. Report any contacts to the nearest station.\"", 
                "choices": [{"label": "Will do. Thanks.", "next": "start"}], 
            }
        "science":
            nodes["findings"] = {
                "speaker": ship_name, 
                "text": "\"Unusual mineral concentrations in the asteroid fields. Could be worth mining. We've also detected anomalous energy signatures further out.\"", 
                "choices": [{"label": "I'll check it out.", "next": "start"}], 
            }

    return {"title": title, "nodes": nodes}

func _hail_station(station: Node2D):

    if event_open or builder_open or star_map_open:
        return
    var data = station.get_hail_data()
    _hail_station_key = data.get("station_key", "")
    _hail_station_type = data.get("type", "trade")
    _hail_station_name = data.get("name", "Station")
    var event_id = "station_hail_%s" % _hail_station_key
    var event: Dictionary = _generate_station_hail_event(data)
    DataManager.events[event_id] = event
    _current_event_poi_id = ""
    event_panel.open_event(DataManager.events, event_id)
    event_open = true
    get_tree().paused = true

func _generate_station_hail_event(data: Dictionary) -> Dictionary:

    var nodes: Dictionary = {}
    var sname: String = data.get("name", "Station")
    var _stype: String = data.get("type", "trade").capitalize()
    var faction: String = data.get("faction", "independent")
    var hostile: bool = data.get("hostile", false)
    var hp_pct: float = data.get("health_pct", 1.0)
    var sp_pct: float = data.get("shield_pct", 0.0)
    var pop_count: int = data.get("population", 0)
    var weapon_count: int = data.get("weapon_count", 0)
    var active_weapons: int = data.get("active_weapons", 0)
    var factions = DataManager.galaxy_data.get("factions", {})
    var faction_name = factions.get(faction, {}).get("name", faction.capitalize())
    var rep = GameManager.get_reputation(faction)
    var disposition = GameManager.get_faction_disposition(faction)
    var standing_line = "\n[%s standing: %+.0f — %s]" % [faction_name, rep, disposition.to_upper()]
    var title = sname

    if hostile:
        nodes["start"] = {
            "speaker": "Station Comm", 
            "text": "Static crackles across the channel. %s is broadcasting a weapons lock. The station's defenses are active — %d turrets tracking your hull.\n[%s — HOSTILE]" % [sname, active_weapons, faction_name], 
            "choices": [{"label": "Break off.", "next": ""}]
        }
        return {"title": title, "nodes": nodes}


    var status_line: String = ""
    if hp_pct < 1.0:
        status_line += "\nHull integrity: %d%%" % int(hp_pct * 100)
    if sp_pct > 0:
        status_line += "  Shields: %d%%" % int(sp_pct * 100)
    if pop_count > 0:
        status_line += "\nStation personnel: %d souls aboard" % pop_count
    if weapon_count > 0:
        status_line += "\nDefense turrets: %d (%d active)" % [weapon_count, active_weapons]


    var opening: String
    match data.get("type", "trade"):
        "trade":
            opening = "\"%s, %s registry. Welcome, captain. We've got a full dock and market standing by. State your business.\"" % [sname, faction_name]
        "military":
            opening = "\"%s command. %s naval installation. Identify yourself and submit to standard security scan before approach.\"" % [sname, faction_name]
        "pirate":
            opening = "\"...%s. You're hailing a free port, captain. We don't ask questions and we expect the same. Credits talk here.\"" % [sname]
        "science":
            opening = "\"%s research station, %s network. We welcome visitors — our sensor arrays have tracked your approach. How can we help?\"" % [sname, faction_name]
        "gateway":
            opening = "\"%s gateway hub. Major transit corridor — all factions welcome under standing accord. Docking bays are open.\"" % [sname]
        _:
            opening = "\"%s station. You're cleared for approach, captain.\"" % [sname]

    var start_choices: Array = []
    start_choices.append({"label": "Request docking clearance.", "next": "dock_confirm"})
    start_choices.append({"label": "What services do you offer?", "next": "services"})
    if weapon_count > 0 or pop_count > 0:
        start_choices.append({"label": "Give me a station status report.", "next": "status"})
    start_choices.append({"label": "Understood. Signing off.", "next": ""})

    nodes["start"] = {
        "speaker": "Station Comm", 
        "text": opening + standing_line, 
        "choices": start_choices, 
    }


    nodes["dock_confirm"] = {
        "speaker": "Station Comm", 
        "text": "\"Docking clearance granted, captain. Bay 1 is open — follow the approach vector. Welcome aboard %s.\"" % [sname], 
        "choices": [
            {"label": "Initiating docking sequence.", "next": "", "effects": [{"type": "dock_station"}]}, 
            {"label": "Acknowledged. Standing by.", "next": "start"}, 
        ], 
    }


    var services_text: String
    match data.get("type", "trade"):
        "trade":
            services_text = "\"Full market access — buy, sell, and trade. Ship repair and modification bay. Mission board's got local contracts. Crew hiring if you need hands.\""
        "military":
            services_text = "\"Limited civilian access: ship repairs, basic resupply. Military contracts available if your standing permits. Crew recruitment from reserve lists.\""
        "pirate":
            services_text = "\"Black market. No questions. Ship mods — we've got some hardware you won't find on the legal market. Crew? Plenty of people looking for work, no references required.\""
        "science":
            services_text = "\"Research data exchange, specialized equipment. We can repair sensor and analysis modules. Limited crew availability — mostly specialists.\""
        "gateway":
            services_text = "\"Major hub — full market, repair bays, mission boards from multiple factions. Large crew pool. Transit corridor access.\""
        _:
            services_text = "\"Standard services — repairs, market, crew hiring.\""
    nodes["services"] = {
        "speaker": "Station Comm", 
        "text": services_text, 
        "choices": [
            {"label": "I'll dock.", "next": "dock_confirm"}, 
            {"label": "Thanks. Out.", "next": ""}, 
        ], 
    }


    if weapon_count > 0 or pop_count > 0:
        var status_text = "\"Station report for %s:%s\"" % [sname, status_line]
        nodes["status"] = {
            "speaker": "Station Comm", 
            "text": status_text, 
            "choices": [{"label": "Copy that.", "next": "start"}], 
        }

    return {"title": title, "nodes": nodes}

var CONSUMABLE_EFFECTS = ["give_module", "give_credits", "give_resource_random", "give_fuel", "repair"]

func _on_event_finished(effects: Array):

    var amount: float
    var count: int
    var res_type: String
    var sys_ships: Array
    var amt: float
    var flag_name: String
    for eff in effects:
        var eff_type: String = eff.get("type", "")
        match eff_type:
            "repair":
                if player and is_instance_valid(player):
                    amount = eff.get("amount", 50)
                    player.health = minf(player.health + amount, player.max_health)
                    player.shields = minf(player.shields + amount, player.max_shields)
                    player.health_changed.emit(player.health, player.max_health, player.shields, player.max_shields)
            "give_module":
                var mod_id: String = eff.get("module_id", "")
                count = int(eff.get("count", 1))
                if mod_id != "":
                    GameManager.add_module(mod_id, count)

                    if hud_control:
                        var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
                        hud_control.show_bark("", "Acquired: %s x%d" % [mod_name, count], Color(0.85, 0.75, 0.3))
            "spawn_enemies":
                count = int(eff.get("count", 3))
                var min_d: float = eff.get("min_dist", 200)
                var max_d: float = eff.get("max_dist", 400)

                get_tree().create_timer(0.5, true, false, false).timeout.connect( func():
                    _spawn.spawn_enemies(count, min_d, max_d)
                )
            "set_tag":
                var tag_name: String = eff.get("tag", "")
                var tag_value = eff.get("value", true)
                if tag_name != "":
                    MvTriggerEngine.set_global_tag(tag_name, tag_value)
            "fire_triggers":
                # Legacy galaxy_data event effect that used to invoke the
                # systems.json spawn_triggers list. With spawn_triggers
                # deleted, this is a noop — author ECA rules listening
                # for a named event instead, and have the event effect
                # dispatch via the engine (or use 'event_type: spawn_wave'
                # in galaxy_data with a matching ECA rule).
                pass
            "give_resource_random":

                var res_keys = GameManager.RESOURCE_TYPES.keys()
                res_type = res_keys[randi() % res_keys.size()]
                var min_amt: int = eff.get("min", 3)
                var max_amt: int = eff.get("max", 8)
                amount = randi_range(min_amt, max_amt)
                var added = GameManager.add_resource(res_type, int(amount))
                if hud_control and added > 0:
                    var res_name = GameManager.RESOURCE_TYPES.get(res_type, {}).get("name", res_type)
                    hud_control.show_bark("", "Collected: %s x%d" % [res_name, added], Color(0.4, 0.7, 0.95))
            "dock_station":

                _pending_open = "dock_station"
            "give_credits":
                amount = eff.get("amount", 50)
                GameManager.credits += int(amount)
                if hud_control:
                    hud_control.show_bark("", "+%d credits" % amount, Color(0.85, 0.75, 0.3))
            "give_fuel":
                amount = eff.get("amount", 10)
                GameManager.fuel = minf(GameManager.fuel + amount, GameManager.fuel_capacity)
                if hud_control:
                    hud_control.show_bark("", "+%d fuel" % amount, Color(0.3, 0.7, 0.95))
            "damage_hull":
                if player and is_instance_valid(player):
                    amount = eff.get("amount", 20)
                    player.health = maxf(player.health - amount, 1.0)
                    player.health_changed.emit(player.health, player.max_health, player.shields, player.max_shields)
                    if hud_control:
                        hud_control.show_bark("", "Hull damage: -%d" % amount, Color(0.9, 0.3, 0.2))
            "buy_npc_cargo":

                var price: int = int(eff.get("price", 0))
                if GameManager.credits >= price and _hail_npc_id != "":
                    GameManager.credits -= price
                    sys_ships = GameManager.npc_ships.get(GameManager.current_system, [])
                    for ship in sys_ships:
                        if ship.get("id") == _hail_npc_id:
                            var ncargo: Dictionary = ship.get("cargo", {})
                            for rk in ncargo:
                                GameManager.add_resource(rk, int(ncargo[rk]))
                            ship["cargo"] = {}
                            ship["credits"] = int(ship.get("credits", 0)) + price
                            break
                    if hud_control:
                        hud_control.show_bark("", "Bought NPC cargo (-%d cr)" % price, Color(0.4, 0.7, 0.95))
                elif hud_control:
                    hud_control.show_bark("", "Can't afford cargo!", Color(0.9, 0.3, 0.2))
            "queue_event":
                var q_event_id: String = eff.get("event_id", "")
                var q_delay_min: float = eff.get("delay_min", 60.0)
                var q_delay_max: float = eff.get("delay_max", 180.0)
                var q_tags: Dictionary = eff.get("tags", {})
                if q_event_id != "":
                    GameManager.queue_event(q_event_id, q_delay_min, q_delay_max, q_tags)

            "take_credits":
                amt = int(eff.get("amount", 0))
                GameManager.credits = maxi(GameManager.credits - int(amt), 0)
                if hud_control:
                    hud_control.show_bark("", "Spent %d credits" % amt, Color(0.9, 0.7, 0.3))
            "take_fuel":
                amt = float(eff.get("amount", 0))
                GameManager.fuel = maxf(GameManager.fuel - amt, 0)
            "reputation_change":
                var fac: String = eff.get("faction", "")
                amt = float(eff.get("amount", 0))
                if fac != "":
                    GameManager.modify_reputation(fac, amt)
                    if hud_control:
                        var rep_sign = "+" if amt > 0 else ""
                        hud_control.show_bark("REP", "%s %s%d" % [fac.capitalize(), rep_sign, int(amt)], Color(0.6, 0.7, 0.9))
            "give_resource":
                res_type = eff.get("resource", "")
                amt = int(eff.get("amount", 0))
                if res_type != "":
                    GameManager.add_resource(res_type, int(amt))
                    if hud_control:
                        hud_control.show_bark("", "Received %s x%d" % [res_type.capitalize(), amt], Color(0.7, 0.85, 0.4))
            "take_resource":
                res_type = eff.get("resource", "")
                amt = int(eff.get("amount", 0))
                if res_type != "":
                    GameManager.remove_resource(res_type, int(amt))
            "encounter_flag":
                flag_name = eff.get("flag", "")
                if flag_name != "":
                    EncounterManager.encounter_flags[flag_name] = true
            "clear_encounter_flag":
                flag_name = eff.get("flag", "")
                if flag_name != "":
                    EncounterManager.encounter_flags.erase(flag_name)
            "spawn_encounter_ship":
                _spawn_encounter_ship(eff)


    if _current_event_poi_id != "":
        var had_consumable = false
        for eff in effects:
            if eff.get("type", "") in CONSUMABLE_EFFECTS:
                had_consumable = true
                break
        if had_consumable:

            var is_station = false
            for poi in _cached_pois:
                if poi.event_id == _current_event_poi_id:
                    if "poi_type" in poi and poi.poi_type == "station":
                        is_station = true
                    break
            if not is_station:
                for poi in _cached_pois:
                    if poi.event_id == _current_event_poi_id:
                        poi.queue_free()
                        break

                if not GameManager.consumed_pois.has(_current_event_poi_id):
                    GameManager.consumed_pois.append(_current_event_poi_id)
        _current_event_poi_id = ""

func _on_encounter_started(event_id: String, enc_id: int):


    var spawns = EncounterManager.get_spawn_data(enc_id)
    for spawn_data in spawns:
        _spawn_encounter_ship(spawn_data)

    AudioManager.play_sfx("comms_hail", 0.6)
    event_panel.open_event(DataManager.events, event_id)
    event_open = true
    get_tree().paused = true

func _spawn_encounter_ship(data: Dictionary):

    if not player or not is_instance_valid(player):
        return
    var dist = float(data.get("distance", 400))
    var angle: float
    if data.get("angle", "random") == "random":
        angle = randf() * TAU
    else:
        angle = float(data.get("angle", 0))
    var spawn_pos = player.global_position + Vector2.from_angle(angle) * dist
    var use_wormhole: bool = data.get("wormhole", false)
    var ship_name: String = data.get("name", "Unknown Vessel")
    var faction: String = data.get("faction", "independent")
    var npc_type: String = data.get("npc_type", "wanderer")
    var is_hostile: bool = data.get("hostile", false)

    var factions_data = DataManager.galaxy_data.get("factions", {})
    var fc = factions_data.get(faction, {}).get("color", [0.5, 0.5, 0.55])
    var rng = RandomNumberGenerator.new()
    rng.seed = ship_name.hash()

    var ship_data: Dictionary = {
        "id": "enc_%d" % randi(), 
        "name": ship_name, 
        "faction": faction, 
        "npc_type": npc_type, 
        "color": fc, 
        "max_health": 80.0, 
        "health": 80.0, 
        "max_shields": 20.0, 
        "shields": 20.0, 
        "max_speed": 160.0, 
        "ship_size": 14.0, 
        "hostile": is_hostile, 
        "world_pos": [spawn_pos.x, spawn_pos.y], 
        "rotation": angle + PI, 
        "route": [], 
        "route_index": 0, 
        "modules": GameManager._generate_npc_modules(rng, npc_type), 
    }
    var faction_info = factions_data.get(faction, {})
    ship_data["ship_style"] = faction_info.get("ship_style", "")

    if use_wormhole and wormhole_script:
        var wh = Node2D.new()
        wh.set_script(wormhole_script)
        add_child(wh)
        wh.global_position = spawn_pos
        wh.finished.connect( func():
            var entity = Area2D.new()
            entity.set_script(npc_ship_script)
            add_child(entity)
            entity.setup(ship_data)
            entity.died.connect(_on_npc_ship_died)
        )
    else:
        var entity = Area2D.new()
        entity.set_script(npc_ship_script)
        add_child(entity)
        entity.setup(ship_data)
        entity.died.connect(_on_npc_ship_died)

func _open_queued_event(event_id: String):

    if hud_control:
        AudioManager.play_sfx("ui_click", 0.5)
    event_panel.open_event(DataManager.events, event_id)
    event_open = true
    get_tree().paused = true

func _on_event_closed():
    event_open = false
    get_tree().paused = time_frozen
    var pending = _pending_open
    _pending_open = ""
    if pending == "dock_station":
        _dock_at_station()

func _is_station_event(event_id: String) -> bool:

    return event_id in ["home_station", "home_station_first", "gateway_station", "pirate_haven"]

func _process_jump(delta: float):
    jump_timer += delta


    if player and is_instance_valid(player):
        var speed = lerpf(0, 3000.0, clampf(jump_timer / (JUMP_DURATION * 0.6), 0, 1))
        player.velocity = Vector2.from_angle(player.rotation) * speed

    if jump_timer >= JUMP_DURATION:
        _complete_jump()

func _complete_jump():
    jumping = false


    var dest_pos = system_world_positions.get(jump_target, Vector2.ZERO)
    var _jump_sys = DataManager.systems.get(jump_target, {})
    var _jump_star_r = _jump_sys.get("star_size", 60) * 20.0
    dest_pos += Vector2(_jump_star_r + 2000.0, 0)
    if player and is_instance_valid(player):
        player.position = dest_pos
        player.velocity = Vector2.ZERO


    loaded_system = ""
    _load_system_content(jump_target)

    queue_redraw()

func _unhandled_input(event: InputEvent):

    if menu_open:
        if event.is_action_pressed("toggle_editor"):
            _toggle_editor()
        return

    if event is InputEventMouseButton and event.pressed and not _any_panel_open():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _target_zoom = clampf(_target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
            get_viewport().set_input_as_handled()
            return
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _target_zoom = clampf(_target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
            get_viewport().set_input_as_handled()
            return

    if region_picker != null and region_picker.has_method("is_open") and region_picker.is_open():
        # Picker owns its own input handling — let it consume the event and
        # don't let SSB's ESC chain fall through to the pause menu.
        return

    var _is_back_pressed = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
    if _is_back_pressed:
        if pause_open:
            _on_pause_resumed()
            return

        if builder_open:
            builder.close_builder()
            return
        if star_map_open:
            star_map.close_map()
            return
        if event_open:
            event_panel._close()
            return
        if editor_open:
            content_editor.visible = false
            content_editor.closed.emit()
            return

        if _fight_ai_active:
            _end_fight_ai()
            return
        if creative_training_ai:
            if _training_naming:
                _cancel_training_naming()
                return
            _start_training_naming()
            return
        if creative_recording_ai:
            _discard_recording_and_return()
            return

        # Canonical pause is the cross-engine Nebula overlay (it sets pause_open +
        # get_tree().paused itself and routes Resume/Save/Settings/Exit). The old
        # authored-pause path on pause_menu.gd is dormant, mirroring the Nebula HUD.
        NebulaPause.open()
        return

    if editor_open:
        return

    if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
        if hud_control:
            hud_control.show_fps = not hud_control.show_fps
        return

    if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
        if _ui != null:
            _ui.toggle_tactical_hud()
        return

    if GameManager.using_controller and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
        if pause_open:
            _on_pause_resumed()
        else:
            NebulaPause.open()
        return

    if event.is_action_pressed("toggle_pause") and not pause_open:
        time_frozen = not time_frozen
        get_tree().paused = time_frozen
        if hud_control:
            hud_control.time_frozen = time_frozen
        return
    if pause_open:
        return
    if event.is_action_pressed("toggle_ship_builder"):
        if creative_previewing_ai:
            _end_ai_preview()
            return
        if creative_test_flying:
            _end_creative_test_fly()
            return
        _toggle_builder()
    elif event.is_action_pressed("toggle_star_map"):
        _toggle_star_map()
    elif event.is_action_pressed("toggle_editor"):
        _toggle_editor()
    elif event.is_action_pressed("save_game"):
        _do_save()
    elif event.is_action_pressed("load_game"):
        _do_load()

func _process(delta: float):
    queue_redraw()

    if starfield:
        starfield.tick(delta, player)

    if player and is_instance_valid(player) and player.camera:
        camera_zoom = lerpf(camera_zoom, _target_zoom, ZOOM_SMOOTH_SPEED * delta)
        player.camera.zoom = Vector2(camera_zoom, camera_zoom)

    if time_frozen or pause_open or menu_open:
        return


    if surface_entry_timer > 0:
        surface_entry_timer -= delta
    if surface_exit_timer > 0:
        surface_exit_timer -= delta

    if jumping:
        if starfield:
            starfield.mark_dirty()
        _process_jump(delta)
        return


    _group_cache_frame += 1
    if _group_cache_frame % 3 == 0:
        _cached_enemies = get_tree().get_nodes_in_group("enemies")
        _cached_npc_ships = get_tree().get_nodes_in_group("npc_ships")
        _cached_station_entities = get_tree().get_nodes_in_group("station_entities")
        _cached_pois = get_tree().get_nodes_in_group("pois")


    GameManager.in_combat = in_combat
    GameManager.tick_game_clock(delta)


    var _any_panel = builder_open or star_map_open or event_open or editor_open
    var _blocked = _any_panel or pause_open or menu_open or time_frozen
    if player and is_instance_valid(player):
        player.input_blocked = _blocked
    if _any_panel:
        return


    if on_surface:
        _process_surface(delta)
        return


    if player and is_instance_valid(player) and not on_surface:
        _tick_poi_detection()



    if not event_open and not builder_open and not star_map_open and not on_surface:
        var triggered_event = GameManager.tick_pending_events(delta)
        if triggered_event != "" and DataManager.events.has(triggered_event):
            _open_queued_event(triggered_event)


    var check_pos: Vector2
    var nearest_dist: float
    var d: float
    if not event_open and not builder_open and not star_map_open and not on_surface:
        if player and is_instance_valid(player):
            check_pos = player.global_position
            var nearest_sys = _find_nearest_system(check_pos)
            nearest_dist = INF
            if nearest_sys != "" and system_world_positions.has(nearest_sys):
                nearest_dist = check_pos.distance_to(system_world_positions[nearest_sys])
            EncounterManager.tick(delta, nearest_dist)


    var enemies = _cached_enemies
    if enemies.is_empty():
        if in_combat:
            in_combat = false
            AudioManager.set_ambient_varied("space")
        if player:
            player.auto_fire_target = null
    else:
        var combat_pos: Vector2 = player.global_position

        var _nearest_enemy: Node2D = null
        nearest_dist = INF
        for e in enemies:
            if not is_instance_valid(e):
                continue
            d = e.global_position.distance_to(combat_pos)
            if d < nearest_dist:
                nearest_dist = d
                _nearest_enemy = e
        if nearest_dist < 600.0 and not in_combat:
            in_combat = true
            AudioManager.set_ambient_varied("combat")


    hail_target = null
    if not in_combat and not on_surface and player and is_instance_valid(player):
        check_pos = player.global_position
        var best_dist = 300.0
        for npc in _cached_npc_ships:
            if not is_instance_valid(npc) or not npc.alive:
                continue
            d = npc.global_position.distance_to(check_pos)
            if d < best_dist:
                best_dist = d
                hail_target = npc

        for se in _cached_station_entities:
            if not is_instance_valid(se) or not se.alive:
                continue
            d = se.global_position.distance_to(check_pos)
            var station_hail_range = (se.ship_size + 80.0) * 5.0
            if d < station_hail_range and d < best_dist:
                best_dist = d
                hail_target = se
        if hail_target and Input.is_action_just_pressed("interact"):
            if hail_target.is_in_group("station_entities"):
                _hail_station(hail_target)
            else:
                _hail_npc_ship(hail_target)


    _update_current_system()
    if not on_surface:
        _poll_proximity_bands()

func _process_surface(_delta: float):
    if not player or not is_instance_valid(player):
        return


    var dist_from_center = player.global_position.length()
    if dist_from_center > SURFACE_RADIUS:
        var push_dir = - player.global_position.normalized()
        player.global_position = player.global_position.normalized() * SURFACE_RADIUS
        player.velocity = player.velocity.lerp(push_dir * 100.0, 0.1)


    if Input.is_action_just_pressed("liftoff"):
        _exit_surface()
        return


    if not _cached_enemies.is_empty():
        var nearest_dist = INF
        for e in _cached_enemies:
            var d = e.global_position.distance_to(player.global_position)
            if d < nearest_dist:
                nearest_dist = d
        if nearest_dist < 600.0 and not in_combat:
            in_combat = true
            AudioManager.set_ambient_varied("combat")
    elif in_combat:
        in_combat = false
        AudioManager.set_ambient_varied("surface")

func _on_enemy_died(pos: Vector2, size: float = 96.0):
    var expl = Node2D.new()
    expl.set_script(ship_explosion_script)
    expl.global_position = pos
    add_child(expl)
    expl.setup(size)
    var _explode_sfx = "ship_explode_%d" % randi_range(1, 7)
    AudioManager.play_sfx(_explode_sfx, 0.8, 0.05)
    var sys = DataManager.systems.get(GameManager.current_system, {})
    var threat = sys.get("threat_level", 1)

    var credit_drop = randi_range(5, 15) * threat
    GameManager.credits += credit_drop

    if randf() < 0.3:
        var fuel_drop = randf_range(2, 6) * threat
        GameManager.fuel = minf(GameManager.fuel + fuel_drop, GameManager.fuel_capacity)
    if randf() < 0.15:
        var res_keys = GameManager.RESOURCE_TYPES.keys()
        var res_type = res_keys[randi() % res_keys.size()]
        GameManager.add_resource(res_type, randi_range(1, 2))
    if hud_control:
        hud_control.queue_redraw()

    #if randf() < DataManager.get_drop_chance(threat):
    #    _spawn_loot.call_deferred(pos)


    GameManager.kill_count += 1
    GameManager.total_kills += 1
    if hud_control:
        hud_control.kill_count = GameManager.kill_count


func _recover_hidden_player_after_surface_death() -> void:
    if player == null or not is_instance_valid(player):
        return
    player.alive = true
    player.health = player.max_health
    player.shields = player.max_shields
    player.death_cause = ""
    if on_surface or _space_simulation_surface_locked:
        _set_space_entity_surface_locked(player, true)
    else:
        player.set_process(true)
        player.set_physics_process(true)
        player.input_blocked = false
    player.visible = false
    if player.has_signal("health_changed"):
        player.health_changed.emit(player.health, player.max_health, player.shields, player.max_shields)

func _set_space_entity_surface_locked(node: Node, locked: bool) -> void:
    if node == null or not is_instance_valid(node):
        return
    if locked:
        if not node.has_meta("_surface_prev_process"):
            node.set_meta("_surface_prev_process", node.is_processing())
        if not node.has_meta("_surface_prev_physics"):
            node.set_meta("_surface_prev_physics", node.is_physics_processing())
        node.set_process(false)
        node.set_physics_process(false)
        if node == player:
            player.input_blocked = true
            player.velocity = Vector2.ZERO
            player.auto_fire_target = null
        return
    if node.has_meta("_surface_prev_process"):
        node.set_process(bool(node.get_meta("_surface_prev_process")))
        node.remove_meta("_surface_prev_process")
    if node.has_meta("_surface_prev_physics"):
        node.set_physics_process(bool(node.get_meta("_surface_prev_physics")))
        node.remove_meta("_surface_prev_physics")
    if node == player:
        player.input_blocked = false

func _set_space_simulation_surface_locked(locked: bool) -> void:
    if _space_simulation_surface_locked == locked:
        return
    _space_simulation_surface_locked = locked
    if get_tree() == null:
        return
    var touched: Dictionary = {}
    for group_name in SURFACE_SPACE_FREEZE_GROUPS:
        for node in get_tree().get_nodes_in_group(group_name):
            if not (node is Node):
                continue
            var entity: Node = node as Node
            var entity_id: int = entity.get_instance_id()
            if touched.has(entity_id):
                continue
            touched[entity_id] = true
            _set_space_entity_surface_locked(entity, locked)
    if player and is_instance_valid(player):
        var player_id: int = player.get_instance_id()
        if not touched.has(player_id):
            _set_space_entity_surface_locked(player, locked)

func _on_trigger_spawn_space_ship(class_id: String, anchor: String, pos: Vector2, use_wormhole: bool, delay: float) -> void:
    if player == null or not is_instance_valid(player):
        return
    var spawn_pos: Vector2 = pos
    match anchor.strip_edges().to_lower():
        "player", "player_offset":
            spawn_pos = player.global_position + pos
        "system", "current_system", "system_offset":
            spawn_pos = system_world_positions.get(GameManager.current_system, Vector2.ZERO) + pos
        _:
            spawn_pos = pos
    _spawn.spawn_enemy_ship(spawn_pos, class_id, use_wormhole, delay)


# Handles MvTriggerEngine's `spawn_space_enemies` action by adapting the
# (class_id, count, dist_min, dist_max, use_wormhole) tuple into the
# spawn_manager's existing spawn_trigger_enemies signature, which expects
# an Array of {class, count} entries. Keeps spawn_manager's scatter math
# (random angle, clamped distance, staggered delays) as the single
# implementation point so the action behaves like the old spawn_triggers.
func _on_trigger_spawn_space_enemies(class_id: String, count: int, dist_min: int, dist_max: int, _use_wormhole: bool) -> void:
    if _spawn == null or class_id.strip_edges().is_empty() or count <= 0:
        return
    var spawns: Array = [{"class": class_id, "count": count}]
    _spawn.spawn_trigger_enemies(spawns, float(dist_min), float(dist_max))


func _spawn_loot(pos: Vector2):
    var sys = DataManager.systems.get(GameManager.current_system, {})
    var threat = sys.get("threat_level", 1)
    var table: Array = DataManager.get_loot_table(threat)
    if table.is_empty():
        return


    var total_weight: float = 0
    for entry in table:
        total_weight += entry.get("weight", 1)
    var roll = randf() * total_weight
    var accumulated: float = 0
    var chosen_id: String = table[0].get("id", "conduit_mk1")
    for entry in table:
        accumulated += entry.get("weight", 1)
        if roll <= accumulated:
            chosen_id = entry.get("id", "conduit_mk1")
            break

    var drop = Area2D.new()
    drop.set_script(loot_script)
    drop.global_position = pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))
    add_child(drop)
    drop.setup(chosen_id)
    drop.picked_up.connect(_on_loot_picked_up)

func _on_loot_picked_up(mod_id: String):
    if not GameManager.module_inventory.has(mod_id):
        GameManager.module_inventory[mod_id] = 0
    GameManager.module_inventory[mod_id] += 1
    AudioManager.play_sfx("loot_pickup", 0.6)

    if hud_control:
        var mod_name = DataManager.modules.get(mod_id, {}).get("name", mod_id)
        hud_control.show_bark("", "Picked up: " + mod_name, Color(0.85, 0.75, 0.3))

func _find_poi_by_event_id(eid: String) -> Node:
    for poi in _cached_pois:
        if poi.event_id == eid:
            return poi
    return null

func _discover_poi(poi_node: Node2D):

    if "discovered" in poi_node and not poi_node.discovered:
        poi_node.discovered = true
        var sys_id = GameManager.current_system
        if not GameManager.discovered_pois.has(sys_id):
            GameManager.discovered_pois[sys_id] = []
        var pname = poi_node.poi_name if "poi_name" in poi_node else ""
        if pname != "" and pname not in GameManager.discovered_pois[sys_id]:
            GameManager.discovered_pois[sys_id].append(pname)

func _tick_poi_detection():

    var det_range = player.detection_radius
    var ppos = player.global_position
    for poi_node in _cached_pois:
        if not is_instance_valid(poi_node):
            continue
        if "discovered" in poi_node and poi_node.discovered:
            continue
        if ppos.distance_to(poi_node.global_position) <= det_range:
            _discover_poi(poi_node)

    for se in _cached_station_entities:
        if not is_instance_valid(se):
            continue
        if not ("poi_marker" in se and se.poi_marker and is_instance_valid(se.poi_marker)):
            continue
        if se.poi_marker.discovered:
            continue
        if ppos.distance_to(se.global_position) <= det_range:
            _discover_poi(se.poi_marker)

    _tick_region_picker_proximity(ppos)


# Closes the open region picker if the player drifts out of the source POI's
# interact_radius (no-op when the picker is closed or the source POI was
# already freed). Keeps the picker honest with the ship's actual landing
# range so the player can't sit still in space with a stale prompt up.
func _tick_region_picker_proximity(ppos: Vector2) -> void:
    if region_picker == null or not region_picker.has_method("is_open") or not region_picker.is_open():
        return
    if _region_picker_poi == null or not is_instance_valid(_region_picker_poi):
        region_picker.call("close")
        _region_picker_pending_data = {}
        _region_picker_poi = null
        return
    var poi_pos: Vector2 = _region_picker_poi.global_position
    var radius: float = 600.0
    if "interact_radius" in _region_picker_poi:
        radius = float(_region_picker_poi.interact_radius)
    if ppos.distance_to(poi_pos) > radius:
        region_picker.call("close")
        _region_picker_pending_data = {}
        _region_picker_poi = null

func _on_scan_hit(target: Node2D):

    if target.is_in_group("pois"):
        _discover_poi(target)
        target.scanned = true
        target.scan_flash = 1.0
    if target.is_in_group("loot"):
        target.scanned = true
    if target.is_in_group("enemies"):
        target.scanned = true
        target.damage_flash = 0.3

func _on_player_health_changed(_h: float, _mh: float, _s: float, _ms: float):
    # Self-play learning: clone dealt damage to player — reward it
    if creative_training_ai and _training_clone and is_instance_valid(_training_clone):
        if _training_clone.cloned_ai:
            _training_clone.cloned_ai.on_dealt_damage()

func _on_player_destroyed():
    if _fight_ai_active:
        if player and is_instance_valid(player):
            var expl = Node2D.new()
            expl.set_script(ship_explosion_script)
            expl.global_position = player.global_position
            add_child(expl)
            expl.setup(player.ship_size)
            AudioManager.play_sfx("ship_explode_%d" % randi_range(1, 7), 0.8, 0.05)
            player.set_process(false)
            player.set_physics_process(false)
            player.visible = false
        GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "DEFEATED!", "color": [1.0, 0.3, 0.2], "duration": 3.0})
        get_tree().create_timer(2.0, true, false, false).timeout.connect(func():
            if _fight_ai_active:
                _end_fight_ai()
        )
        return
    if creative_training_ai:
        # Training mode: explosion VFX but no death screen, auto-advance round
        if player and is_instance_valid(player):
            var expl = Node2D.new()
            expl.set_script(ship_explosion_script)
            expl.global_position = player.global_position
            add_child(expl)
            expl.setup(player.ship_size)
            AudioManager.play_sfx("ship_explode_%d" % randi_range(1, 7), 0.8, 0.05)
            # Stop processing so the player can't take more damage while dead
            player.set_process(false)
            player.set_physics_process(false)
            player.visible = false
        GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "YOU DIED — UPDATING AI", "color": [1.0, 0.3, 0.2], "duration": 2.0})
        get_tree().create_timer(1.0, true, false, false).timeout.connect(func():
            if creative_training_ai:
                _advance_training_round()
        )
        return

    var death_cause = ""
    if on_surface:
        _surface_death_blocked = true
        _recover_hidden_player_after_surface_death()
        return
    if player and is_instance_valid(player):
        death_cause = player.death_cause
        var expl = Node2D.new()
        expl.set_script(ship_explosion_script)
        expl.global_position = player.global_position
        add_child(expl)
        expl.setup(player.ship_size)
        player.set_process(false)
        player.set_physics_process(false)
        var ship_ref = player
        get_tree().create_timer(0.5, true, false, false).timeout.connect(func():
            if ship_ref and is_instance_valid(ship_ref):
                ship_ref.visible = false
        )
        var _explode_sfx = "ship_explode_%d" % randi_range(1, 7)
        AudioManager.play_sfx(_explode_sfx, 0.8, 0.05)
        expl.finished.connect(func():
            if death_screen:
                death_screen.show_death(death_cause)
                get_tree().paused = true
        )
    else:
        if death_screen:
            death_screen.show_death(death_cause)
            get_tree().paused = true

func _on_death_retry():
    _close_mv_runtime_overlays()
    if on_surface or _surface_death_blocked:
        _surface_death_blocked = false
        if death_screen != null:
            death_screen.visible = false
        _recover_hidden_player_after_surface_death()
    get_tree().paused = false
    if death_screen != null:
        death_screen.visible = false
    if creative_training_ai:
        _advance_training_round()
        return
    if creative_previewing_ai:
        _end_ai_preview()
        return
    if creative_test_flying and not creative_recording_ai and not _fight_ai_active:
        _cmc.retry_creative_test_fly()
        return
    if creative_test_flying:
        GameManager.skip_main_menu = true
        GameManager.auto_test_fly = true
        GameManager.reset_to_new_game()
        get_tree().reload_current_scene()
        return
    # Load last checkpoint save
    GameManager.skip_main_menu = true
    if GameManager.load_game(GameManager.current_save_slot):
        get_tree().reload_current_scene()
    else:
        # No save to load — fall back to scene reload
        get_tree().reload_current_scene()

func _on_death_menu():
    _close_mv_runtime_overlays()
    if on_surface or _surface_death_blocked:
        _surface_death_blocked = false
        if death_screen != null:
            death_screen.visible = false
        _recover_hidden_player_after_surface_death()
    get_tree().paused = false
    if death_screen != null:
        death_screen.visible = false
    if creative_test_flying and not creative_recording_ai and not creative_previewing_ai and not creative_training_ai and not _fight_ai_active:
        _end_creative_test_fly()
        return
    GameManager.skip_main_menu = false
    GameManager.auto_test_fly = false
    GameManager.reset_to_new_game()
    DataManager.systems = {}
    DataManager.galaxy_data = {}
    DataManager.galaxy_seed = 0
    get_tree().reload_current_scene()

func _do_save():
    if builder_open or star_map_open or event_open or jumping:
        return
    if GameManager.save_game():
        if hud_control:
            hud_control.show_bark("", "Saved to Slot %d" % GameManager.current_save_slot, Color(0.3, 0.85, 0.4), 2.0)
    else:
        if hud_control:
            hud_control.show_bark("", "Save Failed!", Color(1.0, 0.3, 0.3), 2.0)

func _do_load():
    if builder_open or star_map_open or event_open or jumping:
        return
    if GameManager.load_game():
        get_tree().reload_current_scene()
    else:
        if hud_control:
            hud_control.show_bark("", "No Save Found", Color(1.0, 0.5, 0.2), 2.0)

func _on_power_preset_changed(preset: int):
    if hud_control:
        var p = player.POWER_PRESETS[preset]
        var pcol_arr = p.color
        var pcol = Color(pcol_arr[0], pcol_arr[1], pcol_arr[2])
        hud_control.show_bark("", "Power: " + p.name, pcol, 1.5)
        hud_control.power_preset = preset
