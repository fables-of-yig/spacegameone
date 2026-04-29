extends Node

# Controller for creative mode, test-fly, AI recording, clone training,
# and fight-AI flows. State vars (creative_test_flying, _combat_recorder,
# _training_clone, etc.) live on main.gd; this controller orchestrates the
# transitions and reads/writes via owner_main. Entry points on main.gd are
# thin delegators that call into `cmc.<method>`.


var owner_main: Node = null

func _h() -> Node:
    return owner_main

func on_creative_mode():
    var host = _h()
    host.menu_open = false
    host.main_menu.visible = false
    host.creative_mode_active = true
    get_tree().paused = false
    host.builder.open_creative_builder("core_cruiser")
    host.builder_open = true
    GameManager.builder_open = true

func on_test_fly():
    var host = _h()
    host.menu_open = false
    host.main_menu.visible = false
    host.creative_mode_active = true
    get_tree().paused = false

    var data: Dictionary = {}
    var paths = [
        "user://npc_templates/noblefox.json",
        "res://Space/data/npc_templates/noblefox.json",
    ]
    for path in paths:
        if not FileAccess.file_exists(path):
            continue
        var file = FileAccess.open(path, FileAccess.READ)
        if file:
            var json = JSON.new()
            if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
                data = json.data
            file.close()
            if not data.is_empty() and data.has("modules"):
                print("[TestFly] Loaded Ship For Testing from: ", path, " - ", data.get("modules", []).size(), " modules")
                break

    if data.is_empty() or not data.has("modules"):
        push_error("[TestFly] Ship For Testing template not found in any location!")
        return

    var modules: Array = data.get("modules", [])
    var core_id: String = data.get("core_id", "core_scout")

    for mod in modules:
        if not mod.has("data"):
            mod["data"] = DataManager.modules.get(mod.get("id", ""), {})
        GameManager.init_module_hp(mod)

    host._creative_saved_modules = GameManager.ship_modules.duplicate(true)
    host._creative_saved_core = GameManager.equipped_core
    host._creative_saved_fuel = GameManager.fuel
    host._creative_saved_credits = GameManager.credits
    host._creative_test_modules = modules.duplicate(true)
    host._creative_test_core = core_id
    host.creative_test_flying = true

    GameManager.equipped_core = core_id
    GameManager.ship_modules = modules.duplicate(true)
    GameManager.update_resource_capacity()
    GameManager.fuel = GameManager.fuel_capacity
    GameManager.credits = 99999

    var player = host.player
    if player and is_instance_valid(player):
        player.apply_loadout(GameManager.ship_modules)
        var hp_data = GameManager.get_total_ship_hp()
        player.health = hp_data[1]
        player.max_health = hp_data[1]
        player.shields = player.max_shields
        player.position = Vector2.ZERO

    GameManager.init_faction_reputation()
    host._compute_world_positions()

    var test_sys = DataManager.systems.get(GameManager.current_system, {})
    var start_pos = host.system_world_positions.get(GameManager.current_system, Vector2.ZERO)
    start_pos += Vector2(test_sys.get("star_size", 60) * 20.0 + 2000.0, 0)
    if player:
        player.position = start_pos

    for key in GameManager.persistent_stations.keys():
        if key.begins_with(GameManager.current_system):
            GameManager.persistent_stations.erase(key)

    host.loaded_system = ""
    host._load_system_content(GameManager.current_system)

    host._spawn_warp_portal(start_pos, player, true)
    if host.hud_control:
        host.hud_control.combat_recorder = null
        host.hud_control.test_fly_controls_timer = 28.0

func on_creative_test_fly(placed: Array, core_id: String):
    var host = _h()
    host._creative_saved_modules = GameManager.ship_modules.duplicate(true)
    host._creative_saved_core = GameManager.equipped_core
    host._creative_saved_fuel = GameManager.fuel
    host._creative_saved_credits = GameManager.credits
    host._creative_test_modules = placed.duplicate(true)
    host._creative_test_core = core_id
    host.creative_test_flying = true
    host.builder_open = false
    GameManager.builder_open = false

    GameManager.equipped_core = core_id
    GameManager.ship_modules = placed.duplicate(true)
    GameManager.update_resource_capacity()
    GameManager.fuel = GameManager.fuel_capacity
    GameManager.credits = 99999

    var player = host.player
    if player and is_instance_valid(player):
        player.apply_loadout(GameManager.ship_modules)
        player.position = Vector2.ZERO

    GameManager.init_faction_reputation()
    host._compute_world_positions()

    var test_sys = DataManager.systems.get(GameManager.current_system, {})
    var start_pos = host.system_world_positions.get(GameManager.current_system, Vector2.ZERO)
    start_pos += Vector2(test_sys.get("star_size", 60) * 20.0 + 2000.0, 0)
    if player:
        player.position = start_pos

    for key in GameManager.persistent_stations.keys():
        if key.begins_with(GameManager.current_system):
            GameManager.persistent_stations.erase(key)

    host.loaded_system = ""
    host._load_system_content(GameManager.current_system)

    host._spawn_warp_portal(start_pos, player, true)
    if host.hud_control:
        host.hud_control.combat_recorder = null
        host.hud_control.test_fly_controls_timer = 28.0

func retry_creative_test_fly():
    var host = _h()
    if host._creative_test_modules.is_empty():
        return

    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()
    for proj in get_tree().get_nodes_in_group("projectiles"):
        if is_instance_valid(proj):
            proj.queue_free()

    if host.player and is_instance_valid(host.player):
        host.player.queue_free()

    GameManager.equipped_core = host._creative_test_core
    GameManager.ship_modules = host._creative_test_modules.duplicate(true)
    GameManager.update_resource_capacity()
    GameManager.fuel = GameManager.fuel_capacity
    GameManager.credits = 99999

    host.player = host.player_scene.instantiate()
    host.add_child(host.player)
    host.player.health_changed.connect(host._on_player_health_changed)
    host.player.destroyed.connect(host._on_player_destroyed)
    host.player.scan_pulse_hit.connect(host._on_scan_hit)
    host.player.apply_loadout(GameManager.ship_modules)
    var hp_data = GameManager.get_total_ship_hp()
    host.player.health = hp_data[1]
    host.player.max_health = hp_data[1]
    host.player.shields = host.player.max_shields
    host.player.nearest_star_pos = Vector2(-999999, -999999)
    host.player.nearest_star_radius = 0.0
    if host.player.camera:
        host.player.camera.make_current()
    if host.hud_control:
        host.hud_control.player = host.player

    GameManager.init_faction_reputation()
    host._compute_world_positions()

    var test_sys = DataManager.systems.get(GameManager.current_system, {})
    var start_pos = host.system_world_positions.get(GameManager.current_system, Vector2.ZERO)
    start_pos += Vector2(test_sys.get("star_size", 60) * 20.0 + 2000.0, 0)
    host.player.position = start_pos

    for key in GameManager.persistent_stations.keys():
        if key.begins_with(GameManager.current_system):
            GameManager.persistent_stations.erase(key)

    host.loaded_system = ""
    host._load_system_content(GameManager.current_system)
    host._spawn_warp_portal(start_pos, host.player, true)
    if host.hud_control:
        host.hud_control.combat_recorder = null
        host.hud_control.test_fly_controls_timer = 28.0

func on_record_ai_requested(placed: Array, core_id: String, template_name: String):
    var host = _h()
    host._creative_saved_modules = GameManager.ship_modules.duplicate(true)
    host._creative_saved_core = GameManager.equipped_core
    host._creative_saved_fuel = GameManager.fuel
    host._creative_saved_credits = GameManager.credits
    host._creative_test_modules = placed.duplicate(true)
    host._creative_test_core = core_id
    host.creative_test_flying = true
    host.creative_recording_ai = true
    host._recording_template_name = template_name
    host.builder_open = false
    GameManager.builder_open = false
    get_tree().paused = false

    GameManager.equipped_core = core_id
    GameManager.ship_modules = placed.duplicate(true)
    GameManager.update_resource_capacity()
    GameManager.fuel = GameManager.fuel_capacity
    GameManager.credits = 99999
    var player = host.player
    if player and is_instance_valid(player):
        player.apply_loadout(GameManager.ship_modules)
        player.health = player.max_health
        player.shields = player.max_shields
        player.alive = true
        player.visible = true
        player.set_process(true)
        player.set_physics_process(true)
    else:
        push_warning("Record AI: player invalid")

    var start_pos = Vector2(50000, 50000)
    if player:
        player.position = start_pos
        player.velocity = Vector2.ZERO
        player.nearest_star_pos = Vector2(-999999, -999999)
        player.nearest_star_radius = 0.0

    _spawn_target_dummy(start_pos + Vector2(4000, 0))
    setup_combat_recorder()

func _spawn_target_dummy(pos: Vector2):
    var host = _h()
    var dummy = host.enemy_scene.instantiate()
    dummy.position = pos
    host.add_child(dummy)
    dummy.max_health = 999999.0
    dummy.health = 999999.0
    dummy.max_speed = 0.0
    dummy.acceleration = 0.0
    dummy.fire_rate = 999.0
    dummy.damage = 0.0
    dummy.orbit_distance = 0.0
    dummy.turn_rate = 0.0
    dummy.ship_size = 24.0 * 6.0
    dummy.ship_color = Color(0.6, 0.6, 0.6)
    dummy.enemy_name = "Target Dummy"
    dummy.behavior = "dummy"
    dummy.shape_type = "diamond"
    for child in dummy.get_children():
        if child is CollisionShape2D and child.shape is CircleShape2D:
            child.shape.radius = dummy.ship_size
    dummy.queue_redraw()

func setup_combat_recorder():
    var host = _h()
    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        host._combat_recorder.queue_free()
    host._combat_recorder = CombatRecorder.new()
    var player = host.player
    if player and is_instance_valid(player):
        player.add_child(host._combat_recorder)
        host._combat_recorder.start_recording()
        if host.hud_control:
            host.hud_control.combat_recorder = host._combat_recorder

func load_cloned_recordings():
    var host = _h()
    host._cloned_recordings.clear()
    var paths = CombatRecording.list_recordings()
    for path in paths:
        var rec = CombatRecording.new()
        if rec.load_from_file(path):
            host._cloned_recordings.append(rec)

func spawn_test_fly_waves():
    var wave_count: int = 10
    for w_idx in wave_count:
        var delay = 30.0 + w_idx * 45.0
        get_tree().create_timer(delay, false, false, false).timeout.connect(
            func(): _spawn_test_fly_wave()
        )

func _spawn_test_fly_wave():
    var host = _h()
    if not host.creative_test_flying or not is_instance_valid(host.player):
        return
    var count = randi_range(20, 25)
    var sys = DataManager.systems.get(GameManager.current_system, {})
    var threat = sys.get("threat_level", 5)
    for i in count:
        var stagger = float(i) * randf_range(1.0, 2.0)
        var angle = randf() * TAU
        var dist = randf_range(2000, 5000)
        var spawn_pos = host.player.position + Vector2.from_angle(angle) * dist
        var class_id = host._spawn.pick_enemy_class(threat)
        host._spawn.spawn_enemy_with_wormhole(spawn_pos, class_id, stagger)

func _spawn_test_fly_template_hostiles(center_pos: Vector2):
    var host = _h()
    var rng = RandomNumberGenerator.new()
    rng.seed = randi()
    var templates = GameManager._load_npc_templates()
    var count = 4
    if templates.is_empty():
        host._spawn.spawn_enemies(count, 1500, 5000)
        return
    for i in count:
        GameManager.npc_id_counter += 1
        var tmpl = templates[rng.randi() % templates.size()]
        var modules = []
        for mi in tmpl["modules"].size():
            var entry = tmpl["modules"][mi]
            var gp = entry.get("grid_pos", [0, 0])
            var mod_id = entry.get("id", "")
            var mod_data = DataManager.modules.get(mod_id, {})
            var mod_type = mod_data.get("type", entry.get("type", "armor"))
            modules.append({
                "id": "npc_mod_%d" % mi,
                "grid_pos": [gp[0], gp[1]],
                "deck": 0,
                "data": mod_data.duplicate() if not mod_data.is_empty() else {"type": mod_type, "hex_size": 1},
            })
        var tcol = tmpl.get("colors", {})
        var pc = tcol.get("primary", [0.6, 0.3, 0.3])
        var angle = rng.randf() * TAU
        var dist = rng.randf_range(2000, 6000)
        var spawn_pos = center_pos + Vector2.from_angle(angle) * dist
        var ship_data: Dictionary = {
            "id": "test_hostile_%d" % GameManager.npc_id_counter,
            "name": tmpl.get("name", "Hostile %d" % i),
            "faction": "pirate",
            "npc_type": "pirate",
            "shape": "chevron",
            "color": [pc[0], pc[1], pc[2]],
            "max_health": 400.0,
            "health": 400.0,
            "max_shields": 200.0,
            "shields": 200.0,
            "max_speed": 180.0,
            "ship_size": 8.0,
            "hostile": true,
            "world_pos": [spawn_pos.x, spawn_pos.y],
            "rotation": rng.randf() * TAU,
            "route": [],
            "route_index": 0,
            "system": GameManager.current_system,
            "alive": true,
            "modules": modules,
            "combat_style": tmpl.get("combat_style", "standard"),
            "ship_style": "",
            "crew": [],
            "job": 0,
            "job_target": "",
            "cargo": {},
            "credits": 100,
        }
        var entity = Area2D.new()
        entity.set_script(host.npc_ship_script)
        host.add_child(entity)
        entity.setup(ship_data)
        entity.died.connect(host._on_npc_ship_died)

func discard_recording_and_return():
    var host = _h()
    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        host._combat_recorder.stop_recording()
        host._combat_recorder.queue_free()
        host._combat_recorder = null
    if host.hud_control:
        host.hud_control.combat_recorder = null
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()
    _return_to_builder()

func end_creative_test_fly():
    var host = _h()
    if host.creative_training_ai:
        advance_training_round()
        return

    if host.creative_recording_ai and host._combat_recorder and is_instance_valid(host._combat_recorder):
        if host._combat_recorder.recording.get_frame_count() < 300:
            GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "Need more recording data - keep fighting!", "color": [0.9, 0.5, 0.2], "duration": 3.0})
            return
        _start_training_loop()
        return

    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        host._combat_recorder.stop_recording()
        host._combat_recorder.save_recording()
        host._combat_recorder.queue_free()
        host._combat_recorder = null
    if host.hud_control:
        host.hud_control.combat_recorder = null

    _return_to_builder()

func _start_ai_preview(safe_name: String):
    var host = _h()
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()
    GameManager.reload_npc_templates()
    host.creative_recording_ai = false
    host.creative_previewing_ai = true
    var player = host.player
    if player and is_instance_valid(player):
        player.health = player.max_health
        player.shields = player.max_shields
        player.position = Vector2(50000, 50000)
        player.velocity = Vector2.ZERO
    _spawn_preview_enemy(safe_name, Vector2(50000 + 1200, 50000))

func _spawn_preview_enemy(safe_name: String, pos: Vector2):
    var host = _h()
    var tmpl = GameManager.get_template_by_name(safe_name)
    var rec = GameManager.load_template_recording(safe_name)
    var clone = host.player_scene.instantiate()
    clone.ai_controlled = true
    clone.position = pos
    host.add_child(clone)
    var modules = _build_modules_from_template(tmpl)
    clone.apply_loadout(modules)
    if rec:
        var ai = ClonedAI.new()
        ai.setup(rec, clone.max_speed)
        clone.cloned_ai = ai
    clone.destroyed.connect(func(): _on_preview_enemy_destroyed(clone))
    clone.nearest_star_pos = Vector2(-999999, -999999)
    clone.nearest_star_radius = 0.0
    host._spawn_warp_portal(pos, clone)

func _build_modules_from_template(tmpl: Dictionary) -> Array:
    var modules: Array = []
    for entry in tmpl.get("modules", []):
        var gp = entry.get("grid_pos", [0, 0])
        var mod_id = entry.get("id", "")
        var mod_data = DataManager.modules.get(mod_id, {})
        if mod_data.is_empty():
            continue
        var pm = {
            "id": mod_id,
            "grid_pos": Vector2i(int(gp[0]), int(gp[1])),
            "deck": entry.get("deck", 0),
            "data": mod_data,
        }
        if entry.get("rotation", 0) != 0:
            pm["rotation"] = entry["rotation"]
        modules.append(pm)
    return modules

func _on_preview_enemy_destroyed(clone: Node2D):
    if is_instance_valid(clone):
        clone.visible = false
        clone.set_process(false)
        clone.set_physics_process(false)

func end_ai_preview():
    var host = _h()
    host.creative_test_flying = false
    host.creative_previewing_ai = false
    host._recording_template_name = ""
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()
    _return_to_builder()

func _start_training_loop():
    var host = _h()
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()

    host.creative_training_ai = true
    host._training_round = 0
    host._training_advance_pending = false

    _reset_player_for_training()
    advance_training_round()

func advance_training_round():
    var host = _h()
    if host._training_advance_pending:
        return
    host._training_advance_pending = true

    host._training_round += 1

    _merge_clone_self_play()

    if host._training_clone and is_instance_valid(host._training_clone):
        host._training_clone.set_process(false)
        host._training_clone.set_physics_process(false)
        host._training_clone.queue_free()
    host._training_clone = null

    for proj in get_tree().get_nodes_in_group("projectiles"):
        if is_instance_valid(proj):
            proj.queue_free()

    _reset_player_for_training()

    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        host._combat_recorder.clear_target_cache()

    var snapshot: CombatRecording = null
    if host._combat_recorder and is_instance_valid(host._combat_recorder) and host._combat_recorder.recording:
        snapshot = host._combat_recorder.recording.snapshot()

    if snapshot == null or snapshot.get_frame_count() < 10:
        host._training_advance_pending = false
        return

    if host.hud_control:
        host.hud_control.training_round = host._training_round

    GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "ROUND %d - FIGHT!" % host._training_round, "color": [0.3, 0.8, 1.0], "duration": 2.5})

    get_tree().create_timer(0.5, true, false, false).timeout.connect(func():
        host._training_advance_pending = false
        if host.creative_training_ai:
            _spawn_training_clone(snapshot)
    )

func _spawn_training_clone(rec: CombatRecording):
    var host = _h()
    var pos = Vector2(50000 + 1200, 50000)
    var clone = host.player_scene.instantiate()
    clone.ai_controlled = true
    clone.position = pos
    host.add_child(clone)
    var clone_cam = clone.get_node_or_null("Camera2D")
    if clone_cam:
        clone_cam.queue_free()
    clone.apply_loadout(host._creative_test_modules.duplicate(true))
    var ai = ClonedAI.new()
    ai.setup(rec, clone.max_speed)
    clone.cloned_ai = ai
    clone.nearest_star_pos = Vector2(-999999, -999999)
    clone.nearest_star_radius = 0.0
    clone.destroyed.connect(_on_training_clone_destroyed)
    clone.health_changed.connect(on_training_clone_took_damage)
    host._training_clone = clone
    host._spawn_warp_portal(pos, clone)

func _on_training_clone_destroyed():
    var host = _h()
    if not host.creative_training_ai:
        return
    _merge_clone_self_play()
    if host._training_clone and is_instance_valid(host._training_clone):
        host._training_clone.set_process(false)
        host._training_clone.set_physics_process(false)
        host._training_clone.queue_free()
    host._training_clone = null
    GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "CLONE DEFEATED - UPDATING AI", "color": [0.2, 1.0, 0.4], "duration": 2.0})
    get_tree().create_timer(1.0, true, false, false).timeout.connect(func():
        if host.creative_training_ai:
            advance_training_round()
    )

func on_training_clone_took_damage(_h1: float, _mh: float, _s: float, _ms: float):
    var host = _h()
    if not host.creative_training_ai:
        return
    if host._training_clone and is_instance_valid(host._training_clone) and host._training_clone.cloned_ai:
        host._training_clone.cloned_ai.on_took_damage()

func _merge_clone_self_play():
    var host = _h()
    if host._training_clone == null or not is_instance_valid(host._training_clone):
        return
    var ai: ClonedAI = host._training_clone.cloned_ai
    if ai == null or ai.self_recording == null:
        return
    if ai.self_recording.get_frame_count() < 10:
        return
    if not host._training_clone.alive:
        ai.on_died()
    if host._combat_recorder and is_instance_valid(host._combat_recorder) and host._combat_recorder.recording:
        host._combat_recorder.recording.merge_from(ai.self_recording)

func _reset_player_for_training():
    var host = _h()
    var saved_recorder: Node = null
    var saved_recording: CombatRecording = null
    var was_recording: bool = false
    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        saved_recorder = host._combat_recorder
        saved_recording = host._combat_recorder.recording
        was_recording = host._combat_recorder.is_recording
        host._combat_recorder.is_recording = false
        host.player.remove_child(host._combat_recorder)

    if host.player and is_instance_valid(host.player):
        host.player.queue_free()

    host.player = host.player_scene.instantiate()
    host.player.position = Vector2(50000, 50000)
    host.add_child(host.player)
    host.player.health_changed.connect(host._on_player_health_changed)
    host.player.destroyed.connect(host._on_player_destroyed)
    host.player.scan_pulse_hit.connect(host._on_scan_hit)

    var fresh_modules = host._creative_test_modules.duplicate(true)
    for mod in fresh_modules:
        mod.erase("hp")
        mod.erase("max_hp")
        mod.erase("damaged")
        mod.erase("destroyed")
    GameManager.ship_modules = fresh_modules
    GameManager.update_resource_capacity()
    host.player.apply_loadout(GameManager.ship_modules)
    host.player.shields = host.player.max_shields
    GameManager.fuel = GameManager.fuel_capacity
    host.player.nearest_star_pos = Vector2(-999999, -999999)
    host.player.nearest_star_radius = 0.0

    if host.player.camera:
        host.player.camera.make_current()

    if host.hud_control:
        host.hud_control.player = host.player

    if saved_recorder:
        host.player.add_child(saved_recorder)
        saved_recorder.player = host.player
        saved_recorder.recording = saved_recording
        saved_recorder.is_recording = was_recording
        host._combat_recorder = saved_recorder
        if host.hud_control:
            host.hud_control.combat_recorder = host._combat_recorder

func start_training_naming():
    var host = _h()
    host._training_naming = true
    if host.hud_control:
        host.hud_control.training_naming = true
    get_tree().paused = true
    host._training_name_input = host._recording_template_name if host._recording_template_name != "" else "recording"
    if host._training_name_edit == null:
        host._training_name_edit = LineEdit.new()
        host._training_name_edit.process_mode = Node.PROCESS_MODE_ALWAYS
        host._training_name_edit.placeholder_text = "Enter recording name..."
        var sb = StyleBoxFlat.new()
        sb.bg_color = Color(0.08, 0.08, 0.12)
        sb.border_color = Color(0.4, 0.7, 1.0)
        sb.set_border_width_all(2)
        sb.set_content_margin_all(6)
        host._training_name_edit.add_theme_stylebox_override("normal", sb)
        host._training_name_edit.add_theme_stylebox_override("focus", sb)
        host._training_name_edit.add_theme_color_override("font_color", Color(1, 1, 0.9))
        host._training_name_edit.add_theme_font_size_override("font_size", 16)
        host._training_name_edit.text_submitted.connect(_on_training_name_submitted)
        if host.hud_control:
            host.hud_control.add_child(host._training_name_edit)
        else:
            host.add_child(host._training_name_edit)
    var vp = get_viewport().get_visible_rect().size
    host._training_name_edit.size = Vector2(400, 36)
    host._training_name_edit.position = Vector2((vp.x - 400) * 0.5, vp.y * 0.5)
    host._training_name_edit.text = host._training_name_input
    host._training_name_edit.visible = true
    host._training_name_edit.grab_focus()
    host._training_name_edit.select_all()

func cancel_training_naming():
    var host = _h()
    host._training_naming = false
    if host.hud_control:
        host.hud_control.training_naming = false
    get_tree().paused = false
    if host._training_name_edit:
        host._training_name_edit.visible = false

func _on_training_name_submitted(text: String):
    var host = _h()
    host._training_naming = false
    if host.hud_control:
        host.hud_control.training_naming = false
    if host._training_name_edit:
        host._training_name_edit.visible = false
    var rec_name = text.strip_edges()
    if rec_name == "":
        rec_name = host._recording_template_name if host._recording_template_name != "" else "recording_%d" % Time.get_unix_time_from_system()
    get_tree().paused = false
    _end_training_and_save(rec_name)

func _end_training_and_save(rec_name: String = ""):
    var host = _h()
    var total_frames = 0
    if host._combat_recorder and is_instance_valid(host._combat_recorder) and host._combat_recorder.recording:
        total_frames = host._combat_recorder.recording.get_frame_count()

    if host._combat_recorder and is_instance_valid(host._combat_recorder):
        host._combat_recorder.stop_recording()
        var safe_name = rec_name.replace(" ", "_").to_lower() if rec_name != "" else "recording_%d" % Time.get_unix_time_from_system()
        host._combat_recorder.recording.template_name = host._recording_template_name.replace(" ", "_").to_lower()
        host._combat_recorder.save_recording(safe_name)
        if OS.has_feature("editor"):
            var rec = host._combat_recorder.recording
            DirAccess.make_dir_recursive_absolute("res://Space/data/npc_templates")
            rec.save_to_file("res://Space/data/npc_templates/%s_recording.json" % safe_name)
        GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "AI saved as \"%s\"" % safe_name, "color": [0.3, 1.0, 0.5], "duration": 3.0})
        host._combat_recorder.queue_free()
        host._combat_recorder = null
    if host.hud_control:
        host.hud_control.combat_recorder = null
        host.hud_control.training_round = 0

    if host._training_clone and is_instance_valid(host._training_clone):
        host._training_clone.queue_free()
    host._training_clone = null

    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()

    print("[Training] Saved after %d rounds, %d total frames" % [host._training_round, total_frames])

    _return_to_builder()

func on_fight_ai_requested(placed: Array, core_id: String, template_name: String, recording_path: String):
    var host = _h()
    var rec = CombatRecording.new()
    if not rec.load_from_file(recording_path):
        GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "Failed to load recording!", "color": [1.0, 0.3, 0.2], "duration": 3.0})
        return

    var tmpl = GameManager.get_template_by_name(template_name)
    var clone_modules: Array = []
    var _clone_core: String = core_id
    if not tmpl.is_empty():
        clone_modules = tmpl.get("modules", []).duplicate(true)
        _clone_core = tmpl.get("core_id", core_id)
    else:
        clone_modules = placed.duplicate(true)

    host._creative_saved_modules = GameManager.ship_modules.duplicate(true)
    host._creative_saved_core = GameManager.equipped_core
    host._creative_saved_fuel = GameManager.fuel
    host._creative_saved_credits = GameManager.credits
    host._creative_test_modules = placed.duplicate(true)
    host._creative_test_core = core_id
    host.creative_test_flying = true
    host._fight_ai_active = true
    host.builder_open = false
    GameManager.builder_open = false

    GameManager.equipped_core = core_id
    GameManager.ship_modules = placed.duplicate(true)
    GameManager.update_resource_capacity()
    GameManager.fuel = GameManager.fuel_capacity

    if host.player and is_instance_valid(host.player):
        host.player.queue_free()
    host.player = host.player_scene.instantiate()
    host.player.position = Vector2(50000, 50000)
    host.add_child(host.player)
    host.player.health_changed.connect(host._on_player_health_changed)
    host.player.destroyed.connect(host._on_player_destroyed)
    host.player.scan_pulse_hit.connect(host._on_scan_hit)
    host.player.apply_loadout(GameManager.ship_modules)
    host.player.shields = host.player.max_shields
    host.player.nearest_star_pos = Vector2(-999999, -999999)
    host.player.nearest_star_radius = 0.0
    if host.hud_control:
        host.hud_control.player = host.player

    var clone_pos = Vector2(50000 + 1200, 50000)
    var clone = host.player_scene.instantiate()
    clone.ai_controlled = true
    clone.position = clone_pos
    host.add_child(clone)
    var clone_cam = clone.get_node_or_null("Camera2D")
    if clone_cam:
        clone_cam.queue_free()
    for mod in clone_modules:
        mod.erase("hp")
        mod.erase("max_hp")
        mod.erase("damaged")
        mod.erase("destroyed")
    clone.apply_loadout(clone_modules)
    var ai = ClonedAI.new()
    ai.setup(rec, clone.max_speed)
    clone.cloned_ai = ai
    clone.nearest_star_pos = Vector2(-999999, -999999)
    clone.nearest_star_radius = 0.0
    clone.destroyed.connect(_on_fight_ai_clone_destroyed)
    host._fight_ai_clone = clone
    host._spawn_warp_portal(clone_pos, clone)

    GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "FIGHT!", "color": [0.3, 0.8, 1.0], "duration": 2.0})

func _on_fight_ai_clone_destroyed():
    var host = _h()
    if host._fight_ai_clone and is_instance_valid(host._fight_ai_clone):
        host._fight_ai_clone.set_process(false)
        host._fight_ai_clone.set_physics_process(false)
        host._fight_ai_clone.queue_free()
    host._fight_ai_clone = null
    GameManager.pending_barks.append({"speaker": "SYSTEM", "text": "CLONE DEFEATED!", "color": [0.2, 1.0, 0.4], "duration": 3.0})
    get_tree().create_timer(2.0, true, false, false).timeout.connect(func():
        if host._fight_ai_active:
            end_fight_ai()
    )

func end_fight_ai():
    var host = _h()
    host._fight_ai_active = false
    if host._fight_ai_clone and is_instance_valid(host._fight_ai_clone):
        host._fight_ai_clone.queue_free()
    host._fight_ai_clone = null
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e):
            e.queue_free()
    _return_to_builder()

func _return_to_builder():
    var host = _h()
    host.creative_test_flying = false
    host.creative_recording_ai = false
    host.creative_previewing_ai = false
    host.creative_training_ai = false
    host._fight_ai_active = false
    host._training_round = 0
    host._training_clone = null
    host._training_advance_pending = false
    host._recording_template_name = ""

    GameManager.equipped_core = host._creative_saved_core
    GameManager.ship_modules = host._creative_saved_modules
    GameManager.fuel = host._creative_saved_fuel
    GameManager.credits = host._creative_saved_credits
    GameManager.update_resource_capacity()
    if host.player and is_instance_valid(host.player):
        host.player.apply_loadout(GameManager.ship_modules)

    host._resume_creative_authoring(host._creative_test_core, host._creative_test_modules.duplicate(true))
