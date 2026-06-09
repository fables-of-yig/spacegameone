extends Node

const PackAssetIndex = preload("res://Space/scripts/shared/pack_asset_index.gd")
const FactionsIO = preload("res://Space/scripts/shared/factions_io.gd")

# UI panel coordinator. Owns the CanvasLayer stack and all top-level UI
# Control instances (HUD, builder, star map, event panel, pause/death/main
# menus, content/MV editors, planet viewport). Signal wiring routes through
# `host` (main.gd) — the coordinator constructs panels and connects them to
# the handlers that already live on main. Callers capture the returned
# Control refs and store them in main.gd's typed fields so the ~350 existing
# references elsewhere don't need to be rewritten.

var _editors: Dictionary = {}
var _planet_layer: CanvasLayer = null
var _planet_container: SubViewportContainer = null
var _planet_viewport: SubViewport = null
var _planet_overlay_layer: CanvasLayer = null
var _planet_overlay_root: Control = null
var _region_picker_layer: CanvasLayer = null
var _region_picker: Control = null

# Refs to the two HUDs mounted in setup_hud(). `legacy_hud` is the
# custom-draw HUD that's been here since launch; `tactical_hud` is the
# SCS Meridian re-skin. Exactly one is visible at a time, picked by
# `GameManager.use_tactical_hud`. Flip with toggle_tactical_hud().
var legacy_hud: Control = null
var tactical_hud: Control = null

func _make_layer(layer_num: int) -> CanvasLayer:
    var cl = CanvasLayer.new()
    cl.layer = layer_num
    cl.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(cl)
    return cl

func setup_hud(player: Node2D, system_positions: Dictionary) -> Control:
    var hud_layer = _make_layer(10)
    var hud_script = preload("res://Space/scripts/ui/hud.gd")
    var hud_control = Control.new()
    hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
    hud_control.set_script(hud_script)
    hud_control.player = player
    hud_control.system_positions = system_positions
    hud_layer.add_child(hud_control)
    _mount_hud_screen_overlay(hud_control, player)
    legacy_hud = hud_control

    _mount_tactical_hud(player)
    _apply_hud_visibility()

    return hud_control


# Mounts the tactical HUD on a sibling CanvasLayer so it can be toggled
# without touching the legacy HUD's render order.
func _mount_tactical_hud(player: Node2D) -> void:
    var tactical_layer := _make_layer(11)
    var tactical_script := preload("res://Space/scripts/ui/tactical_hud.gd")
    var tac := Control.new()
    tac.set_anchors_preset(Control.PRESET_FULL_RECT)
    tac.set_script(tactical_script)
    tac.player = player
    tactical_layer.add_child(tac)
    tactical_hud = tac


# Flips which HUD is shown. Updates `GameManager.use_tactical_hud` so
# the choice persists across HUD remounts in the same session.
func toggle_tactical_hud() -> void:
    GameManager.use_tactical_hud = not GameManager.use_tactical_hud
    _apply_hud_visibility()


func _apply_hud_visibility() -> void:
    var on_tactical: bool = GameManager.use_tactical_hud
    if legacy_hud != null:
        legacy_hud.visible = not on_tactical
    if tactical_hud != null:
        tactical_hud.visible = on_tactical


# Overlays the editor-built HUD screen (if any) on top of the hardcoded
# HUD. Absent a saved screen, this is a no-op and the hardcoded HUD runs
# exactly as before.
# Disabled: the Nebula tank-gauge HUD (hud.gd) is now canonical, and UIIo
# auto-provisions a stock hud_space screen for every pack, which would always
# overlay (and clutter) the Nebula gauges. Flip back to restore authored HUD
# overlays. Mirrors MvHud.ALLOW_AUTHORED_HUD.
const ALLOW_AUTHORED_HUD := false


func _mount_hud_screen_overlay(hud_root: Control, player: Node2D) -> void:
    if not ALLOW_AUTHORED_HUD:
        return
    var UIIo = preload("res://Space/scripts/shared/ui/ui_io.gd")
    var HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
    var AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")

    var pack_id := ""
    if MvPackLoader.current_pack != null:
        pack_id = MvPackLoader.current_pack.pack_id
    if pack_id.is_empty():
        return
    var screen_id := ""
    if UIIo.screen_exists(pack_id, "hud_space"):
        screen_id = "hud_space"
    elif UIIo.screen_exists(pack_id, "hud"):
        screen_id = "hud"
    if screen_id.is_empty():
        return
    var screen_data: Dictionary = UIIo.load_screen(pack_id, screen_id)
    if screen_data.is_empty():
        return

    var renderer = Control.new()
    renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
    renderer.set_script(AuthoredScreenRuntime)
    renderer.name = "HudScreenOverlay"
    hud_root.add_child(renderer)
    renderer.call("load_screen", screen_id, screen_data, HudDataSource.new(player, GameManager))

func setup_builder(host: Node) -> Control:
    var builder_layer = _make_layer(20)
    var builder_script = preload("res://Space/scripts/ship_builder/ship_builder.gd")
    var builder = Control.new()
    builder.set_script(builder_script)
    builder.visible = false
    builder_layer.add_child(builder)
    builder.closed.connect(host._on_builder_closed)
    builder.test_fly_requested.connect(host._on_creative_test_fly)
    builder.record_ai_requested.connect(host._on_record_ai_requested)
    builder.fight_ai_requested.connect(host._on_fight_ai_requested)
    return builder

func setup_star_map(host: Node) -> Control:
    var map_layer = _make_layer(15)
    var map_script = preload("res://Space/scripts/ui/star_map.gd")
    var star_map = Control.new()
    star_map.set_script(map_script)
    star_map.visible = false
    map_layer.add_child(star_map)
    star_map.jump_requested.connect(host._on_jump_requested)
    star_map.waypoint_set.connect(host._on_star_map_waypoint)
    star_map.closed.connect(host._on_star_map_closed)
    return star_map

func setup_event_panel(host: Node) -> Control:
    var event_layer = _make_layer(18)

    var bg_art_script = preload("res://Space/scripts/ui/encounter_bg_art.gd")
    var bg_art_node = Control.new()
    bg_art_node.set_script(bg_art_script)
    bg_art_node.visible = false
    event_layer.add_child(bg_art_node)

    var event_script = preload("res://Space/scripts/ui/event_panel.gd")
    var event_panel = Control.new()
    event_panel.set_script(event_script)
    event_panel.visible = false
    event_layer.add_child(event_panel)
    event_panel.bg_art = bg_art_node
    event_panel.event_finished.connect(host._on_event_finished)
    event_panel.closed.connect(host._on_event_closed)
    var pack_id := "demo"
    if MvPackLoader.current_pack != null:
        pack_id = str(MvPackLoader.current_pack.pack_id).strip_edges()
    if pack_id.is_empty():
        pack_id = "demo"
    var portrait_map := {
        "MOORE": "res://Space/art/portraits/moore.png",
        "Moore": "res://Space/art/portraits/moore.png",
        "CIDAS": "res://Space/art/portraits/cidas.png",
        "MEDIC": "res://Space/art/portraits/vu.png",
        "VU": "res://Space/art/portraits/vu.png",
        "ROBOT": "res://Space/art/portraits/cannie.png",
        "CREW": "res://Space/art/portraits/crew.png",
    }
    portrait_map.merge(PackAssetIndex.build_portrait_map(pack_id), true)
    event_panel.portrait_map = portrait_map
    event_panel.static_speakers = {"HARLEN": true}
    # Faction symbol overlay map. Lives parallel to portrait_map; the
    # dialogue node's speaker_faction field looks up here. Empty when
    # the pack has no factions.json or no factions have authored symbols.
    event_panel.faction_symbol_map = FactionsIO.build_faction_symbol_map(pack_id)
    return event_panel

func setup_pause_menu(host: Node) -> Control:
    var pause_layer = _make_layer(90)
    var pause_script = preload("res://Space/scripts/ui/pause_menu.gd")
    var pause_menu = Control.new()
    pause_menu.set_script(pause_script)
    pause_menu.visible = false
    pause_layer.add_child(pause_menu)
    pause_menu.resumed.connect(host._on_pause_resumed)
    pause_menu.load_requested.connect(host._on_pause_load)
    pause_menu.quit_to_menu.connect(host._on_quit_to_menu)
    return pause_menu

func setup_cinematic_overlay() -> CanvasLayer:
    var cinematic_layer = CanvasLayer.new()
    cinematic_layer.set_script(preload("res://Space/scripts/ui/cinematic_overlay.gd"))
    add_child(cinematic_layer)
    return cinematic_layer

func setup_death_screen(host: Node) -> Control:
    var death_layer = _make_layer(95)
    var death_script = preload("res://Space/scripts/ui/death_screen.gd")
    var death_screen = Control.new()
    death_screen.set_script(death_script)
    death_screen.visible = false
    death_layer.add_child(death_screen)
    death_screen.retry_pressed.connect(host._on_death_retry)
    death_screen.menu_pressed.connect(host._on_death_menu)
    return death_screen

# Returns the created main_menu. Caller is responsible for setting
# host.menu_open based on the returned visibility (we set visibility here
# because the skip-main-menu / auto-test-fly logic is naturally local here).
func setup_main_menu(host: Node, gm: Node) -> Control:
    var menu_layer = _make_layer(100)
    var menu_script = preload("res://Space/scripts/ui/main_menu.gd")
    var main_menu = Control.new()
    main_menu.set_script(menu_script)

    if gm.skip_main_menu:
        main_menu.visible = false
        host.menu_open = false
        gm.skip_main_menu = false
    else:
        main_menu.visible = true
        host.menu_open = true
    menu_layer.add_child(main_menu)
    main_menu.load_slot_pressed.connect(host._on_load_slot)
    main_menu.creative_pressed.connect(host._on_creative_mode)
    main_menu.test_fly_pressed.connect(host._on_test_fly)
    main_menu.test_planet_pressed.connect(host._on_test_planet)
    main_menu.play_pack_pressed.connect(host._on_play_pack)
    main_menu.editor_chosen.connect(host._on_editor_chosen)

    if gm.auto_test_fly:
        gm.auto_test_fly = false
        host._on_test_fly.call_deferred()
    return main_menu

## Returns true when this build ships pointed at a specific pack — checked
## by looking for res://shipped_pack.json at the project root. Present =
## strip the editor entirely (no instantiation, no entry points); absent =
## dev / authoring build with the full editor suite.
static func is_shipped_build() -> bool:
    return FileAccess.file_exists("res://shipped_pack.json")


## Reads res://shipped_pack.json and returns its parsed Dictionary. Empty
## dict when the file is missing or malformed; callers should treat empty
## as "not a shipped build, behave like dev". Expected shape:
##   { "pack_id": "<id>", "hide_editor": true }
static func read_shipped_pack_config() -> Dictionary:
    if not is_shipped_build():
        return {}
    var file := FileAccess.open("res://shipped_pack.json", FileAccess.READ)
    if file == null:
        push_warning("[ui_coordinator] shipped_pack.json present but unreadable.")
        return {}
    var text := file.get_as_text()
    file.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("[ui_coordinator] shipped_pack.json is not a JSON object; ignoring.")
        return {}
    return parsed


# Creates all content/MV editor panels under a single layer. Returns a
# dictionary keyed by editor name — caller spreads into its typed fields.
# In a shipped build, returns an empty dict and prints a single log line
# so the rest of the boot flow can no-op past missing editor handles.
func setup_editors(host: Node) -> Dictionary:
    if is_shipped_build():
        print("[ui_coordinator] shipped_pack.json present — skipping editor panel instantiation.")
        _editors = {}
        return _editors

    var editor_layer = _make_layer(25)

    var result: Dictionary = {}
    var mv_editors = [
        ["content_editor", "res://Space/scripts/editor/content_editor.gd"],
        ["region_editor", "res://Space/scripts/editor/region_editor.gd"],
        ["environment_editor", "res://Space/scripts/editor/environment_editor.gd"],
        ["entity_editor", "res://Space/scripts/editor/entity_editor.gd"],
        ["behavior_editor", "res://Space/scripts/editor/behavior_editor.gd"],
        ["theme_editor", "res://Space/scripts/editor/theme_editor.gd"],
        ["audio_editor", "res://Space/scripts/editor/audio_editor.gd"],
        ["player_editor", "res://Space/scripts/editor/player_editor.gd"],
        ["system_editor", "res://Space/scripts/editor/system_editor.gd"],
        ["ship_editor", "res://Space/scripts/editor/ship_editor.gd"],
        ["modules_editor", "res://Space/scripts/editor/modules_editor.gd"],
        ["loot_editor", "res://Space/scripts/editor/loot_catalog_editor.gd"],
        ["trigger_editor", "res://Space/scripts/editor/trigger_editor.gd"],
        ["dialogue_editor", "res://Space/scripts/editor/dialogue_editor.gd"],
        ["shop_editor", "res://Space/scripts/editor/shop_editor.gd"],
        ["quest_editor", "res://Space/scripts/editor/quest_editor.gd"],
        ["factions_editor", "res://Space/scripts/editor/factions_editor.gd"],
    ]
    for pair in mv_editors:
        var ed = _mk_editor(editor_layer, pair[1])
        if ed == null:
            push_warning("[ui_coordinator] editor script missing or failed to load: %s" % pair[1])
            continue
        result[pair[0]] = ed

    if result.has("content_editor"):
        result["content_editor"].closed.connect(host._on_editor_closed)
        result["content_editor"].editor_requested.connect(host._on_content_editor_editor_requested)
        result["content_editor"].playtest_requested.connect(host._on_content_editor_playtest_requested)
    if result.has("region_editor"):
        result["region_editor"].closed.connect(host._on_region_closed)
        result["region_editor"].back_to_pack.connect(host._on_region_back_to_pack)
        result["region_editor"].room_chosen.connect(host._on_region_room_chosen)
    if result.has("environment_editor"):
        result["environment_editor"].closed.connect(host._on_env_editor_closed)
    for pair in mv_editors:
        var key = pair[0]
        if key in ["content_editor", "region_editor", "environment_editor"]:
            continue
        if result.has(key):
            result[key].closed.connect(host._on_mv_editor_closed)
    if result.has("system_editor"):
        result["system_editor"].systems_saved.connect(host._on_system_editor_saved)
        result["system_editor"].region_edit_requested.connect(host._open_region_editor_from_system)
    if result.has("ship_editor"):
        result["ship_editor"].test_fly_requested.connect(host._on_ship_editor_test_fly_requested)
        result["ship_editor"].record_ai_requested.connect(host._on_ship_editor_record_ai_requested)
        result["ship_editor"].fight_ai_requested.connect(host._on_ship_editor_fight_ai_requested)

    _editors = result
    return result

# load() returns null when the script file isn't in the build (the export
# preset stripped it). Returning null here lets setup_editors skip the
# missing entry cleanly instead of crashing on set_script(null).
func _mk_editor(layer: CanvasLayer, script_path: String) -> Control:
    var script = load(script_path)
    if script == null:
        return null
    var ed = Control.new()
    ed.set_script(script)
    ed.visible = false
    layer.add_child(ed)
    return ed

# Creates the planet SubViewport plus a native-resolution overlay layer.
# Returns the created refs in a dict so main.gd can keep typed handles.
# Idempotent - repeat calls return the existing nodes.
func setup_planet_viewport() -> Dictionary:
    if _planet_container != null:
        return {
            "layer": _planet_layer,
            "container": _planet_container,
            "viewport": _planet_viewport,
            "overlay_layer": _planet_overlay_layer,
            "overlay_root": _planet_overlay_root,
        }
    _planet_layer = CanvasLayer.new()
    _planet_layer.name = "PlanetViewportLayer"
    _planet_layer.layer = 15
    # PROCESS_MODE_ALWAYS so the MVMania subtree keeps running while SSB's
    # tree is paused (which we do on planet visits to stop the ship from
    # taking damage / firing weapons / running encounter logic underneath
    # the planet view). Inheritance chains down through the container and
    # SubViewport to the MVMania Main instance below.
    _planet_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_planet_layer)

    _planet_container = SubViewportContainer.new()
    _planet_container.name = "PlanetViewportContainer"
    _planet_container.stretch = true
    _planet_container.stretch_shrink = 4
    _planet_container.visible = false
    _planet_container.anchor_left = 0.0
    _planet_container.anchor_top = 0.0
    _planet_container.anchor_right = 1.0
    _planet_container.anchor_bottom = 1.0
    _planet_container.mouse_filter = Control.MOUSE_FILTER_STOP
    _planet_layer.add_child(_planet_container)

    _planet_viewport = SubViewport.new()
    _planet_viewport.name = "PlanetViewport"
    _planet_viewport.handle_input_locally = true
    _planet_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _planet_container.add_child(_planet_viewport)

    _planet_overlay_layer = CanvasLayer.new()
    _planet_overlay_layer.name = "PlanetOverlayLayer"
    _planet_overlay_layer.layer = 16
    _planet_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    _planet_overlay_layer.visible = false
    add_child(_planet_overlay_layer)

    _planet_overlay_root = Control.new()
    _planet_overlay_root.name = "PlanetOverlayRoot"
    _planet_overlay_root.anchor_right = 1.0
    _planet_overlay_root.anchor_bottom = 1.0
    _planet_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _planet_overlay_root.visible = false
    _planet_overlay_layer.add_child(_planet_overlay_root)

    return {
        "layer": _planet_layer,
        "container": _planet_container,
        "viewport": _planet_viewport,
        "overlay_layer": _planet_overlay_layer,
        "overlay_root": _planet_overlay_root,
    }


# Mounts the region picker modal on its own CanvasLayer above the HUD/star
# map and below the pause menu. Wires region_chosen + cancelled to the host
# (main.gd) handlers so the picker stays a dumb view — host owns the actual
# begin_landing call.
func setup_region_picker(host: Node) -> Control:
    if _region_picker != null:
        return _region_picker
    _region_picker_layer = CanvasLayer.new()
    _region_picker_layer.name = "RegionPickerLayer"
    _region_picker_layer.layer = 60
    _region_picker_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_region_picker_layer)

    var picker_script = preload("res://Space/scripts/ui/region_picker_panel.gd")
    _region_picker = Control.new()
    _region_picker.set_script(picker_script)
    _region_picker.name = "RegionPickerPanel"
    _region_picker_layer.add_child(_region_picker)
    _region_picker.region_chosen.connect(host._on_region_picker_chosen)
    _region_picker.cancelled.connect(host._on_region_picker_cancelled)
    return _region_picker
