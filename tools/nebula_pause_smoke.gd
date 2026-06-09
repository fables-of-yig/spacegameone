extends SceneTree

# Headless smoke for the Nebula Pause + Settings + Keybindings overlays. Autoload-
# free (run with --script): proves the three new scripts parse + construct, the
# settings catalog is well-formed, and the Nebula Theme still builds. The wired
# setting round-trip (SettingsManager apply) needs autoloads, so it is covered by
# the Space/MV scene boots + manual dogfood, not here.
# Run: godot --headless --path <proj> --script res://tools/nebula_pause_smoke.gd

const NT := preload("res://MV/scripts/console/nebula_theme.gd")
const Catalog := preload("res://Space/scripts/shared/settings/settings_catalog.gd")
const SettingsScreenScript := preload("res://Space/scripts/ui/nebula_settings_screen.gd")
const KeybindingsScript := preload("res://Space/scripts/ui/nebula_keybindings.gd")
const PauseScript := preload("res://Space/scripts/ui/nebula_pause_menu.gd")

const VALID_KINDS := ["segmented", "select", "toggle", "slider", "keybinds_cta"]


func _init() -> void:
    var ok := true

    # 1) Theme still builds from real assets.
    var t := NT.theme()
    if t == null or t.default_font == null or not t.has_stylebox("panel", "PanelContainer"):
        push_error("PAUSESMOKE: Nebula theme failed to build")
        ok = false

    # 2) Catalog is well-formed.
    var tabs := Catalog.tabs()
    if tabs.is_empty():
        push_error("PAUSESMOKE: catalog has no tabs")
        ok = false
    var kinds_seen: Dictionary = {}
    var n_settings := 0
    for tab_v in tabs:
        var tab: Dictionary = tab_v
        if str(tab.get("id", "")).is_empty() or (tab.get("groups", []) as Array).is_empty():
            push_error("PAUSESMOKE: tab '%s' malformed" % str(tab.get("label", "?")))
            ok = false
        for group_v in (tab.get("groups", []) as Array):
            var group: Dictionary = group_v
            for setting_v in (group.get("settings", []) as Array):
                var s: Dictionary = setting_v
                n_settings += 1
                var kind := str(s.get("kind", ""))
                kinds_seen[kind] = true
                if not VALID_KINDS.has(kind):
                    push_error("PAUSESMOKE: setting '%s' has bad kind '%s'" % [str(s.get("key", "?")), kind])
                    ok = false
                for req in ["key", "label", "kind", "section"]:
                    if not s.has(req):
                        push_error("PAUSESMOKE: setting '%s' missing '%s'" % [str(s.get("key", "?")), req])
                        ok = false
                if not s.has("wired"):
                    push_error("PAUSESMOKE: setting '%s' missing 'wired' (honesty flag)" % str(s.get("key", "?")))
                    ok = false
                if kind == "segmented" or kind == "select":
                    if (s.get("options", []) as Array).is_empty() and str(s.get("source", "")).is_empty():
                        push_error("PAUSESMOKE: choice setting '%s' has no options/source" % str(s.get("key", "?")))
                        ok = false
                if kind == "slider":
                    if float(s.get("min", 0)) >= float(s.get("max", 0)):
                        push_error("PAUSESMOKE: slider '%s' has min >= max" % str(s.get("key", "?")))
                        ok = false
    print("PAUSESMOKE: catalog = %d settings across %d tabs; kinds = %s" % [n_settings, tabs.size(), str(kinds_seen.keys())])
    # Every render path must have at least one row to exercise it.
    for k in ["segmented", "select", "toggle", "slider", "keybinds_cta"]:
        if not kinds_seen.has(k):
            push_error("PAUSESMOKE: no catalog row of kind '%s' to exercise its renderer" % k)
            ok = false

    # 3) The three scripts construct (parse + _init clean). _ready/_build_ui runs
    #    only when added to a tree (exercised by the scene boots with autoloads).
    var screen: Object = SettingsScreenScript.new()
    var keys: Object = KeybindingsScript.new()
    var pause: Object = PauseScript.new()
    if screen == null or keys == null or pause == null:
        push_error("PAUSESMOKE: one of the overlay scripts failed to instantiate")
        ok = false
    if screen is Object and not (screen as Object).has_method("open_menu"):
        push_error("PAUSESMOKE: settings screen missing open_menu()")
        ok = false
    if keys is Object and not (keys as Object).has_method("feed_capture"):
        push_error("PAUSESMOKE: keybindings missing feed_capture()")
        ok = false
    if pause is Object and not (pause as Object).has_method("open"):
        push_error("PAUSESMOKE: pause menu missing open()")
        ok = false
    if screen is Node:
        (screen as Node).free()
    if keys is Node:
        (keys as Node).free()
    if pause is Node:
        (pause as Node).free()

    print("PAUSESMOKE: %s" % ("PASS" if ok else "FAIL"))
    quit(0 if ok else 1)
