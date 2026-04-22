class_name UndoManager
extends RefCounted

# Simple command-stack undo/redo. Each editor instance (or the global
# editor host) can own one. Commands are (description, do, undo) triples.

var _stack: Array = []
var _index: int = -1
const MAX_STACK: int = 200


func push(description: String, do_fn: Callable, undo_fn: Callable) -> void:
	if _index < _stack.size() - 1:
		_stack.resize(_index + 1)
	_stack.append({ "desc": description, "do": do_fn, "undo": undo_fn })
	if _stack.size() > MAX_STACK:
		_stack.pop_front()
	else:
		_index += 1


func undo() -> String:
	if _index < 0:
		return ""
	var cmd: Dictionary = _stack[_index]
	cmd["undo"].call()
	var desc: String = cmd["desc"]
	_index -= 1
	return desc


func redo() -> String:
	if _index >= _stack.size() - 1:
		return ""
	_index += 1
	var cmd: Dictionary = _stack[_index]
	cmd["do"].call()
	return cmd["desc"]


func can_undo() -> bool:
	return _index >= 0


func can_redo() -> bool:
	return _index < _stack.size() - 1


func clear() -> void:
	_stack.clear()
	_index = -1
