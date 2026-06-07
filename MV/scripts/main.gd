class_name MvMain
extends Node2D

signal camera_focus_finished

const RegIO = preload("res://Space/scripts/shared/reg/reg_io.gd")
const HUD_SCRIPT = preload("res://MV/scripts/hud.gd")

# Top-level game orchestrator for the MVMania planet layer. Ported from the
# C# Main with a heavy trim: flow scripts, effects, cutscenes, entity
# spawning, trigger engine, dialogue runner, HUD, boss HUD, editor overlay,
# and save/load are all deferred to the post-port rebuild. What's left is
# the core loop the user actually wants preserved:
#
#   1. Load the content pack in _enter_tree (so RoomManager._ready can read it)
#   2. Spawn the player at the first floor column of the start room
#   3. Tick the camera follow + initial fade-in
#   4. Run 3-phase door transitions (fade out → load room → fade in)
#   5. Hand control back to SSB when the player walks through an
#      "exit_to_space" tagged door
#
# The scene root (res://MV/scenes/main.tscn) expects these children:
#   RoomLayer (MvRoomManager), PlayerLayer, ForegroundLayer, Camera2D, FadeRect.

var _room_manager: MvRoomManager = null
var _camera: Camera2D = null
var _player: MvPlayer = null
var _fade_rect: ColorRect = null
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null
var _trigger_debug_overlay: CanvasLayer = null
var _hud: CanvasLayer = null
var _dev_console: MvDevConsole = null
var _edit_mode: MvEditMode = null

# Screen-shake state — see camera_shake() for the trigger entry point.
# _shake_intensity is the peak px offset at full strength; _shake_remaining
# decays toward zero and scales intensity for a natural taper-off.
# _shake_offset is the source of truth for the current frame's displacement;
# _physics_process applies it to _camera.offset each tick so a position-
# tweening pan and an active shake compose (pan owns position, shake owns
# offset) instead of one clobbering the other.
var _shake_intensity: float = 0.0
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

# Runtime viewport — the C# code swapped this between game (480x270) and
# editor (1280x720) sizes when the editor opened. Editor's deferred, so we
# only need the game size; keep the constant so a future re-add is trivial.
const GAME_VIEWPORT: Vector2i = Vector2i(480, 270)

var _transitioning: bool = false
var _fade: float = 1.0
var _fade_frame: int = 0
var _transition_phase: int = 0   # 0=idle, 1=fade-out, 2=load, 3=fade-in
var _transition_frame: int = 0
var _pending_door: Dictionary = {}
var _pending_source_room: String = ""
var _pending_target_link: Dictionary = {}
var _last_blocked_door_id: String = ""
var _last_blocked_door_msec: int = 0
var _camera_focus_mode: String = ""
var _camera_focus_target: String = ""
var _camera_focus_pos: Vector2 = Vector2.ZERO
var _camera_pan_active: bool = false
var _camera_pan_tween: Tween = null
# Live re-resolve state for room_variants. When a planet/global flag flips
# such that the current canonical addr would now resolve to a different
# variant than the one currently loaded, we record the canonical here and
# flush it (reload + reposition) once the defer gate clears. Always stores
# the canonical addr — load_room re-runs the resolver to pick the right
# variant for the current flag state at flush time.
var _pending_variant_swap_addr: String = ""
const FADE_OUT_FRAMES: int = 12
const FADE_IN_FRAMES: int = 18
const BLOCKED_DOOR_COOLDOWN_MS: int = 350


func _enter_tree() -> void:
    MvGame.main = self

    # Load the content pack BEFORE any child _ready runs. MvRoomManager
    # reads MvPackLoader.current_pack in its own _ready, so this has to
    # fire first. _enter_tree is top-down (parent before children), _ready
    # is bottom-up (children before parent) — so loading the pack here
    # puts it in place for every downstream _ready.
    #
    # pending_pack_id is set by PlanetaryInterface.begin_landing from the
    # SSB layer when the player interacts with a planet POI. Standalone
    # dev runs can still boot demo, but hosted landings must be explicit.
    var pack_id: String = PlanetaryInterface.pending_pack_id
    if pack_id.is_empty():
        if PlanetaryInterface.hosted:
            push_error("MvMain: hosted landing has no pending pack_id")
            return
        pack_id = "demo"
    var pack: MvPackRef = MvPackLoader.load_pack(pack_id)
    if pack == null:
        push_error("MvMain: failed to load '%s' pack in _enter_tree" % pack_id)


func _exit_tree() -> void:
    prepare_for_teardown()
    if MvGame.main == self:
        MvGame.main = null
    if MvGame.room_manager == _room_manager:
        MvGame.room_manager = null


func prepare_for_teardown() -> void:
    if _hud != null and is_instance_valid(_hud):
        _hud.visible = false


func _ready() -> void:
    if PlanetaryInterface.hosted:
        process_mode = Node.PROCESS_MODE_ALWAYS
    MvGame.simulation_paused = false

    # Only claim the root viewport when running standalone. When hosted
    # inside SSB's planet SubViewport, the parent project owns the root
    # viewport at 1920x1080 and the planet runs at 480x270 via the
    # container's stretch_shrink.
    if not PlanetaryInterface.hosted:
        get_tree().root.content_scale_size = GAME_VIEWPORT

    _room_manager = $RoomLayer as MvRoomManager
    _camera = $Camera2D
    _fade_rect = $FadeLayer/FadeRect
    if PlanetaryInterface.hosted:
        _room_manager.process_mode = Node.PROCESS_MODE_ALWAYS
        ($PlayerLayer as Node).process_mode = Node.PROCESS_MODE_ALWAYS
        ($ForegroundLayer as Node).process_mode = Node.PROCESS_MODE_ALWAYS
        ($FadeLayer as Node).process_mode = Node.PROCESS_MODE_ALWAYS
        _camera.process_mode = Node.PROCESS_MODE_ALWAYS
    # FadeRect is a fullscreen ColorRect in a CanvasLayer. Its default MouseFilter is STOP,
    # so its bounds would eat mouse events even when fully transparent.
    # The fade is purely visual; let input pass straight through.
    _fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _layout_fade_rect()
    _ensure_flash_overlay()
    if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
        get_viewport().size_changed.connect(_on_viewport_size_changed)
    _ensure_trigger_debug_overlay()
    _ensure_dev_console()
    _ensure_edit_mode()

    MvGame.room_manager = _room_manager

    # Hand the RoomManager the ForegroundLayer so Layer1 hi-priority tiles
    # render in front of the player (PlayerLayer is earlier in the tree).
    var fg_layer: Node2D = get_node_or_null("ForegroundLayer") as Node2D
    if fg_layer != null:
        _room_manager.attach_foreground_layer(fg_layer)

    # Spawn the player.
    var player_scene: PackedScene = load("res://MV/scenes/player.tscn")
    _player = player_scene.instantiate() as MvPlayer
    if PlanetaryInterface.hosted:
        _player.process_mode = Node.PROCESS_MODE_ALWAYS
    ($PlayerLayer as Node).add_child(_player)
    _player.entered_door.connect(_on_player_door)
    _player.player_died.connect(_on_player_died)

    # Apply ManiaVar stat effects to the player's physics profile before
    # the first room loads, so gravity/jump/speed reflect stat levels.
    if MvPackLoader.current_pack != null and MvPackLoader.current_pack.physics != null:
        StatsApplier.apply(_player, MvPackLoader.current_pack.physics)

    # Region props (music, gravity_mult, encounter hook) land here via
    # PlanetaryInterface when Space staged a landing. Cleared on consume.
    _apply_pending_region_meta()

    # Load the start room (no flow engine — MvRoomManager carries the
    # pack's start_room address directly).
    _room_manager.load_start_room()
    _ensure_hud()
    _setup_camera()

    var pack_id := MvPackLoader.current_pack.pack_id if MvPackLoader.current_pack != null else "demo"
    MvTriggerEngine.load_triggers(pack_id)
    if not MvTriggerEngine.action_spawn_entity.is_connected(_on_trigger_spawn_entity):
        MvTriggerEngine.action_spawn_entity.connect(_on_trigger_spawn_entity)
    if not MvTriggerEngine.action_despawn_entity.is_connected(_on_trigger_despawn_entity):
        MvTriggerEngine.action_despawn_entity.connect(_on_trigger_despawn_entity)
    if not MvTriggerEngine.action_spawn_entity_at_zone.is_connected(_on_trigger_spawn_entity_at_zone):
        MvTriggerEngine.action_spawn_entity_at_zone.connect(_on_trigger_spawn_entity_at_zone)
    if not MvTriggerEngine.action_move_entity_to_zone.is_connected(_on_trigger_move_entity_to_zone):
        MvTriggerEngine.action_move_entity_to_zone.connect(_on_trigger_move_entity_to_zone)
    if not MvTriggerEngine.action_play_entity_anim.is_connected(_on_trigger_play_entity_anim):
        MvTriggerEngine.action_play_entity_anim.connect(_on_trigger_play_entity_anim)
    if not MvTriggerEngine.action_set_entity_facing.is_connected(_on_trigger_set_entity_facing):
        MvTriggerEngine.action_set_entity_facing.connect(_on_trigger_set_entity_facing)
    if not MvTriggerEngine.action_camera_focus.is_connected(_on_trigger_camera_focus):
        MvTriggerEngine.action_camera_focus.connect(_on_trigger_camera_focus)
    if not MvTriggerEngine.action_camera_unlock.is_connected(_on_trigger_camera_unlock):
        MvTriggerEngine.action_camera_unlock.connect(_on_trigger_camera_unlock)
    if not MvTriggerEngine.action_set_room_weather.is_connected(_on_trigger_set_room_weather):
        MvTriggerEngine.action_set_room_weather.connect(_on_trigger_set_room_weather)
    # Live re-resolve for room_variants: every planet/global flag write
    # routes here so we can check whether the current room's variant
    # resolution changed. Slice 3 owns the defer-and-flush path; slice 2
    # already handles the swap on room entry.
    if PlanetaryInterface.has_signal("flag_changed") \
            and not PlanetaryInterface.flag_changed.is_connected(_on_flag_changed_for_variants):
        PlanetaryInterface.flag_changed.connect(_on_flag_changed_for_variants)
    _fade = 1.0
    _fade_frame = 0

    print("MVMania — pack loaded, game state online")

    # After the initial room load + player spawn, hand control to the
    # PlanetaryInterface so it can rehydrate any pending per-planet
    # snapshot (player position, hp). No-op on fresh boots and first visits.
    var restored_snapshot: bool = PlanetaryInterface.restore_pending_if_any(self)
    var restored_player_progression: bool = PlanetaryInterface.has_method("has_player_progression_snapshot") \
        and bool(PlanetaryInterface.call("has_player_progression_snapshot"))

    # Editor playtest handoff: if the env editor staged a spawn room via
    # begin_landing, load that instead of start_room. This runs AFTER
    # restore_pending_if_any so it wins over any stale per-planet snapshot.
    # Pass Vector2(-1, -1) for the position so load_from_snapshot falls back
    # to the room's player_spawn entity (single source of truth for where
    # the player materializes inside a room).
    var playtest_spawn_override: bool = false
    var has_spawn_override: bool = not PlanetaryInterface.pending_spawn_room.is_empty()
    if has_spawn_override and (PlanetaryInterface.pending_return_to_editor or not restored_snapshot):
        var target_room: String = PlanetaryInterface.pending_spawn_room
        playtest_spawn_override = PlanetaryInterface.pending_return_to_editor
        PlanetaryInterface.pending_spawn_room = ""
        load_from_snapshot(target_room, Vector2(-1, -1), -1)
    elif has_spawn_override:
        PlanetaryInterface.pending_spawn_room = ""

    var boot_room_addr: String = _room_manager.current_room_addr() if _room_manager != null else ""
    var startup_payload: Dictionary = {
        "room": boot_room_addr,
        "fresh_boot": not restored_snapshot and not playtest_spawn_override and not restored_player_progression,
        "restored_snapshot": restored_snapshot,
        "restored_player_progression": restored_player_progression,
        "playtest_spawn_override": playtest_spawn_override,
    }
    if bool(startup_payload["fresh_boot"]):
        if _player != null:
            _player.set_locked(true)
        var intro_authored: bool = MvTriggerEngine.fire_event("new_game_started", startup_payload)
        startup_payload["intro_authored"] = intro_authored
        if not intro_authored:
            spawn_player(Vector2(-1, -1), boot_room_addr)
            if _player != null:
                _player.set_locked(false)
    else:
        startup_payload["intro_authored"] = false
        if _player != null:
            _player.set_locked(false)
    MvTriggerEngine.fire_event("game_started", startup_payload)


func _input(event: InputEvent) -> void:
    # Ctrl+9 — return to the environment editor. Only fires when
    # pending_return_to_editor is set (i.e. we entered MV via the editor's
    # playtest handoff). Scene-changes back to Space; Space main._ready
    # notices the flag and re-opens environment_editor at the stashed
    # pack/region/room.
    if event is InputEventKey and event.pressed and not event.echo:
        var ke: InputEventKey = event
        if ke.keycode == KEY_9 and ke.ctrl_pressed and not ke.shift_pressed and not ke.alt_pressed:
            if PlanetaryInterface.pending_return_to_editor:
                get_viewport().set_input_as_handled()
                get_tree().change_scene_to_file.call_deferred("res://Space/scenes/main.tscn")
        elif ke.keycode == KEY_QUOTELEFT and not ke.ctrl_pressed and not ke.alt_pressed:
            if _dev_console != null:
                get_viewport().set_input_as_handled()
                _dev_console.toggle()
        elif ke.keycode == KEY_F2 and not ke.ctrl_pressed and not ke.alt_pressed:
            if _edit_mode != null:
                get_viewport().set_input_as_handled()
                _edit_mode.toggle()


func _physics_process(_delta: float) -> void:
    if _player == null:
        return

    # Camera follow is gated behind !simulation_paused so a future editor
    # overlay can drive its own pan/zoom without Main re-snapping the
    # camera to the player every physics tick.
    if not MvGame.simulation_paused and not _camera_pan_active:
        _camera.position = _resolve_camera_focus_position()

    _tick_camera_shake(get_physics_process_delta_time())
    # Apply the shake offset to the camera every tick so pan tweens
    # (which animate position) and shake (which owns offset) compose.
    # Pan-finished / focus-reset code no longer touches offset directly.
    if _camera != null:
        _camera.offset = _shake_offset

    # Initial room fade-in (black → clear over 30 frames).
    if _fade > 0.0 and _transition_phase == 0:
        _fade_frame += 1
        _fade = 1.0 - float(_fade_frame) / 30.0
        if _fade < 0.0:
            _fade = 0.0
        _fade_rect.color = Color(0.0, 0.0, 0.0, _fade)

    _tick_door_transition()
    _tick_pending_variant_swap()


# ===== Room variant live re-resolve =====
#
# When a planet/global flag flips while the player is inside a room whose
# canonical addr has room_variants rules, the resolution may change. We
# detect that, capture the canonical addr as pending, and flush it during
# _physics_process once the defer gate clears so we don't yank the rug
# out from under an active dialogue / cinematic / trigger sequence.

# Handler for PlanetaryInterface.flag_changed. Cheap check: ask the room
# manager what the canonical currently resolves to with the new flag
# state; if that's different from what's loaded, queue a swap. We always
# store the canonical addr — load_room() re-runs the resolver at flush
# time, so even if more flags flip while the swap is queued the resolver
# picks whichever variant matches at the moment of flush.
func _on_flag_changed_for_variants(_scope: String, _name: String, _old: Variant, _new: Variant) -> void:
    if _room_manager == null:
        return
    var canonical: String = _room_manager.current_room_addr()
    if canonical.is_empty():
        return
    var resolved_now: String = _room_manager.resolve_room_variant(canonical)
    var currently_loaded: String = _room_manager._current_loaded_room_addr()
    if resolved_now == currently_loaded:
        # No-op: flag changed but the rule outcome didn't.
        return
    _pending_variant_swap_addr = canonical


func _tick_pending_variant_swap() -> void:
    if _pending_variant_swap_addr.is_empty():
        return
    if not _can_apply_variant_swap_now():
        return
    var canonical: String = _pending_variant_swap_addr
    _pending_variant_swap_addr = ""
    _execute_variant_swap(canonical)


# Defer gate: hold the swap while the player is mid-flow so we don't
# yank state out from under anything that's mid-execution. The flag
# change is already recorded in PlanetaryInterface — flushing later
# picks up whatever variant resolves at that point.
func _can_apply_variant_swap_now() -> bool:
    if _transitioning:
        return false  # mid door transition; let it finish
    if MvGame.simulation_paused:
        return false  # editor overlay / pause menu open
    if _camera_pan_active:
        return false  # scripted camera pan in flight
    if MvDialogueRunner != null and MvDialogueRunner.is_active():
        return false
    if MvTriggerEngine != null and not MvTriggerEngine.get_active_sequences().is_empty():
        return false
    if _player != null and _player.has_method("is_scripted_move_active") \
            and bool(_player.call("is_scripted_move_active")):
        return false
    return true


# Executes the swap: capture the player's current position, reload the
# canonical addr (so the room manager re-resolves to whatever variant
# matches the live flag state right now), then place the player at the
# captured position clamped to the new room's bounds. A brief screen
# flash makes the swap visible without a full fade-out cycle.
func _execute_variant_swap(canonical: String) -> void:
    if _room_manager == null or _player == null:
        return
    var captured_pos: Vector2 = _player.position
    var captured_facing: String = ""
    if _player.has_method("get_facing_direction"):
        captured_facing = str(_player.call("get_facing_direction"))
    _room_manager.load_room(canonical)
    _setup_camera()
    var clamped: Vector2 = _clamp_pos_to_room(captured_pos, _room_manager.current_room())
    _player.spawn_at(clamped, "", captured_facing)
    _flash_variant_swap()
    print("MvMain: variant swap applied for '%s' -> loaded '%s'" % [canonical, _room_manager._current_loaded_room_addr()])


# Clamps a coordinate to lie inside a room's pixel bounds, with a small
# inset so the player doesn't land flush against a wall. Falls back to
# the input pos when the room has no usable size metadata.
func _clamp_pos_to_room(pos: Vector2, room: Dictionary) -> Vector2:
    if room.is_empty():
        return pos
    var wpx: float = float(room.get("width_px", 0))
    var hpx: float = float(room.get("height_px", 0))
    var out := pos
    if wpx > 0.0:
        out.x = clampf(out.x, 8.0, maxf(8.0, wpx - 8.0))
    if hpx > 0.0:
        out.y = clampf(out.y, 16.0, maxf(16.0, hpx - 16.0))
    return out


# Brief white flash via the existing _flash_rect overlay. Reuses the
# screen_flash plumbing but with a short, fixed duration so the swap
# reads as deliberate rather than visually jarring.
func _flash_variant_swap() -> void:
    _ensure_flash_overlay()
    if _flash_rect == null:
        return
    if _flash_tween != null and _flash_tween.is_valid():
        _flash_tween.kill()
    _flash_rect.color = Color(1.0, 1.0, 1.0, 0.45)
    _flash_tween = create_tween()
    _flash_tween.tween_property(_flash_rect, "color", Color(0, 0, 0, 0), 0.18)


func _on_viewport_size_changed() -> void:
    _layout_fade_rect()


func _layout_fade_rect() -> void:
    if _fade_rect == null:
        return
    _fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    if _flash_rect != null:
        _flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# Lazy-create a fullscreen ColorRect sibling of _fade_rect on the same
# FadeLayer CanvasLayer. Used by screen_flash trigger action.
func _ensure_flash_overlay() -> void:
    if _flash_rect != null and is_instance_valid(_flash_rect):
        return
    var layer: Node = get_node_or_null("FadeLayer")
    if layer == null:
        return
    _flash_rect = ColorRect.new()
    _flash_rect.color = Color(0, 0, 0, 0)
    _flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(_flash_rect)


# Triggered by the camera_shake action. Adds a decaying random offset to
# the active camera so explosions/impacts feel weighty without touching
# camera.position (which the follow code re-snaps every physics tick).
func camera_shake(intensity: float, duration: float) -> void:
    if _camera == null:
        return
    if duration <= 0.0 or intensity <= 0.0:
        return
    _shake_intensity = maxf(_shake_intensity, intensity)
    _shake_remaining = maxf(_shake_remaining, duration)
    _shake_duration = maxf(_shake_duration, duration)


# Triggered by the screen_flash action. Sets _flash_rect to `color`, then
# tweens its alpha to zero over `duration` seconds. A new flash interrupts
# any in-flight tween so back-to-back flashes don't queue forever.
func screen_flash(color: Color, duration: float) -> void:
    _ensure_flash_overlay()
    if _flash_rect == null:
        return
    if _flash_tween != null and _flash_tween.is_valid():
        _flash_tween.kill()
    _flash_rect.color = color
    if duration <= 0.0:
        _flash_rect.color = Color(color.r, color.g, color.b, 0.0)
        return
    _flash_tween = create_tween()
    _flash_tween.tween_property(_flash_rect, "color:a", 0.0, duration)


func _tick_camera_shake(delta: float) -> void:
    if _shake_remaining <= 0.0:
        return
    _shake_remaining = maxf(0.0, _shake_remaining - delta)
    var falloff: float = (_shake_remaining / _shake_duration) if _shake_duration > 0.0 else 0.0
    var amt: float = _shake_intensity * falloff
    if amt <= 0.0001:
        _shake_offset = Vector2.ZERO
        _shake_intensity = 0.0
        _shake_duration = 0.0
        return
    _shake_offset = Vector2(randf_range(-amt, amt), randf_range(-amt, amt))


func _ensure_trigger_debug_overlay() -> void:
    if _trigger_debug_overlay != null:
        return
    _trigger_debug_overlay = CanvasLayer.new()
    _trigger_debug_overlay.set_script(preload("res://MV/scripts/trigger_debug_overlay.gd"))
    add_child(_trigger_debug_overlay)


func _ensure_hud() -> void:
    if _hud != null:
        return
    _hud = CanvasLayer.new()
    _hud.set_script(HUD_SCRIPT)
    add_child(_hud)


func _ensure_dev_console() -> void:
    if _dev_console != null:
        return
    _dev_console = MvDevConsole.new()
    _dev_console.layer = 128
    add_child(_dev_console)


func _ensure_edit_mode() -> void:
    if _edit_mode != null:
        return
    _edit_mode = MvEditMode.new()
    add_child(_edit_mode)


# Player world position for the dev console's `spawn` command (slice 1).
func get_player_position() -> Vector2:
    if _player != null and is_instance_valid(_player):
        return _player.global_position
    return Vector2.ZERO


# ===== Region meta =====

# Loads the region meta for PlanetaryInterface.pending_region_id (the
# authoritative region target for this landing) and applies music/gravity
# overrides. Does NOT clear pending_region_id — _resolve_current_region_id
# falls back to it later in the boot flow.
func _apply_pending_region_meta() -> void:
    var region_id: String = PlanetaryInterface.pending_region_id.strip_edges()
    if region_id.is_empty():
        return
    var pack: MvPackRef = MvPackLoader.current_pack
    if pack == null:
        return
    var meta: Dictionary = RegIO.load_region(pack.pack_id, region_id)
    if meta.is_empty():
        return

    var music_id: String = str(meta.get("music_id", ""))
    if music_id != "":
        var am: Node = get_node_or_null("/root/AudioManager")
        if am != null and am.has_method("set_ambient"):
            am.set_ambient(music_id)

    var gravity_mult: float = float(meta.get("gravity_mult", 1.0))
    if absf(gravity_mult - 1.0) > 0.0001 and pack.physics != null:
        pack.physics.gravity *= gravity_mult
        if _player != null and _player.has_method("set_physics_profile"):
            _player.set_physics_profile(pack.physics)

    MvTriggerEngine.fire_event("region_enter", {
        "region_id": region_id,
        "music_id": music_id,
        "encounter_id": str(meta.get("encounter_id", "")),
        "visual_theme": str(meta.get("visual_theme", "")),
        "hazard_type": str(meta.get("hazard_type", "")),
        "gravity_mult": gravity_mult,
    })


# ===== Player spawn =====

func _spawn_player_in_room() -> void:
    if _player == null or _room_manager == null:
        return
    var room: Dictionary = _room_manager.current_room()
    var spawn_pos := _default_player_spawn_position(room)
    if spawn_pos.x < 0.0 or spawn_pos.y < 0.0:
        return
    _player.spawn_at(spawn_pos, "", _default_player_spawn_facing(room))


func spawn_player(pos: Vector2 = Vector2(-1, -1), room_addr: String = "",
        zone_id: String = "", entry_direction: String = "", fire_trigger: bool = true,
        facing_direction: String = "") -> bool:
    if _room_manager == null or _player == null:
        return false
    var target_room_addr := room_addr.strip_edges()
    if not target_room_addr.is_empty() and target_room_addr != _room_manager.current_room_addr():
        _room_manager.load_room(target_room_addr)
        _setup_camera()
    var room: Dictionary = _room_manager.current_room()
    var spawn_pos := pos
    var zone_ref := zone_id.strip_edges()
    var spawn_facing: String = facing_direction.strip_edges().to_lower()
    if not zone_ref.is_empty():
        spawn_pos = _room_manager.resolve_zone_position(zone_ref)
    if spawn_pos.x < 0.0 or spawn_pos.y < 0.0:
        spawn_pos = _default_player_spawn_position(room)
        if spawn_facing.is_empty():
            spawn_facing = _default_player_spawn_facing(room)
    if spawn_pos.x < 0.0 or spawn_pos.y < 0.0:
        return false
    _player.spawn_at(spawn_pos, entry_direction.strip_edges(), spawn_facing)
    if fire_trigger:
        MvTriggerEngine.fire_event("player_spawn", {
            "room": _room_manager.current_room_addr(),
            "x": spawn_pos.x,
            "y": spawn_pos.y,
            "zone_id": zone_ref,
        })
    return true


func _default_player_spawn_position(room: Dictionary) -> Vector2:
    if room.is_empty():
        return Vector2(-1, -1)
    var spawn_pos := _find_player_spawn_in_room(room)
    if spawn_pos.x >= 0.0 and spawn_pos.y >= 0.0:
        return spawn_pos
    return _fallback_player_spawn_position(room)


func _default_player_spawn_facing(room: Dictionary) -> String:
    var spawn_entity: Dictionary = _find_player_spawn_entity(room)
    if spawn_entity.is_empty():
        return ""
    var props_v: Variant = spawn_entity.get("properties", {})
    if typeof(props_v) != TYPE_DICTIONARY:
        return ""
    var props: Dictionary = props_v
    var facing: String = str(props.get("facing", "")).strip_edges().to_lower()
    if facing == "left" or facing == "right":
        return facing
    return ""


func _fallback_player_spawn_position(room: Dictionary) -> Vector2:
    var collision_v: Variant = room.get("collision", [])
    if typeof(collision_v) == TYPE_ARRAY:
        var collision: Array = collision_v
        if not collision.is_empty() and typeof(collision[0]) == TYPE_ARRAY:
            var rows: int = collision.size()
            var cols: int = (collision[0] as Array).size()
            for r in range(1, rows):
                for c in range(cols):
                    if _is_floor_at(int(collision[r][c])) and not _is_floor_at(int(collision[r - 1][c])):
                        return Vector2(float(c * 16 + 8), float(r * 16))
    var wpx: float = float(room.get("width_px", 0))
    var hpx: float = float(room.get("height_px", 0))
    if wpx <= 0.0 or hpx <= 0.0:
        return Vector2(-1, -1)
    return Vector2(wpx / 2.0, hpx / 2.0)


func _find_player_spawn_in_room(room: Dictionary) -> Vector2:
    var entity: Dictionary = _find_player_spawn_entity(room)
    if entity.is_empty():
        return Vector2(-1, -1)
    return _player_spawn_position_from_entity(entity)


func _find_player_spawn_entity(room: Dictionary) -> Dictionary:
    var entities_v: Variant = room.get("entities", [])
    if typeof(entities_v) != TYPE_ARRAY:
        return {}
    for entity_v in entities_v:
        if typeof(entity_v) != TYPE_DICTIONARY:
            continue
        var entity: Dictionary = entity_v
        if str(entity.get("type", "")).strip_edges() != "player_spawn":
            continue
        return entity
    return {}


func _player_spawn_position_from_entity(entity: Dictionary) -> Vector2:
    if entity.has("x") and entity.has("y"):
        return Vector2(float(entity.get("x", -1.0)), float(entity.get("y", -1.0)))
    var pos_v: Variant = entity.get("position", null)
    if pos_v is Vector2:
        return pos_v
    if typeof(pos_v) == TYPE_DICTIONARY:
        return Vector2(float(pos_v.get("x", -1.0)), float(pos_v.get("y", -1.0)))
    if typeof(pos_v) == TYPE_ARRAY:
        var pos_arr: Array = pos_v
        if pos_arr.size() >= 2:
            return Vector2(float(pos_arr[0]), float(pos_arr[1]))
    return Vector2(-1, -1)


func _setup_camera() -> void:
    refresh_camera_limits()


# Reset Camera2D limits to the current room's pixel bounds. Public so a
# future editor can call it after closing.
func refresh_camera_limits() -> void:
    var room: Dictionary = _room_manager.current_room()
    if _camera == null or room.is_empty():
        return
    _camera.limit_left = 0
    _camera.limit_top = 0
    _camera.limit_right = int(room["width_px"])
    _camera.limit_bottom = int(room["height_px"])


func _resolve_camera_focus_position() -> Vector2:
    if _camera_focus_mode.is_empty() or _camera_focus_mode == "player":
        return _player.position if _player != null else Vector2.ZERO
    if _camera_focus_mode == "position":
        return _camera_focus_pos
    if _camera_focus_mode == "entity" and _room_manager != null:
        var node := _room_manager.find_entity_node(_camera_focus_target)
        if node != null:
            return node.position
    elif _camera_focus_mode == "zone" and _room_manager != null:
        var pos := _room_manager.resolve_zone_position(_camera_focus_target)
        if pos.x >= 0.0 and pos.y >= 0.0:
            return pos
    return _player.position if _player != null else Vector2.ZERO


func _stop_camera_pan() -> void:
    _camera_pan_active = false
    if _camera_pan_tween != null:
        _camera_pan_tween.kill()
        _camera_pan_tween = null


func _set_camera_focus(mode: String, target_ref: String = "", pos: Vector2 = Vector2.ZERO,
        duration: float = 0.0, speed: float = 0.0) -> void:
    _camera_focus_mode = mode
    _camera_focus_target = target_ref.strip_edges()
    _camera_focus_pos = pos
    var target_pos := _resolve_camera_focus_position()
    _stop_camera_pan()
    if _camera == null:
        return
    if speed > 0.0:
        duration = _camera.position.distance_to(target_pos) / speed
    if duration <= 0.0:
        _camera.position = target_pos
        camera_focus_finished.emit()
        return
    _camera_pan_active = true
    _camera_pan_tween = create_tween()
    _camera_pan_tween.tween_property(_camera, "position", target_pos, duration)
    _camera_pan_tween.finished.connect(_on_camera_pan_finished)


func _on_camera_pan_finished() -> void:
    _camera_pan_active = false
    _camera_pan_tween = null
    if _camera != null:
        _camera.position = _resolve_camera_focus_position()
    camera_focus_finished.emit()


# ===== External control =====

# Trigger-action target: move the player to a new world position (and
# optionally a different room). Used by teleport_player trigger actions
# and by future cutscenes / scripted sequences.
func teleport_player(pos: Vector2, room_addr: String = "") -> void:
    if not room_addr.is_empty() and room_addr != _room_manager.current_room_addr():
        _room_manager.load_room(room_addr)
        _setup_camera()
    if _player != null:
        _player.spawn_at(pos)


# Hot-swap the player's physics profile. Used by a set_physics trigger.
func set_player_physics_profile(profile: MvPhysicsProfile) -> void:
    if _player != null:
        _player.set_physics_profile(profile)


# Public wrapper so a future editor can switch the runtime to a freshly-
# created room after ReloadRooms has picked up the new entry.
func load_room_by_addr(addr: String) -> void:
    _room_manager.load_room(addr)
    _setup_camera()
    _spawn_player_in_room()


# Fires the region_exit trigger event for the active region (if any) and
# hands off to PlanetaryInterface.begin_launch. Use this from anywhere
# that previously called begin_launch directly so authors can react to
# leaving a region without each call site re-implementing the event.
func launch_to_space() -> void:
    var region_id := _resolve_current_region_id()
    if not region_id.is_empty():
        MvTriggerEngine.fire_event("region_exit", {"region_id": region_id})
    PlanetaryInterface.begin_launch(self)


# Dev hotkey entry point for the SSB F9 force-launch: bounce out of the
# planet without going through a door.
func debug_force_launch_from_here() -> void:
    launch_to_space()


# ===== Snapshot helpers (post-port rebuild target) =====

func get_current_room_addr() -> String:
    if _room_manager == null:
        return ""
    return _room_manager.current_room_addr()


func get_player_snapshot() -> Dictionary:
    var d: Dictionary = {}
    if _player == null:
        return d
    d["x"] = _player.position.x
    d["y"] = _player.position.y
    d["hp"] = _player.hp
    d["max_hp"] = _player.max_hp
    return d


# Returns the region id this MV session is tied to. First tries the
# current room addr (region-prefixed in the flattened pack), then falls
# back to PlanetaryInterface.pending_region_id (set by SSB on landing),
# then to the pack's default region. Used by trigger/door code that needs
# to resolve bare room addresses against "the current region".
func _resolve_current_region_id() -> String:
    var room_addr: String = get_current_room_addr()
    var parsed: Dictionary = RegIO.parse_room_addr(room_addr)
    var from_addr: String = str(parsed.get("region_id", "")).strip_edges()
    if not from_addr.is_empty():
        return from_addr
    var pending: String = PlanetaryInterface.pending_region_id.strip_edges()
    if not pending.is_empty():
        return pending
    var pack: MvPackRef = MvPackLoader.current_pack
    if pack == null:
        return ""
    return RegIO.default_region_id(pack.pack_id)


func _on_trigger_spawn_entity(entity_id: String, pos: Vector2, data: Dictionary) -> void:
    if _room_manager == null:
        return
    var entity_tags: Array = data.get("tags", [])
    var entity_props: Dictionary = data.get("properties", {})
    _room_manager.spawn_entity_dynamic(entity_id, pos, entity_tags, entity_props)


func _on_trigger_despawn_entity(entity_id: String) -> void:
    if _room_manager == null:
        return
    _room_manager.despawn_entity_by_id(entity_id)


func _on_trigger_spawn_entity_at_zone(entity_id: String, zone_id: String, data: Dictionary) -> void:
    if _room_manager == null:
        return
    _room_manager.spawn_entity_at_zone(entity_id, zone_id, data)


func _on_trigger_move_entity_to_zone(entity_ref: String, zone_id: String, speed: float) -> void:
    if _room_manager == null:
        return
    if entity_ref == "player" and _player != null:
        var pos := _room_manager.resolve_zone_position(zone_id)
        if pos.x >= 0.0 and pos.y >= 0.0:
            _player.begin_scripted_move(pos, speed)
        return
    _room_manager.move_entity_to_zone(entity_ref, zone_id, speed)


func _on_trigger_play_entity_anim(entity_ref: String, anim_name: String, loop: bool, speed_scale: float) -> void:
    if _room_manager == null:
        return
    if entity_ref == "player" and _player != null:
        _player.play_scripted_animation(anim_name, loop, speed_scale)
        return
    _room_manager.play_entity_animation(entity_ref, anim_name, loop, speed_scale)


func _on_trigger_set_entity_facing(entity_ref: String, direction: String, zone_id: String) -> void:
    var facing_dir: float = 0.0
    var dir_mode: String = direction.strip_edges().to_lower()
    match dir_mode:
        "left":
            facing_dir = -1.0
        "right":
            facing_dir = 1.0
        "toward_zone", "away_from_zone":
            if _room_manager == null:
                return
            var zone_pos := _room_manager.resolve_zone_position(zone_id)
            if zone_pos.x < 0.0 or zone_pos.y < 0.0:
                return
            var origin := _player.position if entity_ref == "player" and _player != null else Vector2.ZERO
            if entity_ref != "player":
                var node := _room_manager.find_entity_node(entity_ref)
                if node == null:
                    return
                origin = node.position
            facing_dir = signf(zone_pos.x - origin.x)
            if dir_mode == "away_from_zone":
                facing_dir *= -1.0
        _:
            return
    if absf(facing_dir) < 0.001:
        return
    if entity_ref == "player" and _player != null:
        if _player.has_method("set_scripted_facing"):
            _player.set_scripted_facing(facing_dir)
        return
    if _room_manager == null:
        return
    var target := _room_manager.find_entity_node(entity_ref)
    if target == null:
        return
    if target.has_method("set_scripted_facing"):
        target.call("set_scripted_facing", facing_dir)
    elif target.has_method("ai_face_dir"):
        target.call("ai_face_dir", facing_dir)


func _on_trigger_camera_focus(mode: String, target_ref: String, pos: Vector2,
        duration: float, speed: float) -> void:
    _set_camera_focus(mode, target_ref, pos, duration, speed)


func _on_trigger_camera_unlock() -> void:
    _camera_focus_mode = ""
    _camera_focus_target = ""
    _camera_focus_pos = Vector2.ZERO
    _stop_camera_pan()
    if _camera != null:
        _camera.position = _resolve_camera_focus_position()
    camera_focus_finished.emit()


func _on_trigger_set_room_weather(room_addr: String, preset: String, color: String,
        intensity: float, speed: float) -> void:
    if _room_manager == null:
        return
    _room_manager.set_room_weather(room_addr, {
        "preset": preset,
        "color": color,
        "intensity": intensity,
        "speed": speed,
    })


func _resolve_trigger_actor(entity_ref: String) -> Node:
    var trimmed: String = entity_ref.strip_edges()
    if trimmed == "player":
        return _player
    if _room_manager == null:
        return null
    return _room_manager.find_entity_node(trimmed)


func wait_for_scripted_move(entity_ref: String, timeout: float = 0.0) -> bool:
    var target: Node = _resolve_trigger_actor(entity_ref)
    if target == null:
        return false
    if target.has_method("is_scripted_move_active"):
        var active_v: Variant = target.call("is_scripted_move_active")
        if typeof(active_v) == TYPE_BOOL and not bool(active_v):
            return true
        if timeout > 0.0:
            var started_ms: int = Time.get_ticks_msec()
            while true:
                var still_active_v: Variant = target.call("is_scripted_move_active")
                if typeof(still_active_v) == TYPE_BOOL and not bool(still_active_v):
                    return true
                var elapsed: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
                if elapsed >= timeout:
                    return false
                await get_tree().process_frame
    if not target.has_signal("scripted_move_finished"):
        return false
    await target.scripted_move_finished
    return true


func wait_for_scripted_animation(entity_ref: String, anim_name: String = "", timeout: float = 0.0) -> bool:
    var target: Node = _resolve_trigger_actor(entity_ref)
    if target == null:
        return false
    var wanted: String = anim_name.strip_edges()
    if target.has_method("is_scripted_animation_active"):
        var active_v: Variant = target.call("is_scripted_animation_active")
        if typeof(active_v) == TYPE_BOOL and not bool(active_v):
            return true
    if not wanted.is_empty() and target.has_method("current_scripted_animation_name"):
        var current_v: Variant = target.call("current_scripted_animation_name")
        if str(current_v).strip_edges() != wanted:
            return true
    if timeout > 0.0 and target.has_method("is_scripted_animation_active"):
        var started_ms: int = Time.get_ticks_msec()
        while true:
            var active_now: Variant = target.call("is_scripted_animation_active")
            if typeof(active_now) == TYPE_BOOL and not bool(active_now):
                return true
            if not wanted.is_empty() and target.has_method("current_scripted_animation_name"):
                var current_name_v: Variant = target.call("current_scripted_animation_name")
                if str(current_name_v).strip_edges() != wanted:
                    return true
            var elapsed: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
            if elapsed >= timeout:
                return false
            await get_tree().process_frame
    if not target.has_signal("scripted_animation_finished"):
        return false
    while true:
        var finished_name: Variant = await target.scripted_animation_finished
        if wanted.is_empty() or str(finished_name).strip_edges() == wanted:
            return true
    return false


func wait_for_camera_focus(timeout: float = 0.0) -> bool:
    if not _camera_pan_active:
        return true
    if timeout <= 0.0:
        await camera_focus_finished
        return true
    var started_ms: int = Time.get_ticks_msec()
    while _camera_pan_active:
        var elapsed: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
        if elapsed >= timeout:
            return false
        await get_tree().process_frame
    return true


func wait_for_dialogue(timeout: float = 0.0) -> bool:
    if MvDialogueRunner == null or not MvDialogueRunner.has_method("is_active"):
        return false
    if not MvDialogueRunner.is_active():
        return true
    if timeout <= 0.0:
        await MvDialogueRunner.dialogue_finished
        return true
    var started_ms: int = Time.get_ticks_msec()
    while MvDialogueRunner.is_active():
        var elapsed: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
        if elapsed >= timeout:
            return false
        await get_tree().process_frame
    return true


func load_from_snapshot(room_addr: String, pos: Vector2, hp: int, max_hp: int = -1) -> void:
    if not room_addr.is_empty() and room_addr != _room_manager.current_room_addr():
        _room_manager.load_room(room_addr)
        _setup_camera()
    if _player != null:
        if pos.x >= 0.0 and pos.y >= 0.0:
            _player.spawn_at(pos)
        else:
            _spawn_player_in_room()
        if max_hp > 0:
            _player.max_hp = max_hp
        if hp > 0:
            _player.hp = mini(hp, _player.max_hp)


# ===== Door transitions =====

func _on_player_door(door_id: String) -> void:
    if _player.is_locked():
        return
    var door: Dictionary = _room_manager.find_door_by_id(door_id) if _room_manager != null and _room_manager.has_method("find_door_by_id") else {}
    if door.is_empty():
        return
    if _blocked_door_attempt_is_throttled(door):
        return
    var payload := _build_door_payload(door)
    MvTriggerEngine.fire_event("door_use_attempt", payload)

    var enabled := _door_enabled(door)
    var locked := _door_locked(door)
    payload["enabled"] = enabled
    payload["locked"] = locked
    if not enabled:
        payload["block_reason"] = "disabled"
        _remember_blocked_door(door)
        _fire_blocked_door_events(door, payload)
        return
    if locked and not _door_access_granted(door):
        payload["block_reason"] = "locked"
        _remember_blocked_door(door)
        _fire_blocked_door_events(door, payload)
        return

    _last_blocked_door_id = ""
    MvTriggerEngine.fire_event("door_use_success", payload)
    MvTriggerEngine.fire_event("door_enter", payload)
    _fire_custom_door_event(str(door.get("success_event_name", "")).strip_edges(), payload)
    start_door_transition(door)


func start_door_transition(door_override: Dictionary = {}) -> void:
    if _transitioning:
        return
    var door: Dictionary = door_override
    if door.is_empty():
        return

    _transitioning = true
    _pending_door = door
    _pending_source_room = _room_manager.current_room_addr() if _room_manager != null else ""
    _pending_target_link = _resolve_door_target_link(door)
    _transition_phase = 1
    _transition_frame = 0
    _player.velocity = Vector2.ZERO
    _player.set_locked(true)


func _tick_door_transition() -> void:
    if _transition_phase == 0:
        return
    _transition_frame += 1

    if _transition_phase == 1:
        var t := clampf(float(_transition_frame) / float(FADE_OUT_FRAMES), 0.0, 1.0)
        _fade_rect.color = Color(0.0, 0.0, 0.0, t)
        if _transition_frame >= FADE_OUT_FRAMES:
            if not _load_destination_room():
                return
            _transition_phase = 3
            _transition_frame = 0
    elif _transition_phase == 3:
        var t := clampf(1.0 - float(_transition_frame) / float(FADE_IN_FRAMES), 0.0, 1.0)
        _fade_rect.color = Color(0.0, 0.0, 0.0, t)
        if _transition_frame >= FADE_IN_FRAMES:
            _transition_phase = 0
            _transitioning = false
            _pending_door = {}
            _pending_source_room = ""
            _pending_target_link = {}


func _cleanup_room_transition_projectiles() -> void:
    if _player != null and _player.has_method("cleanup_room_transition_transients"):
        _player.call("cleanup_room_transition_transients")
    var queued: Dictionary = {}
    _queue_free_transition_group_nodes("mv_projectile", queued)
    _queue_free_transition_group_nodes("mv_grenade", queued)
    var root: Node = get_tree().current_scene
    if root == null:
        root = self
    _queue_free_transition_projectiles_recursive(root, queued)


func _queue_free_transition_group_nodes(group_name: String, queued: Dictionary) -> void:
    var tree := get_tree()
    if tree == null:
        return
    for node in tree.get_nodes_in_group(group_name):
        _queue_free_transition_projectile_node(node, queued)


func _queue_free_transition_projectiles_recursive(node: Node, queued: Dictionary) -> void:
    if node == null:
        return
    if node is MvBeam or node is MvAuthoredProjectile or node is MvGrappleBeam:
        _queue_free_transition_projectile_node(node, queued)
    for child in node.get_children():
        _queue_free_transition_projectiles_recursive(child, queued)


func _queue_free_transition_projectile_node(node: Node, queued: Dictionary) -> void:
    if node == null or not is_instance_valid(node) or node == _player:
        return
    var instance_id := node.get_instance_id()
    if queued.has(instance_id):
        return
    queued[instance_id] = true
    node.queue_free()


func _load_destination_room() -> bool:
    var door := _pending_door
    if door.is_empty():
        _abort_door_transition()
        return false

    var tags: Array = door.get("tags", [])
    if bool(door.get("launch_to_space", false)) or tags.has("exit_to_space"):
        print("MvMain: launch_to_space door traversed — requesting launch")
        launch_to_space()
        return true

    var target_link := _pending_target_link if not _pending_target_link.is_empty() else _resolve_door_target_link(door)
    var target: String = str(target_link.get("room_addr", "")).strip_edges()
    if target.is_empty():
        push_error("MvMain: door '%s' has no resolvable target" % str(door.get("id", "")))
        _abort_door_transition()
        return false
    if not _room_manager.has_room(target):
        push_error("MvMain: door '%s' → '%s' not found (target room missing/unloaded)" % [str(door.get("id", "")), target])
        _abort_door_transition()
        return false
    _cleanup_room_transition_projectiles()
    _room_manager.load_room(target)
    _setup_camera()

    var room: Dictionary = _room_manager.current_room()
    if room.is_empty():
        _abort_door_transition()
        return false

    var target_door: Dictionary = target_link.get("door", {})
    var spawn_pos := _resolve_spawn_position_for_door(door, target_door, room)
    if spawn_pos.x < 0.0 or spawn_pos.y < 0.0:
        spawn_pos = _default_player_spawn_position(room)
    if spawn_pos.x < 0.0 or spawn_pos.y < 0.0:
        spawn_pos = Vector2(float(room.get("width_px", 0)) * 0.5, float(room.get("height_px", 0)) * 0.5)
    var door_side := str(target_door.get("direction", door.get("direction", ""))).strip_edges().to_lower()
    var inward_direction := _door_inward_direction(door_side)
    var facing_direction := inward_direction if inward_direction == "left" or inward_direction == "right" else ""
    _player.spawn_at(spawn_pos, inward_direction, facing_direction)
    _player.set_locked(false)
    var arrival_payload := _build_door_payload(door, target_link, _pending_source_room)
    arrival_payload["arrival_door_id"] = str(target_door.get("id", "")).strip_edges()
    MvTriggerEngine.fire_event("door_arrived", arrival_payload)
    _fire_custom_door_event(str(target_door.get("arrive_event_name", "")).strip_edges(), arrival_payload)
    print("Door transition: %s -> %s spawn=(%s,%s)" % [str(door.get("id", "")), target, spawn_pos.x, spawn_pos.y])
    return true


func _resolve_door_target_link(door: Dictionary) -> Dictionary:
    if _room_manager == null:
        return {}
    var target_door_id := str(door.get("target_door_id", "")).strip_edges()
    if not target_door_id.is_empty() and _room_manager.has_method("find_door_link"):
        var link: Dictionary = _room_manager.find_door_link(target_door_id)
        if not link.is_empty():
            return link
    var target := str(door.get("target", "")).strip_edges()
    if target.is_empty():
        var destinations: Array = door.get("destinations", [])
        for d_v in destinations:
            if typeof(d_v) != TYPE_DICTIONARY:
                continue
            target = str((d_v as Dictionary).get("target", "")).strip_edges()
            if not target.is_empty():
                break
    if target.is_empty():
        return {}
    if _room_manager.has_method("resolve_room_addr"):
        target = str(_room_manager.resolve_room_addr(target, _room_manager.current_room_addr()))
    if target.is_empty():
        return {}
    return {
        "room_addr": target,
        "room": _room_manager.get_room(target) if _room_manager.has_method("get_room") else {},
        "door": {},
    }


func _resolve_spawn_position_for_door(source_door: Dictionary, target_door: Dictionary, room: Dictionary) -> Vector2:
    if _room_manager != null and _room_manager.has_method("door_spawn_position") and not target_door.is_empty():
        var door_spawn: Vector2 = _room_manager.door_spawn_position(target_door, room)
        if door_spawn.x >= 0.0 and door_spawn.y >= 0.0:
            return door_spawn
    var dest_x: int = int(source_door.get("dest_pixel_x", 0))
    var dest_y: int = int(source_door.get("dest_pixel_y", 0))
    if dest_x != 0 or dest_y != 0:
        return Vector2(
            float(dest_x) if dest_x != 0 else float(room.get("width_px", 0)) * 0.5,
            float(dest_y) if dest_y != 0 else float(room.get("height_px", 0)) * 0.5
        )
    return _default_player_spawn_position(room)


func _door_inward_direction(door_side: String) -> String:
    match door_side.strip_edges().to_lower():
        "left":
            return "right"
        "right":
            return "left"
        _:
            return ""


func _door_enabled(door: Dictionary) -> bool:
    var door_id := str(door.get("id", "")).strip_edges()
    var default_value := bool(door.get("enabled", true))
    if door_id.is_empty():
        return default_value
    return MvRoomState.get_door_enabled(door_id, default_value) if MvRoomState != null else default_value


func _door_locked(door: Dictionary) -> bool:
    var door_id := str(door.get("id", "")).strip_edges()
    var default_value := bool(door.get("locked", false))
    if door_id.is_empty():
        return default_value
    return MvRoomState.get_door_locked(door_id, default_value) if MvRoomState != null else default_value


func _door_access_granted(door: Dictionary) -> bool:
    var required_item_id := str(door.get("required_item_id", "")).strip_edges()
    if not required_item_id.is_empty():
        var required_count := maxi(1, int(door.get("required_item_count", 1)))
        if not PlayerInventory.has_item(required_item_id, required_count):
            return false
    var required_var_name := str(door.get("required_var_name", "")).strip_edges()
    if not required_var_name.is_empty():
        var actual: Variant = PlayerInventory.get_var(required_var_name, 0)
        if str(actual) != str(door.get("required_var_value", 1)):
            return false
    var required_tag := str(door.get("required_global_tag", "")).strip_edges()
    if not required_tag.is_empty() and (MvTriggerEngine == null or not MvTriggerEngine.has_global_tag(required_tag)):
        return false
    return true


func _build_door_payload(door: Dictionary, target_link: Dictionary = {}, from_room_override: String = "") -> Dictionary:
    var link := target_link if not target_link.is_empty() else _resolve_door_target_link(door)
    var tags: Array = []
    var tags_v: Variant = door.get("tags", [])
    if typeof(tags_v) == TYPE_ARRAY:
        tags = (tags_v as Array).duplicate()
    var from_room := from_room_override.strip_edges()
    if from_room.is_empty() and _room_manager != null:
        from_room = _room_manager.current_room_addr()
    return {
        "door_id": str(door.get("id", "")).strip_edges(),
        "target_door_id": str(door.get("target_door_id", "")).strip_edges(),
        "from_room": from_room,
        "to_room": str(link.get("room_addr", "")).strip_edges(),
        "door_direction": str(door.get("direction", "")).strip_edges(),
        "enabled": _door_enabled(door),
        "locked": _door_locked(door),
        "launch_to_space": bool(door.get("launch_to_space", false)),
        "tags": tags,
    }


func _fire_custom_door_event(event_name: String, payload: Dictionary) -> void:
    var trimmed := event_name.strip_edges()
    if trimmed.is_empty():
        return
    MvTriggerEngine.fire_event(trimmed, payload)


func _fire_blocked_door_events(door: Dictionary, payload: Dictionary) -> void:
    MvTriggerEngine.fire_event("door_use_blocked", payload)
    _fire_custom_door_event(str(door.get("blocked_event_name", "")).strip_edges(), payload)


func _blocked_door_attempt_is_throttled(door: Dictionary) -> bool:
    var door_id := str(door.get("id", "")).strip_edges()
    if door_id.is_empty() or door_id != _last_blocked_door_id:
        return false
    return Time.get_ticks_msec() - _last_blocked_door_msec < BLOCKED_DOOR_COOLDOWN_MS


func _remember_blocked_door(door: Dictionary) -> void:
    _last_blocked_door_id = str(door.get("id", "")).strip_edges()
    _last_blocked_door_msec = Time.get_ticks_msec()


func _abort_door_transition() -> void:
    _transitioning = false
    _pending_door = {}
    _pending_source_room = ""
    _pending_target_link = {}
    _transition_phase = 0
    _transition_frame = 0
    _fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
    if _player != null:
        _player.set_locked(false)


static func _find_floor_y(room: Dictionary, col: int) -> float:
    var collision: Array = room.get("collision", [])
    if collision.is_empty():
        return float(room.get("height_px", 0)) / 2.0
    var rows: int = collision.size()
    var max_col: int = (collision[0] as Array).size() - 1
    col = clampi(col, 0, max_col)
    for r in range(1, rows):
        if _is_floor_at(int(collision[r][col])) and not _is_floor_at(int(collision[r - 1][col])):
            return float(r * 16)
    return float(room.get("height_px", 0)) / 2.0


static func _is_floor_at(block_type: int) -> bool:
    return block_type != MvRoomManager.BT_AIR \
        and block_type != MvRoomManager.BT_AIR_SPECIAL \
        and block_type != MvRoomManager.BT_TREADMILL_AIR \
        and block_type != MvRoomManager.BT_SHOOT_AIR \
        and block_type != MvRoomManager.BT_BOMB_AIR \
        and block_type != MvRoomManager.BT_GRAPPLE_AIR \
        and block_type != MvRoomManager.BT_DOOR


# ===== Player death =====

func _on_player_died(_source: String) -> void:
    if _player == null:
        return
    # Default death handler: respawn in the current room with full HP.
    # A future trigger system can override by also listening to player_died.
    _player.hp = _player.max_hp
    _spawn_player_in_room()
