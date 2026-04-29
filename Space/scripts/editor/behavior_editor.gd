extends Control

const BehIO = preload("res://Space/scripts/editor/beh/beh_io.gd")
const BehTypes = preload("res://Space/scripts/editor/beh/beh_types.gd")

# Entity behavior editor main controller. Owns behaviors.json for the
# active pack, the currently-selected behavior, and the current node
# selection within that behavior's tree. Child panels:
#   beh_topbar.gd       — pack label + ADD / SAVE / CLOSE
#   beh_list_panel.gd   — left sidebar: behavior list + rename/delete
#   beh_tree_panel.gd   — center: indented tree view of the selected behavior
#   beh_props_panel.gd  — right: properties of the selected node
#
# Behavior tree data is nested dicts — each node is
# `{type, name, children?, action?, condition?, params}`. Selections are
# stored as "node paths": arrays of child indices from root to the
# target. An empty path selects the root.

signal closed

var pack_id: String = ""
var behaviors_data: Dictionary = {"behaviors": []}
var selected_behavior_id: String = ""
var selected_node_path: Array = []
var dirty: bool = false

var topbar: Control = null
var list_panel: Control = null
var tree_panel: Control = null
var props_panel: Control = null
var text_modal: Control = null
var type_picker: Control = null
var leaf_picker: Control = null
var enum_picker: Control = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _skip_close_frame: bool = true
var _modal_callback: Callable = Callable()

var _undo: RefCounted = null

const TOPBAR_H: float = 64.0
const SIDEBAR_W: float = 280.0
const PROPS_W: float = 340.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()


func _capture_state() -> Dictionary:
    return {
        "behaviors_data": behaviors_data.duplicate(true),
        "selected_behavior_id": selected_behavior_id,
        "selected_node_path": selected_node_path.duplicate(),
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var b_v: Variant = snap.get("behaviors_data", null)
    if typeof(b_v) == TYPE_DICTIONARY:
        behaviors_data = b_v
    selected_behavior_id = str(snap.get("selected_behavior_id", ""))
    var p_v: Variant = snap.get("selected_node_path", [])
    selected_node_path = p_v if typeof(p_v) == TYPE_ARRAY else []
    dirty = bool(snap.get("dirty", false))
    if tree_panel != null and tree_panel.has_method("queue_redraw"):
        tree_panel.queue_redraw()
    if list_panel != null and list_panel.has_method("queue_redraw"):
        list_panel.queue_redraw()
    if props_panel != null and props_panel.has_method("queue_redraw"):
        props_panel.queue_redraw()


func _build_layout() -> void:
    topbar = Control.new()
    topbar.set_script(preload("res://Space/scripts/editor/beh/beh_topbar.gd"))
    topbar.editor = self
    add_child(topbar)

    list_panel = Control.new()
    list_panel.set_script(preload("res://Space/scripts/editor/beh/beh_list_panel.gd"))
    list_panel.editor = self
    add_child(list_panel)

    tree_panel = Control.new()
    tree_panel.set_script(preload("res://Space/scripts/editor/beh/beh_tree_panel.gd"))
    tree_panel.editor = self
    add_child(tree_panel)

    props_panel = Control.new()
    props_panel.set_script(preload("res://Space/scripts/editor/beh/beh_props_panel.gd"))
    props_panel.editor = self
    add_child(props_panel)

    type_picker = Control.new()
    type_picker.set_script(preload("res://Space/scripts/editor/beh/beh_type_picker.gd"))
    type_picker.editor = self
    type_picker.visible = false
    add_child(type_picker)
    type_picker.picked.connect(_on_type_picked)

    leaf_picker = Control.new()
    leaf_picker.set_script(preload("res://Space/scripts/editor/beh/beh_leaf_picker.gd"))
    leaf_picker.visible = false
    add_child(leaf_picker)
    leaf_picker.picked.connect(_on_leaf_picked)
    leaf_picker.cancelled.connect(_on_leaf_cancelled)

    enum_picker = Control.new()
    enum_picker.set_script(preload("res://Space/scripts/editor/beh/beh_enum_picker.gd"))
    enum_picker.visible = false
    add_child(enum_picker)
    enum_picker.picked.connect(_on_enum_picked)
    enum_picker.cancelled.connect(_on_enum_cancelled)

    text_modal = Control.new()
    text_modal.set_script(preload("res://Space/scripts/editor/env/env_text_modal.gd"))
    text_modal.visible = false
    add_child(text_modal)
    text_modal.submitted.connect(_on_modal_submit)
    text_modal.cancelled.connect(_on_modal_cancel)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    _layout_children()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _layout_children() -> void:
    if topbar == null:
        return
    var vw := size.x
    var vh := size.y
    topbar.position = Vector2.ZERO
    topbar.size = Vector2(vw, TOPBAR_H)
    list_panel.position = Vector2(0, TOPBAR_H)
    list_panel.size = Vector2(SIDEBAR_W, vh - TOPBAR_H)
    tree_panel.position = Vector2(SIDEBAR_W, TOPBAR_H)
    tree_panel.size = Vector2(vw - SIDEBAR_W - PROPS_W, vh - TOPBAR_H)
    props_panel.position = Vector2(vw - PROPS_W, TOPBAR_H)
    props_panel.size = Vector2(PROPS_W, vh - TOPBAR_H)
    if type_picker != null:
        type_picker.position = Vector2.ZERO
        type_picker.size = Vector2(vw, vh)
    if leaf_picker != null:
        leaf_picker.position = Vector2.ZERO
        leaf_picker.size = Vector2(vw, vh)
    if enum_picker != null:
        enum_picker.position = Vector2.ZERO
        enum_picker.size = Vector2(vw, vh)
    if text_modal != null:
        text_modal.position = Vector2.ZERO
        text_modal.size = Vector2(vw, vh)
    if _tutorial_btn != null:
        _tutorial_btn.position = Vector2(vw - 240, 16)
        _tutorial_btn.size = Vector2(100, 32)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)


func open_editor(p_pack_id: String = ""):
    pack_id = p_pack_id
    visible = true
    _skip_close_frame = true

    behaviors_data = BehIO.load_or_init(pack_id)
    var arr: Array = behaviors_data.get("behaviors", [])
    if arr.is_empty():
        selected_behavior_id = ""
    else:
        var first: Variant = arr[0]
        if typeof(first) == TYPE_DICTIONARY:
            selected_behavior_id = str((first as Dictionary).get("id", ""))
    selected_node_path = []
    dirty = false
    if _undo != null:
        _undo.clear()

    if is_inside_tree():
        _layout_children()


func _process(_delta):
    if _skip_close_frame:
        _skip_close_frame = false
        return


func _input(event):
    if not visible:
        return
    if _skip_close_frame:
        return
    if text_modal != null and text_modal.visible:
        return
    if type_picker != null and type_picker.visible:
        return
    if leaf_picker != null and leaf_picker.visible:
        return
    if enum_picker != null and enum_picker.visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("behavior")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


# ─── Queries ─────────────────────────────────────────────────────────────

func get_behaviors() -> Array:
    var arr_v: Variant = behaviors_data.get("behaviors", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return []
    return arr_v

func get_selected_behavior() -> Dictionary:
    var arr := get_behaviors()
    for b_v in arr:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var b: Dictionary = b_v
        if str(b.get("id", "")) == selected_behavior_id:
            return b
    return {}

func get_selected_root() -> Dictionary:
    var b := get_selected_behavior()
    if b.is_empty():
        return {}
    var root_v: Variant = b.get("root", {})
    if typeof(root_v) != TYPE_DICTIONARY:
        return {}
    return root_v

func get_selected_node() -> Dictionary:
    var root := get_selected_root()
    if root.is_empty():
        return {}
    return BehIO.node_at_path(root, selected_node_path)

func select_behavior(id: String) -> void:
    selected_behavior_id = id
    selected_node_path = []

func select_node(path: Array) -> void:
    selected_node_path = path.duplicate()


# ─── Registry CRUD ───────────────────────────────────────────────────────

func request_add_behavior() -> void:
    show_text_modal("Add behavior", _suggest_new_behavior_id(),
        "Unique id (snake_case).",
        Callable(self, "_create_new_behavior"))

func request_rename_behavior(old_id: String) -> void:
    show_text_modal("Rename behavior", old_id,
        "New id for \"%s\" (must be unique)." % old_id,
        Callable(self, "_rename_behavior_to").bind(old_id))

func request_edit_behavior_field(field: String, title: String, prompt: String) -> void:
    var b := get_selected_behavior()
    if b.is_empty():
        return
    var default_val := str(b.get(field, ""))
    show_text_modal(title, default_val, prompt,
        Callable(self, "_set_behavior_field").bind(field))

func delete_behavior(id: String) -> void:
    var arr := get_behaviors()
    for i in arr.size():
        var b_v: Variant = arr[i]
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        if str((b_v as Dictionary).get("id", "")) == id:
            if _undo != null:
                _undo.begin()
            arr.remove_at(i)
            behaviors_data["behaviors"] = arr
            if selected_behavior_id == id:
                selected_behavior_id = ""
                selected_node_path = []
                if not arr.is_empty():
                    var first: Variant = arr[0]
                    if typeof(first) == TYPE_DICTIONARY:
                        selected_behavior_id = str((first as Dictionary).get("id", ""))
            dirty = true
            if _undo != null:
                _undo.commit("delete behavior")
            return

func _suggest_new_behavior_id() -> String:
    var arr := get_behaviors()
    var ids: Dictionary = {}
    for b_v in arr:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        ids[str((b_v as Dictionary).get("id", ""))] = true
    var i := 1
    while true:
        var candidate := "behavior_%d" % i
        if not ids.has(candidate):
            return candidate
        i += 1
    return "behavior_new"

func _create_new_behavior(id: String) -> void:
    id = id.strip_edges()
    if id.is_empty():
        push_warning("[BehEditor] empty behavior id ignored")
        return
    var arr := get_behaviors()
    for b_v in arr:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        if str((b_v as Dictionary).get("id", "")) == id:
            push_warning("[BehEditor] behavior '%s' already exists" % id)
            return
    if _undo != null:
        _undo.begin()
    arr.append(BehIO.default_behavior(id))
    behaviors_data["behaviors"] = arr
    selected_behavior_id = id
    selected_node_path = []
    dirty = true
    if _undo != null:
        _undo.commit("add behavior")

func _rename_behavior_to(new_id: String, old_id: String) -> void:
    new_id = new_id.strip_edges()
    if new_id.is_empty() or new_id == old_id:
        return
    var arr := get_behaviors()
    for b_v in arr:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        if str((b_v as Dictionary).get("id", "")) == new_id:
            push_warning("[BehEditor] behavior '%s' already exists" % new_id)
            return
    for b_v in arr:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var b: Dictionary = b_v
        if str(b.get("id", "")) == old_id:
            if _undo != null:
                _undo.begin()
            b["id"] = new_id
            if selected_behavior_id == old_id:
                selected_behavior_id = new_id
            dirty = true
            if _undo != null:
                _undo.commit("rename behavior")
            return

func _set_behavior_field(value: String, field: String) -> void:
    var b := get_selected_behavior()
    if b.is_empty():
        return
    if _undo != null:
        _undo.begin()
    b[field] = value
    dirty = true
    if _undo != null:
        _undo.commit("set behavior field")


# ─── Tree CRUD ───────────────────────────────────────────────────────────

func request_pick_node_type(path: Array) -> void:
    if type_picker == null:
        return
    var node := BehIO.node_at_path(get_selected_root(), path)
    var current_type := str(node.get("type", "sequence")) if not node.is_empty() else "sequence"
    type_picker.open(current_type)
    type_picker.set_meta("target_path", path.duplicate())

func _on_type_picked(new_type: String) -> void:
    if type_picker == null:
        return
    var path_v: Variant = type_picker.get_meta("target_path", [])
    if typeof(path_v) != TYPE_ARRAY:
        return
    var path: Array = path_v
    var root := get_selected_root()
    if root.is_empty():
        return
    var node := BehIO.node_at_path(root, path)
    if node.is_empty():
        return
    var old_type := str(node.get("type", ""))
    if old_type == new_type:
        return
    if _undo != null:
        _undo.begin()
    node["type"] = new_type
    # Adjust children array presence to match the new category, but
    # keep existing children when possible so users don't lose work.
    if BehTypes.accepts_children(new_type):
        if not node.has("children") or typeof(node["children"]) != TYPE_ARRAY:
            node["children"] = []
        var limit := BehTypes.max_children(new_type)
        if limit >= 0:
            var kids: Array = node["children"]
            while kids.size() > limit:
                kids.pop_back()
            node["children"] = kids
    else:
        node.erase("children")
    if new_type == "action" and not node.has("action"):
        node["action"] = "idle"
    if new_type == "condition" and not node.has("condition"):
        node["condition"] = "always"
    dirty = true
    if _undo != null:
        _undo.commit("change node type")

func add_child_node(parent_path: Array, type: String = "action") -> void:
    var root := get_selected_root()
    if root.is_empty():
        return
    var parent := BehIO.node_at_path(root, parent_path)
    if parent.is_empty():
        return
    var parent_type := str(parent.get("type", ""))
    if not BehTypes.accepts_children(parent_type):
        push_warning("[BehEditor] '%s' cannot have children" % parent_type)
        return
    var limit := BehTypes.max_children(parent_type)
    if not parent.has("children") or typeof(parent["children"]) != TYPE_ARRAY:
        parent["children"] = []
    var kids: Array = parent["children"]
    if limit >= 0 and kids.size() >= limit:
        push_warning("[BehEditor] '%s' already has %d children" % [parent_type, limit])
        return
    if _undo != null:
        _undo.begin()
    kids.append(BehIO.default_node(type))
    parent["children"] = kids
    selected_node_path = parent_path.duplicate()
    selected_node_path.append(kids.size() - 1)
    dirty = true
    if _undo != null:
        _undo.commit("add child node")

func delete_node(path: Array) -> void:
    if path.is_empty():
        push_warning("[BehEditor] cannot delete root node")
        return
    var root := get_selected_root()
    var info := BehIO.parent_of(root, path)
    if info.is_empty():
        return
    var parent: Dictionary = info["parent"]
    var idx := int(info["index"])
    if not parent.has("children") or typeof(parent["children"]) != TYPE_ARRAY:
        return
    var kids: Array = parent["children"]
    if idx < 0 or idx >= kids.size():
        return
    if _undo != null:
        _undo.begin()
    kids.remove_at(idx)
    parent["children"] = kids
    selected_node_path = path.slice(0, path.size() - 1)
    dirty = true
    if _undo != null:
        _undo.commit("delete node")

func move_node(path: Array, delta: int) -> void:
    if path.is_empty():
        return
    var root := get_selected_root()
    var info := BehIO.parent_of(root, path)
    if info.is_empty():
        return
    var parent: Dictionary = info["parent"]
    var idx := int(info["index"])
    if not parent.has("children") or typeof(parent["children"]) != TYPE_ARRAY:
        return
    var kids: Array = parent["children"]
    var new_idx := idx + delta
    if new_idx < 0 or new_idx >= kids.size():
        return
    if _undo != null:
        _undo.begin()
    var tmp: Variant = kids[idx]
    kids[idx] = kids[new_idx]
    kids[new_idx] = tmp
    parent["children"] = kids
    var new_path: Array = path.duplicate()
    new_path[new_path.size() - 1] = new_idx
    selected_node_path = new_path
    dirty = true
    if _undo != null:
        _undo.commit("move node")

func request_edit_node_field(field: String, title: String, prompt: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    if (field == "action" or field == "condition") and leaf_picker != null:
        var current_name := str(node.get(field, ""))
        leaf_picker.set_meta("target_field", field)
        leaf_picker.open(field, current_name)
        return
    var default_val := str(node.get(field, ""))
    show_text_modal(title, default_val, prompt,
        Callable(self, "_set_node_field").bind(field))


func _on_leaf_picked(leaf_name: String, is_custom: bool) -> void:
    if leaf_picker == null:
        return
    var field: String = str(leaf_picker.get_meta("target_field", ""))
    if field.is_empty():
        return
    var node := get_selected_node()
    if node.is_empty():
        return
    if is_custom:
        show_text_modal("Custom %s name" % field,
            str(node.get(field, "")),
            "Custom %s name. Runtime will warn + fallback if unregistered." % field,
            Callable(self, "_set_node_field_with_schema").bind(field))
        return
    _set_node_field_with_schema(leaf_name, field)


func _on_leaf_cancelled() -> void:
    if leaf_picker != null:
        leaf_picker.remove_meta("target_field")


func _set_node_field_with_schema(value: String, field: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    if _undo != null:
        _undo.begin()
    node[field] = value
    var schema := BehLeafSchema.find_schema(field, value)
    if not schema.is_empty():
        var existing_params_v: Variant = node.get("params", {})
        var existing: Dictionary = existing_params_v if typeof(existing_params_v) == TYPE_DICTIONARY else {}
        var merged: Dictionary = {}
        for f_v in schema.get("fields", []):
            var f: Array = f_v
            var key: String = str(f[0])
            if existing.has(key):
                merged[key] = existing[key]
            else:
                merged[key] = f[3]
        for ek in existing.keys():
            if not merged.has(ek):
                merged[ek] = existing[ek]
        node["params"] = merged
    dirty = true
    if _undo != null:
        _undo.commit("set leaf %s" % field)

func request_edit_node_param(param_key: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    var params_v: Variant = node.get("params", {})
    var default_val := ""
    if typeof(params_v) == TYPE_DICTIONARY:
        var params: Dictionary = params_v
        if params.has(param_key):
            default_val = str(params[param_key])
    var leaf_kind := str(node.get("type", ""))
    var leaf_name := str(node.get(leaf_kind, ""))
    var field_spec: Array = _find_field_spec(leaf_kind, leaf_name, param_key)
    if not field_spec.is_empty():
        var kind_str: String = str(field_spec[2])
        if kind_str == "bool":
            _open_enum_picker("Param: %s" % param_key, [
                {"value": "true", "label": "true"},
                {"value": "false", "label": "false"},
            ], default_val, param_key)
            return
        if BehLeafSchema.is_enum(kind_str):
            var opts: Array = []
            for v in BehLeafSchema.enum_values(kind_str):
                opts.append({"value": v, "label": v})
            _open_enum_picker("Param: %s" % param_key, opts, default_val, param_key)
            return
        var label: String = str(field_spec[1])
        var prompt: String = "%s — kind: %s" % [label, kind_str]
        show_text_modal("Param: %s" % param_key, default_val, prompt,
            Callable(self, "_set_node_param").bind(param_key))
        return
    show_text_modal("Param: %s" % param_key, default_val,
        "Value for param '%s'. Plain string — parsed numeric when possible." % param_key,
        Callable(self, "_set_node_param").bind(param_key))


func request_add_node_param() -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    var leaf_kind := str(node.get("type", ""))
    var leaf_name := str(node.get(leaf_kind, ""))
    var schema := BehLeafSchema.find_schema(leaf_kind, leaf_name)
    if schema.is_empty():
        show_text_modal("Add param", "",
            "Param key (snake_case).",
            Callable(self, "_add_node_param_key"))
        return
    var params_v: Variant = node.get("params", {})
    var have: Dictionary = params_v if typeof(params_v) == TYPE_DICTIONARY else {}
    var opts: Array = []
    for f_v in schema.get("fields", []):
        var f: Array = f_v
        var key: String = str(f[0])
        if have.has(key):
            continue
        opts.append({
            "value": key,
            "label": "%s  (%s)" % [str(f[1]), str(f[2])],
            "help": "Add schema param '%s'. Default: %s" % [key, str(f[3])],
        })
    opts.append({
        "value": "__custom__",
        "label": "(custom key...)",
        "help": "Add a key not in the schema. Runtime handler may ignore it.",
    })
    if enum_picker == null:
        show_text_modal("Add param", "",
            "Param key (snake_case).",
            Callable(self, "_add_node_param_key"))
        return
    enum_picker.set_meta("mode", "add_param")
    enum_picker.open("Add param to '%s'" % leaf_name, opts, "")

func _set_node_field(value: String, field: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    if _undo != null:
        _undo.begin()
    node[field] = value
    dirty = true
    if _undo != null:
        _undo.commit("set node field")

func _set_node_param(value: String, param_key: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    if _undo != null:
        _undo.begin()
    if not node.has("params") or typeof(node["params"]) != TYPE_DICTIONARY:
        node["params"] = {}
    var params: Dictionary = node["params"]
    var trimmed := value.strip_edges()
    var parsed: Variant = trimmed
    if trimmed.is_valid_int():
        parsed = int(trimmed)
    elif trimmed.is_valid_float():
        parsed = float(trimmed)
    elif trimmed == "true":
        parsed = true
    elif trimmed == "false":
        parsed = false
    params[param_key] = parsed
    node["params"] = params
    dirty = true
    if _undo != null:
        _undo.commit("set node param")

func _add_node_param_key(key: String) -> void:
    key = key.strip_edges()
    if key.is_empty():
        return
    var node := get_selected_node()
    if node.is_empty():
        return
    if _undo != null:
        _undo.begin()
    if not node.has("params") or typeof(node["params"]) != TYPE_DICTIONARY:
        node["params"] = {}
    var params: Dictionary = node["params"]
    if not params.has(key):
        params[key] = ""
    node["params"] = params
    dirty = true
    if _undo != null:
        _undo.commit("add node param")

func _find_field_spec(leaf_kind: String, leaf_name: String, key: String) -> Array:
    var schema := BehLeafSchema.find_schema(leaf_kind, leaf_name)
    if schema.is_empty():
        return []
    for f_v in schema.get("fields", []):
        var f: Array = f_v
        if str(f[0]) == key:
            return f
    return []


func _open_enum_picker(title: String, options: Array, current: String,
        param_key: String) -> void:
    if enum_picker == null:
        show_text_modal(title, current, "Value for '%s'." % param_key,
            Callable(self, "_set_node_param").bind(param_key))
        return
    enum_picker.set_meta("mode", "edit_param")
    enum_picker.set_meta("param_key", param_key)
    enum_picker.open(title, options, current)


func _on_enum_picked(value: String) -> void:
    if enum_picker == null:
        return
    var mode: String = str(enum_picker.get_meta("mode", ""))
    if mode == "edit_param":
        var key: String = str(enum_picker.get_meta("param_key", ""))
        enum_picker.remove_meta("mode")
        enum_picker.remove_meta("param_key")
        if not key.is_empty():
            _set_node_param(value, key)
        return
    if mode == "add_param":
        enum_picker.remove_meta("mode")
        if value == "__custom__":
            show_text_modal("Add param", "",
                "Param key (snake_case).",
                Callable(self, "_add_node_param_key"))
            return
        _add_node_param_key(value)


func _on_enum_cancelled() -> void:
    if enum_picker != null:
        enum_picker.remove_meta("mode")
        enum_picker.remove_meta("param_key")


func delete_node_param(key: String) -> void:
    var node := get_selected_node()
    if node.is_empty():
        return
    if not node.has("params") or typeof(node["params"]) != TYPE_DICTIONARY:
        return
    var params: Dictionary = node["params"]
    if params.has(key):
        if _undo != null:
            _undo.begin()
        params.erase(key)
        node["params"] = params
        dirty = true
        if _undo != null:
            _undo.commit("delete node param")


# ─── Save / close ────────────────────────────────────────────────────────

func save_all() -> void:
    var unregistered := _collect_unregistered_leaves()
    if BehIO.save_behaviors(pack_id, behaviors_data):
        dirty = false
        print("[BehEditor] saved behaviors.json for pack '%s'" % pack_id)
        if not unregistered.is_empty():
            push_warning("[BehEditor] saved with %d unregistered leaf(s) — runtime will push_warning and fall back:\n - %s" %
                [unregistered.size(), "\n - ".join(unregistered)])
    else:
        push_error("[BehEditor] save failed for pack '%s'" % pack_id)


func _collect_unregistered_leaves() -> Array:
    var out: Array = []
    for b_v in get_behaviors():
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var b: Dictionary = b_v
        var root_v: Variant = b.get("root", {})
        if typeof(root_v) != TYPE_DICTIONARY:
            continue
        _walk_for_unregistered(root_v, str(b.get("id", "")), out)
    return out


func _walk_for_unregistered(node: Dictionary, behavior_id: String,
        out: Array) -> void:
    var type_str := str(node.get("type", ""))
    if type_str == "action":
        var a_name := str(node.get("action", ""))
        if not a_name.is_empty() and BehLeafSchema.find_schema("action", a_name).is_empty():
            out.append("%s: action '%s' → idle" % [behavior_id, a_name])
    elif type_str == "condition":
        var c_name := str(node.get("condition", ""))
        if not c_name.is_empty() and BehLeafSchema.find_schema("condition", c_name).is_empty():
            out.append("%s: condition '%s' → always" % [behavior_id, c_name])
    var kids_v: Variant = node.get("children", [])
    if typeof(kids_v) == TYPE_ARRAY:
        for k_v in kids_v:
            if typeof(k_v) == TYPE_DICTIONARY:
                _walk_for_unregistered(k_v, behavior_id, out)


func behavior_has_unregistered(id: String) -> bool:
    for b_v in get_behaviors():
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var b: Dictionary = b_v
        if str(b.get("id", "")) != id:
            continue
        var root_v: Variant = b.get("root", {})
        if typeof(root_v) != TYPE_DICTIONARY:
            return false
        var hits: Array = []
        _walk_for_unregistered(root_v, id, hits)
        return not hits.is_empty()
    return false

func request_close() -> void:
    visible = false
    closed.emit()


# ─── Modal plumbing ──────────────────────────────────────────────────────

func show_text_modal(title: String, default_text: String, prompt: String, cb: Callable) -> void:
    _modal_callback = cb
    text_modal.open(title, default_text, prompt)

func _on_modal_submit(text: String) -> void:
    var cb := _modal_callback
    _modal_callback = Callable()
    if cb.is_valid():
        cb.call(text)

func _on_modal_cancel() -> void:
    _modal_callback = Callable()
