class_name EditorUndo
extends RefCounted

# Snapshot-based undo/redo helper for editors whose state lives in a
# plain Dictionary / Array. Each editor plugs in two callables:
#   capture: () -> Variant          returns the live mutable state
#   restore: (Variant) -> void      applies a captured snapshot
#
# Typical usage in an editor:
#   _undo = EditorUndo.new(_take_snapshot, _apply_snapshot)
#   _undo.begin()                   before a mutation
#   data["field"] = new_value
#   _undo.commit("edit field")      pushes undo entry; no-op if unchanged
#
# Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y handling is consolidated via handle_key().
#
# Deep-copies are used both when snapshotting and when applying so the
# undo stack never aliases live editor state.

const _UndoManager = preload("res://Space/scripts/editor/undo_manager.gd")

var _mgr: RefCounted = null
var _capture: Callable
var _restore: Callable
var _pre: Variant = null
var _depth: int = 0


func _init(capture_fn: Callable, restore_fn: Callable) -> void:
	_mgr = _UndoManager.new()
	_capture = capture_fn
	_restore = restore_fn


# Capture pre-edit state. Nested begins share a single outer snapshot so
# the undo granularity matches the outermost user action.
func begin() -> void:
	if _depth == 0:
		_pre = _snapshot()
	_depth += 1


func commit(desc: String) -> void:
	if _depth <= 0:
		return
	_depth -= 1
	if _depth > 0:
		return
	var before: Variant = _pre
	_pre = null
	if before == null:
		return
	var after: Variant = _snapshot()
	if _deep_equal(before, after):
		return
	_mgr.push(desc,
		_apply.bind(after),
		_apply.bind(before))


# Abort a begin() without pushing anything.
func discard() -> void:
	if _depth > 0:
		_depth -= 1
		if _depth == 0:
			_pre = null


func can_undo() -> bool:
	return _mgr != null and _mgr.can_undo()


func can_redo() -> bool:
	return _mgr != null and _mgr.can_redo()


func undo() -> String:
	if _mgr == null:
		return ""
	return _mgr.undo()


func redo() -> String:
	if _mgr == null:
		return ""
	return _mgr.redo()


func clear() -> void:
	if _mgr != null:
		_mgr.clear()
	_pre = null
	_depth = 0


# Consumes Ctrl+Z / Ctrl+Shift+Z (redo) / Ctrl+Y (redo). Returns true if
# the key event was handled, so callers can short-circuit.
func handle_key(ke: InputEventKey) -> bool:
	if not ke.pressed or ke.echo or not ke.ctrl_pressed or ke.alt_pressed:
		return false
	if ke.keycode == KEY_Z:
		if ke.shift_pressed:
			redo()
		else:
			undo()
		return true
	if ke.keycode == KEY_Y and not ke.shift_pressed:
		redo()
		return true
	return false


func _snapshot() -> Variant:
	var v: Variant = _capture.call()
	return _deep_copy(v)


func _apply(snapshot: Variant) -> void:
	_restore.call(_deep_copy(snapshot))


static func _deep_copy(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			return (v as Dictionary).duplicate(true)
		TYPE_ARRAY:
			return (v as Array).duplicate(true)
		_:
			return v


static func _deep_equal(a: Variant, b: Variant) -> bool:
	return a == b
