extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const ContentValidator = preload("res://Space/scripts/editor/content_validator.gd")
const ContentReferenceIndex = preload("res://Space/scripts/editor/content_reference_index.gd")
const PlanetLandingBossRecipe = preload("res://Space/scripts/editor/recipes/planet_landing_boss_recipe.gd")
const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")


signal closed
signal editor_requested(kind: String, pack_id: String)
signal playtest_requested(pack_id: String)

const MODE_ORDER: Array = ["campaign", "objects", "world", "triggers", "recipes", "ui", "audio", "playtest"]
const MODE_LABELS: Dictionary = {
    "campaign": "CAMPAIGN",
    "objects": "GAME PIECES",
    "world": "WORLD",
    "triggers": "GAME LOGIC",
    "recipes": "RECIPES / WIZARDS",
    "ui": "UI + FX",
    "audio": "AUDIO",
    "playtest": "CHECK + PLAY",
}

const MODE_DESCRIPTIONS: Dictionary = {
    "campaign": "Pack metadata, start flow, starting ship, and authoring checklist.",
    "objects": "Definitions: player, ships, modules, loot, entities, AI, dialogue, shops.",
    "world": "Solar systems, POIs, per-POI regions, rooms, and planet landing pathways.",
    "triggers": "Rules for when things happen, what must be true, and what the game should do.",
    "recipes": "One-click setup helpers that generate or wire starter content.",
    "ui": "Theme, authored screens, cinematics, and trigger-driven menu flow.",
    "audio": "Import and curate music / SFX assets for this pack.",
    "playtest": "Validate the pack, including authored UI screens, then launch it as a playable build.",
}

const TILE_W: float = 228.0
const TILE_H: float = 132.0
const TILE_GAP: float = 18.0

const MODE_TILES: Dictionary = {
    "campaign": [
        {
            "kind": "system",
            "label": "WORLD FLOW",
            "subtitle": "Jump into systems, POIs, and region authoring.",
            "accent": Color(0.76, 0.44, 0.95),
        },
        {
            "kind": "player",
            "label": "PLAYER BASELINE",
            "subtitle": "Starting loadout, items, attacks, abilities.",
            "accent": Color(0.95, 0.46, 0.56),
        },
        {
            "kind": "ships",
            "label": "STARTING SHIP",
            "subtitle": "Build ship templates and pick the campaign starter.",
            "accent": Color(0.32, 0.8, 0.96),
        },
        {
            "kind": "theme",
            "label": "DEFAULT UI",
            "subtitle": "Seeded screens, cinematic overlay, theme art.",
            "accent": Color(0.96, 0.82, 0.28),
        },
    ],
    "objects": [
        {
            "kind": "player",
            "label": "PLAYER",
            "subtitle": "Stats, items, equipment, attacks, projectiles.",
            "accent": Color(0.95, 0.46, 0.56),
        },
        {
            "kind": "ships",
            "label": "SHIPS",
            "subtitle": "Ship templates, hull layouts, cores, and start frame setup.",
            "accent": Color(0.32, 0.8, 0.96),
        },
        {
            "kind": "modules",
            "label": "MODULES",
            "subtitle": "Module catalog: stats, tags, prices, sizes, and test inventory.",
            "accent": Color(0.94, 0.74, 0.28),
        },
        {
            "kind": "loot",
            "label": "LOOT + STOCK",
            "subtitle": "Drop tables and shop inventory built from the module catalog.",
            "accent": Color(0.52, 0.86, 0.52),
        },
        {
            "kind": "entity",
            "label": "ENTITIES",
            "subtitle": "Actors, enemy defs, placed-object identities.",
            "accent": Color(0.96, 0.7, 0.28),
        },
        {
            "kind": "behavior",
            "label": "BEHAVIOR",
            "subtitle": "AI trees, params, and reused runtime logic.",
            "accent": Color(0.38, 0.86, 0.58),
        },
        {
            "kind": "dialogue",
            "label": "DIALOGUE",
            "subtitle": "NPC speech, branching choices, authored actions.",
            "accent": Color(0.42, 0.84, 0.88),
        },
        {
            "kind": "shop",
            "label": "SHOPS",
            "subtitle": "Vendor inventories, prices, barter-facing stock.",
            "accent": Color(0.85, 0.73, 0.42),
        },
        {
            "kind": "quest",
            "label": "QUESTS",
            "subtitle": "Stages, objectives, rewards, and journal-facing structure.",
            "accent": Color(0.7, 0.86, 0.42),
        },
    ],
    "world": [
        {
            "kind": "system",
            "label": "SYSTEMS + PLANETS",
            "subtitle": "Author stars, orbiting POIs, region landing lists, and per-POI regions.",
            "accent": Color(0.32, 0.8, 0.96),
        },
    ],
    "recipes": [
        {
            "kind": "__landing_boss_recipe__",
            "label": "STARTER LANDING",
            "subtitle": "Generate a planet landing, key gate, boss room, and trigger wiring.",
            "accent": Color(0.88, 0.58, 0.28),
        },
    ],
    "triggers": [
        {
            "kind": "trigger",
            "label": "GAME LOGIC",
            "subtitle": "When something happens, run dialogue, flags, cutscenes, spawns, or camera logic.",
            "accent": Color(0.93, 0.63, 0.2),
        },
        {
            "kind": "dialogue",
            "label": "CONVERSATIONS",
            "subtitle": "Write NPC lines, player choices, and conversation side effects.",
            "accent": Color(0.42, 0.84, 0.88),
        },
        {
            "kind": "shop",
            "label": "SHOPS",
            "subtitle": "Vendor stock, prices, and economy hooks.",
            "accent": Color(0.85, 0.73, 0.42),
        },
        {
            "kind": "quest",
            "label": "QUESTS",
            "subtitle": "Author progression arcs from objectives into rewards.",
            "accent": Color(0.7, 0.86, 0.42),
        },
    ],
    "ui": [
        {
            "kind": "theme",
            "label": "UI + CINEMATICS",
            "subtitle": "Theme art, screens, button states, cinematic overlay.",
            "accent": Color(0.96, 0.82, 0.28),
        },
        {
            "kind": "trigger",
            "label": "UI BUTTON LOGIC",
            "subtitle": "Use game logic for menu flow, buttons, and authored events.",
            "accent": Color(0.93, 0.63, 0.2),
        },
    ],
    "audio": [
        {
            "kind": "audio",
            "label": "AUDIO",
            "subtitle": "Music, SFX, manifests, and imported assets.",
            "accent": Color(0.48, 0.7, 1.0),
        },
    ],
    "playtest": [
        {
            "kind": "__play_pack__",
            "label": "PLAY PACK",
            "subtitle": "Launch the authored pack through the current game flow.",
            "accent": Color(0.42, 0.88, 0.56),
        },
        {
            "kind": "__validate__",
            "label": "CHECK PACK",
            "subtitle": "Cross-check rooms, entities, triggers, dialogue, and shops.",
            "accent": Color(0.28, 0.6, 0.95),
        },
        {
            "kind": "__reference_lookup__",
            "label": "REFERENCE LOOKUP",
            "subtitle": "Find every trigger, room, shop, dialogue, or object using one authored id.",
            "accent": Color(0.78, 0.62, 0.96),
        },
        {
            "kind": "theme",
            "label": "UI TEST PASS",
            "subtitle": "Quick jump back into authored screens before testing.",
            "accent": Color(0.96, 0.82, 0.28),
        },
    ],
}

var pack_id: String = ""
var _mode: String = "campaign"
var _skip_close_frame: bool = true

var _tooltips_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _validate_rect: Rect2 = Rect2()
var _play_rect: Rect2 = Rect2()
var _save_rect: Rect2 = Rect2()
var _export_rect: Rect2 = Rect2()
var _import_rect: Rect2 = Rect2()
var _mode_rects: Dictionary = {}
var _tile_rects: Array = []

var _validation_summary: String = ""
var _validation_lines: Array = []

var _manifest: Dictionary = {}
var _manifest_dirty: bool = false
var _manifest_fields: Dictionary = {}
var _manifest_desc: TextEdit = null
var _import_dialog: FileDialog = null
var _export_dialog: FileDialog = null
var _reference_dialog: AcceptDialog = null
var _reference_kind: OptionButton = null
var _reference_id: LineEdit = null
var _reference_results: TextEdit = null


func _ready() -> void:
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    _skip_close_frame = true
    set_process(true)
    _build_campaign_controls()
    _build_reference_dialog()


func _build_campaign_controls() -> void:
    var field_names: Array = ["name", "author", "version", "entry_room", "start_realm", "start_system", "start_ship_template"]
    for key in field_names:
        var le: LineEdit = LineEdit.new()
        le.visible = false
        le.placeholder_text = key.replace("_", " ")
        le.text_changed.connect(_on_manifest_field_changed.bind(key))
        add_child(le)
        _manifest_fields[key] = le

    _manifest_desc = TextEdit.new()
    _manifest_desc.visible = false
    _manifest_desc.placeholder_text = "Pack description, campaign premise, testing notes..."
    _manifest_desc.text_changed.connect(_on_manifest_description_changed)
    add_child(_manifest_desc)

    _import_dialog = FileDialog.new()
    _import_dialog.visible = false
    _import_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _import_dialog.use_native_dialog = true
    _import_dialog.title = "Import Pack Bundle"
    _import_dialog.add_filter("*.mvpack", "MV Pack Bundle")
    _import_dialog.add_filter("*.zip", "ZIP Archive")
    _import_dialog.file_selected.connect(_on_import_archive_selected)
    add_child(_import_dialog)

    _export_dialog = FileDialog.new()
    _export_dialog.visible = false
    _export_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    _export_dialog.use_native_dialog = true
    _export_dialog.title = "Export Pack Bundle"
    _export_dialog.add_filter("*.mvpack", "MV Pack Bundle")
    _export_dialog.add_filter("*.zip", "ZIP Archive")
    _export_dialog.file_selected.connect(_on_export_archive_selected)
    add_child(_export_dialog)


func _build_reference_dialog() -> void:
    _reference_dialog = AcceptDialog.new()
    _reference_dialog.title = "Reference Lookup"
    _reference_dialog.visible = false
    _reference_dialog.min_size = Vector2(620, 460)
    add_child(_reference_dialog)

    var root := VBoxContainer.new()
    root.custom_minimum_size = Vector2(580, 380)
    _reference_dialog.add_child(root)

    var row := HBoxContainer.new()
    root.add_child(row)

    _reference_kind = OptionButton.new()
    _reference_kind.custom_minimum_size = Vector2(150, 28)
    for kind in ["item", "ability", "entity", "dialogue", "shop", "quest", "room", "system", "trigger", "behavior", "attack", "projectile"]:
        _reference_kind.add_item(kind)
    row.add_child(_reference_kind)

    _reference_id = LineEdit.new()
    _reference_id.placeholder_text = "authored id"
    _reference_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _reference_id.text_submitted.connect(func(_text: String) -> void: _run_reference_lookup())
    row.add_child(_reference_id)

    var find_button := Button.new()
    find_button.text = "Find"
    find_button.pressed.connect(_run_reference_lookup)
    row.add_child(find_button)

    _reference_results = TextEdit.new()
    _reference_results.editable = false
    _reference_results.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _reference_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(_reference_results)


func current_mode() -> String:
    return _mode


func open_editor(p_pack_id: String = "", start_mode: String = "campaign") -> void:
    pack_id = p_pack_id if not p_pack_id.is_empty() else "demo"
    _mode = start_mode if MODE_LABELS.has(start_mode) else "campaign"
    _skip_close_frame = true
    visible = true
    _validation_summary = ""
    _validation_lines.clear()
    _load_manifest()
    _layout_campaign_controls()
    queue_redraw()


func _process(_delta: float) -> void:
    if visible:
        _layout_campaign_controls()
        queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_campaign_controls()


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _skip_close_frame:
        _skip_close_frame = false
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var key_event: InputEventKey = event as InputEventKey
        if key_event.keycode == KEY_ESCAPE:
            _request_close()
            get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var pos: Vector2 = event.position
        if _close_rect.has_point(pos):
            _request_close()
            accept_event()
            return
        if _tooltips_rect.has_point(pos):
            EditorTooltip.toggle()
            accept_event()
            return
        if _save_rect.has_point(pos):
            _save_manifest()
            accept_event()
            return
        if _export_rect.has_point(pos):
            _begin_export_pack()
            accept_event()
            return
        if _import_rect.has_point(pos):
            _begin_import_pack()
            accept_event()
            return
        if _validate_rect.has_point(pos):
            _run_validation()
            accept_event()
            return
        if _play_rect.has_point(pos):
            _save_manifest()
            playtest_requested.emit(pack_id)
            accept_event()
            return
        for mode_key in _mode_rects.keys():
            var rect: Rect2 = _mode_rects[mode_key]
            if rect.has_point(pos):
                _mode = str(mode_key)
                _layout_campaign_controls()
                accept_event()
                return
        for tile_v in _tile_rects:
            var tile: Dictionary = tile_v
            var rect: Rect2 = tile.get("rect", Rect2())
            if not rect.has_point(pos):
                continue
            _activate_tile(str(tile.get("kind", "")))
            accept_event()
            return


func _draw() -> void:
    var font: Font = ThemeDB.fallback_font
    var mouse_pos: Vector2 = get_local_mouse_position()

    draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.05, 0.075))

    var panel_rect: Rect2 = Rect2(32, 26, size.x - 64, size.y - 52)
    UIPanels.draw_panel(self, panel_rect, Color(0.88, 0.96, 1.0), UIPanels.PanelVariant.ALT)

    draw_string(font, Vector2(panel_rect.position.x + 26, panel_rect.position.y + 38),
        "EDITOR SUITE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.95, 1.0))
    draw_string(font, Vector2(panel_rect.position.x + 26, panel_rect.position.y + 64),
        "Pack: %s" % pack_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.7, 0.82))
    _draw_text_block(
        font,
        Vector2(panel_rect.position.x + 26, panel_rect.position.y + 82),
        str(MODE_DESCRIPTIONS.get(_mode, "")),
        panel_rect.size.x - 520.0,
        12,
        Color(0.72, 0.79, 0.88),
        15.0,
        2
    )

    _tooltips_rect = Rect2(panel_rect.end.x - 660, panel_rect.position.y + 16, EditorTooltip.TOGGLE_WIDTH, 26)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    _import_rect = Rect2(panel_rect.end.x - 518, panel_rect.position.y + 16, 96, 28)
    _draw_action_button(font, _import_rect, "IMPORT", _import_rect.has_point(mouse_pos), Color(0.54, 0.72, 0.98))

    _export_rect = Rect2(panel_rect.end.x - 412, panel_rect.position.y + 16, 98, 28)
    _draw_action_button(font, _export_rect, "EXPORT", _export_rect.has_point(mouse_pos), Color(0.9, 0.72, 0.32))

    _save_rect = Rect2(panel_rect.end.x - 304, panel_rect.position.y + 16, 88, 28)
    _draw_action_button(font, _save_rect, "SAVE", _save_rect.has_point(mouse_pos), Color(0.36, 0.84, 0.52), _manifest_dirty)

    _validate_rect = Rect2(panel_rect.end.x - 206, panel_rect.position.y + 16, 92, 28)
    _draw_action_button(font, _validate_rect, "VALIDATE", _validate_rect.has_point(mouse_pos), Color(0.28, 0.6, 0.95))

    _play_rect = Rect2(panel_rect.end.x - 104, panel_rect.position.y + 16, 74, 28)
    _draw_action_button(font, _play_rect, "PLAY", _play_rect.has_point(mouse_pos), Color(0.42, 0.88, 0.56))

    _close_rect = Rect2(panel_rect.end.x - 104, panel_rect.position.y + panel_rect.size.y - 42, 74, 28)
    _draw_action_button(font, _close_rect, "CLOSE", _close_rect.has_point(mouse_pos), Color(0.78, 0.3, 0.34))

    _draw_mode_tabs(font, panel_rect, mouse_pos)
    _draw_main_panel(font, panel_rect, mouse_pos)
    _draw_validation_panel(font, panel_rect, mouse_pos)


func _draw_mode_tabs(font: Font, panel_rect: Rect2, mouse_pos: Vector2) -> void:
    _mode_rects.clear()
    var x: float = panel_rect.position.x + 24.0
    var y: float = panel_rect.position.y + 114.0
    for mode_key in MODE_ORDER:
        var label: String = str(MODE_LABELS.get(mode_key, mode_key))
        var width: float = maxf(92.0, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 26.0)
        var rect: Rect2 = Rect2(x, y, width, 24)
        _mode_rects[mode_key] = rect
        var active: bool = mode_key == _mode
        var accent: Color = Color(0.35, 0.72, 0.96, 1.0) if active else Color(0.2, 0.24, 0.34, 1.0)
        _draw_chip(font, rect, label, accent, mouse_pos, active)
        if rect.has_point(mouse_pos):
            EditorTooltip.show_text(str(MODE_DESCRIPTIONS.get(mode_key, "")))
        x += width + 8.0


func _draw_main_panel(font: Font, panel_rect: Rect2, mouse_pos: Vector2) -> void:
    var left_rect: Rect2 = Rect2(panel_rect.position.x + 24, panel_rect.position.y + 150, panel_rect.size.x - 352, panel_rect.size.y - 174)
    draw_rect(left_rect, Color(0.055, 0.065, 0.095))
    draw_rect(left_rect, Color(0.26, 0.34, 0.46), false, 1.0)
    _tile_rects.clear()

    if _mode == "campaign":
        _draw_campaign_panel(font, left_rect, mouse_pos)
        return

    var tiles: Array = MODE_TILES.get(_mode, [])
    var cols: int = maxi(int((left_rect.size.x - 24.0 + TILE_GAP) / (TILE_W + TILE_GAP)), 1)
    var start_x: float = left_rect.position.x + 16.0
    var start_y: float = left_rect.position.y + 18.0
    for i in range(tiles.size()):
        var tile: Dictionary = tiles[i]
        var col: int = i % cols
        @warning_ignore("integer_division")
        var row: int = i / cols
        var rect: Rect2 = Rect2(
            start_x + float(col) * (TILE_W + TILE_GAP),
            start_y + float(row) * (TILE_H + TILE_GAP),
            TILE_W,
            TILE_H
        )
        _draw_tile(font, rect, tile, rect.has_point(mouse_pos))
        _tile_rects.append({"kind": tile.get("kind", ""), "rect": rect})


func _draw_campaign_panel(font: Font, rect: Rect2, mouse_pos: Vector2) -> void:
    draw_string(font, Vector2(rect.position.x + 18, rect.position.y + 24),
        "CAMPAIGN SETUP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.84, 0.92, 1.0))
    _draw_text_block(
        font,
        Vector2(rect.position.x + 18, rect.position.y + 42),
        "Use this as the pack control room: identity, start flow, and quick links into core authoring tools.",
        rect.size.x - 36.0,
        11,
        Color(0.66, 0.74, 0.84),
        14.0,
        2
    )

    var readonly_y: float = rect.position.y + 88.0
    draw_string(font, Vector2(rect.position.x + 18, readonly_y),
        "Pack ID: %s" % pack_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.76, 0.84, 0.94))
    _draw_text_block(
        font,
        Vector2(rect.position.x + 18, readonly_y + 10.0),
        "Current start targets are metadata only right now; this hub also handles full-pack import/export so a bundle can move to another editor install intact.",
        rect.size.x - 36.0,
        10,
        Color(0.58, 0.66, 0.76),
        13.0,
        2
    )

    var labels: Array = [
        ["name", "Pack Name"],
        ["author", "Author"],
        ["version", "Version"],
        ["entry_room", "Entry Room"],
        ["start_realm", "Start Realm"],
        ["start_system", "Start System"],
        ["start_ship_template", "Starting Ship"],
    ]
    var label_w: float = 104.0
    var field_w: float = (rect.size.x - 58.0 - label_w * 2.0) * 0.5
    var base_x: float = rect.position.x + 18.0
    var base_y: float = rect.position.y + 126.0
    for i in range(labels.size()):
        @warning_ignore("integer_division")
        var row: int = i / 2
        var col: int = i % 2
        var key_label: Array = labels[i]
        var x: float = base_x + float(col) * (label_w + field_w + 28.0)
        @warning_ignore("confusable_local_declaration")
        var y: float = base_y + float(row) * 40.0
        draw_string(font, Vector2(x, y + 16.0),
            str(key_label[1]), HORIZONTAL_ALIGNMENT_LEFT, int(label_w - 8.0), 11, Color(0.76, 0.84, 0.94))

    draw_string(font, Vector2(base_x, base_y + 148.0),
        "Description", HORIZONTAL_ALIGNMENT_LEFT, int(label_w - 8.0), 11, Color(0.76, 0.84, 0.94))

    var campaign_tiles: Array = MODE_TILES.get("campaign", [])
    var tile_y: float = base_y + 258.0
    var mini_gap: float = 14.0
    var mini_h: float = 102.0
    var campaign_cols: int = mini(3, maxi(int((rect.size.x - 36.0 + mini_gap) / (280.0 + mini_gap)), 1))
    var mini_w: float = (rect.size.x - 36.0 - mini_gap * float(campaign_cols - 1)) / float(campaign_cols)
    for i in range(campaign_tiles.size()):
        var tile: Dictionary = campaign_tiles[i]
        var col: int = i % campaign_cols
        @warning_ignore("integer_division")
        var row: int = i / campaign_cols
        var tile_rect: Rect2 = Rect2(
            rect.position.x + 18.0 + float(col) * (mini_w + mini_gap),
            tile_y + float(row) * (mini_h + mini_gap),
            mini_w,
            mini_h
        )
        _draw_tile(font, tile_rect, tile, tile_rect.has_point(mouse_pos))
        _tile_rects.append({"kind": tile.get("kind", ""), "rect": tile_rect})

    var tile_rows: int = int(ceil(float(campaign_tiles.size()) / float(campaign_cols)))
    var checklist_y: float = maxf(rect.position.y + rect.size.y - 146.0, tile_y + float(tile_rows) * (mini_h + mini_gap) + 10.0)
    draw_string(font, Vector2(rect.position.x + 18, checklist_y),
        "AUTHORING CHECKLIST", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.86, 0.92, 1.0))
    var checklist: Array = [
        "1. Set pack identity and intended start flow here.",
        "2. Pick the starting ship template before building encounter content.",
        "3. Author player baseline and module economy together.",
        "4. Use WORLD for the systems / POI / region / room slice.",
        "5. Use UI + FX for authored menu, HUD, and cinematic surfaces.",
        "6. Use PLAYTEST after every trigger or world-flow change.",
    ]
    var y: float = checklist_y + 24.0
    for line in checklist:
        draw_string(font, Vector2(rect.position.x + 18, y),
            line, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 36), 11, Color(0.68, 0.76, 0.86))
        y += 18.0


func _draw_tile(font: Font, rect: Rect2, tile: Dictionary, hovered: bool) -> void:
    var accent: Color = tile.get("accent", Color(0.5, 0.7, 1.0))
    var bg: Color = Color(0.09, 0.11, 0.16)
    if hovered:
        bg = bg.lerp(accent, 0.14)
    draw_rect(rect, bg)
    draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.95), false, 2.0)
    draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 6), accent)
    var label_y: float = rect.position.y + 28.0
    draw_string(font, Vector2(rect.position.x + 14, label_y),
        str(tile.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 92), 18, Color(0.95, 0.98, 1.0))

    var open_w: float = 52.0
    var open_rect: Rect2 = Rect2(rect.end.x - open_w - 10.0, rect.position.y + 16.0, open_w, 18.0)
    draw_rect(open_rect, Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.95))
    draw_rect(open_rect, Color(accent.r, accent.g, accent.b, 0.95), false, 1.0)
    draw_string(font, Vector2(open_rect.position.x + 8.0, open_rect.position.y + 13.0),
        "OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(accent.r, accent.g, accent.b, 0.98))

    _draw_text_block(
        font,
        Vector2(rect.position.x + 14.0, rect.position.y + 48.0),
        str(tile.get("subtitle", "")),
        rect.size.x - 28.0,
        11,
        Color(0.76, 0.82, 0.9),
        14.0,
        3
    )


func _draw_chip(font: Font, rect: Rect2, label: String, accent: Color, mouse_pos: Vector2, active: bool) -> void:
    var hovered: bool = rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, rect, hovered or active, accent)
    var color: Color = Color(1, 1, 1, 1) if active else Color(0.82, 0.9, 1.0, 1.0)
    var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
    draw_string(font, Vector2(rect.position.x + (rect.size.x - text_w) * 0.5, rect.position.y + 16.0),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_action_button(font: Font, rect: Rect2, label: String, hovered: bool, accent: Color, dirty: bool = false) -> void:
    var bg: Color = Color(0.1, 0.12, 0.18)
    if hovered:
        bg = bg.lerp(accent, 0.18)
    draw_rect(rect, bg)
    draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.95), false, 1.0)
    var text: String = "%s*" % label if dirty else label
    draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 19),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.96, 1.0))


func _draw_validation_panel(font: Font, panel_rect: Rect2, mouse_pos: Vector2) -> void:
    var rect: Rect2 = Rect2(panel_rect.end.x - 300, panel_rect.position.y + 150, 276, panel_rect.size.y - 174)
    draw_rect(rect, Color(0.055, 0.065, 0.095))
    draw_rect(rect, Color(0.26, 0.34, 0.46), false, 1.0)
    draw_string(font, Vector2(rect.position.x + 16, rect.position.y + 24),
        "STATUS + VALIDATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.82, 0.9, 1.0))

    var summary: String = _validation_summary
    if summary.is_empty():
        summary = "Use VALIDATE often. This panel is the suite-wide status surface while the shell grows."
    var summary_h: float = _draw_text_block(
        font,
        Vector2(rect.position.x + 16, rect.position.y + 44),
        summary,
        rect.size.x - 32.0,
        11,
        Color(0.68, 0.76, 0.86),
        14.0,
        5
    )

    var hints: Array = _mode_hints(_mode)
    var y: float = rect.position.y + 52.0 + summary_h + 12.0
    if _validation_lines.is_empty():
        for hint in hints:
            var hint_h: float = _draw_text_block(
                font,
                Vector2(rect.position.x + 16, y),
                hint,
                rect.size.x - 32.0,
                10,
                Color(0.58, 0.66, 0.76),
                13.0,
                4
            )
            y += hint_h + 8.0
    else:
        for line in _validation_lines:
            if y > rect.end.y - 14:
                break
            var color: Color = Color(0.76, 0.82, 0.92)
            if line.begins_with("[ERROR]"):
                color = Color(1.0, 0.62, 0.62)
            elif line.begins_with("[WARNING]"):
                color = Color(1.0, 0.85, 0.58)
            var line_h: float = _draw_text_block(
                font,
                Vector2(rect.position.x + 16, y),
                line,
                rect.size.x - 32.0,
                10,
                color,
                13.0,
                3
            )
            y += line_h + 4.0

    if _play_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Play the current pack through the existing runtime flow.")
    elif _export_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Export a portable bundle with the full effective contents of this pack.")
    elif _import_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Import a portable pack bundle and open it in this hub.")
    elif _save_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Save campaign-level pack metadata from the Campaign tab.")
    elif _validate_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Run cross-file pack validation before playtesting.")


func _mode_hints(mode_key: String) -> Array:
    match mode_key:
        "campaign":
            return [
                "Treat Campaign as the pack control room, not another random editor.",
                "Start targets and starting ship live here as campaign metadata.",
                "Use SAVE after changing name, author, or start flow notes.",
            ]
        "objects":
            return [
                "The suite goal is one Object Editor feel, even if tools are still separate underneath.",
                "Player, ships, modules, loot, entity, and behavior definitions are the current object-editor spine.",
            ]
        "world":
            return [
                "WORLD owns the space-side system graph and the per-POI region lists.",
                "Use Systems + Planets to wire stars, orbiting POIs, and the regions/rooms each POI lands into.",
            ]
        "triggers":
            return [
                "Trigger Editor is the glue layer: event happens, optional checks pass, actions run.",
                "Dialogue authoring lives here because the most common link is NPC `dialogue_id` or trigger `start_dialogue`.",
                "Use Trigger Editor for zones, cutscenes, follow-up logic, UI events, and anything more complex than a plain NPC conversation.",
            ]
        "recipes":
            return [
                "Recipes are setup helpers, not primary authoring pages.",
                "Use them to generate starter structures, then edit the result in the normal World, Game Pieces, and Game Logic tabs.",
            ]
        "ui":
            return [
                "Use Theme + UI for authored screens, sprite button states, and the cinematic overlay slot.",
                "Authored button clicks emit ui_button and can also fire explicit trigger events.",
            ]
        "audio":
            return [
                "Audio stays separate for now, but it belongs in the same suite shell.",
            ]
        "playtest":
            return [
                "VALIDATE then PLAY should become the editor's equivalent of Warcraft 3's Test Map loop.",
                "Press F8 during MV playtests to open the trigger debugger overlay; F7 clears the live log, F6 pauses or resumes trigger sequences, and F5 steps one trigger action while paused.",
                "The Trigger Editor now also has a Debugger window with filters, breakpoints, and active-sequence inspection when you need a richer view than the overlay.",
                "The trigger debugger persists recent history in the autoload after a run, so you can reproduce issues and inspect sequence flow.",
            ]
    return []


func _wrap_text(font: Font, text: String, font_size: int, max_width: float) -> Array:
    var result: Array = []
    var paragraphs: PackedStringArray = text.split("\n")
    for paragraph in paragraphs:
        var source: String = paragraph.strip_edges()
        if source.is_empty():
            result.append("")
            continue
        var words: PackedStringArray = source.split(" ", false)
        var line: String = ""
        for word in words:
            var candidate: String = word if line.is_empty() else "%s %s" % [line, word]
            var candidate_w: float = font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
            if candidate_w <= max_width or line.is_empty():
                line = candidate
            else:
                result.append(line)
                line = word
        if not line.is_empty():
            result.append(line)
    return result


func _draw_text_block(font: Font, pos: Vector2, text: String, max_width: float, font_size: int, color: Color, line_height: float, max_lines: int = -1) -> float:
    var lines: Array = _wrap_text(font, text, font_size, max_width)
    if lines.is_empty():
        return 0.0
    var draw_count: int = lines.size()
    if max_lines > 0:
        draw_count = mini(draw_count, max_lines)
    for i in range(draw_count):
        var line: String = str(lines[i])
        draw_string(
            font,
            Vector2(pos.x, pos.y + line_height * float(i + 1)),
            line,
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            font_size,
            color
        )
    return line_height * float(draw_count)


func _activate_tile(kind: String) -> void:
    match kind:
        "__validate__":
            _run_validation()
        "__play_pack__":
            _save_manifest()
            playtest_requested.emit(pack_id)
        "__landing_boss_recipe__":
            _save_manifest()
            _run_landing_boss_recipe()
        "__reference_lookup__":
            _open_reference_lookup()
        _:
            if not kind.is_empty():
                visible = false
                editor_requested.emit(kind, pack_id)


func _request_close() -> void:
    _save_manifest()
    visible = false
    closed.emit()


func _manifest_path() -> String:
    return PackPaths.writable_pack_file(pack_id, "Pack.json")


func _load_manifest() -> void:
    _manifest = {
        "pack_id": pack_id,
        "name": pack_id,
        "version": "0.1.0",
        "author": "",
        "description": "",
        "entry_room": "",
        "start_realm": "",
        "start_system": "",
        "start_ship_template": "",
    }
    var path: String = _manifest_path()
    if FileAccess.file_exists(path):
        var f: FileAccess = FileAccess.open(path, FileAccess.READ)
        if f != null:
            var parsed: Variant = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(parsed) == TYPE_DICTIONARY:
                for key in (parsed as Dictionary).keys():
                    _manifest[str(key)] = (parsed as Dictionary)[key]
    _manifest.erase("start_region")
    _manifest_dirty = false
    _refresh_manifest_controls()


func _save_manifest() -> void:
    if pack_id.is_empty() or not _manifest_dirty:
        return
    var path: String = _manifest_path()
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("ContentEditor: cannot write %s" % path)
        return
    f.store_string(JSON.stringify(_manifest, "\t"))
    f.close()
    _manifest_dirty = false
    _validation_summary = "Saved campaign metadata for pack '%s'." % pack_id


func _begin_export_pack() -> void:
    if pack_id.is_empty() or _export_dialog == null:
        return
    _save_manifest()
    _export_dialog.current_file = "%s.mvpack" % pack_id
    _export_dialog.popup_centered_ratio(0.75)


func _begin_import_pack() -> void:
    if _import_dialog == null:
        return
    _save_manifest()
    _import_dialog.popup_centered_ratio(0.75)


func _on_export_archive_selected(path: String) -> void:
    var export_path: String = path.strip_edges()
    if export_path.is_empty():
        return
    if export_path.get_extension().is_empty():
        export_path += ".mvpack"
    var result: Dictionary = MvPackLoader.export_portable_pack(pack_id, export_path)
    if bool(result.get("success", false)):
        _validation_summary = "Exported pack '%s' to %s." % [pack_id, export_path.get_file()]
        _validation_lines = [
            "[INFO] Portable bundle created.",
            "[INFO] Pack: %s" % pack_id,
            "[INFO] Files exported: %d" % int(result.get("file_count", 0)),
            "[INFO] Path: %s" % export_path,
        ]
        return
    _validation_summary = "Pack export failed for '%s'." % pack_id
    _validation_lines = ["[ERROR] %s" % str(result.get("error", "Unknown export error."))]


func _on_import_archive_selected(path: String) -> void:
    var result: Dictionary = MvPackLoader.import_portable_pack(path)
    if not bool(result.get("success", false)):
        _validation_summary = "Pack import failed."
        _validation_lines = ["[ERROR] %s" % str(result.get("error", "Unknown import error."))]
        return

    var imported_pack_id: String = str(result.get("pack_id", ""))
    var source_pack_id: String = str(result.get("source_pack_id", imported_pack_id))
    var was_renamed: bool = bool(result.get("renamed", false))
    pack_id = imported_pack_id
    _mode = "campaign"
    _load_manifest()
    _layout_campaign_controls()
    if was_renamed:
        _validation_summary = "Imported '%s' as '%s' and opened it." % [source_pack_id, imported_pack_id]
    else:
        _validation_summary = "Imported and opened pack '%s'." % imported_pack_id
    _validation_lines = [
        "[INFO] Portable bundle imported.",
        "[INFO] Files imported: %d" % int(result.get("file_count", 0)),
        "[INFO] Active pack: %s" % imported_pack_id,
    ]
    if was_renamed:
        _validation_lines.append("[WARNING] Pack id already existed here, so the import was renamed from '%s'." % source_pack_id)


func _refresh_manifest_controls() -> void:
    for key in _manifest_fields.keys():
        var le: LineEdit = _manifest_fields[key]
        if le != null:
            le.text = str(_manifest.get(key, ""))
    if _manifest_desc != null:
        _manifest_desc.text = str(_manifest.get("description", ""))


func _layout_campaign_controls() -> void:
    var should_show: bool = visible and _mode == "campaign"
    var panel_rect: Rect2 = Rect2(32, 26, size.x - 64, size.y - 52)
    var left_rect: Rect2 = Rect2(panel_rect.position.x + 24, panel_rect.position.y + 150, panel_rect.size.x - 352, panel_rect.size.y - 174)

    for key in _manifest_fields.keys():
        var le: LineEdit = _manifest_fields[key]
        if le != null:
            le.visible = should_show
    if _manifest_desc != null:
        _manifest_desc.visible = should_show
    if not should_show:
        return

    var labels: Array = ["name", "author", "version", "entry_room", "start_realm", "start_system", "start_ship_template"]
    var label_w: float = 104.0
    var field_w: float = (left_rect.size.x - 58.0 - label_w * 2.0) * 0.5
    var base_x: float = left_rect.position.x + 18.0
    var base_y: float = left_rect.position.y + 126.0
    for i in range(labels.size()):
        var key: String = str(labels[i])
        @warning_ignore("integer_division")
        var row: int = i / 2
        var col: int = i % 2
        var le: LineEdit = _manifest_fields[key]
        if le == null:
            continue
        var x: float = base_x + float(col) * (label_w + field_w + 28.0)
        var y: float = base_y + float(row) * 40.0
        le.position = Vector2(x + label_w, y)
        le.size = Vector2(field_w, 24)

    if _manifest_desc != null:
        _manifest_desc.position = Vector2(base_x + label_w, base_y + 132.0)
        _manifest_desc.size = Vector2(left_rect.size.x - 52.0 - label_w, 96.0)


func _on_manifest_field_changed(text: String, key: String) -> void:
    _manifest[key] = text
    _manifest_dirty = true


func _on_manifest_description_changed() -> void:
    if _manifest_desc == null:
        return
    _manifest["description"] = _manifest_desc.text
    _manifest_dirty = true


func _run_validation() -> void:
    var issues: Array = ContentValidator.validate(pack_id)
    var errors: int = 0
    var warnings: int = 0
    _validation_lines.clear()
    for issue_v in issues:
        if issue_v == null:
            continue
        var text: String = issue_v.text() if issue_v.has_method("text") else str(issue_v)
        _validation_lines.append(text)
        if text.begins_with("[ERROR]"):
            errors += 1
        elif text.begins_with("[WARNING]"):
            warnings += 1
    if issues.is_empty():
        _validation_summary = "No validator issues found for pack '%s'." % pack_id
        return
    _validation_summary = "%d errors, %d warnings in pack '%s'." % [errors, warnings, pack_id]


func _run_landing_boss_recipe() -> void:
    var result: Dictionary = PlanetLandingBossRecipe.apply(pack_id)
    _validation_lines.clear()
    for error_v in result.get("errors", []):
        _validation_lines.append("[ERROR] %s" % str(error_v))
    if bool(result.get("ok", false)):
        _validation_summary = "Created landing + boss gate recipe for '%s'. Start room: %s." % [
            pack_id,
            str(result.get("start_room", "")),
        ]
        if _validation_lines.is_empty():
            _validation_lines.append("Recipe validation passed with %d total issue(s)." % int(result.get("issue_count", 0)))
    else:
        _validation_summary = "Landing + boss gate recipe needs attention for '%s'." % pack_id
    queue_redraw()


func _open_reference_lookup() -> void:
    if _reference_dialog == null:
        return
    if _reference_results != null:
        _reference_results.text = "Choose a kind, enter an authored id, then press Find."
    if _reference_id != null:
        _reference_id.text = ""
    _reference_dialog.popup_centered()


func _run_reference_lookup() -> void:
    if _reference_kind == null or _reference_id == null or _reference_results == null:
        return
    var kind := _reference_kind.get_item_text(_reference_kind.selected).strip_edges()
    var id := _reference_id.text.strip_edges()
    if id.is_empty():
        _reference_results.text = "Enter an id to inspect."
        return
    var index := ContentReferenceIndex.build(pack_id)
    var lines := ContentReferenceIndex.summary_lines(index, kind, id)
    _reference_results.text = _lines_to_text(lines)
    _validation_summary = "Reference lookup: %s '%s' in pack '%s'." % [kind, id, pack_id]
    _validation_lines = lines
    queue_redraw()


func _lines_to_text(lines: Array) -> String:
    var packed := PackedStringArray()
    for line_v in lines:
        packed.append(str(line_v))
    return "\n".join(packed)
