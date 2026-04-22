extends Node

const PackAssetIndex = preload("res://Space/scripts/editor/pack_asset_index.gd")

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
    return hud_control


# Overlays the editor-built HUD screen (if any) on top of the hardcoded
# HUD. Absent a saved screen, this is a no-op and the hardcoded HUD runs
# exactly as before.
func _mount_hud_screen_overlay(hud_root: Control, player: Node2D) -> void:
    var UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")
    var HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
    var AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")

    var pack_id := ""
    if MvPackLoader.current_pack != null:
        pack_id = MvPackLoader.current_pack.pack_id
    if pack_id.is_empty():
        return
    if not UIIo.screen_exists(pack_id, "hud"):
        return
    var screen_data: Dictionary = UIIo.load_screen(pack_id, "hud")
    if screen_data.is_empty():
        return

    var renderer = Control.new()
    renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
    renderer.set_script(AuthoredScreenRuntime)
    renderer.name = "HudScreenOverlay"
    hud_root.add_child(renderer)
    renderer.call("load_screen", "hud", screen_data, HudDataSource.new(player, GameManager))

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
    main_menu.new_game_pressed.connect(host._on_new_game)
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

# Creates all content/MV editor panels under a single layer. Returns a
# dictionary keyed by editor name — caller spreads into its typed fields.
func setup_editors(host: Node) -> Dictionary:
    var editor_layer = _make_layer(25)

    var result: Dictionary = {}
    result["content_editor"] = _mk_editor(editor_layer, "res://Space/scripts/editor/content_editor.gd")
    result["content_editor"].closed.connect(host._on_editor_closed)
    result["content_editor"].editor_requested.connect(host._on_content_editor_editor_requested)
    result["content_editor"].playtest_requested.connect(host._on_content_editor_playtest_requested)

    result["realm_editor"] = _mk_editor(editor_layer, "res://Space/scripts/editor/realm_editor.gd")
    result["realm_editor"].closed.connect(host._on_realm_closed)
    result["realm_editor"].region_chosen.connect(host._on_realm_region_chosen)

    result["region_editor"] = _mk_editor(editor_layer, "res://Space/scripts/editor/region_editor.gd")
    result["region_editor"].closed.connect(host._on_region_closed)
    result["region_editor"].back_to_realm.connect(host._on_region_back_to_realm)
    result["region_editor"].room_chosen.connect(host._on_region_room_chosen)

    result["environment_editor"] = _mk_editor(editor_layer, "res://Space/scripts/editor/environment_editor.gd")
    result["environment_editor"].closed.connect(host._on_env_editor_closed)

    var mv_editors = [
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
    ]
    for pair in mv_editors:
        var ed = _mk_editor(editor_layer, pair[1])
        ed.closed.connect(host._on_mv_editor_closed)
        result[pair[0]] = ed
    if result.has("system_editor"):
        result["system_editor"].systems_saved.connect(host._on_system_editor_saved)
    if result.has("ship_editor"):
        result["ship_editor"].test_fly_requested.connect(host._on_ship_editor_test_fly_requested)
        result["ship_editor"].record_ai_requested.connect(host._on_ship_editor_record_ai_requested)
        result["ship_editor"].fight_ai_requested.connect(host._on_ship_editor_fight_ai_requested)

    _editors = result
    return result

func _mk_editor(layer: CanvasLayer, script_path: String) -> Control:
    var script = load(script_path)
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
